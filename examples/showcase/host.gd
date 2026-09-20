extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Lobby = preload("res://host/lobby_server.gd")
const Development = preload("res://host/development.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Results = preload("res://host/core/result_service.gd")
var manager = Manager.new()
var results = Results.new()
var result_root := ""
var lobby = Lobby.new()
var automated := false
var visual := false
var initialized := false
var passed := 0
var failed := 0
var processes: Array = []
var rooms: Dictionary = {}
var artifacts: Dictionary = {}
var work := ""
var stop_file := ""
var args: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	visual = args.get("--visual", "false") == "true"
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if initialized:
		manager.poll()
		lobby.poll()
	return false

func _run() -> void:
	work = ProjectSettings.globalize_path("res://logs/games-" + Wire.uid())
	DirAccess.make_dir_recursive_absolute(work)
	stop_file = work.path_join("stop.signal")
	artifacts = Wire.decode(FileAccess.get_file_as_bytes("res://artifacts/games.json"))
	if artifacts.size() != 2:
		printerr("Run tools/build_games.ps1 first.")
		quit(1)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 10000
	result_root = ProjectSettings.globalize_path("res://data/showcase-results" if not automated else "res://data/game-results-" + Wire.uid())
	if not check(results.initialize(result_root, {"blocks": "res://schemas/summary_result.schema.json", "turns": "res://schemas/summary_result.schema.json"}).ok, "private SQLite result store initialized"):
		quit(1)
		return
	var recovery: Dictionary = results.recover()
	print("RESULT_RECOVERY accepted=", recovery.accepted, " rejected=", recovery.rejected, " pending=", recovery.pending)
	manager.result_service = results
	results.manager = manager
	if not check(manager.initialize(config).ok, "host initialized"):
		quit(1)
		return
	initialized = true
	if not check(lobby.start(manager) == OK, "loopback WebSocket lobby bound"):
		await finish()
		return
	for game in ["blocks", "turns"]:
		if not check(Development.register_artifact(manager, artifacts[game]).ok, "independent artifact registered " + game):
			await finish()
			return
		var map: String = artifacts[game].manifest.modes.sandbox.maps[0]
		var created: Dictionary = manager.create_room(game, {"mode": "sandbox", "map": map, "capacity": 16})
		if not check(created.ok, "created " + game):
			await finish()
			return
		rooms[game] = created.room_id
	check(await until(func(): return manager.snapshot(rooms.blocks).get("state", "") == "READY" and manager.snapshot(rooms.turns).get("state", "") == "READY", 22000), "both game processes READY simultaneously")
	if failed > 0:
		await finish()
		return
	var a: Dictionary = manager.snapshot(rooms.blocks)
	var b: Dictionary = manager.snapshot(rooms.turns)
	check(a.pid != b.pid and a.port != b.port and a.launch_id != b.launch_id, "games own distinct processes, ports and launches")
	var chosen: Array = ["blocks", "turns"] if automated else [args.get("--game", "blocks")]
	for game in chosen:
		for role in ["one", "two"]:
			start_client(game, role)
	if automated:
		check(await until(func(): return all_reports("PLAYING"), 35000), "four clients play in two simultaneous games")
		for process in processes:
			var report := read_report(process)
			check(report.get("cross_game_denied", false), "cross-game admission rejected " + process.label)
			check(report.get("snapshot", {}).get("players", []).size() == 2, "own game contains exactly its two players " + process.label)
			if process.game == "blocks":
				check(report.get("phase", "") == "PLAYING" and report.get("snapshot", {}).get("tick", 0) > 0, "both authoritative blocks moved " + process.label)
			else:
				check(int(report.get("snapshot", {}).get("round", 1)) >= 2, "turn-taking reached next round " + process.label)
			if visual:
				check(report.get("screenshot_saved", false), "rendered screenshot saved " + process.label)
		check(lobby.admissions.count(rooms.blocks, "CONNECTED") == 2 and lobby.admissions.count(rooms.turns, "CONNECTED") == 2, "four formal seats remain isolated by game")
		check(await until(func(): return results.accepted_count > 0, 10000), "real turn-based round committed to SQLite")
		var saved: Dictionary = results.repository.execute({"op": "inspect"})
		check(saved.ok and saved.count >= 1 and JSON.parse_string(saved.rows[0].body).game_id == "turns", "stored result belongs to turn-based game")
		var rejoin_marker := FileAccess.open(work.path_join("rejoin.signal"), FileAccess.WRITE)
		rejoin_marker.store_string("rejoin")
		rejoin_marker.close()
		check(await until(func(): return all_reports("REJOINED"), 15000), "four clients exercise leave and rejoin UI handlers")
		for process in processes:
			check(read_report(process).get("rejoined", false), "rejoin preserves identity and receives new world state " + process.label)
		check(lobby.admissions.count(rooms.blocks, "CONNECTED") == 2 and lobby.admissions.count(rooms.turns, "CONNECTED") == 2, "rejoin does not duplicate seats")
		var file := FileAccess.open(stop_file, FileAccess.WRITE)
		file.store_string("stop")
		file.close()
		check(await until(func(): return all_reports("DONE"), 12000), "all clients finish leaving")
		for process in processes:
			var report := read_report(process)
			check(report.get("ok", false) and report.get("returned_to_lobby", false), "client returns to same lobby identity " + process.label)
	else:
		print("两个游戏窗口已经打开。关闭两个窗口后，宿主会回收房间。")
		var deadline := Time.get_ticks_msec() + 1800000
		while Time.get_ticks_msec() < deadline:
			var live := false
			for process in processes:
				live = live or manager.launcher.probe(process.launch_id) != "exited"
			if not live:
				break
			await create_timer(0.5).timeout
	await finish()

func start_client(game: String, role: String) -> void:
	var launch := Wire.uid()
	var label := game + "-" + role
	var output := work.path_join(label + ".json")
	var arguments: Array = ["--path", artifacts[game].project, "--log-file", work.path_join(label + ".log"), "--script", "res://client.gd"]
	if automated and not visual:
		arguments.push_front("--headless")
	else:
		arguments.append_array(["--resolution", "820x650", "--position", "40,60" if role == "one" else "890,60"])
	arguments.append_array(["--", "--launch-id=" + launch, "--url=ws://127.0.0.1:" + str(lobby.port), "--role=" + role, "--room=" + rooms[game], "--other-room=" + rooms["turns" if game == "blocks" else "blocks"], "--output=" + output, "--stop-file=" + stop_file, "--automated=" + ("true" if automated else "false")])
	arguments.append("--rejoin-file=" + work.path_join("rejoin.signal"))
	if args.get("--smoke", "false") == "true":
		arguments.append("--close-after-ms=3500")
	if visual:
		arguments.append("--screenshot=" + work.path_join(label + ".png"))
	var result: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": arguments}, launch, PackedStringArray())
	check(result.ok, "verified client launch " + label)
	processes.append({"launch_id": launch, "output": output, "label": label, "game": game})

func read_report(process: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(process.output):
		return {}
	return Wire.decode(FileAccess.get_file_as_bytes(process.output))

func all_reports(phase: String) -> bool:
	for process in processes:
		if read_report(process).get("phase", "") != phase:
			return false
	return processes.size() == 4

func until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return bool(predicate.call())

func finish() -> void:
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 18000), "all game room processes exited and reclaimed")
	for process in processes:
		if not automated:
			check(read_report(process).get("ok", false), "interactive window completes close handler " + process.label)
		var exited := await until(func(): return manager.launcher.probe(process.launch_id) == "exited", 3000)
		if not exited:
			manager.launcher.terminate(process.launch_id)
			exited = await until(func(): return manager.launcher.probe(process.launch_id) == "exited", 4000)
		check(exited, "owned client process exited " + process.label)
		manager.launcher.forget(process.launch_id)
	check(lobby.admissions.seats.is_empty() and manager.ports.leases.is_empty(), "no admission or port leases remain")
	lobby.close()
	check(manager.close(), "host listeners closed")
	initialized = false
	var recovered: Dictionary = results.recover()
	print("RESULT_STORE path=", result_root, " recovered=", recovered.accepted, " pending=", recovered.pending)
	var reports: Array = []
	for process in processes:
		reports.append(read_report(process))
	var file := FileAccess.open("res://logs/games-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "visual": visual, "automated": automated, "evidence_dir": work, "result_store": result_root, "reports": reports, "artifacts": artifacts}, "  "))
	file.close()
	print("GAMES_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(value: bool, description: String) -> bool:
	if value:
		passed += 1
		print("PASS games: ", description)
	else:
		failed += 1
		printerr("FAIL games: ", description)
	return value
