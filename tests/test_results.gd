extends RefCounted
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Outbox = preload("res://sdk/roomkit/server/result_outbox.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
var passed := 0
var failed := 0

func run() -> Dictionary:
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://examples/result_messages.example.json"))
	for message in examples:
		check(Protocol.validate(message) == "", "documented result message matches control schema " + message.type)
	var record := sample()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(record))
	check(Format.hash_record(record) == Format.hash_record(decoded), "wire integers have stable digest")
	check(Format.valid_record(record), "result contract accepts complete identity")
	var altered := record.duplicate(true)
	altered.payload.round = NAN
	check(not Format.valid_record(altered), "non-finite result rejected")
	altered = record.duplicate(true)
	var nested: Dictionary = altered.payload
	for level in range(14):
		nested.child = {}
		nested = nested.child
	check(not Format.valid_record(altered), "outbox rejects records too deep for control envelope")
	var signature := Format.sign(record, "a".repeat(64))
	check(signature != Format.sign(record, "b".repeat(64)), "launch signing key separates records")
	var box = Outbox.new()
	var directory := ProjectSettings.globalize_path("res://run/test-outbox-" + Wire.uid())
	check(box.initialize(directory, "a".repeat(64)), "outbox initialized in isolated fixture directory")
	check(box.enqueue(record).ok and box.pending().size() == 1, "outbox exists before any send")
	check(box.enqueue(decoded).ok and box.pending().size() == 1, "retry preserves one pending file")
	altered = record.duplicate(true)
	altered.payload.round = 2
	check(not box.enqueue(altered).ok, "same result ID cannot replace pending content")
	var reply := {"result_id": record.result_id, "record_hash": "0".repeat(64), "ok": true, "code": ""}
	check(not box.acknowledge(reply) and box.pending().size() == 1, "wrong digest cannot acknowledge result")
	reply.record_hash = Format.hash_record(record)
	reply.ok = false
	reply.code = "STORAGE_UNAVAILABLE"
	check(not box.acknowledge(reply) and box.pending().size() == 1, "storage outage keeps outbox")
	check(Protocol.validate(Protocol.event("result.submit", record.room_id, record.launch_id, {"record": record, "signature": signature}, record.game_id, record.build_id)) == "", "control submission matches schema")
	check(Protocol.validate(Protocol.event("result.ack", record.room_id, record.launch_id, reply, record.game_id, record.build_id)) == "", "control acknowledgement matches schema")
	reply.ok = true
	reply.code = ""
	check(box.acknowledge(reply) and box.pending().is_empty(), "matching durable ACK removes outbox")
	box.enqueue(record)
	reply.ok = false
	reply.code = "RESULT_CONFLICT"
	check(box.acknowledge(reply) and box.pending().is_empty() and FileAccess.file_exists(box.path_for(record.result_id).trim_suffix(".json") + ".rejected.json"), "permanent failure retained for inspection")
	var precise := record.duplicate(true)
	precise.result_id = Wire.uid()
	precise.payload.measurement = 0.12345678901234566
	check(box.enqueue(precise).ok, "finite fractional payload can be queued")
	var disk: Dictionary = Wire.decode(FileAccess.get_file_as_bytes(box.path_for(precise.result_id)))
	check(disk.signature == Format.sign(disk.record, "a".repeat(64)), "outbox preserves signed floating point precision")
	var sender = Format.Transport.new()
	var receiver = Format.Transport.new()
	var buffer := StreamPeerBuffer.new()
	sender.queue(Protocol.event("result.submit", record.room_id, record.launch_id, disk, record.game_id, record.build_id))
	sender.flush(buffer)
	var frames: Array = receiver.feed(buffer.data_array)
	check(frames.size() == 1 and frames[0].payload.signature == Format.sign(frames[0].payload.record, "a".repeat(64)), "control framing preserves signed floating point precision")
	return {"passed": passed, "failed": failed}

static func sample() -> Dictionary:
	var launch := "a".repeat(32)
	return {"game_id": "minimal_room", "build_id": "dev-004", "room_id": "r_test", "launch_id": launch, "match_id": "m_" + launch + "_one", "result_id": "b".repeat(32), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS result unit: ", label)
	else:
		failed += 1
		printerr("FAIL result unit: ", label)
