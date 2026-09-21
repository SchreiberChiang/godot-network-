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
var result_service
var starts: Dictionary = {}
var terminations: Dictionary = {}
var recovery_guard
var resource_worker: Thread
var resource_room := ""
var resource_cursor := 0
var next_resource_check := 0

func initialize(settings: Dictionary, process_adapter = null) -> Dictionary:
	config = settings.duplicate(true)
	launcher = process_adapter if process_adapter != null else Launcher.new()
	ports = Ports.new(int(config.get("udp_first", 28100)), int(config.get("udp_last", 28131)))
	runtime_root = preload("res://sdk/roomkit/shared/paths.gd").absolute("res://run")
	if OS.get_name() != "Windows":
		return {"ok": false, "code": "UNSUPPORTED_PLATFORM"}
	var output: Array = []
	var result := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/protect_runtime.ps1"), "-ProjectRoot", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://")]), output, false, false)
	if result != 0:
		return {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}
	if config.has("process_journal") and int(config.get("control_port", 0)) == 0:
		return {"ok": false, "code": "INVALID_OPTIONS"}
	var err := server.listen(int(config.get("control_port", 0)), "127.0.0.1")
	if err != OK:
		return {"ok": false, "code": "CONTROL_UNAVAILABLE"}
	control_port = server.get_local_port()
	if config.has("process_journal"):
		recovery_guard = preload("res://host/core/recovery_guard.gd").new()
		if not recovery_guard.initialize(config.process_journal, ports):
			server.stop()
			return {"ok": false, "code": "RECOVERY_REQUIRED"}
	return {"ok": true, "code": ""}

func create_room(game_id: String, options: Dictionary) -> Dictionary:
	if closed or not server.is_listening():
		return {"ok": false, "code": "CONTROL_UNAVAILABLE"}
	if recovery_guard != null and not recovery_guard.healthy:
		return {"ok": false, "code": "RECOVERY_REQUIRED"}
	var resolved: Dictionary = registry.resolve(game_id)
	if not resolved.ok:
		return resolved
	if result_service != null and resolved.manifest.get("sdk_version", "") != "0.4.0":
		return {"ok": false, "code": "BUILD_MISMATCH"}
	var valid: Dictionary = registry.validate_options(game_id, options)
	if not valid.ok:
		return valid
	if active_count() >= int(config.get("max_rooms", 16)):
		return {"ok": false, "code": "HOST_CAPACITY_EXCEEDED"}
	if config.get("async_start", false) and starts.size() >= 2:
		return {"ok": false, "code": "HOST_CAPACITY_EXCEEDED"}
	if rooms.size() >= int(config.get("max_room_history", 4096)):
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
	if recovery_guard != null and not recovery_guard.reserve(launch_id, row.port):
		_fail(row, "PRIVATE_CONFIG_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": room_id}
	var private_config: Dictionary = {"room_id": room_id, "launch_id": launch_id, "token": row.token, "game_id": game_id, "build_id": row.build_id, "udp_port": row.port, "control_port": control_port, "heartbeat_ms": int(config.get("heartbeat_ms", 250)), "host_timeout_ms": int(config.get("heartbeat_timeout_ms", 8000)), "startup_timeout_ms": int(config.get("start_timeout_ms", 15000)), "options": options}
	private_config.compatibility_id = row.compatibility_id
	private_config.game_protocol = row.game_protocol
	if config.has("security"):
		private_config.security = config.security.duplicate(true)
	if config.get("async_start", false):
		return _begin_start(row, resolved.descriptor, private_config)
	if result_service != null:
		var prepared: Dictionary = result_service.prepare_launch(row)
		if not prepared.ok:
			_fail(row, prepared.code)
			_cleanup(row)
			return {"ok": false, "code": row.code, "room_id": room_id}
		private_config.results = prepared.config
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
	if recovery_guard != null and not recovery_guard.confirm(launch_id, launcher.record(launch_id)):
		_fail(row, "PRIVATE_CONFIG_FAILED")
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
	if result_service != null:
		result_service.poll()
	_poll_workers()
	_poll_resources()
	if recovery_guard != null:
		recovery_guard.poll()
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
		# Child identity must be captured before consuming registration bytes.
		if connection.room_id == "" and not starts.is_empty():
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
		if starts.has(row.room_id) or terminations.has(row.room_id):
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
				if config.get("async_start", false):
					var task := Thread.new()
					var owned: Dictionary = launcher.record(row.launch_id)
					if task.start(_terminate_worker.bind(owned)) == OK:
						terminations[row.room_id] = task
						continue
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
	return count + (1 if result_service != null and result_service.busy() else 0) + (1 if recovery_guard != null and not recovery_guard.idle() else 0) + (1 if resource_worker != null else 0)

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
		"result.submit":
			if result_service == null or not result_service.handle(row, message):
				_reject(connection)
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
	if starts.has(row.room_id) or terminations.has(row.room_id):
		return
	if row.pid != 0 and launcher.probe(row.launch_id) != "exited":
		return
	row.exit_confirmed = true
	if row.port != 0 and not ports.release(row.launch_id, true):
		row["cleanup_code"] = "PORT_QUARANTINED"
		return
	row.erase("cleanup_code")
	row.cleaned = true
	if recovery_guard != null:
		recovery_guard.release(row.launch_id)
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

