extends SceneTree
const Client = preload("res://sdk/roomkit/client/room_client.gd")
const World = preload("res://examples/blocks/game.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var client
var world
var settings: Dictionary
var deadline := 0
var input_clock := 0.0
var snapshots := 0
var last_tick := -1
var last_snapshot := 0
var snapshot_gaps: Array = []
var seen_players := 0
var min_x := INF
var max_x := -INF

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--client-config="):
			var path := argument.trim_prefix("--client-config=")
			settings = Wire.decode(FileAccess.get_file_as_bytes(path))
			DirAccess.remove_absolute(path)
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _run() -> void:
	client = Client.new()
	root.add_child(client)
	world = World.new()
	world.name = "GameWorld"
	root.add_child(world)
	if not client.configure(settings):
		finish(false, "CONFIGURE_FAILED")
		return
	var session: Dictionary = await client.open_session("load client")
	if not session.ok:
		finish(false, session.code)
		return
	var joined: Dictionary = await client.join_room(settings.room_id)
	if settings.get("expect_full", false):
		finish(not joined.ok and joined.code == "ROOM_FULL", joined.code)
		return
	if not joined.ok:
		finish(false, joined.code)
		return
	write_report({"phase": "JOINED"})
	while not FileAccess.file_exists(settings.measure_file) and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	snapshot_gaps.sort()
	write_report({"phase": "MEASURED", "moved": max_x - min_x > 20, "players": seen_players, "inputs": world.sequence, "snapshots": snapshots, "tick": last_tick, "snapshot_gap_p95_ms": snapshot_gaps[int(snapshot_gaps.size() * 0.95)] if not snapshot_gaps.is_empty() else 0, "sent_bytes": enet_stat(ENetConnection.HOST_TOTAL_SENT_DATA), "received_bytes": enet_stat(ENetConnection.HOST_TOTAL_RECEIVED_DATA)})
	while not FileAccess.file_exists(settings.stop_file) and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	await client.leave_room()
	finish(true, "")

func _process(delta: float) -> bool:
	if client == null or client.state != "IN_ROOM":
		return false
	input_clock += delta
	var now := Time.get_ticks_msec()
	if input_clock >= 0.05:
		input_clock = 0
		world.send_direction(Vector2(1 if (now / 1600) % 2 == 0 else -1, 0))
	var tick: int = int(world.latest.get("tick", -1))
	if tick != last_tick:
		if last_snapshot > 0:
			snapshot_gaps.append(now - last_snapshot)
		last_snapshot = now
		last_tick = tick
		snapshots += 1
		seen_players = maxi(seen_players, world.latest.get("players", []).size())
		for player in world.latest.get("players", []):
			if player.user_id == client.identity.user_id:
				min_x = minf(min_x, float(player.x))
				max_x = maxf(max_x, float(player.x))
	return false

func enet_stat(kind: int) -> float:
	return client.enet.host.pop_statistic(kind) if client.enet != null else 0.0

func finish(ok: bool, code: String) -> void:
	if client != null:
		client.close()
	write_report({"phase": "DONE", "ok": ok, "code": code}, settings.output + ".done")
	quit(0 if ok else 1)

func write_report(value: Dictionary, path: String = "") -> void:
	if path == "":
		path = settings.output
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
