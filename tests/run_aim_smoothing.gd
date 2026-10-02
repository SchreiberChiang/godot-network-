extends "res://examples/framework/client.gd"
## Deterministic production presentation + input-shell checks. No real network/UI.
const Shooter = preload("res://examples/shooter/game.gd")
const Turns = preload("res://examples/turn_based/game.gd")
var passed := 0
var failed := 0

class PointerView:
	extends RefCounted
	const ARENA_POSITION := Vector2(28, 164)
	var pointer := Vector2.ZERO
	func get_local_mouse_position() -> Vector2:
		return pointer + ARENA_POSITION

class AimSpy:
	extends Node
	var presentation = preload("res://examples/shooter/game.gd").new()
	var latest: Dictionary:
		get: return presentation.latest
	var commands: Array = []
	var visual_samples := 0
	func send_input(move: float, jump: bool, aim: Vector2, fire: bool) -> void:
		commands.append({"move": move, "jump": jump, "aim": aim, "fire": fire})
	func set_local_visual_aim(user: String, aim: Vector2) -> void:
		visual_samples += 1
		presentation.set_local_visual_aim(user, aim)
	func player_view(user: String) -> Dictionary:
		return presentation.player_view(user)
	func world_state(value: Dictionary) -> void:
		presentation.world_state(value)
	func render_aim(player: Dictionary) -> Vector2:
		return presentation.render_aim(player)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			presentation.free()

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	return false

