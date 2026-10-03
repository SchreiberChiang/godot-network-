extends RefCounted
## Stage the coordinator as res://practice_session.gd in a minimal project.
## Uses continuous point trajectories only: no scene, car, physics or services.
const Session = preload("res://practice_session.gd")
const SPAWN := Vector3(9.0, 1.0, 20.0)
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []


func run() -> Dictionary:
	_countdown_and_accumulation()
	_order_and_finish()
	_fraction_time()
	_reverse_skips_and_repeats()
	_restart()
	_invalid_trajectory()
	_snapshot_copies()
	return {"passed": passed, "failed": failed, "checks": checks.duplicate(true)}


func _countdown_and_accumulation() -> void:
	var session = _fresh()
	_check(session.holds_vehicle() and session.snapshot().phase == "countdown", "countdown holds vehicle")
	for index in range(90):
		_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().countdown_remaining_ms == 1500, "ninety 60Hz frames accumulate exactly 1500ms")
	for index in range(89):
		_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().phase == "countdown" and session.snapshot().countdown_remaining_ms == 17, "179 frames remain locked before three seconds")
	_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().phase == "ready" and not session.holds_vehicle(), "180th frame releases exactly at three seconds")
	_check(session.snapshot().elapsed_ms == 0 and session.rules.snapshot().race_elapsed_ms == 0, "countdown contributes zero racing time")
	for index in range(60):
		_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().phase == "ready" and session.snapshot().elapsed_ms == 0, "waiting at start keeps racing time zero")
	_step(session, Vector3(11, 1, 20), 0.04)
	_check(session.snapshot().phase == "running" and session.snapshot().elapsed_ms == 20, "first gate starts at crossing fraction within movement")
	for index in range(600):
		_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().elapsed_ms == 10020 and session.rules.snapshot().race_elapsed_ms == 10020, "600 running frames accumulate 10000ms without per-frame truncation")


func _order_and_finish() -> void:
	var session = _fresh()
	_ready(session)
	_step(session, Vector3(11, 1, 20), 0.04)
	var start: Dictionary = session.snapshot()
	_check(start.phase == "running" and start.next_physical_gate == 1, "first physical zero changes expected gate to one")
	_check(start.passed_checkpoints == 0 and start.lap == 0 and start.results.is_empty() and session.event_sequence == 0, "start gate awards no checkpoint, lap or finish sequence")
	_check(session.events.size() == 1 and session.events[0].kind == "start", "first zero emits only start event")
	_to_last_gate(session)
	var before_finish: Dictionary = session.snapshot()
	_check(before_finish.phase == "running" and before_finish.next_physical_gate == 0, "last numbered physical gate still requires finish zero")
	_check(before_finish.passed_checkpoints == 3 and before_finish.lap == 0 and before_finish.results.is_empty(), "last numbered gate cannot finish early")
	_finish(session)
	var result: Dictionary = session.snapshot()
	_check(result.phase == "finished" and result.lap == 1 and result.passed_checkpoints == 4, "ordered one-two-three-zero completes exactly one lap")
	_check(result.results == [{"user_id": "local-practice", "rank": 1, "completed_laps": 1, "finish_time_ms": 480}], "complete trajectory records exact identity and fraction-based 480ms")
	_check(result.elapsed_ms == 480 and session.event_sequence == 4 and session.holds_vehicle(), "finish freezes at plane and holds vehicle")
	_step(session, Vector3(12, 1, 20), 0.04)
	_check(session.snapshot() == result, "movement after finish cannot alter clock or result")


func _fraction_time() -> void:
	var session = _fresh(Vector3(9.5, 1, 20))
	_ready(session)
	for index in range(30):
		_step(session, session.last_position, 0.04)
	_step(session, Vector3(11.5, 1, 20), 0.04)
	_check(session.snapshot().elapsed_ms == 30, "quarter-segment start excludes first 10ms")
	_check(is_equal_approx(session.start_seconds, 4.21), "ready wait is excluded using actual crossing start time")
	_to_last_gate(session)
	_step(session, Vector3(8, 1, 20), 0.04)
	_step(session, Vector3(9, 1, 20), 0.04)
	_step(session, Vector3(10.5, 1, 20), 0.03)
	_check(session.snapshot().phase == "finished" and session.snapshot().elapsed_ms == 490, "two-thirds-segment finish includes 20ms and excludes final 10ms")
	_check(session.snapshot().results[0].finish_time_ms == 490, "result and display share crossing-based time")
	_check(is_equal_approx(session.events[-1].sim_seconds - session.start_seconds, 0.49), "event timestamps independently prove elapsed 490ms")


