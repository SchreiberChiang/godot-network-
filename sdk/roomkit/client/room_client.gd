extends Node
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const NetRoom = preload("res://sdk/roomkit/shared/net_room.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
# Godot 4.7.2 / bundled ENet: packet loss is a smoothed reliable-send estimate.
# protocol.c initializes the epoch before the first completed interval; elapsed
# wall time or the initial zero alone does NOT establish a measured 0% loss.
const DIAGNOSTIC_INTERVAL_MS := 1000
const DIAGNOSTIC_WINDOW_MS := 30000
const DIAGNOSTIC_MIN_PERCENTILE_SAMPLES := 10
const DIAGNOSTIC_MAX_RTT_SAMPLES := 31
const RELIABLE_LOSS_EPOCH_MS := 10000
const DIAGNOSTIC_PHASES := ["CLOSED", "CONNECTING_LOBBY", "AUTHENTICATING_ACCOUNT", "LOBBY", "CONNECTING", "AUTHENTICATING", "LOADING", "SYNCHRONIZING", "IN_ROOM"]
const DIAGNOSTIC_ERRORS := ["AUTH_FAILED", "CONTROL_UNAVAILABLE", "DISCONNECTED", "INVALID_SNAPSHOT", "LOAD_FAILED", "LOAD_TIMEOUT", "INVALID_RESPONSE", "UNEXPECTED_REPLY", "INVALID_OPTIONS", "RATE_LIMITED", "ALREADY_IN_ROOM", "ALREADY_CONNECTED", "ROOM_NOT_FOUND", "ROOM_FULL", "ROOM_NOT_READY", "ROOM_STOPPED", "TICKET_EXPIRED", "VERSION_MISMATCH", "BUILD_MISMATCH", "AUTH_REQUIRED"]
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
var _diagnostic_cache: Dictionary = {}
var _diagnostic_host_id := 0
var _diagnostic_peer_id := 0
var _diagnostic_collected_ms := -1
var _diagnostic_rtt_samples: Array[Dictionary] = []
var _diagnostic_loss_epoch := -1
var _diagnostic_error := "NONE"

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
		return _failure("INVALID_OPTIONS")
	_diagnostic_error = "NONE"
	last_error = ""
	_reset_network_diagnostics()
	socket.inbound_buffer_size = 65536
	socket.outbound_buffer_size = 65536
	socket.max_queued_packets = 32
	var tls: TLSOptions
	if str(config.url).begins_with("wss:"):
		tls = Secure.client_options(config.ca_certificate, config.get("server_hostname", ""))
		if tls == null:
			return _failure("AUTH_FAILED")
	if socket.connect_to_url(config.url, tls) != OK:
		return _failure("CONTROL_UNAVAILABLE")
	state = "CONNECTING_LOBBY"
	var deadline := Time.get_ticks_msec() + 6000
	while socket.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		state = "CLOSED"
		return _failure("CONTROL_UNAVAILABLE")
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
		return _failure("ALREADY_IN_ROOM")
	var payload := compatibility()
	payload.room_id = room_id
	var reserved: Dictionary = await _request("room.reserve", payload)
	if not reserved.ok:
		return reserved
	return await _connect_reserved(reserved.payload)

func _connect_reserved(admission: Dictionary) -> Dictionary:
	_reset_network_diagnostics()
	_diagnostic_error = "NONE"
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
		_diagnostic_error = "CONTROL_UNAVAILABLE"
		_clear_game()
		return _failure("CONTROL_UNAVAILABLE")
	if config.get("secure_enet", false):
		var tls := Secure.client_options(config.ca_certificate)
		if tls == null or enet.host.dtls_client_setup(config.get("server_hostname", "localhost"), tls) != OK:
			_diagnostic_error = "AUTH_FAILED"
			_clear_game()
			return _failure("AUTH_FAILED")
	network.multiplayer_peer = enet
	_phase("CONNECTING")
	var deadline := Time.get_ticks_msec() + (60000 if config.get("managed", false) else 14000)
	while state != "IN_ROOM" and last_error == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if state == "IN_ROOM":
		return {"ok": true, "payload": snapshot.duplicate(true)}
	var code := last_error if last_error != "" else "LOAD_TIMEOUT"
	_diagnostic_error = diagnostic_error_category(code)
	print("CLIENT_ROOM_JOIN_FAILED code=", diagnostic_error_category(code), " phase=", diagnostic_phase_category(state), " lobby_open=", socket.get_ready_state() == WebSocketPeer.STATE_OPEN)
	_clear_game()
	state = "LOBBY"
	request_failed.emit(code)
	return _failure(code)

func leave_room() -> void:
	if enet != null and network.get_peers().has(1):
		net_node.leave.rpc_id(1)
		# Flush the reliable leave before closing; disconnect also releases the seat.
		await get_tree().create_timer(0.15).timeout
	_clear_game()
	state = "LOBBY" if not identity.is_empty() else "CLOSED"
	room_left.emit()

## Read-only shared cache. Unknown metrics are -1; a measured zero stays zero.
## p50/p95 describe once-per-second observations of ENet's smoothed RTT over
## 30 seconds, NOT packet RTT percentiles. No packet probes or transport changes.
func diagnostics_snapshot() -> Dictionary:
	var value := _diagnostic_cache.duplicate(true) if _diagnostics_cache_is_current() else _empty_network_diagnostics()
	if value.is_empty():
		value = _empty_network_diagnostics()
	value.phase = diagnostic_phase_category(state)
	value.error = _diagnostic_error
	return value

## ENet's reliable-packet round trip time, not a one-way or lobby delay.
## This reader must not consume counters or force additional collection.
func room_round_trip_ms() -> float:
	return float(diagnostics_snapshot().rtt_ms)

static func diagnostic_phase_category(value: String) -> String:
	return value if value in DIAGNOSTIC_PHASES else "OTHER"

static func diagnostic_error_category(value: String) -> String:
	if value.is_empty() or value == "NONE":
		return "NONE"
	return value if value in DIAGNOSTIC_ERRORS else "OTHER"

static func _lobby_close_category(code: int) -> String:
	match code:
		1000: return "NORMAL"
		1001: return "GOING_AWAY"
		1002: return "PROTOCOL_ERROR"
		1003: return "UNSUPPORTED_DATA"
		1006, -1: return "ABNORMAL_CLOSE"
		1007: return "INVALID_PAYLOAD"
		1008: return "POLICY_VIOLATION"
		1009: return "MESSAGE_TOO_BIG"
		1011: return "SERVER_ERROR"
		1012: return "SERVICE_RESTART"
		1013: return "TRY_AGAIN_LATER"
		1015: return "TLS_ERROR"
		_: return "OTHER"

static func _empty_network_diagnostics() -> Dictionary:
	return {"rtt_ms": -1.0, "rtt_variance_ms": -1.0, "reliable_loss_percent": -1.0,
		"tx_bytes_per_sec": -1.0, "rx_bytes_per_sec": -1.0,
		"rtt_p50_ms": -1.0, "rtt_p95_ms": -1.0, "sample_count": 0,
		"rtt_sample_count": 0, "loss_sample_count": 0, "transport_sample_count": 0,
		"loss_state": "unavailable", "window_ms": DIAGNOSTIC_WINDOW_MS, "sample_mono_ms": -1}

func _reset_network_diagnostics() -> void:
	_diagnostic_cache = _empty_network_diagnostics()
	_diagnostic_host_id = 0
	_diagnostic_peer_id = 0
	_diagnostic_collected_ms = -1
	_diagnostic_rtt_samples.clear()
	_diagnostic_loss_epoch = -1

func _diagnostics_transport_ready() -> bool:
	if state != "IN_ROOM" or _disconnect_pending or enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var peer := enet.get_peer(1)
	return peer != null and peer.is_active() and peer.get_state() == ENetPacketPeer.STATE_CONNECTED

func _diagnostics_cache_is_current() -> bool:
	if not _diagnostics_transport_ready() or enet.host == null:
		return false
	return _diagnostic_host_id == enet.host.get_instance_id() and _diagnostic_peer_id == enet.get_peer(1).get_instance_id()

## The sole destructive host-counter reader. Runs from _process after poll;
## HUD, logging, and the compatibility RTT getter only copy its cached result.
func _collect_network_diagnostics(now_ms: int) -> void:
	if not _diagnostics_transport_ready():
		if _diagnostic_host_id != 0 or _diagnostic_collected_ms >= 0:
			_reset_network_diagnostics()
		return
	var peer := enet.get_peer(1)
	var host := enet.host
	if host == null:
		_reset_network_diagnostics()
		return
	if _diagnostic_host_id != host.get_instance_id() or _diagnostic_peer_id != peer.get_instance_id():
		_reset_network_diagnostics()
		_diagnostic_host_id = host.get_instance_id()
		_diagnostic_peer_id = peer.get_instance_id()
	if _diagnostic_collected_ms >= 0 and now_ms - _diagnostic_collected_ms < DIAGNOSTIC_INTERVAL_MS:
		return
	# ENet host totals include protocol headers and retransmissions, not just
	# game payload. pop_statistic resets only its own counter, never the peer.
	var tx_bytes := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var rx_bytes := host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	_accept_network_observation(now_ms,
		peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
		peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
		peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS),
		int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS_EPOCH)), tx_bytes, rx_bytes)

