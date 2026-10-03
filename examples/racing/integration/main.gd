extends Node3D

const Vehicle = preload("res://vehicle.gd")
const Harbor = preload("res://track/harbor.gd")
var car: RigidBody3D
var track: Node3D
var camera: Camera3D
var hud: Label
var held: Dictionary = {}
var test_mode := ""
var evidence_dir := ""
var overview := false
var resets := 0

func _ready() -> void:
	process_physics_priority = -100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="): test_mode = a.trim_prefix("--test=")
		if a.begins_with("--evidence-dir="): evidence_dir = a.trim_prefix("--evidence-dir=")
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("91b1ab")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e9e5cc")
	environment.ambient_light_energy = 0.22
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -30, 0)
	sun.light_energy = 0.65
	add_child(sun)
	track = Harbor.new()
	add_child(track)
	track.grid_models.visible = false
	car = Vehicle.new()
	car.name = "StreetCar"
	add_child(car)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.far = 800
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	layer.add_child(panel)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 19)
	panel.add_child(hud)
	reset_car()
	if not test_mode.is_empty():
		var script = load("res://acceptance.gd")
		if script == null or not script.can_instantiate():
			get_tree().quit(64)
			return
		var tests = script.new()
		tests.lab = self
		add_child(tests)

func reset_car() -> void:
	held.clear()
	var p: Vector3 = track.layout.spawns[0].position
	p.y = track.layout.samples[0].position.y + Vehicle.REST_LENGTH + car.wheel_radius
	car.request_reset(Transform3D(Basis.IDENTITY, p))
	resets += 1

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		held[key] = event.pressed
		if event.pressed:
			if key == KEY_R: reset_car()
			if key == KEY_TAB: overview = not overview
			if key == KEY_ESCAPE: get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		if test_mode.is_empty() and is_instance_valid(car): car.set_command(0, 0, 0, false)

func _physics_process(_delta: float) -> void:
	if test_mode.is_empty():
		car.set_command(float(held.get(KEY_W, false)) - float(held.get(KEY_S, false)), float(held.get(KEY_D, false)) - float(held.get(KEY_A, false)), float(held.get(KEY_SHIFT, false)), bool(held.get(KEY_SPACE, false)))
		if car.global_position.y < -12: reset_car()

func _process(_delta: float) -> void:
	var target := car.get_global_transform_interpolated().origin
	if overview:
		camera.size = 175
		camera.position = Vector3(0, 180, 12)
		camera.look_at(Vector3.ZERO, Vector3.UP)
	else:
		camera.size = 23
		camera.position = target + Vector3(13, 19, 17)
		camera.look_at(target + Vector3(0, 0, -3), Vector3.UP)
	hud.text = "港区环线 · 离线驾驶\nW/S 前进与倒车  A/D 转向  Shift 刹车  空格 漂移\nR 复位  TAB 全景  ESC 退出\n%.0f km/h   %d/4 车轮接地   %.0f FPS\n车辆与赛道接入；本阶段不计圈" % [float(car.telemetry.get("speed", 0)) * 3.6, int(car.telemetry.get("grounded", 0)), Engine.get_frames_per_second()]
