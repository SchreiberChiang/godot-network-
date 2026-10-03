extends Node3D
const Data = preload("res://track_data.gd")
var layout: Dictionary
var flat_track := false
var markers: Node3D
var grid_models: Node3D
var _materials := {}
const ASPHALT := Color("535e66")
const CONCRETE := Color("b1b5a5")
const TEAL := Color("349b91")
const ORANGE := Color("e89b47")
const INK := Color("273d48")
const IVORY := Color("e9e5cc")

func _ready() -> void:
	build()

func build() -> void:
	if not layout.is_empty():
		return
	layout = Data.create(flat_track)
	_box(self, "Water", Vector3(0, -1.2, 0), Vector3(500, 0.3, 500), Color("47858b"))
	_box(self, "QuayFoundation", Vector3(0, -0.75, 0), Vector3(150, 1.4, 124), Color("748e89"), true)
	_box(self, "QuayCap", Vector3(0, -0.06, 0), Vector3(150, 0.12, 124), CONCRETE)
	# One continuous triangulated surface for all 16 m, including the ramp.
	var road_mesh := _ribbon(-8, 8, 0)
	var body := StaticBody3D.new()
	body.name = "DriveSurface"
	body.collision_layer = 1
	add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(road_mesh.get_faces())
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	_mesh(self, "Runoff", road_mesh, Color("9baba2"))
	_mesh(self, "Road", _ribbon(-5, 5, 0.008), ASPHALT)
	_mesh(self, "EdgeLeft", _ribbon(-5.05, -4.9, 0.018), IVORY)
	_mesh(self, "EdgeRight", _ribbon(4.9, 5.05, 0.018), IVORY)
	var s: Array = layout.samples
	var rail := StaticBody3D.new()
	rail.name = "ContinuousGuardrails"
	rail.collision_layer = 1
	add_child(rail)
	for i in range(s.size() - 1):
		for side in [-1.0, 1.0]:
			var a: Vector3 = s[i].position + s[i].right * 8.4 * side
			var b: Vector3 = s[i + 1].position + s[i + 1].right * 8.4 * side
			var part := _box(self, "Barrier", (a + b) * 0.5 + Vector3.UP * 0.36,
				Vector3(0.45, 0.72, a.distance_to(b) + 0.10), IVORY if i % 12 < 9 else TEAL)
			part.look_at_from_position(part.position, part.position + b - a, Vector3.UP)
			var c := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = part.mesh.size
			c.shape = box
			c.transform = part.transform
			rail.add_child(c)
		# Flat, non-colliding curb paint; no curb step to snag a car.
		if i % 3 == 0:
			for side in [-1.0, 1.0]:
				var a: Vector3 = s[i].position + s[i].right * 5.3 * side
				var b: Vector3 = s[i + 1].position + s[i + 1].right * 5.3 * side
				var curb := _box(self, "CurbPaint", (a + b) * 0.5 + Vector3.UP * 0.021,
					Vector3(0.45, 0.025, a.distance_to(b)), ORANGE)
				curb.look_at_from_position(curb.position, curb.position + b - a, Vector3.UP)
	_build_grid()
	_build_checkpoints()
	_build_scenery()

