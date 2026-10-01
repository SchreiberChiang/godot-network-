extends RefCounted
## Isolation rules for tests that start the real Operator (pure checks, no
## process, no service). Used by tests/run_posix_operator.gd before anything is
## started and by tests/run_operator_isolation_rules.gd.
##  - every argument name appears at most once;
##  - --isolation is a folder inside <data_folder> (not <data_folder>/framework);
##  - the path arguments are given, non-empty, absolute or res://, contain no
##    '..' segment and lie inside the isolation folder;
##  - no existing component of the isolation folder or of any path argument is a
##    symbolic link (the full target path is checked, not only the root);
##  - --panel-port is explicit, 1024-65535 and not the production 28291.
const PrivatePath = preload("res://host/platform/posix_private_path.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const REQUIRED := ["--isolation", "--data-root", "--games", "--public-client-dir"]
const PATH_KEYS := ["--isolation", "--data-root", "--games", "--public-client-dir", "--operator-log-path"]

## user_args: OS.get_cmdline_user_args(). Returns {"refusal": "", "values": {...}}.
static func check(user_args: PackedStringArray, data_folder: String) -> Dictionary:
	var values := {}
	for argument in user_args:
		var pair := argument.split("=", true, 1)
		var key := pair[0]
		if values.has(key):
			return _refused("%s is given more than once" % key)
		values[key] = pair[1] if pair.size() == 2 else ""
	for key in REQUIRED:
		if not values.has(key):
			return _refused("%s is required" % key)
	var data := data_folder.simplify_path()
	var framework := data.path_join("framework")
	var resolved := {}
	for key in PATH_KEYS:
		if not values.has(key):
			continue
		var raw := str(values[key]).replace("\\", "/")
		if raw == "":
			return _refused("%s is empty" % key)
		if raw == ".." or raw.begins_with("../") or raw.ends_with("/..") or raw.contains("/../"):
			return _refused("%s contains a '..' segment" % key)
		if not raw.begins_with("res://") and not raw.is_absolute_path():
			return _refused("%s must be an absolute or res:// path" % key)
		resolved[key] = Paths.absolute(raw).simplify_path()
	var isolation: String = resolved["--isolation"]
	if not isolation.begins_with(data + "/") or isolation == framework or isolation.begins_with(framework + "/"):
		return _refused("--isolation must be a folder inside the data folder (not data/framework)")
	for key in resolved:
		var path: String = resolved[key]
		if path != isolation and not path.begins_with(isolation + "/"):
			return _refused("%s is outside the isolation folder" % key)
		if PrivatePath._has_link(path):
			return _refused("%s passes through a symbolic link" % key)
	var port := str(values.get("--panel-port", ""))
	if not port.is_valid_int() or int(port) < 1024 or int(port) > 65535 or int(port) == 28291:
		return _refused("--panel-port must be explicit, 1024-65535 and not the production 28291")
	return {"refusal": "", "values": resolved}

## Where a test may write its own game index: inside the isolation folder, no
## link anywhere on the path, and nothing there yet (never overwrite a file).
static func index_target_refusal(path: String, isolation: String) -> String:
	var target := path.simplify_path()
	if target == isolation or not target.begins_with(isolation + "/"):
		return "the game index is outside the isolation folder"
	if PrivatePath._has_link(target):
		return "the game index path passes through a symbolic link"
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		return "the game index target already exists"
	if not DirAccess.dir_exists_absolute(target.get_base_dir()):
		return "the folder of the game index does not exist"
	return ""

static func _refused(reason: String) -> Dictionary:
	return {"refusal": reason, "values": {}}
