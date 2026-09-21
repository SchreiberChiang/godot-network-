extends "res://examples/framework/client.gd"
## One real client per process. The parent harness owns account/room/process setup.
var test_settings: Dictionary = {}
var driver_report: Dictionary = {"phase": "STARTING", "ok": false, "results": []}
var command_busy := false
var driver_ready := false
var last_report_at := 0
var held_input := {"move": 0.0, "jump": false, "aim_x": 1.0, "aim_y": 0.0, "fire": false}
var input_until := 0
var driver_input_at := 0
var processed_commands: Dictionary = {}
var live_command := ""

func _run() -> void:
	var private_path: String = args.get("--test-config", "")
	if not FileAccess.file_exists(private_path):
		printerr("FRAMEWORK_CLIENT_FAILED code=TEST_CONFIG_MISSING")
		quit(2)
		return
	test_settings = Wire.decode(FileAccess.get_file_as_bytes(private_path), "", 65536)
	# The harness provisions this one-use private file. Credentials stay in memory only.
	DirAccess.remove_absolute(private_path)
	var connection: Variant = test_settings.get("connection", {})
	if not connection is Dictionary or not test_settings.get("control_directory", "") is String or not test_settings.get("report_path", "") is String:
		printerr("FRAMEWORK_CLIENT_FAILED code=TEST_CONFIG_INVALID")
		quit(2)
		return
	game_id = str(test_settings.get("game_id", connection.get("game_id", "shooter")))
	var directory: String = test_settings.control_directory
	DirAccess.make_dir_recursive_absolute(directory)
	var public_path := directory.path_join("connection-public.json")
	var public_file := FileAccess.open(public_path, FileAccess.WRITE)
	if public_file == null:
		printerr("FRAMEWORK_CLIENT_FAILED code=TEST_CONFIG_UNWRITABLE")
		quit(2)
		return
	var public_connection := {}
	for key in ["url", "ca_certificate", "server_hostname"]:
		if connection.has(key):
			public_connection[key] = connection[key]
	public_file.store_string(JSON.stringify(public_connection))
	public_file.close()
	args["--connection-config"] = public_path
	await super._run()
	var supplied_manifest: Variant = test_settings.get("manifest", connection.get("manifest", {}))
	if supplied_manifest is Dictionary and not supplied_manifest.is_empty() and client != null:
		manifest = supplied_manifest.duplicate(true)
		var settings: Dictionary = client.config.duplicate(true)
		settings.merge(manifest, true)
		for key in ["url", "ca_certificate", "server_hostname"]:
			if connection.has(key):
				settings[key] = connection[key]
		settings.managed = true
		settings.secure_enet = true
		configuration_ready = manifest.get("game_id", "") == game_id and client.configure(settings)
	if not configuration_ready:
		driver_report.phase = "FAILED"
		driver_report.code = "CONFIGURATION_FAILED"
		_write_driver_report()
		quit(2)
		return
	if test_settings.get("register", str(test_settings.get("invite_code", "")) != ""):
		var registered: Dictionary = await client.register_account(test_settings.username, test_settings.password, test_settings.get("display_name", test_settings.username), test_settings.get("invite_code", ""))
		driver_report.registration = _safe_result(registered)
		if not registered.ok:
			driver_report.phase = "FAILED"
			driver_report.code = registered.get("code", "REGISTER_FAILED")
			_write_driver_report()
			quit(1)
			return
	await login(test_settings.username, test_settings.password)
	if not authenticated:
		driver_report.phase = "FAILED"
		driver_report.code = account_error if account_error != "" else "LOGIN_FAILED"
		_write_driver_report()
		quit(1)
		return
	driver_report.ok = true
	driver_ready = true
	if str(test_settings.get("room_id", "")) != "":
		selected_room = test_settings.room_id
		await join_selected()
		driver_report.initial_join_ok = client.state == "IN_ROOM"
	_write_driver_report()
	print("FRAMEWORK_CLIENT_READY game=", game_id)

func _process(delta: float) -> bool:
	if not driver_ready or closing:
		return false
	var now := Time.get_ticks_msec()
	if authenticated and not command_busy and client.socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		client.close()
		_reset_session()
	_sync_life_view()
	if client.state == "IN_ROOM" and world.has_method("send_input") and now - driver_input_at >= 34:
		driver_input_at = now
		var active := now < input_until
		var aim := Vector2(float(held_input.aim_x), float(held_input.aim_y))
		world.send_input(float(held_input.move) if active else 0.0, held_input.jump if active else false, aim, held_input.fire if active else false)
	if not command_busy:
		var names := DirAccess.get_files_at(test_settings.control_directory)
		names.sort()
		for name in names:
			if not name.ends_with(".command.json"):
				continue
			var path: String = str(test_settings.control_directory).path_join(name)
			var command := Wire.decode(FileAccess.get_file_as_bytes(path), "", 16384)
			if command.is_empty():
				continue
			command_busy = true
			_run_command(command, path)
			break
	if now - last_report_at > 200:
		last_report_at = now
		_write_driver_report()
	if now - client_started > int(test_settings.get("timeout_ms", 900000)):
		driver_report.ok = false
		driver_report.code = "DRIVER_TIMEOUT"
		_write_driver_report()
		_close()
	return false

