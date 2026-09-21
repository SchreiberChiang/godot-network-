extends SceneTree
const Manager = preload("res://host/core/room_manager.gd")
const Lobby = preload("res://host/lobby_server.gd")
const Identity = preload("res://host/core/identity_provider.gd")
const Secure = preload("res://sdk/roomkit/shared/secure_transport.gd")
const Development = preload("res://host/development.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var manager = Manager.new()
var lobby = Lobby.new()
var provider = Identity.new()
var active := false
var passed := 0
var failed := 0
var work := ""
var security: Dictionary
var children: Array = []
var room := ""
var manifest: Dictionary
var report_name := "secure"

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if active:
		manager.poll()
		lobby.poll()
	return false

func _run() -> void:
	work = ProjectSettings.globalize_path("res://data/secure-test-" + Wire.uid())
	var output: Array = []
	check(OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tools/protect_data.ps1"), "-ProjectRoot", ProjectSettings.globalize_path("res://"), "-DataRoot", work], output) == 0, "private security fixture directory")
	security = Secure.create_local_certificate(work)
	check(not security.is_empty(), "local certificate generated without trusting it globally")
	var expiry := int(Time.get_unix_time_from_system()) + 3600
	check(provider.provision("", "invalid", "player", expiry).is_empty() and provider.provision("user", "x", "root", expiry).is_empty(), "malformed identity and unsupported role rejected")
	var one: String = provider.provision("stable-one", "玩家一", "player", expiry)
	var two: String = provider.provision("stable-two", "玩家二", "player", expiry)
	var admin: String = provider.provision("operator", "管理员", "admin", expiry)
	check(provider.save_file(work.path_join("identities.json")), "only credential digests persisted")
	var reopened = Identity.new()
	check(reopened.load_file(work.path_join("identities.json")) and reopened.authenticate(one, expiry - 1).identity.user_id == "stable-one", "stable identity survives provider reload")
	check(not reopened.authenticate(one, expiry).ok, "expired credential rejected")
	var clear_client = preload("res://sdk/roomkit/client/room_client.gd").new()
	check(not clear_client.configure({"url": "ws://127.0.0.1:1", "credential": one}), "client refuses identity credential over plaintext WebSocket")
	clear_client.free()
	var clear_lobby = Lobby.new()
	clear_lobby.identity_provider = reopened
	check(clear_lobby.start(manager) == ERR_UNAUTHORIZED, "identity provider cannot be exposed over plaintext lobby")
	check(lobby.handle({"expires": 1}, {}).get("code", "") == "AUTH_FAILED", "expired authenticated session cannot execute any request")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/development.json"))
	config.godot_executable = OS.get_executable_path()
	config.heartbeat_timeout_ms = 15000
	config.security = security
	check(manager.initialize(config).ok, "secure host initialized")
	active = true
	lobby.identity_provider = reopened
	check(lobby.start(manager, 0, security) == OK, "WSS listener started")
	check(Development.register_multiplayer(manager).ok, "secure room artifact registered")
	var created: Dictionary = manager.create_room("minimal_room", {"mode": "sandbox", "map": "empty", "capacity": 2})
	if not check(created.ok, "secure room created"):
		await finish()
		return
	room = created.room_id
	check(await until(func(): return manager.snapshot(room).state == "READY", 18000), "DTLS room bound before READY")
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/multiplayer_manifest.json"))
	var wrong_ca := Secure.create_local_certificate(work.path_join("untrusted"))
	var bad := launch_client("bad-certificate", one, {"ca_certificate": wrong_ca.certificate, "reject_session": true})
	check(await until(func(): return read_report(bad).get("phase", "") == "DONE", 16000) and read_report(bad).get("ok", false), "WSS rejects untrusted certificate")
	bad = launch_client("bad-credential", "0".repeat(64), {"reject_session": true})
	check(await until(func(): return read_report(bad).get("phase", "") == "DONE", 16000) and read_report(bad).get("ok", false), "WSS rejects invalid identity credential")
	bad = launch_client("bad-dtls-name", one, {"server_hostname": "wrong.invalid", "reject_enet": true})
	check(await until(func(): return read_report(bad).get("phase", "") == "DONE", 24000) and read_report(bad).get("ok", false), "ENet DTLS rejects wrong certificate hostname")
	# Wait for the rejected admission lease to expire before normal clients join.
	check(await until(func(): return lobby.admissions.seats.is_empty(), 18000), "rejected secure admission expires")
	var a := launch_client("one", one)
	var b := launch_client("two", two)
	check(await until(func(): return read_report(a).get("phase", "") == "JOINED" and read_report(b).get("phase", "") == "JOINED", 22000), "two real WSS + DTLS clients join")
	check(read_report(a).get("user_id", "") == "stable-one" and read_report(b).get("user_id", "") == "stable-two", "identity comes from provider rather than peer ID or submitted name")
	check(lobby.admissions.count(room, "CONNECTED") == 2, "secure peers occupy exactly two seats")
	var marker := FileAccess.open(work.path_join("stop.signal"), FileAccess.WRITE)
	marker.close()
	check(await until(func(): return read_report(a).get("ok", false) and read_report(b).get("ok", false), 8000), "ordinary clients cannot stop room and leave cleanly")
	var operator := launch_client("admin", admin, {"admin": true})
	check(await until(func(): return read_report(operator).get("ok", false), 12000), "authenticated administrator can stop host-created room")
	await finish()

func launch_client(label: String, credential: String, overrides: Dictionary = {}) -> Dictionary:
	var launch := Wire.uid()
	var settings := manifest.duplicate(true)
	settings.merge({"url": "wss://localhost:" + str(lobby.port), "secure_enet": true, "ca_certificate": security.certificate, "credential": credential, "room_id": room, "output": work.path_join(label + ".json"), "stop_file": work.path_join("stop.signal")})
	settings.merge(overrides, true)
	var path := work.path_join("client-" + launch + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(settings))
	file.close()
	var result: Dictionary = manager.launcher.launch({"executable": OS.get_executable_path(), "args": ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", work.path_join(label + ".log"), "--script", "res://tests/fixtures/secure_client.gd", "--"]}, launch, ["--launch-id=" + launch, "--client-config=" + path])
	check(result.ok, "verified secure client process " + label)
	var child := {"launch_id": launch, "output": settings.output}
	children.append(child)
	return child

func read_report(child: Dictionary) -> Dictionary:
	return Wire.decode(FileAccess.get_file_as_bytes(child.output)) if FileAccess.file_exists(child.output) else {}

func until(predicate: Callable, duration: int) -> bool:
	var deadline := Time.get_ticks_msec() + duration
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.03).timeout
	return bool(predicate.call())

func finish() -> void:
	manager.stop_all()
	check(await until(func(): return manager.active_count() == 0, 18000), "secure rooms reclaimed")
	for child in children:
		if manager.launcher.probe(child.launch_id) != "exited":
			manager.launcher.terminate(child.launch_id)
		check(await until(func(): return manager.launcher.probe(child.launch_id) == "exited", 5000), "owned secure client exited")
		manager.launcher.forget(child.launch_id)
	lobby.close()
	check(manager.close() and manager.ports.leases.is_empty(), "secure listeners and leases released")
	active = false
	var file := FileAccess.open("res://logs/" + report_name + "-lifecycle-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "failed": failed, "evidence_dir": work}))
	file.close()
	print("SECURE_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(ok: bool, label: String) -> bool:
	if ok:
		passed += 1
		print("PASS secure: ", label)
	else:
		failed += 1
		printerr("FAIL secure: ", label)
	return ok
