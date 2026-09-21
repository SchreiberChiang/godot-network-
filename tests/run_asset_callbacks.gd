extends "res://sdk/roomkit/server/room_runtime.gd"
## Real Godot execution of deterministic SDK lifecycle callbacks; no network is faked as passed.
const BaseAdapter = preload("res://sdk/roomkit/server/game_adapter.gd")
const ShooterAdapter = preload("res://examples/shooter/adapter.gd")
const ShooterWorld = preload("res://examples/shooter/game.gd")
var passed := 0
var failed := 0
var emitted: Array = []
var disconnected: Array = []

class ProbeAdapter extends BaseAdapter:
	var busy: Dictionary = {}
	var callbacks: Array = []
	func asset_context(_user_id: String) -> Dictionary:
		return {"location": "room", "phase": "maintenance_zone"}
	func set_asset_busy(user_id: String, value: bool) -> void:
		busy[user_id] = value
	func on_asset_state(user_id: String, state: Dictionary) -> void:
		callbacks.append({"type": "state", "user_id": user_id, "state": state})
	func complete_asset_refresh(user_id: String, operation: String, state: Dictionary) -> void:
		callbacks.append({"type": "complete", "user_id": user_id, "operation": operation, "state": state})
	func cancel_asset_refresh(user_id: String, operation: String) -> void:
		callbacks.append({"type": "cancel", "user_id": user_id, "operation": operation})
	func on_player_left(identity: Dictionary, _reason: String) -> void:
		callbacks.append({"type": "left", "user_id": identity.user_id})

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _send(type: String, payload: Dictionary) -> void:
	emitted.append({"type": type, "payload": payload.duplicate(true)})

func _broadcast() -> void:
	pass

func _disconnect(peer_id: int) -> void:
	disconnected.append(peer_id)
	_peer_left(peer_id)

func _member(attempt: String = "attempt-one") -> void:
	members[2] = {"state": "IN_ROOM", "attempt_id": attempt, "user_id": "u1", "display_name": "一号", "deadline": 0, "revision": revision, "assets_ready": true}
	attempts[attempt] = 2

func _reset() -> void:
	adapter = ProbeAdapter.new()
	context = {"assets_enabled": true}
	members.clear()
	attempts.clear()
	asset_operations.clear()
	emitted.clear()
	disconnected.clear()
	_member()

