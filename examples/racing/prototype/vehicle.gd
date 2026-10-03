extends RigidBody3D
## Offline single-body force vehicle. Units: m, kg, s, N. Forward is -Z.
## Only request_reset can replace velocities or the body's transform.

const WHEEL_MOUNTS := [Vector3(-0.85, 0, -1.25), Vector3(0.85, 0, -1.25), Vector3(-0.85, 0, 1.25), Vector3(0.85, 0, 1.25)]
const WHEEL_NAMES := ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
const RADIUS := 0.30
const REST_LENGTH := 0.45
const TRAVEL := 0.30
const SPRING := 24525.0
const DAMPER := 4339.9539
const MAX_SUPPORT := 11772.0
const SETTINGS := {"rear_grip": Vector3(6, 14, 10), "drift_mu": Vector3(0.35, 0.9, 0.85), "recovery_half_life": Vector3(0.12, 0.6, 0.25)}

var wheel_mounts: Array[Vector3] = [Vector3(-0.85, 0, -1.25), Vector3(0.85, 0, -1.25), Vector3(-0.85, 0, 1.25), Vector3(0.85, 0, 1.25)]
var wheel_radius := RADIUS
var low_speed_steer_degrees := 30.0
var settings: Dictionary = {}
var command := {"throttle": 0.0, "steer": 0.0, "brake": 0.0, "drift": false}
var telemetry: Dictionary = {}
var wheel_visuals: Array[Node3D] = []
var _steer_angle := 0.0
var _drift_blend := 0.0
var _gear := 1
var _shift_still_time := 0.0
var _reset_pending := true
var _reset_pose := Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 10))
var _tick := 0
var _wheel_spin := 0.0


func _ready() -> void:
	mass = 1200.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.15, 0)
	custom_integrator = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = true
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.55, 3.9)
	shape.shape = box
	shape.position.y = 0.15
	add_child(shape)
	var contact_material := PhysicsMaterial.new()
	contact_material.friction = 0.35
	contact_material.bounce = 0.0
	physics_material_override = contact_material
	reset_settings()
	_build_placeholder()


func reset_settings() -> void:
	for key in SETTINGS:
		settings[key] = SETTINGS[key].z


func set_setting(key: String, value: float) -> void:
	if SETTINGS.has(key) and is_finite(value):
		settings[key] = clampf(value, SETTINGS[key].x, SETTINGS[key].y)


func set_command(throttle: float, steer: float, brake: float, drift: bool) -> void:
	command = {"throttle": clampf(throttle, -1, 1), "steer": clampf(steer, -1, 1), "brake": clampf(brake, 0, 1), "drift": drift}


