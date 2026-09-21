extends SceneTree
const Client = preload("res://sdk/roomkit/client/room_client.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var client
var settings: Dictionary
var output := ""
var stopping := false
var deadline := 0

func _initialize() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--client-config="):
			path = argument.trim_prefix("--client-config=")
	settings = Wire.decode(FileAccess.get_file_as_bytes(path))
	DirAccess.remove_absolute(path)
	output = settings.output
	deadline = Time.get_ticks_msec() + 45000
	_run.call_deferred()

func _run() -> void:
	client = Client.new()
	root.add_child(client)
	if not client.configure(settings):
		finish(false, "CONFIGURE_FAILED")
		return
	var session: Dictionary = await client.open_session("untrusted display name")
	if settings.get("reject_session", false):
		finish(not session.ok, session.get("code", ""))
		return
	if not session.ok:
		finish(false, session.code)
		return
	if settings.get("admin", false):
		var stop: Dictionary = await client.stop_room(settings.room_id)
		finish(stop.ok, stop.code)
		return
	var forbidden: Dictionary = await client.stop_room(settings.room_id)
	if forbidden.ok or forbidden.code != "AUTH_FAILED":
		finish(false, "UNAUTHORIZED_STOP")
		return
	var joined: Dictionary = await client.join_room(settings.room_id)
	if settings.get("reject_enet", false):
		finish(not joined.ok, joined.get("code", ""))
		return
	if not joined.ok:
		finish(false, joined.code)
		return
	write_report({"phase": "JOINED", "user_id": client.identity.user_id, "display_name": client.identity.display_name})
	while not FileAccess.file_exists(settings.stop_file) and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	await client.leave_room()
	finish(true, "")

func _process(_delta: float) -> bool:
	if not stopping and Time.get_ticks_msec() >= deadline:
		finish(false, "TEST_TIMEOUT")
	return false

func finish(ok: bool, code: String) -> void:
	stopping = true
	if client != null:
		client.close()
	write_report({"phase": "DONE", "ok": ok, "code": code})
	quit(0 if ok else 1)

func write_report(value: Dictionary) -> void:
	var file := FileAccess.open(output + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(output + ".tmp", output)
