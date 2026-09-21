extends "res://host/lobby_server.gd"
var bus
var maintenance := false
var announcement := ""
var shutdown_deadline := -1
var asset_jobs: Dictionary = {}
var permits: Dictionary = {}
var account_tokens: Dictionary = {}
var joining: Dictionary = {}

func begin_shutdown(deadline: int) -> void:
	shutdown_deadline = mini(shutdown_deadline, deadline) if shutdown_deadline >= 0 else deadline
	maintenance = true

func is_draining() -> bool:
	return maintenance or shutdown_deadline >= 0

func notice_message() -> String:
	if shutdown_deadline >= 0:
		var seconds := maxi(0, int(ceil(float(shutdown_deadline - Time.get_ticks_msec()) / 1000.0)))
		return "服务器将在 %d 秒后停止，请保存操作。" % seconds
	return announcement

func configure(local_bus, bind_address: String, advertised_address: String) -> void:
	bus = local_bus
	listen_address = bind_address
	admissions.advertised_host = advertised_address
	request_schema = "res://schemas/managed_lobby_request.schema.json"
	authentication_timeout_ms = 120000
	max_owned_rooms = 1
	# start() requires a provider for TLS; managed login authenticates remotely instead.
	identity_provider = preload("res://host/core/identity_provider.gd").new()

func handle_async(connection: Dictionary, message: Dictionary) -> Dictionary:
	if connection.get("revoked", false):
		return Wire.failure("AUTH_FAILED")
	var payload: Dictionary = message.payload.duplicate(true)
	if str(message.type).begins_with("account."):
		if connection.get("account_busy", false):
			return Wire.failure("RATE_LIMITED")
		if message.type not in ["account.register", "account.login"] and connection.user.is_empty():
			return Wire.failure("AUTH_REQUIRED")
		if message.type in ["account.register", "account.login"] and not connection.user.is_empty():
			return Wire.failure("ALREADY_CONNECTED")
		connection.account_busy = true
		payload.op = "session.logout" if message.type == "account.logout" else message.type
		if message.type not in ["account.register", "account.login"]:
			payload.token = connection.get("account_token", "")
		if message.type in ["account.register", "account.login", "account.change_password"]:
			payload.client_ip = connection.tcp.get_connected_host()
		var result: Dictionary = await bus.request("account.execute", payload)
		connection.account_busy = false
		if not peers.has(connection):
			if result.ok and message.type == "account.login":
				bus.request.call_deferred("account.execute", {"op": "session.logout", "token": result.token})
			return Wire.failure("CONTROL_UNAVAILABLE")
		if result.ok and message.type == "account.login":
			if result.identity.role != "player":
				await bus.request("account.execute", {"op": "session.logout", "token": result.token})
				return Wire.failure("AUTH_FAILED")
			connection.user = result.identity
			connection.expires = result.expires
			connection.account_token = result.token
			account_tokens[connection.user.user_id] = result.token
		if result.ok and message.type in ["account.logout", "account.change_password"]:
			connection.revoked = true
			_finish_session.call_deferred(connection)
		if result.ok and message.type == "account.rename":
			connection.user.display_name = payload.display_name
		return {"ok": result.ok, "code": result.get("code", ""), "payload": result.duplicate(true) if result.ok else {}}
	if connection.user.is_empty():
		return Wire.failure("AUTH_REQUIRED")
	if message.type == "session.create":
		return Wire.failure("AUTH_FAILED")
	if message.type == "server.notice":
		return {"ok": true, "payload": {"maintenance": is_draining(), "message": notice_message()}}
	if message.type == "game.catalog":
		return await bus.request("game.catalog", {})
	if str(message.type).begins_with("asset."):
		return await _asset_request(connection, message)
	if is_draining() and message.type in ["room.create", "room.reserve"]:
		return Wire.failure("ROOM_DRAINING")
	if asset_jobs.has(connection.user.user_id) and message.type in ["room.create", "room.reserve"]:
		return Wire.failure("RATE_LIMITED")
	if message.type == "room.reserve" and not manager.rooms.get(payload.room_id, {}).get("joinable", true):
		return Wire.failure("ROOM_DRAINING")
	return handle(connection, message)

func _finish_session(connection: Dictionary) -> void:
	# Queue the successful reply before the WS close; reject further commands immediately.
	await Engine.get_main_loop().create_timer(0.2).timeout
	if peers.has(connection):
		kick(connection.user.get("user_id", ""), "session_changed")

func _seat(user_id: String) -> Dictionary:
	for seat in admissions.seats.values():
		if seat.user_id == user_id:
			return seat.duplicate(true)
	return {}

func _asset_request(connection: Dictionary, message: Dictionary) -> Dictionary:
	var user_id: String = connection.user.user_id
	if asset_jobs.has(user_id):
		return Wire.failure("RATE_LIMITED")
	var operation_id := Wire.uid()
	asset_jobs[user_id] = operation_id
	var seat := _seat(user_id)
	var context := {"location": "lobby"}
	var valid := true
	if not seat.is_empty():
		valid = seat.state == "CONNECTED" and seat.game_id == message.payload.game_id
		if valid:
			permits[operation_id] = {"room_id": seat.room_id, "launch_id": seat.launch_id, "attempt_id": seat.attempt_id, "user_id": user_id}
			manager.send_control(seat.room_id, "asset.begin", {"operation_id": operation_id, "attempt_id": seat.attempt_id, "user_id": user_id})
			var deadline := Time.get_ticks_msec() + 5000
			while permits.has(operation_id) and not permits[operation_id].has("answer") and Time.get_ticks_msec() < deadline:
				await Engine.get_main_loop().process_frame
			var permit: Dictionary = permits.get(operation_id, {}).get("answer", {})
			valid = permit.get("ok", false) and _seat(user_id).get("attempt_id", "") == seat.attempt_id
			context = permit.get("context", {})
	var result: Dictionary = Wire.failure("ASSET_OPERATION_DENIED")
	if valid and peers.has(connection):
		result = await bus.request("asset.player", {"identity": connection.user.duplicate(true), "token": connection.account_token, "game_id": message.payload.game_id, "action": message.type, "command": message.payload.duplicate(true), "context": context})
	if not seat.is_empty():
		manager.send_control(seat.room_id, "asset.finish", {"operation_id": operation_id, "user_id": user_id, "ok": result.ok, "state": result.get("payload", {}).get("state", {}) if result.ok else {}})
	permits.erase(operation_id)
	asset_jobs.erase(user_id)
	return result

