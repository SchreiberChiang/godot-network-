extends "res://host/operator.gd"
## Runs the actual Operator initialization, _process, host lifecycle and SQLite
## backup helper. Only public connection publishing is suppressed for isolation.
## next_backup / historical restart timestamps are controlled test state: this
## is NOT a thirty-minute wall-clock test or a ten-minute waiting experiment.
var test_passed := 0
var test_failed := 0
var test_started := 0
var test_finishing := false
var test_worker_done := false
var test_host_history: Array = []

func _initialize() -> void:
	test_started = Time.get_ticks_msec()
	super._initialize()
	_exercise.call_deferred()

func _publish_connection() -> void:
	# Do not alter the public connection used by any other source/native fixture.
	pass

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if not test_finishing and Time.get_ticks_msec() - test_started > 240000:
		check(false, "isolated operator test deadline reached")
		_finish.call_deferred()
	return result

func _exercise() -> void:
	if not check(await wait_for(func(): return ready, 45000), "real Operator initializes account/assets/results databases and HTTP listener"):
		await _finish()
		return
	var remaining := next_backup - Time.get_ticks_msec()
	check(remaining > 1799000 and remaining <= 1800000, "real initialization schedules automatic backup thirty minutes ahead")
	# Metrics are outside this test; let an already-started real worker finish.
	next_metrics = Time.get_ticks_msec() + 3600000
	if not check(await wait_for(func(): return worker_count == 0 and not metrics_busy), "initial worker finishes before controlled scheduler scenarios"):
		await _finish()
		return
	if not await _scheduled_backups():
		await _finish()
		return
	if not await _restart_budget():
		await _finish()
		return
	await _finish()

func _scheduled_backups() -> bool:
	check(_backup_rows().is_empty(), "new private Operator has no preexisting backups")
	# Move only this test instance's deadline. The production polling callback,
	# worker drain, SQL online backup and audit are all executed without overrides.
	next_backup = Time.get_ticks_msec() + 400
	await create_timer(0.12).timeout
	check(_backup_rows().is_empty() and not storage_maintenance, "polling before controlled deadline does not start a backup")
	if not check(await wait_for(func(): return _backup_rows().size() == 1 and not storage_maintenance, 30000), "actual Operator timer invokes a real SQLite automatic backup"):
		return false
	var after_due := next_backup - Time.get_ticks_msec()
	check(after_due > 1770000 and after_due <= 1800000, "timer advances next deadline by thirty minutes rather than next frame")
	var first: Dictionary = _backup_rows()[0]
	check(first.automatic and first.kind == "automatic", "scheduled helper marks stored backup as automatic")
	var complete := true
	for file_name in ["accounts.sqlite", "assets.sqlite", "config.json", "server.crt", "server.key"]:
		complete = complete and first.files.has(file_name) and FileAccess.file_exists(root_path.path_join("backups").path_join(first.backup_id).path_join(file_name))
	check(complete, "real scheduled backup contains both databases, configuration and TLS material")
	check(_successful_backup_audits() == 1, "scheduler commits one system automatic-backup audit with scheduled reason")
	await create_timer(0.25).timeout
	check(_backup_rows().size() == 1 and _successful_backup_audits() == 1, "later polling frames do not duplicate the completed automatic backup")

	storage_maintenance = true
	next_backup = Time.get_ticks_msec() - 1
	var blocked_deadline := next_backup
	await create_timer(0.18).timeout
	check(_backup_rows().size() == 1 and next_backup == blocked_deadline, "storage maintenance blocks due timer without consuming its deadline")
	storage_maintenance = false
	if not check(await wait_for(func(): return _backup_rows().size() == 2 and not storage_maintenance, 30000), "one deferred automatic backup runs when storage maintenance ends"):
		return false

	quitting = true
	next_backup = Time.get_ticks_msec() - 1
	blocked_deadline = next_backup
	await create_timer(0.18).timeout
	check(_backup_rows().size() == 2 and next_backup == blocked_deadline, "quitting flag prevents scheduled backup and preserves pending deadline")
	quitting = false
	if not check(await wait_for(func(): return _backup_rows().size() == 3 and not storage_maintenance, 30000), "normal polling resumes one due backup after controlled quitting flag clears"):
		return false

	# A real worker thread is still executing when the next controlled due time
	# arrives. _backup must wait for it, rather than copy the databases mid-job.
	test_worker_done = false
	_hold_worker.call_deferred()
	if not check(await wait_for(func(): return worker_count > 0), "independent real worker entered production worker accounting"):
		return false
	next_backup = Time.get_ticks_msec() - 1
	await create_timer(0.12).timeout
	check(storage_maintenance and not test_worker_done and _backup_rows().size() == 3, "scheduled backup gates mutations and waits for outstanding real worker")
	if not check(await wait_for(func(): return test_worker_done and _backup_rows().size() == 4 and not storage_maintenance, 30000), "scheduled backup finishes only after outstanding worker drains"):
		return false
	check(_successful_backup_audits() == 4, "all four actual scheduler invocations record one successful audit each")
	return true

