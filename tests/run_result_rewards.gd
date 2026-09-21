extends SceneTree
const Repository = preload("res://host/storage/sqlite_repository.gd")
const Service = preload("res://host/core/result_service.gd")
const Format = preload("res://sdk/roomkit/shared/result_format.gd")
const Wire = preload("res://sdk/roomkit/shared/json_wire.gd")
var passed := 0
var failed := 0
var directory := ""
var repository = Repository.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = ProjectSettings.globalize_path("res://data/test-result-rewards-" + Wire.uid())
	print("RESULT_REWARDS_EVIDENCE_DIR=", directory)
	if not check(repository.initialize(directory, "assets.sqlite").ok, "real SQLite result and asset database initializes"):
		finish()
		return
	var initial := {"revision": 1, "credits": 100, "experience": 10, "owned": ["starter", "upgrade"], "profiles": {"generic": {"primary": "upgrade"}}}
	check(seed_wallet("winner", initial).ok, "existing wallet ownership and selected configuration seeded")
	var request := submission([reward("winner", 25, 5), reward("new_user", 20)])
	check(Format.valid_record(request.record), "test uses canonical valid result record")
	check(repository.execute(request).ok, "result plus multiple permanent rewards commits")
	var winner := state("winner")
	check(winner.credits == 125 and winner.experience == 15 and winner.revision == 2, "existing balance and experience increment exactly once")
	check(winner.owned == initial.owned and winner.profiles == initial.profiles, "reward preserves owned items and saved configuration")
	check(state("new_user").credits == 20 and state("new_user").revision == 1, "new wallet initialized in same commit")
	var audit: Dictionary = repository.execute({"op": "asset.audit", "user_id": "winner"})
	check(audit.ok and audit.rows.size() == 2 and JSON.parse_string(audit.rows[0].command).kind == "result_reward", "reward receipt records source and before/after state")
	check(repository.execute(request).code == "DUPLICATE", "same result retry returns original confirmation")
	check(state("winner") == winner and state("new_user").revision == 1, "retry changes neither balances nor revisions")
	var reopened = Repository.new()
	check(reopened.initialize(directory, "assets.sqlite").ok and reopened.execute(request).code == "DUPLICATE", "duplicate identity survives database reopen")
	var recalculated := request.duplicate(true)
	recalculated.rewards[0].credits = 999
	check(repository.execute(recalculated).code == "DUPLICATE" and state("winner") == winner, "retry after reward configuration changes never adds new payout")
	var conflict := request.duplicate(true)
	conflict.record.payload.round = 2
	conflict.record_hash = Format.hash_record(conflict.record)
	conflict.body = Format.canonical(conflict.record)
	check(repository.execute(conflict).code == "RESULT_CONFLICT", "same result ID with changed content refused")
	conflict = request.duplicate(true)
	conflict.record.result_id = Wire.uid()
	conflict.record_hash = Format.hash_record(conflict.record)
	conflict.body = Format.canonical(conflict.record)
	check(repository.execute(conflict).code == "MATCH_RESULT_CONFLICT" and state("winner") == winner, "new result ID cannot pay same match twice")
	var legacy := submission([])
	legacy.erase("rewards")
	check(repository.execute(legacy).ok, "old result-only callers remain compatible")
	var same_case := submission([reward("CaseUser", 10), reward("caseuser", 20)])
	check(repository.execute(same_case).ok and state("CaseUser").credits == 10 and state("caseuser").credits == 20, "stable user IDs keep SQLite case-sensitive identity semantics")
	await concurrent_transactions()
	var invalid_values: Array = [-1, 1.5, "20", true, null, 1000001]
	for invalid in invalid_values:
		var invalid_reward := reward("invalid_user", 0)
		invalid_reward.credits = invalid
		assert_rejected([reward("winner", 1), invalid_reward], "INVALID_REWARD", "invalid reward amount " + str(invalid))
	var bad_space := reward("invalid_user", 1)
	bad_space.space_id = "../other"
	assert_rejected([reward("winner", 1), bad_space], "INVALID_REWARD", "invalid asset space")
	var bad_user := reward("", 1)
	assert_rejected([bad_user], "INVALID_REWARD", "empty identity")
	assert_rejected([reward("winner", 1), reward("winner", 2)], "INVALID_REWARD", "duplicate rewarded identity")
	assert_rejected([reward("winner", 1), null], "INVALID_REWARD", "null reward entry")
	var too_many: Array = []
	for index in range(17):
		too_many.append(reward("too_many_" + str(index), 1))
	check(repository.execute(submission(too_many)).ok and state("too_many_16").credits == 1, "historical participants beyond active room capacity can receive rewards")
	for index in range(17, 257):
		too_many.append(reward("too_many_" + str(index), 1))
	assert_rejected(too_many, "INVALID_REWARD", "more than 256 reward recipients")
	for malformed in [null, {}, {"user_id": "winner", "credits": 1}]:
		var malformed_request := submission([])
		malformed_request.rewards = malformed
		var count_before: int = repository.execute({"op": "inspect"}).count
		check(repository.execute(malformed_request).code == "INVALID_REWARD" and repository.execute({"op": "inspect"}).count == count_before, "malformed reward list does not insert result")
	var ceiling := initial.duplicate(true)
	ceiling.credits = 1000000000
	check(seed_wallet("at_ceiling", ceiling).ok, "balance ceiling fixture seeded")
	assert_rejected([reward("winner", 1), reward("at_ceiling", 1)], "ASSET_LIMIT_EXCEEDED", "later wallet overflow rolls back earlier payout")
	check(state("at_ceiling").credits == 1000000000, "overflow wallet retains original balance")
	check(fixture("install_failure").ok, "SQLite receipt failure trigger installed")
	assert_rejected([reward("winner", 1), reward("reject_user", 20)], "STORAGE_UNAVAILABLE", "later SQL receipt failure rolls back result and all wallets")
	check(state("reject_user").is_empty(), "failed receipt leaves no new wallet")
	check(fixture("drop_failure").ok, "test failure trigger removed")
	var retriable := submission([reward("winner", 1), reward("reject_user", 20)])
	check(repository.execute(retriable).ok, "normal result succeeds after storage fault removed")
	await signed_result_path()
	var capacity := fixture("fill_capacity")
	check(capacity.ok and capacity.receipt_count == 99999, "real SQLite receipt fixture reaches one remaining slot")
	assert_rejected([reward("capacity_a", 1), reward("capacity_b", 1)], "STORAGE_CAPACITY_EXCEEDED", "multi-user payout cannot exceed receipt capacity")
	var last := submission([reward("capacity_last", 1)])
	check(repository.execute(last).ok and fixture("count").receipt_count == 100000, "single remaining receipt slot can commit")
	check(repository.execute(last).code == "DUPLICATE" and state("capacity_last").revision == 1, "duplicate succeeds at full capacity without second receipt")
	assert_rejected([reward("capacity_overflow", 1)], "STORAGE_CAPACITY_EXCEEDED", "full receipt storage rejects new payout and result")
	check(repository.execute(submission([])).ok, "result without rewards remains usable at receipt capacity")
	check(repository.execute({"op": "inspect"}).integrity == "ok", "SQLite integrity holds after rollback and capacity checks")
	finish()

