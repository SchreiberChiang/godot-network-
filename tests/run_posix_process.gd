extends SceneTree
## Real child processes on Linux through host/platform/posix_process_owner.gd and
## real files through host/platform/posix_private_path.gd. No Operator, host or
## game room is started. Fake-backend logic checks live in
## tests/run_posix_owner_logic.gd and are counted separately.
## Usage: --headless --script res://tests/run_posix_process.gd --
##   --work=<empty private dir on a Linux filesystem> --fixture=<posix_child.sh>
##   [--sentinel-pid=<pid of an unrelated process that must survive>]
const Owner = preload("res://host/platform/posix_process_owner.gd")
const PrivatePath = preload("res://host/platform/posix_private_path.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const BASH := "/bin/bash"
const MKFIFO := "/usr/bin/mkfifo"
var args: Dictionary = {}
var passed := 0
var failed := 0
var not_run := 0
var owner
var work := ""
var fixture := ""
var expected_kills := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0].trim_prefix("--")] = pair[1]
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _skip(label: String) -> void:
	not_run += 1
	print("NOT RUN ", label)

func _id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _children() -> Array:
	# Live or zombie processes whose parent is this process.
	var found: Array = []
	for name in DirAccess.get_directories_at("/proc"):
		if name.is_valid_int():
			var seen: Dictionary = owner.backend.identity(int(name))
			if not seen.is_empty() and int(seen.ppid) == OS.get_process_id():
				found.append(int(name))
	return found

func _open_descriptors() -> int:
	var directory := DirAccess.open("/proc/self/fd")
	if directory == null:
		return -1
	directory.include_hidden = true
	directory.list_dir_begin()
	var count := 0
	while directory.get_next() != "":
		count += 1
	return count