func _run() -> void:
	_reset()
	_refresh_assets("u1", "pit_stop")
	check(asset_operations.size() == 1 and adapter.busy.u1 and emitted.back().type == "asset.refresh", "generic game operation obtains bounded busy refresh")
	var operation_id: String = asset_operations.keys()[0]
	check(asset_operations[operation_id].operation == "pit_stop" and asset_operations[operation_id].kind == "refresh", "operation label stays game-owned")
	_refresh_assets("u1", "pit_stop")
	check(asset_operations.size() == 1 and adapter.callbacks.is_empty() and adapter.busy.u1, "same refresh signal twice preserves the original pending transition")
	_refresh_assets("u1", "garage_preview")
	check(asset_operations.size() == 1 and adapter.callbacks.back().type == "cancel" and adapter.callbacks.back().operation == "garage_preview", "overlapping request rejected with caller label")
	_asset_finish({"operation_id": operation_id, "user_id": "other", "ok": true, "state": {"revision": 99}})
	check(asset_operations.size() == 1 and adapter.busy.u1, "wrong-user response cannot unlock another operation")
	_asset_finish({"operation_id": operation_id, "user_id": "u1", "ok": true, "state": {"revision": 1}})
	check(asset_operations.is_empty() and not adapter.busy.u1, "successful refresh releases busy state")
	check(adapter.callbacks[-2].type == "state" and adapter.callbacks[-1].type == "complete" and adapter.callbacks[-1].operation == "pit_stop", "confirmed state precedes generic completion callback")
	var count: int = adapter.callbacks.size()
	_asset_finish({"operation_id": operation_id, "user_id": "u1", "ok": true, "state": {"revision": 2}})
	check(adapter.callbacks.size() == count, "duplicate finish cannot reapply game transition")
	_refresh_assets("u1", "repair")
	operation_id = asset_operations.keys()[0]
	_asset_finish({"operation_id": operation_id, "user_id": "u1", "ok": false, "state": {}})
	check(adapter.callbacks.back().type == "cancel" and adapter.callbacks.back().operation == "repair" and not adapter.busy.u1, "failed refresh reports cancellation")
	_refresh_assets("unknown", "configure")
	check(adapter.callbacks.back().type == "cancel" and asset_operations.is_empty(), "missing member gets immediate cancellation")
	context.assets_enabled = false
	_refresh_assets("u1", "configure")
	check(adapter.callbacks.back().type == "cancel" and asset_operations.is_empty(), "disabled assets fail closed")
	context.assets_enabled = true
	_refresh_assets("u1", "")
	check(asset_operations.is_empty(), "empty operation label cannot become active")
	_refresh_assets("u1", "repair")
	operation_id = asset_operations.keys()[0]
	var deadline: int = asset_operations[operation_id].deadline
	_expire_asset_operations(deadline)
	check(asset_operations.size() == 1, "operation remains live through its deadline")
	_expire_asset_operations(deadline + 1)
	check(asset_operations.is_empty() and members.has(2) and not adapter.busy.u1 and adapter.callbacks.back().type == "cancel", "read-only refresh timeout cancels without disconnecting")
	count = adapter.callbacks.size()
	_asset_finish({"operation_id": operation_id, "user_id": "u1", "ok": true, "state": {"revision": 9}})
	check(adapter.callbacks.size() == count, "late timeout response has no effect")
	_refresh_assets("u1", "repair")
	operation_id = asset_operations.keys()[0]
	asset_operations[operation_id].deadline = -1
	_asset_finish({"operation_id": operation_id, "user_id": "u1", "ok": true, "state": {"revision": 9}})
	check(asset_operations.is_empty() and adapter.callbacks.back().type == "cancel", "expired reply cannot beat the periodic timeout poll")
	_reset()
	var transaction := {"operation_id": "write-one", "attempt_id": "attempt-one", "user_id": "u1"}
	_asset_begin(transaction)
	check(asset_operations.size() == 1 and emitted.back().payload.ok and emitted.back().payload.context.phase == "maintenance_zone", "transaction permit exposes only game-provided context")
	_asset_begin({"operation_id": "write-two", "attempt_id": "attempt-one", "user_id": "u1"})
	check(not emitted.back().payload.ok and asset_operations.size() == 1, "one in-flight asset operation per member")
	_expire_asset_operations(int(asset_operations["write-one"].deadline) + 1)
	check(disconnected == [2] and members.is_empty() and asset_operations.is_empty(), "uncertain transaction timeout ends membership before another state transition")
	_member("attempt-new")
	count = adapter.callbacks.size()
	_asset_finish({"operation_id": "write-one", "user_id": "u1", "ok": true, "state": {"revision": 50}})
	check(adapter.callbacks.size() == count, "old transaction result cannot modify new admission")
	_reset()
	_refresh_assets("u1", "repair")
	_peer_left(2)
	check(asset_operations.is_empty() and attempts.is_empty() and not adapter.busy.u1, "departed member releases in-flight resources")
	check(adapter.callbacks[-2].type == "cancel" and adapter.callbacks[-1].type == "left", "game receives cancellation before removal")
	_reset()
	members[2].state = "LOADING"
	members[2].assets_ready = false
	_loaded(2, revision)
	check(members[2].state == "WAIT_HOST" and int(members[2].deadline) - Time.get_ticks_msec() >= 59900, "initial persistent asset read has sixty-second join window")
	_handle_control({"type": "asset.initial", "payload": {"attempt_id": "attempt-one", "user_id": "other", "state": {"revision": 1}}})
	check(not members[2].assets_ready and adapter.callbacks.is_empty(), "initial state must match admitted identity")
	_handle_control({"type": "asset.initial", "payload": {"attempt_id": "attempt-one", "user_id": "u1", "state": {"revision": 1}}})
	check(members[2].assets_ready and adapter.callbacks.size() == 1, "initial confirmed state arrives before admission callback")
	_handle_control({"type": "asset.initial", "payload": {"attempt_id": "attempt-one", "user_id": "u1", "state": {"revision": 2}}})
	check(adapter.callbacks.size() == 1, "duplicate initial state cannot replace confirmed configuration")
	_reset()
	members[2].state = "WAIT_HOST"
	members[2].assets_ready = false
	members[2].deadline = Time.get_ticks_msec() + 1000
	_handle_control({"type": "member.accepted", "payload": {"attempt_id": "attempt-one", "ok": true}})
	check(disconnected == [2], "member confirmation without mandatory asset state is rejected")
	_reset()
	members[2].state = "WAIT_HOST"
	members[2].assets_ready = false
	members[2].deadline = -1
	_handle_control({"type": "asset.initial", "payload": {"attempt_id": "attempt-one", "user_id": "u1", "state": {"revision": 1}}})
	check(not members[2].assets_ready and adapter.callbacks.is_empty(), "late initial asset state cannot bypass admission timeout")
	_handle_control({"type": "member.accepted", "payload": {"attempt_id": "attempt-one", "ok": true}})
	check(disconnected == [2], "late member confirmation closes expired admission")
	_reset()
	members[2].deadline = -1
	_handle_control({"type": "member.accepted", "payload": {"attempt_id": "attempt-one", "ok": true}})
	check(disconnected.is_empty(), "duplicate confirmation does not close an already admitted member")
	var shooter = ShooterAdapter.new()
	shooter.world = ShooterWorld.new()
	shooter.world.admit({"user_id": "u1", "display_name": "一号"}, 2)
	shooter.world.players.u1.life_state = "dead"
	shooter.world.players.u1.dead_at = 0
	shooter.world.advance(4000)
	shooter.world.request_respawn("u1")
	shooter.complete_asset_refresh("u1", "other_mode", {})
	check(shooter.world.players.u1.life_state == "dead", "shooter ignores unrelated game operation")
	shooter.complete_asset_refresh("u1", "respawn", {"owned": ["rifle", "smg"], "profiles": {"shooter": {"primary": "smg"}}})
	check(shooter.world.players.u1.life_state == "alive" and shooter.world.players.u1.weapon == "smg", "only shooter adapter interprets respawn operation")
	shooter.world.free()
	print("ASSET_CALLBACKS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL asset callbacks: ", label)
