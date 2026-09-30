extends SceneTree
## Limits of host/platform/posix_helper.gd and the Linux branch of
## host/storage/resident_store.gd, with REAL child processes but a STAND-IN for
## PowerShell (tests/fixtures/posix_fake_shell.sh) that hangs, floods or exits on
## request. It shows what happens when a helper misbehaves; it says nothing about
## the real storage scripts (that is tests/run_posix_storage.gd).
## Usage: --headless --script res://tests/run_posix_helper.gd --
##   --work=<empty private dir on a Linux filesystem> --shell=<posix_fake_shell.sh>
## Start the engine with SIGPIPE ignored (`trap '' PIPE` in the calling shell).
## With --expect=pipe-unsafe it must be started WITHOUT that, and only checks that
## every helper call is then refused before anything is started.
## Lines marked INJECTED make the owner refuse to confirm that a child is gone
## (a real, hanging child; only the owner's answer is replaced) and are counted
## separately.
const Owner = preload("res://host/platform/posix_process_owner.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Posix = preload("res://host/platform/posix_helper.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const MODE := "ROOMKIT_FAKE_SHELL_MODE"
var passed := 0
var failed := 0
var injected_passed := 0
var injected_failed := 0
var owner

## The real owner, except that it can be told to answer "still running, cannot be
## confirmed gone" for every child while refuse_all is set.
class StubbornOwner extends Owner:
	var refuse_all := false
	func terminate(launch_id: String, keep_pipes := false) -> bool:
		if refuse_all:
			return false
		return super(launch_id, keep_pipes)
	func probe(launch_id: String) -> String:
		if refuse_all:
			return "running"
		return super(launch_id)
var work := ""

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS ", text)
	else:
		failed += 1
		print("FAIL ", text)
	return value

func check_injected(value: bool, text: String) -> void:
	if value:
		injected_passed += 1
		print("PASS INJECTED ", text)
	else:
		injected_failed += 1
		print("FAIL INJECTED ", text)

func _children() -> Array:
	var found: Array = []
	for name in DirAccess.get_directories_at("/proc"):
		if name.is_valid_int():
			var seen: Dictionary = owner.backend.identity(int(name))
			if not seen.is_empty() and int(seen.ppid) == OS.get_process_id():
				found.append(int(name))
	return found

func _open_descriptors() -> int:
	var listing := DirAccess.open("/proc/self/fd")
	if listing == null:
		return -1
	listing.include_hidden = true
	listing.list_dir_begin()
	var count := 0
	while listing.get_next() != "":
		count += 1
	return count

func _tool(executable: String, arguments: Array) -> bool:
	owner.trust(executable)
	var launch_id := Crypto.new().generate_random_bytes(16).hex_encode()
	if not owner.launch(launch_id, executable, PackedStringArray(arguments)).ok:
		return false
	while owner.probe(launch_id) == "running":
		OS.delay_msec(2)
	var finished: bool = owner.exit_code(launch_id) == 0
	owner.forget(launch_id)
	return finished

## One call in the given stand-in mode; returns [reply, elapsed ms].
func _call(mode: String, input: String, timeout_ms: int) -> Array:
	OS.set_environment(MODE, mode)
	var started := Time.get_ticks_msec()
	var reply: Dictionary = Helper.execute_input("account_store.ps1", ["-Database", work.path_join("unused.sqlite")], input, timeout_ms)
	return [reply, Time.get_ticks_msec() - started]

func _run() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix helper limits (this is ", OS.get_name(), ")")
		print("POSIX_HELPER_RESULT passed=0 failed=0 not_run=1")
		quit(0)
		return
	var args: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0].trim_prefix("--")] = pair[1]
	work = str(args.get("work", ""))
	var source := str(args.get("shell", ""))
	if work == "" or not DirAccess.dir_exists_absolute(work) or not FileAccess.file_exists(source):
		print("FAIL --work must be an existing directory and --shell the stand-in script")
		quit(2)
		return
	owner = StubbornOwner.new()
	Posix._owner = owner  # before any helper is started: the single holder for this run
	var shell := work.path_join("fake-pwsh")
	var fifo := work.path_join("never-written.fifo")
	DirAccess.copy_absolute(source, shell)
	FileAccess.set_unix_permissions(shell, 448)  # octal 700
	_tool("/usr/bin/mkfifo", [fifo])
	OS.set_environment("ROOMKIT_FAKE_SHELL_FIFO", fifo)
	OS.set_environment(Posix.SHELL_VARIABLE, shell)
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	var descriptors_before := _open_descriptors()
	print("INFO engine=", Engine.get_version_info().string, " ", owner.invariant_detail, " sigpipe_ignored=", Posix._sigpipe_ignored(), " dependency=", Posix.dependency())
	if str(args.get("expect", "")) == "pipe-unsafe":
		OS.set_environment(MODE, "ok")
		var refused: Dictionary = Helper.execute_input("account_store.ps1", [], "{}", 3000)
		check(not Posix._sigpipe_ignored() and Posix.dependency() == "HELPER_PIPE_UNSAFE" and refused.code == "HELPER_PIPE_UNSAFE" and Helper.execute("sqlite_store.ps1", [], work, 3000).code == "HELPER_PIPE_UNSAFE", "started without SIGPIPE ignored: every helper call is refused with HELPER_PIPE_UNSAFE")
		check(not Resident.enabled() and Resident.for_database("sqlite_store.ps1", work.path_join("x.sqlite"), 1000).request({"op": "asset.read"}).is_empty() and _children().is_empty() and owner.launch_ids().is_empty(), "the resident path is disabled and no process was started")
		DirAccess.remove_absolute(fifo)
		print("POSIX_HELPER_RESULT passed=", passed, " failed=", failed, " injected_passed=0 injected_failed=0 not_run=0")
		quit(0 if failed == 0 else 1)
		return
	if not check(Posix.dependency() == "", "the helper dependencies are satisfied with the stand-in shell (SIGPIPE is ignored by this engine process)"):
		print("POSIX_HELPER_RESULT passed=", passed, " failed=", failed, " not_run=0")
		quit(1)
		return

	# ---- normal calls ----
	var normal: Array = _call("ok", "{\"op\":\"probe\"}", 5000)
	check(normal[0].get("ok", false) and normal[0].line == Marshalls.utf8_to_base64("{\"op\":\"probe\"}") and int(normal[0].arguments) == 6 and normal[0].file == "account_store.ps1", "the request reaches the child as one base64 line on standard input; the argument vector holds only the fixed options, the script and the database path")
	OS.set_environment(MODE, "ok-noinput")
	var hostile := "x$(touch canary-dollar)`touch canary-tick`;touch canary-semi 'q'"
	var plain: Dictionary = Helper.execute("sqlite_store.ps1", ["-Database", hostile], work, 5000)
	check(plain.get("ok", false) and int(plain.arguments) == 6 and plain.get("last", "") == hostile, "a call without input works, and an argument full of shell syntax arrives as one literal argument")
	var canaries := 0
	for folder in [work, DirAccess.open("/proc/self").read_link("cwd")]:
		for name in DirAccess.get_files_at(folder):
			canaries += 1 if name.begins_with("canary-") else 0
	check(canaries == 0, "that argument executed nothing (no canary file in the work folder or the working directory)")
	check(_children().is_empty() and owner.launch_ids().is_empty(), "finished calls leave no process and no owner record")

	# ---- a helper that misbehaves ----
	var hang: Array = _call("hang", "{}", 600)
	check(hang[0].code == "HELPER_TIMEOUT" and hang[1] < 3000 and _children().is_empty(), "a helper that never answers is ended at the deadline: HELPER_TIMEOUT after %d ms (limit 600), nothing left" % hang[1])
	var closed: Array = _call("silent-close", "{}", 600)
	check(closed[0].code == "HELPER_TIMEOUT" and closed[1] < 3000 and _children().is_empty(), "a helper that closes its output but keeps running is ended at the deadline (%d ms)" % closed[1])
	var big_input := "x".repeat(300000)
	var unread: Array = _call("hang-noread", big_input, 800)
	check(unread[0].code in ["HELPER_TIMEOUT", "HELPER_FAILED"] and unread[1] < 4000 and _children().is_empty(), "a helper that never reads a 400 KiB request cannot block the write forever: %s after %d ms (limit 800)" % [unread[0].code, unread[1]])
	var noisy: Array = _call("stderr-flood", "{}", 8000)
	check(noisy[0].get("ok", false) and noisy[0].line == Marshalls.utf8_to_base64("{}"), "2 MiB on standard error do not block the helper; the reply still arrives (%d ms) and the error text is not returned" % noisy[1])
	var flood: Array = _call("stdout-flood", "{}", 8000)
	check(flood[0].code == "HELPER_FAILED" and flood[1] < 8000 and _children().is_empty(), "6 MiB on standard output exceed the 4 MiB limit: the helper is ended and the call fails (%d ms)" % flood[1])
	check(_call("exit-3", "{}", 5000)[0].code == "HELPER_FAILED", "a helper that exits with a failure code fails the call even when it printed a reply")
	check(_call("garbage", "{}", 5000)[0].code == "HELPER_FAILED", "output that is not a JSON object fails the call")
	check(_call("no-such-mode", "{}", 5000)[0].code == "HELPER_FAILED" and _children().is_empty() and owner.launch_ids().is_empty(), "a helper that exits at once without output fails the call; no process or record remains after all the failures")
	# Several calls at once, each with its own watchdog.
	OS.set_environment(MODE, "hang")
	var threads: Array = []
	for index in 6:
		var thread := Thread.new()
		thread.start(func(): return Helper.execute_input("account_store.ps1", [], "{}", 500 + index * 100))
		threads.append(thread)
	var codes: Array = []
	for thread in threads:
		while thread.is_alive():
			await process_frame
		codes.append(thread.wait_to_finish().code)
	check(codes.all(func(code): return code == "HELPER_TIMEOUT") and _children().is_empty() and owner.launch_ids().is_empty(), "six hanging helpers called from six threads are each ended at their own deadline; nothing is left")

	# ---- resident worker (Linux branch of resident_store.gd) ----
	OS.set_environment(MODE, "worker")
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", work.path_join("Stand-In.sqlite"), 1500)
	var other: RefCounted = Resident.for_database("sqlite_store.ps1", work.path_join("stand-in.sqlite"), 1500)
	var first: Dictionary = store.request({"op": "asset.read", "n": 1})
	var second: Dictionary = store.request({"op": "asset.read", "n": 2})
	check(Resident.enabled() and first.get("ok", false) and second.get("echo", "") == Marshalls.utf8_to_base64(JSON.stringify({"op": "asset.read", "n": 2})) and store.started_workers == 1 and store.worker_pid() > 0, "a worker is started once and serves consecutive requests over its pipe")
	check(other != store and other.request({"op": "x"}).get("ok", false) and other.worker_pid() != store.worker_pid() and _children().size() == 2, "database paths differing only in case get separate stores and separate workers")
	var kills: int = owner.kills_sent()
	other.stop()
	check(other.worker_pid() == -1 and owner.kills_sent() == kills and _children().size() == 1, "stop() lets the worker leave on request: no signal is sent and it is reaped")
	var old_pid: int = store.worker_pid()
	store.stop()
	OS.set_environment(MODE, "worker-mute")
	var started := Time.get_ticks_msec()
	var mute: Dictionary = store.request({"op": "asset.read"})
	var waited := Time.get_ticks_msec() - started
	check(mute.is_empty() and store.timeouts == 1 and store.fallbacks == 1 and waited < 4000 and not store.blocked() and store.worker_pid() == -1 and _children().is_empty(), "a worker that never replies is ended at the request deadline (%d ms, limit 1500): the caller is told to fall back, the worker is reaped" % waited)
	OS.set_environment(MODE, "worker-once")
	var once: Dictionary = store.request({"op": "asset.read"})
	var until := Time.get_ticks_msec() + 3000
	while owner.backend.identity(store.worker_pid()).get("state", "Z") != "Z" and Time.get_ticks_msec() < until:
		OS.delay_msec(5)
	var dead_pid: int = store.worker_pid()
	OS.set_environment(MODE, "worker")
	var after: Dictionary = store.request({"op": "asset.read"})
	check(once.get("ok", false) and after.get("ok", false) and store.worker_pid() != dead_pid and owner.backend.identity(dead_pid).is_empty() and old_pid != dead_pid, "a worker that exited between requests is reaped and replaced on the next request")
	# A worker killed from outside while idle (SIGKILL from bash's builtin kill,
	# itself an owned child): reaped and replaced on the next request.
	var victim: int = store.worker_pid()
	var workers_before: int = store.started_workers
	var fallbacks_before: int = store.fallbacks
	var struck := _tool("/bin/bash", ["-c", "kill -KILL \"$1\"", "bash", str(victim)])
	until = Time.get_ticks_msec() + 3000
	while owner.backend.identity(victim).get("state", "Z") != "Z" and Time.get_ticks_msec() < until:
		OS.delay_msec(2)
	var state_after: String = owner.backend.identity(victim).get("state", "gone")
	var replaced: Dictionary = store.request({"op": "asset.read"})
	check(struck and replaced.get("ok", false) and store.started_workers == workers_before + 1 and store.fallbacks == fallbacks_before and owner.backend.identity(victim).is_empty(), "a worker killed from outside while idle is reaped and replaced on the next request (signal sent=%s, state=%s, reply ok=%s, workers +%d, fallbacks +%d)" % [struck, state_after, replaced.get("ok", false), store.started_workers - workers_before, store.fallbacks - fallbacks_before])
	# Writing to a worker that is already gone must neither end this process nor hang.
	store.stop()
	OS.set_environment(MODE, "worker-once")
	store.request({"op": "asset.read"})
	var workers: int = store.started_workers
	var fallbacks: int = store.fallbacks
	var raced: Array = []
	for index in 20:
		raced.append(store.request({"op": "asset.read"}))
	check(raced.all(func(reply): return reply.is_empty() or reply.get("ok", false)) and store.started_workers > workers and store.started_workers - workers + (store.fallbacks - fallbacks) >= 19, "twenty requests against workers that exit after one reply all return (a reply, or a fallback when the worker was already gone); this process survives writing to a closed pipe")
	store.stop()
	OS.set_environment(MODE, "worker-noisy")
	var loud := true
	for index in 12:
		loud = loud and store.request({"op": "asset.read"}).get("ok", false)
	check(loud and store.worker_pid() > 0, "a worker that writes 3 MiB to standard error over twelve requests keeps answering (its error output is drained)")
	store.queue_limit = 0
	check(store.request({"op": "asset.read"}).get("code", "") == "STORAGE_UNAVAILABLE", "a full queue refuses instead of waiting")
	store.queue_limit = Resident.QUEUE_LIMIT
	OS.set_environment("ROOMKIT_STORAGE_MODE", "oneshot")
	check(not Resident.enabled(), "ROOMKIT_STORAGE_MODE=oneshot disables the resident path")
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	Resident.shutdown_all()
	_absolute_deadlines()
	await _crowd()
	_unstoppable()
	await _crowd_unstoppable()

	# ---- nothing left behind ----
	DirAccess.remove_absolute(fifo)
	await create_timer(0.2).timeout
	check(_children().is_empty(), "no child or zombie of this process remains (%d)" % _children().size())
	check(owner.launch_ids().is_empty() and owner.unheld_ids().is_empty(), "the owner holds no record")
	var descriptors_after := _open_descriptors()
	check(descriptors_after == descriptors_before, "open file descriptors are back to the starting count (%d -> %d)" % [descriptors_before, descriptors_after])
	print("POSIX_HELPER_RESULT passed=", passed, " failed=", failed, " injected_passed=", injected_passed, " injected_failed=", injected_failed, " not_run=0")
	quit(0 if failed == 0 and injected_failed == 0 else 1)

