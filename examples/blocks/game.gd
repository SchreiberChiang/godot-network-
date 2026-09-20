extends Node
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var server := false
var players: Dictionary = {}
var peers: Dictionary = {}
var latest: Dictionary = {}
var tick := 0
var accumulator := 0.0
var sequence := 0
var rejected := 0

func admit(identity: Dictionary, peer: int) -> void:
	if peer <= 1 or players.has(identity.user_id):
		return
	peers[peer] = identity.user_id
	players[identity.user_id] = {"display_name": identity.display_name, "position": Vector2(120 + players.size() * 32, 180), "direction": Vector2.ZERO, "last_input": -1000, "sequence": 0, "window": 0, "received": 0}
	_publish()

func remove_player(user_id: String) -> void:
	players.erase(user_id)
	for peer in peers.keys():
		if peers[peer] == user_id:
			peers.erase(peer)
	_publish()

# Inputs contain direction only; position and elapsed time are server-owned.
func handle_input(peer: int, command: Dictionary, now: int) -> bool:
	if not peers.has(peer) or Validator.validate_file(command, "res://schemas/blocks_input.schema.json") != "":
		rejected += 1
		return false
	var player: Dictionary = players[peers[peer]]
	if now - int(player.window) >= 1000:
		player.window = now
		player.received = 0
	player.received += 1
	if player.received > 60 or int(command.sequence) <= int(player.sequence):
		rejected += 1
		return false
	player.sequence = int(command.sequence)
	player.direction = Vector2(float(command.x), float(command.y)).limit_length(1.0)
	player.last_input = now
	return true

func advance(now: int) -> void:
	tick += 1
	for player in players.values():
		var direction: Vector2 = player.direction if now - int(player.last_input) <= 250 else Vector2.ZERO
		var next: Vector2 = player.position + direction * 180.0 * 0.05
		player.position = Vector2(clampf(next.x, 24, 696), clampf(next.y, 24, 336))

func state_snapshot() -> Dictionary:
	var rows: Array = []
	for user in players:
		var player: Dictionary = players[user]
		rows.append({"user_id": user, "display_name": player.display_name, "x": player.position.x, "y": player.position.y})
	return {"tick": tick, "players": rows}

func _process(delta: float) -> void:
	if not server:
		return
	accumulator = minf(accumulator + delta, 0.2)
	while accumulator >= 0.05:
		accumulator -= 0.05
		advance(Time.get_ticks_msec())
		if tick % 2 == 0:
			_publish()

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func input_command(command: Dictionary) -> void:
	if server:
		handle_input(multiplayer.get_remote_sender_id(), command, Time.get_ticks_msec())

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func world_state(value: Dictionary) -> void:
	if not server and Validator.validate_file(value, "res://schemas/blocks_state.schema.json") == "" and int(value.tick) >= int(latest.get("tick", -1)):
		latest = value

func _publish() -> void:
	if not is_inside_tree():
		return
	for peer in peers:
		world_state.rpc_id(peer, state_snapshot())

func send_direction(direction: Vector2) -> void:
	sequence += 1
	input_command.rpc_id(1, {"sequence": sequence, "x": direction.x, "y": direction.y})

func title() -> String:
	return "方块漫游"

func instructions() -> String:
	return "WASD / 方向键移动 · 切换两个窗口观察同步 · 橙色是你"

func status_text(_user: String) -> String:
	return "%d 人在线   ·   服务器步数 %d" % [latest.get("players", []).size(), int(latest.get("tick", 0))]

func actions() -> Array:
	return []

func draw_on(canvas: CanvasItem, user: String, font: Font) -> void:
	for x in range(0, 721, 40):
		canvas.draw_line(Vector2(x, 0), Vector2(x, 360), Color("26354d"))
	for y in range(0, 361, 40):
		canvas.draw_line(Vector2(0, y), Vector2(720, y), Color("26354d"))
	for player in latest.get("players", []):
		var position := Vector2(player.x, player.y)
		var color := Color("ffbf69") if player.user_id == user else Color("64dfdf")
		canvas.draw_rect(Rect2(position - Vector2(17, 13), Vector2(34, 34)), Color(0, 0, 0, 0.25))
		canvas.draw_rect(Rect2(position - Vector2(16, 16), Vector2(32, 32)), color)
		canvas.draw_string(font, position + Vector2(-42, -26), player.display_name, HORIZONTAL_ALIGNMENT_CENTER, 84, 15, Color("edf3ff"))
