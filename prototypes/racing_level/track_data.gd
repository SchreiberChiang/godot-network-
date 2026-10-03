extends RefCounted
## Authoritative local level geometry; no race state or networking.
const ROAD_WIDTH := 10.0
const APRON_WIDTH := 16.0
const BASE_Y := 0.12
const STEP := 1.4

static func create(flat := false) -> Dictionary:
	var points: Array[Vector3] = []
	# Consecutive analytic lines/arcs. Start = (-52, 2), travel towards -Z.
	_line(points, Vector2(-52, 2), Vector2(-52, -28))
	_arc(points, Vector2(-32, -28), 20.0, PI, PI * 1.5)
	_line(points, Vector2(-32, -48), Vector2(36, -48))
	_arc(points, Vector2(36, -28), 20.0, PI * 1.5, TAU)
	_line(points, Vector2(56, -28), Vector2(56, 18))
	_arc(points, Vector2(42, 18), 14.0, 0.0, PI)
	_line(points, Vector2(28, 18), Vector2(28, -10))
	_arc(points, Vector2(18, -10), 10.0, 0.0, -PI * 0.5)
	_line(points, Vector2(18, -20), Vector2(6, -20))
	_arc(points, Vector2(6, -10), 10.0, -PI * 0.5, -PI)
	_line(points, Vector2(-4, -10), Vector2(-4, 30))
	_arc(points, Vector2(-22, 30), 18.0, 0.0, PI * 0.5)
	_line(points, Vector2(-22, 48), Vector2(-32, 48))
	_arc(points, Vector2(-32, 28), 20.0, PI * 0.5, PI)
	_line(points, Vector2(-52, 28), Vector2(-52, 2))
	points.append(points[0]) # Explicit duplicated closure vertex.
	if flat:
		for i in range(points.size()):
			points[i].y = BASE_Y
	var distance := 0.0
	var samples: Array = []
	var count := points.size() - 1
	for i in range(points.size()):
		if i > 0:
			distance += points[i].distance_to(points[i - 1])
		var index := i % count
		var direction := (points[(index + 1) % count] - points[(index - 1 + count) % count]).normalized()
		var right := direction.cross(Vector3.UP).normalized()
		samples.append({"position": points[i], "forward": direction, "right": right, "distance_m": distance})
	var checkpoints: Array = []
	# The first plane is the finish. Its forward normal points in travel direction.
	var anchors := [Vector2(-52, 2), Vector2(-52, -23), Vector2(-28, -48),
		Vector2(14, -48), Vector2(56, -22), Vector2(56, 15), Vector2(28, 15),
		Vector2(28, -8), Vector2(7, -20), Vector2(-4, 20), Vector2(-27, 48), Vector2(-52, 24)]
	for anchor in anchors:
		var nearest := 0
		var best := INF
		for i in range(count):
			var p: Vector3 = points[i]
			var d := Vector2(p.x, p.z).distance_squared_to(anchor)
			if d < best:
				best = d
				nearest = i
		var s: Dictionary = samples[nearest]
		checkpoints.append({"id": checkpoints.size(), "sample_index": nearest,
			"position": s.position, "forward": s.forward, "right": s.right,
			"half_width_m": 8.25, "height_m": 6.0, "distance_m": s.distance_m})
	var spawns: Array = []
	for row in range(4):
		for col in range(2):
			spawns.append({"id": spawns.size(), "position": Vector3(-54.5 + col * 5.0, BASE_Y + 0.65, 9.0 + row * 5.5),
				"forward": Vector3.FORWARD, "yaw_rad": 0.0, "reserved_size_m": Vector3(2.4, 1.6, 4.2)})
	return {"level_id": "port_loop_01", "version": 1, "samples": samples,
		"checkpoints": checkpoints, "spawns": spawns, "length_m": distance,
		"road_width_m": ROAD_WIDTH, "apron_width_m": APRON_WIDTH,
		"coordinates": "meters; Godot +Y up; model nose -Z; origin at island center; X east, -Z north",
		"island_size_m": Vector3(150, 1.4, 124)}

static func _point(p: Vector2) -> Vector3:
	var height := BASE_Y
	if absf(p.y + 48.0) < 0.001 and p.x > -22.0 and p.x < 18.0:
		height += 2.0 * pow(sin(PI * (p.x + 22.0) / 40.0), 2.0)
	return Vector3(p.x, height, p.y)

static func _line(points: Array[Vector3], a: Vector2, b: Vector2) -> void:
	var n := ceili(a.distance_to(b) / STEP)
	for i in range(n):
		points.append(_point(a.lerp(b, float(i) / n)))

static func _arc(points: Array[Vector3], center: Vector2, radius: float, start: float, finish: float) -> void:
	var n := ceili(absf(finish - start) * radius / STEP)
	for i in range(n):
		var angle := lerpf(start, finish, float(i) / n)
		points.append(_point(center + Vector2(cos(angle), sin(angle)) * radius))

static func json_value(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = json_value(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(json_value(item))
		return result
	return value
