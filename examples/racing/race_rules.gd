extends RefCounted
## One race, owned by a trusted server simulation. No RPC or client result API.
## Checkpoint observations must come from server-side crossing detection, with
## a strictly increasing per-player event sequence allocated by that detector.

const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
const MAX_COUNTER := 2147483647

var _config: Dictionary = {"mode": "race", "checkpoint_count": 3, "laps": 3, "countdown_ms": 3000}
var _phase := "waiting"
var _clock_ms := 0
var _started_at_ms := -1
var _players: Dictionary = {}
var _finishers: Array = []


func configure(options: Variant = {}) -> Dictionary:
	if _phase != "waiting" or not _players.is_empty():
		return _result("CONFIG_LOCKED")
	if typeof(options) != TYPE_DICTIONARY:
		return _result("INVALID_CONFIG")
	var candidate := _config.duplicate(true)
	for key in options:
		if not candidate.has(key):
			return _result("INVALID_CONFIG")
		if key == "mode":
			if typeof(options[key]) != TYPE_STRING or options[key] not in ["race", "practice"]:
				return _result("INVALID_CONFIG")
		elif typeof(options[key]) != TYPE_INT:
			return _result("INVALID_CONFIG")
		candidate[key] = options[key]
	if candidate.checkpoint_count < 2 or candidate.checkpoint_count > 64:
		return _result("INVALID_CONFIG")
	if candidate.laps < 1 or candidate.laps > 99:
		return _result("INVALID_CONFIG")
	if candidate.countdown_ms < 1 or candidate.countdown_ms > 60000:
		return _result("INVALID_CONFIG")
	_config = candidate
	return _result()


func admit(user_id: Variant) -> Dictionary:
	if not _valid_id(user_id):
		return _result("INVALID_PLAYER")
	if _players.has(user_id):
		return _result("ALREADY_JOINED")
	if _phase != "waiting":
		return _result("ROSTER_LOCKED")
	if _players.size() >= _maximum_players():
		return _result("RACE_FULL")
	_players[user_id] = {
		"user_id": user_id, "connected": true, "status": "waiting",
		"completed_laps": 0, "next_checkpoint": 0, "last_event_sequence": 0,
		"rank": 0, "finish_time_ms": -1,
	}
	return _result()


func start_countdown() -> Dictionary:
	if _phase != "waiting":
		return _result("BAD_PHASE")
	if _players.size() < _minimum_players():
		return _result("NOT_ENOUGH_PLAYERS")
	_clock_ms = 0
	_started_at_ms = -1
	_phase = "countdown"
	return _result()


## The server supplies elapsed integer milliseconds, never a client timestamp.
## A step crossing the start boundary retains its racing-time remainder.
func advance(delta_ms: Variant) -> Dictionary:
	if typeof(delta_ms) != TYPE_INT or delta_ms < 0 or delta_ms > MAX_COUNTER:
		return _result("INVALID_TIME")
	if _phase != "countdown" and _phase != "racing":
		return _result("BAD_PHASE")
	if delta_ms > MAX_COUNTER - _clock_ms:
		return _result("INVALID_TIME")
	_clock_ms += delta_ms
	if _phase == "countdown" and _clock_ms >= _config.countdown_ms:
		_started_at_ms = _config.countdown_ms
		_phase = "racing"
		for player in _players.values():
			player.status = "racing"
	return _result()


## Only a trusted server observation, not a network message handler.
## No caller-supplied lap, elapsed time, rank, score or result is accepted.
func observe_checkpoint(user_id: Variant, checkpoint: Variant, event_sequence: Variant) -> Dictionary:
	if not _valid_id(user_id) or not _players.has(user_id):
		return _result("UNKNOWN_PLAYER")
	if _phase != "racing":
		return _result("BAD_PHASE")
	var player: Dictionary = _players[user_id]
	if player.status != "racing":
		return _result("PLAYER_INACTIVE")
	if typeof(checkpoint) != TYPE_INT or checkpoint < 0 or checkpoint >= _config.checkpoint_count:
		return _result("INVALID_CHECKPOINT")
	if typeof(event_sequence) != TYPE_INT or event_sequence < 1 or event_sequence > MAX_COUNTER:
		return _result("INVALID_SEQUENCE")
	if event_sequence <= player.last_event_sequence:
		return _result("STALE_EVENT")
	# Consume even an out-of-order observation: it cannot be replayed later when
	# that checkpoint becomes expected. Rejection changes only this watermark.
	player.last_event_sequence = event_sequence
	if checkpoint != player.next_checkpoint:
		return _result("WRONG_CHECKPOINT")
	player.next_checkpoint += 1
	if player.next_checkpoint == _config.checkpoint_count:
		player.completed_laps += 1
		player.next_checkpoint = 0
		if player.completed_laps == _config.laps:
			player.status = "finished"
			player.next_checkpoint = -1
			player.rank = _finishers.size() + 1
			player.finish_time_ms = _clock_ms - _started_at_ms
			_finishers.append({
				"user_id": user_id, "rank": player.rank,
				"completed_laps": player.completed_laps,
				"finish_time_ms": player.finish_time_ms,
			})
			_finish_if_resolved()
	return _result()


func leave(user_id: Variant) -> Dictionary:
	if not _valid_id(user_id) or not _players.has(user_id):
		return _result("UNKNOWN_PLAYER")
	var player: Dictionary = _players[user_id]
	if not player.connected:
		return _result("ALREADY_LEFT")
	if _phase == "waiting" or _phase == "countdown":
		_players.erase(user_id)
		if _phase == "countdown" and _players.size() < _minimum_players():
			# A later start requires a new explicit countdown, from its full length.
			_phase = "waiting"
			_clock_ms = 0
			_started_at_ms = -1
		return _result()
	player.connected = false
	if player.status == "racing":
		player.status = "dnf"
		_finish_if_resolved()
	# Leaving after finishing never removes, renumbers or overwrites a result.
	return _result()


func snapshot() -> Dictionary:
	return {
		"phase": _phase, "min_players": _minimum_players(), "max_players": _maximum_players(), "config": _config.duplicate(true),
		"countdown_remaining_ms": maxi(0, _config.countdown_ms - _clock_ms) if _phase == "countdown" else 0,
		"race_elapsed_ms": _clock_ms - _started_at_ms if _started_at_ms >= 0 else 0,
		"players": _players.duplicate(true), "finishers": results(),
	}


func results() -> Array:
	return _finishers.duplicate(true)


## Practice explicitly opts into one seat; race keeps its original 2-8 roster.
## Both modes retain the same countdown-end timing and ordered lap semantics.
func _minimum_players() -> int:
	return 1 if _config.mode == "practice" else MIN_PLAYERS


func _maximum_players() -> int:
	return 1 if _config.mode == "practice" else MAX_PLAYERS


func _finish_if_resolved() -> void:
	for player in _players.values():
		if player.status == "racing":
			return
	_phase = "finished"


func _valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() >= 1 and value.length() <= 128 and value == value.strip_edges()


func _result(code := "OK") -> Dictionary:
	return {"ok": code == "OK", "code": code}
