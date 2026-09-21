extends "res://tests/run_secure.gd"
var load_reports: Array = []
var second_room := ""

func _run() -> void:
	report_name = "load"
	work = ProjectSettings.globalize_path("res://data/load-test-" + Wire.uid())
	var output: Array = []
	check(OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_data.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://"), "-DataRoot", work], output) == 0, "private load fixture directory")
	security = Secure.create_local_certificate(work)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 20000
	config.async_start = true
	config.max_room_memory_mb = 512
	config.security = security
	check(manager.initialize(config).ok, "load host initialized")
	active = true
	lobby.identity_provider = provider
	check(lobby.start(manager, 0, security) == OK, "load WSS listener")
	var artifacts := Wire.decode(FileAccess.get_file_as_bytes("res://artifacts/games.json"))
	manifest = artifacts.blocks.manifest
	check(Development.register_artifact(manager, artifacts.blocks).ok, "independent blocks artifact registered")
	var first: Dictionary = manager.create_room("blocks", {"mode": "sandbox", "map": "arena", "capacity": 16})
	var second: Dictionary = manager.create_room("blocks", {"mode": "sandbox", "map": "arena", "capacity": 4})
	if not check(first.ok and second.ok, "two concurrent load rooms allocated"):
		await finish()
		return
	room = first.room_id
	second_room = second.room_id
	check(await until(func(): return manager.snapshot(room).state == "READY" and manager.snapshot(second_room).state == "READY", 24000), "both DTLS rooms READY")
	var expiry := int(Time.get_unix_time_from_system()) + 3600
	for index in range(20):
		var token: String = provider.provision("load-" + str(index), "Load " + str(index), "player", expiry)
		launch_load(index, token, room if index < 16 else second_room)
		await create_timer(0.05).timeout
	check(await until(func(): return reports_in_phase("JOINED") == 20, 35000), "20 actual encrypted clients join 16 + 4 seats")
	check(lobby.admissions.count(room, "CONNECTED") == 16 and lobby.admissions.count(second_room, "CONNECTED") == 4, "formal seat counts exactly match both room capacities")
	var rejected := launch_load(20, provider.provision("seventeenth", "Full", "player", expiry), room, true)
	check(await until(func(): return read_done(rejected).get("ok", false), 12000), "17th client receives ROOM_FULL without entering")
	await create_timer(15).timeout
	var marker := FileAccess.open(work.path_join("measure.signal"), FileAccess.WRITE)
	marker.close()
	check(await until(func(): return reports_in_phase("MEASURED") == 20, 8000), "all moving clients complete measured interval")
	for index in range(20):
		var report := read_report(children[index])
		check(report.get("moved", false) and int(report.get("inputs", 0)) >= 100 and int(report.get("snapshots", 0)) >= 50, "actual input and authoritative snapshots client " + str(index))
		check(report.get("players", 0) == (16 if index < 16 else 4), "client sees its own room population")
		load_reports.append(report)
	var memory: Array = [manager.snapshot(room).get("metrics", {}), manager.snapshot(second_room).get("metrics", {})]
	marker = FileAccess.open(work.path_join("stop.signal"), FileAccess.WRITE)
	marker.close()
	check(await until(func():
		for child in children:
			if not read_done(child).get("ok", false):
				return false
		return true, 12000), "all clients leave cleanly")
	await finish()
	var file := FileAccess.open("res://logs/load-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "players": 20, "room_populations": [16, 4], "measured_seconds": 15, "evidence_dir": work, "client_reports": load_reports, "server_metrics": memory}))
	file.close()
	print("LOAD_RESULT passed=", passed, " failed=", failed)

func launch_load(index: int, credential: String, room_id: String, full: bool = false) -> Dictionary:
	var launch := Wire.uid()
	var settings := manifest.duplicate(true)
	settings.merge({"url": "wss://localhost:" + str(lobby.port), "secure_enet": true, "ca_certificate": security.certificate, "credential": credential, "room_id": room_id, "output": work.path_join("client-" + str(index) + ".json"), "stop_file": work.path_join("stop.signal"), "measure_file": work.path_join("measure.signal"), "expect_full": full})
	var path := work.path_join("bootstrap-" + launch + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(settings))
	file.close()
	var result: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", work.path_join("client-" + str(index) + ".log"), "--script", "res://tests/fixtures/load_client.gd", "--"]}, launch, ["--launch-id=" + launch, "--client-config=" + path])
	check(result.ok, "owned load client launched " + str(index))
	var child := {"launch_id": launch, "output": settings.output}
	children.append(child)
	return child

func reports_in_phase(phase: String) -> int:
	var count := 0
	for child in children:
		if read_report(child).get("phase", "") == phase:
			count += 1
	return count

func read_done(child: Dictionary) -> Dictionary:
	var path: String = child.output + ".done"
	return Wire.decode(FileAccess.get_file_as_bytes(path)) if FileAccess.file_exists(path) else {}
