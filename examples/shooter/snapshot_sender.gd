extends RefCounted
## A bounded game-specific outbox. New publications replace only the waiting
## frame; an active frame must finish so continuous updates cannot starve it.
const Codec = preload("snapshot_codec.gd")
const MAX_PEERS := 16
const PER_PEER_BURST := 16
const TOTAL_BURST := 128
const MIN_FLUSH_MS := 8
const DEADLINE_MARGIN_MS := 100
var active: Array[PackedByteArray] = []
var pending: Array[PackedByteArray] = []
var offsets: Dictionary = {}
var recipients: Array[int] = []
var first_send_ms := -1
var last_flush_ms := -1
var cursor := 0

func enqueue(packets: Array[PackedByteArray]) -> void:
	# Codec-owned immutable packet arrays, at most one active and one pending.
	if not packets.is_empty() and packets.size() <= Codec.MAX_FRAGMENTS:
		pending = packets

func reset() -> void:
	active = []
	pending = []
	offsets.clear()
	recipients.clear()
	first_send_ms = -1
	last_flush_ms = -1
	cursor = 0

func forget(peer: int) -> void:
	# Called at membership removal even if ENet later reuses the same peer ID.
	recipients.erase(peer)
	offsets.erase(peer)

func take(now_ms: int, connected: PackedInt32Array) -> Array:
	var output: Array = []
	if now_ms < 0 or (last_flush_ms >= 0 and now_ms - last_flush_ms < MIN_FLUSH_MS):
		return output
	last_flush_ms = now_ms # No accumulated credit or catch-up bursts after a stall.
	for peer in recipients.duplicate():
		if not connected.has(peer):
			recipients.erase(peer)
			offsets.erase(peer)
	if not active.is_empty() and (recipients.is_empty() or now_ms - first_send_ms >= Codec.frame_ttl_ms(active.size()) - DEADLINE_MARGIN_MS):
		_clear_active()
	if active.is_empty():
		if pending.is_empty() or connected.is_empty():
			return output
		active = pending
		pending = []
		# Peers joining midway wait for the next whole frame; never receive a tail.
		for peer in connected:
			if peer > 1 and not offsets.has(peer) and recipients.size() < MAX_PEERS:
				recipients.append(peer)
				offsets[peer] = 0
		first_send_ms = now_ms
		cursor = 0
	if recipients.is_empty():
		_clear_active()
		return output
	var sent: Dictionary = {}
	var idle := 0
	while output.size() < TOTAL_BURST and idle < recipients.size():
		cursor %= recipients.size()
		var peer: int = recipients[cursor]
		cursor = (cursor + 1) % recipients.size()
		var offset: int = offsets[peer]
		if offset >= active.size() or int(sent.get(peer, 0)) >= PER_PEER_BURST:
			idle += 1
			continue
		idle = 0
		output.append({"peer": peer, "packet": active[offset]})
		offsets[peer] = offset + 1
		sent[peer] = int(sent.get(peer, 0)) + 1
	var complete := true
	for peer in recipients:
		if int(offsets[peer]) < active.size():
			complete = false
	if complete:
		_clear_active() # Never start a second frame in the same flush.
	return output

func _clear_active() -> void:
	active = []
	offsets.clear()
	recipients.clear()
	first_send_ms = -1
	cursor = 0