func signed_result_path() -> void:
	var service = Service.new()
	check(service.initialize(directory, {"reward_fixture": "res://schemas/summary_result.schema.json"}, "assets.sqlite").ok, "actual result service opens shared assets database")
	var row := {"game_id": "reward_fixture", "build_id": "fixture_build", "room_id": "fixture_room", "launch_id": Wire.uid()}
	var grant: Dictionary = service.prepare_launch(row)
	check(grant.ok, "real launch grant persisted for signed acceptance")
	if not grant.ok:
		return
	var request := submission([])
	request.record.launch_id = row.launch_id
	request.record.match_id = "m_" + row.launch_id + "_final"
	service.reward_calculator = func(_record): return [reward("signed_user", 35)]
	var signed := {"record": request.record, "signature": Format.sign(request.record, grant.config.secret)}
	check(service.accept(signed).ok and state("signed_user").credits == 35, "signed trusted result service credits permanent wallet")
	check(service.accept(signed).code == "DUPLICATE" and state("signed_user").revision == 1, "signed result retry does not repeat permanent reward")
	var forged := signed.duplicate(true)
	forged.signature = "0".repeat(64)
	check(service.accept(forged).code == "AUTH_FAILED" and state("signed_user").credits == 35, "forged signature cannot credit assets")