func _restart_budget() -> bool:
	var start_reply: Dictionary = await _start_host()
	if not check(start_reply.ok and host_owned and snapshot.host.state == "RUNNING", "actual managed host starts under this isolated Operator"):
		return false
	_capture_host("initial")
	var old_launch := host_launch
	requested_stop = true
	restart_requested = true
	check((await _host_command("server.stop", {"immediate": true})).ok, "intentional restart requests a real orderly host stop")
	if not check(await wait_for(func(): return host_owned and host_launch != old_launch and snapshot.host.state == "RUNNING", 35000), "intentional restart confirms exit and starts a new real process"):
		return false
	check(restart_times.is_empty(), "intentional restart consumes no crash-restart allowance")
	_capture_host("intentional_restart")

	for crash_number in range(1, 5):
		old_launch = host_launch
		var owned: Dictionary = launcher.record(old_launch)
		if not check(owned.get("verified", false) and int(owned.get("parent_pid", 0)) == OS.get_process_id(), "crash %d targets only a verified child of this test" % crash_number):
			return false
		var killed: Dictionary = await _work(_terminate_owned.bind(owned))
		if not check(killed.get("state", "") == "exited", "crash %d actually terminates the exact owned host process" % crash_number):
			return false
		if crash_number <= 3:
			if not check(await wait_for(func(): return host_owned and host_launch != old_launch and snapshot.host.state == "RUNNING", 35000), "crash %d automatically starts a real replacement host" % crash_number):
				return false
			check(restart_times.size() == crash_number, "crash %d consumes exactly one restart allowance" % crash_number)
			var marker := Wire.decode(FileAccess.get_file_as_bytes(root_path.path_join("host-running.json")))
			check(marker.get("launch_id", "") == host_launch and marker.get("verified", false), "replacement %d publishes only its new verified ownership marker" % crash_number)
			_capture_host("automatic_restart_%d" % crash_number)
		else:
			if not check(await wait_for(func(): return not host_owned and not host_closing and snapshot.host.get("error", "") == "RESTART_LIMIT_REACHED", 15000), "fourth real crash leaves RESTART_LIMIT_REACHED instead of restarting"):
				return false
			check(restart_times.size() == 3 and restart_after == 0 and not FileAccess.file_exists(root_path.path_join("host-running.json")), "limit leaves three recorded attempts, no restart timer and no stale ownership marker")
			await create_timer(2.3).timeout
			check(not host_owned and not starting and host_launch == old_launch and snapshot.host.state == "FAILED", "operator stays failed beyond the normal restart delay after quota exhaustion")
	check(Time.get_ticks_msec() - int(restart_times[0]) < 600000, "all three actual automatic restarts occurred inside the ten-minute window")

	# Seed historical timestamps only after proving four real crashes and the cap.
	# We do not claim to have waited ten minutes. Entries are well clear of the
	# threshold to avoid substituting scheduler jitter for expiry verification.
	start_reply = await _start_host()
	if not check(start_reply.ok and host_owned, "explicit start is possible after automatic restart limit"):
		return false
	_capture_host("manual_after_limit")
	var now := Time.get_ticks_msec()
	var expired := now - 630000
	var recent := now - 570000
	restart_times = [expired, expired - 1000, recent]
	old_launch = host_launch
	var killed: Dictionary = await _work(_terminate_owned.bind(launcher.record(host_launch)))
	if not check(killed.get("state", "") == "exited" and await wait_for(func(): return host_owned and host_launch != old_launch and snapshot.host.state == "RUNNING", 35000), "real crash can restart when controlled historical attempts expire"):
		return false
	check(restart_times.size() == 2 and restart_times.has(recent) and not restart_times.has(expired), "ten-minute rolling filter drops old entries, retains recent one and adds this restart")
	_capture_host("restart_after_controlled_history_expiry")
	var consumed := restart_times.duplicate()
	requested_stop = true
	restart_requested = false
	check((await _host_command("server.stop", {"immediate": true})).ok, "explicit stop requests actual managed host shutdown")
	if not check(await wait_for(func(): return not host_owned and not host_closing and snapshot.host.state == "STOPPED", 20000), "explicit stop confirms actual host exit"):
		return false
	await create_timer(2.3).timeout
	check(not host_owned and restart_after == 0 and restart_times == consumed, "explicit stop neither auto-restarts nor consumes a crash allowance")
	return true

