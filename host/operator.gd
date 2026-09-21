extends SceneTree
## Composition root: one private operator owns databases and the managed host process.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Accounts = preload("res://host/core/account_service.gd")
const Assets = preload("res://host/core/asset_service.gd")
const Results = preload("res://host/core/result_service.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const LocalBus = preload("res://sdk/roomkit/shared/local_rpc.gd")
const Http = preload("res://host/admin_http.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var accounts = Accounts.new()
var assets = Assets.new()
var results = Results.new()
var launcher = Launcher.new()
var http = Http.new()
var bus
var root_path := ""
var operator_log_path := ""
var settings: Dictionary = {}
var catalog_config: Dictionary = {}
var games: Dictionary = {}
var worker_count := 0
var ready := false
var starting := false
var host_launch := ""
var host_peer := ""
var host_owned := false
var host_closing := false
var recovery_busy := false
var recovery_next := 0
var requested_stop := false
var restart_requested := false
var storage_maintenance := false
var restart_times: Array = []
var restart_after := 0
var player_tokens: Dictionary = {}
var snapshot: Dictionary = {"host": {"state": "STOPPED", "pid": 0, "uptime": 0, "maintenance": false, "countdown": 0, "error": ""}, "rooms": [], "players": [], "metrics": {}, "games": []}
var audit: Array = []
var next_metrics := 0
var metrics_busy := false
var next_backup := 0
var quitting := false
var args: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	root_path = Paths.absolute(args.get("--data-root", "res://data/framework"))
	operator_log_path = _operator_log_path(args.get("--operator-log-path", ""), root_path.path_join("logs/operator.log"))
	_run.call_deferred()

func _run() -> void:
	var protection: Dictionary = await _work(_protect_runtime)
	if not protection.ok:
		printerr("OPERATOR_FAILED code=PRIVATE_CONFIG_FAILED")
		quit(1)
		return
	var initialized: Dictionary = await _work(accounts.initialize.bind(root_path))
	if not initialized.ok:
		printerr("OPERATOR_FAILED code=", initialized.code)
		quit(1)
		return
	settings = {"lobby_bind": "0.0.0.0", "advertised_host": "127.0.0.1", "lobby_port": 28300, "game_bind": "0.0.0.0", "control_port": 28301, "udp_first": 28400, "udp_last": 28431, "max_rooms": 16, "asset_spaces": {"shooter": "shooter", "turns": "turns"}}
	if FileAccess.file_exists(root_path.path_join("config.json")):
		var saved := Wire.decode(FileAccess.get_file_as_bytes(root_path.path_join("config.json")))
		if not _valid_config(saved):
			printerr("OPERATOR_FAILED code=INVALID_CONFIG")
			quit(1)
			return
		settings = saved
	else:
		_write_json(root_path.path_join("config.json"), settings)
	games = Wire.decode(FileAccess.get_file_as_bytes(Paths.absolute(args.get("--games", "res://artifacts/framework-games.json"))), "", 65536)
	if games.is_empty():
		printerr("OPERATOR_FAILED code=BUILD_FRAMEWORK_REQUIRED")
		quit(1)
		return
	for entry in games.values():
		for key in ["project", "server_executable", "server_pack"]:
			if entry.has(key) and not str(entry[key]).is_absolute_path():
				entry[key] = Paths.absolute("res://" + str(entry[key]))
	_load_catalog()
	if not (await _work(assets.initialize.bind(root_path, catalog_config))).ok:
		quit(1)
		return
	var result_schemas := {"shooter": "res://schemas/shooter_result.schema.json", "turns": "res://schemas/summary_result.schema.json"}
	if not (await _work(results.initialize.bind(root_path, result_schemas, "assets.sqlite"))).ok:
		quit(1)
		return
	results.reward_calculator = _rewards
	var security := {"key": root_path.path_join("server.key"), "certificate": root_path.path_join("server.crt"), "hostname": "localhost"}
	if not FileAccess.file_exists(security.key) or not FileAccess.file_exists(security.certificate):
		security = await _work(preload("res://sdk/roomkit/shared/secure_transport.gd").create_local_certificate.bind(root_path))
	if security.is_empty():
		quit(1)
		return
	_publish_connection()
	_load_audit()
	http.request_received.connect(_http_request)
	if http.start(int(args.get("--panel-port", "28291"))) != OK:
		printerr("OPERATOR_FAILED code=PANEL_PORT_BUSY")
		quit(1)
		return
	_write_json(root_path.path_join("operator.json"), {"pid": OS.get_process_id(), "port": http.port, "data_root": root_path})
	ready = true
	next_backup = Time.get_ticks_msec() + 1800000
	print("OPERATOR_READY port=", http.port)
	# Never claim/kill a process from the previous controller. Marker requires safe recovery.
	if FileAccess.file_exists(root_path.path_join("host-running.json")):
		snapshot.host.state = "FAILED"
		snapshot.host.error = "RECOVERY_REQUIRED"

func _process(_delta: float) -> bool:
	if bus != null:
		bus.poll()
	if not ready:
		return false
	http.poll()
	if host_owned and not starting and launcher.probe(host_launch) == "exited":
		host_closing = true
		_host_exited.call_deferred()
		host_owned = false
	if not host_owned and not starting and not host_closing and not recovery_busy and FileAccess.file_exists(root_path.path_join("host-running.json")) and Time.get_ticks_msec() >= recovery_next:
		recovery_busy = true
		_recover_previous.call_deferred()
	if restart_after > 0 and Time.get_ticks_msec() >= restart_after:
		restart_after = 0
		_start_host.call_deferred()
	if not storage_maintenance and not quitting and not metrics_busy and Time.get_ticks_msec() >= next_metrics and FileAccess.file_exists("res://tools/operator_maintenance.ps1"):
		metrics_busy = true
		next_metrics = Time.get_ticks_msec() + 5000
		_metrics.call_deferred()
	if not storage_maintenance and not quitting and Time.get_ticks_msec() >= next_backup and FileAccess.file_exists("res://tools/operator_maintenance.ps1"):
		next_backup = Time.get_ticks_msec() + 1800000
		_backup.call_deferred(true, "scheduled")
	if FileAccess.file_exists(root_path.path_join("operator-stop.request")) and not quitting:
		quitting = true
		_shutdown.call_deferred()
	return false

func _work(task: Callable) -> Variant:
	if worker_count >= 8:
		return Wire.failure("RATE_LIMITED")
	worker_count += 1
	var thread := Thread.new()
	if thread.start(task) != OK:
		worker_count -= 1
		return Wire.failure("STORAGE_UNAVAILABLE")
	while thread.is_alive():
		await process_frame
	var result: Variant = thread.wait_to_finish()
	worker_count -= 1
	return result

func _start_host() -> Dictionary:
	if starting or host_owned or host_closing or storage_maintenance or quitting:
		return Wire.failure("HOST_ALREADY_RUNNING")
	if FileAccess.file_exists(root_path.path_join("host-running.json")):
		return Wire.failure("RECOVERY_REQUIRED")
	starting = true
	var safe_rooms: Dictionary = await _work(_inspect_old_rooms.bind(root_path.path_join("processes.json")))
	if not safe_rooms.ok:
		starting = false
		return safe_rooms
	var reset: Dictionary = await _work(accounts.reset_player_sessions)
	if not reset.ok:
		starting = false
		return reset
	requested_stop = false
	snapshot.host.state = "STARTING"
	snapshot.host.error = ""
	var recovered: Dictionary = await _work(results.recover)
	if int(recovered.get("pending", 0)) > 0:
		starting = false
		snapshot.host.state = "FAILED"
		snapshot.host.error = "STORAGE_UNAVAILABLE"
		return Wire.failure("STORAGE_UNAVAILABLE")
	if bus != null:
		bus.close()
	bus = LocalBus.new()
	host_launch = Wire.uid()
	host_peer = ""
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	if bus.listen(secret, host_launch) != OK:
		starting = false
		return Wire.failure("CONTROL_UNAVAILABLE")
	bus.requested.connect(_rpc_request)
	bus.peer_event.connect(_host_event)
	var config := settings.duplicate(true)
	config.merge({"async_start": true, "start_timeout_ms": 30000, "heartbeat_timeout_ms": 15000, "stop_timeout_ms": 5000, "max_room_memory_mb": 512, "process_journal": root_path.path_join("processes.json"), "security": {"key": root_path.path_join("server.key"), "certificate": root_path.path_join("server.crt"), "hostname": "localhost"}})
	var bootstrap := {"rpc": {"port": bus.port, "token": secret, "launch_id": host_launch}, "settings": config, "games": games, "result_root": root_path, "result_schemas": results.schemas}
	var path := Paths.absolute("res://run/managed-" + host_launch + ".json")
	if not _write_json(path, bootstrap):
		starting = false
		return Wire.failure("PRIVATE_CONFIG_FAILED")
	DirAccess.make_dir_recursive_absolute(root_path.path_join("logs"))
	var descriptor := {"executable": OS.get_executable_path(), "args": ["--headless", "--path", Paths.absolute("res://"), "--log-file", root_path.path_join("logs/managed-host.log"), "--script", "res://host/managed_host.gd", "--"]}
	if not OS.has_feature("editor"):
		descriptor = {"executable": Paths.absolute("res://ManagedHost.exe"), "args": ["--headless", "--log-file", root_path.path_join("logs/managed-host.log"), "--"]}
	var launched: Dictionary = await _work(_launch.bind(descriptor, host_launch, path))
	if not launched.owned.is_empty():
		launcher.import_owned(launched.owned)
		host_owned = true
		_write_json(root_path.path_join("host-running.json"), launched.owned)
	starting = false
	if not launched.started.ok:
		snapshot.host.state = "FAILED"
		snapshot.host.error = launched.started.code
		bus.close()
		if host_owned:
			await _work(_terminate_owned.bind(launcher.record(host_launch)))
		return launched.started
	var deadline := Time.get_ticks_msec() + 20000
	while host_owned and host_peer == "" and Time.get_ticks_msec() < deadline:
		await process_frame
	if host_peer == "":
		bus.close()
		if host_owned:
			await _work(_terminate_owned.bind(launcher.record(host_launch)))
		snapshot.host.error = "HOST_START_TIMEOUT"
		return Wire.failure("HOST_START_TIMEOUT")
	return {"ok": true, "payload": snapshot.host.duplicate(true)}

func _launch(descriptor: Dictionary, launch_id: String, path: String) -> Dictionary:
	var child = Launcher.new()
	var result: Dictionary = child.launch(descriptor, launch_id, ["--launch-id=" + launch_id, "--managed-config=" + path])
	return {"started": result, "owned": child.record(launch_id)}

func _host_event(peer_id: String, action: String, payload: Dictionary) -> void:
	if action == "host.status":
		host_peer = peer_id
		snapshot.host = payload.host
		snapshot.rooms = payload.rooms
		snapshot.players = payload.players
	elif action == "host.failed":
		snapshot.host.state = "FAILED"
		snapshot.host.error = payload.code

func _host_exited() -> void:
	launcher.forget(host_launch)
	snapshot.host.state = "STOPPED" if requested_stop else "FAILED"
	snapshot.host.pid = 0
	snapshot.players = []
	if bus != null:
		bus.close()
	for token in player_tokens.keys():
		await _work(accounts.execute.bind({"op": "session.logout", "token": token}))
	player_tokens.clear()
	# Rooms self-stop on control loss. Reuse is gated by verified exit and UDP rebinding.
	var end := Time.get_ticks_msec() + 60000
	var clean := false
	while not clean and Time.get_ticks_msec() < end:
		var inspected: Dictionary = await _work(_inspect_old_rooms.bind(root_path.path_join("processes.json")))
		clean = inspected.ok
		if not clean:
			await create_timer(1.0).timeout
	if not clean:
		snapshot.host.error = "RECOVERY_REQUIRED"
		host_closing = false
		return
	DirAccess.remove_absolute(root_path.path_join("host-running.json"))
	host_closing = false
	if restart_requested or not requested_stop:
		var intentional := restart_requested
		restart_requested = false
		var now := Time.get_ticks_msec()
		restart_times = restart_times.filter(func(value): return now - int(value) < 600000)
		if not intentional and restart_times.size() >= 3:
			snapshot.host.error = "RESTART_LIMIT_REACHED"
		else:
			if not intentional:
				restart_times.append(now)
			restart_after = now + 2000

func _host_command(action: String, payload: Dictionary) -> Dictionary:
	if bus == null or host_peer == "" or not host_owned:
		return Wire.failure("HOST_NOT_RUNNING")
	return await bus.request(action, payload, 60000, host_peer)

func _http_request(request_id: String, request: Dictionary) -> void:
	var result: Dictionary = await _admin(request)
	http.respond(request_id, result, 401 if result.get("code", "") in ["AUTH_FAILED", "AUTH_REQUIRED"] else 200)

func _admin(request: Dictionary) -> Dictionary:
	if Validator.validate_file({"action": request.get("action", ""), "payload": request.get("payload", {})}, "res://schemas/admin_request.schema.json") != "":
		return Wire.failure("INVALID_REQUEST")
	var action: String = request.action
	var payload: Dictionary = request.payload
	var token: String = request.get("token", "")
	if storage_maintenance or quitting:
		return Wire.failure("STORAGE_MAINTENANCE")
	if action == "setup.status":
		return _payload(await _work(accounts.execute.bind({"op": "setup.status"})))
	if action in ["setup.create", "admin.login"]:
		var account_request := {"op": "setup.admin" if action == "setup.create" else "account.login", "username": payload.get("username", ""), "password": payload.get("password", ""), "client_ip": "127.0.0.1"}
		if action == "setup.create":
			account_request.display_name = "管理员"
			account_request.erase("client_ip")
		var reply: Dictionary = await _work(accounts.execute.bind(account_request))
		if action == "setup.create" and reply.ok:
			reply = await _work(accounts.execute.bind({"op": "account.login", "username": payload.username, "password": payload.password, "client_ip": "127.0.0.1"}))
		if reply.ok and reply.identity.role != "admin":
			await _work(accounts.execute.bind({"op": "session.logout", "token": reply.token}))
			return Wire.failure("ADMIN_REQUIRED")
		return _payload(reply)
	var auth: Dictionary = await _work(accounts.execute.bind({"op": "session.authenticate", "token": token}))
	if not auth.ok:
		# Admission/storage failure is not evidence that the credential is invalid.
		# Preserve the safe error code so the browser can retry its existing session.
		return Wire.failure(str(auth.get("code", "STORAGE_UNAVAILABLE")))
	if auth.get("identity", {}).get("role", "") != "admin":
		return Wire.failure("ADMIN_REQUIRED")
	if action == "admin.logout":
		return _payload(await _work(accounts.execute.bind({"op": "session.logout", "token": token})))
	if action == "status":
		var public := snapshot.duplicate(true)
		public.games = _public_games()
		return {"ok": true, "payload": public}
	if storage_maintenance:
		return Wire.failure("STORAGE_MAINTENANCE")
	var result: Dictionary = Wire.failure("INVALID_OPTIONS")
	match action:
		"server.start": result = await _start_host()
		"server.stop", "server.restart":
			requested_stop = true
			restart_requested = action == "server.restart" or payload.get("restart", false)
			result = await _host_command("server.stop", {"immediate": payload.get("immediate", false)})
		"room.create", "room.stop", "room.recreate", "room.joinable", "player.kick", "maintenance.set":
			result = await _host_command(action, payload)
		"account.list", "account.get", "account.rename", "account.reset_password", "account.ban", "account.unban", "invite.create", "invite.list", "invite.revoke":
			var account_request := _account_request(action, payload, token)
			result = _payload(await _work(accounts.execute.bind(account_request)))
			if result.ok and action in ["account.reset_password", "account.ban"] and bus != null:
				bus.broadcast("account.revoked", {"user_id": payload.user_id})
		"asset.read": result = await _asset_read(payload.get("user_id", ""), payload.get("game_id", ""))
		"asset.adjust", "asset.grant", "asset.revoke", "asset.select":
			var command := {"kind": action.trim_prefix("asset."), "request_id": payload.get("operation_id", ""), "reason": payload.get("reason", "")}
			if action == "asset.adjust":
				command.credits = payload.get("coins_delta", 0)
				command.experience = payload.get("xp_delta", 0)
			else:
				command.item_id = payload.get("item_id", "")
				if action == "asset.select":
					command.kind = "configure"
					command.slot = payload.get("slot", "")
			result = _payload(await _work(assets.manage.bind(auth.identity, payload.get("user_id", ""), payload.get("game_id", ""), command)))
		"config.get": result = {"ok": true, "payload": {"config": settings.duplicate(true)}}
		"config.set":
			if host_owned or starting or host_closing or restart_after > 0 or FileAccess.file_exists(root_path.path_join("host-running.json")):
				result = Wire.failure("STOP_SERVER_FIRST")
			else:
				var proposed := settings.duplicate(true)
				proposed.merge(payload.get("config", {}), true)
				if _valid_config(proposed):
					storage_maintenance = true
					while worker_count > 0:
						await process_frame
					var recovered: Dictionary = await _work(results.recover)
					if int(recovered.get("pending", 0)) > 0:
						storage_maintenance = false
						return Wire.failure("STORAGE_UNAVAILABLE")
					var previous := settings.duplicate(true)
					settings = proposed
					_load_catalog()
					result = await _work(assets.initialize.bind(root_path, catalog_config))
					if result.ok:
						if not _write_json(root_path.path_join("config.json"), settings):
							result = Wire.failure("STORAGE_UNAVAILABLE")
						_publish_connection()
					if not result.ok:
						settings = previous
						_load_catalog()
						await _work(assets.initialize.bind(root_path, catalog_config))
					storage_maintenance = false
		"backup.list": result = _payload(await _maintenance({"op": "backup.list"}))
		"backup.create": result = await _backup(false, payload.get("reason", "manual"))
		"backup.restore":
			if host_owned or starting or host_closing:
				result = Wire.failure("STOP_SERVER_FIRST")
			else:
				storage_maintenance = true
				while worker_count > 0:
					await process_frame
				result = _payload(await _maintenance({"op": "backup.restore", "backup_id": payload.get("backup_id", ""), "reason": payload.get("reason", "restore")}))
				if result.ok:
					settings = Wire.decode(FileAccess.get_file_as_bytes(root_path.path_join("config.json")))
					_load_catalog()
					await _work(assets.initialize.bind(root_path, catalog_config))
					await _work(results.initialize.bind(root_path, results.schemas, "assets.sqlite"))
					player_tokens.clear()
					_publish_connection()
				storage_maintenance = false
		"logs.list": result = {"ok": true, "payload": {"logs": [{"label": "operator"}, {"label": "host"}]}}
		"logs.read":
			if payload.get("label", "") in ["operator", "host"]:
				var path: String = operator_log_path if payload.label == "operator" else root_path.path_join("logs/managed-host.log")
				result = _read_log(path)
		"audit.list":
			var records: Dictionary = await _work(accounts.execute.bind({"op": "audit.list", "token": token, "limit": 100}))
			var asset_audit: Dictionary = await _work(assets.repository.execute.bind({"op": "asset.audit_all"}))
			result = _merged_audit(audit, records, asset_audit)
	if action not in ["status", "asset.read", "config.get", "backup.list", "logs.list", "logs.read", "audit.list", "account.list", "account.get", "invite.list"]:
		_audit(auth.identity.user_id, action, payload.get("reason", ""), result.get("code", "OK" if result.ok else "FAILED"), str(payload.get("user_id", payload.get("room_id", payload.get("backup_id", "")))))
	return result

func _account_request(action: String, payload: Dictionary, token: String) -> Dictionary:
	var result := {"op": action, "token": token}
	match action:
		"account.list": result.merge({"search": payload.get("query", ""), "offset": payload.get("offset", 0), "limit": payload.get("limit", 50)})
		"invite.create": result.merge({"uses": payload.get("uses", 1), "expires": int(Time.get_unix_time_from_system()) + int(payload.get("expires_hours", 24)) * 3600, "reason": payload.get("reason", "invite")})
		"account.ban": result.merge({"user_id": payload.get("user_id", ""), "until": 0 if int(payload.get("hours", 0)) == 0 else int(Time.get_unix_time_from_system()) + int(payload.hours) * 3600, "reason": payload.get("reason", "")})
		_: result.merge(payload)
	return result

func _rpc_request(peer_id: String, request_id: String, action: String, payload: Dictionary) -> void:
	var result: Dictionary = Wire.failure("INVALID_OPTIONS")
	if storage_maintenance:
		bus.respond(peer_id, request_id, Wire.failure("STORAGE_UNAVAILABLE"))
		return
	match action:
		"account.execute":
			if payload.get("op", "") in ["account.register", "account.login", "session.logout", "account.change_password", "account.rename"]:
				result = await _work(accounts.execute.bind(payload))
				if result.ok and payload.op == "account.login":
					player_tokens[result.token] = result.identity.user_id
				if payload.op == "session.logout":
					player_tokens.erase(payload.get("token", ""))
		"game.catalog": result = {"ok": true, "payload": {"catalog": catalog_config.duplicate(true)}}
		"asset.initial": result = await _asset_read(payload.user_id, payload.game_id)
		"asset.player":
			var authenticated: Dictionary = await _work(accounts.authenticate.bind(payload.get("token", "")))
			if authenticated.ok and authenticated.identity.user_id == payload.identity.user_id:
				var policy = _policy(payload.game_id)
				if payload.action == "asset.read":
					result = await _asset_read(payload.identity.user_id, payload.game_id) if policy != null and policy.authorize(payload.identity, payload.context, {"kind": "read"}) == "" else Wire.failure("ASSET_OPERATION_DENIED")
				else:
					var command := {"kind": str(payload.action).trim_prefix("asset."), "item_id": payload.command.item_id, "request_id": payload.command.operation_id}
					if command.kind == "select":
						command.slot = payload.command.slot
					result = _payload(await _work(assets.perform.bind(authenticated.identity, payload.game_id, command, policy, payload.context)))
		"result.grant":
			var grant: Dictionary = payload.get("grant", {})
			if grant.get("game_id", "") in games and grant.get("build_id", "") == games[grant.game_id].manifest.build_id:
				result = await _work(results.repository.execute.bind({"op": "grant", "grant": grant}))
				if result.ok:
					results.grants[grant.launch_id] = grant
		"result.submit":
			var checked: Dictionary = results.validate_submission(payload)
			result = await _work(results.repository.execute.bind(checked.request)) if checked.ok else checked
	if bus != null:
		bus.respond(peer_id, request_id, result)

func _policy(game_id: String):
	var paths := {"shooter": "res://examples/shooter/asset_policy.gd", "turns": "res://examples/turn_based/asset_policy.gd"}
	return load(paths[game_id]).new() if paths.has(game_id) else null

func _asset_read(user_id: String, game_id: String) -> Dictionary:
	var result: Dictionary = await _work(assets.read.bind(user_id, game_id))
	if not result.ok:
		return result
	return {"ok": true, "payload": {"state": result.state, "space": result.space_id, "level": assets.catalog.level_for(int(result.state.experience)), "catalog": {"items": assets.catalog.items_for(game_id)}, "slots": assets.catalog.game(game_id).get("slots", {})}}

func _rewards(record: Dictionary) -> Array:
	var rows: Array = []
	if record.game_id == "shooter":
		rows = preload("res://examples/shooter/rewards.gd").calculate(record)
	for row in rows:
		row.space_id = assets.catalog.space_for(record.game_id)
	return rows

func _public_games() -> Array:
	var rows: Array = []
	for game_id in games:
		rows.append({"game_id": game_id, "name": "横版射击" if game_id == "shooter" else "回合取石子", "modes": games[game_id].manifest.modes})
	return rows

func _load_catalog() -> void:
	catalog_config = Wire.decode(FileAccess.get_file_as_bytes("res://examples/asset_catalog.example.json"))
	var shared := {"items": {}}
	for space in catalog_config.spaces.values():
		shared.items.merge(space.items, true)
	catalog_config.spaces.shared = shared
	for game_id in settings.asset_spaces:
		catalog_config.games[game_id].space = settings.asset_spaces[game_id]

func _valid_config(value: Dictionary) -> bool:
	var required := ["lobby_bind", "advertised_host", "lobby_port", "game_bind", "control_port", "udp_first", "udp_last", "max_rooms", "asset_spaces"]
	if value.size() != required.size():
		return false
	for key in required:
		if not value.has(key):
			return false
	for key in ["lobby_bind", "advertised_host", "game_bind"]:
		if not value[key] is String or not str(value[key]).is_valid_ip_address() or ":" in str(value[key]):
			return false
	for key in ["lobby_port", "control_port", "udp_first", "udp_last"]:
		if (not value[key] is int and not value[key] is float) or value[key] != int(value[key]) or int(value[key]) < 1024 or int(value[key]) > 65535:
			return false
	if (not value.max_rooms is int and not value.max_rooms is float) or value.max_rooms != int(value.max_rooms):
		return false
	if int(value.udp_first) > int(value.udp_last) or int(value.udp_last) - int(value.udp_first) > 255 or int(value.max_rooms) < 1 or int(value.max_rooms) > 16 or int(value.lobby_port) == int(value.control_port):
		return false
	if not value.asset_spaces is Dictionary or value.asset_spaces.keys().size() != 2:
		return false
	return value.asset_spaces.get("shooter", "") in ["shooter", "shared"] and value.asset_spaces.get("turns", "") in ["turns", "shared"]

func _publish_connection() -> void:
	var directory := Paths.absolute("res://artifacts/client")
	DirAccess.make_dir_recursive_absolute(directory)
	DirAccess.copy_absolute(root_path.path_join("server.crt"), directory.path_join("server.crt"))
	_write_json(directory.path_join("connection.json"), {"url": "wss://" + str(settings.advertised_host) + ":" + str(int(settings.lobby_port)), "ca_certificate": "server.crt", "server_hostname": "localhost", "secure_enet": true, "managed": true})

func _maintenance(request: Dictionary) -> Dictionary:
	var value := request.duplicate(true)
	value.root = root_path
	var path := root_path.path_join("maintenance-" + Wire.uid() + ".json")
	_write_json(path, value)
	var result: Dictionary = await _work(Helper.execute.bind("operator_maintenance.ps1", ["-Request", path], root_path, 30000))
	DirAccess.remove_absolute(path)
	return result

func _metrics() -> void:
	var result: Dictionary = await _maintenance({"op": "metrics"})
	snapshot.metrics = _metric_snapshot(result)
	metrics_busy = false

static func _metric_snapshot(result: Dictionary) -> Dictionary:
	var available: bool = result.get("ok", false) and result.get("metrics") is Dictionary
	var value: Dictionary = result.metrics.duplicate(true) if available else {}
	value.available = available
	value.sampled_at = int(Time.get_unix_time_from_system())
	if not available:
		value.error = str(result.get("code", "METRICS_UNAVAILABLE"))
	return value

static func _merged_audit(local_rows: Array, account_result: Dictionary, asset_result: Dictionary) -> Dictionary:
	if not account_result.get("ok", false) or not asset_result.get("ok", false):
		return Wire.failure("STORAGE_UNAVAILABLE")
	var rows: Array = local_rows.slice(maxi(0, local_rows.size() - 100))
	for entry in account_result.get("rows", []):
		rows.append({"created_at": entry.created_at, "actor_id": entry.actor_id, "action": entry.action, "user_id": entry.target_id, "reason": entry.reason, "code": entry.result, "before": entry.before_body, "after": entry.after_body})
	for entry in asset_result.get("rows", []):
		var command := Wire.decode(str(entry.command).to_utf8_buffer())
		rows.append({"created_at": Time.get_unix_time_from_datetime_string(str(entry.created_at).replace(" ", "T")), "actor_id": entry.actor_id, "action": "asset." + str(command.get("kind", "transaction")), "user_id": entry.user_id, "reason": command.get("reason", ""), "code": "OK", "before": Wire.decode(str(entry.previous_body).to_utf8_buffer(), "", 65536), "after": Wire.decode(str(entry.body).to_utf8_buffer(), "", 65536)})
	rows.sort_custom(func(a, b): return int(a.get("created_at", a.get("time", 0))) < int(b.get("created_at", b.get("time", 0))))
	return {"ok": true, "payload": {"entries": rows.slice(maxi(0, rows.size() - 100))}}

func _backup(automatic: bool, reason: String) -> Dictionary:
	if storage_maintenance:
		return Wire.failure("STORAGE_MAINTENANCE")
	storage_maintenance = true
	while worker_count > 0:
		await process_frame
	var result := _payload(await _maintenance({"op": "backup.create", "automatic": automatic, "reason": reason}))
	_audit("system" if automatic else "operator", "backup.automatic" if automatic else "backup.snapshot", reason, "OK" if result.ok else result.get("code", "STORAGE_UNAVAILABLE"))
	storage_maintenance = false
	return result

func _audit(actor: String, action: String, reason: String, code: String, target: String = "") -> void:
	var row := {"time": int(Time.get_unix_time_from_system()), "actor_id": actor, "action": action, "user_id": target, "reason": reason.left(256), "code": code}
	audit.append(row)
	var path := root_path.path_join("operator-audit.jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		if file.get_length() > 2097152:
			file.close()
			DirAccess.rename_absolute(path, path + ".previous")
			file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(row))
		file.close()
	if audit.size() > 1000:
		audit.pop_front()

func _load_audit() -> void:
	var path := root_path.path_join("operator-audit.jsonl")
	if FileAccess.file_exists(path):
		for line in _tail(path).split("\n", false):
			var value := Wire.decode(line.to_utf8_buffer())
			if not value.is_empty():
				audit.append(value)
		if audit.size() > 1000:
			audit = audit.slice(audit.size() - 1000)

func _shutdown() -> void:
	if host_owned:
		requested_stop = true
		restart_requested = false
		await _host_command("server.stop", {"immediate": true})
		while host_owned or host_closing:
			await process_frame
	while worker_count > 0:
		await process_frame
	http.close()
	DirAccess.remove_absolute(root_path.path_join("operator-stop.request"))
	DirAccess.remove_absolute(root_path.path_join("operator.json"))
	quit(0)

static func _protect_runtime() -> Dictionary:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Paths.absolute("res://tools/protect_runtime.ps1"), "-ProjectRoot", Paths.absolute("res://")], output, false, false)
	return {"ok": code == 0}

