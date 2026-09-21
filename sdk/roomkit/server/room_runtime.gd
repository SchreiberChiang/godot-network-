extends SceneTree
## Game entry assigns build_identity and adapter, then calls super._initialize().
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const NetRoom = preload("res://sdk/roomkit/shared/net_room.gd")
const Outbox = preload("res://sdk/roomkit/server/result_outbox.gd")
const ResultFormat = preload("res://sdk/roomkit/shared/result_format.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
const ASSET_OPERATION_TIMEOUT_MS := 60000
const ASSET_INITIAL_TIMEOUT_MS := 60000
var adapter
var build_identity: Dictionary
var context: Dictionary
var transport = Transport.new()
var control := StreamPeerTCP.new()
var enet := ENetMultiplayerPeer.new()
var network := SceneMultiplayer.new()
var net_node
var members: Dictionary = {}
var attempts: Dictionary = {}
var revision := 1
var registered := false
var ready := false
var stopping := false
var stop_at := 0
var last_host := 0
var last_beat := 0
var sequence := 0
var step := 0
var started := 0
var result_outbox
var submitted_results: Dictionary = {}
var last_result_send := -1000
var last_result_error := ""
var asset_operations: Dictionary = {}

func _initialize() -> void:
	var args: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var file: String = args.get("--launch-config", "")
	if not FileAccess.file_exists(file):
		quit(2)
		return
	context = Wire.decode(FileAccess.get_file_as_bytes(file), "", 16384)
	if context.is_empty() or context.get("launch_id", "") != args.get("--launch-id", ""):
		quit(2)
		return
	for key in ["game_id", "build_id", "compatibility_id", "game_protocol"]:
		if context.get(key) != build_identity.get(key):
			quit(2)
			return
	var public_context := context.duplicate(true)
	public_context.erase("token")
	public_context.erase("results")
	public_context.erase("security")
	public_context.results_enabled = context.has("results")
	if context.has("results"):
		result_outbox = Outbox.new()
		if not result_outbox.initialize(context.results.directory, context.results.secret):
			quit(2)
			return
		context.erase("results")
	if adapter != null:
		adapter.result_requested.connect(submit_result)
		adapter.asset_refresh_requested.connect(_refresh_assets)
	if adapter == null or not adapter.configure_room(public_context):
		quit(2)
		return
	multiplayer_poll = false
	set_multiplayer(network)
	network.server_relay = false
	network.auth_timeout = 5.0
	network.auth_callback = _authenticate
	network.peer_connected.connect(_peer_connected)
	network.peer_disconnected.connect(_peer_left)
	network.peer_authentication_failed.connect(_peer_left)
	net_node = NetRoom.new()
	net_node.name = "NetRoom"
	root.add_child(net_node)
	net_node.loaded_received.connect(_loaded)
	net_node.leave_received.connect(_disconnect)
	started = Time.get_ticks_msec()
	last_host = started
	control.connect_to_host("127.0.0.1", int(context.control_port))

func _process(_delta: float) -> bool:
	if context.is_empty():
		return false
	var now := Time.get_ticks_msec()
	control.poll()
	if control.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if not registered:
			control.set_no_delay(true)
			_send("room.register", {"token": context.token, "pid": OS.get_process_id()})
			context.token = ""
			registered = true
			enet.set_bind_ip(str(context.get("bind_ip", "127.0.0.1")))
			if enet.create_server(int(context.udp_port), int(context.options.capacity)) != OK:
				_send("room.failed", {"code": "PORT_BIND_FAILED"})
				stopping = true
				stop_at = now + 150
			else:
				if context.has("security"):
					var tls := Secure.server_options(context.security)
					context.erase("security")
					if tls == null or enet.host.dtls_server_setup(tls) != OK:
						_shutdown("CONTROL_UNAVAILABLE")
						return false
				network.multiplayer_peer = enet
				ready = true
				_send("room.ready", {"udp_port": int(context.udp_port)})
		for message in transport.pump(control):
			if not Protocol.validate(message).is_empty() or message.room_id != context.room_id or message.launch_id != context.launch_id or message.game_id != context.game_id or message.build_id != context.build_id:
				_shutdown("CONTROL_UNAVAILABLE")
				break
			last_host = now
			_handle_control(message)
		if ready and not stopping:
			network.poll()
			_expire_asset_operations(now)
			step += 1
			if now - last_beat >= int(context.heartbeat_ms):
				last_beat = now
				sequence += 1
				_send("room.heartbeat", {"sequence": sequence, "step": step})
			for peer_id in members.keys():
				if members[peer_id].state != "IN_ROOM" and now > int(members[peer_id].deadline):
					_disconnect(peer_id)
		if not transport.flush(control) or transport.error != "":
			_shutdown("CONTROL_UNAVAILABLE")
		if registered and result_outbox != null and now - last_result_send >= 1000:
			last_result_send = now
			var pending: Array = result_outbox.pending()
			if not pending.is_empty():
				var item := Wire.decode(FileAccess.get_file_as_bytes(pending[0]), "res://schemas/result_submission.schema.json", 32768)
				if not item.is_empty():
					_send("result.submit", item)
	elif registered:
		_shutdown("CONTROL_UNAVAILABLE")
	if not registered and now - started > int(context.startup_timeout_ms):
		_shutdown("START_TIMEOUT")
	if now - last_host > int(context.host_timeout_ms):
		_shutdown("CONTROL_UNAVAILABLE")
	if stopping and now >= stop_at:
		enet.close()
		quit(0)
	return false

func _authenticate(peer_id: int, bytes: PackedByteArray) -> void:
	if stopping or members.has(peer_id):
		_disconnect(peer_id)
		return
	var hello := Wire.decode(bytes, "res://schemas/admission_hello.schema.json", 4096)
	if hello.is_empty():
		_disconnect(peer_id)
		return
	for key in ["room_id", "launch_id", "game_id", "build_id", "compatibility_id", "game_protocol"]:
		if hello.get(key) != context.get(key):
			_disconnect(peer_id)
			return
	if attempts.has(hello.attempt_id):
		_disconnect(peer_id)
		return
	members[peer_id] = {"state": "AUTHENTICATING", "attempt_id": hello.attempt_id, "user_id": hello.user_id, "display_name": "", "deadline": Time.get_ticks_msec() + 12000, "revision": 0, "assets_ready": not context.get("assets_enabled", false)}
	attempts[hello.attempt_id] = peer_id
	_send("admission.consume", {"ticket": hello.ticket, "attempt_id": hello.attempt_id, "user_id": hello.user_id, "compatibility_id": hello.compatibility_id, "game_protocol": hello.game_protocol})

func _handle_control(message: Dictionary) -> void:
	var payload: Dictionary = message.payload
	match message.type:
		"asset.begin": _asset_begin(payload)
		"asset.finish": _asset_finish(payload)
		"asset.initial":
			if attempts.has(payload.attempt_id):
				var member: Dictionary = members[attempts[payload.attempt_id]]
				if member.user_id == payload.user_id and member.state == "WAIT_HOST" and Time.get_ticks_msec() <= int(member.deadline) and not member.get("assets_ready", false):
					adapter.on_asset_state(payload.user_id, payload.state)
					member.assets_ready = true
		"result.ack":
			if result_outbox != null:
				result_outbox.acknowledge(payload)
				if not payload.ok:
					last_result_error = payload.code
					printerr("RESULT_REJECTED code=", payload.code)
		"room.heartbeat": pass
		"room.drain": network.refuse_new_connections = true
		"room.stop": _shutdown(payload.reason)
		"admission.revoke":
			if attempts.has(payload.attempt_id):
				_disconnect(attempts[payload.attempt_id])
		"admission.result":
			if not attempts.has(payload.attempt_id):
				return
			var peer_id: int = attempts[payload.attempt_id]
			var member: Dictionary = members[peer_id]
			if not payload.ok or payload.user_id != member.user_id:
				_disconnect(peer_id)
				return
			if member.state != "AUTHENTICATING":
				return
			member.display_name = payload.display_name
			member.state = "AUTHENTICATED"
			network.send_auth(peer_id, JSON.stringify({"ok": true, "attempt_id": payload.attempt_id}).to_utf8_buffer())
			network.complete_auth(peer_id)
		"member.accepted":
			if not attempts.has(payload.attempt_id):
				return
			var peer_id: int = attempts[payload.attempt_id]
			var member: Dictionary = members[peer_id]
			if member.state != "WAIT_HOST":
				return
			if not payload.ok or Time.get_ticks_msec() > int(member.deadline):
				_disconnect(peer_id)
				return
			if context.get("assets_enabled", false) and not member.get("assets_ready", false):
				_disconnect(peer_id)
				return
			member.state = "IN_ROOM"
			revision += 1
			adapter.on_player_admitted(_identity(member))
			net_node.confirm.rpc_id(peer_id, _snapshot())
			_broadcast()
		_: _shutdown("CONTROL_UNAVAILABLE")

func _peer_connected(peer_id: int) -> void:
	if not members.has(peer_id) or members[peer_id].state != "AUTHENTICATED":
		_disconnect(peer_id)
		return
	members[peer_id].state = "LOADING"
	_prepare(peer_id)

func _prepare(peer_id: int) -> void:
	members[peer_id].revision = revision
	net_node.prepare.rpc_id(peer_id, _snapshot())

func _loaded(peer_id: int, received_revision: int) -> void:
	if not members.has(peer_id) or members[peer_id].state != "LOADING":
		return
	if received_revision != revision or int(members[peer_id].revision) != revision:
		_prepare(peer_id)
		return
	members[peer_id].state = "WAIT_HOST"
	if context.get("assets_enabled", false):
		members[peer_id].deadline = Time.get_ticks_msec() + ASSET_INITIAL_TIMEOUT_MS
	_send("member.joined", {"attempt_id": members[peer_id].attempt_id, "user_id": members[peer_id].user_id})

func _peer_left(peer_id: int) -> void:
	if not members.has(peer_id):
		return
	var member: Dictionary = members[peer_id]
	for operation_id in asset_operations.keys():
		var operation: Dictionary = asset_operations[operation_id]
		if operation.user_id == member.user_id:
			asset_operations.erase(operation_id)
			adapter.set_asset_busy(member.user_id, false)
			if operation.kind == "refresh":
				adapter.cancel_asset_refresh(member.user_id, operation.operation)
	_send("member.left", {"attempt_id": member.attempt_id, "user_id": member.user_id})
	if member.state == "IN_ROOM":
		adapter.on_player_left(_identity(member), "disconnected")
		revision += 1
	attempts.erase(member.attempt_id)
	members.erase(peer_id)
	_broadcast()

func _disconnect(peer_id: int) -> void:
	_peer_left(peer_id)
	network.disconnect_peer(peer_id)

func _identity(member: Dictionary) -> Dictionary:
	return {"user_id": member.user_id, "display_name": member.display_name}

func _asset_begin(payload: Dictionary) -> void:
	var valid := attempts.has(payload.attempt_id)
	var member: Dictionary = members.get(attempts.get(payload.attempt_id, -1), {})
	valid = valid and context.get("assets_enabled", false) and member.get("state", "") == "IN_ROOM" and member.get("user_id", "") == payload.user_id and not stopping and not asset_operations.has(payload.operation_id)
	for operation in asset_operations.values():
		valid = valid and operation.user_id != payload.user_id
	if not valid:
		_send("asset.permit", {"operation_id": payload.operation_id, "attempt_id": payload.attempt_id, "user_id": payload.user_id, "ok": false, "context": {}})
		return
	asset_operations[payload.operation_id] = {"user_id": payload.user_id, "attempt_id": payload.attempt_id, "kind": "transaction", "operation": "", "deadline": Time.get_ticks_msec() + ASSET_OPERATION_TIMEOUT_MS}
	adapter.set_asset_busy(payload.user_id, true)
	_send("asset.permit", {"operation_id": payload.operation_id, "attempt_id": payload.attempt_id, "user_id": payload.user_id, "ok": true, "context": adapter.asset_context(payload.user_id)})

func _asset_finish(payload: Dictionary) -> void:
	var operation: Dictionary = asset_operations.get(payload.operation_id, {})
	if operation.is_empty() or operation.user_id != payload.user_id:
		return
	if Time.get_ticks_msec() > int(operation.deadline):
		_expire_asset_operations(Time.get_ticks_msec())
		return
	asset_operations.erase(payload.operation_id)
	var member: Dictionary = members.get(attempts.get(operation.attempt_id, -1), {})
	if member.get("state", "") != "IN_ROOM" or member.get("user_id", "") != payload.user_id:
		return
	adapter.set_asset_busy(payload.user_id, false)
	if payload.ok:
		adapter.on_asset_state(payload.user_id, payload.state)
	if operation.kind == "refresh":
		if payload.ok:
			adapter.complete_asset_refresh(payload.user_id, operation.operation, payload.state)
		else:
			adapter.cancel_asset_refresh(payload.user_id, operation.operation)

func _refresh_assets(user_id: String, operation: String) -> void:
	if not context.get("assets_enabled", false) or stopping or operation.is_empty() or operation.length() > 64:
		adapter.cancel_asset_refresh(user_id, operation)
		return
	for existing in asset_operations.values():
		if existing.user_id == user_id:
			if existing.kind == "refresh" and existing.operation == operation:
				return
			adapter.cancel_asset_refresh(user_id, operation)
			return
	for member in members.values():
		if member.user_id == user_id and member.state == "IN_ROOM":
			var operation_id := Wire.uid()
			asset_operations[operation_id] = {"user_id": user_id, "attempt_id": member.attempt_id, "kind": "refresh", "operation": operation, "deadline": Time.get_ticks_msec() + ASSET_OPERATION_TIMEOUT_MS}
			adapter.set_asset_busy(user_id, true)
			_send("asset.refresh", {"operation_id": operation_id, "attempt_id": member.attempt_id, "user_id": user_id})
			return
	adapter.cancel_asset_refresh(user_id, operation)

func _expire_asset_operations(now: int) -> void:
	for operation_id in asset_operations.keys():
		var operation: Dictionary = asset_operations[operation_id]
		if now <= int(operation.deadline):
			continue
		asset_operations.erase(operation_id)
		var peer_id: int = attempts.get(operation.attempt_id, -1)
		var member: Dictionary = members.get(peer_id, {})
		if member.get("user_id", "") != operation.user_id:
			continue
		adapter.set_asset_busy(operation.user_id, false)
		if operation.kind == "refresh":
			adapter.cancel_asset_refresh(operation.user_id, operation.operation)
		else:
			# An uncertain write must not allow a live game transition before it resolves.
			# End this membership; a later reply cannot affect a fresh admission attempt.
			_disconnect(peer_id)

func _snapshot() -> Dictionary:
	var list: Array = []
	for member in members.values():
		if member.state == "IN_ROOM":
			list.append(_identity(member))
	return {"room_id": context.room_id, "revision": revision, "members": list}

func _broadcast() -> void:
	if stopping:
		return
	for peer_id in members:
		if members[peer_id].state == "IN_ROOM":
			net_node.roster.rpc_id(peer_id, _snapshot())

func _shutdown(reason: String) -> void:
	if stopping:
		return
	stopping = true
	stop_at = Time.get_ticks_msec() + 150
	adapter.on_shutdown_requested(reason)
	if result_outbox != null and not result_outbox.pending().is_empty():
		stop_at = Time.get_ticks_msec() + 1500
	for peer_id in members.keys():
		_disconnect(peer_id)
	enet.close()
	_send("room.stopped", {})

func _send(type: String, payload: Dictionary) -> void:
	transport.queue(Protocol.event(type, context.room_id, context.launch_id, payload, context.game_id, context.build_id))

func submit_result(match_key: String, status: String, payload: Dictionary) -> Dictionary:
	if result_outbox == null:
		return Wire.failure("RESULTS_DISABLED")
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,64}$")
	if pattern.search(match_key) == null:
		return Wire.failure("INVALID_RESULT")
	var record := {"game_id": context.game_id, "build_id": context.build_id, "room_id": context.room_id, "launch_id": context.launch_id, "match_id": "m_" + context.launch_id + "_" + match_key, "result_id": submitted_results.get(match_key, {}).get("result_id", Wire.uid()), "result_kind": "final", "result_version": 1, "status": status, "payload": payload.duplicate(true)}
	if submitted_results.has(match_key):
		return {"ok": true, "result_id": record.result_id} if ResultFormat.hash_record(record) == ResultFormat.hash_record(submitted_results[match_key]) else Wire.failure("RESULT_CONFLICT")
	var result: Dictionary = result_outbox.enqueue(record)
	if result.ok:
		submitted_results[match_key] = record
	else:
		last_result_error = result.code
		printerr("RESULT_QUEUE_FAILED code=", result.code)
	return result