func _hold_worker() -> void:
	await _work(_delayed_worker)
	test_worker_done = true

static func _delayed_worker() -> Dictionary:
	OS.delay_msec(1000)
	return {"ok": true}

func _backup_rows() -> Array:
	var rows: Array = []
	var directory := root_path.path_join("backups")
	if not DirAccess.dir_exists_absolute(directory):
		return rows
	for name in DirAccess.get_directories_at(directory):
		if name.begins_with("backup-"):
			var value := Wire.decode(FileAccess.get_file_as_bytes(directory.path_join(name).path_join("manifest.json")), "", 65536)
			if not value.is_empty():
				rows.append(value)
	return rows

func _successful_backup_audits() -> int:
	var count := 0
	for row in audit:
		if row.action == "backup.automatic" and row.actor_id == "system" and row.reason == "scheduled" and row.code == "OK":
			count += 1
	return count

func _capture_host(reason: String) -> void:
	var record: Dictionary = launcher.record(host_launch)
	test_host_history.append({"reason": reason, "launch_id": host_launch, "pid": record.get("pid", 0), "created_filetime": record.get("created_filetime", ""), "verified": record.get("verified", false), "elapsed_ms": Time.get_ticks_msec() - test_started})

func wait_for(predicate: Callable, timeout_ms: int = 15000) -> bool:
	var until := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < until and not test_finishing:
		await process_frame
	return predicate.call()

func check(condition: bool, label: String) -> bool:
	if condition:
		test_passed += 1
		print("PASS ", label)
	else:
		test_failed += 1
		printerr("FAIL ", label)
	return condition

func _finish() -> void:
	if test_finishing:
		return
	test_finishing = true
	quitting = true
	restart_after = 0
	restart_requested = false
	requested_stop = true
	var until := Time.get_ticks_msec() + 30000
	while starting and Time.get_ticks_msec() < until:
		await process_frame
	if host_owned:
		await _host_command("server.stop", {"immediate": true})
	until = Time.get_ticks_msec() + 25000
	while (host_owned or host_closing) and Time.get_ticks_msec() < until:
		await process_frame
	if host_owned:
		check(false, "test cleanup had to terminate its exact owned host")
		await _work(_terminate_owned.bind(launcher.record(host_launch)))
		until = Time.get_ticks_msec() + 15000
		while (host_owned or host_closing) and Time.get_ticks_msec() < until:
			await process_frame
	check(not host_owned and not starting and not host_closing and launcher._records.is_empty(), "all created host process records are confirmed exited and released")
	while worker_count > 0:
		await process_frame
	check(not FileAccess.file_exists(root_path.path_join("host-running.json")), "final owned-host marker is absent")
	http.close()
	if bus != null:
		bus.close()
	DirAccess.remove_absolute(root_path.path_join("operator.json"))
	_write_json(root_path.path_join("schedule-result.json"), {"passed": test_passed, "failed": test_failed, "elapsed_ms": Time.get_ticks_msec() - test_started, "actual_host_launches": test_host_history, "automatic_backups": _backup_rows().size(), "clock_scope": "next_backup and historical restart timestamps controlled in test; real polling, process crashes/restarts and SQLite backup; no 30-minute wall-clock wait", "public_connection_publishing": "suppressed by test subclass"})
	print("OPERATOR_SCHEDULE_RESULT passed=", test_passed, " failed=", test_failed, " evidence=", root_path)
	quit(0 if test_failed == 0 else 1)
