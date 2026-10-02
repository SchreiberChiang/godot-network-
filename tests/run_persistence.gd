extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Service = preload("res://tests/fakes/lost_result_ack.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var manager = Manager.new()
var service = Service.new()
var initialized := false
var passed := 0
var failed := 0
var root_path := ""
var workers: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if initialized:
		manager.poll()
	return false

func _run() -> void:
	root_path = ProjectSettings.globalize_path("res://data/test-results-" + Wire.uid())
	if not check(service.initialize(root_path, {"minimal_room": "res://schemas/summary_result.schema.json"}).ok, "real Windows SQLite initialized"):
		quit(1)
		return
	print("SQLITE_VERSION=", service.repository.version)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 20000
	check(manager.initialize(config).ok, "host initialized")
	manager.result_service = service
	service.manager = manager
	initialized = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	check(manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", root_path.path_join("normal-room.log"), "--script", "res://tests/fixtures/result_room.gd", "--"]}}).ok, "result-capable room registered")
	var created: Dictionary = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
	if not check(created.ok, "durable launch grant saved before child start"):
		await finish()
		return
	check(await until(func(): return service.accepted_count >= 2 and service.ack_count >= 1, 20000), "lost control ACK causes real child retry")
	var row: Dictionary = manager.snapshot(created.room_id)
	var directory := root_path.path_join("outbox").path_join(row.launch_id)
	check(await until(func(): return pending_files(directory).is_empty(), 5000), "matching commit ACK clears room outbox")
	var stored: Dictionary = service.repository.execute({"op": "inspect"})
	check(stored.ok and stored.count == 1, "retried result has one SQLite row")
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 8000), "result room safely stops and reclaims")
	var closed_grants: Dictionary = service.repository.execute({"op": "grants"})
	check(closed_grants.ok and closed_grants.grants.filter(func(grant): return grant.launch_id == row.launch_id and str(grant.ended_at) != "").size() == 1, "normal real room stop durably starts seven-day grant window")
	if not stored.ok or stored.get("rows", []).is_empty():
		await finish()
		return
	var record: Dictionary = JSON.parse_string(stored.rows[0].body)
	var secret: String = service.grants[row.launch_id].secret
	var item := {"record": record, "signature": Format.sign(record, secret)}
	check(service.accept(item).code == "DUPLICATE", "same ID and content returns original confirmation")
	var changed := record.duplicate(true)
	changed.payload.round = 2
	check(service.accept({"record": changed, "signature": Format.sign(changed, secret)}).code == "RESULT_CONFLICT", "same ID changed payload rejected")
	changed = record.duplicate(true)
	changed.result_id = Wire.uid()
	check(service.accept({"record": changed, "signature": Format.sign(changed, secret)}).code == "MATCH_RESULT_CONFLICT", "new ID cannot duplicate a match result")
	check(service.accept({"record": record, "signature": "0".repeat(64)}).code == "AUTH_FAILED", "forged outbox signature rejected")
	changed.game_id = "other_game"
	check(service.accept({"record": changed, "signature": Format.sign(changed, secret)}).code == "AUTH_FAILED", "signed cross-game result rejected")
	var reopened = Service.new()
	check(reopened.initialize(root_path, {"minimal_room": "res://schemas/summary_result.schema.json"}).ok, "repository reopens existing database")
	check(reopened.repository.execute({"op": "inspect"}).count == 1 and reopened.accept(item).code == "DUPLICATE", "idempotency survives repository reopen")
	var backup_path := root_path.path_join("backup.sqlite")
	check(service.repository.execute({"op": "backup", "destination": backup_path}).ok, "native SQLite online backup completes")
	var restored = Repository.new()
	check(restored.initialize(root_path, "backup.sqlite").ok, "backup opens as independent database")
	var inspected: Dictionary = restored.execute({"op": "inspect"})
	check(inspected.ok and inspected.count == 1 and inspected.integrity == "ok", "backup result and integrity verified")
	var unicode_record := record.duplicate(true)
	unicode_record.result_id = Wire.uid()
	unicode_record.match_id += "_unicode"
	unicode_record.payload.players = [{"user_id": "玩家'\"1", "score": 3}]
	check(service.accept({"record": unicode_record, "signature": Format.sign(unicode_record, secret)}).ok, "bound SQL values accept Unicode and quotes")
	var unicode_stored: Dictionary = service.repository.execute({"op": "inspect"})
	check(unicode_stored.count == 2 and JSON.parse_string(unicode_stored.rows[0].body).payload.players[0].user_id == "玩家'\"1", "SQLite UTF-8 round trip preserves result payload")
	var corrupt_path := root_path.path_join("corrupt.sqlite")
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_string("not a database")
	corrupt.close()
	var broken = Repository.new()
	check(not broken.initialize(root_path, "corrupt.sqlite").ok, "corrupt database fails closed")
	var forged_file := directory.path_join("forged.json")
	write_json(forged_file, {"record": record, "signature": "0".repeat(64)})
	check(reopened.recover().rejected == 1 and FileAccess.file_exists(directory.path_join("forged.rejected.json")), "recovery quarantines forged files without discarding evidence")
	await crash_recovery()
	await finish()

