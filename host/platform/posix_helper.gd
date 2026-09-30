extends RefCounted
## Linux: runs the PowerShell storage scripts of tools/ as children owned by
## posix_process_owner.gd. Used by bounded_helper.gd (one-shot calls) and
## storage/resident_store.gd (resident workers). Windows never reaches this file.
##
## - The PowerShell executable comes only from the environment variable
##   ROOMKIT_PWSH, set by the trusted start-up configuration of the host. It must
##   be an absolute path to an executable file; otherwise every call fails with
##   HELPER_DEPENDENCY_MISSING. Nothing is searched on PATH and no client value
##   reaches it.
## - The child is started with an argument vector (fork/exec through the owner),
##   never through a shell and never through OS.execute. Arguments carry only
##   script names, database and request-file paths and numbers. Request bodies
##   that hold passwords, tokens or keys go to the child's standard input as one
##   base64 line; nothing secret is written to a file or a command line here.
## - Deadlines do not depend on stopping the child. The pipes are non-blocking
##   and pump() is one loop on the calling thread: it writes the request in
##   pieces of at most PIPE_BUF (4096) bytes (each written whole or not at all),
##   reads standard output up to a limit, reads and throws away standard error
##   (never returned or logged: it may quote request content), and gives up at
##   the deadline whatever the child does. The deadline is absolute: it is
##   checked on every pass and inside the standard-error drain, so a child that
##   keeps writing cannot extend it, and a reply that arrives after it is not
##   accepted. No reader or watchdog thread exists, so none can be left behind.
## - At the deadline the child is ended through the owner. When that cannot be
##   confirmed, the call still returns at once with HELPER_UNFINISHED; the owner
##   keeps the record (with its pipes) and the launch id is parked here. Every
##   later start first retries the parked ones and releases those now confirmed
##   gone. A record the owner quarantined stays parked for diagnosis.
## - Budget (one lock, reserved before any process is started): every helper
##   start takes a slot, and a slot is held until its child is confirmed gone
##   (one-shot), handed to a resident store (worker), or parked. Slots in use =
##   in-flight starts and calls + parked records <= MAX_HELPERS, so at no time do
##   more than MAX_HELPERS one-shot children or parked records exist, however
##   many threads call at once. A start is refused without starting anything
##   when MAX_UNFINISHED or more are parked (HELPER_BACKLOG_FULL) or when all
##   slots are in use (HELPER_CAPACITY_FULL). A start whose identity could not be
##   verified leaves a quarantined record in the owner; it is parked, not lost.
##   Resident workers are outside the slots once started: one per database, and
##   a blocked store never starts a second one.
## - SIGPIPE: Godot 4.7.2's pipe write (drivers/unix/file_access_unix_pipe.cpp)
##   sets SIGPIPE to ignored around each write and then restores the previous
##   disposition. With two threads writing at once, one can restore the default
##   while the other is still writing to a child that just exited, and the
##   default disposition ends the whole host. The host must therefore be STARTED
##   with SIGPIPE ignored (inherited across exec: `trap '' PIPE` in the start
##   script, or systemd's default IgnoreSIGPIPE=yes); then every restore puts
##   back "ignored". Checked at run time from /proc/self/status; when not ignored
##   no helper is started and every call fails with HELPER_PIPE_UNSAFE.
const Owner = preload("res://host/platform/posix_process_owner.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const SHELL_VARIABLE := "ROOMKIT_PWSH"
const DIAGNOSTICS_VARIABLE := "DOTNET_EnableDiagnostics"
const LISTENER_VARIABLE := "POWERSHELL_DIAGNOSTICS_OPTOUT"
const ONE_SHOT := ["sqlite_store.ps1", "account_store.ps1", "operator_maintenance.ps1"]
const WORKER := "storage_worker.ps1"
const OUTPUT_LIMIT := 4 * 1024 * 1024
const PIPE_BUF := 4096
const MAX_UNFINISHED := 4
const MAX_HELPERS := 8
const UNKNOWN := "unknown"

static var _lock := Mutex.new()
static var _owner
## Launch ids of one-shot helpers that could not be confirmed gone.
static var _parked: Array = []
## Slots held by starts and one-shot calls still in progress.
static var _in_flight := 0

## The single holder of every storage child of this process.
static func owner():
	_lock.lock()
	if _owner == null:
		_owner = Owner.new()
	var found = _owner
	_lock.unlock()
	return found

## "" when helpers can run here, otherwise the reason (a HELPER_ code).
static func dependency() -> String:
	if OS.get_name() != "Linux":
		return "HELPER_UNSUPPORTED_PLATFORM"
	var shell := OS.get_environment(SHELL_VARIABLE)
	if not shell.is_absolute_path() or not FileAccess.file_exists(shell) or (int(FileAccess.get_unix_permissions(shell)) & 64) == 0:
		return "HELPER_DEPENDENCY_MISSING"
	if not owner().invariant_ok:
		return "HELPER_OWNERSHIP_UNAVAILABLE"
	if not _sigpipe_ignored():
		return "HELPER_PIPE_UNSAFE"
	return ""

## Launch ids still parked (for diagnostics and tests).
static func parked() -> Array:
	_lock.lock()
	var copy := _parked.duplicate()
	_lock.unlock()
	return copy

## Retries every parked helper; returns how many are still parked.
static func retry_parked() -> int:
	var holder = owner()
	_lock.lock()
	var still: Array = []
	for launch_id in _parked:
		if holder.record(launch_id).is_empty():
			continue  # released elsewhere already
		if holder.terminate(launch_id, true):  # no signal when it already exited
			holder.forget(launch_id)  # closes its pipes
		else:
			still.append(launch_id)
	_parked = still
	var count := _parked.size()
	_lock.unlock()
	return count

## Starts tools/<script> with non-blocking pipes. {"ok", "code", "id", "pid",
## "stdio", "stderr"}; the caller owns the launch id through owner() and must
## terminate/forget it (or park it).
static func spawn(script: String, arguments: Array) -> Dictionary:
	var reason := dependency()
	if reason != "":
		return {"ok": false, "code": reason}
	var path := Paths.absolute("res://tools/" + script)
	if (not script in ONE_SHOT and script != WORKER) or not FileAccess.file_exists(path):
		return {"ok": false, "code": "HELPER_FAILED"}
	retry_parked()
	_lock.lock()
	var refused := ""
	if _parked.size() >= MAX_UNFINISHED:
		refused = "HELPER_BACKLOG_FULL"
	elif _in_flight + _parked.size() >= MAX_HELPERS:
		refused = "HELPER_CAPACITY_FULL"
	else:
		_in_flight += 1  # reserved before anything is started
	_lock.unlock()
	if refused != "":
		return {"ok": false, "code": refused}
	var vector := PackedStringArray(["-NoProfile", "-NonInteractive", "-File", path])
	for argument in arguments:
		vector.append(str(argument))
	var shell := OS.get_environment(SHELL_VARIABLE)
	var holder = owner()
	holder.trust(shell)
	# Every .NET process creates a debugger pipe pair and a diagnostics socket in
	# the temporary folder and removes them on a normal exit only, so each helper
	# ended at a deadline would leave three files behind. PowerShell (7.6+) adds a
	# listener socket of its own with the same fate. The helpers need none of them.
	if OS.get_environment(DIAGNOSTICS_VARIABLE) != "0":
		OS.set_environment(DIAGNOSTICS_VARIABLE, "0")
	if OS.get_environment(LISTENER_VARIABLE) != "1":
		OS.set_environment(LISTENER_VARIABLE, "1")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var started: Dictionary = holder.launch(id, shell, vector, "", true, false)
	if not started.ok:
		# A start whose identity could not be verified stays quarantined in the
		# owner: its slot becomes a parked record. Otherwise nothing exists.
		_settle(id, holder.record(id).is_empty())
		return {"ok": false, "code": "HELPER_FAILED"}
	if script == WORKER:
		_settle(id, true)  # from here on the resident store is responsible
	return {"ok": true, "code": "", "id": id, "pid": int(started.pid), "stdio": started.stdio, "stderr": started.stderr}

## One exchange with a child on non-blocking pipes, bounded by `deadline`
## (Time.get_ticks_msec()). Writes all of `outgoing`, collects standard output
## (at most `limit` bytes), discards standard error. Returns {"state", "output"}:
##   "line"     first newline received (only when stop_at_line)
##   "exited"   the child is no longer running; its remaining output was read
##   "deadline" the deadline passed first
##   "overflow" more than `limit` bytes of output
static func pump(launch_id: String, stdio: FileAccess, stderr: FileAccess, outgoing: PackedByteArray, deadline: int, limit: int, stop_at_line: bool) -> Dictionary:
	var holder = owner()
	var output := PackedByteArray()
	var sent := 0
	while true:
		if Time.get_ticks_msec() >= deadline:
			return {"state": "deadline", "output": output}
		var progressed := false
		if sent < outgoing.size():
			var piece := outgoing.slice(sent, mini(sent + PIPE_BUF, outgoing.size()))
			if stdio.store_buffer(piece):
				sent += piece.size()
				progressed = true
		var received := stdio.get_buffer(65536)
		if not received.is_empty():
			progressed = true
			if output.size() + received.size() > limit:
				return {"state": "overflow", "output": output}
			output.append_array(received)
			if stop_at_line and received.has(10):
				# A reply read after the deadline is late and not accepted.
				return {"state": "line" if Time.get_ticks_msec() < deadline else "deadline", "output": output}
		if _discard(stderr, deadline) > 0:
			progressed = true
		if not progressed:
			if holder.probe(launch_id) != "running":
				# Gone: everything it wrote is already in the pipes.
				while output.size() <= limit and Time.get_ticks_msec() < deadline:
					received = stdio.get_buffer(65536)
					if received.is_empty():
						break
					output.append_array(received)
				_discard(stderr, deadline)
				if Time.get_ticks_msec() >= deadline:
					return {"state": "deadline", "output": output}
				if output.size() > limit:
					return {"state": "overflow", "output": output}
				if stop_at_line and output.has(10):
					return {"state": "line", "output": output}
				return {"state": "exited", "output": output}
			OS.delay_msec(2)
	return {"state": "deadline", "output": output}

## One bounded call: optional single input line, one JSON object on standard
## output, exit code 0. Returns that object, or {"ok": false, "code": "HELPER_...",
## "state": "unknown"}. Returns by the deadline (plus the time of one stop
## attempt) even when the child cannot be stopped.
static func run(script: String, arguments: Array, line: String, timeout_ms: int) -> Dictionary:
	if not script in ONE_SHOT:
		return _failure("HELPER_FAILED")
	var child := spawn(script, arguments)
	if not child.ok:
		return _failure(child.code)
	var holder = owner()
	var id: String = child.id
	var outgoing := PackedByteArray() if line == "" else (line + "\n").to_utf8_buffer()
	var outcome := pump(id, child.stdio, child.stderr, outgoing, Time.get_ticks_msec() + timeout_ms, OUTPUT_LIMIT, false)
	if not holder.terminate(id, true):  # no signal when it already exited
		_settle(id, false)
		return _failure("HELPER_UNFINISHED")
	_settle(id, true)
	var code: int = holder.exit_code(id)
	holder.forget(id)  # closes the pipes
	if outcome.state == "deadline":
		return _failure("HELPER_TIMEOUT")
	if outcome.state != "exited" or code != 0 or outcome.output.is_empty():
		return _failure("HELPER_FAILED")
	# JSON.parse_string would print the unparsable text to the engine log.
	var reader := JSON.new()
	if reader.parse(outcome.output.get_string_from_utf8().strip_edges()) != OK or not reader.data is Dictionary:
		return _failure("HELPER_FAILED")
	return reader.data

## Gives back a start's slot: released when its child is gone (or handed to a
## resident store), otherwise turned into a parked record, in one step.
static func _settle(launch_id: String, released: bool) -> void:
	_lock.lock()
	_in_flight -= 1
	if not released:
		_parked.append(launch_id)
	_lock.unlock()

## Slots in use right now: {"in_flight", "parked"} (diagnostics and tests).
static func budget() -> Dictionary:
	_lock.lock()
	var used := {"in_flight": _in_flight, "parked": _parked.size()}
	_lock.unlock()
	return used

## Reads what standard error holds right now (at most 1 MiB per call, never past
## the deadline) and keeps nothing. Returns the number of bytes thrown away.
static func _discard(pipe: FileAccess, deadline: int) -> int:
	var total := 0
	while total < 1024 * 1024 and Time.get_ticks_msec() < deadline:
		var chunk := pipe.get_buffer(65536)
		if chunk.is_empty():
			break
		total += chunk.size()
	return total

## SIGPIPE is signal 13: bit 12 of SigIgn in /proc/self/status.
static func _sigpipe_ignored() -> bool:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return false
	var text := file.get_buffer(8192).get_string_from_utf8()
	file.close()
	for entry in text.split("\n"):
		if entry.begins_with("SigIgn:"):
			return (entry.substr(7).strip_edges().hex_to_int() & (1 << 12)) != 0
	return false

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "state": UNKNOWN}
