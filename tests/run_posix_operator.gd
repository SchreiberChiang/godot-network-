extends "res://host/operator.gd"
## Linux Operator, first slice: the real Operator (private folders, databases,
## TLS material, loopback admin listener) starts, stops and loses a managed host.
## The host is tests/fixtures/operator_test_host.gd (same local RPC, no rooms),
## except at the end, where the real host/managed_host.gd runs with the process
## journal and memory limit, is ended by the test (unexpected exit) and restarted.
## Markers of an earlier Operator are inspected read-only (never signalled).
## Public connection publishing is suppressed. Lines marked INJECTED replace a
## launcher answer (hand-over, reclaim or stop refused); every process is real.
## Usage: --headless --script res://tests/run_posix_operator.gd --
##   --data-root=<new folder inside res://data> --panel-port=<free port>
const Owner = preload("res://host/platform/posix_process_owner.gd")
const Isolation = preload("res://tests/support/operator_isolation.gd")
var test_passed := 0
var test_failed := 0
var test_injected_passed := 0
var test_injected_failed := 0
var test_started := 0
var test_host_mode := "normal"
var test_events: Array = []
var test_backend

## The real launcher, except that a test can refuse its answers.
class InjectedLauncher extends Launcher:
	var refuse_import := false
	var refuse_reclaim := false
	var refuse_terminate := false
	func import_owned(record_value: Dictionary) -> bool:
		if refuse_import:
			return false
		return super(record_value)
	func reclaim(launch_id: String) -> bool:
		if refuse_reclaim:
			return false
		return super(launch_id)
	func terminate(launch_id: String) -> bool:
		if refuse_terminate:
			return false
		return super(launch_id)

func _initialize() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix operator slice (this is ", OS.get_name(), ")")
		print("POSIX_OPERATOR_RESULT passed=0 failed=0 injected_passed=0 injected_failed=0 not_run=1")
		quit(0)
		return
	# Never start the real Operator against real data by accident: every rule is
	# in tests/support/operator_isolation.gd (duplicates, empty or relative paths,
	# paths outside the isolation folder, links anywhere on the full path, port).
	var isolation_check: Dictionary = Isolation.check(OS.get_cmdline_user_args(), Paths.absolute("res://data"))
	if isolation_check.refusal != "":
		print("REFUSED run_posix_operator: ", isolation_check.refusal)
		quit(64)
		return
	var games_path: String = isolation_check.values["--games"]
	var index_refusal: String = Isolation.index_target_refusal(games_path, isolation_check.values["--isolation"])
	if index_refusal != "":
		print("REFUSED run_posix_operator: ", index_refusal)
		quit(64)
		return
	test_started = Time.get_ticks_msec()
	test_backend = Owner.PosixBackend.new()
	launcher = InjectedLauncher.new()
	# A one-game index built from the source tree (no built artifacts needed),
	# written once to the validated path only.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/turn_based/game_manifest.json"))
	manifest.sdk_version = "0.5.0"
	var index := {"turns": {"name": "turns", "project": Paths.absolute("res://"), "manifest": manifest, "asset_catalog": "res://examples/asset_catalog.example.json", "asset_policy": "res://examples/turn_based/asset_policy.gd", "result_schema": "res://schemas/summary_result.schema.json"}}
	var file := FileAccess.open(games_path, FileAccess.WRITE)
	if file == null:
		print("REFUSED run_posix_operator: the game index cannot be written")
		quit(64)
		return
	file.store_string(JSON.stringify(index))
	file.close()
	if not PrivatePath.protect_file(games_path, isolation_check.values["--isolation"]).ok:
		print("REFUSED run_posix_operator: the game index cannot be made owner-only")
		quit(64)
		return
	super._initialize()
	_exercise.call_deferred()

func _publish_connection() -> void:
	pass

