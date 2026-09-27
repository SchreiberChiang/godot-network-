extends RefCounted
## Test-stage deletion of one player account across accounts.sqlite, assets.sqlite and
## the Operator's own files (docs/17 section 7). Nothing spans all of them, so a job in
## accounts.sqlite drives fixed steps, each safe to repeat:
##   1. account.delete_begin (accounts, admin token): job assets_pending, sign-in blocked,
##      sessions revoked.
##   2. asset.purge_user (assets): every space's state and receipts deleted, user_id and
##      username replaced in results and receipt texts, tombstone written.
##   3. local.deletion_finish (accounts): account row deleted, audit de-identified; job
##      becomes operator_pending (it still holds user_id and username).
##   4. Operator close-out (close() below): its audit files de-identified and verified,
##      the backups that may hold the account written durably to the deletion journal.
##   5. local.deletion_close (accounts): job done, last user_id/username/reason dropped.
## An interruption anywhere leaves the job open; complete()/close() finish it from a
## repeated admin request or from the Operator's start-up. Success is reported only
## after step 5.
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const JOURNAL := "account-deletions.jsonl"

## Same pseudonym as account_store.ps1 and sqlite_store.ps1 derive.
static func subject_for(user_id: String) -> String:
	return "deleted_" + user_id.sha256_text().left(32)

## Steps 2 and 3 for a job still in assets_pending. Worker thread.
static func complete(accounts, repository, job: Dictionary) -> Dictionary:
	var purge := {"op": "asset.purge_user", "user_id": str(job.user_id)}
	if str(job.get("username", "")) != "":
		purge.username = str(job.username)
	var purged: Dictionary = repository.execute(purge)
	if not purged.get("ok", false):
		return incomplete(job, "assets", str(purged.get("code", "STORAGE_UNAVAILABLE")))
	var finished: Dictionary = accounts.finish_deletion(str(job.job_id))
	if not finished.get("ok", false):
		return incomplete(job, "account", str(finished.get("code", "STORAGE_UNAVAILABLE")))
	var assets := {}
	for key in ["spaces", "asset_states", "asset_receipts", "actor_receipts", "results_deidentified", "receipt_texts_scrubbed"]:
		assets[key] = purged.get(key)
	var next := job.duplicate(true)
	next.state = "operator_pending"
	return {"ok": true, "code": "", "job": next, "assets": assets, "account": finished.get("deletion", {})}

## Steps 2-3 for every open job an earlier run left. Jobs already operator_pending pass
## through unchanged. Returns jobs ready for close() and jobs that failed. Worker thread.
static func resume(accounts, repository) -> Dictionary:
	var pending: Dictionary = accounts.pending_deletions()
	if not pending.get("ok", false):
		return Wire.failure(str(pending.get("code", "STORAGE_UNAVAILABLE")))
	var report := {"ok": true, "code": "", "ready": [], "failed": []}
	for job in pending.get("deletions", []):
		if job.state == "operator_pending":
			report.ready.append({"ok": true, "job": job, "assets": {}, "account": {}})
			continue
		var result := complete(accounts, repository, job)
		if result.ok:
			report.ready.append(result)
		else:
			report.failed.append(result)
	return report

## Needles every de-identification replaces, case-insensitively, with the pseudonym.
static func needles(job: Dictionary) -> Array:
	var found: Array = []
	for value in [str(job.get("user_id", "")), str(job.get("username", ""))]:
		if value.length() >= 3:
			found.append(value)
	return found

static func scrub(text: String, words: Array, subject: String) -> String:
	for word in words:
		text = text.replacen(word, subject)
	return text

static func mentions(text: String, words: Array) -> bool:
	var lower := text.to_lower()
	for word in words:
		if lower.contains(str(word).to_lower()):
			return true
	return false

## De-identifies audit rows in memory: rows about the account get the pseudonym and a
## redacted reason; any other row loses the user_id/username inside its texts.
static func scrub_rows(rows: Array, job: Dictionary) -> int:
	var words := needles(job)
	var changed := 0
	for row in rows:
		if row is Dictionary and _scrub_row(row, str(job.user_id), words, str(job.subject)):
			changed += 1
	return changed

## Rewrites each existing JSON-lines audit file that mentions the account, then reads
## it back. Fails, without partial success, if any write or the verification fails.
static func scrub_files(paths: Array, job: Dictionary) -> Dictionary:
	var words := needles(job)
	var changed := 0
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		if FileAccess.get_open_error() != OK:
			return Wire.failure("AUDIT_READ_FAILED")
		if not mentions(text, words):
			continue
		var lines: Array = []
		for line in text.split("\n", false):
			if mentions(line, words):
				var row := Wire.decode(line.to_utf8_buffer())
				if row.is_empty():
					line = scrub(line, words, str(job.subject))
				else:
					_scrub_row(row, str(job.user_id), words, str(job.subject))
					line = JSON.stringify(row)
				changed += 1
			lines.append(line)
		if not _replace_file(path, "\n".join(lines) + "\n"):
			return Wire.failure("AUDIT_WRITE_FAILED")
		var verified := FileAccess.get_file_as_string(path)
		if FileAccess.get_open_error() != OK or mentions(verified, words):
			return Wire.failure("AUDIT_WRITE_FAILED")
	return {"ok": true, "code": "", "rows": changed}

## Appends one journal entry and reads it back; the journal lives outside the
## databases, so a later restore never erases which backups predate a deletion.
static func append_journal(root: String, entry: Dictionary) -> bool:
	var path := root.path_join(JOURNAL)
	var row := entry.duplicate(true)
	row.time = int(Time.get_unix_time_from_system())
	var line := JSON.stringify(row)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(line)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and FileAccess.get_file_as_string(path).contains(line)

## backup_id -> pseudonyms of deleted accounts that backup may still contain.
static func journal_marks(root: String) -> Dictionary:
	var marks := {}
	var path := root.path_join(JOURNAL)
	if not FileAccess.file_exists(path):
		return marks
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var row := Wire.decode(line.to_utf8_buffer())
		for backup_id in row.get("backups", []):
			var subjects: Array = marks.get(str(backup_id), [])
			if not subjects.has(row.get("subject", "")):
				subjects.append(row.get("subject", ""))
			marks[str(backup_id)] = subjects
	return marks

static func backups_since(rows: Array, created_at: int) -> Array:
	var found: Array = []
	for row in rows:
		if row is Dictionary and int(row.get("created_at", 0)) >= created_at:
			found.append({"backup_id": str(row.get("backup_id", "")), "created_at": int(row.get("created_at", 0)), "kind": str(row.get("kind", ""))})
	return found

static func incomplete(job: Dictionary, stage: String, cause: String) -> Dictionary:
	# The job stays open: the account stays blocked (or gone) and a retry continues.
	return {"ok": false, "code": "ACCOUNT_DELETION_INCOMPLETE", "payload": {"job_id": job.get("job_id", ""), "subject": job.get("subject", ""), "user_id": job.get("user_id", ""), "stage": stage, "cause": cause}}

static func _scrub_row(row: Dictionary, user_id: String, words: Array, subject: String) -> bool:
	var changed := false
	for key in ["user_id", "actor_id"]:
		if str(row.get(key, "")) == user_id:
			row[key] = subject
			row.reason = "redacted:account_deleted"
			changed = true
	for key in row.keys():
		if row[key] is String and mentions(row[key], words):
			row[key] = scrub(row[key], words, subject)
			changed = true
	return changed

static func _replace_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		return false
	return true
