extends SceneTree
## Example composition shell: accounts and inventory are generic, worlds are optional.
const AccountClient = preload("res://sdk/roomkit/client/account_client.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const View = preload("view.gd")
const Sound = preload("sound.gd")
var client
var sound
var last_purchase_sound := ""
var world
var view
var args: Dictionary = {}
var manifest: Dictionary = {}
var game_id := "shooter"
var busy := false
var polling := false
var closing := false
var inventory_open := false
var account_open := false
var authenticated := false
var configuration_ready := false
var message := "请输入账号和密码"
var notice := ""
var maintenance := false
var rooms: Array = []
var assets: Dictionary = {}
var catalog: Dictionary = {}
var asset_space := ""
var asset_level := 1
var pending_asset: Dictionary = {}
var poll_elapsed := 0.0
var input_elapsed := 0.0
var selected_room := ""
var current_room := ""
var last_life := ""
var client_started := 0
var close_acknowledged := false
var account_error := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	game_id = args.get("--game", "shooter")
	root.size = Vector2i(1240, 820)
	root.min_size = Vector2i(930, 615)
	root.content_scale_size = Vector2i(1240, 820)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "RoomKit · 玩家客户端"
	auto_accept_quit = false
	root.close_requested.connect(_close)
	client_started = Time.get_ticks_msec()
	_run.call_deferred()

func _run() -> void:
	client = AccountClient.new()
	root.add_child(client)
	sound = Sound.new()
	sound.name = "Sound"
	if args.has("--audio-settings"):
		sound.settings_path = str(args["--audio-settings"])
	root.add_child(sound)
	view = View.new()
	view.app = self
	root.add_child(view)
	var source := "res://examples/shooter/" if game_id == "shooter" else "res://examples/turn_based/"
	if game_id not in ["shooter", "turns"]:
		message = "此示例客户端仅包含射击和取石子，请检查启动配置"
		return
	var game_path := "res://game/game.gd" if ResourceLoader.exists("res://game/game.gd") else source + "game.gd"
	var game_script = load(game_path)
	if game_script == null or not game_script.can_instantiate():
		message = "无法加载游戏模块，请重新构建当前版本"
		return
	world = game_script.new()
	world.name = "GameWorld"
	root.add_child(world)
	if world.has_signal("presentation_cue"):
		world.presentation_cue.connect(_on_presentation_cue)
	root.title = "RoomKit · " + world.title()
	var manifest_path := "res://game_manifest.json" if FileAccess.file_exists("res://game_manifest.json") else source + "game_manifest.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or parsed.get("game_id", "") != game_id:
		message = "游戏清单缺失或与启动游戏不匹配"
		return
	manifest = parsed
	# An explicit --connection-config wins. Otherwise an exported Client.exe reads
	# connection.json beside itself (double-click start); source runs keep the
	# project's published res://artifacts/client/connection.json.
	var default_connection := OS.get_executable_path().get_base_dir().path_join("connection.json")
	if OS.has_feature("editor"):
		default_connection = Paths.absolute("res://artifacts/client/connection.json")
	var connection_path: String = args.get("--connection-config", default_connection)
	if not FileAccess.file_exists(connection_path):
		message = "未找到连接配置 connection.json（应与 Client.exe 在同一文件夹）。请向服务器主机索取完整客户端目录，或运行 SetServer.cmd 设置服务器。"
		return
	var connection: Variant = JSON.parse_string(FileAccess.get_file_as_string(connection_path))
	if not connection is Dictionary:
		message = "公共连接配置格式错误"
		return
	var settings := manifest.duplicate(true)
	for key in ["url", "ca_certificate", "server_hostname"]:
		if connection.has(key):
			settings[key] = connection[key]
	settings.managed = true
	settings.secure_enet = true
	if settings.has("ca_certificate") and not str(settings.ca_certificate).is_absolute_path() and not str(settings.ca_certificate).begins_with("res://"):
		settings.ca_certificate = connection_path.get_base_dir().path_join(settings.ca_certificate)
	if not client.configure(settings):
		message = "连接配置无效：需要 WSS 地址、可信证书与匹配的游戏版本"
		return
	configuration_ready = true
	client.room_joined.connect(_room_joined)
	client.room_left.connect(_room_left)
	client.join_progress.connect(func(phase): message = "房间连接中：" + phase)
	if args.get("--ui-smoke", "false") == "true":
		await create_timer(0.5).timeout
		await _capture_if_requested()
		print("FRAMEWORK_UI_RESULT login_ready=", configuration_ready)
		quit(0)
	elif args.has("--autoplay"):
		_autoplay(str(args["--autoplay"]))

## Test-only acceptance driver: runs the same login/room functions the buttons
## call, from a private JSON file, and writes a report without credentials.
func _autoplay(path: String) -> void:
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not plan is Dictionary or not plan.has("report_path"):
		push_error("autoplay plan invalid")
		quit(2)
		return
	var report := {"stage": "configured", "ok": false, "build_id": str(manifest.get("build_id", ""))}
	var deadline := Time.get_ticks_msec() + int(plan.get("timeout_ms", 90000))
	if plan.get("register", false):
		await register_account(str(plan.username), str(plan.password), str(plan.get("display_name", plan.username)), str(plan.get("invite_code", "")))
		report.register_message = message
	await login(str(plan.username), str(plan.password))
	report.login_message = message
	if not authenticated:
		report.stage = "login_failed"
		_autoplay_finish(plan, report, 3)
		return
	report.stage = "logged_in"
	selected_room = str(plan.get("room_id", ""))
	if selected_room == "":
		await create_room()
		report.created_room = selected_room
	while client.state == "LOBBY" and Time.get_ticks_msec() < deadline:
		await _refresh_rooms()
		var ready := rooms.any(func(room): return str(room.get("room_id", "")) == selected_room and str(room.get("state", "")) == "READY")
		if ready and not busy:
			await join_selected()
		if client.state != "IN_ROOM":
			await create_timer(0.5).timeout
	report.join_message = message
	if client.state != "IN_ROOM":
		report.stage = "join_failed"
		_autoplay_finish(plan, report, 4)
		return
	report.stage = "in_room"
	report.room_id = current_room
	var wanted := int(plan.get("expect_players", 1))
	while Time.get_ticks_msec() < deadline:
		var ids: Array = []
		for player in world.latest.get("players", []):
			ids.append(str(player.get("user_id", "")))
		report.players = ids
		report.self_visible = ids.has(str(client.identity.get("user_id", "")))
		if report.self_visible and ids.size() >= wanted:
			break
		await create_timer(0.2).timeout
	report.user_id = str(client.identity.get("user_id", ""))
	report.ok = report.get("self_visible", false) and report.players.size() >= wanted
	if report.ok:
		report.stage = "in_room_synced"
		await create_timer(float(plan.get("hold_ms", 0)) / 1000.0).timeout
		if str(plan.get("after", "close")) == "leave":
			await leave_room()
			report.left_state = str(client.state)
			report.leave_message = message
			report.stage = "left_room" if client.state == "LOBBY" else "leave_failed"
			report.ok = client.state == "LOBBY"
			await create_timer(float(plan.get("lobby_ms", 3000)) / 1000.0).timeout
	_autoplay_finish(plan, report, 0 if report.ok else 5)

func _autoplay_finish(plan: Dictionary, report: Dictionary, code: int) -> void:
	var file := FileAccess.open(str(plan.report_path), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
	print("FRAMEWORK_AUTOPLAY stage=", report.stage, " ok=", report.ok)
	await _close()
	if code != 0:
		quit(code)

func login(username: String, password: String) -> void:
	if busy or not configuration_ready:
		return
	busy = true
	message = "正在验证账号…"
	var result: Dictionary = await client.login(username.strip_edges(), password)
	account_error = str(result.get("code", ""))
	if result.ok:
		authenticated = true
		view.clear_passwords()
		message = "已登录，选择或创建一个房间"
		_load_pending()
		await _load_catalog()
		await _read_assets()
		await _refresh_rooms()
		await _read_notice()
	else:
		message = "登录失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func register_account(username: String, password: String, display_name: String, invite: String) -> void:
	if busy or not configuration_ready:
		return
	busy = true
	message = "正在使用邀请码注册…"
	var result: Dictionary = await client.register_account(username.strip_edges(), password, display_name.strip_edges(), invite.strip_edges())
	if result.ok:
		message = "注册成功，请使用刚才的账号密码登录"
		view.register_mode = false
		view.clear_passwords()
	else:
		message = "注册失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func refresh_lobby() -> void:
	if busy or polling or not authenticated:
		return
	busy = true
	await _refresh_rooms()
	await _read_notice()
	busy = false

func _refresh_rooms() -> void:
	var result: Dictionary = await client.list_rooms()
	if result.ok:
		rooms = result.payload.get("rooms", [])
	else:
		message = "房间列表暂不可用：" + explain(result.get("code", "UNKNOWN"))

func _load_catalog() -> void:
	var result: Dictionary = await client._request("game.catalog", {})
	if result.ok:
		var data: Variant = result.payload.get("catalog", result.payload)
		if data is Dictionary and data.has("games") and data.has("spaces"):
			catalog = data.duplicate(true)
			asset_space = str(catalog.games.get(game_id, {}).get("space", ""))

func _read_assets() -> bool:
	var result: Dictionary = await client.read_assets()
	if result.ok and _accept_assets(result.get("payload", {})):
		return true
	message = "资产读取失败：" + explain(result.get("code", "INVALID_ASSET_STATE"))
	return false

func _accept_assets(payload: Dictionary) -> bool:
	var state: Variant = payload.get("state", {})
	if Validator.validate_file(state, "res://schemas/asset_state.schema.json") != "":
		return false
	assets = state.duplicate(true)
	asset_level = int(payload.get("level", asset_level))
	return true

func _read_notice() -> void:
	var result: Dictionary = await client.notice()
	if result.ok:
		maintenance = bool(result.payload.get("maintenance", false))
		notice = str(result.payload.get("message", ""))
		if maintenance and notice == "":
			notice = "服务器维护中，暂不接受新入房"

func create_room() -> void:
	if busy or not authenticated or maintenance or client.state != "LOBBY":
		return
	busy = true
	var mode := str(manifest.modes.keys()[0])
	var options := {"mode": mode, "map": str(manifest.modes[mode].maps[0]), "capacity": mini(8, int(manifest.modes[mode].max_players))}
	message = "正在创建独立游戏房间…"
	var result: Dictionary = await client.create_room(options)
	if result.ok:
		selected_room = str(result.payload.get("room", {}).get("room_id", ""))
		message = "房间已创建，等待就绪后点击进入"
		await _refresh_rooms()
	else:
		message = "创建失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func join_selected() -> void:
	if busy or selected_room == "" or client.state != "LOBBY" or maintenance or not pending_asset.is_empty():
		return
	busy = true
	inventory_open = false
	account_open = false
	world.latest.clear()
	var result: Dictionary = await client.join_room(selected_room)
	if result.ok:
		current_room = selected_room
		message = "已进入房间"
	else:
		message = "入房失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func leave_room() -> void:
	if busy or client.state != "IN_ROOM":
		return
	busy = true
	inventory_open = false
	await client.leave_room()
	current_room = ""
	message = "已返回大厅，账号资产与默认配置已保留"
	await _refresh_rooms()
	await _read_assets()
	busy = false

func _room_joined(_snapshot: Dictionary) -> void:
	last_life = ""
	inventory_open = false

func _room_left() -> void:
	inventory_open = false
	current_room = ""
	last_life = ""
	message = "已离开房间：" + explain(client.last_error) if client.last_error != "" else "已返回大厅"

func inventory_allowed() -> bool:
	if not authenticated or client == null:
		return false
	if client.state == "LOBBY":
		return true
	return client.state == "IN_ROOM" and world != null and world.has_method("can_open_inventory") and world.can_open_inventory(client.identity.get("user_id", ""))

func toggle_inventory() -> void:
	if inventory_open:
		if not busy:
			inventory_open = false
		return
	if busy or not inventory_allowed():
		message = "当前阶段不能打开背包；射击示例需要先死亡或返回大厅"
		return
	busy = true
	account_open = false
	inventory_open = true
	if catalog.is_empty():
		await _load_catalog()
	await _read_assets()
	busy = false

func asset_action(kind: String, item_id: String, slot: String = "") -> void:
	if busy or not inventory_allowed() or not pending_asset.is_empty():
		return
	pending_asset = {"kind": kind, "item_id": item_id, "slot": slot, "operation_id": Wire.uid()}
	if not _save_pending():
		pending_asset.clear()
		return
	await retry_asset()

func retry_asset() -> void:
	if busy or pending_asset.is_empty() or not inventory_allowed():
		return
	busy = true
	message = "正在确认解锁与配置操作…"
	var operation := pending_asset.duplicate(true)
	var result: Dictionary
	if operation.kind == "purchase":
		result = await client.purchase(operation.item_id, operation.operation_id)
	else:
		result = await client.select_item(operation.slot, operation.item_id, operation.operation_id)
	if result.ok and _accept_assets(result.get("payload", {})):
		message = "解锁已保存；可以另行选择默认配置" if operation.kind == "purchase" else "默认配置已保存，下次出生或入房生效"
		if operation.kind == "purchase":
			_purchase_confirmed(str(operation.operation_id))
		pending_asset.clear()
		_save_pending()
	elif not result.ok and result.get("code", "") not in ["CONTROL_UNAVAILABLE", "STORAGE_UNAVAILABLE", "STORAGE_TIMEOUT", "TIMEOUT"]:
		message = "操作未完成：" + explain(result.get("code", "UNKNOWN"))
		pending_asset.clear()
		_save_pending()
		await _read_assets()
	else:
		message = "尚未确认保存结果。请恢复连接后点击“查询 / 重试原操作”，不会另起一次扣款。"
	busy = false

## Success sound only after the server confirmed this operation, once per id.
func _purchase_confirmed(operation_id: String) -> void:
	if sound != null and operation_id != last_purchase_sound:
		last_purchase_sound = operation_id
		sound.play("purchase")

func _on_presentation_cue(cue: String, detail: Dictionary) -> void:
	if sound == null or client == null or client.state != "IN_ROOM":
		return
	var own: bool = str(detail.get("user_id", "")) == str(client.identity.get("user_id", ""))
	# The local player's own damage and death play lower so they read as "taken".
	sound.play(cue, 0.75 if own and cue in ["hit", "death"] else 1.0)

func play_click() -> void:
	if sound != null:
		sound.play("click")

func respawn() -> void:
	if busy or not pending_asset.is_empty() or world == null or not world.has_method("send_respawn") or client.state != "IN_ROOM":
		return
	var player: Dictionary = world.player_view(client.identity.get("user_id", ""))
	if player.get("life_state", "") != "dead" or int(player.get("respawn_wait_ms", 1)) > 0 or player.get("asset_busy", false):
		return
	inventory_open = false
	world.send_respawn()
	message = "正在确认装备并复活…"

func choose(value: int) -> void:
	if not busy and client.state == "IN_ROOM" and world.has_method("choose"):
		world.choose(value)

func rename(display_name: String) -> void:
	if busy or not authenticated:
		return
	busy = true
	var result: Dictionary = await client.rename(display_name.strip_edges())
	if result.ok:
		client.identity.display_name = display_name.strip_edges()
		message = "昵称已保存，房间显示将在重新入房后更新"
	else:
		message = "修改失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func change_password(password: String, new_password: String) -> void:
	if busy or not authenticated:
		return
	busy = true
	var result: Dictionary = await client.change_password(password, new_password)
	view.clear_passwords()
	if result.ok:
		client.close()
		_reset_session()
		message = "密码已更新，请使用新密码登录"
	else:
		message = "修改密码失败：" + explain(result.get("code", "UNKNOWN"))
	busy = false

func logout() -> void:
	if busy or not authenticated:
		return
	busy = true
	await client.logout()
	_reset_session()
	message = "已退出登录"
	busy = false

func _reset_session() -> void:
	authenticated = false
	inventory_open = false
	account_open = false
	assets.clear()
	asset_level = 1
	rooms.clear()
	pending_asset.clear()
	current_room = ""
	if world != null:
		world.latest.clear()

func _pending_path() -> String:
	return Paths.absolute("res://data/client-operations/" + (str(client.identity.get("user_id", "")) + ":" + game_id).sha256_text() + ".json")

func _load_pending() -> void:
	pending_asset.clear()
	if not FileAccess.file_exists(_pending_path()):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_pending_path()))
	if data is Dictionary and data.get("kind", "") in ["purchase", "select"] and data.get("operation_id", "") is String and str(data.operation_id).length() == 32 and data.get("item_id", "") is String and data.get("slot", "") is String:
		pending_asset = data
		message = "发现尚未确认的资产操作，请打开背包查询原操作"

