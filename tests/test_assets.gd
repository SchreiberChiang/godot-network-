extends RefCounted
const Catalog = preload("res://host/core/asset_catalog.gd")
const Rules = preload("res://host/core/asset_rules.gd")
const MatchWallet = preload("res://sdk/roomkit/server/match_wallet.gd")
const Deny = preload("res://sdk/roomkit/server/asset_policy.gd")
const Shooter = preload("res://examples/shooter/asset_policy.gd")
const Turns = preload("res://examples/turn_based/asset_policy.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0

func run() -> Dictionary:
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_messages.example.json"))
	for example in examples:
		check(Validator.validate_file(example.value, "res://schemas/" + str(example.schema)) == "", "documented asset example " + str(example.schema))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	var catalog = Catalog.new()
	check(catalog.configure(config) == "", "trusted catalog schema and defaults")
	check(catalog.level_for(0) == 1 and catalog.level_for(99) == 1, "experience below first level threshold")
	check(catalog.level_for(100) == 2 and catalog.level_for(249) == 2 and catalog.level_for(250) == 3, "exact nonlinear experience thresholds")
	check(catalog.level_for(1000000000) == config.level_thresholds.size(), "experience beyond last threshold caps at table level")
	for invalid in [[1, 100], [0, 100, 50], [0, 100, 100], [0, 0.5], []]:
		var bad_curve := config.duplicate(true)
		bad_curve.level_thresholds = invalid
		check(catalog.configure(bad_curve) == "INVALID_ASSET_CATALOG" and catalog.level_for(250) == 3, "invalid curve rejected without changing active thresholds " + str(invalid))
	var legacy := config.duplicate(true)
	legacy.erase("level_thresholds")
	var legacy_catalog = Catalog.new()
	check(legacy_catalog.configure(legacy) == "" and legacy_catalog.level_for(500) == 1, "legacy catalog without level table has no progression")
	var broken := config.duplicate(true)
	broken.games.shooter.space = "unknown"
	check(catalog.configure(broken) == "UNKNOWN_ASSET_SPACE" and catalog.space_for("shooter") == "shooter", "invalid reload preserves original catalog")
	broken = config.duplicate(true)
	broken.games.shooter.slots.primary.default = "smg"
	check(catalog.configure(broken) == "INVALID_DEFAULT_ITEM", "paid item cannot be initial entitlement")
	var returned: Dictionary = catalog.game("shooter")
	returned.space = "turns"
	check(catalog.space_for("shooter") == "shooter", "returned catalog is detached")
	var initial := Rules.empty_state()
	var view := Rules.project(initial, catalog, "shooter")
	check(view.owned == ["rifle"] and view.profiles.shooter.primary == "rifle" and initial.owned.is_empty(), "free entitlement projected without mutating original state")
	var purchase := {"kind": "purchase", "item_id": "smg", "request_id": "p1"}
	check(Rules.apply(view, catalog, "shooter", purchase).code == "INSUFFICIENT_CREDITS", "cannot unlock without credits")
	var adjusted := Rules.apply(view, catalog, "shooter", {"kind": "adjust", "credits": 300, "experience": 50, "reason": "测试", "request_id": "a1"}, true)
	check(adjusted.ok and adjusted.state.credits == 300, "trusted adjustment")
	var purchased := Rules.apply(adjusted.state, catalog, "shooter", purchase)
	check(purchased.ok and purchased.state.credits == 200 and "smg" in purchased.state.owned, "purchase atomically computes debit and ownership")
	check(purchased.state.profiles.shooter.primary == "rifle", "purchase does not silently select")
	check(Rules.apply(purchased.state, catalog, "shooter", purchase).code == "ALREADY_OWNED", "another request cannot purchase permanent item twice")
	var select := {"kind": "select", "item_id": "smg", "slot": "primary", "request_id": "s1"}
	var selected := Rules.apply(purchased.state, catalog, "shooter", select)
	check(selected.ok and selected.state.profiles.shooter.primary == "smg", "owned item becomes persistent default")
	select.item_id = "shotgun"
	check(Rules.apply(purchased.state, catalog, "shooter", select).code == "ITEM_NOT_OWNED", "selection validates entitlement")
	select.slot = "theme"
	check(Rules.apply(purchased.state, catalog, "shooter", select).code == "INVALID_CONFIGURATION", "game slot isolation")
	purchase.item_id = "jade"
	check(Rules.apply(purchased.state, catalog, "shooter", purchase).code == "UNKNOWN_ITEM", "other game item denied")
	purchase.item_id = "shotgun"
	purchase.credits = -999
	check(Rules.apply(purchased.state, catalog, "shooter", purchase).code == "INVALID_ASSET_COMMAND", "caller cannot choose price")
	check(Rules.apply(view, catalog, "shooter", {"kind": "adjust", "credits": 100, "experience": 0, "reason": "x", "request_id": "a2"}).code == "ADMIN_REQUIRED", "normal transition cannot grant itself credits")
	check(Rules.apply(view, catalog, "shooter", {"kind": "adjust", "credits": -1, "experience": 0, "reason": "x", "request_id": "a3"}, true).code == "ASSET_LIMIT_EXCEEDED", "negative balance prevented")
	var command := {"kind": "purchase", "item_id": "smg", "request_id": "p2"}
	check(Deny.new().authorize({}, {"location": "lobby"}, command) == "ASSET_OPERATION_DENIED", "base policy fails closed")
	check(Shooter.new().authorize({}, {"location": "lobby"}, command) == "", "shooter lobby allowed")
	check(Shooter.new().authorize({}, {"location": "room", "life_state": "dead"}, command) == "", "shooter dead state allowed")
	check(Shooter.new().authorize({}, {"location": "room", "life_state": "alive"}, command) != "", "shooter alive denied")
	check(Shooter.new().authorize({}, {"location": "room"}, command) != "", "missing game state denied")
	check(Turns.new().authorize({}, {"location": "lobby"}, command) == "" and Turns.new().authorize({}, {"location": "room", "life_state": "dead"}, command) != "", "non-shooter game uses its own lobby-only policy")
	var match_a = MatchWallet.new("launch_a", "match_a")
	var match_b = MatchWallet.new("launch_b", "match_a")
	check(match_a.change("u1", 500, "start").ok and match_b.balance("u1") == 0, "same match label in another launch has separate economy")
	check(match_a.change("u1", -200, "buy").balance == 300, "match-local debit")
	check(match_a.change("u1", -200, "buy").balance == 300 and match_a.balance("u1") == 300, "match duplicate debit is idempotent")
	check(match_a.change("u1", -201, "buy").code == "REQUEST_CONFLICT", "match key payload conflict")
	check(match_a.change("u1", -301, "overdraft").code == "INSUFFICIENT_CREDITS", "match overdraft rejected")
	check(initial.credits == 0 and selected.state.credits == 200, "match operations never modify permanent credits")
	match_a.close()
	check(match_a.balance("u1") == 0 and match_a.change("u1", 1, "after").code == "MATCH_CLOSED", "closed match discards local economy and cannot write")
	return {"passed": passed, "failed": failed}

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL assets: ", label)
