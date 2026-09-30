extends SceneTree
## Isolated evaluation prototype for option G: SQLite inside the Godot process
## through the third-party godot-sqlite GDExtension. It is NOT wired into the
## host, the build or the clients, uses only new fake data under --work, and
## ports just the asset commit rule (revision check + receipt idempotency) to
## compare behaviour and cost with the PowerShell helpers. Accounts, passwords,
## deletion, settlement and maintenance are not ported.
## Modes: baseline | verify | perf | crash   (arguments after "--")
const SECRET := "SECRET_PARAM_7731"
var args: Dictionary = {}
var passed := 0
var failed := 0
var frame_max_ms := 0.0
var frame_watch := false
var last_frame := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0].trim_prefix("--")] = pair[1]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if frame_watch and last_frame > 0:
		frame_max_ms = maxf(frame_max_ms, float(now - last_frame) / 1000.0)
	last_frame = now
	return false

func _run() -> void:
	var mode := str(args.get("mode", ""))
	print("PROTO_START mode=", mode, " pid=", OS.get_process_id(), " engine=", Engine.get_version_info().string, " extension_loaded=", ClassDB.class_exists("SQLite"))
	if mode == "baseline":
		await _hold()
		quit(0)
		return
	if not ClassDB.class_exists("SQLite"):
		print("PROTO_BLOCKED the SQLite extension class is not available in this engine")
		quit(3)
		return
	var work := str(args.get("work", ""))
	if work == "" or not DirAccess.dir_exists_absolute(work):
		print("PROTO_BLOCKED --work must name an existing directory")
		quit(2)
		return
	match mode:
		"verify": await _verify(work)
		"perf": await _perf(work)
		"crash": _crash(work)
		_:
			print("PROTO_BLOCKED unknown mode")
			quit(2)

func _hold() -> void:
	var hold := int(args.get("hold-ms", "0"))
	print("PROTO_HOLD pid=", OS.get_process_id(), " ms=", hold)
	if hold > 0:
		await create_timer(float(hold) / 1000.0).timeout

# ---- one connection, used by one thread at a time ----
func _open(path: String, busy_ms: int = 1500):
	var db = ClassDB.instantiate("SQLite")
	db.path = path
	db.default_extension = ""
	db.verbosity_level = 0  # QUIET: never print statements or values
	if not db.open_db():
		return null
	db.query("PRAGMA busy_timeout=%d" % busy_ms)
	db.query("PRAGMA journal_mode=WAL")
	db.query("PRAGMA synchronous=FULL")
	return db

func _schema(db) -> bool:
	var ok: bool = db.query("BEGIN IMMEDIATE")
	ok = ok and db.query("CREATE TABLE IF NOT EXISTS asset_states (user_id TEXT NOT NULL, space_id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision>=0), body TEXT NOT NULL, PRIMARY KEY(user_id,space_id))")
	ok = ok and db.query("CREATE TABLE IF NOT EXISTS asset_receipts (user_id TEXT NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL, space_id TEXT NOT NULL, actor_id TEXT NOT NULL, command TEXT NOT NULL, previous_body TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id,request_id))")
	return db.query("COMMIT") and ok

func _read(db, user: String, space: String) -> Dictionary:
	if not db.query_with_bindings("SELECT revision,body FROM asset_states WHERE user_id=? AND space_id=?", [user, space]):
		return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	var rows: Array = db.query_result
	return {"ok": true, "code": "", "body": rows[0].body if rows.size() else "", "revision": int(rows[0].revision) if rows.size() else 0}

