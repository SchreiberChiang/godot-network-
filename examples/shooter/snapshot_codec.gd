extends RefCounted
## Game-owned complete snapshots, never partial player lists. RPC must provide
## authority checks and use unreliable (unordered); this codec orders by serial.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const STATE_SCHEMA := "res://schemas/shooter_state.schema.json"
const HEADER_SCHEMA := "res://schemas/shooter_snapshot_header.schema.json"
const MAGIC := 0x524b5331
const VERSION := 1
const HEADER_BYTES := 36
const MAX_PACKET_BYTES := 1000
const CHUNK_BYTES := MAX_PACKET_BYTES - HEADER_BYTES
const MAX_RAW_BYTES := 512 * 1024
const MAX_ENCODED_BYTES := MAX_RAW_BYTES
const MAX_FRAGMENTS := 544
const MAX_IN_FLIGHT := 3
const FRAME_TTL_MS := 250
const UINT32_MAX := 0xffffffff
const FLAG_ZSTD := 1
var _stream_id := 0
var _accepted_serial := 0
var _retired_serial := 0
var _last_now := -1
var _frames: Dictionary = {}

static func encode(snapshot: Dictionary, serial: int, stream_id: int) -> Array[PackedByteArray]:
	var output: Array[PackedByteArray] = []
	if serial < 1 or serial > UINT32_MAX or stream_id < 1 or stream_id > UINT32_MAX:
		return output
	if Validator.validate_file(snapshot, STATE_SCHEMA) != "":
		return output
	# Normalize typed arrays/dictionaries and StringName to the ordinary Variant
	# subset accepted by the bounded decoder. This preserves schema semantics.
	var raw := var_to_bytes(_plain(snapshot))
	if raw.is_empty() or raw.size() > MAX_RAW_BYTES:
		return output
	var encoded := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var flags := FLAG_ZSTD
	if encoded.is_empty() or encoded.size() >= raw.size():
		encoded = raw
		flags = 0
	if encoded.size() > MAX_ENCODED_BYTES:
		return output
	var count := int(ceil(float(encoded.size()) / CHUNK_BYTES))
	for index in count:
		var packet := PackedByteArray()
		packet.resize(HEADER_BYTES)
		var fields := [MAGIC, VERSION, flags, stream_id, serial, raw.size(), encoded.size(), count, index]
		for field in fields.size():
			packet.encode_u32(field * 4, fields[field])
		packet.append_array(encoded.slice(index * CHUNK_BYTES, mini((index + 1) * CHUNK_BYTES, encoded.size())))
		output.append(packet)
	return output

func reset() -> void:
	_stream_id = 0
	_accepted_serial = 0
	_retired_serial = 0
	_last_now = -1
	_frames.clear()

func feed(packet: PackedByteArray, now_ms: int) -> Dictionary:
	if now_ms < 0 or now_ms < _last_now:
		return {}
	_last_now = now_ms
	_expire(now_ms)
	var header := _header(packet)
	if header.is_empty():
		return {}
	var stream: int = header.stream_id
	var serial: int = header.serial
	if _stream_id != 0 and stream != _stream_id:
		return {}
	if serial <= maxi(_accepted_serial, _retired_serial):
		return {}
	if _stream_id == 0:
		_stream_id = stream
	if not _frames.has(serial):
		if _frames.size() >= MAX_IN_FLIGHT:
			var oldest: int = _frames.keys().min()
			if serial <= oldest:
				_retire(serial)
				return {}
			_retire(oldest)
		_frames[serial] = {"header": header, "born": now_ms, "parts": {}}
	var frame: Dictionary = _frames[serial]
	for key in ["flags", "raw_size", "encoded_size", "count"]:
		if frame.header[key] != header[key]:
			_retire(serial)
			return {}
	var part := packet.slice(HEADER_BYTES)
	var index: int = header.index
	if frame.parts.has(index):
		if frame.parts[index] != part:
			_retire(serial)
		return {}
	frame.parts[index] = part
	if frame.parts.size() != int(header.count):
		return {}
	var encoded := PackedByteArray()
	for offset in int(header.count):
		encoded.append_array(frame.parts[offset])
	_frames.erase(serial)
	var raw := encoded
	if int(header.flags) == FLAG_ZSTD:
		# Allocation is the already-validated declared length, never an unbounded
		# size from the compressed frame. Godot errors on malformed Zstd are not
		# suppressed; callers/tests must record those expected rejection cases.
		raw = encoded.decompress(int(header.raw_size), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != int(header.raw_size) or not _valid_variant(raw):
		_retire(serial)
		return {}
	# Preflight excludes object types, oversized container counts, bad UTF-8,
	# truncated Variant data and non-finite numbers before the native decoder.
	var decoded: Variant = bytes_to_var(raw) # This Godot API never decodes objects.
	if not decoded is Dictionary or Validator.validate_file(decoded, STATE_SCHEMA) != "":
		_retire(serial)
		return {}
	_accepted_serial = serial
	_retire(serial)
	return decoded

static func _header(packet: PackedByteArray) -> Dictionary:
	if packet.size() <= HEADER_BYTES or packet.size() > MAX_PACKET_BYTES:
		return {}
	var names := ["magic", "version", "flags", "stream_id", "serial", "raw_size", "encoded_size", "count", "index"]
	var header: Dictionary = {}
	for field in names.size():
		header[names[field]] = packet.decode_u32(field * 4)
	if Validator.validate_file(header, HEADER_SCHEMA) != "":
		return {}
	var total: int = header.encoded_size
	var count := int(ceil(float(total) / CHUNK_BYTES))
	if int(header.count) != count or int(header.index) >= count:
		return {}
	var expected := mini(CHUNK_BYTES, total - int(header.index) * CHUNK_BYTES)
	if packet.size() != HEADER_BYTES + expected:
		return {}
	if (int(header.flags) == 0 and int(header.raw_size) != total) or (int(header.flags) == FLAG_ZSTD and total >= int(header.raw_size)):
		return {}
	return header

func _retire(serial: int) -> void:
	_retired_serial = maxi(_retired_serial, serial)
	for pending in _frames.keys():
		if int(pending) <= _retired_serial:
			_frames.erase(pending)

func _expire(now_ms: int) -> void:
	var expired := 0
	for serial in _frames:
		if now_ms - int(_frames[serial].born) >= FRAME_TTL_MS:
			expired = maxi(expired, int(serial))
	if expired > 0:
		_retire(expired)

static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_plain(item))
		return result
	return str(value) if value is StringName else value

