extends Node
## Executed by arcade_main in an isolated evidence directory supplied by launch.
## All motion samples follow actual physics ticks. Input injection is not a phone test.
var lab
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var measurements: Dictionary = {}
var frame_times: Array[float] = []
var measuring_frames := false
var rails: Array[CollisionShape3D] = []
var rail_indices: Dictionary = {}
var rail_shape_indices: Dictionary = {}
var rail_sample: Dictionary = {}
const PLANE_Y := 0.145
const RADIUS := 0.86
const HALF_STRAIGHT := 1.10
const PENETRATION_GATE := 0.05
const EMPTY_ORIGIN := Vector3(220.0, PLANE_Y, 0.0)

func _ready() -> void:
	process_physics_priority = 100
	run.call_deferred()

func _physics_process(_dt: float) -> void:
	if rail_sample.is_empty():
		return
	# Runs after Vehicle's priority 0 callback, including every engine substep.
	var measured: Dictionary = rail_sample.measured
	rail_sample.max_depth = maxf(float(rail_sample.max_depth), _nearby_depth(lab.car, measured))
	rail_sample.finite = bool(rail_sample.finite) and _valid_car()
	var normal: Vector3 = rail_sample.outward
	var face: Vector3 = rail_sample.face
	# Sliding around a bend can cross the initial rail's infinite plane after
	# passing its finite end. Only crossing alongside that actual box is escape.
	var target: CollisionShape3D = rail_sample.target
	var local: Vector3 = target.global_transform.affine_inverse() * lab.car.global_position
	var target_half: Vector3 = (target.shape as BoxShape3D).size * 0.5
	var alongside := absf(local.z) < target_half.z
	rail_sample.escaped = bool(rail_sample.escaped) or (alongside and normal.dot(lab.car.global_position - face) > float(rail_sample.wall_width) + PENETRATION_GATE)
	if int(rail_sample.contact_tick) < 0 and not lab.car.contacted_rail_shapes.is_empty():
		rail_sample.contact_tick = int(rail_sample.ticks)
		rail_sample.pre_contact_speed = float(rail_sample.previous_speed)
	rail_sample.previous_speed = float(lab.car.velocity.length())
	rail_sample.ticks = int(rail_sample.ticks) + 1

func _process(dt: float) -> void:
	if measuring_frames:
		frame_times.append(dt)

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "ok": ok, "detail": detail})
	if ok:
		passed += 1
	else:
		failed += 1
		print("ARCADE_FAILED ", label, " ", str(detail))

func tick() -> void:
	await get_tree().physics_frame
	# physics_frame precedes node callbacks; process_frame samples their completed sweep.
	await get_tree().process_frame

func ticks(count: int) -> void:
	for _i in range(count):
		await tick()

