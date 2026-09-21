extends "res://tests/run_secure.gd"

func _run() -> void:
	report_name = "recovery"
	work = ProjectSettings.globalize_path("res://data/restart-test-" + Wire.uid())
	var output: Array = []
	check(OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_data.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://"), "-DataRoot", work], output) == 0, "private restart fixture")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	base.godot_executable = OS.get_executable_path()
	check(manager.initialize(base).ok, "outer owner initialized")
	active = true
	# No lobby is used by this test; the base poll method needs a manager reference.
	lobby.manager = manager
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	base.control_port = probe.get_local_port()
	probe.stop()
	base.process_journal = work.path_join("processes.json")
	base.stop_file = work.path_join("stop.signal")
	var old := start_host("old", base)
	check(await until(func(): return read_report(old).get("heartbeats", 0) >= 1, 20000), "old real host and room READY")
	var old_port: int = int(read_report(old).get("port", 0))
	check(manager.launcher.terminate(old.launch_id), "kill only verified old host")
	check(await until(func(): return manager.launcher.probe(old.launch_id) == "exited", 6000), "old host exit confirmed")
	var replacement := start_host("replacement", base)
	check(await until(func(): return read_report(replacement).get("phase", "") == "READY", 22000), "replacement immediately starts a new room")
	var report := read_report(replacement)
	check(report.get("initial_orphans", 0) == 1 and int(report.get("port", 0)) != old_port, "restart quarantines persisted port before new allocation")
	check(await until(func(): return read_report(replacement).get("orphans", -1) == 0, 20000), "read-only identity inspection confirms old room exit before reclaim")
	var marker := FileAccess.open(base.stop_file, FileAccess.WRITE)
	marker.close()
	check(await until(func(): return manager.launcher.probe(replacement.launch_id) == "exited", 18000), "replacement stops only its new child and exits")
	var journal := Wire.decode(FileAccess.get_file_as_bytes(base.process_journal))
	check(journal.get("entries", {"unknown": 1}).is_empty(), "normal shutdown empties persisted launch journal")
	# Explicitly test a crash before identity capture: never guess its PID or free its port.
	var unknown := {"version": 1, "entries": {"a".repeat(32): {"port": old_port, "owned": {}}}}
	var file := FileAccess.open(base.process_journal, FileAccess.WRITE)
	file.store_string(JSON.stringify(unknown))
	file.close()
	DirAccess.remove_absolute(base.stop_file)
	var uncertain := start_host("uncertain", base)
	check(await until(func(): return read_report(uncertain).get("phase", "") == "READY", 22000), "unknown old identity does not prevent other free ports serving rooms")
	report = read_report(uncertain)
	check(report.get("orphans", 0) == 1 and int(report.get("port", 0)) != old_port, "unknown identity remains isolated even if UDP currently appears free")
	marker = FileAccess.open(base.stop_file, FileAccess.WRITE)
	marker.close()
	check(await until(func(): return manager.launcher.probe(uncertain.launch_id) == "exited", 18000), "uncertain fixture exits without killing unrelated process")
	await finish()
	print("RECOVERY_RESULT passed=", passed, " failed=", failed)

func start_host(label: String, source: Dictionary) -> Dictionary:
	var config := source.duplicate(true)
	config.report = work.path_join(label + ".json")
	var path := work.path_join(label + "-settings.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(config))
	file.close()
	var launch := Wire.uid()
	var result: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", work.path_join(label + ".log"), "--script", "res://tests/fixtures/recovery_host.gd", "--"]}, launch, ["--launch-id=" + launch, "--settings=" + path])
	check(result.ok, "verified recovery host " + label)
	var child := {"launch_id": launch, "output": config.report}
	children.append(child)
	return child
