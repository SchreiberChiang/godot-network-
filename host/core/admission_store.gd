extends RefCounted
## In-memory local-dev seats. Only digests of bearer tickets are retained.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var tickets: Dictionary = {}
var seats: Dictionary = {}
var ticket_ms := 30000
var loading_ms := 15000

func reserve(row: Dictionary, user: Dictionary, now: int) -> Dictionary:
	if row.state != "READY":
		return Wire.failure("ROOM_STARTING" if row.state == "STARTING" else "ROOM_DRAINING")
	for seat in seats.values():
		if seat.user_id == user.user_id:
			return Wire.failure("ALREADY_IN_ROOM" if seat.state == "CONNECTED" else "ALREADY_RESERVED")
	if count(row.room_id) >= int(row.capacity):
		return Wire.failure("ROOM_FULL")
	if tickets.size() >= 4096:
		return Wire.failure("RATE_LIMITED")
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	var digest := token.sha256_text()
	var seat := {"user_id": user.user_id, "display_name": user.display_name, "room_id": row.room_id, "launch_id": row.launch_id, "game_id": row.game_id, "build_id": row.build_id, "compatibility_id": row.compatibility_id, "game_protocol": row.game_protocol, "state": "RESERVED", "attempt_id": "", "expires": now + ticket_ms, "digest": digest}
	seats[digest] = seat
	tickets[digest] = {"used": false, "expires": now + ticket_ms, "retire": now + ticket_ms + 60000}
	return {"ok": true, "payload": {"ticket": token, "host": "127.0.0.1", "port": row.port, "room_id": row.room_id, "launch_id": row.launch_id, "expires_in_ms": ticket_ms}}

func consume(row: Dictionary, payload: Dictionary, now: int) -> Dictionary:
	var digest: String = str(payload.ticket).sha256_text()
	if not tickets.has(digest):
		return Wire.failure("AUTH_FAILED")
	var ticket: Dictionary = tickets[digest]
	var seat: Dictionary = seats.get(digest, {})
	if seat.is_empty():
		return Wire.failure("TICKET_ALREADY_USED" if ticket.used else "TICKET_EXPIRED")
	if seat.room_id != row.room_id or seat.launch_id != row.launch_id or seat.game_id != row.game_id or seat.build_id != row.build_id or seat.user_id != payload.user_id:
		return Wire.failure("AUTH_FAILED")
	if payload.compatibility_id != seat.compatibility_id or int(payload.game_protocol) != int(seat.game_protocol):
		return Wire.failure("BUILD_MISMATCH")
	if row.state != "READY":
		return Wire.failure("ROOM_DRAINING")
	if ticket.used:
		if seat.attempt_id == payload.attempt_id and seat.state in ["ADMITTING", "CONNECTED"]:
			return accepted(seat)
		return Wire.failure("TICKET_ALREADY_USED")
	if now >= int(ticket.expires):
		seats.erase(digest)
		return Wire.failure("TICKET_EXPIRED")
	ticket.used = true
	seat.state = "ADMITTING"
	seat.attempt_id = payload.attempt_id
	seat.expires = now + loading_ms
	return accepted(seat)

func joined(room_id: String, user_id: String, attempt_id: String, now: int) -> bool:
	for seat in seats.values():
		if seat.room_id == room_id and seat.user_id == user_id and seat.attempt_id == attempt_id and seat.state in ["ADMITTING", "CONNECTED"]:
			# Check here too: control messages can arrive before the expiry sweep.
			if seat.state == "ADMITTING" and now >= int(seat.expires):
				return false
			seat.state = "CONNECTED"
			return true
	return false

func leave(room_id: String, user_id: String, attempt_id: String) -> void:
	for digest in seats.keys():
		var seat: Dictionary = seats[digest]
		if seat.room_id == room_id and seat.user_id == user_id and seat.attempt_id == attempt_id:
			seats.erase(digest)

func cancel_reservations(user_id: String) -> void:
	for digest in seats.keys():
		if seats[digest].user_id == user_id and seats[digest].state == "RESERVED":
			seats.erase(digest)

func poll(rows: Dictionary, now: int) -> Array:
	var revoked: Array = []
	for digest in seats.keys():
		var seat: Dictionary = seats[digest]
		var row: Dictionary = rows.get(seat.room_id, {})
		if row.get("state", "") != "READY" or (seat.state != "CONNECTED" and now >= int(seat.expires)):
			if seat.state == "ADMITTING":
				revoked.append({"room_id": seat.room_id, "attempt_id": seat.attempt_id})
			seats.erase(digest)
	for digest in tickets.keys():
		if now >= int(tickets[digest].retire) and not seats.has(digest):
			tickets.erase(digest)
	return revoked

func count(room_id: String, state: String = "") -> int:
	var total := 0
	for seat in seats.values():
		if seat.room_id == room_id and (state == "" or seat.state == state):
			total += 1
	return total

func accepted(seat: Dictionary) -> Dictionary:
	return {"ok": true, "payload": {"user_id": seat.user_id, "display_name": seat.display_name}}
