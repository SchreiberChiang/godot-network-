extends "res://tests/run_games.gd"
var peak_players := 0

func _initialize() -> void:
	super._initialize()
	args["--panel"] = "true"
	args["--panel-port"] = "0"

func _process(delta: float) -> bool:
	super._process(delta)
	if dashboard != null:
		peak_players = maxi(peak_players, int(dashboard.snapshot().host.online_players))
	return false

func fetch(path: String, headers: PackedStringArray = [], method: int = HTTPClient.METHOD_GET) -> Array:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 4
	var error := request.request("http://127.0.0.1:" + str(dashboard.port) + path, headers, method)
	if error != OK:
		request.queue_free()
		return [error, 0, [], PackedByteArray()]
	var response: Array = await request.request_completed
	request.queue_free()
	return response

func finish() -> void:
	var descriptor: String = dashboard.access_file if dashboard != null else ""
	if dashboard != null and dashboard.port > 0:
		check(not Wire.decode(FileAccess.get_file_as_bytes("res://examples/dashboard_status.example.json"), "res://schemas/dashboard_status.schema.json").is_empty(), "documented dashboard example matches schema")
		var response := await fetch("/")
		check(response[1] == 200 and response[3].get_string_from_utf8().contains("服务器总览"), "dashboard serves real Chinese HTML")
		response = await fetch("/api/status")
		check(response[1] == 401, "HTTP API denies unauthenticated request")
		response = await fetch("/api/status", ["Authorization: Bearer " + dashboard.token, "Origin: https://example.invalid"])
		check(response[1] == 403, "HTTP API denies cross-origin request")
		response = await fetch("/api/status", ["Authorization: Bearer " + dashboard.token], HTTPClient.METHOD_POST)
		check(response[1] == 405, "HTTP API refuses mutation methods")
		response = await fetch("/../run/panel-access.json")
		check(response[1] == 404, "HTTP cannot read private bootstrap files")
		check(await until(func(): return dashboard.storage_state == "ready" and dashboard.result_count >= 1, 16000), "dashboard asynchronously reads actual saved round")
		response = await fetch("/api/status", ["Authorization: Bearer " + dashboard.token])
		var snapshot := Wire.decode(response[3], "res://schemas/dashboard_status.schema.json", 1048576)
		check(response[1] == 200 and not snapshot.is_empty(), "authenticated real HTTP status matches unique schema")
		check(peak_players == 4, "dashboard observed four real players across two games")
		check(snapshot.get("rooms", []).size() == 2 and snapshot.get("storage", {}).get("total", 0) >= 1, "API shows both live rooms and persisted match")
		var body: String = response[3].get_string_from_utf8()
		check(not body.contains(dashboard.token) and not body.contains("secret") and not body.contains("digest") and not body.contains(result_root) and not body.contains("credential"), "public snapshot does not leak keys digests credentials or private paths")
		var authority := "127.0.0.1:" + str(dashboard.port)
		check(dashboard.respond("GET /api/status HTTP/1.1\r\nHost: attacker.invalid\r\nAuthorization: Bearer " + dashboard.token + "\r\n\r\n").get_string_from_utf8().begins_with("HTTP/1.1 403"), "unexpected Host refused")
		check(dashboard.respond("GET /api/status HTTP/1.1\r\nHost: " + authority + "\r\nHost: " + authority + "\r\n\r\n").get_string_from_utf8().begins_with("HTTP/1.1 400"), "duplicate headers refused")
	await super.finish()
	check(not FileAccess.file_exists(descriptor), "panel access descriptor removed on shutdown")
	print("PANEL_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
