extends SceneTree
## Presentation acceptance with real game objects and valid synthetic snapshots.
## No sockets, room processes, accounts or renderer are started by this runner.
const Game = preload("res://examples/shooter/game.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const EPSILON := 0.0001
var cases := 0
var passed := 0
var failed := 0
var _nodes: Array = []

func _initialize() -> void:
	var probe = _new_game()
	_check(probe.has_method("set_local_aim") and probe.has_method("render_aim"), "aim presentation API exists")
	if failed == 0:
		_test_fallback()
		_test_local_frame_rate()
		_test_local_identity()
		_test_invalid_local_input()
		_test_remote_convergence()
		_test_wraparound()
		_test_retarget_continuity()
		_test_unchanged_target()
		_test_duplicate_and_old_ticks()
		_test_same_tick_lifecycle()
		_test_life_transitions()
		_test_round_reset()
		_test_teleport_reset()
		_test_departure_and_rejoin()
		_test_server_rejection()
	_release_nodes()
	print("AIM_PRESENTATION_RESULT cases=", cases, " passed=", passed, " failed=", failed)
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

func _aim(client, user := "u2", own_user := "") -> Vector2:
	return client.render_aim(client.player_view(user), own_user)

func _near(actual: Vector2, expected: Vector2, tolerance := EPSILON) -> bool:
	return actual.is_finite() and actual.distance_to(expected) <= tolerance

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("AIM_PRESENTATION_FAIL " + label)

func _release_nodes() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()

func _test_fallback() -> void:
	cases += 1
	var client = _new_game()
	var player := {"user_id": "unseen", "life_state": "alive", "aim_x": 0.0, "aim_y": -1.0}
	_check(client.latest.is_empty() and _near(client.render_aim(player), Vector2.UP), "no snapshot or aim track falls back to supplied player direction")
	_check(_near(client.render_aim(player, "unseen"), Vector2.UP), "own identity without a local sample still falls back safely")

func _test_local_frame_rate() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var before: Dictionary = client.latest.duplicate(true)
	var responsive := true
	# Twelve 120 Hz samples all arrive before any new server snapshot.
	for frame in 12:
		var direction := Vector2.from_angle(-1.4 + float(frame) * 0.21)
		client.set_local_aim("u1", direction)
		responsive = responsive and _near(_aim(client, "u1", "u1"), direction)
		client.advance_visual(1.0 / 120.0)
	_check(responsive, "local gun responds to every 120 Hz sample without waiting for a snapshot")
	_check(client.latest == before, "local direction and visual advancement do not rewrite authoritative snapshot fields")
	client.set_local_aim("u1", Vector2(3, 4))
	_check(_near(_aim(client, "u1", "u1"), Vector2(0.6, 0.8)), "local presentation normalizes finite non-unit input")
	_check(fixture.authority.players.u1.aim == Vector2.RIGHT, "client presentation never changes server aim")

func _test_local_identity() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.set_local_aim("u1", Vector2.UP)
	_check(_near(_aim(client, "u1", "u1"), Vector2.UP), "matching own player uses local direction")
	_check(_near(_aim(client, "u2", "u1"), Vector2.RIGHT), "another player never inherits local gun direction")
	_check(_near(_aim(client, "u1", "u2"), Vector2.RIGHT), "mismatched own identity does not grant local presentation")
	_check(_near(_aim(client, "u1"), Vector2.RIGHT), "default own identity keeps server presentation")
	client.set_local_aim("unknown", Vector2.DOWN)
	_check(_near(_aim(client, "u2", "unknown"), Vector2.RIGHT), "unadmitted identity cannot override a real player's gun")

func _test_invalid_local_input() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u1.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	client.advance_visual(0.05)
	client.set_local_aim("u1", Vector2.DOWN)
	client.set_local_aim("u1", Vector2.LEFT, false)
	_check(_near(_aim(client, "u1", "u1"), Vector2.UP), "inactive sample clears local presentation")
	client.set_local_aim("u1", Vector2.DOWN)
	client.set_local_aim("u1", Vector2.ZERO)
	_check(_near(_aim(client, "u1", "u1"), Vector2.RIGHT), "zero direction uses the same rightward fallback as send_input")
	client.set_local_aim("u1", Vector2(0, 0.000001))
	_check(_near(_aim(client, "u1", "u1"), Vector2.RIGHT), "tiny direction uses the same rightward fallback as send_input")
	client.set_local_aim("u1", Vector2.DOWN)
	client.set_local_aim("u1", Vector2(NAN, 1))
	_check(_near(_aim(client, "u1", "u1"), Vector2.UP), "NaN direction clears local presentation instead of poisoning render output")
	client.set_local_aim("u1", Vector2.DOWN)
	client.set_local_aim("u1", Vector2(1, INF))
	_check(_near(_aim(client, "u1", "u1"), Vector2.UP), "infinite direction clears local presentation")

func _test_remote_convergence() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.RIGHT), "new remote direction begins at the currently displayed angle")
	var previous := 0.0
	var progressive := true
	for frame in 6:
		client.advance_visual(1.0 / 120.0)
		var direction := _aim(client)
		var angle := direction.angle()
		progressive = progressive and angle < previous and absf(direction.length() - 1.0) < EPSILON
		if frame == 2:
			_check(direction.distance_to(Vector2.RIGHT) > 0.1 and direction.distance_to(Vector2.UP) > 0.1, "25 ms remote direction is between the old and new aim")
		previous = angle
	_check(progressive, "remote gun turns progressively across 120 Hz frames with unit directions")
	_check(_near(_aim(client), Vector2.UP), "remote gun converges within 50 ms")
	client.advance_visual(1.0)
	_check(_near(_aim(client), Vector2.UP), "completed remote blend remains at its server target")

