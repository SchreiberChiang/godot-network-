extends RefCounted
## Local M1 API. No public lobby or client-supplied executable paths.
const Registry = preload("res://host/core/game_registry.gd")
const Ports = preload("res://host/core/port_allocator.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")

var registry = Registry.new()
var ports
var launcher
var server := TCPServer.new()
var control_port := 0
var rooms: Dictionary = {}
var connections: Array = []
var rejected_connections := 0
var config: Dictionary
var runtime_root := ""
var closed := false
var control_handler: Callable

func initialize(settings: Dictionary, process_adapter = null) -> Dictionary:
	config = settings.duplicate(true)
	launcher = process_adapter if process_adapter != null else Launcher.new()
	ports = Ports.new(int(config.get("udp_first", 28100)), int(config.get("udp_last", 28131)))
	runtime_root = ProjectSettings.globalize_path("res://run")
	if OS.get_name() != "Windows":
		return {"ok": false, "code": "UNSUPPORTED_PLATFORM"}
	var output: Array = []
	var result := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_runtime.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://")]), output, false, false)
	if result != 0:
		return {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}
	var err := server.listen(int(config.get("control_port", 0)), "127.0.0.1")
	if err != OK:
		return {"ok": false, "code": "CONTROL_UNAVAILABLE"}
	control_port = server.get_local_port()
	return {"ok": true, "code": ""}

func create_room(game_id: String, options: Dictionary) -> Dictionary:
	if closed or not server.is_listening():
		return {"ok": false, "code": "CONTROL_UNAVAILABLE"}
	var resolved: Dictionary = registry.resolve(game_id)
	if not resolved.ok:
		return resolved
	var valid: Dictionary = registry.validate_options(game_id, options)
	if not valid.ok:
		return valid
	if active_count() >= int(config.get("max_rooms", 16)):
		return {"ok": false, "code": "HOST_CAPACITY_EXCEEDED"}
	var room_id := "r_" + _random_id()
	var launch_id := _random_id()
	var row: Dictionary = {"room_id": room_id, "launch_id": launch_id, "game_id": game_id, "build_id": resolved.manifest.build_id, "state": "ALLOCATING", "history": ["ALLOCATING"], "code": "", "pid": 0, "port": 0, "registered": false, "heartbeats": 0, "last_sequence": -1, "last_step": -1, "last_heartbeat": 0, "last_progress": 0, "cleaned": false, "exit_confirmed": false, "stop_notice": false, "kill_attempted": false, "token": Crypto.new().generate_random_bytes(32).hex_encode(), "config_path": runtime_root.path_join(launch_id + ".json"), "created_at": Time.get_ticks_msec(), "cleanup_deadline": 0}
	rooms[room_id] = row
	row.capacity = int(valid.options.capacity)
	row.compatibility_id = resolved.manifest.compatibility_id
	row.game_protocol = int(resolved.manifest.game_protocol)
	row.port = ports.acquire(launch_id)
	if row.port == 0:
		_fail(row, "PORT_BIND_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": room_id}
	var private_config: Dictionary = {"room_id": room_id, "launch_id": launch_id, "token": row.token, "game_id": game_id, "build_id": row.build_id, "udp_port": row.port, "control_port": control_port, "heartbeat_ms": int(config.get("heartbeat_ms", 250)), "host_timeout_ms": int(config.get("heartbeat_timeout_ms", 8000)), "startup_timeout_ms": int(config.get("start_timeout_ms", 15000)), "options": options}
	private_config.compatibility_id = row.compatibility_id
	private_config.game_protocol = row.game_protocol
	var file := FileAccess.open(row.config_path, FileAccess.WRITE)
	if file == null:
		_fail(row, "PRIVATE_CONFIG_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": room_id}
	file.store_string(JSON.stringify(private_config))
	file.close()
	_transition(row, "STARTING")
	var started: Dictionary = launcher.launch(resolved.descriptor, launch_id, PackedStringArray(["--launch-id=" + launch_id, "--launch-config=" + row.config_path]))
	row.pid = maxi(int(started.get("pid", 0)), 0)
	# Identity capture can block briefly; give the child its full readiness window afterwards.
	row.created_at = Time.get_ticks_msec()
	if not started.ok:
		_fail(row, started.code)
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": room_id}
	return {"ok": true, "code": "", "room_id": room_id}

