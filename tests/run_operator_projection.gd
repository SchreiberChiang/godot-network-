extends SceneTree
## Pure response projection checks; no claim of a live database/helper failure.
const Operator = preload("res://host/operator.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var sample := {"ok": true, "metrics": {"system_cpu_percent": 42, "data_disk_free_bytes": 1234}}
	var projected := Operator._metric_snapshot(sample)
	check(projected.available and projected.system_cpu_percent == 42 and projected.sampled_at > 0, "available sample has values and real sample time")
	projected.system_cpu_percent = 9
	check(sample.metrics.system_cpu_percent == 42, "projected sample is detached")
	projected = Operator._metric_snapshot({"ok": false, "code": "OPERATION_TIMEOUT"})
	check(not projected.available and not projected.has("system_cpu_percent") and projected.error == "OPERATION_TIMEOUT", "failed sample does not carry old measurements")
	check(not Operator._metric_snapshot({"ok": true}).available, "missing metrics are unavailable")
	var ok := {"ok": true, "rows": []}
	var local_rows := [{"time": 100, "action": "server.start"}]
	for pair in [[{"ok": false}, ok], [ok, {"ok": false}], [{}, {}]]:
		var rejected := Operator._merged_audit(local_rows, pair[0], pair[1])
		check(not rejected.ok and rejected.code == "STORAGE_UNAVAILABLE" and rejected.get("payload", {}).is_empty(), "incomplete audit rejected instead of silent partial success")
	var complete := Operator._merged_audit(local_rows, ok, ok)
	check(complete.ok and complete.payload.entries.size() == 1, "complete empty database results preserve operator audit")
	var many: Array = []
	for index in range(150):
		many.append({"time": index, "action": "test"})
	var tail := Operator._merged_audit(many, ok, ok)
	check(tail.payload.entries.size() == 100 and tail.payload.entries[0].time == 50 and many.size() == 150, "merged audit keeps latest bounded history without modifying source")
	print("OPERATOR_PROJECTION_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
