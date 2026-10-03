extends RefCounted
## Client-only local data. Do not use the server's Paths helper here.
## A crashed .active.jsonl or a stale budget lock is deliberately never reclaimed:
## uncertain ownership must stop diagnostics, not delete another process's data.
const SESSION_LIMIT := 2 * 1024 * 1024
const TOTAL_LIMIT := 16 * 1024 * 1024
const QUEUE_LIMIT := 128
const QUEUE_BYTES := 128 * 1024
const WRITE_INTERVAL_MS := 1000
const StrictJSON = preload("res://sdk/roomkit/shared/strict_json.gd")
const PlayerReport = preload("res://sdk/roomkit/shared/player_report.gd")

var _root := ""
var _reports := ""
var _legacy := ""
var _session := Crypto.new().generate_random_bytes(16).hex_encode()
var _recent: Array[Dictionary] = []
var _memory_marks := 0
var _build := "unknown"
var _active := ""
var _mutex := Mutex.new()
var _thread := Thread.new()
var _queue: Array[String] = []
var _queue_bytes := 0
var _dropped := 0
var _enabled := false
var _error := ""
var _closing := false
var _configured := false
var _last_sample := -1000
var _last_mark := -1000
var _pending_seen: Dictionary = {}
var _settings_queued: Dictionary = {}
var _settings_error := ""

## Source overrides are explicit project paths, never cwd, TMP or user://.
static func default_root(source_override: String = "res://data/client-local/source") -> String:
	if not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join("client-data").simplify_path()
	return _source_path(source_override)

static func _source_path(path: String) -> String:
	if path.begins_with("user://") or path.is_empty():
		return ""
	if not path.begins_with("res://") and not path.is_absolute_path():
		return ""
	var base := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.begins_with(base + "/"):
		return ""
	return absolute

## Reject links in every existing ancestor. The caller never gets a fallback path.
static func _plain_path(path: String) -> bool:
	if not path.is_absolute_path():
		return false
	var current := path.simplify_path()
	while current != current.get_base_dir():
		var parent := current.get_base_dir()
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()):
			return false
		current = parent
	return true

func configure(data_root: String, build: String, legacy_source: String = "") -> bool:
	if _configured:
		return false
	_configured = true
	_build = build if _token(build, 96) else "unknown"
	_root = _source_path(data_root) if OS.has_feature("editor") else data_root.simplify_path()
	if _root.is_empty() or (not OS.has_feature("editor") and _root != default_root()) or not _plain_path(_root):
		_fail("UNSAFE_PATH")
		return false
	_reports = _root.path_join("reports")
	_legacy = ProjectSettings.globalize_path("res://data/client-operations") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("data/client-operations")
	if not legacy_source.is_empty():
		if not OS.has_feature("editor") or _source_path(legacy_source).is_empty():
			_fail("UNSAFE_PATH")
			return false
		_legacy = _source_path(legacy_source)
	_build = build if _token(build, 96) else "unknown"
	_session = Crypto.new().generate_random_bytes(16).hex_encode()
	if _session.length() != 32:
		_fail("WRITE_FAILED")
		return false
	if not _plain_path(_reports) or DirAccess.make_dir_recursive_absolute(_reports) != OK:
		_fail("WRITE_FAILED")
	else:
		_enabled = true
	_active = _reports.path_join("session-" + _session + ".active.jsonl")
	if _thread.start(_worker) != OK:
		_fail("WRITE_FAILED")
		return false
	return true

func audio_settings_path() -> String:
	if _root.is_empty() or not _plain_path(_root.path_join("settings")):
		return ""
	return _root.path_join("settings/audio.json")

func load_settings() -> Dictionary:
	var defaults := {"volume": 0.7, "muted": false}
	var path := audio_settings_path()
	if path.is_empty() or not _plain_path(path):
		_settings_error = "UNSAFE_PATH"
		return defaults
	if not FileAccess.file_exists(path):
		return defaults
	if _file_size(path) > 4096:
		_settings_error = "SETTINGS_INVALID"
		return defaults
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_settings_error = "WRITE_FAILED"
		return defaults
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not _valid_settings(data):
		_settings_error = "SETTINGS_INVALID"
		return defaults
	return {"volume": clampf(float(data.volume), 0.0, 1.0), "muted": data.muted}

