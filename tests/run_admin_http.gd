extends SceneTree
## Real local TCP/HTTP transport checks. Fixture handler is NOT an account/server test.
const HTTP = preload("res://host/admin_http.gd")
var server = HTTP.new()
var passed := 0
var failed := 0
var received: Array = []
var fixture_mode := "normal"

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	server.poll()
	return false

func _run() -> void:
	server.request_received.connect(_request)
	if not check(server.start(0) == OK and server.port > 0, "HTTP loopback listener starts on actual ephemeral port"):
		quit(1)
		return
	check(server.start(0) == ERR_ALREADY_IN_USE, "duplicate start does not replace active listener")
	var result := await fetch("GET / HTTP/1.1\r\nHost: %s\r\n\r\n" % authority())
	check(status(result) == 200 and result.get_string_from_utf8().contains("服务器总览"), "actual socket serves Chinese admin HTML")
	check(result.get_string_from_utf8().contains("frame-ancestors 'none'") and result.get_string_from_utf8().contains("Cache-Control: no-store"), "HTTP response supplies frame and cache protections")
	check(not result.get_string_from_utf8().contains("Access-Control-Allow-Origin"), "no CORS permission emitted")
	var start_count := received.size()
	result = await fetch(post("setup.status", {}))
	check(status(result) == 200 and received.size() == start_count + 1, "anonymous setup request reaches explicit service authorization boundary")
	check(received.back().token == "" and received.back().remote_ip == "127.0.0.1", "handler receives remote identity and empty anonymous token")
	result = await fetch(post("status", {}))
	check(status(result) == 401, "fixture service denies unauthenticated status through actual HTTP")
	result = await fetch(post("status", {}, "fixture-session"))
	check(status(result) == 200 and received.back().token == "fixture-session", "Bearer header passed to service, never from JSON body")
	var packet := post("asset.adjust", {"user_id": "test-user", "game_id": "test_game", "reason": "真实 TCP 中文分包", "coins_delta": 2, "xp_delta": 0, "operation_id": "test_adjust"}, "fixture-session").to_utf8_buffer()
	start_count = received.size()
	result = await fetch_bytes([packet.slice(0, 15), packet.slice(15, packet.size() - 8), packet.slice(packet.size() - 8)])
	check(status(result) == 200 and received.size() == start_count + 1, "split request line headers UTF8 body reassembled once over TCP")
	check(received.back().payload.get("reason", "") == "真实 TCP 中文分包", "body Content-Length uses UTF8 bytes")
	var valid_payloads := action_payloads()
	var admin_schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/admin_request.schema.json"))
	check(valid_payloads.size() == admin_schema.properties.action.enum.size(), "explicit realistic fixture covers every administrator action")
	for action in valid_payloads:
		result = await fetch(post(action, valid_payloads[action], "fixture-session"))
		check(status(result) == 200, "strict action payload accepted over actual HTTP: " + action)
		start_count = received.size()
		var invalid: Dictionary = valid_payloads[action].duplicate(true)
		invalid.executable = "C:/unexpected.exe"
		result = await fetch(post(action, invalid, "fixture-session"))
		check(status(result) == 400 and received.size() == start_count, "unexpected payload field rejected before service: " + action)
	# Asset-space membership is checked by the Operator's trusted registry, not
	# by the transport schema. A well-formed but unregistered mapping reaches it.
	var registry_checked: Dictionary = valid_payloads["config.set"].duplicate(true)
	registry_checked.config.asset_spaces["shooter"] = "turns"
	start_count = received.size()
	result = await fetch(post("config.set", registry_checked, "fixture-session"))
	check(status(result) == 200 and received.size() == start_count + 1, "well-formed asset mapping reaches registry authorization boundary")
	for invalid in [
		["room.create", {}], ["room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": "8"}],
		["room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 2.5}],
		["room.create", {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 17}],
		["server.stop", {"immediate": "false", "reason": "test"}], ["account.ban", {"user_id": "user", "hours": -1, "reason": "test"}],
		["account.get", {"user_id": ""}], ["account.delete", {"user_id": "user", "reason": "test"}], ["account.delete", {"user_id": "user", "confirm_username": "../x", "reason": "test"}], ["logs.read", {"label": "../../data/accounts.sqlite"}],
		["setup.create", {"username": "test", "password": "short"}], ["invite.create", {"uses": 1001, "expires_hours": 24, "reason": "test"}],
		["backup.restore", {"backup_id": "../data/accounts.sqlite", "reason": "test"}], ["player.kick", {"user_id": "user", "reason": "\n"}],
		["asset.adjust", {"user_id": "user", "game_id": "shooter", "coins_delta": 1000001, "xp_delta": 0, "reason": "test", "operation_id": "test"}],
		["config.set", {"config": {"lobby_bind": "0.0.0.0", "advertised_host": "127.0.0.1", "lobby_port": 28300, "max_rooms": 17, "asset_spaces": {"shooter": "shooter", "turns": "turns"}}, "reason": "test"}],
		["config.set", {"config": {"lobby_bind": "0.0.0.0", "advertised_host": "127.0.0.1", "lobby_port": 28300, "max_rooms": 16, "asset_spaces": {"shooter": "../turns", "turns": "turns"}}, "reason": "test"}]
	]:
		start_count = received.size()
		result = await fetch(post(invalid[0], invalid[1], "fixture-session"))
		check(status(result) == 400 and received.size() == start_count, "missing field type numeric path or scope constraint rejected: " + invalid[0])
	var rejected := [
		["GET / HTTP/1.1\r\nHost: evil.invalid\r\n\r\n", 403, "foreign Host"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nOrigin: https://evil.invalid\r\nContent-Length: 2\r\nContent-Type: application/json\r\n\r\n{}" % authority(), 403, "cross origin"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nOrigin: null\r\nContent-Length: 2\r\nContent-Type: application/json\r\n\r\n{}" % authority(), 403, "opaque Origin"],
		["GET / HTTP/1.1\r\nHost: %s\r\nhost: %s\r\n\r\n" % [authority(), authority()], 400, "duplicate case insensitive headers"],
		["GET / HTTP/1.1\r\nHost : %s\r\n\r\n" % authority(), 400, "space before header colon"],
		["GET / HTTP/1.1\r\nHost: %s\r\n folded: value\r\n\r\n" % authority(), 400, "folded header"],
		["GET / HTTP/1.1\r\nHost: %s\r\nX-Test: bad\nvalue\r\n\r\n" % authority(), 400, "bare LF header"],
		["GET / HTTP/1.1\r\nHost: %s\r\nTransfer-Encoding: chunked\r\n\r\n" % authority(), 400, "transfer encoding"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nContent-Length: +2\r\n\r\n{}" % authority(), 400, "signed length"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nContent-Length: 1e2\r\n\r\n{}" % authority(), 400, "exponential length"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nContent-Length: 17000\r\n\r\n" % authority(), 413, "oversized declared body"],
		["GET / HTTP/1.1\r\nHost: %s\r\nContent-Length: 2\r\n\r\n{}" % authority(), 400, "GET body"],
		["POST /api HTTP/1.1\r\nHost: %s\r\n\r\n" % authority(), 400, "POST missing length"],
		["POST /api HTTP/1.1\r\nHost: %s\r\nContent-Length: 2\r\nContent-Type: text/plain\r\n\r\n{}" % authority(), 415, "simple cross site content type"],
		["OPTIONS /api HTTP/1.1\r\nHost: %s\r\n\r\n" % authority(), 405, "preflight method"],
		["GET /../data/results.sqlite HTTP/1.1\r\nHost: %s\r\n\r\n" % authority(), 404, "path traversal"],
		["GET /api HTTP/1.1\r\nHost: %s\r\n\r\n" % authority(), 404, "API only accepts POST"],
		["GET / HTTP/1.0\r\nHost: %s\r\n\r\n" % authority(), 400, "unsupported HTTP version"]
	]
	for entry in rejected:
		start_count = received.size()
		result = await fetch(entry[0])
		check(status(result) == entry[1] and received.size() == start_count, "rejects " + entry[2] + " before dispatch")
	for body in ["{}", "[]", '{"action":"server.start","payload":{},"token":"forged"}', '{"action":"shell.exec","payload":{}}', '{"action":"status","action":"server.start","payload":{}}', '{"action":"status","\\u0061ction":"server.start","payload":{}}', '{"action":"status","payload":{"nested":{"value":1,"value":2}}}', '{"action":"status","payload":{"value":1e999}}']:
		start_count = received.size()
		result = await fetch(raw_post(body))
		check(status(result) == 400 and received.size() == start_count, "strict JSON and action envelope refused before dispatch")
	start_count = received.size()
	result = await fetch(post("server.start", {}, "fixture-session") + post("server.stop", {}, "fixture-session"))
	check(status(result) == 400 and received.size() == start_count, "coalesced HTTP pipeline rejected before first mutation dispatch")
	result = await fetch(post("status", {}, "fixture-session").replace("Bearer fixture-session", "Basic fixture-session"))
	check(status(result) == 401, "non-Bearer authorization rejected")
	result = await fetch("GET / HTTP/1.1\r\nHost: " + authority() + "\r\nX-Large: " + "x".repeat(8200))
	check(status(result) == 431, "unterminated header bounded without reading unlimited bytes")
	fixture_mode = "large"
	result = await fetch(post("logs.read", {"label": "operator"}, "fixture-session"))
	var response_text := result.get_string_from_utf8()
	check(status(result) == 200 and response_text.contains("END_OF_LARGE_RESPONSE"), "large response arrives completely using bounded send chunks")
	fixture_mode = "pending"
	var delayed := await open_peer()
	delayed.put_data(post("logs.read", {"label": "operator"}, "fixture-session").to_utf8_buffer())
	await frames(4)
	var pending_id := ""
	for connection in server.peers:
		if connection.phase == "pending":
			pending_id = connection.request_id
	check(not pending_id.is_empty(), "asynchronous request remains pending without duplicate dispatch")
	server.respond(pending_id, {"ok": true, "payload": {"confirmed": true}})
	result = await receive(delayed)
	check(status(result) == 200 and result.get_string_from_utf8().contains("confirmed"), "async response correlates to original HTTP request")
	server.respond(pending_id, {"ok": true})
	check(server.peers.is_empty(), "late duplicate response does not recreate connection")
	delayed = await open_peer()
	delayed.put_data(post("logs.read", {"label": "operator"}, "fixture-session").to_utf8_buffer())
	await frames(4)
	for connection in server.peers:
		if connection.phase == "pending":
			connection.started = Time.get_ticks_msec() - HTTP.REQUEST_TIMEOUT_MS - 1
	result = await receive(delayed)
	check(status(result) == 504, "pending business response deadline enforced with advanced test timestamp")
	fixture_mode = "oversized"
	result = await fetch(post("logs.read", {"label": "operator"}, "fixture-session"))
	check(status(result) == 500 and result.get_string_from_utf8().contains("RESPONSE_TOO_LARGE"), "oversized backend response refused within output bound")
	var invalid_utf8 := "POST /api HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\nContent-Length: 3\r\n\r\n" % authority()
	result = await fetch_bytes([invalid_utf8.to_utf8_buffer() + PackedByteArray([123, 255, 125])])
	check(status(result) == 400, "invalid UTF8 rejected before JSON dispatch")
	var stalled := await open_peer()
	stalled.put_data("GET / HT".to_utf8_buffer())
	await frames(4)
	for connection in server.peers:
		connection.started = Time.get_ticks_msec() - HTTP.READ_TIMEOUT_MS - 1
	result = await receive(stalled)
	check(status(result) == 408, "stalled read deadline enforced on actual TCP connection with advanced test timestamp")
	var pool: Array[StreamPeerTCP] = []
	for index in range(HTTP.MAX_CLIENTS + 2):
		pool.append(await open_peer())
	await frames(4)
	check(server.peers.size() == HTTP.MAX_CLIENTS, "client pool bounded at sixteen")
	server.close()
	await frames(2)
	check(server.peers.is_empty() and not server.listener.is_listening(), "close clears peers and listener")
	for peer in pool:
		peer.disconnect_from_host()
	print("ADMIN_HTTP_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _request(id: String, request: Dictionary) -> void:
	received.append(request.duplicate(true))
	if request.action == "setup.status":
		server.respond(id, {"ok": true, "payload": {"initialized": true}})
	elif request.token != "fixture-session":
		server.respond(id, {"ok": false, "code": "AUTH_REQUIRED"}, 401)
	elif request.action == "logs.read" and fixture_mode == "pending":
		return
	elif request.action == "logs.read" and fixture_mode == "large":
		server.respond(id, {"ok": true, "payload": {"text": "中".repeat(90000) + "END_OF_LARGE_RESPONSE"}})
	elif request.action == "logs.read" and fixture_mode == "oversized":
		server.respond(id, {"ok": true, "payload": {"text": "x".repeat(HTTP.MAX_RESPONSE + 1)}})
	else:
		server.respond(id, {"ok": true, "payload": {"accepted": request.action}})

func authority() -> String:
	return "127.0.0.1:" + str(server.port)

func action_payloads() -> Dictionary:
	var values := {}
	for action in ["setup.status", "admin.logout", "status", "server.start", "invite.list", "backup.list", "logs.list", "config.get"]:
		values[action] = {}
	for action in ["setup.create", "admin.login"]:
		values[action] = {"username": "test_admin", "password": "fixture-only-password"}
	for action in ["server.stop", "server.restart"]:
		values[action] = {"immediate": false, "restart": action == "server.restart", "reason": "HTTP fixture"}
	values["maintenance.set"] = {"enabled": true, "message": "Maintenance fixture"}
	values["room.create"] = {"game_id": "shooter", "mode": "ffa", "map": "depot", "capacity": 8}
	for action in ["room.stop", "room.recreate"]:
		values[action] = {"room_id": "room_test", "reason": "HTTP fixture"}
	values["room.joinable"] = {"room_id": "room_test", "joinable": false, "reason": "HTTP fixture"}
	for action in ["player.kick", "account.unban"]:
		values[action] = {"user_id": "user_test", "reason": "HTTP fixture"}
	values["account.list"] = {"query": "test", "offset": 0, "limit": 50}
	values["account.get"] = {"user_id": "user_test"}
	values["account.reset_password"] = {"user_id": "user_test", "password": "fixture-new-password", "reason": "HTTP fixture"}
	values["account.ban"] = {"user_id": "user_test", "hours": 24, "reason": "HTTP fixture"}
	values["account.delete"] = {"user_id": "user_test", "confirm_username": "user_test", "reason": "HTTP fixture"}
	values["account.rename"] = {"user_id": "user_test", "display_name": "测试玩家", "reason": "HTTP fixture"}
	values["invite.create"] = {"uses": 5, "expires_hours": 168, "reason": "HTTP fixture"}
	values["invite.revoke"] = {"invite_id": "invite_test", "reason": "HTTP fixture"}
	values["asset.read"] = {"user_id": "user_test", "game_id": "shooter"}
	values["asset.adjust"] = {"user_id": "user_test", "game_id": "shooter", "coins_delta": 100, "xp_delta": 0, "reason": "HTTP fixture", "operation_id": "test-adjust"}
	for action in ["asset.grant", "asset.revoke"]:
		values[action] = {"user_id": "user_test", "game_id": "shooter", "item_id": "smg", "reason": "HTTP fixture", "operation_id": "test-item"}
	values["asset.select"] = {"user_id": "user_test", "game_id": "shooter", "slot": "primary", "item_id": "rifle", "reason": "HTTP fixture", "operation_id": "test-select"}
	values["backup.create"] = {"reason": "HTTP fixture"}
	values["backup.restore"] = {"backup_id": "backup-20260922000000000-12345678", "reason": "HTTP fixture"}
	values["logs.read"] = {"label": "operator"}
	values["audit.list"] = {"limit": 100}
	values["config.set"] = {"config": {"lobby_bind": "0.0.0.0", "advertised_host": "127.0.0.1", "lobby_port": 28300, "max_rooms": 16, "asset_spaces": {"shooter": "shooter", "turns": "shared"}}, "reason": "HTTP fixture"}
	return values

func post(action: String, payload: Dictionary, token: String = "") -> String:
	return raw_post(JSON.stringify({"action": action, "payload": payload}), token)

func raw_post(body: String, token: String = "") -> String:
	return "POST /api HTTP/1.1\r\nHost: %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%s\r\n%s" % [authority(), body.to_utf8_buffer().size(), "Authorization: Bearer " + token + "\r\n" if not token.is_empty() else "", body]

func fetch(request: String) -> PackedByteArray:
	return await fetch_bytes([request.to_utf8_buffer()])

func fetch_bytes(chunks: Array) -> PackedByteArray:
	var peer := await open_peer()
	for chunk in chunks:
		if peer.put_data(chunk) != OK:
			return PackedByteArray()
		await frames(2)
	return await receive(peer)

func open_peer() -> StreamPeerTCP:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", server.port)
	for index in range(200):
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await process_frame
	return peer

func receive(peer: StreamPeerTCP) -> PackedByteArray:
	var result := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := peer.get_available_bytes()
		if available > 0:
			var part := peer.get_data(available)
			if part[0] == OK:
				result.append_array(part[1])
		await process_frame
	peer.disconnect_from_host()
	return result

func frames(count: int) -> void:
	for index in range(count):
		await process_frame

func status(response: PackedByteArray) -> int:
	var pieces := response.get_string_from_utf8().split(" ", true, 2)
	return int(pieces[1]) if pieces.size() > 1 else 0

func check(condition: bool, label: String) -> bool:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
	return condition
