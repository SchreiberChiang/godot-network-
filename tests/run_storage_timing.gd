extends SceneTree
## Real storage latency on this machine for register, login, purchase, select and
## settlement through the production account, asset and result services. Each
## operation runs on a worker thread while the main thread polls the private data
## directory, so any temporary request file that exists during the call is seen.
## Timings are storage-layer only: no WSS, lobby, room or Operator RPC time.
const Accounts = preload("res://host/core/account_service.gd")
const Assets = preload("res://host/core/asset_service.gd")
const Shooter = preload("res://examples/shooter/asset_policy.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const PASSWORD := "storage-timing-password"
const OPERATIONS := ["register", "login", "authenticate", "logout", "admin_grant", "purchase", "purchase_retry", "select", "settlement"]
const ACCOUNT_OPERATIONS := ["register", "login", "authenticate", "logout"]
var passed := 0
var failed := 0
var rounds := 5
var label := "run"
var directory := ""
var accounts = Accounts.new()
var assets = Assets.new()
var samples := {}
var observed := {}
var handles := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rounds="):
			rounds = clampi(int(argument.trim_prefix("--rounds=")), 1, 50)
		elif argument.begins_with("--label="):
			label = argument.trim_prefix("--label=").validate_filename()
	for operation in OPERATIONS:
		samples[operation] = []
		observed[operation] = {}
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-storage-timing-" + Wire.uid())
	print("STORAGE_TIMING_EVIDENCE_DIR=", directory)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	if not check(accounts.initialize(directory).ok and assets.initialize(directory, catalog).ok, "real account and asset SQLite initialize"):
		finish({})
		return
	var admin := _setup_admin()
	if not check(admin.ok, "administrator setup, login and invitation succeed"):
		finish({})
		return
	var space: String = assets.catalog.space_for("shooter")
	# Resident workers hold a fixed set of handles for their lifetime; start them
	# first so the check below still catches handles leaked per call.
	assets.repository.prewarm()
	accounts.prewarm()
	handles.before = _handle_count()
	for index in rounds:
		var username := "timing_%02d" % index
		var registered := timed("register", {"op": "account.register", "username": username, "password": PASSWORD, "display_name": "计时玩家%d" % index, "invite_code": admin.invite_code, "client_ip": "127.0.0.1"})
		if not check(registered.ok, "round %d registration" % index):
			break
		var identity: Dictionary = registered.identity
		var login := timed("login", {"op": "account.login", "username": username, "password": PASSWORD, "client_ip": "127.0.0.1"})
		check(login.ok and login.identity.user_id == identity.user_id, "round %d login returns the registered identity" % index)
		check(timed("authenticate", {"op": "session.authenticate", "token": login.get("token", "")}).ok, "round %d session authenticates" % index)
		check(timed("logout", {"op": "session.logout", "token": login.get("token", "")}).ok, "round %d logout" % index)
		var grant := {"kind": "adjust", "credits": 300, "experience": 0, "reason": "计时测试", "request_id": "grant_%d" % index}
		check(timed_call("admin_grant", assets.adjust.bind(admin.identity, identity.user_id, "shooter", grant)).ok, "round %d administrator grant" % index)
		var purchase := {"kind": "purchase", "item_id": "smg", "request_id": "purchase_%d" % index}
		var bought: Dictionary = timed_call("purchase", assets.perform.bind(identity, "shooter", purchase, Shooter.new(), {"location": "lobby"}))
		check(bought.ok and bought.state.credits == 200 and "smg" in bought.state.owned, "round %d purchase commits exactly once" % index)
		var retried: Dictionary = timed_call("purchase_retry", assets.perform.bind(identity, "shooter", purchase, Shooter.new(), {"location": "lobby"}))
		check(retried.get("code", "") == "DUPLICATE" and retried.state.credits == 200, "round %d same request retry returns the receipt" % index)
		var selection := {"kind": "select", "item_id": "smg", "slot": "primary", "request_id": "select_%d" % index}
		var selected: Dictionary = timed_call("select", assets.perform.bind(identity, "shooter", selection, Shooter.new(), {"location": "lobby"}))
		check(selected.ok and selected.state.profiles.shooter.primary == "smg", "round %d selected weapon becomes the default" % index)
		var settled: Dictionary = timed_call("settlement", assets.repository.execute.bind(_submission(identity.user_id, space)))
		check(settled.ok, "round %d result and reward commit together" % index)
		check(assets.read(identity.user_id, "shooter").state.credits == 225, "round %d reward credited once" % index)
	handles.after = _handle_count()
	# Each account call starts a piped helper; an unreleased process entry keeps two
	# handles, so a leak would add about 4 * 2 * rounds handles here.
	check(handles.before > 0 and handles.after - handles.before <= 8, "account helper calls release their process handles (%d -> %d)" % [handles.before, handles.after])
	var breakdown := _breakdown()
	check(breakdown.get("ok", false), "cost breakdown fixture ran")
	for operation in ACCOUNT_OPERATIONS:
		check(not observed[operation].has("account-request"), operation + " leaves no account request body file in the data directory")
	finish(breakdown)

func _setup_admin() -> Dictionary:
	var setup: Dictionary = accounts.execute({"op": "setup.admin", "username": "operator", "password": PASSWORD, "display_name": "计时管理员"})
	var login: Dictionary = accounts.execute({"op": "account.login", "username": "operator", "password": PASSWORD, "client_ip": "127.0.0.1"})
	if not setup.ok or not login.ok:
		return {"ok": false}
	var invite: Dictionary = accounts.execute({"op": "invite.create", "token": login.token, "uses": rounds, "reason": "storage timing"})
	return {"ok": invite.ok, "identity": login.identity, "invite_code": invite.get("invite_code", "")}

func _submission(user_id: String, space: String) -> Dictionary:
	var launch := Wire.uid()
	var record := {"game_id": "shooter", "build_id": "timing_build", "room_id": "timing_room", "launch_id": launch, "match_id": "m_" + launch + "_final", "result_id": Wire.uid(), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}
	return {"op": "accept", "record": record, "record_hash": Format.hash_record(record), "body": Format.canonical(record), "rewards": [{"user_id": user_id, "space_id": space, "credits": 25, "experience": 5}]}

func timed(operation: String, request: Dictionary) -> Dictionary:
	return timed_call(operation, accounts.execute.bind(request))

func timed_call(operation: String, work: Callable) -> Dictionary:
	var thread := Thread.new()
	var started := Time.get_ticks_usec()
	if thread.start(work) != OK:
		return {"ok": false, "code": "THREAD_FAILED"}
	while thread.is_alive():
		_scan(operation)
		OS.delay_msec(2)
	var result: Variant = thread.wait_to_finish()
	samples[operation].append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	_scan(operation)
	return result if result is Dictionary else {"ok": false}

func _scan(operation: String) -> void:
	# Names only; file contents are never opened.
	for name in DirAccess.get_files_at(directory):
		for prefix in ["account-request-", "helper-", "request-"]:
			if name.begins_with(prefix):
				observed[operation][prefix.trim_suffix("-")] = true

func _handle_count() -> int:
	var output: Array = []
	if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).HandleCount" % OS.get_process_id()], output, false, false) != 0 or output.is_empty():
		return -1
	return int(str(output[0]).strip_edges())

