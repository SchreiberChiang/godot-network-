extends Node
## This game owns movement, life states and firearms. The SDK never imports it.
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const SIZE := Vector2(960, 540)
const HALF := Vector2(14, 22)
const SPEED := 235.0
const GRAVITY := 1150.0
const JUMP_SPEED := 470.0
const STEP := 1.0 / 60.0
const SOLIDS := [Rect2(0, 500, 960, 40), Rect2(145, 380, 195, 18), Rect2(620, 380, 195, 18), Rect2(390, 265, 180, 18), Rect2(454, 448, 52, 52)]
const SPAWNS := [Vector2(95, 478), Vector2(865, 478), Vector2(190, 358), Vector2(770, 358), Vector2(420, 243), Vector2(540, 243)]
signal round_finished(match_key: String, players: Array)
signal respawn_requested(user_id: String)
## Client presentation only (sound): derived from accepted server snapshots.
signal presentation_cue(cue: String, detail: Dictionary)
var server := false
var players: Dictionary = {}
var peers: Dictionary = {}
var asset_states: Dictionary = {}
var latest: Dictionary = {}
var config: Dictionary = {}
var ledger: Dictionary = {}
var shots: Array = []
var phase := "waiting"
var round_number := 1
var match_started := -1
var tick := 0
var sequence := 0
var respawn_sequence := 0
var rejected := 0
var accumulator := 0.0
var clock_ms := 0
var previous_step := -1
var spawn_counter := 0
var shot_serial := 0
var last_results: Array = []
var last_duration_ms := 0
# Presentation only: authoritative state and hit detection stay untouched.
var render_tracks: Dictionary = {}
var aim_tracks: Dictionary = {}
var _local_aim_user := ""
var _local_aim := Vector2.ZERO
var visual_shots: Array = []
var last_visual_shot := 0
var snapshot_age := 0.0
# Diagnostic reception times are independent of interpolation/sound acceptance.
var _diagnostic_tick := -1
var _diagnostic_received_ms := -1
var _diagnostic_interval_ms := -1
const BLEND_SECONDS := 0.05
# Body-only arrival smoothing: steady 20 Hz stays at 50 ms. Recent jitter can
# extend a new transition to at most 100 ms, at the cost of extra display lag.
# This is not a remote clock, queued snapshot playback or movement prediction.
const POSITION_BLEND_MAX := 0.1
const POSITION_INTERVAL_COUNT := 6
const POSITION_CADENCE_RESET := 0.25
var _position_intervals: Array[float] = []
var _position_arrival_age := 0.0
var _position_tick := -1
var _position_blend_seconds := BLEND_SECONDS
const TRACER_SPEED := 7000.0
const TRACER_LENGTH := 18.0

