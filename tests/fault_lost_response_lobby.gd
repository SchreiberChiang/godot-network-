extends "res://host/managed_lobby.gd"
## Test-only fault at the final WSS reply boundary. The normal handler has
## completed its real Operator RPC and SQLite commit before this connection dies.
var evidence_path := ""
var injected := false

func _dispatch(connection: Dictionary, message: Dictionary) -> void:
	if injected or message.type != "asset.purchase":
		await super._dispatch(connection, message)
		return
	if not peers.has(connection):
		return
	var result: Dictionary = await handle_async(connection, message)
	connection.pending = maxi(0, int(connection.pending) - 1)
	if not result.ok:
		if peers.has(connection):
			connection.ws.send_text(JSON.stringify(Wire.response(message, result)))
		return
	injected = true
	# Intentionally never serialize or send this successful reply. Disconnecting
	# the accepted TCP socket makes the real SDK observe transport loss, and the
	# inherited drop path asynchronously revokes only this player's old session.
	var state: Dictionary = result.payload.state
	_drop(connection)
	var file := FileAccess.open(evidence_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"operation_id": message.payload.operation_id, "request_id": message.request_id, "committed": true, "reply_sent": false, "tcp_disconnected": connection.tcp.get_status() == StreamPeerTCP.STATUS_NONE, "removed_from_lobby": not peers.has(connection), "credits": state.credits, "revision": state.revision, "owned": state.owned}))
	file.close()
