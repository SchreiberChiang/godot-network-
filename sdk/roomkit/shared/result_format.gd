extends RefCounted
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")

static func normalized(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = normalized(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalized(item))
		return result
	if value is float and is_finite(value) and absf(value) <= 9007199254740991 and floor(value) == value:
		return int(value)
	return value

static func canonical(record: Dictionary) -> String:
	return JSON.stringify(normalized(record), "", true, true)

static func hash_record(record: Dictionary) -> String:
	return canonical(record).sha256_text()

static func sign(record: Dictionary, secret: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret.hex_decode(), canonical(record).to_utf8_buffer()).hex_encode()

static func valid_record(record: Dictionary) -> bool:
	# Reserve the event payload and record levels used by the control envelope.
	return Transport._json_value(record, 2) and Validator.validate_file(record, "res://schemas/result_record.schema.json") == "" and canonical(record).to_utf8_buffer().size() <= 16384
