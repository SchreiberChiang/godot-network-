extends RefCounted
## Stateful geometric detector for ONE authoritative point trajectory.
## No clock, laps, RPC, scene tree, physics query, account or framework dependency.

const MAX_GATES := 64
const WORLD_LIMIT_M := 8192.0
const ARM_DISTANCE_M := 0.02
const MIN_HALF_EXTENT_M := 0.05
const MAX_HALF_EXTENT_M := 1024.0
const BASIS_TOLERANCE := 0.00001

var _gates: Array = []
var _armed: Array[bool] = []
var _max_segment_m := 256.0
var _has_position := false
var _last_position := Vector3.ZERO
var _next_expected := -1
var _needs_reset := false


## Each gate: checkpoint (int), center (Vector3), basis (unit right-handed
## Basis), half_width / half_height (positive metres). Local -Z is forward.
## Configuration is immutable after success; a new race needs a new detector.
func configure(gates: Variant, max_segment_m: Variant = 256.0) -> Dictionary:
	if not _gates.is_empty():
		return _result("CONFIG_LOCKED")
	if typeof(gates) != TYPE_ARRAY or gates.size() < 2 or gates.size() > MAX_GATES:
		return _result("INVALID_GATES")
	if not _number_in(max_segment_m, 0.1, 2048.0):
		return _result("INVALID_SEGMENT_LIMIT")
	var validated: Array = []
	validated.resize(gates.size())
	for value in gates:
		if typeof(value) != TYPE_DICTIONARY or value.size() != 5:
			return _result("INVALID_GATE")
		for key in ["checkpoint", "center", "basis", "half_width", "half_height"]:
			if not value.has(key):
				return _result("INVALID_GATE")
		if typeof(value.checkpoint) != TYPE_INT or value.checkpoint < 0 or value.checkpoint >= gates.size():
			return _result("INVALID_CHECKPOINT")
		if validated[value.checkpoint] != null:
			return _result("DUPLICATE_CHECKPOINT")
		if not _position_valid(value.center) or not _basis_valid(value.basis):
			return _result("INVALID_GATE_TRANSFORM")
		if not _number_in(value.half_width, MIN_HALF_EXTENT_M, MAX_HALF_EXTENT_M) or not _number_in(value.half_height, MIN_HALF_EXTENT_M, MAX_HALF_EXTENT_M):
			return _result("INVALID_GATE_EXTENT")
		# Remove accepted rounding error, never silently accept scale or shear.
		var basis: Basis = value.basis.orthonormalized()
		validated[value.checkpoint] = {
			"center": value.center, "right": basis.x, "up": basis.y,
			"forward": -basis.z, "half_width": float(value.half_width),
			"half_height": float(value.half_height),
		}
	_gates = validated
	_max_segment_m = float(max_segment_m)
	_armed.resize(_gates.size())
	_armed.fill(false)
	return _result()