## Reduction is kept separate from the transport for deterministic edge tests.
## Variance is ENet's smoothed absolute RTT deviation in ms; do not sqrt it.
func _accept_network_observation(now_ms: int, rtt_ms: float, variance_ms: float, raw_loss: float, loss_epoch: int, tx_bytes: float, rx_bytes: float) -> void:
	if _diagnostic_collected_ms >= 0 and now_ms - _diagnostic_collected_ms < DIAGNOSTIC_INTERVAL_MS:
		return
	if _diagnostic_cache.is_empty():
		_diagnostic_cache = _empty_network_diagnostics()
	var elapsed_ms := now_ms - _diagnostic_collected_ms if _diagnostic_collected_ms >= 0 else -1
	_diagnostic_collected_ms = now_ms
	_diagnostic_cache.sample_mono_ms = now_ms
	_diagnostic_cache.sample_count += 1
	_diagnostic_cache.loss_state = "collecting" if int(_diagnostic_cache.loss_sample_count) == 0 else "available"
	if elapsed_ms > 0 and is_finite(tx_bytes) and is_finite(rx_bytes) and tx_bytes >= 0.0 and rx_bytes >= 0.0:
		_diagnostic_cache.tx_bytes_per_sec = tx_bytes * 1000.0 / elapsed_ms
		_diagnostic_cache.rx_bytes_per_sec = rx_bytes * 1000.0 / elapsed_ms
		_diagnostic_cache.transport_sample_count += 1
	else:
		_diagnostic_cache.tx_bytes_per_sec = -1.0
		_diagnostic_cache.rx_bytes_per_sec = -1.0
	_diagnostic_cache.rtt_ms = rtt_ms if is_finite(rtt_ms) and rtt_ms >= 0.0 else -1.0
	_diagnostic_cache.rtt_variance_ms = variance_ms if is_finite(variance_ms) and variance_ms >= 0.0 else -1.0
	if float(_diagnostic_cache.rtt_ms) >= 0.0:
		_diagnostic_rtt_samples.append({"at_ms": now_ms, "rtt_ms": rtt_ms})
	while not _diagnostic_rtt_samples.is_empty() and (now_ms - int(_diagnostic_rtt_samples[0].at_ms) >= DIAGNOSTIC_WINDOW_MS or _diagnostic_rtt_samples.size() > DIAGNOSTIC_MAX_RTT_SAMPLES):
		_diagnostic_rtt_samples.pop_front()
	_diagnostic_cache.rtt_sample_count = _diagnostic_rtt_samples.size()
	_diagnostic_cache.rtt_p50_ms = -1.0
	_diagnostic_cache.rtt_p95_ms = -1.0
	if _diagnostic_rtt_samples.size() >= DIAGNOSTIC_MIN_PERCENTILE_SAMPLES:
		var ordered: Array[float] = []
		for sample in _diagnostic_rtt_samples:
			ordered.append(float(sample.rtt_ms))
		ordered.sort()
		_diagnostic_cache.rtt_p50_ms = ordered[int(ceil(ordered.size() * 0.50)) - 1]
		_diagnostic_cache.rtt_p95_ms = ordered[int(ceil(ordered.size() * 0.95)) - 1]
	_observe_reliable_loss(raw_loss, loss_epoch)

