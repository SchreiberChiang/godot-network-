extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Admissions = preload("res://host/core/admission_store.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
var identity_provider
var tls_options: TLSOptions
var manager
var admissions = Admissions.new()
var listener := TCPServer.new()
var port := 0
var peers: Array = []
var owners: Dictionary = {}

func start(room_manager, listen_port: int = 0, security: Dictionary = {}) -> int:
	manager = room_manager
	if identity_provider != null and security.is_empty():
		return ERR_UNAUTHORIZED
	if not security.is_empty():
		tls_options = Secure.server_options(security)
		if tls_options == null or identity_provider == null:
			return ERR_UNAUTHORIZED
	manager.control_handler = _control
	var error := listener.listen(listen_port, "127.0.0.1")
	if error == OK:
		port = listener.get_local_port()
	return error

func poll() -> void:
	var now := Time.get_ticks_msec()
	for revoked in admissions.poll(manager.rooms, now):
		manager.send_control(revoked.room_id, "admission.revoke", {"attempt_id": revoked.attempt_id})
	while listener.is_connection_available():
		var tcp := listener.take_connection()
		if peers.size() >= 64:
			tcp.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 65536
		ws.outbound_buffer_size = 65536
		ws.max_queued_packets = 16
		var tls: StreamPeerTLS
		if tls_options != null:
			tls = StreamPeerTLS.new()
			if tls.accept_stream(tcp, tls_options) != OK:
				tcp.disconnect_from_host()
				continue
		elif ws.accept_stream(tcp) != OK:
			tcp.disconnect_from_host()
			continue
		peers.append({"ws": ws, "tcp": tcp, "tls": tls, "tls_ready": tls == null, "user": {}, "cache": {}, "created": now, "window": now, "requests": 0})
	for connection in peers.duplicate():
		var ws: WebSocketPeer = connection.ws
		if connection.has("expires") and Time.get_unix_time_from_system() >= float(connection.expires):
			ws.close(1008, "session expired")
			_drop(connection)
			continue
		if not connection.tls_ready:
			connection.tls.poll()
			var tls_state: int = connection.tls.get_status()
			if tls_state == StreamPeerTLS.STATUS_CONNECTED:
				if ws.accept_stream(connection.tls) != OK:
					_drop(connection)
					continue
				connection.tls_ready = true
			elif tls_state != StreamPeerTLS.STATUS_HANDSHAKING or now - int(connection.created) > 5000:
				_drop(connection)
				continue
			else:
				continue
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_drop(connection)
			continue
		if connection.user.is_empty() and now - int(connection.created) > 10000:
			ws.close(1008, "session timeout")
			_drop(connection)
			continue
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		var budget := 8
		while budget > 0 and ws.get_available_packet_count() > 0:
			budget -= 1
			var bytes := ws.get_packet()
			var message := Wire.decode(bytes, "res://schemas/lobby_request.schema.json") if ws.was_string_packet() else {}
			if message.is_empty():
				ws.close(1008, "invalid request")
				_drop(connection)
				break
			if now - int(connection.window) >= 60000:
				connection.window = now
				connection.requests = 0
			connection.requests += 1
			var result: Dictionary = Wire.failure("RATE_LIMITED") if connection.requests > 240 else handle(connection, message)
			if ws.send_text(JSON.stringify(Wire.response(message, result))) != OK:
				_drop(connection)
				break

func handle(connection: Dictionary, message: Dictionary) -> Dictionary:
	if connection.has("expires") and Time.get_unix_time_from_system() >= float(connection.expires):
		return Wire.failure("AUTH_FAILED")
	var payload: Dictionary = message.payload
	if message.type == "session.create":
		if connection.user.is_empty():
			if identity_provider != null:
				var authenticated: Dictionary = identity_provider.authenticate(payload.get("credential", ""), int(Time.get_unix_time_from_system()))
				if not authenticated.ok:
					return Wire.failure("AUTH_FAILED")
				for existing in peers:
					if existing != connection and existing.user.get("user_id", "") == authenticated.identity.user_id:
						return Wire.failure("ALREADY_CONNECTED")
				connection.user = authenticated.identity
				connection.expires = authenticated.expires
			else:
				connection.user = {"user_id": "u_" + Wire.uid(), "display_name": payload.display_name}
		return {"ok": true, "payload": {"user_id": connection.user.user_id, "display_name": connection.user.display_name}}
	if connection.user.is_empty():
		return Wire.failure("AUTH_REQUIRED")
	if message.type in ["room.create", "room.reserve", "room.list"]:
		var resolved: Dictionary = manager.registry.resolve(payload.game_id)
		if not resolved.ok:
			return Wire.failure(resolved.code)
		var manifest: Dictionary = resolved.manifest
		if payload.build_id != manifest.build_id or payload.compatibility_id != manifest.compatibility_id or int(payload.game_protocol) != int(manifest.game_protocol):
			return Wire.failure("BUILD_MISMATCH")
	match message.type:
		"room.create":
			var cache: Dictionary = connection.cache
			var key: String = message.idempotency_key
			var fingerprint := JSON.stringify(payload).sha256_text()
			if cache.has(key):
				return cache[key].result.duplicate(true) if cache[key].fingerprint == fingerprint else Wire.failure("IDEMPOTENCY_CONFLICT")
			if cache.size() >= 128:
				return Wire.failure("RATE_LIMITED")
			var owned_count := 0
			for id in owners:
				if owners[id] == connection.user.user_id and not manager.rooms[id].cleaned:
					owned_count += 1
			if owned_count >= 4:
				return Wire.failure("HOST_CAPACITY_EXCEEDED")
			var created: Dictionary = manager.create_room(payload.game_id, payload.options)
			var result: Dictionary
			if created.ok:
				owners[created.room_id] = connection.user.user_id
				result = {"ok": true, "payload": {"room": public_room(manager.rooms[created.room_id])}}
			else:
				result = Wire.failure(created.code)
			cache[key] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
			return result
		"room.list":
			var rooms: Array = []
			for row in manager.rooms.values():
				if row.game_id == payload.game_id and row.build_id == payload.build_id and row.state == "READY":
					rooms.append(public_room(row))
			var end := mini(rooms.size(), int(payload.offset) + int(payload.limit))
			return {"ok": true, "payload": {"rooms": rooms.slice(int(payload.offset), end), "next_offset": end}}
		"room.get", "room.reserve", "room.stop":
			var row: Dictionary = manager.rooms.get(payload.room_id, {})
			if row.is_empty():
				return Wire.failure("ROOM_NOT_FOUND")
			if message.type == "room.get":
				return {"ok": true, "payload": {"room": public_room(row)}}
			if message.type == "room.stop":
				if owners.get(payload.room_id, "") != connection.user.user_id and connection.user.get("role", "player") != "admin":
					return Wire.failure("AUTH_FAILED")
				manager.stop_room(payload.room_id, "owner_requested")
				return {"ok": true, "payload": {}}
			if payload.game_id != row.game_id or payload.build_id != row.build_id:
				return Wire.failure("BUILD_MISMATCH")
			return admissions.reserve(row, connection.user, Time.get_ticks_msec())
	return Wire.failure("INVALID_OPTIONS")

func public_room(row: Dictionary) -> Dictionary:
	return {"room_id": row.room_id, "game_id": row.game_id, "build_id": row.build_id, "state": row.state, "capacity": row.capacity, "occupied": admissions.count(row.room_id), "connected": admissions.count(row.room_id, "CONNECTED"), "code": row.code}

func _control(row: Dictionary, message: Dictionary) -> bool:
	var payload: Dictionary = message.payload
	match message.type:
		"admission.consume":
			var result: Dictionary = admissions.consume(row, payload, Time.get_ticks_msec())
			manager.send_control(row.room_id, "admission.result", {"attempt_id": payload.attempt_id, "ok": result.ok, "user_id": result.get("payload", {}).get("user_id", ""), "display_name": result.get("payload", {}).get("display_name", ""), "code": result.get("code", "")})
			return true
		"member.joined":
			var accepted: bool = row.state == "READY" and admissions.joined(row.room_id, payload.user_id, payload.attempt_id, Time.get_ticks_msec())
			manager.send_control(row.room_id, "member.accepted", {"attempt_id": payload.attempt_id, "ok": accepted})
			return true
		"member.left":
			admissions.leave(row.room_id, payload.user_id, payload.attempt_id)
			return true
	return false

func _drop(connection: Dictionary) -> void:
	if not connection.user.is_empty():
		admissions.cancel_reservations(connection.user.user_id)
	connection.tcp.disconnect_from_host()
	peers.erase(connection)

func close() -> void:
	for connection in peers.duplicate():
		_drop(connection)
	listener.stop()
