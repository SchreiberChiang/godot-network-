extends SceneTree
## Portable contracts and local socket allocation. Not a Linux host acceptance test.
func _initialize() -> void:
	var passed := 0
	var failed := 0
	for path in ["res://tests/test_transport.gd", "res://tests/test_registry_ports.gd", "res://tests/test_launcher.gd", "res://tests/test_admission.gd", "res://tests/test_games.gd"]:
		var suite = load(path).new()
		var result: Dictionary = suite.run()
		passed += int(result.passed)
		failed += int(result.failed)
	print("PORTABLE_RESULT os=", OS.get_name(), " passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
