extends RefCounted
## Lifecycle/authentication simulations; these do not prove child ENet binding.
const Manager = preload("res://host/core/room_manager.gd")
const Development = preload("res://host/development.gd")
const Fake = preload("res://tests/fakes/fake_launcher.gd")
const Transport = preload("res://sdk/roomkit/shared/control_transport.gd")
const Protocol = preload("res://sdk/roomkit/shared/protocol.gd")
var passed := 0
var failed := 0

class PendingResults extends RefCounted:
	var pending := true
	func busy() -> bool:
		return pending
	func prepare_launch(_row: Dictionary) -> Dictionary:
		return {"ok": true, "config": {}}

class PendingRecovery extends RefCounted:
	var healthy := true
	var pending := true
	func idle() -> bool:
		return not pending
	func reserve(_launch: String, _port: int) -> bool:
		return true
	func confirm(_launch: String, _record: Dictionary) -> bool:
		return true
	func release(_launch: String) -> void:
		pass

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
	_capacity_while_background_busy(manager, fake)
	check(manager.close(), "sim manager closes after reclaim")
	return {"passed": passed, "failed": failed}

func _capacity_while_background_busy(manager, fake) -> void:
	manager.config.max_rooms = 2
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/game_manifest.json"))
	manifest.game_id = "capacity_fixture"
	manifest.sdk_version = "0.5.0"
	var registered: Dictionary = manager.registry.register_game(manifest, {manifest.server_artifact: {"executable": OS.get_executable_path(), "args": []}})
	check(registered.ok, "sim capacity fixture supports managed result service")
	var options := {"mode": "sandbox", "map": "empty", "capacity": 8}
	var first: Dictionary = manager.create_room("capacity_fixture", options)
	check(first.ok, "sim first room starts with max_rooms two and cleaned history")
	if not first.ok:
		return
	var row: Dictionary = manager.rooms[first.room_id]
	var peer := connection(manager)
	manager._receive(peer, Protocol.event("room.register", row.room_id, row.launch_id, {"token": row.token, "pid": row.pid}, row.game_id, row.build_id))
	manager._receive(peer, Protocol.event("room.ready", row.room_id, row.launch_id, {"udp_port": row.port}, row.game_id, row.build_id))
	check(row.state == "READY", "sim capacity fixture reaches ready")
	var results := PendingResults.new()
	var recovery := PendingRecovery.new()
	manager.result_service = results
	manager.recovery_guard = recovery
	# A held worker proves stop still waits for background work without calling
	# OS process inspection or depending on a timing race in a short-lived thread.
	var gate := Semaphore.new()
	var worker := Thread.new()
	var started := worker.start(func(): gate.wait(); return {"state": "unknown"})
	check(started == OK, "sim controlled background worker starts")
	if started == OK:
		manager.resource_worker = worker
	check(manager.active_count() == 4, "sim shutdown workload includes room and three background services")
	var second: Dictionary = manager.create_room("capacity_fixture", options)
	check(second.ok, "sim busy result recovery and metrics work do not consume second room slot")
	var before: int = manager.rooms.size()
	var overflow: Dictionary = manager.create_room("capacity_fixture", options)
	check(second.ok and not overflow.ok and overflow.code == "HOST_CAPACITY_EXCEEDED" and manager.rooms.size() == before, "sim actual two room limit rejects a third without allocation")
	manager.stop_all()
	var draining: Dictionary = manager.create_room("capacity_fixture", options)
	check(second.ok and not draining.ok and draining.code == "HOST_CAPACITY_EXCEEDED", "sim stopping rooms keep slots until confirmed cleanup")
	for pending_row in manager.rooms.values():
		if not pending_row.cleaned:
			fake.crash(pending_row.launch_id)
			manager._cleanup(pending_row)
	check(manager.ports.leases.is_empty() and manager.active_count() == 3, "sim reclaimed rooms leave three background tasks pending")
	check(not manager.close() and manager.server.is_listening(), "sim close waits after all rooms exit while background work remains")
	results.pending = false
	check(manager.active_count() == 2 and not manager.close(), "sim close still waits for recovery and metrics after results finish")
	recovery.pending = false
	check(manager.active_count() == 1 and not manager.close(), "sim close still waits for metrics after recovery finishes")
	if started == OK:
		gate.post()
		worker.wait_to_finish()
		manager.resource_worker = null
	check(manager.active_count() == 0 and manager.close(), "sim close succeeds only after the final background worker is reclaimed")

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
