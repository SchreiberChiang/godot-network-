extends RefCounted
## Linux child-process ownership: start, liveness, exit code, forced stop, reaping.
## Used for room programs, one-shot helpers and resident workers alike.
##
## One registry for the whole parent process
##  All owned children live in ONE process-wide table behind ONE lock (static
##  state below). Objects of this class are only holders: each record has exactly
##  one holder at a time, and every engine call for an owned PID happens inside
##  the registry lock, whichever object or thread asked. A second manager for the
##  same child cannot exist: there is no way to add a record for a PID except by
##  starting it here, and responsibility moves between objects only with a
##  single-use hand-over token (offer/accept). Dictionaries returned by record()
##  are observations and grant nothing.
##
## Why a forced stop here does not reach an unrelated process
##  1. POSIX keeps the PID of a child reserved (running or zombie) until its
##     parent waits for it.
##  2. Supported engine only: Godot 4.7.2 stable, commit ed1daf0bf (the build
##     checked in SUPPORTED_ENGINE). In that source (drivers/unix/os_unix.cpp) a
##     child is waited for only inside OS.is_process_running,
##     OS.get_process_exit_code and OS.kill for that PID; there is no SIGCHLD
##     handler and no wait for "any child". That statement comes from reading
##     that one source revision; any other engine build is refused here rather
##     than assumed to behave the same. The SIGCHLD disposition is additionally
##     checked at run time (ignored would make the kernel reap, caught could let a
##     handler reap); that check is a guard, not a proof of the source behaviour.
##  3. The only callers of those three engine functions for an owned PID are
##     _observe and terminate below, always under the registry lock. Once a child
##     has been seen as not running (that call reaped it) its record is EXITED
##     and the engine is never asked about, or told to signal, that PID again.
##  4. A forced stop is: confirm running, confirm /proc still shows our direct
##     child with the start time recorded at launch, then OS.kill, all in one
##     critical section. OS.kill's result is checked: on failure nothing is
##     assumed, the record stays unfinished and its pipes stay open.
##  5. Every place in this repository that asks the engine to poll, reap or
##     signal a child (checked 2026-09-30):
##       - PosixBackend.is_running / exit_code / kill in this file: the only
##         ones used for registry children, reached only from _observe and
##         terminate.
##       - process_launcher.gd, bounded_helper.gd and storage/resident_store.gd
##         call OS.is_process_running, OS.get_process_exit_code and OS.kill
##         only in their Windows branches, for children they started
##         themselves with powershell.exe. Their Linux branches start pwsh
##         through posix_helper.gd, i.e. launch(..., piped = true) here, and
##         make no engine process call of their own.
##       - OS.execute (Windows helpers, tests) waits only for the one child it
##         started itself. On Unix it runs through a shell, so nothing under
##         host/platform uses it for Linux.
##     A new caller of those engine functions on Linux breaks this argument and
##     must go through this registry.
## Records that do not match are QUARANTINED: never signalled, reported unknown,
## kept for diagnosis. Processes that are not children of this process can never
## enter the registry.
const RUNNING := "running"
const EXITED := "exited"
const QUARANTINED := "quarantined"
const KILLED_EXIT_CODE := -9
const MAX_TERMINATE_FAILURES := 3
const SUPPORTED_ENGINE := {"major": 4, "minor": 7, "patch": 2, "status": "stable", "hash": "ed1daf0bf001b61586d9930840f2f1394092c079"}

static var _guard := Mutex.new()
static var _worlds: Dictionary = {}
static var _real_backend
static var _next_holder := 0

var backend
var invariant_ok := false
var invariant_detail := ""
var _holder := 0
var _trusted: Dictionary = {}

