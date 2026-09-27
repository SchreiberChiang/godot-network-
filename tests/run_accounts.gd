extends SceneTree
const Service = preload("res://host/core/account_service.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0
var directory := ""
var service = Service.new()
var admin := ""
var player := ""
var user_id := ""
const PASSWORD := "Abcd1234"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-accounts-" + Wire.uid())
	print("ACCOUNT_EVIDENCE_DIR=", directory)
	if not check(service.initialize(directory).ok, "real private SQLite initializes"):
		finish()
		return
	check(not call_api({"op": "setup.status"}).initialized, "initial setup required")
	check(service.execute({"op": "account.login", "username": "bad", "password": PASSWORD}).code == "INVALID_ACCOUNT_REQUEST", "network origin required for rate-limited operation")
	check(service.execute({"op": "account.login", "username": "bad", "password": PASSWORD, "client_ip": "local", "role": "admin"}).code == "INVALID_ACCOUNT_REQUEST", "claimed role rejected by schema")
	check(register("before_setup", "0".repeat(32)).code == "SETUP_REQUIRED", "registration cannot precede admin setup")
	check(service.execute({"op": "setup.admin", "username": "operator", "password": "Abc1234", "display_name": "管理员"}).code == "INVALID_ACCOUNT_REQUEST", "seven-character administrator password rejected")
	var setup_request := {"op": "setup.admin", "username": "operator", "password": PASSWORD, "display_name": "管理员"}
	var setup_results: Array = await compete([setup_request, setup_request])
	check(count_ok(setup_results) == 1 and count_code(setup_results, "SETUP_COMPLETE") == 1, "concurrent first admin setup creates exactly one administrator")
	check(call_api({"op": "setup.status"}).initialized, "setup state persists")
	var login_admin := login("operator")
	if not check(login_admin.ok, "real password administrator login"):
		finish()
		return
	admin = login_admin.token
	check(login_admin.identity.role == "admin", "admin role is backend assigned")
	check(call_api(setup_request).code == "SETUP_COMPLETE", "setup cannot create second administrator")
	var invitation := invite(10)
	if not check(invitation.ok, "administrator creates invitation"):
		finish()
		return
	check(call_api({"op": "account.register", "username": "short_user", "password": "Abc1234", "display_name": "短密码", "invite_code": invitation.invite_code, "client_ip": "127.0.0.2"}).code == "INVALID_ACCOUNT_REQUEST", "seven-character player password rejected")
	var first := register("Alice", invitation.invite_code, "127.0.0.2")
	if not check(first.ok, "invite registers real player"):
		finish()
		return
	user_id = first.identity.user_id
	check(first.identity.role == "player", "registration cannot produce admin")
	check(register("ALICE", invitation.invite_code, "127.0.0.3").code == "USERNAME_UNAVAILABLE", "usernames are case insensitive")
	var second := register("Bob", invitation.invite_code, "127.0.0.4")
	check(second.ok and second.identity.user_id != user_id, "stable IDs separate identities from nickname")
	check(login("alice", "wrong-password-test").code == "AUTH_FAILED", "incorrect password refused")
	var first_login := login("ALICE")
	if not check(first_login.ok, "case normalized player login"):
		finish()
		return
	player = first_login.token
	check(first_login.identity.user_id == user_id, "login retains registered stable identity")
	check(login("alice").code == "ALREADY_LOGGED_IN", "duplicate active login rejected")
	check(call_api({"op": "session.authenticate", "token": player}).ok, "original session remains valid after duplicate login")
	check(call_api({"op": "invite.create", "token": player, "reason": "attack"}).code == "ADMIN_REQUIRED", "player cannot create invites")
	check(call_api({"op": "account.list", "token": player}).code == "ADMIN_REQUIRED", "player cannot list accounts")
	check(call_api({"op": "account.get", "token": player, "user_id": second.identity.user_id}).code == "ADMIN_REQUIRED", "cross-account detail denied")
	check(call_api({"op": "account.rename", "token": player, "user_id": second.identity.user_id, "display_name": "stolen"}).code == "ADMIN_REQUIRED", "cross-account rename denied")
	var own := call_api({"op": "account.get", "token": player})
	check(own.ok and own.account.active and own.account.username == "alice", "own detail includes live session state")
	check(call_api({"op": "account.rename", "token": player, "display_name": "玩家 ' 中文"}).ok, "own nickname supports bound Unicode and quotes")
	check(call_api({"op": "account.rename", "token": admin, "user_id": user_id, "display_name": "管理修改", "reason": "用户请求"}).ok, "admin rename with reason")
	check(call_api({"op": "session.authenticate", "token": player}).identity.display_name == "管理修改", "existing session reads updated name")
	check(call_api({"op": "account.change_password", "token": player, "password": PASSWORD, "new_password": "Abc1234", "client_ip": "127.0.0.2"}).code == "INVALID_ACCOUNT_REQUEST", "seven-character replacement password rejected")
	check(call_api({"op": "account.change_password", "token": player, "password": PASSWORD, "new_password": "Newp1234", "client_ip": "127.0.0.2"}).ok, "eight-character player password change commits")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "password change revokes active token")
	check(login("alice").code == "AUTH_FAILED", "old password rejected after change")
	var changed := login("alice", "Newp1234")
	check(changed.ok, "new password authenticates")
	player = changed.get("token", "0".repeat(64))
	check(call_api({"op": "account.reset_password", "token": admin, "user_id": user_id, "password": "Abc1234", "reason": "人工恢复"}).code == "INVALID_ACCOUNT_REQUEST", "seven-character administrator reset rejected")
	check(call_api({"op": "account.reset_password", "token": admin, "user_id": user_id, "password": "Rset1234", "reason": "人工恢复"}).ok, "administrator resets to eight-character password")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "reset revokes active token")
	var reset_login := login("alice", "Rset1234")
	check(reset_login.ok, "reset credential authenticates")
	player = reset_login.get("token", "0".repeat(64))
	check(call_api({"op": "account.ban", "token": admin, "user_id": user_id, "until": int(Time.get_unix_time_from_system()) + 600, "reason": "测试临时封禁"}).ok, "temporary ban commits")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "ban revokes existing session immediately")
	check(login("alice", "Rset1234").code == "ACCOUNT_BANNED", "banned credentials denied")
	check(fixture("expire_bans"), "real database clock fixture expires temporary ban")
	var unexpired := login("alice", "Rset1234")
	check(unexpired.ok, "expired temporary ban permits login")
	player = unexpired.get("token", "0".repeat(64))
	check(call_api({"op": "account.ban", "token": admin, "user_id": user_id, "until": 0, "reason": "测试永久封禁"}).ok, "permanent ban commits")
	var banned := call_api({"op": "account.get", "token": admin, "user_id": user_id})
	check(banned.account.banned and banned.account.ban_until == -1 and not banned.account.active, "ban status and session state visible to administrator")
	check(call_api({"op": "account.unban", "token": admin, "user_id": user_id, "reason": "解除测试"}).ok, "administrator unbans")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "unban never resurrects revoked token")
	check(call_api({"op": "account.ban", "token": admin, "user_id": login_admin.identity.user_id, "reason": "self"}).code == "ADMIN_SELF_PROTECTION", "only administrator cannot accidentally ban self")
	var concurrent_login := {"op": "account.login", "username": "alice", "password": "Rset1234", "client_ip": "127.0.0.5"}
	var login_race: Array = await compete([concurrent_login, concurrent_login])
	check(count_ok(login_race) == 1 and count_code(login_race, "ALREADY_LOGGED_IN") == 1, "simultaneous real password logins produce exactly one token")
	for result in login_race:
		if result.ok:
			player = result.token
	check(call_api({"op": "session.logout", "token": player}).ok, "logout commits")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "logged out token rejected")
	var once := invite(1)
	var users: Array = []
	for name in ["last_invite_a", "last_invite_b"]:
		users.append({"op": "account.register", "username": name, "password": PASSWORD, "display_name": name, "invite_code": once.invite_code, "client_ip": "127.0.0.6"})
	var registrations: Array = await compete(users)
	check(count_ok(registrations) == 1 and count_code(registrations, "INVITE_INVALID") == 1, "concurrent registrations cannot consume one-use invite twice")
	var revoked := invite(2)
	check(call_api({"op": "invite.revoke", "token": admin, "invite_id": revoked.invite_id, "reason": "撤销测试"}).ok, "invitation revoked")
	check(register("revoked_user", revoked.invite_code, "127.0.0.7").code == "INVITE_INVALID", "revoked invitation refused")
	check(fixture("expire_invites"), "real database fixture expires invitations")
	check(register("expired_user", invitation.invite_code, "127.0.0.8").code == "INVITE_INVALID", "expired invitation refused")
	await rate_limits()
	var relogin := login("alice", "Rset1234")
	check(relogin.ok, "login before explicit session expiry")
	player = relogin.get("token", "0".repeat(64))
	check(fixture("expire_sessions"), "real database fixture expires player sessions")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "expired token rejected")
	var next_login := login("alice", "Rset1234")
	check(next_login.ok, "expired session no longer blocks login")
	player = next_login.get("token", "0".repeat(64))
	check(call_api({"op": "session.revoke_all", "token": admin, "user_id": "", "reason": "维护撤销"}).ok, "administrator can revoke all player sessions")
	check(not call_api({"op": "session.authenticate", "token": player}).ok, "bulk revocation invalidates player session")
	check(call_api({"op": "session.authenticate", "token": admin}).ok, "bulk player revocation preserves operator session")
	var details := call_api({"op": "account.list", "token": admin, "search": "alice", "offset": 0, "limit": 10})
	check(details.ok and details.total == 1 and details.accounts[0].user_id == user_id, "administrator search uses persisted accounts")
	var invites := call_api({"op": "invite.list", "token": admin})
	check(invites.ok and invites.total >= 3 and not JSON.stringify(invites).contains("code_hash"), "invite list redacts usable invitation secret")
	var audit := call_api({"op": "audit.list", "token": admin})
	check(audit.ok and audit.total >= 20 and not JSON.stringify(audit).contains(PASSWORD), "persisted audit covers mutations and excludes credentials")
	check(fixture("inspect"), "real SQLite integrity, salted KDF, invite limits and credential redaction")
	var reopened = Service.new()
	check(reopened.initialize(directory).ok and reopened.authenticate(admin).ok, "new adapter instance reopens account database and authenticates")
	var admin_again := login("operator")
	check(admin_again.ok and admin_again.token != admin, "valid operator password rotates lost browser session")
	check(not reopened.authenticate(admin).ok and reopened.authenticate(admin_again.token).ok, "admin rotation leaves only the new bearer valid")
	var files := DirAccess.get_files_at(directory)
	check(Array(files).filter(func(name): return str(name).begins_with("account-request-") or str(name).begins_with("helper-")).is_empty(), "private credential request files removed after every operation")
	finish()

