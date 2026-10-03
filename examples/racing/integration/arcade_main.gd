extends Node3D
const Vehicle = preload("res://arcade_vehicle.gd")
const Harbor = preload("res://track/harbor.gd")
const TuningPanel = preload("res://arcade_tuning_panel.gd")
const Practice = preload("res://practice_session.gd")
const PracticeHUD = preload("res://practice_hud.gd")
const SkidMarks = preload("res://arcade_skid_marks.gd")
const FeedbackAudio = preload("res://arcade_audio.gd")
const VIEW_LIMITS := {"view_pitch_degrees": Vector2(35, 85), "view_size_m": Vector2(12, 50)}
var view_pitch_degrees := 56.0
var view_size_m := 44.5
var car
var track
var camera: Camera3D
var hud: Label
var held: Dictionary = {}
var pointers: Dictionary = {}
var controls: Dictionary = {}
var fuel_bars: Array[ColorRect] = []
var nitro_edge := false
var nitro_requests := 0
var test_mode := ""
var evidence_dir := ""
var overview := false
var resets := 0
var touch_stamp := -1000
var pause_panel: PanelContainer
var flames: Array[MeshInstance3D] = []
var tuning_panel
var tuning_paused := false
var practice
var practice_hud
var skid_marks
var audio_feedback
var quitting := false

func practice_enabled() -> bool:
	return test_mode.is_empty() or test_mode.begins_with("practice") or test_mode.begins_with("feedback")

func quit_safely(code := 0) -> void:
	if quitting: return
	quitting = true
	if is_instance_valid(car): car.paused = true
	if is_instance_valid(audio_feedback): audio_feedback.shutdown()
	# WAV playbacks are released by the audio mixer asynchronously. Keep the
	# tree alive briefly after stopping them; fixed-fps simulated time is not
	# suitable here. This bounded wall-time wait runs only on application exit.
	var deadline := Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	get_tree().quit(code)

func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_physics_priority = -100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="): test_mode = a.trim_prefix("--test=")
		if a.begins_with("--evidence-dir="): evidence_dir = a.trim_prefix("--evidence-dir=")
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("91b1ab")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9e5cc")
	env.ambient_light_energy = 0.22
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -30, 0)
	sun.light_energy = 0.65
	add_child(sun)
	track = Harbor.new()
	track.flat_track = true
	add_child(track)
	track.grid_models.visible = false
	_planar_collision_layers(track)
	car = Vehicle.new()
	car.name = "StreetCar"
	if not test_mode.is_empty() and not practice_enabled(): car.tuning.use_preset("original")
	add_child(car)
	skid_marks = SkidMarks.new()
	add_child(skid_marks)
	car.movement_completed.connect(_feedback_step)
	audio_feedback = FeedbackAudio.new()
	add_child(audio_feedback)
	if practice_enabled():
		practice = Practice.new()
		car.movement_completed.connect(_practice_step)
	for x in [-0.55, 0.55]:
		var flame := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 0.18
		cone.height = 0.8
		cone.radial_segments = 8
		flame.mesh = cone
		flame.rotation.x = PI * 0.5
		flame.position = Vector3(x, 0.35, 2.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("6ce7ee")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.material_override = mat
		car.add_child(flame)
		flames.append(flame)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	camera.far = 800
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	_build_ui()
	get_viewport().size_changed.connect(_layout_controls)
	reset_car()
	if not test_mode.is_empty():
		var script = load("res://practice_acceptance.gd" if practice_enabled() else "res://arcade_acceptance.gd")
		if script == null or not script.can_instantiate():
			quit_safely(64)
			return
		if test_mode.begins_with("feedback"):
			script = load("res://feedback_acceptance.gd")
		var tests = script.new()
		tests.lab = self
		add_child(tests)

func _planar_collision_layers(node: Node) -> void:
	if node is StaticBody3D:
		node.collision_layer = 8 if node.name == "DriveSurface" or node.get_parent().name == "QuayFoundation" else 2
		if node.name == "ContinuousGuardrails":
			for child in node.get_children():
				if child is CollisionShape3D:
					(child.shape as BoxShape3D).size.y = 2.4
					child.position.y = 0.8
	for child in node.get_children():
		_planar_collision_layers(child)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	if practice != null:
		practice_hud = PracticeHUD.new()
		layer.add_child(practice_hud)
		practice_hud.reset_requested.connect(reset_car)
		hud = practice_hud.driving_label
	else:
		var panel := PanelContainer.new()
		panel.position = Vector2(16, 14)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(panel)
		hud = Label.new()
		hud.add_theme_font_size_override("font_size", 18)
		hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(hud)
	for kind in ["left", "right", "nitro_left", "nitro_right"]:
		var button := ColorRect.new()
		button.color = Color(0.12, 0.22, 0.26, 0.87)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(button)
		var caption := Label.new()
		caption.text = "◀" if kind == "left" else ("▶" if kind == "right" else "氮气")
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 26)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(caption)
		controls[kind] = button
	for i in range(3):
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		fuel_bars.append(bar)
	pause_panel = PanelContainer.new()
	layer.add_child(pause_panel)
	var resume := Button.new()
	resume.name = "ResumeDriving"
	resume.text = "已暂停 · 继续驾驶"
	resume.custom_minimum_size = Vector2(260, 64)
	resume.pressed.connect(func(): car.paused = false; held.clear(); pointers.clear(); nitro_edge = false; nitro_requests = 0)
	pause_panel.add_child(resume)
	pause_panel.visible = false
	tuning_panel = TuningPanel.new()
	tuning_panel.vehicle = car
	tuning_panel.view_controller = self
	layer.add_child(tuning_panel)
	_layout_controls()

