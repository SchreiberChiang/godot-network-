extends SceneTree
const Probe = preload("res://tests/support/movement_probe.gd")
var probe
var scenario := 0
var scenarios := ["stable", "jitter", "outage"]
var canvas: Control
var font := SystemFont.new()
var total := 0.0
var auto_stop := 0.0
var screenshot := ""
var captured := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): auto_stop = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--screenshot="): screenshot = arg.trim_prefix("--screenshot=")
	Engine.max_fps = 120
	root.size = Vector2i(960, 460)
	root.content_scale_size = Vector2i(960, 460)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "RoomKit movement baseline - offline"
	# SceneTree is not a Node: its _input method is not dispatched automatically.
	root.window_input.connect(_input)
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw)
	root.add_child(canvas)
	reset()

func reset() -> void:
	if probe != null: probe.close()
	probe = Probe.new()
	probe.setup(scenarios[scenario])

func _process(delta: float) -> bool:
	total += delta
	probe.advance(minf(delta, 0.1))
	if probe.elapsed > 3.0: reset()
	if Input.is_action_just_pressed("ui_cancel"): quit()
	canvas.queue_redraw()
	if screenshot != "" and total >= 1.5 and not captured:
		captured = true
		capture.call_deferred()
	if auto_stop > 0 and total >= auto_stop:
		print("MOVEMENT_PREVIEW_RESULT renderer_fps=", Engine.get_frames_per_second(), " synthetic=true")
		quit(0)
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(screenshot)
	if result != OK: push_error("PREVIEW_SCREENSHOT_FAILED")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		scenario = (scenario + 1) % scenarios.size()
		reset()
		print("MOVEMENT_PREVIEW_SCENARIO ", scenarios[scenario])

func _draw() -> void:
	canvas.draw_rect(Rect2(0, 0, 960, 460), Color("16202e"))
	canvas.draw_string(font, Vector2(30, 45), "人物移动基线 · 离线模拟，不连接服务器", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	canvas.draw_string(font, Vector2(30, 85), "TAB 切换：稳定 / 抖动 / 250ms断流；ESC 退出。当前：" + scenarios[scenario], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var values := [probe.raw(), probe.displayed(), probe.truth(probe.elapsed)]
	var names := ["最新服务器位置（20Hz）", "当前游戏实际显示算法", "合成轨迹参考（并非预测实现）"]
	var colors := [Color("f0ab55"), Color("70c8ff"), Color("75db9e")]
	for row in range(3):
		var y := 170.0 + row * 85.0
		canvas.draw_string(font, Vector2(30, y - 25), names[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, colors[row])
		canvas.draw_line(Vector2(80, y), Vector2(820, y), Color("455269"), 2)
		canvas.draw_circle(Vector2(values[row], y), 12, colors[row])
	canvas.draw_string(font, Vector2(30, 435), "高FPS不等于每帧位置都在变化；参考行只展示已知测试轨迹。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

func _finalize() -> void:
	if probe != null: probe.close()
