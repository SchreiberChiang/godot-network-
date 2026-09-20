extends Node
## Same RPC declarations and /root/NetRoom path on both sides.
signal preparation_received(snapshot: Dictionary)
signal confirmation_received(snapshot: Dictionary)
signal roster_received(snapshot: Dictionary)
signal loaded_received(peer_id: int, revision: int)
signal leave_received(peer_id: int)

@rpc("authority", "call_remote", "reliable")
func prepare(snapshot: Dictionary) -> void:
	preparation_received.emit(snapshot)

@rpc("authority", "call_remote", "reliable")
func confirm(snapshot: Dictionary) -> void:
	confirmation_received.emit(snapshot)

@rpc("authority", "call_remote", "reliable")
func roster(snapshot: Dictionary) -> void:
	roster_received.emit(snapshot)

@rpc("any_peer", "call_remote", "reliable")
func loaded(revision: int) -> void:
	if multiplayer.is_server():
		loaded_received.emit(multiplayer.get_remote_sender_id(), revision)

@rpc("any_peer", "call_remote", "reliable")
func leave() -> void:
	if multiplayer.is_server():
		leave_received.emit(multiplayer.get_remote_sender_id())