func rate_limits() -> void:
	check(fixture("expire_rates"), "rate fixture clears earlier failed-attempt window")
	var blocked := false
	for index in range(5):
		var result := register("rate_user", "f".repeat(32), "user-limit-" + str(index))
		blocked = blocked or result.code != "INVITE_INVALID"
	check(not blocked, "first five username failures recorded across distinct IPs")
	check(register("rate_user", "f".repeat(32), "user-new-ip").code == "RATE_LIMITED", "username rate limit survives IP changes")
	blocked = false
	for index in range(20):
		var result := register("ip_rate_" + str(index), "f".repeat(32), "shared-abusive-ip")
		blocked = blocked or result.code != "INVITE_INVALID"
	check(not blocked, "first twenty IP failures recorded across distinct usernames")
	check(register("ip_rate_next", "f".repeat(32), "shared-abusive-ip").code == "RATE_LIMITED", "IP rate limit survives username changes")
	check(fixture("expire_rates"), "rate window expiry fixture")
	check(register("ip_rate_next", "f".repeat(32), "shared-abusive-ip").code == "INVITE_INVALID", "expired rate window permits fresh attempt")

func register(username: String, code: String, ip: String = "127.0.0.1") -> Dictionary:
	return call_api({"op": "account.register", "username": username, "password": PASSWORD, "display_name": "玩家 " + username, "invite_code": code, "client_ip": ip})

