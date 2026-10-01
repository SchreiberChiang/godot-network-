extends SceneTree
## Real authenticated loopback TCP/RPC with no Operator, database or processes.
const RPC = preload("res://sdk/roomkit/shared/local_rpc.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var server = RPC.new()
var caller = RPC.new()
var requests: Array = []
var cancellations: Array = []
var cancel_now := false
var passed := 0
var failed := 0

func _initialize() -> void:
	server.requested.connect(_requested)
	server.peer_event.connect(_event)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	server.poll()
	caller.poll()
	return false

func pause(ms: int) -> void:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await process_frame

func _requested(peer: String, id: String, action: String, _payload: Dictionary) -> void:
	requests.append({"peer": peer, "id": id, "action": action})
	if action == "late":
		await pause(100)
		server.respond(peer, id, {"ok": true, "token": "a".repeat(64)})
	elif action == "normal":
		server.respond(peer, id, {"ok": true})

func _event(peer: String, action: String, payload: Dictionary) -> void:
	if action != "request.cancel":
		return
	cancellations.append(payload.request_id)
	for request in requests:
		if request.id == payload.request_id and request.peer == peer and request.action == "waiting":
			server.respond(peer, request.id, Wire.failure("CONTROL_UNAVAILABLE"))

func _cancel_later() -> void:
	await pause(40)
	cancel_now = true

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	var launch := Wire.uid()
	var secret := "0".repeat(64)
	check(server.listen(secret, launch) == OK, "loopback listener binds an OS-assigned port")
	check(caller.connect_to(server.port, secret, launch) == OK, "client connects using the exact launch credentials")
	var end := Time.get_ticks_msec() + 3000
	while not caller.ready() and Time.get_ticks_msec() < end:
		await process_frame
	check(caller.ready(), "real TCP peers complete authenticated RPC handshake")
	cancel_now = true
	var result: Dictionary = await caller.request("waiting", {}, 2000, "", func(): return cancel_now)
	await pause(20)
	check(result.code == "CONTROL_UNAVAILABLE" and requests.is_empty() and caller.pending.is_empty(), "cancellation before sending produces no server-side request")

	cancel_now = false
	_cancel_later()
	result = await caller.request("waiting", {}, 2000, "", func(): return cancel_now)
	check(result.code == "CONTROL_UNAVAILABLE" and requests.size() == 1 and cancellations == [requests[0].id], "one cancellation event targets the original internal request over real TCP")
	check(caller.pending.is_empty(), "cancelled request consumes the original response and releases pending state")

	cancel_now = false
	_cancel_later()
	result = await caller.request("late", {}, 2000, "", func(): return cancel_now)
	check(result.ok and result.token == "a".repeat(64) and requests.size() == 2 and cancellations.size() == 2, "if execution already began, its original successful login result is retained for late-session cleanup")
	await pause(30)
	check(cancellations.size() == 2 and caller.pending.is_empty(), "continuing cancellation sends neither duplicates nor a replacement request")
	result = await caller.request("normal", {})
	check(result.ok and requests.size() == 3 and cancellations.size() == 2, "ordinary RPC without a cancellation callback preserves its original behavior")
	caller.close()
	server.close()
	check(caller.peers.is_empty() and server.peers.is_empty(), "all test TCP peers close normally")
	print("LOCAL_RPC_CANCEL_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
