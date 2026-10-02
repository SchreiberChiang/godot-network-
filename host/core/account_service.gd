extends RefCounted
## Private SQLite account adapter (Windows, and Linux through posix_helper.gd). Call execute() on a worker thread.
## The network adapter must set client_ip from its accepted connection.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Resident = preload("res://host/storage/resident_store.gd")
const DataRoot = preload("res://host/platform/posix_data_root.gd")
var root := ""
var database := ""

func initialize(directory: String) -> Dictionary:
	if OS.get_name() == "Linux":
		return _initialize_posix(directory)
	if OS.get_name() != "Windows":
		return Wire.failure("UNSUPPORTED_STORAGE")
	root = Paths.absolute(directory)
	database = root.path_join("accounts.sqlite")
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Paths.absolute("res://tools/protect_data.ps1"), "-ProjectRoot", Paths.absolute("res://"), "-DataRoot", root], output, false, false)
	if code != 0:
		return Wire.failure("PRIVATE_DATA_FAILED")
	return _dispatch({"op": "init"})

## Linux: folders 700 and the database 600, verified before and after the helper
## creates or opens it. When protection fails the service stays unusable.
func _initialize_posix(directory: String) -> Dictionary:
	root = Paths.absolute(directory)
	database = root.path_join("accounts.sqlite")
	if not DataRoot.prepare(root) or not DataRoot.seal(database, false):
		root = ""
		return Wire.failure("PRIVATE_DATA_FAILED")
	var result := _dispatch({"op": "init"})
	if result.get("ok", false) and not DataRoot.seal(database, true):
		root = ""
		return Wire.failure("PRIVATE_DATA_FAILED")
	return result

func execute(request: Dictionary, deadline_ms: int = 0) -> Dictionary:
	if Validator.validate_file(request, "res://schemas/account_request.schema.json") != "":
		return Wire.failure("INVALID_ACCOUNT_REQUEST")
	return _dispatch(request, deadline_ms)

func authenticate(credential: String, _now: int = 0) -> Dictionary:
	# Time is read inside the backend, never accepted from a client or caller.
	return execute({"op": "session.authenticate", "token": credential})

func reset_player_sessions() -> Dictionary:
	# Trusted local lifecycle hook, deliberately absent from execute()'s public
	# schema. The operator must first verify its old host and rooms have exited.
	# The helper records a fixed recovery reason and never clears admin sessions.
	return _dispatch({"op": "local.reset_player_sessions"})

## Trusted local deletion hooks, also absent from execute()'s public schema. The
## Operator reaches them only after an authenticated admin began the job, or when it
## resumes interrupted jobs on start-up (host/core/account_deletion.gd).
func pending_deletions() -> Dictionary:
	return _dispatch({"op": "local.deletion_pending"})

func finish_deletion(job_id: String) -> Dictionary:
	return _dispatch({"op": "local.deletion_finish", "job_id": job_id})

func close_deletion(job_id: String) -> Dictionary:
	return _dispatch({"op": "local.deletion_close", "job_id": job_id})

## Starts the account database's worker early; an all-zero token only returns AUTH_FAILED.
func prewarm() -> Dictionary:
	return _dispatch({"op": "session.authenticate", "token": "0".repeat(64)})

func _dispatch(request: Dictionary, deadline_ms: int = 0) -> Dictionary:
	if root.is_empty():
		return Wire.failure("STORAGE_UNAVAILABLE")
	# Only session.authenticate uses the resident worker in this stage: it is safe to
	# repeat (it only also removes expired sessions). Registration, login and other
	# writes stay on the one-shot helper.
	if request.get("op", "") == "session.authenticate" and Resident.enabled():
		var reply: Dictionary = Resident.for_database("account_store.ps1", database, 10000).request(request)
		if not reply.is_empty():
			return reply
	# Passwords and tokens go to the helper over stdin only; no request file is
	# written, so a host crash mid-call leaves no secret in the data directory.
	# Internal monotonic deadline, never supplied by a network payload. Recompute
	# on this worker immediately before launching, so admission/thread delay does
	# not grant a fresh 30-second helper budget. Windows pipe startup/reaping still
	# has its existing overhead; this is not a hard wall-clock return guarantee.
	var remaining_ms := 30000
	if deadline_ms > 0:
		remaining_ms = mini(remaining_ms, deadline_ms - Time.get_ticks_msec())
		# The Windows helper accepts budgets of at least 100 ms. Never round
		# up a shorter remainder and accidentally grant time past the deadline.
		if remaining_ms < 100:
			return Wire.failure("RATE_LIMITED")
	var result := Helper.execute_input("account_store.ps1", ["-Database", database], JSON.stringify(request), remaining_ms)
	if str(result.get("code", "")).begins_with("HELPER_"):
		return Wire.failure("STORAGE_UNAVAILABLE")
	return result