# ---- the deadline is absolute: output that keeps coming cannot extend it ----
func _absolute_deadlines() -> void:
	var before := _children().size()
	var drip: Array = _call("stdout-drip", "{}", 500)
	check(drip[0].code == "HELPER_TIMEOUT" and drip[1] < 1500 and _children().size() == before, "a helper that keeps writing small pieces of output is still ended at the deadline: HELPER_TIMEOUT after %d ms (deadline 500)" % drip[1])
	var noise: Array = _call("stderr-drip", "{}", 500)
	check(noise[0].code == "HELPER_TIMEOUT" and noise[1] < 1500 and _children().size() == before, "a helper that keeps writing to standard error is still ended at the deadline: HELPER_TIMEOUT after %d ms (deadline 500)" % noise[1])
	var late: Array = _call("late-line", "{}", 500)
	check(late[0].code == "HELPER_TIMEOUT" and not late[0].get("late", false) and late[1] < 1500, "a correct reply that would arrive at 800 ms is not accepted after a 500 ms deadline (%s after %d ms)" % [late[0].code, late[1]])
	OS.set_environment(MODE, "worker-drip")
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", work.path_join("drip.sqlite"), 500)
	var started := Time.get_ticks_msec()
	var dripping: Dictionary = store.request({"op": "asset.read"})
	var waited := Time.get_ticks_msec() - started
	check(dripping.is_empty() and store.timeouts == 1 and waited < 1500 and store.worker_pid() == -1, "a worker that keeps writing to standard error instead of replying is ended at the request deadline (%d ms, deadline 500)" % waited)
	OS.set_environment(MODE, "worker-late")
	started = Time.get_ticks_msec()
	var tardy: Dictionary = store.request({"op": "asset.read"})
	waited = Time.get_ticks_msec() - started
	check(tardy.is_empty() and store.timeouts == 2 and waited < 1500, "a worker reply that would arrive at 800 ms is not accepted after a 500 ms deadline; the caller falls back (%d ms)" % waited)
	OS.set_environment(MODE, "worker-then-drip")
	var answered: Dictionary = store.request({"op": "asset.read"})
	started = Time.get_ticks_msec()
	store.stop()
	waited = Time.get_ticks_msec() - started
	check(answered.get("ok", false) and waited >= 2900 and waited < 4500 and store.worker_pid() == -1 and _children().size() == before, "stop() of a worker that ignores the stop request and keeps writing to standard error returns at its 3 s limit (%d ms); the worker is ended and reaped" % waited)

