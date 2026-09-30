extends RefCounted
## Linux owner-only protection for private folders (700) and sensitive files
## (600), verified after every create, copy or restore. A path that cannot be
## protected and verified must not be used: every function returns
## {"ok": false, "code": ...} in that case and callers stop. The process umask is
## never changed and nothing outside the given boundary is touched.
##
## No external program and no shell are involved. (In this engine OS.execute
## captures output through popen, i.e. a shell, so it is not used here.) Mode
## bits are read and set with FileAccess (stat/chmod system calls). Ownership is
## proved by chmod itself: only the owner of a file may change its mode, so a
## successful chmod to the mode the path already has shows it is ours without
## changing anything. That proof does not hold for the superuser, so running as
## uid 0 is refused.
const DIRECTORY_MODE := 448  # octal 700
const FILE_MODE := 384  # octal 600

## boundary: the private root every protected path must stay inside.
static func protect_directory(path: String, boundary: String) -> Dictionary:
	var refused := _refuse(path, boundary)
	if refused != "":
		return _failure(refused)
	if not DirAccess.dir_exists_absolute(path) and DirAccess.make_dir_recursive_absolute(path) != OK:
		return _failure("PRIVATE_PATH_CREATE_FAILED")
	# Creating it may have followed a link that did not exist a moment ago.
	refused = _refuse(path, boundary)
	if refused != "":
		return _failure(refused)
	return _apply(path, DIRECTORY_MODE, true)

static func protect_file(path: String, boundary: String) -> Dictionary:
	var refused := _refuse(path, boundary)
	if refused != "":
		return _failure(refused)
	if not FileAccess.file_exists(path):
		return _failure("PRIVATE_PATH_MISSING")
	return _apply(path, FILE_MODE, false)

## Copies inside the boundary and protects the copy. A copy inherits the mode of
## its source, so it is never returned as usable before it is 600 and verified;
## on failure the copy is removed.
static func copy_private(source: String, destination: String, boundary: String) -> Dictionary:
	var refused := _refuse(destination, boundary)
	if refused != "":
		return _failure(refused)
	if not FileAccess.file_exists(source) or FileAccess.file_exists(destination):
		return _failure("PRIVATE_PATH_COPY_REFUSED")
	if DirAccess.copy_absolute(source, destination) != OK:
		DirAccess.remove_absolute(destination)
		return _failure("PRIVATE_PATH_COPY_FAILED")
	var result := _apply(destination, FILE_MODE, false)
	if not result.ok:
		DirAccess.remove_absolute(destination)
	return result

## {"ok": true, "mode": "700"} when the path has exactly this mode and belongs
## to the current user. Read-only unless the mode already matches (then the
## ownership proof re-applies the same mode, which changes nothing).
static func verify(path: String, mode: int, directory: bool) -> Dictionary:
	if OS.get_name() != "Linux":
		return _failure("UNSUPPORTED_PLATFORM")
	if _own_uid() <= 0:
		return _failure("PRIVATE_PATH_ROOT_UNSUPPORTED")
	if _has_link(path.simplify_path()):
		return _failure("PRIVATE_PATH_LINK_REFUSED")
	if directory != DirAccess.dir_exists_absolute(path) or (not directory and not FileAccess.file_exists(path)):
		return _failure("PRIVATE_PATH_MISSING")
	if (int(FileAccess.get_unix_permissions(path)) & 4095) != mode:
		return _failure("PRIVATE_PATH_UNVERIFIED")
	if FileAccess.set_unix_permissions(path, mode) != OK:
		return _failure("PRIVATE_PATH_NOT_OWNED")
	return {"ok": true, "code": "", "mode": "%o" % mode}

static func _apply(path: String, mode: int, directory: bool) -> Dictionary:
	if _own_uid() <= 0:
		return _failure("PRIVATE_PATH_ROOT_UNSUPPORTED")
	# chmod succeeds only for the owner, so this both protects and proves ownership.
	if FileAccess.set_unix_permissions(path, mode) != OK:
		return _failure("PRIVATE_PATH_PROTECT_FAILED")
	return verify(path, mode, directory)

static func _refuse(path: String, boundary: String) -> String:
	if OS.get_name() != "Linux":
		return "UNSUPPORTED_PLATFORM"
	var clean := path.simplify_path()
	var root := boundary.simplify_path()
	if not clean.is_absolute_path() or not root.is_absolute_path() or (clean != root and not clean.begins_with(root + "/")):
		return "PRIVATE_PATH_OUTSIDE_BOUNDARY"
	if _has_link(clean):
		return "PRIVATE_PATH_LINK_REFUSED"
	return ""

## True when the path or ANY of its ancestors up to "/" is a symbolic link, so a
## link above the boundary cannot redirect the whole private tree elsewhere.
static func _has_link(clean: String) -> bool:
	var cursor := clean
	while cursor != "/" and cursor != "":
		var base := cursor.get_base_dir()
		var parent := DirAccess.open(base)
		# A parent that exists but cannot be listed cannot be checked: refuse.
		# One that does not exist yet holds nothing, and is itself checked next.
		if parent == null and DirAccess.dir_exists_absolute(base):
			return true
		if parent != null and parent.is_link(cursor):
			return true
		cursor = base
	return false

static func _own_uid() -> int:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return -1
	var text := file.get_buffer(8192).get_string_from_utf8()
	file.close()
	for line in text.split("\n"):
		if line.begins_with("Uid:"):
			return int(line.substr(4).strip_edges().split("\t")[0])
	return -1

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}
