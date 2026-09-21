extends "res://host/operator.gd"
## Real Operator + separate managed host + unmodified AccountClient + SQLite.
## No gameplay room is required for this lobby permanent-asset transaction.
const Client = preload("res://sdk/roomkit/client/account_client.gd")
var test_passed := 0
var test_failed := 0
var test_started := 0
var test_finishing := false
var test_client
var test_host_record: Dictionary = {}
var test_operation := ""
var test_user := ""
var test_receipts := 0
var test_lost_code := ""
var test_checks: Array = []

func _initialize() -> void:
	test_started = Time.get_ticks_msec()
	super._initialize()
	_exercise.call_deferred()

func _publish_connection() -> void:
	# Never alter another source/native instance's public client configuration.
	pass

func _launch(descriptor: Dictionary, launch_id: String, path: String) -> Dictionary:
	var isolated := descriptor.duplicate(true)
	var entry: int = isolated.args.find("res://host/managed_host.gd")
	if entry < 0:
		return {"started": Wire.failure("TEST_HOST_ENTRY_MISSING"), "owned": {}}
	isolated.args[entry] = "res://tests/fault_lost_response_host.gd"
	return super._launch(isolated, launch_id, path)

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if not test_finishing and Time.get_ticks_msec() - test_started > 160000:
		check(false, "bounded test watchdog requests owned cleanup")
		_finish.call_deferred()
	return result

func _exercise() -> void:
	if not check(await wait_for(func(): return ready, 40000), "actual isolated Operator initializes databases and HTTP"):
		await _finish()
		return
	var username := "fault_player_" + Wire.uid().left(8)
	var password := "Test!" + Wire.uid()
	var admin: Dictionary = await _admin({"action": "setup.create", "payload": {"username": "fault_admin", "password": "Admin!" + Wire.uid()}})
	if not check(admin.ok, "real administrator account established"):
		await _finish()
		return
	var admin_token: String = admin.payload.token
	var start: Dictionary = await _start_host()
	if not check(start.ok and await wait_for(func(): return snapshot.host.state == "RUNNING", 25000), "separate real managed host and WSS listener reach RUNNING"):
		await _finish()
		return
	test_host_record = launcher.record(host_launch).duplicate(true)
	check(test_host_record.get("verified", false), "managed host launch identity verified and owned")
	var invitation: Dictionary = await _admin({"action": "invite.create", "payload": {"uses": 1, "expires_hours": 1, "reason": "isolated lost response test"}, "token": admin_token})
	if not check(invitation.ok, "real one-use registration invitation created"):
		await _finish()
		return
	var configuration: Dictionary = games.shooter.manifest.duplicate(true)
	configuration.merge({"url": "wss://127.0.0.1:%d" % int(settings.lobby_port), "ca_certificate": root_path.path_join("server.crt"), "server_hostname": "localhost", "secure_enet": true, "managed": true})
	test_client = Client.new()
	root.add_child(test_client)
	check(test_client.configure(configuration), "original AccountClient configured for private WSS certificate")
	var registered: Dictionary = await test_client.register_account(username, password, "Fault Player", invitation.payload.invite_code)
	if not check(registered.ok, "player registration traverses real WSS and SQLite"):
		await _finish()
		return
	var login: Dictionary = await test_client.login(username, password)
	if not check(login.ok, "original AccountClient authenticates over WSS"):
		await _finish()
		return
	test_user = test_client.identity.user_id
	var old_token: String = test_client.session_token
	var old_socket = test_client.socket
	var funded: Dictionary = await _admin({"action": "asset.adjust", "payload": {"user_id": test_user, "game_id": "shooter", "coins_delta": 500, "xp_delta": 0, "reason": "isolated test balance", "operation_id": Wire.uid()}, "token": admin_token})
	if not check(funded.ok, "real admin transaction funds known starting balance"):
		await _finish()
		return
	var before: Dictionary = await test_client.read_assets()
	if not check(before.ok and before.payload.state.credits == 500 and not before.payload.state.owned.has("smg"), "WSS asset read confirms initial balance and locked weapon"):
		await _finish()
		return
	test_operation = "lost_response_" + Wire.uid()
	var lost: Dictionary = await test_client.purchase("smg", test_operation)
	test_lost_code = lost.get("code", "")
	check(not lost.ok and lost.get("code", "") == "CONTROL_UNAVAILABLE", "SDK actually observes failed purchase reply from disconnected transport")
	check(await wait_for(func(): return old_socket.get_ready_state() == WebSocketPeer.STATE_CLOSED, 5000), "original WSS connection actually reaches CLOSED")
	var marker := Wire.decode(FileAccess.get_file_as_bytes(root_path.path_join("lost-response.json")), "", 65536)
	if not check(marker.get("committed", false) and marker.get("operation_id", "") == test_operation and not marker.get("reply_sent", true) and marker.get("tcp_disconnected", false) and marker.get("removed_from_lobby", false), "server-side evidence proves commit preceded actual TCP disconnect with no reply send"):
		await _finish()
		return
	check(test_client._answers.is_empty() and test_client._pending.is_empty(), "original SDK received no success answer for the lost operation")
	var committed: Dictionary = await _work(assets.read.bind(test_user, "shooter"))
	check(committed.ok and committed.state.credits == 400 and committed.state.owned.count("smg") == 1 and committed.state.revision == before.payload.state.revision + 1, "independent real database read confirms one purchase already committed")
	test_client.close()
	var relogin: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		relogin = await test_client.login(username, password)
		if relogin.ok or relogin.get("code", "") != "ALREADY_LOGGED_IN":
			break
		await create_timer(0.25).timeout
	if not check(relogin.get("ok", false) and test_client.identity.user_id == test_user and test_client.socket != old_socket and test_client.session_token != old_token, "same player reconnects on a new real WSS socket with a fresh authenticated session"):
		await _finish()
		return
	var after_reconnect: Dictionary = await test_client.read_assets()
	check(after_reconnect.ok and after_reconnect.payload.state == committed.state, "reconnected WSS read discovers committed ownership before replay")
	var replay: Dictionary = await test_client.purchase("smg", test_operation)
	check(replay.ok and replay.payload.get("code", "") == "DUPLICATE" and replay.payload.state == committed.state, "same operation_id replay returns original receipt without a second debit")
	var final_state: Dictionary = await test_client.read_assets()
	check(final_state.ok and final_state.payload.state == committed.state, "real WSS final balance ownership and revision remain unchanged after replay")
	var audit_result: Dictionary = await _work(assets.repository.execute.bind({"op": "asset.audit", "user_id": test_user}))
	if check(audit_result.ok, "real SQLite asset audit is available after reconnect replay"):
		for row in audit_result.rows:
			if row.request_id == test_operation:
				test_receipts += 1
				var previous: Dictionary = JSON.parse_string(row.previous_body)
				var changed: Dictionary = JSON.parse_string(row.body)
				check(previous.credits - changed.credits == 100 and changed.owned.count("smg") == 1, "persisted purchase audit records exactly one price debit and one ownership grant")
		check(test_receipts == 1 and audit_result.rows.size() == 2, "SQLite contains exactly one purchase receipt plus the one explicit funding receipt")
	check((await test_client.logout()).ok, "reconnected real player session logs out normally")
	await _finish()