# ---- budget: many callers at once ----
func _crowd() -> void:
	OS.set_environment(MODE, "hang")
	var before := _children().size()
	var threads: Array = []
	for index in 12:
		var thread := Thread.new()
		thread.start(Helper.execute_input.bind("account_store.ps1", [], "{}", 1500))
		threads.append(thread)
	var peak := 0
	var peak_slots := 0
	while threads.any(func(thread): return thread.is_alive()):
		peak = maxi(peak, _children().size() - before)
		var used: Dictionary = Posix.budget()
		peak_slots = maxi(peak_slots, int(used.in_flight) + int(used.parked))
		await process_frame
	var codes: Array = threads.map(func(thread): return thread.wait_to_finish().code)
	var timed_out := codes.count("HELPER_TIMEOUT")
	var refused := codes.count("HELPER_CAPACITY_FULL")
	check(peak <= Posix.MAX_HELPERS and peak_slots <= Posix.MAX_HELPERS and timed_out <= Posix.MAX_HELPERS and timed_out + refused == 12 and refused >= 12 - Posix.MAX_HELPERS, "twelve callers at once: at most %d helpers ever run (peak %d children, %d slots); %d end at their deadline and %d are refused with HELPER_CAPACITY_FULL without a process" % [Posix.MAX_HELPERS, peak, peak_slots, timed_out, refused])
	check(_children().size() == before and Posix.budget().in_flight == 0 and Posix.parked().is_empty(), "afterwards every slot is free and no child remains")