func _layout_controls() -> void:
	var size := get_viewport().get_visible_rect().size
	var button_size := Vector2(88, 72)
	controls.left.position = Vector2(18, size.y - 90)
	controls.right.position = Vector2(size.x - 106, size.y - 90)
	controls.nitro_left.position = Vector2(18, size.y - 174)
	controls.nitro_right.position = Vector2(size.x - 106, size.y - 174)
	for button in controls.values(): button.size = button_size
	for i in range(3):
		fuel_bars[i].position = Vector2(size.x * 0.5 - 94 + i * 65, size.y - 47)
		fuel_bars[i].size = Vector2(58, 14)
	if practice_hud == null: hud.custom_minimum_size = Vector2(minf(560, size.x - 32), 0)
	pause_panel.position = (size - Vector2(260, 64)) * 0.5
	tuning_panel.layout(size)
	sync_tuning_pause()
	pointers.clear()
	nitro_edge = false
	nitro_requests = 0

func reset_car() -> void:
	held.clear()
	pointers.clear()
	nitro_edge = false
	nitro_requests = 0
	var p: Vector3 = track.layout.spawns[0].position
	car.request_reset(Transform3D(Basis.IDENTITY, p))
	if skid_marks != null: skid_marks.reset()
	if audio_feedback != null: audio_feedback.reset()
	tuning_paused = false
	car.paused = false
	if practice != null:
		practice.restart(track.layout.checkpoints, car.global_position)
		car.practice_hold = practice.holds_vehicle()
	sync_tuning_pause()
	resets += 1

func _feedback_step(_previous: Vector3, _current: Vector3, dt: float) -> void:
	skid_marks.step(dt, car.telemetry, car.suspension.snapshot().get("wheels", []), car.paused or car.practice_hold)

func _practice_step(previous: Vector3, current: Vector3, dt: float) -> void:
	practice.step(previous, current, dt)
	car.practice_hold = practice.holds_vehicle()
	# Checkpoint paint follows the trusted detector's next physical gate.
	for marker in track.markers.get_children():
		var id := int(str(marker.name).trim_prefix("CP_"))
		marker.visible = id == practice.expected_gate or practice.phase == "countdown"

func _pointer_kind(position: Vector2) -> String:
	if tuning_panel.visible and tuning_panel.get_global_rect().has_point(position): return ""
	if practice_hud != null and practice_hud.is_visible_in_tree() and practice_hud.card.get_global_rect().has_point(position): return ""
	for kind in controls:
		if controls[kind].get_global_rect().has_point(position): return kind
	return ""

func _pointer_down(id, position: Vector2) -> void:
	if tuning_panel.visible and tuning_panel.get_global_rect().has_point(position):
		pointers[id] = "tuning" # Captured until release, including drags outside UI.
		return
	if practice_hud != null and practice_hud.is_visible_in_tree() and practice_hud.card.get_global_rect().has_point(position):
		pointers[id] = "practice-ui"
		return
	var kind := _pointer_kind(position)
	pointers[id] = kind

func _nitro_is_held() -> bool:
	if bool(held.get(KEY_SPACE, false)): return true
	for kind in pointers.values():
		if str(kind).begins_with("nitro"): return true
	return false

