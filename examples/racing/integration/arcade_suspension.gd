extends RefCounted
## Four visual springs only. Call once AFTER the vehicle's real physics move.
## Frozen initialization/reset samples once; ordinary frozen steps do no work.
const LIMITS := {
	"suspension_travel": Vector2(0.08, 0.30),
	"suspension_hz": Vector2(2.0, 6.0),
	"suspension_damping": Vector2(0.6, 1.2),
	"suspension_tilt_degrees": Vector2(0.0, 6.0),
}
const WHEEL_RADIUS := 0.34
const GROUND_MASK := 8
const MAX_BODY_OFFSET := 0.20
const MIN_GROUND_UP := 0.6427876097 # cos(50 degrees); walls never count.
const SPRING_SUBSTEP := 1.0 / 240.0
var values: Dictionary = {
	"suspension_travel": 0.18, "suspension_hz": 4.0,
	"suspension_damping": 0.9, "suspension_tilt_degrees": 4.0,
}
var _vehicle: CollisionObject3D
var _visual: Node3D
var _pivots: Array[Node3D] = []
var _queries: Array[PhysicsRayQueryParameters3D] = []
var _rest_visual := Transform3D.IDENTITY
var _rest_pivots: Array[Transform3D] = []
var _rest_centers: Array[Vector3] = [] # Vehicle coordinates, never lean coordinates.
var _offsets: Array[float] = []
var _speeds: Array[float] = []
var _targets: Array[float] = []
var _wheels: Array[Dictionary] = []
var _radii: Array[float] = []
var _body_offset := 0.0
var _needs_sample := true
var _last_step_frame := -1
var _last_query_frame := -1
var _ray_queries_this_tick := 0
var _total_ray_queries := 0
var _usec_total := 0
var _sample_steps := 0
var _finite := true
var _configured := false
var _tilt := Vector2.ZERO
var _tilt_speed := Vector2.ZERO

func configure(vehicle: Node3D) -> bool:
	# Restore before recapturing if the same instance is configured again.
	var requested_scale := _visual.scale if _configured and _vehicle == vehicle and is_instance_valid(_visual) else Vector3.ONE
	var preserve_scale := _configured and _vehicle == vehicle and is_instance_valid(_visual)
	reset()
	if preserve_scale: _visual.scale = requested_scale
	_configured = false
	_pivots.clear()
	_queries.clear()
	_rest_pivots.clear()
	_rest_centers.clear()
	_offsets.clear()
	_speeds.clear()
	_targets.clear()
	_wheels.clear()
	_radii.clear()
	_vehicle = vehicle as CollisionObject3D
	if not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return false
	_visual = _vehicle.get("visual_root") as Node3D
	var pivots: Variant = _vehicle.get("steer_pivots")
	if not is_instance_valid(_visual) or not pivots is Array or pivots.size() != 4:
		return false
	if not _usable_transform(_vehicle.global_transform) or not _usable_transform(_visual.global_transform):
		return false
	_rest_visual = _visual.transform
	var inverse := _vehicle.global_transform.affine_inverse()
	for candidate in pivots:
		var pivot := candidate as Node3D
		if not is_instance_valid(pivot) or not _visual.is_ancestor_of(pivot) or not pivot.get_parent() is Node3D:
			return false
		if not _usable_transform(pivot.global_transform):
			return false
		var rest_center: Vector3 = inverse * pivot.global_position
		if not rest_center.is_finite():
			return false
		_pivots.append(pivot)
		_rest_pivots.append(pivot.transform)
		_rest_centers.append(rest_center)
		_radii.append(WHEEL_RADIUS * _visual.global_basis.y.length())
		_offsets.append(0.0)
		_speeds.append(0.0)
		_targets.append(0.0)
		var query := PhysicsRayQueryParameters3D.new()
		query.collision_mask = GROUND_MASK
		query.exclude = [_vehicle.get_rid()]
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.hit_from_inside = false
		_queries.append(query)
	_configured = true
	_needs_sample = true
	_body_offset = 0.0
	_finite = true
	_total_ray_queries = 0
	_usec_total = 0
	_sample_steps = 0
	# Do not reset frame guards: reconfiguration in the same callback cannot
	# spend another four queries. Sampling will occur on the next physics step.
	return true

func reset() -> void:
	if _configured and is_instance_valid(_visual):
		_visual.transform = _rest_visual
		for i in range(_pivots.size()):
			if is_instance_valid(_pivots[i]):
				_pivots[i].transform = _rest_pivots[i]
			_offsets[i] = 0.0
			_speeds[i] = 0.0
			_targets[i] = 0.0
	_body_offset = 0.0
	_needs_sample = true
	_tilt = Vector2.ZERO
	_tilt_speed = Vector2.ZERO
	_wheels.clear()
	_ray_queries_this_tick = 0
	_finite = true

