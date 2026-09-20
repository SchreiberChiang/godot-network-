extends SceneTree
## Standalone demo client: all network actions go through the reusable client SDK.
const Client = preload("res://sdk/roomkit/client/room_client.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var client
var args: Dictionary = {}
var phases: Array = []
var report: Dictionary = {}
var output := ""
var started := 0
var done := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	output = args.get("--output", "")
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _run() -> void:
	client = Client.new()
	root.add_child(client)
	client.join_progress.connect(func(phase): phases.append(phase))
	client.prepare_scene = _load_scene
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	manifest.url = args.get("--url", "")
	if not client.configure(manifest):
		_finish(false, "CONFIGURE")
		return
	var role: String = args.get("--role", "guest")
	var session: Dictionary = await client.open_session("Player One" if role == "creator" else "Player Two")
	if not session.ok:
		_finish(false, session.code)
		return
	report.user_id = client.identity.user_id
	if role == "intruder":
		var reservation: Dictionary = Wire.decode(FileAccess.get_file_as_bytes(args["--room-info"]))
		reservation.ticket = "0".repeat(64)
		var denied: Dictionary = await client._connect_reserved(reservation)
		_finish(not denied.ok and not phases.has("IN_ROOM"), "BAD_TICKET_REJECTED" if not denied.ok else "BAD_TICKET_ACCEPTED")
		return
	var room_id := ""
	if role == "creator":
		var options := {"mode": "sandbox", "map": "empty", "capacity": 2}
		var result: Dictionary = await client.create_room(options, "demo-create-once")
		if not result.ok:
			_finish(false, result.code)
			return
		room_id = result.payload.room.room_id
		var replay: Dictionary = await client.create_room(options, "demo-create-once")
		var conflict: Dictionary = await client.create_room({"mode": "sandbox", "map": "empty", "capacity": 3}, "demo-create-once")
		report.idempotency = replay.ok and replay.payload.room.room_id == room_id and conflict.get("code", "") == "IDEMPOTENCY_CONFLICT"
		if not report.idempotency:
			_finish(false, "IDEMPOTENCY")
			return
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if role == "creator":
			var current: Dictionary = await client.get_room(room_id)
			if current.ok and current.payload.room.state == "READY":
				break
		else:
			var available: Dictionary = await client.list_rooms()
			if available.ok and not available.payload.rooms.is_empty():
				room_id = available.payload.rooms[0].room_id
				break
		await create_timer(0.1).timeout
	if room_id == "":
		_finish(false, "ROOM_NOT_FOUND")
		return
	var joined: Dictionary = await client.join_room(room_id)
	if not joined.ok:
		_finish(false, joined.code)
		return
	report.room_id = room_id
	deadline = Time.get_ticks_msec() + 12000
	while client.snapshot.get("members", []).size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	if client.snapshot.get("members", []).size() != 2:
		_finish(false, "ROSTER_NOT_TWO")
		return
	report.members = client.snapshot.members.duplicate(true)
	report.phase = "TWO_PLAYERS"
	report.phases = phases.duplicate()
	_write()
	while not FileAccess.file_exists(args["--stop-file"]) and Time.get_ticks_msec() - started < 50000:
		await create_timer(0.05).timeout
	await client.leave_room()
	var list: Dictionary = await client.list_rooms()
	report.returned_to_lobby = client.state == "LOBBY" and list.ok and client.identity.user_id == report.user_id
	_finish(report.returned_to_lobby, "LEFT_ROOM")

func _load_scene(_snapshot: Dictionary) -> bool:
	# Deliberately slow loading verifies that network authentication isn't IN_ROOM.
	report.loading_barrier = client.state == "LOADING" and not phases.has("IN_ROOM")
	await create_timer(0.7 if args.get("--role", "") == "guest" else 0.1).timeout
	return report.loading_barrier

func _process(_delta: float) -> bool:
	if not done and Time.get_ticks_msec() - started > 55000:
		_finish(false, "CLIENT_WATCHDOG")
	return false

func _write() -> void:
	if output == "":
		return
	var file := FileAccess.open(output + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report))
	file.close()
	DirAccess.rename_absolute(output + ".tmp", output)

func _finish(ok: bool, code: String) -> void:
	if done:
		return
	done = true
	report.ok = ok
	report.code = code
	report.phase = "DONE"
	report.phases = phases.duplicate()
	_write()
	if is_instance_valid(client):
		client.close()
	print("PLAYER_RESULT ok=", ok, " code=", code)
	quit(0 if ok else 1)
