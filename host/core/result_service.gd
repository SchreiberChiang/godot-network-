extends RefCounted
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var repository = Repository.new()
var grants: Dictionary = {}
var schemas: Dictionary = {}
var _manager: WeakRef
var manager:
	get:
		return _manager.get_ref() if _manager != null else null
	set(value):
		_manager = weakref(value) if value != null else null
var accepted_count := 0
var ack_count := 0
var pending: Array = []
var worker: Thread
var current: Dictionary = {}
var reward_calculator: Callable
# Trusted server clock; injectable only by tests, never from a submission/RPC.
var clock: Callable
var ended: Dictionary = {}
var ending: Dictionary = {}
var next_end: Dictionary = {}
var exit_times: Dictionary = {}

func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

func store_grant(grant: Dictionary) -> Dictionary:
	var request := {"op": "grant", "grant": grant}
	if clock.is_valid():
		request.server_now = now()
	return repository.execute(request)

func apply_grant(grant: Dictionary, result: Dictionary) -> void:
	# Operator storage work runs on a thread; update shared service maps only
	# after the owning main loop receives its response.
	if result.ok:
		for launch in result.get("pruned", []):
			grants.erase(launch)
			ended.erase(launch)
			next_end.erase(launch)
			exit_times.erase(launch)
		grants[grant.launch_id] = grant

func end_launch(launch_id: String, observed_at: int = -1) -> Dictionary:
	# Only the owning host/recovery path calls this after proving process exit.
	var request := {"op": "grant.end", "launch_id": launch_id, "ended_at": now() if observed_at < 0 else observed_at}
	if clock.is_valid():
		request.server_now = now()
	return repository.execute(request)

func commit(request: Dictionary) -> Dictionary:
	request = request.duplicate(true)
	# Production expiry is sampled inside the helper's BEGIN IMMEDIATE, not at
	# validation/queue admission. Only tests override it through this Callable.
	if clock.is_valid():
		request.server_now = now()
	return repository.execute(request)

func confirm_exit(row: Dictionary) -> bool:
	var launch: String = row.launch_id
	if ended.has(launch):
		return true
	if not ending.has(launch) and Time.get_ticks_msec() >= int(next_end.get(launch, 0)):
		ending[launch] = true
		if not exit_times.has(launch):
			exit_times[launch] = int(row.get("exit_observed_at", now()))
		pending.append({"end_launch": launch, "request": {"op": "grant.end", "launch_id": launch, "ended_at": exit_times[launch]}})
		next_end[launch] = Time.get_ticks_msec() + 1000
	return false

func initialize(root: String, payload_schemas: Dictionary, database_name: String = "results.sqlite") -> Dictionary:
	schemas = payload_schemas.duplicate()
	var result: Dictionary = repository.initialize(root, database_name)
	if not result.ok:
		return result
	result = repository.execute({"op": "grants"})
	if not result.ok:
		return result
	grants.clear()
	for grant in result.grants:
		grants[grant.launch_id] = grant
	return {"ok": true, "code": ""}

func prepare_launch(row: Dictionary) -> Dictionary:
	if not schemas.has(row.game_id):
		return Wire.failure("INVALID_RESULT")
	var grant := {"launch_id": row.launch_id, "room_id": row.room_id, "game_id": row.game_id, "build_id": row.build_id, "secret": Crypto.new().generate_random_bytes(32).hex_encode()}
	var result: Dictionary = store_grant(grant)
	if not result.ok:
		return result
	apply_grant(grant, result)
	return {"ok": true, "config": {"directory": repository.root.path_join("outbox").path_join(row.launch_id), "secret": grant.secret}}

func accept(submission: Dictionary) -> Dictionary:
	var validated := validate_submission(submission)
	if not validated.ok:
		return validated
	var result: Dictionary = commit(validated.request)
	if result.ok:
		accepted_count += 1
	return result

func validate_submission(submission: Dictionary) -> Dictionary:
	if Validator.validate_file(submission, "res://schemas/result_submission.schema.json") != "" or not Format.valid_record(submission.get("record", {})):
		return Wire.failure("INVALID_RESULT")
	var record: Dictionary = submission.record
	var grant: Dictionary = grants.get(record.launch_id, {})
	if not grant.is_empty():
		for key in ["game_id", "build_id", "room_id"]:
			if record[key] != grant[key]:
				return Wire.failure("AUTH_FAILED")
		if submission.signature != Format.sign(record, grant.secret):
			return Wire.failure("AUTH_FAILED")
	# Missing grants are resolved transactionally: only an exact already stored
	# signature/hash may replay, and expired unseen results never earn rewards.
	if not record.match_id.begins_with("m_" + record.launch_id + "_"):
		return Wire.failure("AUTH_FAILED")
	if not schemas.has(record.game_id) or Validator.validate_file(record.payload, schemas[record.game_id]) != "":
		return Wire.failure("INVALID_RESULT")
	var request := {"op": "accept", "record": record.duplicate(true), "record_hash": Format.hash_record(record), "body": Format.canonical(record), "signature": submission.signature}
	if reward_calculator.is_valid():
		request.rewards = reward_calculator.call(record.duplicate(true))
	return {"ok": true, "request": request}

