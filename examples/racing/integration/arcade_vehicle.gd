extends CharacterBody3D
## Planar arcade motion; model suspension/lean are visual only. Forward is -Z.
const ArcadeControl = preload("res://arcade_control.gd")
const Tuning = preload("res://arcade_tuning.gd")
const PLANE_Y := 0.145
const RADIUS := 0.86
const HALF_STRAIGHT := 1.10
const TOP_SPEED := 25.0
const BOOST_SPEED := 34.0
const REVERSE_SPEED := TOP_SPEED * 0.25
const ACCELERATION := 10.0
const BOOST_ACCELERATION := 16.0
const BRAKE_DECELERATION := 34.0
const WHEEL_RADIUS := 0.34
var control = ArcadeControl.new()
var tuning = Tuning.new()
var telemetry: Dictionary = {}
var held_left := false
var held_right := false
var paused := false
var driver_enabled := true
var passive_drag := 3.0
var visual_root: Node3D
var wheels: Array[Node3D] = []
var steer_pivots: Array[Node3D] = []
var body_collider: CollisionShape3D
var last_actual_velocity := Vector2.ZERO
var wheel_spin := 0.0
var visual_lean := 0.0
var visual_pitch := 0.0
var yaw_queries := 0
var rejected_yaws := 0
var wall_contacts := 0
var contacted_rail_shapes: Dictionary = {}
var physics_usec_total := 0
var physics_steps := 0

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	safe_margin = 0.015
	max_slides = 6
	collision_layer = 4
	collision_mask = 2 | 4
	body_collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = 2.0 * (RADIUS + HALF_STRAIGHT)
	body_collider.shape = capsule
	body_collider.position.y = 0.52
	body_collider.rotation.x = PI * 0.5
	add_child(body_collider)
	visual_root = (load("res://models/street_car_v2.glb") as PackedScene).instantiate()
	add_child(visual_root)
	for suffix in ["Front_Left", "Front_Right", "Rear_Left", "Rear_Right"]:
		steer_pivots.append(visual_root.find_child("Steer_" + suffix, true, false) as Node3D)
		wheels.append(visual_root.find_child("Wheel_" + suffix, true, false) as Node3D)
		assert(wheels[-1] != null and steer_pivots[-1] != null)
	control.reset()

func set_buttons(left: bool, right: bool) -> void:
	held_left = left
	held_right = right

func request_nitro() -> bool:
	# Input is applied before the next physics tick; check the latest completed
	# movement here as well, rather than the control's previous observation.
	var heading := Vector2(-global_basis.z.x, -global_basis.z.z).normalized()
	if paused or not last_actual_velocity.is_finite() or last_actual_velocity.dot(heading) < -ArcadeControl.SPEED_EPSILON:
		return false
	return control.request_nitro(held_left, held_right)

func request_reset(pose: Transform3D) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, pose.basis.get_euler().y), Vector3(pose.origin.x, PLANE_Y, pose.origin.z))
	velocity = Vector3.ZERO
	last_actual_velocity = Vector2.ZERO
	held_left = false
	held_right = false
	wheel_spin = 0.0
	visual_lean = 0.0
	visual_pitch = 0.0
	control.reset()
	telemetry = {}
	contacted_rail_shapes.clear()
	reset_physics_interpolation()

