extends "res://sdk/roomkit/client/room_client.gd"
## Optional managed account/asset client; gameplay still uses RoomClient's ENet lifecycle.
var session_token := ""

func connect_lobby() -> Dictionary:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return {"ok": true, "payload": {}}
	if config.is_empty() or not config.get("managed", false):
		return Wire.failure("INVALID_OPTIONS")
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 65536
	socket.outbound_buffer_size = 65536
	socket.max_queued_packets = 32
	var tls := Secure.client_options(config.ca_certificate, config.get("server_hostname", ""))
	if tls == null or socket.connect_to_url(config.url, tls) != OK:
		return Wire.failure("CONTROL_UNAVAILABLE")
	state = "CONNECTING_LOBBY"
	var deadline := Time.get_ticks_msec() + 10000
	while socket.get_ready_state() not in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CLOSED] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		state = "CLOSED"
		return Wire.failure("CONTROL_UNAVAILABLE")
	state = "AUTHENTICATING_ACCOUNT"
	return {"ok": true, "payload": {}}

func register_account(username: String, password: String, display_name: String, invite_code: String) -> Dictionary:
	var connected: Dictionary = await connect_lobby()
	if not connected.ok:
		return connected
	return await _request("account.register", {"username": username, "password": password, "display_name": display_name, "invite_code": invite_code})

func login(username: String, password: String) -> Dictionary:
	var connected: Dictionary = await connect_lobby()
	if not connected.ok:
		return connected
	var result: Dictionary = await _request("account.login", {"username": username, "password": password})
	if result.ok:
		identity = result.payload.identity
		session_token = result.payload.get("token", "")
		state = "LOBBY"
		session_changed.emit(identity.duplicate(true))
	return result

func logout() -> Dictionary:
	if state == "IN_ROOM":
		await leave_room()
	var result: Dictionary = await _request("account.logout", {})
	session_token = ""
	close()
	return result

func change_password(password: String, new_password: String) -> Dictionary:
	return await _request("account.change_password", {"password": password, "new_password": new_password})

func rename(display_name: String) -> Dictionary:
	return await _request("account.rename", {"display_name": display_name})

func read_assets() -> Dictionary:
	return await _request("asset.read", {"game_id": config.game_id})

func purchase(item_id: String, operation_id: String = "") -> Dictionary:
	return await _request("asset.purchase", {"game_id": config.game_id, "item_id": item_id, "operation_id": Wire.uid() if operation_id == "" else operation_id})

func select_item(slot: String, item_id: String, operation_id: String = "") -> Dictionary:
	return await _request("asset.select", {"game_id": config.game_id, "slot": slot, "item_id": item_id, "operation_id": Wire.uid() if operation_id == "" else operation_id})

func notice() -> Dictionary:
	return await _request("server.notice", {})
