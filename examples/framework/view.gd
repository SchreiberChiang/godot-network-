extends Control
const ARENA_POSITION := Vector2(28, 164)
var app
var font := SystemFont.new()
var register_mode := false
var login_panel: Control
var lobby_panel: Control
var game_panel: Control
var inventory_panel: Control
var account_panel: Control
var room_list := ItemList.new()
var room_signature := ""
var inventory_signature := ""
var inventory_cards: Control
var login_title: Label
var register_fields: Control
var login_username: LineEdit
var login_password: LineEdit
var register_name: LineEdit
var register_invite: LineEdit
var login_button: Button
var toggle_auth: Button
var refresh_button: Button
var create_button: Button
var join_button: Button
var leave_button: Button
var stop_button: Button
var inventory_buttons: Array = []
var gameplay_buttons: Array = []
var retry_button: Button
var inventory_balance: Label
var inventory_info: Label
var slot_select: OptionButton
var slot_signature := ""
var account_name: LineEdit
var old_password: LineEdit
var new_password: LineEdit
var permanent_message: Label
var active_game: Label
var header_name: Label
var server_notice: Label
var game_status: Label
var scoreboard: Label
var help_text: Label
var own_notice: Label
var pending_label: Label
var asset_hint: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	var style := Theme.new()
	style.default_font = font
	style.default_font_size = 17
	style.set_color("font_color", "Label", Color("e3edf4"))
	style.set_color("font_color", "Button", Color("e7f1f5"))
	style.set_color("font_disabled_color", "Button", Color("647b8b"))
	style.set_stylebox("normal", "Button", _box(Color("233c50")))
	style.set_stylebox("hover", "Button", _box(Color("31536b")))
	style.set_stylebox("pressed", "Button", _box(Color("3c657a")))
	style.set_stylebox("disabled", "Button", _box(Color("182c3c")))
	style.set_stylebox("normal", "LineEdit", _box(Color("0b1723")))
	style.set_stylebox("focus", "LineEdit", _box(Color("112534"), Color("62d5bf")))
	style.set_color("font_color", "LineEdit", Color("e3edf4"))
	style.set_color("font_placeholder_color", "LineEdit", Color("6e8495"))
	style.set_stylebox("panel", "ItemList", _box(Color("101f2d")))
	style.set_stylebox("selected", "ItemList", _box(Color("294d5f")))
	style.set_color("font_color", "ItemList", Color("dce9f1"))
	style.set_constant("v_separation", "ItemList", 16)
	theme = style
	active_game = _label(self, "ROOMKIT", Vector2(28, 19), Vector2(760, 45), 30)
	header_name = _label(self, "玩家入口", Vector2(804, 29), Vector2(402, 35), 17, Color("9fb3c2"))
	header_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	server_notice = _label(self, "", Vector2(28, 88), Vector2(1184, 45), 16, Color("ffd293"))
	permanent_message = _label(self, "", Vector2(44, 752), Vector2(1148, 54), 16, Color("c2d5df"))
	permanent_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_login()
	_build_lobby()
	_build_game()
	_build_inventory()
	_build_account()