# ---- injected: the child hangs AND cannot be confirmed gone ----
func _unstoppable() -> void:
	var start_children := _children().size()
	owner.refuse_all = true
	var bounded := true
	var kept := true
	var cases := [["hang", "{}", "a helper that never answers"], ["hang-noread", "x".repeat(300000), "a helper that never reads a 400 KiB request"], ["stderr-hang", "{}", "a helper that keeps its error output open"]]
	for index in cases.size():
		var outcome: Array = _call(cases[index][0], cases[index][1], 500)
		var parked: Array = Posix.parked()
		var launch_id: String = parked[-1] if parked.size() == index + 1 else ""
		var held_pid := int(owner.record(launch_id).get("pid", -1)) if launch_id != "" else -1
		var ok_now: bool = outcome[0].code == "HELPER_UNFINISHED" and outcome[1] < 2500
		var kept_now: bool = launch_id != "" and owner.launch_ids().has(launch_id) and not owner.pipes(launch_id).is_empty() and not owner.backend.identity(held_pid).is_empty()
		check_injected(ok_now, "%s and cannot be stopped: the call still returns in %d ms (deadline 500) with HELPER_UNFINISHED" % [cases[index][2], outcome[1]])
		check_injected(kept_now, "%s: its record, pipes and live process are kept, and it is parked (%d parked)" % [cases[index][2], parked.size()])
		bounded = bounded and ok_now
		kept = kept and kept_now
	var fourth: Array = _call("hang", "{}", 300)
	var before_full := _children().size()
	var full: Array = _call("ok", "{}", 3000)
	check_injected(fourth[0].code == "HELPER_UNFINISHED" and Posix.parked().size() == Posix.MAX_UNFINISHED and full[0].code == "HELPER_BACKLOG_FULL" and full[1] < 1000 and _children().size() == before_full, "with %d helpers parked no further helper is started: HELPER_BACKLOG_FULL at once" % Posix.MAX_UNFINISHED)
	# Resident worker that hangs and cannot be stopped.
	owner.refuse_all = false
	OS.set_environment(MODE, "worker-mute")
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", work.path_join("unstoppable.sqlite"), 500)
	var backlog := Posix.parked().size()
	Posix._lock.lock()
	var saved: Array = Posix._parked
	Posix._parked = []  # let the worker start; the parked helpers are restored below
	Posix._lock.unlock()
	owner.refuse_all = true
	var started := Time.get_ticks_msec()
	var first: Dictionary = store.request({"op": "asset.read"})
	var waited := Time.get_ticks_msec() - started
	var worker_id: String = store._launch
	check_injected(first.is_empty() and waited < 2500 and store.blocked() and store.timeouts == 1 and store.started_workers == 1, "a worker that never replies and cannot be stopped: the request still returns in %d ms (deadline 500) and the store is blocked" % waited)
	check_injected(worker_id != "" and owner.launch_ids().has(worker_id) and not owner.pipes(worker_id).is_empty() and not owner.backend.identity(store.worker_pid()).is_empty(), "the blocked worker's record, pipes and live process are kept")
	started = Time.get_ticks_msec()
	var second: Dictionary = store.request({"op": "asset.read"})
	check_injected(second.is_empty() and store.started_workers == 1 and Time.get_ticks_msec() - started < 1000 and store.fallbacks == 2, "while blocked no second worker is started for the database; the request is refused at once for the fallback")
	started = Time.get_ticks_msec()
	store.stop()
	check_injected(store.blocked() and Time.get_ticks_msec() - started < 1000 and owner.launch_ids().has(worker_id), "stop() on a blocked worker returns at once and keeps the record")
	# Recovery: the owner can confirm again.
	owner.refuse_all = false
	Posix._lock.lock()
	Posix._parked.append_array(saved)
	Posix._lock.unlock()
	OS.set_environment(MODE, "worker")
	var recovered: Dictionary = store.request({"op": "asset.read"})
	check_injected(recovered.get("ok", false) and not store.blocked() and store.started_workers == 2 and not owner.launch_ids().has(worker_id), "once the owner can stop it, the blocked worker is ended and released and one new worker serves the request")
	var after: Array = _call("ok", "{}", 5000)
	check_injected(after[0].get("ok", false) and Posix.parked().is_empty() and backlog == Posix.MAX_UNFINISHED, "the next helper start first ends and releases all parked helpers, then works")
	store.stop()
	check_injected(_children().size() == start_children and owner.launch_ids().is_empty(), "after recovery no hanging child, record or pipe remains")

