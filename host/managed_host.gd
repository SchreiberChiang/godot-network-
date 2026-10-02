extends SceneTree
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Bus = preload("res://sdk/roomkit/shared/local_rpc.gd")
const Manager = preload("res://host/core/room_manager.gd")
const Lobby = preload("res://host/managed_lobby.gd")
var bus = Bus.new()
var manager = Manager.new()
var lobby = Lobby.new()
var bootstrap: Dictionary = {}
var initialized := false
var stopping := false
var deadline := 0
var last_status := 0
var started := 0
var bus_was_ready := false

func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var path: String = args.get("--managed-config", "")
	bootstrap = Wire.decode(FileAccess.get_file_as_bytes(path), "", 65536)
	if bootstrap.is_empty() or bootstrap.rpc.launch_id != args.get("--launch-id", ""):
		quit(2)
		return
	DirAccess.remove_absolute(path)
	bus.requested.connect(_request)
	bus.event_received.connect(_event)
	bus.connect_to(int(bootstrap.rpc.port), bootstrap.rpc.token, bootstrap.rpc.launch_id)
	started = Time.get_ticks_msec()
	_start.call_deferred()

func _start() -> void:
	while not bus.ready() and Time.get_ticks_msec() - started < 10000:
		await process_frame
	if not bus.ready():
		quit(2)
		return
	bus_was_ready = true
	var settings: Dictionary = bootstrap.settings.duplicate(true)
	settings.godot_executable = OS.get_executable_path()
	settings.async_start = true
	settings.assets_enabled = true
	var result: Dictionary = manager.initialize(settings)
	if not result.ok:
		bus.broadcast("host.failed", {"code": result.code})
		await create_timer(0.1).timeout
		quit(2)
		return
	var results = preload("res://host/core/remote_results.gd").new()
	lobby.manager = manager
	results.configure(bus, manager, bootstrap)
	manager.result_service = results
	for entry in bootstrap.games.values():
		var registered: Dictionary = preload("res://host/development.gd").register_artifact(manager, entry)
		if not registered.ok:
			bus.broadcast("host.failed", {"code": registered.code})
			_begin_stop(0)
			return
	lobby.configure(bus, settings.lobby_bind, settings.advertised_host)
	lobby.admissions.loading_ms = 60000
	if lobby.start(manager, int(settings.lobby_port), settings.security) != OK:
		bus.broadcast("host.failed", {"code": "LOBBY_BIND_FAILED"})
		_begin_stop(0)
		return
	initialized = true
	_publish()

func _process(_delta: float) -> bool:
	bus.poll()
	if initialized or stopping:
		manager.poll()
		lobby.poll()
	if bus_was_ready and not bus.ready() and not stopping:
		_begin_stop(0)
	if stopping:
		if Time.get_ticks_msec() >= deadline:
			manager.stop_all()
			if manager.active_count() == 0:
				lobby.close()
				_publish()
				manager.close()
				bus.broadcast("host.stopped", {})
				bus.poll()
				bus.close()
				quit(0)
				return false
			elif not bus.ready() and manager.close_after_control_loss():
				# Room exits are verified and journaled, but result.end was not
				# acknowledged. Preserve that recovery input without claiming a
				# completed cleanup; the next Operator will close the grants.
				lobby.close()
				bus.close()
				quit(0)
				return false
	if initialized and Time.get_ticks_msec() - last_status > 1000:
		_publish()
	return false