## Coalesce slider changes rather than writing on the UI thread or every frame.
func queue_settings(settings: Dictionary) -> bool:
	if not _valid_settings(settings):
		return false
	_mutex.lock()
	var ok := _thread.is_started() and not _closing
	if ok:
		_settings_queued = {"format": 1, "volume": snappedf(clampf(float(settings.volume), 0.0, 1.0), 0.01), "muted": settings.muted}
	_mutex.unlock()
	return ok

static func _valid_settings(settings: Dictionary) -> bool:
	return (settings.get("volume") is int or settings.get("volume") is float) and is_finite(float(settings.volume)) and settings.get("muted") is bool

func _write_settings(settings: Dictionary) -> void:
	var path := audio_settings_path()
	var ok := not path.is_empty() and _plain_path(path) and _plain_path(path + ".lock")
	if ok:
		ok = DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK
	var locked := false
	if ok:
		locked = DirAccess.make_dir_absolute(path + ".lock") == OK
		ok = locked
	var temporary := path + "." + _session + ".tmp"
	var backup := path + "." + _session + ".previous"
	if ok:
		ok = _plain_path(temporary) and _plain_path(backup) and not FileAccess.file_exists(backup)
	if ok:
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			ok = false
		else:
			file.store_string(JSON.stringify(settings))
			file.flush()
			ok = file.get_error() == OK
			file.close()
			var had_previous := FileAccess.file_exists(path)
			if ok and had_previous:
				ok = DirAccess.rename_absolute(path, backup) == OK
			if ok:
				ok = DirAccess.rename_absolute(temporary, path) == OK
			if not ok and had_previous and FileAccess.file_exists(backup) and not FileAccess.file_exists(path):
				# Keep backup if restoration itself fails; never delete recovery data.
				DirAccess.rename_absolute(backup, path)
			if ok and FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
			if FileAccess.file_exists(temporary):
				DirAccess.remove_absolute(temporary)
	if locked:
		DirAccess.remove_absolute(path + ".lock")
	_mutex.lock()
	_settings_error = "" if ok else "WRITE_FAILED"
	_mutex.unlock()

func report_directory() -> String:
	return _reports

func status() -> Dictionary:
	_mutex.lock()
	var result := {"enabled": _enabled, "error": _error, "queued": _queue.size(), "dropped": _dropped, "session_id": _session, "settings_error": _settings_error, "memory_marks": _memory_marks}
	_mutex.unlock()
	return result

## Exactly one bounded record per second, even if a caller mistakenly polls per frame.
func sample(metrics: Dictionary) -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_sample < WRITE_INTERVAL_MS:
		return false
	_last_sample = now
	return _enqueue(_record(metrics, "sample"))

## No free-text label: arbitrary user text or close_reason cannot become a log.
func mark() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_mark < WRITE_INTERVAL_MS:
		return false
	_last_mark = now
	return _enqueue(_record({}, "mark"))

func _record(metrics: Dictionary, kind: String) -> Dictionary:
	var record := {"utc": Time.get_datetime_string_from_system(true, false) + "Z", "monotonic_ms": Time.get_ticks_msec(), "session_id": _session, "build": _build, "kind": kind}
	var input := metrics.duplicate()
	input.phase = metrics.get("phase", "IDLE")
	input.error = metrics.get("error", "NONE")
	record.merge(PlayerReport.clean_record(input))
	return record

## Submission never opens a report file: this bounded sanitized ring survives
## journal write failure. Its lifetime is this client process only.
func diagnostic_report(report_id: String = "", now_ms: int = -1) -> Dictionary:
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	_trim_recent(now_ms)
	var report := {"format": 1, "report_id": Crypto.new().generate_random_bytes(16).hex_encode() if report_id == "" else report_id, "platform": PlayerReport.platform(), "records": _recent.duplicate(true)}
	while not report.records.is_empty() and JSON.stringify(report).to_utf8_buffer().size() > PlayerReport.MAX_BYTES:
		report.records.pop_front()
	return report if PlayerReport.validate(report) else {}

func _trim_recent(now_ms: int) -> void:
	while not _recent.is_empty() and (int(_recent[0].monotonic_ms) < now_ms - PlayerReport.WINDOW_MS or _recent.size() > PlayerReport.MAX_RECORDS):
		_recent.pop_front()