func poll() -> void:
	if closed:
		return
	while server.is_connection_available():
		var peer := server.take_connection()
		if connections.size() >= 64:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		connections.append({"peer": peer, "transport": Transport.new(), "room_id": "", "accepted_at": Time.get_ticks_msec()})
	for connection in connections.duplicate():
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(connection)
			continue
		var messages: Array = connection.transport.pump(peer)
		if not connection.transport.error.is_empty():
			_reject(connection)
			continue
		for message in messages:
			if not connections.has(connection):
				break
			_receive(connection, message)
		if not connections.has(connection):
			continue
		if not connection.transport.flush(peer):
			_drop(connection)
			continue
		if connection.room_id == "" and Time.get_ticks_msec() - int(connection.accepted_at) > 3000:
			_reject(connection)
	var now := Time.get_ticks_msec()
	for row in rooms.values():
		if row.cleaned:
			continue
		var process_status: String = "exited" if row.pid == 0 else launcher.probe(row.launch_id)
		if process_status == "exited":
			row.exit_confirmed = true
			if row.state not in ["STOPPING", "FAILED"]:
				_fail(row, "PROCESS_EXITED")
			_cleanup(row)
			continue
		if row.state == "STARTING" and now - int(row.created_at) > int(config.get("start_timeout_ms", 15000)):
			_fail(row, "START_TIMEOUT")
		elif row.state == "READY":
			if now - int(row.last_heartbeat) > int(config.get("heartbeat_timeout_ms", 8000)):
				_fail(row, "HEARTBEAT_TIMEOUT")
			elif now - int(row.last_progress) > int(config.get("heartbeat_timeout_ms", 8000)):
				_fail(row, "LOGIC_STALLED")
		if row.state in ["STOPPING", "FAILED"]:
			if now >= int(row.cleanup_deadline) and not row.kill_attempted:
				row.kill_attempted = true
				if not launcher.terminate(row.launch_id):
					row["cleanup_code"] = "PROCESS_IDENTITY_UNVERIFIED"
			_cleanup(row)

func stop_room(room_id: String, reason: String = "requested") -> bool:
	if not rooms.has(room_id):
		return false
	var row: Dictionary = rooms[room_id]
	if row.cleaned or row.state in ["STOPPING", "FAILED"]:
		return true
	_transition(row, "DRAINING")
	_send(row, "room.drain", {"reason": reason})
	_transition(row, "STOPPING")
	row.cleanup_deadline = Time.get_ticks_msec() + int(config.get("stop_timeout_ms", 3000))
	_send(row, "room.stop", {"reason": reason})
	return true

func stop_all() -> void:
	for room_id in rooms:
		stop_room(room_id, "host_shutdown")

func active_count() -> int:
	var count := 0
	for row in rooms.values():
		if not row.cleaned:
			count += 1
	return count

func snapshot(room_id: String) -> Dictionary:
	if not rooms.has(room_id):
		return {}
	var row: Dictionary = rooms[room_id].duplicate(true)
	row.erase("token")
	row.erase("config_path")
	return row

func close() -> bool:
	if active_count() != 0:
		return false
	for connection in connections.duplicate():
		_drop(connection)
	server.stop()
	closed = true
	return true