func _reverse_skips_and_repeats() -> void:
	var session = _fresh(Vector3(11, 1, 20))
	_ready(session)
	_step(session, SPAWN, 0.04)
	_check(session.snapshot().phase == "ready" and session.snapshot().elapsed_ms == 0 and session.events.is_empty(), "reverse zero crossing does not start")
	_step(session, Vector3(11, 1, 20), 0.04)
	_step(session, SPAWN, 0.04)
	_step(session, Vector3(11, 1, 20), 0.04)
	_check(session.snapshot().next_physical_gate == 1 and session.snapshot().passed_checkpoints == 0 and session.event_sequence == 0, "repeated zero cannot add progress after start")
	# Miss gate one outside its aperture, then cross two/three/zero in order.
	# Those later gates cannot repair the missing gate one or award a lap.
	_move(session, Vector3(13, 1, 20))
	_move(session, Vector3(13, 1, 24))
	_move(session, Vector3(8, 1, 24))
	_move(session, Vector3(8, 1, 20))
	_move(session, Vector3(11, 1, 20))
	var skipped: Dictionary = session.snapshot()
	_check(skipped.phase == "running" and skipped.next_physical_gate == 1 and skipped.passed_checkpoints == 0, "out-of-aperture missed gate prevents later checkpoints from scoring")
	_check(skipped.lap == 0 and skipped.results.is_empty() and session.event_sequence == 0, "skipped path has no lap, result or rule event sequence")
	_to_last_gate(session)
	_finish(session)
	_check(session.snapshot().phase == "finished" and session.snapshot().passed_checkpoints == 4, "fresh complete ordered loop still finishes after rejected crossings")


func _restart() -> void:
	var session = _fresh()
	_ready(session)
	_step(session, Vector3(11, 1, 20), 0.04)
	_to_last_gate(session)
	_check(session.snapshot().passed_checkpoints == 3 and session.event_sequence == 3, "restart fixture has real progress just before finish")
	_check(session.restart(_gates(), SPAWN), "restart before finish succeeds")
	_assert_fresh(session, "restart before finish")
	_check(session.restart(_gates(), SPAWN), "immediate consecutive restart succeeds")
	_assert_fresh(session, "consecutive R equivalent")
	_ready(session)
	_step(session, Vector3(11, 1, 20), 0.04)
	_to_last_gate(session)
	_finish(session)
	_check(session.snapshot().results.size() == 1, "restarted session can complete a clean lap")
	_check(session.restart(_gates(), SPAWN), "restart after finish succeeds")
	_assert_fresh(session, "restart clears previous result")


func _invalid_trajectory() -> void:
	var moved = _fresh()
	_step(moved, Vector3(9.1, 1, 20), 0.04)
	_assert_invalid(moved, "MOVED_DURING_COUNTDOWN", "motion during locked countdown")
	var discontinuous = _fresh()
	_ready(discontinuous)
	discontinuous.step(Vector3(9.1, 1, 20), Vector3(9.2, 1, 20), 0.04)
	_assert_invalid(discontinuous, "DISCONTINUITY", "unreported displacement")
	var oversized = _fresh()
	_ready(oversized)
	_step(oversized, Vector3(12, 1, 20), 0.04)
	_assert_invalid(oversized, "SEGMENT_TOO_LONG", "segment longer than two metres")
	var invalid_point = _fresh()
	_ready(invalid_point)
	_step(invalid_point, Vector3(NAN, 1, 20), 0.04)
	_assert_invalid(invalid_point, "INVALID_POSITION", "nonfinite trajectory point")
	for dt in [0.0, -0.001, 0.050001, NAN, INF]:
		var invalid_time = _fresh()
		_step(invalid_time, SPAWN, dt)
		_assert_invalid(invalid_time, "INVALID_STEP_TIME", "invalid physics duration " + str(dt))


