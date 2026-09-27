extends "res://tests/run_framework_clients.gd"
## Client-perceived latency of asset calls through a real Operator: each awaited
## AccountClient call is timed from the client side (WSS lobby -> Operator ->
## storage helpers -> reply). Lobby context only; no room permit hop.
## The parent harness registers nothing itself: it funds this account after the
## driver reports LOBBY, then creates funded.flag in the control directory.
var perf := {}
var retry_code := ""

func _run() -> void:
	await super._run()
	if not driver_ready:
		return
	var control: String = test_settings.control_directory
	var deadline := Time.get_ticks_msec() + 120000
	while not FileAccess.file_exists(control.path_join("funded.flag")) and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok := true
	for index in 3:
		var started := Time.get_ticks_usec()
		ok = _record("read", started, await client.read_assets()) and ok
	var buy_smg := Wire.uid()
	var started := Time.get_ticks_usec()
	ok = _record("purchase", started, await client.purchase("smg", buy_smg)) and ok
	started = Time.get_ticks_usec()
	var retry: Dictionary = await client.purchase("smg", buy_smg)
	ok = _record("purchase_retry", started, retry) and ok
	retry_code = str(retry.get("code", ""))
	started = Time.get_ticks_usec()
	ok = _record("purchase", started, await client.purchase("shotgun", Wire.uid())) and ok
	var items := ["rifle", "smg", "shotgun"]
	for index in 6:
		started = Time.get_ticks_usec()
		ok = _record("select", started, await client.select_item("primary", items[index % 3], Wire.uid())) and ok
	var file := FileAccess.open(str(test_settings.report_path) + ".perf.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "samples": perf, "purchase_retry_code": retry_code}))
		file.close()
	print("ASSET_E2E_CLIENT_DONE ok=", ok)
	driver_report.phase = "DONE"
	_write_driver_report()
	quit(0 if ok else 1)

func _record(operation: String, started: int, result: Dictionary) -> bool:
	if not perf.has(operation):
		perf[operation] = []
	perf[operation].append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	if not result.get("ok", false):
		printerr("ASSET_E2E_CALL_FAILED ", operation, " code=", result.get("code", ""))
	return result.get("ok", false)
