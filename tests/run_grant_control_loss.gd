extends SceneTree
## Short real ManagedHost/room control-loss check, using isolated SQLite only.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Bus = preload("res://sdk/roomkit/shared/local_rpc.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const Service = preload("res://host/core/result_service.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
const Operator = preload("res://host/operator.gd")
var bus = Bus.new()
var launcher = Launcher.new()
var service = Service.new()
var isolation := ""
var latest: Dictionary = {}
var host_peer := ""
var host_launch := ""
var passed := 0
var failed := 0
var quitting := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--isolation="):
			isolation = argument.trim_prefix("--isolation=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	bus.poll()
	return false

func _run() -> void:
	if isolation.is_empty():
		quit(64)
		return
	var store := isolation.path_join("store")
	if not check(service.initialize(store, {"minimal_room": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "isolated SQLite opened"):
		await finish()
		return
	var security := Secure.create_local_certificate(store)
	if not check(not security.is_empty(), "isolated TLS identity created"):
		await finish()
		return
	host_launch = Wire.uid()
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	bus.requested.connect(_rpc)
	bus.peer_event.connect(_event)
	check(bus.listen(secret, host_launch) == OK, "authenticated Operator fixture started")
	var project := isolation.path_join("room-project")
	copy_tree("res://sdk", project.path_join("sdk"))
	copy_tree("res://schemas", project.path_join("schemas"))
	DirAccess.make_dir_recursive_absolute(project.path_join("game"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	write(project.path_join("project.godot"), "config_version=5\n[application]\nconfig/name=\"Grant Control Loss Fixture\"\n")
	write(project.path_join("game/manifest.json"), JSON.stringify(manifest))
	write(project.path_join("game/adapter.gd"), FileAccess.get_file_as_string("res://examples/minimal/empty_adapter.gd"))
	write(project.path_join("game/room.gd"), "extends \"res://sdk/roomkit/server/room_runtime.gd\"\nfunc _initialize() -> void:\n\tbuild_identity = JSON.parse_string(FileAccess.get_file_as_string(\"res://game/manifest.json\"))\n\tadapter = preload(\"res://game/adapter.gd\").new()\n\tsuper._initialize()\n")
	var udp := free_udp()
	var settings := {"control_port": free_tcp(), "lobby_port": free_tcp(), "lobby_bind": "127.0.0.1", "advertised_host": "127.0.0.1", "game_bind": "127.0.0.1", "udp_first": udp, "udp_last": udp + 1, "max_rooms": 1, "process_journal": store.path_join("processes.json"), "security": security, "start_timeout_ms": 30000, "heartbeat_timeout_ms": 10000, "stop_timeout_ms": 3000}
	var bootstrap := {"rpc": {"port": bus.port, "token": secret, "launch_id": host_launch}, "settings": settings, "games": {"minimal_room": {"project": project, "manifest": manifest}}, "result_root": store, "result_schemas": {"minimal_room": "res://schemas/summary_result.schema.json"}}
	var bootstrap_path := store.path_join("bootstrap.json")
	write(bootstrap_path, JSON.stringify(bootstrap))
	var launched: Dictionary = launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", isolation.path_join("managed-host.log"), "--script", "res://host/managed_host.gd", "--", "--managed-config=" + bootstrap_path]}, host_launch, ["--launch-id=" + host_launch])
	if not check(launched.ok and await until(func(): return latest.get("host", {}).get("state", "") == "RUNNING", 30000), "real managed host RUNNING"):
		await finish()
		return
	var created: Dictionary = await bus.request("room.create", {"game_id": "minimal_room", "mode": "sandbox", "map": "empty", "capacity": 2}, 30000, host_peer)
	if not check(created.ok and await until(func(): return latest.get("rooms", []).any(func(row): return row.state == "READY"), 35000), "real room READY after bound UDP"):
		await finish()
		return
	var journal: Dictionary = Wire.decode(FileAccess.get_file_as_bytes(settings.process_journal), "res://schemas/process_journal.schema.json", 65536)
	var room_launch: String = journal.entries.keys()[0]
	check(str(service.repository.execute({"op": "grants"}).grants[0].ended_at) == "", "live room grant has no exit time")
	bus.close() # Operator lost: child must stop, while result.end is unreachable.
	check(await until(func(): return launcher.probe(host_launch) == "exited", 16000), "disconnected real host and room finish without result.end acknowledgement")
	journal = Wire.decode(FileAccess.get_file_as_bytes(settings.process_journal), "res://schemas/process_journal.schema.json", 65536)
	check(journal.entries.has(room_launch) and journal.entries[room_launch].has("exit_confirmed_at"), "host exit retains real room first-exit journal")
	var first := int(journal.entries.get(room_launch, {}).get("exit_confirmed_at", -1))
	check(str(service.repository.execute({"op": "grants"}).grants[0].ended_at) == "", "disconnected shutdown never claims database close succeeded")
	check(Operator._inspect_old_rooms(settings.process_journal, {"root": service.repository.root, "database": service.repository.database}).ok, "new Operator recovery verifies old room and closes grant")
	check(int(service.repository.execute({"op": "grants"}).grants[0].ended_at) == first, "cross-run grant close preserves original exit time")
	check(Wire.decode(FileAccess.get_file_as_bytes(settings.process_journal), "res://schemas/process_journal.schema.json", 65536).entries.is_empty(), "journal removed only after successful durable close")
	await finish()

func _rpc(peer: String, id: String, action: String, payload: Dictionary) -> void:
	var reply := {"ok": false, "code": "CONTROL_UNAVAILABLE"}
	if action == "result.grant":
		reply = service.store_grant(payload.grant)
		if reply.ok:
			service.apply_grant(payload.grant, reply)
	elif action == "result.end":
		reply = service.end_launch(payload.launch_id, int(payload.observed_exit_at))
	bus.respond(peer, id, reply)

func _event(peer: String, action: String, payload: Dictionary) -> void:
	if action == "host.status":
		host_peer = peer
		latest = payload

func finish() -> void:
	if quitting:
		return
	quitting = true
	bus.close()
	if host_launch != "" and launcher.probe(host_launch) == "running":
		if not await until(func(): return launcher.probe(host_launch) == "exited", 6000):
			launcher.terminate(host_launch)
			await until(func(): return launcher.probe(host_launch) == "exited", 5000)
	check(host_launch == "" or launcher.probe(host_launch) == "exited", "only owned test host stopped and confirmed")
	print("GRANT_CONTROL_LOSS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func copy_tree(source: String, target: String) -> void:
	DirAccess.make_dir_recursive_absolute(target)
	for name in DirAccess.get_directories_at(source):
		copy_tree(source.path_join(name), target.path_join(name))
	for name in DirAccess.get_files_at(source):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(source.path_join(name)), target.path_join(name))

func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func free_tcp() -> int:
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK: return 0
	var port := probe.get_local_port()
	probe.stop()
	return port

func free_udp() -> int:
	for port in range(39930, 40100, 2):
		var probe := ENetMultiplayerPeer.new()
		probe.set_bind_ip("127.0.0.1")
		if probe.create_server(port, 1) == OK:
			probe.close()
			return port
	return 0

func until(condition: Callable, milliseconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await create_timer(0.05).timeout
	return bool(condition.call())

func check(value: bool, label: String) -> bool:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", "grant_control_loss: ", label)
	return value
