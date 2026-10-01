extends RefCounted
## Operator-owned clean-up of player session tokens it already knows (docs/17
## "当前收尾任务"). Every path that ends a player's session (explicit logout, lobby
## disconnect, a login reply whose connection is gone, a wrong role, host exit)
## hands the token here; this object keeps the responsibility until the token is
## confirmed gone or the job fails visibly. Nothing else retries a logout.
##
## Limits: one job per token (repeated triggers merge); at most 3 attempts (first
## + 2), 0.5 s then 2 s back-off after a transient failure; at most 2 attempts in
## flight; at most 64 queued jobs; 35 s per job including queueing; an attempt
## counts as "result unknown" after min(10 s, time left). A timed-out attempt
## keeps its slot until it really returns (no unbounded threads). Only transient
## codes are retried; AUTH_FAILED for our own, format-checked old token means it
## is already invalid (an end point). Failures stay listed with their token so a
## later trigger can re-arm them; they never count as success.
##
## The token is never printed or exported: logs and status carry a random job id,
## the reason, attempt count, code and elapsed time only. A pending job does not
## mean the player is online and is never used to restore a connection.
## start_attempt(job_id: String, token: String, attempt: int) must start the
## logout without blocking and later call complete(job_id, attempt, result).
const MAX_ATTEMPTS := 3
const BACKOFF_MS := [500, 2000]
const MAX_RUNNING := 2
const MAX_QUEUED := 64
const MAX_FAILED := 256
const JOB_DEADLINE_MS := 35000
const ATTEMPT_LIMIT_MS := 10000
const TRANSIENT := ["STORAGE_UNAVAILABLE", "RATE_LIMITED", "STORAGE_MAINTENANCE", "HELPER_TIMEOUT", "HELPER_FAILED", "HELPER_UNFINISHED", "HELPER_BACKLOG_FULL", "RESULT_UNKNOWN"]

var start_attempt: Callable
var clock: Callable = func() -> int: return Time.get_ticks_msec()
var job_deadline_ms := JOB_DEADLINE_MS
var attempt_limit_ms := ATTEMPT_LIMIT_MS
var backoff_ms: Array = BACKOFF_MS.duplicate()
var max_queued := MAX_QUEUED
var max_running := MAX_RUNNING
## Called with (token, outcome) once a job ends: "done", "invalid" or "failed".
var on_finished: Callable
var jobs: Dictionary = {}       # token -> job (queued, waiting or running)
var failed: Dictionary = {}     # token -> job (ended without confirmation)
var running: Dictionary = {}    # "<job id>:<attempt>" -> {"job_id", "token", "started", "limit", "stale"}
var events: Array = []          # last 200 log lines, for tests and diagnostics
var outcomes: Dictionary = {}   # job id -> {"outcome", "code"} of ended jobs (last 256)

func _now() -> int:
	return int(clock.call())

## Hands over a known token. Returns {"ok", "code", "job_id"}; ok is false when
## the token is malformed or the queue is full (that failure is kept and logged).
func submit(token: String, user_id: String, reason: String) -> Dictionary:
	if not _valid_token(token):
		return {"ok": false, "code": "INVALID_TOKEN", "job_id": ""}
	if jobs.has(token):
		_log(jobs[token], "merged", "", reason)
		return {"ok": true, "code": "", "job_id": jobs[token].job_id}
	var job := {"job_id": Crypto.new().generate_random_bytes(16).hex_encode(), "user_id": user_id, "reason": reason, "created": _now(), "attempts": 0, "next_at": _now(), "state": "queued", "code": ""}
	if failed.has(token):
		# A later trigger creates a new generation. An old timed-out attempt can
		# still occupy a slot and return; its id must never alias this new job.
		# Keep the previous outcome for callers waiting on that generation.
		failed.erase(token)
	if jobs.size() >= max_queued:
		job.state = "failed"
		job.code = "CLEANUP_QUEUE_FULL"
		_keep_failed(token, job)
		_log(job, "failed", job.code, reason)
		_finish(token, job, "failed")
		return {"ok": false, "code": job.code, "job_id": job.job_id}
	jobs[token] = job
	_log(job, "queued", "", reason)
	return {"ok": true, "code": "", "job_id": job.job_id}

## Drives the jobs; paused (storage maintenance) starts no attempt, but deadlines run.
func poll(paused := false) -> void:
	var now := _now()
	for key in running.keys():
		var entry: Dictionary = running[key]
		if not entry.stale and now - int(entry.started) >= int(entry.limit):
			entry.stale = true
			var job: Dictionary = jobs.get(entry.token, {})
			if not job.is_empty() and job.state == "running" and str(job.job_id) == str(entry.job_id):
				_after_failure(entry.token, job, "RESULT_UNKNOWN")
	for token in jobs.keys():
		var job: Dictionary = jobs[token]
		if job.state != "running" and now - int(job.created) >= job_deadline_ms:
			job.state = "failed"
			job.code = "CLEANUP_DEADLINE" if job.code == "" else job.code
			_fail(token, job, "deadline")
	if paused or not start_attempt.is_valid():
		return
	for token in jobs.keys():
		if running.size() >= max_running:
			return
		var job: Dictionary = jobs[token]
		if job.state in ["queued", "waiting"] and now >= int(job.next_at):
			job.attempts = int(job.attempts) + 1
			job.state = "running"
			var limit := mini(attempt_limit_ms, maxi(1, job_deadline_ms - (now - int(job.created))))
			running[str(job.job_id) + ":" + str(job.attempts)] = {"job_id": job.job_id, "token": token, "started": now, "limit": limit, "stale": false}
			_log(job, "attempt", "", "")
			start_attempt.call(job.job_id, token, int(job.attempts))