func _test_wraparound() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.from_angle(deg_to_rad(179.0))
	_send(client, _next_packet(fixture))
	client.advance_visual(0.05)
	fixture.authority.players.u2.aim = Vector2.from_angle(deg_to_rad(-179.0))
	_send(client, _next_packet(fixture))
	client.advance_visual(0.025)
	_check(_near(_aim(client), Vector2.LEFT, 0.01), "+179 to -179 degrees takes the short path through left")
	client.advance_visual(0.025)
	_check(_near(_aim(client), Vector2.from_angle(deg_to_rad(-179.0))), "wrapped remote target converges")
	fixture.authority.players.u2.aim = Vector2.from_angle(deg_to_rad(179.0))
	_send(client, _next_packet(fixture))
	client.advance_visual(0.025)
	_check(_near(_aim(client), Vector2.LEFT, 0.01), "-179 to +179 degrees also takes the short path")

func _test_retarget_continuity() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	var before := _aim(client)
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), before), "mid-blend target reversal preserves the displayed angle at receipt")
	client.advance_visual(0.01)
	var after := _aim(client)
	_check(after.distance_to(Vector2.UP) < before.distance_to(Vector2.UP) and after.distance_to(before) > 0.01, "new target starts moving from the interrupted visual direction")
	client.advance_visual(0.04)
	_check(_near(_aim(client), Vector2.UP), "retargeted gun converges 50 ms after the newest direction")

func _test_unchanged_target() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.025)
	var before := _aim(client)
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), before), "a newer snapshot with unchanged aim preserves ongoing presentation")
	client.advance_visual(0.025)
	_check(_near(_aim(client), Vector2.DOWN), "unchanged aim in newer snapshots does not continually restart the 50 ms blend")

func _test_duplicate_and_old_ticks() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var old: Dictionary = client.latest.duplicate(true)
	fixture.authority.players.u2.aim = Vector2.DOWN
	var packet := _next_packet(fixture)
	_send(client, packet)
	client.advance_visual(0.025)
	var before := _aim(client)
	_send(client, packet.duplicate(true))
	_check(_near(_aim(client), before), "duplicate snapshot does not jump or restart the current aim")
	_send(client, old)
	_check(_near(_aim(client), before) and int(client.latest.tick) == int(packet.tick), "older snapshot cannot rewind the accepted aim timeline")
	client.advance_visual(0.025)
	_check(_near(_aim(client), Vector2.DOWN), "duplicate and old packets do not delay convergence or replace the target")

