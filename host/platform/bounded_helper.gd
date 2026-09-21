extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")

static func execute(helper: String, arguments: Array, directory: String, timeout_ms: int = 10000) -> Dictionary:
	var path := directory.path_join("helper-" + Wire.uid() + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
	file.store_string(JSON.stringify({"helper": helper, "arguments": arguments}))
	file.close()
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/bounded_helper.ps1"), "-Request", path, "-TimeoutMs", str(timeout_ms)], output, false, false)
	DirAccess.remove_absolute(path)
	if code != 0 or output.is_empty():
		return {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	return parsed if parsed is Dictionary else {"ok": false, "code": "HELPER_FAILED", "state": "unknown"}
