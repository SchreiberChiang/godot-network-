extends SceneTree
## Test-stage account deletion against real, isolated SQLite databases (docs/17 section 7):
## admin protection, typed confirmation, old tokens, several asset spaces, receipts,
## signed results and late settlement, interrupted deletion between the two databases
## and its resumption, repeated deletion, other players untouched, audit
## de-identification, administrator reasons that name the account, the Operator
## close-out (audit files, journal) with write failures and interruption, and older
## backup copies that still hold the account.
const Accounts = preload("res://host/core/account_service.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Results = preload("res://host/core/result_service.gd")
const Deletion = preload("res://host/core/account_deletion.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const PASSWORD := "Abcd1234"
const SPACES := ["shooter", "turns", "shared"]
var passed := 0
var failed := 0
var directory := ""
var accounts = Accounts.new()
var repository = Repository.new()
var results = Results.new()
var admin := ""
var admin_id := ""

class FailingPurge extends RefCounted:
	var inner
	func execute(request: Dictionary) -> Dictionary:
		if request.get("op", "") == "asset.purge_user":
			return {"ok": false, "code": "STORAGE_UNAVAILABLE", "payload": {}}
		return inner.execute(request)

class FailingFinish extends RefCounted:
	var inner
	func finish_deletion(_job_id: String) -> Dictionary:
		return {"ok": false, "code": "STORAGE_UNAVAILABLE", "payload": {}}
	func pending_deletions() -> Dictionary:
		return inner.pending_deletions()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-account-deletion-" + Wire.uid())
	print("ACCOUNT_DELETION_EVIDENCE_DIR=", directory, " storage_mode=", "resident" if Resident.enabled() else "oneshot")
	if not check(accounts.initialize(directory).ok and repository.initialize(directory, "assets.sqlite").ok, "isolated account and asset databases initialize"):
		finish()
		return
	check(results.initialize(directory, {"deletion_fixture": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "result service shares the isolated asset database")
	results.reward_calculator = func(record: Dictionary) -> Array:
		var rows: Array = []
		for player in record.payload.players:
			rows.append({"user_id": player.user_id, "space_id": "shooter", "credits": 10, "experience": 1})
		return rows
	check(call_api({"op": "setup.admin", "username": "dq_admin01", "password": PASSWORD, "display_name": "管理员"}).ok, "fixture administrator created")
	var admin_login := login("dq_admin01")
	if not check(admin_login.ok, "administrator login"):
		finish()
		return
	admin = admin_login.token
	admin_id = admin_login.identity.user_id
	var invitation := call_api({"op": "invite.create", "token": admin, "uses": 5, "expires": int(Time.get_unix_time_from_system()) + 3600, "reason": "deletion fixture"})
	var victim := register("dq_victim01", invitation.get("invite_code", ""))
	var keeper := register("dq_keeper01", invitation.get("invite_code", ""))
	if not check(victim.ok and keeper.ok, "two fake players registered"):
		finish()
		return
	var victim_id: String = victim.identity.user_id
	var keeper_id: String = keeper.identity.user_id
	var victim_token: String = login("dq_victim01").get("token", "")
	var keeper_token: String = login("dq_keeper01").get("token", "")
	check(victim_token != "" and keeper_token != "", "both fake players online with sessions")
	# Audit rows about the victim, with before/after bodies and a free-text reason.
	check(call_api({"op": "account.rename", "token": admin, "user_id": victim_id, "display_name": "改名受害者", "reason": "fixture rename"}).ok, "admin audit row about victim written")
	check(login("dq_victim01", "wrong-password-x").code == "AUTH_FAILED", "failed login leaves a user rate-limit key")
	# Several asset spaces, receipts, and one receipt the victim acted on for the keeper.
	for space in SPACES:
		check(commit(victim_id, space, {"revision": 1, "credits": 100, "experience": 5, "owned": ["starter"], "profiles": {}}, victim_id).ok, "victim wallet seeded in space " + space)
	check(commit(keeper_id, "shooter", {"revision": 1, "credits": 70, "experience": 2, "owned": ["starter"], "profiles": {}}, admin_id).ok, "keeper wallet seeded")
	check(commit(keeper_id, "gift", {"revision": 1, "credits": 1, "experience": 0, "owned": [], "profiles": {}}, victim_id).ok, "keeper receipt acted on by victim seeded")
	var settled := settle([victim_id, keeper_id])
	check(settled.ok, "signed result with rewards for both players accepted")
	var keeper_before := state(keeper_id, "shooter")
	check(keeper_before.get("credits", 0) == 80, "keeper rewarded before deletion")
	# Administrator free text elsewhere that names the victim (username in any case, user_id).
	check(call_api({"op": "account.rename", "token": admin, "user_id": keeper_id, "display_name": "守护者", "reason": "asked by DQ_VICTIM01 / " + victim_id}).ok, "keeper audit reason naming the victim written")
	check(call_api({"op": "invite.create", "token": admin, "uses": 1, "expires": int(Time.get_unix_time_from_system()) + 3600, "reason": "invite for dq_victim01's friend"}).ok, "invite audit reason naming the victim written")
	check(commit(keeper_id, "turns", {"revision": 1, "credits": 5, "experience": 0, "owned": [], "profiles": {}}, admin_id, {"kind": "adjust", "reason": "gift from Dq_Victim01 " + victim_id}).ok, "keeper receipt reason naming the victim written")
	check(fixture("backup").ok, "older backup copy taken before deletion")

	# Refusals that must leave everything unchanged.
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": admin_id, "confirm_username": "dq_admin01", "reason": "fixture"}).code == "ADMIN_SELF_PROTECTION", "administrator cannot be deleted")
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "dq_keeper01", "reason": "wrong one, meant dq_keeper01 not " + victim_id}).code == "DELETE_CONFIRMATION_MISMATCH", "typed username must match the target")
	check(call_api({"op": "account.delete_begin", "token": keeper_token, "user_id": victim_id, "confirm_username": "dq_victim01", "reason": "fixture"}).code == "ADMIN_REQUIRED", "players cannot delete accounts")
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "reason": "fixture"}).code == "INVALID_ACCOUNT_REQUEST", "schema requires the typed confirmation")
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": "user_missing", "confirm_username": "dq_victim01", "reason": "fixture"}).code == "ACCOUNT_NOT_FOUND", "unknown account refused")
	check(accounts.authenticate(victim_token).ok and state(victim_id, "turns").get("credits", 0) == 100, "refused requests changed nothing")
	check(accounts.execute({"op": "local.deletion_pending"}).code == "INVALID_ACCOUNT_REQUEST", "local recovery hook absent from the public account schema")

	# Step 1 only: the job is recorded and the account blocked, as after a crash.
	var begun := call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "DQ_Victim01", "reason": "cleanup of dq_victim01 (" + victim_id + ")"})
	if not check(begun.ok and begun.deletion.state == "assets_pending" and begun.deletion.sessions_revoked == 1, "deletion begins with case-insensitive confirmation and revokes the session"):
		finish()
		return
	var job: Dictionary = begun.deletion
	var subject: String = job.subject
	check(subject == Deletion.subject_for(victim_id), "helper and Godot derive the same pseudonym")
	var begin_row: Dictionary = call_api({"op": "audit.list", "token": admin, "limit": 1}).rows[0]
	check(begin_row.action == "account.delete_begin" and begin_row.reason == "cleanup of " + subject + " (" + subject + ")", "stored deletion reason already has the names replaced")
	check(accounts.close_deletion(job.job_id).code == "DELETION_NOT_READY", "close-out refused before both databases are done")
	check(accounts.authenticate(victim_token).code == "AUTH_FAILED", "old victim token refused")
	check(login("dq_victim01").code == "ACCOUNT_BANNED", "pending deletion blocks new sessions")
	check(call_api({"op": "account.unban", "token": admin, "user_id": victim_id, "reason": "fixture"}).code == "ACCOUNT_DELETION_PENDING", "pending deletion cannot be undone by unban")
	check(call_api({"op": "account.get", "token": admin, "user_id": victim_id}).get("account", {}).get("deletion_pending", false), "admin view marks the pending deletion")
	var again := call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "dq_victim01", "reason": "fixture cleanup"})
	check(again.ok and again.deletion.resumed and again.deletion.job_id == job.job_id, "repeating the request resumes the same job")
	var pending: Dictionary = accounts.pending_deletions()
	check(pending.ok and pending.deletions.size() == 1 and pending.deletions[0].job_id == job.job_id, "pending job visible to the local recovery hook")

	# Asset step fails: nothing is reported as done, assets and account stay.
	var broken_assets := FailingPurge.new()
	broken_assets.inner = repository
	var failed_assets: Dictionary = Deletion.complete(accounts, broken_assets, job)
	check(failed_assets.code == "ACCOUNT_DELETION_INCOMPLETE" and failed_assets.payload.stage == "assets", "asset failure reported as incomplete, not success")
	check(state(victim_id, "shared").get("credits", 0) == 100 and accounts.pending_deletions().deletions.size() == 1, "assets and job untouched after the asset failure")

	# Account step fails after the purge: assets are gone, the tombstone is active.
	var broken_accounts := FailingFinish.new()
	broken_accounts.inner = accounts
	var failed_finish: Dictionary = Deletion.complete(broken_accounts, repository, job)
	check(failed_finish.code == "ACCOUNT_DELETION_INCOMPLETE" and failed_finish.payload.stage == "account", "interruption between the databases reported as incomplete")
	for space in SPACES:
		check(state(victim_id, space).is_empty(), "victim state removed from space " + space)
	check(call_api({"op": "account.get", "token": admin, "user_id": victim_id}).get("account", {}).get("deletion_pending", false), "account row stays blocked until the job finishes")
	check(commit(victim_id, "shooter", {"revision": 1, "credits": 999, "experience": 0, "owned": [], "profiles": {}}, admin_id).code == "ACCOUNT_DELETED", "tombstone refuses a later asset write")
	var late := settle([victim_id, keeper_id])
	check(late.ok and late.get("rewards_skipped", 0) == 1, "late signed result accepted, reward for the deleted player skipped")
	check(state(victim_id, "shooter").is_empty() and state(keeper_id, "shooter").get("credits", 0) == 90, "late settlement pays the keeper only")
	check(results.accept(late.submission).code == "DUPLICATE" and results.accept(settled.submission).code == "DUPLICATE", "retries of both results stay DUPLICATE")
	check(state(victim_id, "shooter").is_empty(), "duplicate retries never recreate the wallet")

	# Resumption (the Operator runs this on start-up) finishes the job.
	var resumed: Dictionary = Deletion.resume(accounts, repository)
	check(resumed.ok and resumed.ready.size() == 1 and resumed.failed.is_empty(), "resume completes both databases of the interrupted job")
	check(resumed.ready[0].account.state == "operator_pending" and resumed.ready[0].account.audit_rows_deidentified > 0 and resumed.ready[0].account.audit_texts_scrubbed >= 2, "account step de-identifies rows and scrubs names from other rows' texts")
	check(resumed.ready[0].assets.receipt_texts_scrubbed == 1, "asset step scrubs the keeper receipt reason")
	var ready_job: Dictionary = resumed.ready[0].job
	check(call_api({"op": "account.get", "token": admin, "user_id": victim_id}).code == "ACCOUNT_ALREADY_DELETED", "deleted account no longer readable")
	check(accounts.finish_deletion(job.job_id).code == "DUPLICATE", "repeated finish is idempotent")
	check(repository.execute({"op": "asset.purge_user", "user_id": victim_id, "username": "dq_victim01"}).ok, "repeated asset purge harmless")
	var open_scan := fixture("scan", victim_id + ",dq_victim01,改名受害者")
	check(open_scan.ok and open_scan.total == 1 and open_scan.tables.get("accounts.sqlite:account_deletions", 0) == 1, "while the Operator close-out is open only its job row still holds the names " + str(open_scan.get("tables", {})))

	# Operator close-out interrupted: a restart finds the job again, not as done.
	var restarted: Dictionary = Deletion.resume(accounts, repository)
	check(restarted.ok and restarted.ready.size() == 1 and restarted.ready[0].job.state == "operator_pending" and restarted.ready[0].job.username == "dq_victim01", "restart hands the unfinished close-out back with what it needs")
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "dq_keeper01", "reason": "retry"}).code == "DELETE_CONFIRMATION_MISMATCH", "retry after the account row is gone still checks the typed username")
	var retried := call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "DQ_victim01", "reason": "retry for dq_victim01"})
	check(retried.ok and retried.deletion.state == "operator_pending" and retried.deletion.resumed and retried.deletion.job_id == job.job_id, "repeated admin request resumes the close-out")

	# Operator files: write failures leave everything open and unchanged.
	var operator_audit := directory.path_join("operator-audit.jsonl")
	var maintenance_audit := directory.path_join("maintenance-audit.jsonl")
	write_text(operator_audit, "\n".join([
		JSON.stringify({"time": 1, "actor_id": admin_id, "action": "player.kick", "user_id": victim_id, "reason": "kick dq_victim01", "code": "OK"}),
		JSON.stringify({"time": 2, "actor_id": admin_id, "action": "asset.adjust", "user_id": keeper_id, "reason": "gift for DQ_Victim01 from " + victim_id, "code": "OK"}),
		JSON.stringify({"time": 3, "actor_id": admin_id, "action": "room.create", "user_id": "room_x", "reason": "unrelated", "code": "OK"}),
		"broken line " + victim_id]) + "\n")
	write_text(maintenance_audit, JSON.stringify({"time": 4, "op": "backup.create", "reason": "before removing dq_victim01", "code": ""}) + "\n")
	var original := FileAccess.get_file_as_string(operator_audit)
	check(FileAccess.set_read_only_attribute(operator_audit, true) == OK, "operator audit file made read-only for the write-failure case")
	var blocked: Dictionary = Deletion.scrub_files([operator_audit, maintenance_audit], ready_job)
	check(not blocked.ok and blocked.code == "AUDIT_WRITE_FAILED", "audit rewrite failure reported, not success")
	check(FileAccess.get_file_as_string(operator_audit) == original and not FileAccess.file_exists(operator_audit + ".tmp"), "failed rewrite leaves the file intact and no temporary copy")
	FileAccess.set_read_only_attribute(operator_audit, false)
	var scrubbed: Dictionary = Deletion.scrub_files([operator_audit, directory.path_join("operator-audit.jsonl.previous"), maintenance_audit], ready_job)
	check(scrubbed.ok and scrubbed.rows == 4, "audit files rewritten: row about the victim, two reasons naming it and a broken line")
	var rewritten := FileAccess.get_file_as_string(operator_audit) + FileAccess.get_file_as_string(maintenance_audit)
	check(not Deletion.mentions(rewritten, [victim_id, "dq_victim01"]) and rewritten.contains(keeper_id) and rewritten.contains("unrelated") and rewritten.contains("redacted:account_deleted"), "operator audit keeps other rows and loses every mention of the victim")
	var memory := [{"user_id": victim_id, "reason": "x"}, {"user_id": keeper_id, "reason": "for DQ_VICTIM01"}, {"user_id": keeper_id, "reason": "plain"}]
	check(Deletion.scrub_rows(memory, ready_job) == 2 and not Deletion.mentions(JSON.stringify(memory), [victim_id, "dq_victim01"]) and memory[2].reason == "plain", "in-memory audit rows scrubbed the same way")
	write_text(directory.path_join(Deletion.JOURNAL), "")
	check(FileAccess.set_read_only_attribute(directory.path_join(Deletion.JOURNAL), true) == OK, "journal made read-only for the write-failure case")
	check(not Deletion.append_journal(directory, {"event": "done", "job_id": job.job_id, "subject": subject, "backups": ["backup-old"]}), "journal write failure detected")
	check(Deletion.resume(accounts, repository).ready.size() == 1, "job still open after the failed close-out")
	FileAccess.set_read_only_attribute(directory.path_join(Deletion.JOURNAL), false)
	check(Deletion.append_journal(directory, {"event": "done", "job_id": job.job_id, "subject": subject, "backups": ["backup-old"]}), "journal entry written and read back")
	check(Deletion.journal_marks(directory).get("backup-old", []) == [subject], "journal marks the backup that predates the deletion")
	var closed := accounts.close_deletion(job.job_id)
	check(closed.ok and closed.deletion.state == "done", "close-out finishes the job")
	check(accounts.close_deletion(job.job_id).code == "DUPLICATE", "repeated close-out is idempotent")
	check(call_api({"op": "account.delete_begin", "token": admin, "user_id": victim_id, "confirm_username": "dq_victim01", "reason": "again dq_victim01 " + victim_id}).code == "ACCOUNT_ALREADY_DELETED", "repeated deletion refused as already deleted")
	var nothing: Dictionary = Deletion.resume(accounts, repository)
	check(nothing.ok and nothing.ready.is_empty() and nothing.failed.is_empty(), "no open job remains")
	var scan := fixture("scan", victim_id + ",dq_victim01,改名受害者")
	check(scan.ok and scan.total == 0, "no row in either current database still holds the user_id, username or nickname, including reasons " + str(scan.get("tables", {})))
	var pseudonym := fixture("scan", subject)
	check(pseudonym.ok and pseudonym.tables.get("assets.sqlite:results", 0) == 2 and pseudonym.tables.get("assets.sqlite:deleted_subjects", 0) == 1, "both results keep their rows with the pseudonym")
	check(pseudonym.tables.get("accounts.sqlite:account_audit", 0) >= 3 and pseudonym.tables.get("assets.sqlite:asset_receipts", 0) == 2, "audit rows and the keeper receipts keep action history under the pseudonym")
	check(fixture("rate_limits").get("user_keys", -1) == 0, "the deleted user's login rate-limit key removed")
	check(login("dq_victim01").code == "AUTH_FAILED", "deleted credentials no longer sign in")
	var audit := call_api({"op": "audit.list", "token": admin, "limit": 200})
	check(audit.ok and JSON.stringify(audit.rows).contains("account.delete") and not JSON.stringify(audit.rows).contains(victim_id), "audit list usable and free of the user_id")

	# Everyone else is unaffected.
	check(accounts.authenticate(keeper_token).ok and state(keeper_id, "shooter").get("credits", 0) == 90 and state(keeper_id, "gift").get("credits", 0) == 1, "keeper session, wallet and gift receipt intact")
	check(repository.execute({"op": "asset.audit", "user_id": keeper_id}).rows.size() == 5, "keeper receipts all kept")
	var reused := register("dq_victim01", invitation.get("invite_code", ""))
	check(reused.ok and reused.identity.user_id != victim_id and state(reused.identity.user_id, "shooter").is_empty(), "username free again for a new test account with a new identity and no assets")

	# The older backup copy still holds the account; restoring it would bring it back.
	var backup := fixture("scan", victim_id, "backup")
	check(backup.ok and backup.tables.get("accounts.sqlite:accounts", 0) == 1 and backup.tables.get("assets.sqlite:asset_states", 0) == 3, "older backup still contains the deleted account and its assets")
	finish()

