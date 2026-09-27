extends SceneTree
## Launch grants carry each room's result signing key. This drives the real
## ResultService.prepare_launch path and checks that the key never exists in any
## file other than the SQLite database while or after it is stored, that stored
## keys still verify signed results, and that error codes are unchanged.
const Service = preload("res://host/core/result_service.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const GAME := "grant_fixture"
const DATABASE := "assets.sqlite"
const DATABASE_FILES := ["assets.sqlite", "assets.sqlite-wal", "assets.sqlite-shm"]
var passed := 0
var failed := 0
var directory := ""
var service = Service.new()
var seen_files := {}
var timings: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-grant-storage-" + Wire.uid())
	print("GRANT_STORAGE_EVIDENCE_DIR=", directory)
	if not check(service.initialize(directory, _schemas(), DATABASE).ok, "real result service opens SQLite"):
		finish()
		return
	var before := _handle_count()
	var secrets := {}
	for index in 5:
		var row := _row(index)
		var prepared := _prepare(row)
		if not check(prepared.ok and str(prepared.config.secret).length() == 64, "grant %d stored and returns a 64-hex key" % index):
			continue
		secrets[row.launch_id] = prepared.config.secret
		check(_files_containing(prepared.config.secret).is_empty(), "grant %d key appears in no file except the database" % index)
	var after := _handle_count()
	check(before > 0 and after - before <= 8, "grant helper calls release their process handles (%d -> %d)" % [before, after])
	check(seen_files.is_empty(), "no temporary file existed in the data directory during grant calls: " + str(seen_files.keys()))
	var reloaded = Service.new()
	check(reloaded.initialize(directory, _schemas(), DATABASE).ok, "new service instance reloads grants")
	var identical := secrets.size() == 5
	for launch in secrets:
		identical = identical and reloaded.grants.get(launch, {}).get("secret", "") == secrets[launch]
	check(identical, "every reloaded key matches the issued key byte for byte")
	if not secrets.is_empty():
		var launch: String = secrets.keys()[0]
		var record := {"game_id": GAME, "build_id": "grant_build", "room_id": reloaded.grants[launch].room_id, "launch_id": launch, "match_id": "m_" + launch + "_final", "result_id": Wire.uid(), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}
		check(reloaded.accept({"record": record, "signature": Format.sign(record, secrets[launch])}).ok, "result signed with the stored key is accepted after reload")
		var forged := {"record": record.duplicate(true), "signature": "0".repeat(64)}
		forged.record.result_id = Wire.uid()
		check(reloaded.accept(forged).code == "AUTH_FAILED", "forged signature still refused")
		var duplicate := _prepare({"game_id": GAME, "build_id": "grant_build", "room_id": "grant_room_dup", "launch_id": launch})
		check(not duplicate.ok and duplicate.code == "STORAGE_UNAVAILABLE", "duplicate launch_id keeps the previous STORAGE_UNAVAILABLE result")
		var again = Service.new()
		check(again.initialize(directory, _schemas(), DATABASE).ok and again.grants[launch].secret == secrets[launch], "failed duplicate grant leaves the stored key unchanged")
	check(_fixture("fill_launches").get("launch_count", 0) == 255, "fixture fills launches to 255")
	check(_prepare(_row(300)).ok, "256th grant still accepted")
	var over := _prepare(_row(301))
	check(not over.ok and over.code == "STORAGE_CAPACITY_EXCEEDED", "257th grant keeps STORAGE_CAPACITY_EXCEEDED")
	check(_fixture("count").get("launch_count", 0) == 256, "capacity refusal adds no row")
	check(seen_files.is_empty(), "still no temporary file after error-path grants: " + str(seen_files.keys()))
	finish()

func _schemas() -> Dictionary:
	return {GAME: "res://schemas/summary_result.schema.json"}

func _row(index: int) -> Dictionary:
	return {"game_id": GAME, "build_id": "grant_build", "room_id": "grant_room_%d" % index, "launch_id": Wire.uid()}

func _prepare(row: Dictionary) -> Dictionary:
	# Worker thread plus 2 ms directory polling: a request file written for the
	# call would exist for the whole helper run (about a second) and be seen.
	var thread := Thread.new()
	var started := Time.get_ticks_usec()
	if thread.start(service.prepare_launch.bind(row)) != OK:
		return {"ok": false, "code": "THREAD_FAILED"}
	while thread.is_alive():
		_scan()
		OS.delay_msec(2)
	var result: Variant = thread.wait_to_finish()
	timings.append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	_scan()
	return result if result is Dictionary else {"ok": false}

func _scan() -> void:
	for name in DirAccess.get_files_at(directory):
		if name not in DATABASE_FILES:
			seen_files[name.get_slice("-", 0)] = true

func _files_containing(secret: String) -> Array:
	# Test-owned directory only. SQLite files are the intended key store.
	var found: Array = []
	var pending: Array = [directory]
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			pending.append(folder.path_join(sub))
		for name in DirAccess.get_files_at(folder):
			if folder == directory and name in DATABASE_FILES:
				continue
			if secret in FileAccess.get_file_as_string(folder.path_join(name)):
				found.append(folder.path_join(name))
	return found

func _handle_count() -> int:
	var output: Array = []
	if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).HandleCount" % OS.get_process_id()], output, false, false) != 0 or output.is_empty():
		return -1
	return int(str(output[0]).strip_edges())

func _fixture(mode: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/grant_database.ps1"), "-Directory", directory, "-Mode", mode], output, false, false)
	var parsed: Variant = JSON.parse_string(str(output[0])) if code == 0 and not output.is_empty() else null
	return parsed if parsed is Dictionary else {}

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS grant_storage: ", text)
	else:
		failed += 1
		printerr("FAIL grant_storage: ", text)
	return value

func finish() -> void:
	var sorted := timings.duplicate()
	sorted.sort()
	if not sorted.is_empty():
		print("GRANT_TIMING median=", sorted[sorted.size() / 2], "ms min=", sorted[0], "ms max=", sorted[-1], "ms samples=", timings)
	print("GRANT_STORAGE_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