func _request(peer_id: String, request_id: String, action: String, payload: Dictionary) -> void:
	var result := {"ok": true, "payload": {}}
	match action:
		"server.stop": _begin_stop(0 if payload.get("immediate", false) else 60000)
		"maintenance.set":
			if stopping:
				result = Wire.failure("ROOM_DRAINING")
			else:
				lobby.maintenance = payload.enabled
				lobby.announcement = payload.get("message", "") if payload.enabled else ""
		"room.create":
			if stopping:
				result = Wire.failure("ROOM_DRAINING")
			else:
				var created: Dictionary = manager.create_room(payload.game_id, {"mode": payload.mode, "map": payload.map, "capacity": payload.capacity, "rules": payload.get("rules", {})})
				result = {"ok": true, "payload": {"room_id": created.room_id}} if created.ok else created
		"room.stop":
			result = {"ok": manager.stop_room(payload.room_id, payload.get("reason", "admin")), "payload": {}}
		"room.joinable":
			if manager.rooms.has(payload.room_id):
				manager.rooms[payload.room_id].joinable = payload.joinable
			else:
				result = Wire.failure("ROOM_NOT_FOUND")
		"room.recreate":
			if stopping:
				bus.respond(peer_id, request_id, Wire.failure("ROOM_DRAINING"))
				return
			var row: Dictionary = manager.rooms.get(payload.room_id, {}).duplicate(true)
			if row.is_empty():
				result = Wire.failure("ROOM_NOT_FOUND")
			else:
				var options: Dictionary = _options(row)
				if payload.has("rules"):
					options.rules = payload.rules
				var valid: Dictionary = manager.registry.validate_options(row.game_id, options)
				if not valid.ok:
					bus.respond(peer_id, request_id, valid)
					return
				manager.stop_room(row.room_id, payload.get("reason", "recreate"))
				var end := Time.get_ticks_msec() + 30000
				while not manager.rooms[row.room_id].cleaned and Time.get_ticks_msec() < end:
					await process_frame
				if stopping:
					result = Wire.failure("ROOM_DRAINING")
				else:
					result = manager.create_room(row.game_id, options) if manager.rooms[row.room_id].cleaned else Wire.failure("CONTROL_UNAVAILABLE")
		"player.kick": lobby.kick(payload.user_id, payload.get("reason", "operator"))
		_: result = Wire.failure("INVALID_OPTIONS")
	_publish()
	bus.respond(peer_id, request_id, result)

func _options(row: Dictionary) -> Dictionary:
	if row.has("options"):
		return row.options.duplicate(true)
	var manifest: Dictionary = bootstrap.games[row.game_id].manifest
	var mode: String = manifest.modes.keys()[0]
	return {"mode": mode, "map": manifest.modes[mode].maps[0], "capacity": row.capacity}

func _event(action: String, payload: Dictionary) -> void:
	if action == "account.revoked":
		lobby.kick(payload.user_id, "account_revoked")

func _begin_stop(delay: int) -> void:
	var requested_deadline := Time.get_ticks_msec() + delay
	# A repeated stop can shorten the grace period, never postpone an accepted stop.
	deadline = mini(deadline, requested_deadline) if stopping else requested_deadline
	stopping = true
	lobby.begin_shutdown(deadline)

func _publish() -> void:
	last_status = Time.get_ticks_msec()
	var rooms: Array = []
	var history: Array = []
	for row in manager.rooms.values():
		var public_row := lobby.public_room(row)
		public_row.merge({"pid": row.pid, "port": row.port, "heartbeats": row.heartbeats, "heartbeat_age_ms": last_status - int(row.last_heartbeat) if row.registered else -1, "joinable": row.get("joinable", true), "cleaned": row.cleaned, "metrics": row.get("metrics", {}), "options": _options(row)})
		if row.cleaned:
			history.append(public_row)
		else:
			rooms.append(public_row)
	rooms.append_array(history.slice(maxi(0, history.size() - maxi(0, 128 - rooms.size()))))
	var players: Array = []
	for connection in lobby.peers:
		if connection.user.is_empty():
			continue
		var seat: Dictionary = lobby._seat(connection.user.user_id)
		players.append({"user_id": connection.user.user_id, "display_name": connection.user.display_name, "room_id": seat.get("room_id", ""), "game_id": seat.get("game_id", ""), "state": seat.get("state", "LOBBY")})
	bus.broadcast("host.status", {"host": {"state": "DRAINING" if stopping else "RUNNING", "pid": OS.get_process_id(), "uptime": (last_status - started) / 1000, "maintenance": lobby.is_draining(), "maintenance_message": lobby.notice_message(), "countdown": maxi(0, (deadline - last_status) / 1000) if stopping else 0, "error": ""}, "rooms": rooms, "players": players})