func _test_same_tick_lifecycle() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	var initial_tick: int = client.latest.tick
	# Admit/remove/respawn can publish synchronously before advance raises tick.
	fixture.authority.players.u2.life_state = "dead"
	fixture.authority.players.u2.hp = 0
	fixture.authority.players.u2.deaths = 1
	fixture.authority.players.u2.aim = Vector2.LEFT
	_send(client, fixture.authority.state_snapshot())
	_check(int(client.latest.tick) == initial_tick and _near(_aim(client), Vector2.LEFT), "same-tick death publication resets aim immediately")
	fixture.authority.remove_player("u2")
	_send(client, fixture.authority.state_snapshot())
	_check(not client.aim_tracks.has("u2") and client.player_view("u2").is_empty(), "same-tick departure publication removes the old track")
	fixture.authority.admit({"user_id": "u2", "display_name": "Same tick rejoin"}, 3)
	fixture.authority.players.u2.position = Vector2(780, 478)
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, fixture.authority.state_snapshot())
	_check(int(client.latest.tick) == initial_tick and _near(_aim(client), Vector2.UP), "same-tick new arrival initializes without departed aim history")

func _test_life_transitions() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	client.set_local_aim("u1", Vector2.UP)
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	for user in ["u1", "u2"]:
		fixture.authority.players[user].life_state = "dead"
		fixture.authority.players[user].hp = 0
		fixture.authority.players[user].deaths = 1
		fixture.authority.players[user].aim = Vector2.LEFT
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.LEFT), "death resets an interrupted remote angle immediately")
	_check(_near(_aim(client, "u1", "u1"), Vector2.LEFT), "dead own player ignores the live local sample")
	client.set_local_aim("u1", Vector2.DOWN)
	_check(_near(_aim(client, "u1", "u1"), Vector2.LEFT), "dead player cannot acquire a new local presentation direction")
	fixture.authority.players.u2.life_state = "alive"
	fixture.authority.players.u2.hp = 100
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.UP), "respawn resets remote angle even at the same position")
	fixture.authority.players.u2.aim = Vector2.RIGHT
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.players.u2.deaths = 2
	fixture.authority.players.u2.aim = Vector2.LEFT
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.LEFT), "raised death count resets aim when an intermediate dead snapshot was missed")

func _test_round_reset() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.round_number += 1
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.UP), "new round snaps to its current server aim without carrying an old blend")

func _test_teleport_reset() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.01)
	fixture.authority.players.u2.position.x -= 101.0
	fixture.authority.players.u2.aim = Vector2.UP
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.UP), "teleport over 100 pixels immediately resets the gun angle")
	fixture.authority.players.u2.position.x -= 100.0
	fixture.authority.players.u2.aim = Vector2.LEFT
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.UP), "exactly 100 pixels remains on the ordinary interpolation path")
	client.advance_visual(0.025)
	var midway := _aim(client)
	_check(midway.distance_to(Vector2.UP) > 0.1 and midway.distance_to(Vector2.LEFT) > 0.1, "ordinary movement still permits an intermediate gun angle")

func _test_departure_and_rejoin() -> void:
	cases += 1
	var fixture := _fixture()
	var client = fixture.client
	fixture.authority.players.u2.aim = Vector2.DOWN
	_send(client, _next_packet(fixture))
	client.advance_visual(0.02)
	fixture.authority.remove_player("u2")
	_send(client, _next_packet(fixture))
	_check(not client.aim_tracks.has("u2") and client.player_view("u2").is_empty(), "departed player loses the aim track and snapshot row")
	_check(client.aim_tracks.has("u1"), "departed player cleanup retains players who remain")
	fixture.authority.admit({"user_id": "u2", "display_name": "Remote again"}, 3)
	fixture.authority.players.u2.position = Vector2(780, 478)
	fixture.authority.players.u2.aim = Vector2.LEFT
	_send(client, _next_packet(fixture))
	_check(_near(_aim(client), Vector2.LEFT), "rejoined identity initializes from its new aim without stale history")
	_check(client.aim_tracks.size() == 2, "rejoin creates only the currently present player tracks")

func _test_server_rejection() -> void:
	cases += 1
	var fixture := _fixture()
	var authority = fixture.authority
	var players_before: Dictionary = authority.players.duplicate(true)
	var latest_before: Dictionary = authority.latest.duplicate(true)
	var player: Dictionary = authority.state_snapshot().players[0]
	authority.set_local_aim("u1", Vector2.UP)
	_check(_near(authority.render_aim(player, "u1"), Vector2.RIGHT), "server rejects local presentation and renders authoritative direction")
	_check(authority.players == players_before and authority.latest == latest_before, "server rejection leaves authoritative state and published snapshot untouched")
	_check(authority.aim_tracks.is_empty(), "server cannot accumulate client aim interpolation tracks")
