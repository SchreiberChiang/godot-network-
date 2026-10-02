extends SceneTree
## Body-presentation acceptance with real game objects and synthetic snapshots.
## No sockets, rooms, renderer, accounts, or wall-clock sleeps are needed.
const Game = preload("res://examples/shooter/game.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const EPSILON := 0.0001
var cases := 0
var passed := 0
var failed := 0
var _nodes: Array = []

func _initialize() -> void:
	_test_initial_and_fallback()
	_test_steady_twenty_hz()
	_test_jitter_bounds()
	_test_rolling_window()
	_test_cadence_stall_boundary()
	_test_duplicate_old_invalid()
	_test_repeated_packets_do_not_mask_stall()
	_test_unchanged_target()
	_test_reversal_continuity()
	_test_stop_start()
	_test_jump_and_landing_samples()
	_test_life_transitions()
	_test_same_tick_lifecycle()
	_test_teleport_boundary()
	_test_lag_is_not_teleport()
	_test_departure_and_rejoin()
	_test_room_resynchronization()
	_test_round_reset()
	_test_shot_deduplication_and_expiry()
	_test_aim_and_local_frame_compatibility()
	_test_presentation_isolation()
	_release_nodes()
	print("MOVEMENT_PRESENTATION_RESULT cases=", cases, " passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _finalize() -> void:
	_release_nodes()

func _new_game(is_server := false):
	var world = Game.new()
	world.server = is_server
	_nodes.append(world)
	return world

func _fixture() -> Dictionary:
	var authority = _new_game(true)
	authority.admit({"user_id": "u1", "display_name": "Local"}, 2)
	authority.admit({"user_id": "u2", "display_name": "Remote"}, 3)
	authority.advance(0)
	authority.players.u1.position = Vector2(120, 478)
	authority.players.u2.position = Vector2(780, 478)
	authority.players.u1.aim = Vector2.RIGHT
	authority.players.u2.aim = Vector2.RIGHT
	var client = _new_game()
	_send(client, authority.state_snapshot())
	return {"authority": authority, "client": client}

func _next_packet(fixture: Dictionary) -> Dictionary:
	fixture.authority.tick += 1
	return fixture.authority.state_snapshot()

func _send(client, packet: Dictionary) -> void:
	var error := Validator.validate_file(packet, "res://schemas/shooter_state.schema.json")
	_check(error == "", "synthetic snapshot obeys shooter state schema: " + error)
	if error == "":
		client.world_state(packet)

func _position(client, user := "u2") -> Vector2:
	return client.render_position(client.player_view(user))

func _aim(client, user := "u2", own_user := "") -> Vector2:
	return client.render_aim(client.player_view(user), own_user)

func _duration(client, user := "u2") -> float:
	return float(client.render_tracks[user].duration)

func _near(actual: Vector2, expected: Vector2, tolerance := EPSILON) -> bool:
	return actual.is_finite() and actual.distance_to(expected) <= tolerance

func _close(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual - expected) <= EPSILON

func _inside_segment_bounds(point: Vector2, from: Vector2, to: Vector2) -> bool:
	return point.is_finite() and point.x >= minf(from.x, to.x) - EPSILON and point.x <= maxf(from.x, to.x) + EPSILON and point.y >= minf(from.y, to.y) - EPSILON and point.y <= maxf(from.y, to.y) + EPSILON

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("MOVEMENT_PRESENTATION_FAIL " + label)

func _release_nodes() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()

func _test_initial_and_fallback() -> void:
	cases += 1
	var client = _new_game()
	_check(_near(client.render_position({"user_id": "unseen", "x": 42.0, "y": 123.0}), Vector2(42, 123)), "missing track falls back to supplied authoritative position")
	var fixture := _fixture()
	_check(_near(_position(fixture.client), Vector2(780, 478)), "first snapshot snaps to initial authoritative position")
	_check(_close(_duration(fixture.client), 0.05), "initial body duration is 50 ms")

func _test_steady_twenty_hz() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var durations_ok := true
	var progress_ok := true
	for packet_index in 10:
		if packet_index == 0:
			client.advance_visual(0.05)
		var from := _position(client)
		fixture.authority.players.u2.position.x -= 12.0
		var target: Vector2 = fixture.authority.players.u2.position
		_send(client, _next_packet(fixture))
		durations_ok = durations_ok and _close(_duration(client), 0.05)
		progress_ok = progress_ok and _near(_position(client), from)
		for frame in 6:
			client.advance_visual(1.0 / 120.0)
			progress_ok = progress_ok and _near(_position(client), from.lerp(target, float(frame + 1) / 6.0))
		progress_ok = progress_ok and _near(_position(client), target)
	_check(durations_ok, "steady 20 Hz packets retain a 50 ms body duration")
	_check(progress_ok, "steady body motion is continuous and linear at 120 Hz and reaches each confirmed target")
	_check(client._position_intervals.size() == 6, "steady cadence retains no more than six progress intervals")

func _test_jitter_bounds() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var expected := [0.07, 0.1, 0.1, 0.1]
	var intervals := [0.07, 0.12, 0.2, 0.03]
	for index in intervals.size():
		client.advance_visual(intervals[index])
		fixture.authority.players.u2.position.x -= 10.0
		_send(client, _next_packet(fixture))
		_check(_close(_duration(client), expected[index]), "recent arrival jitter selects bounded body duration at interval " + str(intervals[index]))
		_check(_duration(client) >= 0.05 and _duration(client) <= 0.1, "adaptive duration stays inside 50–100 ms")
	client.advance_visual(0.1)
	_check(_near(_position(client), fixture.authority.players.u2.position), "jitter-extended body still converges by 100 ms")

func _test_rolling_window() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x -= 10.0
	_send(client, _next_packet(fixture))
	_check(_close(_duration(client), 0.1), "100 ms arrival establishes the jitter high-water duration")
	for index in 6:
		client.advance_visual(0.05)
		fixture.authority.players.u2.position.x -= 10.0
		_send(client, _next_packet(fixture))
		var expected := 0.1 if index < 5 else 0.05
		_check(_close(_duration(client), expected), "old jitter drains after six strict-progress arrivals, sample " + str(index + 1))
	_check(client._position_intervals.size() == 6, "rolling cadence window is bounded after jitter drains")

func _test_cadence_stall_boundary() -> void:
	cases += 1
	for age in [0.249, 0.25, 0.8]:
		var fixture := _fixture()
		var client = fixture.client
		client.advance_visual(0.1)
		fixture.authority.players.u2.position.x -= 10.0
		_send(client, _next_packet(fixture))
		client.advance_visual(age)
		fixture.authority.players.u2.position.x -= 10.0
		_send(client, _next_packet(fixture))
		_check(_close(_duration(client), 0.1 if age < 0.25 else 0.05), "250 ms stale-cadence boundary respected at " + str(age))
		if age >= 0.25:
			_check(client._position_intervals.is_empty(), "stale arrival clears the old cadence rather than appending a stall")

func _test_duplicate_old_invalid() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var old: Dictionary = client.latest.duplicate(true)
	client.advance_visual(0.08)
	fixture.authority.players.u2.position.x -= 40.0
	var packet := _next_packet(fixture)
	_send(client, packet)
	client.advance_visual(0.03)
	var position_before := _position(client)
	var track_before: Dictionary = client.render_tracks.u2.duplicate(true)
	var intervals_before: Array = client._position_intervals.duplicate()
	_send(client, packet.duplicate(true))
	_send(client, old)
	var invalid := packet.duplicate(true)
	invalid.tick += 20
	invalid.players[1].x = 0.0
	_check(Validator.validate_file(invalid, "res://schemas/shooter_state.schema.json") != "", "invalid packet fixture is rejected by schema")
	client.world_state(invalid)
	_check(client.latest == packet and client.render_tracks.u2 == track_before, "duplicate, old, and invalid packets cannot restart or replace a position track")
	_check(_near(_position(client), position_before), "duplicate, old, and invalid receipt preserves displayed position")
	_check(client._position_intervals == intervals_before and _close(client._position_arrival_age, 0.03), "nonprogress packets do not append cadence samples or erase arrival age")
	client.advance_visual(0.05)
	_check(_near(_position(client), Vector2(740, 478)), "nonprogress packets do not delay original transition completion")
	fixture.authority.players.u2.position.x -= 10.0
	_send(client, _next_packet(fixture))
	_check(_close(_duration(client), 0.08), "next progress interval includes time spent receiving duplicate, old, and invalid packets")

func _test_repeated_packets_do_not_mask_stall() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x -= 10.0
	var packet := _next_packet(fixture)
	_send(client, packet)
	client.advance_visual(0.125)
	_send(client, packet.duplicate(true))
	client.advance_visual(0.125)
	_send(client, packet.duplicate(true))
	fixture.authority.players.u2.position.x -= 10.0
	_send(client, _next_packet(fixture))
	_check(_close(_duration(client), 0.05) and client._position_intervals.is_empty(), "duplicate snapshots cannot disguise a 250 ms gap in tick progress")

func _test_unchanged_target() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x -= 40.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.03)
	var before: Dictionary = client.render_tracks.u2.duplicate(true)
	_send(client, _next_packet(fixture))
	_check(client.render_tracks.u2 == before, "newer tick with unchanged position preserves from, target, age, and duration")
	client.advance_visual(0.07)
	_check(_near(_position(client), Vector2(740, 478)), "unchanged newer target cannot postpone completion")

func _test_reversal_continuity() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x = 740.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.025)
	var before := _position(client)
	fixture.authority.players.u2.position.x = 800.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), before), "mid-transition reversal starts exactly at the currently displayed position")
	client.advance_visual(0.05)
	_check(_near(_position(client), before.lerp(Vector2(800, 478), 0.5)), "reversal advances smoothly toward the new target")
	client.advance_visual(0.05)
	_check(_near(_position(client), Vector2(800, 478)), "reversed movement converges within its bounded duration")