# ---- injected: more callers than slots, and none of them can be stopped ----
func _crowd_unstoppable() -> void:
	OS.set_environment(MODE, "hang")
	var before := _children().size()
	owner.refuse_all = true
	var threads: Array = []
	for index in 12:
		var thread := Thread.new()
		thread.start(Helper.execute_input.bind("account_store.ps1", [], "{}", 800))
		threads.append(thread)
	var peak := 0
	var peak_slots := 0
	var started := Time.get_ticks_msec()
	while threads.any(func(thread): return thread.is_alive()):
		peak = maxi(peak, _children().size() - before)
		var used: Dictionary = Posix.budget()
		peak_slots = maxi(peak_slots, int(used.in_flight) + int(used.parked))
		await process_frame
	var waited := Time.get_ticks_msec() - started
	var codes: Array = threads.map(func(thread): return thread.wait_to_finish().code)
	var unfinished := codes.count("HELPER_UNFINISHED")
	var refused := codes.count("HELPER_CAPACITY_FULL") + codes.count("HELPER_BACKLOG_FULL")
	var parked: Array = Posix.parked()
	check_injected(unfinished + refused == 12 and unfinished <= Posix.MAX_HELPERS and parked.size() == unfinished and peak <= Posix.MAX_HELPERS and peak_slots <= Posix.MAX_HELPERS and waited < 3000, "twelve callers at once and no child can be stopped: every call returns within %d ms, at most %d children ever run (peak %d, %d slots), %d are parked and %d refused without a process" % [waited, Posix.MAX_HELPERS, peak, peak_slots, unfinished, refused])
	var before_refusal := _children().size()
	var more: Array = _call("ok", "{}", 3000)
	check_injected(more[0].code == "HELPER_BACKLOG_FULL" and more[1] < 1000 and _children().size() == before_refusal and Posix.budget().in_flight == 0, "with the parked records at the limit the next call is refused at once and starts nothing")
	owner.refuse_all = false
	var recovered: Array = _call("ok", "{}", 5000)
	check_injected(recovered[0].get("ok", false) and Posix.parked().is_empty() and _children().size() == before and owner.launch_ids().is_empty(), "once the owner can stop them, the next call ends and releases every parked helper, then works; nothing remains")