class PosixBackend extends RefCounted:
	func self_pid() -> int:
		return OS.get_process_id()
	func engine_supported() -> bool:
		var version := Engine.get_version_info()
		return OS.get_name() == "Linux" and int(version.major) == int(SUPPORTED_ENGINE.major) and int(version.minor) == int(SUPPORTED_ENGINE.minor) and int(version.patch) == int(SUPPORTED_ENGINE.patch) and str(version.status) == str(SUPPORTED_ENGINE.status) and str(version.hash) == str(SUPPORTED_ENGINE.hash)
	func create_process(executable: String, arguments: PackedStringArray) -> int:
		return OS.create_process(executable, arguments, false)
	## blocking = false puts both ends this process holds in O_NONBLOCK mode:
	## a read returns what is there (possibly nothing) and a write of at most
	## PIPE_BUF (4096) bytes is written whole or not at all.
	func create_piped(executable: String, arguments: PackedStringArray, blocking := true) -> Dictionary:
		return OS.execute_with_pipe(executable, arguments, blocking)
	func is_running(pid: int) -> bool:
		return OS.is_process_running(pid)
	func exit_code(pid: int) -> int:
		return OS.get_process_exit_code(pid)
	func kill(pid: int) -> int:
		return OS.kill(pid)
	func read(path: String) -> String:
		# /proc files report length 0; read what is there instead of trusting it.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		var bytes := file.get_buffer(65536)
		file.close()
		# cmdline separates arguments with NUL; keep them apart as newlines.
		var copy := bytes.duplicate()
		for index in copy.size():
			if copy[index] == 0:
				copy[index] = 10
		return copy.get_string_from_utf8()
	## SIGCHLD is signal 17 on Linux: bit 16 of the masks in /proc/self/status.
	func sigchld_disposition() -> String:
		var ignored := -1
		var caught := -1
		for line in read("/proc/self/status").split("\n"):
			if line.begins_with("SigIgn:"):
				ignored = line.substr(7).strip_edges().hex_to_int()
			elif line.begins_with("SigCgt:"):
				caught = line.substr(7).strip_edges().hex_to_int()
		if ignored < 0 or caught < 0:
			return "unknown"
		if ignored & (1 << 16):
			return "ignored"
		if caught & (1 << 16):
			return "caught"
		return "default"
	## {} when the process has no /proc entry. "state" is the kernel state letter
	## (Z = exited but not yet waited for).
	func identity(pid: int) -> Dictionary:
		var stat := read("/proc/%d/stat" % pid)
		var close := stat.rfind(")")
		if close < 0:
			return {}
		var fields := stat.substr(close + 2).strip_edges().split(" ")
		if fields.size() < 20:
			return {}
		return {"state": fields[0], "ppid": int(fields[1]), "start_time": fields[19], "arguments": read("/proc/%d/cmdline" % pid).split("\n", false)}

## A custom backend is for tests only; owners sharing one backend object share
## one registry, exactly as every real owner shares the process-wide one.
func _init(custom_backend = null) -> void:
	_guard.lock()
	if custom_backend == null:
		if _real_backend == null:
			_real_backend = PosixBackend.new()
		backend = _real_backend
	else:
		backend = custom_backend
	_next_holder += 1
	_holder = _next_holder
	if not _worlds.has(backend.get_instance_id()):
		_worlds[backend.get_instance_id()] = {"records": {}, "offers": {}}
	_guard.unlock()
	var engine_ok: bool = backend.engine_supported()
	var disposition: String = backend.sigchld_disposition()
	invariant_ok = engine_ok and disposition == "default"
	invariant_detail = "engine %s, SIGCHLD disposition is %s" % ["supported" if engine_ok else "NOT the supported build", disposition]

## A holder that goes away must not take its children's records with it: they
## become unheld and can be claimed or shut down by another holder.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_guard.lock()
		var world: Dictionary = _worlds.get(backend.get_instance_id(), {}) if backend != null else {}
		for owned in world.get("records", {}).values():
			if int(owned.holder) == _holder:
				owned.holder = 0
		_guard.unlock()