static func _terminate_owned(owned: Dictionary) -> Dictionary:
	if not owned.get("verified", false):
		return Wire.failure("PROCESS_IDENTITY_UNVERIFIED")
	return Launcher.new()._inspect("terminate", owned)

static func _inspect_old_rooms(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true}
	var journal := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/process_journal.schema.json", 65536)
	if journal.is_empty():
		return Wire.failure("RECOVERY_REQUIRED")
	for entry in journal.entries.values():
		if entry.owned.is_empty() or not entry.owned.get("verified", false):
			return Wire.failure("RECOVERY_REQUIRED")
		if Launcher.new()._inspect("inspect", entry.owned).get("state", "unknown") != "exited":
			return Wire.failure("RECOVERY_REQUIRED")
		var probe := ENetMultiplayerPeer.new()
		probe.set_bind_ip("0.0.0.0")
		if probe.create_server(int(entry.port), 1) != OK:
			return Wire.failure("RECOVERY_REQUIRED")
		probe.close()
	# This controller starts no replacement until every old entry was verified above.
	# Persist that completed recovery before a replacement can publish RUNNING.
	return {"ok": true} if _write_json(path, {"version": 1, "entries": {}}) else Wire.failure("RECOVERY_REQUIRED")

func _recover_previous() -> void:
	var path := root_path.path_join("host-running.json")
	var owned := Wire.decode(FileAccess.get_file_as_bytes(path), "", 65536)
	var inspected: Dictionary = {}
	if owned.get("verified", false) and owned.has_all(["pid", "parent_pid", "launch_id", "created_filetime", "executable"]):
		inspected = await _work(Launcher.new()._inspect.bind("inspect", owned))
	if inspected.get("state", "unknown") == "exited":
		var rooms: Dictionary = await _work(_inspect_old_rooms.bind(root_path.path_join("processes.json")))
		if rooms.ok:
			DirAccess.remove_absolute(path)
			snapshot.host.state = "STOPPED"
			snapshot.host.error = ""
	recovery_next = Time.get_ticks_msec() + 10000
	recovery_busy = false