static func _valid_variant(raw: PackedByteArray) -> bool:
	var budget := [20000]
	return _scan(raw, 0, 0, budget) == raw.size()

static func _scan(raw: PackedByteArray, start: int, depth: int, budget: Array) -> int:
	budget[0] -= 1
	if depth > 8 or int(budget[0]) < 0 or start + 4 > raw.size():
		return -1
	var header := raw.decode_u32(start)
	var type := header & 0xffff
	var flags := header >> 16
	if type == TYPE_BOOL:
		return start + 8 if flags == 0 and start + 8 <= raw.size() and raw.decode_u32(start + 4) <= 1 else -1
	if type == TYPE_INT or type == TYPE_FLOAT:
		var length := 8 if flags == 0 else 12
		if flags > 1 or start + length > raw.size():
			return -1
		if type == TYPE_FLOAT:
			var number := raw.decode_float(start + 4) if flags == 0 else raw.decode_double(start + 4)
			if not is_finite(number):
				return -1
		return start + length
	if type == TYPE_STRING:
		if flags != 0 or start + 8 > raw.size():
			return -1
		var length := raw.decode_u32(start + 4)
		var end := start + 8 + int(ceil(float(length) / 4.0)) * 4
		if end > raw.size() or not _utf8(raw, start + 8, length):
			return -1
		return end
	if type == TYPE_DICTIONARY or type == TYPE_ARRAY:
		if flags != 0 or start + 8 > raw.size():
			return -1
		var count := raw.decode_u32(start + 4)
		if count > 1024:
			return -1
		var cursor := start + 8
		for index in count * (2 if type == TYPE_DICTIONARY else 1):
			cursor = _scan(raw, cursor, depth + 1, budget)
			if cursor < 0:
				return -1
		return cursor
	return -1

static func _utf8(raw: PackedByteArray, start: int, length: int) -> bool:
	var end := start + length
	var cursor := start
	while cursor < end:
		var first := raw[cursor]
		cursor += 1
		if first < 0x80:
			continue
		var extra := 0
		var low := 0x80
		var high := 0xbf
		if first >= 0xc2 and first <= 0xdf:
			extra = 1
		elif first >= 0xe0 and first <= 0xef:
			extra = 2
			if first == 0xe0: low = 0xa0
			if first == 0xed: high = 0x9f
		elif first >= 0xf0 and first <= 0xf4:
			extra = 3
			if first == 0xf0: low = 0x90
			if first == 0xf4: high = 0x8f
		else:
			return false
		if cursor + extra > end or raw[cursor] < low or raw[cursor] > high:
			return false
		for index in extra:
			if raw[cursor + index] < 0x80 or raw[cursor + index] > 0xbf:
				return false
		cursor += extra
	return true
