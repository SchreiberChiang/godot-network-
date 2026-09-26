extends SceneTree
## Real renderer, synthetic 20 Hz snapshots. No network, accounts or user rooms.
const Game = preload("res://examples/shooter/game.gd")
var world = Game.new()
var authority = Game.new()
var elapsed := 0.0
var packet_elapsed := 0.0
var frame_count := 0
var movement_frames := 0
var previous_x := -1.0
var baseline := false
var output := ""
var captured := false
var canvas: Control

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "RoomKit rendering check"
	authority.server = true
	authority.admit({"user_id": "u1", "display_name": "渲染测试"}, 2)
	authority.admit({"user_id": "u2", "display_name": "测试靶"}, 3)
	authority.players.u1.position = Vector2(100, 478)
	authority.players.u2.position = Vector2(850, 478)
	authority.players.u1.fire = true
	authority.advance(0)
	canvas = Control.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	canvas.draw.connect(func(): world.draw_on(canvas, "u1", font))
	root.add_child(canvas)

func _process(delta: float) -> bool:
	elapsed += delta
	packet_elapsed += delta
	world.advance_visual(delta)
	if packet_elapsed >= 0.05:
		packet_elapsed = fmod(packet_elapsed, 0.05)
		authority.tick += 3
		authority.players.u1.position.x = 100 + fmod(elapsed * 110, 280)
		if authority.tick % 12 == 0:
			authority.shots.clear()
			authority._fire(authority.players.u1, roundi(elapsed * 1000))
		world.world_state(authority.state_snapshot())
	if baseline:
		world.render_tracks.clear()
	if elapsed > 1 and elapsed < 7:
		frame_count += 1
		var own: Dictionary = world.player_view("u1")
		if not own.is_empty():
			var x: float = world.render_position(own).x
			if not is_equal_approx(x, previous_x): movement_frames += 1
			previous_x = x
	canvas.queue_redraw()
	if elapsed > 3 and not captured and not world.visual_shots.is_empty() and float(world.visual_shots[0].age) > 0.01:
		captured = true
		capture.call_deferred()
	if elapsed >= 7:
		var result := {"scope": "real_renderer_synthetic_snapshots_no_network", "baseline": baseline, "render_fps": frame_count / 6.0, "movement_updates_per_second": movement_frames / 6.0, "frames": frame_count}
		print("VISUAL_RESULT ", JSON.stringify(result))
		if output != "":
			var file := FileAccess.open(output + ".json", FileAccess.WRITE)
			file.store_string(JSON.stringify(result, "  "))
		quit(0)
	return false

func _finalize() -> void:
	world.free()
	authority.free()

func capture() -> void:
	await RenderingServer.frame_post_draw
	if output != "": root.get_texture().get_image().save_png(output + ".png")