static func _operator_log_path(startup_path: String, fallback: String) -> String:
	# Godot consumes --log-file before exposing get_cmdline_args. Our trusted
	# launchers repeat that same path once as --operator-log-path. Browser
	# requests can only choose operator/host labels, never a filesystem path.
	if startup_path.is_empty():
		return fallback
	if not startup_path.is_absolute_path() or startup_path.begins_with("res://") or startup_path.begins_with("user://") or startup_path.contains("\n") or startup_path.contains("\r"):
		return ""
	return startup_path.simplify_path()

static func _read_log(path: String) -> Dictionary:
	if path.is_empty():
		return Wire.failure("LOG_READ_FAILED")
	if not FileAccess.file_exists(path):
		return Wire.failure("LOG_NOT_FOUND")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Wire.failure("LOG_READ_FAILED")
	var length := file.get_length()
	var count := mini(length, 60000)
	file.seek(maxi(0, length - count))
	var data := file.get_buffer(count)
	var failed := data.size() != count or file.get_error() not in [OK, ERR_FILE_EOF]
	file.close()
	if failed:
		return Wire.failure("LOG_READ_FAILED")
	return {"ok": true, "payload": {"text": data.get_string_from_utf8()}}

static func _tail(path: String) -> String:
	# Internal audit bootstrap tolerates an absent optional journal. HTTP callers
	# use _read_log directly so missing/unreadable and empty are distinguishable.
	var result := _read_log(path)
	return result.payload.text if result.ok else ""

static func _write_json(path: String, value: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func _payload(result: Dictionary) -> Dictionary:
	return {"ok": true, "payload": result} if result.ok else result
