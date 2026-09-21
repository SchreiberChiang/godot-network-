extends "res://tests/run_secure.gd"

func _run() -> void:
	report_name = "template"
	work = ProjectSettings.globalize_path("res://logs/template-" + Wire.uid())
	DirAccess.make_dir_recursive_absolute(work)
	var entry := Wire.decode(FileAccess.get_file_as_bytes("res://artifacts/template.json"))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.async_start = true
	check(manager.initialize(config).ok, "template host initialized")
	active = true
	check(lobby.start(manager) == OK, "template development lobby started")
	var descriptor := {"executable": OS.get_executable_path(), "args": ["--headless", "--path", entry.project, "--script", "res://room.gd", "--"]}
	check(manager.registry.register_game(entry.manifest, {entry.manifest.server_artifact: descriptor}).ok, "new game registered with only manifest and artifact descriptor")
	var created: Dictionary = manager.create_room(entry.manifest.game_id, {"mode": "sandbox", "map": "empty", "capacity": 2})
	check(created.ok, "independent template room accepted")
	room = created.room_id
	check(await until(func(): return manager.snapshot(room).state == "READY", 20000), "template SDK binds real ENet port and registers READY")
	var settings := {"url": "ws://127.0.0.1:" + str(lobby.port), "room_id": room, "output": work.path_join("client.json")}
	var path := work.path_join("settings.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(settings))
	file.close()
	var launch := Wire.uid()
	descriptor.args = ["--headless", "--path", entry.project, "--log-file", work.path_join("client.log"), "--script", "res://client.gd", "--"]
	check(manager.launcher.launch(descriptor, launch, ["--launch-id=" + launch, "--settings=" + path]).ok, "template's own client process started")
	var child := {"launch_id": launch, "output": settings.output}
	children.append(child)
	check(await until(func(): return read_report(child).get("ok", false), 15000), "template client and its copied SDK enter and leave actual room")
	await finish()
	print("TEMPLATE_RESULT passed=", passed, " failed=", failed)
