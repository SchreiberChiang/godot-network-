extends SceneTree
## Local diagnostics regression; not public-network, DTLS or performance acceptance.
const RoomClient = preload("res://sdk/roomkit/client/room_client.gd")
const Shooter = preload("res://examples/shooter/game.gd")
const View = preload("res://examples/framework/view.gd")
var passed := 0
var failed := 0

class PresentationApp:
	extends RefCounted
	var sound = null
	var client = null
	var world = null
	var busy := false
	var inventory_open := false
	func inventory_allowed() -> bool:
		return false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client = RoomClient.new()
	_check(client.room_round_trip_ms() < 0, "closed room has unknown RTT")
	client.state = "IN_ROOM"
	_check(client.room_round_trip_ms() < 0, "missing transport has unknown RTT")
	await _real_enet(client)
	client.free()
	await _snapshot_progress()
	await _frame_window_and_layout()
	print("CLIENT_NETWORK_STATS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _real_enet(client: Node) -> void:
	var server := ENetMultiplayerPeer.new()
	server.set_bind_ip("127.0.0.1")
	if server.create_server(0, 1) != OK:
		_check(false, "create loopback-only ephemeral ENet server")
		return
	_check(true, "create loopback-only ephemeral ENet server")
	client.enet = ENetMultiplayerPeer.new()
	var opened: int = client.enet.create_client("127.0.0.1", server.host.get_local_port())
	_check(opened == OK, "create real local ENet client")
	if opened != OK:
		server.close()
		client.enet.close()
		client.enet = null
		return
	_check(client.room_round_trip_ms() < 0, "connecting transport has unknown RTT")
	var deadline := Time.get_ticks_msec() + 3000
	while client.enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() < deadline:
		server.poll()
		client.enet.poll()
		await process_frame
	_check(client.enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "real loopback ENet handshake completes")
	if client.enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var packet_peer: ENetPacketPeer = client.enet.get_peer(1)
		client._collect_network_diagnostics(Time.get_ticks_msec())
		var observed: float = client.room_round_trip_ms()
		_check(is_finite(observed) and observed >= 0, "connected room exposes finite transport RTT estimate")
		_check(observed == packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), "collector caches ENet reliable round-trip statistic for readers")
		client.state = "LOBBY"
		_check(client.room_round_trip_ms() < 0, "leaving room hides even still-open transport RTT")
		client.state = "IN_ROOM"
	client.enet.close()
	_check(client.room_round_trip_ms() < 0, "closed transport has unknown RTT")
	client.enet = null
	server.close()

func _snapshot_progress() -> void:
	var source = Shooter.new()
	source.server = true
	source.admit({"user_id": "diag-player", "display_name": "诊断玩家"}, 2)
	source.advance(0)
	var value: Dictionary = source.state_snapshot()
	var world = Shooter.new()
	_check(world.snapshot_diagnostics() == {"interval_ms": -1, "age_ms": -1}, "no snapshot has unknown progress metrics")
	world.world_state(value)
	_check(world.snapshot_diagnostics().interval_ms < 0 and world.snapshot_diagnostics().age_ms >= 0, "first snapshot has age but no interarrival sample")
	var first_at: int = world._diagnostic_received_ms
	await _wait_ms(35)
	world.world_state(value.duplicate(true))
	_check(world._diagnostic_received_ms == first_at and world.snapshot_diagnostics().age_ms >= 30, "duplicate tick cannot conceal time without new state")
	value.tick += 3
	world.world_state(value)
	var second_at: int = world._diagnostic_received_ms
	_check(world.snapshot_diagnostics().interval_ms == second_at - first_at, "strictly newer snapshot records actual monotonic reception interval")
	var interval: int = world.snapshot_diagnostics().interval_ms
	var invalid: Dictionary = value.duplicate(true)
	invalid.tick += 3
	invalid.players[0].x = "bad"
	world.world_state(invalid)
	_check(world._diagnostic_received_ms == second_at, "invalid snapshot cannot advance progress metrics")
	await _wait_ms(35)
	var older: Dictionary = value.duplicate(true)
	older.tick -= 3
	world.world_state(older)
	_check(world._diagnostic_received_ms == second_at and world.snapshot_diagnostics().interval_ms == interval, "old tick cannot replace progress or interval")
	_check(world.snapshot_diagnostics().age_ms >= 30, "no new snapshot age advances without render-delta dependence")
	world.latest.clear()
	world.world_state(older)
	_check(world.snapshot_diagnostics().interval_ms < 0, "fresh room starts a new interval baseline")
	world.free()
	source.free()

