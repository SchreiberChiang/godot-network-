extends PanelContainer
var vehicle
var sliders: Dictionary = {}
var values_text: Dictionary = {}
var syncing := false
var status: Label
var telemetry: Label

func _ready() -> void:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "实时调参 · F2 收起"
	heading.add_theme_font_size_override("font_size", 20)
	box.add_child(heading)
	var preset_row := HBoxContainer.new()
	box.add_child(preset_row)
	for item in [["参考街机", "reference"], ["原交付", "original"]]:
		var button := Button.new()
		button.text = item[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_preset.bind(item[1]))
		preset_row.add_child(button)
	telemetry = Label.new()
	box.add_child(telemetry)
	var labels := {"turn_degrees": "转向速度 °/秒", "lateral_keep_turn": "转向时侧滑保留率",
		"lateral_keep_release": "松方向侧滑保留率", "acceleration": "前进加速度", "top_speed": "普通极速 m/s"}
	for key in ["turn_degrees", "lateral_keep_turn", "lateral_keep_release", "acceleration", "top_speed"]:
		var row := HBoxContainer.new()
		var caption := Label.new()
		caption.text = labels[key]
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var number := Label.new()
		row.add_child(number)
		values_text[key] = number
		box.add_child(row)
		var slider := HSlider.new()
		var range_value: Vector2 = vehicle.tuning.LIMITS[key]
		slider.min_value = range_value.x
		slider.max_value = range_value.y
		slider.step = 0.001 if str(key).begins_with("lateral") else 1.0
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_value_changed.bind(key))
		sliders[key] = slider
		box.add_child(slider)
	var hint := Label.new()
	hint.text = "保留率越大越滑：0.2 更抓地，0.95 更滑。\n调整不清空氮气；R 复位并清空氮气，保留参数。\n侧滑保留按参考 50 Hz 换算，实际物理 60 Hz。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var copy := Button.new()
	copy.text = "复制当前参数 · 方便反馈"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(_copy)
	box.add_child(copy)
	_sync()
	visible = false

func _preset(name: String) -> void:
	vehicle.tuning.use_preset(name)
	_sync()

func _value_changed(value: float, key: String) -> void:
	if syncing: return
	if vehicle.tuning.set_value(key, value):
		values_text[key].text = "%.3f" % value if key.begins_with("lateral") else "%.1f" % value
		status.text = "自定义 · 正在生效，本窗口内保留"

func _sync() -> void:
	syncing = true
	for key in sliders:
		var value: float = vehicle.tuning.values[key]
		sliders[key].value = value
		values_text[key].text = "%.3f" % value if str(key).begins_with("lateral") else "%.1f" % value
	syncing = false
	status.text = "当前：" + ("原交付" if vehicle.tuning.profile == "original" else "参考街机") + " · 此参考仍待试玩"

func _copy() -> void:
	DisplayServer.clipboard_set(JSON.stringify(vehicle.tuning.snapshot(), "  "))
	status.text = "参数已复制；可贴到聊天中反馈"

func layout(view_size: Vector2) -> void:
	size = Vector2(minf(360, view_size.x - 32), minf(480, view_size.y - 36))
	position = Vector2(view_size.x - size.x - 16, 18)

func _process(_dt: float) -> void:
	var data: Dictionary = vehicle.telemetry
	telemetry.text = "实际速度 %.1f m/s\n前向 %.1f · 侧向 %.1f m/s\n侧滑角 %.1f° · 转向受阻 %s" % [
		float(data.get("speed", 0)), float(data.get("forward_speed", 0)), float(data.get("lateral_speed", 0)),
		float(data.get("slip_degrees", 0)), "是" if bool(data.get("yaw_blocked_this_tick", false)) else "否"]
