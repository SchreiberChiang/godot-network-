extends SceneTree
## L2-B1: Godot itself calls the account service and the asset repository on
## Linux, and they reach the real PowerShell storage scripts through
## host/platform/posix_helper.gd and posix_process_owner.gd. No Operator, host or
## room is started; every account, password and asset here is a test value in a
## new folder under res://data.
## Usage: --headless --script res://tests/run_posix_storage.gd -- --mode=oneshot|resident
## Lines starting with "PASS"/"FAIL" are real runs against real helper processes.
## Lines starting with "PASS INJECTED"/"FAIL INJECTED" replace the owner's answer
## to "is it confirmed gone" with a refusal (no real process misbehaved) and are
## counted separately.
const Accounts = preload("res://host/core/account_service.gd")
const Assets = preload("res://host/core/asset_service.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Posix = preload("res://host/platform/posix_helper.gd")
const Owner = preload("res://host/platform/posix_process_owner.gd")
const DataRoot = preload("res://host/platform/posix_data_root.gd")
const Policy = preload("res://examples/shooter/asset_policy.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const PASSWORD := "L2b1-Test-Pass-01"
const SPACE := "shooter"

## The real owner, except that a test can make it answer "still running, cannot
## be confirmed gone" for chosen children (or for all of them).
class StubbornOwner extends Owner:
	var refuse_all := false
	var refuse_ids: Dictionary = {}
	func terminate(launch_id: String, keep_pipes := false) -> bool:
		if refuse_all or refuse_ids.has(launch_id):
			return false
		return super(launch_id, keep_pipes)
	func probe(launch_id: String) -> String:
		if refuse_all or refuse_ids.has(launch_id):
			return "running"
		return super(launch_id)

var passed := 0
var failed := 0
var injected_passed := 0
var injected_failed := 0
var mode := ""
var directory := ""
var owner
var accounts = Accounts.new()
var assets = Assets.new()
var admin := {}
var player := {}
var timings: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
	_run.call_deferred()

func check(value: bool, text: String) -> bool:
	if value:
		passed += 1
		print("PASS ", text)
	else:
		failed += 1
		print("FAIL ", text)
	return value

func check_injected(value: bool, text: String) -> void:
	if value:
		injected_passed += 1
		print("PASS INJECTED ", text)
	else:
		injected_failed += 1
		print("FAIL INJECTED ", text)

func finish() -> void:
	print("POSIX_STORAGE_RESULT mode=", mode, " passed=", passed, " failed=", failed, " injected_passed=", injected_passed, " injected_failed=", injected_failed)
	quit(0 if failed == 0 and injected_failed == 0 else 1)

func _timed(label: String, action: Callable) -> Variant:
	var started := Time.get_ticks_msec()
	var result: Variant = action.call()
	if not timings.has(label):
		timings[label] = []
	timings[label].append(Time.get_ticks_msec() - started)
	return result

func _mode_bits(path: String) -> int:
	return int(FileAccess.get_unix_permissions(path)) & 4095

func _children(filter := "") -> Array:
	var found: Array = []
	for name in DirAccess.get_directories_at("/proc"):
		if name.is_valid_int():
			var seen: Dictionary = owner.backend.identity(int(name))
			if not seen.is_empty() and int(seen.ppid) == OS.get_process_id() and (filter == "" or " ".join(seen.arguments).contains(filter)):
				found.append(int(name))
	return found

func _open_descriptors() -> int:
	var listing := DirAccess.open("/proc/self/fd")
	if listing == null:
		return -1
	listing.include_hidden = true
	listing.list_dir_begin()
	var count := 0
	while listing.get_next() != "":
		count += 1
	return count

func _files_under(path: String) -> Array:
	var found: Array = []
	for name in DirAccess.get_files_at(path):
		found.append(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		found.append_array(_files_under(path.path_join(name)))
	return found

func _folders_under(path: String) -> Array:
	var found: Array = [path]
	for name in DirAccess.get_directories_at(path):
		found.append_array(_folders_under(path.path_join(name)))
	return found

func _api(request: Dictionary) -> Dictionary:
	var result: Dictionary = accounts.execute(request)
	if Validator.validate_file(result, "res://schemas/account_response.schema.json") != "":
		check(false, "account response matches its schema: " + str(request.op))
	return result

func _run() -> void:
	if OS.get_name() != "Linux":
		print("NOT RUN posix storage driver (this is ", OS.get_name(), ")")
		print("POSIX_STORAGE_RESULT mode=", mode, " passed=0 failed=0 injected_passed=0 injected_failed=0 not_run=1")
		quit(0)
		return
	if not mode in ["oneshot", "resident"]:
		print("FAIL --mode must be oneshot or resident")
		quit(2)
		return
	OS.set_environment("ROOMKIT_STORAGE_MODE", "oneshot" if mode == "oneshot" else "")
	owner = StubbornOwner.new()
	Posix._owner = owner  # before any helper is started: the single holder for this run
	directory = Paths.absolute("res://data/l2b1-" + mode + "-" + Wire.uid())
	var load_average := FileAccess.open("/proc/loadavg", FileAccess.READ).get_buffer(64).get_string_from_utf8().strip_edges()
	print("INFO engine=", Engine.get_version_info().string, " mode=", mode, " ", owner.invariant_detail, " dependency=", Posix.dependency(), " shell=", OS.get_environment(Posix.SHELL_VARIABLE).get_file(), " loadavg=", load_average)
	print("POSIX_STORAGE_EVIDENCE_DIR=", directory)
	var descriptors_before := _open_descriptors()
	check(_children().is_empty(), "no child process exists before the first storage call")

	_dependency_failures()
	_protection_failures()
	if not _accounts_flow():
		finish()
		return
	if not _assets_flow():
		finish()
		return
	_restore_copy()
	await _bounded_calls()
	if mode == "resident":
		await _resident_behaviour()
		_blocked_worker()
	else:
		check(_children("storage_worker.ps1").is_empty() and Resident.for_database("sqlite_store.ps1", assets.repository.database, 10000).started_workers == 0 and Resident.for_database("account_store.ps1", accounts.database, 10000).started_workers == 0, "one-shot mode never started a resident worker")
	_unfinished_helper()

	# ---- stop and leftovers ----
	Resident.shutdown_all()
	check(_children().is_empty(), "after shutdown no child or zombie of this process remains (%d)" % _children().size())
	check(owner.launch_ids().is_empty() and owner.unheld_ids().is_empty(), "the owner holds no record after shutdown (%d held, %d unheld)" % [owner.launch_ids().size(), owner.unheld_ids().size()])
	var descriptors_after := _open_descriptors()
	check(descriptors_after == descriptors_before, "open file descriptors are back to the starting count (%d -> %d)" % [descriptors_before, descriptors_after])
	var loose: Array = []
	for folder in _folders_under(directory):
		if _mode_bits(folder) != 448:
			loose.append(folder.trim_prefix(directory))
	var files := _files_under(directory)
	for path in files:
		if _mode_bits(path) != 384:
			loose.append(path.trim_prefix(directory))
	check(_mode_bits(DataRoot.boundary()) == 448 and loose.is_empty(), "the data root and every test folder are 700 and every file is 600 (%d files; not matching: %s)" % [files.size(), str(loose)])
	var requests := files.filter(func(path): return path.get_file().begins_with("request-") or path.get_file().begins_with("helper-"))
	check(requests.is_empty(), "no request or helper file is left behind (%d)" % requests.size())
	var secrets := 0
	for path in files:
		var bytes := FileAccess.get_file_as_bytes(path)
		for secret in [PASSWORD, str(admin.get("token", "-")), str(player.get("token", "-"))]:
			if secret.length() >= 8 and _contains(bytes, secret.to_utf8_buffer()):
				secrets += 1
	check(secrets == 0, "no file of the test folder (databases included) contains the test password or a session token in clear (%d hits in %d files)" % [secrets, files.size()])
	for label in timings:
		var values: Array = timings[label]
		values.sort()
		print("INFO timing ", label, " n=", values.size(), " min=", values[0], "ms median=", values[values.size() / 2], "ms max=", values[-1], "ms")
	finish()

func _contains(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	var first := needle[0]
	var index := haystack.find(first)
	while index >= 0 and index + needle.size() <= haystack.size():
		if haystack.slice(index, index + needle.size()) == needle:
			return true
		index = haystack.find(first, index + 1)
	return false

# ---- the PowerShell path must come from trusted configuration ----
func _dependency_failures() -> void:
	var configured := OS.get_environment(Posix.SHELL_VARIABLE)
	DataRoot.prepare(directory)
	var not_executable := directory.path_join("not-a-shell")
	var placeholder := FileAccess.open(not_executable, FileAccess.WRITE)
	placeholder.store_string("#!/bin/false
")
	placeholder.close()
	FileAccess.set_unix_permissions(not_executable, 384)  # octal 600: exists, not executable
	var all_refused := true
	for value in ["", "pwsh", "/nonexistent/roomkit/pwsh", not_executable]:
		OS.set_environment(Posix.SHELL_VARIABLE, value)
		var probe = Accounts.new()
		var result: Dictionary = probe.initialize(directory.path_join("dependency"))
		var direct: Dictionary = Helper.execute_input("account_store.ps1", ["-Database", directory.path_join("dependency/accounts.sqlite")], "{}", 5000)
		all_refused = all_refused and Posix.dependency() == "HELPER_DEPENDENCY_MISSING" and not result.ok and result.code == "STORAGE_UNAVAILABLE" and direct.code == "HELPER_DEPENDENCY_MISSING" and not Resident.enabled()
	OS.set_environment(Posix.SHELL_VARIABLE, configured)
	check(all_refused and _children().is_empty() and not FileAccess.file_exists(directory.path_join("dependency/accounts.sqlite")), "a missing, relative, absent or non-executable PowerShell path is reported as a dependency failure; nothing is started or created")
	check(Posix.dependency() == "", "with the configured path the helper dependencies are satisfied")

# ---- protection failures stop the service (real refusals, nothing injected) ----
func _protection_failures() -> void:
	DataRoot.prepare(directory)
	var real := directory.path_join("real")
	DataRoot.prepare(real)
	var alias := directory.path_join("alias")
	var linked := DirAccess.open(directory).create_link(real, alias) == OK
	var through = Accounts.new()
	var refused: Dictionary = through.initialize(alias.path_join("store"))
	check(linked and refused.code == "PRIVATE_DATA_FAILED" and through.execute({"op": "setup.status"}).code == "STORAGE_UNAVAILABLE" and not DirAccess.dir_exists_absolute(real.path_join("store")), "an account folder reached through a link is refused; the service stays unusable and nothing is created behind the link")
	DirAccess.remove_absolute(alias)
	var outside := directory.path_join("outside.sqlite")
	var trap := directory.path_join("trap")
	DataRoot.prepare(trap)
	var trapped := DirAccess.open(trap).create_link(outside, trap.path_join("assets.sqlite")) == OK
	var repository = Repository.new()
	var denied: Dictionary = repository.initialize(trap, "assets.sqlite")
	check(trapped and denied.code == "PRIVATE_DATA_FAILED" and not FileAccess.file_exists(outside) and repository.execute({"op": "asset.read", "user_id": "x", "space_id": SPACE}).code == "STORAGE_UNAVAILABLE", "a database name that is a link is refused before any helper opens it; the link target is not created")
	DirAccess.remove_absolute(trap.path_join("assets.sqlite"))
	var elsewhere = Repository.new()
	check(elsewhere.initialize("/tmp/roomkit-l2b1-outside", "assets.sqlite").code == "PRIVATE_DATA_FAILED" and not DirAccess.dir_exists_absolute("/tmp/roomkit-l2b1-outside"), "a folder outside the project data folder is refused and not created")
	check(_children().is_empty(), "the refused initialisations started no helper")

# ---- new account database: administrator, invitation, registration, login, session ----
func _accounts_flow() -> bool:
	var root := directory.path_join("store")
	var ready: Dictionary = _timed("accounts init (cold)", func(): return accounts.initialize(root))
	if not check(ready.ok, "a new account database initialises through Godot (%s)" % ready.get("code", "")):
		return false
	check(_mode_bits(accounts.database) == 384 and _mode_bits(root) == 448, "the account database is 600 inside a 700 folder right after initialisation")
	check(not _api({"op": "setup.status"}).initialized, "a new database reports that setup is required")
	var setup := {"op": "setup.admin", "username": "operator", "password": PASSWORD, "display_name": "管理员 Ω"}
	check(_timed("setup.admin", func(): return _api(setup)).ok and _api(setup).code == "SETUP_COMPLETE", "the administrator is created once; a second attempt is refused")
	admin = _timed("login", func(): return _api({"op": "account.login", "username": "operator", "password": PASSWORD, "client_ip": "127.0.0.1"}))
	if not check(admin.ok and admin.identity.role == "admin", "the administrator logs in with the real password check"):
		return false
	var invitation: Dictionary = _api({"op": "invite.create", "token": admin.token, "uses": 2, "expires": int(Time.get_unix_time_from_system()) + 3600, "reason": "测试发放"})
	if not check(invitation.ok and str(invitation.get("invite_code", "")) != "", "the administrator creates an invitation"):
		return false
	var registered: Dictionary = _timed("register", func(): return _api({"op": "account.register", "username": "Alice", "password": PASSWORD, "display_name": "玩家 一 🎮", "invite_code": invitation.invite_code, "client_ip": "127.0.0.2"}))
	check(registered.ok and registered.identity.role == "player", "a player registers with the invitation")
	check(_api({"op": "account.register", "username": "ALICE", "password": PASSWORD, "display_name": "again", "invite_code": invitation.invite_code, "client_ip": "127.0.0.3"}).code == "USERNAME_UNAVAILABLE", "the same user name in another case is refused")
	check(_api({"op": "account.login", "username": "alice", "password": "wrong-password-01", "client_ip": "127.0.0.2"}).code == "AUTH_FAILED", "a wrong password is refused")
	# While a login runs, no child command line may carry the password.
	var leaked := false
	var thread := Thread.new()
	thread.start(func(): return _timed("login", func(): return accounts.execute({"op": "account.login", "username": "alice", "password": PASSWORD, "client_ip": "127.0.0.2"})))
	var observed := 0
	while thread.is_alive():
		for pid in _children():
			var line := " ".join(owner.backend.identity(pid).get("arguments", []))
			observed += 1 if line.contains("account_store.ps1") else 0
			leaked = leaked or line.contains(PASSWORD) or line.contains(Marshalls.utf8_to_base64(PASSWORD))
		OS.delay_msec(1)
	player = thread.wait_to_finish()
	if not check(player.ok and player.identity.user_id == registered.identity.user_id and player.identity.display_name == "玩家 一 🎮", "the player logs in and gets the registered identity with its Unicode name intact"):
		return false
	check(observed > 0 and not leaked, "the helper's command line was observed during the login and never contained the password (%d observations)" % observed)
	check(_api({"op": "account.login", "username": "alice", "password": PASSWORD, "client_ip": "127.0.0.2"}).code == "ALREADY_LOGGED_IN", "a second active login is refused")
	var session: Dictionary = _timed("session.authenticate (first)", func(): return accounts.authenticate(player.token))
	check(session.ok and session.identity.user_id == player.identity.user_id, "the session token is verified")
	for index in 6:
		_timed("session.authenticate (repeat)", func(): return accounts.authenticate(player.token))
	check(accounts.authenticate("0".repeat(64)).code == "AUTH_FAILED", "an unknown token is refused")
	var listed: Dictionary = _api({"op": "account.list", "token": admin.token})
	check(listed.ok and listed.accounts.size() == 2, "the account database holds exactly the two accounts (%d)" % listed.get("accounts", []).size())
	check(_api({"op": "account.list", "token": player.token}).code == "ADMIN_REQUIRED", "a player cannot list accounts")
	var account_store: RefCounted = Resident.for_database("account_store.ps1", accounts.database, 10000)
	if mode == "resident":
		check(account_store.started_workers == 1 and account_store.requests >= 8 and account_store.fallbacks == 0 and _children("storage_worker.ps1").size() == 1, "session checks were served by exactly one account worker, without fallback")
	return true

# ---- new asset database: grant, purchase, repeated request, conflict, balance ----
func _assets_flow() -> bool:
	var configuration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	var root := directory.path_join("store")
	var ready: Dictionary = _timed("assets init (cold)", func(): return assets.initialize(root, configuration))
	if not check(ready.ok, "a new asset database initialises through Godot (%s)" % ready.get("code", "")):
		return false
	check(_mode_bits(assets.repository.database) == 384, "the asset database is 600 right after initialisation")
	var user: Dictionary = player.identity
	var policy = Policy.new()
	var lobby := {"location": "lobby"}
	var grant := {"kind": "adjust", "credits": 300, "experience": 50, "reason": "测试发放 ' 中文", "request_id": "grant_1"}
	check(assets.adjust(user, user.user_id, "shooter", grant).code == "ADMIN_REQUIRED", "a player cannot grant credits")
	if not check(_timed("asset grant", func(): return assets.adjust(admin.identity, user.user_id, "shooter", grant)).ok, "the administrator grants 300 credits"):
		return false
	check(assets.adjust(admin.identity, user.user_id, "shooter", grant).code == "DUPLICATE" and assets.read(user.user_id, "shooter").state.credits == 300, "repeating the grant returns the receipt and does not change the balance")
	var purchase := {"kind": "purchase", "item_id": "smg", "request_id": "purchase_1"}
	check(assets.perform(user, "shooter", purchase, policy, {"location": "room", "life_state": "alive"}).code == "ASSET_OPERATION_DENIED", "the game policy denies a purchase during a round")
	if not check(_timed("asset purchase", func(): return assets.perform(user, "shooter", purchase, policy, lobby)).ok, "the purchase commits"):
		return false
	check(assets.perform(user, "shooter", purchase, policy, lobby).code == "DUPLICATE", "repeating the same purchase request returns the receipt")
	var conflict := purchase.duplicate(true)
	conflict.item_id = "shotgun"
	check(assets.perform(user, "shooter", conflict, policy, lobby).code == "REQUEST_CONFLICT", "the same request id with another item is a conflict")
	var state: Dictionary = _timed("asset read", func(): return assets.read(user.user_id, "shooter")).state
	check(state.credits == 200 and "smg" in state.owned and not "shotgun" in state.owned, "the balance is 200 and only the purchased item is owned")
	for index in 6:
		_timed("asset read", func(): return assets.read(user.user_id, "shooter"))
	var reopened = Assets.new()
	check(reopened.initialize(root, configuration).ok and reopened.read(user.user_id, "shooter").state.credits == 200 and reopened.perform(user, "shooter", purchase, policy, lobby).code == "DUPLICATE", "a new service instance reopens the database: balance and receipts are still there")
	check(reopened.read(admin.identity.user_id, "shooter").state.credits == 0, "another user's wallet is separate")
	var asset_store: RefCounted = Resident.for_database("sqlite_store.ps1", assets.repository.database, 10000)
	if mode == "resident":
		check(asset_store.started_workers == 1 and asset_store.fallbacks == 0 and _children("storage_worker.ps1").size() == 2, "asset reads and commits were served by exactly one asset worker (two workers in total, one per database)")
	return true

# ---- a database copied in with open permissions is protected before use ----
func _restore_copy() -> void:
	Resident.shutdown_all()  # so the account database and its side files are at rest
	var restored := directory.path_join("restored")
	DataRoot.prepare(restored)
	var copy := restored.path_join("accounts.sqlite")
	var copied := DirAccess.copy_absolute(accounts.database, copy) == OK and FileAccess.set_unix_permissions(copy, 420) == OK  # octal 644
	var service = Accounts.new()
	var opened: Dictionary = service.initialize(restored)
	check(copied and opened.ok and _mode_bits(copy) == 384, "a copied database that arrives as 644 is 600 before the service reports ready")
	var again: Dictionary = service.execute({"op": "account.login", "username": "operator", "password": "wrong-password-01", "client_ip": "127.0.0.9"})
	check(service.execute({"op": "setup.status"}).initialized and again.code == "AUTH_FAILED", "the copied database is usable and still holds the administrator")

# ---- one-shot deadline ----
func _bounded_calls() -> void:
	var before := _children().size()
	var started := Time.get_ticks_msec()
	var late: Dictionary = Helper.execute_input("account_store.ps1", ["-Database", accounts.database], JSON.stringify({"op": "setup.status"}), 150)
	var elapsed := Time.get_ticks_msec() - started
	check(late.code == "HELPER_TIMEOUT" and elapsed < 5000 and _children().size() == before, "a one-shot helper that misses a 150 ms deadline is ended and reported as HELPER_TIMEOUT within %d ms; no process is left" % elapsed)
	var never: Dictionary = Helper.execute_input("account_store.ps1", ["-Database", accounts.database], "", 4000)
	check(not never.get("ok", true) and _children().size() == before, "a helper given an empty request fails cleanly (%s) and leaves no process" % never.get("code", ""))
	check(Helper.execute("storage_worker.ps1", [], directory, 2000).code == "HELPER_FAILED" and Helper.execute("../tests/fixtures/posix_child.sh", [], directory, 2000).code == "HELPER_FAILED" and _children().size() == before, "a script that is not one of the one-shot helpers is refused without starting anything")
	check(_api({"op": "setup.status"}).initialized, "the account service still answers after the failed calls")
	await process_frame

# ---- resident workers: fallback, restart, queue, idle exit, stop ----
func _resident_behaviour() -> void:
	var repository = assets.repository
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", repository.database, 10000)
	check(repository.prewarm().ok and store.worker_pid() > 0, "the asset worker runs again after the earlier shutdown")
	var resident := _sequence("parity-resident", func(request): return repository.execute(request))
	var oneshot := _sequence("parity-oneshot", func(request): return repository.execute_oneshot(request))
	check(resident.size() == oneshot.size() and resident == oneshot, "resident and one-shot replies are identical for the same operation sequence")
	# Deadline: the worker is ended through the owner, the commit is repeated once one-shot.
	var fallbacks: int = store.fallbacks
	var timeouts: int = store.timeouts
	var started: int = store.started_workers
	var old_pid: int = store.worker_pid()
	store.timeout_ms = 1
	var late := _commit_once(repository, "timeout-user", "t1")
	store.timeout_ms = 10000
	check(late.ok and late.get("code", "") in ["", "DUPLICATE"] and _revision(repository, "timeout-user") == 1, "a commit whose worker missed the deadline lands exactly once through the fallback (%s)" % late.get("code", ""))
	check(store.timeouts == timeouts + 1 and store.fallbacks == fallbacks + 1 and owner.backend.identity(old_pid).is_empty() and not store.blocked(), "the late worker was ended and reaped; timeout and fallback are counted")
	check(repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE}).ok and store.started_workers == started + 1, "the next request starts a fresh worker")
	# Same for the account worker: the session check falls back and still answers.
	var account_store: RefCounted = Resident.for_database("account_store.ps1", accounts.database, 10000)
	account_store.timeout_ms = 1
	var session: Dictionary = accounts.authenticate(player.token)
	account_store.timeout_ms = 10000
	check(session.ok and session.identity.user_id == player.identity.user_id and account_store.timeouts >= 1, "a session check whose worker missed the deadline is answered by the one-shot path")
	# Crash while idle: an outside SIGKILL (sent by bash's builtin kill, itself an owned child).
	# pwsh is multi-threaded: its main thread shows as a zombie before the other
	# threads have ended, and until then the process cannot be reaped and still
	# counts as running. A request in that window is written to the dying worker
	# and falls back once; the request after it must find it reaped and replace it.
	started = store.started_workers
	var fallbacks_before: int = store.fallbacks
	var victim: int = store.worker_pid()
	var struck := _external_kill(victim)
	var state_after: String = owner.backend.identity(victim).get("state", "gone")
	var served: Dictionary = repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE})
	var replaced_at_once: bool = store.started_workers == started + 1 and store.fallbacks == fallbacks_before
	var fell_back: bool = store.started_workers == started and store.fallbacks == fallbacks_before + 1
	var next: Dictionary = repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE}) if fell_back else served
	check(struck and served.get("ok", false) and next.get("ok", false) and (replaced_at_once or (fell_back and store.started_workers == started + 1)) and owner.backend.identity(victim).is_empty(), "a worker killed from outside while idle is reaped and replaced; every request is answered (signal sent=%s, state after signal=%s, replaced on the first request=%s, one fallback then replaced=%s, workers started +%d)" % [struck, state_after, replaced_at_once, fell_back, store.started_workers - started])
	# Crash during a commit: committed or repeated as DUPLICATE, never twice.
	var thread := Thread.new()
	thread.start(_commit_once.bind(repository, "crash-user", "k1"))
	OS.delay_msec(4)
	_kill_without_waiting(store.worker_pid())
	while thread.is_alive():
		await process_frame
	var crashed: Dictionary = thread.wait_to_finish()
	check(crashed.ok and _revision(repository, "crash-user") == 1, "a commit interrupted by a worker crash lands exactly once (%s)" % crashed.get("code", ""))
	# Writers on both paths at once.
	var threads: Array = []
	for index in 6:
		var writer := Thread.new()
		writer.start(_commit_cycles.bind(repository, "mixed-%d" % index, 2, index % 2 == 1))
		threads.append(writer)
	var all_ok := true
	for writer in threads:
		while writer.is_alive():
			await process_frame
		all_ok = writer.wait_to_finish() and all_ok
	var chains := true
	for index in 6:
		chains = chains and _revision(repository, "mixed-%d" % index) == 2
	check(all_ok and chains and _children("storage_worker.ps1").filter(func(pid): return " ".join(owner.backend.identity(pid).arguments).contains(repository.database)).size() == 1, "three resident and three one-shot writers all commit, every user has exactly 2 revisions, and the database still has one worker")
	var results: Array = []
	threads.clear()
	var body := Format.canonical({"revision": 1, "credits": 1, "experience": 0, "owned": [], "profiles": {}})
	var request := {"op": "asset.commit", "user_id": "same", "space_id": SPACE, "request_id": "same-1", "fingerprint": "same", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}
	for index in 6:
		var racer := Thread.new()
		racer.start(func(): return repository.execute(request) if index % 2 == 0 else repository.execute_oneshot(request))
		threads.append(racer)
	for racer in threads:
		while racer.is_alive():
			await process_frame
		results.append(racer.wait_to_finish())
	var fresh := results.filter(func(r): return r.ok and r.get("code", "") == "").size()
	var duplicate := results.filter(func(r): return r.ok and r.get("code", "") == "DUPLICATE").size()
	check(fresh == 1 and duplicate == 5 and _revision(repository, "same") == 1, "six concurrent copies of one request across both paths: one commit, five receipts (%d/%d)" % [fresh, duplicate])
	# Queue limit.
	store.queue_limit = 0
	var refused: Dictionary = repository.execute({"op": "asset.read", "user_id": "queue", "space_id": SPACE})
	store.queue_limit = Resident.QUEUE_LIMIT
	check(not refused.ok and refused.code == "STORAGE_UNAVAILABLE", "a full queue refuses with STORAGE_UNAVAILABLE instead of waiting")
	# Idle exit and restart; path case.
	var lower = Repository.new()
	var upper = Repository.new()
	check(lower.initialize(directory.path_join("case/idle"), "assets.sqlite").ok and upper.initialize(directory.path_join("case/IDLE"), "assets.sqlite").ok, "two folders whose names differ only in case both initialise")
	var lower_store: RefCounted = Resident.for_database("sqlite_store.ps1", lower.database, 10000)
	var upper_store: RefCounted = Resident.for_database("sqlite_store.ps1", upper.database, 10000)
	lower_store.idle_seconds = 2
	var lower_body := Format.canonical({"revision": 1, "credits": 11, "experience": 0, "owned": [], "profiles": {}})
	var wrote: Dictionary = lower.execute({"op": "asset.commit", "user_id": "case", "space_id": SPACE, "request_id": "c1", "fingerprint": "c1", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": lower_body})
	check(lower_store != upper_store and wrote.ok and upper.prewarm().ok and lower_store.worker_pid() != upper_store.worker_pid() and _revision(lower, "case") == 1 and _revision(upper, "case") == 0, "paths differing only in case are separate databases with separate workers; a write to one is not seen in the other")
	var idle_pid: int = lower_store.worker_pid()
	var until := Time.get_ticks_msec() + 10000
	while owner.backend.identity(idle_pid).get("state", "Z") != "Z" and Time.get_ticks_msec() < until:
		await process_frame
	check(owner.backend.identity(idle_pid).get("state", "") == "Z", "an idle worker exits by itself and stays reserved (zombie) until the owner looks at it")
	check(lower.execute({"op": "asset.read", "user_id": "case", "space_id": SPACE}).ok and lower_store.started_workers == 2 and owner.backend.identity(idle_pid).is_empty(), "the next request reaps it and starts a new worker")
	# Mode switch and stop.
	OS.set_environment("ROOMKIT_STORAGE_MODE", "oneshot")
	var requests: int = store.requests
	check(not Resident.enabled() and repository.execute({"op": "asset.read", "user_id": "mode", "space_id": SPACE}).ok and store.requests == requests, "ROOMKIT_STORAGE_MODE=oneshot bypasses the worker")
	OS.set_environment("ROOMKIT_STORAGE_MODE", "")
	var kills: int = owner.kills_sent()
	Resident.shutdown_all()
	check(store.worker_pid() == -1 and _children().is_empty(), "shutdown_all stops every worker; no child remains")
	print("INFO shutdown sent ", owner.kills_sent() - kills, " forced stops (0 means every worker left on request)")
	started = store.started_workers
	check(repository.execute({"op": "asset.read", "user_id": "mode", "space_id": SPACE}).ok and store.started_workers == started + 1, "the resident path restarts after a shutdown")

# ---- injected: the owner refuses to confirm that the old worker is gone ----
func _blocked_worker() -> void:
	var repository = assets.repository
	var store: RefCounted = Resident.for_database("sqlite_store.ps1", repository.database, 10000)
	repository.prewarm()
	var started: int = store.started_workers
	var fallbacks: int = store.fallbacks
	var old_worker: String = store._launch
	owner.refuse_ids[old_worker] = true
	store.stop()
	var answered: Dictionary = repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE})
	check_injected(store.blocked() and store.started_workers == started and store.worker_pid() > 0, "while the old worker cannot be confirmed gone no replacement is started and its record is kept")
	check_injected(answered.ok and store.fallbacks == fallbacks + 1, "requests are still answered, through the one-shot path")
	owner.refuse_ids.erase(old_worker)
	check_injected(repository.execute({"op": "asset.read", "user_id": "timeout-user", "space_id": SPACE}).ok and not store.blocked() and store.started_workers == started + 1, "once the old worker is confirmed gone a new worker is started")

