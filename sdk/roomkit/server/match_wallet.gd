extends RefCounted
## Optional match-local economy. Never opens the permanent store or grants account assets.
## Create a fresh instance per match. No persistence, account conversion or recovery promise.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var _instance: String
var _balances: Dictionary = {}
var _receipts: Dictionary = {}
var _closed := false

func _init(launch_id: String, match_id: String) -> void:
	_instance = launch_id + "/" + match_id
	_closed = launch_id.is_empty() or match_id.is_empty()

func instance_id() -> String:
	return _instance

func balance(user_id: String) -> int:
	return int(_balances.get(user_id, 0))

func change(user_id: String, delta: int, request_id: String) -> Dictionary:
	if _closed:
		return Wire.failure("MATCH_CLOSED")
	if user_id.is_empty() or user_id.length() > 128 or request_id.is_empty() or request_id.length() > 64 or delta < -1000000 or delta > 1000000:
		return Wire.failure("INVALID_ASSET_COMMAND")
	var key := JSON.stringify([user_id, request_id])
	if _receipts.has(key):
		if int(_receipts[key].delta) != delta:
			return Wire.failure("REQUEST_CONFLICT")
		return _receipts[key].result.duplicate(true)
	if _receipts.size() >= 10000 or (not _balances.has(user_id) and _balances.size() >= 16):
		return Wire.failure("ASSET_LIMIT_EXCEEDED")
	var next := balance(user_id) + delta
	if next < 0 or next > 1000000000:
		return Wire.failure("INSUFFICIENT_CREDITS" if next < 0 else "ASSET_LIMIT_EXCEEDED")
	_balances[user_id] = next
	var result := {"ok": true, "balance": next, "instance_id": _instance}
	_receipts[key] = {"delta": delta, "result": result.duplicate(true)}
	return result

func close() -> void:
	_closed = true
	_balances.clear()
	_receipts.clear()
