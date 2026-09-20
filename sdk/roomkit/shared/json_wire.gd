extends RefCounted
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")

static func decode(bytes: PackedByteArray, schema: String = "", limit: int = 16384) -> Dictionary:
	if bytes.size() == 0 or bytes.size() > limit:
		return {}
	var size := bytes.size()
	var framed := PackedByteArray([(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255])
	framed.append_array(bytes)
	var codec = Transport.new()
	var messages: Array = codec.feed(framed)
	if messages.size() != 1:
		return {}
	var message: Dictionary = messages[0]
	if not schema.is_empty() and Validator.validate_file(message, schema) != "":
		return {}
	return message

static func uid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func request(type: String, payload: Dictionary, key: String = "") -> Dictionary:
	var result := {"version": 1, "kind": "request", "type": type, "request_id": uid(), "payload": payload}
	if key != "":
		result.idempotency_key = key
	return result

static func response(request_message: Dictionary, result: Dictionary) -> Dictionary:
	var reply := {"version": 1, "kind": "response", "type": request_message.type, "request_id": request_message.request_id, "ok": result.ok, "payload": result.get("payload", {})}
	if not result.ok:
		reply.error = {"code": result.code, "message": result.code, "retryable": result.code in ["ROOM_STARTING", "ROOM_FULL", "RATE_LIMITED"]}
	return reply

static func failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "payload": {}}
