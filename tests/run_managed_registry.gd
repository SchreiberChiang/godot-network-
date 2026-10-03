extends SceneTree
## Real Godot registry/configuration tests; no process, network or database claims.
const Registry = preload("res://host/core/managed_game_registry.gd")
const Catalog = preload("res://host/core/asset_catalog.gd")
const GameRegistry = preload("res://host/core/game_registry.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0
var fixture := ""

func _initialize() -> void:
	fixture = "res://run/managed-registry-" + Wire.uid()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	_write("policy.gd", "extends RefCounted\nfunc authorize(_identity: Dictionary, _context: Dictionary, _command: Dictionary) -> String:\n\treturn \"\"\n")
	_write("reward.gd", "extends RefCounted\nstatic func calculate(_record: Dictionary) -> Array:\n\treturn []\n")
	_write("result.schema.json", JSON.stringify({"type": "object", "additionalProperties": false}))
	_run.call_deferred()

func _run() -> void:
	var base := {"race": _entry("race", "garage")}
	var registry = Registry.new()
	var initial: String = registry.configure(base)
	check(initial == "", "third game registers without example defaults: " + initial)
	if initial != "":
		printerr("REGISTRY_DIAGNOSTIC schema=", Validator.validate_file(base, "res://schemas/managed_game_registry.schema.json"), " version=", base.race.manifest.godot_version, " project=", Registry._path(fixture, "res://", true))
		printerr("REGISTRY_DIAGNOSTIC manifest=", GameRegistry.new().register_game(base.race.manifest, {"race-artifact": {"executable": OS.get_executable_path(), "args": []}}))
		print("MANAGED_REGISTRY_RESULT passed=", passed, " failed=", failed)
		quit(1)
		return
	check(registry.entries.race.manifest.modes.has("sprint"), "mode names come from game manifest")
	check(registry.default_spaces == {"race": "garage"}, "game id and default space may differ")
	check(registry.policies.race.authorize({}, {}, {}) == "", "loaded policy accepts declared interface")
	check(registry.rewards.race.calculate({}) == [], "static reward calculator works through loaded instance")
	check(base.race.project == fixture and base.race.asset_policy == "policy.gd", "configure never rewrites caller paths")
	check(registry.entries.race.project.is_absolute_path() and registry.entries.race.asset_policy.ends_with("/policy.gd"), "relative service paths resolve against game project")
	check(not registry.catalog_for({"race": "garage"}).is_empty(), "independent asset space initializes")
	check(not registry.catalog_for({"race": "shared"}).is_empty(), "shared asset space initializes")
	check(registry.catalog_for({"race": "unknown"}).is_empty(), "unknown asset space denied")
	check(registry.catalog_for({}).is_empty(), "missing asset binding denied")
	check(registry.catalog_for({"race": "garage", "unknown": "shared"}).is_empty(), "unknown game binding denied")
	check(not registry.valid_spaces([]), "nonobject space configuration denied")
	var projected: Dictionary = registry.catalog_for({"race": "shared"})
	projected.games.race.space = "changed"
	check(registry.catalog.games.race.space == "garage", "catalog projections do not mutate registration")
	var host_registry = GameRegistry.new()
	check(host_registry.register_game(base.race.manifest, {"race-artifact": {"executable": OS.get_executable_path(), "args": []}}).ok, "host accepts declared third-game manifest")
	check(host_registry.validate_options("race", {"mode": "sprint", "map": "track", "capacity": 2}).ok, "host permits registered non-example mode")
	check(not host_registry.validate_options("race", {"mode": "ffa", "map": "track", "capacity": 2}).ok, "host rejects unregistered example mode")
	check(not host_registry.validate_options("race", {"mode": "sprint", "map": "unknown", "capacity": 2}).ok, "host rejects unregistered map")

	_reject(registry, {}, "INVALID_GAME_REGISTRY", "empty registry")
	_reject(registry, {"race": "bad"}, "INVALID_GAME_REGISTRY", "nonobject game")
	var bad := base.duplicate(true)
	bad.race.manifest.game_id = "other"
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "mismatched game identity")
	bad = base.duplicate(true)
	bad.race.manifest.sdk_version = "0.4.0"
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "unsupported SDK")
	bad = base.duplicate(true)
	bad.race.manifest.modes.sprint.min_players = 5
	bad.race.manifest.modes.sprint.max_players = 2
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "inverted player range")
	bad = base.duplicate(true)
	bad.race.manifest.max_players = 1
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "mode exceeds game capacity")
	bad = base.duplicate(true)
	bad.race.manifest.build_id = "REPLACE_ME"
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "deployment placeholder")
	bad = base.duplicate(true)
	bad.race.manifest.modes.sprint.maps = ["track", "track"]
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "duplicate map")
	bad = base.duplicate(true)
	bad.race.unexpected = "value"
	_reject(registry, bad, "INVALID_GAME_REGISTRY", "unknown registry field")
	bad = base.duplicate(true)
	bad.race.asset_policy = "missing.gd"
	_reject(registry, bad, "GAME_SERVICE_MISSING", "missing policy file")
	bad = base.duplicate(true)
	bad.race.asset_policy = "result.schema.json"
	_reject(registry, bad, "INVALID_GAME_SERVICE", "nonscript policy")
	for path in ["user://private", "https://example.invalid/game", "bad\npath", "bad\tpath"]:
		bad = base.duplicate(true)
		bad.race.project = path
		_reject(registry, bad, "INVALID_GAME_REGISTRY", "unsafe project path " + str(path.length()))
	_write("node_policy.gd", "extends Node\nfunc authorize(_a, _b, _c):\n\treturn \"\"\n")
	_write("constructor_policy.gd", "extends RefCounted\nfunc _init(_required):\n\tpass\nfunc authorize(_a, _b, _c):\n\treturn \"\"\n")
	_write("wrong_policy.gd", "extends RefCounted\nfunc authorize(_a):\n\treturn \"\"\n")
	_write("missing_policy.gd", "extends RefCounted\n")
	for script in ["node_policy.gd", "constructor_policy.gd", "wrong_policy.gd", "missing_policy.gd"]:
		bad = base.duplicate(true)
		bad.race.asset_policy = script
		_reject(registry, bad, "INVALID_GAME_SERVICE", script)
	_write("wrong_reward.gd", "extends RefCounted\nfunc calculate(_a, _b):\n\treturn []\n")
	bad = base.duplicate(true)
	bad.race.reward_script = "wrong_reward.gd"
	_reject(registry, bad, "INVALID_GAME_SERVICE", "reward signature")
	_write("invalid_result.json", "[]")
	bad = base.duplicate(true)
	bad.race.result_schema = "invalid_result.json"
	_reject(registry, bad, "INVALID_GAME_SERVICE", "nonobject result schema")
	var no_reward := base.duplicate(true)
	no_reward.race.erase("reward_script")
	check(Registry.new().configure(no_reward) == "", "reward service is optional")
	_write("inherited_policy.gd", "extends \"" + fixture + "/policy.gd\"\n")
	var inherited := base.duplicate(true)
	inherited.race.asset_policy = "inherited_policy.gd"
	check(Registry.new().configure(inherited) == "", "policy may inherit declared service interface")

	var legacy := {"shooter": {"project": "res://examples/shooter", "manifest": _manifest("shooter")}, "turns": {"project": "res://examples/turn_based", "manifest": _manifest("turns")}}
	var defaults := Wire.decode(FileAccess.get_file_as_bytes("res://examples/framework/services.json"))
	var legacy_registry = Registry.new()
	check(legacy_registry.configure(legacy, defaults) == "", "previous two-game indexes gain trusted example defaults")
	check(legacy.shooter.size() == 2, "legacy input remains untouched")
	var no_services := {"race": {"project": fixture, "manifest": _manifest("race")}}
	check(Registry.new().configure(no_services, defaults) == "INVALID_GAME_REGISTRY", "new game cannot inherit another game's services")
	var explicit := legacy.duplicate(true)
	explicit.shooter.name = "Local name"
	check(legacy_registry.configure(explicit, defaults) == "" and legacy_registry.entries.shooter.name == "Local name", "local explicit values override compatibility defaults")
	check(legacy_registry.rewards.shooter.calculate({"payload": {"players": []}}) == [], "existing shooter static rewards remain callable")

	var two := {"race": _entry("race", "shared"), "board": _entry("board", "board_space")}
	var merged_registry = Registry.new()
	check(merged_registry.configure(two) == "", "default shared space may coexist with independent game")
	var shared: Dictionary = merged_registry.catalog_for({"race": "shared", "board": "shared"})
	check(not shared.is_empty() and shared.spaces.shared.items.has_all(["race_free", "board_free"]), "sharing retains items already in the default shared space")
	check(Catalog.new().configure(shared) == "", "combined shared catalog remains valid")
	var first := _catalog("alpha", "alpha_space", 70)
	var second := _catalog("beta", "beta_space", 70)
	_write("alpha.json", JSON.stringify(first))
	_write("beta.json", JSON.stringify(second))
	var many := {"alpha": _entry("alpha", "alpha_space"), "beta": _entry("beta", "beta_space")}
	many.alpha.asset_catalog = "alpha.json"
	many.beta.asset_catalog = "beta.json"
	var many_registry = Registry.new()
	check(many_registry.configure(many) == "", "separate catalogs may each fit their item budget")
	check(many_registry.catalog_for({"alpha": "shared", "beta": "shared"}).is_empty(), "oversized merged space rejected before config save")
	var conflict := _catalog("board", "garage")
	conflict.spaces.garage.items = {"race_free": {"name": "Conflict", "price": 0}}
	conflict.games.board.slots.choice.allowed = ["race_free"]
	conflict.games.board.slots.choice.default = "race_free"
	_write("conflict.json", JSON.stringify(conflict))
	bad = base.duplicate(true)
	bad.board = _entry("board", "garage")
	bad.board.asset_catalog = "conflict.json"
	_reject(registry, bad, "ASSET_CATALOG_CONFLICT", "conflicting item definition")
	conflict = _catalog("board", "board_space")
	conflict.level_thresholds = [0, 2]
	_write("thresholds.json", JSON.stringify(conflict))
	bad.board.asset_catalog = "thresholds.json"
	_reject(registry, bad, "ASSET_CATALOG_CONFLICT", "incompatible level thresholds")
	check(Validator.validate_file(base, "res://schemas/managed_game_registry.schema.json") == "", "standalone registration schema accepts explicit new game")
	var prepared := base.duplicate(true)
	prepared.race.prepared_input_receipt = {"format": 1, "algorithm": "roomkit-prepared-input-v1", "sha256": "a".repeat(64), "files": [{"path": "game_manifest.json", "sha256": "b".repeat(64)}]}
	check(Registry.new().configure(prepared) == "", "frozen build receipt coexists with the runtime registry")
	var invalid_receipt := prepared.duplicate(true)
	invalid_receipt.race.prepared_input_receipt.algorithm = "unknown"
	_reject(registry, invalid_receipt, "INVALID_GAME_REGISTRY", "unknown frozen input algorithm")
	for receipt_path in ["../private", "/private", "game/../private", "game\\private", "C:/private"]:
		invalid_receipt = prepared.duplicate(true)
		invalid_receipt.race.prepared_input_receipt.files[0].path = receipt_path
		_reject(registry, invalid_receipt, "INVALID_GAME_REGISTRY", "unsafe frozen input metadata path")
	print("MANAGED_REGISTRY_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _reject(registry, value: Dictionary, code: String, label: String) -> void:
	var before: Dictionary = registry.entries.duplicate(true)
	var previous_policy = registry.policies.get("race")
	var previous_catalog: Dictionary = registry.catalog.duplicate(true)
	var previous_rewards: Dictionary = registry.rewards.duplicate()
	var previous_schemas: Dictionary = registry.result_schemas.duplicate()
	var previous_spaces: Dictionary = registry.default_spaces.duplicate()
	check(registry.configure(value) == code, "reject " + label)
	check(registry.entries == before and registry.catalog == previous_catalog and registry.policies.get("race") == previous_policy and registry.rewards == previous_rewards and registry.result_schemas == previous_schemas and registry.default_spaces == previous_spaces, "failed registration is atomic: " + label)

func _entry(game_id: String, space: String) -> Dictionary:
	var path := game_id + "-" + space + "-catalog.json"
	_write(path, JSON.stringify(_catalog(game_id, space)))
	return {"project": fixture, "manifest": _manifest(game_id), "name": game_id, "asset_catalog": path, "asset_policy": "policy.gd", "result_schema": "result.schema.json", "reward_script": "reward.gd"}

func _manifest(game_id: String) -> Dictionary:
	var version := Engine.get_version_info()
	var fixture_version := "%d.%d.%d.%s" % [version.major, version.minor, version.patch, version.status]
	return {"manifest_version": 1, "game_id": game_id, "build_id": game_id + "-registry-test", "control_protocol": 1, "game_protocol": 1, "sdk_version": "0.5.0", "godot_version": fixture_version, "compatibility_id": game_id + "-v1", "server_artifact": game_id + "-artifact", "transport": "enet", "max_players": 16, "modes": {"sprint": {"min_players": 1, "max_players": 16, "maps": ["track"], "allow_join_in_progress": true}}}

func _catalog(game_id: String, space: String, count: int = 1) -> Dictionary:
	var item := game_id + "_free"
	var items := {item: {"name": "Free", "price": 0}}
	for index in range(1, count):
		items[game_id + "_item" + str(index)] = {"name": "Item", "price": 1}
	return {"version": 1, "spaces": {space: {"items": items}}, "games": {game_id: {"space": space, "slots": {"choice": {"allowed": [item], "default": item}}}}}

func _write(name: String, content: String) -> void:
	var file := FileAccess.open(fixture.path_join(name), FileAccess.WRITE)
	if file == null:
		push_error("Registry test fixture write failed")
		quit(2)
		return
	file.store_string(content)
	file.close()

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