func _enqueue(record: Dictionary) -> bool:
	if not _closing:
		_recent.append(record.duplicate(true))
		_trim_recent(Time.get_ticks_msec())
		if record.kind == "mark":
			_memory_marks += 1
	var line := JSON.stringify(record) + "\n"
	var bytes := line.to_utf8_buffer().size()
	_mutex.lock()
	if not _enabled or _closing:
		_mutex.unlock()
		return false
	if _queue.size() >= QUEUE_LIMIT or _queue_bytes + bytes > QUEUE_BYTES:
		_dropped += 1
		_mutex.unlock()
		return false
	_queue.append(line)
	_queue_bytes += bytes
	_mutex.unlock()
	return true

func _fail(code: String) -> void:
	_mutex.lock()
	if _error.is_empty():
		_error = code
	_enabled = false
	_queue.clear()
	_queue_bytes = 0
	_mutex.unlock()

## Only a short-lived cross-process directory lock guards budget accounting and
## retention. Lock contention/crash never permits speculative stale-lock removal.
func _lock_budget() -> bool:
	var path := _reports.path_join(".budget-lock")
	if not _plain_path(path):
		return false
	for attempt in 50:
		if DirAccess.make_dir_absolute(path) == OK:
			return true
		OS.delay_msec(10)
	return false

func _unlock_budget() -> void:
	DirAccess.remove_absolute(_reports.path_join(".budget-lock"))

func _worker() -> void:
	var next_write := Time.get_ticks_msec() + WRITE_INTERVAL_MS
	while true:
		_mutex.lock()
		var closing := _closing
		_mutex.unlock()
		if not closing and Time.get_ticks_msec() < next_write:
			OS.delay_msec(20)
			continue
		_mutex.lock()
		var batch := "".join(_queue)
		var settings := _settings_queued.duplicate()
		var enabled := _enabled
		_queue.clear()
		_queue_bytes = 0
		_settings_queued.clear()
		_mutex.unlock()
		if enabled and not batch.is_empty():
			_write_batch(batch)
		if not settings.is_empty():
			_write_settings(settings)
		next_write = Time.get_ticks_msec() + WRITE_INTERVAL_MS
		if closing:
			break
	_finish_session()

func _write_batch(batch: String) -> bool:
	if not _plain_path(_reports) or not _plain_path(_active):
		_fail("UNSAFE_PATH")
		return false
	if not _lock_budget():
		_fail("LOCK_BUSY")
		return false
	var ok := _prune_ended(2)
	var total := _log_bytes()
	var current := _file_size(_active)
	var size := batch.to_utf8_buffer().size()
	if not ok or total < 0:
		_unlock_budget()
		_fail("UNSAFE_PATH")
		return false
	if current + size > SESSION_LIMIT or total + size > TOTAL_LIMIT:
		_unlock_budget()
		_fail("SESSION_FULL" if current + size > SESSION_LIMIT else "BUDGET_FULL")
		return false
	var file := FileAccess.open(_active, FileAccess.READ_WRITE if FileAccess.file_exists(_active) else FileAccess.WRITE)
	if file == null:
		_unlock_budget()
		_fail("WRITE_FAILED")
		return false
	file.seek_end()
	file.store_string(batch)
	file.flush() # Worker batch only, at most 1 Hz; never a render-frame flush.
	ok = file.get_error() == OK
	file.close()
	_unlock_budget()
	if not ok:
		_fail("WRITE_FAILED")
	return ok

func _finish_session() -> void:
	if not FileAccess.file_exists(_active):
		return
	if not _plain_path(_active) or not _lock_budget():
		_fail("LOCK_BUSY")
		return
	# Budget lock serializes completion. Increment beyond existing stamps even if
	# wall time moves backwards or two sessions finish in the same microsecond.
	var finished_at := int(Time.get_unix_time_from_system() * 1000000.0)
	var directory := DirAccess.open(_reports)
	if directory != null:
		directory.include_hidden = true
		for name in directory.get_files():
			if _ended_name(name):
				finished_at = maxi(finished_at, int(name.split("-")[1]) + 1)
	var ended := _reports.path_join("ended-%020d-%s.jsonl" % [finished_at, _session])
	if DirAccess.rename_absolute(_active, ended) != OK or not _prune_ended(2):
		_fail("WRITE_FAILED")
	_unlock_budget()