## Executables come from trusted host configuration only (never from a client).
func trust(executable: String) -> void:
	if executable.is_absolute_path():
		_guard.lock()
		_trusted[executable] = true
		_guard.unlock()

## arguments are passed as a vector to fork/exec; nothing goes through a shell.
## marker: when not empty, exactly this argument must be present and is later
## required in the child's command line (room programs use "--launch-id=<id>").
## piped: also returns "stdio" and "stderr" (one-shot helpers, resident workers).
## blocking: with piped, false asks for non-blocking pipes (see PosixBackend).
func launch(launch_id: String, executable: String, arguments: PackedStringArray, marker := "", piped := false, blocking := true) -> Dictionary:
	if not invariant_ok:
		return _failure("PROCESS_OWNERSHIP_UNAVAILABLE")
	_guard.lock()
	var trusted: bool = _trusted.has(executable)
	_guard.unlock()
	if not _valid_id(launch_id) or not trusted or (marker != "" and arguments.count(marker) != 1):
		return _failure("INVALID_OPTIONS")
	if not FileAccess.file_exists(executable):
		return _failure("PROGRAM_NOT_FOUND")
	_guard.lock()
	var records := _records()
	if records.has(launch_id):
		_guard.unlock()
		return _failure("INVALID_OPTIONS")
	var pipes: Dictionary = {}
	var pid := -1
	if piped:
		pipes = backend.create_piped(executable, arguments) if blocking else backend.create_piped(executable, arguments, false)
		pid = int(pipes.get("pid", -1))
	else:
		pid = backend.create_process(executable, arguments)
	if pid <= 0:
		_guard.unlock()
		return _failure("PROCESS_LAUNCH_FAILED")
	var owned := {"launch_id": launch_id, "holder": _holder, "pid": pid, "parent_pid": backend.self_pid(), "executable": executable, "marker": marker, "state": RUNNING, "exit_code": -1, "start_time": "", "terminate_failures": 0, "last_error": "", "stdio": pipes.get("stdio"), "stderr": pipes.get("stderr")}
	records[launch_id] = owned
	_capture(owned)
	var result := {"ok": owned.state != QUARANTINED, "code": "" if owned.state != QUARANTINED else "PROCESS_IDENTITY_UNVERIFIED", "pid": pid}
	if piped:
		result.stdio = owned.stdio
		result.stderr = owned.stderr
	_guard.unlock()
	return result

## "running", "exited", or "unknown" (not held by this object, or quarantined).
func probe(launch_id: String) -> String:
	_guard.lock()
	var state := "unknown"
	var owned := _held(launch_id)
	if not owned.is_empty():
		_observe(owned)
		state = owned.state if owned.state != QUARANTINED else "unknown"
	_guard.unlock()
	return state

## Exit code once exited (KILLED_EXIT_CODE after a forced stop), else -1.
func exit_code(launch_id: String) -> int:
	_guard.lock()
	var code := -1
	var owned := _held(launch_id)
	if not owned.is_empty():
		_observe(owned)
		code = int(owned.exit_code)
	_guard.unlock()
	return code

