extends Node3D

const Vehicle = preload("res://vehicle.gd")
const Arena = preload("res://arena.gd")
const Hud = preload("res://hud.gd")

var car: RigidBody3D
var camera: Camera3D
var hud: Control
var held: Dictionary = {}
var test_command: Dictionary = {}
var test_mode := ""
var evidence_dir := ""
var active_pad := 0
var render_frames := 0
var frame_ms: Array[float] = []
var _last_frame_usec := 0
var _spawn_positions := [Vector3(0, 0.9, 10), Vector3(-35, 0.9, -10), Vector3(35, 0.9, 5)]


func _ready() -> void:
	Input.use_accumulated_input = false
	process_physics_priority = -100
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test="):
			test_mode = argument.trim_prefix("--test=")
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	add_child(Arena.new())
	car = Vehicle.new()
	car.name = "PlaceholderCar"
	add_child(car)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.far = 500
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.lab = self
	layer.add_child(hud)
	go_to_pad(0)
	if not test_mode.is_empty():
		var harness = load("res://tests/acceptance.gd").new()
		harness.lab = self
		add_child(harness)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		held[code] = event.pressed
		if event.pressed:
			match code:
				KEY_R: go_to_pad(active_pad)
				KEY_F1: hud.debug_visible = not hud.debug_visible
				KEY_1: go_to_pad(0)
				KEY_2: go_to_pad(1)
				KEY_3: go_to_pad(2)
				KEY_ESCAPE: get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		if is_instance_valid(car):
			car.set_command(0, 0, 0, false)


func input_command() -> Dictionary:
	return {"throttle": float(_key(KEY_W, KEY_UP)) - float(_key(KEY_S, KEY_DOWN)), "steer": float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT)), "brake": float(_key(KEY_SHIFT, KEY_SHIFT)), "drift": _key(KEY_SPACE, KEY_SPACE)}


func _key(first: int, second: int) -> bool:
	return bool(held.get(first, false)) or bool(held.get(second, false))


func _physics_process(_delta: float) -> void:
	var controls := input_command() if test_command.is_empty() else test_command
	car.set_command(controls.throttle, controls.steer, controls.brake, controls.drift)
	if car.global_position.y < -12:
		go_to_pad(active_pad)


func _process(_delta: float) -> void:
	render_frames += 1
	var now := Time.get_ticks_usec()
	if _last_frame_usec != 0 and frame_ms.size() < 7200:
		frame_ms.append((now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	var target := car.get_global_transform_interpolated().origin
	camera.position = target + Vector3(13, 28, 22)
	camera.look_at(target + Vector3(0, 0, -3), Vector3.UP)
	hud.queue_redraw()


func go_to_pad(index: int) -> void:
	active_pad = clampi(index, 0, _spawn_positions.size() - 1)
	held.clear()
	test_command.clear()
	car.request_reset(Transform3D(Basis.IDENTITY, _spawn_positions[active_pad]))
