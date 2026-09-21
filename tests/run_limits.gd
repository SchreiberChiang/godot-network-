extends "res://tests/run_secure.gd"

func _run() -> void:
	report_name = "limits"
	work = ProjectSettings.globalize_path("res://data/limits-" + Wire.uid())
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.async_start = true
	config.max_room_memory_mb = 1
	config.max_room_history = 1
	check(manager.initialize(config).ok, "resource-limited host initialized")
	active = true
	lobby.manager = manager
	check(Development.register_multiplayer(manager).ok, "resource fixture registered")
	var created: Dictionary = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
	check(created.ok, "real room accepted with measured memory limit")
	room = created.room_id
	check(await until(func(): return manager.snapshot(room).get("cleaned", false), 22000), "over-budget real process exits and reclaims its port")
	check(manager.snapshot(room).get("code", "") == "ROOM_MEMORY_LIMIT", "verified working set triggers explicit failure reason")
	check(manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2}).get("code", "") == "HOST_CAPACITY_EXCEEDED", "retained room history is bounded")
	await finish()
	print("LIMITS_RESULT passed=", passed, " failed=", failed)
