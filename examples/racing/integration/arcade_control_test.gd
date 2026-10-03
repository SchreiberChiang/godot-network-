extends Node
## Can be instantiated without adding to SceneTree: new().run() -> Dictionary.
const Control := preload("arcade_control.gd")
const FORWARD := Vector2(0.0, -1.0)
const DRIFT_VELOCITY := Vector2(4.0, -10.0)
const EPSILON := 0.00001

var _checks: Array[Dictionary] = []
var _passed := 0
var _failed := 0

func run() -> Dictionary:
	_checks.clear()
	_passed = 0
	_failed = 0
	_test_defaults_and_modes()
	_test_drift_resources()
	_test_requests_and_duration()
	_test_boost_brake_reverse()
	_test_backward_inertia_nitro()
	_test_rates_and_invalid_inputs()
	return {"passed": _passed, "failed": _failed, "checks": _checks.duplicate(true)}

func _check(name: String, ok: bool, detail: Variant = null) -> void:
	_checks.append({"name": name, "ok": ok, "detail": detail})
	if ok:
		_passed += 1
	else:
		_failed += 1

func _close(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) < EPSILON

func _peek(control: Control) -> Dictionary:
	return control.step(0.0, false, false, Vector2.ZERO, FORWARD)

func _charge(control: Control, units: float) -> Dictionary:
	return control.step(units / Control.DRIFT_CHARGE_RATE, false, false, DRIFT_VELOCITY, FORWARD)

func _test_defaults_and_modes() -> void:
	var control := Control.new()
	var state := _peek(control)
	_check("starts forward without fuel or boost", state.mode == "forward" and state.steer == 0 and state.fuel == 0.0 and state.boost_remaining == 0.0 and not state.boost_active)
	_check("empty tank refuses nitro without mutation", not control.request_nitro(false, false) and _peek(control).fuel == 0.0)
	var left := control.step(0.1, true, false, Vector2.ZERO, FORWARD)
	var right := control.step(0.1, false, true, Vector2.ZERO, FORWARD)
	_check("single keys steer in forward mode", left.steer == -1 and right.steer == 1 and left.mode == "forward" and right.mode == "forward")
	state = control.step(0.1, true, true, Vector2(0.0, -0.16), FORWARD)
	_check("both keys brake above stop threshold and never steer", state.mode == "brake" and state.steer == 0)
	state = control.step(0.1, true, true, Vector2(0.3, 0.0), FORWARD)
	_check("sideways motion must also stop before reverse", state.mode == "brake")
	state = control.step(0.1, true, true, Vector2(0.0, -0.15), FORWARD)
	_check("near-zero speed switches both keys to reverse", state.mode == "reverse" and state.steer == 0)
	state = control.step(0.1, true, true, Vector2(0.0, 3.0), FORWARD)
	_check("reverse stays latched while both keys held", state.mode == "reverse" and state.steer == 0)
	state = control.step(0.1, false, true, Vector2(0.0, 3.0), FORWARD)
	_check("release of either key restores forward despite backward inertia", state.mode == "forward" and state.steer == 1)

func _test_drift_resources() -> void:
	var control := Control.new()
	var state := control.step(4.0, false, false, DRIFT_VELOCITY, FORWARD)
	_check("actual drift charges without steering input", state.drifting and _close(state.fuel, 1.0))
	state = control.step(100.0, false, false, DRIFT_VELOCITY, FORWARD)
	_check("fuel is capped at three units", state.drifting and state.fuel == 3.0)
	control.reset()
	state = control.step(20.0, true, false, Vector2.ZERO, FORWARD)
	_check("wall-blocked steering without actual displacement cannot charge", not state.drifting and state.fuel == 0.0)
	state = control.step(20.0, true, false, Vector2(0.0, -20.0), FORWARD)
	_check("fast straight motion cannot charge", not state.drifting and state.fuel == 0.0)
	state = control.step(20.0, true, false, Vector2(5.0, -5.99), FORWARD)
	_check("forward speed below six cannot charge", not state.drifting and state.fuel == 0.0)
	state = control.step(20.0, true, false, Vector2(4.0, 10.0), FORWARD)
	_check("backward actual motion cannot charge", not state.drifting and state.fuel == 0.0)
	for angle in [7.9, 8.0, 75.0, 75.1]:
		control.reset()
		var velocity := Vector2(10.0 * tan(deg_to_rad(angle)), -10.0)
		state = control.step(1.0, false, false, velocity, FORWARD)
		var expected := angle >= 8.0 and angle <= 75.0
		_check("actual slip boundary %.1f degrees" % angle, state.drifting == expected and _close(state.fuel, 0.25 if expected else 0.0), state)
	control.reset()
	state = control.step(4.0, false, false, Vector2(-4.0, -6.0), FORWARD * 2.0)
	_check("six m/s boundary and opposite slip normalize heading", state.drifting and _close(state.fuel, 1.0))

