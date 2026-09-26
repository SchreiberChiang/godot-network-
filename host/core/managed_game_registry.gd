extends RefCounted
## Trusted local composition metadata; never load this from a player request.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Catalog = preload("res://host/core/asset_catalog.gd")
const GameRegistry = preload("res://host/core/game_registry.gd")
var entries: Dictionary = {}
var catalog: Dictionary = {}
var policies: Dictionary = {}
var rewards: Dictionary = {}
var result_schemas: Dictionary = {}
var default_spaces: Dictionary = {}

func configure(raw: Dictionary, defaults: Dictionary = {}) -> String:
	var next := raw.duplicate(true)
	for game_id in next:
		if not next[game_id] is Dictionary:
			return "INVALID_GAME_REGISTRY"
		# Compatibility for previous locally generated indexes. New games must
		# supply every service explicitly, not inherit another game's behavior.
		if defaults.has(game_id) and defaults[game_id] is Dictionary:
			for key in defaults[game_id]:
				if not next[game_id].has(key):
					next[game_id][key] = defaults[game_id][key]
	if Validator.validate_file(next, "res://schemas/managed_game_registry.schema.json") != "":
		return "INVALID_GAME_REGISTRY"
	var merged := {"version": 1, "spaces": {}, "games": {}}
	var next_policies := {}
	var next_rewards := {}
	var next_schemas := {}
	var spaces := {}
	for game_id in next:
		var entry: Dictionary = next[game_id]
		if entry.manifest.game_id != game_id or entry.manifest.sdk_version != "0.5.0":
			return "INVALID_GAME_REGISTRY"
		# Reuse the host's semantic checks (limits and deployment placeholders),
		# not just the manifest's structural schema. This never starts a process.
		var manifest_check: Dictionary = GameRegistry.new().register_game(entry.manifest, {entry.manifest.server_artifact: {"executable": OS.get_executable_path(), "args": []}})
		if not manifest_check.ok:
			return "INVALID_GAME_REGISTRY"
		for key in ["project", "server_executable", "server_pack", "client_executable", "client_pack"]:
			if entry.has(key):
				entry[key] = _path(str(entry[key]), "res://", true)
				if entry[key] == "":
					return "INVALID_GAME_REGISTRY"
		for key in ["asset_catalog", "asset_policy", "result_schema", "reward_script"]:
			if entry.has(key):
				entry[key] = _path(str(entry[key]), entry.project, false)
				if entry[key] == "" or not FileAccess.file_exists(entry[key]):
					return "GAME_SERVICE_MISSING"
		var source := Wire.decode(FileAccess.get_file_as_bytes(entry.asset_catalog), "", 262144)
		var checked = Catalog.new()
		if checked.configure(source) != "" or not source.games.has(game_id):
			return "INVALID_ASSET_CATALOG"
		var thresholds: Array = source.get("level_thresholds", [0])
		if merged.has("level_thresholds") and merged.level_thresholds != thresholds:
			return "ASSET_CATALOG_CONFLICT"
		merged.level_thresholds = thresholds.duplicate()
		var binding: Dictionary = source.games[game_id].duplicate(true)
		var space: String = binding.space
		if not merged.spaces.has(space):
			merged.spaces[space] = {"items": {}}
		if not _merge_items(merged.spaces[space].items, source.spaces[space].items):
			return "ASSET_CATALOG_CONFLICT"
		merged.games[game_id] = binding
		spaces[game_id] = space
		if not str(entry.asset_policy).ends_with(".gd"):
			return "INVALID_GAME_SERVICE"
		var policy_script = load(entry.asset_policy)
		if not _valid_service_script(policy_script, "authorize", 3):
			return "INVALID_GAME_SERVICE"
		var policy = policy_script.new()
		if not policy is RefCounted or not policy.has_method("authorize"):
			return "INVALID_GAME_SERVICE"
		next_policies[game_id] = policy
		var schema: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry.result_schema))
		if not schema is Dictionary or schema.is_empty():
			return "INVALID_GAME_SERVICE"
		next_schemas[game_id] = entry.result_schema
		if entry.has("reward_script"):
			if not str(entry.reward_script).ends_with(".gd"):
				return "INVALID_GAME_SERVICE"
			var reward_script = load(entry.reward_script)
			if not _valid_service_script(reward_script, "calculate", 1):
				return "INVALID_GAME_SERVICE"
			var calculator = reward_script.new()
			if not calculator is RefCounted or not calculator.has_method("calculate"):
				return "INVALID_GAME_SERVICE"
			next_rewards[game_id] = calculator
	if Catalog.new().configure(merged) != "":
		return "INVALID_ASSET_CATALOG"
	entries = next
	catalog = merged
	policies = next_policies
	rewards = next_rewards
	result_schemas = next_schemas
	default_spaces = spaces
	return ""

func valid_spaces(value: Variant) -> bool:
	if not value is Dictionary or value.size() != default_spaces.size():
		return false
	for game_id in default_spaces:
		if not value.get(game_id) in [default_spaces[game_id], "shared"]:
			return false
	return true

func catalog_for(spaces: Dictionary) -> Dictionary:
	if not valid_spaces(spaces):
		return {}
	var value := catalog.duplicate(true)
	var shared := {"items": {}}
	for game_id in spaces:
		if spaces[game_id] == "shared":
			if not _merge_items(shared.items, catalog.spaces[default_spaces[game_id]].items):
				return {}
		value.games[game_id].space = spaces[game_id]
	if not shared.items.is_empty():
		value.spaces.shared = shared
	# Individually valid catalogs can exceed a space's item limit when shared.
	# Reject before the operator persists a configuration it cannot initialize.
	if Catalog.new().configure(value) != "":
		return {}
	return value

static func _valid_service_script(script: Variant, method: String, argument_count: int) -> bool:
	if not script is Script or not script.can_instantiate():
		return false
	var base: String = script.get_instance_base_type()
	if base != "RefCounted" and not ClassDB.is_parent_class(base, "RefCounted"):
		return false
	var has_method := false
	# Include inherited script methods, including an inherited constructor.
	var cursor: Script = script
	var checked_init := false
	while cursor != null:
		for definition in cursor.get_script_method_list():
			var name: String = definition.name
			var count: int = definition.args.size()
			var required: int = count - definition.default_args.size()
			if name == "_init" and not checked_init:
				checked_init = true
				if required > 0:
					return false
			if name == method and not has_method:
				if required > argument_count or count < argument_count:
					return false
				has_method = true
		cursor = cursor.get_base_script()
	return has_method

static func _merge_items(target: Dictionary, source: Dictionary) -> bool:
	for item_id in source:
		if target.has(item_id) and target[item_id] != source[item_id]:
			return false
		target[item_id] = source[item_id].duplicate(true)
	return true

static func _path(value: String, base: String, disk: bool) -> String:
	if value.to_utf8_buffer().has(0) or value.contains("\n") or value.contains("\r") or value.begins_with("user://"):
		return ""
	if value.begins_with("res://"):
		return Paths.absolute(value) if disk else value.simplify_path()
	if "://" in value:
		return ""
	if value.is_absolute_path():
		return value.simplify_path()
	var joined := base.path_join(value).simplify_path()
	return Paths.absolute(joined) if disk else joined
