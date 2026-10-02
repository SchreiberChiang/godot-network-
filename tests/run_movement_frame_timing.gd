extends SceneTree
## Independent synthetic frame-quantization check, not wall-clock/network timing.
## A nominal 20 Hz stream reaches alternating fifth/seventh 120 Hz frames.
const Game = preload("res://examples/shooter/game.gd")
const STEP := 1.0 / 120.0
const SPEED := 120.0
var passed := 0
var failed := 0

func _initialize() -> void:
	var baseline_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-script="):
			baseline_path = arg.trim_prefix("--baseline-script=")
	if baseline_path == "":
		printerr("Pass --baseline-script for the untouched reference game.gd")
		quit(2)
		return
	var baseline: Script = load(baseline_path)
	if baseline == null or not baseline.can_instantiate():
		quit(2)
		return
	for quantized in [false, true]:
		_compare(baseline, quantized)
	print("MOVEMENT_FRAME_TIMING_RESULT passed=", passed, " failed=", failed)
	quit(0 if failed == 0 else 1)

func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("MOVEMENT_FRAME_TIMING_FAIL " + description)

func _truth(seconds: float) -> float:
	return 100.0 + SPEED * minf(seconds, 2.0)

func _compare(baseline: Script, quantized: bool) -> void:
	var source = Game.new()
	source.server = true
	source.admit({"user_id": "moving", "display_name": "Frame timing"}, 2)
	var worlds := [baseline.new(), Game.new()]
	var stats := [{"sum_error": 0.0, "frames": 0, "pause": 0, "max_pause": 0, "stop_ms": -1.0},
		{"sum_error": 0.0, "frames": 0, "pause": 0, "max_pause": 0, "stop_ms": -1.0}]
	var previous := [100.0, 100.0]
	var next_packet := 0
	var finite_and_bounded := true
	var stable_equal := true
	var max_duration := 0.0
	# Positions stop at t=2.0; exclude startup and the actual stop from stall metrics.
	for frame in range(0, 421):
		var now := frame * STEP
		if frame > 0:
			for world in worlds:
				world.advance_visual(STEP)
		var arrival_frame: int = next_packet * 6 + (next_packet % 2 if quantized else 0)
		if next_packet <= 60 and frame == arrival_frame:
			source.tick = next_packet * 3
			source.players.moving.position = Vector2(_truth(next_packet * 0.05), 478)
			var packet: Dictionary = source.state_snapshot()
			for world in worlds:
				world.world_state(packet.duplicate(true))
			next_packet += 1
		var displayed: Array[float] = []
		for index in 2:
			var world = worlds[index]
			var player: Dictionary = world.player_view("moving")
			var position: Vector2 = world.render_position(player)
			displayed.append(position.x)
			finite_and_bounded = finite_and_bounded and position.is_finite() and position.x >= 99.999 and position.x <= float(player.x) + 0.001
			if frame >= 60 and frame < 228:
				stats[index].frames += 1
				stats[index].sum_error += absf(_truth(now) - position.x)
				stats[index].pause = int(stats[index].pause) + 1 if absf(position.x - previous[index]) < 0.0001 else 0
				stats[index].max_pause = maxi(int(stats[index].max_pause), int(stats[index].pause))
			if frame >= 240 and stats[index].stop_ms < 0 and absf(position.x - _truth(2.0)) < 0.0001:
				stats[index].stop_ms = (now - 2.0) * 1000.0
			previous[index] = position.x
		stable_equal = stable_equal and absf(displayed[0] - displayed[1]) < 0.0001
		max_duration = maxf(max_duration, float(worlds[1].render_tracks.moving.duration))
	var old_mean: float = stats[0].sum_error / stats[0].frames
	var new_mean: float = stats[1].sum_error / stats[1].frames
	var extra_lag_ms := (new_mean - old_mean) / SPEED * 1000.0
	_check(next_packet == 61, "all progressing snapshots delivered")
	_check(finite_and_bounded, "presentation finite and never extrapolates past confirmed endpoint")
	_check(float(stats[1].stop_ms) >= 0 and float(stats[1].stop_ms) <= 100.001, "stopped within finite transition after final moving sample")
	_check(int(stats[1].max_pause) <= int(stats[0].max_pause), "frame quantization does not add moving-interval holds")
	_check(max_duration <= 0.100001, "transition duration remains bounded")
	if quantized:
		_check(max_duration > 0.05 and max_duration <= 7.0 * STEP + 0.000001, "five/seven frame arrivals measure actual quantized duration")
		_check(extra_lag_ms <= STEP * 1000.0 + 0.001, "one-frame reception quantization costs at most one extra display frame on this trajectory")
	else:
		_check(stable_equal, "ideal six-frame stable stream matches old positions including stop")
		_check(absf(extra_lag_ms) < 0.001, "ideal stable stream adds no mean lag")
	print("MOVEMENT_FRAME_TIMING_ROW ", JSON.stringify({"scenario": "five_seven_frames" if quantized else "six_frames",
		"display_hz": 120, "source_hz": 20, "baseline_mean_error_px": old_mean, "candidate_mean_error_px": new_mean,
		"extra_equivalent_mean_lag_ms": extra_lag_ms, "baseline_pause_ms": int(stats[0].max_pause) * STEP * 1000.0,
		"candidate_pause_ms": int(stats[1].max_pause) * STEP * 1000.0, "baseline_stop_ms": stats[0].stop_ms,
		"candidate_stop_ms": stats[1].stop_ms, "max_candidate_transition_ms": max_duration * 1000.0,
		"scope": "synthetic_frame_quantization_no_network_or_renderer"}))
	for world in worlds:
		world.free()
	source.free()
