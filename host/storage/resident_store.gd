extends RefCounted
## One serial resident storage worker (tools/storage_worker.ps1) per database file.
## Callers on worker threads queue on a mutex, so a database never has more than one
## worker process. The host holds the worker's process handle (execute_with_pipe),
## enforces a per-request deadline and kills the worker on timeout.
## request() returns {} when the resident path failed (no reply, timeout, worker
## fault). Callers then repeat the operation through the one-shot helper, which is
## only allowed for operations that are safe to repeat: reads, receipt-guarded
## asset.commit with the same request_id, and session.authenticate.
## Set ROOMKIT_STORAGE_MODE=oneshot to use only the one-shot helpers.
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const QUEUE_LIMIT := 16
const REPLY_LIMIT := 4 * 1024 * 1024
static var _registry: Dictionary = {}
static var _registry_lock := Mutex.new()

var helper := ""
var database := ""
var timeout_ms := 10000
var idle_seconds := 300
var queue_limit := QUEUE_LIMIT
var started_workers := 0
var requests := 0
var fallbacks := 0
var timeouts := 0
var _serial := Mutex.new()
var _state := Mutex.new()
var _waiting := 0
var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _deadline := 0

static func enabled() -> bool:
	# Needs the verified Godot 4.7.2 handle-release rule used by BoundedHelper.
	return OS.get_environment("ROOMKIT_STORAGE_MODE").to_lower() != "oneshot" and Helper._handle_release_verified()

static func for_database(helper_name: String, database_path: String, timeout: int) -> RefCounted:
	var key := helper_name + "|" + database_path.simplify_path().to_lower()
	_registry_lock.lock()
	var store: RefCounted = _registry.get(key)
	if store == null:
		store = (load("res://host/storage/resident_store.gd") as GDScript).new()
		store.helper = helper_name
		store.database = database_path
		store.timeout_ms = timeout
		_registry[key] = store
	_registry_lock.unlock()
	return store

static func shutdown_all() -> void:
	_registry_lock.lock()
	var stores: Array = _registry.values()
	_registry_lock.unlock()
	for store in stores:
		store.stop()

func request(payload: Dictionary) -> Dictionary:
	_state.lock()
	if _waiting >= queue_limit:
		_state.unlock()
		return {"ok": false, "code": "STORAGE_UNAVAILABLE"}
	_waiting += 1
	requests += 1
	_state.unlock()
	_serial.lock()
	var reply := _exchange(payload)
	_serial.unlock()
	_state.lock()
	_waiting -= 1
	_state.unlock()
	return reply

func worker_pid() -> int:
	_state.lock()
	var pid := _pid
	_state.unlock()
	return pid

func stop() -> void:
	# Waits for an in-flight request, asks the worker to exit, then releases it.
	_serial.lock()
	_state.lock()
	if _pid > 0:
		if _stdio != null:
			_stdio.store_line("")
		var until := Time.get_ticks_msec() + 3000
		while OS.get_process_exit_code(_pid) < 0 and OS.is_process_running(_pid) and Time.get_ticks_msec() < until:
			OS.delay_msec(5)
		_release_locked()
	_state.unlock()
	_serial.unlock()

func _exchange(payload: Dictionary) -> Dictionary:
	if not _ensure_worker():
		fallbacks += 1
		return {}
	_state.lock()
	var pid := _pid
	var stdio := _stdio
	var stderr := _stderr
	_deadline = Time.get_ticks_msec() + timeout_ms
	_state.unlock()
	var guard := Thread.new()
	guard.start(_guard.bind(pid))
	var bytes := PackedByteArray()
	var complete := stdio.store_line(Marshalls.utf8_to_base64(JSON.stringify(payload)))
	while complete:
		var chunk := stdio.get_buffer(65536)
		if chunk.is_empty() or bytes.size() + chunk.size() > REPLY_LIMIT:
			complete = false
			break
		bytes.append_array(chunk)
		if chunk.has(10):
			break
	_state.lock()
	_deadline = 0
	_state.unlock()
	guard.wait_to_finish()
	var reply: Variant = null
	if complete:
		var end := bytes.find(10)
		reply = JSON.parse_string(bytes.slice(0, end).get_string_from_utf8())
	if reply is Dictionary and reply.get("code", "") != "WORKER_FAILED":
		return reply
	# The worker's state is unknown: release it (unless the guard already killed it).
	_state.lock()
	if _pid == pid:
		_release_locked()
	else:
		stdio.close()
		stderr.close()
	_state.unlock()
	fallbacks += 1
	return {}

func _guard(pid: int) -> void:
	# Per-request deadline. Only kills while the entry is still ours and present.
	while true:
		_state.lock()
		if _deadline == 0 or _pid != pid:
			_state.unlock()
			return
		if Time.get_ticks_msec() > _deadline:
			if OS.is_process_running(pid) or OS.get_process_exit_code(pid) >= 0:
				OS.kill(pid)
			# The blocked caller closes its own pipe references after the read fails.
			_pid = -1
			_stdio = null
			_stderr = null
			_deadline = 0
			timeouts += 1
			_state.unlock()
			return
		_state.unlock()
		OS.delay_msec(2)

func _ensure_worker() -> bool:
	_state.lock()
	if _pid > 0 and not OS.is_process_running(_pid):
		# Idle exit or crash: release the finished process entry before replacing it.
		_release_locked()
	if _pid <= 0:
		var launched := OS.execute_with_pipe("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Paths.absolute("res://tools/storage_worker.ps1"), "-Helper", helper, "-Database", database, "-IdleSeconds", str(idle_seconds)], true)
		if launched.is_empty():
			_state.unlock()
			return false
		_pid = int(launched.pid)
		_stdio = launched.stdio
		_stderr = launched.stderr
		started_workers += 1
	_state.unlock()
	return true

func _release_locked() -> void:
	# Held-handle rule (see BoundedHelper._wait_and_release): OS.kill only while the
	# process entry is present; it terminates a live worker or just frees the
	# handles of a finished one. Never reached with a missing entry.
	if _pid > 0 and (OS.is_process_running(_pid) or OS.get_process_exit_code(_pid) >= 0):
		OS.kill(_pid)
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()
	_pid = -1
	_stdio = null
	_stderr = null
