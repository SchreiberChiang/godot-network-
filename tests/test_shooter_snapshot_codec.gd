extends RefCounted
const Codec = preload("res://examples/shooter/snapshot_codec.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0
var expected_native_rejections := 0

func run() -> Dictionary:
	var state := _snapshot(8, 96)
	var packets := Codec.encode(state, 1, 42)
	_check(packets.size() > 1, "varied dense snapshot requires multiple bounded packets")
	var bounded := true
	for packet in packets:
		bounded = bounded and packet.size() <= 1000
	_check(bounded, "every RPC parameter packet fits 1000 bytes")
	var decoder := Codec.new()
	var complete: Dictionary = {}
	var premature := false
	for index in range(packets.size() - 1, -1, -1):
		var received: Dictionary = decoder.feed(packets[index], 10)
		if index > 0: premature = premature or not received.is_empty()
		else: complete = received
	_check(not premature and complete == state, "reverse fragment arrival applies only the complete identical state")
	_check(decoder.feed(packets[0], 11).is_empty(), "completed serial replay never reapplies")
	var next := Codec.encode(state, 2, 42)
	_check(_deliver(decoder, next, 12) == state, "different serial at the same tick is accepted")
	_check(_deliver(decoder, Codec.encode(state, 1, 42), 13).is_empty(), "older completed serial cannot replace a newer snapshot")
	_check(_deliver(decoder, Codec.encode(state, 3, 43), 14).is_empty(), "another stream is rejected until reset")
	decoder.reset()
	_check(_deliver(decoder, Codec.encode(state, 1, 43), 0) == state, "reset permits a new stream and restarts serial/time state")

	decoder = Codec.new()
	_check(decoder.feed(packets[0], 0).is_empty() and decoder.feed(packets[0], 200).is_empty(), "identical duplicate does not complete or refresh a partial frame")
	var expired: Dictionary = {}
	for index in range(1, packets.size()): expired = decoder.feed(packets[index], 250)
	_check(expired.is_empty() and _deliver(decoder, packets, 251).is_empty(), "TTL boundary retires the frame so late pieces cannot restart it")
	_check(_deliver(decoder, next, 252) == state, "missing or expired frame does not prevent the next serial recovering")
	decoder = Codec.new()
	decoder.feed(packets[0], 0)
	var conflict := packets[0].duplicate()
	conflict[Codec.HEADER_BYTES] ^= 1
	decoder.feed(conflict, 1)
	_check(_deliver(decoder, packets, 2).is_empty(), "duplicate index with conflicting content retires the entire serial")
	_check(_deliver(decoder, next, 3) == state, "frame following a duplicate conflict recovers")
	decoder = Codec.new()
	decoder.feed(packets[0], 0)
	var different := packets[1].duplicate()
	different.encode_u32(20, different.decode_u32(20) + 1)
	decoder.feed(different, 1)
	_check(_deliver(decoder, packets, 2).is_empty(), "same serial with conflicting header metadata is rejected")
	decoder = Codec.new()
	for serial in [1, 3, 2, 4]: decoder.feed(Codec.encode(state, serial, 42)[0], 0)
	_check(decoder._frames.size() == 3 and not decoder._frames.has(1), "at most three in-flight frames retain the newer serials")
	_check(_deliver(decoder, Codec.encode(state, 4, 42), 10) == state and decoder._frames.is_empty(), "newer completion clears older incomplete frames")
	_check(decoder.feed(Codec.encode(state, 5, 42)[0], 9).is_empty() and decoder._frames.is_empty(), "backwards clock input cannot create or extend a frame")

	_test_headers(state, packets)
	_test_payloads()
	_test_typed_containers()
	_test_wide_integers()
	var unicode := _snapshot(16, 192)
	for player in unicode.players:
		player.user_id = "🙂".repeat(128)
		player.display_name = "🙂".repeat(32)
		player.notice = "🙂".repeat(128)
	for index in 256:
		unicode.last_results.append({"user_id": "🙂".repeat(128), "kills": 100000, "deaths": 100000, "participation_ms": 3600000, "credits": 1000000})
	var raw_size := var_to_bytes(unicode).size()
	_check(raw_size < Codec.MAX_RAW_BYTES and Validator.validate_file(unicode, Codec.STATE_SCHEMA) == "", "512 KiB covers current maximum collections with maximum four-byte Unicode strings")
	_check(_deliver(Codec.new(), Codec.encode(unicode, 1, 1), 0) == unicode, "maximum legal collections and Unicode strings round trip without loss")
	print("INFO maximum_schema_variant_bytes=", raw_size)
	return {"passed": passed, "failed": failed, "expected_native_rejections": expected_native_rejections}

func _test_typed_containers() -> void:
	var ordinary := _snapshot(2, 4)
	ordinary.last_results.append({"user_id": ordinary.players[0].user_id, "kills": 1, "deaths": 2, "participation_ms": 50, "credits": 3})
	var typed: Dictionary[String, Variant] = {}
	typed.assign(ordinary)
	for name in ["players", "shots", "last_results"]:
		var rows: Array[Dictionary] = []
		for row in ordinary[name]:
			var typed_row: Dictionary[String, Variant] = {}
			typed_row.assign(row)
			rows.append(typed_row)
		typed[name] = rows
	var received := _deliver(Codec.new(), Codec.encode(typed, 1, 42), 0)
	_check(typed.is_typed() and typed.players.is_typed() and typed.players[0].is_typed() and received == ordinary and not received.is_typed() and not received.players.is_typed() and not received.players[0].is_typed(), "typed root, row dictionaries and arrays normalize while preserving snapshot semantics")

func _test_wide_integers() -> void:
	var state := _snapshot(1, 1)
	state.tick = 4294967297
	state.round = 9007199254740991
	state.shots[0].id = 9223372036854775807
	state.shots[0].at = 4294967297
	var received := _deliver(Codec.new(), Codec.encode(state, 1, 42), 0)
	_check(Validator.validate_file(state, Codec.STATE_SCHEMA) == "" and received == state and typeof(received.get("tick")) == TYPE_INT and received.get("tick") == 4294967297 and received.get("round") == 9007199254740991 and not received.get("shots", []).is_empty() and received.shots[0].id == 9223372036854775807 and received.shots[0].at == 4294967297, "schema-legal 64-bit integers round trip exactly without 32-bit truncation or float conversion")

func _test_headers(state: Dictionary, packets: Array[PackedByteArray]) -> void:
	var mutations := {"magic": [0, 0], "version": [4, 2], "flags": [8, 2], "stream_zero": [12, 0], "serial_zero": [16, 0], "raw_zero": [20, 0], "raw_over_cap": [20, Codec.MAX_RAW_BYTES + 1], "encoded_over_cap": [24, Codec.MAX_ENCODED_BYTES + 1], "count_wrong": [28, 1], "index_outside": [32, packets.size()]}
	var all_rejected := true
	for name in mutations:
		var changed := packets[0].duplicate()
		changed.encode_u32(mutations[name][0], mutations[name][1])
		var receiver := Codec.new()
		all_rejected = all_rejected and receiver.feed(changed, 0).is_empty() and receiver._frames.is_empty() and receiver._stream_id == 0
	_check(all_rejected, "malformed header fields fail before stream binding or allocation")
	var short := packets[0].slice(0, packets[0].size() - 1)
	var large := packets[0].duplicate()
	large.append(0)
	_check(Codec.new().feed(short, 0).is_empty() and Codec.new().feed(large, 0).is_empty(), "truncated or extra fragment data is rejected")
	var invalid := state.duplicate(true)
	invalid.players[0].hp = 101
	_check(Codec.encode(invalid, 1, 1).is_empty() and Codec.encode(state, 0, 1).is_empty() and Codec.encode(state, 1, 0).is_empty() and Codec.encode(state, Codec.UINT32_MAX + 1, 1).is_empty(), "encoder refuses invalid schema and invalid serial/stream ranges")
	_check(_deliver(Codec.new(), Codec.encode(state, Codec.UINT32_MAX, Codec.UINT32_MAX), 0) == state, "maximum unsigned identifiers are encoded without signed truncation")

func _test_payloads() -> void:
	var ordinary := _snapshot(1, 0)
	var ordinary_raw := var_to_bytes(ordinary)
	_check(_deliver(Codec.new(), _pack(ordinary_raw, ordinary_raw.size(), 0), 0) == ordinary, "uncompressed complete Variant is supported without changing logical state")
	var invalid_schema := var_to_bytes({"tick": 1})
	_check(_deliver(Codec.new(), _pack(invalid_schema, invalid_schema.size(), 0), 0).is_empty(), "well-formed Variant with invalid snapshot semantics is rejected")
	var trailing := var_to_bytes(_snapshot(1, 0))
	trailing.append(0)
	_check(_deliver(Codec.new(), _pack(trailing, trailing.size(), 0), 0).is_empty(), "trailing bytes after a valid Variant are rejected")
	var huge_count := PackedByteArray()
	huge_count.resize(8)
	huge_count.encode_u32(0, TYPE_ARRAY)
	huge_count.encode_u32(4, 0xffffffff)
	_check(_deliver(Codec.new(), _pack(huge_count, huge_count.size(), 0), 0).is_empty(), "hostile Variant container count is rejected before native allocation")
	var invalid_utf8 := var_to_bytes("x")
	invalid_utf8[8] = 0xff
	var object_type := PackedByteArray()
	object_type.resize(4)
	object_type.encode_u32(0, TYPE_OBJECT)
	_check(_deliver(Codec.new(), _pack(invalid_utf8, invalid_utf8.size(), 0), 0).is_empty() and _deliver(Codec.new(), _pack(object_type, object_type.size(), 0), 0).is_empty(), "invalid UTF-8 and object Variant tags never reach native decoding")
	var corrupt := PackedByteArray([1, 2, 3, 4, 5])
	_expected_native("corrupt_zstd", _pack(corrupt, 100, Codec.FLAG_ZSTD))
	var bomb_raw := PackedByteArray()
	bomb_raw.resize(Codec.MAX_RAW_BYTES)
	bomb_raw.fill(65)
	var bomb := bomb_raw.compress(FileAccess.COMPRESSION_ZSTD)
	_expected_native("compressed_size_mismatch", _pack(bomb, 100, Codec.FLAG_ZSTD))
	var valid := var_to_bytes(_snapshot(1, 0))
	var compressed := valid.compress(FileAccess.COMPRESSION_ZSTD)
	var packet_set := _pack(compressed, valid.size() + 4, Codec.FLAG_ZSTD)
	_check(_deliver(Codec.new(), packet_set, 0).is_empty(), "decompressed byte count must equal the declared raw size")

func _expected_native(name: String, packets: Array[PackedByteArray]) -> void:
	expected_native_rejections += 1
	print("EXPECTED_NATIVE_REJECTION_BEGIN case=", name)
	_check(_deliver(Codec.new(), packets, 0).is_empty(), "malformed compressed payload rejected: " + name)
	print("EXPECTED_NATIVE_REJECTION_END case=", name)

func _pack(encoded: PackedByteArray, raw_size: int, flags: int) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	var count := int(ceil(float(encoded.size()) / Codec.CHUNK_BYTES))
	for index in count:
		var packet := PackedByteArray()
		packet.resize(Codec.HEADER_BYTES)
		var fields := [Codec.MAGIC, Codec.VERSION, flags, 42, 1, raw_size, encoded.size(), count, index]
		for field in fields.size(): packet.encode_u32(field * 4, fields[field])
		packet.append_array(encoded.slice(index * Codec.CHUNK_BYTES, mini((index + 1) * Codec.CHUNK_BYTES, encoded.size())))
		result.append(packet)
	return result

func _deliver(decoder: RefCounted, packets: Array[PackedByteArray], now_ms: int) -> Dictionary:
	var latest: Dictionary = {}
	for packet in packets:
		var result: Dictionary = decoder.feed(packet, now_ms)
		if not result.is_empty(): latest = result
	return latest

func _snapshot(count: int, shot_count: int) -> Dictionary:
	var state := {"tick": 7, "phase": "active", "round": 1, "remaining_ms": 10000, "kill_limit": 0, "players": [], "shots": [], "last_results": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	for index in count:
		state.players.append({"user_id": _noise(rng, 34), "display_name": _noise(rng, 32), "x": rng.randf_range(14, 946), "y": rng.randf_range(22, 478), "aim_x": rng.randf_range(-1, 1), "aim_y": rng.randf_range(-1, 1), "hp": 100, "life_state": "alive", "weapon": "rifle", "kills": 0, "deaths": 0, "respawn_wait_ms": 0, "asset_busy": false, "notice": _noise(rng, 128)})
	for index in shot_count:
		state.shots.append({"id": index + 1, "at": index * 10, "x": rng.randf_range(-1500, 2460), "y": rng.randf_range(-1500, 2040), "end_x": rng.randf_range(-1500, 2460), "end_y": rng.randf_range(-1500, 2040), "weapon": "shotgun"})
	return state

func _noise(rng: RandomNumberGenerator, count: int) -> String:
	var result := ""
	for index in count: result += char(rng.randi_range(33, 126))
	return result

func _check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else: failed += 1
	print("PASS " if condition else "FAIL ", label)
