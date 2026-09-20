extends SceneTree
## No scenes, gameplay, assets or previous-project dependencies.
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
const GAME_ID := "minimal_room"
const BUILD_ID := "dev-001"
var transport = Transport.new()
var peer := StreamPeerTCP.new()
var enet := ENetMultiplayerPeer.new()
var context: Dictionary
var fixture := ""
var registered := false
var ready := false
var stopping := false
var quit_at := 0
var started_at := 0
var last_host := 0
var last_heartbeat := 0
var sequence := 0
var step := 0

func _initialize() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	fixture = args.get("--fixture", "")
	var path: String = args.get("--launch-config", "")
	if path.is_empty() or not FileAccess.file_exists(path):
		quit(2)
		return
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		quit(2)
		return
	context = value
	if context.get("launch_id", "") != args.get("--launch-id", "") or context.get("game_id", "") != GAME_ID or context.get("build_id", "") != BUILD_ID:
		quit(2)
		return
	started_at = Time.get_ticks_msec()
	last_host = started_at
	if fixture not in ["no_register", "delayed_register"]:
		peer.connect_to_host("127.0.0.1", int(context.control_port))

func _process(_delta: float) -> bool:
	if context.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if fixture == "no_register":
		if now - started_at > int(context.startup_timeout_ms) + 10000:
			quit(3)
		return false
	if fixture == "delayed_register" and now - started_at < 4000:
		return false
	if fixture == "delayed_register" and not registered and peer.get_status() == StreamPeerTCP.STATUS_NONE:
		peer.connect_to_host("127.0.0.1", int(context.control_port))
	if fixture == "control_drop" and sequence >= 2:
		peer.disconnect_from_host()
		if now - started_at > 15000:
			enet.close()
			quit(5)
		return false
	peer.poll()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if not registered:
			peer.set_no_delay(true)
			_send("room.register", {"token": context.token, "pid": OS.get_process_id()})
			context.token = ""
			registered = true
			if fixture != "no_ready":
				enet.set_bind_ip("127.0.0.1")
				var error := enet.create_server(int(context.udp_port), int(context.options.capacity))
				if error != OK:
					_send("room.failed", {"code": "PORT_BIND_FAILED"})
					stopping = true
					quit_at = now + 150
				else:
					ready = true
					_send("room.ready", {"udp_port": int(context.udp_port)})
		for message in transport.pump(peer):
			if not Protocol.validate(message).is_empty() or message.room_id != context.room_id or message.launch_id != context.launch_id or message.game_id != GAME_ID or message.build_id != BUILD_ID:
				quit(4)
				return false
			last_host = now
			match message.type:
				"room.drain":
					pass
				"room.stop":
					if fixture != "ignore_stop":
						stopping = true
						enet.close()
						_send("room.stopped", {})
						quit_at = now + 100
				"room.heartbeat":
					pass
				_:
					quit(4)
		if ready and not stopping and now - last_heartbeat >= int(context.heartbeat_ms):
			last_heartbeat = now
			sequence += 1
			if fixture != "logic_stall":
				step += 1
			if fixture != "silent":
				_send("room.heartbeat", {"sequence": sequence, "step": step})
		if not transport.flush(peer) or not transport.error.is_empty():
			quit(4)
	elif registered:
		enet.close()
		quit(5)
	if stopping and now >= quit_at:
		enet.close()
		quit(0)
	if not registered and now - started_at > int(context.startup_timeout_ms):
		quit(3)
	if registered and now - last_host > int(context.host_timeout_ms) + 10000:
		enet.close()
		quit(5)
	return false

func _send(type: String, payload: Dictionary) -> void:
	transport.queue(Protocol.event(type, context.room_id, context.launch_id, payload, GAME_ID, BUILD_ID))
