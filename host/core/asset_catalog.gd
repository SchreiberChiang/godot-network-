extends RefCounted
## Immutable, trusted deployment configuration; never accept this from a player.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var _config: Dictionary = {}

func configure(value: Dictionary) -> String:
	if Validator.validate_file(value, "res://schemas/asset_catalog.schema.json") != "":
		return "INVALID_ASSET_CATALOG"
	for game in value.games.values():
		if not value.spaces.has(game.space):
			return "UNKNOWN_ASSET_SPACE"
		var items: Dictionary = value.spaces[game.space].items
		for slot in game.slots.values():
			if not slot.default in slot.allowed:
				return "INVALID_DEFAULT_ITEM"
			for item_id in slot.allowed:
				if not items.has(item_id):
					return "UNKNOWN_ITEM"
			if int(items[slot.default].price) != 0:
				return "INVALID_DEFAULT_ITEM"
	_config = value.duplicate(true)
	return ""

func game(game_id: String) -> Dictionary:
	return _config.get("games", {}).get(game_id, {}).duplicate(true)

func space_for(game_id: String) -> String:
	return str(game(game_id).get("space", ""))

func items_for(game_id: String) -> Dictionary:
	var space := space_for(game_id)
	return _config.get("spaces", {}).get(space, {}).get("items", {}).duplicate(true)

func allows(game_id: String, item_id: String) -> bool:
	for slot in game(game_id).get("slots", {}).values():
		if item_id in slot.allowed:
			return true
	return false

func default_items(game_id: String) -> Array:
	var result: Array = []
	for slot in game(game_id).get("slots", {}).values():
		if not slot.default in result:
			result.append(slot.default)
	return result