func _frame_window_and_layout() -> void:
	var view = View.new()
	_check(view.worst_frame_ms(1000000) < 0, "empty frame window is unknown")
	view._observe_frame(1000000)
	_check(view.worst_frame_ms(1000000) < 0, "first presentation callback has no frame interval sample")
	view._observe_frame(1120000)
	view._observe_frame(1136667)
	_check(is_equal_approx(view.worst_frame_ms(2119999), 120.0), "monotonic callbacks preserve a recent 120 ms stall beside average FPS")
	_check(is_equal_approx(view.worst_frame_ms(2120001), 16.667), "one-second window drops expired stall but keeps ordinary frame interval")
	_check(view.worst_frame_ms(2136668) < 0, "frame window does not retain stale measurements")
	view._observe_frame(2736667)
	_check(is_equal_approx(view.worst_frame_ms(2736667), 1600.0), "1600 ms callback pause is measured independently of capped or smoothed Engine delta")
	var unknown := View.diagnostics_line(60, -1, -1, {})
	_check(unknown.count("—") == 4 and not unknown.contains("0 ms"), "unknown network and frame samples display dashes")
	var measured := View.diagnostics_line(60, 123.0, 87.0, {"interval_ms": 150, "age_ms": 220})
	_check(measured.contains("123 ms") and measured.contains("87 ms") and measured.contains("150 ms") and measured.contains("220 ms"), "line keeps rendering, RTT and state-progress measurements separate")
	view.app = PresentationApp.new()
	view.set_process(false)
	root.add_child(view)
	view.set_process(false)
	view.diagnostics_text.text = View.diagnostics_line(999, 9999.0, 99999.0, {"interval_ms": 999999, "age_ms": 9999999})
	var label: Label = view.diagnostics_text
	var font: Font = label.get_theme_font("font")
	var text_size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
	_check(text_size.x < label.size.x, "large diagnostic values fit allocated HUD width")
	_check(label.position.y >= view.help_text.position.y + view.help_text.size.y, "diagnostics have their own row after instructions")
	_check(label.position.y + maxf(label.size.y, text_size.y) <= view.permanent_message.position.y, "diagnostic row fits above permanent feedback")
	_check(label.clip_text and label.tooltip_text.contains("非单程") and label.tooltip_text.contains("非 GPU"), "label bounds and tooltip preserve metric meaning")
	print("HUD_LAYOUT width=", label.size.x, " height=", label.size.y, " text_width=", text_size.x, " text_height=", text_size.y, " position_y=", label.position.y, " feedback_y=", view.permanent_message.position.y)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hud-screenshot="):
			await _capture_hud(view, argument.trim_prefix("--hud-screenshot="))
	view.free()

func _capture_hud(view: Control, path: String) -> void:
	# An offscreen real renderer is only invoked explicitly by this isolated test.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1240, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	view.reparent(viewport)
	view.set_process(false)
	for panel in [view.login_panel, view.lobby_panel, view.inventory_panel, view.account_panel]:
		panel.hide()
	view.game_panel.show()
	view.game_status.text = "隔离 HUD 布局检查 · 不是联网试玩"
	view.help_text.text = "A / D 移动  ·  空格跳跃  ·  鼠标瞄准与开枪  ·  B 背包  ·  R 复活"
	view.permanent_message.text = "反馈区域仍单独显示。诊断：帧率、帧间隔、网络往返、状态更新。"
	view.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png(path)
	_check(error == OK, "isolated real-renderer HUD image saved")
	view.reparent(root)
	viewport.free()

func _wait_ms(duration: int) -> void:
	var deadline := Time.get_ticks_msec() + duration
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