func handle(row: Dictionary, message: Dictionary) -> bool:
	if message.type != "result.submit":
		return false
	var record: Dictionary = message.payload.record
	var result: Dictionary = Wire.failure("AUTH_FAILED")
	if record.launch_id == row.launch_id and record.room_id == row.room_id and row.registered:
		result = validate_submission(message.payload)
		if result.ok:
			var job := {"room_id": row.room_id, "result_id": record.result_id, "record_hash": result.request.record_hash, "request": result.request}
			for existing in pending + ([current] if not current.is_empty() else []):
				if existing.has("result_id") and existing.result_id == job.result_id and existing.record_hash == job.record_hash:
					return true
			if pending.size() < 64:
				pending.append(job)
				return true
			result = Wire.failure("STORAGE_CAPACITY_EXCEEDED")
	_send_ack(row.room_id, {"result_id": record.result_id, "record_hash": Format.hash_record(record), "ok": result.ok, "code": result.code})
	return true

func poll() -> void:
	if worker != null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		if current.has("end_launch"):
			ending.erase(current.end_launch)
			if result.ok:
				ended[current.end_launch] = true
		else:
			if result.ok:
				accepted_count += 1
			_send_ack(current.room_id, {"result_id": current.result_id, "record_hash": current.record_hash, "ok": result.ok, "code": result.code})
		current = {}
	if worker == null and not pending.is_empty():
		current = pending.pop_front()
		worker = Thread.new()
		if worker.start(commit.bind(current.request)) != OK:
			worker = null
			if current.has("end_launch"):
				ending.erase(current.end_launch)
			else:
				_send_ack(current.room_id, {"result_id": current.result_id, "record_hash": current.record_hash, "ok": false, "code": "STORAGE_UNAVAILABLE"})
			current = {}

func busy() -> bool:
	return worker != null or not pending.is_empty()

func _send_ack(room_id: String, payload: Dictionary) -> void:
	ack_count += 1
	manager.send_control(room_id, "result.ack", payload)

# Offline recovery uses persisted launch grants, never trusts an arbitrary file.
func recover() -> Dictionary:
	var report := {"accepted": 0, "rejected": 0, "pending": 0}
	var root_access := DirAccess.open(repository.root)
	if root_access == null:
		report.pending += 1
		return report
	if root_access.is_link("outbox"):
		report.pending += 1
		return report
	var outbox_access := DirAccess.open(repository.root.path_join("outbox"))
	if outbox_access == null:
		return report
	# Also scan previously reclaimed grants: transaction receipts still support
	# exact retries, while new expired files become explicit rejected evidence.
	for launch in DirAccess.get_directories_at(repository.root.path_join("outbox")):
		if outbox_access.is_link(launch):
			report.pending += 1
			continue
		var directory: String = repository.root.path_join("outbox").path_join(launch)
		if not DirAccess.dir_exists_absolute(directory):
			continue
		var access := DirAccess.open(directory)
		if access == null:
			report.pending += 1
			continue
		for name in DirAccess.get_files_at(directory):
			if not name.ends_with(".json") or name.ends_with(".rejected.json"):
				continue
			if access.is_link(name):
				report.pending += 1
				continue
			var path: String = directory.path_join(name)
			var submission := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/result_submission.schema.json", 32768)
			var result: Dictionary = Wire.failure("AUTH_FAILED")
			if not submission.is_empty() and submission.record.launch_id == launch:
				result = accept(submission)
			if result.ok:
				if DirAccess.remove_absolute(path) == OK:
					report.accepted += 1
				else:
					report.pending += 1
			elif result.code in ["STORAGE_UNAVAILABLE", "STORAGE_CAPACITY_EXCEEDED"]:
				report.pending += 1
			else:
				if DirAccess.rename_absolute(path, path.trim_suffix(".json") + ".rejected.json") == OK:
					report.rejected += 1
				else:
					report.pending += 1
	return report
