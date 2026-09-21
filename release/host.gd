extends "res://examples/showcase/host.gd"

func _initialize() -> void:
	super._initialize()
	automated = args.get("--automated", "false") == "true"
	args["--managed"] = "true"

func _run() -> void:
	var base := OS.get_executable_path().get_base_dir()
	var index := Wire.decode(FileAccess.get_file_as_bytes(base.path_join("games.json")))
	if index.size() != 2:
		printerr("RELEASE_ERROR code=ARTIFACT_INDEX_MISSING")
		quit(1)
		return
	for entry in index.values():
		for field in ["project", "server_pack", "server_executable", "client_pack", "client_executable"]:
			entry[field] = base.path_join(entry[field])
	DirAccess.make_dir_recursive_absolute(preload("res://sdk/roomkit/shared/paths.gd").absolute("res://artifacts"))
	var path := preload("res://sdk/roomkit/shared/paths.gd").absolute("res://artifacts/games.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(index))
	file.close()
	args["--artifacts"] = path
	await super._run()
