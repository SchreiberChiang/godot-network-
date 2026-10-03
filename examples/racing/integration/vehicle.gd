extends "res://vehicle_base.gd"
## V2 asset is in ground coordinates; rigid body origin is the suspension mount plane.
const MODEL_OFFSET_Y := -0.67012
const MODEL_WHEELS := ["Front_Left", "Front_Right", "Rear_Left", "Rear_Right"]
var visual_root: Node3D
var wheel_meshes: Array[Node3D] = []
var contacted_rail_shapes: Dictionary = {}

func _init() -> void:
	wheel_mounts = [Vector3(-0.82, 0, -1.23), Vector3(0.82, 0, -1.23), Vector3(-0.82, 0, 1.22), Vector3(0.82, 0, 1.22)]
	wheel_radius = 0.34
	low_speed_steer_degrees = 25.0

func _ready() -> void:
	super._ready()
	# Two convex body proxies are expressed relative to the physical root.
	var collider := get_child(0) as CollisionShape3D
	(collider.shape as BoxShape3D).size = Vector3(1.78, 0.48, 4.0)
	collider.position = Vector3(0, 0.59 + MODEL_OFFSET_Y, 0)
	var cabin := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.44, 0.43, 1.58)
	cabin.shape = box
	cabin.position = Vector3(0, 1.13 + MODEL_OFFSET_Y, 0.22)
	add_child(cabin)
	contact_monitor = true
	max_contacts_reported = 16

func _build_placeholder() -> void:
	visual_root = (load("res://models/street_car_v2.glb") as PackedScene).instantiate() as Node3D
	visual_root.name = "StreetCarV2"
	visual_root.position.y = MODEL_OFFSET_Y
	add_child(visual_root)
	for suffix in MODEL_WHEELS:
		var pivot := visual_root.find_child("Steer_" + suffix, true, false) as Node3D
		var wheel := visual_root.find_child("Wheel_" + suffix, true, false) as Node3D
		assert(pivot != null and wheel != null, "V2 wheel hierarchy missing")
		wheel_visuals.append(pivot)
		wheel_meshes.append(wheel)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	if telemetry.get("reset", false):
		# The reset callback still carries contacts from the PRE-reset pose.
		contacted_rail_shapes.clear()
		return
	for i in range(state.get_contact_count()):
		var collider = state.get_contact_collider_object(i)
		if is_instance_valid(collider) and collider.name == "ContinuousGuardrails":
			contacted_rail_shapes[state.get_contact_collider_shape(i)] = true
	_sync_wheels()

func _physics_process(_delta: float) -> void:
	pass

func _sync_wheels() -> void:
	if telemetry.is_empty() or telemetry.wheels.size() != 4:
		return
	for i in range(4):
		wheel_visuals[i].position = wheel_mounts[i] - Vector3.UP * (float(telemetry.wheels[i].length) + MODEL_OFFSET_Y)
		wheel_visuals[i].rotation.y = _steer_angle if i < 2 else 0.0
		# Imported V2 wheel orientation rolls towards -Z with a negative X angle.
		wheel_meshes[i].rotation.x = -_wheel_spin

func visual_wheel_error() -> float:
	var error := 0.0
	if telemetry.get("wheels", []).size() != 4:
		return INF
	for i in range(4):
		var expected := global_transform * (wheel_mounts[i] - Vector3.UP * float(telemetry.wheels[i].length))
		error = maxf(error, wheel_meshes[i].global_position.distance_to(expected))
	return error