func _init() -> void:
	var path: String = get_script().resource_path.get_base_dir().path_join("game_config.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and Validator.validate_file(data, "res://schemas/shooter_config.schema.json") == "":
		config = data

# Called by the adapter with host-validated room options; never a gameplay RPC.
func configure(overrides: Dictionary = {}) -> bool:
	var candidate := config.duplicate(true)
	for key in overrides:
		if key not in ["duration_ms", "minimum_participation_ms", "respawn_ms", "kill_limit"]:
			return false
		candidate[key] = overrides[key]
	if phase != "waiting" or Validator.validate_file(candidate, "res://schemas/shooter_config.schema.json") != "":
		return false
	config = candidate
	return true

func admit(identity: Dictionary, peer: int) -> void:
	var user := str(identity.get("user_id", ""))
	if config.is_empty() or peer <= 1 or user == "" or players.has(user) or peers.has(peer) or players.size() >= 16:
		return
	peers[peer] = user
	players[user] = {"user_id": user, "display_name": str(identity.get("display_name", user)).left(32), "position": Vector2.ZERO, "velocity": Vector2.ZERO, "move": 0.0, "aim": Vector2.RIGHT, "jump_pressed": false, "jump_queued": false, "fire": false, "grounded": false, "hp": 100, "life_state": "alive", "weapon": "rifle", "last_input": -1000, "last_shot": -10000, "sequence": 0, "respawn_sequence": 0, "window": clock_ms, "received": 0, "dead_at": 0, "asset_busy": false, "respawn_pending": false, "notice": "", "kills": 0, "deaths": 0}
	_spawn(players[user])
	if phase == "active":
		_join_ledger(user)
	_publish()

func remove_player(user_id: String) -> void:
	if ledger.has(user_id) and players.has(user_id):
		ledger[user_id].joined_at = -1
	players.erase(user_id)
	asset_states.erase(user_id)
	for peer in peers.keys():
		if peers[peer] == user_id:
			peers.erase(peer)
	_publish()

func on_asset_state(user_id: String, state: Dictionary) -> void:
	asset_states[user_id] = state.duplicate(true)

func set_asset_busy(user_id: String, busy: bool) -> void:
	if players.has(user_id):
		players[user_id].asset_busy = busy or bool(players[user_id].respawn_pending)

func asset_context(user_id: String) -> Dictionary:
	if not players.has(user_id):
		return {}
	return {"location": "room", "life_state": players[user_id].life_state}

func handle_input(peer: int, command: Dictionary, now: int) -> bool:
	if not peers.has(peer) or Validator.validate_file(command, "res://schemas/shooter_input.schema.json") != "":
		return _reject()
	var player: Dictionary = players[peers[peer]]
	if now - int(player.window) >= 1000:
		player.window = now
		player.received = 0
	player.received += 1
	var aim := Vector2(float(command.aim_x), float(command.aim_y))
	if player.received > 90 or int(command.sequence) <= int(player.sequence) or aim.length_squared() < 0.0001:
		return _reject()
	player.sequence = int(command.sequence)
	player.last_input = now
	player.move = float(command.move)
	player.aim = aim.normalized()
	player.jump_queued = bool(player.jump_queued) or (command.jump and not player.jump_pressed)
	player.jump_pressed = command.jump
	player.fire = command.fire
	return true

func request_respawn(user_id: String) -> bool:
	if not players.has(user_id):
		return false
	var player: Dictionary = players[user_id]
	if player.life_state != "dead" or player.asset_busy or player.respawn_pending or clock_ms - int(player.dead_at) < int(config.respawn_ms):
		return false
	player.respawn_pending = true
	player.asset_busy = true
	player.notice = "正在确认已保存的装备"
	respawn_requested.emit(user_id)
	return true

func complete_respawn(user_id: String, state: Dictionary) -> bool:
	if not players.has(user_id) or not players[user_id].respawn_pending:
		return false
	on_asset_state(user_id, state)
	_spawn(players[user_id])
	_publish()
	return true

func cancel_respawn(user_id: String) -> void:
	if players.has(user_id) and players[user_id].respawn_pending:
		players[user_id].respawn_pending = false
		players[user_id].asset_busy = false
		players[user_id].notice = "装备确认失败，请重试复活"

func advance(now: int) -> void:
	if config.is_empty() or now < clock_ms:
		return
	clock_ms = now
	tick += 1
	var elapsed := 0 if previous_step < 0 else maxi(0, now - previous_step)
	var dt := STEP if previous_step < 0 else clampf(float(elapsed) / 1000.0, 0.0, 0.1)
	previous_step = now
	if phase == "waiting" and players.size() >= 2:
		_begin_round(now)
	if phase == "active":
		var until := mini(now, match_started + int(config.duration_ms))
		for user in players:
			if not ledger.has(user):
				continue
			var row: Dictionary = ledger[user]
			row.participation_ms += maxi(0, until - maxi(int(row.joined_at), now - elapsed))
		if now >= match_started + int(config.duration_ms):
			_finish_round()
	for player in players.values():
		if player.life_state != "alive":
			continue
		var fresh := now - int(player.last_input) <= 250
		_move(player, dt, fresh)
	for player in players.values():
		if player.life_state != "alive":
			continue
		var fresh := now - int(player.last_input) <= 250
		if phase == "active" and fresh and player.fire and now - int(player.last_shot) >= int(config.weapons[player.weapon].cooldown_ms):
			_fire(player, now)
			if int(config.get("kill_limit", 0)) > 0 and int(player.kills) >= int(config.kill_limit):
				_finish_round()
	for index in range(shots.size() - 1, -1, -1):
		if now - int(shots[index].at) > 160:
			shots.remove_at(index)

func _begin_round(now: int) -> void:
	phase = "active"
	match_started = now
	ledger.clear()
	for user in players:
		players[user].kills = 0
		players[user].deaths = 0
		_join_ledger(user)

func _join_ledger(user: String) -> void:
	if not ledger.has(user):
		ledger[user] = {"user_id": user, "kills": 0, "deaths": 0, "participation_ms": 0, "joined_at": clock_ms}
	else:
		ledger[user].joined_at = clock_ms
	players[user].kills = int(ledger[user].kills)
	players[user].deaths = int(ledger[user].deaths)

func _finish_round() -> void:
	last_duration_ms = maxi(1, mini(clock_ms - match_started, int(config.duration_ms)))
	var rows: Array = []
	for record in ledger.values():
		var credits := 0
		if int(record.participation_ms) >= int(config.minimum_participation_ms):
			credits = int(config.completion_credits) + int(record.kills) * int(config.kill_credits)
		rows.append({"user_id": record.user_id, "kills": record.kills, "deaths": record.deaths, "participation_ms": record.participation_ms, "credits": credits})
	last_results = rows.duplicate(true)
	phase = "waiting"
	var key := "round_" + str(round_number)
	round_number += 1
	match_started = -1
	ledger.clear()
	round_finished.emit(key, rows)

func _move(player: Dictionary, dt: float, fresh: bool) -> void:
	if dt <= 0:
		return
	# A delayed frame must not tunnel through an 18px platform at terminal speed.
	var count := maxi(1, ceili(dt / STEP))
	for index in count:
		_move_step(player, dt / count, fresh)

func _move_step(player: Dictionary, dt: float, fresh: bool) -> void:
	var velocity: Vector2 = player.velocity
	velocity.x = float(player.move) * SPEED if fresh else 0.0
	if fresh and player.jump_queued and player.grounded:
		velocity.y = -JUMP_SPEED
	player.jump_queued = false
	velocity.y = minf(velocity.y + GRAVITY * dt, 700.0)
	var position: Vector2 = player.position
	position.x = clampf(position.x + velocity.x * dt, HALF.x, SIZE.x - HALF.x)
	for solid: Rect2 in SOLIDS:
		if Rect2(position - HALF, HALF * 2).intersects(solid):
			if velocity.x > 0:
				position.x = solid.position.x - HALF.x
			elif velocity.x < 0:
				position.x = solid.end.x + HALF.x
	position.y += velocity.y * dt
	player.grounded = false
	for solid: Rect2 in SOLIDS:
		if Rect2(position - HALF, HALF * 2).intersects(solid):
			if velocity.y >= 0:
				position.y = solid.position.y - HALF.y
				player.grounded = true
			else:
				position.y = solid.end.y + HALF.y
			velocity.y = 0
	if position.y < HALF.y:
		position.y = HALF.y
		velocity.y = maxf(0.0, velocity.y)
	player.position = position
	player.velocity = velocity

func _fire(player: Dictionary, now: int) -> void:
	player.last_shot = now
	var weapon: Dictionary = config.weapons[player.weapon]
	var origin: Vector2 = player.position + Vector2(0, -5)
	for pellet in int(weapon.pellets):
		# Spread belongs to the server. Fixed fan is reproducible, not client-controlled.
		var offset := 0.0
		if int(weapon.pellets) > 1:
			offset = (float(pellet) / float(int(weapon.pellets) - 1) - 0.5) * float(weapon.spread)
		elif float(weapon.spread) > 0:
			offset = sin(float(shot_serial) * 2.399963) * float(weapon.spread)
		var direction: Vector2 = player.aim.rotated(offset)
		var distance := float(weapon.range)
		for solid: Rect2 in SOLIDS:
			distance = minf(distance, ray_rect(origin, direction, solid, distance))
		var target := ""
		for user in players:
			var other: Dictionary = players[user]
			if user == player.user_id or other.life_state != "alive":
				continue
			var hit := ray_rect(origin, direction, Rect2(other.position - HALF, HALF * 2), distance)
			if hit < distance:
				distance = hit
				target = user
		if target != "":
			_damage(target, player.user_id, int(weapon.damage), now)
		shot_serial += 1
		var end := origin + direction * distance
		shots.append({"id": shot_serial, "at": now, "x": origin.x, "y": origin.y, "end_x": end.x, "end_y": end.y, "weapon": player.weapon})
		if shots.size() > 192:
			shots.pop_front()

static func ray_rect(origin: Vector2, direction: Vector2, rect: Rect2, maximum: float) -> float:
	var near := 0.0
	var far := maximum
	for axis in 2:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < rect.position[axis] or origin[axis] > rect.end[axis]:
				return maximum
			continue
		var a: float = (rect.position[axis] - origin[axis]) / direction[axis]
		var b: float = (rect.end[axis] - origin[axis]) / direction[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if far < near:
			return maximum
	return near if near <= maximum and far >= 0 else maximum

func _damage(target: String, attacker: String, damage: int, now: int) -> void:
	var victim: Dictionary = players[target]
	if victim.life_state != "alive":
		return
	victim.hp = maxi(0, int(victim.hp) - damage)
	if victim.hp > 0:
		return
	victim.life_state = "dead"
	victim.dead_at = now
	victim.velocity = Vector2.ZERO
	victim.fire = false
	victim.deaths += 1
	victim.notice = "可以打开背包解锁或选择武器，再手动复活"
	players[attacker].kills += 1
	if ledger.has(target):
		ledger[target].deaths += 1
	if ledger.has(attacker):
		ledger[attacker].kills += 1

func _spawn(player: Dictionary) -> void:
	var state: Dictionary = asset_states.get(player.user_id, {})
	var chosen := str(state.get("profiles", {}).get("shooter", {}).get("primary", "rifle"))
	var valid: bool = chosen == "rifle" or (chosen in state.get("owned", []) and config.weapons.has(chosen))
	player.notice = "" if valid else "保存的装备已不可用，已使用基础步枪"
	player.weapon = chosen if valid else "rifle"
	player.position = _spawn_position()
	spawn_counter += 1
	player.velocity = Vector2.ZERO
	player.move = 0.0
	player.fire = false
	player.jump_queued = false
	player.jump_pressed = false
	player.grounded = true
	player.hp = 100
	player.life_state = "alive"
	player.respawn_pending = false
	player.asset_busy = false
	player.last_input = -1000
	player.last_shot = clock_ms

func _spawn_position() -> Vector2:
	var best: Vector2 = SPAWNS[spawn_counter % SPAWNS.size()]
	var best_distance := -1.0
	for offset in SPAWNS.size():
		var candidate: Vector2 = SPAWNS[(spawn_counter + offset) % SPAWNS.size()]
		var closest := INF
		for player in players.values():
			if player.life_state == "alive" and player.position != Vector2.ZERO:
				closest = minf(closest, candidate.distance_squared_to(player.position))
		if closest > best_distance:
			best_distance = closest
			best = candidate
	return best

func state_snapshot() -> Dictionary:
	var rows: Array = []
	for user in players:
		var player: Dictionary = players[user]
		rows.append({"user_id": user, "display_name": player.display_name, "x": player.position.x, "y": player.position.y, "aim_x": player.aim.x, "aim_y": player.aim.y, "hp": player.hp, "life_state": player.life_state, "weapon": player.weapon, "kills": player.kills, "deaths": player.deaths, "respawn_wait_ms": maxi(0, int(config.respawn_ms) - (clock_ms - int(player.dead_at))) if player.life_state == "dead" else 0, "asset_busy": player.asset_busy, "notice": player.notice})
	var remaining := maxi(0, int(config.get("duration_ms", 300000)) - (clock_ms - match_started)) if phase == "active" else int(config.get("duration_ms", 300000))
	return {"tick": tick, "phase": phase, "round": round_number, "remaining_ms": remaining, "kill_limit": int(config.get("kill_limit", 0)), "players": rows, "shots": shots.duplicate(true), "last_results": last_results.duplicate(true)}

func _process(delta: float) -> void:
	if not server:
		advance_visual(delta)
		return
	accumulator = minf(accumulator + delta, 0.1)
	while accumulator >= STEP:
		accumulator -= STEP
		advance(Time.get_ticks_msec() - roundi(accumulator * 1000.0))
		if tick % 3 == 0:
			_publish()

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func input_command(command: Dictionary) -> void:
	if server:
		handle_input(multiplayer.get_remote_sender_id(), command, Time.get_ticks_msec())

@rpc("any_peer", "call_remote", "reliable", 1)
func respawn_command(value: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not server or not peers.has(peer) or value < 1 or value > 9007199254740991:
		return
	var player: Dictionary = players[peers[peer]]
	if value <= int(player.respawn_sequence):
		return
	player.respawn_sequence = value
	request_respawn(player.user_id)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func world_state(value: Dictionary) -> void:
	if not server and Validator.validate_file(value, "res://schemas/shooter_state.schema.json") == "" and int(value.tick) >= int(latest.get("tick", -1)):
		var cues: Array = [] if latest.is_empty() else presentation_cues(latest, value, last_visual_shot)
		if latest.is_empty():
			render_tracks.clear()
			aim_tracks.clear()
			set_local_aim("", Vector2.ZERO, false)
			visual_shots.clear()
			last_visual_shot = 0
			_diagnostic_tick = -1
			_diagnostic_received_ms = -1
			_diagnostic_interval_ms = -1
		if int(value.tick) > _diagnostic_tick:
			var now := Time.get_ticks_msec()
			if _diagnostic_received_ms >= 0:
				_diagnostic_interval_ms = now - _diagnostic_received_ms
			_diagnostic_tick = int(value.tick)
			_diagnostic_received_ms = now
		# Admission, departure and respawn can publish again within the same tick.
		# Unchanged targets do not restart their blend; accepted life changes do.
		_update_aim_targets(value)
		_update_visual_targets(value)
		latest = value
		snapshot_age = 0.0
		for cue in cues:
			presentation_cue.emit(cue.cue, cue)

## Client reception gaps/progress age only. No remote clock or packet-loss claim.
func snapshot_diagnostics() -> Dictionary:
	return {"interval_ms": _diagnostic_interval_ms, "age_ms": Time.get_ticks_msec() - _diagnostic_received_ms if _diagnostic_received_ms >= 0 else -1}

## Sound cues between two accepted snapshots. Shots are server-confirmed and
## new by id (one cue per trigger pull, so a shotgun's pellets play once); a hit
## is a confirmed hp drop of a living player; a death is the transition into dead
## or a raised death count, so a repeated or equal snapshot yields nothing. The
## snapshot carries no attacker, so "hit" means any confirmed damage, not only
## damage dealt by the local player.
static func presentation_cues(old: Dictionary, value: Dictionary, seen_shot: int) -> Array:
	var cues: Array = []
	var pulls: Dictionary = {}
	for shot in value.get("shots", []):
		if int(shot.id) > seen_shot:
			var key := "%d:%.1f:%.1f" % [int(shot.at), float(shot.x), float(shot.y)]
			if not pulls.has(key):
				pulls[key] = true
				cues.append({"cue": "fire", "weapon": str(shot.weapon), "x": float(shot.x), "y": float(shot.y)})
	var before: Dictionary = {}
	for player in old.get("players", []):
		before[str(player.user_id)] = player
	for player in value.get("players", []):
		var user := str(player.user_id)
		if not before.has(user):
			continue
		var previous: Dictionary = before[user]
		var died: bool = (previous.life_state == "alive" and player.life_state == "dead") or int(player.deaths) > int(previous.deaths)
		if died:
			cues.append({"cue": "death", "user_id": user})
		elif previous.life_state == "alive" and player.life_state == "alive" and int(player.hp) < int(previous.hp):
			cues.append({"cue": "hit", "user_id": user})
	return cues

func _update_visual_targets(value: Dictionary) -> void:
	_update_position_cadence(value)
	var present: Dictionary = {}
	for player in value.players:
		var user: String = player.user_id
		present[user] = true
		var target := Vector2(player.x, player.y)
		var from := render_position(player)
		var old: Dictionary = render_tracks.get(user, {})
		var previous := player_view(user)
		# Death, respawn and teleports must never glide through the map.
		# Compare confirmed positions: display lag alone is not a teleport.
		var reset: bool = old.is_empty() or old.get("life", "") != player.life_state or int(old.get("deaths", -1)) != int(player.deaths) or int(value.round) != int(latest.get("round", value.round))
		if not previous.is_empty():
			reset = reset or Vector2(float(previous.x), float(previous.y)).distance_to(target) > 100.0
		if reset:
			from = target
		if reset or old.get("to", Vector2.INF) != target:
			render_tracks[user] = {"from": from, "to": target, "age": 0.0, "duration": _position_blend_seconds, "life": player.life_state, "deaths": player.deaths}
	for user in render_tracks.keys():
		if not present.has(user):
			render_tracks.erase(user)
	for shot in value.shots:
		if int(shot.id) <= last_visual_shot:
			continue
		last_visual_shot = int(shot.id)
		visual_shots.append({"from": Vector2(shot.x, shot.y), "to": Vector2(shot.end_x, shot.end_y), "age": 0.0})

func _update_position_cadence(value: Dictionary) -> void:
	if latest.is_empty() or int(value.round) != int(latest.get("round", value.round)):
		_position_intervals.clear()
		_position_tick = -1
		_position_blend_seconds = BLEND_SECONDS
	# Same-tick lifecycle publications are valid, but not new cadence samples.
	if int(value.tick) <= _position_tick:
		return
	if _position_tick >= 0:
		if _position_arrival_age >= POSITION_CADENCE_RESET:
			_position_intervals.clear()
		else:
			_position_intervals.append(_position_arrival_age)
			if _position_intervals.size() > POSITION_INTERVAL_COUNT:
				_position_intervals.pop_front()
	_position_blend_seconds = BLEND_SECONDS
	for interval in _position_intervals:
		_position_blend_seconds = maxf(_position_blend_seconds, minf(interval, POSITION_BLEND_MAX))
	_position_arrival_age = 0.0
	_position_tick = int(value.tick)

func advance_visual(delta: float) -> void:
	snapshot_age += delta
	_position_arrival_age += delta
	for track in render_tracks.values():
		track.age = minf(float(track.age) + delta, float(track.duration))
	for track in aim_tracks.values():
		track.age = minf(float(track.age) + delta, BLEND_SECONDS)
	for index in range(visual_shots.size() - 1, -1, -1):
		var shot: Dictionary = visual_shots[index]
		shot.age += delta
		if float(shot.age) > shot.from.distance_to(shot.to) / TRACER_SPEED + 0.04:
			visual_shots.remove_at(index)

func render_position(player: Dictionary) -> Vector2:
	var track: Dictionary = render_tracks.get(player.user_id, {})
	if track.is_empty():
		return Vector2(player.x, player.y)
	return track.from.lerp(track.to, clampf(float(track.age) / float(track.duration), 0.0, 1.0))

## Presentation only. The caller samples the same direction as send_input,
## every display frame; neither snapshots nor server hit detection are changed.
func set_local_aim(user: String, direction: Vector2, active: bool = true) -> void:
	if server:
		return
	var player := player_view(user)
	if not active or player.get("life_state", "") != "alive" or not direction.is_finite():
		_local_aim_user = ""
		_local_aim = Vector2.ZERO
		return
	_local_aim_user = user
	_local_aim = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT

func render_aim(player: Dictionary, own_user: String = "") -> Vector2:
	var confirmed := Vector2(float(player.get("aim_x", 1)), float(player.get("aim_y", 0)))
	if server:
		return confirmed
	if own_user == _local_aim_user and str(player.get("user_id", "")) == own_user and player.get("life_state", "") == "alive" and not _local_aim.is_zero_approx():
		return _local_aim
	var track: Dictionary = aim_tracks.get(player.get("user_id", ""), {})
	if track.is_empty():
		return confirmed
	return Vector2.from_angle(lerp_angle(float(track.from), float(track.to), clampf(float(track.age) / BLEND_SECONDS, 0.0, 1.0)))

func _update_aim_targets(value: Dictionary) -> void:
	var present: Dictionary = {}
	for player in value.players:
		var user: String = player.user_id
		present[user] = true
		var direction := Vector2(float(player.aim_x), float(player.aim_y))
		var target := direction.angle()
		var old: Dictionary = aim_tracks.get(user, {})
		var previous := player_view(user)
		var reset: bool = old.is_empty() or old.get("life", "") != player.life_state or int(old.get("deaths", -1)) != int(player.deaths) or int(value.round) != int(latest.get("round", value.round))
		if not previous.is_empty():
			reset = reset or Vector2(float(previous.x), float(previous.y)).distance_to(Vector2(float(player.x), float(player.y))) > 100.0
		if reset or not is_zero_approx(angle_difference(float(old.get("to", target)), target)):
			var from := target if reset else render_aim(player).angle()
			aim_tracks[user] = {"from": from, "to": target, "age": 0.0, "life": player.life_state, "deaths": player.deaths}
		if reset and user == _local_aim_user:
			set_local_aim("", Vector2.ZERO, false)
	for user in aim_tracks.keys():
		if not present.has(user):
			aim_tracks.erase(user)
	if not present.has(_local_aim_user):
		set_local_aim("", Vector2.ZERO, false)

static func tracer_segment(origin: Vector2, end: Vector2, age: float) -> PackedVector2Array:
	var distance := origin.distance_to(end)
	var head := minf(distance, 29.0 + maxf(age, 0.0) * TRACER_SPEED)
	var direction := origin.direction_to(end)
	return PackedVector2Array([origin + direction * maxf(0.0, head - TRACER_LENGTH), origin + direction * head])

func _publish() -> void:
	latest = state_snapshot()
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer():
		return
	for peer in peers:
		world_state.rpc_id(peer, latest)

func _reject() -> bool:
	rejected += 1
	return false

func send_input(move: float, jump: bool, aim: Vector2, fire: bool) -> void:
	sequence += 1
	var direction := aim.normalized() if aim.length_squared() > 0.0001 else Vector2.RIGHT
	input_command.rpc_id(1, {"sequence": sequence, "move": clampf(move, -1, 1), "jump": jump, "aim_x": direction.x, "aim_y": direction.y, "fire": fire})

func send_respawn() -> void:
	respawn_sequence += 1
	respawn_command.rpc_id(1, respawn_sequence)

func player_view(user: String) -> Dictionary:
	for player in latest.get("players", []):
		if player.user_id == user:
			return player
	return {}

func can_open_inventory(user: String) -> bool:
	return player_view(user).get("life_state", "") == "dead"

func title() -> String:
	return "零号仓库 · 自由混战"

func instructions() -> String:
	return "A / D 移动 · 空格跳跃 · 鼠标瞄准 / 左键射击 · 死亡后打开背包并手动复活"

func actions() -> Array:
	return ["复活"]

func status_text(user: String) -> String:
	var player := player_view(user)
	if player.get("life_state", "") == "dead":
		var wait := int(ceil(float(player.get("respawn_wait_ms", 0)) / 1000.0))
		return "已阵亡 · %s" % ("还需等待 %d 秒" % wait if wait > 0 else "可打开背包或点击复活")
	if latest.get("phase", "waiting") == "waiting":
		return "等待第二名玩家 · 可以自由移动熟悉地图"
	var seconds := int(latest.get("remaining_ms", 0)) / 1000
	var goal := int(latest.get("kill_limit", 0))
	return "第 %d 局 · %02d:%02d · 生命 %d · 击杀 %d / 死亡 %d%s" % [int(latest.get("round", 1)), seconds / 60, seconds % 60, int(player.get("hp", 100)), int(player.get("kills", 0)), int(player.get("deaths", 0)), " · %d 杀获胜" % goal if goal > 0 else ""]

func draw_on(canvas: CanvasItem, user: String, font: Font) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, SIZE), Color("101b2b"))
	for x in range(0, 961, 60):
		canvas.draw_line(Vector2(x, 0), Vector2(x, 500), Color("192a3d"))
	for y in range(20, 501, 60):
		canvas.draw_line(Vector2(0, y), Vector2(960, y), Color("192a3d"))
	for x in [65, 285, 665, 885]:
		canvas.draw_rect(Rect2(x, 92, 8, 300), Color("20344a"))
		canvas.draw_circle(Vector2(x + 4, 94), 5, Color("f4bf69"))
	canvas.draw_string(font, Vector2(38, 56), "DEPOT / 01", HORIZONTAL_ALIGNMENT_LEFT, 350, 30, Color("4a657e"))
	canvas.draw_string(font, Vector2(678, 56), "ROOMKIT  •  FFA", HORIZONTAL_ALIGNMENT_LEFT, 260, 18, Color("66859a"))
	for solid: Rect2 in SOLIDS:
		canvas.draw_rect(solid, Color("293f53"))
		canvas.draw_line(solid.position, Vector2(solid.end.x, solid.position.y), Color("7fa1aa"), 3)
		for x in range(int(solid.position.x) + 10, int(solid.end.x) - 5, 28):
			canvas.draw_line(Vector2(x, solid.position.y + 5), Vector2(x + 8, minf(solid.end.y - 3, solid.position.y + 13)), Color("405b6b"), 2)
	for shot in visual_shots:
		var travel: float = shot.from.distance_to(shot.to) / TRACER_SPEED
		if float(shot.age) < travel:
			var segment := tracer_segment(shot.from, shot.to, shot.age)
			canvas.draw_line(segment[0], segment[1], Color("ffe2a0"), 2, true)
		else:
			var fade := 1.0 - clampf((float(shot.age) - travel) / 0.04, 0, 1)
			canvas.draw_circle(shot.to, 2.5 * fade, Color(1.0, 0.75, 0.35, fade))
	for player in latest.get("players", []):
		var position := render_position(player)
		var own: bool = player.user_id == user
		var color := Color("ffcd79") if own else Color("81d4df")
		if player.life_state == "dead":
			canvas.draw_line(position + Vector2(-10, 12), position + Vector2(10, -8), Color("637389"), 3)
			canvas.draw_line(position + Vector2(10, 12), position + Vector2(-10, -8), Color("637389"), 3)
			canvas.draw_string(font, position + Vector2(-70, -33), player.display_name + " · 阵亡", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color("94a2b3"))
			continue
		canvas.draw_circle(position + Vector2(0, 22), 16, Color(0, 0, 0, 0.2))
		canvas.draw_rect(Rect2(position + Vector2(-11, -8), Vector2(22, 25)), color)
		canvas.draw_circle(position + Vector2(0, -15), 10, color.lightened(0.1))
		canvas.draw_rect(Rect2(position + Vector2(-7, -17), Vector2(14, 5)), Color("142638"))
		canvas.draw_line(position + Vector2(-6, 14), position + Vector2(-7, 22), color.darkened(0.22), 6)
		canvas.draw_line(position + Vector2(6, 14), position + Vector2(7, 22), color.darkened(0.22), 6)
		var aim := render_aim(player, user)
		var gun_length := 29.0 if player.weapon == "rifle" else (20.0 if player.weapon == "smg" else 34.0)
		canvas.draw_line(position + Vector2(0, -5), position + Vector2(0, -5) + aim * gun_length, Color("d8e1e3"), 6)
		canvas.draw_rect(Rect2(position + Vector2(-22, -37), Vector2(44, 4)), Color("34414d"))
		canvas.draw_rect(Rect2(position + Vector2(-22, -37), Vector2(44 * float(player.hp) / 100.0, 4)), color)
		canvas.draw_string(font, position + Vector2(-70, -46), player.display_name + (" · 你" if own else ""), HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color("eef3f5"))
	canvas.draw_string(font, Vector2(28, 526), "整局完成后获得金币    ·    利用平台与掩体    ·    死亡后可以解锁、选择武器", HORIZONTAL_ALIGNMENT_LEFT, 905, 14, Color("9cadbb"))
