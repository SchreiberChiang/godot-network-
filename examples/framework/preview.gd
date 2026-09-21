extends "client.gd"
## Explicit rendering fixture. No socket login, room admission or database is tested.
const Shooter = preload("res://examples/shooter/game.gd")

func _run() -> void:
	await super._run()
	if view == null or world == null:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(Paths.absolute("res://logs/framework-preview"))
	configuration_ready = true
	message = "界面渲染测试数据 · 未连接服务器"
	await _picture("01-login")
	view.register_mode = true
	await _picture("02-register")
	view.register_mode = false
	authenticated = true
	client.identity = {"user_id": "preview_one", "display_name": "仓库守望者"}
	client.state = "LOBBY"
	assets = {"revision": 3, "credits": 180, "experience": 40, "owned": ["rifle", "smg"], "profiles": {"shooter": {"primary": "rifle"}}}
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	asset_space = "shooter"
	rooms = [{"room_id": "r_7da5d58f", "state": "READY", "occupied": 2, "capacity": 8}, {"room_id": "r_b3c1ae44", "state": "STARTING", "occupied": 0, "capacity": 8}]
	await _picture("03-lobby")
	inventory_open = true
	await _picture("04-inventory")
	inventory_open = false
	account_open = true
	await _picture("05-account")
	account_open = false
	client.state = "IN_ROOM"
	var simulation = Shooter.new()
	simulation.admit({"user_id": "preview_one", "display_name": "仓库守望者"}, 2)
	simulation.admit({"user_id": "preview_two", "display_name": "海盐汽水"}, 3)
	simulation.advance(0)
	simulation.players.preview_one.position = Vector2(225, 358)
	simulation.players.preview_two.position = Vector2(720, 358)
	simulation.handle_input(2, {"sequence": 1, "move": 0, "jump": false, "fire": true, "aim_x": 1, "aim_y": 0}, 300)
	simulation.advance(300)
	world.latest = simulation.state_snapshot()
	await _picture("06-shooter")
	simulation._damage("preview_one", "preview_two", 100, 300)
	simulation.advance(4000)
	world.latest = simulation.state_snapshot()
	await _picture("07-dead")
	simulation.free()
	print("FRAMEWORK_RENDER_RESULT screenshots=7 fixture_only=true")
	quit(0)

func _process(_delta: float) -> bool:
	return false

func _picture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(Paths.absolute("res://logs/framework-preview/" + label + ".png"))
	if error != OK:
		printerr("FRAMEWORK_RENDER_FAILED ", label, " ", error)
