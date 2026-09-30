extends SceneTree
## Rule checks for host/platform/posix_process_owner.gd against a FAKE process
## table (no real process is started; runs on any platform). Real-process
## evidence is tests/run_posix_process.gd; the two are counted separately.
const Owner = preload("res://host/platform/posix_process_owner.gd")
var passed := 0
var failed := 0

## Mimics the engine: asking whether an exited child is running reaps it, after
## which its PID may belong to anyone. Any kill of a reaped or foreign PID is a
## violation the tests look for.
class FakeBackend extends RefCounted:
	var disposition := "default"
	var supported := true
	var next_pid := 1000
	var table: Dictionary = {}
	var log: Array = []
	var violations: Array = []
	var create_fails := false
	var hide_marker := false
	var kill_fails := false
	var kill_without_effect := false
	func self_pid() -> int:
		return 77
	func engine_supported() -> bool:
		return supported
	func sigchld_disposition() -> String:
		return disposition
	func create_process(_executable: String, arguments: PackedStringArray) -> int:
		if create_fails:
			return -1
		next_pid += 1
		table[next_pid] = {"alive": true, "reaped": false, "code": 0, "ppid": 77, "start": str(next_pid * 10), "arguments": Array(arguments) if not hide_marker else []}
		log.append("create %d" % next_pid)
		return next_pid
	func create_piped(executable: String, arguments: PackedStringArray) -> Dictionary:
		return {"pid": create_process(executable, arguments), "stdio": FakePipe.new(), "stderr": FakePipe.new()}
	func is_running(pid: int) -> bool:
		log.append("is_running %d" % pid)
		var entry: Dictionary = table.get(pid, {})
		if entry.is_empty() or entry.reaped:
			return false
		if not entry.alive:
			entry.reaped = true
			log.append("reap %d" % pid)
			return false
		return true
	func exit_code(pid: int) -> int:
		return int(table.get(pid, {}).get("code", -1))
	func kill(pid: int) -> int:
		log.append("kill %d" % pid)
		var entry: Dictionary = table.get(pid, {})
		if entry.is_empty() or entry.reaped or int(entry.ppid) != 77:
			violations.append("kill of a PID that is not our unreaped child: %d" % pid)
			return FAILED
		if kill_fails:
			return ERR_INVALID_PARAMETER
		if kill_without_effect:
			return OK
		entry.alive = false
		entry.reaped = true
		return OK
	func identity(pid: int) -> Dictionary:
		var entry: Dictionary = table.get(pid, {})
		if entry.is_empty() or entry.reaped:
			return {}
		return {"state": "S" if entry.alive else "Z", "ppid": entry.ppid, "start_time": entry.start, "arguments": entry.arguments}
	func exits(pid: int, code: int) -> void:
		table[pid].alive = false
		table[pid].code = code
	func kills() -> int:
		return log.filter(func(line): return str(line).begins_with("kill ")).size()

class FakePipe extends RefCounted:
	var closed := 0
	func close() -> void:
		closed += 1

var program := ""