func _physics_process(dt: float) -> void:
	if paused:
		return
	var started := Time.get_ticks_usec()
	var rejected_before := rejected_yaws
	var forward3 := -global_basis.z
	var forward := Vector2(forward3.x, forward3.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var motion := Vector2(velocity.x, velocity.z)
	var state: Dictionary = control.step(dt, held_left, held_right, last_actual_velocity, forward)
	var longitudinal := motion.dot(forward)
	var lateral := motion.dot(right)
	if driver_enabled:
		var steer: float = state.steer
		_try_yaw(-steer * tuning.yaw_rate(longitudinal) * dt)
		# Heading changes first; keep world momentum, then gradually remove sideslip.
		forward3 = -global_basis.z
		forward = Vector2(forward3.x, forward3.z).normalized()
		right = Vector2(-forward.y, forward.x)
		longitudinal = motion.dot(forward)
		lateral = motion.dot(right)
		lateral *= tuning.lateral_multiplier(steer != 0.0 and longitudinal > 6.0, dt)
		if state.mode == "brake":
			# Existing boost still applies its forward drive; brakes dominate it.
			longitudinal += BOOST_ACCELERATION * float(state.boost_fraction) * dt
			longitudinal = move_toward(longitudinal, 0.0, BRAKE_DECELERATION * dt)
			lateral = move_toward(lateral, 0.0, BRAKE_DECELERATION * dt)
		elif state.mode == "reverse":
			longitudinal = move_toward(longitudinal, -float(tuning.values.top_speed) * 0.25, float(tuning.values.acceleration) * dt)
		else:
			var cap: float = BOOST_SPEED if float(state.boost_fraction) > 0.0 else tuning.values.top_speed
			# Releasing both keys while reversing first decelerates into forward drive.
			var engine: float = float(tuning.values.acceleration) + BOOST_ACCELERATION * float(state.boost_fraction)
			longitudinal = move_toward(longitudinal, cap, engine * dt)
		motion = forward * longitudinal + right * lateral
		motion = motion.limit_length(BOOST_SPEED if float(state.boost_fraction) > 0.0 else float(tuning.values.top_speed))
		if state.mode == "reverse":
			motion = motion.limit_length(float(tuning.values.top_speed) * 0.25)
	else:
		motion *= exp(-passive_drag * dt)
	velocity = Vector3(motion.x, 0.0, motion.y)
	var incoming := velocity
	move_and_slide() # Exactly one engine sweep per real physics tick.
	for i in range(get_slide_collision_count()):
		var hit := get_slide_collision(i)
		if hit.get_collider() != null and hit.get_collider().name == "ContinuousGuardrails":
			contacted_rail_shapes[hit.get_collider_shape_index()] = true
		var normal := hit.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 0.01:
			continue
		normal = normal.normalized()
		if incoming.dot(normal) < -0.05:
			velocity = incoming.slide(normal) * 0.82
			incoming = velocity
			wall_contacts += 1
			var peer = hit.get_collider()
			if peer is CharacterBody3D and peer.has_method("receive_push"):
				peer.receive_push(-normal * minf(3.0, motion.length() * 0.15))
	global_position.y = PLANE_Y
	velocity.y = 0.0
	var real := get_real_velocity()
	last_actual_velocity = Vector2(real.x, real.z)
	wheel_spin -= last_actual_velocity.dot(forward) * dt / WHEEL_RADIUS
	visual_lean = lerpf(visual_lean, -float(state.steer) * clampf(motion.length() / TOP_SPEED, 0.0, 1.0) * 0.08, 1.0 - exp(-9.0 * dt))
	visual_pitch = lerpf(visual_pitch, 0.035 if state.mode == "brake" else (-0.025 if state.boost_active else 0.0), 1.0 - exp(-8.0 * dt))
	_sync_visual(float(state.steer))
	physics_usec_total += Time.get_ticks_usec() - started
	physics_steps += 1
	telemetry = {"mode": state.mode, "speed": last_actual_velocity.length(), "forward_speed": last_actual_velocity.dot(forward),
		"lateral_speed": last_actual_velocity.dot(right), "tuning": tuning.snapshot(),
		"yaw_blocked_this_tick": rejected_yaws > rejected_before,
		"fuel": state.fuel, "boost_active": state.boost_active, "boost_remaining": state.boost_remaining,
		"drifting": state.drifting, "slip_degrees": rad_to_deg(atan2(last_actual_velocity.dot(right), maxf(absf(last_actual_velocity.dot(forward)), 0.01))),
		"yaw_queries": yaw_queries, "rejected_yaws": rejected_yaws, "wall_contacts": wall_contacts,
		"physics_steps": physics_steps, "mean_script_usec": float(physics_usec_total) / physics_steps,
		"suspension_ray_queries": 0}

func _try_yaw(amount: float) -> void:
	if absf(amount) < 0.000001:
		return
	var count := maxi(1, ceili(absf(amount) / deg_to_rad(2.0)))
	var step := amount / count
	for _i in range(count):
		var before := global_transform
		var after := Transform3D(Basis(Vector3.UP, step) * before.basis, before.origin)
		var blocked := false
		# Conservative translation envelopes cover both capsule ends and its middle.
		for local_end in [Vector3(0, 0.52, HALF_STRAIGHT), Vector3(0, 0.52, -HALF_STRAIGHT)]:
			yaw_queries += 1
			if test_move(before, after * local_end - before * local_end, null, 0.003, false):
				blocked = true
				break
		if not blocked:
			yaw_queries += 1
			blocked = test_move(after, Vector3.ZERO, null, 0.003, true)
		if blocked:
			rejected_yaws += 1
			break
		global_transform = after

func receive_push(push: Vector3) -> void:
	if push.is_finite():
		velocity = (velocity + Vector3(push.x, 0.0, push.z)).limit_length(float(tuning.values.top_speed))

func _sync_visual(steer: float) -> void:
	visual_root.rotation = Vector3(visual_pitch, 0.0, visual_lean)
	for i in range(4):
		steer_pivots[i].rotation.y = -steer * deg_to_rad(25.0) if i < 2 else 0.0
		wheels[i].rotation.x = wheel_spin
