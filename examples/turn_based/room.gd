extends "res://sdk/roomkit/server/room_runtime.gd"
const Adapter = preload("adapter.gd")

func _initialize() -> void:
	build_identity = JSON.parse_string(FileAccess.get_file_as_string("res://game_manifest.json"))
	adapter = Adapter.new()
	adapter.resolve_peer = _peer_for_user
	super._initialize()

func _peer_for_user(user_id: String) -> int:
	for peer in members:
		if members[peer].user_id == user_id and members[peer].state == "IN_ROOM":
			return int(peer)
	return 0
