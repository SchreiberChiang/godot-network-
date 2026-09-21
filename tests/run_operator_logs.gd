extends SceneTree
const Operator = preload("res://host/operator.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var arguments := {}
	for item in OS.get_cmdline_user_args():
		var pair := item.split("=", true, 1)
		if pair.size() == 2:
			arguments[pair[0]] = pair[1]
	var directory: String = arguments.get("--test-root", "")
	var expected_log: String = arguments.get("--expected-log", "")
	if directory.is_empty() or expected_log.is_empty():
		quit(2)
		return
	var fallback := directory.path_join("fallback.log")
	check(Operator._operator_log_path(arguments.get("--operator-log-path", ""), fallback) == expected_log.replace("\\", "/"), "real launcher argument maps the same engine log path")
	var live_log := Operator._read_log(expected_log)
	check(live_log.ok and live_log.payload.text is String, "active engine log is actually readable while Godot runs")
	check(Operator._operator_log_path("", fallback) == fallback, "older launchers retain the fixed private log default")
	check(Operator._operator_log_path("relative.log", fallback) == "", "relative startup path refused")
	check(Operator._operator_log_path("res://project.godot", fallback) == "", "resource path refused")
	check(Operator._operator_log_path("user://logs/godot.log", fallback) == "", "user resource path refused")
	check(Operator._operator_log_path(expected_log + "\n", fallback) == "", "control character path refused")
	check(Operator._operator_log_path(directory.path_join("child/../normal.log"), fallback).ends_with("/normal.log"), "trusted absolute path is normalized")
	check(Operator._read_log("").code == "LOG_READ_FAILED", "invalid startup log selection is explicit error")
	check(Operator._read_log(directory.path_join("missing.log")).code == "LOG_NOT_FOUND", "missing file differs from empty")
	var empty := directory.path_join("empty.log")
	var file := FileAccess.open(empty, FileAccess.WRITE)
	file.close()
	var result := Operator._read_log(empty)
	check(result.ok and result.payload.text == "", "existing empty log succeeds with empty text")
	var populated := directory.path_join("populated.log")
	file = FileAccess.open(populated, FileAccess.WRITE)
	file.store_string("older\n" + "x".repeat(60000))
	file.close()
	result = Operator._read_log(populated)
	check(result.ok and result.payload.text.length() == 60000 and result.payload.text == "x".repeat(60000), "real file read returns bounded latest bytes")
	result = Operator._read_log(directory.path_join("locked.log"))
	check(not result.ok and result.code == "LOG_READ_FAILED", "actual Windows share-denied file is explicit read failure")
	check(not result.has("payload") or not result.payload.has("path"), "read error never exposes private path")
	print("OPERATOR_LOG_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