func _initialize() -> void:
	program = OS.get_executable_path()
	_preconditions()
	_lifecycle()
	_failed_termination()
	_single_ownership()
	_released_holder()
	_kept_pipes()
	print("POSIX_OWNER_LOGIC_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _owner(backend) -> RefCounted:
	var owner = Owner.new(backend)
	owner.trust(program)
	return owner

func _start(owner, id: String, piped := false) -> Dictionary:
	return owner.launch(id, program, PackedStringArray(["--launch-id=" + id]), "--launch-id=" + id, piped)

func _id(character: String) -> String:
	return character.repeat(32)

func _preconditions() -> void:
	# The kernel or a handler could reap behind us, or the engine build is unknown.
	for disposition in ["ignored", "caught", "unknown"]:
		var unsafe := FakeBackend.new()
		unsafe.disposition = disposition
		var refused = _owner(unsafe)
		_check(not refused.invariant_ok and _start(refused, _id("a")).code == "PROCESS_OWNERSHIP_UNAVAILABLE" and unsafe.log.is_empty(), "with SIGCHLD %s nothing is launched or signalled" % disposition)
	var other_engine := FakeBackend.new()
	other_engine.supported = false
	var unsupported = _owner(other_engine)
	_check(not unsupported.invariant_ok and _start(unsupported, _id("a")).code == "PROCESS_OWNERSHIP_UNAVAILABLE" and unsupported.accept("0".repeat(64)) == "" and other_engine.log.is_empty(), "an engine build other than the supported one is refused: nothing launched, accepted or signalled")
	var backend := FakeBackend.new()
	var owner = Owner.new(backend)
	owner.trust("/opt/roomkit/program")
	_check(owner.launch(_id("a"), "/opt/roomkit/program", PackedStringArray([])).code == "PROGRAM_NOT_FOUND" and backend.log.is_empty(), "a missing trusted program creates no process")
	owner.trust(program)
	_check(owner.launch(_id("a"), "/not/trusted", PackedStringArray([])).code == "INVALID_OPTIONS" and owner.launch("zz", program, PackedStringArray([])).code == "INVALID_OPTIONS" and owner.launch(_id("a"), program, PackedStringArray(["--launch-id=" + _id("a"), "--launch-id=" + _id("a")]), "--launch-id=" + _id("a")).code == "INVALID_OPTIONS" and backend.log.is_empty(), "untrusted programs, bad ids and duplicated markers start nothing")
	var failing := FakeBackend.new()
	failing.create_fails = true
	var none = _owner(failing)
	_check(_start(none, _id("a")).code == "PROCESS_LAUNCH_FAILED" and none.launch_ids().is_empty(), "a failed start leaves no record")
	var hidden := FakeBackend.new()
	hidden.hide_marker = true
	var strict = _owner(hidden)
	var unverified: Dictionary = _start(strict, _id("f"))
	_check(not unverified.ok and unverified.code == "PROCESS_IDENTITY_UNVERIFIED" and not strict.terminate(_id("f")) and hidden.kills() == 0 and strict.record(_id("f")).last_error == "MARKER_UNVERIFIED", "a child whose marker cannot be verified is quarantined and never signalled")

func _lifecycle() -> void:
	var backend := FakeBackend.new()
	var owner = _owner(backend)
	var first: Dictionary = _start(owner, _id("a"))
	_check(first.ok and owner.probe(_id("a")) == "running", "a verified child is running")
	backend.exits(int(first.pid), 4)
	_check(owner.probe(_id("a")) == "exited" and owner.exit_code(_id("a")) == 4, "an exit is observed once and its code kept")
	var kills := backend.kills()
	_check(owner.terminate(_id("a")) and owner.terminate(_id("a")) and backend.kills() == kills, "an exited (reaped) child is never signalled, however often cleanup repeats")
	backend.table[int(first.pid)] = {"alive": true, "reaped": false, "code": 0, "ppid": 1, "start": "999", "arguments": []}
	_check(owner.terminate(_id("a")) and backend.kills() == kills and backend.violations.is_empty(), "after the PID is reused by an unrelated process the old record still sends nothing")
	_check(owner.forget(_id("a")), "the exited record is released")
	var second: Dictionary = _start(owner, _id("b"))
	backend.log.clear()
	_check(owner.terminate(_id("b")) and backend.log == ["is_running %d" % second.pid, "kill %d" % second.pid], "a forced stop is exactly: confirm running, then signal, with nothing in between")
	_check(owner.exit_code(_id("b")) == Owner.KILLED_EXIT_CODE and owner.probe(_id("b")) == "exited" and owner.kills_sent() == 1, "the stopped child is marked killed")
	backend.log.clear()
	owner.probe(_id("b"))
	owner.terminate(_id("b"))
	_check(backend.log.is_empty(), "no engine call is made for a PID after it was reaped")
	owner.forget(_id("b"))
	var fourth: Dictionary = _start(owner, _id("d"))
	backend.table[int(fourth.pid)].start = "changed"
	kills = backend.kills()
	_check(not owner.terminate(_id("d")) and owner.probe(_id("d")) == "unknown" and backend.kills() == kills and not owner.forget(_id("d")) and owner.record(_id("d")).last_error == "IDENTITY_MISMATCH", "a start-time mismatch quarantines the record: refused, not signalled, not dropped")
	var fifth: Dictionary = _start(owner, _id("e"))
	backend.table[int(fifth.pid)].ppid = 1
	_check(not owner.terminate(_id("e")) and backend.kills() == kills, "a process that is no longer our child is not signalled")
	_start(owner, _id("3"))
	_start(owner, _id("4"))
	var unconfirmed: Array = owner.shutdown_all()
	_check(unconfirmed.has(_id("d")) and unconfirmed.has(_id("e")) and not unconfirmed.has(_id("3")) and owner.probe(_id("4")) == "exited", "parent stop ends running children and reports the quarantined ones")
	_check(backend.violations.is_empty(), "no signal ever reached a reaped or foreign PID in the lifecycle rules")

func _failed_termination() -> void:
	var backend := FakeBackend.new()
	var owner = _owner(backend)
	var child: Dictionary = _start(owner, _id("a"), true)
	backend.kill_fails = true
	var confirmed: bool = owner.terminate(_id("a"))
	var seen: Dictionary = owner.record(_id("a"))
	_check(not confirmed and seen.state == "running" and backend.table[int(child.pid)].alive, "when the engine cannot send the signal, termination is not confirmed and the record stays running")
	_check(int(seen.terminate_failures) == 1 and seen.last_error == "KILL_FAILED" and child.stdio.closed == 0 and child.stderr.closed == 0, "the failure is recorded for diagnosis and the pipes stay open")
	_check(not owner.forget(_id("a")) and owner.probe(_id("a")) == "running" and owner.exit_code(_id("a")) == -1, "an unfinished record cannot be released and reports no exit code")
	backend.kill_fails = false
	_check(owner.terminate(_id("a")) and owner.probe(_id("a")) == "exited" and child.stdio.closed == 1 and int(owner.record(_id("a")).terminate_failures) == 1, "a retry that succeeds confirms the exit, closes the pipes once and keeps the failure count")
	var kills := backend.kills()
	_check(owner.terminate(_id("a")) and backend.kills() == kills and child.stdio.closed == 1 and owner.forget(_id("a")), "cleanup repeated after recovery sends nothing, closes nothing twice, and the record is released")
	# The signal is reported as sent but the child is still there.
	var stubborn: Dictionary = _start(owner, _id("b"))
	backend.kill_without_effect = true
	_check(not owner.terminate(_id("b")) and owner.record(_id("b")).last_error == "STILL_PRESENT_AFTER_KILL" and owner.probe(_id("b")) == "running", "a child still present after a reported signal is not confirmed")
	_check(not owner.terminate(_id("b")) and not owner.terminate(_id("b")) and owner.probe(_id("b")) == "unknown" and owner.record(_id("b")).state == "quarantined", "after three failed attempts the record is quarantined")
	kills = backend.kills()
	_check(not owner.terminate(_id("b")) and backend.kills() == kills and not owner.forget(_id("b")) and backend.table[int(stubborn.pid)].alive, "a quarantined record is not signalled again and is kept")
	_check(backend.violations.is_empty(), "failed terminations never signalled a reaped or foreign PID")

func _single_ownership() -> void:
	var backend := FakeBackend.new()
	var source = _owner(backend)
	var spawned: Dictionary = _start(source, _id("a"), true)
	var other = _owner(backend)
	_check(other.probe(_id("a")) == "unknown" and not other.terminate(_id("a")) and other.record(_id("a")).is_empty() and not other.forget(_id("a")) and backend.kills() == 0, "another object cannot observe, stop or release a record it does not hold")
	_check(_start(other, _id("a")).code == "INVALID_OPTIONS", "a launch id in use anywhere in the process cannot be started again")
	# Observation records and copies grant nothing.
	var observation: Dictionary = source.record(_id("a"))
	_check(other.accept(str(observation.get("launch_id", ""))) == "" and other.accept(str(observation.pid).lpad(64, "0")) == "" and other.accept("f".repeat(64)) == "" and other.probe(_id("a")) == "unknown", "an observation record, a guessed value or a forged token does not grant ownership")
	_check(not other.has_method("import_owned") and not other.has_method("export_owned"), "there is no way to add a record from a dictionary")
	# Single-use hand-over.
	var token: String = source.offer(_id("a"))
	_check(token.length() == 64 and source.probe(_id("a")) == "running", "after an offer the source still holds the record and stays responsible")
	var receiver_one = _owner(backend)
	var receiver_two = _owner(backend)
	var accepted_one: String = receiver_one.accept(token)
	var accepted_two: String = receiver_two.accept(String(token))
	_check(accepted_one == _id("a") and accepted_two == "" and receiver_two.probe(_id("a")) == "unknown", "a hand-over token is consumed exactly once: the second receiver gets nothing")
	backend.log.clear()
	_check(source.probe(_id("a")) == "unknown" and not source.terminate(_id("a")) and not source.forget(_id("a")) and source.offer(_id("a")) == "" and source.pipes(_id("a")).is_empty() and backend.log.is_empty(), "after the hand-over the source can no longer observe, stop, release or offer the child, and makes no engine call for it")
	var moved: Dictionary = receiver_one.pipes(_id("a"))
	_check(moved.get("stdio") == spawned.stdio and spawned.stdio.closed == 0, "the pipes of a piped child move with the hand-over and stay open")
	_check(receiver_one.accept(token) == "" and source.accept(token) == "", "a used token cannot be replayed by anyone")
	# A newer offer replaces an older one; an offer dies with the child.
	var stale: String = receiver_one.offer(_id("a"))
	var fresh: String = receiver_one.offer(_id("a"))
	_check(receiver_two.accept(stale) == "" and receiver_one.probe(_id("a")) == "running", "an older offer is void once a newer one exists")
	_check(receiver_one.accept(fresh) == "" and receiver_one.probe(_id("a")) == "running", "a holder cannot accept its own offer, and the token is spent")
	var last: String = receiver_one.offer(_id("a"))
	_check(receiver_one.terminate(_id("a")) and receiver_two.accept(last) == "" and receiver_one.probe(_id("a")) == "exited", "the offering holder can still stop the child; the token is then worthless")
	_check(receiver_one.offer(_id("a")) == "" and receiver_one.forget(_id("a")) and spawned.stdio.closed == 1, "an exited record cannot be offered; releasing it closes the pipes once")
	# Two receivers racing on threads for one token.
	var raced: Dictionary = _start(source, _id("b"))
	var racing: String = source.offer(_id("b"))
	var contenders: Array = []
	var threads: Array = []
	for index in 8:
		contenders.append(_owner(backend))
		threads.append(Thread.new())
	for index in 8:
		threads[index].start(contenders[index].accept.bind(racing))
	var winners := 0
	for thread in threads:
		if thread.wait_to_finish() == _id("b"):
			winners += 1
	var holders: int = contenders.filter(func(contender): return contender.probe(_id("b")) == "running").size()
	_check(winners == 1 and holders == 1, "eight receivers racing for one token: exactly one becomes the holder (%d winners, %d holders)" % [winners, holders])
	for contender in contenders:
		contender.terminate(_id("b"))
	_check(not backend.table[int(raced.pid)].alive and backend.kills() == 2 and backend.violations.is_empty(), "the single holder stops the child with one signal; no violation")
	# Registries of different backends (tests) do not mix; one backend is one registry.
	_start(source, _id("c"))
	var wrong_child: String = source.offer(_id("c"))
	_check(receiver_two.accept(wrong_child, _id("d")) == "" and source.probe(_id("c")) == "running" and receiver_two.accept(wrong_child, _id("c")) == "", "a token presented under a different launch id is refused and spent; the child stays with its holder")
	var elsewhere = _owner(FakeBackend.new())
	_check(_start(elsewhere, _id("c")).ok and elsewhere.accept(source.offer(_id("c"))) == "" and source.probe(_id("c")) == "running", "a token is only valid inside the registry that issued it")

func _released_holder() -> void:
	var backend := FakeBackend.new()
	var temporary = _owner(backend)
	var child: Dictionary = _start(temporary, _id("a"))
	var token: String = temporary.offer(_id("a"))
	var keeper = _owner(backend)
	var rival = _owner(backend)
	_check(keeper.unheld_ids().is_empty(), "a record with a living holder is not unheld")
	temporary = null
	_check(keeper.unheld_ids() == [_id("a")], "when a holder object goes away its running child is listed as unheld, not lost")
	_check(keeper.accept(token) == _id("a") and keeper.probe(_id("a")) == "running" and keeper.unheld_ids().is_empty(), "an offer made before the holder went away can still be accepted once")
	var second = _owner(backend)
	_start(second, _id("b"))
	second = null
	_check(keeper.claim_unheld(_id("b")) and not rival.claim_unheld(_id("b")) and rival.probe(_id("b")) == "unknown", "an unheld record is claimed by exactly one holder")
	var third = _owner(backend)
	var orphan: Dictionary = _start(third, _id("c"))
	third = null
	var unconfirmed: Array = keeper.shutdown_all()
	_check(unconfirmed.is_empty() and not backend.table[int(child.pid)].alive and not backend.table[int(orphan.pid)].alive and keeper.unheld_ids().is_empty(), "parent stop also ends unheld children")
	_check(backend.violations.is_empty(), "no signal ever reached a reaped or foreign PID after holders were released")

func _kept_pipes() -> void:
	# A caller whose other thread may still be reading asks for the pipes to stay
	# open across the stop; they are closed when the record is released.
	var backend := FakeBackend.new()
	var owner = _owner(backend)
	var child: Dictionary = _start(owner, _id("a"), true)
	_check(owner.terminate(_id("a"), true) and owner.probe(_id("a")) == "exited" and child.stdio.closed == 0 and child.stderr.closed == 0 and not owner.pipes(_id("a")).is_empty(), "a stop that keeps the pipes confirms the exit and leaves both pipes open")
	_check(owner.terminate(_id("a")) and child.stdio.closed == 0 and owner.forget(_id("a")) and child.stdio.closed == 1 and child.stderr.closed == 1, "repeating the stop closes nothing; the release closes each pipe exactly once")
	var second: Dictionary = _start(owner, _id("b"), true)
	_check(owner.terminate(_id("b"), true) and owner.forget(_id("b")) and second.stdio.closed == 1 and backend.violations.is_empty(), "releasing the record closes the kept pipes")