## Never removes *.active.jsonl, unknown files, links, directories or external data.
func _prune_ended(keep: int) -> bool:
	var directory := DirAccess.open(_reports)
	if directory != null:
		directory.include_hidden = true
	if directory == null:
		return false
	var ended: Array[String] = []
	for name in directory.get_files():
		if name.begins_with("ended-") and name.ends_with(".jsonl"):
			if directory.is_link(name) or not _ended_name(name):
				return false
			ended.append(name)
	ended.sort()
	while ended.size() > keep:
		if DirAccess.remove_absolute(_reports.path_join(ended.pop_front())) != OK:
			return false
	return true

static func _ended_name(name: String) -> bool:
	var parts := name.trim_suffix(".jsonl").split("-")
	return parts.size() == 3 and parts[0] == "ended" and parts[1].length() == 20 and parts[1].is_valid_int() and parts[2].length() == 32 and parts[2].is_valid_hex_number(false)

func _log_bytes() -> int:
	var directory := DirAccess.open(_reports)
	if directory != null:
		directory.include_hidden = true
	if directory == null:
		return -1
	var total := 0
	for name in directory.get_files():
		if directory.is_link(name):
			return -1
		# Every file counts, even an unknown one. Unknown directories stop logging.
		total += _file_size(_reports.path_join(name))
	for name in directory.get_directories():
		if name != ".budget-lock":
			return -1
	return total

static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TOTAL_LIMIT
	var size := file.get_length()
	file.close()
	return size

func close() -> void:
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()
	_mutex.lock()
	_enabled = false
	_mutex.unlock()

## Settings are separate from reports. Sound uses this path, never user://.
## Pending data is server/account/game scoped and never appears in reports.
func _pending_path(server: String, account: String, game: String) -> String:
	if _root.is_empty() or server.is_empty() or account.is_empty() or game.is_empty():
		return ""
	var binding := JSON.stringify([server, account, game]).sha256_text()
	return _root.path_join("pending/v1").path_join(binding + ".json")

func load_pending(server: String, account: String, game: String) -> Dictionary:
	var path := _pending_path(server, account, game)
	if path.is_empty() or not _plain_path(path):
		return {"operation": {}, "warning": "UNSAFE_PATH"}
	var warning := _legacy_warning(server, account, game)
	if not warning.is_empty():
		return {"operation": {}, "warning": warning}
	if FileAccess.file_exists(path):
		var value := _read_operation(path)
		if value.is_empty():
			return {"operation": {}, "warning": "PENDING_INVALID"}
		_pending_seen[path] = str(value.operation_id)
		return {"operation": value, "warning": ""}
	_pending_seen[path] = ""
	return {"operation": {}, "warning": ""}

## Upgrades quarantine only the recognized same-client legacy receipt directory.
## Compare duplicate source bytes before choosing either copy; never guess which
## of two conflicting receipts belongs to this server or discard either one.
func _legacy_source(account: String, game: String) -> Dictionary:
	var name := (account + ":" + game).sha256_text() + ".json"
	var original := _legacy.path_join(name)
	var quarantined := _root.path_join("legacy-client-operations/client-operations").path_join(name)
	for candidate in [original, quarantined]:
		if not _plain_path(candidate):
			return {"path": "", "warning": "UNSAFE_PATH"}
		if DirAccess.dir_exists_absolute(candidate):
			return {"path": "", "warning": "LEGACY_CHANGED"}
	var original_exists := FileAccess.file_exists(original)
	var quarantined_exists := FileAccess.file_exists(quarantined)
	if original_exists and quarantined_exists:
		# Empty SHA256 indicates a read failure and is never proof of equality.
		var original_digest := FileAccess.get_sha256(original)
		var quarantine_digest := FileAccess.get_sha256(quarantined)
		if original_digest.is_empty() or quarantine_digest.is_empty() or original_digest != quarantine_digest:
			return {"path": "", "warning": "LEGACY_CONFLICT"}
	return {"path": quarantined if quarantined_exists else original, "warning": ""}

