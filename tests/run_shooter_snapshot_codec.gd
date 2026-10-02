extends SceneTree
const Suite = preload("res://tests/test_shooter_snapshot_codec.gd")
func _initialize() -> void:
	var result: Dictionary = Suite.new().run()
	print("SHOOTER_SNAPSHOT_CODEC_RESULT passed=", result.passed, " failed=", result.failed, " expected_native_rejections=", result.expected_native_rejections)
	quit(0 if int(result.failed) == 0 else 1)
