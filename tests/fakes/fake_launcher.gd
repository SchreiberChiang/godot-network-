extends RefCounted
## Deterministic process simulation. This never starts or stops an OS process.

var next_failure := ""
var next_pid := 1000
var termination_allowed := true
var termination_confirms_exit := true
var terminate_calls: Array[String] = []
var _records: Dictionary = {}

func launch(_descriptor: Dictionary, launch_id: String, _extra_args: PackedStringArray) -> Dictionary:
	if not next_failure.is_empty():
		var code := next_failure
		next_failure = ""
		return {"ok": false, "code": code, "pid": -1}
	if _records.has(launch_id):
		return {"ok": false, "code": "INVALID_OPTIONS", "pid": -1}
	next_pid += 1
	_records[launch_id] = {"launch_id": launch_id, "pid": next_pid, "state": "running", "verified": true}
	return {"ok": true, "code": "", "pid": next_pid}

func probe(launch_id: String) -> String:
	return str(_records.get(launch_id, {}).get("state", "unknown"))

func terminate(launch_id: String) -> bool:
	if probe(launch_id) == "exited":
		return true
	if not termination_allowed or probe(launch_id) != "running":
		return false
	terminate_calls.append(launch_id)
	if termination_confirms_exit:
		_records[launch_id]["state"] = "exited"
	return termination_confirms_exit

func record(launch_id: String) -> Dictionary:
	return _records.get(launch_id, {}).duplicate(true)

func forget(launch_id: String) -> bool:
	if probe(launch_id) != "exited":
		return false
	_records.erase(launch_id)
	return true

func set_state(launch_id: String, state: String) -> void:
	if _records.has(launch_id):
		_records[launch_id]["state"] = state

func crash(launch_id: String) -> void:
	set_state(launch_id, "exited")
