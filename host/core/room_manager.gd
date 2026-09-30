extends RefCounted
## Local M1 API. No public lobby or client-supplied executable paths.
##
## Linux (L2-B2 first item): room children are owned by posix_process_owner.gd
## through process_launcher.gd. The runtime folder is 700 and each private launch
## file 600 (posix_private_path.gd); both are verified or the call fails. A child
## started on a worker thread (async_start) is taken over with the single-use
## handoff token, never with an observation record; when that fails the host
## claims the now unheld record and stops the room, and a record it cannot claim
## keeps the room and its port (nothing is released for a child that may still
## run). Forced stops run on the calling thread (they are quick on Linux) and are
## retried every stop_timeout_ms until the owner confirms the exit or quarantines
## the record; resources stay allocated until then. Not yet on Linux: the process
## journal (recovery_guard.gd) and the per-room memory limit, which both rely on
## Windows helpers; they are refused at initialize instead of silently skipped.
const Registry = preload("res://host/core/game_registry.gd")
const Ports = preload("res://host/core/port_allocator.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
const PrivatePath = preload("res://host/platform/posix_private_path.gd")

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
	if OS.get_name() == "Linux":
		if config.has("process_journal"):
			return {"ok": false, "code": "RECOVERY_UNSUPPORTED"}
		if int(config.get("max_room_memory_mb", 0)) > 0:
			return {"ok": false, "code": "RESOURCE_LIMIT_UNSUPPORTED"}
		if not _protect_runtime_posix():
			return {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}
	elif OS.get_name() != "Windows":
		return {"ok": false, "code": "UNSUPPORTED_PLATFORM"}
	else:
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
	if result_service != null and resolved.manifest.get("sdk_version", "") not in ["0.4.0", "0.5.0"]:
		return {"ok": false, "code": "BUILD_MISMATCH"}
	var valid: Dictionary = registry.validate_options(game_id, options)
	if not valid.ok:
		return valid
	if _room_count() >= int(config.get("max_rooms", 16)):
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
	row.options = valid.options.duplicate(true)
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
	var private_config: Dictionary = {"room_id": room_id, "launch_id": launch_id, "token": row.token, "game_id": game_id, "build_id": row.build_id, "udp_port": row.port, "control_port": control_port, "heartbeat_ms": int(config.get("heartbeat_ms", 250)), "host_timeout_ms": int(config.get("heartbeat_timeout_ms", 8000)), "startup_timeout_ms": int(config.get("start_timeout_ms", 15000)), "options": valid.options}
	private_config.compatibility_id = row.compatibility_id
	private_config.game_protocol = row.game_protocol
	private_config.bind_ip = str(config.get("game_bind", "127.0.0.1"))
	private_config.assets_enabled = bool(config.get("assets_enabled", false))
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
	if not _seal_private_file(row.config_path):
		_fail(row, "PRIVATE_CONFIG_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": room_id}
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
			_drop(connection, "TRANSPORT_CLOSED", "", str(peer.get_status()))
			continue
		# Child identity must be captured before consuming registration bytes.
		if connection.room_id == "" and not starts.is_empty():
			continue
		var messages: Array = connection.transport.pump(peer)
		if not connection.transport.error.is_empty():
			_reject(connection, "TRANSPORT_ERROR", "", connection.transport.error)
			continue
		for message in messages:
			if not connections.has(connection):
				break
			_receive(connection, message)
		if not connections.has(connection):
			continue
		if not connection.transport.flush(peer):
			_drop(connection, "WRITE_FAILED", "", connection.transport.error)
			continue
		if connection.room_id == "" and Time.get_ticks_msec() - int(connection.accepted_at) > 3000:
			_reject(connection, "REGISTER_TIMEOUT")
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
			if OS.get_name() == "Linux" and now >= int(row.cleanup_deadline) and now >= int(row.get("next_kill_at", 0)):
				# Retried until the owner confirms the exit or quarantines the record;
				# the room keeps its resources meanwhile.
				row.kill_attempted = true
				row.kill_attempts = int(row.get("kill_attempts", 0)) + 1
				row.next_kill_at = now + int(config.get("stop_timeout_ms", 3000))
				if launcher.terminate(row.launch_id):
					row.erase("cleanup_code")
				else:
					row["cleanup_code"] = "PROCESS_IDENTITY_UNVERIFIED"
			elif OS.get_name() != "Linux" and now >= int(row.cleanup_deadline) and not row.kill_attempted:
				row.kill_attempted = true
				if config.get("async_start", false) and OS.get_name() != "Linux":
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
	# Shutdown must also wait for work which can outlive the last room.
	return _room_count() + (1 if result_service != null and result_service.busy() else 0) + (1 if recovery_guard != null and not recovery_guard.idle() else 0) + (1 if resource_worker != null else 0)

func _room_count() -> int:
	# Starting, stopping and failed rooms retain capacity until cleanup confirms
	# resources are reclaimed. Background services do not allocate room slots.
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
		_drop(connection, "HOST_CLOSED")
	server.stop()
	closed = true
	return true

func _receive(connection: Dictionary, message: Dictionary) -> void:
	if not Protocol.validate(message).is_empty():
		_reject(connection, "SCHEMA_REJECTED", str(message.get("type", "")))
		return
	var row: Dictionary = rooms.get(message.room_id, {})
	if row.is_empty() or row.cleaned or message.launch_id != row.launch_id or message.game_id != row.game_id or message.build_id != row.build_id:
		_reject(connection, "IDENTITY_MISMATCH", message.type)
		return
	if connection.room_id == "":
		if message.type != "room.register" or row.state != "STARTING" or row.registered or message.payload.token != row.token or int(message.payload.pid) != int(row.pid):
			_reject(connection, "REGISTER_REJECTED", message.type)
			return
		connection.room_id = row.room_id
		row.registered = true
		_remove_config(row)
		row.token = ""
		return
	if connection.room_id != row.room_id:
		_reject(connection, "ROOM_MISMATCH", message.type)
		return
	match message.type:
		"room.ready":
			if row.state != "STARTING" or int(message.payload.udp_port) != int(row.port):
				_reject(connection, "READY_REJECTED", message.type)
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
				_reject(connection, "HEARTBEAT_SEQUENCE", message.type)
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
				_reject(connection, "UNEXPECTED_STOPPED", message.type)
				return
			row.stop_notice = true
		"room.failed":
			_fail(row, message.payload.code)
		"result.submit":
			if result_service == null or not result_service.handle(row, message):
				_reject(connection, "RESULT_REJECTED", message.type)
		_:
			if not control_handler.is_valid() or not control_handler.call(row, message):
				_reject(connection, "HANDLER_REJECTED", message.type)

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
			_drop(connection, "ROOM_CLEANED")
	if row.state != "FAILED":
		_transition(row, "STOPPED")

func _remove_config(row: Dictionary) -> void:
	if FileAccess.file_exists(row.config_path):
		DirAccess.remove_absolute(row.config_path)

func _drop(connection: Dictionary, reason := "UNSPECIFIED", message_type := "", transport_code := "") -> void:
	connection.peer.disconnect_from_host()
	connections.erase(connection)
	var row: Dictionary = rooms.get(connection.room_id, {})
	if not row.is_empty() and not row.cleaned and row.state in ["STARTING", "READY"]:
		_log_control_closed(connection, row, reason, message_type, transport_code)
		var code := "PROCESS_EXITED" if launcher.probe(row.launch_id) == "exited" else "CONTROL_UNAVAILABLE"
		_fail(row, code)
	elif row.is_empty() and reason not in ["HOST_CLOSED"]:
		_log_control_closed(connection, {}, reason, message_type, transport_code)

func _reject(connection: Dictionary, reason := "UNSPECIFIED", message_type := "", transport_code := "") -> void:
	rejected_connections += 1
	_drop(connection, reason, message_type, transport_code)

## Redacted control diagnostics: fixed reason names, identifiers already shown in
## the admin panel, a message type only if it is a plain protocol word, transport
## codes from control_transport.gd, and timing. Never payloads, tokens or keys.
func _log_control_closed(connection: Dictionary, row: Dictionary, reason: String, message_type: String, transport_code: String) -> void:
	var now := Time.get_ticks_msec()
	var safe_type := message_type if message_type.length() <= 32 and _plain_word(message_type) else "invalid"
	var fields := ["ROOM_CONTROL_CLOSED t=%d" % int(Time.get_unix_time_from_system() * 1000.0), "reason=" + reason, "type=" + (safe_type if safe_type != "" else "-"), "transport=" + ("-" if transport_code == "" else (transport_code if _plain_word(transport_code) else "invalid"))]
	if row.is_empty():
		fields.append("room=unregistered age_ms=%d" % (now - int(connection.get("accepted_at", now))))
	else:
		fields.append_array(["room=" + str(row.room_id), "launch=" + str(row.launch_id).left(8), "state=" + str(row.state), "heartbeats=%d" % int(row.heartbeats), "since_heartbeat_ms=%d" % (now - int(row.last_heartbeat) if int(row.last_heartbeat) > 0 else -1), "age_ms=%d" % (now - int(row.created_at))])
	print(" ".join(fields))

static func _plain_word(value: String) -> bool:
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-":
			return false
	return true

func _transition(row: Dictionary, state: String) -> void:
	row.state = state
	row.history.append(state)
	print("ROOM_STATE t=", int(Time.get_unix_time_from_system() * 1000.0), " room=", row.room_id, " state=", state, " code=", row.code)

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
		if result_service.has_method("worker_store"):
			store = result_service.worker_store()
		private_config.results = {"directory": str(store.root).path_join("outbox").path_join(row.launch_id), "secret": grant.secret}
	var task := Thread.new()
	_transition(row, "STARTING")
	if task.start(_start_worker.bind(descriptor.duplicate(true), private_config.duplicate(true), row.config_path, grant, store)) != OK:
		_fail(row, "PROCESS_LAUNCH_FAILED")
		_cleanup(row)
		return {"ok": false, "code": row.code, "room_id": row.room_id}
	starts[row.room_id] = task
	return {"ok": true, "code": "", "room_id": row.room_id}

## Linux: runtime folder 700 (created if missing, links refused), with the same
## .gdignore marker as on Windows.
func _protect_runtime_posix() -> bool:
	if not PrivatePath.protect_directory(runtime_root, runtime_root).ok:
		return false
	var marker := runtime_root.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		var file := FileAccess.open(marker, FileAccess.WRITE)
		if file == null:
			return false
		file.close()
	return PrivatePath.protect_file(marker, runtime_root).ok

## A private launch file (it carries the room token): 600 and verified on Linux.
## The runtime folder's ACL already covers it on Windows.
static func _seal_private_file(path: String) -> bool:
	if OS.get_name() != "Linux":
		return true
	var root := path.get_base_dir()
	if PrivatePath.protect_file(path, root).ok:
		return true
	DirAccess.remove_absolute(path)
	return false

static func _start_worker(descriptor: Dictionary, bootstrap: Dictionary, path: String, grant: Dictionary, store: Dictionary) -> Dictionary:
	if not grant.is_empty():
		var written: Dictionary
		if store.has("rpc"):
			var remote = preload("res://sdk/roomkit/shared/local_rpc.gd").new()
			remote.connect_to(int(store.rpc.port), store.rpc.token, store.rpc.launch_id)
			written = remote.blocking_request("result.grant", {"grant": grant})
			remote.close()
		else:
			var repository = preload("res://host/storage/sqlite_repository.gd").new()
			repository.root = store.root
			repository.database = store.database
			written = repository.execute({"op": "grant", "grant": grant})
		if not written.ok:
			return {"started": written, "owned": {}, "grant": {}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"started": {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}, "owned": {}, "grant": grant}
	file.store_string(JSON.stringify(bootstrap))
	file.close()
	if not _seal_private_file(path):
		return {"started": {"ok": false, "code": "PRIVATE_CONFIG_FAILED"}, "owned": {}, "grant": grant}
	var isolated = Launcher.new()
	var started: Dictionary = isolated.launch(descriptor, bootstrap.launch_id, ["--launch-id=" + bootstrap.launch_id, "--launch-config=" + path])
	# owned: an observation (journal, diagnostics). handoff: what moves the child
	# to the main launcher (Windows: the same record; Linux: a single-use token that
	# exists only in memory).
	return {"started": started, "owned": isolated.record(bootstrap.launch_id), "handoff": isolated.handoff(bootstrap.launch_id), "grant": grant}

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
		row.pid = maxi(0, int(completed.started.get("pid", 0)))
		var handed: Dictionary = completed.get("handoff", {})
		var taken: bool = not handed.is_empty() and launcher.import_owned(handed)
		if not taken and row.pid > 0:
			# The worker's launcher is gone; its child must not be left unmanaged.
			var claimed: bool = OS.get_name() == "Linux" and launcher.reclaim(row.launch_id)
			if not claimed:
				row["cleanup_code"] = "PROCESS_OWNERSHIP_LOST"
			if completed.started.ok:
				_fail(row, "PROCESS_HANDOFF_FAILED")
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
