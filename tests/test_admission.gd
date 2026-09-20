extends RefCounted
const Store = preload("res://host/core/admission_store.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0

func run() -> Dictionary:
	var row := {"room_id": "room_a", "launch_id": "launch_a", "game_id": "game_a", "build_id": "build_a", "compatibility_id": "compat_a", "game_protocol": 1, "capacity": 1, "state": "STARTING", "port": 28100}
	var user := {"user_id": "alice", "display_name": "Alice"}
	var other := {"user_id": "bob", "display_name": "Bob"}
	var store = Store.new()
	check(store.reserve(row, user, 0).code == "ROOM_STARTING", "no ticket before READY")
	row.state = "READY"
	var first: Dictionary = store.reserve(row, user, 0)
	check(first.ok and first.payload.ticket.length() == 64, "high entropy ticket issued")
	check(not JSON.stringify(store.seats).contains(first.payload.ticket) and not JSON.stringify(store.tickets).contains(first.payload.ticket), "store retains digest not bearer token")
	check(store.reserve(row, other, 0).code == "ROOM_FULL", "last seat reserved atomically")
	check(store.reserve(row, user, 0).code == "ALREADY_RESERVED", "same user cannot reserve twice")
	var payload := {"ticket": first.payload.ticket, "attempt_id": "attempt_a", "user_id": "alice", "compatibility_id": "compat_a", "game_protocol": 1}
	var wrong := payload.duplicate()
	wrong.user_id = "bob"
	check(store.consume(row, wrong, 1).code == "AUTH_FAILED", "ticket cannot change identity")
	wrong = payload.duplicate()
	wrong.compatibility_id = "wrong"
	check(store.consume(row, wrong, 1).code == "BUILD_MISMATCH", "ticket checks compatibility")
	for key in ["room_id", "launch_id", "game_id", "build_id"]:
		var changed := row.duplicate()
		changed[key] = "other"
		check(store.consume(changed, payload, 1).code == "AUTH_FAILED", "ticket rejects cross " + key)
	check(store.consume(row, payload, 1).ok, "valid ticket consumed")
	check(store.count(row.room_id, "ADMITTING") == 1 and store.count(row.room_id) == 1, "admission does not double count seat")
	check(store.consume(row, payload, 2).ok, "same attempt retry is idempotent")
	wrong = payload.duplicate()
	wrong.attempt_id = "new_attempt"
	check(store.consume(row, wrong, 2).code == "TICKET_ALREADY_USED", "new attempt cannot replay consumed ticket")
	check(not store.joined(row.room_id, "bob", "attempt_a", 2), "wrong member cannot become connected")
	check(store.joined(row.room_id, "alice", "attempt_a", 2), "loading complete moves to connected")
	check(store.count(row.room_id, "CONNECTED") == 1, "one connected member")
	check(store.reserve(row, user, 2).code == "ALREADY_IN_ROOM", "connected user has a single seat")
	store.leave(row.room_id, "alice", "stale_attempt")
	check(store.count(row.room_id) == 1, "stale leave cannot evict new attempt")
	store.leave(row.room_id, "alice", "attempt_a")
	check(store.count(row.room_id) == 0, "leave releases seat")
	check(store.consume(row, payload, 3).code == "TICKET_ALREADY_USED", "disconnect cannot revive used ticket")
	var next: Dictionary = store.reserve(row, user, 3)
	check(next.ok and next.payload.ticket != first.payload.ticket, "rejoin gets fresh ticket")
	payload.ticket = next.payload.ticket
	check(store.consume(row, payload, 3 + store.ticket_ms).code == "TICKET_EXPIRED", "expired ticket rejected")
	check(store.count(row.room_id) == 0, "expiration recovers seat")
	next = store.reserve(row, user, 50000)
	payload.ticket = next.payload.ticket
	store.consume(row, payload, 50001)
	check(not store.joined(row.room_id, "alice", "attempt_a", 50001 + store.loading_ms), "expired loading cannot beat the expiry sweep")
	var revoked: Array = store.poll({row.room_id: row}, 50001 + store.loading_ms)
	check(revoked.size() == 1 and store.count(row.room_id) == 0, "loading timeout revokes pending admission")
	store.reserve(row, user, 80000)
	row.state = "FAILED"
	store.poll({row.room_id: row}, 80001)
	check(store.count(row.room_id) == 0, "room failure releases all seat states")
	row.state = "READY"
	store.reserve(row, user, 100000)
	store.cancel_reservations(user.user_id)
	check(store.count(row.room_id) == 0, "lobby disconnect cancels unused reservation")
	var request := Wire.request("session.create", {"display_name": "Alice"})
	check(Validator.validate_file(request, "res://schemas/lobby_request.schema.json") == "", "standard JSON session request matches schema")
	request.payload.executable = "bad"
	check(Validator.validate_file(request, "res://schemas/lobby_request.schema.json") != "", "lobby contract rejects executable injection")
	var compat := {"game_id": "game_a", "build_id": "build_a", "compatibility_id": "compat_a", "game_protocol": 1, "options": {"mode": "sandbox", "map": "empty", "capacity": 2}}
	check(Validator.validate_file(Wire.request("room.create", compat), "res://schemas/lobby_request.schema.json") != "", "create requires idempotency key")
	check(Validator.validate_file(Wire.request("room.create", compat, "key"), "res://schemas/lobby_request.schema.json") == "", "keyed create matches schema")
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://examples/m2_messages.example.json"))
	check(examples.size() == 17, "all documented M2 examples loaded")
	for example in examples:
		check(Validator.validate_file(example.message, "res://schemas/" + example.schema + ".schema.json") == "", "schema accepts M2 example " + example.label)
	return {"passed": passed, "failed": failed}

func check(value: bool, description: String) -> void:
	if value:
		passed += 1
		print("PASS admission: ", description)
	else:
		failed += 1
		printerr("FAIL admission: ", description)
