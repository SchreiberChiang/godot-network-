extends SceneTree
## A runnable account/asset integration client. Replace this shell with your UI.
const AccountClient = preload("res://sdk/roomkit/client/account_client.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const World = preload("res://game/world.gd")
var client
var world
var settings: Dictionary = {}
var report: Dictionary = {"phase": "STARTING", "ok": false, "user_id": "", "registration": {"attempted": false, "ok": false, "code": ""}, "assets": {}, "world": {}, "results": []}
var completed: Dictionary = {}
var command_busy := false
var active := false
var closing := false
var started := 0
var last_report := 0

func _initialize() -> void:
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _run() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--settings="):
			path = argument.trim_prefix("--settings=")
	if path.is_empty() or not FileAccess.file_exists(path):
		await _finish("SETTINGS_REQUIRED")
		return
	settings = Wire.decode(FileAccess.get_file_as_bytes(path), "", 65536)
	if not _valid_settings():
		await _finish("INVALID_SETTINGS")
		return
	var connection: Dictionary = settings.get("connection", {})
	if settings.has("connection_config"):
		var connection_path: String = settings.connection_config
		if not FileAccess.file_exists(connection_path):
			await _finish("INVALID_CONNECTION")
			return
		connection = Wire.decode(FileAccess.get_file_as_bytes(connection_path), "", 65536)
		if not _valid_connection(connection):
			await _finish("INVALID_CONNECTION")
			return
		var certificate: String = connection.get("ca_certificate", "")
		if not certificate.is_empty() and not certificate.is_absolute_path():
			connection.ca_certificate = connection_path.get_base_dir().path_join(certificate)
	if not _valid_connection(connection):
		await _finish("INVALID_CONNECTION")
		return
	var manifest := Wire.decode(FileAccess.get_file_as_bytes("res://game_manifest.json"), "res://schemas/game_manifest.schema.json", 65536)
	var config := manifest.duplicate(true)
	for key in ["url", "ca_certificate", "server_hostname"]:
		if connection.has(key):
			config[key] = connection[key]
	config.managed = true
	config.secure_enet = true
	client = AccountClient.new()
	root.add_child(client)
	world = World.new()
	world.name = "ManagedTemplateWorld"
	root.add_child(world)
	if manifest.is_empty() or not client.configure(config):
		await _finish("INVALID_CONNECTION")
		return
	report.game_id = manifest.game_id
	if settings.get("register", not str(settings.get("invite_code", "")).is_empty()):
		var registered: Dictionary = await client.register_account(settings.username, settings.password, settings.get("display_name", settings.username), settings.get("invite_code", ""))
		# Keep only the registration outcome, never the response payload or credentials.
		report.registration = {"attempted": true, "ok": bool(registered.get("ok", false)), "code": str(registered.get("code", ""))}
		if not registered.ok:
			await _finish(registered.get("code", "REGISTER_FAILED"))
			return
	var logged: Dictionary = await _login()
	if not logged.ok:
		await _finish(logged.get("code", "LOGIN_FAILED"))
		return
	if not str(settings.get("room_id", "")).is_empty():
		var joined: Dictionary = await _join(settings.room_id)
		if not joined.ok:
			await _finish(joined.get("code", "JOIN_FAILED"))
			return
	active = true
	_write_report()
	print("MANAGED_TEMPLATE_CLIENT_READY game=", report.game_id)
	if str(settings.get("control_directory", "")).is_empty():
		await _finish()

func _valid_settings() -> bool:
	for key in ["username", "password"]:
		if not settings.get(key) is String or str(settings[key]).is_empty():
			return false
	for key in ["display_name", "invite_code", "report_path", "control_directory", "room_id", "connection_config"]:
		if settings.has(key) and not settings[key] is String:
			return false
	if settings.has("connection") and not settings.connection is Dictionary:
		return false
	if settings.has("register") and not settings.register is bool:
		return false
	if settings.has("timeout_ms") and (not settings.timeout_ms is float and not settings.timeout_ms is int):
		return false
	return settings.has("connection") or settings.has("connection_config")

func _valid_connection(connection: Dictionary) -> bool:
	for key in ["url", "ca_certificate"]:
		if not connection.get(key) is String or str(connection[key]).is_empty():
			return false
	if connection.has("server_hostname") and not connection.server_hostname is String:
		return false
	return str(connection.url).begins_with("wss://")

func _process(_delta: float) -> bool:
	if not active or closing:
		return false
	if Time.get_ticks_msec() - started > clampi(int(settings.get("timeout_ms", 300000)), 1000, 900000):
		_finish.call_deferred("CLIENT_TIMEOUT")
		return false
	if not command_busy:
		var directory: String = settings.get("control_directory", "")
		var files := DirAccess.get_files_at(directory)
		files.sort()
		for name in files:
			if not name.ends_with(".command.json") or completed.has(name):
				continue
			var command := Wire.decode(FileAccess.get_file_as_bytes(directory.path_join(name)), "", 16384)
			if command.is_empty():
				continue
			completed[name] = true
			command_busy = true
			_command.call_deferred(command)
			break
	if Time.get_ticks_msec() - last_report >= 100:
		_write_report()
	return false

func _login() -> Dictionary:
	var result: Dictionary = await client.login(settings.username, settings.password)
	if result.ok:
		report.user_id = result.payload.identity.user_id
		report.phase = "LOBBY"
		report.ok = true
		var read: Dictionary = await client.read_assets()
		if not read.ok:
			return read
		_accept_assets(read)
	return result

func _join(room_id: String) -> Dictionary:
	world.latest = {}
	var result: Dictionary = await client.join_room(room_id)
	if not result.ok:
		return result
	var deadline := Time.get_ticks_msec() + 15000
	while _own_player().is_empty() and client.state == "IN_ROOM" and Time.get_ticks_msec() < deadline:
		await process_frame
	if _own_player().is_empty():
		return Wire.failure("INITIAL_STATE_TIMEOUT")
	report.phase = "IN_ROOM"
	report.room_id = room_id
	return result

func _own_player() -> Dictionary:
	for player in world.latest.get("players", []):
		if player.user_id == report.user_id:
			return player
	return {}

func _command(command: Dictionary) -> void:
	var id: String = str(command.get("id", ""))
	var action: String = str(command.get("action", ""))
	var response := Wire.failure("INVALID_COMMAND")
	if id.is_empty() or completed.has("id:" + id):
		command_busy = false
		return
	completed["id:" + id] = true
	match action:
		"read": response = await client.read_assets()
		"purchase": response = await client.purchase(str(command.get("item_id", "")), str(command.get("operation_id", id)))
		"select": response = await client.select_item(str(command.get("slot", "")), str(command.get("item_id", "")), str(command.get("operation_id", id)))
		"join": response = await _join(str(command.get("room_id", "")))
		"leave":
			# The public SDK returns void; use its resulting state as the local outcome.
			await client.leave_room()
			response = {"ok": true} if client.state == "LOBBY" else Wire.failure("NOT_IN_LOBBY")
			if response.ok:
				report.phase = "LOBBY"
				world.latest = {}
		"logout":
			response = await client.logout()
			if response.ok:
				report.phase = "LOGGED_OUT"
				world.latest = {}
		"login": response = await _login()
		"close": response = {"ok": true}
	_accept_assets(response)
	var safe := {"id": id, "action": action, "ok": bool(response.get("ok", false)), "code": str(response.get("code", ""))}
	if response.get("payload", {}).has("state"):
		safe.state = response.payload.state.duplicate(true)
	report.results.append(safe)
	if report.results.size() > 200:
		report.results.pop_front()
	command_busy = false
	_write_report()
	if action == "close":
		await _finish()

func _accept_assets(response: Dictionary) -> void:
	if response.get("ok", false) and response.get("payload", {}).get("state") is Dictionary:
		report.assets = response.payload.state.duplicate(true)

func _write_report() -> void:
	last_report = Time.get_ticks_msec()
	if world != null:
		report.world = world.latest.duplicate(true)
	var output: Variant = settings.get("report_path", "")
	if not output is String or str(output).is_empty():
		return
	var path: String = output
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()

func _finish(code: String = "") -> void:
	if closing:
		return
	closing = true
	if client != null:
		if client.state in ["LOBBY", "IN_ROOM"]:
			var logged_out: Dictionary = await client.logout()
			if not logged_out.ok and code.is_empty():
				code = str(logged_out.get("code", "LOGOUT_FAILED"))
		client.close()
	report.phase = "CLOSED" if code.is_empty() else "FAILED"
	report.ok = code.is_empty()
	report.code = code
	_write_report()
	print("MANAGED_TEMPLATE_CLIENT_RESULT ok=", report.ok, " code=", code)
	quit(0 if code.is_empty() else 1)
