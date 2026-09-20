extends Node
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
var manager = Manager.new()
var room_id := ""
var started := 0
var stop_requested := false

func _ready() -> void:
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	settings.godot_executable = OS.get_executable_path()
	var result: Dictionary = manager.initialize(settings)
	if result.ok:
		result = Development.register_game(manager)
	if result.ok:
		result = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 8})
	if not result.ok:
		printerr("DEMO_FAILED code=", result.code)
		get_tree().quit(1)
		return
	room_id = result.room_id
	started = Time.get_ticks_msec()
	print("ROOMKIT_DEMO_STARTED control=127.0.0.1:", manager.control_port)

func _process(_delta: float) -> void:
	if room_id.is_empty():
		return
	manager.poll()
	var row: Dictionary = manager.snapshot(room_id)
	if not stop_requested and (row.heartbeats >= 4 or Time.get_ticks_msec() - started > 20000):
		stop_requested = true
		manager.stop_all()
	if row.cleaned:
		manager.close()
		var passed: bool = row.state == "STOPPED" and row.exit_confirmed and row.heartbeats >= 4
		print("DEMO_PASS" if passed else "DEMO_FAIL", " heartbeats=", row.heartbeats, " leases=", manager.ports.leases.size())
		get_tree().quit(0 if passed else 1)
	elif Time.get_ticks_msec() - started > 35000:
		printerr("DEMO_FAIL cleanup quarantined; inspect run records")
		get_tree().quit(1)