func _host_descriptor() -> Dictionary:
	if test_host_mode == "real":
		return super()
	if test_host_mode == "missing":
		return {"executable": root_path.path_join("no-such-host-program"), "args": []}
	return {"executable": OS.get_executable_path(), "args": ["--headless", "--path", Paths.absolute("res://"), "--log-file", root_path.path_join("logs/test-host.log"), "--script", "res://tests/fixtures/operator_test_host.gd", "--", "--mode=" + test_host_mode]}

func _host_event(peer_id: String, action: String, payload: Dictionary) -> void:
	test_events.append({"action": action, "code": str(payload.get("code", ""))})
	super(peer_id, action, payload)

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if Time.get_ticks_msec() - test_started > 400000:
		print("FAIL isolated operator test deadline reached")
		quit(1)
	return result

func check(value: bool, text: String) -> bool:
	if value:
		test_passed += 1
		print("PASS ", text)
	else:
		test_failed += 1
		print("FAIL ", text)
	return value

func check_injected(value: bool, text: String) -> void:
	if value:
		test_injected_passed += 1
		print("PASS INJECTED ", text)
	else:
		test_injected_failed += 1
		print("FAIL INJECTED ", text)

func wait_for(predicate: Callable, timeout_ms := 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())

func _mode(path: String) -> int:
	return int(FileAccess.get_unix_permissions(path)) & 4095

func _children() -> Array:
	var found: Array = []
	for name in DirAccess.get_directories_at("/proc"):
		if name.is_valid_int():
			var seen: Dictionary = test_backend.identity(int(name))
			if not seen.is_empty() and int(seen.ppid) == OS.get_process_id():
				found.append(int(name))
	return found

func _marker() -> String:
	return root_path.path_join("host-running.json")

