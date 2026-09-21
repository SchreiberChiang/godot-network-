extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
var manager = Manager.new()
var active := false
var passed := 0
var failed := 0
var cycles := 0
var gaps: Array = []
var previous := 0

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if active:
		var now := Time.get_ticks_msec()
		if previous > 0:
			gaps.append(now - previous)
		previous = now
		manager.poll()
	return false

func _run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.async_start = true
	check(manager.initialize(config).ok, "stress host initialized")
	check(Development.register_game(manager).ok, "fixture registered")
	active = true
	var before := OS.get_static_memory_usage()
	var started := Time.get_ticks_msec()
	for cycle in range(100):
		var created: Dictionary = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
		if not check(created.ok, "cycle creation"):
			break
		var id: String = created.room_id
		if not check(await until(func(): return manager.snapshot(id).get("heartbeats", 0) >= 2, 20000), "cycle actual READY and heartbeats"):
			break
		manager.stop_room(id)
		if not check(await until(func(): return manager.snapshot(id).cleaned, 15000), "cycle confirmed child exit"):
			break
		check(manager.ports.leases.is_empty() and manager.launcher._records.is_empty(), "cycle releases ports and owned process handles")
		cycles += 1
		if cycles % 10 == 0:
			print("STRESS_PROGRESS cycles=", cycles)
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 20000), "all stress rooms reclaimed")
	check(manager.close(), "stress listener closed")
	active = false
	gaps.sort()
	var report := {"passed": passed, "failed": failed, "cycles": cycles, "elapsed_ms": Time.get_ticks_msec() - started, "memory_before": before, "memory_after": OS.get_static_memory_usage(), "poll_gap_p95_ms": gaps[int(gaps.size() * 0.95)] if not gaps.is_empty() else 0, "poll_gap_max_ms": gaps.back() if not gaps.is_empty() else 0}
	var file := FileAccess.open("res://logs/stress-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("STRESS_RESULT passed=", passed, " failed=", failed, " cycles=", cycles)
	quit(0 if failed == 0 and cycles == 100 else 1)

func until(predicate: Callable, timeout: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return bool(predicate.call())

func check(ok: bool, label: String) -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL stress: ", label)
	return ok