## True only when the child is confirmed gone. An exited or quarantined record
## is never signalled. When the engine reports that the signal could not be
## sent, or the child is still there afterwards, nothing is assumed: the record
## stays RUNNING with its pipes open and a failure count, and the call returns
## false. It may be retried; after MAX_TERMINATE_FAILURES the record is
## quarantined so it is never signalled again and stays visible for diagnosis.
## keep_pipes: leave the pipes open on success (they are closed by forget()), for
## callers whose other thread may still be inside a read on them.
func terminate(launch_id: String, keep_pipes := false) -> bool:
	_guard.lock()
	var confirmed := false
	var owned := _held(launch_id)
	if not owned.is_empty():
		_observe(owned)
		if owned.state == EXITED:
			confirmed = true
		elif owned.state == RUNNING:
			var seen: Dictionary = backend.identity(int(owned.pid))
			if seen.is_empty() or int(seen.ppid) != int(owned.parent_pid) or str(seen.start_time) != str(owned.start_time):
				owned.state = QUARANTINED
				owned.last_error = "IDENTITY_MISMATCH"
			else:
				_count_kill()
				var result: int = backend.kill(int(owned.pid))
				var after: Dictionary = backend.identity(int(owned.pid)) if result == OK else {}
				var still_ours: bool = not after.is_empty() and int(after.ppid) == int(owned.parent_pid) and str(after.start_time) == str(owned.start_time)
				if result == OK and not still_ours:
					# The engine signalled and waited for it: reaped, never ask again.
					owned.state = EXITED
					owned.exit_code = KILLED_EXIT_CODE
					if not keep_pipes:
						_close_pipes(owned)
					confirmed = true
				else:
					owned.terminate_failures = int(owned.terminate_failures) + 1
					owned.last_error = "KILL_FAILED" if result != OK else "STILL_PRESENT_AFTER_KILL"
					if int(owned.terminate_failures) >= MAX_TERMINATE_FAILURES:
						owned.state = QUARANTINED
	_guard.unlock()
	return confirmed

## Releases an EXITED record (and closes its pipes). Anything else is kept.
func forget(launch_id: String) -> bool:
	_guard.lock()
	var removed := false
	var owned := _held(launch_id)
	if not owned.is_empty():
		_observe(owned)
		if owned.state == EXITED:
			_close_pipes(owned)
			_records().erase(launch_id)
			_drop_offers(launch_id)
			removed = true
	_guard.unlock()
	return removed

## An observation for logs and status. It contains no argument vector, pipes or
## credentials, and it cannot be used to gain ownership.
func record(launch_id: String) -> Dictionary:
	_guard.lock()
	var copy := {}
	var owned := _held(launch_id)
	if not owned.is_empty():
		copy = {"launch_id": owned.launch_id, "pid": owned.pid, "parent_pid": owned.parent_pid, "executable": owned.executable, "state": owned.state, "exit_code": owned.exit_code, "start_time": owned.start_time, "terminate_failures": owned.terminate_failures, "last_error": owned.last_error}
	_guard.unlock()
	return copy

## The pipes of a piped child held by this object (they move with a hand-over).
func pipes(launch_id: String) -> Dictionary:
	_guard.lock()
	var owned := _held(launch_id)
	var found := {} if owned.is_empty() else {"stdio": owned.stdio, "stderr": owned.stderr}
	_guard.unlock()
	return found

## Hand-over, step 1: returns a single-use token, or "" when this object does not
## hold a RUNNING record. The record STAYS with this object (and it stays
## responsible for it) until another holder accepts the token.
func offer(launch_id: String) -> String:
	_guard.lock()
	var token := ""
	var owned := _held(launch_id)
	if not owned.is_empty() and owned.state == RUNNING:
		_drop_offers(launch_id)
		token = Crypto.new().generate_random_bytes(32).hex_encode()
		_world().offers[token] = launch_id
	_guard.unlock()
	return token

## Hand-over, step 2: atomically makes this object the holder. The token is
## consumed whether or not it succeeds, so it works once, for one receiver. The
## child is re-checked against /proc; pipes move with the record. Returns the
## launch id, or "" when refused. expected: when not empty, the launch id the
## receiver was told; a token for any other child is refused (and still spent),
## and that child stays with its current holder.
func accept(token: String, expected := "") -> String:
	if not invariant_ok or token.length() != 64:
		return ""
	_guard.lock()
	var world := _world()
	var launch_id := str(world.offers.get(token, ""))
	world.offers.erase(token)
	var accepted := ""
	var owned: Dictionary = world.records.get(launch_id, {})
	if not owned.is_empty() and int(owned.holder) != _holder and (expected == "" or expected == launch_id):
		_observe(owned)
		var seen: Dictionary = backend.identity(int(owned.pid)) if owned.state == RUNNING else {}
		if owned.state == RUNNING and not seen.is_empty() and int(seen.ppid) == int(owned.parent_pid) and str(seen.start_time) == str(owned.start_time):
			owned.holder = _holder
			accepted = launch_id
	_guard.unlock()
	return accepted

