extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Registry = preload("res://host/core/game_registry.gd")
const Ports = preload("res://host/core/port_allocator.gd")
const RacePorts = preload("res://tests/fixtures/racing_ports.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
var manager = Manager.new()
var passed := 0
var failed := 0
var child_pids: Array = []
var settings: Dictionary
var options := {"mode": "sandbox", "map": "empty", "capacity": 8}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	settings.godot_executable = OS.get_executable_path()
	settings.heartbeat_ms = 100
	settings.heartbeat_timeout_ms = 8000
	settings.start_timeout_ms = 4000
	settings.stop_timeout_ms = 600
	var initialized: Dictionary = manager.initialize(settings)
	check(initialized.ok, "G00 real host initialized on loopback")
	if not initialized.ok:
		_finish()
		return
	set_fixture("")
	check(not manager.create_room("unknown", options).ok, "G02 unknown game rejected")
	check(not manager.create_room("minimal_room", {"executable": "anything"}).ok, "G09 request cannot select executable")
	var id := create()
	check(await wait_for(func(): return manager.snapshot(id).get("heartbeats", 0) >= 3), "G01 registered READY with actual child heartbeats")
	var row: Dictionary = manager.snapshot(id)
	check(row.registered and row.state == "READY", "G01 authenticated register precedes READY")
	check(not manager.ports.can_bind(row.port), "G01 UDP remains bound while READY")
	check(not row.has("token") and not row.has("config_path"), "G09 public snapshot redacts bootstrap")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path("res://run").path_join(row.launch_id + ".json")), "G09 private launch file removed after registration")
	await stop_and_check(id, "G01")
	row = manager.snapshot(id)
	check(row.history == ["ALLOCATING", "STARTING", "READY", "DRAINING", "STOPPING", "STOPPED"], "G01 complete ordered state history")
	check(row.stop_notice and row.exit_confirmed, "G01 stopped notice and OS exit independently confirmed")

	manager.registry = Registry.new()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/game_manifest.json"))
	manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": ProjectSettings.globalize_path("res://run/does-not-exist.exe"), "args": []}})
	var missing: Dictionary = manager.create_room("minimal_room", options)
	check(not missing.ok and missing.code == "PROGRAM_NOT_FOUND", "G02 missing program rejected by real launcher")
	check(manager.snapshot(missing.room_id).cleaned and manager.ports.leases.is_empty(), "G02 missing program resources reclaimed")

	# Genuine competing UDP holder; only the stale allocation is injected.
	set_fixture("")
	var held_port: int = manager.ports.acquire("holder_probe")
	manager.ports.release("holder_probe", true)
	var holder_launch := Crypto.new().generate_random_bytes(16).hex_encode()
	var ready_path := ProjectSettings.globalize_path("res://run").path_join(holder_launch + ".ready")
	var holder: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/fixtures/udp_holder.gd", "--", "--port=" + str(held_port), "--ready-path=" + ready_path]}, holder_launch, PackedStringArray(["--launch-id=" + holder_launch]))
	child_pids.append(holder.pid)
	check(holder.ok and await wait_for(func(): return FileAccess.file_exists(ready_path)), "G03 competing real UDP process bound")
	var raced = RacePorts.new()
	raced.raced_port = held_port
	manager.ports = raced
	id = create()
	check(await wait_for(func(): return manager.snapshot(id).get("state", "") == "FAILED"), "G03 actual child rejects occupied UDP bind")
	row = manager.snapshot(id)
	check(not row.history.has("READY") and row.code == "PORT_BIND_FAILED", "G03 never READY on bind failure")
	check(await wait_for(func(): return manager.snapshot(id).get("exit_confirmed", false)), "G03 failed child exit confirmed")
	check(not manager.snapshot(id).cleaned and manager.ports.leases.size() == 1, "G03 port quarantined while competing holder alive")
	check(manager.launcher.probe(holder_launch) == "running", "G03 occupancy owner was not terminated")
	check(manager.launcher.terminate(holder_launch), "G03 test closes only its verified holder")
	check(await wait_for(func(): return manager.snapshot(id).get("cleaned", false)), "G03 quarantine released only after UDP rebind")
	manager.launcher.forget(holder_launch)
	DirAccess.remove_absolute(ready_path)
	manager.ports = Ports.new(int(settings.udp_first), int(settings.udp_last))

	for fixture in ["no_register", "no_ready"]:
		set_fixture(fixture)
		id = create()
		check(await wait_for(func(): return manager.snapshot(id).get("cleaned", false), 12000), "G04 " + fixture + " bounded cleanup")
		row = manager.snapshot(id)
		check(row.state == "FAILED" and row.code == "START_TIMEOUT" and not row.history.has("READY"), "G04 " + fixture + " START_TIMEOUT")
		check(row.exit_confirmed and manager.ports.leases.is_empty(), "G04 " + fixture + " real exit + lease reclaimed")

	set_fixture("delayed_register")
	manager.config.start_timeout_ms = 12000
	id = create()
	row = manager.snapshot(id)
	check(row.state == "STARTING" and not row.registered, "G07 attacks occur before legitimate registration")
	var before: int = manager.rejected_connections
	await inject(Protocol.event("room.register", id, row.launch_id, {"token": "0".repeat(64), "pid": row.pid}, row.game_id, row.build_id))
	await inject(Protocol.event("room.register", id, "f".repeat(32), {"token": manager.rooms[id].token, "pid": row.pid}, row.game_id, row.build_id))
	check(manager.rejected_connections >= before + 2, "G07 wrong credential and launch rejected over real TCP")
	check(not manager.snapshot(id).registered, "G07 forged messages cannot register the room")
	check(await wait_for(func(): return manager.snapshot(id).get("heartbeats", 0) >= 2), "G07 genuine child registers after rejected attempts")
	check(manager.snapshot(id).state == "READY", "G07 invalid sockets do not contaminate healthy room")
	await stop_and_check(id, "G07")
	manager.config.start_timeout_ms = 4000

	set_fixture("")
	var a := create()
	var b := create()
	check(await wait_for(func(): return manager.snapshot(a).get("heartbeats", 0) >= 2 and manager.snapshot(b).get("heartbeats", 0) >= 2), "G05 A and B real processes READY")
	var b_before: int = manager.snapshot(b).heartbeats
	check(manager.launcher.terminate(manager.snapshot(a).launch_id), "G05 terminate verified A only")
	check(await wait_for(func(): return manager.snapshot(a).get("cleaned", false) and manager.snapshot(b).get("heartbeats", 0) > b_before), "G05 A reclaimed while B continues")
	check(manager.snapshot(a).code == "PROCESS_EXITED" and manager.snapshot(b).state == "READY", "G05 crash state isolated")
	await stop_and_check(b, "G05")

	set_fixture("ignore_stop")
	id = create()
	check(await wait_for(func(): return manager.snapshot(id).get("heartbeats", 0) >= 2), "stop timeout fixture READY")
	await stop_and_check(id, "forced stop")
	check(manager.snapshot(id).kill_attempted, "uncooperative child terminated after deadline with verified identity")

	set_fixture("control_drop")
	id = create()
	check(await wait_for(func(): return manager.snapshot(id).get("code", "") == "CONTROL_UNAVAILABLE"), "authenticated control loss immediately makes room unavailable")
	check(await wait_for(func(): return manager.snapshot(id).get("cleaned", false)), "control loss with live child receives bounded cleanup")
	check(manager.snapshot(id).exit_confirmed and manager.snapshot(id).kill_attempted, "control loss terminates only verified owned child")

	for fixture in ["silent", "logic_stall"]:
		set_fixture(fixture)
		manager.config.heartbeat_timeout_ms = 800
		id = create()
		check(await wait_for(func(): return manager.snapshot(id).get("cleaned", false)), fixture + " cleanup")
		check(manager.snapshot(id).code == ("HEARTBEAT_TIMEOUT" if fixture == "silent" else "LOGIC_STALLED"), fixture + " distinct health failure")
	manager.config.heartbeat_timeout_ms = 8000

	set_fixture("")
	for iteration in range(10):
		id = create()
		check(await wait_for(func(): return manager.snapshot(id).get("heartbeats", 0) >= 2), "G08 cycle %d READY" % (iteration + 1))
		await stop_and_check(id, "G08 cycle %d" % (iteration + 1))
	check(manager.active_count() == 0 and manager.ports.leases.is_empty(), "G08 no active records or leases")
	var all_exited := true
	for child_pid in child_pids:
		if child_pid > 0 and OS.is_process_running(child_pid):
			all_exited = false
	check(all_exited, "G08 all recorded children exited")
	manager.stop_all()
	await wait_for(func(): return manager.active_count() == 0, 15000)
	check(manager.close(), "control listener closed after cleanup")
	_finish()

