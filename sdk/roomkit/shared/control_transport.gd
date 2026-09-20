extends RefCounted
const StrictJSON = preload("res://sdk/roomkit/shared/strict_json.gd")
const MAX_BODY := 65536
const MAX_BUFFER := (MAX_BODY + 4) * 2
const MAX_QUEUE := (MAX_BODY + 4) * 4
const MAX_DEPTH := 16
var error := ""
var _rx := PackedByteArray()
var _tx: Array[PackedByteArray] = []
var _offset := 0
var _pending := 0

func queue(message: Dictionary) -> bool:
	if error != "":
		return false
	if not _json_value(message, 0):
		return _fail("INVALID_JSON")
	var body := JSON.stringify(message, "", true, true).to_utf8_buffer()
	if body.size() == 0 or body.size() > MAX_BODY:
		return _fail("MESSAGE_TOO_LARGE")
	if not StrictJSON.valid(body.get_string_from_utf8(), MAX_DEPTH):
		return _fail("INVALID_JSON")
	if _pending + body.size() + 4 > MAX_QUEUE:
		return _fail("SEND_QUEUE_FULL")
	var frame := PackedByteArray()
	var size := body.size()
	frame.append_array(PackedByteArray([(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255]))
	frame.append_array(body)
	_tx.append(frame)
	_pending += frame.size()
	return true

func feed(bytes: PackedByteArray) -> Array:
	if error != "":
		return []
	if _rx.size() + bytes.size() > MAX_BUFFER:
		_fail("RECEIVE_BUFFER_FULL")
		return []
	_rx.append_array(bytes)
	var messages: Array = []
	while _rx.size() >= 4:
		var size := (int(_rx[0]) << 24) | (int(_rx[1]) << 16) | (int(_rx[2]) << 8) | int(_rx[3])
		if size <= 0 or size > MAX_BODY:
			_fail("INVALID_LENGTH")
			return []
		if _rx.size() < size + 4:
			break
		var body := _rx.slice(4, size + 4)
		_rx = _rx.slice(size + 4)
		if not _valid_utf8(body):
			_fail("INVALID_UTF8")
			return []
		var text := body.get_string_from_utf8()
		if not StrictJSON.valid(text, MAX_DEPTH):
			_fail("INVALID_JSON")
			return []
		var json := JSON.new()
		if json.parse(text) != OK or not json.data is Dictionary or not _json_value(json.data, 0):
			_fail("INVALID_JSON")
			return []
		messages.append(json.data)
	return messages

func pump(stream: StreamPeerTCP) -> Array:
	if error != "":
		return []
	var available := mini(stream.get_available_bytes(), MAX_BODY + 4)
	if available == 0:
		return []
	var result := stream.get_partial_data(available)
	if result[0] != OK:
		_fail("READ_FAILED")
		return []
	return feed(result[1])

func flush(stream: StreamPeer) -> bool:
	return flush_with_writer(func(bytes: PackedByteArray): return stream.put_partial_data(bytes))

func flush_with_writer(writer: Callable) -> bool:
	if error != "":
		return false
	# Bound per-poll work, including a writer which consumes one byte at a time.
	for iteration in range(64):
		if _tx.is_empty():
			break
		var bytes := _tx[0].slice(_offset)
		var result: Variant = writer.call(bytes)
		if not result is Array or result.size() != 2 or int(result[0]) != OK:
			return _fail("WRITE_FAILED")
		var written := int(result[1])
		if written < 0 or written > bytes.size():
			return _fail("WRITE_FAILED")
		if written == 0:
			break
		_offset += written
		_pending -= written
		if _offset == _tx[0].size():
			_tx.pop_front()
			_offset = 0
	return true

func pending_bytes() -> int:
	return _pending

func _fail(code: String) -> bool:
	error = code
	_rx.clear()
	_tx.clear()
	_pending = 0
	_offset = 0
	return false

static func _valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first := int(bytes[index])
		var count := 0
		var value := 0
		var minimum := 0
		if first < 128:
			index += 1
			continue
		elif first >= 194 and first <= 223:
			count = 1
			value = first & 31
			minimum = 128
		elif first >= 224 and first <= 239:
			count = 2
			value = first & 15
			minimum = 2048
		elif first >= 240 and first <= 244:
			count = 3
			value = first & 7
			minimum = 65536
		else:
			return false
		if index + count >= bytes.size():
			return false
		for offset in range(1, count + 1):
			var byte := int(bytes[index + offset])
			if byte < 128 or byte > 191:
				return false
			value = (value << 6) | (byte & 63)
		if value < minimum or value > 1114111 or (value >= 55296 and value <= 57343):
			return false
		index += count + 1
	return true

static func _json_value(value: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return false
	if value is Dictionary:
		for key in value:
			if (not key is String and not key is StringName) or not _json_value(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not _json_value(item, depth + 1):
				return false
		return true
	if value is float:
		return is_finite(value)
	return value == null or value is String or value is int or value is bool
