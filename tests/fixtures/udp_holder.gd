extends SceneTree
var socket := PacketPeerUDP.new()
var until := 0

func _initialize() -> void:
	var args: Dictionary = {}
	for item in OS.get_cmdline_user_args():
		var pair := item.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	if socket.bind(int(args.get("--port", 0)), "127.0.0.1") != OK:
		quit(2)
		return
	var file := FileAccess.open(args["--ready-path"], FileAccess.WRITE)
	file.store_string("BOUND")
	file.close()
	until = Time.get_ticks_msec() + 60000

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= until:
		socket.close()
		quit(0)
	return false