func _migration_path(account: String, game: String) -> String:
	return _root.path_join("pending/migrations").path_join((account + ":" + game).sha256_text() + ".json")

static func _read_marker(path: String) -> Dictionary:
	if not _plain_path(path) or not FileAccess.file_exists(path) or _file_size(path) > 4096:
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary or value.get("state") not in ["PREPARED", "COMMITTED"] or not value.get("binding") is String or str(value.binding).length() != 64 or not str(value.binding).is_valid_hex_number(false) or not value.get("operation_id") is String or str(value.operation_id).length() != 32 or not value.get("source_sha256") is String or str(value.source_sha256).length() != 64:
		return {}
	var done := path + ".committed"
	if not _plain_path(done):
		return {}
	if FileAccess.file_exists(done):
		var completion := FileAccess.open(done, FileAccess.READ)
		if completion == null or completion.get_length() > 256:
			return {}
		var digest := completion.get_as_text()
		completion.close()
		if digest != JSON.stringify([value.binding, value.operation_id, value.source_sha256]).sha256_text():
			return {}
		value.state = "COMMITTED"
	return value

func _legacy_warning(server: String, account: String, game: String) -> String:
	var selected := _legacy_source(account, game)
	if not str(selected.warning).is_empty():
		return str(selected.warning)
	var source: String = selected.path
	var marker := _migration_path(account, game)
	if not _plain_path(source) or not _plain_path(marker) or not _plain_path(marker + ".lock"):
		return "UNSAFE_PATH"
	if DirAccess.dir_exists_absolute(marker + ".lock"):
		return "LEGACY_MIGRATION_INCOMPLETE"
	if not FileAccess.file_exists(marker) and not DirAccess.dir_exists_absolute(marker):
		return "LEGACY_UNBOUND" if FileAccess.file_exists(source) else ""
	var assignment := _read_marker(marker)
	if assignment.is_empty():
		return "LEGACY_CHANGED"
	# A changed legacy receipt is not covered by an earlier server assignment.
	if FileAccess.file_exists(source) and FileAccess.get_sha256(source) != str(assignment.source_sha256):
		return "LEGACY_CHANGED"
	var binding := JSON.stringify([server, account, game]).sha256_text()
	if str(assignment.binding) == binding and assignment.state == "PREPARED":
		return "LEGACY_MIGRATION_INCOMPLETE"
	return ""

static func _write_marker(path: String, assignment: Dictionary, session_id: String) -> bool:
	var destination := path + ".committed" if assignment.state == "COMMITTED" else path
	var temporary := destination + "." + session_id + ".tmp"
	if not _plain_path(destination) or not _plain_path(temporary) or FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var content := JSON.stringify([assignment.binding, assignment.operation_id, assignment.source_sha256]).sha256_text() if assignment.state == "COMMITTED" else JSON.stringify(assignment)
	file.store_string(content)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	if ok:
		ok = DirAccess.rename_absolute(temporary, destination) == OK
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return ok

## Explicit human-confirmed server association only; never called on login.
## Write a durable PREPARED server assignment BEFORE exposing any pending copy.
## A failed second write remains blocked and can only resume to the same server.
func bind_legacy(server: String, account: String, game: String) -> bool:
	var selected := _legacy_source(account, game)
	if not str(selected.warning).is_empty():
		return false
	var source: String = selected.path
	var marker := _migration_path(account, game)
	if _pending_path(server, account, game).is_empty() or not _plain_path(source) or not _plain_path(marker) or not _plain_path(marker + ".lock"):
		return false
	var operation := _read_operation(source)
	if operation.is_empty() or DirAccess.make_dir_recursive_absolute(marker.get_base_dir()) != OK or DirAccess.make_dir_absolute(marker + ".lock") != OK:
		return false
	var binding := JSON.stringify([server, account, game]).sha256_text()
	var digest := FileAccess.get_sha256(source)
	var assignment := _read_marker(marker)
	var ok := true
	if FileAccess.file_exists(marker) or DirAccess.dir_exists_absolute(marker):
		ok = not assignment.is_empty() and str(assignment.binding) == binding and str(assignment.operation_id) == str(operation.operation_id) and str(assignment.source_sha256) == digest and assignment.state == "PREPARED"
	else:
		assignment = {"binding": binding, "operation_id": operation.operation_id, "source_sha256": digest, "state": "PREPARED"}
		ok = _write_marker(marker, assignment, _session)
	if ok:
		ok = _save_pending(server, account, game, operation, true)
	if ok:
		assignment.state = "COMMITTED"
		ok = _write_marker(marker, assignment, _session)
	DirAccess.remove_absolute(marker + ".lock")
	return ok

