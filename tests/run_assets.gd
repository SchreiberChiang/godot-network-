extends SceneTree
const Service = preload("res://host/core/asset_service.gd")
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Shooter = preload("res://examples/shooter/asset_policy.gd")
const Turns = preload("res://examples/turn_based/asset_policy.gd")
const Rules = preload("res://host/core/asset_rules.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var unit: Dictionary = preload("res://tests/test_assets.gd").new().run()
	passed += unit.passed
	failed += unit.failed
	var configuration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://examples/asset_catalog.example.json"))
	var directory := ProjectSettings.globalize_path("res://data/test-assets-" + Wire.uid())
	print("ASSET_EVIDENCE_DIR=", directory)
	if not check(database_fixture(directory, "legacy"), "real v1 database fixture created"):
		finish()
		return
	var service = Service.new()
	if not check(service.initialize(directory, configuration).ok, "real SQLite initialized"):
		finish()
		return
	var legacy: Dictionary = service.repository.execute({"op": "inspect"})
	check(legacy.ok and legacy.count == 1 and JSON.parse_string(legacy.rows[0].body).fixture == "preserve-me", "v1 migration preserves existing results")
	var user := {"user_id": "asset-user", "role": "player"}
	var admin := {"user_id": "operator", "role": "admin"}
	var lobby := {"location": "lobby"}
	var policy = Shooter.new()
	var grant := {"kind": "adjust", "credits": 300, "experience": 50, "reason": "测试发放 ' 中文", "request_id": "grant_1"}
	check(service.adjust(user, user.user_id, "shooter", grant).code == "ADMIN_REQUIRED", "player cannot grant credits")
	if not check(service.adjust(admin, user.user_id, "shooter", grant).ok, "real credit grant commits"):
		finish()
		return
	check(service.adjust(admin, user.user_id, "shooter", grant).code == "DUPLICATE", "duplicate grant returns committed receipt")
	check(service.read(user.user_id, "shooter").state.credits == 300, "duplicate grant does not double balance")
	var purchase := {"kind": "purchase", "item_id": "smg", "request_id": "purchase_1"}
	check(service.perform(user, "shooter", purchase, policy, {"location": "room", "life_state": "alive"}).code == "ASSET_OPERATION_DENIED", "game policy denies before store transaction")
	if not check(service.perform(user, "shooter", purchase, policy, lobby).ok, "unlock committed to actual SQLite"):
		finish()
		return
	check(service.perform(user, "shooter", purchase, policy, lobby).code == "DUPLICATE", "retry after assumed lost response returns receipt")
	var conflict := purchase.duplicate(true)
	conflict.item_id = "shotgun"
	check(service.perform(user, "shooter", conflict, policy, lobby).code == "REQUEST_CONFLICT", "same request key different item refused")
	var selected := {"kind": "select", "item_id": "smg", "slot": "primary", "request_id": "select_1"}
	check(service.perform(user, "shooter", selected, policy, {"location": "room", "life_state": "dead"}).ok, "death policy permits persistent selection")
	var reloaded = Service.new()
	check(reloaded.initialize(directory, configuration).ok, "new service instance reopens database")
	var state: Dictionary = reloaded.read(user.user_id, "shooter").state
	check(state.credits == 200 and state.profiles.shooter.primary == "smg" and "smg" in state.owned, "credits ownership and default survive reopen")
	check(reloaded.perform(user, "shooter", purchase, policy, lobby).code == "DUPLICATE", "idempotency survives reopen")
	check(reloaded.read("different-user", "shooter").state.credits == 0, "user isolation")
	check(reloaded.read(user.user_id, "turns").state.credits == 0, "independent game wallet isolation")
	var shared := configuration.duplicate(true)
	shared.spaces.shared = {"items": configuration.spaces.shooter.items.duplicate(true)}
	shared.spaces.shared.items.merge(configuration.spaces.turns.items, true)
	shared.games.shooter.space = "shared"
	shared.games.turns.space = "shared"
	var shared_service = Service.new()
	check(shared_service.initialize(directory, shared).ok, "alternate shared-space configuration loads without migration")
	check(shared_service.read(user.user_id, "shooter").state.credits == 0, "switch uses distinct wallet instead of copying balance")
	grant.request_id = "shared_grant"
	check(shared_service.adjust(admin, user.user_id, "shooter", grant).ok, "shared space funded")
	check(shared_service.perform(user, "turns", {"kind": "purchase", "item_id": "jade", "request_id": "theme_purchase"}, Turns.new(), lobby).ok, "non-shooter theme uses identical purchase service")
	check(shared_service.perform(user, "turns", {"kind": "select", "item_id": "jade", "slot": "theme", "request_id": "theme_select"}, Turns.new(), lobby).ok, "non-shooter default uses identical configuration service")
	var both: Dictionary = shared_service.read(user.user_id, "shooter").state
	check(both.credits == 200 and both.profiles.turns.theme == "jade" and both.profiles.shooter.primary == "rifle", "shared credits retain per-game selection")
	check(reloaded.read(user.user_id, "shooter").state.credits == 200 and reloaded.read(user.user_id, "shooter").state.profiles.shooter.primary == "smg", "switching back preserves original separate-space assets")
	await competing_commits(reloaded, user.user_id)
	var audit: Dictionary = reloaded.repository.execute({"op": "asset.audit", "user_id": user.user_id})
	check(audit.ok and audit.rows.size() >= 7, "committed operations carry durable audit")
	var found_unicode := false
	for row in audit.get("rows", []):
		if row.actor_id == "operator" and "中文" in row.command:
			found_unicode = true
	check(found_unicode, "bound SQLite values preserve Unicode audit reason")
	var backup := directory.path_join("asset-backup.sqlite")
	check(reloaded.repository.execute({"op": "backup", "destination": backup}).ok, "real SQLite asset backup")
	var restored = Repository.new()
	check(restored.initialize(directory, "asset-backup.sqlite").ok, "backup reopens")
	var restored_state: Dictionary = restored.execute({"op": "asset.read", "user_id": user.user_id, "space_id": "shooter"})
	check(restored_state.ok and JSON.parse_string(restored_state.body).profiles.shooter.primary == "smg", "backup retains default and ownership")
	check(restored.execute({"op": "inspect"}).integrity == "ok", "database integrity check")
	if check(database_fixture(directory, "rollback"), "test-only receipt failure installed"):
		grant.request_id = "rollback_request"
		check(not reloaded.adjust(admin, "rollback-user", "shooter", grant).ok, "injected SQLite receipt failure reported")
		check(reloaded.read("rollback-user", "shooter").state.credits == 0, "receipt failure rolls back asset change")
		check(reloaded.repository.execute({"op": "asset.audit", "user_id": "rollback-user"}).rows.is_empty(), "failed transaction leaves no success receipt")
	finish()

func database_fixture(directory: String, mode: String) -> bool:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/asset_database.ps1"), "-Directory", directory, "-Mode", mode], output, true, false)
	return code == 0 and not output.is_empty() and "ASSET_DATABASE_FIXTURE_OK" in str(output[0])

func competing_commits(service, user_id: String) -> void:
	var before: Dictionary = service.read(user_id, "shooter").state
	var commands := [{"kind": "purchase", "item_id": "shotgun", "request_id": "race_a"}, {"kind": "adjust", "credits": -200, "experience": 0, "reason": "concurrent", "request_id": "race_b"}]
	var threads: Array = []
	for command in commands:
		var candidate: Dictionary = Rules.apply(before, service.catalog, "shooter", command, true)
		if not check(candidate.ok, "race candidate valid against same original balance"):
			continue
		var request := {"op": "asset.commit", "user_id": user_id, "space_id": "shooter", "request_id": command.request_id, "fingerprint": Format.hash_record(command), "actor_id": "race-test", "command": Format.canonical(command), "expected_revision": before.revision, "body": Format.canonical(candidate.state)}
		var thread := Thread.new()
		if check(thread.start(_commit_worker.bind(service.repository.root, request)) == OK, "independent writer started"):
			threads.append(thread)
	var accepted := 0
	var conflicts := 0
	for thread in threads:
		while thread.is_alive():
			await process_frame
		var result: Dictionary = thread.wait_to_finish()
		accepted += int(result.ok)
		conflicts += int(result.get("code", "") == "ASSET_VERSION_CONFLICT")
	check(accepted == 1 and conflicts == 1, "two real SQLite writers cannot spend same revision twice")
	var after: Dictionary = service.read(user_id, "shooter").state
	check(after.credits == 0 and int(after.revision) == int(before.revision) + 1, "one atomic debit no lost update or overdraft")

func _commit_worker(directory: String, request: Dictionary) -> Dictionary:
	var repository = Repository.new()
	repository.root = directory
	repository.database = directory.path_join("assets.sqlite")
	return repository.execute(request)

func check(value: bool, label: String) -> bool:
	if value:
		passed += 1
		print("PASS assets: ", label)
	else:
		failed += 1
		printerr("FAIL assets: ", label)
	return value

func finish() -> void:
	print("ASSETS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
