extends SceneTree
const Client = preload("res://sdk/roomkit/client/room_client.gd")
var client
var settings: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--settings="):
			settings = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--settings=")))
	_run.call_deferred()

func _run() -> void:
	if settings.is_empty():
		print("Provide a private --settings JSON file containing url, room_id and optional TLS credentials. See README.md.")
		quit(1)
		return
	client = Client.new()
	root.add_child(client)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game_manifest.json"))
	manifest.merge(settings, true)
	var ok: bool = client.configure(manifest)
	if ok:
		var session: Dictionary = await client.open_session("Template player")
		ok = session.ok
	if ok:
		var joined: Dictionary = await client.join_room(settings.room_id)
		ok = joined.ok and client.state == "IN_ROOM"
	if ok:
		await client.leave_room()
		ok = client.state == "LOBBY"
	client.close()
	if settings.has("output"):
		var file := FileAccess.open(settings.output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"ok": ok}))
		file.close()
	print("TEMPLATE_CLIENT_RESULT ok=", ok)
	quit(0 if ok else 1)
