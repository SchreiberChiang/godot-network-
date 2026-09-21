extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var manager = Manager.new()
var config: Dictionary
var initialized := false
var created: Dictionary
var initial_orphans := 0
var started := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings="):
			config = Wire.decode(FileAccess.get_file_as_bytes(arg.trim_prefix("--settings=")))
	_run.call_deferred()

func _run() -> void:
	config.godot_executable = OS.get_executable_path()
	config.async_start = true
	if not manager.initialize(config).ok or not Development.register_multiplayer(manager).ok:
		quit(2)
		return
	initialized = true
	initial_orphans = manager.recovery_guard.orphans.size()
	created = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
	started = Time.get_ticks_msec()
	if not created.ok:
		quit(2)
		return

func _process(_delta: float) -> bool:
	if not initialized:
		return false
	manager.poll()
	var row: Dictionary = manager.snapshot(created.room_id)
	if row.state == "READY":
		var report := {"phase": "READY", "port": row.port, "pid": row.pid, "launch_id": row.launch_id, "initial_orphans": initial_orphans, "orphans": manager.recovery_guard.orphans.size(), "heartbeats": row.heartbeats}
		var file := FileAccess.open(config.report + ".tmp", FileAccess.WRITE)
		file.store_string(JSON.stringify(report))
		file.close()
		DirAccess.rename_absolute(config.report + ".tmp", config.report)
	if FileAccess.file_exists(config.stop_file) or Time.get_ticks_msec() - started > 45000:
		manager.stop_all()
		if manager.active_count() == 0:
			manager.close()
			quit(0)
	return false