func _box(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(7)
	box.set_content_margin_all(12)
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	return box

func _panel(position: Vector2, dimensions: Vector2, parent: Node = self, color := Color("142536")) -> Panel:
	var node := Panel.new()
	node.position = position
	node.size = dimensions
	node.add_theme_stylebox_override("panel", _box(color))
	parent.add_child(node)
	return node

func _label(parent: Node, text: String, position: Vector2, dimensions: Vector2, font_size := 17, color := Color("e3edf4")) -> Label:
	var node := Label.new()
	node.text = text
	node.position = position
	node.size = dimensions
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _button(parent: Node, text: String, position: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.position = position
	node.size = dimensions
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _field(parent: Node, label: String, position: Vector2, width := 410.0, secret := false) -> LineEdit:
	_label(parent, label, position, Vector2(width, 24), 15, Color("9cb3c3"))
	var node := LineEdit.new()
	node.position = position + Vector2(0, 29)
	node.size = Vector2(width, 43)
	node.secret = secret
	node.max_length = 128 if secret else 32
	parent.add_child(node)
	return node

func _build_login() -> void:
	login_panel = Control.new()
	add_child(login_panel)
	_label(login_panel, "连接你的下一场比赛", Vector2(52, 218), Vector2(560, 58), 34)
	var intro := _label(login_panel, "独立房间 · 持久资产 · 通用游戏接入\n\n使用管理员发放的邀请码注册。\n解锁与默认配置会保存在服务器，\n离开房间后仍然保留。", Vector2(56, 308), Vector2(540, 238), 20, Color("9eb5c7"))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(login_panel, "WINDOWS  /  ENCRYPTED CONNECTION", Vector2(56, 618), Vector2(540, 30), 14, Color("5bcbb7"))
	var form := _panel(Vector2(668, 152), Vector2(520, 565), login_panel)
	login_title = _label(form, "欢迎回来", Vector2(44, 27), Vector2(425, 44), 28)
	login_username = _field(form, "用户名 · 3–32 个英文字母、数字或 _ . -", Vector2(44, 93), 432)
	login_password = _field(form, "密码 · 8–128 个字符", Vector2(44, 181), 432, true)
	register_fields = Control.new()
	form.add_child(register_fields)
	register_name = _field(register_fields, "昵称", Vector2(44, 268), 432)
	register_invite = _field(register_fields, "管理员发放的邀请码", Vector2(44, 354), 432)
	register_invite.max_length = 128
	login_button = _button(form, "登录", Vector2(44, 280), Vector2(432, 48), _submit_login)
	login_button.add_theme_stylebox_override("normal", _box(Color("246958")))
	toggle_auth = _button(form, "没有账号？使用邀请码注册", Vector2(44, 347), Vector2(432, 43), func(): register_mode = not register_mode)
	login_password.text_submitted.connect(func(_text): _submit_login())

func _submit_login() -> void:
	if register_mode:
		app.register_account(login_username.text, login_password.text, register_name.text, register_invite.text)
	else:
		app.login(login_username.text, login_password.text)

func _build_lobby() -> void:
	lobby_panel = Control.new()
	add_child(lobby_panel)
	_label(lobby_panel, "游戏大厅", Vector2(40, 143), Vector2(500, 43), 28)
	_label(lobby_panel, "选择就绪的房间，或创建你自己的独立房间。", Vector2(41, 194), Vector2(720, 35), 17, Color("93acbf"))
	room_list.position = Vector2(40, 248)
	room_list.size = Vector2(735, 370)
	room_list.add_theme_font_size_override("font_size", 19)
	room_list.item_selected.connect(func(index): app.selected_room = str(room_list.get_item_metadata(index)))
	room_list.item_activated.connect(func(_index): app.join_selected())
	lobby_panel.add_child(room_list)
	refresh_button = _button(lobby_panel, "刷新房间", Vector2(40, 642), Vector2(170, 48), func(): app.refresh_lobby())
	create_button = _button(lobby_panel, "创建房间", Vector2(230, 642), Vector2(170, 48), func(): app.create_room())
	join_button = _button(lobby_panel, "进入所选房间", Vector2(520, 642), Vector2(255, 48), func(): app.join_selected())
	var profile := _panel(Vector2(802, 151), Vector2(388, 542), lobby_panel)
	_label(profile, "准备出发", Vector2(30, 28), Vector2(322, 40), 25)
	asset_hint = _label(profile, "正在读取资产…", Vector2(30, 98), Vector2(325, 135), 19, Color("b4cbd7"))
	asset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_buttons.append(_button(profile, "背包与默认配置  [B]", Vector2(30, 258), Vector2(328, 48), func(): app.toggle_inventory()))
	_button(profile, "账号设置", Vector2(30, 329), Vector2(328, 46), func(): app.account_open = true)
	_button(profile, "退出登录", Vector2(30, 400), Vector2(328, 46), func(): app.logout())
	_label(profile, "每个账号默认最多一个活动房间", Vector2(30, 479), Vector2(328, 35), 14, Color("7d97aa"))

func _build_game() -> void:
	game_panel = Control.new()
	game_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_panel)
	game_status = _label(game_panel, "正在连接…", Vector2(28, 124), Vector2(950, 33), 19, Color("98dbc8"))
	var side := _panel(Vector2(1008, 164), Vector2(204, 540), game_panel)
	_label(side, "房间操作", Vector2(18, 18), Vector2(170, 33), 20)
	inventory_buttons.append(_button(side, "打开背包 [B]", Vector2(16, 72), Vector2(172, 44), func(): app.toggle_inventory()))
	var respawn := _button(side, "手动复活 [R]", Vector2(16, 133), Vector2(172, 44), func(): app.respawn())
	gameplay_buttons.append(respawn)
	var take_one := _button(side, "取 1 颗", Vector2(16, 72), Vector2(172, 44), func(): app.choose(1))
	var take_two := _button(side, "取 2 颗", Vector2(16, 133), Vector2(172, 44), func(): app.choose(2))
	gameplay_buttons.append(take_one)
	gameplay_buttons.append(take_two)
	scoreboard = _label(side, "", Vector2(18, 206), Vector2(172, 208), 14, Color("a6bccb"))
	scoreboard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leave_button = _button(side, "返回大厅", Vector2(16, 468), Vector2(172, 46), func(): app.leave_room())
	help_text = _label(game_panel, "", Vector2(28, 709), Vector2(965, 27), 14, Color("8fa6b7"))
	own_notice = _label(game_panel, "", Vector2(1026, 568), Vector2(172, 57), 13, Color("ffdca1"))
	own_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_inventory() -> void:
	inventory_panel = _panel(Vector2(173, 128), Vector2(894, 601), self, Color("182f40"))
	_label(inventory_panel, "背包与默认配置", Vector2(28, 21), Vector2(690, 43), 27)
	_button(inventory_panel, "关闭", Vector2(774, 22), Vector2(92, 38), func(): app.toggle_inventory())
	inventory_balance = _label(inventory_panel, "", Vector2(30, 85), Vector2(820, 35), 20, Color("ffcf84"))
	inventory_info = _label(inventory_panel, "", Vector2(30, 126), Vector2(824, 49), 15, Color("9fbccc"))
	inventory_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_select = OptionButton.new()
	slot_select.position = Vector2(30, 185)
	slot_select.size = Vector2(280, 40)
	slot_select.item_selected.connect(func(_index): inventory_signature = "")
	inventory_panel.add_child(slot_select)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 246)
	scroll.size = Vector2(838, 222)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_panel.add_child(scroll)
	inventory_cards = Control.new()
	inventory_cards.custom_minimum_size = Vector2(824, 219)
	scroll.add_child(inventory_cards)
	pending_label = _label(inventory_panel, "", Vector2(30, 484), Vector2(830, 40), 15, Color("ffd398"))
	pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retry_button = _button(inventory_panel, "查询 / 重试原操作", Vector2(30, 540), Vector2(290, 39), func(): app.retry_asset())
	_button(inventory_panel, "刷新资产", Vector2(657, 540), Vector2(200, 39), _refresh_inventory)

