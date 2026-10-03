extends Node
## Drives the real vehicle/arena physics. Keyboard injection is engine-level only.
var lab: Node3D
var checks: Array = []
var trace: Array = []
var metrics: Dictionary = {}
var cases := ["settle", "accelerate", "brake", "reverse", "forward_again", "direct_reverse", "turn_setup", "turn_accelerate", "circle", "drift", "recover", "ramp_setup", "ramp", "drop"]
var durations := [180, 300, 240, 180, 240, 240, 100, 300, 300, 60, 120, 120, 480, 180]
var case_index := 0
var case_tick := 0
var _case_start := Vector3.ZERO
var _finite := true
var _max_point_error := 0.0
var _max_friction_ratio := 0.0
var _air_force := 0.0
var _minimum_up := 1.0
var _settle_heights: Array[float] = []
var _settle_support: Array[float] = []
var _peak_drift := 0.0
var _heading_at_circle_start := Vector3.FORWARD
var _ramp_peak := 0.0
var _ramp_tilt := 0.0
var _ramp_air_ticks := 0
var _capture_pending := false
var _screenshots: Array = []
var _start_usec := 0
var _done := false
var _shift_observed := false
var _shift_safe := true


func _ready() -> void:
	_start_usec = Time.get_ticks_usec()
	_check(Engine.get_version_info().string.begins_with("4.7.2"), "Godot 4.7.2 runtime")
	_check(ProjectSettings.get_setting("physics/3d/physics_engine") == "GodotPhysics3D", "explicit physics backend")
	_check(Engine.physics_ticks_per_second == 60, "fixed physics 60 Hz")
	var root := OS.get_environment("RACING_DRIVING_ISOLATION").replace("\\", "/")
	_check(root.begins_with("F:/") and ProjectSettings.globalize_path("res://").replace("\\", "/").begins_with(root + "/project/"), "isolated F drive minimal project")
	_check(OS.get_user_data_dir().replace("\\", "/").begins_with(root + "/"), "isolated engine user data")
	_check(not DirAccess.dir_exists_absolute("res://host") and not DirAccess.dir_exists_absolute("res://sdk"), "no framework/service dependencies")
	_key(KEY_W, true)
	_key(KEY_SPACE, true)
	_check(lab.input_command().throttle == 1.0 and lab.input_command().drift, "engine input W and Space press path")
	_key(KEY_W, false)
	_key(KEY_SPACE, false)
	_check(lab.input_command().throttle == 0.0 and not lab.input_command().drift, "engine input release path")
	_key(KEY_D, true)
	lab._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(lab.input_command().steer == 0.0, "focus-loss handler clears held controls")
	lab.car.set_setting("drift_mu", 50)
	_check(is_equal_approx(lab.car.settings.drift_mu, 0.9), "grip parameter upper clamp")
	lab.car.set_setting("recovery_half_life", -1)
	_check(is_equal_approx(lab.car.settings.recovery_half_life, 0.12), "recovery parameter lower clamp")
	lab.car.reset_settings()
	lab.go_to_pad(0)
	lab.hud.debug_visible = true