func _save_pending() -> bool:
	var path := _pending_path()
	if pending_asset.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		message = "无法保存操作回执，请检查客户端数据目录写入权限"
		return false
	file.store_string(JSON.stringify(pending_asset))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		message = "无法保存操作回执，请检查客户端数据目录写入权限"
		return false
	return true

func _process(delta: float) -> bool:
	if client == null or view == null or closing:
		return false
	if authenticated and not busy and client.socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		client.close()
		_reset_session()
		message = "连接已关闭或登录已失效，请重新登录；未确认操作已保留"
	if authenticated:
		poll_elapsed += delta
		if poll_elapsed >= 5 and not busy and not polling:
			poll_elapsed = 0
			_poll()
	if client.state == "IN_ROOM" and world != null:
		var own: String = client.identity.get("user_id", "")
		_sync_life_view()
		input_elapsed += delta
		if world.has_method("send_input") and input_elapsed >= 1.0 / 30.0:
			input_elapsed = 0
			var enabled: bool = root.has_focus() and not inventory_open and not account_open and not busy
			var axis := 0.0
			if enabled:
				axis = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
			var player: Dictionary = world.player_view(own)
			var pointer: Vector2 = view.get_local_mouse_position() - view.ARENA_POSITION
			var aim := pointer - Vector2(float(player.get("x", 480)), float(player.get("y", 270)))
			var fire: bool = enabled and Rect2(Vector2.ZERO, Vector2(960, 540)).has_point(pointer) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			world.send_input(axis, enabled and (Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_W)), aim, fire)
	if args.has("--close-after-ms") and Time.get_ticks_msec() - client_started >= int(args["--close-after-ms"]):
		_close()
	return false

