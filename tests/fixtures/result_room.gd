extends "res://sdk/roomkit/server/room_runtime.gd"
var proposed := false
var exit_marker := ""

func _initialize() -> void:
	build_identity = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	adapter = preload("res://examples/minimal/empty_adapter.gd").new()
	super._initialize()
	if result_outbox != null:
		exit_marker = result_outbox.directory.path_join("worker-exited.marker")

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if ready and not stopping and not proposed:
		proposed = true
		var queued := submit_result("only", "completed", {"round": 1, "players": []})
		if not queued.ok:
			printerr("FIXTURE_QUEUE_FAILED")
	return result

func _finalize() -> void:
	if not exit_marker.is_empty():
		var file := FileAccess.open(exit_marker, FileAccess.WRITE)
		if file != null:
			file.store_string(context.launch_id)
			file.close()