func _physics_process(_delta: float) -> void:
	if _done or lab.car.telemetry.get("reset", true):
		return
	var data: Dictionary = lab.car.telemetry
	var position: Vector3 = data.pose.origin
	case_tick += 1
	if case_tick == 1:
		_case_start = position
		_shift_observed = false
		_shift_safe = true
		if cases[case_index] == "circle":
			_heading_at_circle_start = -data.pose.basis.z
	_finite = _finite and position.is_finite() and data.velocity.is_finite() and data.angular_velocity.is_finite() and data.speed < 100
	_max_point_error = maxf(_max_point_error, data.point_velocity_error)
	_max_friction_ratio = maxf(_max_friction_ratio, data.friction_ratio)
	_minimum_up = minf(_minimum_up, data.pose.basis.y.dot(Vector3.UP))
	for wheel in data.wheels:
		if not wheel.grounded:
			_air_force = maxf(_air_force, wheel.tire_force.length() + wheel.suspension_force.length())
	if data.tick % 6 == 0:
		trace.append({"case": cases[case_index], "tick": data.tick, "x": position.x, "y": position.y, "z": position.z, "speed": data.speed, "forward": data.forward_speed, "slip": data.slip_degrees, "contacts": data.grounded, "gear": data.gear, "drift": data.drift_blend})
	match cases[case_index]:
		"settle":
			_control(0)
			if case_tick > 90:
				_settle_heights.append(position.y)
				_settle_support.append(data.support_sum)
		"accelerate", "turn_accelerate":
			_control(1)
			if data.forward_speed >= 10:
				metrics[cases[case_index] + "_seconds"] = case_tick / 60.0
				_finish_case(data)
				return
		"brake":
			_control(0, 0, 1)
			if absf(data.forward_speed) < 0.1:
				metrics.braking_distance = position.distance_to(_case_start)
				_finish_case(data)
				return
		"reverse": _control(-1)
		"forward_again", "direct_reverse":
			var desired := 1 if cases[case_index] == "forward_again" else -1
			_control(desired)
			if not _shift_observed:
				if data.gear == desired:
					_shift_observed = true
					_shift_safe = _shift_safe and data.velocity.slide(Vector3.UP).length() < 0.3
				elif case_tick > 4:
					_shift_safe = _shift_safe and data.brake == 1.0 and data.drive == 0.0
		"turn_setup", "ramp_setup", "drop": _control(0)
		"circle":
			_control(clampf(0.12 + (10 - data.forward_speed) * 0.35, 0, 1), 0.25)
		"drift":
			_control(0.65, 0.45, 0, true)
			_peak_drift = maxf(_peak_drift, absf(data.slip_degrees))
		"recover":
			# Scripted driver countersteers; this is not an automatic vehicle assist.
			_control(0.3, clampf(data.slip_degrees / 30.0, -0.8, 0.8))
			if case_tick == 90:
				metrics.recovery_slip_1_5s = absf(data.slip_degrees)
				metrics.recovery_forward_speed_1_5s = data.forward_speed
		"ramp":
			_control(1)
			_ramp_peak = maxf(_ramp_peak, position.y)
			for wheel in data.wheels:
				if wheel.grounded:
					_ramp_tilt = maxf(_ramp_tilt, absf(wheel.normal.z))
			if position.z < -20 and data.grounded == 0:
				_ramp_air_ticks += 1
	if lab.test_mode == "render" and not _capture_pending and ((cases[case_index] == "circle" and case_tick == 120) or (cases[case_index] == "ramp" and case_tick == 180)):
		_capture(cases[case_index])
	if case_tick >= durations[case_index]:
		_finish_case(data)


func _finish_case(data: Dictionary) -> void:
	var label: String = cases[case_index]
	metrics[label + "_final_speed"] = data.forward_speed
	match label:
		"settle":
			metrics.rest_height = data.pose.origin.y
			metrics.rest_height_range = _settle_heights.max() - _settle_heights.min()
			var support := 0.0
			for value in _settle_support: support += value
			metrics.static_support = support / _settle_support.size()
			_check(data.grounded == 4, "four wheels support on flat ground")
			_check(absf(data.pose.origin.y - 0.63) < 0.02, "static suspension sag within two centimeters")
			_check(metrics.rest_height_range < 0.01, "settled vertical range below one centimeter")
			_check(absf(metrics.static_support - 11772) / 11772 < 0.05, "support balances gravity within five percent")
		"accelerate":
			_check(metrics.get("accelerate_seconds", 999) >= 2.5 and metrics.get("accelerate_seconds", 999) <= 4.0, "zero to ten m/s in planned window")
			_check(absf(data.pose.origin.x - _case_start.x) < 0.05, "straight acceleration does not steer itself")
		"brake":
			_check(metrics.get("braking_distance", 999) < 12 and absf(data.forward_speed) < 0.1, "brakes stop within twelve meters")
			_check(data.gear == 1, "dedicated braking does not engage reverse")
		"reverse": _check(data.gear == -1 and data.forward_speed < -2, "reverse engages after a stop")
		"forward_again", "direct_reverse":
			var desired := 1 if label == "forward_again" else -1
			_check(_shift_observed and _shift_safe and data.forward_speed * desired > 2, label + " brakes before changing gear and then accelerates")
		"turn_setup": _check(data.speed < 0.1 and data.pose.basis.y.dot(Vector3.UP) > 0.999, "physical reset clears motion and orientation")
		"turn_accelerate": _check(data.forward_speed >= 10, "turn fixture reaches ten m/s")
		"circle":
			metrics.turn_degrees = rad_to_deg(_heading_at_circle_start.angle_to(-data.pose.basis.z))
			metrics.signed_turn_degrees = rad_to_deg(_heading_at_circle_start.signed_angle_to(-data.pose.basis.z, Vector3.UP))
			_check(metrics.signed_turn_degrees < -45 and data.pose.origin.x > _case_start.x + 5, "positive steering turns right")
			_check(metrics.turn_degrees > 45, "front wheel forces turn body without heading overwrite")
			_check(data.pose.basis.y.dot(Vector3.UP) > 0.9 and data.grounded == 4, "corner remains upright on four contacts")
		"drift":
			metrics.peak_drift_degrees = _peak_drift
			_check(data.drift_blend > 0.8 and _peak_drift >= 15 and _peak_drift <= 40, "drift input produces bounded visible sideslip")
		"recover":
			_check(metrics.get("recovery_slip_1_5s", 999) < 5 and metrics.get("recovery_forward_speed_1_5s", 0) >= 5, "scripted countersteer recovers sideslip within one and half seconds while still driving forward")
			_check(data.drift_blend < 0.02, "rear grip parameters recover smoothly")
		"ramp":
			metrics.ramp_peak_height = _ramp_peak
			metrics.ramp_air_ticks = _ramp_air_ticks
			_check(_ramp_tilt > 0.15 and _ramp_peak > 2.5, "vehicle drives up real ten degree ramp")
			_check(_ramp_air_ticks >= 10, "vehicle leaves ramp under real rigidbody gravity")
			_check(data.grounded == 4 and absf(data.velocity.y) < 0.5, "vehicle lands and settles after ramp")
		"drop": _check(data.grounded == 4 and absf(data.pose.origin.y - 0.63) < 0.02 and absf(data.velocity.y) < 0.1, "half-meter drop converges")
	print("DRIVING_CASE ", label, " ", JSON.stringify(metrics))
	case_index += 1
	case_tick = 0
	if case_index >= cases.size():
		_done = true
		_complete()
		return
	match cases[case_index]:
		"turn_setup": lab.car.request_reset(Transform3D(Basis.IDENTITY, Vector3(-35, 0.9, -10)))
		"ramp_setup": lab.car.request_reset(Transform3D(Basis.IDENTITY, Vector3(35, 0.9, 5)))
		"drop": lab.car.request_reset(Transform3D(Basis.IDENTITY, Vector3(0, 1.13, 0)))