func _ribbon(left: float, right: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Array = layout.samples
	for i in range(samples.size() - 1):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		var al: Vector3 = a.position + a.right * left + Vector3.UP * lift
		var ar: Vector3 = a.position + a.right * right + Vector3.UP * lift
		var bl: Vector3 = b.position + b.right * left + Vector3.UP * lift
		var br: Vector3 = b.position + b.right * right + Vector3.UP * lift
		var normal: Vector3 = a.right.cross(b.position - a.position).normalized()
		for vertex in [al, bl, ar, ar, bl, br]:
			st.set_normal(normal)
			st.add_vertex(vertex)
	st.index()
	return st.commit()

func _build_grid() -> void:
	grid_models = Node3D.new()
	grid_models.name = "OptionalScaleModels"
	add_child(grid_models)
	for spawn in layout.spawns:
		var p: Vector3 = spawn.position
		var floor_y := Data.BASE_Y + 0.04
		for side in [-1, 1]:
			_box(self, "GridSide", Vector3(p.x + side * 1.35, floor_y, p.z), Vector3(0.10, 0.02, 4.5), IVORY)
		_box(self, "GridRear", Vector3(p.x, floor_y, p.z + 2.25), Vector3(2.8, 0.02, 0.10), IVORY)
		_floor_text(self, str(spawn.id + 1), Vector3(p.x, floor_y + 0.02, p.z + 1.4), 0.012, IVORY)
		# Original primitive scale proxies, no car asset imported from another task.
		var proxy := Node3D.new()
		grid_models.add_child(proxy)
		proxy.position = Vector3(p.x, Data.BASE_Y, p.z)
		_box(proxy, "ScaleBody", Vector3(0, 0.48, 0), Vector3(1.8, 0.60, 3.55), TEAL if spawn.id < 2 else Color("687e7c"))
		_box(proxy, "ScaleCabin", Vector3(0, 0.95, 0.24), Vector3(1.50, 0.42, 1.7), INK)
		_box(proxy, "NoseMarkerMinusZ", Vector3(0, 0.82, -1.15), Vector3(0.35, 0.06, 0.62), ORANGE)
		for x in [-0.94, 0.94]:
			for z in [-1.12, 1.12]:
				_box(proxy, "Wheel", Vector3(x, 0.31, z), Vector3(0.24, 0.56, 0.70), INK)
	for row in range(2):
		for col in range(10):
			_box(self, "FinishPaint", Vector3(-56.5 + col, Data.BASE_Y + 0.04, 1.65 + row * 0.7),
				Vector3(1, 0.02, 0.7), IVORY if (row + col) % 2 == 0 else INK)
	for x in [-60.9, -43.1]:
		_box(self, "FinishPylon", Vector3(x, 2.5, 2), Vector3(0.75, 5.0, 0.8), TEAL, true)
		_box(self, "FinishBeacon", Vector3(x, 5.1, 2), Vector3(1.05, 0.25, 1.0), ORANGE)
	_floor_text(self, "START / FINISH", Vector3(-64, 0.13, 4), 0.02, INK, PI * 0.5)

func _build_checkpoints() -> void:
	markers = Node3D.new()
	markers.name = "CheckpointGuide"
	add_child(markers)
	for cp in layout.checkpoints:
		var node := Node3D.new()
		node.name = "CP_%02d" % cp.id
		markers.add_child(node)
		node.position = cp.position
		node.basis = Basis.looking_at(cp.forward, Vector3.UP)
		for x in [-8.9, 8.9]:
			_box(node, "CheckpointBollard", Vector3(x, 0.55, 0), Vector3(0.35, 1.1, 0.35), ORANGE)
		_floor_text(node, "%02d" % cp.id, Vector3(6.35, 0.06, -0.8), 0.016, INK)
		for x in range(-8, 9, 2):
			_box(node, "PlaneGuide", Vector3(x, 0.05, 0), Vector3(0.7, 0.025, 0.12), Color("79b6ac"))
		# Painted arrow always follows -Z in each checkpoint's local frame.
		for side in [-1, 1]:
			var arrow := _box(node, "TravelArrow", Vector3(side * 0.42, 0.055, -2.4), Vector3(0.12, 0.02, 1.3), IVORY)
			arrow.rotation.y = side * PI / 4.0

func _build_scenery() -> void:
	# Warehouses fit completely outside both road and runoff.
	_warehouse(Vector3(-28, 0, -7), Vector3(22, 6, 25), "03")
	_warehouse(Vector3(-67, 0, -30), Vector3(8, 4.2, 18), "01")
	for x in [-32.0, -21.0]:
		for z in [17.0, 24.0]:
			_container(Vector3(x, 1.1, z), Vector3(8, 2.2, 3.4), TEAL if z == 17 else Color("7d9292"))
	_container(Vector3(12, 1.1, 4), Vector3(8, 2.2, 3.4), TEAL)
	_container(Vector3(12, 1.1, 10), Vector3(8, 2.2, 3.4), Color("c9b981"))
	_container(Vector3(12, 3.3, 4), Vector3(8, 2.2, 3.4), Color("879b99"))
	for z in [-42.0, -15.0, 15.0, 44.0]:
		_box(self, "QuayFender", Vector3(75.3, -0.4, z), Vector3(0.8, 1, 3), INK)
		_box(self, "MooringBollard", Vector3(72.5, 0.6, z), Vector3(0.8, 1.2, 0.8), ORANGE, true)
	for z in [-6.0, 28.0]:
		_box(self, "TimberPier", Vector3(83, -0.3, z), Vector3(16, 0.8, 7), Color("adac8a"), true)
		for x in range(76, 91, 2):
			_box(self, "PierJoint", Vector3(x, 0.12, z), Vector3(0.10, 0.02, 7), Color("868e7d"))
	# Harbor crane on the eastern quay, boom points over water.
	for z in [-28.0, -20.0]:
		_box(self, "CraneLeg", Vector3(69, 4, z), Vector3(0.6, 8, 0.7), ORANGE, true)
	_box(self, "CraneBeam", Vector3(76, 8, -24), Vector3(16, 0.7, 0.8), ORANGE)
	_box(self, "CraneCable", Vector3(83, 5, -24), Vector3(0.1, 6, 0.1), INK)
	_box(self, "CraneHook", Vector3(83, 2.1, -24), Vector3(0.7, 0.7, 0.7), INK)
	for p in [Vector3(-67, 0, 12), Vector3(-39, 0, -34), Vector3(-16, 0, 2), Vector3(14, 0, -34), Vector3(67, 0, 36), Vector3(-25, 0, 59)]:
		_box(self, "LampPole", p + Vector3.UP * 2.2, Vector3(0.2, 4.4, 0.2), INK, true)
		_box(self, "LampHead", p + Vector3.UP * 4.5, Vector3(1.0, 0.15, 0.65), IVORY)
	_floor_text(self, "PORT LOOP", Vector3(-26, 0.13, -28), 0.045, INK)
	_floor_text(self, "CARGO / 03", Vector3(-26, 6.10, -7), 0.025, IVORY)
	_floor_text(self, "SLOW\n14m", Vector3(42, 0.15, 18), 0.023, INK)
	_floor_text(self, "N", Vector3(-66, 0.13, -53), 0.06, INK)
	for i in range(22):
		_box(self, "WaterGlint", Vector3(79 + (i % 4) * 7, -1.025, -57 + i * 5.5), Vector3(2.5 + i % 3, 0.018, 0.12), Color("74a7a4"))

func _warehouse(p: Vector3, size: Vector3, code: String) -> void:
	_box(self, "Warehouse" + code, p + Vector3.UP * size.y * 0.5, size, Color("c1c4ae"), true)
	_box(self, "WarehouseRoof", p + Vector3.UP * (size.y + 0.1), Vector3(size.x + 0.5, 0.25, size.z + 0.5), Color("637c7e"))
	for z in range(-2, 3):
		_box(self, "RoofSeam", p + Vector3(0, size.y + 0.25, z * size.z / 5), Vector3(size.x + 0.4, 0.08, 0.15), Color("8ba19b"))
	for z in [-5.0, 5.0]:
		_box(self, "LoadingDoor", p + Vector3(-size.x * 0.5 - 0.02, 1.4, z), Vector3(0.05, 2.8, 3.0), TEAL)

func _container(p: Vector3, size: Vector3, color: Color) -> void:
	_box(self, "Container", p, size, color, true)
	for i in range(7):
		_box(self, "ContainerRib", p + Vector3(-size.x * 0.5 + 0.5 + i, 0, size.z * 0.5 + 0.04), Vector3(0.07, size.y * 0.85, 0.1), color.lightened(0.12))

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_materials[key] = material
	return _materials[key]

func _mesh(parent: Node3D, title: String, mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)
	return node

func _box(parent: Node3D, title: String, pos: Vector3, size: Vector3, color: Color, collision := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := _mesh(parent, title, mesh, color)
	node.position = pos
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		node.add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	return node

func _floor_text(parent: Node3D, text: String, pos: Vector3, scale_px: float, color: Color, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = scale_px
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	parent.add_child(label)
	label.position = pos
	label.rotation = Vector3(-PI / 2.0, yaw, 0)