func _run() -> void:
	_remote_tracks()
	_lifecycle()
	_local_and_shots()
	_shell_sampling()
	_sampling_rates()
	_turn_latency()
	print("AIM_SMOOTHING_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _source():
	var source = Shooter.new()
	source.server = true
	source.admit({"user_id": "u1", "display_name": "Aim test"}, 2)
	source.players.u1.position = Vector2(300, 220)
	return source

func _send(source, target, degrees: float) -> Dictionary:
	source.players.u1.aim = Vector2.from_angle(deg_to_rad(degrees))
	source.tick += 3
	var value: Dictionary = source.state_snapshot()
	target.world_state(value)
	return target.player_view("u1")

func _near(direction: Vector2, degrees: float, tolerance := 0.001) -> bool:
	return absf(rad_to_deg(angle_difference(direction.angle(), deg_to_rad(degrees)))) < tolerance and absf(direction.length() - 1.0) < 0.00001

func _remote_tracks() -> void:
	var source = _source()
	var target = Shooter.new()
	var row := _send(source, target, 0)
	_check(_near(target.render_aim(row), 0), "first observation snaps to authoritative angle")
	row = _send(source, target, 90)
	_check(_near(target.render_aim(row), 0), "remote 90 degree turn starts at currently displayed angle")
	for frame in 6:
		target.advance_visual(1.0 / 120.0)
		_check(_near(target.render_aim(row), 15.0 * (frame + 1)), "120 Hz remote turn advances each frame %d" % frame)
	target.advance_visual(1.0)
	_check(_near(target.render_aim(row), 90), "network gap freezes on endpoint without extrapolation")
	row = _send(source, target, 179)
	target.advance_visual(0.05)
	row = _send(source, target, -179)
	target.advance_visual(0.025)
	_check(_near(target.render_aim(row), 180), "positive angle boundary takes 2 degree arc")
	target.advance_visual(0.025)
	row = _send(source, target, 179)
	target.advance_visual(0.025)
	_check(_near(target.render_aim(row), 180), "negative angle boundary takes 2 degree arc")
	target.advance_visual(0.05)
	row = _send(source, target, 0)
	target.advance_visual(0.05)
	row = _send(source, target, 180)
	target.advance_visual(0.025)
	_check(absf(absf(rad_to_deg(target.render_aim(row).angle())) - 90.0) < 0.001, "exact opposite aim stays unit length and takes a half turn")
	var before: Vector2 = target.render_aim(row)
	row = _send(source, target, -45)
	_check(before.is_equal_approx(target.render_aim(row)), "rapid reversal retargets continuously from displayed angle")
	target.advance_visual(0.01)
	var age: float = target.aim_tracks.u1.age
	row = _send(source, target, -45)
	target.world_state(target.latest.duplicate(true))
	_check(is_equal_approx(target.aim_tracks.u1.age, age), "unchanged and repeated angle snapshots do not restart blend")
	var stale: Dictionary = target.latest.duplicate(true)
	stale.tick -= 1
	stale.players[0].aim_x = 1
	stale.players[0].aim_y = 0
	target.world_state(stale)
	_check(target.latest.tick > stale.tick and is_equal_approx(target.aim_tracks.u1.age, age), "stale snapshot cannot replace an aim target")
	source.players.u1.position.x += 12
	row = _send(source, target, 30)
	target.advance_visual(0.025)
	var position_age: float = target.render_tracks.u1.age
	row = _send(source, target, 60)
	_check(is_equal_approx(target.render_tracks.u1.age, position_age), "turning alone does not restart existing position blend")
	_check(is_equal_approx(target.render_position(row).x, 306), "existing position interpolation remains unchanged")
	for fps in [30, 60, 120, 240]:
		row = _send(source, target, -80)
		target.advance_visual(0.05)
		row = _send(source, target, 80)
		for frame in ceili(0.05 * fps):
			target.advance_visual(1.0 / fps)
		_check(_near(target.render_aim(row), 80), "%d FPS blend reaches endpoint without frame-rate-dependent tail" % fps)
	target.free()
	source.free()

func _lifecycle() -> void:
	var source = _source()
	var target = Shooter.new()
	var row := _send(source, target, 0)
	target.set_local_visual_aim("u1", Vector2.UP)
	source.players.u1.life_state = "dead"
	source.players.u1.hp = 0
	source.players.u1.deaths += 1
	row = _send(source, target, 90)
	_check(target.local_visual_user == "" and _near(target.render_aim(row), 90), "death clears local override and snaps remote aim")
	target.set_local_visual_aim("u1", Vector2.LEFT)
	_check(target.local_visual_user == "", "dead player cannot acquire a local override")
	source.players.u1.life_state = "alive"
	source.players.u1.hp = 100
	row = _send(source, target, -90)
	_check(_near(target.render_aim(row), -90), "respawn snaps without blending old life angle")
	target.set_local_visual_aim("u1", Vector2.LEFT)
	source.players.u1.deaths += 1
	row = _send(source, target, 45)
	_check(target.local_visual_user == "" and _near(target.render_aim(row), 45), "missed death packet still resets on changed death count")
	source.players.u1.position.x += 200
	row = _send(source, target, 130)
	_check(_near(target.render_aim(row), 130), "teleport resets angle along with existing position snap")
	target.set_local_visual_aim("u1", Vector2.UP)
	var missing: Dictionary = source.state_snapshot()
	missing.tick += 3
	missing.players = []
	target.world_state(missing)
	_check(target.aim_tracks.is_empty() and target.local_visual_user == "", "player removal clears angle and local state")
	source.tick = missing.tick
	row = _send(source, target, 12)
	_check(_near(target.render_aim(row), 12), "returning player starts from fresh snapshot")
	target.set_local_visual_aim("u1", Vector2.UP)
	target.latest.clear()
	source.tick = 0
	row = _send(source, target, -12)
	_check(target.local_visual_user == "" and _near(target.render_aim(row), -12), "room reset accepts lower tick and clears all old aim history")
	target.free()
	source.free()

func _local_and_shots() -> void:
	var source = _source()
	var target = Shooter.new()
	var row := _send(source, target, 0)
	var frozen: Dictionary = target.latest.duplicate(true)
	for degrees in [5, 80, 179, -179, -45, 180, 0]:
		var intended := Vector2.from_angle(deg_to_rad(degrees))
		target.set_local_visual_aim("u1", intended * 300)
		_check(_near(target.render_aim(row), degrees), "local fast turn %d is immediate and normalized" % degrees)
	_check(target.latest == frozen and source.players.u1.aim == Vector2.RIGHT, "local display cannot change snapshot or authority")
	target.set_local_visual_aim("u1", Vector2.ZERO)
	_check(target.render_aim(row) == Vector2.RIGHT, "zero local aim uses identical input-command fallback")
	target.set_local_visual_aim("u1", Vector2(NAN, 0))
	_check(target.local_visual_user == "", "non-finite local sample is discarded")
	source.set_local_visual_aim("u1", Vector2.DOWN)
	_check(source.local_visual_user == "", "server ignores presentation setter")
	var aim := Vector2.from_angle(deg_to_rad(-35))
	var command := {"sequence": 1, "move": 0.0, "jump": false, "fire": true, "aim_x": aim.x, "aim_y": aim.y}
	_check(source.handle_input(2, command, 1000), "unchanged input schema accepts intended direction")
	source._fire(source.players.u1, 1000)
	row = _send(source, target, -35)
	target.set_local_visual_aim("u1", aim)
	var shot: Dictionary = source.shots.back()
	var shot_origin := Vector2(shot.x, shot.y)
	var shot_end := Vector2(shot.end_x, shot.end_y)
	var actual := shot_origin.direction_to(shot_end)
	var error := absf(rad_to_deg(target.render_aim(row).angle_to(actual)))
	_check(error < 0.001, "stationary rifle muzzle and processed shot direction agree below 0.001 degree")
	var pivot: Vector2 = target.render_position(row) + Vector2(0, -5)
	_check(pivot.is_equal_approx(shot_origin), "stationary gun pivot equals authoritative shot origin")
	var muzzle_tip_gap := (pivot + target.render_aim(row) * 29.0).distance_to(shot_origin)
	_check(is_equal_approx(muzzle_tip_gap, 29.0), "drawn rifle muzzle tip is intentionally 29px ahead of server ray origin")
	for weapon in ["smg", "shotgun"]:
		source.players.u1.weapon = weapon
		source.shots.clear()
		source._fire(source.players.u1, 2000)
		var maximum := 0.0
		for pellet in source.shots:
			var direction := Vector2(pellet.x, pellet.y).direction_to(Vector2(pellet.end_x, pellet.end_y))
			maximum = maxf(maximum, absf(aim.angle_to(direction)))
		var allowed: float = source.config.weapons[weapon].spread * (0.5 if weapon == "shotgun" else 1.0)
		_check(maximum > 0 and maximum <= allowed + 0.00001, "%s retains server-owned spread around visual aim" % weapon)
	target.set_local_visual_aim("u1", -aim)
	var transient := absf(rad_to_deg(target.render_aim(row).angle_to(actual)))
	_check(absf(transient - 180.0) < 0.001, "instant reversal exposes expected 180 degree transient vs older shot")
	_check(target.visual_shots.back().from == shot_origin and target.visual_shots.back().to == shot_end, "confirmed tracer retains exact server endpoints despite local turn")
	source.players.u1.weapon = "rifle"
	source.players.u1.position.x += 12
	row = _send(source, target, -35)
	var pivot_gap: float = (target.render_position(row) + Vector2(0, -5)).distance_to(source.players.u1.position + Vector2(0, -5))
	_check(is_equal_approx(pivot_gap, 12.0), "existing movement interpolation can offset current gun pivot by 12px in fixture")
	target.set_local_visual_aim("u1", aim)
	var moving_tip_gap: float = (target.render_position(row) + Vector2(0, -5) + target.render_aim(row) * 29.0).distance_to(source.players.u1.position + Vector2(0, -5))
	_check(moving_tip_gap > 17.0 and moving_tip_gap < 41.0, "moving muzzle-tip/ray-origin gap includes existing 12px position lag")
	print("AIM_ERROR_RESULT stationary_rifle_deg=", error, " delayed_reversal_deg=", transient, " stationary_muzzle_tip_gap_px=", muzzle_tip_gap, " moving_pivot_gap_px=", pivot_gap, " moving_muzzle_tip_gap_px=", moving_tip_gap)
	target.free()
	source.free()

func _shell_sampling() -> void:
	client = AccountClient.new()
	client.state = "IN_ROOM"
	client.identity = {"user_id": "u1"}
	view = PointerView.new()
	var source = _source()
	world = AimSpy.new()
	_send(source, world, 0)
	var initial: Dictionary = world.latest.duplicate(true)
	var matching := true
	for frame in 120:
		var direction := Vector2.from_angle(frame * TAU / 120.0)
		view.pointer = source.players.u1.position + direction * 250.0
		super._process(1.0 / 120.0)
		matching = matching and world.render_aim(world.player_view("u1")).is_equal_approx(direction)
		if (frame + 1) % 4 == 0:
			matching = matching and world.commands.back().aim.is_equal_approx(direction * 250.0)
	_check(world.visual_samples == 120 and matching, "production input shell samples local aim every 120Hz frame from exact input vector")
	_check(world.commands.size() == 30 and world.latest == initial, "production shell retains 30Hz command cadence and snapshot immutability")
	_check(world.commands.all(func(c): return c.move == 0 and not c.jump and not c.fire), "unfocused headless client still cannot move, jump or fire")
	world.free()
	world = Turns.new()
	super._process(1.0 / 30.0)
	_check(not world.has_method("player_view") and not world.has_method("send_input"), "optional shooter input path does not require aim API in turn-based game")
	world.free()
	world = null
	client.free()
	client = null
	view = null
	source.free()

func _sampling_rates() -> void:
	var source = _source()
	var local_view = Shooter.new()
	var remote_view = Shooter.new()
	var counts := {"raw": 0, "local": 0, "remote": 0}
	var previous := {"raw": Vector2.ZERO, "local": Vector2.ZERO, "remote": Vector2.ZERO}
	for frame in 240:
		var degrees := frame * 3.0
		local_view.advance_visual(1.0 / 120.0)
		remote_view.advance_visual(1.0 / 120.0)
		if frame % 6 == 0:
			_send(source, local_view, degrees)
			remote_view.world_state(local_view.latest.duplicate(true))
		local_view.set_local_visual_aim("u1", Vector2.from_angle(deg_to_rad(degrees)))
		var row: Dictionary = local_view.player_view("u1")
		var values := {"raw": Vector2(row.aim_x, row.aim_y), "local": local_view.render_aim(row), "remote": remote_view.render_aim(remote_view.player_view("u1"))}
		for key in counts:
			if frame >= 120 and not values[key].is_equal_approx(previous[key]):
				counts[key] += 1
			previous[key] = values[key]
	_check(counts.raw == 20 and counts.local == 120 and counts.remote == 120, "synthetic steady turn: 20 raw snapshot updates become 120 local and remote display updates")
	print("AIM_RATE_RESULT synthetic_fps=120 raw_snapshot_updates=", counts.raw, " local_updates=", counts.local, " remote_updates=", counts.remote)
	local_view.free()
	remote_view.free()
	source.free()

func _turn_latency() -> void:
	# Discrete synthetic delivery, not an ENet latency measurement. Exercise the
	# unchanged 60Hz authority/cooldown with 30Hz commands and 20Hz snapshots.
	for one_way_frames in [0, 6]:
		var source = _source()
		source.admit({"user_id": "u2", "display_name": "Target"}, 3)
		source.players.u1.position = Vector2(300, 478)
		source.players.u2.position = Vector2(850, 478)
		var target = Shooter.new()
		target.world_state(source.state_snapshot())
		var pending_inputs: Array = []
		var pending_states: Array = []
		var sequence_id := 0
		var seen_shot := 0
		var generated_shot := 0
		var same_time_error := 0.0
		var received_error := 0.0
		var same_time_samples := 0
		var received_samples := 0
		for frame in 480:
			var now := roundi(frame * 1000.0 / 120.0)
			var aim := Vector2.from_angle(deg_to_rad(frame * 6.0)) # 720 deg/s
			target.advance_visual(1.0 / 120.0)
			if frame % 4 == 1:
				sequence_id += 1
				pending_inputs.append({"due": frame + one_way_frames, "command": {"sequence": sequence_id, "move": 0.0, "jump": false, "fire": true, "aim_x": aim.x, "aim_y": aim.y}})
			while not pending_inputs.is_empty() and pending_inputs[0].due <= frame:
				source.handle_input(2, pending_inputs.pop_front().command, now)
			if frame % 2 == 0:
				source.advance(now)
				for shot in source.shots:
					if shot.id > generated_shot:
						generated_shot = shot.id
						if frame >= 120:
							var direction := Vector2(shot.x, shot.y).direction_to(Vector2(shot.end_x, shot.end_y))
							same_time_error = maxf(same_time_error, absf(rad_to_deg(aim.angle_to(direction))))
							same_time_samples += 1
			if frame % 6 == 0:
				pending_states.append({"due": frame + one_way_frames, "value": source.state_snapshot()})
			while not pending_states.is_empty() and pending_states[0].due <= frame:
				var value: Dictionary = pending_states.pop_front().value
				target.world_state(value)
				for shot in value.shots:
					if shot.id > seen_shot:
						seen_shot = shot.id
						if frame >= 120:
							var direction := Vector2(shot.x, shot.y).direction_to(Vector2(shot.end_x, shot.end_y))
							received_error = maxf(received_error, absf(rad_to_deg(aim.angle_to(direction))))
							received_samples += 1
			target.set_local_visual_aim("u1", aim)
		var bound: float = 24.01 + one_way_frames * 6.0
		_check(same_time_samples > 8 and same_time_error > 1.0 and same_time_error <= bound, "720deg/s with %dms one-way: live displayed aim differs from same-time server shot within sampling bound" % roundi(one_way_frames * 1000.0 / 120.0))
		_check(received_samples > 8 and received_error >= same_time_error, "snapshot batching/delivery adds age to first displayed confirmed tracer")
		print("AIM_TIMING_RESULT synthetic_turn_deg_per_s=720 one_way_ms=", one_way_frames * 1000.0 / 120.0, " same_time_shot_max_deg=", same_time_error, " first_received_tracer_max_deg=", received_error, " shot_samples=", same_time_samples, " tracer_samples=", received_samples)
		target.free()
		source.free()

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)
