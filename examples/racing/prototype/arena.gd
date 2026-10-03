extends Node3D
## Original geometric proving ground, no external assets or production game.

func _ready() -> void:
	_box(Vector3(220, 1, 260), Vector3(0, -0.5, -65), Color("35464e"), true)
	_box(Vector3(13, 0.012, 200), Vector3(0, 0.006, -65), Color("495b61"), false)
	for z in range(-160, 30, 8):
		_box(Vector3(0.12, 0.015, 3), Vector3(0, 0.018, z), Color("f5cf7c"), false)
	for x in [-6.5, 6.5]:
		_box(Vector3(0.1, 0.014, 200), Vector3(x, 0.015, -65), Color("c3d4d0"), false)
	for index in range(96):
		var angle := TAU * index / 96.0
		var point := Vector3(-35 + sin(angle) * 20, 0.018, -30 + cos(angle) * 20)
		var stripe := _box(Vector3(0.16, 0.015, 0.8), point, Color("7abec6"), false)
		stripe.rotation.y = angle
	var ramp_length := 16.0
	var angle := deg_to_rad(10)
	var ramp_height := ramp_length * 0.5 * sin(angle) - 0.15 * cos(angle)
	var ramp := _box(Vector3(10, 0.3, ramp_length), Vector3(35, ramp_height, -15), Color("638575"), true)
	ramp.rotation.x = angle
	for index in range(5):
		_box(Vector3(0.6, 0.6, 0.6), Vector3(-15 + (1.0 if index % 2 == 0 else -1.0) * 3, 0.3, -20 - index * 12), Color("eba868"), true)
	for index in range(3):
		var height: float = [0.05, 0.10, 0.20][index]
		_box(Vector3(7, height, 2), Vector3(55, height / 2, -10 - index * 15), Color("81988c"), true)
	_label("STRAIGHT / BRAKE", Vector3(0, 0.08, 19))
	_label("CIRCLE / DRIFT", Vector3(-35, 0.08, -30))
	_label("10 DEG RAMP / JUMP", Vector3(35, 0.08, 8))
	_label("STEPS", Vector3(55, 0.08, 8))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("172a3b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6cbd6")
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	add_child(world_environment)


func _box(size: Vector3, position_value: Vector3, color: Color, collide: bool) -> Node3D:
	var node: Node3D = StaticBody3D.new() if collide else Node3D.new()
	node.position = position_value
	if collide:
		node.collision_layer = 1
		node.collision_mask = 2
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		node.add_child(collision)
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	node.add_child(mesh)
	add_child(node)
	return node


func _label(text: String, point: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.02
	label.modulate = Color("d8e6de")
	label.outline_size = 0
	label.position = point
	label.rotation.x = -PI / 2
	add_child(label)
