extends Node
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const NetRoom = preload("res://sdk/roomkit/shared/net_room.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
signal session_changed(identity: Dictionary)
signal join_progress(phase: String)
signal room_joined(snapshot: Dictionary)
signal room_left
signal roster_changed(snapshot: Dictionary)
signal request_failed(code: String)
var prepare_scene: Callable
var state := "CLOSED"
var config: Dictionary = {}
var identity: Dictionary = {}
var snapshot: Dictionary = {}
var last_error := ""
var socket := WebSocketPeer.new()
var network := SceneMultiplayer.new()
var enet: ENetMultiplayerPeer
var net_node
var _pending: Dictionary = {}
var _answers: Dictionary = {}
var _admission: Dictionary = {}
var _attempt := ""
var _disconnect_pending := false
var _load_generation := 0
var _lobby_close_logged := false
var request_schema := "res://schemas/lobby_request.schema.json"
var response_schema := "res://schemas/lobby_response.schema.json"

func configure(settings: Dictionary) -> bool:
	var url: String = settings.get("url", "")
	var pattern := RegEx.new()
	pattern.compile("^wss://[A-Za-z0-9.-]+:[0-9]{1,5}/?$")
	if state != "CLOSED" or not (url.begins_with("ws://127.0.0.1:") or pattern.search(url) != null):
		return false
	if url.begins_with("wss:") and (not settings.has("ca_certificate") or not settings.get("secure_enet", false)):
		return false
	if not url.begins_with("wss:") and (settings.has("credential") or settings.get("secure_enet", false)):
		return false
	for key in ["game_id", "build_id", "compatibility_id", "game_protocol"]:
		if not settings.has(key):
			return false
	config = settings.duplicate(true)
	if config.get("managed", false):
		request_schema = "res://schemas/managed_lobby_request.schema.json"
		response_schema = "res://schemas/managed_lobby_response.schema.json"
	return true

func open_session(display_name: String) -> Dictionary:
	if config.is_empty() or state != "CLOSED":
		return Wire.failure("INVALID_OPTIONS")
	socket.inbound_buffer_size = 65536
	socket.outbound_buffer_size = 65536
	socket.max_queued_packets = 32
	var tls: TLSOptions
	if str(config.url).begins_with("wss:"):
		tls = Secure.client_options(config.ca_certificate, config.get("server_hostname", ""))
		if tls == null:
			return Wire.failure("AUTH_FAILED")
	if socket.connect_to_url(config.url, tls) != OK:
		return Wire.failure("CONTROL_UNAVAILABLE")
	state = "CONNECTING_LOBBY"
	var deadline := Time.get_ticks_msec() + 6000
	while socket.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		state = "CLOSED"
		return Wire.failure("CONTROL_UNAVAILABLE")
	var payload := {"display_name": display_name}
	if config.has("credential"):
		payload.credential = config.credential
		config.erase("credential")
	var result: Dictionary = await _request("session.create", payload)
	if result.ok:
		identity = result.payload
		state = "LOBBY"
		session_changed.emit(identity.duplicate())
	return result

func list_rooms(offset: int = 0, limit: int = 50) -> Dictionary:
	var payload := compatibility()
	payload.merge({"offset": offset, "limit": limit})
	return await _request("room.list", payload)

func create_room(options: Dictionary, key: String = "") -> Dictionary:
	var payload := compatibility()
	payload.options = options
	return await _request("room.create", payload, Wire.uid() if key.is_empty() else key)

func get_room(room_id: String) -> Dictionary:
	return await _request("room.get", {"room_id": room_id})

func stop_room(room_id: String) -> Dictionary:
	return await _request("room.stop", {"room_id": room_id})

func join_room(room_id: String) -> Dictionary:
	if state != "LOBBY":
		return Wire.failure("ALREADY_IN_ROOM")
	var payload := compatibility()
	payload.room_id = room_id
	var reserved: Dictionary = await _request("room.reserve", payload)
	if not reserved.ok:
		return reserved
	return await _connect_reserved(reserved.payload)

func _connect_reserved(admission: Dictionary) -> Dictionary:
	_admission = admission.duplicate(true)
	_attempt = Wire.uid()
	last_error = ""
	get_tree().multiplayer_poll = false
	network = SceneMultiplayer.new()
	get_tree().set_multiplayer(network)
	network.auth_timeout = 5.0
	network.auth_callback = _authenticate
	network.peer_authenticating.connect(_send_auth)
	network.peer_authentication_failed.connect(func(_id): _connection_lost("AUTH_FAILED"))
	network.connection_failed.connect(func(): _connection_lost("AUTH_FAILED"))
	network.server_disconnected.connect(func(): _connection_lost("DISCONNECTED"))
	net_node = NetRoom.new()
	net_node.name = "NetRoom"
	get_tree().root.add_child(net_node)
	net_node.preparation_received.connect(_prepare)
	net_node.confirmation_received.connect(_confirm)
	net_node.roster_received.connect(_roster)
	enet = ENetMultiplayerPeer.new()
	if enet.create_client(admission.host, int(admission.port)) != OK:
		_clear_game()
		return Wire.failure("CONTROL_UNAVAILABLE")
	if config.get("secure_enet", false):
		var tls := Secure.client_options(config.ca_certificate)
		if tls == null or enet.host.dtls_client_setup(config.get("server_hostname", "localhost"), tls) != OK:
			_clear_game()
			return Wire.failure("AUTH_FAILED")
	network.multiplayer_peer = enet
	_phase("CONNECTING")
	var deadline := Time.get_ticks_msec() + (60000 if config.get("managed", false) else 14000)
	while state != "IN_ROOM" and last_error == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if state == "IN_ROOM":
		return {"ok": true, "payload": snapshot.duplicate(true)}
	var code := last_error if last_error != "" else "LOAD_TIMEOUT"
	print("CLIENT_ROOM_JOIN_FAILED code=", code, " phase=", state, " lobby_open=", socket.get_ready_state() == WebSocketPeer.STATE_OPEN)
	_clear_game()
	state = "LOBBY"
	request_failed.emit(code)
	return Wire.failure(code)

func leave_room() -> void:
	if enet != null and network.get_peers().has(1):
		net_node.leave.rpc_id(1)
		# Flush the reliable leave before closing; disconnect also releases the seat.
		await get_tree().create_timer(0.15).timeout
	_clear_game()
	state = "LOBBY" if not identity.is_empty() else "CLOSED"
	room_left.emit()

func close() -> void:
	_clear_game()
	socket.close()
	socket = WebSocketPeer.new()
	_lobby_close_logged = false
	identity.clear()
	_pending.clear()
	_answers.clear()
	state = "CLOSED"

func compatibility() -> Dictionary:
	return {"game_id": config.game_id, "build_id": config.build_id, "compatibility_id": config.compatibility_id, "game_protocol": config.game_protocol}

func _request(type: String, payload: Dictionary, key: String = "") -> Dictionary:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return Wire.failure("CONTROL_UNAVAILABLE")
	var message := Wire.request(type, payload, key)
	if Validator.validate_file(message, request_schema) != "":
		return Wire.failure("INVALID_OPTIONS")
	if _pending.size() >= 32:
		return Wire.failure("RATE_LIMITED")
	_pending[message.request_id] = type
	if socket.send_text(JSON.stringify(message)) != OK:
		_pending.erase(message.request_id)
		return Wire.failure("CONTROL_UNAVAILABLE")
	var deadline := Time.get_ticks_msec() + (60000 if config.get("managed", false) else 10000)
	while not _answers.has(message.request_id) and Time.get_ticks_msec() < deadline and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		await get_tree().process_frame
	_pending.erase(message.request_id)
	if not _answers.has(message.request_id):
		return Wire.failure("CONTROL_UNAVAILABLE")
	var answer: Dictionary = _answers[message.request_id]
	_answers.erase(message.request_id)
	return {"ok": answer.ok, "payload": answer.payload, "code": answer.get("error", {}).get("code", "")}

func _process(_delta: float) -> void:
	socket.poll()
	var budget := 16
	while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var bytes := socket.get_packet()
		var message := Wire.decode(bytes, response_schema) if socket.was_string_packet() else {}
		if message.is_empty() or _pending.get(message.get("request_id", ""), "") != message.get("type", ""):
			# Redacted: which check failed and the reply type only, never the body.
			var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if socket.was_string_packet() else null
			var raw_type := str(raw.get("type", "")) if raw is Dictionary else ""
			print("CLIENT_LOBBY_CLOSING reason=", "schema" if message.is_empty() else "unexpected_reply", " type=", _word(raw_type, 32), " pending=", _pending.size(), " state=", state)
			socket.close(1008, "invalid response")
			break
		_answers[message.request_id] = message
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _lobby_close_logged and not identity.is_empty():
		_lobby_close_logged = true
		print("CLIENT_LOBBY_CLOSED code=", socket.get_close_code(), " reason=", _word(socket.get_close_reason().replace(" ", "_"), 60), " state=", state)
	if enet != null:
		network.poll()
	if _disconnect_pending:
		_disconnect_pending = false
		_clear_game()
		state = "LOBBY"
		room_left.emit()

func _send_auth(peer_id: int) -> void:
	if peer_id != 1:
		return
	_phase("AUTHENTICATING")
	var hello := compatibility()
	hello.merge({"type": "hello", "room_id": _admission.room_id, "launch_id": _admission.launch_id, "user_id": identity.user_id, "attempt_id": _attempt, "ticket": _admission.ticket})
	network.send_auth(1, JSON.stringify(hello).to_utf8_buffer())
	_admission.ticket = ""

func _authenticate(peer_id: int, bytes: PackedByteArray) -> void:
	var reply := Wire.decode(bytes, "res://schemas/admission_reply.schema.json", 4096)
	if peer_id != 1 or reply.is_empty() or reply.attempt_id != _attempt:
		_connection_lost("AUTH_FAILED")
		return
	network.complete_auth(1)

func _prepare(value: Dictionary) -> void:
	if not _valid_snapshot(value) or state not in ["CONNECTING", "AUTHENTICATING", "LOADING", "SYNCHRONIZING"]:
		_connection_lost("INVALID_SNAPSHOT")
		return
	_load_generation += 1
	var generation := _load_generation
	snapshot = value.duplicate(true)
	_phase("LOADING")
	if prepare_scene.is_valid():
		var loaded: Variant = await prepare_scene.call(snapshot.duplicate(true))
		if loaded != true:
			_connection_lost("LOAD_FAILED")
			return
	if generation != _load_generation or enet == null:
		return
	_phase("SYNCHRONIZING")
	net_node.loaded.rpc_id(1, int(value.revision))

func _confirm(value: Dictionary) -> void:
	if not _valid_snapshot(value) or state != "SYNCHRONIZING":
		_connection_lost("INVALID_SNAPSHOT")
		return
	var present := false
	for member in value.members:
		present = present or member.user_id == identity.user_id
	if not present:
		_connection_lost("INVALID_SNAPSHOT")
		return
	snapshot = value.duplicate(true)
	_phase("IN_ROOM")
	room_joined.emit(snapshot.duplicate(true))

func _roster(value: Dictionary) -> void:
	if state == "IN_ROOM" and _valid_snapshot(value) and int(value.revision) >= int(snapshot.revision):
		snapshot = value.duplicate(true)
		roster_changed.emit(snapshot.duplicate(true))

func _valid_snapshot(value: Dictionary) -> bool:
	return Validator.validate_file(value, "res://schemas/room_snapshot.schema.json") == "" and value.room_id == _admission.room_id

## Diagnostics print only short protocol words; anything else becomes "other".
static func _word(value: String, limit: int) -> String:
	if value == "":
		return "-"
	if value.length() > limit:
		return "other"
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-":
			return "other"
	return value

func _connection_lost(code: String) -> void:
	last_error = code
	_disconnect_pending = true

func _phase(value: String) -> void:
	state = value
	join_progress.emit(value)

func _clear_game() -> void:
	_load_generation += 1
	if enet != null:
		enet.close()
		enet = null
	network.multiplayer_peer = null
	if is_instance_valid(net_node):
		get_tree().root.remove_child(net_node)
		net_node.queue_free()
		net_node = null
	_admission.clear()
	snapshot.clear()
