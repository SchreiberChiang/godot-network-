extends RefCounted
## Native writable paths are beside the executable; res:// reads remain in the PCK.
static func absolute(path: String) -> String:
	if path.begins_with("res://") and not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join(path.trim_prefix("res://"))
	return ProjectSettings.globalize_path(path)
