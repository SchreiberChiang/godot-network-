extends SceneTree
## Focused real Windows process-identity and cached-HANDLE reclamation test.
## Child mode owns no sockets/files and exits itself if its test parent vanishes.
const Launcher = preload("res://host/platform/process_launcher.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
var child_mode := false
var child_started := 0
var passed := 0
var failed := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--version-info" in args:
		print("ENGINE_VERSION_INFO=", JSON.stringify(Engine.get_version_info()))
		quit(0)
		return
	if "--unit-only" in args:
		var unit: Dictionary = preload("res://tests/test_launcher.gd").new().run()
		print("LAUNCHER_UNIT_RESULT passed=", unit.passed, " failed=", unit.failed)
		quit(0 if int(unit.failed) == 0 else 1)
		return
	child_mode = "--launcher-child" in args
	if child_mode:
		child_started = Time.get_ticks_msec()
		return
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if child_mode and Time.get_ticks_msec() - child_started > 30000:
		quit(0)
	return false

func _run() -> void:
	print("ENGINE_VERSION_INFO=", JSON.stringify(Engine.get_version_info()))
	DirAccess.make_dir_recursive_absolute(Paths.absolute("res://logs"))
	var protection: Array = []
	_check(OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Paths.absolute("res://tools/protect_runtime.ps1"), "-ProjectRoot", Paths.absolute("res://")], protection) == 0, "private helper directory initialized")
	var launcher = Launcher.new()
	var descriptor := {"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", ProjectSettings.globalize_path("res://logs/launcher-real-child.log"), "--script", "res://tests/test_launcher_real.gd", "--", "--launcher-child"]}
	if not OS.has_feature("editor"):
		descriptor.args = ["--headless", "--", "--launcher-child"]
	# Warm the count helper before taking a baseline.
	_handle_count()
	var before := _handle_count()
	var completed := 0
	for cycle in range(10):
		var launch_id := Crypto.new().generate_random_bytes(16).hex_encode()
		var result: Dictionary = launcher.launch(descriptor, launch_id, PackedStringArray(["--launch-id=" + launch_id]))
		_check(result.ok and launcher.probe(launch_id) == "running", "real child identity captured")
		if not result.ok:
			# Unknown identity must remain quarantined; the child self-exits at 30s.
			if int(result.pid) > 0:
				await _wait_for_child_exit(launcher, launch_id)
				launcher.forget(launch_id)
			continue
		if cycle == 0:
			var wrong: Dictionary = launcher.record(launch_id)
			wrong.created_filetime = str(int(wrong.created_filetime) + 1)
			var denied: Dictionary = launcher._inspect("terminate", wrong)
			_check(denied.get("state", "unknown") == "unknown" and launcher.probe(launch_id) == "running", "wrong creation time refuses real termination")
		var terminated: bool = launcher.terminate(launch_id)
		_check(terminated, "verified real child termination confirms exit")
		if not terminated:
			await _wait_for_child_exit(launcher, launch_id)
		_check(launcher.probe(launch_id) == "exited", "original spawned handle confirms exit")
		var child_pid := int(result.pid)
		_check(OS.get_process_exit_code(child_pid) >= 0, "finished child has cached exit code")
		_check(launcher.forget(launch_id), "confirmed exit can be forgotten")
		_check(OS.get_process_exit_code(child_pid) == -1, "forget removes native cached handle entry")
		completed += 1
	var after := _handle_count()
	_check(completed == 10, "all 10 real process cycles completed")
	_check(before > 0 and after <= before + 2, "native handle count stays bounded")
	print("LAUNCHER_HANDLE_COUNTS before=", before, " after=", after)
	print("REAL_LAUNCHER_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _wait_for_child_exit(launcher, launch_id: String) -> void:
	var deadline := Time.get_ticks_msec() + 32000
	while launcher.probe(launch_id) != "exited" and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(launcher.probe(launch_id) == "exited", "failed-test child self-exits within deadline")

func _handle_count() -> int:
	var output: Array = []
	var code := OS.execute(OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe"), PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id " + str(OS.get_process_id()) + ").HandleCount"]), output, false, false)
	return int(str(output[0]).strip_edges()) if code == 0 and not output.is_empty() else -1

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS real_launcher: ", label)
	else:
		failed += 1
		push_error("FAIL real_launcher: " + label)
