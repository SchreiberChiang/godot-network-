extends SceneTree
## Stand-in managed host for tests/run_posix_operator.gd. It speaks the same
## local RPC as host/managed_host.gd (bootstrap file, token, host.status,
## server.stop, exit on control loss) but starts no RoomManager, lobby or room.
##   --mode=normal       report status, leave on server.stop or control loss
##   --mode=silent       never connect (start timeout)
##   --mode=ignore_stop  answer server.stop but stay; leave only on control loss
## It reports the mode bits its bootstrap file had (it carries the RPC token)
## before it deletes that file, and exits by itself after 180 s in any case.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Bus = preload("res://sdk/roomkit/shared/local_rpc.gd")
var bus = Bus.new()
var mode := "normal"
var config_mode := -1
var started := 0
var last_status := 0
var bus_was_ready := false

func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	mode = args.get("--mode", "normal")
	started = Time.get_ticks_msec()
	var path: String = args.get("--managed-config", "")
	var bootstrap := Wire.decode(FileAccess.get_file_as_bytes(path), "", 65536)
	if bootstrap.is_empty() or bootstrap.rpc.launch_id != args.get("--launch-id", ""):
		quit(2)
		return
	config_mode = int(FileAccess.get_unix_permissions(path)) & 4095
	DirAccess.remove_absolute(path)
	if mode == "silent":
		return
	bus.requested.connect(_request)
	bus.connect_to(int(bootstrap.rpc.port), bootstrap.rpc.token, bootstrap.rpc.launch_id)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 180000:
		quit(3)
		return false
	if mode == "silent":
		return false
	bus.poll()
	if bus.ready():
		bus_was_ready = true
		if Time.get_ticks_msec() - last_status > 500:
			last_status = Time.get_ticks_msec()
			bus.broadcast("host.status", {"host": {"state": "RUNNING", "pid": OS.get_process_id(), "uptime": (last_status - started) / 1000, "maintenance": false, "countdown": 0, "error": "", "config_mode": config_mode}, "rooms": [], "players": []})
	elif bus_was_ready:
		quit(0)  # control connection lost: the Operator is gone or closed it
	elif Time.get_ticks_msec() - started > 10000:
		quit(2)  # never connected (same limit as host/managed_host.gd)
	return false

func _request(peer_id: String, request_id: String, action: String, _payload: Dictionary) -> void:
	if action == "server.stop":
		bus.respond(peer_id, request_id, {"ok": true, "code": "", "payload": {}})
		if mode != "ignore_stop":
			bus.broadcast("host.stopped", {})
			bus.poll()
			bus.close()
			quit(0)
		return
	bus.respond(peer_id, request_id, Wire.failure("HOST_NOT_RUNNING"))
