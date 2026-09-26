extends SceneTree

func _initialize() -> void:
	var source = load("res://tests/test_shooter.gd")
	if source == null or not source.can_instantiate():
		quit(1)
		return
	var result: Dictionary = source.new().run()
	for path in ["res://examples/shooter/adapter.gd", "res://examples/framework/view.gd", "res://host/managed_host.gd", "res://host/operator.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			result.failed += 1
	print("SHOOTER_RESULT passed=", result.passed, " failed=", result.failed)
	quit(0 if result.failed == 0 else 1)
