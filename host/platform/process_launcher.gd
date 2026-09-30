extends RefCounted
## Process ownership boundary. No shell command construction or PID-only kills.
## Records exist only for children spawned by this launcher instance.
## Windows: this file (process handles + process_identity.ps1). Linux: every call
## is delegated to posix_process_owner.gd, which documents why its forced stop
## cannot reach an unrelated process. Other platforms are refused.

const HELPER_PATH := "res://tools/process_identity.ps1"
const Helper = preload("res://host/platform/bounded_helper.gd")
const PosixOwner = preload("res://host/platform/posix_process_owner.gd")
var _records: Dictionary = {}
var _posix = PosixOwner.new() if OS.get_name() == "Linux" else null

func launch(descriptor: Dictionary, launch_id: String, extra_args: PackedStringArray) -> Dictionary:
	if _posix != null:
		return _launch_posix(descriptor, launch_id, extra_args)
	if OS.get_name() != "Windows":
		return _failure("UNSUPPORTED_PLATFORM")
	if not _valid_launch_id(launch_id) or _records.has(launch_id):
		return _failure("INVALID_OPTIONS")
	var executable: String = str(descriptor.get("executable", ""))
	if not executable.is_absolute_path() or not FileAccess.file_exists(executable):
		return _failure("PROGRAM_NOT_FOUND")
	var configured_args: Variant = descriptor.get("args", [])
	if not configured_args is Array and not configured_args is PackedStringArray:
		return _failure("INVALID_OPTIONS")
	var arguments := PackedStringArray()
	for argument in configured_args:
		if not argument is String:
			return _failure("INVALID_OPTIONS")
		arguments.append(argument)
	arguments.append_array(extra_args)
	var marker_count := 0
	for argument in arguments:
		if argument.begins_with("--launch-id"):
			if argument != "--launch-id=" + launch_id:
				return _failure("INVALID_OPTIONS")
			marker_count += 1
	if marker_count != 1:
		return _failure("INVALID_OPTIONS")
	if not FileAccess.file_exists(HELPER_PATH) or not FileAccess.file_exists(_powershell_path()):
		return _failure("PROCESS_IDENTITY_UNVERIFIED")
	var child_pid: int = OS.create_process(executable, arguments, false)
	if child_pid <= 0:
		return _failure("PROCESS_LAUNCH_FAILED")
	_records[launch_id] = {
		"launch_id": launch_id, "pid": child_pid, "parent_pid": OS.get_process_id(),
		"executable": executable, "created_filetime": "", "verified": false,
		"exited": false, "termination_requested": false,
	}
	# OS retains a Windows HANDLE for its own spawned child, so routine polling
	# does not adopt a different process if a numeric PID is reused.
	if not OS.is_process_running(child_pid):
		_records[launch_id]["exited"] = true
		return {"ok": true, "code": "", "pid": child_pid}
	var captured := _inspect("capture", _records[launch_id])
	if captured.get("state", "unknown") == "running":
		_records[launch_id]["created_filetime"] = str(captured.get("created_filetime", ""))
		_records[launch_id]["verified"] = true
		return {"ok": true, "code": "", "pid": child_pid}
	if not OS.is_process_running(child_pid):
		_records[launch_id]["exited"] = true
		return {"ok": true, "code": "", "pid": child_pid}
	return {"ok": false, "code": "PROCESS_IDENTITY_UNVERIFIED", "pid": child_pid}

func probe(launch_id: String) -> String:
	if _posix != null:
		return _posix.probe(launch_id)
	if not _records.has(launch_id):
		return "unknown"
	var owned: Dictionary = _records[launch_id]
	if bool(owned["exited"]):
		return "exited"
	if not OS.is_process_running(int(owned["pid"])):
		owned["exited"] = true
		return "exited"
	return "running" if bool(owned["verified"]) else "unknown"

func terminate(launch_id: String) -> bool:
	if _posix != null:
		return _posix.terminate(launch_id)
	if not _records.has(launch_id):
		return false
	var state := probe(launch_id)
	if state == "exited":
		return true
	var owned: Dictionary = _records[launch_id]
	if state != "running" or not bool(owned["verified"]):
		return false
	var result := _inspect("terminate", owned)
	if result.get("state", "unknown") == "exited":
		# A helper's result is not sufficient: confirm our original child exited.
		owned["termination_requested"] = true
		return probe(launch_id) == "exited"
	return false

func record(launch_id: String) -> Dictionary:
	# Never contains argument vectors, bootstrap contents, or control credentials.
	if _posix != null:
		return _posix.record(launch_id)
	return _records.get(launch_id, {}).duplicate(true)

## What a worker passes to import_owned() of the launcher that takes over.
## Windows: the record itself (the process handle is already held). Linux: a
## single-use token; this launcher stays responsible until it is accepted.
## record() is an observation on both platforms and is not a hand-over on Linux.
func handoff(launch_id: String) -> Dictionary:
	if _posix != null:
		var token: String = _posix.offer(launch_id)
		return {} if token == "" else {"launch_id": launch_id, "handoff": token}
	return record(launch_id)

