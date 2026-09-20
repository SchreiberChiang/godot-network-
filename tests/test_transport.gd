extends RefCounted

const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")

class PartialWriter:
	extends RefCounted
	var bytes := PackedByteArray()
	var chunk := 3
	var block_next := false
	var fail := false
	var calls := 0

	func write(data: PackedByteArray) -> Array:
		calls += 1
		if fail:
			return [ERR_CONNECTION_ERROR, 0]
		if block_next:
			block_next = false
			return [OK, 0]
		var count := mini(chunk, data.size())
		bytes.append_array(data.slice(0, count))
		return [OK, count]

var passed := 0
var failed := 0

func run() -> Dictionary:
	passed = 0
	failed = 0
	_contracts()
	_framing()
	_invalid_frames()
	_writes()
	return {"passed": passed, "failed": failed}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS transport: ", label)
	else:
		failed += 1
		print("FAIL transport: ", label)

func _event(type: String, payload: Dictionary) -> Dictionary:
	return Protocol.event(type, "r_unit", "launch_unit", payload, "minimal_room", "dev-001")

func _contracts() -> void:
	var examples: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://examples/control_messages.example.json"))
	_check(examples is Array and examples.size() == 7, "seven documented control examples loaded")
	if examples is Array:
		for message: Dictionary in examples:
			_check(Protocol.validate(message).is_empty(), "schema accepts example " + str(message.type))
	var good := _event("room.ready", {"udp_port": 28100})
	_check(Protocol.validate(good).is_empty(), "generated event validates")
	_check(good.event_id != _event("room.ready", {"udp_port": 28100}).event_id, "generated event identifiers differ")
	var bad: Dictionary = good.duplicate(true)
	bad.type = "room.unknown"
	_check(not Protocol.validate(bad).is_empty(), "unknown control type rejected")
	bad = good.duplicate(true)
	bad["unknown"] = true
	_check(not Protocol.validate(bad).is_empty(), "unknown envelope field rejected")
	bad = good.duplicate(true)
	bad.payload["unknown"] = true
	_check(not Protocol.validate(bad).is_empty(), "unknown payload field rejected")
	for field: String in ["room_id", "launch_id", "game_id", "build_id", "event_id", "payload"]:
		bad = good.duplicate(true)
		bad.erase(field)
		_check(not Protocol.validate(bad).is_empty(), "required control field " + field)
	for value: Variant in ["28100", 28100.5, true, 0, 65536]:
		_check(not Protocol.validate(_event("room.ready", {"udp_port": value})).is_empty(), "invalid UDP port type or range " + str(value))
	bad = good.duplicate(true)
	bad.version = 2
	_check(not Protocol.validate(bad).is_empty(), "unsupported protocol version rejected")
	bad = good.duplicate(true)
	bad.request_id = "not_a_request"
	_check(not Protocol.validate(bad).is_empty(), "request identifier forbidden on control event")
	bad = good.duplicate(true)
	bad.idempotency_key = "not_a_request"
	_check(not Protocol.validate(bad).is_empty(), "request idempotency key forbidden on control event")
	bad = good.duplicate(true)
	bad.kind = "request"
	bad.request_id = "request"
	_check(not Protocol.validate(bad).is_empty(), "request envelope rejected on control channel")
	_check(not Protocol.validate(_event("room.register", {"token": "short", "pid": 1234})).is_empty(), "malformed registration token rejected")
	_check(not Protocol.validate(_event("room.register", {"token": "0".repeat(64), "pid": 0})).is_empty(), "invalid registration PID rejected")
	_check(not Protocol.validate(_event("room.heartbeat", {"sequence": 0, "step": 0})).is_empty(), "heartbeat sequence starts at one")
	_check(not Protocol.validate(_event("room.heartbeat", {"sequence": 1, "step": -1})).is_empty(), "negative heartbeat step rejected")
	_check(not Protocol.validate(_event("room.heartbeat", {"sequence": 9007199254740992, "step": 1})).is_empty(), "heartbeat integer bounded to exact JSON range")
	_check(not Protocol.validate(_event("room.failed", {"code": "ARBITRARY_REMOTE_CODE"})).is_empty(), "undocumented remote failure code rejected")
	_check(not Protocol.validate(_event("room.stop", {"reason": ""})).is_empty(), "empty stop reason rejected")
	_check(not Validator.validate_file({}, "res://schemas/not_present.schema.json").is_empty(), "missing schema fails closed")

