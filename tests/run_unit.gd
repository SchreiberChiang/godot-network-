extends SceneTree

func _initialize() -> void:
	var passed := 0
	var failed := 0
	for script in ["res://tests/test_transport.gd", "res://tests/test_registry_ports.gd", "res://tests/test_launcher.gd", "res://tests/test_manager.gd", "res://tests/test_admission.gd", "res://tests/test_games.gd", "res://tests/test_results.gd"]:
		var source = load(script)
		if source == null or not source.can_instantiate():
			printerr("FAIL load suite ", script)
			failed += 1
			continue
		var suite = source.new()
		var result: Dictionary = suite.run()
		passed += int(result.passed)
		failed += int(result.failed)
	print("UNIT_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
