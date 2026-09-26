extends SceneTree
## Syntax/contract tests only: no socket, authentication, database or room process.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const StrictJSON = preload("res://sdk/roomkit/shared/strict_json.gd")
const AdminHTTP = preload("res://host/admin_http.gd")
var passed := 0
var failed := 0
var examples: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("MANAGED_CONTRACTS_SCOPE=schemas_and_strict_json_only_no_network_or_authentication")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://examples/managed_messages.example.json"))
	if not check(parsed is Dictionary and parsed.get("cases", null) is Array, "example fixture parses"):
		finish()
		return
	check(parsed.cases.size() >= 64, "at least 64 managed examples remain present")
	for item in parsed.cases:
		if not check(item is Dictionary and item.get("name", "") != "" and not examples.has(item.name), "unique example name: " + str(item.get("name", ""))):
			continue
		examples[item.name] = item
		var error := validate_case(item)
		check(error == "", "valid example: " + str(item.name) + (" (" + error + ")" if error != "" else ""))
	for name in ["control.asset.initial", "control.asset.begin", "control.asset.permit", "control.asset.refresh", "control.asset.finish", "control.asset.finish.failed", "managed.account.register", "managed.account.login", "managed.asset.purchase", "managed.asset.select", "managed.login.response", "managed.assets.response", "managed.error.response", "rpc.hello", "rpc.account.execute.typed", "rpc.asset.player", "rpc.response", "reward.batch"]:
		check(examples.has(name), "required coverage: " + name)
	var admin_schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/admin_request.schema.json"))
	for action in admin_schema.properties.action.enum:
		check(examples.has("admin." + str(action)), "every admin action has an example: " + str(action))

	for field in ["role", "user_id", "token", "client_ip", "identity"]:
		reject_set("managed.account.login", ["payload"], field, "forged", "public login rejects client identity field " + field)
	reject_set("managed.account.register", ["payload"], "role", "admin", "registration cannot claim administrator role")
	reject_set("managed.account.rename", ["payload"], "user_id", "other-user", "public rename cannot target another identity")
	for field in ["user_id", "space_id", "credits", "experience", "context", "role", "actor_id"]:
		reject_set("managed.asset.purchase", ["payload"], field, "forged", "public purchase rejects authority field " + field)
	reject_set("managed.asset.select", ["payload"], "owned", ["shotgun"], "selection cannot inject ownership")
	reject_set("managed.asset.purchase", [], "idempotency_key", "wrong-layer", "asset persistence key belongs in payload.operation_id")
	reject_set("managed.asset.purchase", ["payload"], "operation_id", "../../receipt", "asset operation ID rejects path syntax")
	reject_set("managed.asset.read", [], "user_id", "forged", "envelope rejects identity injection")
	reject_set("managed.account.login", [], "type", "account.promote", "unknown public account operation rejected")
	reject_remove("managed.account.login", ["payload"], "password", "login requires password")
	reject_remove("managed.error.response", [], "error", "failed lobby response requires error object")
	reject_set("managed.login.response", [], "error", {"code": "AUTH_FAILED", "message": "failed", "retryable": false}, "successful lobby response cannot carry an error")
	reject_set("managed.login.response", ["payload", "identity"], "role", "owner", "typed account response rejects unknown role")

	reject_remove("control.asset.begin", ["payload"], "attempt_id", "asset begin requires admission attempt")
	reject_set("control.asset.begin", ["payload"], "role", "admin", "asset begin has no caller role override")
	reject_remove("control.asset.initial", ["payload", "state"], "owned", "initial assets require complete state")
	reject_set("control.asset.initial", ["payload", "state"], "credits", -1, "initial assets reject negative permanent balance")
	reject_remove("control.asset.refresh", ["payload"], "user_id", "asset refresh requires stable identity")
	reject_set("control.asset.permit", ["payload"], "ok", "true", "asset permit permission is boolean")
	reject_set("control.asset.finish", ["payload"], "state", {}, "successful finish cannot replace state with empty object")
	reject_set("control.asset.finish", ["payload"], "actor_id", "admin", "finish cannot inject administrator identity")
	reject_remove("control.asset.finish", [], "launch_id", "control update requires room launch identity")

	reject_set("rpc.hello", [], "token", "bad-token", "RPC hello requires token shape")
	reject_set("rpc.hello", [], "launch_id", "bad-launch", "RPC hello requires launch shape")
	reject_set("rpc.hello", [], "role", "admin", "RPC handshake rejects claimed role")
	reject_remove("rpc.account.execute.typed", [], "id", "RPC request requires correlation ID")
	reject_set("rpc.asset.initial", [], "action", "../../read", "RPC action rejects path syntax")
	reject_set("rpc.asset.initial", [], "user_id", "forged", "RPC envelope rejects identity override")
	reject_set("rpc.account.execute.typed", ["payload"], "role", "admin", "typed account RPC body rejects claimed role")
	reject_remove("rpc.account.execute.typed", ["payload"], "client_ip", "typed login RPC requires server-injected origin")

	reject_set("admin.server.start", [], "token", "forged", "admin bearer does not belong in JSON body")
	reject_set("admin.server.start", [], "role", "admin", "admin body cannot grant a role")
	reject_set("admin.asset.adjust", ["payload"], "actor_id", "admin", "admin adjustment cannot select its actor")
	reject_set("admin.room.create", ["payload"], "executable", "C:/untrusted.exe", "room API cannot choose a process executable")
	reject_set("admin.server.stop", ["payload"], "immediate", "false", "server stop requires boolean immediate flag")
	reject_remove("admin.account.reset_password", ["payload"], "reason", "password reset requires audit reason")
	reject_set("admin.account.ban", ["payload"], "hours", -1, "negative ban duration rejected")
	reject_set("admin.backup.restore", ["payload"], "backup_id", "../../accounts.sqlite", "restore cannot accept arbitrary file path")
	reject_set("admin.config.set", ["payload", "config"], "process_path", "C:/untrusted.exe", "config rejects arbitrary executable setting")
	for key in ["../racer", "racer/track", "Racer", "x", "r".repeat(65)]:
		reject_set("admin.config.set", ["payload", "config", "asset_spaces"], key, "garage", "asset space map rejects invalid game ID: " + key)
	for value in ["../garage", "res://garage", "Garage", "x", "g".repeat(65), 1, {}, null]:
		reject_set("admin.config.set", ["payload", "config", "asset_spaces"], "racer", value, "asset space map rejects invalid space ID: " + str(value))
	reject_set("admin.config.set", ["payload", "config"], "asset_spaces", {}, "asset space map cannot be empty")
	var spaces := {}
	for index in range(33):
		spaces["game_" + str(index)] = "shared"
	reject_set("admin.config.set", ["payload", "config"], "asset_spaces", spaces, "asset space map caps registered games at 32")
	spaces.erase("game_32")
	var bounded_config: Dictionary = examples["admin.config.set"].duplicate(true)
	bounded_config.message.payload.config.asset_spaces = spaces
	check(validate_case(bounded_config) == "", "32 syntactically valid game mappings accepted before runtime registry check")
	var unknown_config: Dictionary = examples["admin.config.set"].duplicate(true)
	unknown_config.message.payload.config.asset_spaces = {"unregistered_game": "unknown_space"}
	check(validate_case(unknown_config) == "", "ID syntax success does not claim registry membership or allowed mapping")
	reject_set("admin.account.list", ["payload"], "limit", 100000, "admin account list is bounded")

	var reward: Array = examples["reward.batch"].message.duplicate(true)
	reward[0].credits = 0.5
	reject_value(reward, "result_rewards.schema.json", "rewards reject fractional currency")
	reward[0].credits = "100"
	reject_value(reward, "result_rewards.schema.json", "rewards reject string currency")
	reward[0].credits = 100
	reward[0].role = "admin"
	reject_value(reward, "result_rewards.schema.json", "rewards reject actor role")
	reward = []
	for index in range(257):
		reward.append({"user_id": "user_" + str(index), "space_id": "shooter", "credits": 1, "experience": 0})
	reject_value(reward, "result_rewards.schema.json", "rewards cap historical participants at 256")
	check(not AdminHTTP._unique_keys('{"action":"status","action":"server.start","payload":{}}'), "admin HTTP key check rejects duplicate actions without opening a socket")
	check(not AdminHTTP._unique_keys('{"role":"player","r\\u006fle":"admin"}'), "admin HTTP key check rejects escaped duplicate identity keys")
	check(not StrictJSON.valid('{"action":"status","payload":{},}'), "strict parser rejects trailing comma")
	print("MANAGED_CONTRACTS_NOTE=valid_dummy_hello_does_not_authenticate_and_generic_rpc_payload_requires_runtime_service_checks")
	for name in ["admin.room.create", "admin.room.recreate"]:
		var ruled: Dictionary = examples[name].duplicate(true)
		ruled.message.payload.rules = {"duration_seconds": 60, "kill_limit": 10, "respawn_seconds": 0}
		check(validate_case(ruled) == "", "bounded room rules accepted for " + name)
		for bad in [{"kill_limit": 1.5}, {"kill_limit": true}, {"kill_limit": -1}, {"kill_limit": "5"}, {"path/invalid": 1}]:
			ruled.message.payload.rules = bad
			check(validate_case(ruled) != "", "invalid room rules rejected for " + name)
	reject_set("admin.room.stop", ["payload"], "rules", {}, "stop cannot carry recreate-only rules")
	finish()

