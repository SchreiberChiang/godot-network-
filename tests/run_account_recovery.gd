extends SceneTree
## Real Windows SQLite account recovery; no lobby, room or operator process.
const Accounts = preload("res://host/core/account_service.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const PASSWORD := "account-recovery-test-password"
const RESET_OP := "local.reset_player_sessions"
var passed := 0
var failed := 0
var service = Accounts.new()
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-account-recovery-" + Wire.uid())
	print("ACCOUNT_RECOVERY_EVIDENCE_DIR=", directory)
	if not check(service.initialize(directory).ok, "real private account database initializes"):
		finish()
		return
	var result: Dictionary = service.reset_player_sessions()
	check(result.ok and result.revoked == 0, "local reset is safe before first account setup")
	if not check(api({"op": "setup.admin", "username": "recovery_admin", "password": PASSWORD, "display_name": "Recovery operator"}).ok, "real administrator setup"):
		finish()
		return
	var admin := login("recovery_admin")
	if not check(admin.ok, "real administrator password login"):
		finish()
		return
	var invite := api({"op": "invite.create", "token": admin.token, "uses": 2, "reason": "recovery fixture"})
	if not check(invite.ok, "real invitation created"):
		finish()
		return
	for username in ["recovery_one", "recovery_two"]:
		check(api({"op": "account.register", "username": username, "password": PASSWORD, "display_name": username, "invite_code": invite.invite_code}).ok, "real player registration " + username)
	var one := login("recovery_one")
	var two := login("recovery_two")
	if not check(one.ok and two.ok, "two actual player sessions persist"):
		finish()
		return
	service = Accounts.new()
	check(service.initialize(directory).ok, "replacement account service reopens existing SQLite")
	check(login("recovery_one").get("code", "") == "ALREADY_LOGGED_IN", "old persisted player session reproduces restart lockout")
	for token in ["", one.token, admin.token]:
		var request := {"op": RESET_OP}
		if token != "":
			request.token = token
		check(service.execute(request).get("code", "") == "INVALID_ACCOUNT_REQUEST", "public execute rejects internal reset even with a valid bearer")
	check(Validator.validate_file(Wire.request(RESET_OP, {}), "res://schemas/managed_lobby_request.schema.json") != "", "public managed schema cannot invoke reset")
	check(Validator.validate_file({"action": RESET_OP, "payload": {}}, "res://schemas/admin_request.schema.json") != "", "admin HTTP schema cannot invoke lifecycle reset")
	var snapshot := fixture("inspect")
	check(snapshot.get("player_sessions", -1) == 2 and snapshot.get("admin_sessions", -1) == 1, "rejected public requests leave both players and admin intact")
	result = service.reset_player_sessions()
	check(result.ok and result.revoked == 2 and result.size() == 3, "trusted local reset revokes exactly both players and returns only safe counts")
	check(not service.authenticate(one.token).ok and not service.authenticate(two.token).ok, "both pre-restart player bearers are invalid")
	check(service.authenticate(admin.token).ok, "original administrator bearer remains valid")
	var fresh := login("recovery_one")
	check(fresh.ok and fresh.get("token", "") != one.token, "player can log in immediately after recovery with a fresh bearer")
	check(fixture("block_audit").get("ok", false), "real SQLite audit failure trigger installed")
	result = service.reset_player_sessions()
	check(not result.ok and result.get("code", "") == "STORAGE_UNAVAILABLE", "failed audit makes recovery fail")
	snapshot = fixture("inspect")
	check(snapshot.get("player_sessions", -1) == 1 and snapshot.get("admin_sessions", -1) == 1 and snapshot.get("recovery_audit", -1) == 2, "audit failure rolls back session deletion and preserves prior journal")
	check(fixture("unblock_audit").get("ok", false), "real audit failure trigger removed")
	result = service.reset_player_sessions()
	check(result.ok and result.revoked == 1, "local reset succeeds after temporary audit fault clears")
	result = service.reset_player_sessions()
	check(result.ok and result.revoked == 0, "repeat local reset is safe and changes no remaining session")
	check(service.authenticate(admin.token).ok, "repeated recovery still preserves administrator session")
	var audit := api({"op": "audit.list", "token": admin.token})
	var recovery_rows: Array = []
	for row in audit.get("rows", []):
		if row.action == RESET_OP:
			recovery_rows.append(row)
	var matching := false
	for row in recovery_rows:
		var before: Dictionary = JSON.parse_string(row.before_body)
		var after: Dictionary = JSON.parse_string(row.after_body)
		if row.actor_id == "system:operator" and row.reason == "operator_restart_after_verified_exit" and before.get("player_sessions", -1) == 2 and after.get("player_sessions", -1) == 0:
			matching = true
	check(recovery_rows.size() == 4 and matching, "durable recovery audit records fixed local actor reason and before/after counts")
	var serialized := JSON.stringify(audit)
	check(PASSWORD not in serialized and str(one.token) not in serialized and str(two.token) not in serialized and str(admin.token) not in serialized and str(fresh.get("token", "unavailable")) not in serialized and "token_hash" not in serialized, "recovery audit never contains passwords bearer values or token hashes")
	snapshot = fixture("inspect")
	check(snapshot.get("player_sessions", -1) == 0 and snapshot.get("admin_sessions", -1) == 1 and snapshot.get("integrity", "") == "ok", "final real database contains only administrator session and passes integrity check")
	finish()

func api(request: Dictionary) -> Dictionary:
	if request.op in ["account.login", "account.register", "account.change_password"]:
		request.client_ip = "127.0.0.88"
	return service.execute(request)

func login(username: String) -> Dictionary:
	return api({"op": "account.login", "username": username, "password": PASSWORD})

func fixture(mode: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/account_recovery_database.ps1"), "-Directory", directory, "-Mode", mode], output, false, false)
	if code != 0 or output.is_empty():
		return {}
	var value: Variant = JSON.parse_string(str(output[0]))
	return value if value is Dictionary else {}

func check(condition: bool, label: String) -> bool:
	if condition:
		passed += 1
		print("PASS account recovery: ", label)
	else:
		failed += 1
		printerr("FAIL account recovery: ", label)
	return condition

func finish() -> void:
	print("ACCOUNT_RECOVERY_RESULT passed=", passed, " failed=", failed)
	quit(1 if failed > 0 else 0)