func _observe_reliable_loss(raw_loss: float, loss_epoch: int) -> void:
	# ENet's epoch is an opaque wrapping uint32 host clock, not our monotonic
	# clock. Never compare it to Time.get_ticks_msec() or infer loss from ticks.
	if loss_epoch <= 0:
		_diagnostic_loss_epoch = -1
		_diagnostic_cache.reliable_loss_percent = -1.0
		_diagnostic_cache.loss_sample_count = 0
		_diagnostic_cache.loss_state = "collecting"
		return
	if _diagnostic_loss_epoch < 0:
		_diagnostic_loss_epoch = loss_epoch
		return
	var elapsed_epoch := (loss_epoch - _diagnostic_loss_epoch) & 0xffffffff
	if elapsed_epoch == 0:
		return
	_diagnostic_loss_epoch = loss_epoch
	if elapsed_epoch < RELIABLE_LOSS_EPOCH_MS or elapsed_epoch >= 0x80000000:
		# Unexpected epoch regression/reset cannot inherit a previous estimate.
		_diagnostic_cache.reliable_loss_percent = -1.0
		_diagnostic_cache.loss_sample_count = 0
		_diagnostic_cache.loss_state = "collecting"
		return
	if not is_finite(raw_loss) or raw_loss < 0.0 or raw_loss > ENetPacketPeer.PACKET_LOSS_SCALE:
		return
	_diagnostic_cache.reliable_loss_percent = raw_loss / float(ENetPacketPeer.PACKET_LOSS_SCALE) * 100.0
	_diagnostic_cache.loss_sample_count += 1
	_diagnostic_cache.loss_state = "available"