func wait_for(predicate: Callable, timeout_ms: int = 15000) -> bool:
	var until := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < until and not test_finishing:
		await process_frame
	return predicate.call()

func check(condition: bool, label: String) -> bool:
	test_checks.append({"name": label, "passed": condition})
	if condition:
		test_passed += 1
		print("PASS ", label)
	else:
		test_failed += 1
		printerr("FAIL ", label)
	return condition

func _finish() -> void:
	if test_finishing:
		return
	test_finishing = true
	quitting = true
	restart_after = 0
	restart_requested = false
	requested_stop = true
	if test_client != null:
		test_client.close()
	var until := Time.get_ticks_msec() + 30000
	while starting and Time.get_ticks_msec() < until:
		await process_frame
	if host_owned:
		await _host_command("server.stop", {"immediate": true})
	until = Time.get_ticks_msec() + 25000
	while (host_owned or host_closing) and Time.get_ticks_msec() < until:
		await process_frame
	if host_owned:
		check(false, "cleanup required exact verified host termination")
		await _work(_terminate_owned.bind(launcher.record(host_launch)))
		until = Time.get_ticks_msec() + 15000
		while (host_owned or host_closing) and Time.get_ticks_msec() < until:
			await process_frame
	check(not host_owned and not starting and not host_closing and launcher._records.is_empty(), "all actual managed-host process records confirmed exited and released")
	while worker_count > 0:
		await process_frame
	check(not FileAccess.file_exists(root_path.path_join("host-running.json")), "owned host journal removed after verified exit")
	http.close()
	if bus != null:
		bus.close()
	DirAccess.remove_absolute(root_path.path_join("operator.json"))
	_write_json(root_path.path_join("response-loss-result.json"), {"passed": test_passed, "failed": test_failed, "checks": test_checks, "elapsed_ms": Time.get_ticks_msec() - test_started, "host": test_host_record, "operation_id": test_operation, "purchase_receipts": test_receipts, "lost_client_code": test_lost_code, "scope": "actual Operator SQLite, child managed host and original AccountClient over WSS; test lobby drops exactly one committed success response and disconnects real TCP; no gameplay room or exported EXE", "public_connection_publishing": "suppressed by test subclass"})
	print("ASSET_RESPONSE_LOSS_RESULT passed=", test_passed, " failed=", test_failed, " evidence=", root_path)
	quit(0 if test_failed == 0 else 1)