func _control(row: Dictionary, message: Dictionary) -> bool:
	var payload: Dictionary = message.payload
	if message.type == "admission.consume" and not _admission_open(row):
		# Match the presented ticket before freeing its pending seat. Other users and
		# already connected members must survive a rejected admission attempt.
		var seat: Dictionary = admissions.seats.get(str(payload.ticket).sha256_text(), {})
		if seat.get("room_id", "") == row.room_id and seat.get("launch_id", "") == row.launch_id and seat.get("user_id", "") == payload.user_id and seat.get("state", "") in ["RESERVED", "ADMITTING"]:
			admissions.leave(row.room_id, seat.user_id, seat.attempt_id)
		manager.send_control(row.room_id, "admission.result", {"attempt_id": payload.attempt_id, "ok": false, "user_id": "", "display_name": "", "code": "ROOM_DRAINING"})
		return true
	if message.type == "asset.permit":
		var pending: Dictionary = permits.get(payload.operation_id, {})
		if not pending.is_empty() and pending.room_id == row.room_id and pending.launch_id == row.launch_id and pending.attempt_id == payload.attempt_id and pending.user_id == payload.user_id:
			permits[payload.operation_id].answer = payload.duplicate(true)
		return true
	if message.type == "asset.refresh":
		_refresh.call_deferred(row.duplicate(true), payload.duplicate(true))
		return true
	if message.type == "member.joined":
		var key: String = payload.attempt_id
		if not joining.has(key):
			joining[key] = true
			_admit_with_assets.call_deferred(row.duplicate(true), payload.duplicate(true))
		return true
	return super._control(row, message)

func _admission_open(row: Dictionary) -> bool:
	var current: Dictionary = manager.rooms.get(row.room_id, {})
	return not is_draining() and current.get("state", "") == "READY" and current.get("launch_id", "") == row.launch_id and current.get("joinable", true)

func _admit_with_assets(row: Dictionary, payload: Dictionary) -> void:
	var seat := _seat(payload.user_id)
	var result: Dictionary = Wire.failure("AUTH_FAILED")
	if _admission_open(row) and seat.get("attempt_id", "") == payload.attempt_id and seat.get("room_id", "") == row.room_id and seat.get("launch_id", "") == row.launch_id:
		result = await bus.request("asset.initial", {"user_id": payload.user_id, "game_id": row.game_id})
	# Asset loading crosses an await: stop/maintenance/joinability can change while
	# the account worker replies. Recheck the live launch and gate before CONNECTED.
	var valid: bool = result.ok and _admission_open(row) and admissions.joined(row.room_id, payload.user_id, payload.attempt_id, Time.get_ticks_msec())
	if valid:
		manager.send_control(row.room_id, "asset.initial", {"user_id": payload.user_id, "attempt_id": payload.attempt_id, "state": result.payload.state})
	else:
		var pending := _seat(payload.user_id)
		if pending.get("state", "") == "ADMITTING":
			admissions.leave(row.room_id, payload.user_id, payload.attempt_id)
	manager.send_control(row.room_id, "member.accepted", {"attempt_id": payload.attempt_id, "ok": valid})
	joining.erase(payload.attempt_id)

func _refresh(row: Dictionary, payload: Dictionary) -> void:
	var seat := _seat(payload.user_id)
	var result: Dictionary = Wire.failure("AUTH_FAILED")
	if seat.get("attempt_id", "") == payload.attempt_id and seat.room_id == row.room_id and seat.state == "CONNECTED":
		result = await bus.request("asset.initial", {"user_id": payload.user_id, "game_id": row.game_id})
	manager.send_control(row.room_id, "asset.finish", {"operation_id": payload.operation_id, "user_id": payload.user_id, "ok": result.ok, "state": result.get("payload", {}).get("state", {}) if result.ok else {}})

func kick(user_id: String, reason: String) -> void:
	for seat in admissions.seats.values().duplicate(true):
		if seat.user_id == user_id:
			manager.send_control(seat.room_id, "admission.revoke", {"attempt_id": seat.attempt_id})
			admissions.leave(seat.room_id, user_id, seat.attempt_id)
	for connection in peers.duplicate():
		if connection.user.get("user_id", "") == user_id:
			connection.ws.close(1008, reason.left(60))
			_drop(connection)

func _drop(connection: Dictionary) -> void:
	var user_id: String = connection.user.get("user_id", "")
	if user_id != "":
		for seat in admissions.seats.values().duplicate(true):
			if seat.user_id == user_id:
				manager.send_control(seat.room_id, "admission.revoke", {"attempt_id": seat.attempt_id})
				admissions.leave(seat.room_id, user_id, seat.attempt_id)
		var token: String = account_tokens.get(user_id, "")
		account_tokens.erase(user_id)
		if token != "" and bus != null and bus.ready():
			bus.request.call_deferred("account.execute", {"op": "session.logout", "token": token})
	super._drop(connection)
