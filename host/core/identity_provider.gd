extends RefCounted
## Pluggable boundary. The supplied adapter authenticates provisioned opaque tokens.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var accounts: Dictionary = {}

func load_file(path: String) -> bool:
	var parsed := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/identities.schema.json", 65536)
	if parsed.is_empty():
		return false
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/identities.schema.json"))
	for digest in parsed.accounts:
		if str(digest).length() != 64 or Validator.validate(parsed.accounts[digest], schema.properties.accounts.additionalProperties) != "":
			return false
		for character in str(digest):
			if character not in "0123456789abcdef":
				return false
	accounts = parsed.accounts
	return true

func authenticate(credential: String, now: int) -> Dictionary:
	if credential.length() != 64:
		return Wire.failure("AUTH_FAILED")
	var record: Dictionary = accounts.get(credential.sha256_text(), {})
	if record.is_empty() or now >= int(record.expires):
		return Wire.failure("AUTH_FAILED")
	return {"ok": true, "expires": record.expires, "identity": {"user_id": record.user_id, "display_name": record.display_name, "role": record.role}}

func provision(user_id: String, display_name: String, role: String, expires: int) -> String:
	if role not in ["player", "admin"] or accounts.size() >= 128:
		return ""
	var record := {"user_id": user_id, "display_name": display_name, "role": role, "expires": expires}
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/identities.schema.json"))
	if Validator.validate(record, schema.properties.accounts.additionalProperties) != "":
		return ""
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	accounts[token.sha256_text()] = record
	return token

func save_file(path: String) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"accounts": accounts}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
