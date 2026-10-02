extends SceneTree
## Consumer-side check of an actual SafeReplace legacy-upgrade fixture.
const Local = preload("res://examples/framework/client_data.gd")
const ACCOUNT := "n1-upgrade-account"
const SERVER := "wss://upgrade.invalid:28300"
const ID := "0123456789abcdef0123456789abcdef"
var passed := 0
var failed := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			path = arg.trim_prefix("--data-root=")
	if path.is_empty():
		quit(2)
		return
	var local := Local.new()
	_check(local.configure(path, "upgrade-fixture"), "upgraded client-data path is readable by actual client module")
	var before: Dictionary = local.load_pending(SERVER, ACCOUNT, "shooter")
	_check(before.warning == "LEGACY_UNBOUND" and before.operation.is_empty(), "upgraded old receipt requires explicit server association and cannot replay")
	_check(local.bind_legacy(SERVER, ACCOUNT, "shooter"), "explicit association imports the generator-migrated original receipt")
	var after: Dictionary = local.load_pending(SERVER, ACCOUNT, "shooter")
	_check(after.warning == "" and after.operation.get("operation_id", "") == ID and after.operation.get("item_id", "") == "smg", "original operation id and action survive generator and runtime migration")
	_check(local.load_pending("wss://other.invalid:28300", ACCOUNT, "shooter").operation.is_empty(), "upgraded receipt cannot cross server binding")
	_check(local.load_pending(SERVER, ACCOUNT, "turns").operation.is_empty() and local.load_pending(SERVER, "other-account", "shooter").operation.is_empty(), "upgraded receipt cannot cross game or account")
	var source := path.path_join("legacy-client-operations/client-operations").path_join((ACCOUNT + ":shooter").sha256_text() + ".json")
	_check(FileAccess.file_exists(source), "original quarantined bytes remain for recovery")
	local.close()
	var restart := Local.new()
	restart.configure(path, "upgrade-fixture")
	_check(restart.load_pending(SERVER, ACCOUNT, "shooter").operation.get("operation_id", "") == ID, "upgrade receipt association survives client restart")
	restart.close()
	print("CLIENT_UPGRADE_RECEIPT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