func _test_requests_and_duration() -> void:
	var control := Control.new()
	_charge(control, 0.75)
	_check("fractional fuel cannot buy partial nitro", not control.request_nitro(false, false) and _close(_peek(control).fuel, 0.75))
	_charge(control, 0.25)
	var accepted: bool = control.request_nitro(true, false)
	var state := _peek(control)
	_check("one edge deducts one unit and queues 1.5 seconds", accepted and _close(state.fuel, 0.0) and _close(state.boost_remaining, 1.5))
	_check("next request with empty tank does not deduct again", not control.request_nitro(false, false) and _close(_peek(control).boost_remaining, 1.5))
	state = control.step(1.0, false, false, Vector2.ZERO, FORWARD)
	_check("first second sprays fully and leaves half second", _close(state.boost_fraction, 1.0) and _close(state.boost_remaining, 0.5))
	state = control.step(1.0, false, false, Vector2.ZERO, FORWARD)
	_check("crossing expiry sprays exactly half the step", _close(state.boost_fraction, 0.5) and state.boost_remaining == 0.0 and state.boost_active)
	state = control.step(1.0, false, false, Vector2.ZERO, FORWARD)
	_check("following step has no residual spray", state.boost_fraction == 0.0 and not state.boost_active)
	control.reset()
	_charge(control, 3.0)
	control.request_nitro(false, false)
	control.step(0.4, false, false, Vector2.ZERO, FORWARD)
	accepted = control.request_nitro(false, false)
	state = _peek(control)
	_check("second edge appends duration without refilling elapsed time", accepted and _close(state.fuel, 1.0) and _close(state.boost_remaining, 2.6))
	state = control.step(2.0, false, false, Vector2.ZERO, FORWARD)
	_check("queued nitro never stacks strength above one", _close(state.boost_fraction, 1.0) and _close(state.boost_remaining, 0.6))
	state = control.step(1.0, false, false, Vector2.ZERO, FORWARD)
	_check("queued duration remainder is conserved", _close(state.boost_fraction, 0.6) and state.boost_remaining == 0.0)

func _test_boost_brake_reverse() -> void:
	var control := Control.new()
	_charge(control, 3.0)
	_check("both keys refuse nitro without spending", not control.request_nitro(true, true) and _close(_peek(control).fuel, 3.0))
	control.step(0.1, true, true, Vector2.ZERO, FORWARD)
	_check("reverse mode refuses nitro without spending", not control.request_nitro(false, false))
	control.step(0.1, false, false, Vector2.ZERO, FORWARD)
	control.request_nitro(false, false)
	var state := control.step(1.0, true, true, Vector2.ZERO, FORWARD)
	_check("both keys can command stationary brake throughout active nitro", state.mode == "brake" and state.steer == 0 and _close(state.boost_fraction, 1.0) and _close(state.boost_remaining, 0.5))
	_check("active nitro cannot buy another unit while braking", not control.request_nitro(true, true))
	state = control.step(1.0, true, true, Vector2.ZERO, FORWARD)
	_check("expiry step remains braking and drains real remainder", state.mode == "brake" and _close(state.boost_fraction, 0.5) and state.boost_remaining == 0.0)
	state = control.step(0.1, true, true, Vector2.ZERO, FORWARD)
	_check("reverse starts only after nitro fully expires", state.mode == "reverse" and not state.boost_active)
	state = control.step(4.0, true, true, DRIFT_VELOCITY, FORWARD)
	_check("latched reverse cannot drift-charge", state.mode == "reverse" and not state.drifting and _close(state.fuel, 2.0))
	control.reset()
	state = control.step(0.1, true, true, Vector2(0.0, 3.0), FORWARD)
	_check("reset clears reverse latch before next both-key command", state.mode == "brake")
	_charge(control, 2.0)
	control.request_nitro(false, false)
	control.step(0.1, false, false, DRIFT_VELOCITY, FORWARD)
	control.reset()
	state = _peek(control)
	_check("reset clears fuel, queued spray and drift", state.mode == "forward" and state.fuel == 0.0 and state.boost_remaining == 0.0 and not state.boost_active and not state.drifting)

