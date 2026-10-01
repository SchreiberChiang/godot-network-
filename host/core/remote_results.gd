extends RefCounted
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
var repository = Repository.new()
var schemas: Dictionary = {}
var grants: Dictionary = {}
var rpc_config: Dictionary = {}
var bus
var _manager: WeakRef
# RoomManager owns this service; its return route must not own the manager.
var manager:
	get:
		return _manager.get_ref() if _manager != null else null
	set(value):
		_manager = weakref(value) if value != null else null
var pending: Dictionary = {}

func configure(local_bus, room_manager, bootstrap: Dictionary) -> void:
	bus = local_bus
	manager = room_manager
	rpc_config = bootstrap.rpc.duplicate(true)
	repository.root = bootstrap.result_root
	schemas = bootstrap.result_schemas.duplicate(true)

func worker_store() -> Dictionary:
	return {"root": repository.root, "database": "", "rpc": rpc_config.duplicate(true)}

func poll() -> void:
	pass

func busy() -> bool:
	return not pending.is_empty()

func handle(row: Dictionary, message: Dictionary) -> bool:
	if message.type != "result.submit":
		return false
	var record: Dictionary = message.payload.record
	if record.room_id != row.room_id or record.launch_id != row.launch_id:
		return false
	var hash := Format.hash_record(record)
	if pending.has(hash):
		return true
	if pending.size() >= 64:
		return false
	pending[hash] = true
	_submit.call_deferred(row.room_id, record.result_id, hash, message.payload.duplicate(true))
	return true

func _submit(room_id: String, result_id: String, hash: String, submission: Dictionary) -> void:
	var result: Dictionary = await bus.request("result.submit", submission)
	pending.erase(hash)
	var target = manager
	if target != null:
		target.send_control(room_id, "result.ack", {"result_id": result_id, "record_hash": hash, "ok": result.ok, "code": result.get("code", "")})
