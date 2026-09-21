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

func initialize(root: String, payload_schemas: Dictionary) -> Dictionary:
	schemas = payload_schemas.duplicate()
	var result: Dictionary = repository.initialize(root)
	if not result.ok:
		return result
	result = repository.execute({"op": "grants"})
	if not result.ok:
		return result
	for grant in result.grants:
		grants[grant.launch_id] = grant
	return {"ok": true, "code": ""}

func prepare_launch(row: Dictionary) -> Dictionary:
	if not schemas.has(row.game_id):
		return Wire.failure("INVALID_RESULT")
	var grant := {"launch_id": row.launch_id, "room_id": row.room_id, "game_id": row.game_id, "build_id": row.build_id, "secret": Crypto.new().generate_random_bytes(32).hex_encode()}
	var result: Dictionary = repository.execute({"op": "grant", "grant": grant})
	if not result.ok:
		return result
	grants[row.launch_id] = grant
	return {"ok": true, "config": {"directory": repository.root.path_join("outbox").path_join(row.launch_id), "secret": grant.secret}}

func accept(submission: Dictionary) -> Dictionary:
	var validated := validate_submission(submission)
	if not validated.ok:
		return validated
	var result: Dictionary = repository.execute(validated.request)
	if result.ok:
		accepted_count += 1
	return result

func validate_submission(submission: Dictionary) -> Dictionary:
	if Validator.validate_file(submission, "res://schemas/result_submission.schema.json") != "" or not Format.valid_record(submission.get("record", {})):
		return Wire.failure("INVALID_RESULT")
	var record: Dictionary = submission.record
	var grant: Dictionary = grants.get(record.launch_id, {})
	if grant.is_empty():
		return Wire.failure("AUTH_FAILED")
	for key in ["game_id", "build_id", "room_id"]:
		if record[key] != grant[key]:
			return Wire.failure("AUTH_FAILED")
	if not record.match_id.begins_with("m_" + record.launch_id + "_") or submission.signature != Format.sign(record, grant.secret):
		return Wire.failure("AUTH_FAILED")
	if not schemas.has(record.game_id) or Validator.validate_file(record.payload, schemas[record.game_id]) != "":
		return Wire.failure("INVALID_RESULT")
	return {"ok": true, "request": {"op": "accept", "record": record.duplicate(true), "record_hash": Format.hash_record(record), "body": Format.canonical(record)}}

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
				if existing.result_id == job.result_id and existing.record_hash == job.record_hash:
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
		if result.ok:
			accepted_count += 1
		_send_ack(current.room_id, {"result_id": current.result_id, "record_hash": current.record_hash, "ok": result.ok, "code": result.code})
		current = {}
	if worker == null and not pending.is_empty():
		current = pending.pop_front()
		worker = Thread.new()
		if worker.start(repository.execute.bind(current.request)) != OK:
			worker = null
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
	for launch in grants:
		var directory: String = repository.root.path_join("outbox").path_join(launch)
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for name in DirAccess.get_files_at(directory):
			if not name.ends_with(".json") or name.ends_with(".rejected.json"):
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
