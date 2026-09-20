extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Service = preload("res://tests/fakes/lost_result_ack.gd")
var manager = Manager.new()
var service = Service.new()
var initialized := false
var args: Dictionary = {}
var room_id := ""
var reported := false
var started := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	_run.call_deferred()

func _run() -> void:
	started = Time.get_ticks_msec()
	var result: Dictionary = service.initialize(args["--store"], {"minimal_room": "res://schemas/summary_result.schema.json"})
	if not result.ok:
		quit(2)
		return
	if args.get("--mode", "") == "recover":
		var recovered: Dictionary = service.recover()
		write_report({"recovered": recovered, "stored": service.repository.execute({"op": "inspect"})})
		quit(0)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 8000
	if not manager.initialize(config).ok:
		quit(2)
		return
	manager.result_service = service
	service.manager = manager
	service.block_before_commit = true
	initialized = true
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	result = manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", args["--worker-log"], "--script", "res://tests/fixtures/result_room.gd", "--"]}})
	if not result.ok:
		quit(2)
		return
	result = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
	if not result.ok:
		quit(2)
		return
	room_id = result.room_id

func _process(_delta: float) -> bool:
	if not initialized:
		return false
	manager.poll()
	if not reported and service.received > 0:
		reported = true
		var row: Dictionary = manager.snapshot(room_id)
		write_report({"phase": "PENDING", "room_id": room_id, "launch_id": row.launch_id, "port": row.port, "pid": row.pid})
	if Time.get_ticks_msec() - started > 60000:
		manager.stop_all()
		if manager.active_count() == 0:
			manager.close()
			quit(1)
	return false

func write_report(data: Dictionary) -> void:
	var path: String = args["--report"]
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