func request_reset(pose: Transform3D) -> void:
	_reset_pose = pose
	_reset_pending = true
	set_command(0, 0, 0, false)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_tick += 1
	if _reset_pending:
		state.transform = _reset_pose
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_steer_angle = 0
		_drift_blend = 0
		_gear = 1
		_shift_still_time = 0
		_wheel_spin = 0
		_reset_pending = false
		telemetry = {"tick": _tick, "reset": true, "wheels": [], "pose": state.transform, "speed": 0.0, "forward_speed": 0.0}
		# Synchronize the visual node before clearing interpolation history.
		global_transform = state.transform
		reset_physics_interpolation()
		return
	var dt := state.step
	var pose := state.transform
	var up := pose.basis.y.normalized()
	var forward := -pose.basis.z.normalized()
	var right := pose.basis.x.normalized()
	var forward_speed := state.linear_velocity.dot(forward)
	var side_speed := state.linear_velocity.dot(right)
	var speed := state.linear_velocity.length()
	var max_steer := deg_to_rad(lerpf(low_speed_steer_degrees, 12.0, clampf(absf(forward_speed) / 25.0, 0, 1)))
	_steer_angle = move_toward(_steer_angle, -float(command.steer) * max_steer, deg_to_rad(90.0) * dt)
	var desired_gear := -1 if float(command.throttle) < 0 else 1
	var throttle := absf(float(command.throttle))
	var brake: float = command.brake
	if throttle > 0.01 and desired_gear != _gear:
		brake = 1.0
		if state.linear_velocity.slide(Vector3.UP).length() < 0.15:
			_shift_still_time += dt
		else:
			_shift_still_time = 0
		if _shift_still_time >= 0.12:
			_gear = desired_gear
			_shift_still_time = 0
		throttle = 0
	else:
		_shift_still_time = 0
	if throttle > 0 and forward_speed * _gear < -0.3:
		brake = 1.0
	if brake > 0.01:
		throttle = 0
	var hits: Array = []
	var rear_grounded := false
	var space := state.get_space_state()
	for index in range(4):
		var origin: Vector3 = pose * wheel_mounts[index]
		var query := PhysicsRayQueryParameters3D.create(origin, origin - up * (REST_LENGTH + wheel_radius), 1, [get_rid()])
		query.collide_with_areas = false
		query.hit_from_inside = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			if normal.length_squared() < 0.5 or normal.dot(Vector3.UP) < cos(deg_to_rad(50)) or normal.dot(up) <= 0.25:
				hit = {}
		hits.append(hit)
		if index >= 2 and not hit.is_empty():
			rear_grounded = true
	var drift_target := 1.0 if bool(command.drift) and absf(forward_speed) >= 6.0 and rear_grounded else 0.0
	var half_life := 0.12 if drift_target > _drift_blend else float(settings.recovery_half_life)
	_drift_blend = lerpf(_drift_blend, drift_target, 1.0 - exp(-log(2.0) * dt / half_life))
	var wheels: Array = []
	var grounded := 0
	var support_sum := 0.0
	var point_velocity_error := 0.0
	var max_friction_ratio := 0.0
	for index in range(4):
		var origin: Vector3 = pose * wheel_mounts[index]
		var hit: Dictionary = hits[index]
		var wheel := {"origin": origin, "point": origin - up * (REST_LENGTH + wheel_radius), "normal": Vector3.ZERO, "grounded": false, "length": REST_LENGTH, "compression": 0.0, "support": 0.0, "tire_force": Vector3.ZERO, "requested_tire_force": Vector3.ZERO, "suspension_force": Vector3.ZERO, "limit": 0.0}
		if not hit.is_empty():
			grounded += 1
			var point: Vector3 = hit.position
			var normal: Vector3 = hit.normal
			var length := origin.distance_to(point) - wheel_radius
			var compression := clampf(REST_LENGTH - length, 0, TRAVEL)
			var mount_velocity := state.get_velocity_at_local_position(origin - pose.origin)
			var support := clampf(SPRING * compression - DAMPER * mount_velocity.dot(up), 0, MAX_SUPPORT)
			state.apply_force(up * support, origin - pose.origin)
			var tire_forward := forward.rotated(up, _steer_angle if index < 2 else 0.0)
			tire_forward = tire_forward.slide(normal).normalized()
			var tire_right := tire_forward.cross(normal).normalized()
			var contact_velocity := state.get_velocity_at_local_position(point - pose.origin)
			var theoretical := state.linear_velocity + state.angular_velocity.cross(point - pose.origin - state.center_of_mass)
			point_velocity_error = maxf(point_velocity_error, contact_velocity.distance_to(theoretical))
			var longitudinal := contact_velocity.dot(tire_forward)
			var lateral := contact_velocity.dot(tire_right)
			var grip := 10.0 if index < 2 else lerpf(float(settings.rear_grip), 4.0, _drift_blend)
			var mu := 1.2 if index < 2 else lerpf(1.2, float(settings.drift_mu), _drift_blend)
			var lateral_force := -mass * 0.25 * lateral * (1 - exp(-grip * dt)) / dt
			var top_speed := 25.0 if _gear > 0 else 6.0
			var taper := maxf(0, 1 - pow(maxf(0, longitudinal * _gear) / top_speed, 2))
			var engine_force := throttle * _gear * 2250.0 * taper if index >= 2 else 0.0
			var stopping_force := minf(brake * 2000.0 + 45.0, mass * 0.25 * absf(longitudinal) / dt)
			var longitudinal_force := engine_force - signf(longitudinal) * stopping_force
			var requested := tire_right * lateral_force + tire_forward * longitudinal_force
			var limit := mu * support * maxf(0, up.dot(normal))
			var force := requested.limit_length(limit)
			state.apply_force(force, point - pose.origin)
			if limit > 0.001:
				max_friction_ratio = maxf(max_friction_ratio, force.length() / limit)
			support_sum += support
			wheel.merge({"point": point, "normal": normal, "grounded": true, "length": clampf(length, REST_LENGTH - TRAVEL, REST_LENGTH), "compression": compression, "support": support, "suspension_force": up * support, "tire_force": force, "requested_tire_force": requested, "limit": limit}, true)
		wheels.append(wheel)
	# Small aerodynamic drag is separate from tire friction; no velocity overwrite.
	state.apply_central_force(-state.linear_velocity * speed * 0.35)
	_wheel_spin += forward_speed * dt / wheel_radius
	telemetry = {"tick": _tick, "reset": false, "dt": dt, "pose": pose, "velocity": state.linear_velocity, "angular_velocity": state.angular_velocity, "com": pose.origin + state.center_of_mass, "speed": speed, "forward_speed": forward_speed, "side_speed": side_speed, "slip_degrees": rad_to_deg(atan2(side_speed, absf(forward_speed))) if speed >= 2 else 0.0, "steer_degrees": rad_to_deg(_steer_angle), "drift_blend": _drift_blend, "gear": _gear, "brake": brake, "drive": throttle * _gear, "grounded": grounded, "support_sum": support_sum, "wheels": wheels, "point_velocity_error": point_velocity_error, "friction_ratio": max_friction_ratio}


func _physics_process(_delta: float) -> void:
	if telemetry.is_empty() or telemetry.wheels.size() != 4:
		return
	for index in range(4):
		var pivot := wheel_visuals[index]
		pivot.position = wheel_mounts[index] - Vector3.UP * float(telemetry.wheels[index].length)
		pivot.rotation.y = _steer_angle if index < 2 else 0.0
		pivot.get_child(0).rotation.x = _wheel_spin


func _build_placeholder() -> void:
	_box_mesh("Body", Vector3(1.8, 0.55, 3.9), Vector3(0, 0.15, 0), Color("eb8d42"))
	_box_mesh("Cabin", Vector3(1.4, 0.45, 1.5), Vector3(0, 0.64, 0.2), Color("24384d"))
	_box_mesh("HoodStripe", Vector3(0.18, 0.02, 1.0), Vector3(0, 0.44, -1.25), Color("fff1ce"))
	for index in range(4):
		var pivot := Node3D.new()
		pivot.name = WHEEL_NAMES[index]
		add_child(pivot)
		wheel_visuals.append(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = RADIUS
		cylinder.bottom_radius = RADIUS
		cylinder.height = 0.24
		cylinder.radial_segments = 12
		mesh.mesh = cylinder
		mesh.rotation.z = PI / 2
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("17242f")
		mesh.material_override = material
		spin.add_child(mesh)


func _box_mesh(label: String, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
