extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var root := ""
var database := ""
var version := ""

func initialize(directory: String, database_name: String = "results.sqlite") -> Dictionary:
	if OS.get_name() != "Windows" or database_name.get_file() != database_name:
		return Wire.failure("UNSUPPORTED_STORAGE")
	root = ProjectSettings.globalize_path(directory)
	database = root.path_join(database_name)
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_data.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://"), "-DataRoot", root]), output, false, false)
	if code != 0:
		return Wire.failure("PRIVATE_DATA_FAILED")
	var result := execute({"op": "init"})
	version = result.get("sqlite_version", "")
	return result

func execute(request: Dictionary) -> Dictionary:
	var path := root.path_join("request-" + Wire.uid() + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Wire.failure("STORAGE_UNAVAILABLE")
	file.store_string(JSON.stringify(request))
	file.close()
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/sqlite_store.ps1"), "-Database", database, "-Request", path]), output, false, false)
	DirAccess.remove_absolute(path)
	if code != 0 or output.is_empty():
		return Wire.failure("STORAGE_UNAVAILABLE")
	var result: Variant = JSON.parse_string(str(output[0]))
	return result if result is Dictionary else Wire.failure("STORAGE_UNAVAILABLE")
