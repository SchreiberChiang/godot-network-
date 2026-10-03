extends Node3D
const Harbor = preload("res://harbor.tscn")
const Data = preload("res://track_data.gd")
var harbor: Node3D
var camera: Camera3D
var info: Label
var target := Vector3.ZERO
var azimuth := 0.68
var elevation := 0.82
var radius := 220.0
var view_id := 1
var capture_dir := ""

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			capture_dir = argument.trim_prefix("--out=")
	harbor = Harbor.instantiate()
	add_child(harbor)
	var env := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color("25464e")
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color("d9ece2")
	resource.ambient_light_energy = 0.22
	resource.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = resource
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -32, 0)
	sun.light_color = Color("ffedca")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 350
	add_child(sun)
	camera = Camera3D.new()
	camera.far = 800
	add_child(camera)
	_ui()
	_set_view(1)
	print("LEVEL_VIEWER_READY version=", Engine.get_version_info().string, " user_dir=", OS.get_user_data_dir())
	print("LEVEL_RESOURCE_ROOT=", ProjectSettings.globalize_path("res://"))
	if not capture_dir.is_empty():
		_capture.call_deferred()

func _ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203a42")
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	style.border_width_left = 4
	style.border_color = Color("e89b47")
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "ROOMKIT  /  ORIGINAL LEVEL STUDY 01"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.modulate = Color("91c6ba")
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "PORT LOOP"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 14)
	column.add_child(info)
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 28
	footer.offset_right = -28
	footer.offset_top = -82
	footer.offset_bottom = -22
	footer.add_theme_stylebox_override("panel", style)
	canvas.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	footer.add_child(row)
	for entry in [["1  DIORAMA", 1], ["2  ROUTE PLAN", 2], ["3  HAIRPIN", 3]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(_set_view.bind(entry[1]))
		row.add_child(button)
	var hint := Label.new()
	hint.text = "  RMB orbit  |  wheel zoom  |  C checkpoints  |  G grid cars  |  Esc exit"
	hint.add_theme_font_size_override("font_size", 14)
	row.add_child(hint)

func _set_view(id: int) -> void:
	view_id = id
	target = Vector3.ZERO
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if id == 1:
		azimuth = 0.68
		elevation = 0.90
		radius = 220
		camera.size = 162
		_orbit()
	elif id == 2:
		camera.size = 149
		camera.position = Vector3(0, 190, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 65
		target = Vector3(36, 0, 13)
		camera.position = Vector3(62, 25, 52)
		camera.look_at(target)
	var offset := camera.position - target
	radius = offset.length()
	azimuth = atan2(offset.x, offset.z)
	elevation = asin(offset.y / radius)
	info.text = "%s  |  %.0f m loop  |  10 m road + runoff\n8 grid positions  /  12 planes  /  gentle 2 m rise" % [["", "DIORAMA", "ROUTE PLAN", "HAIRPIN"][id], harbor.layout.length_m]

func _orbit() -> void:
	camera.position = target + Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * radius
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_view(1)
			KEY_2: _set_view(2)
			KEY_3: _set_view(3)
			KEY_C: harbor.markers.visible = not harbor.markers.visible
			KEY_G: harbor.grid_models.visible = not harbor.grid_models.visible
			KEY_ESCAPE: get_tree().quit()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		azimuth -= event.relative.x * 0.005
		elevation = clampf(elevation + event.relative.y * 0.005, 0.15, 1.5)
		_orbit()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			camera.size = clampf(camera.size * factor, 25, 240)
			if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
				radius = clampf(radius * factor, 8, 300)
				_orbit()

func _capture() -> void:
	var names := ["diorama", "top", "track"]
	for id in [1, 2, 3]:
		_set_view(id)
		for frame in range(10):
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := capture_dir.path_join(names[id - 1] + ".jpg")
		var result := image.save_jpg(path, 0.92)
		print("CAPTURE ", names[id - 1], " result=", result, " size=", image.get_size())
		if result != OK:
			get_tree().quit(2)
			return
	var f := FileAccess.open(capture_dir.path_join("layout.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(Data.json_value(harbor.layout), "\t"))
	get_tree().quit(0)
