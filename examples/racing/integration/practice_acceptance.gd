extends Node
## Real physics lap, driven only through the same two digital steering inputs.
## Synthetic coordinator tests are reported separately from this vehicle lap.
const Unit = preload("res://tests/test_racing_practice.gd")
var lab
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var driving := false
var nearest := 0
var braking := false
var movement_frames := 0
var path_m := 0.0
var max_segment := 0.0
var finite := true
var samples: Array[Dictionary] = []
var measurements: Dictionary = {}

func _ready() -> void:
	process_physics_priority = -200
	lab.car.movement_completed.connect(_sample)
	run.call_deferred()

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "ok": ok, "detail": detail})
	if ok: passed += 1
	else:
		failed += 1
		print("PRACTICE_FAILED ", label, " ", str(detail))

func tick() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _r() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	lab._input(event)
	event.pressed = false
	lab._input(event)

func _sample(previous: Vector3, current: Vector3, _dt: float) -> void:
	if not driving: return
	movement_frames += 1
	var distance := previous.distance_to(current)
	path_m += distance
	max_segment = maxf(max_segment, distance)
	finite = finite and current.is_finite() and lab.car.velocity.is_finite()
	if movement_frames % 60 == 0:
		samples.append({"physics_frame": Engine.get_physics_frames(), "position": [current.x, current.y, current.z],
			"speed": lab.car.velocity.length(), "nearest_sample": nearest, "phase": lab.practice.phase,
			"next_gate": lab.practice.expected_gate})

func _physics_process(_dt: float) -> void:
	if not driving or lab.car.practice_hold or lab.car.paused: return
	var road: Array = lab.track.layout.samples
	var count := road.size() - 1
	var position: Vector3 = lab.car.global_position
	var best := INF
	var selected := nearest
	for index in range(maxi(0, nearest - 2), nearest + 26):
		var point: Vector3 = road[index % count].position
		var distance := Vector2(position.x - point.x, position.z - point.z).length_squared()
		if distance < best:
			best = distance
			selected = index
	nearest = maxi(nearest, selected)
	var speed: float = lab.car.velocity.length()
	var ahead := nearest + ceili((5.0 + speed * 0.18) / 1.4)
	var target: Vector3 = road[ahead % count].position
	var heading := Vector2(-lab.car.global_basis.z.x, -lab.car.global_basis.z.z).normalized()
	# Counter drift using measured motion, without changing the vehicle's state.
	var aim := Vector2(target.x - position.x, target.z - position.z) - Vector2(lab.car.velocity.x, lab.car.velocity.z) * 0.25
	var angle := heading.angle_to(aim)
	if speed > 13.4: braking = true
	elif speed < 12.6: braking = false
	if braking: lab.car.set_buttons(true, true)
	else: lab.car.set_buttons(angle < -0.035, angle > 0.035)

func image_file(name: String) -> void:
	if lab.test_mode != "practice-render": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check("actual window screenshot " + name, get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join(name + ".png")) == OK)

