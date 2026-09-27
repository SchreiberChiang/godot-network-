extends SceneTree
## Evaluation harness for a resident storage worker (tests/perf/resident_store_probe.ps1).
## Compares the same asset.snapshot + asset.commit cycle through (a) the current
## one-shot bounded helper and (b) a resident PowerShell worker, then measures
## start-up, concurrency (one worker per thread and one shared worker), memory
## growth over many requests, and restart after a killed worker. Private test
## directory only; production code is not changed or called differently.
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const SPACE := "shooter"
var passed := 0
var failed := 0
var directory := ""
var repository = Repository.new()
var report := {}
var shared_lock := Mutex.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-resident-probe-" + Wire.uid())
	print("RESIDENT_PROBE_EVIDENCE_DIR=", directory)
	if not check(repository.initialize(directory, "assets.sqlite").ok, "real asset database initializes through the production helper"):
		finish()
		return
	# (a) Current path: one PowerShell pair per call.
	var oneshot := {"snapshot": [], "commit": [], "cycle": []}
	for index in 5:
		check(_cycle("oneshot-user", index, func(request): return repository.execute(request), oneshot), "one-shot cycle %d commits" % index)
	report.oneshot = _stats_all(oneshot)
	# (b) Resident worker.
	var started := Time.get_ticks_usec()
	var worker := _start_worker()
	if not check(not worker.is_empty(), "resident worker starts"):
		finish()
		return
	var first := _ask(worker, {"op": "asset.read", "user_id": "warmup", "space_id": SPACE})
	report.resident_first_reply_ms = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)
	check(first.get("ok", false), "resident worker answers the first request (start-up included)")
	var resident := {"snapshot": [], "commit": [], "cycle": []}
	for index in 30:
		check(_cycle("resident-user", index, func(request): return _ask(worker, request), resident), "resident cycle %d commits" % index)
	report.resident = _stats_all(resident)
	check(_chain_ok("resident-user", 30), "resident commits keep the receipt chain and revision exact")
	# Memory growth of the long-lived process over many requests.
	var memory := {"after_40": _working_set(worker.pid)}
	for index in 400:
		_ask(worker, {"op": "asset.read", "user_id": "resident-user", "space_id": SPACE})
	memory.after_440 = _working_set(worker.pid)
	report.resident_working_set_bytes = memory
	check(memory.after_40 > 0 and memory.after_440 > 0, "worker working set sampled")
	# Concurrency A: four threads, each with its own resident worker, distinct users.
	report.concurrent_own_workers = await _concurrent(4, 10, false)
	# Concurrency B: four threads sharing the one worker (requests serialised).
	report.concurrent_shared_worker = await _concurrent(4, 10, true, worker)
	# Crash and restart: kill the held worker, then time a fresh worker's first reply.
	_stop_worker(worker, true)
	started = Time.get_ticks_usec()
	var replacement := _start_worker()
	var after_restart := _ask(replacement, {"op": "asset.read", "user_id": "resident-user", "space_id": SPACE})
	report.restart_first_reply_ms = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)
	check(after_restart.get("ok", false) and _chain_ok("resident-user", 30), "restarted worker reads the same committed state")
	_stop_worker(replacement, false)
	finish()

