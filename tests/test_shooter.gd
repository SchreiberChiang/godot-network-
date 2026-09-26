extends RefCounted
const Game = preload("res://examples/shooter/game.gd")
const Policy = preload("res://examples/shooter/asset_policy.gd")
const Rewards = preload("res://examples/shooter/rewards.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
var passed := 0
var failed := 0
var completions: Array = []
var refreshes: Array = []

func run() -> Dictionary:
	_contracts()
	_inputs_and_physics()
	_collision_edges()
	_shooting_and_assets()
	_rounds_and_rewards()
	_room_rules_and_visuals()
	return {"passed": passed, "failed": failed}

func _game():
	var world = Game.new()
	world.server = true
	world.admit({"user_id": "u1", "display_name": "甲"}, 2)
	world.admit({"user_id": "u2", "display_name": "乙"}, 3)
	return world

func _command(sequence: int, move := 0.0, jump := false, fire := false, aim := Vector2.RIGHT) -> Dictionary:
	return {"sequence": sequence, "move": move, "jump": jump, "aim_x": aim.x, "aim_y": aim.y, "fire": fire}

func _contracts() -> void:
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://examples/shooter/messages.example.json"))
	for item in examples:
		check(Validator.validate_file(item.value, "res://schemas/" + item.schema) == "", "documented " + item.schema)
	var world = Game.new()
	check(world.configure() and world.config.duration_ms == 300000 and world.config.respawn_ms == 3000, "trusted production defaults load")
	check(not world.configure({"weapons": {}}) and not world.configure({"duration_ms": -1}), "test seam cannot override firearm data and validates durations")
	world.admit({"user_id": "u1", "display_name": "甲"}, 2)
	world.admit({"user_id": "u1", "display_name": "伪造重复"}, 3)
	world.admit({"user_id": "u2", "display_name": "另一个"}, 2)
	check(world.players.size() == 1 and world.peers.size() == 1, "duplicate identities and peers cannot replace admitted player")
	check(world.players.u1.weapon == "rifle", "new account spawns with basic rifle")
	world.advance(100)
	check(world.phase == "waiting", "one player does not start round")
	check(Validator.validate_file(world.state_snapshot(), "res://schemas/shooter_state.schema.json") == "", "live waiting state validates")
	world.free()

func _inputs_and_physics() -> void:
	var world = _game()
	world.advance(0)
	check(world.phase == "active", "second admitted player starts round")
	check(not world.configure({"duration_ms": 1}), "cannot mutate active match duration")
	check(not world.handle_input(99, _command(1), 0), "unadmitted peer has no input authority")
	var command := _command(1)
	command.damage = 100
	check(not world.handle_input(2, command, 0), "client damage field rejected")
	command = _command(1)
	command.position = {"x": 900, "y": 90}
	check(not world.handle_input(2, command, 0), "client position field rejected")
	command = _command(1)
	command.aim_x = NAN
	check(not world.handle_input(2, command, 0), "non-finite aim rejected")
	check(not world.handle_input(2, _command(1, 2), 0), "overspeed direction rejected")
	check(not world.handle_input(2, _command(1, 0, false, false, Vector2.ZERO), 0), "zero aim rejected")
	world.players.u1.position = Vector2(70, 478)
	check(world.handle_input(2, _command(1, 1), 0), "valid movement accepted")
	check(not world.handle_input(2, _command(1, -1), 0), "replayed sequence rejected")
	world.advance(100)
	check(is_equal_approx(world.players.u1.position.x, 93.5), "server bounds displacement with trusted delta")
	var x: float = world.players.u1.position.x
	world.advance(400)
	check(world.players.u1.position.x == x, "stale held movement stops")
	check(world.handle_input(2, _command(2, 0, true), 400), "jump request accepted")
	world.advance(417)
	check(world.players.u1.position.y < 478 and world.players.u1.velocity.y < 0, "grounded jump uses server impulse")
	world.handle_input(2, _command(3, 0, false), 420)
	world.handle_input(2, _command(4, 0, true), 430)
	var velocity: float = world.players.u1.velocity.y
	world.advance(434)
	check(world.players.u1.velocity.y > velocity, "airborne jump cannot add another impulse")
	for now in range(450, 1601, 16):
		world.advance(now)
	check(is_equal_approx(world.players.u1.position.y, 478), "gravity lands on ground")
	world.players.u1.position = Vector2(200, 340)
	world.players.u1.velocity = Vector2(0, 180)
	world.advance(1700)
	check(is_equal_approx(world.players.u1.position.y, 358) and world.players.u1.grounded, "falling actor lands on raised platform")
	world.players.u1.position = Vector2(430, 478)
	world.players.u1.velocity = Vector2.ZERO
	world.handle_input(2, _command(5, 1), 1700)
	world.advance(1800)
	check(world.players.u1.position.x <= 440, "solid wall blocks horizontal movement")
	world.players.u1.position = Vector2(15, 478)
	world.handle_input(2, _command(6, -1), 1800)
	world.advance(1900)
	check(world.players.u1.position.x == 14, "world edge contains actor")
	for index in range(7, 104):
		world.handle_input(2, _command(index), 1900)
	check(not world.handle_input(2, _command(104), 1900), "input flood is bounded")
	check(Validator.validate_file(world.state_snapshot(), "res://schemas/shooter_state.schema.json") == "", "physics snapshot validates")
	world.free()

func _collision_edges() -> void:
	var world = _game()
	world.advance(0)
	world.players.u1.position = Vector2(200, 350)
	world.players.u1.velocity = Vector2(0, 700)
	world.advance(100)
	check(is_equal_approx(world.players.u1.position.y, 358) and world.players.u1.grounded, "delayed frame cannot tunnel through thin platform")
	world.advance(100)
	check(world.players.u1.grounded, "zero elapsed catch-up iteration preserves ground contact")
	check(is_equal_approx(Game.ray_rect(Vector2(0, 5), Vector2.RIGHT, Rect2(10, 0, 5, 10), 100), 10), "hitscan slab intersection is nearest surface")
	check(Game.ray_rect(Vector2(0, 15), Vector2.RIGHT, Rect2(10, 0, 5, 10), 100) == 100, "parallel ray outside target does not hit")
	world.free()

func _shooting_and_assets() -> void:
	var world = _game()
	world.respawn_requested.connect(func(user): refreshes.append(user))
	world.advance(0)
	world.players.u1.position = Vector2(80, 478)
	world.players.u2.position = Vector2(280, 478)
	world.handle_input(2, _command(1, 0, false, true), 250)
	world.advance(250)
	check(world.players.u2.hp == 75 and world.players.u1.hp == 100, "server hits nearest opponent, not self")
	world.handle_input(2, _command(2, 0, false, true), 260)
	world.advance(260)
	check(world.players.u2.hp == 75, "input packet spam cannot bypass weapon cadence")
	for index in range(3, 6):
		var now := 250 + (index - 2) * 230
		world.handle_input(2, _command(index, 0, false, true), now)
		world.advance(now)
	check(world.players.u2.life_state == "dead" and world.players.u2.hp == 0 and world.players.u1.kills == 1 and world.players.u2.deaths == 1, "four rifle hits kill once and record authoritative score")
	world.handle_input(2, _command(6, 0, false, true), 1200)
	world.advance(1200)
	check(world.players.u1.kills == 1, "dead bodies do not generate extra kills")
	check(not world.request_respawn("u2") and refreshes.is_empty(), "respawn forbidden before three-second wait")
	var state := {"owned": ["rifle", "smg"], "profiles": {"shooter": {"primary": "smg"}}}
	world.on_asset_state("u1", state)
	check(world.players.u1.weapon == "rifle", "confirmed default changes do not swap living weapon")
	var policy = Policy.new()
	check(policy.authorize({}, world.asset_context("u1"), {"kind": "select"}) != "", "server alive context rejects equipment modifications")
	check(policy.authorize({}, world.asset_context("u2"), {"kind": "purchase"}) == "", "server dead context authorizes purchases")
	check(policy.authorize({}, {"location": "lobby"}, {"kind": "read"}) == "", "lobby inventory read uses same game policy")
	check(policy.authorize({}, world.asset_context("u1"), {"kind": "read"}) != "", "alive inventory read also remains closed")
	world.advance(4100)
	world.set_asset_busy("u2", true)
	check(not world.request_respawn("u2"), "pending asset write blocks respawn")
	world.set_asset_busy("u2", false)
	check(world.request_respawn("u2") and refreshes == ["u2"] and world.players.u2.life_state == "dead", "manual respawn requests fresh state without early spawn")
	check(not world.request_respawn("u2"), "duplicate respawn request does not create second refresh")
	check(world.complete_respawn("u2", state) and world.players.u2.weapon == "smg" and world.players.u2.hp == 100 and not world.players.u2.asset_busy, "confirmed fresh ownership and selection used at respawn")
	check(not world.complete_respawn("u2", state), "late duplicate refresh cannot spawn twice")
	world.players.u2.life_state = "dead"
	world.players.u2.dead_at = 0
	world.request_respawn("u2")
	world.cancel_respawn("u2")
	check(world.players.u2.life_state == "dead" and not world.players.u2.asset_busy and not world.players.u2.respawn_pending, "failed asset refresh leaves dead player retryable")
	world.request_respawn("u2")
	world.complete_respawn("u2", {"owned": ["rifle"], "profiles": {"shooter": {"primary": "shotgun"}}})
	check(world.players.u2.weapon == "rifle" and world.players.u2.notice != "", "revoked or invalid selection falls back with explicit notice")
	world.players.u1.position = Vector2(400, 478)
	world.players.u2.position = Vector2(600, 478)
	world.handle_input(2, _command(7, 0, false, true), 4500)
	world.advance(4500)
	check(world.players.u2.hp == 100 and world.shots.back().end_x <= 454, "walls occlude hitscan before target")
	world.players.u1.position = Vector2(80, 478)
	world.players.u2.position = Vector2(280, 478)
	world.players.u1.weapon = "shotgun"
	world.handle_input(2, _command(8, 0, false, true), 5400)
	world.advance(5400)
	check(world.shots.size() == 6 and world.players.u2.hp < 100, "shotgun emits authoritative pellet fan")
	check(Validator.validate_file(world.state_snapshot(), "res://schemas/shooter_state.schema.json") == "", "combat and shot snapshot validates")
	world.remove_player("u2")
	check(not world.peers.has(3) and not world.asset_states.has("u2") and not world.complete_respawn("u2", state), "leave removes peer/state and rejects stale refresh")
	world.free()

func _rounds_and_rewards() -> void:
	var world = _game()
	world.configure({"duration_ms": 70000})
	world.round_finished.connect(func(key, rows): completions.append({"key": key, "rows": rows}))
	world.advance(0)
	world.advance(30000)
	check(completions.is_empty(), "no intermediate round rewards")
	world.remove_player("u2")
	world.advance(60000)
	world.admit({"user_id": "u2", "display_name": "乙"}, 4)
	world.ledger.u1.kills = 2
	world.advance(70000)
	check(completions.size() == 1 and completions[0].key == "round_1", "one completion at round deadline")
	var rows: Array = completions[0].rows
	check(rows[0].participation_ms == 70000 and rows[0].credits == 30, "eligible participation earns completed-round plus kills")
	check(rows[1].participation_ms == 40000 and rows[1].credits == 0, "disconnected time excluded and short participation earns nothing")
	check(world.round_number == 2 and world.phase == "waiting", "completed round transitions for next match")
	world.advance(70016)
	check(completions.size() == 1 and world.phase == "active" and world.players.u1.kills == 0, "new round resets match score without duplicate settlement")
	var record := {"game_id": "shooter", "status": "completed", "payload": {"round": 1, "duration_ms": 70000, "players": rows}}
	check(Validator.validate_file(record.payload, "res://schemas/shooter_result.schema.json") == "", "real generated result validates")
	check(Rewards.calculate(record) == [{"user_id": "u1", "credits": 30, "experience": 0}], "host independently recalculates eligible rewards")
	record.payload.players[0].credits = 999999
	check(Rewards.calculate(record)[0].credits == 30, "claimed result credits cannot inflate payout")
	record.status = "aborted"
	check(Rewards.calculate(record).is_empty(), "aborted round never awards completion credits")
	record.status = "completed"
	record.payload.duration_ms = 1000
	check(Rewards.calculate(record).is_empty(), "test-short round cannot bypass production reward minimum")
	record.payload.duration_ms = 70000
	record.payload.players.append(record.payload.players[0].duplicate(true))
	check(Rewards.calculate(record).is_empty(), "duplicate result user invalidates all rewards")
	record.payload.players.pop_back()
	record.payload.players[0].participation_ms = 70001
	check(Rewards.calculate(record).is_empty(), "participation cannot exceed completed duration")
	world.free()

func _room_rules_and_visuals() -> void:
	var world = _game()
	check(world.configure({"duration_ms": 120000, "kill_limit": 1, "respawn_ms": 0}), "custom match rules accepted")
	world.advance(0)
	world.players.u1.position = Vector2(80, 478)
	world.players.u2.position = Vector2(180, 478)
	world.players.u2.hp = 1
	world.handle_input(2, _command(1, 0, false, true), 1000)
	world.advance(1000)
	check(world.phase == "waiting" and world.round_number == 2, "kill target ends match before time limit")
	check(world.last_duration_ms == 1000 and world.last_results[0].kills == 1, "kill completion records actual elapsed duration and score")
	check(Rewards.calculate({"game_id": "shooter", "status": "completed", "payload": {"round": 1, "duration_ms": world.last_duration_ms, "players": world.last_results}}).is_empty(), "early kill target cannot bypass reward participation minimum")
	var client = Game.new()
	var snapshot: Dictionary = world.state_snapshot()
	client.world_state(snapshot)
	var start: Vector2 = client.render_position(snapshot.players[0])
	snapshot = snapshot.duplicate(true)
	snapshot.tick += 3
	snapshot.players[0].x += 12
	client.world_state(snapshot)
	check(client.render_position(snapshot.players[0]) == start, "snapshot does not instantly snap rendered position")
	client.advance_visual(1.0 / 60.0)
	check(is_equal_approx(client.render_position(snapshot.players[0]).x, start.x + 4), "20 Hz positions interpolate on 60 Hz render frames")
	client.advance_visual(0.1)
	check(is_equal_approx(client.render_position(snapshot.players[0]).x, start.x + 12), "network stall freezes at authoritative endpoint without extrapolating")
	snapshot = snapshot.duplicate(true)
	snapshot.tick += 3
	snapshot.players[0].x = 800
	client.world_state(snapshot)
	check(client.render_position(snapshot.players[0]).x == 800, "teleport snaps immediately")
	var visual_count: int = client.visual_shots.size()
	client.world_state(snapshot)
	check(client.visual_shots.size() == visual_count, "repeated snapshot cannot replay shot effects")
	client.advance_visual(0.3)
	check(client.visual_shots.is_empty(), "shot visuals expire even without new network packets")
	snapshot = snapshot.duplicate(true)
	client.latest.clear()
	client.world_state(snapshot)
	check(client.visual_shots.size() > 0, "joining another room resets per-room shot serial tracking")
	for age in [0.0, 0.025, 0.05, 0.1]:
		var segment := Game.tracer_segment(Vector2.ZERO, Vector2(900, 0), age)
		check(segment[0].distance_to(segment[1]) <= 18.001 and segment[1].x <= 900, "bullet stays short and stops at server hit endpoint")
	client.free()
	world.free()

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL shooter: ", label)