## Result of one attempt (also of one that already timed out).
func complete(job_id: String, attempt: int, result: Dictionary) -> void:
	var key := job_id + ":" + str(attempt)
	var entry: Dictionary = running.get(key, {})
	running.erase(key)
	if entry.is_empty():
		return
	var token: String = entry.token
	var job: Dictionary = jobs.get(token, {})
	if job.is_empty() or str(job.job_id) != job_id:
		return
	var code := "" if result.get("ok", false) else str(result.get("code", "RESULT_UNKNOWN"))
	if result.get("ok", false) or code == "AUTH_FAILED":
		# A late answer of a timed-out attempt still ends the job when it is final.
		job.code = code
		job.state = "done" if code == "" else "invalid"
		jobs.erase(token)
		_log(job, job.state, code, "")
		_finish(token, job, job.state)
		return
	if entry.stale:
		return  # this attempt was already counted as unknown
	if code in TRANSIENT:
		_after_failure(token, job, code)
	else:
		job.code = code
		job.state = "failed"
		_fail(token, job, "permanent")

## Sessions that are known to be gone already (restore, account deletion): the
## jobs end without an attempt and are not reported as failures.
func cancel_user(user_id: String, reason: String) -> void:
	for token in jobs.keys():
		if jobs[token].user_id == user_id:
			_cancel(token, reason)
	for token in failed.keys():
		if failed[token].user_id == user_id:
			failed.erase(token)

func cancel_all(reason: String) -> void:
	for token in jobs.keys():
		_cancel(token, reason)
	failed.clear()

func job_state(job_id: String) -> String:
	for token in jobs:
		if jobs[token].job_id == job_id:
			return jobs[token].state
	for token in failed:
		if failed[token].job_id == job_id:
			return "failed"
	return "ended"

func has_token(token: String) -> bool:
	return jobs.has(token) or failed.has(token)

func idle() -> bool:
	return jobs.is_empty() and running.is_empty()

## Public view (no token): counts and the failed jobs.
func status() -> Dictionary:
	var listed: Array = []
	for token in failed:
		var job: Dictionary = failed[token]
		listed.append({"job_id": job.job_id, "reason": job.reason, "attempts": job.attempts, "code": job.code})
	return {"pending": jobs.size(), "running": running.size(), "failed": failed.size(), "failed_jobs": listed}

func _after_failure(token: String, job: Dictionary, code: String) -> void:
	job.code = code
	var now := _now()
	if int(job.attempts) >= MAX_ATTEMPTS:
		job.state = "failed"
		_fail(token, job, "exhausted")
		return
	var next_at := now + int(backoff_ms[mini(int(job.attempts) - 1, backoff_ms.size() - 1)])
	if next_at - int(job.created) >= job_deadline_ms:
		job.state = "failed"
		_fail(token, job, "deadline")
		return
	job.state = "waiting"
	job.next_at = next_at
	_log(job, "retry", code, "")

func _fail(token: String, job: Dictionary, why: String) -> void:
	jobs.erase(token)
	_keep_failed(token, job)
	_log(job, "failed", job.code, why)
	_finish(token, job, "failed")

func _cancel(token: String, reason: String) -> void:
	var job: Dictionary = jobs[token]
	jobs.erase(token)
	outcomes[str(job.job_id)] = {"outcome": "cancelled", "code": ""}
	_log(job, "cancelled", "", reason)

func _keep_failed(token: String, job: Dictionary) -> void:
	failed[token] = job
	while failed.size() > MAX_FAILED:
		var oldest: String = failed.keys()[0]
		_log(failed[oldest], "dropped", failed[oldest].code, "failed list full")
		failed.erase(oldest)

func _finish(token: String, job: Dictionary, outcome: String) -> void:
	outcomes[str(job.job_id)] = {"outcome": outcome, "code": str(job.code)}
	while outcomes.size() > MAX_FAILED:
		outcomes.erase(outcomes.keys()[0])
	if on_finished.is_valid():
		on_finished.call(token, outcome)

func _log(job: Dictionary, event: String, code: String, detail: String) -> void:
	var line := "SESSION_CLEANUP job=%s event=%s attempt=%d code=%s ms=%d reason=%s%s" % [job.job_id, event, int(job.attempts), code if code != "" else "-", _now() - int(job.created), job.reason, (" detail=" + detail) if detail != "" else ""]
	print(line)
	events.append(line)
	if events.size() > 200:
		events.pop_front()

static func _valid_token(token: String) -> bool:
	if token.length() != 64:
		return false
	for character in token:
		if not character in "0123456789abcdef":
			return false
	return true