func run() -> void:
	var unit: Dictionary = Unit.new().run()
	for entry in unit.checks: check("coordinator: " + str(entry.name), bool(entry.ok))
	check("practice has twelve actual track gates", lab.track.layout.checkpoints.size() == 12)
	check("approved values remain in vehicle", lab.car.tuning.values == lab.car.tuning.get_script().new().values)
	check("real renderer when requested", lab.test_mode != "practice-render" or DisplayServer.get_name() != "headless", DisplayServer.get_name())
	var driving_values: Dictionary = lab.car.tuning.values.duplicate()
	check("camera controls are separate from eight driving values", lab.tuning_panel.view_sliders.size() == 2 and lab.tuning_panel.sliders.size() == 8 and lab.view_pitch_degrees == 56.0 and lab.view_size_m == 44.5)
	check("invalid camera settings rejected", not lab.set_view_value("view_pitch_degrees", NAN) and not lab.set_view_value("view_pitch_degrees", 90) and not lab.set_view_value("view_size_m", 0) and not lab.set_view_value("other", 10))
	lab.tuning_panel.view_sliders.view_pitch_degrees.value = 82.0
	lab.tuning_panel.view_sliders.view_size_m.value = 18.0
	await tick()
	var actual_pitch := rad_to_deg(asin(clampf(lab.camera.global_basis.z.y, -1, 1)))
	check("camera sliders affect actual camera without changing driving", absf(actual_pitch - 82.0) < 0.01 and lab.camera.size == 18.0 and lab.car.tuning.values == driving_values, {"actual_pitch": actual_pitch, "orthographic_size": lab.camera.size})
	_r()
	check("R preserves chosen camera view", lab.view_pitch_degrees == 82.0 and lab.view_size_m == 18.0)
	lab.tuning_panel.visible = true
	await image_file("practice-camera-tuning")
	lab.tuning_panel.visible = false
	lab.tuning_panel.view_sliders.view_pitch_degrees.value = 56.0
	lab.tuning_panel.view_sliders.view_size_m.value = 44.5
	_r()
	var spawn: Vector3 = lab.car.global_position
	check("R begins a new countdown with no results", lab.practice.phase == "countdown" and lab.practice.snapshot().results.is_empty() and lab.practice.events.is_empty())
	lab.car.set_buttons(true, false)
	await tick()
	check("countdown holds car even with steering input", lab.car.global_position == spawn and lab.car.velocity == Vector3.ZERO and not lab.car.request_nitro())
	var time_before: float = lab.practice.sim_seconds
	var saved_mode: String = lab.test_mode
	lab.test_mode = ""
	lab._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	lab.test_mode = saved_mode
	for _i in range(12): await tick()
	check("injected focus-out route pauses countdown and clears input", lab.car.paused and lab.pause_panel.visible and lab.practice.sim_seconds == time_before and lab.car.global_position == spawn and lab.held.is_empty())
	(lab.pause_panel.find_child("ResumeDriving", true, false) as Button).pressed.emit()
	await image_file("practice-countdown")
	var wait_frames := 0
	while lab.practice.phase == "countdown" and wait_frames < 220:
		await tick()
		wait_frames += 1
	check("countdown resumes to ready", lab.practice.phase == "ready" and lab.practice.error.is_empty())
	# Enable the input driver before the next movement callback. No transform,
	# velocity, tuning, detector or rules mutation occurs during the real lap.
	nearest = 0
	driving = true
	var initial_resets: int = lab.resets
	var start_frame := Engine.get_physics_frames()
	var captured_running := false
	while lab.practice.phase not in ["finished", "invalid"] and Engine.get_physics_frames() - start_frame < 7000:
		await tick()
		if not captured_running and lab.practice.phase == "running":
			captured_running = true
			await image_file("practice-running")
	driving = false
	lab.car.set_buttons(false, false)
	var gates: Array[int] = []
	for event in lab.practice.events: gates.append(int(event.physical_gate))
	measurements = {"lap_state": lab.practice.snapshot(), "events": lab.practice.events.duplicate(true),
		"samples": samples, "movement_frames": movement_frames, "path_m": path_m,
		"max_segment_m": max_segment, "finite": finite, "resets_during_lap": lab.resets - initial_resets,
		"driver": "digital left/right/brake only; no teleport/velocity/tuning injection", "physics_hz": Engine.physics_ticks_per_second}
	check("actual vehicle completes a full practice circle", lab.practice.phase == "finished", measurements.lap_state)
	check("actual gates pass 0-start,1 through 11,0-finish", gates == [0,1,2,3,4,5,6,7,8,9,10,11,0], gates)
	check("actual lap has continuous finite movement and no reset", finite and max_segment <= 2.0 and path_m > 350.0 and movement_frames > 1000 and lab.resets == initial_resets, {"distance": path_m, "steps": movement_frames, "max_segment": max_segment})
	var results: Array = lab.practice.snapshot().results
	var measured_ms := floori((float(lab.practice.events[-1].sim_seconds) - float(lab.practice.events[0].sim_seconds)) * 1000.0 + 0.000001) if lab.practice.events.size() >= 2 else -1
	check("one final result equals independently measured line-to-line clock", results.size() == 1 and results[0].finish_time_ms == lab.practice.elapsed_ms and lab.practice.elapsed_ms == measured_ms and measured_ms > 15000, {"recorded": lab.practice.elapsed_ms, "independent_ms": measured_ms})
	if lab.practice.phase == "finished":
		var finish_time: int = lab.practice.elapsed_ms
		var finish_position: Vector3 = lab.car.global_position
		for _i in range(8): await tick()
		check("finish freezes vehicle and timing", lab.car.global_position == finish_position and lab.practice.elapsed_ms == finish_time)
		check("finish HUD presents actual lap and restart", lab.practice_hud.visible and lab.practice_hud.state.phase == "finished" and lab.practice_hud.clock_label.text.contains(lab._practice_clock(finish_time)))
		await image_file("practice-finished")
		await layout_checks()
		lab.practice_hud.restart_button.pressed.emit()
		check("finish restart button starts a fresh session", lab.practice.phase == "countdown" and lab.practice.events.is_empty() and lab.practice.elapsed_ms == 0 and lab.practice.snapshot().results.is_empty())
	_r()
	check("actual R after lap clears results, sequence and nitro", lab.practice.phase == "countdown" and lab.practice.expected_gate == 0 and lab.practice.event_sequence == 0 and lab.practice.elapsed_ms == 0 and lab.practice.snapshot().results.is_empty() and lab.car.control._fuel == 0.0)
	while lab.practice.phase == "countdown": await tick()
	nearest = 0
	driving = true
	var restart_drive_frame := Engine.get_physics_frames()
	while lab.practice.passed_checkpoints < 1 and lab.practice.phase != "invalid" and Engine.get_physics_frames() - restart_drive_frame < 400: await tick()
	driving = false
	check("second real drive acquires checkpoint progress", lab.practice.phase == "running" and lab.practice.passed_checkpoints >= 1)
	var running_time: int = lab.practice.elapsed_ms
	var running_position: Vector3 = lab.car.global_position
	lab.test_mode = ""
	lab._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	lab.test_mode = saved_mode
	for _i in range(12): await tick()
	check("injected focus-out freezes running lap clock and car", lab.practice.elapsed_ms == running_time and lab.car.global_position == running_position)
	_r()
	check("R during actual lap discards progress and paused state", lab.practice.phase == "countdown" and lab.practice.passed_checkpoints == 0 and lab.practice.expected_gate == 0 and lab.practice.elapsed_ms == 0 and not lab.car.paused)
	_r()
	check("repeated R cannot preserve any prior crossing", lab.practice.events.is_empty() and lab.practice.event_sequence == 0 and lab.practice.snapshot().results.is_empty())
	finish()