func settle(players: Array) -> Dictionary:
	var launch := Wire.uid()
	var prepared: Dictionary = results.prepare_launch({"launch_id": launch, "room_id": "room_fixture", "game_id": "deletion_fixture", "build_id": "fixture_build"})
	if not prepared.ok:
		return prepared
	var rows: Array = []
	for user in players:
		rows.append({"user_id": user, "score": 3})
	var record := {"game_id": "deletion_fixture", "build_id": "fixture_build", "room_id": "room_fixture", "launch_id": launch, "match_id": "m_" + launch + "_final", "result_id": Wire.uid(), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": rows}}
	var submission := {"record": record, "signature": Format.sign(record, prepared.config.secret)}
	var accepted: Dictionary = results.accept(submission)
	accepted.submission = submission
	return accepted

func commit(user: String, space: String, body: Dictionary, actor: String, command: Dictionary = {}) -> Dictionary:
	var current := state(user, space)
	body.revision = int(current.get("revision", 0)) + 1
	return repository.execute({"op": "asset.commit", "user_id": user, "space_id": space, "request_id": Wire.uid(), "fingerprint": Wire.uid(), "actor_id": actor, "command": Format.canonical(command), "expected_revision": int(current.get("revision", 0)), "body": Format.canonical(body)})

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func state(user: String, space: String) -> Dictionary:
	var response: Dictionary = repository.execute({"op": "asset.read", "user_id": user, "space_id": space})
	return JSON.parse_string(response.body) if response.ok and response.body != "" else {}

func register(username: String, code: String) -> Dictionary:
	return call_api({"op": "account.register", "username": username, "password": PASSWORD, "display_name": "玩家 " + username, "invite_code": code, "client_ip": "127.0.0.9"})

func login(username: String, password: String = PASSWORD) -> Dictionary:
	return call_api({"op": "account.login", "username": username, "password": password, "client_ip": "127.0.0.9"})

func call_api(request: Dictionary) -> Dictionary:
	var result: Dictionary = accounts.execute(request)
	if Validator.validate_file(result, "res://schemas/account_response.schema.json") != "":
		check(false, "response schema: " + str(request.get("op", "")) + " " + Validator.validate_file(result, "res://schemas/account_response.schema.json"))
	return result

func fixture(mode: String, needles: String = "", copy: String = "") -> Dictionary:
	var output: Array = []
	var arguments := ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/deletion_database.ps1"), "-Directory", directory, "-Mode", mode]
	if needles != "":
		arguments.append_array(["-Needles", needles])
	if copy != "":
		arguments.append_array(["-Copy", copy])
	var code := OS.execute("powershell.exe", arguments, output, true, false)
	var parsed: Variant = JSON.parse_string(str(output[0]).strip_edges()) if code == 0 and not output.is_empty() else null
	return parsed if parsed is Dictionary else {"ok": false, "output": output}

func check(value: bool, label: String) -> bool:
	if value:
		passed += 1
		print("PASS account_deletion: ", label)
	else:
		failed += 1
		printerr("FAIL account_deletion: ", label)
	return value

func finish() -> void:
	Resident.shutdown_all()
	print("ACCOUNT_DELETION_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
