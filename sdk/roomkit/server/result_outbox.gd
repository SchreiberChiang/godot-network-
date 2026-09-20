extends RefCounted
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var directory := ""
var secret := ""

func initialize(path: String, signing_secret: String) -> bool:
	directory = path
	secret = signing_secret
	return path.is_absolute_path() and signing_secret.length() == 64 and DirAccess.make_dir_recursive_absolute(path) == OK

func enqueue(record: Dictionary) -> Dictionary:
	if not Format.valid_record(record):
		return Wire.failure("INVALID_RESULT")
	var path := path_for(record.result_id)
	if FileAccess.file_exists(path):
		var old := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/result_submission.schema.json", 32768)
		return {"ok": true, "result_id": record.result_id} if not old.is_empty() and Format.hash_record(old.record) == Format.hash_record(record) else Wire.failure("RESULT_CONFLICT")
	if pending().size() >= 128:
		return Wire.failure("STORAGE_CAPACITY_EXCEEDED")
	var body := {"record": record, "signature": Format.sign(record, secret)}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return Wire.failure("STORAGE_UNAVAILABLE")
	file.store_string(JSON.stringify(body, "", true, true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return Wire.failure("STORAGE_UNAVAILABLE")
	return {"ok": true, "result_id": record.result_id}

func pending() -> Array:
	var found: Array = []
	for name in DirAccess.get_files_at(directory):
		if name.ends_with(".json") and not name.ends_with(".rejected.json"):
			found.append(directory.path_join(name))
	return found

func acknowledge(reply: Dictionary) -> bool:
	var path := path_for(reply.result_id)
	if not FileAccess.file_exists(path):
		return false
	var item := Wire.decode(FileAccess.get_file_as_bytes(path), "res://schemas/result_submission.schema.json", 32768)
	if item.is_empty() or Format.hash_record(item.record) != reply.record_hash:
		return false
	if reply.ok:
		return DirAccess.remove_absolute(path) == OK
	if reply.code not in ["STORAGE_UNAVAILABLE", "STORAGE_CAPACITY_EXCEEDED"]:
		return DirAccess.rename_absolute(path, path.trim_suffix(".json") + ".rejected.json") == OK
	return false

func path_for(result_id: String) -> String:
	return directory.path_join(result_id.sha256_text() + ".json")