func layout_checks() -> void:
	var window := get_tree().root
	# The headless display starts at 64x64. Use an explicit desktop fixture
	# so returning from compact mode actually crosses the 900px threshold.
	var original_size := Vector2i(1280, 800)
	window.size = original_size
	await tick()
	await tick()
	check("explicit desktop viewport for responsive gate", get_viewport().get_visible_rect().size.x >= 900.0)
	for size in [Vector2i(844, 390), Vector2i(640, 360)]:
		window.size = size
		await tick()
		await tick()
		var actual: Vector2 = get_viewport().get_visible_rect().size
		var card: Rect2 = lab.practice_hud.card.get_global_rect()
		var clear := true
		for control in lab.controls.values(): clear = clear and not card.intersects(control.get_global_rect())
		check("actual compact HUD clears driving buttons " + str(size), clear and card.end.x <= actual.x - 16 and card.end.y <= actual.y - 174, {"card_end": [card.end.x, card.end.y], "viewport": [actual.x, actual.y]})
		var touch := InputEventScreenTouch.new()
		touch.index = 8
		touch.pressed = true
		touch.position = lab.practice_hud.restart_button.get_global_rect().get_center()
		lab._input(touch)
		var drag := InputEventScreenDrag.new()
		drag.index = 8
		drag.position = lab.controls.nitro_left.get_global_rect().get_center()
		lab._input(drag)
		check("HUD pointer remains captured outside card " + str(size), lab.pointers.get(8) == "practice-ui" and lab.button_state() == Vector2i.ZERO and lab.nitro_requests == 0)
		touch.pressed = false
		lab._input(touch)
		await image_file("practice-" + str(size.x) + "x" + str(size.y))
		lab.toggle_tuning()
		await tick()
		check("compact tuning is paused and mutually exclusive " + str(size), lab.car.paused and not lab.practice_hud.visible and not lab.pause_panel.visible)
		await image_file("practice-tuning-" + str(size.x))
		_r()
		await tick()
		check("R while compact tuning open remains paused " + str(size), lab.car.paused and lab.practice.phase == "countdown" and lab.practice.snapshot().countdown_remaining_ms == 3000)
		var paused_position: Vector3 = lab.car.global_position
		for _i in range(12): await tick()
		check("compact F2 freezes countdown and car " + str(size), lab.practice.snapshot().countdown_remaining_ms == 3000 and lab.car.global_position == paused_position)
		lab.toggle_tuning()
		await tick()
		check("closing compact tuning resumes its own pause " + str(size), not lab.car.paused and lab.practice_hud.visible)
	window.size = original_size
	await tick()
	lab.toggle_tuning()
	window.size = Vector2i(844, 390)
	await tick()
	check("resize into compact tuning acquires a pause", lab.car.paused and lab.tuning_paused)
	var paused_countdown: int = lab.practice.snapshot().countdown_remaining_ms
	var paused_position: Vector3 = lab.car.global_position
	for _i in range(12): await tick()
	check("resize pause actually freezes countdown and car", lab.practice.snapshot().countdown_remaining_ms == paused_countdown and lab.car.global_position == paused_position)
	window.size = original_size
	await tick()
	await tick()
	check("resize wide releases only tuning-owned pause", not lab.car.paused and not lab.tuning_paused, {"paused": lab.car.paused, "tuning_paused": lab.tuning_paused, "viewport": str(get_viewport().get_visible_rect().size), "requested": str(original_size)})
	window.size = Vector2i(844, 390)
	await tick()
	var saved_mode: String = lab.test_mode
	lab.test_mode = ""
	lab._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	lab.test_mode = saved_mode
	window.size = original_size
	await tick()
	lab.toggle_tuning()
	await tick()
	check("resize and F2 close do not release focus-owned pause", lab.car.paused and not lab.tuning_paused)
	(lab.pause_panel.find_child("ResumeDriving", true, false) as Button).pressed.emit()
	await tick()

func finish() -> void:
	var result := {"passed": passed, "failed": failed, "mode": lab.test_mode, "checks": checks,
		"measurements": measurements, "engine": Engine.get_version_info().string,
		"network_used": false, "physical_phone_test": false, "lap_completed": bool(measurements.get("lap_state", {}).get("phase", "") == "finished")}
	var file := FileAccess.open(lab.evidence_dir.path_join(lab.test_mode + "-result.json"), FileAccess.WRITE)
	if file == null: check("result written", false, FileAccess.get_open_error())
	else:
		file.store_string(JSON.stringify(result, "\t") + "\n")
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK: check("result written", false, write_error)
	print("PRACTICE_ACCEPTANCE_RESULT passed=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)
