extends SceneTree
## Run as an unprivileged UID against a test-owned read-only project directory.
const ClientData = preload("res://examples/framework/client_data.gd")
var failed := 0
var passed := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var data_root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-root="):
			data_root = arg.trim_prefix("--data-root=")
	if data_root.is_empty():
		quit(2)
		return
	var probe := FileAccess.open(data_root.path_join("must-not-write.txt"), FileAccess.WRITE)
	_check(probe == null, "actual process cannot write the read-only fixture")
	if probe != null:
		probe.close()
	var data = ClientData.new()
	data.configure(data_root, "readonly-test")
	data.sample({"phase": "LOBBY", "fps": 60})
	data.queue_settings({"volume": 0.2, "muted": true})
	data.close()
	_check(not data.status().enabled and data.status().error != "", "read-only failure stops diagnostics with fixed status")
	_check(data.status().settings_error != "", "read-only settings failure is separately visible")
	_check(not data.save_pending("wss://example.invalid:28300", "synthetic-account", "shooter", {"kind": "purchase", "operation_id": "12345678901234567890123456789012", "item_id": "smg", "slot": ""}), "read-only receipt persistence refuses before any operation can be sent")
	_check(not FileAccess.file_exists(data_root.path_join("must-not-write.txt")), "read-only failure does not fall back to another directory")
	print("CLIENT_JOURNAL_READONLY_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
