extends "res://host/operator.gd"
const ResultOutbox = preload("res://sdk/roomkit/server/result_outbox.gd")
const ResultFormat = preload("res://sdk/roomkit/shared/result_format.gd")
const Schema = preload("res://sdk/roomkit/shared/schema_validator.gd")
## Production admission/RPC handlers with doubles; no service initialization,
## listener, helper or database. The ten-second timeout is real wall-clock time.
class FakeAccounts extends RefCounted:
	var lock := Mutex.new()
	var calls: Array = []
	var login_delay_ms := 0
	func execute(request: Dictionary, _deadline_ms: int = 0) -> Dictionary:
		var op := str(request.op)
		lock.lock()
		calls.append(op)
		lock.unlock()
		if op == "account.login":
			OS.delay_msec(login_delay_ms)
			return {"ok": true, "token": "a".repeat(64), "identity": {"user_id": "fake-player"}}
		return {"ok": true, "code": ""}
	func count(op: String = "") -> int:
		lock.lock()
		var result := calls.size() if op == "" else calls.count(op)
		lock.unlock()
		return result

class FakeBus extends RefCounted:
	var peers := {"host": {"authenticated": true}, "other": {"authenticated": true}}
	var replies: Dictionary = {}
	func respond(peer: String, id: String, result: Dictionary) -> void:
		if peers.get(peer, {}).get("authenticated", false):
			replies[id] = result.duplicate(true)

var passed := 0
var failed := 0
var fake = FakeAccounts.new()
var maintenance_calls := 0

func _initialize() -> void:
	accounts = fake
	bus = FakeBus.new()
	cleanup.start_attempt = _cleanup_attempt
	cleanup.on_finished = _cleanup_finished
	_run_tests.call_deferred()

func _process(_delta: float) -> bool:
	cleanup.poll(storage_maintenance)
	return false

func _maintenance(_request: Dictionary) -> Dictionary:
	maintenance_calls += 1
	await create_timer(0.05).timeout
	return {"ok": true, "backups": []}

func _audit(_actor: String, _action: String, _reason: String, _code: String, _target: String = "") -> void:
	pass

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func request(id: String, op := "account.register") -> void:
	await _rpc_request("host", id, "account.execute", {"op": op})

func settle() -> void:
	var end := Time.get_ticks_msec() + 2000
	while (not account_requests.is_empty() or not cleanup.idle()) and Time.get_ticks_msec() < end:
		await process_frame

func reset() -> void:
	check(account_requests.is_empty() and backup_waiters == 0 and worker_count == 0, "all request contexts, waiting slots and workers have been released")
	_end_storage_maintenance()
	fake = FakeAccounts.new()
	accounts = fake
	bus = FakeBus.new()
	player_tokens.clear()
	quitting = false

