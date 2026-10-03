extends Node3D
## Read-only presentation, called AFTER movement and the suspension ray samples.
## wheels[2..3]: world-space point/normal/center Vector3 plus grounded bool.
## Geometry remains in world space; no physics, input or driving state is changed.
## Eight persistent meshes, one shader/material, and a fixed 4096-quad FIFO pool.
## Fade runs in the shader using our step clock (never shader TIME). Only dirty
## 512-quad blocks upload geometry; fading alone does not rebuild any surfaces.

const CAPACITY := 4096
const MAX_MESH_NODES := 8
const QUADS_PER_BLOCK := 512
const LIFETIME_SECONDS := 8.0
const SAMPLE_DISTANCE := 0.2
const MAX_SEGMENT_DISTANCE := 2.0
const HALF_WIDTH := 0.11
const SURFACE_OFFSET := 0.014
const MIN_FORWARD_SPEED := 6.0
const MIN_SLIP_DEGREES := 8.0
const MAX_SLIP_DEGREES := 75.0
const EPSILON := 0.000001
const INK := Color(0.035, 0.031, 0.027, 0.64)
const FADE_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float trail_age_seconds = 0.0;
uniform float lifetime_seconds = 8.0;
void fragment() {
	float age = max(0.0, trail_age_seconds - UV.x);
	float fade = 1.0 - smoothstep(0.0, lifetime_seconds, age);
	float edge = smoothstep(0.0, 0.13, UV.y) * smoothstep(0.0, 0.13, 1.0 - UV.y);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * fade * edge;
}
"""

class MeshBlock:
	extends RefCounted
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var arrays: Array = []
	var mesh: ArrayMesh
	var instance: MeshInstance3D
	var live_quads := 0
	var dirty := false

var enabled := true
var _blocks: Array[MeshBlock] = []
var _material: ShaderMaterial
var _births := PackedFloat64Array()
var _age_seconds := 0.0
var _write_cursor := 0
var _expire_cursor := 0
var _active_quads := 0
var _total_created := 0
var _dropped_for_capacity := 0
var _surface_uploads := 0
var _last_step_uploads := 0
var _invalid_observations := 0
var _was_frozen := false
var _connected: Array[bool] = [false, false]
var _has_edges: Array[bool] = [false, false]
var _points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _centers: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _left_edges: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _right_edges: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _rear_contacts: Array[Dictionary] = [{}, {}]

func _ready() -> void:
	_ensure_storage()

func step(dt: float, telemetry: Dictionary, wheels: Array, frozen: bool = false) -> void:
	_last_step_uploads = 0
	_observe_contacts(wheels)
	if frozen:
		_was_frozen = true
		_break_samples()
		return # No new geometry, lifetime advance, expiry, or shader-time writes.
	if _was_frozen:
		_break_samples()
		_was_frozen = false
	if not is_finite(dt) or dt <= 0.0 or not is_finite(_age_seconds + dt) \
		or _age_seconds + dt > 1.0e30: # Also stay finite when packed into float32 UVs.
		_invalid_observations += 1
		_break_samples()
		return
	_ensure_storage()
	_age_seconds += dt
	_material.set_shader_parameter("trail_age_seconds", _age_seconds)
	_expire_oldest()
	var forward_speed := float(telemetry.get("forward_speed", 0.0))
	var slip := absf(float(telemetry.get("slip_degrees", 0.0)))
	var drifting := enabled and is_finite(forward_speed) and is_finite(slip) \
		and forward_speed >= MIN_FORWARD_SPEED and slip + EPSILON >= MIN_SLIP_DEGREES \
		and slip - EPSILON <= MAX_SLIP_DEGREES and str(telemetry.get("mode", "forward")) != "reverse"
	if not drifting:
		_break_samples()
	else:
		for rear in range(2):
			_sample_rear(rear)
	_flush_dirty_blocks()

func reset() -> void:
	# Keep all allocated nodes/resources/containers for the next practice run.
	_age_seconds = 0.0
	_write_cursor = 0
	_expire_cursor = 0
	_active_quads = 0
	_total_created = 0
	_dropped_for_capacity = 0
	_surface_uploads = 0
	_last_step_uploads = 0
	_invalid_observations = 0
	_was_frozen = false
	_break_samples()
	_rear_contacts = [{}, {}]
	for rear in range(2):
		_points[rear] = Vector3.ZERO
		_centers[rear] = Vector3.ZERO
		_normals[rear] = Vector3.UP
		_left_edges[rear] = Vector3.ZERO
		_right_edges[rear] = Vector3.ZERO
	_births.fill(0.0)
	for block in _blocks:
		block.vertices.fill(Vector3.ZERO)
		block.colors.fill(Color(0, 0, 0, 0))
		block.uvs.fill(Vector2.ZERO)
		block.live_quads = 0
		block.dirty = false
		block.mesh.clear_surfaces()
		block.instance.visible = false
	if _material != null:
		_material.set_shader_parameter("trail_age_seconds", 0.0)

func snapshot() -> Dictionary:
	var oldest_age := 0.0
	if _active_quads > 0:
		oldest_age = _age_seconds - _births[_expire_cursor]
	var contacts := _rear_contacts.duplicate(true)
	for rear in range(2):
		contacts[rear]["connected"] = _connected[rear]
		contacts[rear]["sample_point"] = _points[rear]
	return {
		"enabled": enabled, "frozen": _was_frozen,
		"active_quads": _active_quads, "capacity": CAPACITY,
		"max_mesh_nodes": MAX_MESH_NODES, "mesh_nodes": _blocks.size(),
		"total_created": _total_created, "dropped_for_capacity": _dropped_for_capacity,
		"finite": _storage_is_finite(), "age_seconds": _age_seconds,
		"oldest_age_seconds": oldest_age, "lifetime_seconds": LIFETIME_SECONDS,
		"rear_contacts": contacts, "rear_grounded": [bool(contacts[0].get("grounded", false)), bool(contacts[1].get("grounded", false))],
		"surface_uploads": _surface_uploads, "last_step_uploads": _last_step_uploads,
		"invalid_observations": _invalid_observations,
	}

func _ensure_storage() -> void:
	if not _blocks.is_empty():
		return
	_births.resize(CAPACITY)
	var shader := Shader.new()
	shader.code = FADE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.render_priority = 1
	_material.set_shader_parameter("lifetime_seconds", LIFETIME_SECONDS)
	for number in range(MAX_MESH_NODES):
		var block := MeshBlock.new()
		block.vertices.resize(QUADS_PER_BLOCK * 4)
		block.colors.resize(QUADS_PER_BLOCK * 4)
		block.colors.fill(Color(0, 0, 0, 0))
		block.uvs.resize(QUADS_PER_BLOCK * 4)
		block.indices.resize(QUADS_PER_BLOCK * 6)
		for quad in range(QUADS_PER_BLOCK):
			var vertex := quad * 4
			var index := quad * 6
			block.indices[index] = vertex
			block.indices[index + 1] = vertex + 1
			block.indices[index + 2] = vertex + 2
			block.indices[index + 3] = vertex + 2
			block.indices[index + 4] = vertex + 1
			block.indices[index + 5] = vertex + 3
		block.arrays.resize(Mesh.ARRAY_MAX)
		block.arrays[Mesh.ARRAY_INDEX] = block.indices
		block.mesh = ArrayMesh.new()
		block.instance = MeshInstance3D.new()
		block.instance.name = "RearSkidBlock%d" % number
		block.instance.mesh = block.mesh
		block.instance.material_override = _material
		block.instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		block.instance.top_level = true
		block.instance.transform = Transform3D.IDENTITY
		block.instance.visible = false
		add_child(block.instance)
		_blocks.append(block)

func _observe_contacts(wheels: Array) -> void:
	for rear in range(2):
		var wheel: Dictionary = {}
		if wheels.size() == 4 and wheels[rear + 2] is Dictionary:
			wheel = wheels[rear + 2]
		var point = wheel.get("point", null)
		var normal = wheel.get("normal", null)
		var center = wheel.get("center", null)
		var valid := point is Vector3 and normal is Vector3 and center is Vector3
		if valid:
			valid = point.is_finite() and normal.is_finite() and center.is_finite() \
				and is_finite(normal.length_squared()) and normal.length_squared() > EPSILON
		_rear_contacts[rear] = {
			"wheel_index": rear + 2, "grounded": bool(wheel.get("grounded", false)), "valid": valid,
			"point": point if valid else Vector3.ZERO,
			"normal": normal.normalized() if valid else Vector3.UP,
			"center": center if valid else Vector3.ZERO,
		}
		if not valid and not wheel.is_empty():
			_invalid_observations += 1

func _sample_rear(rear: int) -> void:
	var contact: Dictionary = _rear_contacts[rear]
	if not bool(contact.valid) or not bool(contact.grounded):
		_connected[rear] = false
		_has_edges[rear] = false
		return
	var point: Vector3 = contact.point
	var normal: Vector3 = contact.normal
	var center: Vector3 = contact.center
	if not _connected[rear]:
		_anchor(rear, point, normal, center)
		return
	var displacement := point - _points[rear]
	var distance := displacement.length()
	var center_distance := center.distance_to(_centers[rear])
	if not is_finite(distance) or not is_finite(center_distance) \
		or distance > MAX_SEGMENT_DISTANCE or center_distance > MAX_SEGMENT_DISTANCE \
		or normal.dot(_normals[rear]) < 0.5:
		_anchor(rear, point, normal, center)
		return
	# Both physical wheel center and contact must move; contact jitter alone is
	# not displacement. Accumulate against the last accepted sample, not frames.
	if distance + EPSILON < SAMPLE_DISTANCE or center_distance + EPSILON < SAMPLE_DISTANCE:
		return
	var direction := displacement / distance
	var side := normal.cross(direction)
	var previous_side := _normals[rear].cross(direction)
	if side.length_squared() <= EPSILON or previous_side.length_squared() <= EPSILON:
		_anchor(rear, point, normal, center)
		return
	side = side.normalized() * HALF_WIDTH
	previous_side = previous_side.normalized() * HALF_WIDTH
	var start := _points[rear] + _normals[rear] * SURFACE_OFFSET
	var end := point + normal * SURFACE_OFFSET
	var start_left := _left_edges[rear] if _has_edges[rear] else start - previous_side
	var start_right := _right_edges[rear] if _has_edges[rear] else start + previous_side
	var end_left := end - side
	var end_right := end + side
	if _append_quad(start_left, start_right, end_left, end_right):
		_left_edges[rear] = end_left
		_right_edges[rear] = end_right
		_anchor(rear, point, normal, center)
		_has_edges[rear] = true
	else:
		# Pool pressure must not produce a later bridge across skipped samples.
		_anchor(rear, point, normal, center)

func _anchor(rear: int, point: Vector3, normal: Vector3, center: Vector3) -> void:
	_points[rear] = point
	_normals[rear] = normal
	_centers[rear] = center
	_connected[rear] = true
	_has_edges[rear] = false

func _break_samples() -> void:
	_connected.fill(false)
	_has_edges.fill(false)

func _append_quad(start_left: Vector3, start_right: Vector3, end_left: Vector3, end_right: Vector3) -> bool:
	if _active_quads == CAPACITY:
		# Reuse only after the full fade lifetime, even at excessive sample rates.
		_dropped_for_capacity += 1
		return false
	if not start_left.is_finite() or not start_right.is_finite() \
		or not end_left.is_finite() or not end_right.is_finite():
		_invalid_observations += 1
		return false
	var block: MeshBlock = _blocks[int(_write_cursor / float(QUADS_PER_BLOCK))]
	var vertex := (_write_cursor % QUADS_PER_BLOCK) * 4
	block.vertices[vertex] = start_left
	block.vertices[vertex + 1] = start_right
	block.vertices[vertex + 2] = end_left
	block.vertices[vertex + 3] = end_right
	for corner in range(4):
		block.colors[vertex + corner] = INK
		block.uvs[vertex + corner] = Vector2(_age_seconds, float(corner % 2))
	_births[_write_cursor] = _age_seconds
	block.live_quads += 1
	block.dirty = true
	_write_cursor = (_write_cursor + 1) % CAPACITY
	_active_quads += 1
	_total_created += 1
	return true

func _expire_oldest() -> void:
	while _active_quads > 0 and _age_seconds - _births[_expire_cursor] >= LIFETIME_SECONDS:
		var block: MeshBlock = _blocks[int(_expire_cursor / float(QUADS_PER_BLOCK))]
		var vertex := (_expire_cursor % QUADS_PER_BLOCK) * 4
		for corner in range(4):
			block.vertices[vertex + corner] = Vector3.ZERO
			block.colors[vertex + corner] = Color(0, 0, 0, 0)
		block.live_quads -= 1
		block.dirty = true
		_expire_cursor = (_expire_cursor + 1) % CAPACITY
		_active_quads -= 1

func _flush_dirty_blocks() -> void:
	for block in _blocks:
		if not block.dirty:
			continue
		block.mesh.clear_surfaces()
		block.instance.visible = block.live_quads > 0
		if block.live_quads > 0:
			block.arrays[Mesh.ARRAY_VERTEX] = block.vertices
			block.arrays[Mesh.ARRAY_COLOR] = block.colors
			block.arrays[Mesh.ARRAY_TEX_UV] = block.uvs
			block.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, block.arrays)
		block.dirty = false
		_surface_uploads += 1
		_last_step_uploads += 1

func _storage_is_finite() -> bool:
	if not is_finite(_age_seconds):
		return false
	for block in _blocks:
		for vertex in block.vertices:
			if not vertex.is_finite():
				return false
		for uv in block.uvs:
			if not uv.is_finite():
				return false
	for birth in _births:
		if not is_finite(birth):
			return false
	return true
