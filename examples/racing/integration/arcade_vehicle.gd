extends CharacterBody3D
## Planar arcade motion; model suspension/lean are visual only. Forward is -Z.
const ArcadeControl = preload("res://arcade_control.gd")
const Tuning = preload("res://arcade_tuning.gd")
const PLANE_Y := 0.145
const RADIUS := 0.86
const HALF_STRAIGHT := 1.10
const TOP_SPEED := 25.0
const BRAKE_DECELERATION := 34.0
const BOOST_MIN_BRAKE_MARGIN := 18.0
const BOOST_RECOVERY_DECELERATION := 20.0
const YAW_CONTACT_PADDING := 0.04
const WALL_RELEASE_MAX_SPEED := 6.0
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
var yaw_shape := ConvexPolygonShape3D.new()
var yaw_ring: Array[Vector2] = []
var wall_release_contacts: Array[Dictionary] = []

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
	for i in range(32):
		yaw_ring.append(Vector2(cos(TAU * i / 32.0), sin(TAU * i / 32.0)))
	yaw_shape.margin = 0.0
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
	wall_release_contacts.clear()
	reset_physics_interpolation()

func _physics_process(dt: float) -> void:
	if paused:
		return
	var started := Time.get_ticks_usec()
	for i in range(wall_release_contacts.size() - 1, -1, -1):
		wall_release_contacts[i].remaining = float(wall_release_contacts[i].remaining) - dt
		if float(wall_release_contacts[i].remaining) <= 0.0 or not is_instance_valid(wall_release_contacts[i].body):
			wall_release_contacts.remove_at(i)
	var rejected_before := rejected_yaws
	var forward3 := -global_basis.z
	var forward := Vector2(forward3.x, forward3.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var motion := Vector2(velocity.x, velocity.z)
	var state: Dictionary = control.step(dt, held_left, held_right, last_actual_velocity, forward)
	var longitudinal := motion.dot(forward)
	var lateral := motion.dot(right)
	var boost_acceleration: float = float(tuning.values.nitro_extra_acceleration) * float(state.boost_fraction)
	var normal_cap: float = tuning.values.top_speed
	var boost_cap: float = tuning.nitro_speed()
	# Once spray expires, spend only speed already present. No stored high cap
	# remains for the engine to accelerate back toward after ordinary recovery.
	var speed_limit := boost_cap if float(state.boost_fraction) > 0.0 else maxf(normal_cap, minf(boost_cap, motion.length()) - BOOST_RECOVERY_DECELERATION * dt)
	var release_motion := Vector2.ZERO
	if driver_enabled:
		var steer: float = state.steer
		var requested_yaw := -steer * tuning.yaw_rate(longitudinal) * dt
		_try_yaw(requested_yaw)
		# A capsule against a wall cannot rotate around its center without its
		# tail briefly sweeping into that wall. Only a turn toward the open side
		# may request a small outward movement for this engine sweep. Its resolved
		# world momentum is retained, just like normal driving motion. This is
		# collision-tested motion, not a teleport or ignoring the touched wall.
		if rejected_yaws > rejected_before and steer != 0.0:
			var wanted_heading := forward3.rotated(Vector3.UP, requested_yaw)
			for contact in wall_release_contacts:
				var normal: Vector3 = contact.normal
				if wanted_heading.dot(normal) > forward3.dot(normal) + 0.00001:
					var old_extent := RADIUS + HALF_STRAIGHT * absf(forward3.dot(normal))
					var new_extent := RADIUS + HALF_STRAIGHT * absf(wanted_heading.dot(normal))
					var room := clampf(new_extent - old_extent + 0.03, 0.03, 0.10)
					release_motion += Vector2(normal.x, normal.z) * minf(room / dt, WALL_RELEASE_MAX_SPEED)
		# Heading changes first; keep world momentum, then gradually remove sideslip.
		forward3 = -global_basis.z
		forward = Vector2(forward3.x, forward3.z).normalized()
		right = Vector2(-forward.y, forward.x)
		longitudinal = motion.dot(forward)
		lateral = motion.dot(right)
		lateral *= tuning.lateral_multiplier(steer != 0.0 and longitudinal > 6.0, dt)
		if state.mode == "brake":
			# Existing boost still applies its forward drive; brakes dominate it.
			longitudinal += boost_acceleration * dt
			var brake_rate := maxf(BRAKE_DECELERATION, boost_acceleration + BOOST_MIN_BRAKE_MARGIN)
			longitudinal = move_toward(longitudinal, 0.0, brake_rate * dt)
			lateral = move_toward(lateral, 0.0, BRAKE_DECELERATION * dt)
		elif state.mode == "reverse":
			longitudinal = move_toward(longitudinal, -float(tuning.values.top_speed) * 0.25, float(tuning.values.acceleration) * dt)
		else:
			# Releasing both keys while reversing first decelerates into forward drive.
			var engine: float = float(tuning.values.acceleration) + boost_acceleration
			longitudinal = move_toward(longitudinal, speed_limit, engine * dt)
		motion = forward * longitudinal + right * lateral
		motion = motion.limit_length(speed_limit)
		if state.mode == "reverse":
			motion = motion.limit_length(float(tuning.values.top_speed) * 0.25)
	else:
		motion *= exp(-passive_drag * dt)
	if release_motion.length_squared() > 0.0:
		release_motion = release_motion.limit_length(minf(0.10 / dt, WALL_RELEASE_MAX_SPEED))
		var outward := release_motion.normalized()
		motion += outward * maxf(0.0, release_motion.length() - motion.dot(outward))
		motion = motion.limit_length(speed_limit)
	velocity = Vector3(motion.x, 0.0, motion.y)
	var incoming := velocity
	move_and_slide() # Exactly one engine sweep per real physics tick.
	var has_wall_contact := false
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
			# Keep the engine's velocity after all slide planes have been resolved.
			# Apply wall friction once per tick below, never once per collision.
			has_wall_contact = true
			if hit.get_collider() is StaticBody3D:
				var duplicate := false
				for previous in wall_release_contacts:
					if previous.body == hit.get_collider() and (previous.normal as Vector3).dot(normal) > 0.995:
						previous.remaining = 0.12
						duplicate = true
				if not duplicate: wall_release_contacts.append({"body": hit.get_collider(), "normal": normal, "remaining": 0.12})
			wall_contacts += 1
			var peer = hit.get_collider()
			if peer is CharacterBody3D and peer.has_method("receive_push"):
				peer.receive_push(-normal * minf(3.0, motion.length() * 0.15))
	var wall_friction_applications := 0
	if has_wall_contact:
		velocity *= exp(-float(tuning.values.wall_slide_drag) * dt)
		wall_friction_applications = 1
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
		"nitro_top_speed": boost_cap, "nitro_extra_acceleration": tuning.values.nitro_extra_acceleration,
		"speed_limit": speed_limit, "wall_friction_applications": wall_friction_applications,
		"wall_release_motion_mps": release_motion.length(),
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
		var blocked := not _yaw_envelope_clear(before, after, step)
		if blocked:
			rejected_yaws += 1
			break
		global_transform = after

func _yaw_envelope_clear(before: Transform3D, after: Transform3D, angle: float) -> bool:
	# Convex hull of both endpoint pairs, inflated by the endpoint arc's sagitta,
	# covers every intermediate centerline. A circumscribed 32-gon covers its
	# radius; the Y prism conservatively encloses the horizontal capsule.
	# Unlike translating the entire car by one endpoint's displacement, this
	# permits rotations whose actual swept volume moves away from a wall.
	# Extra clearance prevents query/contact tolerance from admitting a yaw
	# which the actual swept capsule would otherwise resolve too deeply.
	var radius := (RADIUS + YAW_CONTACT_PADDING + HALF_STRAIGHT * (1.0 - cos(absf(angle) * 0.5))) / cos(PI / 32.0)
	var outline := PackedVector2Array()
	for orientation in [before.basis, after.basis]:
		for end in [-HALF_STRAIGHT, HALF_STRAIGHT]:
			var center: Vector3 = orientation * Vector3(0, 0.52, end)
			for direction in yaw_ring:
				outline.append(Vector2(center.x, center.z) + direction * radius)
	var hull := Geometry2D.convex_hull(outline)
	var vertices := PackedVector3Array()
	for point in hull:
		vertices.append(Vector3(point.x, 0.52 - RADIUS, point.y))
		vertices.append(Vector3(point.x, 0.52 + RADIUS, point.y))
	yaw_shape.points = vertices
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = yaw_shape
	query.transform = Transform3D(Basis.IDENTITY, before.origin)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.003
	yaw_queries += 1
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func receive_push(push: Vector3) -> void:
	if push.is_finite():
		velocity = (velocity + Vector3(push.x, 0.0, push.z)).limit_length(float(tuning.values.top_speed))

func _sync_visual(steer: float) -> void:
	visual_root.rotation = Vector3(visual_pitch, 0.0, visual_lean)
	for i in range(4):
		steer_pivots[i].rotation.y = -steer * deg_to_rad(25.0) if i < 2 else 0.0
		wheels[i].rotation.x = wheel_spin
