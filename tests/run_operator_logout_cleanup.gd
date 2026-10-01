extends "res://host/operator.gd"
## The Operator's handling of player logouts with test doubles only (formalises
## Codex's review probe logs/codex-l3-checkpoint/original_logout_probe.gd, whose original
## failures stay in data/codex-l3-logout-review-*/). Never calls super
## _initialize: no listener, helper, database or host is started. Covers the
## production RPC path and the host-exit path: capacity refusal then success,
## storage failures then success, retries used up (responsibility kept), a slow
## attempt answered LOGOUT_PENDING, an answer lost after the commit, repeated
## triggers, storage maintenance, an old token cleaned after a new login, and
## the host exit. Each case would fail against the old handler, which dropped
## the token on any logout reply.
## Usage (tools/run_isolated_test.ps1 requires the service arguments):
##   --data-root=<isolation>/data --games=... --public-client-dir=... --panel-port=...
class FakeAccounts extends RefCounted:
	var lock := Mutex.new()
	var replies: Array = []        # consumed in order; the last one repeats
	var delay_ms := 0
	var calls: Array = []          # tokens passed to session.logout
	var committed: Dictionary = {}
	func execute(request: Dictionary) -> Dictionary:
		lock.lock()
		calls.append(str(request.get("token", "")))
		var reply: Dictionary = replies[0] if replies.size() == 1 else replies.pop_front()
		var wait := int(reply.get("delay", delay_ms))
		lock.unlock()
		if reply.get("commit", false):
			lock.lock()
			committed[str(request.get("token", ""))] = true
			lock.unlock()
		if wait > 0:
			OS.delay_msec(wait)
		lock.lock()
		var answer := reply.duplicate(true)
		answer.erase("commit")
		answer.erase("delay")
		if answer.get("after_commit", false) and committed.has(str(request.get("token", ""))):
			answer = {"ok": false, "code": "AUTH_FAILED"}
		answer.erase("after_commit")
		lock.unlock()
		return answer
	func count() -> int:
		lock.lock()
		var n := calls.size()
		lock.unlock()
		return n

class FakeBus extends RefCounted:
	var replies: Dictionary = {}
	var peers: Dictionary = {"host": {"authenticated": true}}
	func respond(_peer: String, id: String, result: Dictionary) -> void:
		if peers.get(_peer, {}).get("authenticated", false):
			replies[id] = result.duplicate(true)
	func close() -> void:
		peers.clear()
	func poll() -> void:
		pass

var test_passed := 0
var test_failed := 0
var fake

func _initialize() -> void:
	var data_root := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-root="):
			data_root = argument.trim_prefix("--data-root=").replace("\\", "/")
	if data_root == "" or not data_root.to_lower().begins_with(Paths.absolute("res://data").replace("\\", "/").to_lower() + "/"):
		print("REFUSED run_operator_logout_cleanup: --data-root inside res://data is required")
		quit(64)
		return
	root_path = data_root
	DirAccess.make_dir_recursive_absolute(root_path)
	# The clean-up member is looked up by name so the same file also runs against
	# the old Operator (without it) and shows its failures.
	if _c() != null:
		_c().start_attempt = Callable(self, "_cleanup_attempt")
		_c().on_finished = Callable(self, "_cleanup_finished")
	else:
		print("INFO this Operator has no session clean-up (old handler)")
	bus = FakeBus.new()
	_exercise.call_deferred()

func _process(_delta: float) -> bool:
	if _c() != null:
		_c().poll(storage_maintenance)
	return false

func _c():
	return get("cleanup")

func _status() -> Dictionary:
	return _c().status() if _c() != null else {"failed": 0, "failed_jobs": [{"attempts": 0}]}

func _events() -> Array:
	return _c().events if _c() != null else []

func check(value: bool, text: String) -> void:
	if value:
		test_passed += 1
		print("PASS ", text)
	else:
		test_failed += 1
		print("FAIL ", text)

func setup(replies: Array, delay := 0) -> void:
	fake = FakeAccounts.new()
	fake.replies = replies
	fake.delay_ms = delay
	accounts = fake
	worker_count = 0
	storage_maintenance = false

func key(seed: String) -> String:
	return seed.sha256_text()

func logout(id: String, token: String) -> Dictionary:
	await _rpc_request("host", id, "account.execute", {"op": "session.logout", "token": token, "reason": "explicit"})
	return bus.replies.get(id, {})