func _test_stop_start() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x = 750.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.035)
	_send(client, _next_packet(fixture))
	client.advance_visual(0.065)
	_check(_near(_position(client), Vector2(750, 478)), "stop reaches the most recent confirmed point without asymptotic drift")
	client.advance_visual(0.5)
	_check(_near(_position(client), Vector2(750, 478)), "stopped body neither extrapolates nor overshoots when snapshots pause")
	fixture.authority.players.u2.position.x = 770.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(750, 478)) and _close(_duration(client), 0.05), "restart after idle is continuous with fresh 50 ms cadence")
	client.advance_visual(0.025)
	_check(_near(_position(client), Vector2(760, 478)), "restart exposes a finite intermediate position")
	client.advance_visual(0.025)
	_check(_near(_position(client), Vector2(770, 478)), "restart reaches its target in finite time")

func _test_jump_and_landing_samples() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var heights := [455.0, 432.0, 412.0, 397.0, 388.0, 392.0, 410.0, 438.0, 478.0]
	var gaps := [0.033, 0.075, 0.02, 0.065, 0.05, 0.09, 0.03, 0.05, 0.075]
	var continuous := true
	var bounded := true
	for index in heights.size():
		var gap: float = gaps[index]
		for frame in 6:
			client.advance_visual(gap / 6.0)
		var from := _position(client)
		fixture.authority.players.u2.position = Vector2(780 + index * 4, heights[index])
		var target: Vector2 = fixture.authority.players.u2.position
		_send(client, _next_packet(fixture))
		continuous = continuous and _near(_position(client), from)
		for frame in 3:
			client.advance_visual(0.001)
			bounded = bounded and _inside_segment_bounds(_position(client), from, target)
	_check(continuous, "jump apex, descent, and landing samples preserve receipt continuity")
	_check(bounded, "jump and landing presentation remains finite and bounded by confirmed segment endpoints")
	client.advance_visual(0.1)
	_check(_near(_position(client), fixture.authority.players.u2.position), "landing converges to the authoritative floor position")
	client.advance_visual(0.3)
	_check(_close(_position(client).y, 478.0), "paused landing does not predict below the floor")