func crash_recovery() -> void:
	var crash_store := root_path.path_join("crash-store")
	var report_path := root_path.path_join("crash-host.json")
	var host := launch_host(crash_store, report_path, "pending")
	check(await until(func(): return read_json(report_path).get("phase", "") == "PENDING", 22000), "real host receives durable outbox before commit")
	var row := read_json(report_path)
	if row.is_empty():
		return
	var directory := crash_store.path_join("outbox").path_join(row.launch_id)
	check(pending_files(directory).size() == 1, "pending result is outside ephemeral run directory")
	check(manager.launcher.terminate(host.launch_id), "terminate only verified test host process")
	check(await until(func(): return manager.launcher.probe(host.launch_id) == "exited", 6000), "test host process exit confirmed")
	check(await until(func(): return FileAccess.file_exists(directory.path_join("worker-exited.marker")), 10000), "orphan room exits on control disconnect")
	var udp := ENetMultiplayerPeer.new()
	udp.set_bind_ip("127.0.0.1")
	check(udp.create_server(int(row.port), 1) == OK, "orphan room releases its UDP port")
	udp.close()
	check(pending_files(directory).size() == 1, "unacknowledged outbox survives both process exits")
	var recovery_path := root_path.path_join("recovery-host.json")
	var recovery := launch_host(crash_store, recovery_path, "recover")
	check(await until(func(): return manager.launcher.probe(recovery.launch_id) == "exited", 20000), "fresh recovery host exits normally")
	var report := read_json(recovery_path)
	check(report.get("recovered", {}).get("accepted", 0) == 1 and report.get("stored", {}).get("count", 0) == 1, "fresh host recovers exactly one persisted result")
	check(report.get("closed_grants", []).filter(func(grant): return grant.launch_id == row.launch_id and str(grant.ended_at) != "").size() == 1, "cross-run read-only exit recovery durably closes real orphan grant")
	check(pending_files(directory).is_empty(), "recovered outbox removed only after commit")
	var again_path := root_path.path_join("recovery-again.json")
	var again := launch_host(crash_store, again_path, "recover")
	check(await until(func(): return manager.launcher.probe(again.launch_id) == "exited", 20000), "second fresh host verifies recovery")
	check(read_json(again_path).get("stored", {}).get("count", 0) == 1 and read_json(again_path).get("recovered", {}).get("accepted", -1) == 0, "restarting recovery cannot duplicate result")

func launch_host(store: String, report: String, mode: String) -> Dictionary:
	var launch := Wire.uid()
	var result: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", root_path.path_join(mode + "-" + launch + ".log"), "--script", "res://tests/fixtures/result_host.gd", "--", "--store=" + store, "--mode=" + mode, "--report=" + report, "--worker-log=" + root_path.path_join("orphan-room.log")]}, launch, PackedStringArray(["--launch-id=" + launch]))
	check(result.ok, "verified host launch " + mode)
	var worker := {"launch_id": launch}
	workers.append(worker)
	return worker

func pending_files(path: String) -> Array:
	var paths: Array = []
	if DirAccess.dir_exists_absolute(path):
		for name in DirAccess.get_files_at(path):
			if name.ends_with(".json") and not name.ends_with(".rejected.json"):
				paths.append(name)
	return paths

func read_json(path: String) -> Dictionary:
	return Wire.decode(FileAccess.get_file_as_bytes(path), "", 65536) if FileAccess.file_exists(path) else {}

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func until(predicate: Callable, timeout: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return bool(predicate.call())

func finish() -> void:
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 12000), "all owned rooms reclaimed")
	for worker in workers:
		if manager.launcher.probe(worker.launch_id) != "exited":
			manager.launcher.terminate(worker.launch_id)
		check(await until(func(): return manager.launcher.probe(worker.launch_id) == "exited", 8000), "owned test host exit confirmed")
		manager.launcher.forget(worker.launch_id)
	check(manager.close() and manager.ports.leases.is_empty(), "listeners closed and port leases empty")
	initialized = false
	write_json("res://logs/persistence-result.json", {"passed": passed, "failed": failed, "data_root": root_path, "sqlite_version": service.repository.version})
	print("PERSISTENCE_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(ok: bool, label: String) -> bool:
	if ok:
		passed += 1
		print("PASS persistence: ", label)
	else:
		failed += 1
		printerr("FAIL persistence: ", label)
	return ok