# ---- injected: a one-shot helper that cannot be confirmed gone ----
func _unfinished_helper() -> void:
	var held: int = owner.launch_ids().size()
	owner.refuse_all = true
	var result: Dictionary = Helper.execute_input("account_store.ps1", ["-Database", accounts.database], JSON.stringify({"op": "setup.status"}), 4000)
	owner.refuse_all = false
	var kept: Array = owner.launch_ids()
	var parked: Array = Posix.parked()
	check_injected(result.code == "HELPER_UNFINISHED" and kept.size() == held + 1 and parked.size() == 1 and kept.has(parked[0]), "a helper that cannot be confirmed gone is reported as HELPER_UNFINISHED; its record is kept and parked, not released")
	var working: bool = accounts.execute({"op": "setup.status"}).get("initialized", false)
	check_injected(working and Posix.parked().is_empty() and not owner.launch_ids().has(parked[0]), "the next helper start releases the parked record once the owner confirms it; the service works again")

## Same signal, but returns as soon as it was sent (used while a request is in
## flight, where the store itself must notice the loss).
func _kill_without_waiting(pid: int) -> void:
	if pid <= 0:
		return
	owner.trust("/bin/bash")
	var launch_id := Wire.uid()
	if owner.launch(launch_id, "/bin/bash", PackedStringArray(["-c", "kill -KILL \"$1\"", "bash", str(pid)])).ok:
		while owner.probe(launch_id) == "running":
			OS.delay_msec(1)
		owner.forget(launch_id)

