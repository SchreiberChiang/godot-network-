extends RefCounted
## Linux counterpart of tools/protect_data.ps1 for the storage services: the
## project data folder and every folder down to the requested one become 700, and
## database files 600, each verified by posix_private_path.gd. Same boundary as on
## Windows: only folders inside <project>/data are accepted. Any failure means the
## caller must not use the folder or the database.
const PrivatePath = preload("res://host/platform/posix_private_path.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
## SQLite keeps these next to a database; they hold the same data.
const SIDE_FILES := ["", "-wal", "-shm", "-journal"]

static func boundary() -> String:
	return Paths.absolute("res://data").simplify_path()

## Creates and protects the data root and the folders down to `root`.
static func prepare(root: String) -> bool:
	var data := boundary()
	var target := root.simplify_path()
	if target != data and not target.begins_with(data + "/"):
		return false
	if not PrivatePath.protect_directory(data, data).ok:
		return false
	var cursor := data
	for part in target.trim_prefix(data).split("/", false):
		cursor = cursor.path_join(part)
		if not PrivatePath.protect_directory(cursor, data).ok:
			return false
	var marker := data.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		var file := FileAccess.open(marker, FileAccess.WRITE)
		if file == null:
			return false
		file.close()
	return PrivatePath.protect_file(marker, data).ok

## Protects a database and its side files. With required = false a database that
## does not exist yet is fine (it is sealed again after it was created); one that
## exists (created earlier, copied in or restored) must become 600 before use.
static func seal(database: String, required: bool) -> bool:
	var data := boundary()
	# A link in place of the database (even one pointing nowhere yet) is refused.
	if PrivatePath._has_link(database.simplify_path()):
		return false
	if not FileAccess.file_exists(database):
		return not required
	for suffix in SIDE_FILES:
		var path: String = database + suffix
		if suffix != "" and not FileAccess.file_exists(path):
			continue
		# SQLite may remove a side file at any moment; one that is gone needs nothing.
		if not PrivatePath.protect_file(path, data).ok and (suffix == "" or FileAccess.file_exists(path) or PrivatePath._has_link(path.simplify_path())):
			return false
	return true

## A non-secret request file written into a protected folder.
static func seal_file(path: String) -> bool:
	return PrivatePath.protect_file(path, boundary()).ok
