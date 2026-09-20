extends "res://sdk/roomkit/server/game_adapter.gd"
var players: Dictionary = {}

func on_player_admitted(identity: Dictionary) -> void:
	players[identity.user_id] = identity.duplicate()

func on_player_left(identity: Dictionary, _reason: String) -> void:
	players.erase(identity.user_id)

func on_shutdown_requested(_reason: String) -> void:
	players.clear()
