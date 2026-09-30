extends SceneTree
## L2-B2 first item on Linux: room lifecycle through RoomManager with real room
## children (examples/minimal/room.gd), owned by the process owner. Complements
## tests/run_integration.gd (normal lifecycle, timeouts, crash, forced stop,
## forged registration), which also runs on Linux now.
## Covered here: private runtime files, start on a worker thread with the
## single-use hand-over, a failed hand-over, a child that exits at once, a record
## that no longer matches (quarantine), and a stop that cannot be confirmed.
## Lines marked INJECTED replace a launcher answer (hand-over, reclaim or stop
## refused); the room processes themselves are real. Counted separately.
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Registry = preload("res://host/core/game_registry.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const Owner = preload("res://host/platform/posix_process_owner.gd")
var passed := 0
var failed := 0
var injected_passed := 0
var injected_failed := 0
var settings: Dictionary
var options := {"mode": "sandbox", "map": "empty", "capacity": 8}
var backend

## The real launcher, except that a test can refuse its answers.
class InjectedLauncher extends Launcher:
	var refuse_import := false
	var refuse_reclaim := false
	var refuse_terminate := false
	var terminate_calls := 0
	func import_owned(record_value: Dictionary) -> bool:
		if refuse_import:
			return false
		return super(record_value)
	func reclaim(launch_id: String) -> bool:
		if refuse_reclaim:
			return false
		return super(launch_id)
	func terminate(launch_id: String) -> bool:
		terminate_calls += 1
		if refuse_terminate:
			return false
		return super(launch_id)

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

func _mode(path: String) -> int:
	return int(FileAccess.get_unix_permissions(path)) & 4095

func _alive(pid: int) -> bool:
	var seen: Dictionary = backend.identity(pid)
	return not seen.is_empty() and int(seen.ppid) == OS.get_process_id() and seen.state != "Z"

func _children() -> int:
	var count := 0
	for name in DirAccess.get_directories_at("/proc"):
		if name.is_valid_int():
			var seen: Dictionary = backend.identity(int(name))
			if not seen.is_empty() and int(seen.ppid) == OS.get_process_id():
				count += 1
	return count

func _make(async_start: bool, first_port: int) -> RefCounted:
	var manager = Manager.new()
	var config := settings.duplicate(true)
	config.async_start = async_start
	config.udp_first = first_port
	config.udp_last = first_port + 15
	var initialized: Dictionary = manager.initialize(config, InjectedLauncher.new())
	check(initialized.ok, "a %s room manager initialises on Linux (%s)" % ["worker-thread" if async_start else "direct", initialized.get("code", "")])
	return manager

func _fixture(manager, fixture: String) -> void:
	manager.registry = Registry.new()
	Development.register_game(manager, fixture)

func _wait(manager, predicate: Callable, timeout_ms := 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		manager.poll()
		if predicate.call():
			return true
		await create_timer(0.03).timeout
	manager.poll()
	return bool(predicate.call())

func _run() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix room lifecycle (this is ", OS.get_name(), ")")
		print("POSIX_ROOMS_RESULT passed=0 failed=0 injected_passed=0 injected_failed=0 not_run=1")
		quit(0)
		return
	backend = Owner.PosixBackend.new()
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	settings.godot_executable = OS.get_executable_path()
	settings.heartbeat_ms = 100
	settings.heartbeat_timeout_ms = 8000
	settings.start_timeout_ms = 8000
	settings.stop_timeout_ms = 600
	var children_before := _children()
	print("INFO engine=", Engine.get_version_info().string, " children_at_start=", children_before)

	# ---- refusals that must not be skipped silently ----
	var refused = Manager.new()
	var journal := settings.duplicate(true)
	journal.process_journal = "res://run/test-journal.json"
	journal.control_port = 28199
	check(refused.initialize(journal).code == "RECOVERY_UNSUPPORTED", "the process journal (Windows helpers) is refused on Linux instead of being skipped")
	var limited := settings.duplicate(true)
	limited.max_room_memory_mb = 256
	check(Manager.new().initialize(limited).code == "RESOURCE_LIMIT_UNSUPPORTED", "a per-room memory limit is refused on Linux instead of being silently not enforced")

	var direct = _make(false, 28100)
	var runtime: String = direct.runtime_root
	check(_mode(runtime) == 448 and _mode(runtime.path_join(".gdignore")) == 384, "the runtime folder is 700 and its marker 600")

	# ---- private launch file ----
	_fixture(direct, "delayed_register")
	var made: Dictionary = direct.create_room("minimal_room", options)
	var row: Dictionary = direct.rooms.get(made.get("room_id", ""), {})
	var config_path: String = row.get("config_path", "")
	check(made.ok and FileAccess.file_exists(config_path) and _mode(config_path) == 384, "the private launch file (it holds the room token) is 600 while the room starts")
	check(await _wait(direct, func(): return direct.snapshot(made.room_id).get("heartbeats", 0) >= 2), "the room registers, binds its UDP port and becomes READY")
	check(not FileAccess.file_exists(config_path) and not direct.ports.can_bind(int(row.port)), "after registration the launch file is gone and the room's UDP port is really bound")
	direct.stop_room(made.room_id)
	check(await _wait(direct, func(): return direct.snapshot(made.room_id).get("cleaned", false)) and direct.snapshot(made.room_id).state == "STOPPED" and direct.ports.leases.is_empty(), "stop: STOPPED, exit confirmed, port released")

	# ---- a child that exits at once ----
	direct.registry = Registry.new()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/game_manifest.json"))
	direct.registry.register_game(manifest, {manifest.server_artifact: {"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/fixtures/posix_child.gd", "--", "--mode=exit", "--code=3"]}})
	var quick: Dictionary = direct.create_room("minimal_room", options)
	check(quick.ok and await _wait(direct, func(): return direct.snapshot(quick.room_id).get("cleaned", false)), "a room program that exits at once is noticed and cleaned up")
	var ended: Dictionary = direct.snapshot(quick.room_id)
	check(ended.state == "FAILED" and ended.code == "PROCESS_EXITED" and not ended.history.has("READY") and ended.exit_confirmed and direct.ports.leases.is_empty(), "it ends FAILED/PROCESS_EXITED, never READY, exit confirmed, port released")

	# ---- a record that no longer matches the process: quarantine ----
	_fixture(direct, "ignore_stop")
	var odd: Dictionary = direct.create_room("minimal_room", options)
	check(await _wait(direct, func(): return direct.snapshot(odd.room_id).get("heartbeats", 0) >= 2), "a room that will ignore stop requests is READY")
	var odd_row: Dictionary = direct.rooms[odd.room_id]
	var records: Dictionary = direct.launcher._posix._records()
	var true_start: String = records[odd_row.launch_id].start_time
	records[odd_row.launch_id].start_time = "1"  # the test makes its own record stale
	var kills: int = direct.launcher._posix.kills_sent()
	direct.stop_room(odd.room_id)
	await _wait(direct, func(): return int(direct.rooms[odd.room_id].get("kill_attempts", 0)) >= 2, 5000)
	check(not direct.snapshot(odd.room_id).cleaned and direct.snapshot(odd.room_id).get("cleanup_code", "") == "PROCESS_IDENTITY_UNVERIFIED" and direct.ports.leases.has(odd_row.launch_id) and _alive(int(odd_row.pid)) and direct.launcher._posix.kills_sent() == kills, "(record changed by the test) a room whose record no longer matches is not signalled; it keeps its port and its record, and the process is untouched")
	records[odd_row.launch_id].start_time = true_start
	records[odd_row.launch_id].state = Owner.RUNNING
	check(await _wait(direct, func(): return direct.snapshot(odd.room_id).get("cleaned", false)) and not _alive(int(odd_row.pid)) and direct.ports.leases.is_empty(), "(clean-up) once the record matches again the retried stop ends it and the port is released")

	# ---- a stop that cannot be confirmed ----
	_fixture(direct, "ignore_stop")
	var stuck: Dictionary = direct.create_room("minimal_room", options)
	check(await _wait(direct, func(): return direct.snapshot(stuck.room_id).get("heartbeats", 0) >= 2), "another uncooperative room is READY")
	var stuck_row: Dictionary = direct.rooms[stuck.room_id]
	direct.launcher.refuse_terminate = true
	direct.stop_room(stuck.room_id)
	await _wait(direct, func(): return int(direct.rooms[stuck.room_id].get("kill_attempts", 0)) >= 3, 6000)
	check_injected(not direct.snapshot(stuck.room_id).cleaned and direct.ports.leases.has(stuck_row.launch_id) and _alive(int(stuck_row.pid)) and int(direct.rooms[stuck.room_id].kill_attempts) >= 3 and direct.snapshot(stuck.room_id).get("cleanup_code", "") == "PROCESS_IDENTITY_UNVERIFIED", "while the stop cannot be confirmed the room keeps its port and record, and the stop is retried (%d attempts)" % int(direct.rooms[stuck.room_id].kill_attempts))
	direct.launcher.refuse_terminate = false
	check_injected(await _wait(direct, func(): return direct.snapshot(stuck.room_id).get("cleaned", false)) and not _alive(int(stuck_row.pid)) and direct.ports.leases.is_empty(), "once the stop can be confirmed the room is ended and everything is released")

	# ---- start on a worker thread: single-use hand-over ----
	var threaded = _make(true, 28140)
	_fixture(threaded, "")
	var handed: Dictionary = threaded.create_room("minimal_room", options)
	check(handed.ok and await _wait(threaded, func(): return threaded.snapshot(handed.room_id).get("heartbeats", 0) >= 2), "a room started on a worker thread becomes READY")
	var handed_row: Dictionary = threaded.rooms[handed.room_id]
	check(threaded.launcher.probe(handed_row.launch_id) == "running" and not threaded.launcher.record(handed_row.launch_id).is_empty() and threaded.launcher._posix.unheld_ids().is_empty(), "the main launcher holds the child after the hand-over; nothing is left unheld")
	threaded.stop_room(handed.room_id)
	check(await _wait(threaded, func(): return threaded.snapshot(handed.room_id).get("cleaned", false)) and threaded.snapshot(handed.room_id).state == "STOPPED" and threaded.ports.leases.is_empty(), "stopped and released like a directly started room")

	# ---- a failed hand-over ----
	threaded.launcher.refuse_import = true
	var lost: Dictionary = threaded.create_room("minimal_room", options)
	var lost_ok := await _wait(threaded, func(): return threaded.snapshot(lost.room_id).get("cleaned", false))
	var lost_row: Dictionary = threaded.snapshot(lost.room_id)
	check_injected(lost_ok and lost_row.code == "PROCESS_HANDOFF_FAILED" and not lost_row.history.has("READY") and lost_row.exit_confirmed and not _alive(int(lost_row.pid)) and threaded.ports.leases.is_empty(), "when the hand-over fails the host claims the worker's child, stops it and releases the port (%s)" % lost_row.get("code", ""))
	threaded.launcher.refuse_reclaim = true
	var orphan: Dictionary = threaded.create_room("minimal_room", options)
	await _wait(threaded, func(): return threaded.snapshot(orphan.room_id).get("code", "") == "PROCESS_HANDOFF_FAILED", 8000)
	await _wait(threaded, func(): return false, 1500)
	var orphan_row: Dictionary = threaded.rooms[orphan.room_id]
	check_injected(not orphan_row.cleaned and orphan_row.get("cleanup_code", "") in ["PROCESS_OWNERSHIP_LOST", "PROCESS_IDENTITY_UNVERIFIED"] and threaded.ports.leases.has(orphan_row.launch_id) and threaded.launcher._posix.unheld_ids().has(orphan_row.launch_id), "when the child cannot be claimed either, the room keeps its port and the child stays listed as unheld (not lost, not released)")
	threaded.launcher.refuse_import = false
	threaded.launcher.refuse_reclaim = false
	check_injected(threaded.launcher.reclaim(orphan_row.launch_id) and await _wait(threaded, func(): return threaded.snapshot(orphan.room_id).get("cleaned", false)) and threaded.ports.leases.is_empty(), "(clean-up) once claimed, the retried stop ends it and the port is released")

	# ---- nothing left ----
	for manager in [direct, threaded]:
		manager.stop_all()
		await _wait(manager, func(): return manager.active_count() == 0, 10000)
		check(manager.close(), "the room manager closes after all rooms are cleaned")
	await create_timer(0.3).timeout
	check(_children() == children_before, "no room child or zombie of this process remains (%d -> %d)" % [children_before, _children()])
	var leftovers: Array = Array(DirAccess.get_files_at(runtime)).filter(func(name): return name.ends_with(".json"))
	check(leftovers.is_empty(), "no private launch file remains in the runtime folder (%d)" % leftovers.size())
	print("POSIX_ROOMS_RESULT passed=", passed, " failed=", failed, " injected_passed=", injected_passed, " injected_failed=", injected_failed, " not_run=0")
	quit(0 if failed == 0 and injected_failed == 0 else 1)
