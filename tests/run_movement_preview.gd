extends SceneTree
const Probe = preload("res://tests/support/movement_probe.gd")
const BASELINE_REVISION := "bc4f75f77e5521795becc20d3f277a44fb279d97"
var old_probe
var new_probe
var baseline_script: Script
var baseline_path := ""
var baseline_hash := ""
var baseline_config_hash := ""
var scenario := 0
var scenarios := ["stable", "jitter", "outage"]
var scenario_names := ["稳定更新", "到达抖动", "250ms 快照断流"]
var selected := 1
var canvas: Control
var font := SystemFont.new()
var highlight: StyleBoxFlat
var total := 0.0
var auto_stop := 0.0
var screenshot := ""
var captured := false
var capture_pending := false
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): auto_stop = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--screenshot="): screenshot = arg.trim_prefix("--screenshot=")
		if arg.begins_with("--baseline-script="): baseline_path = arg.trim_prefix("--baseline-script=")
		if arg.begins_with("--baseline-sha256="): baseline_hash = arg.trim_prefix("--baseline-sha256=")
		if arg.begins_with("--baseline-config-sha256="): baseline_config_hash = arg.trim_prefix("--baseline-config-sha256=")
		if arg.begins_with("--scenario="): scenario = scenarios.find(arg.trim_prefix("--scenario="))
	if scenario < 0 or baseline_path == "" or baseline_hash == "" or baseline_config_hash == "":
		push_error("MOVEMENT_PREVIEW_REQUIRES_VERIFIED_BASELINE use PreviewMovement.cmd")
		quit(1)
		return
	var config_path := baseline_path.get_base_dir().path_join("game_config.json")
	if FileAccess.get_sha256(baseline_path) != baseline_hash or FileAccess.get_sha256(config_path) != baseline_config_hash:
		push_error("MOVEMENT_PREVIEW_BASELINE_HASH_MISMATCH")
		quit(1)
		return
	baseline_script = load(baseline_path) as Script
	if baseline_script == null:
		push_error("MOVEMENT_PREVIEW_BASELINE_LOAD_FAILED")
		quit(1)
		return
	if screenshot != "" and auto_stop <= 0: auto_stop = 2.0
	Engine.max_fps = 120
	root.size = Vector2i(960, 600)
	root.content_scale_size = Vector2i(960, 600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "RoomKit movement A/B - offline synthetic snapshots"
	# SceneTree does not receive Node input callbacks automatically.
	root.window_input.connect(_input)
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	highlight = StyleBoxFlat.new()
	highlight.bg_color = Color("23354d")
	highlight.border_color = Color("95b5df")
	highlight.set_border_width_all(1)
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw)
	root.add_child(canvas)
	reset()
	print("MOVEMENT_PREVIEW_BASELINE revision=", BASELINE_REVISION, " script_sha256=", baseline_hash,
		" config_sha256=", baseline_config_hash, " candidate_sha256=", FileAccess.get_sha256("res://examples/shooter/game.gd"))

func reset() -> void:
	if old_probe != null: old_probe.close()
	if new_probe != null: new_probe.close()
	new_probe = Probe.new()
	new_probe.setup(scenarios[scenario])
	old_probe = Probe.new()
	old_probe.setup(scenarios[scenario], baseline_script, new_probe.packets)

func _process(delta: float) -> bool:
	if canvas == null: return false
	total += delta
	var step := minf(delta, 0.1)
	old_probe.advance(step)
	new_probe.advance(step)
	if old_probe.error != "" or new_probe.error != "":
		push_error("MOVEMENT_PREVIEW_PROBE_FAILED old=" + old_probe.error + " new=" + new_probe.error)
		failed = true
		finish()
		return false
	if new_probe.elapsed > Probe.DURATION: reset()
	canvas.queue_redraw()
	var capture_time := minf(1.5, auto_stop * 0.5) if auto_stop > 0 else 1.5
	if screenshot != "" and total >= capture_time and not captured:
		captured = true
		capture_pending = true
		capture.call_deferred()
	if auto_stop > 0 and total >= auto_stop and not capture_pending: finish()
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(screenshot)
	if result != OK:
		failed = true
		push_error("PREVIEW_SCREENSHOT_FAILED code=" + str(result))
	else:
		print("MOVEMENT_PREVIEW_SCREENSHOT ", screenshot)
	capture_pending = false

func finish() -> void:
	print("MOVEMENT_PREVIEW_RESULT renderer_fps=", Engine.get_frames_per_second(), " synthetic=true scenario=",
		scenarios[scenario], " selected=", "new" if selected == 1 else "old", " baseline=", BASELINE_REVISION,
		" failed=", failed)
	quit(1 if failed else 0)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_TAB:
			scenario = (scenario + 1) % scenarios.size()
			reset()
			print("MOVEMENT_PREVIEW_SCENARIO ", scenarios[scenario])
		KEY_SPACE, KEY_B:
			selected = 1 - selected
			print("MOVEMENT_PREVIEW_SELECTION ", "new" if selected == 1 else "old")
		KEY_ESCAPE:
			finish()

func _draw() -> void:
	canvas.draw_rect(Rect2(0, 0, 960, 600), Color("16202e"))
	canvas.draw_string(font, Vector2(30, 40), "人物移动 A/B · 离线合成快照，不连接服务器", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
	canvas.draw_string(font, Vector2(30, 76), "TAB 切场景；Space / B 切旧新版强调；ESC 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	canvas.draw_string(font, Vector2(30, 108), "场景：" + scenario_names[scenario] + "  |  当前选择：" + ("新版" if selected == 1 else "旧版"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe2a0"))
	canvas.draw_string(font, Vector2(30, 139), "相同轨迹 / 20Hz 快照 / 到达时序 / 显示 delta；基准 " + BASELINE_REVISION.left(12), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("bac6d8"))
	var values := [old_probe.displayed(), new_probe.displayed(), new_probe.raw(), new_probe.truth(new_probe.elapsed)]
	var names := ["旧版：固定提交中的真实 game.gd", "新版：当前工程中的真实 game.gd", "共同最新权威位置（20Hz）", "合成轨迹参考（并非预测实现）"]
	var colors := [Color("f0ab55"), Color("70c8ff"), Color("c5b1f0"), Color("75db9e")]
	for row in range(4):
		var y := 210.0 + row * 90.0
		if row == selected:
			canvas.draw_style_box(highlight, Rect2(20, y - 45, 920, 77))
		canvas.draw_string(font, Vector2(35, y - 20), ("▶ " if row == selected else "") + names[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, colors[row])
		canvas.draw_line(Vector2(80, y + 8), Vector2(820, y + 8), Color("455269"), 2)
		canvas.draw_circle(Vector2(values[row], y + 8), 12, colors[row])
		canvas.draw_string(font, Vector2(830, y + 14), "%.1f px" % values[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, colors[row])
	canvas.draw_string(font, Vector2(30, 563), "高 FPS 不等于每帧位置变化；流畅度与位置落后需要同时观察。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	canvas.draw_string(font, Vector2(30, 589), "仅验证合成呈现；没有网络、物理输入或真人手感验收。", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("bac6d8"))

func _finalize() -> void:
	if old_probe != null: old_probe.close()
	if new_probe != null: new_probe.close()
