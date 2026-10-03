extends Control

var lab: Node3D
var debug_visible := false
var _stats: Label
var _wheel_stats: Label
var _sliders: Dictionary = {}
var _update_elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("ROOMKIT  /  DRIVING LAB", Vector2(24, 18), 25)
	title.modulate = Color("f4d294")
	_label("OFFLINE   /   PLACEHOLDER VEHICLE   /   60 Hz PHYSICS", Vector2(25, 51), 13)
	_stats = _label("Settling suspension...", Vector2(25, 85), 19)
	_wheel_stats = _label("", Vector2(25, 185), 15)
	var panel := PanelContainer.new()
	panel.position = Vector2(974, 22)
	panel.custom_minimum_size = Vector2(282, 270)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "LIVE GRIP SETTINGS"
	column.add_child(heading)
	for key in lab.car.SETTINGS:
		var limits: Vector3 = lab.car.SETTINGS[key]
		var row := Label.new()
		column.add_child(row)
		var slider := HSlider.new()
		slider.min_value = limits.x
		slider.max_value = limits.y
		slider.step = 0.01
		slider.value = limits.z
		slider.focus_mode = Control.FOCUS_NONE
		slider.custom_minimum_size.x = 250
		column.add_child(slider)
		_sliders[key] = slider
		row.text = "%s  %.2f" % [key, slider.value]
		slider.value_changed.connect(func(value: float):
			lab.car.set_setting(key, value)
			row.text = "%s  %.2f" % [key, value])
	var defaults := Button.new()
	defaults.text = "Restore grip defaults"
	defaults.focus_mode = Control.FOCUS_NONE
	defaults.pressed.connect(func():
		lab.car.reset_settings()
		for key in _sliders:
			_sliders[key].value = lab.car.settings[key])
	column.add_child(defaults)
	var controls := _label("W / UP  Drive     S / DOWN  Brake, then reverse     A / D  Steer     SHIFT  Brake\nSPACE  Drift     R  Reset pad     F1  Force display     1 Straight / 2 Circle / 3 Ramp     ESC  Exit", Vector2(25, 730), 17)
	controls.modulate = Color("f2e7ce")
	_label("Orange body = forward hood stripe   |   Tire forces only; no artificial heading snap", Vector2(25, 697), 14)


func _label(value: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label


func _process(delta: float) -> void:
	_update_elapsed += delta
	if _update_elapsed < 0.1 or lab.car.telemetry.get("reset", true):
		return
	_update_elapsed = 0
	var data: Dictionary = lab.car.telemetry
	_stats.text = "%5.1f km/h    %s    CONTACT %d / 4\nSLIP %5.1f deg    STEER %5.1f deg\nDRIFT %.2f    RENDER %d FPS" % [data.speed * 3.6, "FORWARD" if data.gear == 1 else "REVERSE", data.grounded, data.slip_degrees, -data.steer_degrees, data.drift_blend, Engine.get_frames_per_second()]
	if data.speed < 2:
		_stats.text = _stats.text.replace("SLIP %5.1f deg" % data.slip_degrees, "SIDE %5.2f m/s" % data.side_speed)
	_wheel_stats.visible = debug_visible
	var lines := "PHYSICS SAMPLE  /  arrows: 1 m per 3500 N (cap 4 m)\nGreen = spring    Cyan = tire    Yellow = velocity / 5\n"
	for index in range(data.wheels.size()):
		var wheel: Dictionary = data.wheels[index]
		lines += "%s   %s   L %.3f m   spring %5.0f N\n" % [lab.car.WHEEL_NAMES[index], "GROUND" if wheel.grounded else "AIR", wheel.length, wheel.support]
	_wheel_stats.text = lines


func _draw() -> void:
	if not debug_visible or lab.car.telemetry.get("reset", true):
		return
	var data: Dictionary = lab.car.telemetry
	for wheel in data.wheels:
		_line(wheel.origin, wheel.point, Color("e7c775"), 1)
		_line(wheel.origin, wheel.origin + (wheel.suspension_force / 3500.0).limit_length(4), Color("8cde91"), 3)
		_line(wheel.point, wheel.point + (wheel.tire_force / 3500.0).limit_length(4), Color("6de3f2"), 3)
		_line(wheel.point, wheel.point + wheel.normal * 0.7, Color.WHITE, 1)
	var origin: Vector3 = data.pose.origin
	_line(origin, origin + data.velocity / 5.0, Color("ffcb5c"), 4)
	if not lab.camera.is_position_behind(data.com):
		draw_circle(lab.camera.unproject_position(data.com), 4, Color("ff6589"))


func _line(start: Vector3, end: Vector3, color: Color, width: float) -> void:
	if lab.camera.is_position_behind(start) or lab.camera.is_position_behind(end):
		return
	draw_line(lab.camera.unproject_position(start), lab.camera.unproject_position(end), color, width, true)
