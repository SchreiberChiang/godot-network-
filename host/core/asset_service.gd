extends RefCounted
## Internal trusted service. Not a network handler: authentication and live-room fencing
## must happen before calling it. Run on a bounded worker, never in the room polling loop.
const Catalog = preload("res://host/core/asset_catalog.gd")
const Rules = preload("res://host/core/asset_rules.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var catalog = Catalog.new()
var repository = Repository.new()
var _ready := false

func initialize(directory: String, configuration: Dictionary) -> Dictionary:
	_ready = false
	var error: String = catalog.configure(configuration)
	if error != "":
		return Wire.failure(error)
	var result: Dictionary = repository.initialize(directory, "assets.sqlite")
	_ready = result.ok
	return result

func read(user_id: String, game_id: String) -> Dictionary:
	if not _ready or user_id.is_empty() or user_id.length() > 128:
		return Wire.failure("INVALID_ASSET_COMMAND")
	var space: String = catalog.space_for(game_id)
	if space == "":
		return Wire.failure("UNKNOWN_GAME")
	var result: Dictionary = repository.execute({"op": "asset.read", "user_id": user_id, "space_id": space})
	if not result.ok:
		return result
	var state: Dictionary = Rules.empty_state() if result.body == "" else Wire.decode(str(result.body).to_utf8_buffer(), "res://schemas/asset_state.schema.json", 65536)
	if state.is_empty():
		return Wire.failure("STORAGE_UNAVAILABLE")
	var projected := Rules.project(state, catalog, game_id)
	if Validator.validate_file(projected, "res://schemas/asset_state.schema.json") != "":
		return Wire.failure("ASSET_LIMIT_EXCEEDED")
	return {"ok": true, "space_id": space, "state": projected}

func perform(identity: Dictionary, game_id: String, command: Dictionary, policy, trusted_context: Dictionary) -> Dictionary:
	if not _valid_identity(identity) or policy == null or not policy.has_method("authorize"):
		return Wire.failure("AUTH_FAILED")
	if Validator.validate_file(command, "res://schemas/asset_command.schema.json") != "" or command.get("kind", "") not in ["purchase", "select"]:
		return Wire.failure("INVALID_ASSET_COMMAND")
	var denied: String = policy.authorize(identity.duplicate(true), trusted_context.duplicate(true), command.duplicate(true))
	if denied != "":
		return Wire.failure(denied)
	return _transact(str(identity.user_id), game_id, command, str(identity.user_id), false)

func adjust(administrator: Dictionary, user_id: String, game_id: String, command: Dictionary) -> Dictionary:
	if not _valid_identity(administrator) or administrator.get("role", "") != "admin":
		return Wire.failure("ADMIN_REQUIRED")
	if command.get("kind", "") != "adjust":
		return Wire.failure("INVALID_ASSET_COMMAND")
	return _transact(user_id, game_id, command, str(administrator.user_id), true)

func manage(administrator: Dictionary, user_id: String, game_id: String, command: Dictionary) -> Dictionary:
	if not _valid_identity(administrator) or administrator.get("role", "") != "admin":
		return Wire.failure("ADMIN_REQUIRED")
	if command.get("kind", "") not in ["grant", "revoke", "configure", "adjust"]:
		return Wire.failure("INVALID_ASSET_COMMAND")
	return _transact(user_id, game_id, command, str(administrator.user_id), true)

func _transact(user_id: String, game_id: String, command: Dictionary, actor_id: String, administrative: bool) -> Dictionary:
	if not _ready or user_id.is_empty() or user_id.length() > 128 or Validator.validate_file(command, "res://schemas/asset_command.schema.json") != "":
		return Wire.failure("INVALID_ASSET_COMMAND")
	var space: String = catalog.space_for(game_id)
	if space == "":
		return Wire.failure("UNKNOWN_GAME")
	var fingerprint := Format.hash_record({"user_id": user_id, "actor_id": actor_id, "game_id": game_id, "space_id": space, "command": command})
	var receipt: Dictionary = repository.execute({"op": "asset.receipt", "user_id": user_id, "request_id": command.request_id, "fingerprint": fingerprint})
	if not receipt.ok:
		return receipt
	if receipt.found:
		return _decode_receipt(receipt)
	var current := read(user_id, game_id)
	if not current.ok:
		return current
	var changed := Rules.apply(current.state, catalog, game_id, command, administrative)
	if not changed.ok:
		return changed
	var result: Dictionary = repository.execute({"op": "asset.commit", "user_id": user_id, "space_id": space, "request_id": command.request_id, "fingerprint": fingerprint, "actor_id": actor_id, "command": Format.canonical(command), "expected_revision": current.state.revision, "body": Format.canonical(changed.state)})
	return _decode_receipt(result)

static func _decode_receipt(result: Dictionary) -> Dictionary:
	if not result.ok:
		return result
	var state := Wire.decode(str(result.get("body", "")).to_utf8_buffer(), "res://schemas/asset_state.schema.json", 65536)
	return Wire.failure("STORAGE_UNAVAILABLE") if state.is_empty() else {"ok": true, "code": result.get("code", ""), "state": state}

static func _valid_identity(identity: Dictionary) -> bool:
	return identity.get("user_id", null) is String and not identity.user_id.is_empty() and identity.user_id.length() <= 128