func _test_backward_inertia_nitro() -> void:
	var control := Control.new()
	_charge(control, 2.0)
	control.step(0.1, true, true, Vector2.ZERO, FORWARD)
	control.step(0.1, true, true, Vector2(0.0, 3.0), FORWARD)
	var state := control.step(0.1, false, true, Vector2(0.0, 3.0), FORWARD)
	var denied: bool = not control.request_nitro(false, true)
	state = control.step(0.0, false, true, Vector2(0.0, 3.0), FORWARD)
	_check("forward intent with actual backward inertia refuses nitro without spending", denied and state.mode == "forward" and _close(state.fuel, 2.0) and state.boost_remaining == 0.0)
	state = control.step(1.0, false, false, Vector2(NAN, 0.0), FORWARD)
	_check("invalid displacement preserves backward nitro restriction and cannot charge", not control.request_nitro(false, false) and _close(state.fuel, 2.0) and not state.drifting)
	state = control.step(1.0, false, false, DRIFT_VELOCITY, Vector2.ZERO)
	_check("invalid heading preserves backward nitro restriction and cannot charge", not control.request_nitro(false, false) and _close(state.fuel, 2.0) and not state.drifting)
	control.step(0.1, false, false, Vector2(0.0, -2.0), FORWARD)
	var accepted: bool = control.request_nitro(false, false)
	state = control.step(0.0, false, false, Vector2(0.0, -2.0), FORWARD)
	_check("actual forward recovery permits nitro again", accepted and _close(state.fuel, 1.0) and _close(state.boost_remaining, 1.5))
	state = control.step(0.2, false, false, Vector2(0.0, 1.0), FORWARD)
	denied = not control.request_nitro(false, false)
	state = control.step(0.0, false, false, Vector2(0.0, 1.0), FORWARD)
	_check("active nitro cannot append duration during actual backward motion", denied and state.mode == "forward" and _close(state.fuel, 1.0) and _close(state.boost_remaining, 1.3))
	control.step(0.0, false, false, Vector2.ZERO, FORWARD)
	accepted = control.request_nitro(false, false)
	state = _peek(control)
	_check("actual zero-speed recovery permits queued nitro", accepted and _close(state.fuel, 0.0) and _close(state.boost_remaining, 2.8))

func _test_rates_and_invalid_inputs() -> void:
	var results: Array[Dictionary] = []
	for hz in [60, 120]:
		var control := Control.new()
		var dt := 1.0 / float(hz)
		for _i in range(4 * hz):
			control.step(dt, false, false, DRIFT_VELOCITY, FORWARD)
		var accepted: bool = control.request_nitro(false, false)
		var spray_time := 0.0
		var peak_fraction := 0.0
		var state: Dictionary = {}
		for _i in range(2 * hz):
			state = control.step(dt, false, false, DRIFT_VELOCITY, FORWARD)
			spray_time += float(state.boost_fraction) * dt
			peak_fraction = maxf(peak_fraction, float(state.boost_fraction))
		_check("%d Hz conserved charge and real spray duration" % hz, accepted and _close(spray_time, 1.5) and _close(state.fuel, 0.5) and state.boost_remaining == 0.0 and peak_fraction <= 1.0, {"spray_time": spray_time, "fuel": state.fuel})
		results.append({"spray_time": spray_time, "fuel": state.fuel})
	_check("60 and 120 Hz give the same resource/time result", _close(results[0].spray_time, results[1].spray_time) and _close(results[0].fuel, results[1].fuel))
	var control := Control.new()
	_charge(control, 1.0)
	control.request_nitro(false, false)
	var state := control.step(1.5, false, false, DRIFT_VELOCITY, FORWARD)
	_check("boosting drift earns less than one spent unit", _close(state.fuel, 0.375) and state.boost_remaining == 0.0 and not control.request_nitro(false, false))
	control.reset()
	_charge(control, 2.0)
	control.request_nitro(false, false)
	state = control.step(1.0, false, false, DRIFT_VELOCITY, FORWARD)
	var extended: bool = control.request_nitro(false, false)
	state = _peek(control)
	_check("boost-time drift charge can fund a later queued request", extended and _close(state.fuel, 0.25) and _close(state.boost_remaining, 2.0))
	control.reset()
	_charge(control, 1.0)
	control.request_nitro(false, false)
	for bad_dt in [0.0, -1.0, NAN, INF]:
		state = control.step(bad_dt, false, false, DRIFT_VELOCITY, FORWARD)
		_check("invalid dt %s does not charge or drain" % str(bad_dt), _close(state.fuel, 0.0) and _close(state.boost_remaining, 1.5) and state.boost_fraction == 0.0)
	for invalid_forward in [Vector2.ZERO, Vector2(NAN, 0.0), Vector2(INF, 0.0)]:
		state = control.step(0.1, false, false, DRIFT_VELOCITY, invalid_forward)
		_check("invalid heading cannot charge %s" % str(invalid_forward), not state.drifting and state.fuel == 0.0 and is_finite(float(state.boost_remaining)))
	for invalid_velocity in [Vector2(NAN, 0.0), Vector2(INF, 0.0)]:
		state = control.step(0.1, true, true, invalid_velocity, FORWARD)
		_check("invalid displacement cannot charge or start reverse %s" % str(invalid_velocity), state.mode == "brake" and not state.drifting and state.fuel == 0.0)
