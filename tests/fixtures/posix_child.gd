extends SceneTree
## Engine child for tests/run_posix_process.gd (editor binary only).
##   --mode=exit --code=N   quit with N        --mode=hang   run until killed
func _initialize() -> void:
	var mode := "exit"
	var code := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--code="):
			code = int(argument.trim_prefix("--code="))
	if mode == "exit":
		quit(code)
