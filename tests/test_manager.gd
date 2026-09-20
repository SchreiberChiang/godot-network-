extends RefCounted
## Lifecycle/authentication simulations; these do not prove child ENet binding.
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Fake = preload("res://tests/fakes/fake_launcher.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
var passed := 0
var failed := 0

func run() -> Dictionary:
	var fake = Fake.new()
	var manager = Manager.new()
	var initialized: Dictionary = manager.initialize({"udp_first": 28300, "udp_last": 28331}, fake)
	check(initialized.ok, "sim manager initialized")
	if not initialized.ok:
		return {"passed": passed, "failed": failed}
	check(Development.register_game(manager).ok, "sim game registered")
	var made: Dictionary = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 8})
	check(made.ok, "sim process created")
	var row: Dictionary = manager.rooms[made.room_id]
	var message: Dictionary = Protocol.event("room.register", row.room_id, row.launch_id, {"token": "0".repeat(64), "pid": row.pid}, row.game_id, row.build_id)
	var bad := connection(manager)
	manager._receive(bad, message)
	check(not row.registered and not manager.connections.has(bad), "sim wrong token rejected before registration")
	bad = connection(manager)
	message.payload.token = row.token
	message.launch_id = "f".repeat(32)
	manager._receive(bad, message)
	check(not row.registered and not manager.connections.has(bad), "sim correct token wrong launch rejected")
	bad = connection(manager)
	message.launch_id = row.launch_id
	message.payload.pid = row.pid + 1
	manager._receive(bad, message)
	check(not row.registered and not manager.connections.has(bad), "sim correct token wrong PID rejected")
	var valid := connection(manager)
	message.payload.pid = row.pid
	manager._receive(valid, message)
	check(row.registered and valid.room_id == row.room_id, "sim correct credentials bind exactly one connection")
	bad = connection(manager)
	manager._receive(bad, message)
	check(not manager.connections.has(bad) and manager.connections.has(valid), "sim registration replay cannot replace authenticated socket")
	manager._receive(valid, Protocol.event("room.ready", row.room_id, row.launch_id, {"udp_port": row.port}, row.game_id, row.build_id))
	check(row.state == "READY", "sim ready after registration")
	manager.stop_room(row.room_id)
	manager._receive(valid, Protocol.event("room.stopped", row.room_id, row.launch_id, {}, row.game_id, row.build_id))
	manager._cleanup(row)
	check(row.stop_notice and not row.cleaned and manager.ports.leases.has(row.launch_id), "sim stopped notice cannot release a living process")
	fake.set_state(row.launch_id, "unknown")
	row.cleanup_deadline = 0
	manager.poll()
	check(not row.cleaned and fake.terminate_calls.is_empty(), "sim unknown process identity is never killed or released")
	fake.crash(row.launch_id)
	manager.poll()
	check(row.cleaned and row.exit_confirmed and manager.ports.leases.is_empty(), "sim only confirmed exit permits reclaim")
	check(manager.close(), "sim manager closes after reclaim")
	return {"passed": passed, "failed": failed}

func connection(manager) -> Dictionary:
	var result := {"peer": StreamPeerTCP.new(), "transport": Transport.new(), "room_id": "", "accepted_at": Time.get_ticks_msec()}
	manager.connections.append(result)
	return result

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
