extends SceneTree
## One targeted offline pass; the caller must verify exact Godot 4.7.2 first.
const Local = preload("res://examples/framework/client_data.gd")
var passed := 0
var failed := 0
var cases: Array = []
var base := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, name: String) -> void:
	cases.append({"name": name, "ok": ok})
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", name)

func _new(name: String) -> Local:
	var local := Local.new()
	local.configure(base.path_join(name), "test-n1", base.path_join(name + "-legacy"))
	return local

func _write(path: String, content: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

func _files(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	return dir.get_files() if dir != null else PackedStringArray()

func _run() -> void:
	var options: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	if options.has("--journal-child"):
		await _child(str(options["--journal-child"]), str(options.get("--child-id", "child")))
		return
	base = Local.default_root(str(options.get("--journal-root", "res://data/test-client-journal/中文 空格-" + Crypto.new().generate_random_bytes(6).hex_encode())))
	if base.is_empty():
		print("CLIENT_JOURNAL invalid isolated root")
		quit(2)
		return
	_check(base.begins_with(ProjectSettings.globalize_path("res://")), "source path is explicitly project-contained")
	_check(Local.default_root("relative/cwd") == "", "relative cwd rejected")
	_check(Local.default_root("user://client-data") == "", "user fallback rejected")
	_check(Local.default_root("res://../outside") == "", "project escape rejected")
	var invalid := Local.new()
	_check(not invalid.configure("relative", "test"), "unsafe configured path rejected")
	_check(invalid.status().error == "UNSAFE_PATH", "unsafe path fixed error")
	invalid.close()

	var privacy = _new("privacy")
	_check(privacy.status().enabled and str(privacy.status().session_id).length() == 32, "random per-session id")
	var secret := "SYNTHETIC_PASSWORD_TOKEN_INVITE_TICKET_BODY"
	var raw := {"password": secret, "username": secret, "token": secret, "credential": secret, "ticket": secret, "invite_code": secret, "chat": secret, "payload": {"body": secret}, "url": "wss://" + secret, "close_reason": secret, "phase": secret, "error": secret, "rtt_ms": secret, "fps": 60.0, "frame_max_ms": NAN}
	_check(privacy.sample(raw), "first diagnostic sample accepted")
	_check(not privacy.sample(raw), "sampling gate prevents frame-rate logging")
	_check(privacy.mark() and not privacy.mark(), "fixed marker and 1Hz marker gate")
	privacy.queue_settings({"volume": 0.2, "muted": true, "password": secret})
	privacy.queue_settings({"volume": 0.8, "muted": false})
	_check(not FileAccess.file_exists(privacy.audio_settings_path()), "settings changes queued off UI thread")
	privacy.close()
	var output := ""
	for name in _files(privacy.report_directory()):
		output += FileAccess.get_file_as_string(privacy.report_directory().path_join(name))
	_check(not output.contains(secret) and not output.contains("close_reason") and not output.contains("password"), "secrets and arbitrary close reasons absent")
	var lines := output.strip_edges().split("\n")
	_check(lines.size() == 2, "sample and marker JSONL records only")
	var row: Variant = JSON.parse_string(lines[0])
	_check(row is Dictionary and row.get("phase") == "IDLE" and row.get("error") == "OTHER", "unknown categories fixed")
	_check(row is Dictionary and row.get("utc", "").ends_with("Z") and row.get("monotonic_ms") is float, "UTC and monotonic timestamps")
	_check(row is Dictionary and not row.has("rtt_ms") and not row.has("frame_max_ms"), "non-numeric and nonfinite metrics omitted")
	var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(privacy.audio_settings_path()))
	_check(settings is Dictionary and is_equal_approx(float(settings.volume), 0.8) and not settings.muted and not settings.has("password"), "coalesced whitelisted settings flushed on close")
	var restart = _new("privacy")
	_check(is_equal_approx(float(restart.load_settings().volume), 0.8), "settings survive restart")
	_check(restart.status().session_id != privacy.status().session_id, "session ids differ")
	restart.close()

	var queue = _new("queue")
	for index in 400:
		queue._enqueue(queue._record({"fps": index}, "sample"))
	_check(int(queue.status().queued) <= Local.QUEUE_LIMIT and int(queue.status().dropped) > 0, "bounded queue drops excess without growth")
	queue.close()

	var retain_root := base.path_join("retention")
	for index in 5:
		var local = _new("retention")
		local.sample({"fps": index})
		local.close()
	var ended := 0
	var retained_fps: Array[int] = []
	for name in _files(retain_root.path_join("reports")):
		if name.begins_with("ended-"):
			ended += 1
			var retained: Variant = JSON.parse_string(FileAccess.get_file_as_string(retain_root.path_join("reports").path_join(name)).strip_edges())
			if retained is Dictionary:
				retained_fps.append(int(retained.get("fps", -1)))
	retained_fps.sort()
	_check(ended == 2 and retained_fps == [3, 4], "only latest two ended sessions retained")

	var capacity = _new("capacity")
	var sentinel := capacity.report_directory().path_join("session-foreign.active.jsonl")
	_write(sentinel, "x".repeat(Local.TOTAL_LIMIT))
	capacity.sample({"fps": 1})
	capacity.queue_settings({"volume": 0.4, "muted": true})
	capacity.close()
	_check(capacity.status().error == "BUDGET_FULL", "total budget full stops only diagnostics")
	_check(FileAccess.file_exists(sentinel) and Local._file_size(sentinel) == Local.TOTAL_LIMIT, "foreign active session never deleted")
	_check(capacity._log_bytes() <= Local.TOTAL_LIMIT, "total log bytes stay within cap")
	_check(FileAccess.file_exists(capacity.audio_settings_path()), "settings persist despite log budget failure")
	var hidden = _new("hidden-budget")
	_write(hidden.report_directory().path_join(".hidden.log"), "x".repeat(Local.TOTAL_LIMIT))
	hidden.sample({"fps": 1})
	hidden.close()
	_check(hidden.status().error == "BUDGET_FULL", "hidden files count toward log budget")

	var cap_session = _new("session-cap")
	_write(cap_session._active, "x".repeat(Local.SESSION_LIMIT - 1))
	cap_session.sample({"fps": 1})
	cap_session.close()
	_check(cap_session.status().error == "SESSION_FULL", "individual session cap stops recording")
	for name in _files(cap_session.report_directory()):
		_check(Local._file_size(cap_session.report_directory().path_join(name)) <= Local.SESSION_LIMIT, "ended session at most 2MiB")

	# Real filesystem failure, no test-only production fault bypass.
	var blocked_path := base.path_join("blocked")
	_write(blocked_path, "ordinary file prevents directory creation")
	var blocked := Local.new()
	blocked.configure(blocked_path, "test-n1", base.path_join("blocked-legacy"))
	_check(not blocked.status().enabled and blocked.status().error == "WRITE_FAILED", "directory creation failure disables logs with fixed status")
	blocked.close()
	var locked = _new("locked")
	DirAccess.make_dir_absolute(locked.report_directory().path_join(".budget-lock"))
	locked.sample({"fps": 1})
	locked.close()
	_check(locked.status().error == "LOCK_BUSY", "stale or contended lock fails closed")
	_check(DirAccess.dir_exists_absolute(locked.report_directory().path_join(".budget-lock")), "foreign lock not force removed")
	var settings_blocked = _new("settings-blocked")
	_write(settings_blocked._root.path_join("settings"), "not a directory")
	settings_blocked.sample({"fps": 1})
	settings_blocked.queue_settings({"volume": 0.1, "muted": false})
	settings_blocked.close()
	_check(settings_blocked.status().settings_error == "WRITE_FAILED" and settings_blocked.status().error == "", "settings failure isolated from logging")

	_pending_cases()
	_quarantine_cases()
	await _multi_process()
	var report := {"suite": "client_journal", "engine": Engine.get_version_info(), "passed": passed, "failed": failed, "cases": cases, "limitations": ["No exported Windows permission behavior verified by this source run", "No disk-full or hard-crash power-loss simulation", "OS.create_process does not return child exit status; child fixed status files and terminated PIDs verified"]}
	_write(base.path_join("result.json"), JSON.stringify(report, "\t"))
	print("CLIENT_JOURNAL_RESULT passed=", passed, " failed=", failed, " report=", base.path_join("result.json"))
	quit(0 if failed == 0 else 1)

func _pending_cases() -> void:
	var local = _new("pending")
	var operation := {"kind": "purchase", "item_id": "rifle", "slot": "", "operation_id": "0123456789abcdef0123456789abcdef"}
	_check(local.save_pending("wss://a:1", "account-a", "shooter", operation), "new pending receipt saved")
	_check(local.load_pending("wss://a:1", "account-a", "shooter").operation == operation, "pending exact operation id preserved")
	_check(local.load_pending("wss://b:1", "account-a", "shooter").operation.is_empty(), "pending server isolation")
	_check(local.load_pending("wss://a:1", "account-b", "shooter").operation.is_empty(), "pending account isolation")
	_check(local.load_pending("wss://a:1", "account-a", "turns").operation.is_empty(), "pending game isolation")
	var other := operation.duplicate()
	other.operation_id = "fedcba9876543210fedcba9876543210"
	_check(not local.save_pending("wss://a:1", "account-a", "shooter", other), "pending different id cannot overwrite unresolved receipt")
	_check(local.save_pending("wss://a:1", "account-a", "shooter", {}), "acknowledged loaded pending can clear")
	var legacy_file: String = local._legacy.path_join(("legacy-account:shooter").sha256_text() + ".json")
	var legacy_bytes := JSON.stringify(operation)
	_write(legacy_file, legacy_bytes)
	_check(local.load_pending("wss://a:1", "legacy-account", "shooter").warning == "LEGACY_UNBOUND", "old account-game hash does not guess server")
	_check(not local.save_pending("wss://a:1", "legacy-account", "shooter", other), "unbound legacy blocks new operations")
	_check(local.bind_legacy("wss://a:1", "legacy-account", "shooter"), "explicit binding migrates local receipt")
	_check(local.load_pending("wss://a:1", "legacy-account", "shooter").operation == operation, "migration preserves original operation id")
	_check(FileAccess.get_file_as_string(legacy_file) == legacy_bytes, "legacy recovery source unchanged")
	_check(local.load_pending("wss://b:1", "legacy-account", "shooter").operation.is_empty(), "migrated operation cannot cross server")
	local.save_pending("wss://a:1", "legacy-account", "shooter", {})
	_check(local.load_pending("wss://a:1", "legacy-account", "shooter").warning == "", "resolved migration not automatically imported again")
	_check(not local.bind_legacy("wss://b:1", "legacy-account", "shooter"), "existing migration cannot bind a second server")
	# PREPARED persists if target write fails. The target is never exposed to load
	# or rebound elsewhere, and a same-server explicit retry can finish safely.
	var fault_source: String = local._legacy.path_join(("fault-account:shooter").sha256_text() + ".json")
	_write(fault_source, legacy_bytes)
	var fault_path := local._pending_path("wss://a:1", "fault-account", "shooter")
	DirAccess.make_dir_recursive_absolute(fault_path)
	_check(not local.bind_legacy("wss://a:1", "fault-account", "shooter"), "migration target-write failure preserved")
	_check(local.load_pending("wss://a:1", "fault-account", "shooter").warning == "LEGACY_MIGRATION_INCOMPLETE", "partial migration blocks target receipt exposure")
	_check(not local.bind_legacy("wss://b:1", "fault-account", "shooter"), "partial migration cannot rebind another server")
	DirAccess.remove_absolute(fault_path)
	_check(local.bind_legacy("wss://a:1", "fault-account", "shooter"), "same server explicit retry recovers prepared migration")
	_check(local.load_pending("wss://a:1", "fault-account", "shooter").operation == operation, "recovered migration has exact original operation")
	_write(fault_source, JSON.stringify(other))
	_check(local.load_pending("wss://a:1", "fault-account", "shooter").warning == "LEGACY_CHANGED", "changed legacy source is not silently covered by old marker")
	var marker_source: String = local._legacy.path_join(("marker-account:shooter").sha256_text() + ".json")
	_write(marker_source, legacy_bytes)
	DirAccess.make_dir_recursive_absolute(local._migration_path("marker-account", "shooter"))
	_check(not local.bind_legacy("wss://a:1", "marker-account", "shooter"), "migration marker failure refuses bind")
	_check(not FileAccess.file_exists(local._pending_path("wss://a:1", "marker-account", "shooter")), "marker failure creates no loadable pending target")

	# Completion-marker failure leaves immutable PREPARED intent and no exposure.
	var complete_source: String = local._legacy.path_join(("complete-account:shooter").sha256_text() + ".json")
	_write(complete_source, legacy_bytes)
	DirAccess.make_dir_recursive_absolute(local._migration_path("complete-account", "shooter") + ".committed")
	_check(not local.bind_legacy("wss://a:1", "complete-account", "shooter"), "completion marker failure is reported")
	_check(local.load_pending("wss://a:1", "complete-account", "shooter").warning == "LEGACY_MIGRATION_INCOMPLETE", "completion failure keeps pending inaccessible")
	_check(not local.bind_legacy("wss://b:1", "complete-account", "shooter"), "completion failure retains original server binding")
	DirAccess.remove_absolute(local._migration_path("complete-account", "shooter") + ".committed")
	_check(local.bind_legacy("wss://a:1", "complete-account", "shooter"), "completion failure recovers to same server")
	var changed_body := operation.duplicate()
	changed_body.item_id = "other-item"
	_check(not local.save_pending("wss://a:1", "complete-account", "shooter", changed_body), "same operation id cannot change request body")

	local.close()

func _quarantine_cases() -> void:
	var local: Local = _new("quarantined")
	var account := "quarantine-account"
	var filename := (account + ":shooter").sha256_text() + ".json"
	var quarantine := local._root.path_join("legacy-client-operations/client-operations").path_join(filename)
	var original := local._legacy.path_join(filename)
	var operation := {"kind": "select", "item_id": "rifle", "slot": "primary", "operation_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
	var bytes := JSON.stringify(operation, "\t")
	_write(quarantine, bytes)
	_check(local.load_pending("wss://a:1", account, "shooter").warning == "LEGACY_UNBOUND", "quarantined receipt discovered without automatic binding")
	_check(not local.save_pending("wss://a:1", account, "shooter", operation), "quarantined unbound receipt blocks new operation")
	_check(local.bind_legacy("wss://a:1", account, "shooter"), "explicit binding imports quarantined receipt")
	_check(local.load_pending("wss://a:1", account, "shooter").operation == operation, "quarantined operation id preserved")
	_check(local.load_pending("wss://b:1", account, "shooter").operation.is_empty(), "quarantined receipt remains server scoped")
	_check(FileAccess.get_file_as_string(quarantine) == bytes and not FileAccess.file_exists(original), "quarantine bytes retained without creating old path")
	local.close()
	var restarted: Local = _new("quarantined")
	_check(restarted.load_pending("wss://a:1", account, "shooter").operation == operation, "quarantined binding survives restart")
	_check(restarted.save_pending("wss://a:1", account, "shooter", {}), "quarantined pending can be explicitly resolved")
	_check(restarted.load_pending("wss://a:1", account, "shooter").operation.is_empty() and restarted.load_pending("wss://a:1", account, "shooter").warning == "", "resolved quarantine is not imported again")
	# Matching source/quarantine copies are harmless; conflicting bytes are never
	# resolved by choosing a location, even if one receipt was previously bound.
	_write(original, bytes)
	_check(restarted.load_pending("wss://a:1", account, "shooter").warning == "", "identical original and quarantine copies accepted")
	var conflicting := operation.duplicate()
	conflicting.operation_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	_write(original, JSON.stringify(conflicting))
	_check(restarted.load_pending("wss://a:1", account, "shooter").warning == "LEGACY_CONFLICT", "conflicting original and quarantine copies block load")
	_check(not restarted.bind_legacy("wss://b:1", account, "shooter"), "conflicting legacy copies cannot bind another server")
	_check(not restarted.save_pending("wss://a:1", account, "shooter", operation), "conflicting legacy copies block new operations")
	_check(FileAccess.get_file_as_string(quarantine) == bytes and FileAccess.get_file_as_string(original) == JSON.stringify(conflicting), "conflicting recovery copies remain unchanged")
	restarted.close()

func _multi_process() -> void:
	var path := base.path_join("multi")
	var children: Array[int] = []
	for id in ["one", "two"]:
		var child_args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/run_client_journal.gd", "--", "--journal-child=" + path, "--child-id=" + id]
		children.append(OS.create_process(OS.get_executable_path(), child_args))
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and (not FileAccess.file_exists(path.path_join("one-ready")) or not FileAccess.file_exists(path.path_join("two-ready"))):
		await create_timer(0.05).timeout
	var names := _files(path.path_join("reports"))
	var active := 0
	for name in names:
		if name.ends_with(".active.jsonl"):
			active += 1
	_check(active == 2, "two real processes write independent active sessions")
	var third = _new("multi")
	third.sample({"fps": 3})
	third.close()
	var all_preserved := true
	for name in names:
		if name.ends_with(".active.jsonl"):
			all_preserved = all_preserved and FileAccess.file_exists(path.path_join("reports").path_join(name))
	_check(all_preserved, "other process close cannot remove active sessions")
	_write(path.path_join("release"), "release owned child fixtures")
	while Time.get_ticks_msec() < deadline:
		var running := false
		for pid in children:
			running = running or (pid > 0 and OS.is_process_running(pid))
		if not running:
			break
		await create_timer(0.05).timeout
	var child_sessions_clean := true
	for id in ["one", "two"]:
		var done_path := path.path_join(id + "-done")
		if not FileAccess.file_exists(done_path) or FileAccess.get_file_as_string(done_path) != "":
			child_sessions_clean = false
	for pid in children:
		if pid <= 0 or OS.is_process_running(pid):
			child_sessions_clean = false
	_check(child_sessions_clean, "both child sessions report no error and owned PIDs have exited")
	var ended := 0
	for name in _files(path.path_join("reports")):
		if name.begins_with("ended-"):
			ended += 1
	_check(ended == 2, "cross-process retention keeps last two ended sessions")

func _child(path: String, id: String) -> void:
	var local := Local.new()
	local.configure(path, "child-n1", path.path_join("legacy"))
	local.sample({"fps": 60})
	await create_timer(1.2).timeout
	_write(path.path_join(id + "-ready"), "ready")
	var deadline := Time.get_ticks_msec() + 8000
	while not FileAccess.file_exists(path.path_join("release")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	local.close()
	_write(path.path_join(id + "-done"), str(local.status().error))
	quit(0)
