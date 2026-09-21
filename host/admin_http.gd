extends RefCounted
## Bounded loopback HTTP transport. Authorization and mutations belong to the service.
signal request_received(request_id: String, request: Dictionary)
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const StrictJSON = preload("res://sdk/roomkit/shared/strict_json.gd")
const MAX_HEADER := 8192
const MAX_BODY := 16384
const MAX_RESPONSE := 2097152
const MAX_CLIENTS := 16
const READ_TIMEOUT_MS := 5000
const REQUEST_TIMEOUT_MS := 60000
const WRITE_TIMEOUT_MS := 10000
var listener := TCPServer.new()
var peers: Array = []
var port := 0
var html := PackedByteArray()

func start(requested_port: int = 28291) -> int:
	if listener.is_listening():
		return ERR_ALREADY_IN_USE
	html = FileAccess.get_file_as_bytes("res://host/admin.html")
	if html.is_empty():
		return ERR_FILE_NOT_FOUND
	var error := listener.listen(requested_port, "127.0.0.1")
	if error == OK:
		port = listener.get_local_port()
	return error

func poll() -> void:
	while listener.is_connection_available():
		var peer := listener.take_connection()
		if peers.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		peers.append({"peer": peer, "input": PackedByteArray(), "output": PackedByteArray(), "offset": 0, "started": Time.get_ticks_msec(), "phase": "read", "request_id": "", "header_size": 0, "length": 0, "headers": {}, "method": "", "path": ""})
	for connection in peers.duplicate():
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(connection)
			continue
		var elapsed := Time.get_ticks_msec() - int(connection.started)
		if connection.phase == "read":
			if elapsed > READ_TIMEOUT_MS:
				_reject(connection, 408, "REQUEST_TIMEOUT")
			else:
				_read(connection)
		elif connection.phase == "pending" and elapsed > REQUEST_TIMEOUT_MS:
			_reject(connection, 504, "OPERATION_TIMEOUT")
		elif connection.phase == "write" and elapsed > WRITE_TIMEOUT_MS:
			_drop(connection)
		if connection.phase == "write" and connection in peers:
			var result := peer.put_partial_data(connection.output.slice(connection.offset, connection.offset + 65536))
			if result[0] != OK:
				_drop(connection)
				continue
			connection.offset += int(result[1])
			if connection.offset >= connection.output.size():
				_drop(connection)

func _read(connection: Dictionary) -> void:
	var peer: StreamPeerTCP = connection.peer
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	if connection.input.size() + available > MAX_HEADER + MAX_BODY:
		_reject(connection, 413, "REQUEST_TOO_LARGE")
		return
	var received := peer.get_data(available)
	if received[0] != OK:
		_drop(connection)
		return
	connection.input.append_array(received[1])
	if connection.header_size == 0:
		var header_end := _header_end(connection.input)
		if header_end < 0:
			if connection.input.size() > MAX_HEADER:
				_reject(connection, 431, "HEADERS_TOO_LARGE")
			return
		if header_end + 4 > MAX_HEADER:
			_reject(connection, 431, "HEADERS_TOO_LARGE")
			return
		if not _parse_header(connection, connection.input.slice(0, header_end)):
			return
		connection.header_size = header_end + 4
	var expected: int = connection.header_size + connection.length
	if connection.input.size() < expected:
		return
	if connection.input.size() != expected:
		_reject(connection, 400, "ONE_REQUEST_PER_CONNECTION")
		return
	if connection.method == "GET":
		_queue(connection, 200, "text/html; charset=utf-8", html)
		return
	var body_bytes: PackedByteArray = connection.input.slice(connection.header_size)
	var body := Wire.decode(body_bytes, "res://schemas/admin_request.schema.json", MAX_BODY)
	if body.is_empty() or not _unique_keys(body_bytes.get_string_from_utf8()):
		_reject(connection, 400, "INVALID_REQUEST")
		return
	var authorization: String = connection.headers.get("authorization", "")
	var token := ""
	if not authorization.is_empty():
		if not authorization.begins_with("Bearer ") or authorization.length() > 263:
			_reject(connection, 401, "AUTH_FAILED")
			return
		token = authorization.substr(7)
		if token.is_empty() or token.contains(" ") or token.contains("\t"):
			_reject(connection, 401, "AUTH_FAILED")
			return
	connection.input.clear()
	connection.phase = "pending"
	connection.started = Time.get_ticks_msec()
	connection.request_id = Wire.uid()
	request_received.emit(connection.request_id, {"action": body.action, "payload": body.payload, "token": token, "remote_ip": peer.get_connected_host()})

