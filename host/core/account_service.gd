extends RefCounted
## Windows private SQLite account adapter. Call execute() on a worker thread.
## The network adapter must set client_ip from its accepted connection.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Helper = preload("res://host/platform/bounded_helper.gd")
const Paths = preload("res://sdk/roomkit/shared/paths.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const Resident = preload("res://host/storage/resident_store.gd")
var root := ""
var database := ""

func initialize(directory: String) -> Dictionary:
	if OS.get_name() != "Windows":
		return Wire.failure("UNSUPPORTED_STORAGE")
	root = Paths.absolute(directory)
	database = root.path_join("accounts.sqlite")
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Paths.absolute("res://tools/protect_data.ps1"), "-ProjectRoot", Paths.absolute("res://"), "-DataRoot", root], output, false, false)
	if code != 0:
		return Wire.failure("PRIVATE_DATA_FAILED")
	return _dispatch({"op": "init"})

func execute(request: Dictionary) -> Dictionary:
	if Validator.validate_file(request, "res://schemas/account_request.schema.json") != "":
		return Wire.failure("INVALID_ACCOUNT_REQUEST")
	return _dispatch(request)

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

func _dispatch(request: Dictionary) -> Dictionary:
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
	var result := Helper.execute_input("account_store.ps1", ["-Database", database], JSON.stringify(request), 30000)
	if str(result.get("code", "")).begins_with("HELPER_"):
		return Wire.failure("STORAGE_UNAVAILABLE")
	return result
