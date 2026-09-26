extends "res://sdk/roomkit/server/game_adapter.gd"
const World = preload("game.gd")
var resolve_peer: Callable
var world
var persist_results := false

func configure_room(context: Dictionary) -> bool:
	persist_results = context.get("results_enabled", false)
	world = World.new()
	world.name = "GameWorld"
	world.server = true
	var rules: Dictionary = context.get("options", {}).get("rules", {})
	var overrides: Dictionary = {}
	for key in rules:
		match key:
			"duration_seconds": overrides.duration_ms = int(rules[key]) * 1000
			"respawn_seconds": overrides.respawn_ms = int(rules[key]) * 1000
			"kill_limit": overrides.kill_limit = rules[key]
			_:
				world.free()
				return false
	if not world.configure(overrides):
		world.free()
		return false
	world.round_finished.connect(_round_finished)
	world.respawn_requested.connect(_respawn_requested)
	Engine.get_main_loop().root.add_child(world)
	return true

func on_asset_state(user_id: String, state: Dictionary) -> void:
	world.on_asset_state(user_id, state)

func set_asset_busy(user_id: String, busy: bool) -> void:
	world.set_asset_busy(user_id, busy)

func asset_context(user_id: String) -> Dictionary:
	return world.asset_context(user_id)

func complete_asset_refresh(user_id: String, operation: String, state: Dictionary) -> void:
	if operation == "respawn":
		world.complete_respawn(user_id, state)

func cancel_asset_refresh(user_id: String, operation: String) -> void:
	if operation == "respawn":
		world.cancel_respawn(user_id)

func on_player_admitted(identity: Dictionary) -> void:
	world.admit(identity, resolve_peer.call(identity.user_id))

func on_player_left(identity: Dictionary, _reason: String) -> void:
	world.remove_player(identity.user_id)

func on_shutdown_requested(_reason: String) -> void:
	# An interrupted round produces no completed result and therefore no reward.
	world.set_process(false)

func _respawn_requested(user_id: String) -> void:
	asset_refresh_requested.emit(user_id, "respawn")

func _round_finished(key: String, rows: Array) -> void:
	if persist_results:
		result_requested.emit(key, "completed", {"round": world.round_number - 1, "duration_ms": world.last_duration_ms, "players": rows})