func _snapshot_copies() -> void:
	var session = _fresh()
	_ready(session)
	_step(session, Vector3(11, 1, 20), 0.04)
	_to_last_gate(session)
	_finish(session)
	var before: Dictionary = session.snapshot()
	var copy: Dictionary = session.snapshot()
	copy.phase = "running"
	copy.elapsed_ms = 0
	copy.next_physical_gate = 0
	copy.results[0].rank = 9
	copy.results[0].finish_time_ms = -1
	copy.results.append({"user_id": "forged", "rank": 1})
	_check(session.snapshot() == before, "snapshot scalar and nested result mutation cannot change session")
	var waiting = _fresh()
	var waiting_copy: Dictionary = waiting.snapshot()
	waiting_copy.results.append({"user_id": "forged"})
	_check(waiting.snapshot().results.is_empty(), "empty snapshot result array is detached")


func _gates() -> Array:
	# Non-origin world positions: no implicit spawn-relative coordinate shift.
	return [
		_gate(0, Vector3(10, 0, 20), Vector3.RIGHT, Vector3.BACK),
		_gate(1, Vector3(12, 0, 22), Vector3.BACK, Vector3.LEFT),
		_gate(2, Vector3(10, 0, 24), Vector3.LEFT, Vector3.FORWARD),
		_gate(3, Vector3(8, 0, 22), Vector3.FORWARD, Vector3.RIGHT),
	]


func _gate(id: int, position: Vector3, forward: Vector3, right: Vector3) -> Dictionary:
	return {"id": id, "position": position, "forward": forward, "right": right, "half_width_m": 0.4, "height_m": 2.0}


func _fresh(position := SPAWN):
	var session = Session.new()
	_check(session.restart(_gates(), position), "valid non-origin rectangle configures")
	return session


func _ready(session) -> void:
	for index in range(180):
		_step(session, session.last_position, 1.0 / 60.0)
	_check(session.snapshot().phase == "ready", "stationary three-second countdown reaches ready")


func _step(session, target: Vector3, dt := 0.04) -> void:
	session.step(session.last_position, target, dt)


func _move(session, target: Vector3) -> void:
	var origin: Vector3 = session.last_position
	var count := maxi(1, ceili(origin.distance_to(target)))
	for index in range(1, count + 1):
		_step(session, origin.lerp(target, float(index) / count))


func _to_last_gate(session) -> void:
	for point in [Vector3(12, 1, 20), Vector3(12, 1, 21), Vector3(12, 1, 23), Vector3(12, 1, 24), Vector3(11, 1, 24), Vector3(9, 1, 24), Vector3(8, 1, 24), Vector3(8, 1, 23), Vector3(8, 1, 21)]:
		_step(session, point)


func _finish(session) -> void:
	for point in [Vector3(8, 1, 20), Vector3(9, 1, 20), Vector3(11, 1, 20)]:
		_step(session, point)


func _assert_fresh(session, label: String) -> void:
	var snapshot: Dictionary = session.snapshot()
	_check(snapshot.phase == "countdown" and snapshot.countdown_remaining_ms == 3000 and session.holds_vehicle(), label + " resets full locked countdown")
	_check(snapshot.elapsed_ms == 0 and snapshot.lap == 0 and snapshot.passed_checkpoints == 0 and snapshot.next_physical_gate == 0 and snapshot.results.is_empty(), label + " clears clock, progress and result")
	_check(session.event_sequence == 0 and session.events.is_empty() and session.sim_seconds == 0.0 and session.start_seconds == -1.0 and session.last_position == SPAWN and snapshot.error.is_empty(), label + " clears sequence, history, anchor and error")


func _assert_invalid(session, code: String, label: String) -> void:
	var snapshot: Dictionary = session.snapshot()
	_check(snapshot.phase == "invalid" and snapshot.error == code and session.holds_vehicle(), label + " invalidates and holds vehicle")
	_step(session, Vector3(11, 1, 20), 0.04)
	_check(session.snapshot() == snapshot, label + " cannot recover via later valid movement")
	_check(session.restart(_gates(), SPAWN), label + " explicit restart succeeds")
	_assert_fresh(session, label + " restart")


func _check(condition: bool, label: String) -> void:
	checks.append({"name": label, "ok": condition})
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("RACING_PRACTICE_FAIL: " + label)
