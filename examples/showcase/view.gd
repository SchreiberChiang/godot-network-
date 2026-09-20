extends Node2D
var app
var font := SystemFont.new()
var exit_button := Button.new()
var action_buttons: Array = []

func _ready() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	exit_button.position = Vector2(640, 567)
	exit_button.size = Vector2(130, 42)
	exit_button.add_theme_font_override("font", font)
	exit_button.add_theme_font_size_override("font_size", 18)
	exit_button.pressed.connect(func(): app.toggle_room())
	add_child(exit_button)
	for i in app.world.actions().size():
		var button := Button.new()
		button.text = app.world.actions()[i]
		button.position = Vector2(50 + i * 150, 567)
		button.size = Vector2(136, 42)
		button.add_theme_font_override("font", font)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func(): app.choose(i + 1))
		add_child(button)
		action_buttons.append(button)

func _process(_delta: float) -> void:
	exit_button.text = "重新入房" if app.client.state == "LOBBY" else "退出房间"
	exit_button.disabled = app.busy or app.client.state not in ["LOBBY", "IN_ROOM"]
	for button in action_buttons:
		button.disabled = app.client.state != "IN_ROOM" or app.world.latest.get("active_user", "") != app.client.identity.get("user_id", "") or app.world.latest.get("players", []).size() < 2
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 820, 650), Color("101a2b"))
	draw_string(font, Vector2(50, 38), "ROOMKIT   /   LOCAL PLAY", HORIZONTAL_ALIGNMENT_LEFT, 720, 15, Color("64dfdf"))
	draw_string(font, Vector2(50, 83), app.world.title(), HORIZONTAL_ALIGNMENT_LEFT, 510, 33, Color("f2f5fc"))
	draw_string(font, Vector2(585, 78), app.display_name, HORIZONTAL_ALIGNMENT_RIGHT, 185, 19, Color("ffbf69"))
	draw_string(font, Vector2(50, 117), app.world.instructions(), HORIZONTAL_ALIGNMENT_LEFT, 720, 17, Color("aebdd5"))
	var active: bool = app.client.state == "IN_ROOM"
	draw_string(font, Vector2(50, 149), app.world.status_text(app.client.identity.get("user_id", "")) if active else app.message, HORIZONTAL_ALIGNMENT_LEFT, 720, 18, Color("a3dbc4"))
	draw_rect(Rect2(49, 169, 722, 362), Color("39506d"))
	draw_rect(Rect2(50, 170, 720, 360), Color("1b293f"))
	if active:
		draw_set_transform(Vector2(50, 170))
		app.world.draw_on(self, app.client.identity.get("user_id", ""), font)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_string(font, Vector2(80, 345), "大厅已保留 · 准备好后可重新入房" if app.client.state == "LOBBY" else "正在连接本机房间…", HORIZONTAL_ALIGNMENT_CENTER, 660, 23, Color("aebdd5"))
	draw_string(font, Vector2(50, 635), "本机回环连接  ·  独立房间进程  ·  关闭两个窗口后自动回收", HORIZONTAL_ALIGNMENT_LEFT, 720, 14, Color("8699b6"))
