extends SceneTree
## Deterministic presentation comparison against an unedited baseline script.
## No sockets, accounts, server processes or input prediction. Both worlds see
## exactly the same valid snapshots and display deltas. These are synthetic
## body-position metrics, NOT input-to-photon or public-network measurements.
const Candidate = preload("res://examples/shooter/game.gd")
const Validator = preload("res://sdk/roomkit/shared/schema_validator.gd")
const SPEED := 235.0
const DURATION := 3.0
var failed := 0
var baseline_path := ""
var output := ""
var baseline_script: Script

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-script="):
			baseline_path = arg.trim_prefix("--baseline-script=")
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if baseline_path == "":
		printerr("Pass --baseline-script=res://<isolated baseline>/game.gd; copy its game_config.json beside it")
		quit(2)
		return
	baseline_script = load(baseline_path)
	if baseline_script == null or not baseline_script.can_instantiate():
		quit(2)
		return
	var rows: Array = []
	for fps in [60, 120]:
		for scenario in ["stable20", "jitter20_80", "short_gap150", "stop_start", "reversal", "jump_land"]:
			rows.append(_compare(scenario, fps))
	var report := {
		"scope": "deterministic_real_game_objects_synthetic_snapshots_no_network_or_renderer",
		"engine": Engine.get_version_info().string,
		"baseline_script": baseline_path,
		"baseline_sha256": FileAccess.get_sha256(baseline_path),
		"candidate_sha256": FileAccess.get_sha256("res://examples/shooter/game.gd"),
		"measurement_window_seconds": [0.5, 2.5],
		"moving_frame_threshold_px": 0.001,
		"definitions": {
			"moving_frame_ratio": "fraction of all sampled display intervals whose rendered position changes by >0.001 px; intentional stops included in transition scenarios",
			"longest_stall_ms": "longest consecutive duration of unchanged sampled positions; intentional stops included in transition scenarios",
			"position_error_px": "Euclidean distance from known continuous synthetic truth at the same display time, including configured network delay",
			"follow_lag_ms": "constant-speed cases only: signed truth.x minus rendered.x divided by235px/s; includes synthetic network+sampling+presentation",
			"extra_display_latency_ms": "candidate minus baseline mean equivalent constant-speed follow lag on identical inputs",
			"speed_error_rms_px_s": "RMS of rendered frame-velocity minus truth frame-velocity; measures speed ripple as well as stalls",
			"settle_after_last_arrival_ms": "time from final snapshot delivery until display is within0.001px of its confirmed endpoint"
		},
		"rows": rows,
		"failed": failed
	}
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			failed += 1
		else:
			file.store_string(JSON.stringify(report, "  ") + "\n")
	print("MOVEMENT_COMPARISON_RESULT cases=", rows.size(), " failed=", failed)
	quit(0 if failed == 0 else 1)

func _truth(scenario: String, time: float) -> Vector2:
	var t := clampf(time, 0.0, DURATION)
	var x := 100.0 + SPEED * t
	var y := 478.0
	if scenario == "stop_start":
		x = 100.0 + SPEED * (minf(t, 0.85) + maxf(0, t - 1.55))
	elif scenario == "reversal":
		x = 300.0 + SPEED * (minf(t, 1.3) - maxf(0, t - 1.3))
	elif scenario == "jump_land":
		var air := clampf(t - 0.9, 0, 0.8)
		y -= 470.0 * air - 587.5 * air * air
	return Vector2(x, y)

func _packets(scenario: String) -> Array:
	var result: Array = []
	var source = Candidate.new()
	source.server = true
	source.admit({"user_id": "moving", "display_name": "Synthetic moving target"}, 2)
	for index in 61:
		if scenario == "short_gap150" and index in [20, 21]:
			continue
		var time := float(index) * 0.05
		source.tick = index * 3
		source.players.moving.position = _truth(scenario, time)
		var packet: Dictionary = source.state_snapshot()
		if Validator.validate_file(packet, "res://schemas/shooter_state.schema.json") != "":
			failed += 1
		var jitter := 0.03 if index % 2 == 1 and scenario != "stable20" else 0.0
		# short_gap150 uses regular arrivals so the isolated gap is exactly150ms.
		if scenario == "short_gap150":
			jitter = 0.0
		result.append({"at": time + 0.04 + jitter, "value": packet})
	source.free()
	return result

