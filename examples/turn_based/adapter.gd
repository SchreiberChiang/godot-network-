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
	world.round_finished.connect(_round_finished)
	Engine.get_main_loop().root.add_child(world)
	return true

func on_player_admitted(identity: Dictionary) -> void:
	world.admit(identity, resolve_peer.call(identity.user_id))

func on_player_left(identity: Dictionary, _reason: String) -> void:
	world.remove_player(identity.user_id)

func on_shutdown_requested(_reason: String) -> void:
	if persist_results and not world.players.is_empty():
		_emit_result(world.round_number, "aborted", world.players.values())
	world.set_process(false)

func _round_finished(index: int, rows: Array) -> void:
	if persist_results:
		_emit_result(index, "completed", rows)

func _emit_result(index: int, status: String, rows: Array) -> void:
	var scores: Array = []
	for player in rows:
		scores.append({"user_id": player.user_id, "score": player.score})
	result_requested.emit("round_" + str(index), status, {"round": index, "players": scores})