## Linux: takes over the record of a child whose launcher object no longer
## exists (for example a worker thread's launcher after a failed hand-over).
## One winner; the identity is re-checked by the owner before any signal.
## Windows keeps process handles per launcher and has nothing to reclaim.
func reclaim(launch_id: String) -> bool:
	if _posix != null:
		return _posix.claim_unheld(launch_id)
	return false

func forget(launch_id: String) -> bool:
	if _posix != null:
		return _posix.forget(launch_id)
	if probe(launch_id) != "exited":
		return false
	_reap_finished_handle(_records[launch_id])
	_records.erase(launch_id)
	return true

func _reap_finished_handle(owned: Dictionary) -> void:
	# This is a version-specific resource release, never our termination path.
	# Godot 4.7.2 OS_Windows::get_process_exit_code returns >= 0 only for a
	# finished child still present in its HANDLE map. OS_Windows::kill removes
	# that entry and closes both handles even when TerminateProcess on the
	# already-finished process fails. No other code may call OS.kill for these
	# children; each launch record has one owner, including worker transfers.
	# Source: github.com/godotengine/godot/blob/4.7.2-stable/platform/windows/os_windows.cpp
	# Microsoft PROCESS_INFORMATION: an open process handle prevents PID reuse.
	# Refuse all unverified engine versions instead of risking kill's PID fallback.
	var version := Engine.get_version_info()
	if OS.get_name() != "Windows" or int(version.major) != 4 or int(version.minor) != 7 or int(version.patch) != 2 or str(version.status) != "stable" or str(version.build) not in ["steam", "official"] or str(version.hash) != "ed1daf0bf001b61586d9930840f2f1394092c079":
		return
	if not _records.has(str(owned["launch_id"])) or not bool(owned["exited"]):
		return
	var child_pid := int(owned["pid"])
	if child_pid <= 0 or OS.is_process_running(child_pid):
		return
	# A missing entry returns -1. This gate must remain adjacent to OS.kill.
	if OS.get_process_exit_code(child_pid) < 0:
		return
	OS.kill(child_pid)

func _inspect(mode: String, owned: Dictionary) -> Dictionary:
	var arguments: Array = [
		"-Mode", mode,
		"-ProcessId", str(int(owned["pid"])), "-ExpectedParentPid", str(int(owned["parent_pid"])),
		"-ExpectedExecutable", str(owned["executable"]), "-LaunchId", str(owned["launch_id"]),
	]
	if not str(owned["created_filetime"]).is_empty():
		arguments.append_array(PackedStringArray(["-ExpectedCreationFileTime", str(owned["created_filetime"])]))
	return Helper.execute("process_identity.ps1", arguments, preload("res://sdk/roomkit/shared/paths.gd").absolute("res://run"))

func import_owned(record_value: Dictionary) -> bool:
	# Internal transfer from an isolated worker that launched this exact child.
	if _posix != null:
		# Linux: only the single-use token from handoff() moves responsibility.
		# A record() dictionary, a copy, or a changed launch id grants nothing.
		var stated := str(record_value.get("launch_id", ""))
		return stated != "" and _posix.accept(str(record_value.get("handoff", "")), stated) == stated
	if record_value.is_empty() or _records.has(record_value.launch_id) or int(record_value.parent_pid) != OS.get_process_id():
		return false
	_records[record_value.launch_id] = record_value.duplicate(true)
	return true

## Linux: same argument rules as above, then the owner starts and verifies the
## child. The executable comes from the host's game registry, never a client.
func _launch_posix(descriptor: Dictionary, launch_id: String, extra_args: PackedStringArray) -> Dictionary:
	var executable: String = str(descriptor.get("executable", ""))
	if not _valid_launch_id(launch_id) or not executable.is_absolute_path():
		return _failure("INVALID_OPTIONS" if executable.is_absolute_path() else "PROGRAM_NOT_FOUND")
	var configured_args: Variant = descriptor.get("args", [])
	if not configured_args is Array and not configured_args is PackedStringArray:
		return _failure("INVALID_OPTIONS")
	var arguments := PackedStringArray()
	for argument in configured_args:
		if not argument is String:
			return _failure("INVALID_OPTIONS")
		arguments.append(argument)
	arguments.append_array(extra_args)
	for argument in arguments:
		if argument.begins_with("--launch-id") and argument != "--launch-id=" + launch_id:
			return _failure("INVALID_OPTIONS")
	_posix.trust(executable)
	var started: Dictionary = _posix.launch(launch_id, executable, arguments, "--launch-id=" + launch_id)
	return {"ok": started.ok, "code": started.code, "pid": started.pid}

func _powershell_path() -> String:
	return OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")

func _valid_launch_id(value: String) -> bool:
	if value.length() < 16 or value.length() > 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "pid": -1}
