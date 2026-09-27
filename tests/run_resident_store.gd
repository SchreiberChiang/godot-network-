extends SceneTree
## Resident storage worker (host/storage/resident_store.gd, tools/storage_worker.ps1)
## against real SQLite: parity with the one-shot path, one worker per database, no
## request files, mixed old/new concurrency, helper errors, timeout and crash
## fallback without double debits, queue limit, idle exit, mode switch, shutdown,
## session.authenticate parity and handle release.
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Accounts = preload("res://host/core/account_service.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const SPACE := "shooter"
const PASSWORD := "resident-test-password"
var passed := 0
var failed := 0
var directory := ""
var repository = Repository.new()
var store: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-resident-store-" + Wire.uid())
	print("RESIDENT_STORE_EVIDENCE_DIR=", directory)
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	check(Resident.enabled(), "resident mode is the default on the verified engine")
	if not check(repository.initialize(directory, "assets.sqlite").ok, "asset database initializes"):
		finish()
		return
	var handles_before := _handle_count()
	store = Resident.for_database("sqlite_store.ps1", repository.database, 10000)
	check(repository.prewarm().ok and store.worker_pid() > 0 and store.started_workers == 1, "prewarm starts exactly one worker")
	_parity()
	_one_worker_per_database()
	_no_request_files()
	await _concurrency()
	_helper_error_keeps_worker()
	await _timeout_and_crash()
	_queue_limit()
	await _idle_exit()
	_mode_switch_and_shutdown()
	_accounts()
	Resident.shutdown_all()
	check(_worker_processes() == 0, "no storage worker for this test directory remains after shutdown_all")
	var handles_after := _handle_count()
	check(handles_before > 0 and handles_after - handles_before <= 12, "worker restarts release their process handles (%d -> %d)" % [handles_before, handles_after])
	finish()

func _parity() -> void:
	var resident := _sequence("parity-resident", func(request): return repository.execute(request))
	var oneshot := _sequence("parity-oneshot", func(request): return repository.execute_oneshot(request))
	check(resident.size() == oneshot.size() and resident == oneshot, "resident and one-shot replies are identical for the same operation sequence")
	for index in resident.size():
		if resident[index] != oneshot[index]:
			printerr("  step ", index, " resident=", resident[index], " oneshot=", oneshot[index])

func _sequence(user: String, send: Callable) -> Array:
	# Same content for both users so replies can be compared exactly.
	var replies: Array = []
	var body := Format.canonical({"revision": 1, "credits": 5, "experience": 0, "owned": ["rifle"], "profiles": {}})
	replies.append(send.call({"op": "asset.read", "user_id": user, "space_id": SPACE}))
	replies.append(send.call({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1"}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1"}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "other", "actor_id": "test", "command": "{}", "expected_revision": 1, "body": body}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "other", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r2", "fingerprint": "f2", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.read", "user_id": user, "space_id": SPACE}))
	return replies

func _one_worker_per_database() -> void:
	var second = Repository.new()
	second.root = repository.root
	second.database = repository.database
	check(second.execute({"op": "asset.read", "user_id": "shared", "space_id": SPACE}).ok, "a second repository instance on the same database works")
	check(Resident.for_database("sqlite_store.ps1", repository.database, 10000) == store and store.started_workers == 1, "both instances share the single worker")
	check(_worker_processes() == 1, "exactly one storage worker process serves this database")

func _no_request_files() -> void:
	var seen := {}
	var thread := Thread.new()
	thread.start(_files_worker)
	while thread.is_alive():
		for name in DirAccess.get_files_at(directory):
			if name.begins_with("request-") or name.begins_with("helper-"):
				seen[name.get_slice("-", 0)] = true
		OS.delay_msec(1)
	thread.wait_to_finish()
	check(seen.is_empty(), "resident reads and snapshots create no request or helper files: " + str(seen.keys()))

func _files_worker() -> void:
	for index in 20:
		repository.execute({"op": "asset.read", "user_id": "files", "space_id": SPACE})
		repository.execute({"op": "asset.snapshot", "user_id": "files", "space_id": SPACE, "request_id": "x%d" % index, "fingerprint": "f"})