func set_value(key: String, value: float) -> bool:
	if not LIMITS.has(key) or not is_finite(value):
		return false
	var bounds: Vector2 = LIMITS[key]
	# Bounds use Vector2 float32 storage; decimal endpoints remain accepted.
	if value < float(bounds.x) - 0.0000001 or value > float(bounds.y) + 0.0000001:
		return false
	values[key] = clampf(value, bounds.x, bounds.y)
	_tilt_speed = Vector2.ZERO
	if key in ["suspension_travel", "suspension_hz", "suspension_damping"]:
		var travel := float(values.suspension_travel)
		for i in range(_offsets.size()):
			_offsets[i] = clampf(_offsets[i], -travel, travel)
			_targets[i] = clampf(_targets[i], -travel, travel)
			_speeds[i] = 0.0 # New stiffness/travel never releases stale momentum.
	return true

func step(dt: float, steer: float, pitch: float, roll: float, frozen: bool = false) -> Dictionary:
	_ray_queries_this_tick = 0
	_finite = true
	if not _configured or not is_instance_valid(_vehicle) or not is_instance_valid(_visual):
		_finite = false
		return snapshot()
	if not is_finite(dt) or dt <= 0.0 or not is_finite(steer) or not is_finite(pitch) or not is_finite(roll):
		_finite = false
		return snapshot()
	if not Engine.is_in_physics_frame():
		# Direct-space reads belong to a physics callback, not render callbacks.
		_finite = false
		return snapshot()
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame or (frozen and not _needs_sample):
		return snapshot()
	if not _usable_transform(_vehicle.global_transform):
		_finite = false
		return snapshot()
	for pivot in _pivots:
		if not is_instance_valid(pivot):
			_finite = false
			return snapshot()
		var parent := pivot.get_parent() as Node3D
		if not is_instance_valid(parent) or not _usable_transform(parent.global_transform):
			_finite = false
			return snapshot()
	for key in LIMITS:
		var limit: Vector2 = LIMITS[key]
		var value := float(values.get(key, NAN))
		if not is_finite(value) or value < limit.x - 0.0000001 or value > limit.y + 0.0000001:
			_finite = false
			return snapshot()
	if frame == _last_query_frame:
		return snapshot()
	_last_step_frame = frame
	_last_query_frame = frame
	var started := Time.get_ticks_usec()
	var pose := _vehicle.global_transform
	var travel := float(values.suspension_travel)
	var space := _vehicle.get_world_3d().direct_space_state
	var fit_sum := 0.0
	var fit_count := 0
	_wheels.clear()
	for i in range(4):
		var rest_center: Vector3 = pose * _rest_centers[i]
		# Reserve the body fit allowance even at the minimum travel, so the
		# present root Y=.145 cannot leave all four rays above the flat road.
		_queries[i].from = rest_center + Vector3.UP * (travel + MAX_BODY_OFFSET)
		_queries[i].to = rest_center - Vector3.UP * (_radii[i] + travel + MAX_BODY_OFFSET)
		var hit := space.intersect_ray(_queries[i])
		_ray_queries_this_tick += 1
		_total_ray_queries += 1
		var point := rest_center - Vector3.UP * _radii[i]
		var normal := Vector3.UP
		var grounded := false
		if not hit.is_empty():
			var hit_point: Vector3 = hit.position
			var hit_normal: Vector3 = hit.normal
			if hit_point.is_finite() and hit_normal.is_finite() and hit_normal.length_squared() > 0.5:
				hit_normal = hit_normal.normalized()
				if hit_normal.dot(Vector3.UP) >= MIN_GROUND_UP:
					point = hit_point
					normal = hit_normal
					grounded = true
					fit_sum += (point + Vector3.UP * _radii[i] - rest_center).y
					fit_count += 1
			else:
				_finite = false
		_wheels.append({"point": point, "normal": normal, "grounded": grounded, "center": rest_center})
	if _needs_sample and fit_count > 0:
		_body_offset = clampf(fit_sum / float(fit_count), -MAX_BODY_OFFSET, MAX_BODY_OFFSET)
	var initial := _needs_sample
	var bounded_dt := minf(dt, 0.25)
	for i in range(4):
		var neutral: Vector3 = pose * _rest_centers[i] + Vector3.UP * _body_offset
		_targets[i] = clampf((_wheels[i].point.y + _radii[i]) - neutral.y, -travel, travel) if _wheels[i].grounded else -travel
		if initial:
			_offsets[i] = _targets[i]
			_speeds[i] = 0.0
		elif not frozen:
			_integrate_spring(i, bounded_dt, travel)
	_needs_sample = false
	var tilt_limit := deg_to_rad(float(values.suspension_tilt_degrees))
	var tilt_target := Vector2(clampf(pitch, -tilt_limit, tilt_limit), clampf(roll, -tilt_limit, tilt_limit))
	if initial: _tilt = tilt_target
	elif not frozen: _integrate_tilt(tilt_target, bounded_dt, tilt_limit)
	_apply_visual(pose, clampf(steer, -1.0, 1.0), _tilt.x, _tilt.y)
	_usec_total += Time.get_ticks_usec() - started
	_sample_steps += 1
	return snapshot()