func _frame(body: PackedByteArray) -> PackedByteArray:
	var size := body.size()
	var result := PackedByteArray([(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255])
	result.append_array(body)
	return result

func _framing() -> void:
	var first := {"text": "房间中文 😀", "number": 123}
	# Godot JSON decodes all JSON numbers as float. Dictionary equality is
	# type-sensitive even though scalar 123 == 123.0; assert the exact wire value.
	var first_wire := {"text": "房间中文 😀", "number": 123.0}
	var second := {"text": "second", "nested": {"enabled": true}}
	var first_frame := _frame(JSON.stringify(first).to_utf8_buffer())
	var second_frame := _frame(JSON.stringify(second).to_utf8_buffer())
	var receiver = Transport.new()
	var messages: Array = []
	for byte: int in first_frame:
		messages.append_array(receiver.feed(PackedByteArray([byte])))
	_check(receiver.error.is_empty() and messages.size() == 1 and messages[0] == first_wire, "one-byte fragmentation including UTF-8 boundaries")
	receiver = Transport.new()
	var joined := first_frame.duplicate()
	joined.append_array(second_frame)
	messages = receiver.feed(joined)
	_check(receiver.error.is_empty() and messages.size() == 2 and messages[0] == first_wire and messages[1] == second, "two coalesced frames preserve order")
	receiver = Transport.new()
	joined = first_frame.duplicate()
	joined.append_array(second_frame.slice(0, 5))
	messages = receiver.feed(joined)
	_check(messages.size() == 1 and messages[0] == first_wire, "complete frame before incomplete suffix emitted once")
	messages = receiver.feed(second_frame.slice(5))
	_check(messages.size() == 1 and messages[0] == second, "incomplete suffix retained until next feed")
	_check(receiver.feed(PackedByteArray()).is_empty() and receiver.error.is_empty(), "empty feed is harmless")
	var max_body := ("{\"x\":\"" + "x".repeat(Transport.MAX_BODY - 8) + "\"}").to_utf8_buffer()
	_check(max_body.size() == Transport.MAX_BODY, "boundary fixture measures UTF-8 bytes")
	receiver = Transport.new()
	messages = receiver.feed(_frame(max_body))
	_check(receiver.error.is_empty() and messages.size() == 1, "exactly 64 KiB JSON body accepted")
	var depth_ok := "{\"x\":".repeat(Transport.MAX_DEPTH) + "0" + "}".repeat(Transport.MAX_DEPTH)
	receiver = Transport.new()
	_check(receiver.feed(_frame(depth_ok.to_utf8_buffer())).size() == 1 and receiver.error.is_empty(), "exactly sixteen object levels accepted")
	receiver = Transport.new()
	_check(receiver.feed(_frame(JSON.stringify({"braces": "[{\\\"".repeat(40)}).to_utf8_buffer())).size() == 1, "braces and escaped quotes inside strings do not count as nesting")

func _rejected(bytes: PackedByteArray, label: String, expected_error: String = "") -> void:
	var receiver = Transport.new()
	var result: Array = receiver.feed(bytes)
	_check(result.is_empty() and not receiver.error.is_empty() and (expected_error.is_empty() or receiver.error == expected_error), label)

func _invalid_frames() -> void:
	_rejected(PackedByteArray([0, 0, 0, 0]), "zero-length prefix rejected before body")
	_rejected(PackedByteArray([0, 1, 0, 1]), "64 KiB plus one prefix rejected before body")
	_rejected(PackedByteArray([255, 255, 255, 255]), "unsigned 32-bit maximum prefix rejected")
	var overflow := PackedByteArray()
	overflow.resize(Transport.MAX_BUFFER + 1)
	_rejected(overflow, "receive buffer overflow rejected")
	var invalid_utf8: Array = [
		PackedByteArray([34, 192, 128, 34]),
		PackedByteArray([34, 237, 160, 128, 34]),
		PackedByteArray([34, 244, 144, 128, 128, 34]),
		PackedByteArray([34, 226, 130]),
		PackedByteArray([34, 128, 34]),
	]
	for index: int in range(invalid_utf8.size()):
		_rejected(_frame(invalid_utf8[index]), "invalid UTF-8 case " + str(index + 1), "INVALID_UTF8")
	for invalid: String in ["[]", "null", "true", "123", "\"text\"", "{", "{\"x\":1,}", "{\"x\":01}", "{\"x\":true}{}", "{\"x\":\"raw\nnewline\"}", "{\"x\":1e999}"]:
		_rejected(_frame(invalid.to_utf8_buffer()), "non-object or malformed/non-finite JSON case " + str(invalid.length()))
	var deep := "{\"x\":".repeat(Transport.MAX_DEPTH + 1) + "0" + "}".repeat(Transport.MAX_DEPTH + 1)
	_rejected(_frame(deep.to_utf8_buffer()), "seventeen object levels rejected")
	var receiver = Transport.new()
	receiver.feed(PackedByteArray([0, 0, 0, 0]))
	var writer := PartialWriter.new()
	_check(receiver.feed(_frame("{}".to_utf8_buffer())).is_empty() and not receiver.queue({}) and not receiver.flush_with_writer(writer.write) and writer.calls == 0, "failed codec refuses all later I/O")
	var combined := _frame("{}".to_utf8_buffer())
	combined.append_array(PackedByteArray([0, 0, 0, 0]))
	_rejected(combined, "invalid trailing frame fails entire feed batch")

func _writes() -> void:
	var first := {"text": "界".repeat(80)}
	var second := {"text": "second message", "value": 123}
	var second_wire := {"text": "second message", "value": 123.0}
	var sender = Transport.new()
	_check(sender.queue(first) and sender.queue(second), "two outbound frames queued")
	var expected := _frame(JSON.stringify(first).to_utf8_buffer())
	expected.append_array(_frame(JSON.stringify(second).to_utf8_buffer()))
	_check(sender.pending_bytes() == expected.size(), "pending bytes include both length prefixes")
	var writer := PartialWriter.new()
	writer.block_next = true
	_check(sender.flush_with_writer(writer.write) and writer.bytes.is_empty() and sender.pending_bytes() == expected.size(), "simulated zero-byte write preserves complete queue")
	_check(sender.flush_with_writer(writer.write) and sender.pending_bytes() > 0 and sender.pending_bytes() < expected.size(), "simulated short writes make bounded progress")
	for iteration: int in range(20):
		if sender.pending_bytes() == 0:
			break
		sender.flush_with_writer(writer.write)
	_check(sender.pending_bytes() == 0 and writer.bytes == expected, "simulated partial writes preserve every byte and frame boundary")
	var receiver = Transport.new()
	var decoded: Array = receiver.feed(writer.bytes)
	_check(decoded.size() == 2 and decoded[0] == first and decoded[1] == second_wire, "simulated partial-write bytes decode as original messages")
	var calls_before := writer.calls
	_check(sender.flush_with_writer(writer.write) and writer.calls == calls_before, "empty send queue makes no writer call")
	sender = Transport.new()
	sender.queue(first)
	writer = PartialWriter.new()
	writer.fail = true
	_check(not sender.flush_with_writer(writer.write) and not sender.error.is_empty() and sender.pending_bytes() == 0, "simulated write error closes and clears queue")
	sender = Transport.new()
	sender.queue({})
	_check(not sender.flush_with_writer(func(_data: PackedByteArray) -> Array: return [OK, -1]), "negative written count rejected")
	sender = Transport.new()
	sender.queue({})
	_check(not sender.flush_with_writer(func(data: PackedByteArray) -> Array: return [OK, data.size() + 1]), "over-reported written count rejected")
	sender = Transport.new()
	sender.queue({})
	_check(not sender.flush_with_writer(func(_data: PackedByteArray) -> Array: return [OK]), "malformed writer result rejected")
	sender = Transport.new()
	var memory_stream := StreamPeerBuffer.new()
	sender.queue(second)
	_check(sender.flush(memory_stream) and memory_stream.data_array == _frame(JSON.stringify(second).to_utf8_buffer()), "production StreamPeer flush path works with memory stream")
	sender = Transport.new()
	var overhead := JSON.stringify({"x": ""}).to_utf8_buffer().size()
	var maximum_message := {"x": "x".repeat(Transport.MAX_BODY - overhead)}
	var queued_all := true
	for index: int in range(4):
		queued_all = sender.queue(maximum_message) and queued_all
	_check(queued_all and sender.pending_bytes() == Transport.MAX_QUEUE, "exact send-queue byte budget accepted")
	_check(not sender.queue({}) and not sender.error.is_empty(), "outbound backpressure limit fails closed")
	sender = Transport.new()
	_check(not sender.queue({"x": "x".repeat(Transport.MAX_BODY)}) and not sender.error.is_empty(), "oversized outbound message rejected")
	sender = Transport.new()
	_check(not sender.queue({"x": INF}), "outbound infinity rejected before lossy serialization")
	sender = Transport.new()
	_check(not sender.queue({"x": NAN}), "outbound NaN rejected before lossy serialization")
