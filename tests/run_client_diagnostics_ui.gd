extends "res://examples/framework/client.gd"
## Headless shell wiring and measured font/layout checks, not a rendered screenshot.
const ShooterWorld = preload("res://examples/shooter/game.gd")
var passed := 0
var failed := 0
func _initialize() -> void:
	_verify.call_deferred()
func _process(_delta: float) -> bool:
	return false
func _verify() -> void:
	client = AccountClient.new()
	world = ShooterWorld.new()
	var source = ShooterWorld.new()
	source.server = true
	source.admit({"user_id": "diag-ui", "display_name": "Synthetic"}, 2)
	source.advance(0)
	world.world_state(source.state_snapshot())
	world.latest.clear()
	_check(world.snapshot_diagnostics() == {"interval_ms": -1, "age_ms": -1}, "room boundary before first new snapshot hides prior-room reception values")
	account_error = "AUTH_FAILED"
	_check(diagnostic_metrics().error == "AUTH_FAILED", "account preflight failure appears as fixed diagnostic error")
	account_error = "password-token-ticket-should-never-log"
	_check(diagnostic_metrics().error == "OTHER", "arbitrary account error reduced to fixed category")
	account_error = ""
	sound = Sound.new()
	root.add_child(sound)
	view = View.new()
	view.app = self
	view.set_process(false)
	root.add_child(view)
	view.set_process(false)
	var metrics := {"rtt_ms": 89.0, "rtt_variance_ms": 16.0, "reliable_loss_percent": -1.0, "loss_state": "collecting", "phase": "CONNECTING", "error": "NONE", "tx_bytes_per_sec": 1000.0, "rx_bytes_per_sec": 2000.0}
	var compact: String = View.diagnostics_line(120, 14.0, 89.0, {"interval_ms": 51, "age_ms": 9}, metrics)
	_check(compact.contains("统计中") and not compact.contains("0.00%"), "compact HUD does not claim initial zero loss")
	var detail: String = View.diagnostics_details(metrics)
	_check(detail.contains("非单程") and detail.contains("不是标准差") and detail.contains("不是所有 UDP") and detail.contains("至少 10"), "expanded details explain RTT, variation, loss scope and percentile sample threshold")
	_check(detail.contains("RTT 波动 16 ms") and detail.contains("1.0 KiB/s") and detail.contains("2.0 KiB/s"), "detail uses cached numerical units without sqrt")
	metrics.reliable_loss_percent = 0.0
	metrics.loss_state = "available"
	_check(View.diagnostics_details(metrics).contains("0.00%"), "proven measured zero loss remains visible")
	var label: Label = view.diagnostics_text
	var font: Font = label.get_theme_font("font")
	var text_size := font.get_string_size(compact, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
	_check(text_size.x <= label.size.x, "extended compact HUD fits allotted row at fixture values")
	_check(view.diagnostics_panel.get_child_count() > 0 and view.legacy_confirm.ok_button_text == "确认归属并迁入", "details and explicit legacy association confirmation are constructed")
	_check(not view.legacy_import_button.visible, "legacy import control starts hidden without pending legacy receipt")
	await _capture_diagnostics_fixture(metrics)
	view.free()
	view = null
	sound.free()
	sound = null
	client.free()
	client = null
	world.free()
	world = null
	source.free()
	print("CLIENT_DIAGNOSTICS_UI_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _capture_diagnostics_fixture(metrics: Dictionary) -> void:
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			destination = argument.trim_prefix("--capture=").replace("\\", "/").simplify_path()
	if destination.is_empty():
		return
	var allowed := ProjectSettings.globalize_path("res://logs/")
	if not destination.begins_with(allowed) or not destination.ends_with(".png") or FileAccess.file_exists(destination) or not ClientData._plain_path(destination) or DisplayServer.get_name() == "headless":
		_check(false, "render capture requires fresh project log PNG and real renderer")
		return
	root.gui_embed_subwindows = true
	root.size = Vector2i(1240, 780)
	view._process(0)
	view.diagnostics_detail.text = View.diagnostics_details(metrics) + "\n\n诊断日志已停记（权限、容量或写入失败）；游戏不受影响；音效设置未保存；队列满时丢弃了 999999 条记录"
	view.diagnostics_panel.popup_centered(Vector2i(810, 430))
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_check(view.diagnostics_detail.position.y + view.diagnostics_detail.size.y <= 348, "long diagnostics state stays above action buttons")
	_check(root.get_texture().get_image().save_png(destination) == OK, "actual rendered diagnostics screenshot saved")

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