func _test_life_transitions() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.position.x = 760.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.players.u2.life_state = "dead"
	fixture.authority.players.u2.hp = 0
	fixture.authority.players.u2.deaths = 1
	fixture.authority.players.u2.position.x = 750.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(750, 478)), "death snaps an interrupted body transition at a nearby position")
	fixture.authority.players.u2.life_state = "alive"
	fixture.authority.players.u2.hp = 100
	fixture.authority.players.u2.position.x = 790.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(790, 478)), "respawn snaps immediately even without a teleport-sized displacement")
	fixture.authority.players.u2.position.x = 770.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.players.u2.deaths = 2
	fixture.authority.players.u2.position.x = 780.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(780, 478)), "raised deaths counter resets an alive body when the dead snapshot was missed")
	_check(int(client.render_tracks.u2.deaths) == 2, "position track retains current lifecycle counter")

func _test_same_tick_lifecycle() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var initial_tick: int = client.latest.tick
	client.advance_visual(0.04)
	fixture.authority.players.u2.position.x = 760.0
	fixture.authority.players.u2.life_state = "dead"
	fixture.authority.players.u2.hp = 0
	fixture.authority.players.u2.deaths = 1
	_send(client, fixture.authority.state_snapshot())
	_check(_near(_position(client), Vector2(760, 478)), "same-tick death publication resets body immediately")
	client.advance_visual(0.04)
	fixture.authority.players.u2.position.x = 790.0
	fixture.authority.players.u2.life_state = "alive"
	fixture.authority.players.u2.hp = 100
	_send(client, fixture.authority.state_snapshot())
	_check(int(client.latest.tick) == initial_tick and _near(_position(client), Vector2(790, 478)), "same-tick respawn publication is accepted and snapped")
	_check(client._position_intervals.is_empty() and _close(client._position_arrival_age, 0.08), "same-tick lifecycle packets preserve strict-progress arrival age")
	fixture.authority.players.u2.position.x = 780.0
	_send(client, _next_packet(fixture))
	_check(_close(_duration(client), 0.08), "next progress packet measures the whole same-tick lifecycle interval")