func validate_case(item: Dictionary) -> String:
	var schema: String = item.get("schema", "")
	if schema.get_file() != schema or not schema.ends_with(".schema.json"):
		return "INVALID_FIXTURE_SCHEMA"
	var error := Validator.validate_file(item.message, "res://schemas/" + schema)
	if error != "":
		return error
	for typed in item.get("checks", []):
		var value: Variant = resolve(item.message, typed.path)
		if value == null:
			return "MISSING_TYPED_VALUE"
		var typed_schema: String = typed.schema
		if typed_schema.get_file() != typed_schema or not typed_schema.ends_with(".schema.json"):
			return "INVALID_FIXTURE_SCHEMA"
		error = Validator.validate_file(value, "res://schemas/" + typed_schema)
		if error != "":
			return error
	return ""

func resolve(message: Variant, path: Array) -> Variant:
	var value: Variant = message
	for key in path:
		if not value is Dictionary or not value.has(key):
			return null
		value = value[key]
	return value

func reject_set(name: String, path: Array, key: String, value: Variant, label: String) -> void:
	var item: Dictionary = examples[name].duplicate(true)
	var target: Variant = resolve(item.message, path)
	if not target is Dictionary:
		check(false, "invalid negative fixture: " + label)
		return
	target[key] = value
	check(validate_case(item) != "", label)

func reject_remove(name: String, path: Array, key: String, label: String) -> void:
	var item: Dictionary = examples[name].duplicate(true)
	var target: Variant = resolve(item.message, path)
	if not target is Dictionary or not target.has(key):
		check(false, "invalid negative fixture: " + label)
		return
	target.erase(key)
	check(validate_case(item) != "", label)

func reject_value(value: Variant, schema: String, label: String) -> void:
	check(Validator.validate_file(value, "res://schemas/" + schema) != "", label)

func check(condition: bool, label: String) -> bool:
	if condition:
		passed += 1
		print("PASS contract: ", label)
	else:
		failed += 1
		printerr("FAIL contract: ", label)
	return condition

func finish() -> void:
	print("MANAGED_CONTRACTS_RESULT passed=", passed, " failed=", failed)
	quit(1 if failed > 0 else 0)
