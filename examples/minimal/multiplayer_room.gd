extends "res://sdk/roomkit/server/room_runtime.gd"

func _initialize() -> void:
	build_identity = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	adapter = preload("res://examples/minimal/empty_adapter.gd").new()
	super._initialize()
