extends RefCounted
## Pure driving intent and match-local nitro; no physics, input polling or services.
## The caller supplies collision-resolved displacement velocity in the XZ plane.
const FUEL_CAPACITY := 3.0
const NITRO_COST := 1.0
const BOOST_DURATION := 1.5
const DRIFT_CHARGE_RATE := 0.25
const REVERSE_STOP_SPEED := 0.15
const SPEED_EPSILON := 0.000001
const DRIFT_MIN_FORWARD_SPEED := 6.0
const DRIFT_MIN_ANGLE := 8.0
const DRIFT_MAX_ANGLE := 75.0
const TIME_EPSILON := 0.000000001
const ANGLE_EPSILON := 0.00001

var _fuel := 0.0
var _boost_remaining := 0.0
var _mode := "forward"
var _drifting := false
var _request_busy := false

func reset() -> void:
	_fuel = 0.0
	_boost_remaining = 0.0
	_mode = "forward"
	_drifting = false
	_request_busy = false

func request_nitro(left: bool, right: bool) -> bool:
	# One invocation is one edge. Holding/debouncing keys belongs to the caller.
	# No callbacks occur within this transaction; queued requests only add time.
	if _request_busy or (left and right) or _mode == "reverse":
		return false
	if _fuel + TIME_EPSILON < NITRO_COST:
		return false
	_request_busy = true
	_fuel = maxf(0.0, _fuel - NITRO_COST)
	_boost_remaining += BOOST_DURATION
	_request_busy = false
	return true

func step(dt: float, left: bool, right: bool, actual_velocity: Vector2, forward: Vector2) -> Dictionary:
	var steer := int(right) - int(left)
	var has_boost := _boost_remaining > 0.0
	var valid_velocity := actual_velocity.is_finite() and is_finite(actual_velocity.length())
	if not (left and right):
		_mode = "forward"
	elif has_boost:
		# Active nitro cannot change the braking command into reverse thrust.
		_mode = "brake"
	elif _mode == "reverse":
		pass # Keep reversing while both keys remain held, even once moving.
	elif valid_velocity and actual_velocity.length() <= REVERSE_STOP_SPEED + SPEED_EPSILON:
		_mode = "reverse"
	else:
		_mode = "brake"

	_drifting = _is_actual_drift(actual_velocity, forward, valid_velocity)
	var boost_fraction := 0.0
	if is_finite(dt) and dt > 0.0:
		var boost_time := minf(dt, _boost_remaining)
		_boost_remaining = maxf(0.0, _boost_remaining - boost_time)
		if _boost_remaining < TIME_EPSILON:
			_boost_remaining = 0.0
		boost_fraction = clampf(boost_time / dt, 0.0, 1.0)
		if _drifting:
			_fuel = minf(FUEL_CAPACITY, _fuel + dt * DRIFT_CHARGE_RATE)
	return {
		"mode": _mode,
		"steer": steer,
		"boost_fraction": boost_fraction,
		# True also on the final partially boosted step. Force uses the fraction.
		"boost_active": boost_fraction > 0.0 or _boost_remaining > 0.0,
		"fuel": _fuel,
		"boost_remaining": _boost_remaining,
		"drifting": _drifting,
	}

func _is_actual_drift(velocity: Vector2, forward: Vector2, valid_velocity: bool) -> bool:
	if not valid_velocity or not forward.is_finite() or _mode == "reverse":
		return false
	var forward_length := forward.length()
	if not is_finite(forward_length) or forward_length <= TIME_EPSILON:
		return false
	var heading := forward / forward_length
	var forward_speed := velocity.dot(heading)
	if forward_speed < DRIFT_MIN_FORWARD_SPEED:
		return false
	var slip_angle := rad_to_deg(atan2(absf(heading.cross(velocity)), forward_speed))
	return slip_angle + ANGLE_EPSILON >= DRIFT_MIN_ANGLE and slip_angle - ANGLE_EPSILON <= DRIFT_MAX_ANGLE
