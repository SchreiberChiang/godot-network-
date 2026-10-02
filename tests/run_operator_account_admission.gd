extends "res://host/operator.gd"
## Production account RPC/admission with thread-safe doubles. Never calls the
## service's _initialize/_process: no listener, helper, database or host is started.
## Deadline cases shorten only the live test context, not production constants.
## Shutdown's late-success ordering is a separate suggested regression; this
## test deliberately does not invoke the real _shutdown or start any service.

class FakeAccounts extends RefCounted:
	var lock := Mutex.new()
	var calls: Array = []
	var login_delay_ms := 0
	var running := 0
	var peak_running := 0
	func execute(request: Dictionary, deadline_ms: int = 0) -> Dictionary:
		var op := str(request.get("op", ""))
		lock.lock()
		calls.append({"op": op, "deadline_ms": deadline_ms})
		running += 1
		peak_running = maxi(peak_running, running)
		var delay := login_delay_ms if op == "account.login" else 0
		lock.unlock()
		if delay > 0:
			OS.delay_msec(delay)
		var result := {"ok": true, "code": ""}
		if op == "account.login":
			var seed := str(request.get("username", "fake-player"))
			result.token = seed.sha256_text()
			result.identity = {"user_id": "fake-" + seed, "role": "player"}
		lock.lock()
		running -= 1
		lock.unlock()
		return result
	func count(op: String = "") -> int:
		lock.lock()
		var total := 0
		for call in calls:
			if op == "" or call.op == op:
				total += 1
		lock.unlock()
		return total
	func recorded_deadlines() -> Array:
		lock.lock()
		var values: Array = []
		for call in calls:
			values.append(int(call.deadline_ms))
		lock.unlock()
		return values
	func active() -> int:
		lock.lock()
		var total := running
		lock.unlock()
		return total
	func peak() -> int:
		lock.lock()
		var total := peak_running
		lock.unlock()
		return total

class FakeBus extends RefCounted:
	var peers := {"host": {"authenticated": true}, "other": {"authenticated": true}}
	var replies: Dictionary = {}
	func respond(peer: String, id: String, result: Dictionary) -> void:
		if peers.get(peer, {}).get("authenticated", false):
			replies[id] = result.duplicate(true)
	func close() -> void:
		peers.clear()

var passed := 0
var failed := 0
var fake = FakeAccounts.new()

func _initialize() -> void:
	accounts = fake
	bus = FakeBus.new()
	cleanup.start_attempt = _cleanup_attempt
	cleanup.on_finished = _cleanup_finished
	_run_tests.call_deferred()

func _process(_delta: float) -> bool:
	cleanup.poll(storage_maintenance)
	return false

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

func request(id: String, op := "account.rename") -> void:
	await _rpc_request("host", id, "account.execute", {"op": op, "username": id})

func context(id: String) -> Dictionary:
	return account_requests.get(_account_context_key(bus, "host", id), {})

func shorten(id: String, remaining_ms: int) -> void:
	var live := context(id)
	check(not live.is_empty(), "pending request exposes its own live context")
	if not live.is_empty():
		live.deadline_ms = Time.get_ticks_msec() + remaining_ms

func settle(timeout_ms := 2500) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while (not account_requests.is_empty() or not cleanup.idle() or fake.active() > 0) and Time.get_ticks_msec() < deadline:
		await process_frame

func reset() -> void:
	# Cancellation releases artificial-capacity waiters even if an assertion
	# failed; a test never leaves a coroutine to start against a later fake.
	for live in account_requests.values():
		live.cancelled = true
	await settle()
	check(account_requests.is_empty() and cleanup.idle() and fake.active() == 0 and backup_waiters == 0, "contexts, backup budgets, threads and cleanup have settled")
	worker_count = 0
	_end_storage_maintenance()
	quitting = false
	player_tokens.clear()
	fake = FakeAccounts.new()
	accounts = fake
	bus = FakeBus.new()
	cleanup = SessionCleanup.new()
	cleanup.start_attempt = _cleanup_attempt
	cleanup.on_finished = _cleanup_finished