func concurrent_transactions() -> void:
	var duplicate := submission([reward("race_duplicate", 40)])
	var results: Array = await compete([duplicate, duplicate])
	check(results.filter(func(result): return result.ok).size() == 2 and results.filter(func(result): return result.get("code", "") == "DUPLICATE").size() == 1, "two real SQLite writers agree on one accepted result")
	check(state("race_duplicate").credits == 40 and state("race_duplicate").revision == 1, "concurrent retry credits exactly once")
	results = await compete([submission([reward("race_sum", 30)]), submission([reward("race_sum", 50)])])
	check(results.filter(func(result): return result.ok).size() == 2, "distinct result transactions both commit")
	check(state("race_sum").credits == 80 and state("race_sum").revision == 2, "concurrent results accumulate without lost update")

func assert_rejected(rewards: Array, code: String, label: String) -> void:
	var count_before: int = repository.execute({"op": "inspect"}).count
	var before := state("winner")
	var audit_before: int = repository.execute({"op": "asset.audit", "user_id": "winner"}).rows.size()
	var result: Dictionary = repository.execute(submission(rewards))
	check(not result.ok and result.get("code", "") == code, label + " reports expected error")
	check(repository.execute({"op": "inspect"}).count == count_before and state("winner") == before and repository.execute({"op": "asset.audit", "user_id": "winner"}).rows.size() == audit_before, label + " leaves result, wallet and audit unchanged")

func reward(user: String, credits: int, experience: int = 0) -> Dictionary:
	return {"user_id": user, "space_id": "fixture", "credits": credits, "experience": experience}

func submission(rewards: Array) -> Dictionary:
	var launch := Wire.uid()
	var record := {"game_id": "reward_fixture", "build_id": "fixture_build", "room_id": "fixture_room", "launch_id": launch, "match_id": "m_" + launch + "_final", "result_id": Wire.uid(), "result_kind": "final", "result_version": 1, "status": "completed", "payload": {"round": 1, "players": []}}
	return {"op": "accept", "record": record, "record_hash": Format.hash_record(record), "body": Format.canonical(record), "rewards": rewards}

func seed_wallet(user: String, body: Dictionary) -> Dictionary:
	return repository.execute({"op": "asset.commit", "user_id": user, "space_id": "fixture", "request_id": Wire.uid(), "fingerprint": Wire.uid(), "actor_id": "fixture", "command": "{}", "expected_revision": 0, "body": Format.canonical(body)})

func state(user: String) -> Dictionary:
	var response: Dictionary = repository.execute({"op": "asset.read", "user_id": user, "space_id": "fixture"})
	return JSON.parse_string(response.body) if response.ok and response.body != "" else {}

func fixture(mode: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://tests/fixtures/result_reward_database.ps1"), "-Directory", directory, "-Mode", mode], output, true, false)
	if code != 0 or output.is_empty():
		return {"ok": false}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	return parsed if parsed is Dictionary else {"ok": false}

func compete(requests: Array) -> Array:
	var threads: Array = []
	for request in requests:
		var thread := Thread.new()
		if check(thread.start(worker.bind(request)) == OK, "reward storage worker starts"):
			threads.append(thread)
	var responses: Array = []
	for thread in threads:
		while thread.is_alive():
			await process_frame
		responses.append(thread.wait_to_finish())
	return responses

func worker(request: Dictionary) -> Dictionary:
	var store = Repository.new()
	store.root = directory
	store.database = directory.path_join("assets.sqlite")
	return store.execute(request)

func check(value: bool, label: String) -> bool:
	if value:
		passed += 1
		print("PASS result_rewards: ", label)
	else:
		failed += 1
		printerr("FAIL result_rewards: ", label)
	return value

func finish() -> void:
	print("RESULT_REWARDS_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)
