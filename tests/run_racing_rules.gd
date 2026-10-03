extends SceneTree


func _initialize() -> void:
	var source = load("res://tests/test_racing_rules.gd")
	if source == null or not source.can_instantiate():
		print("RACING_RULES_LOAD_FAILED")
		quit(1)
		return
	var result: Dictionary = source.new().run()
	print("RACING_RULES_RESULT passed=", result.passed, " failed=", result.failed)
	quit(0 if result.failed == 0 else 1)