func _cycle(user: String, index: int, send: Callable, into: Dictionary) -> bool:
	var cycle_start := Time.get_ticks_usec()
	var request_id := "%s_%d_%s" % [user, index, Wire.uid().left(8)]
	var fingerprint := Wire.uid()
	var started := Time.get_ticks_usec()
	var snapshot: Dictionary = send.call({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": request_id, "fingerprint": fingerprint})
	into.snapshot.append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	if not snapshot.get("ok", false) or snapshot.get("found", true):
		return false
	var state: Dictionary = {"revision": 0, "credits": 0, "experience": 0, "owned": [], "profiles": {}} if str(snapshot.body) == "" else JSON.parse_string(str(snapshot.body))
	var changed := state.duplicate(true)
	changed.revision = int(state.revision) + 1
	changed.credits = int(state.credits) + 1
	started = Time.get_ticks_usec()
	var commit: Dictionary = send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": request_id, "fingerprint": fingerprint, "actor_id": "probe", "command": "{}", "expected_revision": int(state.revision), "body": Format.canonical(changed)})
	into.commit.append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	into.cycle.append(snappedf((Time.get_ticks_usec() - cycle_start) / 1000.0, 0.1))
	return commit.get("ok", false) and commit.get("code", "") == ""

func _concurrent(threads_count: int, cycles: int, shared: bool, shared_worker: Dictionary = {}) -> Dictionary:
	var threads: Array = []
	var started := Time.get_ticks_usec()
	for index in threads_count:
		var thread := Thread.new()
		if check(thread.start(_concurrent_worker.bind("race-%s-%d" % ["shared" if shared else "own", index], cycles, shared, shared_worker)) == OK, "concurrency worker starts"):
			threads.append(thread)
	var cycle_times: Array = []
	var failures := 0
	for thread in threads:
		while thread.is_alive():
			await process_frame
		var result: Dictionary = thread.wait_to_finish()
		cycle_times.append_array(result.cycles)
		failures += int(result.failures)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	var total := threads_count * cycles
	check(failures == 0, "%s concurrency: all %d cycles committed" % ["shared-worker" if shared else "own-worker", total])
	var stats := _stats(cycle_times)
	stats.failures = failures
	stats.wall_ms = snappedf(elapsed, 0.1)
	stats.cycles_per_second = snappedf(total / (elapsed / 1000.0), 0.01)
	return stats

func _concurrent_worker(user: String, cycles: int, shared: bool, shared_worker: Dictionary) -> Dictionary:
	var own := {} if shared else _start_worker()
	var into := {"snapshot": [], "commit": [], "cycle": []}
	var failures := 0
	var send := func(request):
		if not shared:
			return _ask(own, request)
		shared_lock.lock()
		var reply := _ask(shared_worker, request)
		shared_lock.unlock()
		return reply
	for index in cycles:
		if not _cycle(user, index, send, into):
			failures += 1
	if not shared:
		_stop_worker(own, false)
	return {"cycles": into.cycle, "failures": failures}

func _start_worker() -> Dictionary:
	var launched := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/perf/resident_store_probe.ps1"), "-Database", repository.database, "-Scratch", directory], true)
	return {} if launched.is_empty() else {"pid": int(launched.pid), "stdio": launched.stdio, "stderr": launched.stderr}

func _ask(worker: Dictionary, request: Dictionary) -> Dictionary:
	var stdio: FileAccess = worker.stdio
	if not stdio.store_line(Marshalls.utf8_to_base64(JSON.stringify(request))):
		return {"ok": false, "code": "PROBE_WRITE_FAILED"}
	var line := stdio.get_line()
	var parsed: Variant = JSON.parse_string(line)
	return parsed if parsed is Dictionary else {"ok": false, "code": "PROBE_BAD_REPLY"}

func _stop_worker(worker: Dictionary, kill_first: bool) -> void:
	# Held-handle rule as in BoundedHelper: OS.kill only while the entry is present.
	var pid: int = worker.pid
	if not kill_first:
		worker.stdio.store_line("")
	var deadline := Time.get_ticks_msec() + 5000
	while not kill_first and OS.get_process_exit_code(pid) < 0 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	if OS.is_process_running(pid) or OS.get_process_exit_code(pid) >= 0:
		OS.kill(pid)
	worker.stdio.close()
	worker.stderr.close()

func _working_set(pid: int) -> int:
	var output: Array = []
	if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).WorkingSet64" % pid], output, false, false) != 0 or output.is_empty():
		return -1
	return int(str(output[0]).strip_edges())

func _chain_ok(user: String, expected_revision: int) -> bool:
	var stored: Dictionary = repository.execute({"op": "asset.read", "user_id": user, "space_id": SPACE})
	var state: Variant = JSON.parse_string(str(stored.get("body", "")))
	return stored.get("ok", false) and state is Dictionary and int(state.revision) == expected_revision and int(state.credits) == expected_revision

static func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "min_ms": sorted[0], "median_ms": sorted[sorted.size() / 2], "p95_ms": sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)], "max_ms": sorted[-1]}

static func _stats_all(groups: Dictionary) -> Dictionary:
	var out := {}
	for key in groups:
		out[key] = _stats(groups[key])
	return out

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL resident_probe: ", text)
	return value

func finish() -> void:
	report.passed = passed
	report.failed = failed
	var file := FileAccess.open(ProjectSettings.globalize_path("res://logs/resident-probe.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print(JSON.stringify(report))
	print("RESIDENT_PROBE_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
