extends RefCounted
## Lateral retention is expressed at a reference 50 Hz, then converted with dt.
## The actual project still runs at 60 Hz. Unity's source timestep is unverified.
const REFERENCE_DT := 0.02
const LIMITS := {
	"turn_degrees": Vector2(30, 240), "lateral_keep_turn": Vector2(0, 1),
	"lateral_keep_release": Vector2(0, 1), "acceleration": Vector2(5, 40),
	"top_speed": Vector2(12, 30),
	"nitro_speed_multiplier": Vector2(1.05, 1.8), "nitro_extra_acceleration": Vector2(0, 60),
	"wall_slide_drag": Vector2(0, 8),
}
var values: Dictionary = {}
var profile := "player"
var legacy_steering := false

func _init() -> void:
	use_preset("player")

func use_preset(name: String) -> void:
	profile = name if name in ["player", "original", "reference"] else "reference"
	legacy_steering = profile == "original"
	values = {"turn_degrees": rad_to_deg(1.22), "lateral_keep_turn": exp(-2.8 * REFERENCE_DT),
		"lateral_keep_release": exp(-5.8 * REFERENCE_DT), "acceleration": 10.0, "top_speed": 25.0} if legacy_steering else {
		"turn_degrees": 175.0, "lateral_keep_turn": 0.95, "lateral_keep_release": 0.95,
		"acceleration": 30.0, "top_speed": 20.0}
	values.nitro_speed_multiplier = 34.0 / float(values.top_speed)
	values.nitro_extra_acceleration = 16.0
	values.wall_slide_drag = 0.8
	if profile == "player":
		# Eight values approved in the user's final playable handling feedback.
		values.merge({"turn_degrees": 120.0, "lateral_keep_turn": 0.97, "lateral_keep_release": 0.989,
			"acceleration": 24.0, "top_speed": 30.0, "nitro_speed_multiplier": 1.71999995231628,
			"nitro_extra_acceleration": 59.0, "wall_slide_drag": 6.2}, true)

func set_value(key: String, value: float) -> bool:
	if not LIMITS.has(key) or not is_finite(value):
		return false
	var bounds: Vector2 = LIMITS[key]
	# Vector2 stores float32 bounds. Normalize only this fractional multiplier;
	# a tiny negative lateral keep must still be rejected before fractional pow.
	if key == "nitro_speed_multiplier":
		if value < 1.05 - 0.000001 or value > 1.8 + 0.000001: return false
		value = clampf(value, 1.05, 1.8)
	elif value < float(bounds.x) or value > float(bounds.y):
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

func nitro_speed() -> float:
	return float(values.top_speed) * float(values.nitro_speed_multiplier)

func snapshot() -> Dictionary:
	return {"format": 1, "profile": profile, "reference_hz": 50,
		"legacy_steering": legacy_steering, "values": values.duplicate(true)}
