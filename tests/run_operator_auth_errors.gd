extends "res://host/operator.gd"
## Executes production _admin / _http_request / worker admission. Only the
## account helper and HTTP response sink are doubles; no live fixture is used.
class AccountDouble extends RefCounted:
	var reply: Dictionary = {}
	var calls := 0
	func execute(_request: Dictionary) -> Dictionary:
		calls += 1
		return reply.duplicate(true)

class HttpDouble extends RefCounted:
	var result: Dictionary = {}
	var status := 0
	func respond(_id: String, response: Dictionary, http_status: int) -> void:
		result = response
		status = http_status

var test_passed := 0
var test_failed := 0

func _initialize() -> void:
	accounts = AccountDouble.new()
	http = HttpDouble.new()
	_exercise.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _exercise() -> void:
	var request := {"action": "status", "payload": {}, "token": "a".repeat(64)}
	worker_count = 8
	await _http_request("capacity", request)
	check(http.result.code == "RATE_LIMITED" and http.status != 401 and accounts.calls == 0, "real worker admission failure remains retryable, not invalid credentials")
	worker_count = 0
	accounts.reply = Wire.failure("STORAGE_UNAVAILABLE")
	await _http_request("storage", request)
	check(http.result.code == "STORAGE_UNAVAILABLE" and http.status != 401, "account storage failure preserves code without HTTP auth rejection")
	accounts.reply = {"ok": true, "identity": {"role": "admin"}}
	await _http_request("recovered", request)
	check(http.result.ok and http.status == 200 and http.result.payload.host.state == "STOPPED", "same authenticated request succeeds after temporary storage recovery")
	accounts.reply = Wire.failure("AUTH_FAILED")
	await _http_request("expired", request)
	check(http.result.code == "AUTH_FAILED" and http.status == 401, "real credential rejection still produces HTTP 401")
	accounts.reply = {"ok": true, "identity": {"role": "player"}}
	await _http_request("role", request)
	check(not http.result.ok and http.result.code == "ADMIN_REQUIRED", "authenticated player cannot enter admin status")
	check(worker_count == 0, "all actual worker threads finish with balanced admission count")
	print("OPERATOR_AUTH_ERRORS_RESULT passed=", test_passed, " failed=", test_failed)
	quit(0 if test_failed == 0 else 1)

func check(condition: bool, label: String) -> void:
	if condition:
		test_passed += 1
		print("PASS ", label)
	else:
		test_failed += 1
		printerr("FAIL ", label)
