extends "res://examples/framework/client.gd"
## Pure client feedback regression using confirmed snapshot projections, not UI/network acceptance.
const ShooterWorld = preload("res://examples/shooter/game.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	_verify_feedback.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _verify_feedback() -> void:
	client = AccountClient.new()
	client.state = "IN_ROOM"
	client.identity = {"user_id": "feedback_player"}
	world = ShooterWorld.new()
	_snapshot("alive")
	message = "已进入房间"
	_sync_life_view()
	_check(message == "已进入房间", "initial admission preserves its own feedback")
	_snapshot("dead")
	_sync_life_view()
	_check(message == "你已阵亡，可以打开背包解锁或选枪", "confirmed death changes feedback")
	message = "正在确认装备并复活…"
	_sync_life_view()
	_check(message == "正在确认装备并复活…", "pending respawn is not announced successful before confirmation")
	inventory_open = true
	_snapshot("alive")
	_sync_life_view()
	_check(message == "已复活，可以继续战斗", "confirmed respawn replaces stale pending feedback")
	_check(not inventory_open, "confirmed living state closes inventory")
	message = "昵称已保存"
	_sync_life_view()
	_check(message == "昵称已保存", "stable alive snapshots preserve subsequent operation feedback")
	client.state = "LOBBY"
	_snapshot("dead")
	_sync_life_view()
	_check(message == "昵称已保存", "out-of-room snapshots do not change feedback")
	client.free()
	world.free()
	print("FRAMEWORK_FEEDBACK_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _snapshot(life: String) -> void:
	world.latest = {"players": [{"user_id": "feedback_player", "life_state": life, "hp": 100 if life == "alive" else 0, "weapon": "smg"}]}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