func _concurrency() -> void:
	# Four resident and four one-shot writers on the same database at once.
	var threads: Array = []
	for index in 8:
		var thread := Thread.new()
		thread.start(_commit_cycles.bind("mixed-%d" % index, 3, index % 2 == 1))
		threads.append(thread)
	var ok := true
	for thread in threads:
		while thread.is_alive():
			await process_frame
		ok = thread.wait_to_finish() and ok
	var chains := true
	for index in 8:
		chains = chains and _revision("mixed-%d" % index) == 3
	check(ok and chains, "mixed resident and one-shot writers all commit; every user has exactly 3 revisions")
	# Same request from six threads: exactly one fresh commit.
	var results: Array = []
	threads.clear()
	var body := Format.canonical({"revision": 1, "credits": 1, "experience": 0, "owned": [], "profiles": {}})
	var request := {"op": "asset.commit", "user_id": "same", "space_id": SPACE, "request_id": "same-1", "fingerprint": "same", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}
	for index in 6:
		var thread := Thread.new()
		thread.start(func(): return repository.execute(request) if index % 2 == 0 else repository.execute_oneshot(request))
		threads.append(thread)
	for thread in threads:
		while thread.is_alive():
			await process_frame
		results.append(thread.wait_to_finish())
	var fresh := results.filter(func(r): return r.ok and r.get("code", "") == "").size()
	var duplicate := results.filter(func(r): return r.ok and r.get("code", "") == "DUPLICATE").size()
	check(fresh == 1 and duplicate == 5 and _revision("same") == 1, "six concurrent copies across both paths: one commit, five receipts (%d/%d)" % [fresh, duplicate])

func _commit_cycles(user: String, cycles: int, oneshot: bool) -> bool:
	for index in cycles:
		var snapshot: Dictionary = _send({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "c%d" % index, "fingerprint": "f%d" % index}, oneshot)
		if not snapshot.get("ok", false):
			return false
		var state: Dictionary = {"revision": 0, "credits": 0} if str(snapshot.body) == "" else JSON.parse_string(str(snapshot.body))
		var body := Format.canonical({"revision": int(state.revision) + 1, "credits": int(state.credits) + 1, "experience": 0, "owned": [], "profiles": {}})
		var commit: Dictionary = _send({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "c%d" % index, "fingerprint": "f%d" % index, "actor_id": "test", "command": "{}", "expected_revision": int(state.revision), "body": body}, oneshot)
		if not commit.get("ok", false):
			return false
	return true

func _send(request: Dictionary, oneshot: bool) -> Dictionary:
	return repository.execute_oneshot(request) if oneshot else repository.execute(request)

func _helper_error_keeps_worker() -> void:
	var pid: int = store.worker_pid()
	var bad: Dictionary = repository.execute({"op": "asset.commit", "user_id": "bad", "space_id": SPACE, "request_id": "bad", "fingerprint": "bad", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": "not json"})
	check(not bad.ok and bad.code == "STORAGE_UNAVAILABLE", "helper failure inside the worker returns the same STORAGE_UNAVAILABLE as the one-shot path")
	check(store.worker_pid() == pid and repository.execute({"op": "asset.read", "user_id": "bad", "space_id": SPACE}).ok, "the worker survives the helper's exit path and keeps serving")

func _timeout_and_crash() -> void:
	# Timeout: the guard kills the worker, the commit is repeated once one-shot.
	var before_fallbacks: int = store.fallbacks
	var before_timeouts: int = store.timeouts
	var started: int = store.started_workers
	store.timeout_ms = 1
	var result := _commit_once("timeout-user", "t1")
	store.timeout_ms = 10000
	check(result.ok and result.get("code", "") in ["", "DUPLICATE"] and _revision("timeout-user") == 1, "timed-out commit completes exactly once through the fallback (%s)" % result.get("code", ""))
	check(store.timeouts == before_timeouts + 1 and store.fallbacks == before_fallbacks + 1, "timeout and fallback are counted")
	check(repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE}).ok and store.started_workers == started + 1, "next request starts a fresh worker")
	# Crash while idle: the entry is gone, the next request restarts transparently.
	started = store.started_workers
	OS.kill(store.worker_pid())
	check(repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE}).ok and store.started_workers == started + 1, "a killed idle worker is replaced on the next request")
	# Crash during a commit: result is either committed or repeated as DUPLICATE, never twice.
	var thread := Thread.new()
	thread.start(_commit_once.bind("crash-user", "k1"))
	OS.delay_msec(4)
	var pid: int = store.worker_pid()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	while thread.is_alive():
		await process_frame
	var crashed: Dictionary = thread.wait_to_finish()
	check(crashed.ok and _revision("crash-user") == 1, "commit interrupted by a worker crash lands exactly once (%s)" % crashed.get("code", ""))

func _commit_once(user: String, request_id: String) -> Dictionary:
	var body := Format.canonical({"revision": 1, "credits": 7, "experience": 0, "owned": [], "profiles": {}})
	return repository.execute({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": request_id, "fingerprint": request_id, "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body})