## Call once per completed authoritative movement segment, in order.
## expected_checkpoint must agree with the previous result.next_expected.
## reset_or_teleport discards the ENTIRE segment and reanchors at current.
## Invalid points require a later explicitly marked reset; discontinuous or
## oversized finite segments are discarded and reanchored automatically.
func step(previous: Variant, current: Variant, expected_checkpoint: Variant, reset_or_teleport: Variant = false) -> Dictionary:
	if _gates.is_empty():
		return _result("NOT_CONFIGURED")
	if typeof(expected_checkpoint) != TYPE_INT or expected_checkpoint < 0 or expected_checkpoint >= _gates.size():
		return _result("INVALID_EXPECTED")
	if typeof(reset_or_teleport) != TYPE_BOOL:
		return _result("INVALID_RESET")
	if _next_expected >= 0 and expected_checkpoint != _next_expected:
		return _result("EXPECTED_MISMATCH")
	if not _position_valid(previous) or not _position_valid(current):
		_needs_reset = true
		_armed.fill(false)
		return _result("INVALID_POSITION")
	if _next_expected < 0:
		_next_expected = expected_checkpoint
	if reset_or_teleport:
		_reanchor(current)
		return _result("RESET")
	if _needs_reset:
		return _result("RESET_REQUIRED")
	# Exact continuity is intentional: reuse the preceding authoritative value.
	if _has_position and previous != _last_position:
		_reanchor(current)
		return _result("DISCONTINUITY")
	if _segment_length_squared(previous, current) > _max_segment_m * _max_segment_m:
		_reanchor(current)
		return _result("SEGMENT_TOO_LONG")
	var hits: Array = []
	for index in _gates.size():
		var gate: Dictionary = _gates[index]
		var d0 := _projection(previous, gate.center, gate.forward)
		var d1 := _projection(current, gate.center, gate.forward)
		if d0 <= -ARM_DISTANCE_M:
			_armed[index] = true
		# Arriving on the plane is not yet a crossing. Leaving the plane toward
		# +forward emits t=0 only if a prior behind-plane sample armed this gate.
		if d0 <= 0.0 and d1 > 0.0:
			if _armed[index]:
				var fraction := -d0 / (d1 - d0)
				var x := lerpf(_projection(previous, gate.center, gate.right), _projection(current, gate.center, gate.right), fraction)
				var y := lerpf(_projection(previous, gate.center, gate.up), _projection(current, gate.center, gate.up), fraction)
				# Closed aperture, no expanded acceptance epsilon outside the gate.
				if absf(x) <= gate.half_width and absf(y) <= gate.half_height:
					hits.append({"checkpoint": index, "fraction": clampf(fraction, 0.0, 1.0)})
			# Even an out-of-aperture/wrong-order crossing consumes this approach.
			_armed[index] = false
		if d1 <= -ARM_DISTANCE_M:
			_armed[index] = true
	# Strict total order: do not use an epsilon comparator (not transitive).
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.fraction == b.fraction:
			return a.checkpoint < b.checkpoint
		return a.fraction < b.fraction
	)
	var events: Array = []
	for hit in hits:
		if hit.checkpoint == _next_expected:
			events.append(hit)
			_next_expected = (_next_expected + 1) % _gates.size()
	_has_position = true
	_last_position = current
	var result := _result()
	result.events = events
	return result


func _reanchor(current: Vector3) -> void:
	_last_position = current
	_has_position = true
	_needs_reset = false
	_armed.fill(false)


func _result(code := "OK") -> Dictionary:
	return {"ok": code == "OK" or code == "RESET", "code": code,
		"events": [], "next_expected": _next_expected}


func _number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and value >= minimum and value <= maximum


func _position_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_VECTOR3 and value.is_finite() and absf(value.x) <= WORLD_LIMIT_M and absf(value.y) <= WORLD_LIMIT_M and absf(value.z) <= WORLD_LIMIT_M


func _basis_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_BASIS or not value.is_finite():
		return false
	return absf(value.x.length_squared() - 1.0) <= BASIS_TOLERANCE and absf(value.y.length_squared() - 1.0) <= BASIS_TOLERANCE and absf(value.z.length_squared() - 1.0) <= BASIS_TOLERANCE and absf(value.x.dot(value.y)) <= BASIS_TOLERANCE and absf(value.x.dot(value.z)) <= BASIS_TOLERANCE and absf(value.y.dot(value.z)) <= BASIS_TOLERANCE and absf(value.determinant() - 1.0) <= BASIS_TOLERANCE


## Scalar GDScript float arithmetic avoids Vector3 float32 intermediate dots
## and subtractions. Input Vector3 precision is still bounded by the engine.
func _projection(point: Vector3, center: Vector3, axis: Vector3) -> float:
	return (float(point.x) - float(center.x)) * float(axis.x) + (float(point.y) - float(center.y)) * float(axis.y) + (float(point.z) - float(center.z)) * float(axis.z)


func _segment_length_squared(a: Vector3, b: Vector3) -> float:
	var x := float(a.x) - float(b.x)
	var y := float(a.y) - float(b.y)
	var z := float(a.z) - float(b.z)
	return x * x + y * y + z * z
