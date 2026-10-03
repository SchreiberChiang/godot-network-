extends RefCounted

const Detector = preload("res://examples/racing/checkpoints/checkpoint_detector.gd")
var passed := 0
var failed := 0
var _frame_detector: RefCounted
var _frame_rate_index := 0
var _frame_elapsed := 0.0
var _frame_previous := Vector3(0, 0, 5)
var _frame_expected := 0
var _frame_events: Array = []
var _frame_count := 0
const FRAME_RATES := [30, 60, 120]


func run() -> void:
	var version := Engine.get_version_info()
	_check(version.major == 4 and version.minor == 7 and version.patch == 2, "requested Godot 4.7.2")
	var isolation := OS.get_environment("RACING_CHECKPOINTS_ISOLATION").replace("\\", "/").trim_suffix("/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	_check(not isolation.is_empty() and user_dir.begins_with(isolation + "/"), "user data remains in isolated F-drive run")
	print("TEST_ENV engine=", version.string, " user_data=", user_dir)
	_test_geometry()
	_test_sequence()
	_test_multiframe()
	_test_resets()
	_test_validation()
	_test_partition_invariance()


func _gate(index: int, center := Vector3.ZERO, basis := Basis.IDENTITY, width := 2.0, height := 1.0) -> Dictionary:
	return {"checkpoint": index, "center": center, "basis": basis, "half_width": width, "half_height": height}


func _new(gates: Array = [], limit := 256.0) -> RefCounted:
	var detector = Detector.new()
	if gates.is_empty():
		gates = [_gate(0), _gate(1, Vector3(0, 0, -10))]
	_check(detector.configure(gates, limit).ok, "configure test course")
	return detector


func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL ", label)


func _event(result: Dictionary, checkpoint: int, fraction: float, label: String) -> void:
	_check(result.ok and result.events.size() == 1, label + " count")
	if result.events.size() == 1:
		_check(result.events[0].checkpoint == checkpoint, label + " checkpoint")
		_check(is_finite(result.events[0].fraction) and absf(result.events[0].fraction - fraction) < 0.000002, label + " fraction")


func _none(result: Dictionary, label: String, code := "OK") -> void:
	_check(result.code == code and result.events.is_empty(), label)


func _test_geometry() -> void:
	_event(_new().step(Vector3(0, 0, 3), Vector3(0, 0, -1), 0), 0, 0.75, "forward crossing")
	_none(_new().step(Vector3(0, 0, -1), Vector3(0, 0, 3), 0), "reverse")
	_none(_new().step(Vector3(0, 0, 1), Vector3(0, 0, 1), 0), "stationary")
	_none(_new().step(Vector3(-1, 0, 0), Vector3(1, 0, 0), 0), "coplanar slide")
	_none(_new().step(Vector3(0, 0, 0), Vector3(0, 0, -1), 0), "unarmed plane departure")
	for point in [Vector3(2.001, 0, 0), Vector3(-2.001, 0, 0), Vector3(0, 1.001, 0), Vector3(0, -1.001, 0)]:
		_none(_new().step(point + Vector3.BACK, point + Vector3.FORWARD, 0), "outside aperture " + str(point))
	for point in [Vector3(2, 1, 0), Vector3(-2, -1, 0)]:
		_event(_new().step(point + Vector3.BACK, point + Vector3.FORWARD, 0), 0, 0.5, "closed aperture corner")
	_none(_new().step(Vector3(5, 0, 1), Vector3(1, 0, -1), 0), "end inside but intersection outside")
	_event(_new().step(Vector3(0, 0, 1), Vector3(3, 0, -1), 0), 0, 0.5, "end outside but intersection inside")
	var basis := Basis.from_euler(Vector3(0.3, 1.1, -0.2))
	var center := Vector3(231, 6, -151)
	var gates := [_gate(0, center, basis), _gate(1, Vector3(0, 0, -500))]
	_event(_new(gates).step(center + basis * Vector3(0.3, 0.2, 2), center + basis * Vector3(0.3, 0.2, -2), 0), 0, 0.5, "rotated translated gate")
	_none(_new(gates).step(center + basis * Vector3(0, 2, 2), center + basis * Vector3(0, 2, -2), 0), "rotated local height")
	# A shallow direction is still a crossing, not rejected by a speed epsilon.
	var slow = _new()
	_none(slow.step(Vector3(0, 0, 0.1), Vector3(0, 0, 0.000001), 0), "slow approach")
	_event(slow.step(Vector3(0, 0, 0.000001), Vector3(1, 0, -0.000001), 0), 0, 0.5, "near parallel crossing")


func _test_sequence() -> void:
	var gates := [_gate(2, Vector3(0, 0, -20)), _gate(0), _gate(1, Vector3(0, 0, -10))]
	var detector = _new(gates)
	var result: Dictionary = detector.step(Vector3(0, 0, 10), Vector3(0, 0, -30), 0)
	_check(result.events.size() == 3 and result.next_expected == 0, "high speed three gates")
	for index in result.events.size():
		_check(result.events[index].checkpoint == index and absf(result.events[index].fraction - (index + 1) * 0.25) < 0.000001, "spatial sorting " + str(index))
	_none(detector.step(Vector3(0, 0, -30), Vector3(0, 0, -19), 0), "back through last gate")
	_none(detector.step(Vector3(0, 0, -19), Vector3(0, 0, -30), 0), "last gate cannot count again")
	_none(detector.step(Vector3(0, 0, -30), Vector3(0, 0, 10), 0), "reverse whole course")
	_check(detector.step(Vector3(0, 0, 10), Vector3(0, 0, -30), 0).events.size() == 3, "later ordered traversal allowed")
	var wrong_order = _new([_gate(0, Vector3(0, 0, -10)), _gate(1)])
	_event(wrong_order.step(Vector3(0, 0, 5), Vector3(0, 0, -15), 0), 0, 0.75, "earlier wrong gate not reused")
	_none(wrong_order.step(Vector3(0, 0, -15), Vector3(0, 0, -16), 1), "wrong gate not buffered")
	var tied = _new([_gate(1), _gate(0)])
	var ties: Dictionary = tied.step(Vector3.BACK, Vector3.FORWARD, 0)
	_check(ties.events.size() == 2, "coincident deterministic count")
	if ties.events.size() == 2:
		_check(ties.events[0].checkpoint == 0 and ties.events[1].checkpoint == 1 and ties.events[0].fraction == ties.events[1].fraction, "exact ties ordered by id")
	_event(_new([_gate(1), _gate(0)]).step(Vector3.BACK, Vector3.FORWARD, 1), 1, 0.5, "tie is not reordered around expected")
	var many: Array = []
	for index in range(63, -1, -1):
		many.append(_gate(index, Vector3(0, 0, -index)))
	var many_result: Dictionary = _new(many).step(Vector3(0, 0, 1), Vector3(0, 0, -64), 0)
	_check(many_result.events.size() == 64 and many_result.next_expected == 0, "bounded maximum gate batch")
	for index in many_result.events.size():
		_check(many_result.events[index].checkpoint == index and many_result.events[index].fraction >= 0 and many_result.events[index].fraction <= 1, "bounded batch event " + str(index))


func _test_multiframe() -> void:
	var detector = _new()
	_none(detector.step(Vector3(0, 0, 0.2), Vector3(0, 0, 0.01), 0), "armed slow approach")
	_event(detector.step(Vector3(0, 0, 0.01), Vector3(0, 0, -0.01), 0), 0, 0.5, "cross before positive hysteresis distance")
	_none(detector.step(Vector3(0, 0, -0.01), Vector3(0, 0, -0.2), 1), "no delayed duplicate")
	_none(detector.step(Vector3(0, 0, -0.2), Vector3(0, 0, 0.3), 1), "retreat beyond arm distance")
	_none(detector.step(Vector3(0, 0, 0.3), Vector3(0, 0, -0.3), 1), "retreat and recross is duplicate")
	_none(detector.step(Vector3(0, 0, -0.3), Vector3(0, 0, 0.3), 0), "caller cannot rewind expected", "EXPECTED_MISMATCH")
	var edge = _new()
	_none(edge.step(Vector3.BACK, Vector3.ZERO, 0), "arrive exactly on plane")
	_none(edge.step(Vector3.ZERO, Vector3.ZERO, 0), "wait on plane")
	_event(edge.step(Vector3.ZERO, Vector3.FORWARD, 0), 0, 0.0, "armed plane departure")
	var retreat = _new()
	_none(retreat.step(Vector3.BACK, Vector3.ZERO, 0), "touch plane")
	_none(retreat.step(Vector3.ZERO, Vector3.BACK, 0), "touch and retreat never crossed")
	var jitter = _new()
	var previous := Vector3.ZERO
	for index in 60:
		var current := Vector3(0, 0, 0.005 if index % 2 == 0 else -0.005)
		_none(jitter.step(previous, current, 0), "unarmed stand-line jitter " + str(index))
		previous = current
	var outside = _new()
	_none(outside.step(Vector3(3, 0, 1), Vector3(3, 0, -1), 0), "outside consumes approach")
	_none(outside.step(Vector3(3, 0, -1), Vector3(0, 0, 0), 0), "return only to plane")
	_none(outside.step(Vector3(0, 0, 0), Vector3(0, 0, -1), 0), "cannot reuse outside approach")


func _test_resets() -> void:
	var detector = _new()
	_none(detector.step(Vector3(0, 0, 2), Vector3(0, 0, -12), 0, true), "marked teleport", "RESET")
	_none(detector.step(Vector3(0, 0, -12), Vector3(0, 0, -13), 0), "no deferred teleport event")
	_none(detector.step(Vector3(0, 0, -13), Vector3(0, 0, 2), 0, true), "reset behind gate", "RESET")
	_event(detector.step(Vector3(0, 0, 2), Vector3(0, 0, -2), 0), 0, 0.5, "new movement after reset")
	_none(detector.step(Vector3(0, 0, -2), Vector3(0, 0, 2), 1, true), "reset preserves cursor", "RESET")
	_none(detector.step(Vector3(0, 0, 2), Vector3(0, 0, -2), 1), "reset cannot duplicate accepted gate")
	_none(detector.step(Vector3(0, 0, -2), Vector3.ZERO, 1, true), "reset on plane", "RESET")
	_none(detector.step(Vector3.ZERO, Vector3.FORWARD, 1), "reset removes approach history")
	var discontinuity = _new()
	_none(discontinuity.step(Vector3(0, 0, 3), Vector3(0, 0, 2), 0), "continuous baseline")
	_none(discontinuity.step(Vector3(0, 0, 1), Vector3(0, 0, -1), 0), "unmarked start gap", "DISCONTINUITY")
	_none(discontinuity.step(Vector3(0, 0, -1), Vector3(0, 0, -2), 0), "gap reanchors")
	_none(_new([], 10.0).step(Vector3(0, 0, 5), Vector3(0, 0, -6), 0), "oversized segment", "SEGMENT_TOO_LONG")
	_event(_new([], 10.0).step(Vector3(0, 0, 5), Vector3(0, 0, -5), 0), 0, 0.5, "exact segment bound")
	var invalid = _new()
	_none(invalid.step(Vector3.BACK, Vector3(INF, 0, 0), 0), "bad sample", "INVALID_POSITION")
	_none(invalid.step(Vector3.BACK, Vector3.FORWARD, 0), "bad sample requires reset", "RESET_REQUIRED")
	_none(invalid.step(Vector3.BACK, Vector3.ZERO, 0, true), "explicit recovery", "RESET")
	_none(invalid.step(Vector3.ZERO, Vector3.FORWARD, 0), "recovery at plane unarmed")


func _test_validation() -> void:
	_none(Detector.new().step(Vector3.ZERO, Vector3.ZERO, 0), "unconfigured", "NOT_CONFIGURED")
	for value in [null, {}, [], [_gate(0)], 1, "gates"]:
		_check(not Detector.new().configure(value).ok, "invalid collection")
	for value in [0, -1, NAN, INF, true, "2", 2048.1]:
		_check(not Detector.new().configure([_gate(0), _gate(1)], value).ok, "invalid segment limit")
	for value in [0, -1, NAN, INF, true, "2", 0.049, 1024.1]:
		var gate := _gate(0)
		gate.half_width = value
		_check(not Detector.new().configure([gate, _gate(1)]).ok, "invalid width")
	for value in [Basis(Vector3(2, 0, 0), Vector3.UP, Vector3.BACK), Basis(Vector3.RIGHT, Vector3(0.1, 1, 0), Vector3.BACK), Basis(Vector3.LEFT, Vector3.UP, Vector3.BACK), Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Basis(Vector3(INF, 0, 0), Vector3.UP, Vector3.BACK), null]:
		var gate := _gate(0)
		gate.basis = value
		_check(not Detector.new().configure([gate, _gate(1)]).ok, "invalid basis")
	for value in [Vector3(NAN, 0, 0), Vector3(INF, 0, 0), Vector3(8193, 0, 0), Vector3(1e30, 1e30, 1e30), null, Vector2.ZERO]:
		_none(_new().step(Vector3.BACK, value, 0), "invalid sample position", "INVALID_POSITION")
		var gate := _gate(0)
		gate.center = value
		_check(not Detector.new().configure([gate, _gate(1)]).ok, "invalid gate center")
	for value in [-1, 2, 0.0, true, "0", null]:
		_none(_new().step(Vector3.BACK, Vector3.FORWARD, value), "invalid expected", "INVALID_EXPECTED")
	_none(_new().step(Vector3.BACK, Vector3.FORWARD, 0, 1), "invalid reset flag", "INVALID_RESET")
	_check(not Detector.new().configure([_gate(0), _gate(0)]).ok, "duplicate id")
	_check(not Detector.new().configure([_gate(0), _gate(2)]).ok, "missing id")
	var unknown := _gate(0)
	unknown.extra = 0
	_check(not Detector.new().configure([unknown, _gate(1)]).ok, "unknown gate field")
	var original := [_gate(0), _gate(1, Vector3(0, 0, -10))]
	var isolated = _new(original)
	original[0].center = Vector3(0, 0, -100)
	_event(isolated.step(Vector3.BACK, Vector3.FORWARD, 0), 0, 0.5, "defensive config copy")
	_check(isolated.configure(original).code == "CONFIG_LOCKED", "configuration cannot rewind history")
	var bound := Vector3(8192, 8192, 8190)
	_event(_new([_gate(0, bound), _gate(1)]).step(bound + Vector3.BACK, bound + Vector3.FORWARD, 0), 0, 0.5, "world bound arithmetic")
	var independent = _new()
	_event(independent.step(Vector3.BACK, Vector3.FORWARD, 0), 0, 0.5, "independent racer")


func _sample_path(samples: int) -> Array:
	var detector = _new([_gate(0, Vector3(0, 0, 1)), _gate(1, Vector3(0, 0, -9)), _gate(2, Vector3(0, 0, -21))])
	var result_times: Array = []
	var previous := Vector3(0, 0, 5)
	var expected := 0
	for index in samples:
		var current := Vector3(0, 0, 5.0 - 30.0 * (index + 1) / samples)
		var result: Dictionary = detector.step(previous, current, expected)
		_check(result.ok, "partition valid")
		for event in result.events:
			result_times.append((index + event.fraction) * 0.3 / samples)
		expected = result.next_expected
		previous = current
	return result_times


func _test_partition_invariance() -> void:
	for samples in [1, 3, 9, 18, 36, 37]:
		var times := _sample_path(samples)
		_check(times.size() == 3, "partition event count " + str(samples))
		if times.size() == 3:
			for index in 3:
				_check(absf(times[index] - [0.04, 0.14, 0.26][index]) < 0.000002, "global crossing time independent of partitions")
	# Deliberately below arming distance: coarse sampling must not invent history.
	_none(_new().step(Vector3(0, 0, 0.005), Vector3(0, 0, -5), 0), "no earlier behind sample means unarmed")
	# Endpoints cannot reconstruct a bent path around a finite gate.
	var bent = _new()
	_none(bent.step(Vector3(0, 0, 2), Vector3(4, 0, 0), 0), "bend arrives outside aperture")
	_none(bent.step(Vector3(4, 0, 0), Vector3(0, 0, -2), 0), "bend crosses outside aperture")
	_event(_new().step(Vector3(0, 0, 2), Vector3(0, 0, -2), 0), 0, 0.5, "coarse chord differs from bent path by contract")
	# Both gates must remember the earlier behind-side sample even though gate 1
	# only becomes expected when the trajectory is already inside its arm band.
	var dense_gates := [_gate(0), _gate(1, Vector3(0, 0, -0.01))]
	var coarse: Dictionary = _new(dense_gates).step(Vector3(0, 0, 0.1), Vector3(0, 0, -0.1), 0)
	_check(coarse.events.size() == 2, "dense gates coarse")
	var dense = _new(dense_gates)
	var previous := Vector3(0, 0, 0.1)
	var expected := 0
	var dense_ids: Array = []
	for z in [0.005, -0.005, -0.015, -0.1]:
		var current := Vector3(0, 0, z)
		var result: Dictionary = dense.step(previous, current, expected)
		for event in result.events:
			dense_ids.append(event.checkpoint)
		expected = result.next_expected
		previous = current
	_check(dense_ids == [0, 1], "dense gates fine sampling preserves both arms")


func begin_physics_frames() -> void:
	_frame_detector = _new([_gate(0, Vector3(0, 0, 1)), _gate(1, Vector3(0, 0, -9)), _gate(2, Vector3(0, 0, -21))])
	_frame_elapsed = 0.0
	_frame_previous = Vector3(0, 0, 5)
	_frame_expected = 0
	_frame_events = []
	_frame_count = 0
	Engine.physics_ticks_per_second = FRAME_RATES[_frame_rate_index]


## Driven by actual SceneTree physics callbacks, no vehicle/server scene.
func physics_tick(delta: float) -> bool:
	var rate: int = FRAME_RATES[_frame_rate_index]
	_check(absf(delta - 1.0 / rate) < 0.000001, "actual physics delta " + str(rate))
	var current := Vector3(0, 0, 5.0 - 100.0 * (_frame_elapsed + delta))
	var result: Dictionary = _frame_detector.step(_frame_previous, current, _frame_expected)
	_check(result.ok, "actual physics segment")
	for event in result.events:
		_frame_events.append({"checkpoint": event.checkpoint, "time": _frame_elapsed + event.fraction * delta})
	_frame_expected = result.next_expected
	_frame_previous = current
	_frame_elapsed += delta
	_frame_count += 1
	if _frame_count < rate * 0.3:
		return false
	_check(_frame_events.size() == 3, "actual frames count " + str(rate))
	for index in _frame_events.size():
		_check(_frame_events[index].checkpoint == index and absf(_frame_events[index].time - [0.04, 0.14, 0.26][index]) < 0.000002, "actual frames crossing time " + str(rate))
	print("PHYSICS_FRAMES rate=", rate, " frames=", _frame_count, " events=", _frame_events)
	_frame_rate_index += 1
	if _frame_rate_index == FRAME_RATES.size():
		return true
	begin_physics_frames()
	return false