func _queue_limit() -> void:
	store.queue_limit = 0
	var refused: Dictionary = repository.execute({"op": "asset.read", "user_id": "queue", "space_id": SPACE})
	store.queue_limit = Resident.QUEUE_LIMIT
	check(not refused.ok and refused.code == "STORAGE_UNAVAILABLE", "a full queue refuses with STORAGE_UNAVAILABLE instead of waiting")

func _idle_exit() -> void:
	var other = Repository.new()
	check(other.initialize(directory.path_join("idle"), "assets.sqlite").ok, "second database initializes")
	var idle_store: RefCounted = Resident.for_database("sqlite_store.ps1", other.database, 10000)
	idle_store.idle_seconds = 2
	check(other.prewarm().ok and idle_store.started_workers == 1, "second database gets its own worker")
	var pid: int = idle_store.worker_pid()
	var until := Time.get_ticks_msec() + 8000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < until:
		await process_frame
	check(not OS.is_process_running(pid), "an idle worker exits by itself")
	check(other.execute({"op": "asset.read", "user_id": "idle", "space_id": SPACE}).ok and idle_store.started_workers == 2, "the next request restarts it")

func _mode_switch_and_shutdown() -> void:
	OS.set_environment("ROOMKIT_STORAGE_MODE", "oneshot")
	var seen := false
	var thread := Thread.new()
	thread.start(func(): return repository.execute({"op": "asset.read", "user_id": "mode", "space_id": SPACE}))
	while thread.is_alive():
		for name in DirAccess.get_files_at(directory):
			seen = seen or name.begins_with("request-")
		OS.delay_msec(1)
	var reply: Dictionary = thread.wait_to_finish()
	check(not Resident.enabled() and reply.ok and seen, "ROOMKIT_STORAGE_MODE=oneshot uses the one-shot helper")
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	Resident.shutdown_all()
	check(store.worker_pid() == -1, "shutdown_all stops the worker")
	var started: int = store.started_workers
	check(repository.execute({"op": "asset.read", "user_id": "mode", "space_id": SPACE}).ok and store.started_workers == started + 1, "the resident path restarts after shutdown")

func _accounts() -> void:
	var accounts = Accounts.new()
	if not check(accounts.initialize(directory).ok, "account database initializes"):
		return
	check(accounts.execute({"op": "setup.admin", "username": "operator", "password": PASSWORD, "display_name": "admin"}).ok, "administrator created (one-shot path)")
	var login: Dictionary = accounts.execute({"op": "account.login", "username": "operator", "password": PASSWORD, "client_ip": "127.0.0.1"})
	check(login.ok, "login stays on the one-shot path and succeeds")
	var resident: Dictionary = accounts.authenticate(login.get("token", ""))
	var account_store: RefCounted = Resident.for_database("account_store.ps1", accounts.database, 10000)
	check(resident.ok and resident.identity.role == "admin" and account_store.started_workers == 1, "session.authenticate is served by the account worker")
	check(account_store.worker_pid() != store.worker_pid() and account_store.worker_pid() > 0, "account and asset databases use separate workers")
	OS.set_environment("ROOMKIT_STORAGE_MODE", "oneshot")
	var oneshot: Dictionary = accounts.authenticate(login.get("token", ""))
	var bad_oneshot: Dictionary = accounts.authenticate("0".repeat(64))
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	var bad_resident: Dictionary = accounts.authenticate("0".repeat(64))
	check(resident == oneshot and bad_resident == bad_oneshot and bad_resident.code == "AUTH_FAILED", "valid and invalid tokens give identical replies on both paths")
	check(accounts.execute({"op": "session.logout", "token": login.token}).ok and accounts.authenticate(login.token).code == "AUTH_FAILED", "a logged-out token is refused by the resident path")

func _revision(user: String) -> int:
	var stored: Dictionary = repository.execute_oneshot({"op": "asset.read", "user_id": user, "space_id": SPACE})
	var state: Variant = JSON.parse_string(str(stored.get("body", "")))
	return int(state.revision) if state is Dictionary else 0

func _worker_processes() -> int:
	var output: Array = []
	var filter := "@(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*storage_worker.ps1*' -and $_.CommandLine -like '*%s*' }).Count" % directory.get_file()
	if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", filter], output, false, false) != 0 or output.is_empty():
		return -1
	return int(str(output[0]).strip_edges())

func _handle_count() -> int:
	var output: Array = []
	if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).HandleCount" % OS.get_process_id()], output, false, false) != 0 or output.is_empty():
		return -1
	return int(str(output[0]).strip_edges())

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS resident_store: ", text)
	else:
		failed += 1
		printerr("FAIL resident_store: ", text)
	return value

func finish() -> void:
	print("RESIDENT_STORE_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
