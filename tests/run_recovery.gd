extends "res://tests/run_secure.gd"

func _run() -> void:
	report_name = "recovery"
	work = ProjectSettings.globalize_path("res://data/restart-test-" + Wire.uid())
	var output: Array = []
	check(OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_data.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://"), "-DataRoot", work], output) == 0, "private restart fixture")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	base.godot_executable = OS.get_executable_path()
	var free_range := free_udp_range()
	if not check(free_range > 0, "independent recovery UDP range available"):
		quit(1)
		return
	base.udp_first = free_range
	base.udp_last = free_range + 7
	check(manager.initialize(base).ok, "outer owner initialized")
	active = true
	# No lobby is used by this test; the base poll method needs a manager reference.
	lobby.manager = manager
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	base.control_port = probe.get_local_port()
	probe.stop()
	print("RECOVERY_TEST_PORTS udp_first=", base.udp_first, " udp_last=", base.udp_last, " control=", base.control_port)
	base.process_journal = work.path_join("processes.json")
	base.stop_file = work.path_join("stop.signal")
	var old := start_host("old", base)
	# Return the exact snapshot that satisfied the wait. The fixture replaces its
	# report continuously; a second file read can observe the replacement gap and
	# return {} even though the preceding predicate saw a valid READY report.
	var old_report := await wait_report(old, func(value: Dictionary): return value.get("phase", "") == "READY" and value.get("heartbeats", 0) >= 1, 20000)
	check(not old_report.is_empty(), "old real host and room READY")
	var old_port: int = int(old_report.get("port", 0))
	if not check(old_port >= base.udp_first and old_port <= base.udp_last, "captured READY snapshot has a valid persisted port"):
		await finish()
		return
	check(manager.launcher.terminate(old.launch_id), "kill only verified old host")
	check(await until(func(): return manager.launcher.probe(old.launch_id) == "exited", 6000), "old host exit confirmed")
	var replacement := start_host("replacement", base)
	var report := await wait_report(replacement, func(value: Dictionary): return value.get("phase", "") == "READY", 22000)
	check(not report.is_empty(), "replacement immediately starts a new room")
	check(report.get("initial_orphans", 0) == 1 and int(report.get("port", 0)) != old_port, "restart quarantines persisted port before new allocation")
	report = await wait_report(replacement, func(value: Dictionary): return value.get("orphans", -1) == 0, 20000)
	check(not report.is_empty(), "read-only identity inspection confirms old room exit before reclaim")
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
	report = await wait_report(uncertain, func(value: Dictionary): return value.get("phase", "") == "READY", 22000)
	check(not report.is_empty(), "unknown old identity does not prevent other free ports serving rooms")
	check(report.get("orphans", 0) == 1 and int(report.get("port", 0)) != old_port, "unknown identity remains isolated even if UDP currently appears free")
	check(manager.ports.can_bind(old_port), "unknown identity port remains quarantined after UDP probe confirms it is free")
	marker = FileAccess.open(base.stop_file, FileAccess.WRITE)
	marker.close()
	check(await until(func(): return manager.launcher.probe(uncertain.launch_id) == "exited", 18000), "uncertain fixture exits without killing unrelated process")
	await finish()
	print("RECOVERY_RESULT passed=", passed, " failed=", failed)

func wait_report(child: Dictionary, predicate: Callable, duration: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + duration
	while Time.get_ticks_msec() < deadline:
		var snapshot := read_report(child)
		if not snapshot.is_empty() and predicate.call(snapshot):
			return snapshot
		await create_timer(0.03).timeout
	return {}

func free_udp_range() -> int:
	# Separate candidates from this repository's normal development/operator ports.
	# Hold all eight probes while validating a candidate, then release for the
	# actual room bind. Startup still fails honestly if another process races us.
	for attempt in range(64):
		var first := 40000 + (Crypto.new().generate_random_bytes(2).decode_u16(0) % 1000) * 8
		var probes: Array[PacketPeerUDP] = []
		var available := true
		for port in range(first, first + 8):
			var udp := PacketPeerUDP.new()
			if udp.bind(port, "127.0.0.1") != OK:
				available = false
			probes.append(udp)
		for udp in probes:
			udp.close()
		if available:
			return first
	return 0

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
