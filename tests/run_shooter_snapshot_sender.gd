extends SceneTree
## Deterministic scheduling boundaries, separate from actual ENet acceptance.
const Sender = preload("res://examples/shooter/snapshot_sender.gd")
const Codec = preload("res://examples/shooter/snapshot_codec.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for count in [1, 87, 544]:
		for peers in [1, 8, 16]:
			for interval in [8, 17, 34]:
				_capacity(count, peers, interval)
	_queue_and_lifecycle()
	_ttl()
	print("SHOOTER_SNAPSHOT_SENDER_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _packets(count: int, serial: int) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	for index in count:
		var data := PackedByteArray()
		data.resize(12)
		data.encode_u32(0, serial)
		data.encode_u32(4, index)
		result.append(data)
	return result

func _peers(count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for index in count:
		result.append(index + 2)
	return result

func _capacity(count: int, peer_count: int, interval: int) -> void:
	var sender := Sender.new()
	sender.enqueue(_packets(count, 1))
	var connected := _peers(peer_count)
	var received: Dictionary = {}
	for peer in connected:
		received[peer] = []
	var valid := true
	var now := 100
	var finished := false
	while now < 2600:
		var deliveries: Array = sender.take(now, connected)
		var counts: Dictionary = {}
		valid = valid and deliveries.size() <= 128
		for delivery in deliveries:
			counts[delivery.peer] = int(counts.get(delivery.peer, 0)) + 1
			valid = valid and int(counts[delivery.peer]) <= 16
			received[delivery.peer].append(int(delivery.packet.decode_u32(4)))
		# Continuously replacing the waiting frame must not restart the active one.
		sender.enqueue(_packets(count, 2 + now))
		if sender.active.is_empty():
			finished = true
			break
		now += interval
	for peer in connected:
		valid = valid and received[peer] == range(count)
	_check(finished and valid and now - 100 < Codec.frame_ttl_ms(count) - 100,
		"scheduler emits all %d indexes for %d recipients at %d ms within bounds" % [count, peer_count, interval])

func _queue_and_lifecycle() -> void:
	var sender := Sender.new()
	sender.enqueue(_packets(40, 1))
	var peers := _peers(8)
	var first: Array = sender.take(100, peers)
	_check(first.size() == 128 and not sender.active.is_empty(), "first flush leaves a bounded active frame")
	_check(sender.take(100, peers).is_empty() and sender.take(107, peers).is_empty(), "same timestamp and tight repeated calls cannot burst again")
	sender.enqueue(_packets(4, 2))
	sender.enqueue(_packets(4, 3))
	_check(sender.pending.size() == 4 and sender.pending[0].decode_u32(0) == 3, "only latest waiting publication is retained")
	var joined := peers.duplicate()
	joined.append(42)
	var middle: Array = sender.take(117, joined)
	_check(middle.all(func(row): return row.peer != 42 and row.packet.decode_u32(0) == 1), "new peer receives no partial tail and active frame survives coalescing")
	sender.take(134, joined)
	var next: Array = sender.take(151, joined)
	_check(next.size() == 36 and next.all(func(row): return row.packet.decode_u32(0) == 3), "next whole frame includes joining peer and drops obsolete pending frame")
	sender.enqueue(_packets(87, 4))
	sender.take(168, joined)
	sender.enqueue(_packets(1, 5))
	var after_stall: Array = sender.take(900, joined)
	_check(after_stall.size() == 9 and after_stall.all(func(row): return row.packet.decode_u32(0) == 5), "expired unsent tail is abandoned after stall and latest queued frame starts")
	_check(sender.take(901, joined).is_empty(), "stall does not accrue catch-up credit")
	sender.enqueue(_packets(87, 6))
	sender.take(920, peers)
	var survivors := PackedInt32Array([3])
	var disconnected: Array = sender.take(937, survivors)
	_check(disconnected.size() == 16 and disconnected.all(func(row): return row.peer == 3), "disconnected peers are removed before more data is emitted")
	sender.forget(3)
	_check(sender.take(954, survivors).is_empty(), "peer ID reused after membership removal cannot receive previous active tail")
	sender.enqueue(_packets(10, 7))
	sender.reset()
	_check(sender.take(0, peers).is_empty() and sender.active.is_empty() and sender.pending.is_empty() and sender.offsets.is_empty(), "reset releases all queued packets, recipients and clock state")

func _ttl() -> void:
	_check(Codec.frame_ttl_ms(1) == 250 and Codec.frame_ttl_ms(87) == 490 and Codec.frame_ttl_ms(544) == 2428, "size-based lifetime budgets small and maximum frames without claiming network delivery")
	var decoder := Codec.new()
	var packet := PackedByteArray()
	packet.resize(1000)
	var fields := [Codec.MAGIC, Codec.VERSION, 0, 71, 1, 524288, 524288, 544, 0]
	for index in fields.size():
		packet.encode_u32(index * 4, fields[index])
	decoder.feed(packet, 100)
	decoder.feed(packet, 2300)
	_check(decoder._frames.size() == 1 and int(decoder._frames[1].born) == 100, "large incomplete frame remains bounded and duplicates never extend its birth time")
	decoder.feed(packet, 2528)
	_check(decoder._frames.is_empty() and decoder._retired_serial == 1, "large frame expires at its exact size-dependent boundary")

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
