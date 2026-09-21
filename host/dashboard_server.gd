extends RefCounted
## Read-only, loopback-only operator surface. Explicit allowlists, never raw state.
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
var listener := TCPServer.new()
var peers: Array = []
var port := 0
var token := ""
var manager
var lobby
var service
var worker: Thread
var next_read := 0
var records: Array = []
var storage_state := "loading"
var storage_updated := 0
var result_count := 0
var started := Time.get_ticks_msec()
var access_file := ""
var html: PackedByteArray

func start(room_manager, lobby_server, result_service, requested_port: int = 28291) -> int:
	manager = room_manager
	lobby = lobby_server
	service = result_service
	html = FileAccess.get_file_as_bytes("res://host/dashboard.html")
	if html.is_empty():
		return ERR_FILE_NOT_FOUND
	var error := listener.listen(requested_port, "127.0.0.1")
	if error != OK:
		return error
	port = listener.get_local_port()
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	access_file = Paths.absolute("res://run/panel-access.json" if requested_port != 0 else "res://run/panel-test-" + str(port) + ".json")
	var file := FileAccess.open(access_file, FileAccess.WRITE)
	if file == null:
		listener.stop()
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify({"url": "http://127.0.0.1:" + str(port), "token": token, "pid": OS.get_process_id()}))
	file.close()
	return OK

func poll() -> void:
	_poll_results()
	while listener.is_connection_available():
		var peer := listener.take_connection()
		if peers.size() >= 16:
			peer.disconnect_from_host()
			continue
		peers.append({"peer": peer, "input": PackedByteArray(), "output": PackedByteArray(), "offset": 0, "started": Time.get_ticks_msec()})
	for connection in peers.duplicate():
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(connection.started) > 5000:
			_drop(connection)
			continue
		if connection.output.is_empty():
			var available := peer.get_available_bytes()
			if available > 0:
				if connection.input.size() + available > 4096:
					_drop(connection)
					continue
				var incoming := peer.get_data(available)
				if incoming[0] != OK:
					_drop(connection)
					continue
				connection.input.append_array(incoming[1])
				var request: String = connection.input.get_string_from_utf8()
				if "\r\n\r\n" in request:
					connection.output = respond(request)
		if not connection.output.is_empty():
			var sent := peer.put_partial_data(connection.output.slice(connection.offset, connection.offset + 131072))
			if sent[0] != OK:
				_drop(connection)
				continue
			connection.offset += int(sent[1])
			if connection.offset >= connection.output.size():
				_drop(connection)

func respond(request: String) -> PackedByteArray:
	var lines := request.split("\r\n")
	var parts := lines[0].split(" ")
	if parts.size() != 3 or parts[0] != "GET" or parts[2] != "HTTP/1.1":
		return _response(405, "text/plain", "Read only".to_utf8_buffer())
	var headers := {}
	for line in lines.slice(1):
		if line.is_empty():
			break
		var pair := line.split(":", true, 1)
		if pair.size() != 2 or headers.has(pair[0].to_lower()):
			return _response(400, "text/plain", PackedByteArray())
		headers[pair[0].to_lower()] = pair[1].strip_edges()
	var authority := "127.0.0.1:" + str(port)
	if headers.get("host", "") != authority or headers.get("origin", "http://" + authority) != "http://" + authority:
		return _response(403, "text/plain", PackedByteArray())
	if headers.has("transfer-encoding") or headers.get("content-length", "0") != "0":
		return _response(400, "text/plain", PackedByteArray())
	if parts[1] == "/" or parts[1] == "/index.html":
		return _response(200, "text/html; charset=utf-8", html)
	if parts[1] != "/api/status":
		return _response(404, "text/plain", PackedByteArray())
	if headers.get("authorization", "") != "Bearer " + token:
		return _response(401, "text/plain", "Open StartPanel.cmd on this computer".to_utf8_buffer())
	return _response(200, "application/json; charset=utf-8", JSON.stringify(snapshot()).to_utf8_buffer())

