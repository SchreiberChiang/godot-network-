extends SceneTree
## Rules of host/core/session_cleanup.gd with a test clock and scripted attempt
## results (no storage, no Operator, no process). Covers: first-try success, one
## and two capacity refusals then success (0.5 s / 2 s back-off), storage failure
## until the attempts run out, an answer lost after the commit (timed-out attempt,
## retry finds the token already invalid), a late answer of a timed-out attempt,
## repeated triggers, an old token cleaned after a new login, re-arming a failed
## job, queue and concurrency limits, the 35 s deadline, permanent errors, paused
## attempts during maintenance, cancellation, and that no token is ever logged.
const Cleanup = preload("res://host/core/session_cleanup.gd")
var passed := 0
var failed := 0
var now := 0
var started: Array = []     # [job_id, token, attempt]
var finished: Array = []    # [token, outcome]

func _initialize() -> void:
	_run()
	print("SESSION_CLEANUP_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func check(value: bool, text: String) -> void:
	if value:
		passed += 1
		print("PASS ", text)
	else:
		failed += 1
		print("FAIL ", text)

func fresh():
	started.clear()
	finished.clear()
	now = 1000
	var cleanup = Cleanup.new()
	cleanup.clock = func() -> int: return now
	cleanup.start_attempt = func(job_id: String, token: String, attempt: int) -> void: started.append([job_id, token, attempt])
	cleanup.on_finished = func(token: String, outcome: String) -> void: finished.append([token, outcome])
	return cleanup

func token(seed: String) -> String:
	return seed.sha256_text()

## Answers the last started attempt.
func answer(cleanup, result: Dictionary) -> void:
	var last: Array = started[-1]
	cleanup.complete(last[0], last[2], result)

func advance(cleanup, ms: int) -> void:
	now += ms
	cleanup.poll()

func no_token_logged(cleanup, tokens: Array) -> bool:
	var text := "\n".join(cleanup.events) + JSON.stringify(cleanup.status())
	for value in tokens:
		if text.contains(value):
			return false
	return true

func _run() -> void:
	var a := token("a")
	var b := token("b")

	var c = fresh()
	check(c.submit(a, "u1", "explicit").ok and c.status().pending == 1, "a known token becomes one clean-up job")
	c.poll()
	check(started.size() == 1 and started[0][1] == a and started[0][2] == 1, "the first attempt starts at once")
	answer(c, {"ok": true, "code": ""})
	check(finished == [[a, "done"]] and c.idle() and c.outcomes[started[0][0]].outcome == "done", "a confirmed logout ends the job (done) and releases the responsibility")

	c = fresh()
	c.submit(a, "u1", "disconnect")
	c.poll()
	answer(c, {"ok": false, "code": "RATE_LIMITED"})
	advance(c, 499)
	check(started.size() == 1, "after a capacity refusal nothing is sent before 0.5 s")
	advance(c, 1)
	check(started.size() == 2 and started[1][2] == 2, "the second attempt starts after 0.5 s")
	answer(c, {"ok": true, "code": ""})
	check(finished == [[a, "done"]], "one capacity refusal, then success")

	c = fresh()
	c.submit(a, "u1", "disconnect")
	c.poll()
	answer(c, {"ok": false, "code": "RATE_LIMITED"})
	advance(c, 500)
	answer(c, {"ok": false, "code": "STORAGE_MAINTENANCE"})
	advance(c, 1999)
	check(started.size() == 2, "after the second refusal nothing is sent before 2 s")
	advance(c, 1)
	check(started.size() == 3 and started[2][2] == 3, "the third (last) attempt starts after 2 s")
	answer(c, {"ok": true, "code": ""})
	check(finished == [[a, "done"]], "two refusals, then success on the third attempt")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll()
	answer(c, {"ok": false, "code": "STORAGE_UNAVAILABLE"})
	advance(c, 500)
	answer(c, {"ok": false, "code": "STORAGE_UNAVAILABLE"})
	advance(c, 2000)
	answer(c, {"ok": false, "code": "STORAGE_UNAVAILABLE"})
	advance(c, 10000)
	var status: Dictionary = c.status()
	check(started.size() == 3 and finished == [[a, "failed"]], "storage failure on all 3 attempts: no fourth attempt, the job fails")
	check(status.failed == 1 and status.failed_jobs[0].code == "STORAGE_UNAVAILABLE" and status.failed_jobs[0].attempts == 3 and c.has_token(a), "the failure stays listed (code, attempts) and keeps the token's responsibility")
	var failed_id: String = started[0][0]
	c.submit(a, "u1", "host_exit")
	c.poll()
	check(started.size() == 4 and started[3][0] != failed_id and started[3][2] == 1 and c.status().failed == 0 and c.outcomes[failed_id].outcome == "failed", "a later trigger gets a new job id and keeps the previous failure outcome")
	answer(c, {"ok": true, "code": ""})
	check(finished[-1] == [a, "done"] and not c.has_token(a), "the re-armed job ends confirmed")

	# The previous attempt can outlive the job deadline. Re-arming must neither
	# overwrite its physical running slot nor let its late reply finish a new job.
	c = fresh()
	var old_job: Dictionary = c.submit(a, "u1", "explicit")
	c.poll()
	advance(c, Cleanup.JOB_DEADLINE_MS)
	var new_job: Dictionary = c.submit(a, "u1", "host_exit")
	c.poll()
	check(old_job.job_id != new_job.job_id and c.status().running == 2, "re-arming while an expired attempt is still running keeps both physical slots")
	c.submit(b, "u2", "disconnect")
	c.poll()
	check(started.size() == 2, "a third attempt cannot start while the old and new attempts still occupy both slots")
	c.complete(old_job.job_id, 1, {"ok": true, "code": ""})
	check(c.job_state(new_job.job_id) == "running" and c.status().running == 1 and finished == [[a, "failed"]], "the old late success releases only its own slot without completing the re-armed job")
	c.poll()
	check(started.size() == 3 and c.status().running == 2, "the released physical slot admits the next token without dropping the current attempt")
	c.complete(new_job.job_id, 1, {"ok": true, "code": ""})
	answer(c, {"ok": true, "code": ""})
	check(c.idle() and finished == [[a, "failed"], [a, "done"], [b, "done"]], "each generation ends separately and all physical slots are released")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll()
	advance(c, 9999)
	check(c.job_state(started[0][0]) == "running", "an attempt is waited for up to 10 s")
	advance(c, 1)
	check(c.job_state(started[0][0]) == "waiting" and c.status().running == 1, "after 10 s the result counts as unknown; the old attempt keeps its slot")
	advance(c, 500)
	check(started.size() == 2, "the retry starts after 0.5 s")
	answer(c, {"ok": false, "code": "AUTH_FAILED"})
	check(finished == [[a, "invalid"]], "answer lost after the commit: the retry finds the old token already invalid (end point)")
	c.complete(started[0][0], 1, {"ok": true, "code": ""})
	check(finished.size() == 1 and c.status().running == 0, "the late answer of the first attempt frees its slot and changes nothing")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll()
	advance(c, 10000)
	c.complete(started[0][0], 1, {"ok": true, "code": ""})
	check(finished == [[a, "done"]] and started.size() == 1, "a late success of a timed-out attempt still ends the job before the retry")

	c = fresh()
	var first: Dictionary = c.submit(a, "u1", "explicit")
	var second: Dictionary = c.submit(a, "u1", "disconnect")
	c.poll()
	check(first.job_id == second.job_id and started.size() == 1 and c.status().pending == 1, "repeated triggers for one token merge into one job")

	c = fresh()
	c.submit(a, "u1", "disconnect")
	# The player logged in again with a new token (b) before the old one was cleaned.
	c.poll()
	answer(c, {"ok": false, "code": "AUTH_FAILED"})
	var calls: Array = started.map(func(item): return item[1])
	check(calls == [a] and not calls.has(b) and finished == [[a, "invalid"]], "an old token cleaned after a new login touches only the old token")

	c = fresh()
	c.max_queued = 64
	var accepted := 0
	for index in 64:
		if c.submit(token("q" + str(index)), "u", "load").ok:
			accepted += 1
	var refused: Dictionary = c.submit(token("q64"), "u", "load")
	check(accepted == 64 and not refused.ok and refused.code == "CLEANUP_QUEUE_FULL" and c.status().failed == 1, "at most 64 queued jobs; the 65th is refused and listed as failed")
	c.poll()
	check(started.size() == 2 and c.status().running == 2, "at most 2 attempts run at the same time")
	answer(c, {"ok": true, "code": ""})
	c.poll()
	check(started.size() == 3, "a finished attempt frees a slot for the next job")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll(true)
	check(started.is_empty(), "no attempt starts while storage maintenance runs")
	now += 34999
	c.poll(true)
	check(c.job_state(c.submit(b, "u2", "x").job_id) == "queued" and c.has_token(a), "a waiting job survives until its deadline")
	now += 1
	c.poll(true)
	check(finished[0] == [a, "failed"] and c.status().failed_jobs[0].code == "CLEANUP_DEADLINE", "35 s after the hand-over (queueing included) the job fails with CLEANUP_DEADLINE")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll()
	advance(c, 30000)
	advance(c, 500)
	check(started.size() == 2 and c.running.values().any(func(entry): return int(entry.limit) <= 4500), "a late attempt gets at most the time left before the deadline")

	c = fresh()
	c.submit(a, "u1", "explicit")
	c.poll()
	answer(c, {"ok": false, "code": "INVALID_ACCOUNT_REQUEST"})
	advance(c, 5000)
	check(started.size() == 1 and finished == [[a, "failed"]], "a permanent error is not retried")

	c = fresh()
	check(not c.submit("not-a-token", "u1", "x").ok and not c.submit(a.to_upper(), "u1", "x").ok, "a malformed token is refused")

	c = fresh()
	c.submit(a, "u1", "x")
	c.submit(b, "u2", "x")
	c.cancel_user("u1", "account_revoked")
	check(not c.has_token(a) and c.has_token(b) and c.outcomes.values().any(func(item): return item.outcome == "cancelled"), "cancelling one user's sessions leaves the others")
	c.cancel_all("restore")
	check(c.idle() and finished.is_empty(), "cancel_all (restore) ends every job without reporting a failure")

	check(no_token_logged(c, [a, b]), "no token appears in the log lines or the status")
