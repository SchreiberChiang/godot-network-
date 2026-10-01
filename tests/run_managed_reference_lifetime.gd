extends SceneTree
## No children, database or listeners. Real RefCounted objects prove that a
## closed manager releases its lobby callback and result-service back reference.
const Manager = preload("res://host/core/room_manager.gd")
const Lobby = preload("res://host/lobby_server.gd")
const Results = preload("res://host/core/remote_results.gd")
class ReplyBus extends RefCounted:
	func request(_method: String, _payload: Dictionary) -> Dictionary:
		return {"ok": true, "code": ""}

class AckTarget extends RefCounted:
	var acks: Array = []
	func send_control(room: String, kind: String, payload: Dictionary) -> void:
		acks.append({"room": room, "kind": kind, "payload": payload})
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _initialize() -> void:
	var manager = Manager.new()
	var lobby = Lobby.new()
	lobby.manager = manager
	manager.control_handler = Callable(lobby, "_control")
	var lobby_ref: WeakRef = weakref(lobby)
	manager.rooms["active"] = {"cleaned": false}
	check(not manager.close(), "active manager refuses close")
	check(manager.control_handler.is_valid(), "failed close retains control callback")
	manager.rooms.clear()
	check(manager.close(), "idle manager closes")
	lobby = null
	check(lobby_ref.get_ref() == null, "closed manager no longer retains lobby")
	# Explicitly clean the old-code comparison's failed case too.
	manager.control_handler = Callable()
	manager = null

	manager = Manager.new()
	var results = Results.new()
	results.configure(null, manager, {"rpc": {}, "result_root": "", "result_schemas": {}})
	manager.result_service = results
	results.pending["unfinished"] = true
	check(not manager.close(), "pending result prevents close")
	results.pending.clear()
	check(manager.close(), "manager closes after result completes")
	var manager_ref: WeakRef = weakref(manager)
	var results_ref: WeakRef = weakref(results)
	manager = null
	results = null
	check(manager_ref.get_ref() == null and results_ref.get_ref() == null,
		"result service does not keep closed manager and repository alive")
	# Break the baseline cycle after recording the failed assertion.
	var survivor = manager_ref.get_ref()
	if survivor != null:
		survivor.result_service = null
	survivor = null

	results = Results.new()
	var target = AckTarget.new()
	results.configure(ReplyBus.new(), target, {"rpc": {}, "result_root": "", "result_schemas": {}})
	results.pending["hash"] = true
	await results._submit("room", "result", "hash", {})
	check(results.pending.is_empty() and target.acks.size() == 1 and
		target.acks[0].kind == "result.ack" and target.acks[0].payload.ok,
		"live manager receives the original result ACK once")
	target = null
	results.pending["late"] = true
	await results._submit("room", "result", "late", {})
	check(results.pending.is_empty(), "late result completes safely after manager is released")
	results = null
	print("MANAGED_REFERENCE_TEST_RESULT passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