func _refresh_inventory() -> void:
	if app.busy or not app.inventory_allowed():
		return
	app.busy = true
	await app._load_catalog()
	await app._read_assets()
	app.busy = false

func _build_account() -> void:
	account_panel = _panel(Vector2(340, 132), Vector2(560, 585), self, Color("182f40"))
	_label(account_panel, "账号设置", Vector2(32, 24), Vector2(370, 45), 28)
	_button(account_panel, "关闭", Vector2(427, 27), Vector2(100, 37), func(): app.account_open = false)
	account_name = _field(account_panel, "新昵称 · 房间显示需重新入房更新", Vector2(32, 96), 345)
	_button(account_panel, "保存昵称", Vector2(395, 125), Vector2(132, 43), func(): app.rename(account_name.text))
	old_password = _field(account_panel, "当前密码", Vector2(32, 214), 496, true)
	new_password = _field(account_panel, "新密码 · 8–128 个字符", Vector2(32, 310), 496, true)
	_button(account_panel, "更新密码并重新登录", Vector2(32, 418), Vector2(496, 46), func(): app.change_password(old_password.text, new_password.text))
	var help := _label(account_panel, "忘记密码请联系管理员重置。\n更改密码后，当前登录会话会失效。", Vector2(32, 492), Vector2(496, 65), 16, Color("9bb4c5"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func clear_passwords() -> void:
	login_password.text = ""
	old_password.text = ""
	new_password.text = ""

var ui_elapsed := 0.1

func _process(delta: float) -> void:
	if app == null or login_panel == null:
		return
	# Arena redraw follows the display; text, lists and forms need only 10 Hz.
	queue_redraw()
	ui_elapsed += delta
	if ui_elapsed < 0.1:
		return
	ui_elapsed = 0.0
	var authenticated: bool = app.authenticated
	var in_room: bool = app.client != null and app.client.state == "IN_ROOM"
	active_game.text = "ROOMKIT  /  " + ("零号仓库" if app.game_id == "shooter" else "十二颗石子")
	header_name.text = str(app.client.identity.get("display_name", "")) + "  ·  " + ("房间内" if in_room else "大厅") if authenticated else "玩家账号入口"
	server_notice.text = app.notice
	permanent_message.text = ("处理中 · " if app.busy else "") + app.message
	login_panel.visible = not authenticated
	lobby_panel.visible = authenticated and not in_room and not app.inventory_open and not app.account_open
	game_panel.visible = authenticated and in_room and not app.inventory_open and not app.account_open
	inventory_panel.visible = authenticated and app.inventory_open
	account_panel.visible = authenticated and app.account_open
	register_fields.visible = register_mode
	login_title.text = "邀请码注册" if register_mode else "欢迎回来"
	login_button.text = "创建账号" if register_mode else "登录"
	login_button.position.y = 448 if register_mode else 280
	toggle_auth.position.y = 508 if register_mode else 347
	toggle_auth.text = "已有账号？返回登录" if register_mode else "没有账号？使用邀请码注册"
	login_button.disabled = app.busy or not app.configuration_ready
	toggle_auth.disabled = app.busy
	refresh_button.disabled = app.busy or app.polling
	create_button.disabled = app.busy or app.maintenance or not app.pending_asset.is_empty()
	join_button.disabled = app.busy or app.maintenance or app.selected_room == "" or not app.pending_asset.is_empty() or not _selected_ready()
	leave_button.disabled = app.busy
	for button in inventory_buttons:
		button.disabled = app.busy or not app.inventory_allowed()
		button.visible = button != inventory_buttons[1] or app.game_id == "shooter"
	if authenticated:
		_refresh_room_list()
		var slots: Dictionary = app.assets.get("profiles", {}).get(app.game_id, {})
		var defaults: Array = []
		for slot in slots:
			defaults.append(_item_name(str(slots[slot])))
		asset_hint.text = "金币  %d\n等级  %d  ·  经验  %d\n默认配置  %s" % [int(app.assets.get("credits", 0)), int(app.asset_level), int(app.assets.get("experience", 0)), " / ".join(defaults) if not defaults.is_empty() else "尚未读取"]
	if in_room and app.world != null:
		game_status.text = app.world.status_text(app.client.identity.get("user_id", ""))
		help_text.text = app.world.instructions()
		help_text.text += "  ·  %d FPS" % Engine.get_frames_per_second()
		var own: Dictionary = app.world.player_view(app.client.identity.get("user_id", "")) if app.world.has_method("player_view") else {}
		own_notice.text = str(own.get("notice", ""))
		gameplay_buttons[0].visible = app.game_id == "shooter"
		gameplay_buttons[0].disabled = app.busy or own.get("life_state", "") != "dead" or int(own.get("respawn_wait_ms", 1)) > 0 or own.get("asset_busy", false) or not app.pending_asset.is_empty()
		for index in [1, 2]:
			gameplay_buttons[index].visible = app.game_id == "turns"
			gameplay_buttons[index].disabled = app.busy or app.world.latest.get("active_user", "") != app.client.identity.get("user_id", "") or app.world.latest.get("players", []).size() < 2
		var score_lines: Array = ["当前对局"]
		for player in app.world.latest.get("players", []):
			if app.game_id == "shooter":
				score_lines.append("%s  %d / %d" % [str(player.display_name).left(8), int(player.kills), int(player.deaths)])
			else:
				score_lines.append("%s  %d分" % [str(player.display_name).left(8), int(player.score)])
			if score_lines.size() >= 9:
				break
		scoreboard.text = "\n".join(score_lines)
	if inventory_panel.visible:
		_update_inventory()
	queue_redraw()

func _selected_ready() -> bool:
	for row in app.rooms:
		if str(row.room_id) == app.selected_room:
			return row.get("state", "") == "READY" and int(row.get("occupied", 0)) < int(row.get("capacity", 0))
	return false

func _refresh_room_list() -> void:
	var signature: String = JSON.stringify(app.rooms) + str(app.selected_room)
	if signature == room_signature:
		return
	room_signature = signature
	room_list.clear()
	var states := {"READY": "可进入", "STARTING": "启动中", "ALLOCATING": "分配中", "DRAINING": "关闭中", "STOPPING": "关闭中", "STOPPED": "已关闭", "FAILED": "启动失败"}
	for row in app.rooms:
		var text := "房间 %s      %s      %d / %d 人" % [str(row.room_id).left(10), str(states.get(row.get("state", ""), row.get("state", ""))), int(row.get("occupied", 0)), int(row.get("capacity", 0))]
		var index := room_list.add_item(text)
		room_list.set_item_metadata(index, row.room_id)
		if row.room_id == app.selected_room:
			room_list.select(index)
	if app.rooms.is_empty():
		room_list.add_item("暂无房间，点击下方“创建房间”开始。")
		room_list.set_item_disabled(0, true)

func _item_name(item_id: String) -> String:
	return str(app.catalog.get("spaces", {}).get(app.asset_space, {}).get("items", {}).get(item_id, {}).get("name", item_id))

func _update_inventory() -> void:
	inventory_balance.text = "金币  %d    ·    等级  %d    ·    经验  %d" % [int(app.assets.get("credits", 0)), int(app.asset_level), int(app.assets.get("experience", 0))]
	inventory_info.text = "解锁只购买所有权；选择后保存默认配置。当前空间：" + app.asset_space + "。"
	if app.client.state == "IN_ROOM":
		inventory_info.text += "\n射击示例死亡期间允许操作，确认保存后可手动复活。"
	var slots: Dictionary = app.catalog.get("games", {}).get(app.game_id, {}).get("slots", {})
	var new_slot_signature := JSON.stringify(slots)
	if slot_signature != new_slot_signature:
		slot_signature = new_slot_signature
		slot_select.clear()
		for slot in slots:
			var index := slot_select.item_count
			slot_select.add_item("默认武器" if slot == "primary" else ("默认主题" if slot == "theme" else str(slot)))
			slot_select.set_item_metadata(index, slot)
	var slot := str(slot_select.get_item_metadata(slot_select.selected)) if slot_select.item_count > 0 and slot_select.selected >= 0 else ""
	var signature: String = JSON.stringify(app.assets) + JSON.stringify(app.catalog) + slot + str(app.busy) + str(app.pending_asset.is_empty())
	if signature != inventory_signature:
		inventory_signature = signature
		for child in inventory_cards.get_children():
			inventory_cards.remove_child(child)
			child.queue_free()
		var allowed: Array = slots.get(slot, {}).get("allowed", [])
		if allowed.is_empty():
			_label(inventory_cards, "商品目录暂不可用，请点击刷新资产。", Vector2.ZERO, Vector2(820, 70), 18)
		inventory_cards.custom_minimum_size.y = maxi(1, ceili(float(allowed.size()) / 3.0)) * 231
		for index in allowed.size():
			var item_id := str(allowed[index])
			var item: Dictionary = app.catalog.get("spaces", {}).get(app.asset_space, {}).get("items", {}).get(item_id, {})
			var owned: bool = item_id in app.assets.get("owned", [])
			var selected: bool = app.assets.get("profiles", {}).get(app.game_id, {}).get(slot, "") == item_id
			var card := _panel(Vector2((index % 3) * 278, (index / 3) * 231), Vector2(264, 219), inventory_cards, Color("102332"))
			_label(card, str(item.get("name", item_id)), Vector2(18, 14), Vector2(228, 33), 22)
			_label(card, "当前默认" if selected else ("已永久解锁" if owned else "%d 金币解锁" % int(item.get("price", 0))), Vector2(18, 57), Vector2(228, 30), 17, Color("79d6c0") if owned else Color("ffcb86"))
			var description: String = {"rifle": "稳定、精确的基础武器", "smg": "高射速，适合中近距离", "shotgun": "近距离六颗散射弹丸", "classic": "简单清晰的经典石子", "jade": "柔和的玉石色彩主题"}.get(item_id, "持久物品 · 当前游戏可用")
			_label(card, description, Vector2(18, 104), Vector2(228, 30), 14, Color("8faebe"))
			var action := _button(card, "已设为默认" if selected else ("选择为默认" if owned else "解锁"), Vector2(18, 157), Vector2(228, 44), func(): app.asset_action("select" if owned else "purchase", item_id, slot))
			action.disabled = app.busy or selected or not app.pending_asset.is_empty() or (not owned and int(app.assets.get("credits", 0)) < int(item.get("price", 0)))
	pending_label.text = "" if app.pending_asset.is_empty() else "待确认：" + ("解锁 " if app.pending_asset.kind == "purchase" else "选择 ") + _item_name(app.pending_asset.item_id) + "。请查询原操作后再入房或复活。"
	retry_button.visible = not app.pending_asset.is_empty()
	retry_button.disabled = app.busy
	slot_select.disabled = app.busy

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_B:
		app.toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_R and not app.account_open:
		app.respawn()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE:
		if app.inventory_open:
			app.toggle_inventory()
		elif app.account_open:
			app.account_open = false

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1240, 820), Color("0c1724"))
	draw_line(Vector2(28, 77), Vector2(1212, 77), Color("243a4c"), 1)
	draw_rect(Rect2(28, 746, 1184, 61), Color("142434"))
	if app == null or app.client == null or app.world == null:
		return
	if app.authenticated and app.client.state == "IN_ROOM" and not app.inventory_open and not app.account_open:
		draw_rect(Rect2(ARENA_POSITION - Vector2.ONE, Vector2(962, 542)), Color("466274"))
		draw_set_transform(ARENA_POSITION)
		if app.game_id == "turns":
			draw_rect(Rect2(Vector2.ZERO, Vector2(960, 540)), Color("172d3d"))
			draw_set_transform(ARENA_POSITION + Vector2(120, 90))
		app.world.draw_on(self, app.client.identity.get("user_id", ""), font)
		draw_set_transform(Vector2.ZERO)