func _parse_header(connection: Dictionary, bytes: PackedByteArray) -> bool:
	for byte in bytes:
		if byte > 126 or (byte < 32 and byte not in [9, 10, 13]):
			_reject(connection, 400, "INVALID_HEADERS")
			return false
	var lines := bytes.get_string_from_ascii().split("\r\n")
	var first := lines[0].split(" ", true)
	if first.size() != 3 or first[2] != "HTTP/1.1":
		_reject(connection, 400, "INVALID_REQUEST_LINE")
		return false
	var headers := {}
	for line in lines.slice(1):
		var pair := line.split(":", true, 1)
		if pair.size() != 2 or pair[0].is_empty() or headers.has(pair[0].to_lower()):
			_reject(connection, 400, "INVALID_HEADERS")
			return false
		for character in pair[0]:
			if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-":
				_reject(connection, 400, "INVALID_HEADERS")
				return false
		if pair[1].contains("\r") or pair[1].contains("\n"):
			_reject(connection, 400, "INVALID_HEADERS")
			return false
		headers[pair[0].to_lower()] = pair[1].strip_edges()
	var authority := "127.0.0.1:" + str(port)
	if headers.get("host", "") != authority or headers.get("origin", "http://" + authority) != "http://" + authority:
		_reject(connection, 403, "ORIGIN_DENIED")
		return false
	if headers.has("transfer-encoding") or headers.has("expect"):
		_reject(connection, 400, "UNSUPPORTED_FRAMING")
		return false
	var content_length: String = headers.get("content-length", "0")
	if content_length.is_empty() or content_length.length() > 8:
		_reject(connection, 400, "INVALID_CONTENT_LENGTH")
		return false
	for character in content_length:
		if not character in "0123456789":
			_reject(connection, 400, "INVALID_CONTENT_LENGTH")
			return false
	var length := content_length.to_int()
	if length > MAX_BODY:
		_reject(connection, 413, "REQUEST_TOO_LARGE")
		return false
	if first[0] not in ["GET", "POST"]:
		_reject(connection, 405, "METHOD_NOT_ALLOWED")
		return false
	if (first[0] == "GET" and first[1] not in ["/", "/index.html"]) or (first[0] == "POST" and first[1] != "/api"):
		_reject(connection, 404, "NOT_FOUND")
		return false
	if (first[0] == "GET" and length != 0) or (first[0] == "POST" and (not headers.has("content-length") or length == 0)):
		_reject(connection, 400, "INVALID_CONTENT_LENGTH")
		return false
	if first[0] == "POST" and headers.get("content-type", "").to_lower() not in ["application/json", "application/json; charset=utf-8"]:
		_reject(connection, 415, "JSON_REQUIRED")
		return false
	connection.headers = headers
	connection.length = length
	connection.method = first[0]
	connection.path = first[1]
	return true

func respond(request_id: String, result: Dictionary, http_status: int = 200) -> void:
	for connection in peers:
		if connection.request_id == request_id and connection.phase == "pending":
			var body := JSON.stringify(result).to_utf8_buffer()
			if body.size() > MAX_RESPONSE:
				_reject(connection, 500, "RESPONSE_TOO_LARGE")
			else:
				_queue(connection, http_status if http_status in [200, 202, 400, 401, 403, 404, 409, 429, 500, 503] else 500, "application/json; charset=utf-8", body)
			return

func _reject(connection: Dictionary, status: int, code: String) -> void:
	_queue(connection, status, "application/json; charset=utf-8", JSON.stringify({"ok": false, "code": code}).to_utf8_buffer())

func _queue(connection: Dictionary, status: int, content_type: String, body: PackedByteArray) -> void:
	var header := "HTTP/1.1 %d Response\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n\r\n" % [status, content_type, body.size()]
	connection.output = header.to_utf8_buffer() + body
	connection.input.clear()
	connection.offset = 0
	connection.started = Time.get_ticks_msec()
	connection.phase = "write"

static func _header_end(bytes: PackedByteArray) -> int:
	for index in range(maxi(0, bytes.size() - MAX_BODY - MAX_HEADER), bytes.size() - 3):
		if bytes[index] == 13 and bytes[index + 1] == 10 and bytes[index + 2] == 13 and bytes[index + 3] == 10:
			return index
	return -1

static func _unique_keys(text: String) -> bool:
	# Wire.decode already verified JSON grammar, UTF8, depth and finite numbers.
	# Reject ambiguous object keys too, including differently escaped equivalents.
	var stack: Array = []
	var index := 0
	while index < text.length():
		var character := text[index]
		if character == "{" or character == "[":
			stack.append({} if character == "{" else null)
		elif character == "}" or character == "]":
			stack.pop_back()
		elif character == "\"":
			var end: int = StrictJSON._string(text, index)
			var next: int = StrictJSON._space(text, end)
			if next < text.length() and text[next] == ":":
				var key: Variant = JSON.parse_string(text.substr(index, end - index))
				if stack.is_empty() or not stack.back() is Dictionary or stack.back().has(key):
					return false
				stack.back()[key] = true
			index = end
			continue
		index += 1
	return true

func _drop(connection: Dictionary) -> void:
	connection.peer.disconnect_from_host()
	peers.erase(connection)

func close() -> void:
	listener.stop()
	for connection in peers.duplicate():
		_drop(connection)
	port = 0