func _input(event: InputEvent) -> void:
	var nitro_before := _nitro_is_held()
	if event is InputEventKey and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		held[key] = event.pressed
		if event.pressed:
			if key == KEY_F2: toggle_tuning()
			if key == KEY_R: reset_car()
			if key == KEY_M: audio_feedback.set_muted(not audio_feedback.muted)
			if key == KEY_TAB: overview = not overview
			if key == KEY_ESCAPE: quit_safely()
	elif event is InputEventScreenTouch:
		touch_stamp = Time.get_ticks_msec()
		if event.pressed: _pointer_down(event.index, event.position)
		else: pointers.erase(event.index)
	elif event is InputEventScreenDrag:
		touch_stamp = Time.get_ticks_msec()
		if pointers.has(event.index) and pointers[event.index] not in ["tuning", "practice-ui"]:
			pointers[event.index] = _pointer_kind(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			pointers.erase("mouse")
		elif Time.get_ticks_msec() - touch_stamp > 150:
			_pointer_down("mouse", event.position)
	elif event is InputEventMouseMotion and pointers.has("mouse") and pointers.mouse not in ["tuning", "practice-ui"]:
		pointers.mouse = _pointer_kind(event.position)
	# One logical action for both screen buttons and the keyboard. A release
	# followed by another press remains another edge, even within one tick.
	if not nitro_before and _nitro_is_held():
		nitro_requests += 1
		nitro_edge = true

func button_state() -> Vector2i:
	return Vector2i(int(bool(held.get(KEY_A, false)) or bool(held.get(KEY_LEFT, false)) or "left" in pointers.values()),
		int(bool(held.get(KEY_D, false)) or bool(held.get(KEY_RIGHT, false)) or "right" in pointers.values()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: quit_safely()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		pointers.clear()
		nitro_edge = false
		nitro_requests = 0
		if test_mode.is_empty() and is_instance_valid(car):
			tuning_paused = false
			car.paused = true

func _physics_process(_dt: float) -> void:
	if test_mode.is_empty() and not car.paused:
		apply_controls()

func apply_controls() -> void:
	if car.paused: return
	if car.practice_hold:
		nitro_requests = 0
		nitro_edge = false
		car.set_buttons(false, false)
		return
	var buttons := button_state()
	car.set_buttons(buttons.x != 0, buttons.y != 0)
	for _i in range(nitro_requests):
		car.request_nitro()
	nitro_edge = false
	nitro_requests = 0

func _process(_dt: float) -> void:
	audio_feedback.update_feedback(_dt, car.telemetry, practice.snapshot() if practice != null else {}, car.paused, car.practice_hold)
	var target: Vector3 = car.get_global_transform_interpolated().origin
	var focus := Vector3.ZERO if overview else target + Vector3(0, 0, -3)
	var pitch := deg_to_rad(view_pitch_degrees)
	var offset := Vector3(13, 0, 20).normalized() * cos(pitch) * 32.0 + Vector3.UP * sin(pitch) * 32.0
	camera.size = 175 if overview else view_size_m
	camera.position = Vector3(0, 180, 12) if overview else focus + offset
	camera.look_at(focus, Vector3.UP)
	var fuel := float(car.telemetry.get("fuel", 0))
	var remaining := float(car.telemetry.get("boost_remaining", 0))
	var mode: String = car.telemetry.get("mode", "forward")
	hud.text = "港区 · 单人练习\n←/A  →/D 转向；双键制动/倒车；空格 氮气\n%.0f km/h  氮气 %.1f/3  喷射 %.1f 秒  %s\n漂移充能 · R重开  F2调参  TAB全景  ESC退出" % [
		float(car.telemetry.get("speed", 0)) * 3.6, fuel, remaining,
		"倒车" if mode == "reverse" else ("制动" if mode == "brake" else ("漂移" if car.telemetry.get("drifting", false) else "前进"))]
	if practice != null:
		practice_hud.set_state(practice.snapshot())
		practice_hud.visible = not (tuning_panel.visible and get_viewport().get_visible_rect().size.x < 900.0)
		hud.text = "%.0f km/h · 氮气 %.1f/3 · %s" % [float(car.telemetry.get("speed", 0)) * 3.6, fuel, "倒车" if mode == "reverse" else ("漂移" if car.telemetry.get("drifting", false) else "前进")]
	for i in range(3):
		var amount := clampf(fuel - i, 0.0, 1.0)
		fuel_bars[i].color = Color("46ccd2").lerp(Color("213c49"), 1.0 - amount)
	var buttons := button_state()
	controls.left.color = Color("408d96") if buttons.x else Color(0.12, 0.22, 0.26, 0.87)
	controls.right.color = Color("408d96") if buttons.y else Color(0.12, 0.22, 0.26, 0.87)
	var nitro_color := Color("56dbe4") if remaining > 0 else (Color("328a92") if fuel >= 1 else Color("34434a"))
	controls.nitro_left.color = nitro_color
	controls.nitro_right.color = nitro_color
	for flame in flames: flame.visible = bool(car.telemetry.get("boost_active", false))
	pause_panel.visible = car.paused and not tuning_panel.visible

func _practice_clock(ms: int) -> String:
	var seconds := floori(float(ms) / 1000.0)
	return "%02d:%02d.%03d" % [floori(float(seconds) / 60.0), seconds % 60, ms % 1000]

func set_view_value(key: String, value: float) -> bool:
	if not VIEW_LIMITS.has(key) or not is_finite(value): return false
	var bounds: Vector2 = VIEW_LIMITS[key]
	if value < bounds.x or value > bounds.y: return false
	set(key, value)
	return true

func toggle_tuning() -> void:
	tuning_panel.visible = not tuning_panel.visible
	tuning_panel.layout(get_viewport().get_visible_rect().size)
	held.clear()
	pointers.clear()
	nitro_requests = 0
	nitro_edge = false
	sync_tuning_pause()

func sync_tuning_pause() -> void:
	var needs_pause: bool = tuning_panel.visible and get_viewport().get_visible_rect().size.x < 900.0
	if needs_pause and not car.paused:
		tuning_paused = true
		car.paused = true
	elif not needs_pause and tuning_paused:
		car.paused = false
		tuning_paused = false
	if is_instance_valid(practice_hud): practice_hud.visible = not needs_pause
	if is_instance_valid(pause_panel): pause_panel.visible = car.paused and not tuning_panel.visible