func _breakdown() -> Dictionary:
	var starts: Array = []
	for index in rounds:
		var started := Time.get_ticks_usec()
		OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "exit 0"], [], false, false)
		starts.append(snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1))
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/storage_cost_breakdown.ps1"), "-Rounds", "3"], output, false, false)
	var parsed: Variant = JSON.parse_string(str(output[0])) if code == 0 and not output.is_empty() else null
	var result: Dictionary = parsed if parsed is Dictionary else {"ok": false}
	result["powershell_start_ms"] = starts
	return result

static func stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {"count": sorted.size(), "min_ms": sorted[0], "median_ms": sorted[sorted.size() / 2], "max_ms": sorted[-1], "mean_ms": snappedf(total / sorted.size(), 0.1), "samples_ms": values}

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS storage_timing: ", text)
	else:
		failed += 1
		printerr("FAIL storage_timing: ", text)
	return value

func finish(breakdown: Dictionary) -> void:
	var report := {"label": label, "rounds": rounds, "engine": Engine.get_version_info().string, "evidence_dir": directory, "timings": {}, "temporary_files_seen": {}, "breakdown": breakdown, "godot_handles": handles, "passed": passed, "failed": failed}
	for operation in OPERATIONS:
		report.timings[operation] = stats(samples[operation])
		report.temporary_files_seen[operation] = observed[operation].keys()
		if not samples[operation].is_empty():
			print("TIMING ", operation, " median=", report.timings[operation].median_ms, "ms min=", report.timings[operation].min_ms, "ms max=", report.timings[operation].max_ms, "ms files=", observed[operation].keys())
	var path := ProjectSettings.globalize_path("res://logs/storage-timing-" + label + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("STORAGE_TIMING_REPORT=", path)
	print("STORAGE_TIMING_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