func _integrate_spring(index: int, dt: float, travel: float) -> void:
	# Damping is implicit. At <=1/240 s and <=6 Hz, this bounded semi-implicit
	# spring is stable across the allowed damping range, including dt spikes.
	var count := maxi(1, ceili(dt / SPRING_SUBSTEP))
	var h := dt / float(count)
	var omega := TAU * float(values.suspension_hz)
	var damping := 2.0 * float(values.suspension_damping) * omega
	for _substep in range(count):
		_speeds[index] = (_speeds[index] - omega * omega * (_offsets[index] - _targets[index]) * h) / (1.0 + damping * h)
		_speeds[index] = clampf(_speeds[index], -omega * travel, omega * travel)
		var next := _offsets[index] + _speeds[index] * h
		_offsets[index] = clampf(next, -travel, travel)
		if (next > travel and _speeds[index] > 0.0) or (next < -travel and _speeds[index] < 0.0):
			_speeds[index] = 0.0
	if not is_finite(_offsets[index]) or not is_finite(_speeds[index]):
		_offsets[index] = _targets[index]
		_speeds[index] = 0.0
		_finite = false

func _integrate_tilt(target: Vector2, dt: float, limit: float) -> void:
	var count := maxi(1, ceili(dt / SPRING_SUBSTEP))
	var h := dt / float(count)
	var omega := TAU * float(values.suspension_hz)
	var damping := 2.0 * float(values.suspension_damping) * omega
	for _i in range(count):
		_tilt_speed = (_tilt_speed - omega * omega * (_tilt - target) * h) / (1.0 + damping * h)
		_tilt_speed = _tilt_speed.limit_length(omega * limit)
		_tilt += _tilt_speed * h
		_tilt = Vector2(clampf(_tilt.x, -limit, limit), clampf(_tilt.y, -limit, limit))

func _apply_visual(pose: Transform3D, steer: float, pitch: float, roll: float) -> void:
	var tilt := deg_to_rad(float(values.suspension_tilt_degrees))
	var lean := Basis.from_euler(Vector3(clampf(pitch, -tilt, tilt), 0.0, clampf(roll, -tilt, tilt)))
	var model_pose := _rest_visual
	# Preserve the imported rest scale while rotating the visible shell.
	model_pose.basis = lean * _rest_visual.basis
	_visual.transform = model_pose
	_visual.global_position += Vector3.UP * _body_offset
	for i in range(4):
		var center: Vector3 = pose * _rest_centers[i] + Vector3.UP * (_body_offset + _offsets[i])
		var parent := _pivots[i].get_parent() as Node3D
		var pivot_pose := _rest_pivots[i]
		pivot_pose.basis = Basis(Vector3.UP, -steer * deg_to_rad(25.0) if i < 2 else 0.0) * pivot_pose.basis
		# Full affine inverse handles model/ancestor scale, translation and lean.
		pivot_pose.origin = parent.global_transform.affine_inverse() * center
		_pivots[i].transform = pivot_pose
		_wheels[i].center = _pivots[i].global_position
		_wheels[i]["offset"] = _offsets[i]
		_wheels[i]["target_offset"] = _targets[i]
		_wheels[i]["spring_speed"] = _speeds[i]
		_wheels[i]["radius"] = _radii[i]
		if not _wheels[i].grounded:
			_wheels[i].point = center - Vector3.UP * _radii[i]
		_finite = _finite and _pivots[i].global_position.is_finite() and _usable_transform(_pivots[i].global_transform)
	_finite = _finite and _usable_transform(_visual.global_transform)

func snapshot() -> Dictionary:
	var grounded := 0
	for wheel in _wheels:
		if wheel.grounded:
			grounded += 1
	return {"format": 1, "values": values.duplicate(true), "configured": _configured,
		"ray_queries_this_tick": _ray_queries_this_tick, "total_ray_queries": _total_ray_queries,
		"mean_usec": float(_usec_total) / float(_sample_steps) if _sample_steps > 0 else 0.0,
		"sample_steps": _sample_steps, "finite": _finite, "grounded_count": grounded,
		"body_offset": _body_offset, "needs_sample": _needs_sample, "wheels": _wheels.duplicate(true)}

func _usable_transform(pose: Transform3D) -> bool:
	return pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite() and is_finite(pose.basis.determinant()) and absf(pose.basis.determinant()) > 0.000001
