extends SceneTree
## Example composition shell: accounts and inventory are generic, worlds are optional.
const AccountClient = preload("res://sdk/roomkit/client/account_client.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const View = preload("view.gd")
const Sound = preload("sound.gd")
const ClientData = preload("client_data.gd")
const PlayerReport = preload("res://sdk/roomkit/shared/player_report.gd")
var client
var sound
var local_data
var pending_warning := ""
var _diagnostic_sample_at_ms := -1000
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
var report_busy := false
var report_message := "打开本机邮件草稿后由你确认发送；离线也可复制诊断摘要"
var report_email := ""

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
	# Source/test storage is explicitly project-local; exports are fixed beside Client.exe.
	var source := "res://examples/shooter/" if game_id == "shooter" else "res://examples/turn_based/"
	var manifest_path := "res://game_manifest.json" if FileAccess.file_exists("res://game_manifest.json") else source + "game_manifest.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	local_data = ClientData.new()
	var data_root: String = ClientData.default_root(str(args.get("--client-data", "res://data/client-local/source")))
	local_data.configure(data_root, str(parsed.get("build_id", "unknown")) if parsed is Dictionary else "unknown")
	client = AccountClient.new()
	root.add_child(client)
	sound = Sound.new()
	sound.name = "Sound"
	sound.settings_loader = local_data.load_settings
	sound.settings_writer = local_data.queue_settings
	root.add_child(sound)
	view = View.new()
	view.app = self
	root.add_child(view)
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
	# Optional external public contact, separate from the SDK/session credentials.
	if PlayerReport.valid_email(connection.get("report_email")):
		report_email = str(connection.report_email)
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
		await _close()
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
	account_error = str(result.get("code", ""))
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
	if busy or selected_room == "" or client.state != "LOBBY" or maintenance or not pending_asset.is_empty() or pending_warning != "":
		return
	busy = true
	inventory_open = false
	account_open = false
	_reset_world_network_state()
	var result: Dictionary = await client.join_room(selected_room)
	if result.ok:
		current_room = selected_room
		message = "已进入房间"
	else:
		_reset_world_network_state()
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
	_reset_world_network_state()
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
	if busy or not inventory_allowed() or not pending_asset.is_empty() or pending_warning != "":
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
	if busy or not pending_asset.is_empty() or pending_warning != "" or world == null or not world.has_method("send_respawn") or client.state != "IN_ROOM":
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
	pending_warning = ""
	current_room = ""
	_reset_world_network_state()

func _reset_world_network_state() -> void:
	if world == null:
		return
	if world.has_method("reset_network_state"):
		world.reset_network_state()
	else:
		world.latest.clear()

func _pending_server() -> String:
	return str(client.config.get("url", "")) if client != null else ""

func _load_pending() -> void:
	pending_asset.clear()
	pending_warning = ""
	if local_data == null:
		return
	var result: Dictionary = local_data.load_pending(_pending_server(), str(client.identity.get("user_id", "")), game_id)
	pending_asset = result.get("operation", {})
	pending_warning = str(result.get("warning", ""))
	if pending_warning == "LEGACY_UNBOUND":
		message = "发现旧版待确认操作，尚不能确认属于哪个服务器。请打开背包核对并迁入；原文件已保留。"
	elif pending_warning == "LEGACY_MIGRATION_INCOMPLETE":
		message = "上次旧操作迁入尚未完成，原文件已保留；请打开背包重试同一服务器归属"
	elif pending_warning != "":
		message = "待确认操作读取失败，原文件保留；请检查客户端数据目录后重试"
	elif not pending_asset.is_empty():
		message = "发现尚未确认的资产操作，请打开背包查询原操作"

func bind_legacy_pending() -> void:
	if busy or not authenticated or local_data == null or pending_warning not in ["LEGACY_UNBOUND", "LEGACY_MIGRATION_INCOMPLETE"]:
		return
	if local_data.bind_legacy(_pending_server(), str(client.identity.get("user_id", "")), game_id):
		_load_pending()
		message = "旧操作已迁入，编号保持不变；需要你另行点击查询 / 重试"
	else:
		message = "旧操作未迁入，原文件保留；请检查数据目录写入权限"

func _save_pending() -> bool:
	if local_data == null or not local_data.save_pending(_pending_server(), str(client.identity.get("user_id", "")), game_id, pending_asset):
		message = "无法保存操作回执，请检查客户端数据目录写入权限；原回执未删除"
		return false
	return true

## The SDK owns destructive ENet counter collection. UI and JSONL only copy its cache.
func diagnostic_metrics() -> Dictionary:
	var metrics: Dictionary = client.diagnostics_snapshot() if client != null else {}
	# Managed account preflight can fail before RoomClient._request is reached.
	if account_error != "" and not authenticated and client != null:
		metrics.error = client.diagnostic_error_category(account_error)
	metrics.fps = Engine.get_frames_per_second()
	metrics.frame_max_ms = view.worst_frame_ms() if view != null else -1.0
	var updates: Dictionary = world.snapshot_diagnostics() if client != null and client.state == "IN_ROOM" and world != null and world.has_method("snapshot_diagnostics") else {}
	metrics.snapshot_interval_ms = float(updates.get("interval_ms", -1))
	metrics.snapshot_age_ms = float(updates.get("age_ms", -1))
	return metrics

func mark_stall() -> void:
	if local_data == null:
		message = "诊断采集未启动，无法标记"
		return
	var previous_marks: int = local_data.status().get("memory_marks", 0)
	if local_data.mark():
		message = "已在本次脱敏报告中标记刚才卡顿"
	elif int(local_data.status().get("memory_marks", 0)) > previous_marks:
		message = "已保留内存卡顿标记；当前磁盘日志未写入，可继续游戏"
	else:
		message = "未新增标记：请间隔一秒再点，或检查诊断采集是否已关闭"

func submit_diagnostic_report() -> void:
	if report_busy or local_data == null:
		return
	var report: Dictionary = local_data.diagnostic_report()
	if report.is_empty():
		report_message = "近期没有可整理的诊断记录，请稍后再试"
		return
	if not PlayerReport.valid_email(report_email):
		report_message = "未配置有效收件地址；可复制诊断摘要，或从本地报告目录手动分享"
		return
	var uri := PlayerReport.mailto(report, report_email)
	if uri.is_empty():
		report_message = "邮件草稿太长；请复制诊断摘要和收件地址，在邮件应用中粘贴发送"
		return
	report_busy = true
	var result: int = _open_mail_draft(uri)
	report_busy = false
	report_message = "已请求打开本机邮件草稿；请检查内容后自行点击发送" if result == OK else "无法打开邮件应用；请复制摘要和收件地址，在邮件应用或网页邮箱中粘贴发送"

func _open_mail_draft(uri: String) -> int:
	return OS.shell_open(uri)

func _copy_report_text(text: String) -> bool:
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get() == text

func copy_diagnostic_report() -> void:
	if local_data == null:
		report_message = "诊断采集未启动"
		return
	var report: Dictionary = local_data.diagnostic_report()
	var text := PlayerReport.summary(report)
	if text.is_empty():
		report_message = "近期没有可复制的诊断记录，请稍后再试"
		return
	report_message = "诊断摘要已复制；可粘贴到邮件中，检查后自行发送" if _copy_report_text(text) else "无法复制摘要；请打开本地报告目录，手动选择 JSONL 附件"

func copy_report_recipient() -> void:
	if not PlayerReport.valid_email(report_email):
		report_message = "未配置有效收件地址，请向服主索取联系方式"
		return
	report_message = "收件地址已复制；请自行打开邮件应用发送" if _copy_report_text(report_email) else "无法复制收件地址，请向服主索取联系方式"

func open_report_directory() -> void:
	if local_data == null or local_data.report_directory() == "":
		message = "报告目录不可用，请检查客户端数据目录权限"
		return
	if OS.shell_open(local_data.report_directory()) != OK:
		message = "无法自动打开，请在 client-data/reports 中查看脱敏 JSONL；不要发送整个 client-data"

func local_data_message() -> String:
	if local_data == null:
		return "诊断日志未启动"
	var status: Dictionary = local_data.status()
	var result := "脱敏日志：每秒采样" if status.get("enabled", false) else "诊断日志已停记（权限、容量或写入失败）；游戏不受影响"
	if str(status.get("settings_error", "")) != "":
		result += "；音效设置未保存"
	if int(status.get("dropped", 0)) > 0:
		result += "；队列满时丢弃了 %d 条记录" % int(status.dropped)
	return result

func _finalize() -> void:
	if local_data != null:
		local_data.close()

func _process(delta: float) -> bool:
	if client == null or view == null or closing:
		_clear_aim_presentation()
		return false
	var diagnostic_now := Time.get_ticks_msec()
	if local_data != null and diagnostic_now - _diagnostic_sample_at_ms >= 1000:
		_diagnostic_sample_at_ms = diagnostic_now
		local_data.sample(diagnostic_metrics())
	if authenticated and not busy and client.socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		client.close()
		_reset_session()
		message = "连接已关闭或登录已失效，请重新登录；未确认操作已保留"
	if authenticated:
		poll_elapsed += delta
		if poll_elapsed >= 5 and not busy and not polling:
			poll_elapsed = 0
			_poll()
	_sync_aim_presentation()
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

func _clear_aim_presentation() -> void:
	if world != null and world.has_method("set_local_aim"):
		world.set_local_aim("", Vector2.ZERO, false)

func _sync_aim_presentation() -> void:
	if world == null or not world.has_method("set_local_aim"):
		return
	if client == null or view == null or closing or client.state != "IN_ROOM":
		_clear_aim_presentation()
		return
	var user: String = client.identity.get("user_id", "")
	var player: Dictionary = world.player_view(user)
	var pointer: Vector2 = view.get_local_mouse_position() - view.ARENA_POSITION
	# Keep the origin identical to the unchanged 30 Hz input calculation.
	var aim := pointer - Vector2(float(player.get("x", 480)), float(player.get("y", 270)))
	world.set_local_aim(user, aim, root.has_focus() and not inventory_open and not account_open and not busy)

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
	if local_data != null:
		local_data.close()
	quit(0)

func _logout_on_close() -> void:
	await client.logout()
	close_acknowledged = true

static func explain(code: String) -> String:
	var names := {"AUTH_FAILED": "账号、密码或会话无效", "AUTH_REQUIRED": "请先登录", "INVALID_OPTIONS": "输入格式不正确，请检查长度与内容", "INVALID_ACCOUNT_REQUEST": "账号输入格式不正确，请检查长度与内容", "ACCOUNT_EXISTS": "该用户名已经注册", "USERNAME_TAKEN": "该用户名已经注册", "INVITE_INVALID": "邀请码无效、已用完或已过期", "INVALID_INVITE": "邀请码无效、已用完或已过期", "ACCOUNT_BANNED": "账号已被封禁", "ALREADY_CONNECTED": "账号已有有效登录，请先退出原会话", "ALREADY_LOGGED_IN": "账号已有有效登录，请先退出原会话", "SESSION_EXISTS": "账号已有有效登录，请先退出原会话", "RATE_LIMITED": "操作过于频繁，请稍后重试", "CONTROL_UNAVAILABLE": "服务器连接中断或未启动", "STORAGE_MAINTENANCE": "服务器维护中，请稍后再试", "BUILD_MISMATCH": "客户端与服务器版本不匹配", "ROOM_NOT_READY": "房间仍在启动，请稍后进入", "ROOM_NOT_FOUND": "房间已关闭", "ROOM_FULL": "房间人数已满", "ROOM_DRAINING": "房间或服务器正在维护", "INSUFFICIENT_CREDITS": "金币不足", "ALREADY_OWNED": "你已拥有该物品", "ITEM_NOT_OWNED": "尚未解锁该物品", "ASSET_OPERATION_DENIED": "当前游戏阶段不允许操作背包", "ROOM_LIMIT_EXCEEDED": "房间数量已达上限", "OWNED_ROOM_LIMIT": "每个账号最多拥有一个活动房间", "INVALID_ASSET_STATE": "未收到有效的资产确认", "DISCONNECTED": "房间连接已断开", "": "连接已结束"}
	return str(names.get(code, code))
