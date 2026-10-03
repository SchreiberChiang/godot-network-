extends SceneTree

var suite: RefCounted


func _initialize() -> void:
	var source = load("res://tests/test_racing_checkpoints.gd")
	if source == null or not source.can_instantiate():
		print("RACING_CHECKPOINTS_LOAD_FAILED")
		quit(1)
		return
	suite = source.new()
	suite.run()
	suite.begin_physics_frames()


func _physics_process(delta: float) -> bool:
	if suite != null and suite.physics_tick(delta):
		print("RACING_CHECKPOINTS_RESULT passed=", suite.passed, " failed=", suite.failed)
		quit(0 if suite.failed == 0 else 1)
	return false
