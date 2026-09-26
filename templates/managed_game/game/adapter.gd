extends "res://sdk/roomkit/server/game_adapter.gd"
const World = preload("res://game/world.gd")
var resolve_peer: Callable
var world
var game_id := ""
var confirmed: Dictionary = {}

func configure_room(context: Dictionary) -> bool:
	game_id = str(context.game_id)
	world = World.new()
	world.name = "ManagedTemplateWorld"
	world.server = true
	Engine.get_main_loop().root.add_child(world)
	return bool(context.get("assets_enabled", false))

func on_asset_state(user_id: String, state: Dictionary) -> void:
	confirmed[user_id] = state.duplicate(true)
	# This template applies the saved default on admission. Existing players do
	# not change appearance just because an administrator edits their profile.

func on_player_admitted(identity: Dictionary) -> void:
	var state: Dictionary = confirmed.get(identity.user_id, {})
	var badge: String = state.get("profiles", {}).get(game_id, {}).get("badge", "standard")
	if badge not in state.get("owned", []):
		badge = "standard"
	world.admit(identity, resolve_peer.call(identity.user_id), badge, int(state.get("revision", 0)))

func on_player_left(identity: Dictionary, _reason: String) -> void:
	confirmed.erase(identity.user_id)
	world.remove_player(identity.user_id)

func on_shutdown_requested(_reason: String) -> void:
	confirmed.clear()
	world.set_process(false)