func _begin_start(row: Dictionary, descriptor: Dictionary, private_config: Dictionary) -> Dictionary:
	var grant := {}
	var store := {}
	if result_service != null:
		if not result_service.schemas.has(row.game_id):
			_fail(row, "INVALID_RESULT")
			_cleanup(row)
			return {"ok": false, "code": row.code, "room_id": row.room_id}
		grant = {"launch_id": row.launch_id, "room_id": row.room_id, "game_id": row.game_id, "build_id": row.build_id, "secret": Crypto.new().generate_random_bytes(32).hex_encode()}
		store = {"root": result_service.repository.root, "database": result_service.repository.database}
		private_config.results = {"directory": str(store.root).path_join("outbox").path_join(row.launch_id), "secret": grant.secret}
	var task := Thread.new()
	_transition(row, "STARTING")
	if task.start(_start_worker.bind(descriptor.duplicate(true), private_config.duplicate(true), row.config_path, grant, store)) != OK:
		_fail(row, "PROCESS_LAUNCH_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": row.room_id}
	starts[row.room_id] = task
	return {"ok": true, "code": "", "room_id": row.room_id}

static func _start_worker(descriptor: Dictionary, bootstrap: Dictionary, path: String, grant: Dictionary, store: Dictionary) -> Dictionary:
	if not grant.is_empty():
		var repository = preload("res://host/storage/sqlite_repository.gd").new()
		repository.root = store.root
		repository.database = store.database
		var written: Dictionary = repository.execute({"op": "grant", "grant": grant})
		if not written.ok:
			return {"started": written, "owned": {}, "grant": {}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"started": {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}, "owned": {}, "grant": grant}
	file.store_string(JSON.stringify(bootstrap))
	file.close()
	var isolated = Launcher.new()
	var started: Dictionary = isolated.launch(descriptor, bootstrap.launch_id, ["--launch-id=" + bootstrap.launch_id, "--launch-config=" + path])
	return {"started": started, "owned": isolated.record(bootstrap.launch_id), "grant": grant}

static func _terminate_worker(owned: Dictionary) -> bool:
	if owned.is_empty():
		return false
	var isolated = Launcher.new()
	isolated.import_owned(owned)
	return isolated.terminate(owned.launch_id)

func _poll_workers() -> void:
	for id in starts.keys():
		var task: Thread = starts[id]
		if task.is_alive():
			continue
		var completed: Dictionary = task.wait_to_finish()
		starts.erase(id)
		var row: Dictionary = rooms[id]
		if not completed.grant.is_empty():
			result_service.grants[row.launch_id] = completed.grant
		if not completed.owned.is_empty():
			launcher.import_owned(completed.owned)
		row.pid = maxi(0, int(completed.started.get("pid", 0)))
		if recovery_guard != null and not recovery_guard.confirm(row.launch_id, completed.owned):
			_fail(row, "PRIVATE_CONFIG_FAILED")
		row.created_at = Time.get_ticks_msec()
		if not completed.started.ok:
			_fail(row, completed.started.code)
			_cleanup(row)
	for id in terminations.keys():
		var task: Thread = terminations[id]
		if not task.is_alive():
			var terminated: bool = task.wait_to_finish()
			terminations.erase(id)
			if not terminated:
				rooms[id]["cleanup_code"] = "PROCESS_IDENTITY_UNVERIFIED"

func _poll_resources() -> void:
	if resource_worker != null and not resource_worker.is_alive():
		var result: Dictionary = resource_worker.wait_to_finish()
		resource_worker = null
		var row: Dictionary = rooms[resource_room]
		if not row.cleaned and result.get("state", "unknown") == "running":
			row.metrics = {"working_set_bytes": result.working_set_bytes, "cpu_ms": result.cpu_ms}
			if float(result.working_set_bytes) > float(config.max_room_memory_mb) * 1048576:
				_fail(row, "ROOM_MEMORY_LIMIT")
	if int(config.get("max_room_memory_mb", 0)) <= 0 or resource_worker != null or Time.get_ticks_msec() < next_resource_check:
		return
	next_resource_check = Time.get_ticks_msec() + 1000
	var live: Array = []
	for row in rooms.values():
		if row.state == "READY" and not row.cleaned:
			live.append(row)
	if live.is_empty():
		return
	var selected: Dictionary = live[resource_cursor % live.size()]
	resource_cursor += 1
	resource_room = selected.room_id
	var owned: Dictionary = launcher.record(selected.launch_id)
	resource_worker = Thread.new()
	if resource_worker.start(_resource_snapshot.bind(owned)) != OK:
		resource_worker = null

static func _resource_snapshot(owned: Dictionary) -> Dictionary:
	return Launcher.new()._inspect("inspect", owned)
