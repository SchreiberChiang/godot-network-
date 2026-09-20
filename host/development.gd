extends RefCounted
## Development composition root; concrete fixture paths do not belong to host/core.
static func register_game(manager, fixture: String = "") -> Dictionary:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/game_manifest.json"))
	var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://examples/minimal/room.gd", "--"]
	if not fixture.is_empty():
		args.append("--fixture=" + fixture)
	return manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": manager.config.get("godot_executable", OS.get_executable_path()), "args": args}})

static func register_multiplayer(manager) -> Dictionary:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://examples/minimal/multiplayer_room.gd", "--"]
	return manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": manager.config.get("godot_executable", OS.get_executable_path()), "args": args}})

static func register_artifact(manager, entry: Dictionary) -> Dictionary:
	var manifest: Dictionary = entry.manifest
	var args: Array = ["--headless", "--path", entry.project, "--log-file", str(entry.project).path_join("server.log"), "--script", "res://game/room.gd", "--"]
	return manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": manager.config.get("godot_executable", OS.get_executable_path()), "args": args}})