func _compare(scenario: String, fps: int) -> Dictionary:
	var baseline = baseline_script.new()
	var candidate = Candidate.new()
	var worlds := [baseline, candidate]
	var stats := [_empty_stats(), _empty_stats()]
	var packets := _packets(scenario)
	var next := 0
	var delta := 1.0 / float(fps)
	var previous := [Vector2.ZERO, Vector2.ZERO]
	var final_at := -1.0
	for frame in range(1, ceili(3.6 * fps) + 1):
		var now := frame * delta
		for world in worlds:
			world.advance_visual(delta)
		while next < packets.size() and float(packets[next].at) <= now + 0.000001:
			for world in worlds:
				world.world_state(packets[next].value.duplicate(true))
			next += 1
			if next == packets.size():
				final_at = now
		for index in 2:
			var player: Dictionary = worlds[index].player_view("moving")
			if player.is_empty():
				continue
			var position: Vector2 = worlds[index].render_position(player)
			var stat: Dictionary = stats[index]
			if now >= 0.5 - 0.000001 and now <= 2.5 + 0.000001:
				var distance := position.distance_to(previous[index])
				stat.frames += 1
				if distance > 0.001:
					stat.moving += 1
					stat.stall = 0.0
				else:
					stat.stall += delta
					stat.max_stall = maxf(stat.max_stall, stat.stall)
				var truth := _truth(scenario, now)
				stat.errors.append(position.distance_to(truth))
				stat.lags.append((truth.x - position.x) / SPEED * 1000.0)
				var velocity: Vector2 = (position - previous[index]) / delta
				var truth_velocity := (truth - _truth(scenario, now - delta)) / delta
				stat.speed_error_squared += velocity.distance_squared_to(truth_velocity)
				stat.max_step = maxf(stat.max_step, distance)
			if final_at >= 0 and stat.settle_ms < 0 and position.distance_to(_truth(scenario, DURATION)) <= 0.001:
				stat.settle_ms = (now - final_at) * 1000.0
			previous[index] = position
			if not position.is_finite():
				failed += 1
	var constant_speed := scenario in ["stable20", "jitter20_80", "short_gap150"]
	var result := {"scenario": scenario, "display_hz": fps, "baseline": _summarize(stats[0], constant_speed), "candidate": _summarize(stats[1], constant_speed)}
	if constant_speed:
		result.extra_display_latency_ms = result.candidate.follow_lag_ms.mean - result.baseline.follow_lag_ms.mean
	if stats[1].settle_ms < 0 or stats[1].settle_ms > 100.01:
		failed += 1
		printerr("Candidate failed finite100ms endpoint convergence: ", scenario, " ", fps)
	if scenario == "stable20" and absf(result.candidate.moving_frame_ratio - result.baseline.moving_frame_ratio) > 0.001:
		failed += 1
	if scenario == "jitter20_80" and result.candidate.moving_frame_ratio <= result.baseline.moving_frame_ratio:
		failed += 1
	print("MOVEMENT_ROW ", JSON.stringify(result))
	baseline.free()
	candidate.free()
	return result

func _empty_stats() -> Dictionary:
	return {"frames": 0, "moving": 0, "stall": 0.0, "max_stall": 0.0, "errors": [], "lags": [], "speed_error_squared": 0.0, "max_step": 0.0, "settle_ms": -1.0}

func _distribution(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values:
		total += float(value)
	return {"mean": total / values.size(), "p95": values[mini(values.size() - 1, ceili(values.size() * 0.95) - 1)], "max": values[-1]}

func _summarize(stat: Dictionary, constant_speed: bool) -> Dictionary:
	var result := {"sampled_frames": stat.frames, "moving_frame_ratio": float(stat.moving) / stat.frames, "longest_stall_ms": stat.max_stall * 1000.0, "position_error_px": _distribution(stat.errors), "speed_error_rms_px_s": sqrt(stat.speed_error_squared / stat.frames), "max_frame_displacement_px": stat.max_step, "settle_after_last_arrival_ms": stat.settle_ms}
	if constant_speed:
		result.follow_lag_ms = _distribution(stat.lags)
	return result