func create() -> String:
	var result: Dictionary = manager.create_room("minimal_room", options)
	check(result.ok, "create accepted")
	var id: String = result.get("room_id", "")
	if not id.is_empty():
		child_pids.append(manager.snapshot(id).pid)
	return id

func set_fixture(value: String) -> void:
	manager.registry = Registry.new()
	check(Development.register_game(manager, value).ok, "registered local fixture " + value)

func wait_for(predicate: Callable, timeout_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		manager.poll()
		if predicate.call():
			return true
		await create_timer(0.03).timeout
	manager.poll()
	return bool(predicate.call())

func stop_and_check(id: String, label: String) -> void:
	manager.stop_room(id)
	check(await wait_for(func(): return manager.snapshot(id).get("cleaned", false)), label + " cleanup complete")
	var row: Dictionary = manager.snapshot(id)
	check(row.get("state", "") == "STOPPED" and row.get("exit_confirmed", false), label + " STOPPED and real process exit")
	check(not manager.ports.leases.has(row.get("launch_id", "")), label + " lease released")

func inject(message: Dictionary) -> void:
	var socket := StreamPeerTCP.new()
	var wire = Transport.new()
	socket.connect_to_host("127.0.0.1", manager.control_port)
	var connected := await wait_for(func():
		socket.poll()
		return socket.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	check(connected, "G07 injection socket connected")
	if connected:
		wire.queue(message)
		wire.flush(socket)
		await wait_for(func():
			socket.poll()
			return socket.get_status() != StreamPeerTCP.STATUS_CONNECTED, 2000)
	socket.disconnect_from_host()

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	var file := FileAccess.open("res://logs/integration-result.json", FileAccess.WRITE)
	var snapshots: Array = []
	for id in manager.rooms:
		snapshots.append(manager.snapshot(id))
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "child_pids": child_pids, "rooms": snapshots}, "  "))
	file.close()
	print("INTEGRATION_RESULT passed=", passed, " failed=", failed, " children=", child_pids.size())
	quit(0 if failed == 0 else 1)
