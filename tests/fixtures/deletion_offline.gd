extends SceneTree
## Test-only helper for tests/test_account_deletion.ps1, run while the Operator is
## stopped (begin, finish) or next to it (register). It reads a one-use private config file,
## deletes it, and works only on that isolated test data root. "begin" performs only
## step 1 of a deletion, leaving the pending job an Operator crash would leave.
const Accounts = preload("res://host/core/account_service.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Deletion = preload("res://host/core/account_deletion.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")

func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--config="):
			path = arg.trim_prefix("--config=")
	var config := Wire.decode(FileAccess.get_file_as_bytes(path), "", 16384)
	DirAccess.remove_absolute(path)
	var root: String = str(config.get("data_root", "")).replace("\\", "/")
	if not root.get_file().begins_with("test-account-deletion-") or not root.get_base_dir().simplify_path() == ProjectSettings.globalize_path("res://data").simplify_path():
		print("DELETION_OFFLINE ", JSON.stringify({"ok": false, "code": "ROOT_REFUSED"}))
		quit(2)
		return
	var accounts = Accounts.new()
	var result: Dictionary = accounts.initialize(root)
	if result.ok and config.mode == "register":
		result = accounts.execute({"op": "account.register", "username": config.username, "password": config.password, "display_name": config.username, "invite_code": config.invite_code, "client_ip": "127.0.0.9"})
	elif result.ok and config.mode in ["begin", "finish"]:
		var login: Dictionary = accounts.execute({"op": "account.login", "username": config.admin_username, "password": config.admin_password, "client_ip": "127.0.0.9"})
		result = login if not login.ok else accounts.execute({"op": "account.delete_begin", "token": login.token, "user_id": config.user_id, "confirm_username": config.username, "reason": "offline interruption fixture"})
		# "finish" also completes both databases but stops before the Operator's
		# close-out, as a crash right after local.deletion_finish would.
		if result.ok and config.mode == "finish":
			var repository = Repository.new()
			var job: Dictionary = result.deletion
			job.username = str(config.username).to_lower()
			var completed: Dictionary = repository.initialize(root, "assets.sqlite")
			if completed.ok:
				completed = Deletion.complete(accounts, repository, job)
			result = {"ok": completed.ok, "code": completed.get("code", ""), "deletion": completed.get("job", {})}
			Resident.shutdown_all()
	print("DELETION_OFFLINE ", JSON.stringify({"ok": result.get("ok", false), "code": result.get("code", ""), "user_id": result.get("identity", {}).get("user_id", ""), "state": result.get("deletion", {}).get("state", "")}))
	quit(0 if result.get("ok", false) else 1)
