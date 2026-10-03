extends Node3D

# This scene displays imported GLB files. It does not reconstruct their meshes.
var car: Node3D
var prop_group: Node3D
var camera: Camera3D
var headline: Label
var subtitle: Label
var footer: Label
var animated := false
var elapsed := 0.0
var interactive := false
var failures: Array[String] = []
var evidence := {}
const WHEELS := ["Front_Left", "Front_Right", "Rear_Left", "Rear_Right"]

func _ready() -> void:
	interactive = "--interactive" in OS.get_cmdline_user_args()
	get_viewport().transparent_bg = false
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("c7d5d4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce9f0")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("fff1d9")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = 0.20
	fill.light_color = Color("b6dce8")
	add_child(fill)
	add_box(Vector3(0,-.10,0), Vector3(200,.15,200), Color("aebfbd"))
	add_box(Vector3(0,-.035,0), Vector3(8,.07,7.5), Color("68787c"))
	# Restrained stage markings establish scale without obscuring the model.
	for x in [-3.82,3.82]:
		add_box(Vector3(x,.004,0), Vector3(.035,.008,7.1), Color("bac7c4"))
	for z in [-3.6,3.6]:
		add_box(Vector3(0,.004,z), Vector3(7.65,.008,.035), Color("bac7c4"))
	car = asset("street_car_v2.glb")
	prop_group = Node3D.new()
	add_child(prop_group)
	var cone := asset("traffic_cone_v2.glb", prop_group)
	cone.position = Vector3(2.55,0,-1.55)
	var barrier := asset("road_barrier_v2.glb", prop_group)
	barrier.position = Vector3(2.35,0,.15)
	barrier.rotation.y = -.18
	var tires := asset("tire_barrier_v2.glb", prop_group)
	tires.position = Vector3(2.45,0,1.60)
	prop_group.visible = false
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	headline = label(canvas,Vector2(46,32),30,Color("23383e"))
	subtitle = label(canvas,Vector2(48,75),15,Color("345055"))
	footer = label(canvas,Vector2(48,900),15,Color("23383e"))
	set_view(1)
	if interactive:
		footer.text = "1  THREE-QUARTER     2  TOP     3  KIT     SPACE  WHEELS     ESC  EXIT"
	else:
		_run_capture.call_deferred()

func asset(filename: String, parent: Node = self) -> Node3D:
	var packed := load("res://models/" + filename) as PackedScene
	if packed == null:
		push_error("Asset load failed: " + filename)
		get_tree().quit(2)
		return Node3D.new()
	var node := packed.instantiate() as Node3D
	parent.add_child(node)
	return node

func add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	mesh.material = material
	node.mesh = mesh
	node.position = pos
	add_child(node)

func label(parent: Node, pos: Vector2, size: int, color: Color) -> Label:
	var node := Label.new()
	parent.add_child(node)
	node.position = pos
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node

func set_view(view: int) -> void:
	car.position = Vector3.ZERO
	prop_group.visible = view == 3
	if view == 1:
		camera.position = Vector3(5.7,5.0,-7.5)
		camera.look_at(Vector3(0,.55,0))
		camera.size = 6.5
		headline.text = "LAGOON / 02"
		subtitle.text = "ORIGINAL LOW-POLY STREET CAR     /     GODOT 4.7.2"
		footer.text = "4.10 m LONG     /     2,846 TRIANGLES     /     SIX MATERIALS     /     FRONT -Z"
	elif view == 2:
		camera.position = Vector3(0,10,0)
		camera.look_at(Vector3.ZERO,Vector3(0,0,-1))
		camera.size = 6.2
		headline.text = "LAGOON / PLAN VIEW"
		subtitle.text = "FRONT AT TOP     /     METRES     /     +Y UP"
		footer.text = "2.45 m WHEELBASE     /     1.64 m TRACK     /     FOUR INDEPENDENT WHEELS"
	else:
		car.position.x = -1.35
		camera.position = Vector3(7.5,9.2,-10)
		camera.look_at(Vector3(.25,.35,.05))
		camera.size = 9.0
		headline.text = "LAGOON / STREET KIT"
		subtitle.text = "ONE CAR     +     TRAFFIC CONE     +     TIRE WALL     +     ROAD BARRIER"
		footer.text = "PURE GEOMETRY     /     NO TEXTURES     /     SINGLE-SIDED MATERIALS     /     OFFLINE"

