extends RefCounted

const Launcher = preload("res://host/platform/process_launcher.gd")
const FakeLauncher = preload("res://tests/fakes/fake_launcher.gd")
var passed := 0
var failed: Array[String] = []

func run() -> Dictionary:
	passed = 0
	failed.clear()
	var fake = FakeLauncher.new()
	_check(fake.probe("unowned") == "unknown", "Unknown process is unknown")
	_check(not fake.terminate("unowned"), "Unknown process cannot be terminated")
	_check(not fake.forget("unowned"), "Unknown process cannot be forgotten as exited")
	var started: Dictionary = fake.launch({}, "a", PackedStringArray())
	_check(started.ok and fake.probe("a") == "running", "Fake starts tracked child")
	_check(not fake.forget("a"), "Live child cannot be forgotten")
	_check(not fake.launch({}, "a", PackedStringArray()).ok, "Duplicate launch rejected")
	fake.launch({}, "b", PackedStringArray())
	fake.crash("a")
	_check(fake.probe("a") == "exited" and fake.probe("b") == "running", "One crash preserves other child")
	_check(fake.forget("a") and fake.record("a").is_empty(), "Confirmed exit can be forgotten")
	fake.set_state("b", "unknown")
	_check(not fake.terminate("b") and not fake.forget("b"), "Unknown identity quarantined")
	fake.set_state("b", "running")
	fake.termination_confirms_exit = false
	_check(not fake.terminate("b") and fake.probe("b") == "running", "Terminate request does not imply exit")
	fake.termination_confirms_exit = true
	_check(fake.terminate("b") and fake.probe("b") == "exited", "Owned termination confirms exit")
	fake.next_failure = "PROGRAM_NOT_FOUND"
	_check(fake.launch({}, "c", PackedStringArray()).code == "PROGRAM_NOT_FOUND" and fake.probe("c") == "unknown", "Failed spawn leaves no tracked process")
	var real = Launcher.new()
	_check(real.probe("unowned") == "unknown" and not real.terminate("unowned"), "Real launcher refuses unowned process")
	if OS.get_name() == "Windows":
		var missing: Dictionary = real.launch({"executable": ProjectSettings.globalize_path("res://missing-roomkit.exe"), "args": []}, "0123456789abcdef", PackedStringArray(["--launch-id=0123456789abcdef"]))
		_check(not missing.ok and missing.code == "PROGRAM_NOT_FOUND" and missing.pid == -1, "Real launcher rejects missing executable before spawn")
		var wrong_marker: Dictionary = real.launch({"executable": OS.get_executable_path(), "args": []}, "0123456789abcdef", PackedStringArray(["--launch-id=wrong"]))
		_check(not wrong_marker.ok and wrong_marker.code == "INVALID_OPTIONS", "Real launcher rejects mismatched launch marker")
	return {"passed": passed, "failed": failed.size(), "failures": failed.duplicate()}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS launcher: ", label)
	else:
		failed.append(label)
		push_error("FAIL launcher: " + label)