func _test_teleport_boundary() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.position.x = 680.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(780, 478)), "exactly 100 pixels retains the ordinary interpolation path")
	client.advance_visual(0.025)
	_check(_near(_position(client), Vector2(730, 478)), "exactly 100-pixel displacement has a smooth midpoint")
	fixture.authority.players.u2.position.x = 579.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(579, 478)), "101-pixel consecutive authoritative displacement snaps immediately")

func _test_lag_is_not_teleport() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.position.x = 690.0
	_send(client, _next_packet(fixture))
	fixture.authority.players.u2.position.x = 600.0
	_send(client, _next_packet(fixture))
	_check(_near(_position(client), Vector2(780, 478)), "180-pixel display backlog is not a teleport when consecutive authoritative steps are 90 pixels")
	client.advance_visual(0.025)
	_check(_near(_position(client), Vector2(690, 478)), "large display backlog still interpolates rather than triggering a false snap")
	client.advance_visual(0.025)
	_check(_near(_position(client), Vector2(600, 478)), "lagged body reaches the newest confirmed position")

func _test_departure_and_rejoin() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.position.x = 750.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.remove_player("u2")
	_send(client, fixture.authority.state_snapshot())
	_check(not client.render_tracks.has("u2") and client.player_view("u2").is_empty(), "same-tick departure removes the old body track")
	_check(client.render_tracks.has("u1"), "departure retains the remaining player's body track")
	fixture.authority.admit({"user_id": "u2", "display_name": "Rejoined"}, 3)
	fixture.authority.players.u2.position = Vector2(820, 478)
	_send(client, fixture.authority.state_snapshot())
	_check(_near(_position(client), Vector2(820, 478)), "same-tick rejoin initializes fresh without departed movement history")
	_check(client.render_tracks.size() == 2, "rejoin retains exactly the current player tracks")

func _test_room_resynchronization() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.tick += 20
	fixture.authority.players.u2.position.x = 750.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	client.set_local_aim("u1", Vector2.UP)
	client.latest.clear()
	fixture.authority.tick = 0
	fixture.authority.players.u2.position = Vector2(760, 450)
	_send(client, fixture.authority.state_snapshot())
	_check(int(client.latest.tick) == 0 and _near(_position(client), Vector2(760, 450)), "cleared room accepts lower tick and snaps to its new authoritative position")
	_check(client._position_intervals.is_empty() and _close(_duration(client), 0.05), "room resynchronization discards stale cadence and restores 50 ms duration")
	_check(_near(_aim(client, "u1", "u1"), Vector2.RIGHT), "room reset clears the prior local aim override")
	client.advance_visual(0.05)
	fixture.authority.players.u2.position.x = 770.0
	_send(client, _next_packet(fixture))
	_check(_close(_duration(client), 0.05), "new room cadence uses only progress since its own first snapshot")