func wheel(suffix: String) -> Node3D:
	return car.find_child("Wheel_" + suffix, true, false) as Node3D

func steer(suffix: String) -> Node3D:
	return car.find_child("Steer_" + suffix, true, false) as Node3D

func reset_wheels() -> void:
	for suffix in WHEELS:
		wheel(suffix).rotation = Vector3.ZERO
		steer(suffix).rotation = Vector3.ZERO

func _process(delta: float) -> void:
	if animated:
		elapsed += delta
		for suffix in WHEELS:
			wheel(suffix).rotation.x = -elapsed * 4.0
			steer(suffix).rotation.y = sin(elapsed * 1.6) * .44 if suffix.begins_with("Front") else 0.0

func _unhandled_key_input(event: InputEvent) -> void:
	if not interactive or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.keycode == KEY_SPACE:
		animated = not animated
		if not animated: reset_wheels()
	elif event.keycode in [KEY_1,KEY_2,KEY_3]:
		set_view(event.keycode - KEY_0)
	footer.text = "1  THREE-QUARTER     2  TOP     3  KIT     SPACE  WHEELS     ESC  EXIT"

func check(condition: bool, description: String) -> void:
	if not condition: failures.append(description)

func capture(filename: String) -> void:
	for i in range(6): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	check(picture.get_width() == 1280 and picture.get_height() == 960, "Image size " + filename)
	var path := ProjectSettings.globalize_path("res://../evidence/" + filename)
	check(picture.save_png(path) == OK, "Write screenshot " + filename)
	print("CAPTURE ",filename)

func _run_capture() -> void:
	evidence["engine"] = Engine.get_version_info().string
	evidence["renderer"] = RenderingServer.get_current_rendering_method()
	evidence["adapter"] = RenderingServer.get_video_adapter_name()
	evidence["user_data"] = OS.get_user_data_dir()
	evidence["resource_root"] = ProjectSettings.globalize_path("res://")
	check(OS.get_user_data_dir().replace("\\","/").contains("/artifacts/racing-models/"),"User data isolated in artifact")
	for suffix in WHEELS:
		check(wheel(suffix) != null and steer(suffix) != null,"Imported wheel hierarchy " + suffix)
	if not failures.is_empty():
		finish()
		return
	await capture("three_quarter.png")
	set_view(2)
	await capture("top.png")
	set_view(3)
	await capture("kit.png")
	set_view(1)
	var centers := {}
	for suffix in WHEELS: centers[suffix] = wheel(suffix).global_position
	wheel("Front_Left").rotation.x = -.7
	check(not wheel("Front_Left").basis.is_equal_approx(Basis.IDENTITY),"One wheel rotates")
	for suffix in ["Front_Right","Rear_Left","Rear_Right"]:
		check(wheel(suffix).basis.is_equal_approx(Basis.IDENTITY),"Sibling unchanged " + suffix)
	reset_wheels()
	animated = true
	for i in range(60): await get_tree().process_frame
	animated = false
	var transforms := []
	for suffix in WHEELS:
		check(wheel(suffix).global_position.distance_to(centers[suffix]) < .00001,"Pivot stable " + suffix)
		check(abs(wheel(suffix).rotation.x) > .1,"Rolling ran " + suffix)
		if suffix.begins_with("Front"):
			check(abs(steer(suffix).rotation.y) > .005,"Steering ran " + suffix)
		else:
			check(is_zero_approx(steer(suffix).rotation.y),"Rear steering remains zero " + suffix)
		transforms.append({"wheel":suffix,"center":[wheel(suffix).global_position.x,wheel(suffix).global_position.y,wheel(suffix).global_position.z],
			"roll_x":wheel(suffix).rotation.x,"steer_y":steer(suffix).rotation.y})
	evidence["animated_frames"] = 60
	evidence["wheel_transforms"] = transforms
	headline.text = "LAGOON / WHEEL CHECK"
	subtitle.text = "FRONT STEER +Y     /     FOUR LOCAL -X ROLLS     /     FIXED HUB CENTRES"
	await capture("wheel_check.png")
	finish()

func finish() -> void:
	evidence["failures"] = failures
	evidence["status"] = "PASS" if failures.is_empty() else "FAIL"
	var file := FileAccess.open("res://../evidence/godot_result.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence,"\t") + "\n")
	else: failures.append("Cannot write evidence")
	print("V2_RENDER_RESULT ",JSON.stringify(evidence))
	get_tree().quit(0 if failures.is_empty() else 1)
