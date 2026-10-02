extends SceneTree
## Real SQLite with prefilled grants and a trusted test clock; no 256 rooms.
const Service = preload("res://host/core/result_service.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
const Manager = preload("res://host/core/room_manager.gd")
const Fake = preload("res://tests/fakes/fake_launcher.gd")
const Guard = preload("res://host/core/recovery_guard.gd")
const Ports = preload("res://host/core/port_allocator.gd")
const Remote = preload("res://host/core/remote_results.gd")
var passed := 0
var failed := 0
var directory := ""
var service = Service.new()
var moment := 1700000000
const WINDOW := 604800

class Closing extends RefCounted:
	var approved := false
	var seen: Array = []
	func busy() -> bool: return not approved
	func confirm_exit(row: Dictionary) -> bool:
		seen.append(row.duplicate(true))
		return approved

class DeadBus extends RefCounted:
	func ready() -> bool: return false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolation="):
			directory = arg.trim_prefix("--isolation=").path_join("grant-db")
	if directory.is_empty():
		quit(64)
		return
	service.clock = func(): return moment
	check(service.initialize(directory, {"grant_fixture": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "isolated real SQLite initialized")
	service.reward_calculator = func(_record): return [{"user_id": "fixture_user", "space_id": "fixture", "credits": 7, "experience": 0}]
	var old := _row()
	var active := _row()
	var created: Dictionary = service.prepare_launch(old)
	check(created.ok, "grant persists using stdin")
	check(service.prepare_launch(active).ok, "second grant remains active")
	var accepted := submission(old, created.config.secret, "accepted")
	check(service.accept(accepted).ok and credits() == 7, "signed result and reward commit")
	check(service.end_launch(old.launch_id).ok, "first verified exit records server time")
	moment += 10
	check(service.end_launch(old.launch_id).ok, "repeat close succeeds")
	var inspect := fixture("inspect")
	var ended_row: Array = inspect.grants.filter(func(row): return row.launch_id == old.launch_id)
	check(ended_row.size() == 1 and int(ended_row[0].ended_at) == 1700000000, "close retry never extends first exit time")
	moment = 1700000000 + WINDOW - 1
	var waiting := submission(old, created.config.secret, "late")
	var queued: Dictionary = service.validate_submission(waiting)
	check(queued.ok, "signed submission passes before boundary")
	moment += 1
	check(service.commit(queued.request).code == "RESULT_EXPIRED" and credits() == 7, "transaction rechecks deadline after validation; no late reward")
	check(service.accept(accepted).code == "DUPLICATE" and credits() == 7, "already accepted retry is idempotent at boundary")
	check(fixture("fill").count == 256, "capacity seeded without opening 256 rooms")
	var replacement: Dictionary = service.prepare_launch(_row())
	check(replacement.ok and fixture("inspect").count == 256, "grant transaction reclaims eligible authorization before capacity check")
	inspect = fixture("inspect")
	check(inspect.grants.filter(func(row): return row.launch_id == old.launch_id).is_empty(), "expired signing key removed from launches")
	check(inspect.expired.size() == 1 and not inspect.expired_columns.any(func(row): return row.name == "secret"), "lightweight expiration has no signing key")
	check(service.prepare_launch(_row()).code == "STORAGE_CAPACITY_EXCEEDED", "all other active or unknown grants retain capacity")
	check(service.accept(waiting).code == "RESULT_EXPIRED" and credits() == 7, "expired unseen result cannot restore rewards")
	check(service.accept(accepted).code == "DUPLICATE" and credits() == 7, "accepted exact hash and signature retry after key removal")
	var changed := accepted.duplicate(true)
	changed.record.payload.round = 9
	changed.signature = Format.sign(changed.record, created.config.secret)
	check(not service.accept(changed).ok and credits() == 7, "changed signed record cannot reuse old accepted receipt")
	changed = accepted.duplicate(true)
	changed.signature = "0".repeat(64)
	check(not service.accept(changed).ok, "forged signature cannot replay accepted receipt")
	var reopened = Service.new()
	check(reopened.initialize(directory, {"grant_fixture": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "service reopens after authorization reclamation")
	reopened.clock = func(): return moment
	check(reopened.accept(accepted).code == "DUPLICATE" and credits() == 7, "exact signed replay survives process restart without grant key")
	var outbox := directory.path_join("outbox").path_join(old.launch_id)
	DirAccess.make_dir_recursive_absolute(outbox)
	write_json(outbox.path_join("accepted.json"), accepted)
	write_json(outbox.path_join("late.json"), waiting)
	var recovered: Dictionary = reopened.recover()
	check(recovered.accepted == 1 and recovered.rejected == 1 and recovered.pending == 0, "offline recovery finds pruned launches and distinguishes accepted and expired")
	check(FileAccess.file_exists(outbox.path_join("late.rejected.json")), "signed late submission remains as explicit rejected evidence")
	check(fixture("inspect").expired[0].rejected_count.to_int() >= 2, "expired attempts leave lightweight rejection counters")
	var legacy := directory.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(legacy)
	check(fixture("legacy", legacy).ok, "old version 2 database fixture made")
	var old_service = Service.new()
	old_service.clock = func(): return moment + WINDOW * 500
	check(old_service.initialize(legacy, {"grant_fixture": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "old table receives additive upgrade")
	check(fixture("inspect", legacy).grants[0].ended_at == "", "legacy grant without exit proof remains unknown")
	check(fixture("fill", legacy).count == 256 and old_service.prepare_launch(_row()).code == "STORAGE_CAPACITY_EXCEEDED", "old unknown grant is not swept by creation age")
	var active_item := submission(active, service.grants[active.launch_id].secret, "active")
	check(service.accept(active_item).ok and credits() == 14, "old active room never expires just because a week elapsed")
	check(service.end_launch(active.launch_id).ok, "second room ends only after explicit server proof")
	var legacy_signed := submission(active, service.grants[active.launch_id].secret, "legacy_accepted")
	var legacy_request: Dictionary = service.validate_submission(legacy_signed).request
	legacy_request.erase("signature") # trusted legacy helper fixture, no receipt row
	check(service.commit(legacy_request).ok and credits() == 21, "legacy accepted result lacks new signature receipt")
	moment += WINDOW
	check(service.accept(legacy_signed).code == "DUPLICATE" and credits() == 21, "expired retained grant authenticates legacy original hash and installs signature receipt")
	var late_active := submission(active, service.grants[active.launch_id].secret, "racing")
	var validated: Dictionary = service.validate_submission(late_active)
	var pruning := Thread.new()
	var accepting := Thread.new()
	check(pruning.start(service.store_grant.bind(_grant(_row()))) == OK and accepting.start(service.commit.bind(validated.request)) == OK, "reclamation and acceptance use competing real SQLite writers")
	while pruning.is_alive() or accepting.is_alive():
		await process_frame
	var reclaimed: Dictionary = pruning.wait_to_finish()
	var declined: Dictionary = accepting.wait_to_finish()
	check(reclaimed.ok and declined.code == "RESULT_EXPIRED" and credits() == 21, "prune/accept race cannot pay an expired result")
	check(service.accept(active_item).code == "DUPLICATE" and credits() == 21, "race preserves accepted receipt and reward")
	check(service.accept(legacy_signed).code == "DUPLICATE" and credits() == 21, "legacy exact signed retry remains idempotent after grant removal")
	_lifecycle()
	_recovery()
	_control_loss()
	print("GRANT_RECYCLING_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _lifecycle() -> void:
	var manager = Manager.new()
	var fake = Fake.new()
	manager.launcher = fake
	manager.ports = Ports.new(39900, 39908)
	var closing = Closing.new()
	manager.result_service = closing
	var launch := Wire.uid()
	fake.launch({}, launch, [])
	var row := {"room_id": "test", "launch_id": launch, "pid": 1001, "port": manager.ports.acquire(launch), "cleaned": false, "state": "STOPPING", "history": [], "code": "", "token": "", "config_path": directory.path_join("absent.json")}
	manager.rooms.test = row
	manager._cleanup(row)
	check(closing.seen.is_empty() and not row.cleaned, "running child cannot start seven-day clock")
	fake.crash(launch)
	manager._cleanup(row)
	var first: int = row.exit_observed_at
	check(not row.cleaned and manager.ports.leases.has(launch), "failed durable close retains room and UDP lease")
	manager._cleanup(row)
	check(row.exit_observed_at == first and closing.seen.size() == 2, "failed close keeps original verified exit time")
	closing.approved = true
	manager._cleanup(row)
	check(row.cleaned and not manager.ports.leases.has(launch), "confirmed durable close permits normal resource release")

func _recovery() -> void:
	var guard = Guard.new()
	var allocator = Ports.new(39910, 39918)
	var launch := Wire.uid()
	var journal := directory.path_join("processes.json")
	write_json(journal, {"version": 1, "entries": {launch: {"port": 39910, "owned": {}, "exit_confirmed_at": 1700000001}}})
	check(guard.initialize(journal, allocator), "cross-run journal preserves original verified exit timestamp")
	guard.confirmed_exits[launch] = true # read-only process-inspection outcome injected
	var closing = Closing.new()
	guard.exit_handler = closing.confirm_exit
	guard.poll()
	check(guard.entries.has(launch) and allocator.leases.has("orphan:" + launch), "recovery does not discard journal on storage close failure")
	check(closing.seen.size() == 1 and closing.seen[0].exit_observed_at == 1700000001, "recovery retries original timestamp rather than restart time")
	closing.approved = true
	guard.poll()
	check(guard.entries.is_empty() and allocator.leases.is_empty(), "recovery releases verified orphan only after durable close")

func _control_loss() -> void:
	var manager = Manager.new()
	manager.launcher = Fake.new()
	manager.ports = Ports.new(39920, 39928)
	var remote = Remote.new()
	remote.bus = DeadBus.new()
	manager.result_service = remote
	manager.recovery_guard = Guard.new()
	var journal := directory.path_join("disconnected-processes.json")
	check(manager.recovery_guard.initialize(journal, manager.ports), "control-loss production manager owns persistent exit journal")
	var launch := Wire.uid()
	manager.launcher.launch({}, launch, [])
	var row := {"room_id": "dead_bus", "launch_id": launch, "pid": 1001, "port": manager.ports.acquire(launch), "cleaned": false, "state": "STOPPING", "history": [], "code": "", "token": "", "config_path": directory.path_join("absent.json")}
	manager.rooms.dead_bus = row
	manager.recovery_guard.reserve(launch, row.port)
	check(not manager.close_after_control_loss(), "dead bus never permits shutdown while room child still running")
	manager.launcher.crash(launch)
	manager._cleanup(row)
	var first: int = row.exit_observed_at
	check(not row.cleaned and not remote.busy() and not remote.ended.has(launch), "control loss preserves unacknowledged close without impossible RPC")
	remote.pending.test = true
	check(not manager.close_after_control_loss(), "shutdown waits existing result RPC to unwind")
	remote.pending.clear()
	check(manager.close_after_control_loss() and not row.cleaned and manager.ports.leases.has(launch), "disconnected host can close transport without faking database cleanup")
	var preserved := Wire.decode(FileAccess.get_file_as_bytes(journal), "res://schemas/process_journal.schema.json", 65536)
	check(preserved.entries.has(launch) and preserved.entries[launch].exit_confirmed_at == first, "disconnected shutdown retains original durable exit evidence")

func _row() -> Dictionary:
	return {"game_id": "grant_fixture", "build_id": "grant_build", "room_id": "fixture_room", "launch_id": Wire.uid()}

func _grant(row: Dictionary) -> Dictionary:
	row = row.duplicate(true)
	row.secret = Crypto.new().generate_random_bytes(32).hex_encode()
	return row

func submission(row: Dictionary, secret: String, suffix: String) -> Dictionary:
	var record := {"game_id": row.game_id, "build_id": row.build_id, "room_id": row.room_id, "launch_id": row.launch_id, "match_id": "m_" + row.launch_id + "_" + suffix, "result_id": Wire.uid(), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}
	return {"record": record, "signature": Format.sign(record, secret)}

func credits() -> int:
	var row: Dictionary = service.repository.execute({"op": "asset.read", "user_id": "fixture_user", "space_id": "fixture"})
	var value: Variant = JSON.parse_string(row.get("body", ""))
	return int(value.credits) if value is Dictionary else 0

func fixture(mode: String, root: String = "") -> Dictionary:
	var output: Array = []
	var shell := "powershell.exe"
	if OS.get_name() == "Linux":
		shell = OS.get_environment("ROOMKIT_PWSH") if not OS.get_environment("ROOMKIT_PWSH").is_empty() else "pwsh"
	var code := OS.execute(shell, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/grant_recycling_database.ps1"), "-Directory", directory if root.is_empty() else root, "-Mode", mode], output, false, false)
	var parsed: Variant = JSON.parse_string(str(output[0])) if code == 0 and not output.is_empty() else null
	return parsed if parsed is Dictionary else {}

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func check(value: bool, label: String) -> bool:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", "grant_recycling: ", label)
	return value