func _run_tests() -> void:
	check(ACCOUNT_REQUEST_LIMIT_MS == 30000 and MAX_ACCOUNT_REQUESTS == 72, "account admission shares the existing 30 s budget and 72-context bound")
	check(has_method("_wait_for_account_worker"), "production account admission method is present")

	worker_count = 8
	var id := Wire.uid()
	var began := Time.get_ticks_msec()
	request(id)
	await create_timer(0.03).timeout
	var live := context(id)
	check(fake.count() == 0 and worker_count == 8 and account_requests.size() == 1 and not bus.replies.has(id), "eight busy worker slots queue the account without starting a ninth worker")
	check(int(live.get("deadline_ms", 0)) >= began + 30000 and int(live.get("deadline_ms", 0)) <= began + 30050 and int(live.get("epoch", -1)) == maintenance_epoch, "request context keeps an absolute original deadline and maintenance epoch")
	var original_deadline := int(live.get("deadline_ms", 0))
	worker_count = 7
	await settle()
	check(fake.count() == 1 and bus.replies.get(id, {}).get("ok", false) and worker_count == 7, "one released slot executes the original account once and returns its slot")
	check(fake.recorded_deadlines() == [original_deadline], "the original absolute deadline reaches the worker instead of restarting a full budget")
	await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	_host_event("other", "request.cancel", {"request_id": id})
	check(not context(id).get("cancelled", true), "another authenticated peer cannot cancel this queued account")
	_host_event("host", "request.cancel", {"request_id": id})
	await settle()
	check(fake.count() == 0 and bus.replies.get(id, {}).get("code", "") == "CONTROL_UNAVAILABLE", "cancellation while queued executes no account operation")
	await reset()

	for replace in [false, true]:
		worker_count = 8
		id = Wire.uid()
		request(id)
		var previous_bus = bus
		if replace:
			bus = FakeBus.new()
		else:
			bus.peers.erase("host")
		await settle()
		check(fake.count() == 0 and not previous_bus.replies.has(id) and not bus.replies.has(id), "queued request belongs only to its original host peer and bus")
		await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	quitting = true
	await settle()
	check(fake.count() == 0 and bus.replies.get(id, {}).get("code", "") == "STORAGE_MAINTENANCE", "shutdown refuses a queued account without executing it")
	await reset()

	for kind in ["restore", "config"]:
		worker_count = 8
		id = Wire.uid()
		request(id)
		_begin_storage_maintenance(kind)
		_end_storage_maintenance()
		await settle()
		check(fake.count() == 0 and bus.replies.get(id, {}).get("code", "") == "STORAGE_MAINTENANCE", kind + " invalidates a queued account even when the entire window falls between frames")
		await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	_begin_storage_maintenance("backup")
	await create_timer(0.03).timeout
	check(fake.count() == 0 and worker_count == 8 and backup_waiters == 1, "an observed backup window waits without adding a worker to the backup drain")
	_end_storage_maintenance()
	worker_count = 7
	await settle()
	check(fake.count() == 1 and bus.replies.get(id, {}).get("ok", false) and backup_waiters == 0, "the observed backup ends and releases exactly one original account operation")
	await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	_begin_storage_maintenance("backup")
	_end_storage_maintenance()
	await settle()
	check(fake.count() == 0 and bus.replies.get(id, {}).get("code", "") == "STORAGE_MAINTENANCE", "a missed maintenance epoch fails safely instead of executing after an unobserved window")
	await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	shorten(id, 50)
	await create_timer(0.09).timeout
	await settle()
	check(fake.count() == 0 and not bus.replies.get(id, {}).get("ok", true), "queue deadline expires without starting an account helper")
	worker_count = 7
	await create_timer(0.02).timeout
	check(fake.count() == 0, "expired queued work never starts later when capacity is freed")
	await reset()

	worker_count = 8
	id = Wire.uid()
	request(id)
	shorten(id, 50)
	_begin_storage_maintenance("backup")
	await create_timer(0.09).timeout
	await settle()
	check(fake.count() == 0 and backup_waiters == 0 and not bus.replies.get(id, {}).get("ok", true), "backup waiting consumes the shortened original request budget")
	_end_storage_maintenance()
	await create_timer(0.02).timeout
	check(fake.count() == 0, "ending backup cannot revive a request whose original deadline expired")
	await reset()

	# Eight real worker threads remain active while 64 more account contexts wait.
	# Additional contexts are refused; cancellation never cancels those threads.
	fake.login_delay_ms = 500
	var active_ids: Array = []
	for index in 8:
		id = Wire.uid()
		active_ids.append(id)
		request(id, "account.login")
	var waiting_ids: Array = []
	for index in 64:
		id = Wire.uid()
		waiting_ids.append(id)
		request(id)
	var extra := Wire.uid()
	await request(extra)
	check(worker_count == 8 and account_requests.size() == 72 and fake.peak() <= 8, "eight executing accounts and 64 waiters fit the production context budget without extra worker threads")
	check(bus.replies.get(extra, {}).get("code", "") == "RATE_LIMITED", "the 73rd context is refused before execution")
	for waiting_id in waiting_ids:
		_host_event("host", "request.cancel", {"request_id": waiting_id})
	await settle()
	check(fake.count("account.login") == 8 and fake.count("account.rename") == 0 and account_requests.is_empty() and worker_count == 0, "all 64 cancellations free their budgets while each of the eight started logins executes once")
	check(active_ids.all(func(active_id): return bus.replies.get(active_id, {}).get("ok", false)), "original in-flight logins still return their successful result")
	await reset()

	fake.login_delay_ms = 100
	id = Wire.uid()
	request(id, "account.login")
	create_timer(0.02).timeout.connect(func(): _host_event("host", "request.cancel", {"request_id": id}))
	await settle()
	check(fake.count("account.login") == 1 and fake.count("session.logout") == 1 and player_tokens.is_empty(), "cancellation after execution starts cleans the issued token once without replaying login")
	await reset()

	print("OPERATOR_ACCOUNT_ADMISSION_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
