extends RefCounted
## Pure permanent-asset transition. Persistence and game-specific permissions are separate.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")

static func empty_state() -> Dictionary:
	return {"revision": 0, "credits": 0, "experience": 0, "owned": [], "profiles": {}}

static func project(state: Dictionary, catalog, game_id: String) -> Dictionary:
	var result := state.duplicate(true)
	for item in catalog.default_items(game_id):
		if not item in result.owned:
			result.owned.append(item)
	var selected: Dictionary = result.profiles.get(game_id, {}).duplicate(true)
	for slot_id in catalog.game(game_id).get("slots", {}):
		var slot: Dictionary = catalog.game(game_id).slots[slot_id]
		var item: String = selected.get(slot_id, "")
		if not item in slot.allowed or not item in result.owned:
			selected[slot_id] = slot.default
	result.profiles[game_id] = selected
	return result

static func apply(state: Dictionary, catalog, game_id: String, command: Dictionary, administrative: bool = false) -> Dictionary:
	if Validator.validate_file(state, "res://schemas/asset_state.schema.json") != "" or Validator.validate_file(command, "res://schemas/asset_command.schema.json") != "":
		return Wire.failure("INVALID_ASSET_COMMAND")
	if catalog.game(game_id).is_empty():
		return Wire.failure("UNKNOWN_GAME")
	var next := project(state, catalog, game_id)
	var items: Dictionary = catalog.items_for(game_id)
	match command.kind:
		"purchase":
			if not catalog.allows(game_id, command.item_id):
				return Wire.failure("UNKNOWN_ITEM")
			if command.item_id in next.owned:
				return Wire.failure("ALREADY_OWNED")
			var price := int(items[command.item_id].price)
			if int(next.credits) < price:
				return Wire.failure("INSUFFICIENT_CREDITS")
			next.credits = int(next.credits) - price
			next.owned.append(command.item_id)
		"grant", "revoke":
			if not administrative:
				return Wire.failure("ADMIN_REQUIRED")
			if not catalog.allows(game_id, command.item_id):
				return Wire.failure("UNKNOWN_ITEM")
			if command.kind == "grant":
				if command.item_id in next.owned:
					return Wire.failure("ALREADY_OWNED")
				next.owned.append(command.item_id)
			else:
				if command.item_id in catalog.default_items(game_id):
					return Wire.failure("ASSET_OPERATION_DENIED")
				if not command.item_id in next.owned:
					return Wire.failure("ITEM_NOT_OWNED")
				next.owned.erase(command.item_id)
				next = project(next, catalog, game_id)
		"select", "configure":
			if command.kind == "configure" and not administrative:
				return Wire.failure("ADMIN_REQUIRED")
			var slot: Dictionary = catalog.game(game_id).slots.get(command.slot, {})
			if not command.item_id in slot.get("allowed", []):
				return Wire.failure("INVALID_CONFIGURATION")
			if not command.item_id in next.owned:
				return Wire.failure("ITEM_NOT_OWNED")
			next.profiles[game_id][command.slot] = command.item_id
		"adjust":
			if not administrative:
				return Wire.failure("ADMIN_REQUIRED")
			next.credits = int(next.credits) + int(command.credits)
			next.experience = int(next.experience) + int(command.experience)
	next.revision = int(state.revision) + 1
	if Validator.validate_file(next, "res://schemas/asset_state.schema.json") != "":
		return Wire.failure("ASSET_LIMIT_EXCEEDED")
	return {"ok": true, "state": next}
