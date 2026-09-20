extends RefCounted
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")

static func event(type: String, room_id: String, launch_id: String, payload: Dictionary, game_id: String = "", build_id: String = "") -> Dictionary:
	return {"version": 1, "kind": "event", "type": type, "event_id": Crypto.new().generate_random_bytes(16).hex_encode(), "room_id": room_id, "launch_id": launch_id, "game_id": game_id, "build_id": build_id, "payload": payload}

static func validate(message: Dictionary) -> String:
	var error := Validator.validate_file(message, "res://schemas/envelope.schema.json")
	if error != "":
		return error
	return Validator.validate_file(message, "res://schemas/control.schema.json")
