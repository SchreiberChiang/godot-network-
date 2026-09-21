extends SceneTree

func _initialize() -> void:
	var source = load("res://tests/test_shooter.gd")
	if source == null or not source.can_instantiate():
		printerr("SHOOTER_RESULT load failure")
		quit(1)
		return
	var result: Dictionary = source.new().run()
	print("SHOOTER_RESULT passed=", result.passed, " failed=", result.failed)
	quit(0 if result.failed == 0 else 1)
