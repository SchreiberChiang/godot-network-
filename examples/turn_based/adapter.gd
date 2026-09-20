extends "res://sdk/roomkit/server/game_adapter.gd"
const World = preload("game.gd")
var resolve_peer: Callable
var world

func configure_room(_context: Dictionary) -> bool:
	world = World.new()
	world.name = "GameWorld"
	world.server = true
	Engine.get_main_loop().root.add_child(world)
	return true

func on_player_admitted(identity: Dictionary) -> void:
	world.admit(identity, resolve_peer.call(identity.user_id))

func on_player_left(identity: Dictionary, _reason: String) -> void:
	world.remove_player(identity.user_id)

func on_shutdown_requested(_reason: String) -> void:
	world.set_process(false)
