extends SceneTree
const Probe = preload("res://tests/support/movement_probe.gd")

func _initialize() -> void:
	var results := {}
	var failed := false
	var checks := 0
	for scenario in ["stable", "jitter", "outage"]:
		var probe = Probe.new()
		probe.setup(scenario)
		results[scenario] = probe.measure()
		failed = failed or results[scenario].error != ""
		probe.close()
		var repeat_probe = Probe.new()
		repeat_probe.setup(scenario)
		var repeated: Dictionary = repeat_probe.measure()
		repeat_probe.close()
		# Harness validity, not required visual behavior of a future candidate.
		var valid: bool = results[scenario].frames == 336 and results[scenario].error == ""
		var bounded: bool = results[scenario].moving_frames >= 0 and results[scenario].moving_frames <= 336
		var reproducible: bool = JSON.stringify(results[scenario]) == JSON.stringify(repeated)
		checks += int(valid) + int(bounded) + int(reproducible)
		failed = failed or not valid or not bounded or not reproducible
	print("MOVEMENT_BASELINE_RESULT ", JSON.stringify({
		"scope": "synthetic_snapshots_no_network_no_renderer",
		"display_hz": 120, "snapshot_hz": 20, "speed_px_s": 120,
		"measurement_start_s": 0.2, "duration_s": 3.0,
		"harness_checks_passed": checks, "harness_checks_total": 9,
		"scenarios": results}))
	quit(1 if failed else 0)
