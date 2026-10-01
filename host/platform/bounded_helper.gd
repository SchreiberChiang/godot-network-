extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Posix = preload("res://host/platform/posix_helper.gd")
const OUTPUT_LIMIT := 4 * 1024 * 1024

## Linux: both entry points start the helper script directly through
## posix_helper.gd (owned child, pipes, watchdog deadline). There is no wrapper
## script, no job file, and the Windows handle-release rule below is not used.

static func execute(helper: String, arguments: Array, directory: String, timeout_ms: int = 10000) -> Dictionary:
	if OS.get_name() == "Linux":
		return Posix.run(helper, arguments, "", timeout_ms)
	var path := directory.path_join("helper-" + Wire.uid() + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
	file.store_string(JSON.stringify({"helper": helper, "arguments": arguments}))
	file.close()
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/bounded_helper.ps1"), "-Request", path, "-TimeoutMs", str(timeout_ms)], output, false, false)
	DirAccess.remove_absolute(path)
	if output.is_empty():
		return {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
	var reader := JSON.new()
	var parsed: Variant = reader.data if reader.parse(str(output[0]).strip_edges()) == OK else null
	if code != 0:
		# bounded_helper.ps1 exits 1 with its own fixed failure line; keep that
		# code (HELPER_TIMEOUT or HELPER_FAILED) so a timeout is not reported as a
		# generic failure. Anything else stays HELPER_FAILED.
		var wrapper_code := str(parsed.get("code", "")) if parsed is Dictionary else ""
		return {"ok": false, "code": wrapper_code if wrapper_code in ["HELPER_TIMEOUT", "HELPER_FAILED"] else "HELPER_FAILED", "state": "unknown"}
	return parsed if parsed is Dictionary else {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}

## Same bounded helper, but the job and a request body travel over standard input
## instead of a temporary file. Use it for bodies carrying passwords or tokens, so
## nothing is left on disk if the host dies mid-call. Blocks like execute(); the
## script's own deadline ends the helper chain.
static func execute_input(helper: String, arguments: Array, input: String, timeout_ms: int = 10000) -> Dictionary:
	if OS.get_name() == "Linux":
		return Posix.run(helper, arguments, Marshalls.utf8_to_base64(input), timeout_ms)
	var failure := {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
	var job := JSON.stringify({"helper": helper, "arguments": arguments, "input": Marshalls.utf8_to_base64(input)})
	var launched := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/bounded_helper.ps1"), "-TimeoutMs", str(timeout_ms)], true)
	if launched.is_empty():
		return failure
	var pid := int(launched.pid)
	var stdio: FileAccess = launched.stdio
	var stderr: FileAccess = launched.stderr
	var output := PackedByteArray()
	var complete := false
	if stdio.store_line(Marshalls.utf8_to_base64(job)):
		# The helper writes one short JSON line; read until the pipe closes.
		complete = _drain(stdio, output, OUTPUT_LIMIT)
	# stderr is not used for results; drain it so the helper can never block.
	_drain(stderr, PackedByteArray(), 0)
	stdio.close()
	stderr.close()
	var code := _wait_and_release(pid, timeout_ms + 5000)
	if code != 0 or not complete or output.is_empty():
		return failure
	var parsed: Variant = JSON.parse_string(output.get_string_from_utf8())
	return parsed if parsed is Dictionary else failure

static func _drain(pipe: FileAccess, into: PackedByteArray, limit: int) -> bool:
	var within := true
	while true:
		var chunk := pipe.get_buffer(4096)
		if chunk.is_empty():
			return within
		if into.size() + chunk.size() > limit:
			within = false
		elif limit > 0:
			into.append_array(chunk)
	return within

static func _wait_and_release(pid: int, deadline_ms: int) -> int:
	# execute_with_pipe keeps the child's process and thread handles in Godot's
	# process map until OS.kill; without releasing them every call leaks two
	# handles. Same version-specific rule as ProcessLauncher._reap_finished_handle:
	# on Godot 4.7.2 a code >= 0 means the child has exited AND its entry is still
	# present, so OS.kill uses that held handle (TerminateProcess on the finished
	# process fails harmlessly) and closes both handles. With a missing entry kill
	# would fall back to opening the bare PID, so that path is never reached.
	var started := Time.get_ticks_msec()
	var code := OS.get_process_exit_code(pid)
	while code < 0 and Time.get_ticks_msec() - started < deadline_ms:
		OS.delay_msec(2)
		code = OS.get_process_exit_code(pid)
	if not _handle_release_verified():
		return code
	if code >= 0:
		OS.kill(pid)
	elif OS.is_process_running(pid):
		# Still in the map and alive past every deadline: terminate through the
		# held handle, then report failure.
		OS.kill(pid)
		return -1
	return code

static func _handle_release_verified() -> bool:
	var version := Engine.get_version_info()
	return OS.get_name() == "Windows" and int(version.major) == 4 and int(version.minor) == 7 and int(version.patch) == 2 and str(version.status) == "stable" and str(version.build) in ["steam", "official"] and str(version.hash) == "ed1daf0bf001b61586d9930840f2f1394092c079"
