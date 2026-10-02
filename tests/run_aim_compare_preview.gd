extends "res://examples/framework/client.gd"
## Offline presentation sandbox: no accounts, network, files or service startup.
const Shooter = preload("res://examples/shooter/game.gd")

class PreviewCanvas extends Node2D:
	const ARENA_POSITION := Vector2(28, 96)
	var app
	var font := SystemFont.new()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1016, 716), Color("0c1724"))
		draw_string(font, Vector2(28, 30), "离线转枪对照 · 全部为合成状态，不连接服务器", HORIZONTAL_ALIGNMENT_LEFT, 960, 20, Color.WHITE)
		draw_string(font, Vector2(28, 60), "TAB 切换（" + app.candidate_label + "）：" + ("旧版 / 快照方向" if app.baseline else "候选 / 本机逐帧 + 远端平滑") + "    ESC 退出", HORIZONTAL_ALIGNMENT_LEFT, 960, 18, Color("ffcd79"))
		draw_set_transform(ARENA_POSITION)
		var shown_world = app.source if app.baseline else app.world
		shown_world.draw_on(self, "aim-local", font)
		draw_set_transform(Vector2.ZERO)
		draw_string(font, Vector2(28, 665), "鼠标瞄准左边的你；右边玩家自动转枪。快照 20 Hz，位置固定。", HORIZONTAL_ALIGNMENT_LEFT, 960, 18, Color.WHITE)
		draw_string(font, Vector2(28, 695), "本机视觉即时响应；实际射击仍等服务器处理，本预览不验收联网或命中。", HORIZONTAL_ALIGNMENT_LEFT, 960, 16, Color("9cadbb"))

var source
var candidate_label := "候选"
var baseline := false
var elapsed := 0.0
var snapshot_elapsed := 0.0
var frame_count := 0
var sampled_frames := 0
var rendered_changes := 0
var previous_aim := Vector2.INF
var snapshot_count := 0
var preview_start := 0
var duration_ms := 0
var report_path := ""
var screenshot_path := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	duration_ms = int(args.get("--duration-ms", "0"))
	report_path = str(args.get("--report", ""))
	screenshot_path = str(args.get("--screenshot", ""))
	root.size = Vector2i(1016, 716)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	candidate_label = str(args.get("--candidate-label", "候选"))
	root.title = "RoomKit · 离线转枪对照 · " + candidate_label
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	client = AccountClient.new()
	client.state = "IN_ROOM"
	client.identity = {"user_id": "aim-local"}
	world = Shooter.new()
	baseline = args.has("--baseline")
	source = Shooter.new()
	source.server = true
	source.admit({"user_id": "aim-local", "display_name": "本机鼠标"}, 2)
	source.admit({"user_id": "aim-remote", "display_name": "远端合成转向"}, 3)
	source.players["aim-local"].position = Vector2(220, 350)
	source.players["aim-remote"].position = Vector2(740, 350)
	source.advance(0)
	_publish_preview()
	view = PreviewCanvas.new()
	view.app = self
	root.add_child(view)
	preview_start = Time.get_ticks_msec()
	root.close_requested.connect(func(): quit())

func _process(delta: float) -> bool:
	elapsed += delta
	frame_count += 1
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		quit()
		return false
	if Input.is_action_just_pressed("ui_focus_next"):
		baseline = not baseline
	world.advance_visual(delta)
	_preview_sync_local_aim()
	if duration_ms > 0:
		# Automated rendering uses a repeatable pointer path, not a network claim.
		_preview_set_local_aim("aim-local", Vector2.from_angle(elapsed * 4.0), true)
	snapshot_elapsed += delta
	if snapshot_elapsed >= 0.05:
		snapshot_elapsed = fmod(snapshot_elapsed, 0.05)
		_publish_preview()
	var shown_world = source if baseline else world
	var shown: Vector2 = _preview_render_aim(shown_world, shown_world.player_view("aim-remote"), "aim-local")
	if elapsed > 0.1:
		sampled_frames += 1
		if not shown.is_equal_approx(previous_aim):
			rendered_changes += 1
	previous_aim = shown
	view.queue_redraw()
	if duration_ms > 0 and not closing and Time.get_ticks_msec() - preview_start >= duration_ms:
		closing = true
		_finish_preview.call_deferred()
	return false

func _publish_preview() -> void:
	var own: Dictionary = source.players["aim-local"]
	if view != null:
		var direction: Vector2 = view.get_local_mouse_position() - view.ARENA_POSITION - own.position
		own.aim = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
		if duration_ms > 0:
			own.aim = Vector2.from_angle(elapsed * 4.0)
	source.players["aim-remote"].aim = Vector2.from_angle(elapsed * 4.0)
	source.tick += 3
	source.latest = source.state_snapshot()
	world.world_state(source.latest)
	snapshot_count += 1

func _finish_preview() -> void:
	await RenderingServer.frame_post_draw
	var result := {"mode": "baseline" if baseline else "candidate", "frames": frame_count, "sampled_frames": sampled_frames, "direction_changes": rendered_changes, "snapshots": snapshot_count, "elapsed_ms": Time.get_ticks_msec() - preview_start, "synthetic": true}
	var ok := true
	if screenshot_path != "":
		ok = root.get_texture().get_image().save_png(screenshot_path) == OK
	if report_path != "":
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		ok = ok and file != null
		if file != null:
			file.store_string(JSON.stringify(result))
	print("AIM_PREVIEW_RESULT ", JSON.stringify(result))
	quit(0 if ok else 1)

func _finalize() -> void:
	for node in [source, world, client]:
		if is_instance_valid(node):
			node.free()

# Common display harness; only these adapters account for candidate API names.
# Production game/client source files are never modified by this comparison.
func _preview_set_local_aim(user: String, direction: Vector2, enabled: bool) -> void:
	if world.has_method("set_local_aim"):
		world.set_local_aim(user, direction, enabled)
	else:
		world.set_local_visual_aim(user if enabled else "", direction)

func _preview_sync_local_aim() -> void:
	var player: Dictionary = world.player_view("aim-local")
	var pointer: Vector2 = view.get_local_mouse_position() - view.ARENA_POSITION
	var direction := pointer - Vector2(float(player.x), float(player.y))
	_preview_set_local_aim("aim-local", direction, root.has_focus())

func _preview_render_aim(game, player: Dictionary, user: String) -> Vector2:
	if game.has_method("set_local_aim"):
		return game.render_aim(player, user)
	return game.render_aim(player)