func login(username: String, password: String = PASSWORD) -> Dictionary:
	return call_api({"op": "account.login", "username": username, "password": password, "client_ip": "127.0.0.2"})

func invite(uses: int) -> Dictionary:
	return call_api({"op": "invite.create", "token": admin, "uses": uses, "expires": int(Time.get_unix_time_from_system()) + 3600, "reason": "测试发放"})

func call_api(request: Dictionary) -> Dictionary:
	var result: Dictionary = service.execute(request)
	if Validator.validate_file(result, "res://schemas/account_response.schema.json") != "":
		check(false, "response schema: " + str(request.op))
	return result

func compete(requests: Array) -> Array:
	var threads: Array = []
	for request in requests:
		var thread := Thread.new()
		if check(thread.start(worker.bind(request)) == OK, "independent account worker starts"):
			threads.append(thread)
	var results: Array = []
	for thread in threads:
		while thread.is_alive():
			await process_frame
		results.append(thread.wait_to_finish())
	return results

func worker(request: Dictionary) -> Dictionary:
	var instance = Service.new()
	instance.root = directory
	instance.database = directory.path_join("accounts.sqlite")
	return instance.execute(request)

func count_ok(results: Array) -> int:
	return results.filter(func(result): return result.ok).size()

func count_code(results: Array, code: String) -> int:
	return results.filter(func(result): return result.get("code", "") == code).size()

func fixture(mode: String) -> bool:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/account_database.ps1"), "-Directory", directory, "-Mode", mode], output, true, false)
	return code == 0 and not output.is_empty() and "ACCOUNT_DATABASE_FIXTURE_OK" in str(output[0])

func check(value: bool, label: String) -> bool:
	if value:
		passed += 1
		print("PASS accounts: ", label)
	else:
		failed += 1
		printerr("FAIL accounts: ", label)
	return value

func finish() -> void:
	print("ACCOUNTS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