## Same rule as tools/sqlite_store.ps1 asset.commit: one IMMEDIATE transaction,
## receipt first (same fingerprint -> DUPLICATE, other -> REQUEST_CONFLICT), then
## the expected revision, then state and receipt together. Errors return a fixed
## code only; SQL text and bound values are never returned or printed.
func _commit(db, r: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(r.body))
	if not parsed is Dictionary or str(r.body).length() > 65536 or int(r.expected_revision) < 0 or int(parsed.get("revision", -1)) != int(r.expected_revision) + 1:
		return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	if not db.query("BEGIN IMMEDIATE"):
		return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	var result := {"ok": true, "code": ""}
	var ok: bool = db.query_with_bindings("SELECT fingerprint,body FROM asset_receipts WHERE user_id=? AND request_id=?", [r.user_id, r.request_id])
	var receipt: Array = db.query_result
	ok = ok and db.query_with_bindings("SELECT revision,body FROM asset_states WHERE user_id=? AND space_id=?", [r.user_id, r.space_id])
	var current: Array = db.query_result
	var revision := int(current[0].revision) if current.size() else 0
	if not ok:
		result = {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	elif receipt.size():
		if str(receipt[0].fingerprint) != str(r.fingerprint):
			result = {"ok": false, "code": "REQUEST_CONFLICT"}
		else:
			result = {"ok": true, "code": "DUPLICATE", "body": receipt[0].body}
	elif revision != int(r.expected_revision):
		result = {"ok": false, "code": "ASSET_VERSION_CONFLICT"}
	else:
		var previous: String = current[0].body if current.size() else ""
		ok = db.query_with_bindings("INSERT INTO asset_states (user_id,space_id,revision,body) VALUES (?,?,?,?) ON CONFLICT(user_id,space_id) DO UPDATE SET revision=excluded.revision,body=excluded.body", [r.user_id, r.space_id, int(parsed.revision), r.body])
		ok = ok and db.query_with_bindings("INSERT INTO asset_receipts (user_id,request_id,fingerprint,space_id,actor_id,command,previous_body,body) VALUES (?,?,?,?,?,?,?,?)", [r.user_id, r.request_id, r.fingerprint, r.space_id, r.actor_id, r.command, previous, r.body])
		if ok:
			result.body = r.body
		else:
			db.query("ROLLBACK")
			return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	if not db.query("COMMIT"):
		db.query("ROLLBACK")
		return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	return result

func _body(revision: int, credits: int, owned: Array, primary: String) -> String:
	return JSON.stringify({"revision": revision, "credits": credits, "experience": 0, "owned": owned, "profiles": {"shooter": {"primary": primary}}})

func _request(id: String, fingerprint: String, expected: int, body: String, command: String = "{}") -> Dictionary:
	return {"user_id": "user_proto", "space_id": "shooter", "request_id": id, "fingerprint": fingerprint, "expected_revision": expected, "body": body, "actor_id": "admin:proto", "command": command}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		print("FAIL ", label)

# ---- correctness ----
func _verify(work: String) -> void:
	var reason := "测试 发放 🎁 it's <ok> & done"
	var folder := work.path_join("存档 测试 dir")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("assets.sqlite")
	var db = _open(path)
	_check(db != null and FileAccess.file_exists(path), "database opens at a path with Chinese characters and spaces")
	if db == null:
		print("PROTO_RESULT passed=", passed, " failed=", failed + 1)
		quit(1)
		return
	db.query("SELECT sqlite_version() AS v")
	print("INFO sqlite_version=", db.query_result[0].v)
	db.query("PRAGMA journal_mode")
	_check(str(db.query_result[0].journal_mode).to_lower() == "wal", "WAL journal mode is active")
	_check(_schema(db), "schema is created inside one IMMEDIATE transaction")
	# Parameter binding and text.
	db.query("CREATE TABLE t (id TEXT PRIMARY KEY, body TEXT NOT NULL)")
	var values := ["玩家 一 🎮", reason, "x'); DROP TABLE t;--", "", "😀🎮"]
	var bound := true
	for index in values.size():
		bound = bound and db.query_with_bindings("INSERT INTO t (id,body) VALUES (?,?)", [str(index), values[index]])
	db.query("SELECT id,body FROM t ORDER BY id")
	var rows: Array = db.query_result
	var same := bound and rows.size() == values.size()
	for index in values.size():
		same = same and rows[index].body == values[index]
	_check(same, "bound parameters round-trip Unicode, quotes and SQL-looking text exactly")
	db.query_with_bindings("SELECT length(body) AS n FROM t WHERE id=?", ["0"])
	_check(int(db.query_result[0].n) == 6, "SQLite counts the stored text in characters (UTF-8 stored correctly)")
	# Transactions.
	db.query("BEGIN IMMEDIATE")
	db.query_with_bindings("INSERT INTO t (id,body) VALUES (?,?)", ["rolled", "back"])
	db.query("ROLLBACK")
	db.query_with_bindings("SELECT count(*) AS n FROM t WHERE id=?", ["rolled"])
	_check(int(db.query_result[0].n) == 0, "ROLLBACK discards the transaction")
	# Errors must not reveal bound values.
	var failed_insert: bool = db.query_with_bindings("INSERT INTO t (id,body) VALUES (?,?)", ["0", SECRET])
	_check(not failed_insert and not str(db.error_message).contains(SECRET), "a failed statement reports an error without the bound value")
	var bad_sql: bool = db.query_with_bindings("SELEC nothing FROM t WHERE body=?", [SECRET])
	_check(not bad_sql and not str(db.error_message).contains(SECRET), "a syntax error reports no bound value")
	# Asset commit rule.
	_check(_read(db, "user_proto", "shooter").body == "", "a new player has no stored assets")
	var grant := _commit(db, _request("req_grant", "fp_grant", 0, _body(1, 500, ["rifle"], "rifle"), JSON.stringify({"kind": "admin_adjust", "reason": reason})))
	_check(grant.ok and grant.code == "", "first commit stores the granted balance")
	var buy_body := _body(2, 380, ["rifle", "smg"], "rifle")
	var buy := _commit(db, _request("req_buy", "fp_buy", 1, buy_body))
	var again := _commit(db, _request("req_buy", "fp_buy", 1, buy_body))
	var state: Dictionary = JSON.parse_string(_read(db, "user_proto", "shooter").body)
	_check(buy.ok and again.ok and again.code == "DUPLICATE" and again.body == buy_body and int(state.credits) == 380 and int(state.revision) == 2, "repeating the same purchase request returns the stored receipt and deducts only once")
	_check(_commit(db, _request("req_buy", "fp_other", 2, _body(3, 260, ["rifle", "smg"], "rifle"))).code == "REQUEST_CONFLICT", "the same request id with different content is refused")
	_check(_commit(db, _request("req_stale", "fp_stale", 1, _body(2, 100, ["rifle"], "rifle"))).code == "ASSET_VERSION_CONFLICT", "a commit based on a stale revision is refused")
	_check(not _commit(db, _request("req_jump", "fp_jump", 2, _body(9, 0, [], "rifle"))).ok, "a commit that skips revisions is refused")
	var select := _commit(db, _request("req_select", "fp_select", 2, _body(3, 380, ["rifle", "smg"], "smg")))
	state = JSON.parse_string(_read(db, "user_proto", "shooter").body)
	_check(select.ok and int(state.revision) == 3 and int(state.credits) == 380 and state.profiles.shooter.primary == "smg", "selection commit saves the loadout; refused requests changed nothing")
	db.query_with_bindings("SELECT command FROM asset_receipts WHERE user_id=? AND request_id=?", ["user_proto", "req_grant"])
	_check(JSON.parse_string(db.query_result[0].command).reason == reason, "the Unicode command text is preserved exactly")
	db.query("SELECT count(*) AS n FROM asset_receipts")
	_check(int(db.query_result[0].n) == 3, "three receipts are recorded")
	# Lock wait: another connection on another thread holds the write lock.
	var holder := Thread.new()
	holder.start(_hold_lock.bind(path, 400))
	await create_timer(0.15).timeout
	var impatient = _open(path, 50)
	var started := Time.get_ticks_msec()
	var refused: bool = not impatient.query("BEGIN IMMEDIATE")
	var refused_ms := Time.get_ticks_msec() - started
	_check(refused and not str(impatient.error_message).contains(SECRET), "a short busy timeout gives up while another connection holds the write lock (%d ms)" % refused_ms)
	impatient.close_db()
	started = Time.get_ticks_msec()
	var waited := _commit(db, _request("req_wait", "fp_wait", 3, _body(4, 380, ["rifle", "smg"], "smg")))
	var waited_ms := Time.get_ticks_msec() - started
	holder.wait_to_finish()
	_check(waited.ok and waited_ms >= 100, "the default busy timeout waits for the lock and then commits (%d ms)" % waited_ms)
	# Backup and restore through the SQLite backup API.
	var backup := folder.path_join("assets backup.sqlite")
	_check(db.backup_to(backup) and FileAccess.file_exists(backup), "backup_to writes a copy with the SQLite backup API")
	_commit(db, _request("req_spend", "fp_spend", 4, _body(5, 0, ["rifle", "smg"], "smg")))
	_check(int(JSON.parse_string(_read(db, "user_proto", "shooter").body).credits) == 0, "state changes after the backup")
	var copy = _open(backup)
	copy.query("PRAGMA integrity_check")
	var intact: bool = str(copy.query_result[0].integrity_check) == "ok"
	_check(intact and int(JSON.parse_string(_read(copy, "user_proto", "shooter").body).credits) == 380, "the backup reopens, passes the integrity check and holds the balance from backup time")
	copy.close_db()
	_check(db.restore_from(backup) and int(JSON.parse_string(_read(db, "user_proto", "shooter").body).credits) == 380, "restore_from brings the live database back to the backup")
	db.close_db()
	# Crash in the middle of a transaction (a child process kills itself).
	var crash_dir := work.path_join("crash")
	DirAccess.make_dir_recursive_absolute(crash_dir)
	var forwarded := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://proto.gd", "--", "--mode=crash", "--work=" + crash_dir]
	var child := OS.create_process(OS.get_executable_path(), forwarded)
	var deadline := Time.get_ticks_msec() + 30000
	while not FileAccess.file_exists(crash_dir.path_join("crash.ready")) and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	# The child now sits inside an open write transaction. Kill it from outside.
	var reached := FileAccess.file_exists(crash_dir.path_join("crash.ready")) and OS.is_process_running(child)
	OS.kill(child)
	deadline = Time.get_ticks_msec() + 10000
	while OS.is_process_running(child) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var code := 0 if OS.is_process_running(child) else 1
	print("INFO after kill: wal_file_present=", FileAccess.file_exists(crash_dir.path_join("crash.sqlite-wal")))
	var after = _open(crash_dir.path_join("crash.sqlite"))
	var survived := after != null
	if survived:
		after.query("PRAGMA integrity_check")
		survived = str(after.query_result[0].integrity_check) == "ok"
		after.query("SELECT id FROM t ORDER BY id")
		var ids: Array = after.query_result.map(func(row): return row.id)
		survived = survived and ids == ["committed"]
		after.close_db()
	_check(reached and code != 0 and survived, "after a process is killed from outside in the middle of a write transaction the database reopens intact: committed row kept, uncommitted row gone")
	print("PROTO_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _hold_lock(path: String, milliseconds: int) -> void:
	var other = _open(path)
	other.query("BEGIN IMMEDIATE")
	OS.delay_msec(milliseconds)
	other.query("COMMIT")
	other.close_db()

func _crash(work: String) -> void:
	var db = _open(work.path_join("crash.sqlite"))
	db.query("CREATE TABLE t (id TEXT PRIMARY KEY)")
	db.query_with_bindings("INSERT INTO t (id) VALUES (?)", ["committed"])
	db.query("BEGIN IMMEDIATE")
	db.query_with_bindings("INSERT INTO t (id) VALUES (?)", ["uncommitted"])
	# Signal the parent, then stay inside the open transaction until it kills us.
	var marker := FileAccess.open(work.path_join("crash.ready"), FileAccess.WRITE)
	marker.store_string("ready")
	marker.close()
	while true:
		OS.delay_msec(200)

# ---- cost: database work on a worker thread, the main loop keeps running ----
func _perf(work: String) -> void:
	var path := work.path_join("perf.sqlite")
	var opened := Time.get_ticks_usec()
	var db = _open(path)
	_schema(db)
	var first := _commit(db, _request("req_0", "fp_0", 0, _body(1, 100000, ["rifle"], "rifle")))
	var first_read := _read(db, "user_proto", "shooter")
	print("INFO first_reply_since_engine_start_ms=", Time.get_ticks_msec(), " open_schema_first_commit_read_ms=", snappedf(float(Time.get_ticks_usec() - opened) / 1000.0, 0.1), " ok=", first.ok and first_read.ok)
	db.close_db()
	var reads := int(args.get("reads", "200"))
	var commits := int(args.get("commits", "100"))
	# Idle frames first, as the reference for main-thread hitches.
	frame_max_ms = 0.0
	frame_watch = true
	await create_timer(1.0).timeout
	var idle_max := frame_max_ms
	frame_max_ms = 0.0
	var worker := Thread.new()
	worker.start(_workload.bind(path, reads, commits))
	while worker.is_alive():
		await process_frame
	var busy_max := frame_max_ms
	frame_watch = false
	var report: Dictionary = worker.wait_to_finish()
	print("INFO worker_thread reads=", reads, " read_p50_ms=", report.read_p50, " read_p95_ms=", report.read_p95, " commits=", commits, " commit_p50_ms=", report.commit_p50, " commit_p95_ms=", report.commit_p95, " duplicates_ok=", report.duplicates_ok, " final_revision=", report.final_revision)
	print("INFO main_thread_max_frame_ms idle=", snappedf(idle_max, 0.1), " during_database_work=", snappedf(busy_max, 0.1))
	_check(report.ok and report.final_revision == commits + 1 and report.duplicates_ok, "workload on the worker thread completed with the expected final revision")
	await _hold()
	print("PROTO_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _workload(path: String, reads: int, commits: int) -> Dictionary:
	var db = _open(path)
	var read_times: Array = []
	var commit_times: Array = []
	var ok := db != null
	for index in reads:
		var started := Time.get_ticks_usec()
		ok = ok and _read(db, "user_proto", "shooter").ok
		read_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var revision := 1
	for index in commits:
		var started := Time.get_ticks_usec()
		var reply := _commit(db, _request("req_%d" % (index + 1), "fp_%d" % (index + 1), revision, _body(revision + 1, 100000 - index, ["rifle"], "rifle")))
		commit_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
		ok = ok and reply.ok
		revision += 1
	var duplicate := _commit(db, _request("req_1", "fp_1", 1, _body(2, 100000, ["rifle"], "rifle")))
	var final_revision := int(_read(db, "user_proto", "shooter").revision)
	db.close_db()
	return {"ok": ok, "read_p50": _percentile(read_times, 0.5), "read_p95": _percentile(read_times, 0.95), "commit_p50": _percentile(commit_times, 0.5), "commit_p95": _percentile(commit_times, 0.95), "duplicates_ok": duplicate.code == "DUPLICATE", "final_revision": final_revision}

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted := values.duplicate()
	sorted.sort()
	return snappedf(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * fraction)) - 1)], 0.01)