func snapshot() -> Dictionary:
	var room_rows: Array = []
	var players: Array = []
	var now := Time.get_ticks_msec()
	var active := 0
	for row in manager.rooms.values():
		if not row.cleaned:
			active += 1
		room_rows.append({"room_id": row.room_id, "game_id": row.game_id, "state": row.state, "code": row.code, "pid": row.pid, "port": row.port, "capacity": row.capacity, "players": lobby.admissions.count(row.room_id, "CONNECTED"), "reserved": lobby.admissions.count(row.room_id) - lobby.admissions.count(row.room_id, "CONNECTED"), "heartbeats": row.heartbeats, "heartbeat_age_ms": now - int(row.last_heartbeat) if row.last_heartbeat > 0 and not row.cleaned else -1, "memory_bytes": row.get("metrics", {}).get("working_set_bytes", -1), "cpu_ms": row.get("metrics", {}).get("cpu_ms", -1), "cleaned": row.cleaned})
	for seat in lobby.admissions.seats.values():
		players.append({"user_id": seat.user_id, "display_name": seat.display_name, "game_id": seat.game_id, "room_id": seat.room_id, "state": seat.state})
	room_rows.reverse()
	# Keep every active room visible even after a long sequence of stopped rooms.
	room_rows = room_rows.filter(func(row): return not row.cleaned) + room_rows.filter(func(row): return row.cleaned)
	return {"version": 1, "host": {"engine": Engine.get_version_info().string, "pid": OS.get_process_id(), "uptime_ms": now - started, "sampled_at": Time.get_unix_time_from_system(), "engine_memory_bytes": OS.get_static_memory_usage() if OS.get_static_memory_usage() > 0 else -1, "active_rooms": active, "room_history_total": manager.rooms.size(), "online_players": players.filter(func(p): return p.state == "CONNECTED").size(), "lobby_sessions": lobby.peers.filter(func(p): return not p.user.is_empty()).size(), "control_port": manager.control_port, "lobby_port": lobby.port, "quarantined_ports": manager.recovery_guard.orphans.size() if manager.recovery_guard != null else 0}, "rooms": room_rows.slice(0, 128), "players": players, "storage": {"state": storage_state, "updated_at": storage_updated, "total": result_count, "records": records}}

func _poll_results() -> void:
	if worker != null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		storage_state = "ready" if result.get("ok", false) else "error"
		if storage_state == "ready":
			storage_updated = int(Time.get_unix_time_from_system())
			result_count = int(result.count)
			records.clear()
			for row in result.rows:
				var body: Variant = JSON.parse_string(row.body)
				if not body is Dictionary:
					continue
				var scores: Array = []
				var submitted_players: Variant = body.get("payload", {}).get("players", [])
				if not submitted_players is Array:
					submitted_players = []
				for player in submitted_players:
					if player is Dictionary and player.has("user_id") and player.user_id is String and (player.get("score", 0) is float or player.get("score", 0) is int):
						scores.append({"user_id": player.user_id, "score": player.get("score", 0)})
				records.append({"game_id": body.game_id, "match_id": body.match_id, "status": body.status, "players": scores})
	if service == null or worker != null or Time.get_ticks_msec() < next_read:
		return
	next_read = Time.get_ticks_msec() + 5000
	worker = Thread.new()
	if worker.start(_read_results.bind(service.repository.root, service.repository.database)) != OK:
		worker = null
		storage_state = "error"

static func _read_results(root: String, database: String) -> Dictionary:
	var repository = preload("res://host/storage/sqlite_repository.gd").new()
	repository.root = root
	repository.database = database
	return repository.execute({"op": "inspect"})

func _response(status: int, content_type: String, body: PackedByteArray) -> PackedByteArray:
	var header := "HTTP/1.1 %d Response\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'\r\n\r\n" % [status, content_type, body.size()]
	return header.to_utf8_buffer() + body

func _drop(connection: Dictionary) -> void:
	connection.peer.disconnect_from_host()
	peers.erase(connection)

func close() -> void:
	listener.stop()
	for connection in peers.duplicate():
		_drop(connection)
	if worker != null:
		worker.wait_to_finish()
		worker = null
	if not access_file.is_empty():
		DirAccess.remove_absolute(access_file)
	token = ""
	manager = null
	lobby = null
	service = null
