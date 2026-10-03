extends Node
var lab
var checks: Array[Dictionary] = []
var measurements: Dictionary = {}
var duplicate_probe := false
var duplicate_ok := false

func _ready() -> void:
	process_physics_priority = 100
	run.call_deferred()

func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	if not ok: print("FEEDBACK_FAILED ", name, " ", detail)

func tick() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _physics_process(dt: float) -> void:
	if not duplicate_probe: return
	duplicate_probe = false
	var before: int = lab.car.suspension.snapshot().total_ray_queries
	var result: Dictionary = lab.car.suspension.step(dt, 0, 0, 0)
	duplicate_ok = int(result.total_ray_queries) == before and result.ray_queries_this_tick == 0

func sample_wheels(x: float, grounded := true) -> Array:
	var out: Array = []
	for z in [-1.0, -1.0, 1.0, 1.0]:
		var point := Vector3(x, 0, z)
		out.append({"point": point, "center": point + Vector3.UP * 0.34, "normal": Vector3.UP, "grounded": grounded})
	return out

func run() -> void:
	await tick()
	var approved: Dictionary = lab.car.tuning.values.duplicate(true)
	var initial: Dictionary = lab.car.suspension.snapshot()
	check("startup frozen car samples all four real ground contacts", initial.grounded_count == 4 and initial.total_ray_queries >= 4, initial)
	for wheel in initial.wheels:
		check("stationary wheel touches ground within1mm", absf((wheel.center.y - wheel.radius) - wheel.point.y) < 0.001)
	var rays: int = initial.total_ray_queries
	for _i in range(6): await tick()
	check("countdown freezes query and spring after initialization", lab.car.suspension.snapshot().total_ray_queries == rays)
	check("four independent safe suspension sliders", lab.tuning_panel.suspension_sliders.size() == 4)
	check("bad and excessive suspension values rejected", not lab.car.suspension.set_value("suspension_hz", NAN) and not lab.car.suspension.set_value("suspension_travel", 1.0) and not lab.car.suspension.set_value("none", 1.0))
	lab.tuning_panel.suspension_sliders.suspension_hz.value = 3.0
	check("suspension tuning preserves driving values and camera", lab.car.suspension.values.suspension_hz == 3.0 and approved == lab.car.tuning.values and lab.view_pitch_degrees == 56 and lab.view_size_m == 44.5)
	lab.tuning_panel.suspension_sliders.suspension_hz.value = 4.0
	lab.reset_car()
	duplicate_probe = true
	await tick()
	check("same callback repeated step never exceeds four rays", duplicate_ok)
	var root_pose: Transform3D = lab.car.global_transform
	var hold_total: int = lab.car.suspension.snapshot().total_ray_queries
	lab.car.paused = true
	for _i in range(5): await tick()
	check("pause freezes vehicle and suspension rays", lab.car.global_transform == root_pose and lab.car.suspension.snapshot().total_ray_queries == hold_total)
	lab.car.paused = false
	check_audio()
	check_trails()
	await check_scale_and_contacts()
	await check_eight_cars()
	lab.reset_car()
	while lab.practice.phase == "countdown": await tick()
	# Real driving to build charge and marks; no position/velocity injection.
	lab.car.set_buttons(true, false)
	var seen := 0
	var end := Engine.get_physics_frames() + 420
	while Engine.get_physics_frames() < end:
		await tick()
		seen = maxi(seen, int(lab.skid_marks.snapshot().active_quads))
		check("running suspension bounded4 and finite", lab.car.suspension.snapshot().ray_queries_this_tick <= 4 and lab.car.suspension.snapshot().finite)
	check("real drift produces rear tire marks", seen > 10, seen)
	measurements.real_car = {"suspension": lab.car.suspension.snapshot(), "marks": lab.skid_marks.snapshot(), "physics_mean_usec": lab.car.telemetry.get("mean_script_usec", 0)}
	lab.car.request_nitro()
	for _i in range(12): await tick()
	check("audio playback resources and fixed voice budget", lab.audio_feedback.snapshot().loaded and lab.audio_feedback.snapshot().voices == 6)
	if lab.test_mode == "feedback-render":
		await RenderingServer.frame_post_draw
		check("actual feedback view saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("feedback-driving.png")) == OK)
		lab.toggle_tuning()
		await tick()
		await RenderingServer.frame_post_draw
		check("actual suspension controls view saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("feedback-tuning.png")) == OK)
		lab.toggle_tuning()
	var age: float = lab.skid_marks.snapshot().age_seconds
	var sound_clock: float = lab.audio_feedback.snapshot().clock
	lab.car.paused = true
	for _i in range(8): await tick()
	check("pause freezes trail lifetime and audio clock", lab.skid_marks.snapshot().age_seconds == age and lab.audio_feedback.snapshot().clock == sound_clock)
	lab.reset_car()
	check("R clears geometry and audio state without modifying tuning", lab.skid_marks.snapshot().active_quads == 0 and lab.audio_feedback.snapshot().clock == 0 and lab.car.tuning.values == approved)
	await tick()
	check("R resamples real ground once", lab.car.suspension.snapshot().grounded_count == 4)
	var failed := 0
	for entry in checks:
		if not entry.ok: failed += 1
	var result := {"passed": checks.size() - failed, "failed": failed, "checks": checks, "measurements": measurements, "heard": false, "driver_injected": "digital left only; pure trail observations separate", "mode": lab.test_mode}
	var file := FileAccess.open(lab.evidence_dir.path_join(lab.test_mode + "-result.json"), FileAccess.WRITE)
	if file == null: lab.quit_safely(2); return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("FEEDBACK_ACCEPTANCE_RESULT passed=", result.passed, " failed=", failed)
	lab.quit_safely(0 if failed == 0 else 1)

func check_audio() -> void:
	var audio = lab.audio_feedback
	check("six dot PCM assets loaded", audio.loaded and audio.voices.size() == 6)
	for name in audio.LOOPS:
		check("actual loop configured " + name, audio.voices[name].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and audio.voices[name].stream.loop_end == 96000)
	audio.update_feedback(0.1, {"speed": 30, "forward_speed": 30, "slip_degrees": 25, "boost_active": true}, {}, false, false)
	check("drift and nitro produce nonzero mix", audio.levels.tire_skid_loop > 0 and audio.levels.nitro_loop > 0)
	var impacts: int = audio.play_counts.impact_soft
	audio.update_feedback(0.1, {"wall_impact_speed": 8}, {}, false, false)
	audio.update_feedback(0.01, {"wall_impact_speed": 8}, {}, false, false)
	check("impact rate limited", audio.play_counts.impact_soft == impacts + 1)
	audio.set_muted(true)
	check("mute immediately silences all fixed voices", audio.voices.impact_soft.volume_db == -80 and audio.voices.engine_idle_loop.volume_db == -80)
	lab.tuning_panel._process(0.01)
	check("keyboard mute synchronizes panel switch", not lab.tuning_panel.sound.button_pressed)
	audio.set_muted(false)
	audio.reset()
	var beeps: int = audio.play_counts.countdown_beep
	for ms in [3000, 2500, 2000, 1500, 1000]: audio.update_feedback(0.01, {}, {"phase": "countdown", "countdown_remaining_ms": ms}, false, true)
	audio.update_feedback(0.01, {}, {"phase": "ready"}, false, false)
	check("countdown beeps once3-2-1 and ready", audio.play_counts.countdown_beep == beeps + 4)
	audio.reset()

func check_trails() -> void:
	var marks = load("res://arcade_skid_marks.gd").new()
	add_child(marks)
	var drifting := {"forward_speed": 20, "slip_degrees": 25, "mode": "forward"}
	marks.step(0.016, drifting, sample_wheels(0))
	marks.step(0.016, drifting, sample_wheels(0.1))
	check("stationary and short movement create no marks", marks.snapshot().active_quads == 0)
	marks.step(0.016, drifting, sample_wheels(0.3))
	check("each grounded rear tire creates one quad", marks.snapshot().active_quads == 2)
	var age: float = marks.snapshot().age_seconds
	marks.step(2.0, drifting, sample_wheels(0.6), true)
	check("frozen marks retain lifetime and geometry", marks.snapshot().age_seconds == age and marks.snapshot().active_quads == 2)
	marks.step(0.016, drifting, sample_wheels(4.0))
	check("resume reanchors instead of drawing long bridge", marks.snapshot().active_quads == 2)
	marks.step(0.016, drifting, sample_wheels(4.3, false))
	check("ungrounded rear wheels create no marks", marks.snapshot().active_quads == 2)
	marks.reset()
	for i in range(2200): marks.step(0.001, drifting, sample_wheels(float(i) * 0.25))
	var full: Dictionary = marks.snapshot()
	check("fixed pool caps4096 and8 mesh nodes", full.active_quads == 4096 and full.mesh_nodes == 8 and full.capacity == 4096 and full.finite, full)
	marks.step(9.0, {}, [])
	check("expired quads fully reclaimed", marks.snapshot().active_quads == 0)
	marks.reset()
	check("R reuses mesh storage and clears clock", marks.snapshot().mesh_nodes == 8 and marks.snapshot().age_seconds == 0)
	measurements.trail_budget = full
	marks.queue_free()

func check_scale_and_contacts() -> void:
	var dummy = lab.car.get_script().new()
	add_child(dummy)
	dummy.driver_enabled = false
	dummy.request_reset(Transform3D(Basis.IDENTITY, Vector3(0, 0.145, 0)))
	dummy.visual_root.scale = Vector3.ONE * 1.1
	check("uniform model scale recaptured", dummy.suspension.configure(dummy) and dummy.visual_root.scale.is_equal_approx(Vector3.ONE * 1.1))
	await tick()
	var wheels: Array = dummy.suspension.snapshot().wheels
	for wheel in wheels: check("scaled wheel remains tangent to real ground", wheel.grounded and absf(wheel.center.y - wheel.radius - wheel.point.y) < 0.001 and absf(wheel.radius - 0.374) < 0.0001)
	dummy.request_reset(Transform3D(Basis.IDENTITY, Vector3(220, 0.145, 0)))
	await tick()
	check("lost real ground gives finite bounded droop", dummy.suspension.snapshot().grounded_count == 0 and dummy.suspension.snapshot().finite)
	dummy.queue_free()
	await tick()

func check_eight_cars() -> void:
	var cars: Array = []
	for i in range(8):
		var dummy = lab.car.get_script().new()
		add_child(dummy)
		dummy.driver_enabled = false
		dummy.request_reset(Transform3D(Basis.IDENTITY, Vector3(-12 + i * 3, 0.145, 0)))
		cars.append(dummy)
	for _i in range(90): await tick()
	var queries := 0
	var usec := 0.0
	for car in cars:
		var data: Dictionary = car.suspension.snapshot()
		check("eight-car probe4 rays per tick and valid ground", data.ray_queries_this_tick == 4 and data.grounded_count == 4 and data.finite)
		queries += int(data.ray_queries_this_tick)
		usec += float(data.mean_usec)
		car.queue_free()
	measurements.eight_active_probe_cars = {"rays_per_tick": queries, "summed_mean_suspension_usec": usec, "scope": "8 stationary active cars plus frozen main; local machine only; excludes snapshot deep copies"}
	check("eight-car query upper bound32", queries == 32)
	await tick()