func _run_tests() -> void:
	check(BACKUP_WAIT_LIMIT_MS == 10000 and MAX_BACKUP_WAITERS == 64, "production wait deadline is 10 s with a 64-request budget")
	_begin_storage_maintenance("backup")
	var id := Wire.uid()
	request(id)
	await create_timer(0.04).timeout
	check(fake.count() == 0 and worker_count == 0 and backup_waiters == 1 and not bus.replies.has(id), "backup waits without executing the account request or taking a worker")
	_end_storage_maintenance()
	await settle()
	check(fake.count() == 1 and bus.replies[id].ok, "ending the backup executes the original request exactly once")
	reset()

	_begin_storage_maintenance("backup")
	for action in ["result.submit", "result.grant", "asset.execute"]:
		id = Wire.uid()
		await _rpc_request("host", id, action, {})
		check(bus.replies[id].code == "STORAGE_UNAVAILABLE" and worker_count == 0, action + " keeps its retryable storage refusal without executing during backup")
	var record := {"result_id": Wire.uid(), "match_id": "backup-test", "room_id": Wire.uid(), "launch_id": Wire.uid(), "game_id": "minimal_room", "build_id": "test", "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}
	var outbox := ResultOutbox.new()
	var work := ProjectSettings.globalize_path("res://data/backup-outbox-" + Wire.uid())
	check(outbox.initialize(work, "a".repeat(64)) and outbox.enqueue(record).ok, "a fake signed result is durably queued in a new test directory")
	var ack := {"result_id": record.result_id, "record_hash": ResultFormat.hash_record(record), "ok": false, "code": bus.replies[id].code}
	check(Schema.validate_file(ack, "res://schemas/result_ack.schema.json").is_empty(), "maintenance result ACK retains the existing wire contract")
	check(not outbox.acknowledge(ack) and outbox.pending().size() == 1, "backup refusal leaves the result pending instead of rejecting or losing it")
	reset()

	_begin_storage_maintenance("backup")
	id = Wire.uid()
	var start := Time.get_ticks_msec()
	await request(id)
	var elapsed := Time.get_ticks_msec() - start
	check(elapsed >= 10000 and elapsed < 11000 and bus.replies[id].code == "STORAGE_MAINTENANCE" and fake.count() == 0, "the real 10 s deadline returns maintenance without executing or replaying")
	_end_storage_maintenance()
	await create_timer(0.02).timeout
	check(fake.count() == 0, "a timed-out request never starts later when the backup finishes")
	reset()

	for kind in ["restore", "config"]:
		_begin_storage_maintenance(kind)
		id = Wire.uid()
		start = Time.get_ticks_msec()
		await request(id)
		check(bus.replies[id].code == "STORAGE_MAINTENANCE" and fake.count() == 0 and Time.get_ticks_msec() - start < 100, kind + " refuses immediately instead of queuing across a destructive operation")
		reset()

	_begin_storage_maintenance("backup")
	id = Wire.uid()
	request(id)
	_end_storage_maintenance()
	_begin_storage_maintenance("restore")
	_end_storage_maintenance()
	await settle()
	check(fake.count() == 0 and bus.replies[id].code == "STORAGE_MAINTENANCE", "a restore completed before the waiter wakes still invalidates the original backup epoch")
	reset()

	_begin_storage_maintenance("backup")
	id = Wire.uid()
	request(id)
	_host_event("other", "request.cancel", {"request_id": id})
	check(not account_requests[_account_context_key(bus, "host", id)].cancelled, "another peer cannot cancel this host's request")
	_host_event("host", "request.cancel", {"request_id": id})
	await settle()
	check(fake.count() == 0 and bus.replies[id].code == "CONTROL_UNAVAILABLE", "player cancellation observed before execution causes zero account calls")
	_host_event("host", "request.cancel", {"request_id": Wire.uid()})
	_host_event("host", "request.cancel", {"request_id": "invalid"})
	check(account_requests.is_empty(), "unknown or malformed cancellations create no stored tombstones")
	reset()

	for replace in [false, true]:
		_begin_storage_maintenance("backup")
		id = Wire.uid()
		var old_bus = bus
		request(id)
		if replace:
			bus = FakeBus.new()
		else:
			bus.peers.erase("host")
		await settle()
		check(fake.count() == 0 and not bus.replies.has(id), "host disconnect/replacement cancels the waiter without replying on the new connection")
		reset()

	_begin_storage_maintenance("backup")
	var ids: Array = []
	for index in MAX_BACKUP_WAITERS:
		id = Wire.uid()
		ids.append(id)
		request(id)
	var extra := Wire.uid()
	await request(extra)
	check(backup_waiters == MAX_BACKUP_WAITERS and bus.replies[extra].code == "RATE_LIMITED" and fake.count() == 0 and worker_count == 0, "the 65th waiter is refused without taking a worker or executing")
	for pending_id in ids:
		_host_event("host", "request.cancel", {"request_id": pending_id})
	await settle()
	check(backup_waiters == 0 and fake.count() == 0, "all 64 cancellations release their budgets and never execute")
	reset()

	# Exercise the real _backup drain/gate, substituting only the external helper.
	worker_count = 1
	_backup(true, "test")
	id = Wire.uid()
	request(id)
	await create_timer(0.02).timeout
	check(worker_count == 1 and maintenance_calls == 0 and backup_waiters == 1, "queued login adds no worker while the actual backup drains an existing worker")
	worker_count = 0
	await settle()
	check(maintenance_calls == 1 and fake.count() == 1 and bus.replies[id].ok, "the actual backup helper completes and releases one account execution")
	reset()

	fake.login_delay_ms = 100
	id = Wire.uid()
	request(id, "account.login")
	create_timer(0.02).timeout.connect(func(): _host_event("host", "request.cancel", {"request_id": id}))
	await settle()
	check(fake.count("account.login") == 1 and fake.count("session.logout") == 1 and player_tokens.is_empty(), "cancellation after login execution started never replays it and cleans the newly issued session")
	reset()
	quitting = true
	id = Wire.uid()
	await request(id)
	check(bus.replies[id].code == "STORAGE_MAINTENANCE" and fake.count() == 0, "shutdown refuses a new account operation without queuing it")
	print("OPERATOR_BACKUP_WAIT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