func _exercise() -> void:
	if not check(await wait_for(func(): return ready, 90000), "the real Operator initialises on Linux: databases, TLS material and the loopback admin listener"):
		await _finish()
		return
	next_backup = Time.get_ticks_msec() + 3600000
	await wait_for(func(): return worker_count == 0, 60000)
	print("INFO data_root=", root_path, " panel_port=", http.port, " children_at_start=", _children().size())

	# ---- system metrics and a backup through tools/operator_maintenance.ps1 (pwsh) ----
	check(await wait_for(func(): return snapshot.metrics.has("available") and not metrics_busy, 60000), "the Operator samples system metrics on Linux")
	var metrics: Dictionary = snapshot.metrics
	print("INFO metrics cpu=", metrics.get("system_cpu_percent"), " memory_used=", metrics.get("system_memory_used_bytes"), " memory_total=", metrics.get("system_memory_total_bytes"), " disk_free=", metrics.get("data_disk_free_bytes"))
	check(metrics.get("available", false) and int(metrics.get("system_memory_total_bytes", 0)) > 0 and int(metrics.get("system_memory_used_bytes", 0)) > 0 and metrics.get("system_cpu_percent") != null and int(metrics.get("data_disk_total_bytes", 0)) > 0, "memory (/proc/meminfo), CPU (/proc/stat) and data disk metrics are available (%s)" % metrics.get("error", ""))
	var backup: Dictionary = await _backup(false, "linux operator test")
	var backup_id := str(backup.get("payload", {}).get("backup_id", ""))
	var backup_dir := root_path.path_join("backups").path_join(backup_id)
	var loose_backup: Array = Array(DirAccess.get_files_at(backup_dir)).filter(func(name): return _mode(backup_dir.path_join(name)) != 384)
	check(backup.ok and backup_id != "" and _mode(root_path.path_join("backups")) == 448 and _mode(backup_dir) == 448 and loose_backup.is_empty() and DirAccess.get_files_at(backup_dir).size() >= 5, "a manual backup is taken on Linux; its folders are 700 and its files 600 (%s)" % backup.get("code", ""))

	# ---- private folders and files ----
	var runtime := Paths.absolute("res://run")
	var files := ["config.json", "operator.json", "server.key", "server.crt", "accounts.sqlite", "assets.sqlite"]
	var loose: Array = files.filter(func(name): return _mode(root_path.path_join(name)) != 384)
	check(_mode(runtime) == 448 and _mode(root_path) == 448 and loose.is_empty(), "the runtime and data folders are 700; configuration, marker, TLS key and certificate and both databases are 600 (not 600: %s)" % str(loose))
	var real := root_path.path_join("real-folder")
	DirAccess.make_dir_absolute(real)
	var linked := DirAccess.open(root_path).create_link(real, root_path.path_join("linked-folder")) == OK
	check(linked and not _write_json(root_path.path_join("linked-folder/x.json"), {"a": 1}) and not FileAccess.file_exists(real.path_join("x.json")), "a private JSON file is not written through a linked folder")
	DirAccess.remove_absolute(root_path.path_join("linked-folder"))
	DirAccess.remove_absolute(real)

	# ---- normal start and stop ----
	test_host_mode = "normal"
	var started: Dictionary = await _start_host()
	check(started.ok and host_owned and host_peer != "", "the Operator starts a managed host and receives its status over the local RPC (%s)" % started.get("code", ""))
	check(int(snapshot.host.get("config_mode", -1)) == 384, "the host's bootstrap file (it carries the RPC token) was 600 when the host read it (%o)" % int(snapshot.host.get("config_mode", -1)))
	var marker_text := FileAccess.get_file_as_string(_marker())
	var marker := Wire.decode(marker_text.to_utf8_buffer())
	check(FileAccess.file_exists(_marker()) and _mode(_marker()) == 384 and str(marker.get("launch_id", "")) == host_launch and int(marker.get("pid", 0)) > 0 and not marker_text.contains("handoff") and not marker_text.contains("token"), "host-running.json is 600 and holds only the observation record (launch id, pid), never the hand-over token")
	check(not FileAccess.file_exists(runtime.path_join("managed-" + host_launch + ".json")) and launcher._posix.unheld_ids().is_empty(), "the bootstrap file is gone and no host record is left unheld")
	var host_pid := int(marker.get("pid", 0))
	requested_stop = true
	var kills: int = launcher._posix.kills_sent()
	await _host_command("server.stop", {"immediate": true})
	check(await wait_for(func(): return not host_owned and not host_closing, 30000) and snapshot.host.state == "STOPPED" and not FileAccess.file_exists(_marker()) and launcher._posix.launch_ids().is_empty() and launcher._posix.kills_sent() == kills, "a normal stop: the host leaves on request (no signal), the Operator confirms the exit, removes the marker and releases the record")
	check(test_backend.identity(host_pid).is_empty(), "the stopped host process is gone (reaped)")

	# ---- start failure ----
	test_host_mode = "missing"
	var missing: Dictionary = await _start_host()
	check(not missing.ok and missing.code == "PROGRAM_NOT_FOUND" and not host_owned and not FileAccess.file_exists(_marker()) and snapshot.host.state == "FAILED", "a host program that does not exist fails the start with PROGRAM_NOT_FOUND; no marker, nothing owned")
	check(not FileAccess.file_exists(runtime.path_join("managed-" + host_launch + ".json")), "the bootstrap file of the host that never started (it carries the RPC token) is removed")

	# ---- start timeout, then a stop that cannot be confirmed ----
	test_host_mode = "silent"
	launcher.refuse_terminate = true
	var silent: Dictionary = await _start_host()
	requested_stop = true  # no automatic restart once it is gone
	var silent_pid := int(launcher.record(host_launch).get("pid", 0))
	check(not silent.ok and silent.code == "HOST_START_TIMEOUT", "a host that never connects fails the start with HOST_START_TIMEOUT")
	await wait_for(func(): return host_stop_attempts >= 2, 12000)
	check_injected(host_owned and host_stop_pending and host_stop_attempts >= 2 and FileAccess.file_exists(_marker()) and not test_backend.identity(silent_pid).is_empty(), "while its stop cannot be confirmed the host stays owned, its marker stays, and the stop is retried (%d attempts)" % host_stop_attempts)
	launcher.refuse_terminate = false
	check_injected(await wait_for(func(): return not host_owned and not host_closing, 20000) and not host_stop_pending and not FileAccess.file_exists(_marker()) and test_backend.identity(silent_pid).is_empty(), "once the stop can be confirmed the host is ended, the marker removed and the record released")

	# ---- hand-over refused, claim succeeds ----
	test_host_mode = "normal"
	launcher.refuse_import = true
	var claimed: Dictionary = await _start_host()
	launcher.refuse_import = false
	check_injected(claimed.ok and host_owned and launcher._posix.unheld_ids().is_empty(), "when the hand-over is refused the Operator claims the host and runs it normally")
	requested_stop = true
	await _host_command("server.stop", {"immediate": true})
	check(await wait_for(func(): return not host_owned and not host_closing, 30000) and not FileAccess.file_exists(_marker()), "that host stops normally")

	# ---- hand-over and claim both refused ----
	launcher.refuse_import = true
	launcher.refuse_reclaim = true
	var lost: Dictionary = await _start_host()
	var lost_launch := host_launch
	launcher.refuse_import = false
	launcher.refuse_reclaim = false
	check_injected(not lost.ok and not host_owned and snapshot.host.error in ["PROCESS_OWNERSHIP_LOST", "HOST_START_TIMEOUT"] and FileAccess.file_exists(_marker()) and launcher._posix.unheld_ids().has(lost_launch), "when neither hand-over nor claim works the start fails, the marker stays and the host stays listed as unheld (not lost)")
	var again: Dictionary = await _start_host()
	check_injected(not again.ok and again.code == "RECOVERY_REQUIRED", "while that marker exists no new host is started (RECOVERY_REQUIRED)")
	var reclaimed: bool = launcher.reclaim(lost_launch)
	var gone := await wait_for(func(): return launcher.probe(lost_launch) == "exited", 15000)
	check_injected(reclaimed and gone and launcher.forget(lost_launch), "(clean-up) the unheld host left on control loss; once claimed its exit is confirmed and the record released")
	DirAccess.remove_absolute(_marker())  # test clean-up of its own marker

	# ---- the Operator goes away: the host must not outlive it ----
	test_host_mode = "normal"
	var orphaned: Dictionary = await _start_host()
	var orphan_pid := int(launcher.record(host_launch).get("pid", 0))
	requested_stop = true
	kills = launcher._posix.kills_sent()
	bus.close()  # stands in for an Operator exit: the host sees its control connection close
	check(orphaned.ok and await wait_for(func(): return not host_owned and not host_closing, 20000) and test_backend.identity(orphan_pid).is_empty() and launcher._posix.kills_sent() == kills, "when the control connection closes (stands in for Operator exit) the host leaves by itself; no signal was needed")

	# ---- a marker left by an earlier Operator: read-only recovery ----
	var journal := root_path.path_join("processes.json")
	var self_seen: Dictionary = test_backend.identity(OS.get_process_id())
	var live_marker := {"platform": "linux", "launch_id": Wire.uid(), "pid": OS.get_process_id(), "parent_pid": int(self_seen.ppid), "executable": OS.get_executable_path(), "start_time": str(self_seen.start_time), "boot_id": Launcher.boot_id()}
	kills = launcher._posix.kills_sent()
	_write_json(_marker(), live_marker)
	recovery_next = 0
	await create_timer(1.0).timeout
	await wait_for(func(): return not recovery_busy, 10000)
	check(FileAccess.file_exists(_marker()) and launcher._posix.kills_sent() == kills and (await _start_host()).code == "RECOVERY_REQUIRED", "a marker whose process still runs (same PID and start time; here the test process itself) is kept, nothing is signalled, and no new host is started")
	var gone_marker := live_marker.duplicate()
	gone_marker.pid = orphan_pid
	gone_marker.start_time = "1"
	_write_json(_marker(), gone_marker)
	recovery_next = 0
	check(await wait_for(func(): return not FileAccess.file_exists(_marker()), 15000) and snapshot.host.state == "STOPPED" and launcher._posix.kills_sent() == kills, "a marker whose process is gone (PID absent or reused with another start time) is cleared read-only; the host state returns to STOPPED")

	# ---- the real managed host on Linux: journal and memory limit active ----
	settings.lobby_port = 28520
	settings.control_port = 28521
	settings.udp_first = 28530
	settings.udp_last = 28537
	test_host_mode = "real"
	test_events.clear()
	var real_host: Dictionary = await _start_host()
	check(real_host.ok and host_owned and host_peer != "" and not test_events.any(func(event): return event.action == "host.failed"), "the real managed host starts on Linux with the process journal and the per-room memory limit (%s %s)" % [real_host.get("code", ""), str(test_events.filter(func(event): return event.action == "host.failed"))])
	check(FileAccess.file_exists(journal) and _mode(journal) == 384, "the host's process journal exists and is 600")
	var real_marker := Wire.decode(FileAccess.get_file_as_string(_marker()).to_utf8_buffer())
	check(real_marker.get("platform", "") == "linux" and Launcher.inspect_previous(real_marker).state == "running", "host-running.json holds the Linux record of the running host (read-only inspection: running)")

	# ---- the host exits unexpectedly: FAILED, rooms journal checked, restart ----
	requested_stop = false
	var first_pid := int(real_marker.get("pid", 0))
	check(launcher.terminate(host_launch), "(fault) the test ends the host it started, through the verified owner record")
	check(await wait_for(func(): return snapshot.host.state == "FAILED" and not host_closing and restart_after > 0, 60000) and not FileAccess.file_exists(_marker()), "an unexpected host exit is reported FAILED; after the journal check the marker is removed and a restart is scheduled")
	check(await wait_for(func(): return host_owned and host_peer != "" and int(Wire.decode(FileAccess.get_file_as_string(_marker()).to_utf8_buffer()).get("pid", first_pid)) != first_pid, 60000), "the Operator restarts the host by itself")
	requested_stop = true
	restart_after = 0
	await _host_command("server.stop", {"immediate": true})
	check(await wait_for(func(): return not host_owned and not host_closing, 30000) and snapshot.host.state == "STOPPED" and not FileAccess.file_exists(_marker()), "the restarted host stops normally and the Operator releases it")
	var left: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(journal)) if FileAccess.file_exists(journal) else {"entries": {}}
	check(left.entries.is_empty(), "no room entry is left in the process journal")
	await _finish()

func _finish() -> void:
	quitting = true
	restart_after = 0
	requested_stop = true
	if host_owned:
		await _host_command("server.stop", {"immediate": true})
		await wait_for(func(): return not host_owned and not host_closing, 20000)
	while worker_count > 0:
		await process_frame
	Resident.shutdown_all()
	http.close()
	if bus != null:
		bus.close()
	await create_timer(0.5).timeout
	check(not host_owned and launcher._posix.launch_ids().is_empty() and launcher._posix.unheld_ids().is_empty(), "no host record is held or unheld at the end")
	check(_children().is_empty(), "no child process of the Operator remains (%d)" % _children().size())
	check(not FileAccess.file_exists(_marker()), "no host marker remains")
	DirAccess.remove_absolute(root_path.path_join("operator.json"))
	print("POSIX_OPERATOR_RESULT passed=", test_passed, " failed=", test_failed, " injected_passed=", test_injected_passed, " injected_failed=", test_injected_failed, " not_run=0")
	quit(0 if test_failed == 0 and test_injected_failed == 0 else 1)