func _control(throttle: float, steer := 0.0, brake := 0.0, drift := false) -> void:
	lab.test_command = {"throttle": throttle, "steer": steer, "brake": brake, "drift": drift}


func _capture(label: String) -> void:
	_capture_pending = true
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var path: String = lab.evidence_dir.path_join(label + ".png")
	var result := picture.save_png(path)
	_check(result == OK and picture.get_width() == 1280 and picture.get_height() == 800, "actual rendered viewport capture " + label)
	_screenshots.append(path)
	_capture_pending = false


func _complete() -> void:
	_check(_finite, "all recorded rigidbody states finite and bounded")
	_check(_max_point_error < 0.0001, "Godot point velocity includes correct COM lever")
	_check(_max_friction_ratio <= 1.00001, "shared tire force budget never exceeded")
	_check(_air_force == 0, "airborne wheels apply no suspension or tire force")
	_check(_minimum_up > 0.6, "vehicle does not roll over during scripted course")
	if lab.test_mode == "render":
		_check(_screenshots.size() == 2, "two real-render views saved")
	var failures := 0
	for entry in checks:
		if not entry.passed: failures += 1
	var elapsed := (Time.get_ticks_usec() - _start_usec) / 1000000.0
	var frame_times: Array[float] = lab.frame_ms.duplicate()
	frame_times.sort()
	var report := {"mode": lab.test_mode, "engine": Engine.get_version_info(), "physics_backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "physics_hz": Engine.physics_ticks_per_second, "fixed_fps": 60 if lab.test_mode == "physics" else null, "realtime_synchronized": lab.test_mode == "render", "wall_seconds": elapsed, "render_frames": lab.render_frames, "observed_average_fps": lab.render_frames / elapsed if lab.test_mode == "render" else null, "frame_ms_median": frame_times[frame_times.size() / 2] if not frame_times.is_empty() else 0, "frame_ms_p95": frame_times[int(frame_times.size() * 0.95)] if not frame_times.is_empty() else 0, "passed": checks.size() - failures, "failed": failures, "metrics": metrics, "max_point_velocity_error": _max_point_error, "max_friction_ratio": _max_friction_ratio, "minimum_up_dot": _minimum_up, "checks": checks, "trace": trace, "screenshots": _screenshots, "not_run": ["physical keyboard", "manual handling acceptance", "Linux", "network", "race rules integration", "100m straight", "three complete circles", "slalom acceptance", "step obstacle acceptance", "render FPS comparison"]}
	var file := FileAccess.open(lab.evidence_dir.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write acceptance report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DRIVING_RESULT passed=", report.passed, " failed=", report.failed)
	get_tree().quit(0 if failures == 0 else 1)


func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	checks.append({"name": label, "passed": condition})
	if not condition: print("DRIVING_FAIL ", label)
