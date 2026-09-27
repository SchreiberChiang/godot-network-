extends "res://tests/run_framework_clients.gd"
## Real headless client for tests/test_account_deletion.ps1. After the harness funds
## the account it buys one item; after the harness deletes (or keeps) the account it
## reports whether the host closed this connection, whether the old session can
## still read assets, and what signing in again returns.

func _run() -> void:
	await super._run()
	if not driver_ready:
		return
	var control: String = test_settings.control_directory
	if not await _wait_flag(control.path_join("funded.flag")):
		_done(false)
		return
	var bought: Dictionary = await client.purchase("smg", Wire.uid())
	driver_report.purchase_code = str(bought.get("code", ""))
	driver_report.purchase_ok = bought.get("ok", false)
	# Shops are closed during a live round, so a seated player buys first, then joins.
	if str(test_settings.get("join_room_id", "")) != "":
		selected_room = test_settings.join_room_id
		await join_selected()
		driver_report.joined = client.state == "IN_ROOM"
	_write_driver_report()
	if not await _wait_flag(control.path_join("check.flag")):
		_done(false)
		return
	var deadline := Time.get_ticks_msec() + 8000
	while client.socket.get_ready_state() != WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec() < deadline and test_settings.get("expect_deleted", false):
		await process_frame
	driver_report.socket_closed = client.socket.get_ready_state() == WebSocketPeer.STATE_CLOSED
	driver_report.state_after = str(client.state)
	var read_after: Dictionary = await client.read_assets()
	driver_report.read_after_ok = read_after.get("ok", false)
	driver_report.read_after_code = str(read_after.get("code", ""))
	if test_settings.get("expect_deleted", false):
		client.close()
		var again: Dictionary = await client.login(test_settings.username, test_settings.password)
		driver_report.relogin_ok = again.get("ok", false)
		driver_report.relogin_code = str(again.get("code", ""))
	_done(true)

func _wait_flag(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 180000
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
		await process_frame
	return FileAccess.file_exists(path)

func _done(ok: bool) -> void:
	driver_report.phase = "DONE"
	driver_report.ok = ok
	_write_driver_report()
	print("DELETION_CLIENT_DONE ok=", ok)
	quit(0 if ok else 1)
