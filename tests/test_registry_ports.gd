extends RefCounted

const GameRegistry = preload("res://host/core/game_registry.gd")
const PortAllocator = preload("res://host/core/port_allocator.gd")

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	passed = 0
	failed = 0
	_test_registry()
	_test_ports()
	return {"passed": passed, "failed": failed}


func _test_registry() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/minimal/game_manifest.json"))
	var artifacts: Dictionary = {
		manifest.server_artifact: {"executable": OS.get_executable_path(), "args": ["--headless"]},
	}
	var registry := GameRegistry.new()
	_check(registry.register_game(manifest, artifacts).ok, "registry accepts schema-valid manifest and local artifact")
	_check(registry.resolve("not_registered").code == "GAME_NOT_FOUND", "unknown game rejected")
	_check(registry.register_game(manifest, artifacts).code == "GAME_ALREADY_REGISTERED", "duplicate registration rejected")
	_check(GameRegistry.new().register_game(manifest, {}).code == "ARTIFACT_NOT_FOUND", "unknown artifact rejected")
	var invalid: Dictionary = manifest.duplicate(true)
	invalid.godot_version = "PIN_EXACT_TESTED_VERSION"
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "placeholder engine rejected")
	invalid = manifest.duplicate(true)
	invalid.modes.sandbox.min_players = 17
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "manifest numeric bounds enforced")
	invalid = manifest.duplicate(true)
	invalid.modes.sandbox.min_players = 8
	invalid.modes.sandbox.max_players = 4
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "cross-field limits enforced")
	invalid = manifest.duplicate(true)
	invalid.max_players = 8
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "mode cannot exceed build capacity")
	invalid = manifest.duplicate(true)
	invalid.executable = OS.get_executable_path()
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "manifest executable injection rejected")
	invalid = manifest.duplicate(true)
	invalid.modes.sandbox.maps = ["empty", "empty"]
	_check(GameRegistry.new().register_game(invalid, artifacts).code == "INVALID_MANIFEST", "duplicate map rejected by authoritative schema")
	var untrusted: Dictionary = {manifest.server_artifact: {"executable": "relative.exe", "args": []}}
	_check(GameRegistry.new().register_game(manifest, untrusted).code == "UNTRUSTED_ARTIFACT", "relative executable rejected")
	untrusted = {manifest.server_artifact: {"executable": OS.get_executable_path(), "args": [123]}}
	_check(GameRegistry.new().register_game(manifest, untrusted).code == "UNTRUSTED_ARTIFACT", "non-string argument rejected")
	var options := {"mode": "sandbox", "map": "empty", "capacity": 4}
	_check(registry.validate_options("minimal_room", options).ok, "allowlisted room options accepted")
	options.executable = "arbitrary.exe"
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "remote executable option rejected")
	options.erase("executable")
	options.map = "res://arbitrary_map.tscn"
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "arbitrary map path rejected")
	options.map = "empty"
	options.mode = "unknown"
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "unknown mode rejected")
	options.mode = "sandbox"
	options.capacity = 17
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "over-capacity option rejected")
	options.capacity = NAN
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "NaN capacity rejected")
	options.capacity = 1.5
	_check(registry.validate_options("minimal_room", options).code == "INVALID_OPTIONS", "fractional capacity rejected")
	var resolved: Dictionary = registry.resolve("minimal_room")
	resolved.manifest.modes.sandbox.max_players = 1
	resolved.descriptor.executable = "changed"
	_check(registry.resolve("minimal_room").manifest.modes.sandbox.max_players == 16, "resolved manifests are defensive copies")
	_check(registry.resolve("minimal_room").descriptor.executable == OS.get_executable_path(), "resolved artifacts are defensive copies")


func _test_ports() -> void:
	var occupied := PacketPeerUDP.new()
	var bind_result: int = occupied.bind(0, "127.0.0.1")
	_check(bind_result == OK, "test obtains ephemeral UDP fixture")
	if bind_result != OK:
		return
	var occupied_port: int = occupied.get_local_port()
	var blocked := PortAllocator.new(occupied_port, occupied_port)
	_check(blocked.acquire("blocked") == 0, "occupied UDP port not allocated")
	_check(occupied.is_bound(), "allocator leaves port owner running")
	occupied.close()
	var allocator := PortAllocator.new(occupied_port, occupied_port)
	_check(allocator.acquire("launch-a") == occupied_port, "available port gets lease")
	_check(allocator.acquire("launch-a") == occupied_port, "same launch has stable lease")
	_check(allocator.acquire("launch-b") == 0, "lease cannot be double allocated")
	_check(not allocator.release("launch-a", false), "live process retains quarantine")
	_check(allocator.leases.has("launch-a"), "unsafe release keeps lease recorded")
	var blocker := PacketPeerUDP.new()
	var blocker_result: int = blocker.bind(occupied_port, "127.0.0.1")
	_check(blocker_result == OK, "test occupies leased port after allocation")
	if blocker_result == OK:
		_check(not allocator.release("launch-a", true), "exited process with busy port stays quarantined")
		_check(blocker.is_bound(), "release probe leaves concurrent owner running")
	blocker.close()
	_check(allocator.release("launch-a", true), "confirmed exit and reusable UDP port release lease")
	_check(allocator.leases.is_empty(), "all released leases removed")
	_check(not allocator.release("unknown", true), "unknown lease cannot be released")
	_check(PortAllocator.new(0, 0).acquire("invalid") == 0, "invalid range rejected")
	_check(allocator.acquire("") == 0, "empty launch identity rejected")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS registry_ports: ", label)
	else:
		failed += 1
		push_error("FAIL registry_ports: " + label)