func _test_round_reset() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x = 750.0
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.round_number += 1
	fixture.authority.players.u2.position.x = 760.0
	_send(client, fixture.authority.state_snapshot())
	_check(_near(_position(client), Vector2(760, 478)), "same-tick new round snaps a nearby position without old body interpolation")
	_check(client._position_intervals.is_empty() and _close(_duration(client), 0.05), "round transition clears body cadence")
	_check(_close(client._position_arrival_age, 0.0), "new round starts its arrival clock at receipt")

func _test_shot_deduplication_and_expiry() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var shot := {"id": 1, "at": 0, "x": 100.0, "y": 200.0, "end_x": 170.0, "end_y": 200.0, "weapon": "rifle"}
	fixture.authority.shots = [shot]
	var packet := _next_packet(fixture)
	_send(client, packet)
	_send(client, packet.duplicate(true))
	_check(client.visual_shots.size() == 1 and client.last_visual_shot == 1, "duplicate shot publication creates one visual tracer")
	client.advance_visual(0.049)
	_check(client.visual_shots.size() == 1, "tracer remains until travel duration plus expiry margin")
	client.advance_visual(0.002)
	_check(client.visual_shots.is_empty(), "tracer expires after travel duration plus 40 ms")
	_send(client, _next_packet(fixture))
	_check(client.visual_shots.is_empty(), "expired shot IDs do not revive in newer snapshots")
	var second := shot.duplicate(true)
	second.id = 2
	fixture.authority.shots = [shot, second]
	_send(client, _next_packet(fixture))
	_check(client.visual_shots.size() == 1 and client.last_visual_shot == 2, "new shot ID renders once alongside an already-seen shot")
	var stale := packet.duplicate(true)
	stale.shots[0].id = 50
	_send(client, stale)
	_check(client.visual_shots.size() == 1 and client.last_visual_shot == 2, "old packet cannot inject a newer-looking shot ID")
	client.latest.clear()
	fixture.authority.tick = 0
	fixture.authority.shots = [shot]
	_send(client, fixture.authority.state_snapshot())
	_check(client.visual_shots.size() == 1 and client.last_visual_shot == 1, "new room resets tracer history and accepts its own low shot IDs")

func _test_aim_and_local_frame_compatibility() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.advance_visual(0.1)
	fixture.authority.players.u2.position.x = 740.0
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	var local_responsive := true
	for frame in 6:
		var direction := Vector2.from_angle(float(frame) * 0.2)
		client.set_local_aim("u1", direction)
		local_responsive = local_responsive and _near(_aim(client, "u1", "u1"), direction)
		client.advance_visual(1.0 / 120.0)
	_check(local_responsive, "local gun still accepts every 120 Hz sample while the body uses adaptive smoothing")
	_check(_near(_aim(client), Vector2.UP), "remote aim remains on its original 50 ms convergence path")
	_check(_near(_position(client), Vector2(760, 478)) and _close(_duration(client), 0.1), "50 ms aim completion does not accelerate the 100 ms body transition")
	client.advance_visual(0.05)
	_check(_near(_position(client), Vector2(740, 478)) and _near(_aim(client), Vector2.UP), "body and gun both settle to their own confirmed targets")

func _test_presentation_isolation() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var authority = fixture.authority
	authority.players.u2.position.x = 750.0
	var packet := _next_packet(fixture)
	var packet_before := packet.duplicate(true)
	var server_players: Dictionary = authority.players.duplicate(true)
	var server_latest: Dictionary = authority.latest.duplicate(true)
	_send(client, packet)
	for frame in 24:
		client.set_local_aim("u1", Vector2.from_angle(float(frame) * 0.11))
		client.advance_visual(1.0 / 120.0)
		_position(client)
		_aim(client)
	_check(packet == packet_before and client.latest == packet_before, "presentation never rewrites caller packet or accepted authoritative snapshot")
	_check(authority.players == server_players and authority.latest == server_latest, "client presentation leaves server simulation state and published snapshot untouched")
	var rejected := packet.duplicate(true)
	rejected.players[1].x = 800.0
	authority.world_state(rejected)
	authority.set_local_aim("u1", Vector2.DOWN)
	_check(authority.players == server_players and authority.latest == server_latest, "server rejects client snapshot and local presentation overrides")
	_check(authority.render_tracks.is_empty() and authority.aim_tracks.is_empty(), "server does not accumulate client position or aim tracks")
