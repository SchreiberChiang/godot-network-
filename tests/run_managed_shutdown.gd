extends SceneTree
## Real managed host + real room process + SDK WSS/DTLS client. The trusted
## operator RPC account/asset/result responses below are fixtures, not SQLite
## acceptance. Holding asset.initial creates a deterministic admission race.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Bus = preload("res://sdk/roomkit/shared/local_rpc.gd")
const Launcher = preload("res://host/platform/process_launcher.gd")
const Client = preload("res://sdk/roomkit/client/account_client.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
var bus = Bus.new()
var launcher = Launcher.new()
var client = Client.new()
var context: Dictionary = {}
var latest: Dictionary = {}
var host_peer := ""
var launch_id := ""
var room_id := ""
var room_port := 0
var recreate_room_id := ""
var recreate_room_port := 0
var recreate_result: Dictionary = {}
var stop_result: Dictionary = {}
var passed := 0
var failed := 0
var started := 0
var finishing := false
var hold_assets := false
var held_asset: Dictionary = {}
var join_result: Dictionary = {}
var asset_requests := 0
var stopped_notice := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-config="):
			context = Wire.decode(FileAccess.get_file_as_bytes(arg.trim_prefix("--test-config=")), "", 65536)
	started = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	bus.poll()
	if not finishing and Time.get_ticks_msec() - started > 140000:
		check(false, "test watchdog reached bounded cleanup")
		_finish.call_deferred()
	return false

func _run() -> void:
	if not check(not context.is_empty(), "isolated private fixture settings loaded"):
		await _finish()
		return
	var security := Secure.create_local_certificate(context.root)
	if not check(not security.is_empty(), "real test TLS certificate created"):
		await _finish()
		return
	launch_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	bus.requested.connect(_rpc)
	bus.peer_event.connect(_event)
	if not check(bus.listen(secret, launch_id) == OK, "authenticated local operator fixture listening"):
		await _finish()
		return
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	var udp := _free_udp_block()
	settings.merge({"control_port": _free_tcp(), "lobby_port": _free_tcp(), "lobby_bind": "127.0.0.1", "advertised_host": "127.0.0.1", "game_bind": "127.0.0.1", "udp_first": udp, "udp_last": udp + 3, "max_rooms": 4, "process_journal": str(context.root).path_join("processes.json"), "security": security, "start_timeout_ms": 30000, "heartbeat_timeout_ms": 10000}, true)
	if not check(udp > 0 and settings.control_port != settings.lobby_port, "independent free TCP and UDP ports selected"):
		await _finish()
		return
	var bootstrap := {"rpc": {"port": bus.port, "token": secret, "launch_id": launch_id}, "settings": settings, "games": {"shooter": context.game}, "result_root": context.root, "result_schemas": {"shooter": "res://schemas/shooter_result.schema.json"}}
	var bootstrap_path: String = str(context.root).path_join("managed-bootstrap.json")
	_write(bootstrap_path, bootstrap)
	var launched: Dictionary = launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", Paths.absolute("res://"), "--log-file", str(context.evidence).path_join("managed-host.log"), "--script", "res://host/managed_host.gd", "--", "--managed-config=" + bootstrap_path]}, launch_id, ["--launch-id=" + launch_id])
	if not check(launched.ok and launcher.record(launch_id).get("verified", false), "exact managed host process ownership verified"):
		await _finish()
		return
	if not check(await _wait(func(): return latest.get("host", {}).get("state", "") == "RUNNING", 25000), "real managed host and WSS lobby RUNNING"):
		await _finish()
		return
	var created: Dictionary = await _admin("room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 4})
	if not check(created.ok, "trusted operator creates isolated real shooter room"):
		await _finish()
		return
	room_id = created.payload.room_id
	if not check(await _wait(func(): return _row().get("state", "") == "READY", 35000), "room child registered READY after UDP bind"):
		await _finish()
		return
	room_port = int(_row().port)
	check(not _udp_available(room_port), "live room UDP port is occupied")
	root.add_child(client)
	var world = preload("res://examples/shooter/game.gd").new()
	world.name = "GameWorld"
	root.add_child(world)
	var configuration: Dictionary = context.game.manifest.duplicate(true)
	configuration.merge({"url": "wss://127.0.0.1:%d" % int(settings.lobby_port), "ca_certificate": security.certificate, "server_hostname": "localhost", "secure_enet": true, "managed": true})
	check(client.configure(configuration), "unmodified managed SDK client configured")
	if not check((await client.login("shutdown_fixture", "FixturePassword!123")).ok, "real WSS account exchange using trusted identity fixture"):
		await _finish()
		return
	var first_notice: Dictionary = await client.notice()
	check(first_notice.ok and not first_notice.payload.maintenance, "client reads normal service notice")

	# A valid reservation issued before closing a room must not authorize a later ENet join.
	var reserved: Dictionary = await _reserve()
	check(reserved.ok, "ticket issued before joinability change")
	check((await _admin("room.joinable", {"room_id": room_id, "joinable": false})).ok, "operator closes admission on live room")
	var before := asset_requests
	var rejected: Dictionary = await client._connect_reserved(reserved.payload)
	check(not rejected.ok and asset_requests == before, "real DTLS ticket consume rejected after joinable false")
	check(await _wait(_no_seat), "rejected ticket releases its reserved seat")
	check((await _admin("room.joinable", {"room_id": room_id, "joinable": true})).ok, "operator reopens live room")
	reserved = await _reserve()
	check(reserved.ok, "new ticket available after rejected prior reservation")
	check((await _admin("maintenance.set", {"enabled": true, "message": "专项维护"})).ok, "ordinary maintenance enabled")
	before = asset_requests
	rejected = await client._connect_reserved(reserved.payload)
	check(not rejected.ok and asset_requests == before, "preissued DTLS ticket cannot cross maintenance boundary")
	check(await _wait(_no_seat), "maintenance rejection releases pending seat")
	check((await _admin("maintenance.set", {"enabled": false})).ok, "ordinary maintenance can end before shutdown")
	var joined: Dictionary = await client.join_room(room_id)
	check(joined.ok and client.state == "IN_ROOM", "positive control completes real WSS ticket and DTLS room admission")
	check((await _admin("maintenance.set", {"enabled": true, "message": "专项维护"})).ok, "maintenance toggles while an existing player stays connected")
	var maintenance_notice: Dictionary = await client.notice()
	check(maintenance_notice.ok and maintenance_notice.payload.message == "专项维护" and client.state == "IN_ROOM", "existing client reads maintenance announcement without forced disconnect")
	check((await _admin("maintenance.set", {"enabled": false})).ok, "maintenance restored for pending admission race")
	await client.leave_room()
	check(await _wait(_no_seat), "positive control leaves room and reclaims seat")

	# Deliberately delay only the trusted asset response, after ticket authentication.
	if not await _hold_join():
		await _finish()
		return
	check((await _admin("room.joinable", {"room_id": room_id, "joinable": false})).ok, "room closed while asset.initial response is pending")
	_release_asset()
	check(await _wait(func(): return not join_result.is_empty()), "pending join completed after held response returned")
	check(not join_result.get("ok", true) and client.state == "LOBBY", "final admission rechecks joinability after await")
	check(await _wait(_no_seat), "late joinability rejection reclaims ADMITTING seat")
	check((await _admin("room.joinable", {"room_id": room_id, "joinable": true})).ok, "room reopened before shutdown race")
	var extra: Dictionary = await _admin("room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 2})
	if not check(extra.ok, "second real room created for in-flight recreate boundary"):
		await _finish()
		return
	recreate_room_id = extra.payload.room_id
	if not check(await _wait(func(): return _find_room(recreate_room_id).get("state", "") == "READY", 35000), "second real room reaches READY"):
		await _finish()
		return
	recreate_room_port = int(_find_room(recreate_room_id).port)
	if not await _hold_join():
		await _finish()
		return
	# Queue both RPCs before the next bus flush: recreate first enters its await,
	# then stop sets the gate before any subsequent room-manager cleanup tick.
	_recreate_other.call_deferred()
	_stop_gracefully.call_deferred()
	check(await _wait(func(): return not stop_result.is_empty()) and stop_result.get("ok", false), "managed host accepts real sixty second graceful stop")
	check(await _wait(func(): return not recreate_result.is_empty()) and not recreate_result.get("ok", true) and recreate_result.get("code", "") == "ROOM_DRAINING", "in-flight recreate rechecks stop after old process exit")
	check(latest.get("rooms", []).size() == 2, "in-flight recreate did not allocate a replacement during shutdown")
	var toggle: Dictionary = await _admin("maintenance.set", {"enabled": false})
	check(not toggle.ok and toggle.code == "ROOM_DRAINING", "maintenance false cannot override accepted shutdown")
	var overwrite: Dictionary = await _admin("maintenance.set", {"enabled": true, "message": "overwrite attempt"})
	check(not overwrite.ok and overwrite.code == "ROOM_DRAINING", "maintenance message cannot overwrite shutdown countdown")
	_release_asset()
	check(await _wait(func(): return not join_result.is_empty()), "pending shutdown join completes after held response")
	check(not join_result.get("ok", true) and client.state == "LOBBY", "final admission rechecks shutdown after asynchronous asset response")
	check(await _wait(_no_seat), "shutdown race leaves no connected or pending seat")
	var notice_a: Dictionary = await client.notice()
	var seconds_a := _seconds(notice_a)
	check(notice_a.ok and notice_a.payload.maintenance and seconds_a > 40 and seconds_a <= 60, "actual WSS client reads graceful stop countdown message")
	await create_timer(2.2).timeout
	check((await _admin("server.stop", {"immediate": false})).ok, "repeated graceful stop accepted without extending deadline")
	var notice_b: Dictionary = await client.notice()
	var seconds_b := _seconds(notice_b)
	check(notice_b.ok and notice_b.payload.maintenance and seconds_b > 0 and seconds_b <= seconds_a - 2, "second actual WSS countdown decreases despite repeated stop")
	print("CLIENT_COUNTDOWN first=", seconds_a, " second=", seconds_b)
	var blocked_create: Dictionary = await client.create_room({"mode": "ffa", "map": "depot", "capacity": 2})
	var blocked_reserve: Dictionary = await _reserve()
	check(not blocked_create.ok and blocked_create.code == "ROOM_DRAINING", "real player create refused during shutdown")
	check(not blocked_reserve.ok and blocked_reserve.code == "ROOM_DRAINING", "real player reserve refused during shutdown")
	var admin_create: Dictionary = await _admin("room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 2})
	var admin_recreate: Dictionary = await _admin("room.recreate", {"room_id": room_id})
	check(not admin_create.ok and admin_create.code == "ROOM_DRAINING" and not admin_recreate.ok and admin_recreate.code == "ROOM_DRAINING", "operator create and recreate remain refused while stopping")
	await _finish()

func _hold_join() -> bool:
	hold_assets = true
	held_asset = {}
	join_result = {}
	_join.call_deferred()
	return check(await _wait(func(): return not held_asset.is_empty(), 15000), "real authenticated join waits at trusted asset.initial boundary")

func _join() -> void:
	join_result = await client.join_room(room_id)

func _recreate_other() -> void:
	recreate_result = await _admin("room.recreate", {"room_id": recreate_room_id})

func _stop_gracefully() -> void:
	stop_result = await _admin("server.stop", {"immediate": false})

func _release_asset() -> void:
	hold_assets = false
	if not held_asset.is_empty():
		bus.respond(held_asset.peer, held_asset.id, _asset_state())
		held_asset = {}

func _reserve() -> Dictionary:
	var request: Dictionary = client.compatibility()
	request.room_id = room_id
	return await client._request("room.reserve", request)

func _admin(action: String, payload: Dictionary) -> Dictionary:
	return await bus.request(action, payload, 10000, host_peer)

func _rpc(peer: String, id: String, action: String, payload: Dictionary) -> void:
	var response := {"ok": true, "code": "", "payload": {}}
	match action:
		"account.execute":
			if payload.get("op", "") == "account.login":
				response = {"ok": true, "code": "", "token": "a".repeat(64), "identity": {"user_id": "shutdown_test_player", "display_name": "Shutdown fixture", "role": "player"}, "expires": int(Time.get_unix_time_from_system()) + 600}
			elif payload.get("op", "") != "session.logout":
				response = Wire.failure("AUTH_FAILED")
		"asset.initial":
			asset_requests += 1
			if hold_assets:
				held_asset = {"peer": peer, "id": id}
				return
			response = _asset_state()
		"result.grant": pass
		_: response = Wire.failure("INVALID_OPTIONS")
	bus.respond(peer, id, response)

func _asset_state() -> Dictionary:
	return {"ok": true, "payload": {"state": {"revision": 1, "credits": 0, "experience": 0, "owned": ["rifle"], "profiles": {"shooter": {"primary": "rifle"}}}}}

func _event(peer: String, action: String, payload: Dictionary) -> void:
	if action == "host.status":
		host_peer = peer
		latest = payload.duplicate(true)
	elif action == "host.stopped":
		stopped_notice = true
	elif action == "host.failed":
		check(false, "managed host failed: " + payload.get("code", ""))

func _row() -> Dictionary:
	return _find_room(room_id)

func _find_room(target: String) -> Dictionary:
	for row in latest.get("rooms", []):
		if row.room_id == target:
			return row
	return {}

func _no_seat() -> bool:
	for player in latest.get("players", []):
		if player.user_id == "shutdown_test_player":
			return player.state == "LOBBY"
	return false

func _seconds(notice: Dictionary) -> int:
	var pattern := RegEx.new()
	pattern.compile("^服务器将在 ([0-9]+) 秒后停止，请保存操作。$")
	var found := pattern.search(notice.get("payload", {}).get("message", ""))
	return int(found.get_string(1)) if found != null else -1

func _free_tcp() -> int:
	var listener := TCPServer.new()
	if listener.listen(0, "127.0.0.1") != OK:
		return 0
	var port := listener.get_local_port()
	listener.stop()
	return port

func _free_udp_block() -> int:
	for _attempt in range(100):
		var first := randi_range(48000, 55000)
		var available := true
		for offset in range(4):
			available = _udp_available(first + offset) and available
		if available:
			return first
	return 0

func _udp_available(port: int) -> bool:
	var udp := PacketPeerUDP.new()
	var result := udp.bind(port, "127.0.0.1")
	udp.close()
	return result == OK

func _wait(predicate: Callable, timeout: int = 10000) -> bool:
	var end := Time.get_ticks_msec() + timeout
	while not predicate.call() and Time.get_ticks_msec() < end and not finishing:
		await process_frame
	return predicate.call()

func check(condition: bool, label: String) -> bool:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
	return condition

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _finish() -> void:
	if finishing:
		return
	finishing = true
	_release_asset()
	if host_peer != "" and launcher.probe(launch_id) == "running":
		check((await _admin("server.stop", {"immediate": true})).ok, "immediate stop shortens deadline for owned cleanup")
	var end := Time.get_ticks_msec() + 20000
	while launch_id != "" and launcher.probe(launch_id) == "running" and Time.get_ticks_msec() < end:
		await process_frame
	if launch_id != "" and launcher.probe(launch_id) == "running":
		check(false, "managed host exceeded verified shutdown deadline")
		launcher.terminate(launch_id)
	if launch_id != "" and launcher.record(launch_id).size() > 0:
		check(launcher.probe(launch_id) == "exited", "exact owned managed host OS exit confirmed")
		launcher.forget(launch_id)
	if room_port > 0:
		check(_udp_available(room_port), "real child room UDP port reclaimed after host stop")
		if recreate_room_port > 0:
			check(_udp_available(recreate_room_port), "second child port reclaimed after aborted recreate")
		var journal: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(context.root).path_join("processes.json")))
		check(journal is Dictionary and journal.get("entries", {"missing": true}).is_empty(), "confirmed room exit removed private process journal entry")
	client.close()
	bus.close()
	if not context.is_empty():
		_write(str(context.evidence).path_join("result.json"), {"passed": passed, "failed": failed, "scope": "real managed host + shooter process + SDK WSS/DTLS; trusted RPC account/asset/result fixtures", "host_stopped_notice": stopped_notice, "room_port": room_port, "test_root": context.root})
	print("MANAGED_SHUTDOWN_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
