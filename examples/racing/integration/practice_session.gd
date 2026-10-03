extends RefCounted
## Offline practice owns its own rules/detector; it is not a network result API.
const Rules = preload("res://examples/racing/race_rules.gd")
const Detector = preload("res://examples/racing/checkpoints/checkpoint_detector.gd")
const USER := "local-practice"
const COUNTDOWN_MS := 3000
var rules
var detector
var phase := "invalid"
var error := "NOT_STARTED"
var sim_seconds := 0.0
var start_seconds := -1.0
var elapsed_ms := 0
var expected_gate := 0
var passed_checkpoints := 0
var event_sequence := 0
var events: Array[Dictionary] = []
var last_position := Vector3.ZERO
var gate_count := 0

func restart(checkpoints: Array, position: Vector3) -> bool:
	phase = "invalid"
	error = ""
	sim_seconds = 0.0
	start_seconds = -1.0
	elapsed_ms = 0
	expected_gate = 0
	passed_checkpoints = 0
	event_sequence = 0
	events.clear()
	last_position = position
	gate_count = checkpoints.size()
	rules = Rules.new()
	detector = Detector.new()
	var gates: Array = []
	for cp in checkpoints:
		if not cp is Dictionary: return invalidate("INVALID_TRACK")
		for key in ["id", "position", "right", "forward", "height_m", "half_width_m"]:
			if not cp.has(key): return invalidate("INVALID_TRACK")
		if typeof(cp.id) != TYPE_INT or not cp.position is Vector3 or not cp.right is Vector3 or not cp.forward is Vector3:
			return invalidate("INVALID_TRACK")
		if typeof(cp.height_m) not in [TYPE_INT, TYPE_FLOAT] or typeof(cp.half_width_m) not in [TYPE_INT, TYPE_FLOAT]:
			return invalidate("INVALID_TRACK")
		var right: Vector3 = cp.right
		var forward: Vector3 = cp.forward
		var up := right.cross(forward)
		gates.append({"checkpoint": int(cp.id), "center": cp.position + up * float(cp.height_m) * 0.5,
			"basis": Basis(right, up, -forward), "half_width": float(cp.half_width_m), "half_height": float(cp.height_m) * 0.5})
	var configured: Dictionary = detector.configure(gates, 2.0)
	if not configured.ok: return invalidate(str(configured.code))
	var configured_rules: Dictionary = rules.configure({"mode": "practice", "checkpoint_count": gate_count, "laps": 1, "countdown_ms": COUNTDOWN_MS})
	if not configured_rules.ok: return invalidate(str(configured_rules.code))
	if not rules.admit(USER).ok or not rules.start_countdown().ok: return invalidate("RULE_START_FAILED")
	var anchored: Dictionary = detector.step(position, position, 0, true)
	if not anchored.ok: return invalidate(str(anchored.code))
	phase = "countdown"
	return true

func invalidate(code: String) -> bool:
	phase = "invalid"
	error = code
	return false

func holds_vehicle() -> bool:
	return phase in ["countdown", "finished", "invalid"]

## Called only after a completed movement; paused physics emits no callback.
func step(previous: Vector3, current: Vector3, dt: float) -> void:
	if phase in ["finished", "invalid"]: return
	if not is_finite(dt) or dt <= 0.0 or dt > 0.05:
		invalidate("INVALID_STEP_TIME")
		return
	if previous != last_position:
		invalidate("DISCONTINUITY")
		return
	if not current.is_finite():
		invalidate("INVALID_POSITION")
		return
	var segment_start := sim_seconds
	sim_seconds += dt
	if phase == "countdown":
		if previous != current:
			invalidate("MOVED_DURING_COUNTDOWN")
			return
		var remaining: int = rules.snapshot().countdown_remaining_ms
		var target := mini(COUNTDOWN_MS, floori(sim_seconds * 1000.0 + 0.000001))
		var delta := target - (COUNTDOWN_MS - remaining)
		if delta > 0 and not rules.advance(delta).ok:
			invalidate("COUNTDOWN_CLOCK_FAILED")
			return
		last_position = current
		if rules.snapshot().phase == "racing": phase = "ready"
		return
	var crossed: Dictionary = detector.step(previous, current, expected_gate)
	if not crossed.ok:
		invalidate(str(crossed.code))
		return
	last_position = current
	expected_gate = int(crossed.next_expected)
	for hit in crossed.events:
		var gate: int = hit.checkpoint
		var event_seconds := segment_start + float(hit.fraction) * dt
		if phase == "ready":
			if gate != 0:
				invalidate("BAD_START_GATE")
				return
			start_seconds = event_seconds
			phase = "running"
			events.append({"physical_gate": 0, "kind": "start", "elapsed_ms": 0, "sim_seconds": event_seconds})
			continue
		if not advance_elapsed(event_seconds): return
		event_sequence += 1
		var rule_gate := gate_count - 1 if gate == 0 else gate - 1
		var accepted: Dictionary = rules.observe_checkpoint(USER, rule_gate, event_sequence)
		if not accepted.ok:
			invalidate(str(accepted.code))
			return
		passed_checkpoints += 1
		events.append({"physical_gate": gate, "rule_gate": rule_gate, "kind": "checkpoint", "elapsed_ms": elapsed_ms, "sim_seconds": event_seconds})
		if rules.snapshot().phase == "finished":
			phase = "finished"
			return # Do not include the movement remainder after the finish plane.
	if phase == "running": advance_elapsed(sim_seconds)

func advance_elapsed(at_seconds: float) -> bool:
	var target := floori(maxf(0.0, at_seconds - start_seconds) * 1000.0 + 0.000001)
	var delta := target - elapsed_ms
	if delta < 0 or (delta > 0 and not rules.advance(delta).ok): return invalidate("RACE_CLOCK_FAILED")
	elapsed_ms = target
	return true

func snapshot() -> Dictionary:
	var state: Dictionary = rules.snapshot() if rules != null else {}
	return {"phase": phase, "countdown_remaining_ms": state.get("countdown_remaining_ms", 0),
		"elapsed_ms": elapsed_ms, "lap": 1 if phase == "finished" else 0, "target_laps": 1,
		"passed_checkpoints": passed_checkpoints, "checkpoint_count": gate_count,
		"next_physical_gate": expected_gate, "error": error, "results": rules.results() if rules != null and phase == "finished" else []}