func close() -> void:
	_clear_game()
	last_error = ""
	_diagnostic_error = "NONE"
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
		return _failure("CONTROL_UNAVAILABLE")
	var message := Wire.request(type, payload, key)
	if Validator.validate_file(message, request_schema) != "":
		return _failure("INVALID_OPTIONS")
	if _pending.size() >= 32:
		return _failure("RATE_LIMITED")
	_pending[message.request_id] = type
	if socket.send_text(JSON.stringify(message)) != OK:
		_pending.erase(message.request_id)
		return _failure("CONTROL_UNAVAILABLE")
	var deadline := Time.get_ticks_msec() + (60000 if config.get("managed", false) else 10000)
	while not _answers.has(message.request_id) and Time.get_ticks_msec() < deadline and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		await get_tree().process_frame
	_pending.erase(message.request_id)
	if not _answers.has(message.request_id):
		return _failure("CONTROL_UNAVAILABLE")
	var answer: Dictionary = _answers[message.request_id]
	_answers.erase(message.request_id)
	if not answer.ok:
		_diagnostic_error = diagnostic_error_category(str(answer.get("error", {}).get("code", "")))
	elif type in ["account.login", "session.create"]:
		_diagnostic_error = "NONE"
	return {"ok": answer.ok, "payload": answer.payload, "code": answer.get("error", {}).get("code", "")}

func _failure(code: String) -> Dictionary:
	_diagnostic_error = diagnostic_error_category(code)
	return Wire.failure(code)

func _process(_delta: float) -> void:
	socket.poll()
	var budget := 16
	while socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var bytes := socket.get_packet()
		var message := Wire.decode(bytes, response_schema) if socket.was_string_packet() else {}
		if message.is_empty() or _pending.get(message.get("request_id", ""), "") != message.get("type", ""):
			# Neither arbitrary reply fields nor a sanitized close reason are safe.
			_diagnostic_error = "INVALID_RESPONSE" if message.is_empty() else "UNEXPECTED_REPLY"
			print("CLIENT_LOBBY_CLOSING reason=", _diagnostic_error, " pending=", _pending.size(), " state=", diagnostic_phase_category(state))
			socket.close(1008, "invalid response")
			break
		_answers[message.request_id] = message
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _lobby_close_logged and not identity.is_empty():
		_lobby_close_logged = true
		if _diagnostic_error == "NONE":
			_diagnostic_error = "CONTROL_UNAVAILABLE"
		print("CLIENT_LOBBY_CLOSED category=", _lobby_close_category(socket.get_close_code()), " state=", diagnostic_phase_category(state))
	if enet != null:
		network.poll()
	_collect_network_diagnostics(Time.get_ticks_msec())
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

func _connection_lost(code: String) -> void:
	last_error = code
	_diagnostic_error = diagnostic_error_category(code)
	_disconnect_pending = true
	_reset_network_diagnostics()

func _phase(value: String) -> void:
	state = value
	join_progress.emit(value)

func _clear_game() -> void:
	_reset_network_diagnostics()
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
