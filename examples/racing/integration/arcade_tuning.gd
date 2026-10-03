extends RefCounted
## Lateral retention is expressed at a reference 50 Hz, then converted with dt.
## The actual project still runs at 60 Hz. Unity's source timestep is unverified.
const REFERENCE_DT := 0.02
const LIMITS := {
	"turn_degrees": Vector2(30, 240), "lateral_keep_turn": Vector2(0, 1),
	"lateral_keep_release": Vector2(0, 1), "acceleration": Vector2(5, 40),
	"top_speed": Vector2(12, 30),
}
var values: Dictionary = {}
var profile := "reference"
var legacy_steering := false

func _init() -> void:
	use_preset("reference")

func use_preset(name: String) -> void:
	profile = "original" if name == "original" else "reference"
	legacy_steering = profile == "original"
	values = {"turn_degrees": rad_to_deg(1.22), "lateral_keep_turn": exp(-2.8 * REFERENCE_DT),
		"lateral_keep_release": exp(-5.8 * REFERENCE_DT), "acceleration": 10.0, "top_speed": 25.0} if legacy_steering else {
		"turn_degrees": 175.0, "lateral_keep_turn": 0.95, "lateral_keep_release": 0.95,
		"acceleration": 30.0, "top_speed": 20.0}

func set_value(key: String, value: float) -> bool:
	if not LIMITS.has(key) or not is_finite(value):
		return false
	var bounds: Vector2 = LIMITS[key]
	if value < bounds.x or value > bounds.y:
		return false
	values[key] = value
	profile = "custom"
	if key == "turn_degrees": legacy_steering = false
	return true

func lateral_multiplier(turning: bool, dt: float) -> float:
	if not is_finite(dt) or dt <= 0.0: return 1.0
	var keep: float = values.lateral_keep_turn if turning else values.lateral_keep_release
	return pow(keep, dt / REFERENCE_DT)

func yaw_rate(forward_speed: float) -> float:
	if not is_finite(forward_speed): return 0.0
	# Reverse never steers; the user's straight reverse rule remains intact.
	if legacy_steering:
		return lerpf(2.05, 1.22, clampf(absf(forward_speed) / 25.0, 0, 1)) * clampf(forward_speed / 4.0, 0, 1)
	return deg_to_rad(float(values.turn_degrees)) * clampf(forward_speed / 8.0, 0, 1)

func snapshot() -> Dictionary:
	return {"format": 1, "profile": profile, "reference_hz": 50,
		"legacy_steering": legacy_steering, "values": values.duplicate(true)}
