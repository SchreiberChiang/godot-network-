extends SceneTree
## Linux process journal and cross-run recovery rules, with real processes but no
## service: ProcessLauncher.journal_record / inspect_previous and RecoveryGuard.
## A record from an earlier run is only ever inspected read-only; nothing here
## signals a process it did not start itself. Test children are
## tests/fixtures/posix_child.sh (bash, builtins only).
## Usage: --headless --script res://tests/run_posix_journal_rules.gd --
##   --work=<new folder inside res://data> --fixture=<posix_child.sh>
const Launcher = preload("res://host/platform/process_launcher.gd")
const Guard = preload("res://host/core/recovery_guard.gd")
const Ports = preload("res://host/core/port_allocator.gd")
const Owner = preload("res://host/platform/posix_process_owner.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const BASH := "/bin/bash"
var passed := 0
var failed := 0
var work := ""
var fixture := ""
var launcher

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

func _hang(fifo_name: String) -> Dictionary:
	var launch_id := Crypto.new().generate_random_bytes(16).hex_encode()
	var fifo := work.path_join(fifo_name)
	var maker := Crypto.new().generate_random_bytes(16).hex_encode()
	launcher._posix.trust("/usr/bin/mkfifo")
	launcher._posix.launch(maker, "/usr/bin/mkfifo", PackedStringArray([fifo]))
	while launcher._posix.probe(maker) == "running":
		OS.delay_msec(2)
	launcher._posix.forget(maker)
	var started: Dictionary = launcher.launch({"executable": BASH, "args": [fixture]}, launch_id, PackedStringArray(["--launch-id=" + launch_id, "--mode=hang", "--fifo=" + fifo]))
	return {"ok": started.ok, "launch_id": launch_id, "pid": int(started.pid)}

func _until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return bool(predicate.call())

func _run() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix journal rules (this is ", OS.get_name(), ")")
		print("POSIX_JOURNAL_RESULT passed=0 failed=0 not_run=1")
		quit(0)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work="):
			work = argument.trim_prefix("--work=")
		elif argument.begins_with("--fixture="):
			fixture = argument.trim_prefix("--fixture=")
	if work == "" or fixture == "" or not DirAccess.dir_exists_absolute(work):
		print("FAIL --work (existing folder inside res://data) and --fixture are required")
		quit(2)
		return
	launcher = Launcher.new()
	var backend = Owner.PosixBackend.new()
	var boot := Launcher.boot_id()
	check(boot.length() >= 16, "the kernel boot id is readable")

	# ---- journal_record of a real child ----
	var child := _hang("fifo-a")
	var record: Dictionary = launcher.journal_record(child.launch_id)
	var journal := {"version": 1, "entries": {child.launch_id: {"port": 42001, "owned": record}}}
	check(child.ok and record.platform == "linux" and int(record.pid) == child.pid and record.boot_id == boot and str(record.start_time) != "" and Launcher.inspectable(record), "journal_record of an owned child holds pid, parent, executable, start time and boot id")
	check(Validator.validate_file(journal, "res://schemas/process_journal.schema.json") == "", "a journal with a Linux record matches the journal schema")
	check(not JSON.stringify(record).contains("handoff") and not record.has("state"), "the journal record carries no hand-over token and no live state")
	check(Launcher.inspect_previous(record).state == "running", "the same pid with the same start time is reported running")

	# ---- records that must count as gone (read-only; nothing is signalled) ----
	var self_seen: Dictionary = backend.identity(OS.get_process_id())
	var foreign := {"platform": "linux", "launch_id": "b".repeat(32), "pid": OS.get_process_id(), "parent_pid": 1, "executable": BASH, "start_time": str(int(self_seen.start_time) + 1), "boot_id": boot}
	check(Launcher.inspect_previous(foreign).state == "exited" and not backend.identity(OS.get_process_id()).is_empty(), "a live PID with another start time (reused by an unrelated process) counts as the old process gone, and that process is untouched")
	var rebooted := record.duplicate()
	rebooted.boot_id = "00000000-0000-0000-0000-000000000000"
	check(Launcher.inspect_previous(rebooted).state == "exited", "a record from before a restart of the kernel (other boot id) counts as gone")
	var missing := record.duplicate()
	missing.pid = 4194303  # above the default pid_max: no such process
	check(Launcher.inspect_previous(missing).state == "exited", "a PID that no longer exists counts as gone")
	var incomplete := record.duplicate()
	incomplete.erase("start_time")
	check(not Launcher.inspectable(incomplete) and Launcher.inspect_previous(incomplete).state == "unknown", "a record without a start time is not inspectable (its port stays quarantined)")
	check(Launcher.inspect_previous({}).state == "unknown" and not Launcher.inspectable({"verified": false}), "an empty or unverified record stays unknown")
	var windows_record := {"pid": 1234, "verified": true, "exited": false, "launch_id": "c".repeat(32), "created_filetime": "1", "executable": "x", "parent_pid": 1, "termination_requested": false}
	check(Launcher.inspect_previous(windows_record).state == "unknown", "a Windows record is never inspected on Linux")
	var zombie := _hang("fifo-z")
	var zombie_record: Dictionary = launcher.journal_record(zombie.launch_id)
	var kills: int = launcher._posix.kills_sent()
	# Make it a zombie: end it through the owner WITHOUT reaping is impossible, so
	# end it from outside and read /proc before the owner looks at it.
	var killer := Crypto.new().generate_random_bytes(16).hex_encode()
	launcher._posix.trust(BASH)
	launcher._posix.launch(killer, BASH, PackedStringArray(["-c", "kill -KILL \"$1\"", "bash", str(zombie.pid)]))
	while launcher._posix.probe(killer) == "running":
		OS.delay_msec(2)
	launcher._posix.forget(killer)
	await _until(func(): return backend.identity(zombie.pid).get("state", "Z") == "Z", 3000)
	check(backend.identity(zombie.pid).get("state", "") == "Z" and Launcher.inspect_previous(zombie_record).state == "exited", "a zombie (exited, not yet reaped) counts as gone")
	launcher.probe(zombie.launch_id)
	launcher.forget(zombie.launch_id)

	# ---- RecoveryGuard across runs ----
	var journal_path := work.path_join("processes.json")
	var holder := PacketPeerUDP.new()
	var ports = Ports.new(42100, 42107)
	var busy_port := 42103
	# Each entry's record carries its own launch id (the guard refuses a journal
	# whose record names another entry).
	var gone := missing.duplicate()
	gone.launch_id = "e".repeat(32)
	var file := FileAccess.open(journal_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "entries": {child.launch_id: {"port": 42101, "owned": record}, "d".repeat(32): {"port": 42102, "owned": {}}, "e".repeat(32): {"port": busy_port, "owned": gone}}}))
	file.close()
	check(holder.bind(busy_port, "127.0.0.1") == OK, "(setup) an unrelated socket holds one journalled port")
	var guard = Guard.new()
	check(guard.initialize(journal_path, ports) and guard.orphans.size() == 3 and ports.leases.size() == 3, "a new run loads three entries of an earlier run and quarantines their ports")
	check((int(FileAccess.get_unix_permissions(journal_path)) & 4095) == 384 and (int(FileAccess.get_unix_permissions(work)) & 4095) == 448, "the journal is 600 in a 700 folder")
	for round in 3:
		guard.poll()
		await _until(func(): return guard.idle(), 3000)
		guard.poll()
		await create_timer(1.1).timeout
	check(guard.orphans.has(child.launch_id) and ports.leases.has("orphan:" + child.launch_id), "an entry whose process still runs keeps its port quarantined")
	check(guard.orphans.has("d".repeat(32)) and ports.leases.has("orphan:" + "d".repeat(32)), "an entry recorded before identity capture (no record) stays quarantined")
	check(guard.orphans.has("e".repeat(32)) and ports.leases.has("orphan:" + "e".repeat(32)), "an entry whose process is gone but whose port is still bound stays quarantined")
	check(launcher.probe(child.launch_id) == "running" and launcher._posix.kills_sent() == kills, "the guard signalled nothing; the recorded child still runs")
	holder.close()
	check(launcher.terminate(child.launch_id), "(test) the test ends its own child")
	var released := await _until(func():
		guard.poll()
		return not guard.orphans.has(child.launch_id) and not guard.orphans.has("e".repeat(32)), 12000)
	check(released and not ports.leases.has("orphan:" + child.launch_id) and not ports.leases.has("orphan:" + "e".repeat(32)) and ports.leases.has("orphan:" + "d".repeat(32)), "once the process is gone and the port can be bound again, only those entries are released; the unknown one stays")
	var saved := JSON.parse_string(FileAccess.get_file_as_string(journal_path)) as Dictionary
	check(saved.entries.size() == 1 and saved.entries.has("d".repeat(32)), "the journal on disk keeps only the unknown entry")
	launcher.forget(child.launch_id)
	for name in DirAccess.get_files_at(work):
		if name.begins_with("fifo-"):
			DirAccess.remove_absolute(work.path_join(name))
	print("POSIX_JOURNAL_RESULT passed=", passed, " failed=", failed, " not_run=0")
	quit(0 if failed == 0 else 1)
