extends SceneTree
## Review test for asset transactions through the real AssetService: purchase,
## selection, duplicates, request conflicts, retry after reopen, and concurrent
## debits, checked against the SQLite receipt chain after every step. It also
## counts how many storage helper calls each operation makes (one request file
## exists per call for about a second, so 2 ms directory polling sees each one).
## Behaviour assertions must hold before and after the asset.snapshot change;
## only the round-trip counts are expected to differ.
const Service = preload("res://host/core/asset_service.gd")
const Shooter = preload("res://examples/shooter/asset_policy.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const LOBBY := {"location": "lobby"}
var passed := 0
var failed := 0
var directory := ""
var catalog: Dictionary = {}
var service = Service.new()
var admin := {"user_id": "snapshot-admin", "role": "admin"}
var user := {"user_id": "snapshot-user", "role": "player"}
var trips := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-asset-snapshot-" + Wire.uid())
	print("ASSET_SNAPSHOT_EVIDENCE_DIR=", directory)
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	if not check(service.initialize(directory, catalog).ok, "real asset SQLite initializes"):
		finish()
		return
	var grant := _counted("adjust", _adjust.bind(250, "grant_250"))
	check(grant.ok and grant.state.credits == 250, "administrator grant commits")
	var purchase := {"kind": "purchase", "item_id": "smg", "request_id": "buy_smg"}
	var bought := _counted("purchase", _perform.bind(purchase))
	check(bought.ok and bought.get("code", "") == "" and bought.state.credits == 150 and "smg" in bought.state.owned, "purchase debits 100 once and grants ownership")
	var ledger := _ledger()
	var retry := _counted("duplicate", _perform.bind(purchase))
	check(retry.ok and retry.code == "DUPLICATE" and retry.state == bought.state and _ledger() == ledger, "same purchase request returns the receipt without a second debit")
	var changed := purchase.duplicate(true)
	changed.item_id = "shotgun"
	check(_perform(changed).code == "REQUEST_CONFLICT" and _ledger() == ledger, "same request id with different content is refused and changes nothing")
	check(_perform({"kind": "select", "item_id": "shotgun", "slot": "primary", "request_id": "select_unowned"}).code == "ITEM_NOT_OWNED" and _ledger() == ledger, "selecting an unowned item is refused")
	check(_perform({"kind": "purchase", "item_id": "shotgun", "request_id": "buy_shotgun_poor"}).code == "INSUFFICIENT_CREDITS" and _ledger() == ledger, "purchase above balance is refused")
	check(_perform({"kind": "purchase", "item_id": "smg", "request_id": "buy_smg_again"}).code == "ALREADY_OWNED" and _ledger() == ledger, "buying an owned item again is refused")
	var selection := {"kind": "select", "item_id": "smg", "slot": "primary", "request_id": "select_smg"}
	var selected := _counted("select", _perform.bind(selection))
	check(selected.ok and selected.state.profiles.shooter.primary == "smg" and selected.state.credits == 150, "selection saves the default without touching credits")
	check(_perform(selection).code == "DUPLICATE", "same selection request is idempotent")
	# A client that lost the reply reconnects to a fresh host process and retries.
	var reopened = Service.new()
	check(reopened.initialize(directory, catalog).ok, "new service instance reopens the database")
	var after_reopen: Dictionary = reopened.perform(user, "shooter", purchase, Shooter.new(), LOBBY)
	check(after_reopen.code == "DUPLICATE" and after_reopen.state == bought.state, "retry after reopen returns the original purchase receipt")
	check(_chain_ok(), "receipt chain and state agree after sequential operations")
	await _concurrent_same_request()
	await _concurrent_overspend()
	await _concurrent_grants()
	for operation in trips:
		print("ROUND_TRIPS ", operation, "=", trips[operation])
	check(trips.get("purchase", 0) == 2 and trips.get("select", 0) == 2 and trips.get("adjust", 0) == 2, "purchase, select and grant each use two storage calls")
	check(trips.get("duplicate", 0) == 1, "an already committed request is answered with one storage call")
	finish()

func _concurrent_same_request() -> void:
	check(_adjust(200, "grant_for_race").ok, "top up before duplicate race")
	var before := _state()
	var command := {"kind": "purchase", "item_id": "shotgun", "request_id": "race_same"}
	var results: Array = await _race([command, command, command, command])
	var fresh := results.filter(func(r): return r.ok and r.get("code", "") == "").size()
	var duplicates := results.filter(func(r): return r.ok and r.get("code", "") == "DUPLICATE").size()
	var after := _state()
	check(fresh == 1 and duplicates == 3, "four concurrent copies: one commit, three receipts (%d/%d)" % [fresh, duplicates])
	check(after.credits == before.credits - 200 and int(after.revision) == int(before.revision) + 1 and "shotgun" in after.owned, "shotgun debited exactly once")
	check(_chain_ok(), "receipt chain intact after duplicate race")

func _concurrent_overspend() -> void:
	# Fresh player with 250 credits; smg (100) + shotgun (200) together exceed it.
	var player := {"user_id": "snapshot-racer", "role": "player"}
	check(service.adjust(admin, player.user_id, "shooter", {"kind": "adjust", "credits": 250, "experience": 0, "reason": "race", "request_id": "racer_grant"}).ok, "racer funded")
	var results: Array = await _race([{"kind": "purchase", "item_id": "smg", "request_id": "racer_smg"}, {"kind": "purchase", "item_id": "shotgun", "request_id": "racer_shotgun"}], player)
	var accepted := results.filter(func(r): return r.ok).size()
	var after: Dictionary = service.read(player.user_id, "shooter").state
	var spent := 250 - int(after.credits)
	check(accepted == 1 and (spent == 100 or spent == 200) and int(after.revision) == 2, "overspending race: exactly one purchase commits, balance never negative (spent %d)" % spent)
	var loser: Dictionary = results.filter(func(r): return not r.ok)[0] if accepted == 1 else {}
	check(loser.get("code", "") in ["ASSET_VERSION_CONFLICT", "INSUFFICIENT_CREDITS"], "losing purchase reports a conflict or shortage: " + str(loser.get("code", "")))
	check(_chain_ok(player.user_id), "racer receipt chain intact")
	# The losing request left no receipt, so the same id can succeed later.
	var missing := "racer_shotgun" if "smg" in after.owned else "racer_smg"
	check(service.adjust(admin, player.user_id, "shooter", {"kind": "adjust", "credits": 200, "experience": 0, "reason": "retry", "request_id": "racer_topup"}).ok, "racer topped up")
	var item := "shotgun" if missing == "racer_shotgun" else "smg"
	check(service.perform(player, "shooter", {"kind": "purchase", "item_id": item, "request_id": missing}, Shooter.new(), LOBBY).ok, "losing request id retried later commits once")
	check(_chain_ok(player.user_id), "racer chain intact after retry")

func _concurrent_grants() -> void:
	var before := _state()
	var commands: Array = []
	for index in 5:
		commands.append({"kind": "adjust", "credits": 10, "experience": 0, "reason": "race", "request_id": "grant_race_%d" % index})
	var results: Array = await _race(commands, admin, true)
	var accepted := results.filter(func(r): return r.ok).size()
	var conflicts := results.filter(func(r): return r.get("code", "") == "ASSET_VERSION_CONFLICT").size()
	var after := _state()
	check(accepted >= 1 and accepted + conflicts == 5, "five concurrent grants: %d committed, %d version conflicts, no other outcome" % [accepted, conflicts])
	check(after.credits == before.credits + 10 * accepted and int(after.revision) == int(before.revision) + accepted, "no lost update: credits and revision match committed grants")
	check(_chain_ok(), "receipt chain intact after grant race")

func _race(commands: Array, actor: Dictionary = {}, administrative: bool = false) -> Array:
	var player: Dictionary = user if actor.is_empty() or administrative else actor
	var threads: Array = []
	for command in commands:
		var thread := Thread.new()
		if check(thread.start(_race_worker.bind(player, command, administrative)) == OK, "race worker starts"):
			threads.append(thread)
	var results: Array = []
	for thread in threads:
		while thread.is_alive():
			await process_frame
		results.append(thread.wait_to_finish())
	return results

func _race_worker(player: Dictionary, command: Dictionary, administrative: bool) -> Dictionary:
	# Each worker owns a service instance, as separate Operator worker calls do.
	var instance = Service.new()
	instance.catalog = service.catalog
	instance.repository.root = service.repository.root
	instance.repository.database = service.repository.database
	instance._ready = true
	if administrative:
		return instance.adjust(admin, user.user_id, "shooter", command)
	return instance.perform(player, "shooter", command, Shooter.new(), LOBBY)

func _perform(command: Dictionary) -> Dictionary:
	return service.perform(user, "shooter", command, Shooter.new(), LOBBY)

func _adjust(credits: int, request_id: String) -> Dictionary:
	return service.adjust(admin, user.user_id, "shooter", {"kind": "adjust", "credits": credits, "experience": 0, "reason": "snapshot test", "request_id": request_id})

func _state(user_id: String = user.user_id) -> Dictionary:
	return service.read(user_id, "shooter").state

func _ledger(user_id: String = user.user_id) -> Array:
	var audit: Dictionary = service.repository.execute({"op": "asset.audit", "user_id": user_id})
	return audit.get("rows", [])

func _chain_ok(user_id: String = user.user_id) -> bool:
	# Oldest first: each receipt's previous_body must equal the prior body, and the
	# newest body must equal the stored state; revision counts the receipts.
	var rows: Array = _ledger(user_id).filter(func(row): return row.space_id == "shooter")
	rows.reverse()
	var previous := ""
	for row in rows:
		if str(row.previous_body) != previous:
			return false
		previous = str(row.body)
	var stored: Dictionary = service.repository.execute({"op": "asset.read", "user_id": user_id, "space_id": "shooter"})
	var state: Variant = JSON.parse_string(str(stored.get("body", "")))
	return stored.ok and str(stored.body) == previous and state is Dictionary and int(state.revision) == rows.size()

func _counted(operation: String, work: Callable) -> Dictionary:
	# One-shot calls leave one request file each; resident calls are counted by the
	# database's worker (asset.read/snapshot/commit only, as routed in production).
	var names := {}
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", service.repository.database, 10000) if Resident.enabled() else null
	var before: int = store.requests if store != null else 0
	var thread := Thread.new()
	if thread.start(work) != OK:
		return {"ok": false, "code": "THREAD_FAILED"}
	while thread.is_alive():
		for name in DirAccess.get_files_at(directory):
			if name.begins_with("request-"):
				names[name] = true
		OS.delay_msec(2)
	var result: Variant = thread.wait_to_finish()
	trips[operation] = names.size() + ((store.requests - before) if store != null else 0)
	return result if result is Dictionary else {"ok": false}

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS asset_snapshot: ", text)
	else:
		failed += 1
		printerr("FAIL asset_snapshot: ", text)
	return value

func finish() -> void:
	print("ASSET_SNAPSHOT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
