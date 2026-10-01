extends RefCounted
## Authenticated loopback RPC for the operator and its exact managed host launch.
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
signal requested(peer_id: String, request_id: String, action: String, payload: Dictionary)
signal event_received(action: String, payload: Dictionary)
signal peer_event(peer_id: String, action: String, payload: Dictionary)
var listener: TCPServer
var peers: Dictionary = {}
var pending: Dictionary = {}
var token := ""
var launch_id := ""
var port := 0
var client_id := ""
var last_error := ""

func listen(secret: String, launch: String, listen_port: int = 0) -> int:
	token = secret
	launch_id = launch
	listener = TCPServer.new()
	var result := listener.listen(listen_port, "127.0.0.1")
	if result == OK:
		port = listener.get_local_port()
	return result

func connect_to(server_port: int, secret: String, launch: String) -> int:
	port = server_port
	token = secret
	launch_id = launch
	client_id = Wire.uid()
	var tcp := StreamPeerTCP.new()
	var result := tcp.connect_to_host("127.0.0.1", port)
	peers[client_id] = _peer(tcp, false)
	return result

func _peer(tcp: StreamPeerTCP, server_side: bool) -> Dictionary:
	return {"tcp": tcp, "codec": Transport.new(), "authenticated": false, "hello_sent": false, "server": server_side, "created": Time.get_ticks_msec(), "last": Time.get_ticks_msec(), "heartbeat": 0}

func poll() -> void:
	if listener != null:
		while listener.is_connection_available():
			var tcp := listener.take_connection()
			if peers.size() >= 16:
				tcp.disconnect_from_host()
			else:
				peers[Wire.uid()] = _peer(tcp, true)
	var now := Time.get_ticks_msec()
	for id in peers.keys():
		var peer: Dictionary = peers[id]
		peer.tcp.poll()
		if peer.tcp.get_status() == StreamPeerTCP.STATUS_NONE or peer.tcp.get_status() == StreamPeerTCP.STATUS_ERROR or now - int(peer.last) > 30000:
			_drop(id)
			continue
		if not peer.authenticated and now - int(peer.created) > 5000:
			_drop(id)
			continue
		if peer.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if not peer.server and not peer.hello_sent:
			peer.codec.queue({"version": 1, "kind": "hello", "token": token, "launch_id": launch_id})
			peer.hello_sent = true
		for message in peer.codec.pump(peer.tcp):
			if Validator.validate_file(message, "res://schemas/local_rpc.schema.json") != "":
				_drop(id)
				break
			if not peer.authenticated:
				if peer.server and message.kind == "hello" and message.token == token and message.launch_id == launch_id:
					peer.authenticated = true
					peer.codec.queue({"version": 1, "kind": "hello_ok"})
				elif not peer.server and message.kind == "hello_ok":
					peer.authenticated = true
				else:
					_drop(id)
					break
			else:
				match message.kind:
					"request": requested.emit(id, message.id, message.action, message.payload)
					"response":
						if pending.has(message.id) and pending[message.id].peer == id:
							pending[message.id].result = message.payload
					"event":
						event_received.emit(message.action, message.payload)
						peer_event.emit(id, message.action, message.payload)
					"heartbeat": pass
					_:
						_drop(id)
						break
			peer.last = now
		if not peers.has(id):
			continue
		if peer.authenticated and now - int(peer.heartbeat) > 1000:
			peer.codec.queue({"version": 1, "kind": "heartbeat"})
			peer.heartbeat = now
		if not peer.codec.flush(peer.tcp):
			_drop(id)

func ready() -> bool:
	return peers.has(client_id) and peers[client_id].authenticated

func request(action: String, payload: Dictionary, timeout_ms: int = 60000, peer_id: String = "", cancel: Callable = Callable()) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	var target := client_id if peer_id == "" else peer_id
	while peers.has(target) and not peers[target].authenticated and Time.get_ticks_msec() < deadline:
		if cancel.is_valid() and cancel.call():
			return Wire.failure("CONTROL_UNAVAILABLE")
		await Engine.get_main_loop().process_frame
	if cancel.is_valid() and cancel.call():
		return Wire.failure("CONTROL_UNAVAILABLE")
	var id := _begin(target, action, payload)
	if id == "":
		return Wire.failure("CONTROL_UNAVAILABLE")
	var cancellation_sent := false
	while pending.has(id) and not pending[id].has("result") and Time.get_ticks_msec() < deadline:
		if not cancellation_sent and cancel.is_valid() and cancel.call():
			cancellation_sent = true
			if peers.has(target) and peers[target].authenticated:
				peers[target].codec.queue({"version": 1, "kind": "event", "action": "request.cancel", "payload": {"request_id": id}})
			# Keep awaiting the original result: execution may already have begun.
			# An abandoned successful login still needs its token for clean-up.
			# Cancellation is neither a retry nor a rollback promise.
		await Engine.get_main_loop().process_frame
	var result: Dictionary = pending.get(id, {}).get("result", Wire.failure("CONTROL_UNAVAILABLE"))
	pending.erase(id)
	return result

func blocking_request(action: String, payload: Dictionary, timeout_ms: int = 30000) -> Dictionary:
	# Only for an isolated worker with its own connection; never the Godot polling thread.
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not ready() and peers.has(client_id) and Time.get_ticks_msec() < deadline:
		poll()
		OS.delay_msec(2)
	var id := _begin(client_id, action, payload)
	if id == "":
		return Wire.failure("CONTROL_UNAVAILABLE")
	while pending.has(id) and not pending[id].has("result") and Time.get_ticks_msec() < deadline:
		poll()
		OS.delay_msec(2)
	var result: Dictionary = pending.get(id, {}).get("result", Wire.failure("CONTROL_UNAVAILABLE"))
	pending.erase(id)
	return result

func _begin(target: String, action: String, payload: Dictionary) -> String:
	if not peers.has(target) or not peers[target].authenticated or pending.size() >= 64:
		return ""
	var id := Wire.uid()
	if not peers[target].codec.queue({"version": 1, "kind": "request", "id": id, "action": action, "payload": payload}):
		return ""
	pending[id] = {"peer": target}
	return id

func respond(peer_id: String, id: String, result: Dictionary) -> void:
	if peers.has(peer_id) and peers[peer_id].authenticated:
		peers[peer_id].codec.queue({"version": 1, "kind": "response", "id": id, "payload": result})

func broadcast(action: String, payload: Dictionary) -> void:
	for peer in peers.values():
		if peer.authenticated:
			peer.codec.queue({"version": 1, "kind": "event", "action": action, "payload": payload})

func _drop(id: String) -> void:
	if peers.has(id):
		peers[id].tcp.disconnect_from_host()
		peers.erase(id)
	for request_id in pending:
		if pending[request_id].peer == id:
			pending[request_id].result = Wire.failure("CONTROL_UNAVAILABLE")

func close() -> void:
	for id in peers.keys():
		_drop(id)
	if listener != null:
		listener.stop()
