extends Node
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
signal round_finished(round_index: int, scores: Array)
var server := false
var players: Dictionary = {}
var peers: Dictionary = {}
var order: Array = []
var latest: Dictionary = {}
var stones := 12
var round_number := 1
var turn := 1
var active_user := ""
var rejected := 0
var elapsed := 0.0

func admit(identity: Dictionary, peer: int) -> void:
	if peer <= 1 or players.has(identity.user_id):
		return
	peers[peer] = identity.user_id
	players[identity.user_id] = {"user_id": identity.user_id, "display_name": identity.display_name, "score": 0}
	order.append(identity.user_id)
	if active_user == "":
		active_user = identity.user_id
	_publish()

func remove_player(user_id: String) -> void:
	var previous := order.find(user_id)
	players.erase(user_id)
	order.erase(user_id)
	for peer in peers.keys():
		if peers[peer] == user_id:
			peers.erase(peer)
	if active_user == user_id:
		active_user = "" if order.is_empty() else str(order[maxi(previous, 0) % order.size()])
	# Invalidate queued inputs on membership changes too.
	turn += 1
	_publish()

func handle_input(peer: int, command: Dictionary) -> bool:
	if not peers.has(peer) or Validator.validate_file(command, "res://schemas/turns_input.schema.json") != "":
		rejected += 1
		return false
	var user: String = peers[peer]
	if order.size() < 2 or user != active_user or int(command.turn) != turn or int(command.take) > stones:
		rejected += 1
		return false
	stones -= int(command.take)
	if stones == 0:
		players[user].score += 1
		round_finished.emit(round_number, players.values().duplicate(true))
		round_number += 1
		stones = 12
	active_user = str(order[(order.find(user) + 1) % order.size()])
	turn += 1
	_publish()
	return true

func state_snapshot() -> Dictionary:
	return {"round": round_number, "stones": stones, "turn": turn, "active_user": active_user, "players": players.values().duplicate(true)}

func _process(delta: float) -> void:
	if server:
		elapsed += delta
		if elapsed >= 0.5:
			elapsed = 0
			_publish()

@rpc("any_peer", "call_remote", "reliable", 1)
func input_command(command: Dictionary) -> void:
	if server:
		handle_input(multiplayer.get_remote_sender_id(), command)

@rpc("authority", "call_remote", "reliable", 1)
func world_state(value: Dictionary) -> void:
	if not server and Validator.validate_file(value, "res://schemas/turns_state.schema.json") == "" and int(value.turn) >= int(latest.get("turn", 0)):
		latest = value

func _publish() -> void:
	if not is_inside_tree():
		return
	for peer in peers:
		world_state.rpc_id(peer, state_snapshot())

func choose(take: int) -> void:
	input_command.rpc_id(1, {"turn": int(latest.get("turn", 0)), "take": take})

func title() -> String:
	return "十二颗石子"

func instructions() -> String:
	return "每回合取 1 或 2 颗 · 取走最后一颗得 1 分 · 至少两人开始"

func status_text(user: String) -> String:
	if latest.get("players", []).size() < 2:
		return "等待另一名玩家入座"
	return "第 %d 局   ·   %s" % [int(latest.get("round", 1)), "轮到你了" if latest.get("active_user", "") == user else "等待对手选择"]

func actions() -> Array:
	return ["取 1 颗", "取 2 颗"]

func draw_on(canvas: CanvasItem, user: String, font: Font) -> void:
	for i in int(latest.get("stones", 12)):
		var position := Vector2(135 + (i % 6) * 90, 135 + (i / 6) * 80)
		canvas.draw_circle(position + Vector2(0, 5), 24, Color(0, 0, 0, 0.25))
		canvas.draw_circle(position, 22, Color("a3dbc4"))
		canvas.draw_circle(position - Vector2(6, 7), 5, Color("d3f7e5"))
	var names: Array = []
	for player in latest.get("players", []):
		names.append("%s%s：%d 分" % [player.display_name, "（你）" if player.user_id == user else "", int(player.score)])
	canvas.draw_string(font, Vector2(26, 36), "    /    ".join(names), HORIZONTAL_ALIGNMENT_LEFT, 668, 19, Color("edf3ff"))
