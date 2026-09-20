extends RefCounted
## Server-owned manifest and artifact allowlist. Remote requests supply options only.

const SchemaValidator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const MANIFEST_SCHEMA := "res://schemas/game_manifest.schema.json"

var _games: Dictionary = {}


func register_game(manifest: Dictionary, artifacts: Dictionary) -> Dictionary:
	var schema_error: String = SchemaValidator.validate_file(manifest, MANIFEST_SCHEMA)
	if not schema_error.is_empty():
		return _failure("INVALID_MANIFEST")
	if _has_placeholder(manifest):
		return _failure("INVALID_MANIFEST")
	for mode: Dictionary in manifest.modes.values():
		if int(mode.min_players) > int(mode.max_players):
			return _failure("INVALID_MANIFEST")
		if int(mode.max_players) > int(manifest.max_players):
			return _failure("INVALID_MANIFEST")
	var artifact: String = manifest.server_artifact
	if not artifacts.has(artifact):
		return _failure("ARTIFACT_NOT_FOUND")
	if not artifacts[artifact] is Dictionary:
		return _failure("UNTRUSTED_ARTIFACT")
	var descriptor: Dictionary = artifacts[artifact]
	if not _valid_descriptor(descriptor):
		return _failure("UNTRUSTED_ARTIFACT")
	var game_id: String = manifest.game_id
	if _games.has(game_id):
		return _failure("GAME_ALREADY_REGISTERED")
	_games[game_id] = {
		"manifest": manifest.duplicate(true),
		"descriptor": descriptor.duplicate(true),
	}
	return {"ok": true, "code": ""}


func resolve(game_id: String) -> Dictionary:
	if not _games.has(game_id):
		return _failure("GAME_NOT_FOUND")
	var entry: Dictionary = _games[game_id]
	return {
		"ok": true,
		"code": "",
		"manifest": entry.manifest.duplicate(true),
		"descriptor": entry.descriptor.duplicate(true),
	}


func validate_options(game_id: String, options: Dictionary) -> Dictionary:
	var entry: Dictionary = resolve(game_id)
	if not entry.ok:
		return entry
	if options.size() != 3 or not options.has_all(["mode", "map", "capacity"]):
		return _failure("INVALID_OPTIONS")
	if not options.mode is String or not options.map is String:
		return _failure("INVALID_OPTIONS")
	var capacity: Variant = options.capacity
	if not (capacity is int or capacity is float):
		return _failure("INVALID_OPTIONS")
	if not is_finite(float(capacity)) or float(capacity) != floor(float(capacity)):
		return _failure("INVALID_OPTIONS")
	var modes: Dictionary = entry.manifest.modes
	if not modes.has(options.mode):
		return _failure("INVALID_OPTIONS")
	var mode: Dictionary = modes[options.mode]
	if not options.map in mode.maps:
		return _failure("INVALID_OPTIONS")
	if capacity < mode.min_players or capacity > mode.max_players:
		return _failure("INVALID_OPTIONS")
	return {
		"ok": true,
		"code": "",
		"options": {"mode": options.mode, "map": options.map, "capacity": int(capacity)},
	}


func _valid_descriptor(descriptor: Dictionary) -> bool:
	if descriptor.size() != 2 or not descriptor.has_all(["executable", "args"]):
		return false
	if not descriptor.executable is String or not descriptor.args is Array:
		return false
	var executable: String = descriptor.executable
	if executable.is_empty() or not executable.is_absolute_path():
		return false
	if executable.begins_with("res://") or executable.begins_with("user://"):
		return false
	for argument: Variant in descriptor.args:
		if not argument is String:
			return false
	# File existence belongs to ProcessLauncher: stale deployments have a distinct
	# launch failure and must exercise the same resource cleanup as other failures.
	return true


func _has_placeholder(manifest: Dictionary) -> bool:
	for key: String in ["godot_version", "build_id", "sdk_version", "compatibility_id", "server_artifact"]:
		var value: String = str(manifest[key]).to_upper()
		if value.contains("PIN_EXACT") or value.contains("PLACEHOLDER") or value.contains("REPLACE_ME"):
			return true
	var version_pattern := RegEx.new()
	version_pattern.compile("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_.-]+$")
	return version_pattern.search(str(manifest.godot_version)) == null


func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
