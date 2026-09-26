extends Node
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var server := false
var players: Dictionary = {}
var peers: Dictionary = {}
var latest: Dictionary = {}
var revision := 0
var elapsed := 0.0

func admit(identity: Dictionary, peer: int, badge: String, asset_revision: int) -> void:
	players[identity.user_id] = {"user_id": identity.user_id, "display_name": identity.display_name, "badge": badge, "asset_revision": asset_revision}
	peers[identity.user_id] = peer
	revision += 1
	_publish()

func remove_player(user_id: String) -> void:
	players.erase(user_id)
	peers.erase(user_id)
	revision += 1
	_publish()

func _process(delta: float) -> void:
	if server:
		elapsed += delta
		if elapsed >= 0.2:
			elapsed = 0.0
			_publish()

func _publish() -> void:
	if not is_inside_tree():
		return
	var value := {"revision": revision, "players": players.values().duplicate(true)}
	for peer in peers.values():
		if int(peer) > 1:
			world_state.rpc_id(int(peer), value)

@rpc("authority", "call_remote", "reliable", 1)
func world_state(value: Dictionary) -> void:
	if not server and Validator.validate_file(value, "res://schemas/managed_template_state.schema.json") == "" and int(value.revision) >= int(latest.get("revision", 0)):
		latest = value.duplicate(true)