func seconds(duration: float) -> void:
	# Render FPS can be below physics Hz: count actual engine steps, not the
	# number of coroutine resumptions which may skip several substeps.
	var end_step := Engine.get_physics_frames() + ceili(duration * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < end_step:
		await tick()

func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	lab._input(event)

func buttons(left: bool, right: bool) -> void:
	_key(KEY_A, left)
	_key(KEY_D, right)
	lab.apply_controls()

func nitro_edge() -> void:
	_key(KEY_SPACE, true)
	lab.apply_controls()
	_key(KEY_SPACE, false)
	lab.apply_controls()

func _touch(index: int, kind: String, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = down
	var widget: Control = lab.controls[kind]
	event.position = widget.get_global_rect().get_center()
	lab._input(event)

func reset_at(origin: Vector3 = EMPTY_ORIGIN, forward: Vector3 = Vector3.FORWARD) -> void:
	lab.held.clear()
	lab.pointers.clear()
	lab.nitro_edge = false
	lab.nitro_requests = 0
	lab.car.paused = false
	lab.car.driver_enabled = true
	lab.car.passive_drag = 3.0
	lab.car.request_reset(Transform3D(Basis.looking_at(forward, Vector3.UP), origin))
	lab.apply_controls()

func inject_velocity(motion: Vector3) -> void:
	lab.car.velocity = motion
	lab.car.last_actual_velocity = Vector2(motion.x, motion.z)

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _telemetry() -> Dictionary:
	return lab.car.telemetry.duplicate(true)

func run() -> void:
	print("ARCADE_PHASE start ", lab.test_mode)
	measurements.physics_hz = Engine.physics_ticks_per_second
	check("real physics configured at 60 Hz", Engine.physics_ticks_per_second == 60)
	var unit_script: Script = load("res://arcade_control_test.gd")
	check("pure control test script available", unit_script != null and unit_script.can_instantiate())
	if unit_script != null and unit_script.can_instantiate():
		var suite: Node = unit_script.new()
		var pure: Dictionary = suite.call("run")
		measurements.pure_logic = pure.duplicate(true)
		for item in pure.get("checks", []):
			check("logic: " + str(item.get("name", "unnamed")), bool(item.get("ok", false)), item.get("detail"))
		suite.free()
	print("ARCADE_PHASE pure_complete")
	await tick()
	print("ARCADE_PHASE first_tick")
	await tuning_run()
	await player_run()
	if lab.test_mode == "physics":
		await player_wall_run()
	lab.car.tuning.use_preset("original")
	lab.tuning_panel._sync()
	reset_at()
	if lab.test_mode == "render":
		await render_run()
	elif lab.test_mode == "physics":
		measurement_controls()
		await driving_run()
		await touch_run()
		_collect_rails()
		await rail_run()
		await thin_pole_run()
		await yaw_and_escape_run()
		await push_run()
	else:
		check("supported test mode", false, lab.test_mode)
	finish()

func tuning_run() -> void:
	var tuning = lab.car.tuning
	var saved: Dictionary = tuning.snapshot()
	# Scalar normalization check: five source ticks and six target ticks must
	# yield the same retention over 100 ms, including the user's 0.2 case.
	for keep in [0.2, 0.95, 1.0, 0.0]:
		tuning.set_value("lateral_keep_turn", keep)
		check("retention time equivalence " + str(keep), absf(pow(tuning.lateral_multiplier(true, 0.02), 5) - pow(tuning.lateral_multiplier(true, 1.0 / 60.0), 6)) < 0.000001)
	check("invalid tuning values rejected", not tuning.set_value("turn_degrees", NAN) and not tuning.set_value("lateral_keep_turn", -0.1) and not tuning.set_value("top_speed", 35) and not tuning.set_value("unknown", 10))
	tuning.use_preset("original")
	check("old grip/yaw model preserved", absf(tuning.lateral_multiplier(true, 1.0 / 60.0) - exp(-2.8 / 60.0)) < 0.000001 and absf(tuning.yaw_rate(25) - 1.22) < 0.000001)
	# UI paths call the same live model; they must not reset velocity or fuel.
	reset_at()
	await seconds(1.0)
	var before_velocity: Vector3 = lab.car.velocity
	var before_fuel: float = lab.car.control._fuel
	lab.tuning_panel._preset("reference")
	check("preset is live without resetting motion/fuel", lab.car.velocity == before_velocity and lab.car.control._fuel == before_fuel and tuning.profile == "reference")
	var ui_value: float = 0.2
	lab.tuning_panel.sliders.lateral_keep_turn.value = ui_value
	check("slider updates actual physics setting", absf(float(tuning.values.lateral_keep_turn) - ui_value) < 0.000001)
	tuning.use_preset("reference")
	lab.tuning_panel._sync()
	reset_at()
	await seconds(1.2)
	check("reference acceleration and speed operate in real physics", float(lab.car.telemetry.speed) > 19.0 and float(lab.car.telemetry.speed) <= 20.05, _telemetry())
	buttons(true, false)
	await seconds(0.6)
	var held_slip: float = absf(float(lab.car.telemetry.slip_degrees))
	check("short reference turn gives measurable sideslip", held_slip > 15.0 and _valid_car(), _telemetry())
	await seconds(4.2)
	check("reference sustained slide actually charges nitro", lab.car.control._fuel >= 1.0 and absf(float(lab.car.telemetry.slip_degrees)) > 20.0, _telemetry())
	buttons(false, false)
	await seconds(0.3)
	var released_slip: float = absf(float(lab.car.telemetry.slip_degrees))
	check("reference keeps visible slip briefly after release", released_slip > 3.0 and released_slip < 75.0, _telemetry())
	measurements.live_tuning = {"short_turn_slip_degrees": held_slip, "released_at_0_3s_slip_degrees": released_slip, "reference": tuning.snapshot()}
	var fuel: float = lab.car.control._fuel
	lab.tuning_panel.sliders.turn_degrees.value = 140
	check("live turn adjustment preserves earned fuel", lab.car.control._fuel == fuel and float(tuning.values.turn_degrees) == 140)
	lab.tuning_panel.visible = true
	lab.tuning_panel.layout(get_viewport().get_visible_rect().size)
	var panel_point: Vector2 = lab.tuning_panel.get_global_rect().get_center()
	check("tuning panel cannot become a driving pointer", lab._pointer_kind(panel_point).is_empty())
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = panel_point
	lab._input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.position = lab.controls.nitro_left.get_global_rect().get_center()
	lab._input(motion)
	check("mouse slider drag remains captured outside panel", lab.pointers.get("mouse") == "tuning" and lab.nitro_requests == 0)
	mouse.pressed = false
	lab._input(mouse)
	var touch := InputEventScreenTouch.new()
	touch.index = 99
	touch.pressed = true
	touch.position = panel_point
	lab._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 99
	drag.position = lab.controls.nitro_right.get_global_rect().get_center()
	lab._input(drag)
	check("touch slider drag remains captured outside panel", lab.pointers.get(99) == "tuning" and lab.nitro_requests == 0)
	touch.pressed = false
	lab._input(touch)
	check("UI pointers release without leaving input held", not lab.pointers.has(99) and not lab.pointers.has("mouse"))
	if lab.test_mode == "render":
		await tick()
		await RenderingServer.frame_post_draw
		check("live tuning panel frame saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("tuning.png")) == OK)
	lab.tuning_panel.visible = false
	var nitro_fuel: float = lab.car.control._fuel
	check("reference nitro still consumes one unit", lab.car.request_nitro() and absf(lab.car.control._fuel - nitro_fuel + 1) < 0.000001)
	buttons(true, true)
	await seconds(0.4)
	check("reference dual brake cannot reverse during active nitro", lab.car.telemetry.mode == "brake" and lab.car.telemetry.boost_active and float(lab.car.telemetry.forward_speed) >= 0)
	await seconds(2.0)
	check("tuning preserves capped straight reverse", lab.car.telemetry.mode == "reverse" and float(lab.car.telemetry.speed) <= 5.05 and float(lab.car.telemetry.forward_speed) < -4.5, _telemetry())
	if lab.test_mode == "physics":
		var wall := _box_body(Vector3(225, 0.8, 0), Vector3(0.45, 2.4, 50))
		var collider := wall.get_child(0) as CollisionShape3D
		reset_at(Vector3(225 - 0.225 - RADIUS - 0.03, PLANE_Y, 0))
		await tick()
		inject_velocity(Vector3.FORWARD * 10)
		var rejections: int = lab.car.rejected_yaws
		buttons(false, true)
		var deepest := 0.0
		for _i in range(Engine.physics_ticks_per_second):
			await tick()
			deepest = maxf(deepest, capsule_depth(lab.car, collider))
		check("reference fast yaw still rejects wall penetration", deepest <= PENETRATION_GATE and lab.car.rejected_yaws > rejections and _valid_car(), {"depth_m": deepest, "rejected_yaws": lab.car.rejected_yaws - rejections})
		reset_at(Vector3(225 - 0.225 - RADIUS - HALF_STRAIGHT - 0.04, PLANE_Y, 12), Vector3.RIGHT)
		await seconds(0.8)
		var blocked_x: float = lab.car.global_position.x
		buttons(true, true)
		await seconds(1.5)
		check("reference can reverse away from real wall", lab.car.telemetry.mode == "reverse" and lab.car.global_position.x < blocked_x - 3 and float(lab.car.telemetry.speed) <= 5.05 and _valid_car(), _telemetry())
		wall.queue_free()
		await tick()
	tuning.use_preset(str(saved.profile))
	lab.tuning_panel._sync()
	reset_at()

func player_run() -> void:
	print("ARCADE_PHASE player_start")
	var tuning = lab.car.tuning
	tuning.use_preset("player")
	var feedback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://player-feedback.json"))
	var matches: bool = feedback.get("values", {}).size() == 8
	for key in feedback.get("values", {}):
		matches = matches and absf(float(tuning.values.get(key, -1000)) - float(feedback.values[key])) < 0.000001
	check("player eight values match archived approved user feedback", matches, tuning.snapshot())
	check("new nitro and contact bounds reject invalid values", not tuning.set_value("nitro_speed_multiplier", 1) and not tuning.set_value("nitro_extra_acceleration", 61) and not tuning.set_value("wall_slide_drag", -1) and not tuning.set_value("wall_slide_drag", NAN))
	check("fractional retention rejects even tiny negative values", not tuning.set_value("lateral_keep_turn", -0.0000001) and not tuning.set_value("lateral_keep_release", -0.0000001) and is_finite(tuning.lateral_multiplier(true, 1.0 / 60.0)))
	lab.tuning_panel._sync()
	lab.tuning_panel.sliders.nitro_speed_multiplier.value = 1.6
	lab.tuning_panel.sliders.nitro_extra_acceleration.value = 40
	lab.tuning_panel.sliders.wall_slide_drag.value = 0.4
	check("three new sliders reach the live physics model", absf(tuning.nitro_speed() - 48) < 0.00001 and float(tuning.values.nitro_extra_acceleration) == 40 and absf(float(tuning.values.wall_slide_drag) - 0.4) < 0.00001)
	tuning.use_preset("player")
	lab.tuning_panel._sync()
	reset_at()
	await seconds(1.4)
	check("player straight ordinary speed remains 30 m/s", float(lab.car.telemetry.speed) >= 29.9 and float(lab.car.telemetry.speed) <= 30.05 and _valid_car(), _telemetry())
	var turning := true
	var charge_end := Engine.get_physics_frames() + 540
	while Engine.get_physics_frames() < charge_end:
		var forward_speed: float = lab.car.telemetry.forward_speed
		if forward_speed < 10: turning = false
		if forward_speed > 16: turning = true
		buttons(turning, false)
		await tick()
	check("player sustained driving earns two real nitro units", lab.car.control._fuel >= 2 and lab.car.telemetry.drifting and _valid_car(), _telemetry())
	buttons(false, false)
	# Preserve only fuel earned above. Pose/velocity staging isolates straight
	# acceleration from the preceding real drift, without manufacturing charge.
	lab.car.global_transform = Transform3D(Basis.IDENTITY, EMPTY_ORIGIN)
	lab.car.reset_physics_interpolation()
	inject_velocity(Vector3.FORWARD * 30)
	await tick()
	nitro_edge()
	await seconds(0.15)
	var launch_speed: float = lab.car.telemetry.speed
	var approved_boost_cap: float = tuning.nitro_speed()
	check("approved boost gives stronger initial straight acceleration", launch_speed >= 41.0 and launch_speed <= approved_boost_cap + 0.05, _telemetry())
	await seconds(0.3)
	check("approved boost reaches archived 51.6 m/s cap", absf(approved_boost_cap - 51.6) < 0.00001 and float(lab.car.telemetry.speed) >= approved_boost_cap - 0.1 and float(lab.car.telemetry.speed) <= approved_boost_cap + 0.05, _telemetry())
	var decay: Array[Dictionary] = []
	var last_speed: float = lab.car.velocity.length()
	var expired := false
	var first_drop := 0.0
	var maximum_drop := 0.0
	var monotonic := true
	# Higher approved boost speed needs (cap - ordinary) / 20 seconds to settle.
	# Include the remaining active spray; keep monotonic/per-step decay gates.
	var expiry_budget := 1.5 + (approved_boost_cap - float(tuning.values.top_speed)) / 20.0
	var expiry_end := Engine.get_physics_frames() + ceili(expiry_budget * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < expiry_end:
		await tick()
		var speed: float = lab.car.velocity.length()
		if not bool(lab.car.telemetry.boost_active):
			if not expired: first_drop = last_speed - speed
			expired = true
			maximum_drop = maxf(maximum_drop, last_speed - speed)
			monotonic = monotonic and speed <= last_speed + 0.001
			decay.append({"physics_frame": Engine.get_physics_frames(), "speed_mps": speed, "speed_limit": lab.car.telemetry.speed_limit})
		last_speed = speed
		if expired and speed <= 30.01: break
	check("nitro expiry recovers existing overspeed without one-frame clipping", expired and first_drop <= 1.1 and maximum_drop <= 1.1 and monotonic and last_speed <= 30.01, {"first_drop_mps": first_drop, "max_drop_mps": maximum_drop, "end_speed_mps": last_speed, "samples": decay})
	check("expired nitro cannot regain its former high cap", float(lab.car.telemetry.speed_limit) <= 30.01)
	# A second genuinely earned unit exercises the strongest exposed boost.
	tuning.set_value("nitro_speed_multiplier", 1.8)
	tuning.set_value("nitro_extra_acceleration", 60)
	nitro_edge()
	await seconds(0.4)
	check("maximum slider boost stays within 54 m/s", float(lab.car.telemetry.speed) > 53 and float(lab.car.telemetry.speed) <= 54.05, _telemetry())
	buttons(true, true)
	var brake_samples: Array[float] = []
	var prior: float = lab.car.velocity.length()
	var brakes_dominate := true
	var reverse_during_boost := false
	var brake_end := Engine.get_physics_frames() + 35
	while Engine.get_physics_frames() < brake_end:
		await tick()
		var now: float = lab.car.velocity.length()
		brakes_dominate = brakes_dominate and now < prior - 0.15
		reverse_during_boost = reverse_during_boost or (lab.car.telemetry.boost_active and lab.car.telemetry.mode == "reverse")
		brake_samples.append(now)
		prior = now
	check("dual-key brake dominates even maximum active nitro", brakes_dominate and not reverse_during_boost and lab.car.telemetry.mode == "brake", brake_samples)
	await seconds(2.5)
	var reverse_yaw: float = lab.car.rotation.y
	await seconds(0.2)
	check("player reverse remains straight and limited to quarter speed", lab.car.telemetry.mode == "reverse" and float(lab.car.telemetry.forward_speed) <= -7.4 and float(lab.car.telemetry.speed) <= 7.55 and absf(angle_difference(reverse_yaw, lab.car.rotation.y)) < 0.00001, _telemetry())
	measurements.player_nitro = {"eight_user_values_preserved": matches, "approved_boost_cap_mps": approved_boost_cap, "launch_after_150ms_mps": launch_speed, "expiry": decay, "maximum_boost_brake_speeds": brake_samples, "earned_fuel_only": true}
	tuning.use_preset("player")
	lab.tuning_panel._sync()
	if lab.test_mode == "render":
		lab.tuning_panel.visible = true
		await tick()
		await RenderingServer.frame_post_draw
		check("player eight-slider panel frame saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("nitro-panel.png")) == OK)
		lab.tuning_panel.visible = false
	reset_at()
	print("ARCADE_PHASE player_complete")

func player_wall_run() -> void:
	print("ARCADE_PHASE wall_contact_start")
	lab.car.tuning.use_preset("player")
	var wall := _box_body(Vector3(225, 0.8, 0), Vector3(0.45, 2.4, 200))
	var collider := wall.get_child(0) as CollisionShape3D
	var reports: Array[Dictionary] = []
	# Preserve the previous low-drag regression; independently exercise the
	# approved higher contact drag, which intentionally loses more wall speed.
	for config in [{"degrees": 5.0, "drag": 0.8}, {"degrees": 15.0, "drag": 0.8},
		{"degrees": 5.0, "drag": 6.2}, {"degrees": 15.0, "drag": 6.2}]:
		var degrees: float = config.degrees
		var drag: float = config.drag
		lab.car.tuning.set_value("wall_slide_drag", drag)
		var angle := deg_to_rad(degrees)
		var direction := Vector3(sin(angle), 0, -cos(angle))
		var extent := RADIUS + HALF_STRAIGHT * absf(sin(angle))
		reset_at(Vector3(225 - 0.225 - extent - 0.03, PLANE_Y, 0), direction)
		await tick()
		inject_velocity(direction * 30)
		var initial: Vector3 = lab.car.global_position
		var contacts := 0
		var first_ratio := 0.0
		var prior_tangent := absf(lab.car.velocity.z)
		var deepest := -INF
		var once_per_tick := true
		for _i in range(120):
			await tick()
			deepest = maxf(deepest, capsule_depth(lab.car, collider))
			once_per_tick = once_per_tick and int(lab.car.telemetry.wall_friction_applications) <= 1
			if lab.car.get_slide_collision_count() > 0:
				if contacts == 0: first_ratio = absf(lab.car.velocity.z) / prior_tangent
				contacts += 1
			prior_tangent = absf(lab.car.velocity.z)
		var tangent: float = absf(lab.car.velocity.z)
		var distance := absf(lab.car.global_position.z - initial.z)
		if drag == 0.8:
			check("baseline glancing contact keeps tangential motion %.0f degrees" % degrees, contacts > 90 and first_ratio > 0.95 and tangent > 16 and distance > 35 and once_per_tick and deepest <= PENETRATION_GATE and _valid_car(), {"contact_ticks": contacts, "first_tangent_ratio": first_ratio, "end_tangent_mps": tangent, "distance_m": distance, "max_depth_m": deepest})
		else:
			var expected_ratio := exp(-drag / Engine.physics_ticks_per_second)
			check("approved wall drag applies once with finite sliding %.0f degrees" % degrees, contacts > 90 and absf(first_ratio - expected_ratio) < 0.025 and tangent > 0.1 and distance > 1.0 and once_per_tick and deepest <= PENETRATION_GATE and _valid_car(), {"drag": drag, "expected_first_ratio": expected_ratio, "first_tangent_ratio": first_ratio, "contact_ticks": contacts, "end_tangent_mps": tangent, "distance_m": distance, "max_depth_m": deepest})
		# Do not reset or move the body before testing escape from real contact.
		var attached_x: float = lab.car.global_position.x
		var attached_yaw: float = lab.car.rotation.y
		var max_assist := 0.0
		buttons(true, false)
		for _i in range(60):
			await tick()
			deepest = maxf(deepest, capsule_depth(lab.car, collider))
			max_assist = maxf(max_assist, float(lab.car.telemetry.wall_release_motion_mps))
		var turn_change := absf(angle_difference(attached_yaw, lab.car.rotation.y))
		var separation: float = attached_x - lab.car.global_position.x
		check("turning away escapes attached wall %.0f degrees drag %.1f" % [degrees, drag], turn_change > 0.2 and separation > 0.3 and deepest <= PENETRATION_GATE and max_assist <= 6.001 and _valid_car(), {"turn_radians": turn_change, "separation_m": separation, "max_depth_m": deepest, "max_assist_mps": max_assist})
		reports.append({"angle_degrees": degrees, "wall_slide_drag": drag, "contact_ticks": contacts, "first_tangent_ratio": first_ratio, "end_tangent_mps": tangent, "distance_m": distance, "escape_rotation_radians": turn_change, "escape_separation_m": separation, "max_depth_m": deepest, "teleport_before_escape": false})
	lab.car.tuning.use_preset("player")
	wall.queue_free()
	await tick()
	# Passive high-speed staging isolates the sweep from the ordinary speed cap.
	var pole := _box_body(Vector3(226, 0.8, 0), Vector3(0.2, 2.4, 0.2))
	var pole_shape := pole.get_child(0) as CollisionShape3D
	for speed in [45.0, 54.0]:
		reset_at()
		lab.car.driver_enabled = false
		lab.car.passive_drag = 0
		await tick()
		inject_velocity(Vector3.RIGHT * speed)
		var contact := false
		var deepest := -INF
		var crossed := false
		for _i in range(30):
			await tick()
			deepest = maxf(deepest, capsule_depth(lab.car, pole_shape))
			crossed = crossed or lab.car.global_position.x > 226.15
			for j in range(lab.car.get_slide_collision_count()):
				contact = contact or lab.car.get_slide_collision(j).get_collider() == pole
		check("thin pole blocks new boost speed %.0f m/s" % speed, contact and not crossed and deepest <= PENETRATION_GATE and _valid_car(), {"contacted": contact, "max_depth_m": deepest, "speed_staged_mps": speed})
	measurements.player_wall = reports
	pole.queue_free()
	await tick()
	reset_at()
	print("ARCADE_PHASE wall_contact_complete")

func driving_run() -> void:
	reset_at()
	check("reset clears real momentum and match resources", lab.car.velocity == Vector3.ZERO and lab.car.last_actual_velocity == Vector2.ZERO and lab.car.control._fuel == 0.0 and lab.car.control._boost_remaining == 0.0)
	var initial: Vector3 = lab.car.global_position
	var peak := 0.0
	var finite := true
	for _i in range(3 * Engine.physics_ticks_per_second):
		await tick()
		peak = maxf(peak, float(lab.car.telemetry.get("speed", 0.0)))
		finite = finite and _valid_car()
	check("released controls automatically drive forward", lab.car.global_position.distance_to(initial) > 20.0 and float(lab.car.telemetry.get("forward_speed", 0.0)) > 23.0, _telemetry())
	check("automatic forward cap 25 m/s and fixed plane", finite and peak <= 25.05, {"peak_mps": peak, "end": _vec(lab.car.global_position)})
	buttons(true, false)
	var drift_ticks := 0
	var max_slip := 0.0
	var start_fuel: float = lab.car.control._fuel
	for _i in range(14 * Engine.physics_ticks_per_second):
		await tick()
		if bool(lab.car.telemetry.get("drifting", false)):
			drift_ticks += 1
		max_slip = maxf(max_slip, absf(float(lab.car.telemetry.get("slip_degrees", 0.0))))
		finite = finite and _valid_car()
	var expected_fuel := minf(3.0, start_fuel + float(drift_ticks) / Engine.physics_ticks_per_second * 0.25)
	check("steering produces actual sideslip and full drift charge", finite and drift_ticks >= 12 * Engine.physics_ticks_per_second and lab.car.control._fuel >= 2.99, {"drifting_ticks": drift_ticks, "max_slip_degrees": max_slip, "fuel": lab.car.control._fuel})
	check("physics drift fuel agrees with real qualifying ticks", absf(float(lab.car.control._fuel) - expected_fuel) <= 0.01, {"expected": expected_fuel, "actual": lab.car.control._fuel})
	buttons(false, false)
	await seconds(1.0)
	check("releasing turn naturally removes sideslip", absf(float(lab.car.telemetry.get("slip_degrees", 999.0))) < 1.0 and not lab.car.telemetry.get("drifting", true), _telemetry())
	var before_fuel: float = lab.car.control._fuel
	var saved_velocity: Vector3 = lab.car.velocity
	var saved_actual: Vector2 = lab.car.last_actual_velocity
	var heading: Vector3 = -lab.car.global_basis.z
	var cached_forward: float = lab.car.control._last_actual_forward_speed
	inject_velocity(-heading * 3.0)
	var bridge_denied: bool = not lab.car.request_nitro()
	check("input bridge refuses latest backward motion despite stale forward control cache", cached_forward >= 0.0 and before_fuel >= 1.0 and bridge_denied and lab.car.control._fuel == before_fuel and lab.car.control._boost_remaining == 0.0, {"cached_forward_mps": cached_forward, "latest_backward_mps": -3.0, "observation_injected_between_ticks": true})
	lab.car.velocity = saved_velocity
	lab.car.last_actual_velocity = saved_actual
	nitro_edge()
	check("input edge buys one real 1.5 second boost", absf(float(lab.car.control._fuel) - (before_fuel - 1.0)) < 0.001 and absf(float(lab.car.control._boost_remaining) - 1.5) < 0.001)
	await seconds(0.35)
	var before_append: float = lab.car.control._boost_remaining
	nitro_edge()
	check("second input appends duration without stacking strength", absf(float(lab.car.control._boost_remaining) - before_append - 1.5) < 0.001 and absf(float(lab.car.control._fuel) - before_fuel + 2.0) < 0.001)
	var boost_peak := 0.0
	for _i in range(ceili(0.35 * Engine.physics_ticks_per_second)):
		await tick()
		boost_peak = maxf(boost_peak, float(lab.car.telemetry.get("speed", 0.0)))
	check("nitro really accelerates within 34 m/s cap", boost_peak > 32.0 and boost_peak <= 34.05, boost_peak)
	buttons(true, true)
	var denied_fuel: float = lab.car.control._fuel
	var denied_time: float = lab.car.control._boost_remaining
	nitro_edge()
	check("brake nitro input denied without spending or extending", lab.car.control._fuel == denied_fuel and lab.car.control._boost_remaining == denied_time)
	var stop_with_boost := false
	var premature_reverse := false
	var low_speed_tick := -1
	for i in range(4 * Engine.physics_ticks_per_second):
		await tick()
		var remaining: float = lab.car.control._boost_remaining
		var speed: float = lab.car.telemetry.get("speed", 99.0)
		var mode: String = lab.car.telemetry.get("mode", "")
		if remaining > 0.02 and speed <= 0.15:
			stop_with_boost = true
			low_speed_tick = i
		premature_reverse = premature_reverse or (remaining > 0.0 and mode == "reverse")
		if mode == "reverse" and float(lab.car.telemetry.get("forward_speed", 0)) < -6.0:
			break
	check("brakes can stop while existing boost continues spraying", stop_with_boost and low_speed_tick >= 0, {"stopped_tick": low_speed_tick})
	check("all queued boost expires before straight reverse", not premature_reverse and lab.car.control._boost_remaining == 0.0 and lab.car.telemetry.get("mode") == "reverse", _telemetry())
	var reverse_yaw: float = lab.car.rotation.y
	await seconds(1.0)
	check("both keys reverse straight at at most 6.25 m/s", float(lab.car.telemetry.get("forward_speed", 0.0)) < -6.0 and float(lab.car.telemetry.get("speed", 99.0)) <= 6.30 and absf(angle_difference(reverse_yaw, lab.car.rotation.y)) < 0.0001, _telemetry())
	before_fuel = lab.car.control._fuel
	nitro_edge()
	check("reverse request cannot consume fuel", lab.car.control._fuel == before_fuel and lab.car.control._boost_remaining == 0.0)
	buttons(false, false)
	await seconds(1.0)
	check("release changes backward inertia into forward drive", lab.car.telemetry.get("mode") == "forward" and float(lab.car.telemetry.get("forward_speed", -99)) > 2.0, _telemetry())
	measurements.driving = {"automatic_peak_mps": peak, "boost_peak_mps": boost_peak, "drift_ticks": drift_ticks, "slip_peak_degrees": max_slip, "final": _telemetry()}

func _valid_car() -> bool:
	return lab.car.global_position.is_finite() and lab.car.velocity.is_finite() and lab.car.global_basis.is_finite() and absf(float(lab.car.global_position.y) - PLANE_Y) < 0.0001 and absf(float(lab.car.velocity.y)) < 0.0001

func touch_run() -> void:
	reset_at()
	# Establish fuel from real driving; no synthetic control.step charge.
	await seconds(3.0)
	buttons(false, true)
	await seconds(14.0)
	buttons(false, false)
	await seconds(0.6)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = (lab.controls.left as Control).get_global_rect().get_center()
	mouse.pressed = true
	lab._input(mouse)
	_touch(77, "right", true)
	mouse.pressed = false
	lab._input(mouse)
	lab.apply_controls()
	check("touch suppression cannot strand an existing mouse direction on release", not lab.pointers.has("mouse") and not lab.car.held_left and lab.car.held_right)
	_touch(77, "right", false)
	lab.apply_controls()
	_touch(0, "left", true)
	_touch(1, "right", true)
	_touch(2, "nitro_left", true)
	var fuel: float = lab.car.control._fuel
	check("same-frame brake touch queues one logical nitro request", lab.nitro_requests == 1)
	lab.apply_controls()
	check("same-frame two fingers brake before nitro decision", lab.car.held_left and lab.car.held_right and lab.car.control._fuel == fuel and lab.car.control._boost_remaining == 0.0)
	_touch(0, "left", false)
	_touch(1, "right", false)
	_touch(2, "nitro_left", false)
	lab.apply_controls()
	check("touch release removes both driving commands", not lab.car.held_left and not lab.car.held_right and lab.pointers.is_empty())
	fuel = lab.car.control._fuel
	_touch(3, "nitro_left", true)
	_touch(4, "nitro_right", true)
	check("two nitro pointers queue only one logical edge", lab.nitro_requests == 1)
	lab.apply_controls()
	check("same-frame two nitro fingers coalesce to one edge", absf(float(lab.car.control._fuel) - fuel + 1.0) < 0.001 and absf(float(lab.car.control._boost_remaining) - 1.5) < 0.001)
	lab.apply_controls()
	check("held nitro fingers do not repeat purchases", absf(float(lab.car.control._fuel) - fuel + 1.0) < 0.001)
	_touch(3, "nitro_left", false)
	_touch(4, "nitro_right", false)
	lab.apply_controls()
	# Full release and press twice before the same physics tick must keep both edges.
	var before_time: float = lab.car.control._boost_remaining
	fuel = lab.car.control._fuel
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	check("two complete keyboard edges in one tick are retained", lab.nitro_requests == 2)
	lab.apply_controls()
	check("retained same-tick edges spend two units and append three seconds", fuel >= 2.0 and absf(float(lab.car.control._fuel) - fuel + 2.0) < 0.001 and absf(float(lab.car.control._boost_remaining) - before_time - 3.0) < 0.001)
	var window: Window = get_tree().root
	var old_size: Vector2i = window.size
	window.size = Vector2i(360, 640)
	await get_tree().process_frame
	lab._layout_controls()
	var visible: Rect2 = get_viewport().get_visible_rect()
	var fitted := true
	for widget in lab.controls.values():
		fitted = fitted and visible.encloses(widget.get_global_rect())
	_touch(5, "left", true)
	lab.apply_controls()
	var narrow_responds: bool = lab.car.held_left and not lab.car.held_right
	_touch(5, "left", false)
	lab.apply_controls()
	check("360x640 input layout fits and releases", window.size == Vector2i(360, 640) and fitted and narrow_responds and not lab.car.held_left, {"viewport": [visible.size.x, visible.size.y], "injected_only": true})
	_touch(6, "right", true)
	lab.apply_controls()
	window.size = old_size
	await get_tree().process_frame
	lab._layout_controls()
	lab.apply_controls()
	check("layout restoration clears stranded touch pointers", lab.pointers.is_empty() and not lab.car.held_right)
	measurements.touch = {"injected_only": true, "physical_phone_test": false, "narrow_window": [360, 640], "restored_window": [old_size.x, old_size.y]}

func point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var ratio := clampf((point - a).dot(segment) / segment.length_squared(), 0.0, 1.0) if segment.length_squared() > 0.000000001 else 0.0
	return point.distance_to(a + segment * ratio)

func segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var ab := b - a
	var cd := d - c
	var denominator := ab.cross(cd)
	if absf(denominator) > 0.000000001:
		var t := (c - a).cross(cd) / denominator
		var u := (c - a).cross(ab) / denominator
		if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
			return 0.0
	return minf(minf(point_segment_distance(a, c, d), point_segment_distance(b, c, d)), minf(point_segment_distance(c, a, b), point_segment_distance(d, a, b)))

func segment_rectangle_distance(a: Vector2, b: Vector2, half: Vector2) -> float:
	if (absf(a.x) <= half.x and absf(a.y) <= half.y) or (absf(b.x) <= half.x and absf(b.y) <= half.y):
		return 0.0
	var corners: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var closest := INF
	for i in range(4):
		closest = minf(closest, segment_distance(a, b, corners[i], corners[(i + 1) % 4]))
	return closest

func capsule_depth(vehicle: Node3D, box: CollisionShape3D) -> float:
	# Horizontal capsule: a finite centerline swept by RADIUS, including its belly.
	var inverse := box.global_transform.affine_inverse()
	var a: Vector3 = inverse * (vehicle.global_transform * Vector3(0, 0.52, -HALF_STRAIGHT))
	var b: Vector3 = inverse * (vehicle.global_transform * Vector3(0, 0.52, HALF_STRAIGHT))
	var half: Vector3 = (box.shape as BoxShape3D).size * 0.5
	return RADIUS - segment_rectangle_distance(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(half.x, half.z))

func measurement_controls() -> void:
	var half := Vector2(0.225, 0.5)
	for depth in [0.03, 0.08]:
		var measured := RADIUS - segment_rectangle_distance(Vector2(-half.x - RADIUS + depth, -HALF_STRAIGHT), Vector2(-half.x - RADIUS + depth, HALF_STRAIGHT), half)
		check("finite capsule measurement retains %.0f cm penetration" % (depth * 100), absf(measured - depth) < 0.00001 and (measured > PENETRATION_GATE) == (depth > PENETRATION_GATE), measured)
	check("finite rectangle excludes remote infinite wall projection", segment_rectangle_distance(Vector2(-0.5, 5), Vector2(0.5, 6), half) > RADIUS)
	check("finite capsule measurement detects full centerline crossing", segment_rectangle_distance(Vector2(-3, 0), Vector2(3, 0), half) == 0.0)
	check("finite capsule measurement detects belly-only thin pole", segment_rectangle_distance(Vector2(0, -HALF_STRAIGHT), Vector2(0, HALF_STRAIGHT), Vector2(0.1, 0.1)) == 0.0)
	check("finite segment distance retains collinear overlap", segment_distance(Vector2(0, 0), Vector2(0, 3), Vector2(0, 1), Vector2(0, 2)) == 0.0)

func _collect_rails() -> void:
	var body := lab.track.get_node_or_null("ContinuousGuardrails") as StaticBody3D
	check("actual finite guardrail body available", body != null)
	if body == null:
		return
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			rails.append(child)
	for owner_id in body.get_shape_owners():
		var shape := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D:
			continue
		for local_index in range(body.shape_owner_get_shape_count(owner_id)):
			var index: int = body.shape_owner_get_shape_index(owner_id, local_index)
			rail_indices[index] = shape
			rail_shape_indices[shape] = index
	check("guardrails are unscaled planar finite boxes", not rails.is_empty() and _rails_unscaled(), rails.size())
	var capsule: CapsuleShape3D = lab.car.body_collider.shape
	check("one horizontal capsule fills the full body", lab.car.get_children().filter(func(n): return n is CollisionShape3D).size() == 1 and absf(capsule.radius - RADIUS) < 0.00001 and absf(capsule.height - 2 * (RADIUS + HALF_STRAIGHT)) < 0.00001 and absf(lab.car.body_collider.rotation.x - PI * 0.5) < 0.00001)

func _rails_unscaled() -> bool:
	for shape in rails:
		if not shape.global_basis.get_scale().is_equal_approx(Vector3.ONE):
			return false
	return true

func _shape_index(shape: CollisionShape3D) -> int:
	return int(rail_shape_indices.get(shape, -1))

func _nearby_depth(vehicle: Node3D, measured: Dictionary) -> float:
	var deepest := -INF
	for box in rails:
		var half: Vector3 = (box.shape as BoxShape3D).size * 0.5
		var delta: Vector3 = vehicle.global_position - box.global_position
		# Cheap finite global AABB rejection precedes transform/geometry work.
		var broad_x := absf(box.global_basis.x.x) * half.x + absf(box.global_basis.z.x) * half.z + 4.0
		var broad_z := absf(box.global_basis.x.z) * half.x + absf(box.global_basis.z.z) * half.z + 4.0
		if absf(delta.x) > broad_x or absf(delta.z) > broad_z:
			continue
		measured[_shape_index(box)] = true
		deepest = maxf(deepest, capsule_depth(vehicle, box))
	return deepest

func _outward(shape: CollisionShape3D, side: float) -> Vector3:
	var normal := shape.global_basis.x.normalized()
	var samples: Array = lab.track.layout.samples
	var index := clampi(floori(float(rails.find(shape)) / 2.0), 0, samples.size() - 1)
	var expected: Vector3 = samples[index].right * side
	return normal if normal.dot(expected) > 0.0 else -normal

func rail_run() -> void:
	if rails.size() < 4:
		check("rail collision matrix has real shapes", false)
		return
	var segment_count := floori(float(rails.size()) / 2.0)
	var straight := mini(8, segment_count - 1)
	var bend := 0
	var greatest_angle := 0.0
	for i in range(segment_count - 1):
		var angle := rails[i * 2].global_basis.z.angle_to(rails[(i + 1) * 2].global_basis.z)
		if angle > greatest_angle:
			greatest_angle = angle
			bend = i
	var specs: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		for speed in [6.0, 12.0, 25.0, 34.0]:
			specs.append({"label": "straight", "segment": straight, "side": side, "speed": speed, "angle": 0.0, "seam": false})
	specs.append({"label": "oblique", "segment": straight, "side": 1.0, "speed": 25.0, "angle": 0.4, "seam": false})
	specs.append({"label": "bend", "segment": bend, "side": -1.0, "speed": 25.0, "angle": 0.15, "seam": false})
	specs.append({"label": "ordinary-seam", "segment": straight, "side": 1.0, "speed": 34.0, "angle": 0.0, "seam": true})
	specs.append({"label": "closed-loop-seam", "segment": segment_count - 1, "side": -1.0, "speed": 34.0, "angle": 0.0, "seam": true})
	var reports: Array[Dictionary] = []
	for spec in specs:
		var target: CollisionShape3D = rails[int(spec.segment) * 2 + (0 if float(spec.side) < 0 else 1)]
		var outward := _outward(target, float(spec.side))
		var half: Vector3 = (target.shape as BoxShape3D).size * 0.5
		var center := target.global_position
		if bool(spec.seam):
			center -= target.global_basis.z * half.z
		var face := center - outward * half.x
		var forward := outward.rotated(Vector3.UP, float(spec.angle))
		reset_at(Vector3(face.x, PLANE_Y, face.z) - outward * 5.0, forward)
		lab.car.driver_enabled = false
		lab.car.passive_drag = 0.0
		await tick()
		inject_velocity(forward * float(spec.speed))
		var measured: Dictionary = {}
		rail_sample = {"target": target, "measured": measured, "max_depth": maxf(-1.0, _nearby_depth(lab.car, measured)), "finite": _valid_car(), "escaped": false, "outward": outward, "face": face, "wall_width": half.x * 2.0, "contact_tick": -1, "pre_contact_speed": 0.0, "previous_speed": lab.car.velocity.length(), "ticks": 0}
		await seconds(2.0)
		var sample := rail_sample.duplicate(true)
		rail_sample.clear()
		var peak_depth: float = sample.max_depth
		var finite: bool = sample.finite
		var escaped: bool = sample.escaped
		var contact_tick: int = sample.contact_tick
		var pre_contact_speed: float = sample.pre_contact_speed
		var samples: int = sample.ticks
		var contacted: Array = lab.car.contacted_rail_shapes.keys()
		var covered := not contacted.is_empty()
		for index in contacted:
			covered = covered and measured.has(index) and rail_indices.has(index)
		var label := "%s side %s speed %.0f" % [spec.label, spec.side, spec.speed]
		check("real rail contact " + label, contact_tick >= 0, contacted)
		check("all actual contact shapes measured " + label, covered, {"contacts": contacted, "measured": measured.keys()})
		check("finite capsule stays inside 5cm gate " + label, finite and not escaped and peak_depth <= PENETRATION_GATE, {"max_penetration_m": peak_depth, "escaped": escaped})
		reports.append({"spec": spec, "max_penetration_m": peak_depth, "escaped": escaped, "finite_fixed_y": finite, "contacted_shape_indices": contacted, "all_contact_shapes_measured": covered, "first_contact_tick": contact_tick, "pre_contact_speed_mps": pre_contact_speed, "sampled_actual_ticks": samples, "end": _vec(lab.car.global_position)})
	measurements.guardrails = reports

func _box_body(origin: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 4
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	lab.add_child(body)
	body.global_position = origin
	return body

func thin_pole_run() -> void:
	# Sideways motion meets a 20cm pole at the capsule belly, between end spheres.
	var pole := _box_body(Vector3(226, 0.8, 0), Vector3(0.2, 2.4, 0.2))
	var collider := pole.get_child(0) as CollisionShape3D
	reset_at()
	lab.car.driver_enabled = false
	lab.car.passive_drag = 0.0
	await tick()
	inject_velocity(Vector3.RIGHT * 12.0)
	var contacted := false
	var penetration := -INF
	var crossed := false
	for _i in range(Engine.physics_ticks_per_second):
		await tick()
		penetration = maxf(penetration, capsule_depth(lab.car, collider))
		crossed = crossed or float(lab.car.global_position.x) > 226.15
		for j in range(lab.car.get_slide_collision_count()):
			contacted = contacted or lab.car.get_slide_collision(j).get_collider() == pole
	check("20cm belly pole blocks where two end spheres leave a gap", contacted and not crossed and penetration <= PENETRATION_GATE and _valid_car(), {"contacted": contacted, "penetration_m": penetration, "end": _vec(lab.car.global_position)})
	pole.queue_free()
	await tick()

func yaw_and_escape_run() -> void:
	var wall := _box_body(Vector3(225, 0.8, 0), Vector3(0.45, 2.4, 50))
	var collider := wall.get_child(0) as CollisionShape3D
	reset_at(Vector3(225 - 0.225 - RADIUS - 0.03, PLANE_Y, 0))
	await tick()
	inject_velocity(Vector3.FORWARD * 10.0)
	var initial_rejections: int = lab.car.rejected_yaws
	buttons(false, true)
	var penetration := capsule_depth(lab.car, collider)
	var finite := _valid_car()
	for _i in range(Engine.physics_ticks_per_second):
		await tick()
		penetration = maxf(penetration, capsule_depth(lab.car, collider))
		finite = finite and _valid_car()
	check("turning beside wall rejects penetrating rotation", lab.car.rejected_yaws > initial_rejections and penetration <= PENETRATION_GATE and finite, {"rejected": lab.car.rejected_yaws - initial_rejections, "penetration_m": penetration})
	reset_at(Vector3(220, PLANE_Y, 0))
	await seconds(1.0)
	var yaw: float = lab.car.rotation.y
	buttons(false, true)
	await seconds(0.5)
	check("away from wall the vehicle can turn", absf(angle_difference(yaw, lab.car.rotation.y)) > 0.2 and _valid_car())
	# Facing the wall squarely, actual collision first blocks forward drive.
	reset_at(Vector3(225 - 0.225 - RADIUS - HALF_STRAIGHT - 0.04, PLANE_Y, 12), Vector3.RIGHT)
	await seconds(0.8)
	var blocked_position: Vector3 = lab.car.global_position
	buttons(true, true)
	await seconds(1.5)
	check("both-key reverse escapes a real blocked wall", lab.car.telemetry.get("mode") == "reverse" and float(lab.car.telemetry.get("forward_speed", 0)) < -5.5 and lab.car.global_position.x < blocked_position.x - 3.0 and _valid_car(), {"blocked": _vec(blocked_position), "escaped": _vec(lab.car.global_position)})
	wall.queue_free()
	await tick()

func push_run() -> void:
	var script: Script = load("res://arcade_vehicle.gd")
	var dummy = script.new()
	dummy.name = "AcceptancePushDummy"
	lab.add_child(dummy)
	dummy.driver_enabled = false
	dummy.passive_drag = 0.0
	dummy.request_reset(Transform3D(Basis.IDENTITY, Vector3(220, PLANE_Y, -7)))
	reset_at()
	lab.car.driver_enabled = false
	lab.car.passive_drag = 0.0
	await tick()
	var original: Vector3 = dummy.global_position
	inject_velocity(Vector3.FORWARD * 12.0)
	var contact := false
	var finite := true
	for _i in range(Engine.physics_ticks_per_second):
		await tick()
		finite = finite and _valid_car() and dummy.global_position.is_finite() and dummy.velocity.is_finite() and absf(dummy.global_position.y - PLANE_Y) < 0.0001
		for j in range(lab.car.get_slide_collision_count()):
			contact = contact or lab.car.get_slide_collision(j).get_collider() == dummy
	check("local dummy car receives collision push and moves", contact and finite and dummy.global_position.distance_to(original) > 0.2 and dummy.velocity.length() > 0.1, {"contacted": contact, "distance_m": dummy.global_position.distance_to(original), "velocity": _vec(dummy.velocity), "network_used": false})
	dummy.queue_free()
	await tick()

func render_run() -> void:
	print("ARCADE_PHASE render_start")
	check("render uses an actual graphics display", DisplayServer.get_name() != "headless", DisplayServer.get_name())
	if DisplayServer.get_name() == "headless":
		return
	check("render imports four wheels and steering pivots", lab.car.wheels.size() == 4 and lab.car.steer_pivots.size() == 4)
	# Charge only by actual driving, then stage at the real track spawn for pixels.
	reset_at()
	await seconds(3.0)
	print("ARCADE_PHASE render_accelerated")
	buttons(true, false)
	await seconds(14.0)
	print("ARCADE_PHASE render_charged")
	check("render has real drifting motion and charge", lab.car.telemetry.get("drifting", false) and lab.car.control._fuel >= 2.9)
	buttons(false, false)
	var spawn: Vector3 = lab.track.layout.spawns[0].position
	lab.car.global_transform = Transform3D(Basis.IDENTITY, Vector3(spawn.x, PLANE_Y, spawn.z))
	inject_velocity(Vector3.FORWARD * 20.0)
	lab.car.reset_physics_interpolation()
	await tick()
	var camera_basis: Basis = lab.camera.global_basis
	nitro_edge()
	await seconds(0.6)
	buttons(true, false)
	await seconds(0.25)
	check("render shows actual boost and visual lean", lab.car.telemetry.get("boost_active", false) and absf(float(lab.car.visual_lean)) > 0.01 and float(lab.car.telemetry.get("speed", 0)) > 20.0)
	check("HUD contains current nitro speed and drift information", not lab.hud.text.is_empty() and lab.fuel_bars.size() == 3 and lab.flames[0].visible and lab.flames[1].visible)
	await RenderingServer.frame_post_draw
	print("ARCADE_PHASE driver_drawn")
	check("actual driver frame saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("driving.png")) == OK)
	buttons(false, false)
	# Readback/PNG compression stalls are diagnostic work, outside the driving
	# sample. Discard the following frame deltas before timing normal rendering.
	await get_tree().process_frame
	await get_tree().process_frame
	var start_steps: int = lab.car.physics_steps
	var start_usec: int = lab.car.physics_usec_total
	frame_times.clear()
	measuring_frames = true
	var end_usec := Time.get_ticks_usec() + 3000000
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
	measuring_frames = false
	check("driver camera direction stays fixed while car turns", camera_basis.is_equal_approx(lab.camera.global_basis))
	var total := 0.0
	var slowest := 0.0
	for dt in frame_times:
		total += dt
		slowest = maxf(slowest, dt)
	var step_count: int = lab.car.physics_steps - start_steps
	var mean_script := float(lab.car.physics_usec_total - start_usec) / maxi(1, step_count)
	measurements.render = {"frames": frame_times.size(), "seconds": total, "mean_fps": float(frame_times.size()) / total if total > 0 else 0.0, "min_fps": 1.0 / slowest if slowest > 0 else 0.0, "slowest_frame_ms": slowest * 1000.0, "car_mean_script_usec": mean_script, "physics_steps": step_count, "physics_hz": Engine.physics_ticks_per_second, "screenshot_readback_in_sample": false, "visual_review": "pending human or main-agent image inspection", "spawn_staging_preserved_real_drift_fuel": true}
	check("three seconds of actual frames and physics recorded", total >= 2.8 and frame_times.size() >= 30 and step_count >= 175, measurements.render)
	lab.overview = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check("actual complete track overview saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("track.png")) == OK)

func finish() -> void:
	var evidence: String = lab.evidence_dir
	if evidence.is_empty() or not DirAccess.dir_exists_absolute(evidence):
		check("provided isolated evidence directory exists", false, evidence)
	else:
		var result := {"passed": passed, "failed": failed, "mode": lab.test_mode, "checks": checks, "measurements": measurements, "engine": Engine.get_version_info().string, "network_used": false, "physical_phone_test": false, "lap_completed": false}
		var path := evidence.path_join(str(lab.test_mode) + "-result.json")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			check("JSON evidence file opened", false, {"path": path, "error": FileAccess.get_open_error()})
		else:
			file.store_string(JSON.stringify(result, "\t") + "\n")
			file.flush()
			var write_error := file.get_error()
			file.close()
			if write_error != OK:
				check("JSON evidence file written", false, write_error)
	print("ARCADE_ACCEPTANCE_RESULT passed=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)