func settle(timeout_ms := 15000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while _c() != null and not _c().idle() and Time.get_ticks_msec() < deadline:
		await process_frame

func _exercise() -> void:
	var t := key("one")

	setup([{"ok": true, "code": ""}])
	player_tokens[t] = "player-1"
	worker_count = 8  # every worker busy: the first attempt is refused (RATE_LIMITED)
	var release := func(): worker_count = 0
	create_timer(0.3).timeout.connect(release)
	var reply: Dictionary = await logout("capacity", t)
	check(reply.get("ok", false) and fake.count() == 1 and not player_tokens.has(t), "capacity refusal, then the retry logs out; the token is released only after the confirmation")

	setup([{"ok": false, "code": "STORAGE_UNAVAILABLE"}, {"ok": false, "code": "STORAGE_UNAVAILABLE"}, {"ok": true, "code": ""}])
	player_tokens[t] = "player-1"
	reply = await logout("storage", t)
	check(reply.get("ok", false) and fake.count() == 3 and not player_tokens.has(t), "two storage failures, then success on the third attempt")

	setup([{"ok": false, "code": "STORAGE_UNAVAILABLE"}])
	player_tokens[t] = "player-1"
	reply = await logout("exhausted", t)
	check(not reply.get("ok", true) and reply.get("code", "") == "STORAGE_UNAVAILABLE" and fake.count() == 3, "storage failure on every attempt: the host is told the failure after 3 attempts, not success")
	check(player_tokens.has(t) and _status().failed == 1 and _status().failed_jobs[0].attempts == 3, "the failed clean-up keeps the token's responsibility and stays listed")
	if _c() != null:
		_c().cancel_all("test reset")
	player_tokens.clear()

	setup([{"ok": true, "code": ""}], 9000)
	player_tokens[t] = "player-1"
	reply = await logout("slow", t)
	check(reply.get("code", "") == "LOGOUT_PENDING" and str(reply.get("payload", {}).get("job_id", "")) != "" and player_tokens.has(t), "an attempt still running after 8 s: the host is told LOGOUT_PENDING and the token stays owned")
	await settle()
	check(not player_tokens.has(t) and fake.count() == 1, "the slow attempt then confirms and the token is released")

	setup([{"ok": true, "code": "", "commit": true, "delay": 11000}, {"ok": true, "code": "", "after_commit": true}])
	player_tokens[t] = "player-1"
	reply = await logout("lost", t)
	check(reply.get("code", "") == "LOGOUT_PENDING", "a logout whose answer does not come within 10 s is not reported as done")
	await settle(20000)
	check(not player_tokens.has(t) and fake.count() == 2 and _events().any(func(line): return line.contains("event=invalid")), "answer lost after the commit: the retry finds the old token already invalid and the job ends")

	setup([{"ok": true, "code": ""}], 600)
	player_tokens[t] = "player-1"
	_rpc_request("host", "dup-1", "account.execute", {"op": "session.logout", "token": t, "reason": "explicit"})
	await logout("dup-2", t)
	await settle()
	check(fake.count() == 1 and bus.replies.get("dup-1", {}).get("ok", false) and bus.replies.get("dup-2", {}).get("ok", false), "two triggers for one token make one logout; both callers get the result")

	setup([{"ok": true, "code": ""}])
	player_tokens[t] = "player-1"
	storage_maintenance = true
	var finish_maintenance := func(): storage_maintenance = false
	create_timer(1.0).timeout.connect(finish_maintenance)
	reply = await logout("maintenance", t)
	check(reply.get("ok", false) and fake.count() == 1 and not player_tokens.has(t), "a logout during storage maintenance is queued (not refused) and runs afterwards")

	var old := key("old")
	var fresh := key("new")
	setup([{"ok": false, "code": "AUTH_FAILED"}])
	player_tokens[old] = "player-1"
	player_tokens[fresh] = "player-1"
	reply = await logout("old-token", old)
	check(fake.calls == [old] and player_tokens.has(fresh) and not player_tokens.has(old), "an old token cleaned after a new login: only the old token is touched, the new one stays")
	player_tokens.clear()

	# The account helper may finish after the requesting host has disappeared.
	# Its successful login must not be handed to a replacement host or left live.
	var late_token := key("late-login")
	setup([{"ok": true, "token": late_token, "identity": {"user_id": "player-1"}, "delay": 100}, {"ok": true, "code": ""}])
	var previous_bus = bus
	var replace_host := func():
		previous_bus.close()
		bus = FakeBus.new()
	create_timer(0.05).timeout.connect(replace_host)
	await _rpc_request("host", "late-login", "account.execute", {"op": "account.login"})
	await settle()
	check(fake.calls == ["", late_token] and not player_tokens.has(late_token) and bus.replies.is_empty() and not previous_bus.replies.has("late-login"), "login finishes after host replacement: its token is cleaned and no reply reaches the new host")

	setup([{"ok": true, "token": late_token, "identity": {"user_id": "player-1"}, "delay": 100}, {"ok": true, "code": ""}])
	var dropped_bus = bus
	create_timer(0.05).timeout.connect(func(): dropped_bus.close())
	await _rpc_request("host", "dropped-login", "account.execute", {"op": "account.login"})
	await settle()
	check(fake.calls == ["", late_token] and not player_tokens.has(late_token) and bus.replies.is_empty(), "login finishes after its control peer disappears: the issued token is still cleaned")
	bus = FakeBus.new()

	setup([{"ok": true, "code": ""}])
	var first := key("p1")
	var second := key("p2")
	player_tokens[first] = "player-1"
	player_tokens[second] = "player-2"
	requested_stop = true
	host_closing = true
	await _host_exited()
	await settle()
	check(player_tokens.is_empty() and fake.count() == 2 and _events().filter(func(line): return line.contains("reason=host_exit") and line.contains("event=done")).size() == 2, "host exit: the Operator takes over every token it holds and confirms each")

	var text := "\n".join(_events()) + JSON.stringify(bus.replies) + JSON.stringify(_status())
	check(not text.contains(t) and not text.contains(old) and not text.contains(fresh) and not text.contains(first), "no token in the clean-up log lines, the replies or the status")
	print("OPERATOR_LOGOUT_CLEANUP_RESULT passed=", test_passed, " failed=", test_failed)
	quit(0 if test_failed == 0 else 1)
