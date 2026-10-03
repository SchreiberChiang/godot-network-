extends "res://examples/framework/client.gd"
## Isolated local privacy, mail-draft and clipboard checks. No services/mail app.
class FakeAccount:
	extends "res://sdk/roomkit/client/account_client.gd"
	var requests: Array[Dictionary] = []
	func _request(type: String, payload: Dictionary, _key: String = "") -> Dictionary:
		requests.append({"type": type, "payload": payload.duplicate(true)})
		return {"ok": false, "code": "CONTROL_UNAVAILABLE"}
var opened: Array[String] = []
var copied: Array[String] = []
var draft_result := OK
func _open_mail_draft(uri: String) -> int:
	opened.append(uri)
	return draft_result
func _copy_report_text(text: String) -> bool:
	copied.append(text)
	return true
var passed := 0
var failed := 0
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	_verify.call_deferred()
func _process(_delta: float) -> bool:
	return false
func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", label)
func _verify() -> void:
	local_data = ClientData.new()
	_check(not local_data.configure("relative-unsafe", "synthetic-n1"), "fixture refuses disk path; no files written")
	var secret := "PASSWORD_USER_IP_PATH_RAW_ERROR"
	var raw := {"username": secret, "token": secret, "path": secret, "ip": secret, "close_reason": secret, "error": secret, "phase": secret, "rtt_ms": -1, "frame_max_ms": NAN, "fps": 60, "loss_state": "collecting", "rx_bytes_per_sec": "12"}
	_check(not local_data.sample(raw), "journal disabled without disabling memory collection")
	mark_stall()
	_check(message.contains("已保留内存"), "write-disabled successful marker accurately reported")
	mark_stall()
	_check(message.contains("未新增标记"), "repeat marker does not claim retention")
	var report: Dictionary = local_data.diagnostic_report()
	_check(PlayerReport.validate(report) and report.records.size() == 2, "write-disabled sample and marker collected")
	_check(not JSON.stringify(report).contains(secret), "all arbitrary sensitive values absent")
	_check(not report.records[0].has("rtt_ms") and not report.records[0].has("frame_max_ms") and not report.records[0].has("rx_bytes_per_sec"), "unknown, nonfinite and wrong-type metrics omitted rather than zero")
	_check(report.records[0].loss_state == "collecting" and report.records[0].fps == 60, "known metrics preserved")
	var loss_report: Dictionary = report.duplicate(true)
	loss_report.records[0].reliable_loss_percent = 0
	loss_report.records[0].loss_sample_count = 0
	_check(PlayerReport.summary(loss_report).contains("丢包估计 未知") and PlayerReport.mailto(loss_report, "test@example.com").uri_decode().contains("丢包估计 未知"), "collecting zero loss remains unknown in copied and mailed output")
	loss_report.records[0].loss_state = "available"
	loss_report.records[0].loss_sample_count = 1
	_check(PlayerReport.summary(loss_report).contains("丢包估计 0%") and PlayerReport.mailto(loss_report, "test@example.com").uri_decode().contains("丢包估计 0%"), "mature measured zero loss remains zero in both local outputs")
	_check(PlayerReport.summary(loss_report).contains("不代表全部 UDP") and PlayerReport.mailto(loss_report, "test@example.com").uri_decode().contains("不代表全部 UDP"), "standalone local summaries explain reliable-send loss scope")
	var tampered: Dictionary = report.duplicate(true)
	tampered.records[0].password = secret
	_check(not PlayerReport.validate(tampered), "record arbitrary fields rejected")
	tampered = report.duplicate(true)
	tampered.username = secret
	_check(not PlayerReport.validate(tampered), "top-level arbitrary fields rejected")
	tampered = report.duplicate(true)
	tampered.report_id = "A".repeat(32)
	_check(not PlayerReport.validate(tampered), "lowercase random id required")
	tampered = report.duplicate(true)
	tampered.records = []
	for index in 33:
		tampered.records.append(report.records[0])
	_check(not PlayerReport.validate(tampered), "more than 32 records rejected")
	var full := {}
	for key in PlayerReport.record_schema().properties:
		if PlayerReport.record_schema().properties[key].get("type") == "number":
			full[key] = 9007199254740991
	for index in 50:
		local_data._enqueue(local_data._record(full, "sample"))
	_check(local_data._recent.size() == 32, "ring bounded to 32 including markers")
	var bounded: Dictionary = local_data.diagnostic_report()
	_check(PlayerReport.validate(bounded) and JSON.stringify(bounded).to_utf8_buffer().size() <= 12000 and bounded.records.size() < 32, "byte bound drops oldest records")
	tampered = bounded.duplicate(true)
	tampered.records = local_data._recent.duplicate(true)
	_check(not PlayerReport.validate(tampered), "validator independently enforces UTF8 byte bound")
	var now := Time.get_ticks_msec()
	local_data._recent[0].monotonic_ms = now - 120001
	local_data._recent[1].monotonic_ms = now - 120000
	var at_boundary: Dictionary = local_data.diagnostic_report("1".repeat(32), now)
	_check(at_boundary.records[0].monotonic_ms >= now - 120000, "recent window excludes older records")
	_check(local_data.diagnostic_report("", now + 120001).is_empty(), "expired ring yields no report")
	local_data._enqueue(local_data._record({"fps": 42}, "sample"))
	client = FakeAccount.new()
	client.identity = {"user_id": "synthetic-user"}
	client.config = {"url": "wss://synthetic.invalid:443"}
	root.add_child(client)
	authenticated = false
	_check(client.requests.is_empty() and opened.is_empty() and copied.is_empty(), "collection never opens composer, copies or uploads")
	submit_diagnostic_report()
	_check(opened.is_empty() and report_message.contains("未配置"), "missing recipient opens nothing and offers manual fallback")
	for address in ["a@example.com\n", "a@example.com\r\nBcc:evil@example.com", "a@example.com?subject=evil", "a@example.com&bcc=b@example.com", "a@example.com#evil", "a@example.com/evil", " a@example.com", "mailto:a@example.com", "a@example.com=" , "a@example.com@example.com", "a@bad..invalid", "a@-bad.invalid", "a@" + "b".repeat(64) + ".invalid"]:
		_check(not PlayerReport.valid_email(address), "reject mailto/control injection: " + address.c_escape())
	_check(PlayerReport.valid_email("synthetic.report+local@example.com"), "plain external configured email accepted")
	report_email = "synthetic.report+local@example.com"
	submit_diagnostic_report()
	_check(opened.size() == 1 and opened[0].begins_with("mailto:" + report_email), "offline explicit click opens one local draft")
	_check(opened[0].to_utf8_buffer().size() <= 1800 and not opened[0].contains("\n") and not opened[0].contains(secret), "whole percent-encoded mailto bounded and sanitized")
	_check(not busy and not report_busy and report_message.contains("自行点击发送") and not report_message.contains("已发送"), "draft status neither locks gameplay nor claims sent")
	await process_frame
	_check(opened.size() == 1 and client.requests.is_empty(), "no automatic draft reopening or game-server request")
	report_busy = true
	submit_diagnostic_report()
	_check(opened.size() == 1 and not busy, "busy click suppressed without gameplay lock")
	report_busy = false
	draft_result = ERR_UNAVAILABLE
	submit_diagnostic_report()
	_check(opened.size() == 2 and report_message.contains("无法打开") and copied.is_empty(), "missing mail app offers fallback without silently overwriting clipboard")
	copy_diagnostic_report()
	_check(copied.size() == 1 and copied[0].contains("脱敏诊断摘要") and copied[0].contains("未知") and not copied[0].contains(secret), "explicit offline copy produces sanitized human summary with unknown preserved")
	copy_report_recipient()
	_check(copied.size() == 2 and copied[1] == report_email, "recipient copied only on explicit action")
	var maximum_uri: String = PlayerReport.mailto(bounded, "a".repeat(64) + "@" + "b".repeat(60) + "." + "c".repeat(60) + ".example")
	_check(not maximum_uri.is_empty() and maximum_uri.to_utf8_buffer().size() <= 1800, "large numeric metrics and long email remain within entire URI limit")
	_check(PlayerReport.summary({}).is_empty() and PlayerReport.mailto({}, report_email).is_empty(), "invalid report cannot become summary or mail draft")
	_check(client.requests.is_empty(), "all draft and fallback actions avoid SDK network API")
	sound = Sound.new()
	root.add_child(sound)
	view = View.new()
	view.app = self
	root.add_child(view)
	view.set_process(false)
	_check(view.report_submit_button.text == "准备反馈邮件", "explicit visible local mail action")
	view.diagnostics_panel.popup_centered(Vector2i(810, 526))
	view._process(0.11)
	_check(not view.report_submit_button.disabled, "mail action available while logged out and offline")
	_check(view.report_submit_button.position.x >= 440 and view.report_result.position.y > 470 and view.report_result.position.y + view.report_result.size.y <= view.diagnostics_panel.size.y, "mail, copy actions, disclosure and result have separate rows")
	if args.has("--screenshot") and DisplayServer.get_name() != "headless":
		root.gui_embed_subwindows = true
		root.size = Vector2i(1240, 820)
		report_message = "无法打开邮件应用；请复制摘要和收件地址，在邮件应用或网页邮箱中粘贴发送"
		view.diagnostics_panel.popup_centered(Vector2i(810, 526))
		view._process(0.11)
		for index in 4:
			await process_frame
		await _capture_if_requested()
	view.free()
	view = null
	sound.free()
	sound = null
	client.free()
	client = null
	local_data.close()
	local_data = null
	print("PLAYER_REPORT_CLIENT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