func _external_kill(pid: int) -> bool:
	if pid <= 0:
		return false
	owner.trust("/bin/bash")
	var launch_id := Wire.uid()
	if not owner.launch(launch_id, "/bin/bash", PackedStringArray(["-c", "kill -KILL \"$1\"", "bash", str(pid)])).ok:
		return false
	var until := Time.get_ticks_msec() + 5000
	while owner.probe(launch_id) == "running" and Time.get_ticks_msec() < until:
		OS.delay_msec(2)
	var sent: bool = owner.exit_code(launch_id) == 0
	owner.forget(launch_id)
	# The signal is delivered asynchronously: wait until the target has really
	# ended (it stays a zombie until its owner looks at it).
	until = Time.get_ticks_msec() + 5000
	while sent and owner.backend.identity(pid).get("state", "Z") != "Z" and Time.get_ticks_msec() < until:
		OS.delay_msec(2)
	return sent

func _sequence(user: String, send: Callable) -> Array:
	var replies: Array = []
	var body := Format.canonical({"revision": 1, "credits": 5, "experience": 0, "owned": ["rifle"], "profiles": {}})
	replies.append(send.call({"op": "asset.read", "user_id": user, "space_id": SPACE}))
	replies.append(send.call({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1"}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1"}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "f1", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r1", "fingerprint": "other", "actor_id": "test", "command": "{}", "expected_revision": 1, "body": body}))
	replies.append(send.call({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "r2", "fingerprint": "f2", "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body}))
	replies.append(send.call({"op": "asset.read", "user_id": user, "space_id": SPACE}))
	return replies

func _commit_once(repository, user: String, request_id: String) -> Dictionary:
	var body := Format.canonical({"revision": 1, "credits": 7, "experience": 0, "owned": [], "profiles": {}})
	return repository.execute({"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": request_id, "fingerprint": request_id, "actor_id": "test", "command": "{}", "expected_revision": 0, "body": body})

func _commit_cycles(repository, user: String, cycles: int, oneshot: bool) -> bool:
	for index in cycles:
		var snapshot: Dictionary = repository.execute_oneshot({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "c%d" % index, "fingerprint": "f%d" % index}) if oneshot else repository.execute({"op": "asset.snapshot", "user_id": user, "space_id": SPACE, "request_id": "c%d" % index, "fingerprint": "f%d" % index})
		if not snapshot.get("ok", false):
			return false
		var state: Dictionary = {"revision": 0, "credits": 0} if str(snapshot.body) == "" else JSON.parse_string(str(snapshot.body))
		var body := Format.canonical({"revision": int(state.revision) + 1, "credits": int(state.credits) + 1, "experience": 0, "owned": [], "profiles": {}})
		var commit := {"op": "asset.commit", "user_id": user, "space_id": SPACE, "request_id": "c%d" % index, "fingerprint": "f%d" % index, "actor_id": "test", "command": "{}", "expected_revision": int(state.revision), "body": body}
		var result: Dictionary = repository.execute_oneshot(commit) if oneshot else repository.execute(commit)
		if not result.get("ok", false):
			return false
	return true

func _revision(repository, user: String) -> int:
	var stored: Dictionary = repository.execute_oneshot({"op": "asset.read", "user_id": user, "space_id": SPACE})
	var body := str(stored.get("body", ""))
	var state: Variant = JSON.parse_string(body) if body != "" else null
	return int(state.revision) if state is Dictionary else 0