func _sync_life_view() -> void:
	if client.state != "IN_ROOM" or world == null or not world.has_method("player_view"):
		return
	var life: String = world.player_view(client.identity.get("user_id", "")).get("life_state", "")
	if life != last_life:
		var previous_life := last_life
		last_life = life
		if life == "alive":
			inventory_open = false
			if previous_life == "dead":
				message = "已复活，可以继续战斗"
		if life == "dead":
			message = "你已阵亡，可以打开背包解锁或选枪"

func _poll() -> void:
	polling = true
	await _read_notice()
	if authenticated and client.state == "LOBBY" and not busy:
		await _refresh_rooms()
	polling = false

func _capture_if_requested() -> void:
	if args.has("--screenshot") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args["--screenshot"])

func _close() -> void:
	if closing:
		return
	closing = true
	if client != null:
		if authenticated and client.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_logout_on_close()
			var deadline := Time.get_ticks_msec() + 2500
			while not close_acknowledged and Time.get_ticks_msec() < deadline:
				await process_frame
		client.close()
	quit(0)

func _logout_on_close() -> void:
	await client.logout()
	close_acknowledged = true

static func explain(code: String) -> String:
	var names := {"AUTH_FAILED": "账号、密码或会话无效", "AUTH_REQUIRED": "请先登录", "INVALID_OPTIONS": "输入格式不正确，请检查长度与内容", "INVALID_ACCOUNT_REQUEST": "账号输入格式不正确，请检查长度与内容", "ACCOUNT_EXISTS": "该用户名已经注册", "USERNAME_TAKEN": "该用户名已经注册", "INVITE_INVALID": "邀请码无效、已用完或已过期", "INVALID_INVITE": "邀请码无效、已用完或已过期", "ACCOUNT_BANNED": "账号已被封禁", "ALREADY_CONNECTED": "账号已有有效登录，请先退出原会话", "ALREADY_LOGGED_IN": "账号已有有效登录，请先退出原会话", "SESSION_EXISTS": "账号已有有效登录，请先退出原会话", "RATE_LIMITED": "操作过于频繁，请稍后重试", "CONTROL_UNAVAILABLE": "服务器连接中断或未启动", "STORAGE_MAINTENANCE": "服务器维护中，请稍后再试", "BUILD_MISMATCH": "客户端与服务器版本不匹配", "ROOM_NOT_READY": "房间仍在启动，请稍后进入", "ROOM_NOT_FOUND": "房间已关闭", "ROOM_FULL": "房间人数已满", "ROOM_DRAINING": "房间或服务器正在维护", "INSUFFICIENT_CREDITS": "金币不足", "ALREADY_OWNED": "你已拥有该物品", "ITEM_NOT_OWNED": "尚未解锁该物品", "ASSET_OPERATION_DENIED": "当前游戏阶段不允许操作背包", "ROOM_LIMIT_EXCEEDED": "房间数量已达上限", "OWNED_ROOM_LIMIT": "每个账号最多拥有一个活动房间", "INVALID_ASSET_STATE": "未收到有效的资产确认", "DISCONNECTED": "房间连接已断开", "": "连接已结束"}
	return str(names.get(code, code))
