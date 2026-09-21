extends SceneTree
const Client = preload("res://sdk/roomkit/client/room_client.gd")
const World = preload("res://game/game.gd")
const View = preload("view.gd")
var client
var world
var view
var args: Dictionary = {}
var report: Dictionary = {}
var display_name := ""
var message := "连接中"
var busy := false
var automated := false
var finishing := false
var capturing := false
var playing := false
var rejoining := false
var started := 0
var input_elapsed := 0.0
var ready_since := 0
var initial_positions: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	automated = args.get("--automated", "false") == "true"
	started = Time.get_ticks_msec()
	auto_accept_quit = false
	root.close_requested.connect(_close)
	_run.call_deferred()

func _run() -> void:
	client = Client.new()
	root.add_child(client)
	world = World.new()
	world.name = "GameWorld"
	root.add_child(world)
	display_name = "玩家一" if args.get("--role", "one") == "one" else "玩家二"
	root.title = "RoomKit · " + world.title() + " · " + display_name
	view = View.new()
	view.app = self
	root.add_child(view)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game_manifest.json"))
	config.url = args.get("--url", "")
	if args.has("--client-config"):
		var bootstrap: Variant = JSON.parse_string(FileAccess.get_file_as_string(args["--client-config"]))
		DirAccess.remove_absolute(args["--client-config"])
		if bootstrap is Dictionary:
			config.merge(bootstrap, true)
	if not client.configure(config):
		await _finish(false, "CONFIGURE_FAILED")
		return
	var session: Dictionary = await client.open_session(display_name)
	if not session.ok:
		await _finish(false, session.code)
		return
	report.user_id = client.identity.user_id
	report.game_id = config.game_id
	if automated:
		var forbidden: Dictionary = await client.join_room(args["--other-room"])
		report.cross_game_denied = not forbidden.ok and forbidden.code == "BUILD_MISMATCH"
		if not report.cross_game_denied:
			await _finish(false, "CROSS_GAME_ALLOWED")
			return
	await _join()

func _join() -> void:
	busy = true
	message = "认证并加载游戏中"
	world.latest.clear()
	var joined: Dictionary = await client.join_room(args["--room"])
	busy = false
	message = "已返回大厅" if joined.ok else "入房失败：" + str(joined.code)
	if not joined.ok and automated:
		await _finish(false, joined.code)

func toggle_room() -> void:
	if busy:
		return
	if client.state == "IN_ROOM":
		busy = true
		await client.leave_room()
		world.latest.clear()
		message = "已返回大厅，身份保持不变"
		busy = false
	elif client.state == "LOBBY":
		await _join()

func choose(take: int) -> void:
	if client.state == "IN_ROOM" and world.has_method("choose"):
		world.choose(take)

func _process(delta: float) -> bool:
	if finishing or client == null:
		return false
	var now := Time.get_ticks_msec()
	if not automated and FileAccess.file_exists(args.get("--stop-file", "")):
		_close()
		return false
	if args.has("--close-after-ms") and now - started >= int(args["--close-after-ms"]):
		_close()
		return false
	if automated and now - started > 45000:
		_finish(false, "CLIENT_TIMEOUT")
		return false
	if client.state != "IN_ROOM":
		return false
	input_elapsed += delta
	if world.has_method("send_direction") and input_elapsed >= 0.05:
		input_elapsed = 0
		var direction := Vector2.ZERO
		if automated:
			if not playing:
				direction.x = 1.0 if args.get("--role") == "one" else -1.0
		elif root.has_focus():
			direction = Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).limit_length(1)
		world.send_direction(direction)
	if not automated:
		return false
	if world.latest.get("players", []).size() == 2 and ready_since == 0:
		ready_since = now
		for player in world.latest.players:
			initial_positions[player.user_id] = player.get("x", 0)
	if world.has_method("choose") and not playing and world.latest.get("active_user", "") == client.identity.user_id and world.latest.get("players", []).size() == 2 and input_elapsed >= 0.2:
		input_elapsed = 0
		world.choose(2 if int(world.latest.get("stones", 12)) >= 2 else 1)
	if not playing and not capturing and ready_since > 0:
		var success := false
		if world.has_method("send_direction") and now - ready_since > 900:
			success = true
			for player in world.latest.players:
				success = success and absf(float(player.x) - float(initial_positions.get(player.user_id, player.x))) >= 18
		elif world.has_method("choose"):
			success = int(world.latest.get("round", 1)) >= 2
		if success:
			_report_playing()
	if playing and FileAccess.file_exists(args.get("--stop-file", "")):
		_finish(true, "PLAYED_AND_LEFT")
	elif playing and not rejoining and FileAccess.file_exists(args.get("--rejoin-file", "")):
		_rejoin_check()
	return false

func _rejoin_check() -> void:
	rejoining = true
	# Exercise the same handlers as the visible leave/rejoin button.
	await toggle_room()
	var kept_identity: bool = client.state == "LOBBY" and client.identity.user_id == report.user_id
	await create_timer(0.3).timeout
	await toggle_room()
	var deadline := Time.get_ticks_msec() + 5000
	while world.latest.get("players", []).size() != 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	report.rejoined = kept_identity and client.state == "IN_ROOM" and world.latest.get("players", []).size() == 2
	report.rejoined_snapshot = world.latest.duplicate(true)
	report.phase = "REJOINED"
	_write()

func _report_playing() -> void:
	capturing = true
	if args.has("--screenshot"):
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(args["--screenshot"])
		report.screenshot_saved = error == OK
	report.snapshot = world.latest.duplicate(true)
	report.phase = "PLAYING"
	report.ok = true
	playing = true
	_write()

func _close() -> void:
	await _finish(true, "WINDOW_CLOSED")

func _finish(ok: bool, code: String) -> void:
	if finishing:
		return
	finishing = true
	if client != null:
		await client.leave_room()
		var rooms: Dictionary = await client.list_rooms()
		report.returned_to_lobby = rooms.ok and client.identity.get("user_id", "") == report.get("user_id", "")
		client.close()
	report.phase = "DONE"
	report.ok = ok and report.get("returned_to_lobby", false)
	report.code = code
	_write()
	print("GAME_CLIENT_RESULT game=", report.get("game_id", ""), " ok=", report.ok, " code=", code)
	quit(0 if report.ok else 1)

func _write() -> void:
	var path: String = args.get("--output", "")
	if path.is_empty():
		return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