func _receive(connection: Dictionary, message: Dictionary) -> void:
	if not Protocol.validate(message).is_empty():
		_reject(connection)
		return
	var row: Dictionary = rooms.get(message.room_id, {})
	if row.is_empty() or row.cleaned or message.launch_id != row.launch_id or message.game_id != row.game_id or message.build_id != row.build_id:
		_reject(connection)
		return
	if connection.room_id == "":
		if message.type != "room.register" or row.state != "STARTING" or row.registered or message.payload.token != row.token or int(message.payload.pid) != int(row.pid):
			_reject(connection)
			return
		connection.room_id = row.room_id
		row.registered = true
		_remove_config(row)
		row.token = ""
		return
	if connection.room_id != row.room_id:
		_reject(connection)
		return
	match message.type:
		"room.ready":
			if row.state != "STARTING" or int(message.payload.udp_port) != int(row.port):
				_reject(connection)
				return
			_transition(row, "READY")
			row.last_heartbeat = Time.get_ticks_msec()
			row.last_progress = row.last_heartbeat
		"room.heartbeat":
			# A heartbeat already in flight can arrive after the local stop decision.
			if row.state in ["DRAINING", "STOPPING", "FAILED"]:
				return
			var sequence := int(message.payload.sequence)
			var step := int(message.payload.step)
			if row.state != "READY" or sequence <= int(row.last_sequence) or step < int(row.last_step):
				_reject(connection)
				return
			row.last_heartbeat = Time.get_ticks_msec()
			if step > int(row.last_step):
				row.last_progress = row.last_heartbeat
			row.last_sequence = sequence
			row.last_step = step
			row.heartbeats += 1
			# Authenticated duplex liveness: echo the same schema-valid sequence.
			_send(row, "room.heartbeat", message.payload)
		"room.stopped":
			if row.state not in ["STOPPING", "FAILED"]:
				_reject(connection)
				return
			row.stop_notice = true
		"room.failed":
			_fail(row, message.payload.code)
		_:
			if not control_handler.is_valid() or not control_handler.call(row, message):
				_reject(connection)

func send_control(room_id: String, type: String, payload: Dictionary) -> void:
	if rooms.has(room_id):
		_send(rooms[room_id], type, payload)

func _send(row: Dictionary, type: String, payload: Dictionary) -> void:
	for connection in connections:
		if connection.room_id == row.room_id:
			connection.transport.queue(Protocol.event(type, row.room_id, row.launch_id, payload, row.game_id, row.build_id))
			return

func _fail(row: Dictionary, code: String) -> void:
	if row.state == "FAILED":
		return
	row.code = code
	_transition(row, "FAILED")
	row.cleanup_deadline = Time.get_ticks_msec() + int(config.get("stop_timeout_ms", 3000))
	_send(row, "room.stop", {"reason": code})

func _cleanup(row: Dictionary) -> void:
	if row.cleaned:
		return
	if row.pid != 0 and launcher.probe(row.launch_id) != "exited":
		return
	row.exit_confirmed = true
	if row.port != 0 and not ports.release(row.launch_id, true):
		row["cleanup_code"] = "PORT_QUARANTINED"
		return
	row.erase("cleanup_code")
	row.cleaned = true
	_remove_config(row)
	row.token = ""
	if row.pid != 0:
		launcher.forget(row.launch_id)
	for connection in connections.duplicate():
		if connection.room_id == row.room_id:
			_drop(connection)
	if row.state != "FAILED":
		_transition(row, "STOPPED")

func _remove_config(row: Dictionary) -> void:
	if FileAccess.file_exists(row.config_path):
		DirAccess.remove_absolute(row.config_path)

func _drop(connection: Dictionary) -> void:
	connection.peer.disconnect_from_host()
	connections.erase(connection)
	var row: Dictionary = rooms.get(connection.room_id, {})
	if not row.is_empty() and not row.cleaned and row.state in ["STARTING", "READY"]:
		var code := "PROCESS_EXITED" if launcher.probe(row.launch_id) == "exited" else "CONTROL_UNAVAILABLE"
		_fail(row, code)

func _reject(connection: Dictionary) -> void:
	rejected_connections += 1
	_drop(connection)

func _transition(row: Dictionary, state: String) -> void:
	row.state = state
	row.history.append(state)
	print("ROOM_STATE room=", row.room_id, " state=", state, " code=", row.code)

static func _random_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
