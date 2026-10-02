extends RefCounted
## Deterministic synthetic snapshots, not a network or physics benchmark.
const Game = preload("res://examples/shooter/game.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const SPEED := 120.0
const DURATION := 3.0
const STEP := 1.0 / 120.0
var world = Game.new()
var authority = Game.new()
var packets: Array = []
var next_packet := 0
var elapsed := 0.0
var error := ""

func setup(scenario: String) -> void:
	authority.server = true
	authority.admit({"user_id": "u1", "display_name": "Moving"}, 2)
	authority.admit({"user_id": "u2", "display_name": "Stationary"}, 3)
	authority.advance(0)
	authority.players.u2.position = Vector2(850, 478)
	for index in range(61):
		var source := index * 0.05
		if scenario == "outage" and source >= 1.0 and source < 1.25:
			continue
		var delay := 0.0
		if scenario == "jitter":
			delay = [0.0, 0.015, 0.035, 0.005][index % 4]
		authority.tick = index * 3
		authority.players.u1.position = Vector2(truth(source), 478)
		var packet: Dictionary = authority.state_snapshot().duplicate(true)
		var validation := Validator.validate_file(packet, "res://schemas/shooter_state.schema.json")
		if validation != "": error = validation
		packets.append({"arrival": source + delay, "packet": packet})
	packets.sort_custom(func(a, b): return float(a.arrival) < float(b.arrival))
	advance(0.0)

func truth(time: float) -> float:
	return 100.0 + SPEED * time

func advance(delta: float) -> void:
	# Split at arrival times so coarse display frames do not shift reception.
	var end := elapsed + delta
	while next_packet < packets.size() and float(packets[next_packet].arrival) <= end + 0.000001:
		var arrival := maxf(elapsed, float(packets[next_packet].arrival))
		world.advance_visual(arrival - elapsed)
		elapsed = arrival
		world.world_state(packets[next_packet].packet.duplicate(true))
		if int(world.latest.get("tick", -1)) != int(packets[next_packet].packet.tick):
			error = "SNAPSHOT_NOT_ACCEPTED"
		next_packet += 1
	world.advance_visual(maxf(0.0, end - elapsed))
	elapsed = end

func displayed() -> float:
	var player: Dictionary = world.player_view("u1")
	return world.render_position(player).x if not player.is_empty() else truth(0.0)

func raw() -> float:
	return float(world.player_view("u1").get("x", 100.0))

func measure() -> Dictionary:
	var frames := 0
	var moving := 0
	var pause := 0
	var longest_pause := 0
	var worst_error := 0.0
	var sum_error := 0.0
	var previous := displayed()
	for frame in range(1, 361):
		advance(STEP)
		var x := displayed()
		if not is_finite(x): error = "NONFINITE_POSITION"
		# Exclude startup; all measured truth positions have constant velocity.
		if frame >= 25:
			frames += 1
			var distance := absf(truth(elapsed) - x)
			sum_error += distance
			worst_error = maxf(worst_error, distance)
			if absf(x - previous) > 0.0001:
				moving += 1
				pause = 0
			else:
				pause += 1
				longest_pause = maxi(longest_pause, pause)
		previous = x
	return {"frames": frames, "moving_frames": moving,
		"moving_frame_percent": moving * 100.0 / frames,
		"longest_pause_ms": longest_pause * STEP * 1000.0,
		"mean_position_error_px": sum_error / frames,
		"max_position_error_px": worst_error,
		"equivalent_mean_lag_ms": sum_error / frames / SPEED * 1000.0,
		"error": error}

func close() -> void:
	world.free()
	authority.free()
