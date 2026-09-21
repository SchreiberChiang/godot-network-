extends SceneTree
const Service = preload("res://host/core/result_service.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var directory: String = preload("res://sdk/roomkit/shared/paths.gd").absolute(args.get("--store", "res://data/showcase-results"))
	if not FileAccess.file_exists(directory.path_join("results.sqlite")):
		printerr("RESULTS_ERROR code=DATABASE_NOT_FOUND; play a complete round using StartTurns.cmd first.")
		quit(1)
		return
	var service = Service.new()
	var result: Dictionary = service.initialize(directory, {"turns": "res://schemas/summary_result.schema.json", "blocks": "res://schemas/summary_result.schema.json", "minimal_room": "res://schemas/summary_result.schema.json"})
	if not result.ok:
		printerr("RESULTS_ERROR code=", result.code)
		quit(1)
		return
	match args.get("--operation", "inspect"):
		"recover":
			result = service.recover()
			result.ok = result.pending == 0
			print("RECOVERY ", JSON.stringify(result))
		"backup":
			var destination := directory.path_join("backup-" + str(Time.get_unix_time_from_system()).replace(".", "-") + ".sqlite")
			result = service.repository.execute({"op": "backup", "destination": destination})
			if result.ok:
				print("BACKUP_PATH=", destination)
		"inspect":
			result = service.repository.execute({"op": "inspect"})
			if result.ok:
				print("已保存 ", int(result.count), " 局；数据库检查：", result.integrity)
				print("数据目录：", directory)
				for row in result.rows:
					var record: Dictionary = JSON.parse_string(row.body)
					print("游戏：", record.game_id, " | 第 ", int(record.payload.get("round", 0)), " 局 | ", "完成" if record.status == "completed" else "中止")
					for player in record.payload.get("players", []):
						print("  玩家 ", player.user_id, "：", int(player.score), " 分")
				print("RESULT_COUNT=", int(result.count), " INTEGRITY=", result.integrity)
		_:
			result = {"ok": false, "code": "INVALID_OPERATION"}
	print("RESULTS_TOOL ok=", result.ok, " code=", result.get("code", ""))
	quit(0 if result.ok else 1)
