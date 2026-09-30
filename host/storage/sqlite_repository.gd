extends RefCounted
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const DataRoot = preload("res://host/platform/posix_data_root.gd")
var root := ""
var database := ""
var version := ""
# Requests carrying room result signing keys: sent over stdin, never as a file.
const STDIN_OPERATIONS := ["grant"]
# Served by this database's resident worker. All are safe to repeat: two reads and
# asset.commit, whose receipt check turns a repeated request_id into DUPLICATE.
const RESIDENT_OPERATIONS := ["asset.read", "asset.snapshot", "asset.commit"]

func initialize(directory: String, database_name: String = "results.sqlite") -> Dictionary:
	if not OS.get_name() in ["Windows", "Linux"] or database_name.get_file() != database_name:
		return Wire.failure("UNSUPPORTED_STORAGE")
	root = preload("res://sdk/roomkit/shared/paths.gd").absolute(directory)
	database = root.path_join(database_name)
	if OS.get_name() == "Linux":
		# Folders 700 and the database 600, verified before and after the helper
		# creates or opens it. When protection fails the repository stays unusable.
		if not DataRoot.prepare(root) or not DataRoot.seal(database, false):
			root = ""
			return Wire.failure("PRIVATE_DATA_FAILED")
		var ready := execute({"op": "init"})
		if ready.get("ok", false) and not DataRoot.seal(database, true):
			root = ""
			return Wire.failure("PRIVATE_DATA_FAILED")
		version = ready.get("sqlite_version", "")
		return ready
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://tools/protect_data.ps1"), "-ProjectRoot", preload("res://sdk/roomkit/shared/paths.gd").absolute("res://"), "-DataRoot", root]), output, false, false)
	if code != 0:
		return Wire.failure("PRIVATE_DATA_FAILED")
	var result := execute({"op": "init"})
	version = result.get("sqlite_version", "")
	return result

func execute(request: Dictionary) -> Dictionary:
	if str(request.get("op", "")) in RESIDENT_OPERATIONS and not root.is_empty() and Resident.enabled():
		var reply: Dictionary = Resident.for_database("sqlite_store.ps1", database, 10000).request(request)
		if not reply.is_empty():
			# The one-shot path reports every helper failure as Wire.failure; same shape here.
			if not reply.get("ok", false) and reply.get("code", "") == "STORAGE_UNAVAILABLE":
				return Wire.failure("STORAGE_UNAVAILABLE")
			return reply
		# Resident path failed; the same request is repeated once through the
		# one-shot helper below (safe for these operations, see above).
	return execute_oneshot(request)

## Starts this database's worker and pays its start-up and compile cost early.
func prewarm() -> Dictionary:
	return execute({"op": "asset.read", "user_id": "__prewarm__", "space_id": "__prewarm__"})

## The original per-call helper path; also the fallback for the resident worker.
func execute_oneshot(request: Dictionary) -> Dictionary:
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
	if OS.get_name() == "Linux" and not DataRoot.seal_file(path):
		DirAccess.remove_absolute(path)
		return Wire.failure("STORAGE_UNAVAILABLE")
	var result := Helper.execute("sqlite_store.ps1", ["-Database", database, "-Request", path], root)
	DirAccess.remove_absolute(path)
	if result.get("code", "").begins_with("HELPER_"):
		return Wire.failure("STORAGE_UNAVAILABLE")
	return result