func save_pending(server: String, account: String, game: String, operation: Dictionary) -> bool:
	return _save_pending(server, account, game, operation, false)

func _save_pending(server: String, account: String, game: String, operation: Dictionary, allow_legacy: bool) -> bool:
	if not allow_legacy and not _legacy_warning(server, account, game).is_empty():
		return false
	var path := _pending_path(server, account, game)
	if path.is_empty() or not _plain_path(path) or not _plain_path(path + ".lock") or (not operation.is_empty() and not _valid_operation(operation)):
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK or DirAccess.make_dir_absolute(path + ".lock") != OK:
		return false
	var existing := _read_operation(path) if FileAccess.file_exists(path) else {}
	var ok := true
	if FileAccess.file_exists(path) and existing.is_empty():
		ok = false
	elif operation.is_empty():
		if not existing.is_empty():
			ok = str(existing.operation_id) == str(_pending_seen.get(path, "")) and DirAccess.remove_absolute(path) == OK
	else:
		if not existing.is_empty():
			# Do not replace an existing receipt: Windows rename may remove its
			# destination before a failed move. Same-id/different-body is rejected.
			ok = existing == _clean_operation(operation)
			if ok:
				_pending_seen[path] = str(existing.operation_id)
		else:
			var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
			var file := FileAccess.open(temporary, FileAccess.WRITE)
			if file == null:
				ok = false
			else:
				file.store_string(JSON.stringify(_clean_operation(operation)))
				file.flush()
				ok = file.get_error() == OK
				file.close()
				if ok:
					ok = DirAccess.rename_absolute(temporary, path) == OK
				if FileAccess.file_exists(temporary):
					DirAccess.remove_absolute(temporary)
			if ok:
				_pending_seen[path] = str(operation.operation_id)
	DirAccess.remove_absolute(path + ".lock")
	return ok

static func _read_operation(path: String) -> Dictionary:
	if _file_size(path) > 8192:
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes or not StrictJSON.valid(text, 2):
		return {}
	# A JSON Dictionary alone has already lost duplicate keys. Read this flat
	# four-string receipt before that information can be discarded. Shared strict
	# grammar checks quoting, separators and trailing bytes; values stay unchanged.
	var index := StrictJSON._space(text, 0)
	if index >= text.length() or text[index] != "{":
		return {}
	index = StrictJSON._space(text, index + 1)
	var value := {}
	while index < text.length() and text[index] == "\"":
		var end := StrictJSON._string(text, index)
		var key: String = JSON.parse_string(text.substr(index, end - index))
		if key not in ["kind", "operation_id", "item_id", "slot"] or value.has(key):
			return {}
		index = StrictJSON._space(text, StrictJSON._space(text, end) + 1)
		if text[index] != "\"":
			return {}
		end = StrictJSON._string(text, index)
		value[key] = JSON.parse_string(text.substr(index, end - index))
		index = StrictJSON._space(text, end)
		if text[index] == "}":
			return value if _valid_operation(value) else {}
		index = StrictJSON._space(text, index + 1)
	return {}

static func _valid_operation(value: Dictionary) -> bool:
	return value.size() == 4 and value.get("kind", "") in ["purchase", "select"] and value.get("operation_id") is String and str(value.operation_id).length() == 32 and value.get("item_id") is String and str(value.item_id).length() <= 128 and value.get("slot") is String and str(value.slot).length() <= 128

static func _clean_operation(value: Dictionary) -> Dictionary:
	return {"kind": value.kind, "operation_id": value.operation_id, "item_id": value.item_id, "slot": value.slot}

static func _token(value: String, maximum: int) -> bool:
	if value.is_empty() or value.length() > maximum:
		return false
	for index in value.length():
		var ch := value.unicode_at(index)
		if not ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch in [45, 46, 95]):
			return false
	return true
