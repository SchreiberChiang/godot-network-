extends SceneTree
## Regression for "empty room disappears / join returns to login" with a
## non-loopback advertised_host (docs/17). Contract and lobby logic only; the
## end-to-end reproduction is tests/run_room_disappear_probe.ps1.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Lobby = preload("res://host/managed_lobby.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
var passed := 0
var failed := 0

class FakeManager extends RefCounted:
	var rooms: Dictionary = {}
	var sent: Array = []
	var control_handler: Callable
	func send_control(room_id: String, type: String, payload: Dictionary) -> void:
		sent.append({"room_id": room_id, "type": type, "payload": payload.duplicate(true)})

func _initialize() -> void:
	_reserve_contract()
	_revoke_only_known_attempts()
	# A script error aborts a group silently; require every check to have run.
	_check(passed + failed == 15, "all 15 checks ran")
	print("ROOM_DISAPPEAR_REGRESSION passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _reply(host: String) -> Dictionary:
	var request := Wire.request("room.reserve", {"game_id": "shooter", "build_id": "b", "compatibility_id": "c", "game_protocol": 1, "room_id": "r_1"})
	return Wire.response(request, {"ok": true, "payload": {"ticket": "a".repeat(64), "host": host, "port": 28400, "room_id": "r_1", "launch_id": "l_1", "expires_in_ms": 30000}})

func _reserve_contract() -> void:
	for host in ["127.0.0.1", "192.168.10.20", "203.0.113.7"]:
		_check(Validator.validate_file(_reply(host), "res://schemas/managed_lobby_response.schema.json") == "", "reserve reply with advertised host %s passes the client schema" % host)
	for host in ["256.1.1.1", "example.com", "::1", "0.0.0.0.1", ""]:
		_check(Validator.validate_file(_reply(host), "res://schemas/managed_lobby_response.schema.json") != "", "reserve reply with invalid host '%s' is still rejected" % host)

func _revoke_only_known_attempts() -> void:
	var manager := FakeManager.new()
	var lobby = Lobby.new()
	lobby.manager = manager
	var row := {"room_id": "r_1", "launch_id": "l_1", "game_id": "shooter", "build_id": "b", "compatibility_id": "c", "game_protocol": 1, "port": 28400, "capacity": 8, "state": "READY"}
	manager.rooms["r_1"] = row
	var reserved: Dictionary = lobby.admissions.reserve(row, {"user_id": "u_reserved", "display_name": "R"}, 0)
	_check(reserved.ok, "a seat can be reserved")
	lobby.kick("u_reserved", "session_changed")
	_check(manager.sent.is_empty(), "releasing a RESERVED seat sends no admission.revoke (it has no attempt)")
	_check(lobby.admissions.count("r_1") == 0, "the RESERVED seat is released")
	var consumed: Dictionary = lobby.admissions.consume(row, {"ticket": reserved.payload.ticket, "user_id": "u_reserved", "attempt_id": "att_1", "compatibility_id": "c", "game_protocol": 1}, 1)
	_check(not consumed.ok, "the released seat's ticket can no longer be consumed (%s)" % consumed.get("code", ""))
	var second: Dictionary = lobby.admissions.reserve(row, {"user_id": "u_admitting", "display_name": "A"}, 0)
	lobby.admissions.consume(row, {"ticket": second.payload.ticket, "user_id": "u_admitting", "attempt_id": "att_2", "compatibility_id": "c", "game_protocol": 1}, 1)
	lobby.kick("u_admitting", "session_changed")
	_check(manager.sent.size() == 1 and manager.sent[0].type == "admission.revoke" and manager.sent[0].payload.attempt_id == "att_2", "an ADMITTING seat is still revoked in its room")
	var envelope := Protocol.event("admission.revoke", "r_1", "l_1", manager.sent[0].payload, "shooter", "b")
	_check(Protocol.validate(envelope) == "", "the revoke the host sends passes the room's control schema")
	_check(Protocol.validate(Protocol.event("admission.revoke", "r_1", "l_1", {"attempt_id": ""}, "shooter", "b")) != "", "an empty-attempt revoke (the old bug) is what the room rejects")

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