func _run_command(command: Dictionary, path: String) -> void:
	var id := str(command.get("id", path.get_file()))
	if processed_commands.has(id):
		DirAccess.remove_absolute(path)
		command_busy = false
		return
	live_command = id
	var result := {"ok": true, "code": ""}
	var response: Dictionary = {}
	match str(command.get("action", "")):
		"read":
			response = await client.read_assets()
			if response.ok:
				_accept_assets(response.get("payload", {}))
			result = _safe_result(response)
		"purchase":
			response = await client.purchase(command.item_id, command.get("operation_id", id))
			if response.ok:
				_accept_assets(response.get("payload", {}))
			result = _safe_result(response)
		"select":
			response = await client.select_item(command.slot, command.item_id, command.get("operation_id", id))
			if response.ok:
				_accept_assets(response.get("payload", {}))
			result = _safe_result(response)
		"input":
			for key in ["move", "jump", "aim_x", "aim_y", "fire"]:
				if command.has(key):
					held_input[key] = command[key]
			input_until = Time.get_ticks_msec() + clampi(int(command.get("duration_ms", 1000)), 0, 300000)
		"respawn":
			if world.has_method("send_respawn"):
				world.send_respawn()
			else:
				result = {"ok": false, "code": "UNSUPPORTED_GAME"}
		"choose":
			if world.has_method("choose"):
				world.choose(int(command.get("take", 1)))
			else:
				result = {"ok": false, "code": "UNSUPPORTED_GAME"}
		"join":
			selected_room = command.room_id
			await join_selected()
			result = {"ok": client.state == "IN_ROOM", "code": client.last_error}
		"join_sdk":
			# The SDK returns reservation failures directly; last_error only tracks
			# the subsequent ENet handshake. Preserve the actual public API reply.
			if client.state == "LOBBY":
				world.latest.clear()
			response = await client.join_room(str(command.room_id))
			result = _safe_result(response)
		"leave":
			await leave_room()
			result = {"ok": client.state == "LOBBY", "code": client.last_error}
		"rooms":
			response = await client.list_rooms()
			result = _safe_result(response)
		"notice":
			response = await client.notice()
			result = _safe_result(response)
		"login":
			await login(test_settings.username, test_settings.password)
			result = {"ok": authenticated, "code": "" if authenticated else account_error}
		"logout":
			await logout()
			result = {"ok": not authenticated, "code": ""}
		"inventory":
			await toggle_inventory()
			result = {"ok": inventory_open, "code": "" if inventory_open else "UI_INVENTORY_DENIED"}
		"capture":
			if DisplayServer.get_name() == "headless":
				result = {"ok": false, "code": "NO_RENDERER"}
			else:
				await RenderingServer.frame_post_draw
				var image_path: String = str(test_settings.control_directory).path_join(str(command.get("name", "client.png")).get_file())
				result = {"ok": root.get_texture().get_image().save_png(image_path) == OK, "code": "", "screenshot": image_path}
		"close":
			result = {"ok": true, "code": "CLOSED"}
		_:
			result = {"ok": false, "code": "UNKNOWN_DRIVER_ACTION"}
	result.id = id
	result.action = str(command.get("action", ""))
	driver_report.results.append(result)
	if driver_report.results.size() > 128:
		driver_report.results.pop_front()
	processed_commands[id] = true
	live_command = ""
	_write_driver_report()
	DirAccess.remove_absolute(path)
	command_busy = false
	if command.get("action", "") == "close":
		driver_report.phase = "DONE"
		_write_driver_report()
		await _close()

func _safe_result(response: Dictionary) -> Dictionary:
	var safe := {"ok": bool(response.get("ok", false)), "code": str(response.get("code", ""))}
	var payload: Dictionary = response.get("payload", {})
	for key in ["state", "rooms", "room", "message", "maintenance"]:
		if payload.has(key):
			safe[key] = payload[key]
	return safe

func _write_driver_report() -> void:
	if not test_settings.has("report_path"):
		return
	if driver_report.phase not in ["FAILED", "DONE"]:
		driver_report.phase = str(client.state) if client != null else "STARTING"
	driver_report.command = live_command
	driver_report.user_id = client.identity.get("user_id", "") if client != null else ""
	driver_report.assets = assets.duplicate(true)
	driver_report.inventory_open = inventory_open
	driver_report.world = world.latest.duplicate(true) if world != null else {}
	var path: String = test_settings.report_path
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(driver_report))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