func _until(condition: Callable, milliseconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await create_timer(0.02).timeout
	return condition.call()

func _shell(launch_id: String, extra: Array, piped := false) -> Dictionary:
	var marker := "--launch-id=" + launch_id
	return owner.launch(launch_id, BASH, PackedStringArray([fixture, marker] + extra), marker, piped)

func _hang(launch_id: String, piped := false) -> Dictionary:
	var fifo := work.path_join("fifo-" + launch_id)
	_tool(owner, MKFIFO, [fifo])
	return _shell(launch_id, ["--mode=hang", "--fifo=" + fifo], piped)

## Runs a small program to its end through an owner: fork/exec with an argument
## vector, no shell, and the child is reaped by the owner. (OS.execute would go
## through a shell in this engine, so the test does not use it either.)
func _tool(holder, executable: String, arguments: Array) -> bool:
	holder.trust(executable)
	var launch_id := _id()
	if not holder.launch(launch_id, executable, PackedStringArray(arguments)).ok:
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while holder.probe(launch_id) == "running" and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	var finished: bool = holder.probe(launch_id) == "exited" and holder.exit_code(launch_id) == 0
	holder.forget(launch_id)
	return finished

func _canaries(folders: Array) -> Array:
	var found: Array = []
	for folder in folders:
		for name in DirAccess.get_files_at(folder):
			if name.begins_with("canary-"):
				found.append(folder.path_join(name))
	return found

func _run() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix process tests (this is ", OS.get_name(), ")")
		print("POSIX_PROCESS_RESULT passed=0 failed=0 not_run=1")
		quit(0)
		return
	work = str(args.get("work", ""))
	fixture = str(args.get("fixture", ""))
	if work == "" or not DirAccess.dir_exists_absolute(work) or not FileAccess.file_exists(fixture):
		print("FAIL --work must be an existing directory and --fixture the child script")
		quit(2)
		return
	owner = Owner.new()
	owner.trust(BASH)
	var sentinel := int(args.get("sentinel-pid", "0"))
	var sentinel_before: Dictionary = owner.backend.identity(sentinel) if sentinel > 0 else {}
	var descriptors_before := _open_descriptors()
	print("INFO engine=", Engine.get_version_info().string, " pid=", OS.get_process_id(), " ", owner.invariant_detail, " children_at_start=", _children().size(), " open_descriptors=", descriptors_before)

	# ---- invariant and refusals (no process may be created) ----
	_check(owner.invariant_ok, "this is the supported engine build and SIGCHLD is neither ignored nor caught (children are reaped only on request)")
	var before := _children().size()
	_check(owner.launch(_id(), "/usr/bin/env", PackedStringArray(["true"])).code == "INVALID_OPTIONS", "an executable that is not in the trusted list is refused")
	_check(owner.launch(_id(), "bash", PackedStringArray([fixture])).code == "INVALID_OPTIONS", "a relative executable path is refused")
	var plain := _id()
	_check(owner.launch(plain, BASH, PackedStringArray([fixture]), "--launch-id=" + plain).code == "INVALID_OPTIONS", "a launch without its marker argument is refused")
	_check(owner.launch("not-a-launch-id", BASH, PackedStringArray([fixture])).code == "INVALID_OPTIONS", "a malformed launch id is refused")
	owner.trust("/nonexistent/roomkit-program")
	_check(owner.launch(_id(), "/nonexistent/roomkit-program", PackedStringArray([])).code == "PROGRAM_NOT_FOUND", "a missing program is reported without starting anything")
	_check(_children().size() == before, "refused launches created no process")

	# ---- normal exit, immediate exit, non-zero exit ----
	var normal := _id()
	var started: Dictionary = _shell(normal, ["--mode=exit", "--code=0"])
	_check(started.ok and int(started.pid) > 0, "a child starts and its identity is verified from /proc")
	_check(await _until(func(): return owner.probe(normal) == "exited", 5000) and owner.exit_code(normal) == 0, "normal exit is observed with exit code 0")
	_check(_shell(normal, ["--mode=exit"]).code == "INVALID_OPTIONS", "a launch id cannot be reused while its record exists")
	_check(owner.forget(normal) and not owner.forget(normal), "an exited record is forgotten once")
	var quick := _id()
	_shell(quick, ["--mode=exit", "--code=0"])
	OS.delay_msec(300)  # the child is already gone before the first probe
	_check(owner.probe(quick) == "exited" and owner.exit_code(quick) == 0, "a child that exits right after starting is reported exited, exit code 0")
	var seven := _id()
	_shell(seven, ["--mode=exit", "--code=7"])
	_check(await _until(func(): return owner.probe(seven) == "exited", 5000) and owner.exit_code(seven) == 7, "a non-zero exit code is reported exactly (7)")
	owner.forget(quick)
	owner.forget(seven)

	# ---- start failure after fork: a trusted file that cannot be executed ----
	var broken := work.path_join("not-executable.txt")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("not a program")
	file.close()
	owner.trust(broken)
	var failing := _id()
	var attempt: Dictionary = owner.launch(failing, broken, PackedStringArray(["--launch-id=" + failing]), "--launch-id=" + failing)
	var ended: bool = await _until(func(): return owner.probe(failing) == "exited", 5000)
	_check(ended and owner.exit_code(failing) != 0, "a program that cannot be executed ends as exited with a failure code (launch ok=%s, code %d)" % [attempt.ok, owner.exit_code(failing)])
	owner.forget(failing)

	# ---- an exited child stays reserved until this owner asks ----
	var lingering := _id()
	var lingering_pid := int(_shell(lingering, ["--mode=exit", "--code=3"]).pid)
	await create_timer(1.5).timeout  # frames keep running; nothing may reap it
	var zombie: Dictionary = owner.backend.identity(lingering_pid)
	_check(not zombie.is_empty() and zombie.state == "Z" and int(zombie.ppid) == OS.get_process_id(), "an exited child is still a zombie of this process 1.5 s later (not reaped behind our back)")
	_check(owner.probe(lingering) == "exited" and owner.exit_code(lingering) == 3 and owner.backend.identity(lingering_pid).is_empty(), "the owner's probe reaps it and keeps its exit code (3)")
	var kills: int = owner.kills_sent()
	_check(owner.terminate(lingering) and owner.kills_sent() == kills, "terminating an already exited child succeeds without sending any signal")
	owner.forget(lingering)

	# ---- stuck child, forced stop, repeated cleanup ----
	var stuck := _id()
	var stuck_pid := int(_hang(stuck).pid)
	await create_timer(0.3).timeout
	_check(owner.probe(stuck) == "running" and owner.backend.identity(stuck_pid).arguments.has("--launch-id=" + stuck), "a stuck child is running and carries its launch marker")
	kills = owner.kills_sent()
	_check(owner.terminate(stuck) and owner.kills_sent() == kills + 1, "forced stop of the stuck child sends exactly one signal and is confirmed")
	expected_kills += 1
	_check(owner.probe(stuck) == "exited" and owner.exit_code(stuck) == Owner.KILLED_EXIT_CODE and owner.backend.identity(stuck_pid).is_empty(), "after the forced stop the child is reaped (no /proc entry) and marked as killed")
	_check(owner.terminate(stuck) and owner.terminate(stuck) and owner.kills_sent() == kills + 1, "repeating the cleanup sends no further signal")
	_check(owner.forget(stuck), "the stopped child's record is released")

	# ---- expired or forged identity: refuse, never signal ----
	kills = owner.kills_sent()
	if sentinel > 0 and not sentinel_before.is_empty():
		var forged := {"launch_id": _id(), "pid": sentinel, "parent_pid": OS.get_process_id(), "executable": BASH, "marker": "", "state": "running", "start_time": str(sentinel_before.start_time), "handoff": "0".repeat(64)}
		var forger = Launcher.new()
		_check(not owner.has_method("import_owned") and not forger.import_owned(forged) and forger.probe(forged.launch_id) == "unknown" and not forger.terminate(forged.launch_id) and owner.accept(forged.handoff) == "" and owner.kills_sent() == kills, "a forged record pointing at an unrelated process is not accepted and cannot be terminated")
	else:
		_skip("forged record pointing at the sentinel (no --sentinel-pid)")
	var expired := _id()
	var expired_pid := int(_hang(expired).pid)
	await create_timer(0.2).timeout
	var true_start: String = owner._records()[expired].start_time
	owner._records()[expired].start_time = "1"  # simulate a record that no longer matches the live process
	_check(not owner.terminate(expired) and owner.probe(expired) == "unknown" and owner.kills_sent() == kills and not owner.backend.identity(expired_pid).is_empty(), "a record whose start time no longer matches is quarantined: termination refused, no signal, process untouched")
	_check(not owner.forget(expired), "a quarantined record is kept, not silently dropped")
	owner._records()[expired].start_time = true_start  # test clean-up of our own child
	owner._records()[expired].state = Owner.RUNNING
	_check(owner.terminate(expired), "(clean-up) the test's own child is stopped once its record is restored")
	expected_kills += 1
	owner.forget(expired)

	# ---- hand-over between owner objects of this process (worker thread) ----
	var moved := _id()
	var thread := Thread.new()
	thread.start(func():
		var temporary = Owner.new()
		temporary.trust(BASH)
		var fifo := work.path_join("fifo-" + moved)
		_tool(temporary, MKFIFO, [fifo])
		temporary.launch(moved, BASH, PackedStringArray([fixture, "--launch-id=" + moved, "--mode=hang", "--fifo=" + fifo]), "--launch-id=" + moved)
		return [temporary.offer(moved), temporary.record(moved)])
	while thread.is_alive():
		await process_frame
	var handed: Array = thread.wait_to_finish()
	_check(owner.probe(moved) == "unknown" and owner.unheld_ids().has(moved), "a child whose worker-thread holder is gone is listed as unheld, and is not yet ours")
	var rival = Owner.new()
	_check(rival.accept(str(handed[1].get("launch_id", "")).rpad(64, "0")) == "" and owner.accept(handed[0]) == moved and rival.accept(handed[0]) == "" and owner.probe(moved) == "running" and rival.probe(moved) == "unknown", "a child started on a worker thread is taken over with its single-use token; a second receiver and an observation record get nothing")
	_check(not rival.terminate(moved) and owner.terminate(moved), "only the receiving owner can stop the handed-over child")
	expected_kills += 1
	owner.forget(moved)

	# ---- piped child handed over: the pipes move with it ----
	var piped_moved := _id()
	var source = Owner.new()
	source.trust(BASH)
	var from_source: Dictionary = source.launch(piped_moved, BASH, PackedStringArray([fixture, "--launch-id=" + piped_moved, "--mode=echo"]), "--launch-id=" + piped_moved, true)
	var piped_token: String = source.offer(piped_moved)
	var taken: bool = owner.accept(piped_token) == piped_moved
	var moved_pipes: Dictionary = owner.pipes(piped_moved)
	var moved_reply := ""
	if taken and moved_pipes.get("stdio") != null:
		moved_pipes.stdio.store_line("moved pipe")
		moved_pipes.stdio.flush()
		moved_reply = moved_pipes.stdio.get_line()
	_check(from_source.ok and taken and moved_reply == "moved pipe" and source.pipes(piped_moved).is_empty() and source.probe(piped_moved) == "unknown", "a piped child is handed over explicitly: its pipes move to the receiver and still work; the source keeps nothing")
	_check(owner.terminate(piped_moved) and owner.forget(piped_moved) and owner.pipes(piped_moved).is_empty(), "the receiver stops the piped child and its pipes are closed with the record")
	expected_kills += 1
	from_source = {}
	moved_pipes = {}

	# ---- piped children (one-shot helpers, resident workers) ----
	var echo := _id()
	var piped: Dictionary = _shell(echo, ["--mode=echo"], true)
	var reply := ""
	if piped.ok:
		piped.stdio.store_line("owned pipe")
		piped.stdio.flush()
		reply = piped.stdio.get_line()
		piped.stdio.close()
		owner._records()[echo].stdio = null
	_check(piped.ok and reply == "owned pipe", "a piped child answers on its pipe")
	_check(await _until(func(): return owner.probe(echo) == "exited", 5000) and owner.exit_code(echo) == 0, "closing its input ends the piped child normally, exit code 0")
	owner.forget(echo)
	var silent := _id()
	_hang(silent, true)
	await create_timer(0.2).timeout
	_check(owner.probe(silent) == "running" and owner.terminate(silent) and owner.probe(silent) == "exited", "a piped child that never answers is stopped on timeout")
	expected_kills += 1
	owner.forget(silent)

	# ---- engine child (actual Godot arguments), editor binary only ----
	if OS.has_feature("editor"):
		var engine := OS.get_executable_path()
		owner.trust(engine)
		var project := ProjectSettings.globalize_path("res://")
		var engine_exit := _id()
		var engine_args := PackedStringArray(["--headless", "--path", project, "--script", "res://tests/fixtures/posix_child.gd", "--", "--launch-id=" + engine_exit, "--mode=exit", "--code=5"])
		var engine_started: Dictionary = owner.launch(engine_exit, engine, engine_args, "--launch-id=" + engine_exit)
		print("INFO engine child: executable=", engine.get_file(), " arguments=", " ".join(engine_args).replace(project, "<project>").replace(engine_exit, "<launch-id>"), " parent_pid=", OS.get_process_id(), " child_pid=", engine_started.pid)
		_check(engine_started.ok and await _until(func(): return owner.probe(engine_exit) == "exited", 30000) and owner.exit_code(engine_exit) == 5, "an engine child started with real Godot arguments exits with its code (5)")
		owner.forget(engine_exit)
		var engine_hang := _id()
		var hang_args := PackedStringArray(["--headless", "--path", project, "--script", "res://tests/fixtures/posix_child.gd", "--", "--launch-id=" + engine_hang, "--mode=hang"])
		var hang_pid := int(owner.launch(engine_hang, engine, hang_args, "--launch-id=" + engine_hang).pid)
		await create_timer(1.5).timeout
		var relation: Dictionary = owner.backend.identity(hang_pid)
		print("INFO engine child relation: state=", relation.get("state", "?"), " ppid_is_parent=", int(relation.get("ppid", -1)) == OS.get_process_id(), " has_marker=", relation.get("arguments", []).has("--launch-id=" + engine_hang))
		_check(owner.probe(engine_hang) == "running" and owner.terminate(engine_hang) and owner.backend.identity(hang_pid).is_empty(), "a running engine child is stopped and reaped")
		expected_kills += 1
		owner.forget(engine_hang)
	else:
		_skip("engine child with real Godot arguments (needs the editor binary; this binary ignores --script)")

	# ---- the launcher's Linux branch (same interface the room manager uses) ----
	var launcher = Launcher.new()
	var via := _id()
	var via_fifo := work.path_join("fifo-" + via)
	_tool(owner, MKFIFO, [via_fifo])
	var descriptor := {"executable": BASH, "args": [fixture]}
	var launched: Dictionary = launcher.launch(descriptor, via, PackedStringArray(["--launch-id=" + via, "--mode=hang", "--fifo=" + via_fifo]))
	_check(launched.ok and launcher.probe(via) == "running" and int(launcher.record(via).pid) == int(launched.pid), "the launcher starts a child on Linux and reports it running")
	_check(launcher.launch(descriptor, _id(), PackedStringArray(["--mode=exit"])).code == "INVALID_OPTIONS", "the launcher still requires the launch marker")
	_check(launcher.terminate(via) and launcher.probe(via) == "exited" and launcher.forget(via) and launcher.probe(via) == "unknown", "the launcher stops, confirms and forgets the child")
	expected_kills += 1
	var isolated = Launcher.new()
	var transferred := _id()
	var transfer_fifo := work.path_join("fifo-" + transferred)
	_tool(owner, MKFIFO, [transfer_fifo])
	isolated.launch(descriptor, transferred, PackedStringArray(["--launch-id=" + transferred, "--mode=hang", "--fifo=" + transfer_fifo]))
	var observed: Dictionary = isolated.record(transferred)
	_check(not launcher.import_owned(observed) and not launcher.import_owned(observed.duplicate(true)) and launcher.probe(transferred) == "unknown" and isolated.probe(transferred) == "running", "the launcher refuses an observation record (or a copy of one): the child stays with the launcher that started it")
	var renamed: Dictionary = isolated.handoff(transferred)
	var other_id := _id()
	renamed.launch_id = other_id
	_check(not launcher.import_owned(renamed) and launcher.probe(other_id) == "unknown" and launcher.probe(transferred) == "unknown" and isolated.probe(transferred) == "running", "a hand-over whose launch id was changed is refused and creates no record under either id")
	renamed.launch_id = transferred
	_check(not launcher.import_owned(renamed), "that token was spent by the refused attempt")
	var ticket: Dictionary = isolated.handoff(transferred)
	var second_launcher = Launcher.new()
	_check(launcher.import_owned(ticket) and not second_launcher.import_owned(ticket.duplicate(true)) and not launcher.import_owned(ticket) and launcher.probe(transferred) == "running" and second_launcher.probe(transferred) == "unknown", "a hand-over from an isolated launcher is accepted once; a copy given to a second launcher and a replay are refused")
	kills = owner.kills_sent()
	_check(isolated.probe(transferred) == "unknown" and not isolated.terminate(transferred) and not isolated.forget(transferred) and isolated.handoff(transferred).is_empty() and owner.kills_sent() == kills, "after the hand-over the source launcher can no longer observe, stop, release or offer the child")
	_check(launcher.terminate(transferred) and launcher.forget(transferred), "the receiving launcher stops the child")
	expected_kills += 1

	# ---- parent stops normally: every remaining child is stopped first ----
	var remaining_pids: Array = []
	for index in 3:
		remaining_pids.append(int(_hang(_id()).pid))
	await create_timer(0.3).timeout
	kills = owner.kills_sent()
	var unconfirmed: Array = owner.shutdown_all()
	expected_kills += 3
	_check(unconfirmed.is_empty() and owner.kills_sent() == kills + 3 and remaining_pids.all(func(pid): return owner.backend.identity(pid).is_empty()), "a normal parent stop ends all three remaining children and confirms each")
	for launch_id in owner.launch_ids():
		owner.forget(launch_id)

	# ---- owner-only files and folders ----
	var private := work.path_join("private")
	var made: Dictionary = PrivatePath.protect_directory(private, work)
	_check(made.ok and made.mode == "700", "a private folder is created as 700 and verified (%s)" % made.get("code", ""))
	var secret := private.path_join("secret.json")
	file = FileAccess.open(secret, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	var guarded: Dictionary = PrivatePath.protect_file(secret, work)
	_check(guarded.ok and guarded.mode == "600", "a sensitive file is set to 600 and verified")
	var loose := work.path_join("loose-source.db")
	file = FileAccess.open(loose, FileAccess.WRITE)
	file.store_string("source")
	file.close()
	FileAccess.set_unix_permissions(loose, 420)  # octal 644, as an imported file may be
	var copied: Dictionary = PrivatePath.copy_private(loose, private.path_join("copy.db"), work)
	_check(copied.ok and copied.mode == "600", "a copy of a 644 file is 600 and verified before it is reported usable")
	_check(not PrivatePath.copy_private(loose, private.path_join("copy.db"), work).ok, "copying over an existing private file is refused")
	_check(PrivatePath.verify(loose, 384, false).code == "PRIVATE_PATH_UNVERIFIED", "a file with a wider mode fails verification")
	_check(PrivatePath.protect_file(loose, private).code == "PRIVATE_PATH_OUTSIDE_BOUNDARY" and PrivatePath.protect_directory(work.path_join("../escape"), work).code == "PRIVATE_PATH_OUTSIDE_BOUNDARY", "paths outside the private boundary are refused")
	var link := private.path_join("link.json")
	var linked: bool = DirAccess.open(private).create_link(secret, link) == OK
	_check(linked and PrivatePath.protect_file(link, work).code == "PRIVATE_PATH_LINK_REFUSED" and PrivatePath.verify(link, 384, false).code == "PRIVATE_PATH_LINK_REFUSED", "a symbolic link is refused")
	DirAccess.remove_absolute(link)  # the test's own link; a link's mode bits are always open

	# ---- a link ABOVE the private boundary redirects the whole tree: refused ----
	var real_root := work.path_join("real-root")
	DirAccess.make_dir_absolute(real_root)
	var alias := work.path_join("alias-root")
	var aliased: bool = DirAccess.open(work).create_link(real_root, alias) == OK
	var through: Dictionary = PrivatePath.protect_directory(alias.path_join("store/private"), alias.path_join("store"))
	_check(aliased and through.code == "PRIVATE_PATH_LINK_REFUSED" and not DirAccess.dir_exists_absolute(real_root.path_join("store")), "a private folder whose boundary is reached through a linked ancestor is refused and nothing is created behind the link")
	DirAccess.make_dir_recursive_absolute(real_root.path_join("store"))
	file = FileAccess.open(real_root.path_join("store/data.db"), FileAccess.WRITE)
	file.store_string("data")
	file.close()
	FileAccess.set_unix_permissions(real_root.path_join("store/data.db"), 420)
	_check(PrivatePath.protect_file(alias.path_join("store/data.db"), alias.path_join("store")).code == "PRIVATE_PATH_LINK_REFUSED" and PrivatePath.verify(alias.path_join("store/data.db"), 420, false).code == "PRIVATE_PATH_LINK_REFUSED" and PrivatePath.copy_private(loose, alias.path_join("store/copy.db"), alias.path_join("store")).code == "PRIVATE_PATH_LINK_REFUSED" and (int(FileAccess.get_unix_permissions(real_root.path_join("store/data.db"))) & 4095) == 420 and not FileAccess.file_exists(real_root.path_join("store/copy.db")), "protect, verify and copy through a linked ancestor are all refused; the file behind the link is left unchanged")
	_check(PrivatePath.protect_file(real_root.path_join("store/data.db"), real_root.path_join("store")).ok, "the same file reached by its real path is protected normally")
	DirAccess.remove_absolute(alias)

	# ---- names a shell would execute: nothing may run ----
	var cwd := DirAccess.open("/proc/self").read_link("cwd")
	var hostile := "x$(touch canary-dollar)`touch canary-tick`;touch canary-semi"
	var quoted := "it's \"quoted\" & $HOME | x"
	var canary_folders: Array = [work, private, cwd]
	var special_ok := true
	for name in [hostile, quoted]:
		var folder := private.path_join(name)
		var made_special: Dictionary = PrivatePath.protect_directory(folder, work)
		var inner := folder.path_join(name + ".json")
		file = FileAccess.open(inner, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
		FileAccess.set_unix_permissions(inner, 420)
		var inner_result: Dictionary = PrivatePath.protect_file(inner, work)
		var copy_result: Dictionary = PrivatePath.copy_private(loose, folder.path_join(name + ".copy"), work)
		var modes_ok: bool = (int(FileAccess.get_unix_permissions(folder)) & 4095) == 448 and (int(FileAccess.get_unix_permissions(inner)) & 4095) == 384 and (int(FileAccess.get_unix_permissions(folder.path_join(name + ".copy"))) & 4095) == 384
		special_ok = special_ok and made_special.ok and inner_result.ok and copy_result.ok and PrivatePath.verify(inner, 384, false).ok and modes_ok
		canary_folders.append(folder)
	_check(special_ok, "folders and files whose names contain quotes, backticks, $( ), ; & | are protected to 700/600 and verified")
	var ran: Array = _canaries(canary_folders)
	_check(ran.is_empty(), "protecting those paths executed nothing: no canary file in the work folder, the private folders or the working directory (%d found)" % ran.size())
	var literal := _id()
	var literal_argument := "--note=$(touch canary-arg)`touch canary-arg2`;touch canary-arg3"
	var literal_pid := int(owner.launch(literal, BASH, PackedStringArray([fixture, "--launch-id=" + literal, "--mode=exit", "--code=0", literal_argument]), "--launch-id=" + literal).pid)
	var literal_seen: Dictionary = owner.backend.identity(literal_pid)
	var finished_literal: bool = await _until(func(): return owner.probe(literal) == "exited", 5000)
	_check(finished_literal and (literal_seen.get("state", "") == "Z" or literal_seen.get("arguments", []).has(literal_argument)) and _canaries(canary_folders).is_empty(), "a child argument containing shell syntax reaches the child as one literal argument and executes nothing")
	owner.forget(literal)
	# Control: the same name DOES execute when a shell evaluates it, so the
	# absence of canaries above means something. Runs inside the test folder only.
	var control_folder := work.path_join("shell-control")
	DirAccess.make_dir_absolute(control_folder)
	_tool(owner, BASH, ["-c", "cd \"$1\" && eval \"stat -c %a $2\" >/dev/null 2>&1; exit 0", "bash", control_folder, hostile])
	var control: Array = _canaries([control_folder])
	_check(control.size() == 3 and _canaries(canary_folders).is_empty(), "control: a shell evaluating that name does create the canaries (%d of 3), so their absence above is meaningful" % control.size())
	for path in control:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(control_folder)
	var missing: Dictionary = PrivatePath.copy_private(work.path_join("absent.db"), private.path_join("never.db"), work)
	_check(not missing.ok and not FileAccess.file_exists(private.path_join("never.db")), "a failed copy leaves nothing behind")
	var unowned: Dictionary = PrivatePath.verify("/etc/hostname", 384, false)
	_check(not unowned.ok, "a file owned by someone else fails verification (read-only check)")

	# ---- nothing left behind ----
	for name in DirAccess.get_files_at(work):
		if name.begins_with("fifo-"):
			DirAccess.remove_absolute(work.path_join(name))
	_check(Array(DirAccess.get_files_at(work)).filter(func(name): return name.begins_with("fifo-")).is_empty() and not FileAccess.file_exists(link), "the test's own FIFO files and link are removed")
	await create_timer(0.2).timeout
	var left := _children()
	_check(left.is_empty(), "no child or zombie of this process remains (%d)" % left.size())
	var descriptors_after := _open_descriptors()
	_check(descriptors_after == descriptors_before, "open file descriptors are back to the starting count (%d -> %d)" % [descriptors_before, descriptors_after])
	_check(owner.kills_sent() == expected_kills, "signals sent equal the intended forced stops (%d of %d)" % [owner.kills_sent(), expected_kills])
	if sentinel > 0 and not sentinel_before.is_empty():
		var sentinel_after: Dictionary = owner.backend.identity(sentinel)
		_check(not sentinel_after.is_empty() and sentinel_after.start_time == sentinel_before.start_time and sentinel_after.state != "Z", "the unrelated sentinel process is still the same live process")
	else:
		_skip("sentinel survival (no --sentinel-pid)")
	print("POSIX_PROCESS_RESULT passed=", passed, " failed=", failed, " not_run=", not_run)
	quit(0 if failed == 0 else 1)
