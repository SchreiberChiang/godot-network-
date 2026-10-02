extends SceneTree
## Malformed legacy receipts must remain recoverable, never become transactions.
const Local = preload("res://examples/framework/client_data.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var base := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--receipt-root="):
			base = argument.trim_prefix("--receipt-root=").replace("\\", "/")
	if base.is_empty() or DirAccess.dir_exists_absolute(base):
		quit(64)
		return
	var local := Local.new()
	if not local.configure(base.path_join("client-data"), "receipt-test", base.path_join("legacy")):
		print("CLIENT_RECEIPT setup refused")
		quit(64)
		return
	var operation := {"kind": "purchase", "item_id": "步枪 \"quoted\" \\ 雪😀", "slot": "", "operation_id": "0123456789abcdef0123456789abcdef"}
	var valid := JSON.stringify(operation)
	var cases := {
		"unknown": valid.trim_suffix("}") + ",\"unknown\":\"keep this\"}",
		"duplicate": valid.trim_suffix("}") + ",\"operation_id\":\"ffffffffffffffffffffffffffffffff\"}",
		"duplicate_escaped": valid.trim_suffix("}") + ",\"operation_\\u0069d\":\"ffffffffffffffffffffffffffffffff\"}",
		"nested": valid.replace("\"slot\":\"\"", "\"slot\":{\"nested\":\"value\"}"),
		"missing": "{\"kind\":\"purchase\",\"operation_id\":\"0123456789abcdef0123456789abcdef\"}",
		"trailing_comma": valid.trim_suffix("}") + ",}",
	}
	for account in cases:
		var path := local._legacy.path_join((account + ":shooter").sha256_text() + ".json")
		_write(path, cases[account])
		var digest := FileAccess.get_sha256(path)
		_check(not local.bind_legacy("wss://receipt-test:1", account, "shooter"), account + " bind refused")
		_check(FileAccess.get_sha256(path) == digest, account + " original unchanged")
		_check(not FileAccess.file_exists(local._migration_path(account, "shooter")), account + " no migration marker")
		_check(not FileAccess.file_exists(local._pending_path("wss://receipt-test:1", account, "shooter")), account + " no pending destination")
	var legacy := local._legacy.path_join(("valid:shooter").sha256_text() + ".json")
	_write(legacy, valid)
	_check(local.bind_legacy("wss://receipt-test:1", "valid", "shooter"), "valid Unicode and escaped text migrates")
	_check(local.load_pending("wss://receipt-test:1", "valid", "shooter").operation == operation, "all receipt fields and operation id preserved")
	_check(FileAccess.get_file_as_string(legacy) == valid, "valid source retained unchanged")
	var extra := operation.duplicate()
	extra.unknown = "unrecognized field"
	_check(not local.save_pending("wss://receipt-test:1", "new-invalid", "shooter", extra), "new receipt also rejects unknown format")
	local.close()
	print("CLIENT_RECEIPT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL ", label)
