extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Lobby = preload("res://host/lobby_server.gd")
const Client = preload("res://sdk/roomkit/client/room_client.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var manager = Manager.new()
var lobby = Lobby.new()
var observer
var initialized := false
var passed := 0
var failed := 0
var processes: Array = []
var work := ""
var stop_file := ""
var started := 0

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if initialized:
		manager.poll()
		lobby.poll()
	return false

func _run() -> void:
	started = Time.get_ticks_msec()
	work = ProjectSettings.globalize_path("res://logs/players-" + Wire.uid())
	DirAccess.make_dir_recursive_absolute(work)
	stop_file = work.path_join("leave.signal")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 10000
	check(manager.initialize(config).ok, "host initialized")
	check(Development.register_multiplayer(manager).ok, "multiplayer build registered")
	check(lobby.start(manager) == OK, "standard WebSocket lobby bound on loopback")
	initialized = true
	print("演示：大厅已启动，先检查无效入场票。")
	observer = Client.new()
	root.add_child(observer)
	var identity: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	identity.url = "ws://127.0.0.1:" + str(lobby.port)
	check(observer.configure(identity), "SDK configured")
	var session: Dictionary = await observer.open_session("Test Observer")
	check(session.ok, "development session over real WebSocket")
	if not session.ok:
		await finish()
		return
	var attack_room: Dictionary = await observer.create_room({"mode": "sandbox", "map": "empty", "capacity": 2}, "attack-room")
	check(attack_room.ok, "test room created via lobby")
	if not attack_room.ok:
		await finish()
		return
	var attack_id: String = attack_room.payload.room.room_id
	check(await until(func(): return manager.snapshot(attack_id).get("state", "") == "READY"), "room READY before admission test")
	var row: Dictionary = manager.snapshot(attack_id)
	var info_path := work.path_join("public-room.json")
	write_json(info_path, {"room_id": attack_id, "launch_id": row.launch_id, "host": "127.0.0.1", "port": row.port})
	var intruder := start_player("intruder", info_path)
	check(await until(func(): return read_report(intruder).get("phase", "") == "DONE", 18000), "bad ticket client finishes")
	check(read_report(intruder).get("ok", false), "invalid ticket rejected before IN_ROOM over real ENet")
	check(lobby.admissions.count(attack_id) == 0, "invalid ticket creates no seat or member")
	var stopped: Dictionary = await observer.stop_room(attack_id)
	check(stopped.ok, "owner stops room via lobby")
	check(await until(func(): return manager.snapshot(attack_id).get("cleaned", false)), "attack room safely reclaimed")
	print("演示：正在启动玩家一和玩家二。")
	var one := start_player("creator")
	var two := start_player("guest")
	var ready_two := await until(func(): return read_report(one).get("phase", "") == "TWO_PLAYERS" and read_report(two).get("phase", "") == "TWO_PLAYERS", 25000)
	check(ready_two, "two independent client processes joined and see each other")
	if ready_two:
		var first := read_report(one)
		var second := read_report(two)
		check(first.user_id != second.user_id and first.room_id == second.room_id, "distinct stable identities in same room")
		check(first.get("idempotency", false), "lost create response retry doesn't create another room; conflicting key rejected")
		check(first.get("loading_barrier", false) and second.get("loading_barrier", false), "both clients wait for scene preparation before IN_ROOM")
		check(first.phases.has("SYNCHRONIZING") and second.phases.has("SYNCHRONIZING"), "initial snapshot acknowledged before entering")
		check(lobby.admissions.count(first.room_id, "CONNECTED") == 2 and lobby.admissions.count(first.room_id) == 2, "two connected seats counted once")
		var full: Dictionary = await observer.join_room(first.room_id)
		check(not full.ok and full.code == "ROOM_FULL", "third client rejected while two-seat room full")
		var denied: Dictionary = await observer.stop_room(first.room_id)
		check(not denied.ok and denied.code == "AUTH_FAILED", "non-owner cannot stop another user's room")
		var old: String = observer.config.compatibility_id
		observer.config.compatibility_id = "incompatible"
		var mismatch: Dictionary = await observer.list_rooms()
		check(not mismatch.ok and mismatch.code == "BUILD_MISMATCH", "incompatible build rejected with explicit error")
		observer.config.compatibility_id = old
		print("演示：玩家一和玩家二已进入同一个房间，双方都看到了两人名单。")
	var marker := FileAccess.open(stop_file, FileAccess.WRITE)
	marker.store_string("leave")
	marker.close()
	check(await until(func(): return read_report(one).get("phase", "") == "DONE" and read_report(two).get("phase", "") == "DONE", 12000), "both clients finish leave flow")
	check(read_report(one).get("returned_to_lobby", false) and read_report(two).get("returned_to_lobby", false), "both clients return to lobby with same session")
	check(await until(func(): return lobby.admissions.seats.is_empty()), "all player seats released")
	print("演示：两位玩家已退出并返回大厅，正在关闭房间。")
	await finish()

func start_player(role: String, info: String = "") -> Dictionary:
	var launch := Wire.uid()
	var output := work.path_join(role + ".json")
	var descriptor := {"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", work.path_join(role + "-godot.log"), "--script", "res://examples/minimal/test_player.gd", "--", "--role=" + role, "--url=ws://127.0.0.1:" + str(lobby.port), "--output=" + output, "--stop-file=" + stop_file]}
	if info != "":
		descriptor.args.append("--room-info=" + info)
	var result: Dictionary = manager.launcher.launch(descriptor, launch, PackedStringArray(["--launch-id=" + launch]))
	check(result.ok, "start verified client " + role)
	var record := {"launch_id": launch, "pid": result.get("pid", 0), "output": output, "role": role}
	processes.append(record)
	return record

func read_report(process: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(process.output):
		return {}
	return Wire.decode(FileAccess.get_file_as_bytes(process.output))

func until(predicate: Callable, timeout_ms: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.03).timeout
	return bool(predicate.call())

func finish() -> void:
	if is_instance_valid(observer):
		observer.close()
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 16000), "all room processes exited and ports reclaimed")
	for process in processes:
		var exited := await until(func(): return manager.launcher.probe(process.launch_id) == "exited", 3000)
		if not exited:
			manager.launcher.terminate(process.launch_id)
			exited = await until(func(): return manager.launcher.probe(process.launch_id) == "exited", 3000)
		check(exited, "verified client exit " + process.role)
		manager.launcher.forget(process.launch_id)
	check(manager.ports.leases.is_empty() and lobby.admissions.seats.is_empty(), "no port or admission leases remain")
	lobby.close()
	check(manager.close(), "host listeners closed")
	initialized = false
	var reports: Array = []
	for process in processes:
		reports.append(read_report(process))
	write_json("res://logs/players-result.json", {"passed": passed, "failed": failed, "client_reports": reports, "elapsed_ms": Time.get_ticks_msec() - started, "evidence_dir": work})
	print("演示完成：房间和测试玩家均已退出。" if failed == 0 else "演示有失败，请查看 logs/players-result.json。")
	print("PLAYERS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS players: ", description)
	else:
		failed += 1
		printerr("FAIL players: ", description)
