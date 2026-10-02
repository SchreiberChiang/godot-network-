extends "res://host/operator.gd"
## Exercises the real _shutdown with account/bus/http doubles only. No service
## initialization, real helper, database or host is started. The isolated runner
## must supply --data-root inside its fresh isolation directory.
## FakeHttp.close records the cleanup state at the production shutdown boundary.
## Always judge SHUTDOWN_CLEANUP_RESULT / shutdown-probe-result.json, including
## failed, even if a particular engine processes _shutdown's quit(0) first.

class FakeAccounts extends RefCounted:
	var lock := Mutex.new()
	var login_calls := 0
	var logout_calls := 0
	var logout_confirmed := 0
	var token := "a".repeat(64)
	func execute(request: Dictionary, _deadline_ms: int = 0) -> Dictionary:
		match str(request.get("op", "")):
			"account.login":
				lock.lock()
				login_calls += 1
				lock.unlock()
				OS.delay_msec(1000)
				return {"ok": true, "code": "", "token": token, "identity": {"user_id": "fake-player", "role": "player"}}
			"session.logout":
				lock.lock()
				logout_calls += 1
				lock.unlock()
				OS.delay_msec(200)
				lock.lock()
				logout_confirmed += 1
				lock.unlock()
				return {"ok": true, "code": ""}
		return {"ok": false, "code": "INVALID_OPTIONS"}
	func counts() -> Dictionary:
		lock.lock()
		var result := {"login": login_calls, "logout": logout_calls, "logout_confirmed": logout_confirmed}
		lock.unlock()
		return result

class FakeBus extends RefCounted:
	var peers := {"host": {"authenticated": true}}
	var replies: Dictionary = {}
	func respond(peer: String, id: String, result: Dictionary) -> void:
		if peers.get(peer, {}).get("authenticated", false):
			replies[id] = result.duplicate(true)
	func close() -> void:
		peers.clear()

class FakeHttp extends RefCounted:
	var operator
	func close() -> void:
		operator.observe_shutdown_boundary()

var fake = FakeAccounts.new()
var probe_passed := 0
var probe_failed := 0
var observed := false
var result_path := ""

func _initialize() -> void:
	var supplied := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-root="):
			supplied = argument.trim_prefix("--data-root=")
	var allowed := Paths.absolute("res://data").replace("\\", "/").to_lower() + "/"
	var actual := Paths.absolute(supplied).replace("\\", "/") if supplied != "" else ""
	if actual == "" or not actual.to_lower().begins_with(allowed) or actual.to_lower() == allowed + "framework" or actual.to_lower().begins_with(allowed + "framework/") or ".." in actual.split("/"):
		print("REFUSED shutdown cleanup probe requires isolated --data-root")
		quit(64)
		return
	root_path = actual
	result_path = root_path.path_join("shutdown-probe-result.json")
	if FileAccess.file_exists(result_path):
		print("REFUSED shutdown cleanup probe never overwrites an existing report")
		quit(64)
		return
	if DirAccess.make_dir_recursive_absolute(root_path) != OK:
		print("REFUSED shutdown cleanup probe cannot create its isolated data directory")
		quit(64)
		return
	accounts = fake
	bus = FakeBus.new()
	var observer := FakeHttp.new()
	observer.operator = self
	http = observer
	cleanup.start_attempt = _cleanup_attempt
	cleanup.on_finished = _cleanup_finished
	_exercise.call_deferred()

func _process(_delta: float) -> bool:
	cleanup.poll(storage_maintenance)
	return false

func check(value: bool, label: String) -> void:
	if value:
		probe_passed += 1
		print("PASS ", label)
	else:
		probe_failed += 1
		print("FAIL ", label)

func _exercise() -> void:
	_rpc_request("host", Wire.uid(), "account.execute", {"op": "account.login", "username": "fake-player"})
	var deadline := Time.get_ticks_msec() + 500
	while fake.counts().login == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(fake.counts().login == 1 and worker_count == 1 and account_requests.size() == 1 and cleanup.idle(), "one login is running while no cleanup job exists at shutdown entry")
	# Simulates the already-departed host, without invoking real host management.
	# The successful login will therefore submit login_reply_lost after it returns.
	bus.close()
	quitting = true
	await _shutdown()
	if not observed:
		check(false, "production shutdown reached the observer boundary")
		write_result()
	# SceneTree.quit schedules exit; this supplies the test verdict if the engine
	# returns from _shutdown before finishing its main loop. The fixed result is
	# authoritative even if an engine honors the earlier shutdown quit code.
	quit(0 if probe_failed == 0 else 1)

func observe_shutdown_boundary() -> void:
	observed = true
	var counts := fake.counts()
	var status := cleanup.status()
	check(counts.login == 1 and counts.logout == 1 and counts.logout_confirmed == 1, "the late login executes once and its issued session is confirmed logged out once")
	check(worker_count == 0 and account_requests.is_empty() and cleanup.idle() and player_tokens.is_empty(), "shutdown closes HTTP only after late-account work and its cleanup responsibility are drained")
	check(int(status.pending) == 0 and int(status.running) == 0 and int(status.failed) == 0, "the shutdown boundary has no pending, running or failed cleanup")
	check(bus.replies.is_empty(), "no successful late-login reply reaches the departed host")
	write_result()

func write_result() -> void:
	var result := {"passed": probe_passed, "failed": probe_failed, "observed": observed, "calls": fake.counts(), "workers": worker_count, "account_contexts": account_requests.size(), "cleanup": cleanup.status(), "held_tokens": player_tokens.size()}
	var output := FileAccess.open(result_path, FileAccess.WRITE)
	if output == null:
		probe_failed += 1
		result.failed = probe_failed
		print("FAIL cannot write isolated shutdown probe result")
	else:
		output.store_string(JSON.stringify(result))
		output.close()
	print("SHUTDOWN_CLEANUP_RESULT passed=", probe_passed, " failed=", probe_failed, " result=", result_path)
