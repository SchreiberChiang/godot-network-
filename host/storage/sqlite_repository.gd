extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
var root := ""
var database := ""
var version := ""
# Requests carrying room result signing keys: sent over stdin, never as a file.
const STDIN_OPERATIONS := ["grant"]

func initialize(directory: String, database_name: String = "results.sqlite") -> Dictionary:
	if OS.get_name() != "Windows" or database_name.get_file() != database_name:
		return Wire.failure("UNSUPPORTED_STORAGE")
	root = preload("res://sdk/roomkit/shared/paths.gd").absolute(directory)
	database = root.path_join(database_name)
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/protect_data.ps1"), "-ProjectRoot", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://"), "-DataRoot", root]), output, false, false)
	if code != 0:
		return Wire.failure("PRIVATE_DATA_FAILED")
	var result := execute({"op": "init"})
	version = result.get("sqlite_version", "")
	return result

func execute(request: Dictionary) -> Dictionary:
	if str(request.get("op", "")) in STDIN_OPERATIONS:
		if root.is_empty():
			return Wire.failure("STORAGE_UNAVAILABLE")
		var piped := Helper.execute_input("sqlite_store.ps1", ["-Database", database], JSON.stringify(request))
		return Wire.failure("STORAGE_UNAVAILABLE") if str(piped.get("code", "")).begins_with("HELPER_") else piped
	var path := root.path_join("request-" + Wire.uid() + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Wire.failure("STORAGE_UNAVAILABLE")
	file.store_string(JSON.stringify(request))
	file.close()
	var result := Helper.execute("sqlite_store.ps1", ["-Database", database, "-Request", path], root)
	DirAccess.remove_absolute(path)
	if result.get("code", "").begins_with("HELPER_"):
		return Wire.failure("STORAGE_UNAVAILABLE")
	return result
