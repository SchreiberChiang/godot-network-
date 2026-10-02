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
var ended: Dictionary = {}
var ending: Dictionary = {}
var next_end: Dictionary = {}
var exit_times: Dictionary = {}

func configure(local_bus, room_manager, bootstrap: Dictionary) -> void:
	bus = local_bus
	manager = room_manager
	rpc_config = bootstrap.rpc.duplicate(true)
	repository.root = bootstrap.result_root
	schemas = bootstrap.result_schemas.duplicate(true)

func worker_store() -> Dictionary:
	return {"root": repository.root, "database": "", "rpc": rpc_config.duplicate(true)}

func apply_grant(grant: Dictionary, result: Dictionary) -> void:
	for launch in result.get("pruned", []):
		grants.erase(launch)
		ended.erase(launch)
		next_end.erase(launch)
		exit_times.erase(launch)
	grants[grant.launch_id] = grant

func poll() -> void:
	pass

func busy() -> bool:
	return not pending.is_empty() or not ending.is_empty()

func control_disconnected() -> bool:
	return bus != null and not bus.ready()

func confirm_exit(row: Dictionary) -> bool:
	var launch: String = row.launch_id
	if ended.has(launch):
		return true
	# Keep the durable exit journal for a new Operator. A dead control bus can
	# never acknowledge result.end; don't enqueue new, impossible RPCs forever.
	if control_disconnected():
		return false
	if not ending.has(launch) and Time.get_ticks_msec() >= int(next_end.get(launch, 0)):
		if not exit_times.has(launch):
			exit_times[launch] = int(row.get("exit_observed_at", Time.get_unix_time_from_system()))
		ending[launch] = true
		_end.call_deferred(launch)
	return false

func _end(launch: String) -> void:
	var result: Dictionary = await bus.request("result.end", {"launch_id": launch, "observed_exit_at": exit_times[launch]})
	ending.erase(launch)
	if result.ok:
		ended[launch] = true
	else:
		next_end[launch] = Time.get_ticks_msec() + 1000

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