## Takes a record whose holder object no longer exists. One winner.
func claim_unheld(launch_id: String) -> bool:
	_guard.lock()
	var owned: Dictionary = _records().get(launch_id, {})
	var claimed: bool = invariant_ok and not owned.is_empty() and int(owned.holder) == 0
	if claimed:
		owned.holder = _holder
	_guard.unlock()
	return claimed

## Normal stop of the parent: stops every child this object holds, and every
## unheld one. Returns the launch ids that could not be confirmed gone.
func shutdown_all() -> Array:
	var remaining: Array = []
	for launch_id in unheld_ids():
		claim_unheld(launch_id)
	for launch_id in launch_ids():
		if not terminate(launch_id):
			remaining.append(launch_id)
	return remaining

func launch_ids() -> Array:
	_guard.lock()
	var ids: Array = []
	for owned in _records().values():
		if int(owned.holder) == _holder:
			ids.append(owned.launch_id)
	_guard.unlock()
	return ids

func unheld_ids() -> Array:
	_guard.lock()
	var ids: Array = []
	for owned in _records().values():
		if int(owned.holder) == 0:
			ids.append(owned.launch_id)
	_guard.unlock()
	return ids

## Signals sent through this registry (all holders), for tests and diagnostics.
func kills_sent() -> int:
	_guard.lock()
	var count := int(_world().get("kills", 0))
	_guard.unlock()
	return count

# ---- internals, always under _guard ----
func _world() -> Dictionary:
	return _worlds[backend.get_instance_id()]

func _records() -> Dictionary:
	return _world().records

func _held(launch_id: String) -> Dictionary:
	var owned: Dictionary = _records().get(launch_id, {})
	return owned if not owned.is_empty() and int(owned.holder) == _holder else {}

func _count_kill() -> void:
	_world()["kills"] = int(_world().get("kills", 0)) + 1

func _drop_offers(launch_id: String) -> void:
	var offers: Dictionary = _world().offers
	for token in offers.keys():
		if offers[token] == launch_id:
			offers.erase(token)

func _capture(owned: Dictionary) -> void:
	# Right after fork the child still shows the parent's command line; wait
	# briefly for exec (the marker appears) or for an early exit.
	var deadline := Time.get_ticks_msec() + 1000
	while true:
		var seen: Dictionary = backend.identity(int(owned.pid))
		if seen.is_empty() or int(seen.ppid) != int(owned.parent_pid):
			_observe(owned)
			if owned.state == RUNNING:
				owned.state = QUARANTINED
				owned.last_error = "IDENTITY_UNVERIFIED"
			return
		owned.start_time = str(seen.start_time)
		if seen.state == "Z" or str(owned.marker) == "" or seen.arguments.has(str(owned.marker)):
			return
		if Time.get_ticks_msec() >= deadline:
			owned.state = QUARANTINED
			owned.last_error = "MARKER_UNVERIFIED"
			return
		OS.delay_msec(5)

func _observe(owned: Dictionary) -> void:
	if owned.state != RUNNING:
		return
	if not backend.is_running(int(owned.pid)):
		# That call reaped the child: from here on the PID is no longer ours.
		# Pipes stay open so the holder can still read what the child wrote.
		owned.state = EXITED
		owned.exit_code = backend.exit_code(int(owned.pid))

func _close_pipes(owned: Dictionary) -> void:
	for key in ["stdio", "stderr"]:
		if owned.get(key) != null:
			owned[key].close()
			owned[key] = null

func _valid_id(value: String) -> bool:
	if value.length() < 16 or value.length() > 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "pid": -1}
