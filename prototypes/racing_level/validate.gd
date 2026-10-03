extends SceneTree
const Data = preload("res://track_data.gd")
const Harbor = preload("res://harbor.tscn")
var passed := 0
var failed := 0
var results: Array = []
var out_dir := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=")
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	passed += int(ok)
	failed += int(not ok)
	results.append({"name": label, "passed": ok, "detail": detail})
	print("PASS " if ok else "FAIL ", label, " ", detail)

func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _run() -> void:
	var d := Data.create()
	var samples: Array = d.samples
	var n := samples.size() - 1
	_check(n > 100 and samples[0].position.is_equal_approx(samples[n].position), "closed_centerline", n)
	_check(samples[0].forward.is_equal_approx(samples[n].forward), "closed_tangent")
	var finite := true
	var regular := true
	var min_width := INF
	var max_grade := 0.0
	var min_height := INF
	var max_height := -INF
	for i in range(samples.size()):
		var p: Vector3 = samples[i].position
		var f: Vector3 = samples[i].forward
		var r: Vector3 = samples[i].right
		finite = finite and p.is_finite() and f.is_finite() and r.is_finite() and is_finite(samples[i].distance_m)
		regular = regular and absf(f.length() - 1) < 0.001 and absf(r.length() - 1) < 0.001 and absf(f.dot(r)) < 0.001
		min_height = minf(min_height, p.y)
		max_height = maxf(max_height, p.y)
		if i < n:
			var next: Vector3 = samples[i + 1].position
			var advance: Vector3 = next - p
			regular = regular and advance.length() > 0.01 and advance.length() < 1.5
			max_grade = maxf(max_grade, absf(advance.y) / _xz(advance).length())
			var mid_right: Vector3 = (r + samples[i + 1].right) * 0.5
			min_width = minf(min_width, (mid_right * Data.ROAD_WIDTH).length())
	_check(finite, "finite_centerline")
	_check(regular, "continuous_nonzero_segments_and_frames")
	_check(min_width >= 8.0, "net_road_width_at_vertices_and_midpoints", min_width)
	_check(max_grade < 0.17 and max_height - min_height > 1.95, "gentle_2m_rise", {"max_grade": max_grade, "height_m": max_height - min_height})
	var crossings := 0
	var closest_remote := INF
	for i in range(n):
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			if Geometry2D.segment_intersects_segment(_xz(samples[i].position), _xz(samples[i + 1].position), _xz(samples[j].position), _xz(samples[j + 1].position)) != null:
				crossings += 1
			var delta_s: float = absf(samples[j].distance_m - samples[i].distance_m)
			if minf(delta_s, d.length_m - delta_s) > 25:
				closest_remote = minf(closest_remote, samples[i].position.distance_to(samples[j].position))
	_check(crossings == 0, "no_centerline_crossings", crossings)
	_check(closest_remote > Data.APRON_WIDTH + 1.0, "separated_remote_route_legs", closest_remote)
	_check(_planes_cover(d.checkpoints, samples), "ordered_forward_planes_cover_entire_runoff")
	var wrong_plane: Array = d.checkpoints.duplicate(true)
	wrong_plane[2].position += Vector3(100, 0, 0)
	_check(not _planes_cover(wrong_plane, samples), "off_route_checkpoint_negative_fixture_rejected")
	wrong_plane = d.checkpoints.duplicate(true)
	wrong_plane[2].forward *= -1
	_check(not _planes_cover(wrong_plane, samples), "reversed_checkpoint_negative_fixture_rejected")
	_check(_grid_clear(d.spawns), "eight_nonoverlapping_car_reservations")
	var malformed: Array = d.spawns.duplicate(true)
	malformed[1].position = malformed[0].position
	_check(not _grid_clear(malformed), "overlapping_grid_negative_fixture_rejected")
	var tree := Harbor.instantiate()
	root.add_child(tree)
	await physics_frame
	await physics_frame
	var world: World3D = tree.get_world_3d()
	var space := world.direct_space_state
	var road_body: StaticBody3D = tree.get_node("DriveSurface")
	_check(road_body.get_child_count() == 1 and road_body.get_child(0).shape is ConcavePolygonShape3D,
		"single_continuous_static_road_mesh", road_body.get_child(0).shape.get_faces().size() / 3)
	var misses := 0
	var wrong_height := 0
	var probes := 0
	# Both segment ends and centers, across the full road + both runoff shoulders.
	for i in range(n):
		for t in [0.0, 0.5]:
			var p: Vector3 = samples[i].position.lerp(samples[i + 1].position, t)
			var right: Vector3 = samples[i].right.lerp(samples[i + 1].right, t)
			for offset in [-7.8, -4.9, 0.0, 4.9, 7.8]:
				var floor: Vector3 = p + right * offset
				var ray := PhysicsRayQueryParameters3D.create(floor + Vector3.UP * 0.25, floor - Vector3.UP * 0.3, 1)
				var hit := space.intersect_ray(ray)
				probes += 1
				if hit.is_empty() or hit.collider != road_body:
					misses += 1
				elif absf(hit.position.y - floor.y) > 0.004:
					wrong_height += 1
	_check(misses == 0 and wrong_height == 0, "physics_surface_at_seams_ramp_and_shoulders", {"probes": probes, "misses": misses, "wrong_height": wrong_height})
	var walls: StaticBody3D = tree.get_node("ContinuousGuardrails")
	var rail_misses := 0
	for i in range(n):
		for side in [-1.0, 1.0]:
			var p: Vector3 = samples[i].position + Vector3.UP * 0.36
			var r: Vector3 = samples[i].right * side
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + r * 7.9, p + r * 9.2, 1))
			if hit.is_empty() or hit.collider != walls:
				rail_misses += 1
	_check(rail_misses == 0 and walls.get_child_count() == n * 2, "continuous_static_guardrails", {"shapes": walls.get_child_count(), "misses": rail_misses})
	var grid_surface := true
	for spawn in d.spawns:
		var p: Vector3 = spawn.position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 2, 1))
		grid_surface = grid_surface and not hit.is_empty() and hit.collider == road_body
	_check(grid_surface, "eight_spawns_over_road")
	var user_path := OS.get_user_data_dir().replace("\\", "/")
	_check(user_path.begins_with(ProjectSettings.globalize_path("res://artifacts/").replace("\\", "/")), "isolated_user_data", user_path)
	var version := str(Engine.get_version_info().string)
	_check(version.begins_with("4.7.2"), "required_engine_version", version)
	if not out_dir.is_empty():
		var f := FileAccess.open(out_dir.path_join("validation.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": results, "engine": version, "length_m": d.length_m}, "\t"))
		f = FileAccess.open(out_dir.path_join("layout.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(Data.json_value(d), "\t"))
	print("LEVEL_VALIDATION ", passed, " passed / ", failed, " failed")
	tree.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)

func _planes_cover(planes: Array, samples: Array) -> bool:
	if planes.size() != 12:
		return false
	var previous := -1
	for i in range(planes.size()):
		var cp: Dictionary = planes[i]
		if cp.id != i or cp.sample_index <= previous or cp.sample_index >= samples.size() - 1:
			return false
		var sample: Dictionary = samples[cp.sample_index]
		if not cp.position.is_finite() or not cp.forward.is_finite() or not cp.right.is_finite():
			return false
		if not is_finite(cp.half_width_m) or not is_finite(cp.height_m) or cp.height_m < 6.0 or cp.half_width_m < Data.APRON_WIDTH * 0.5:
			return false
		if not cp.position.is_equal_approx(sample.position) or not cp.forward.is_equal_approx(sample.forward) or not cp.right.is_equal_approx(sample.right):
			return false
		var before: Vector3 = samples[(cp.sample_index - 1 + samples.size() - 1) % (samples.size() - 1)].position
		var after: Vector3 = samples[cp.sample_index + 1].position
		if (before - cp.position).dot(cp.forward) >= 0 or (after - cp.position).dot(cp.forward) <= 0:
			return false
		previous = cp.sample_index
	return true

func _grid_clear(spawns: Array) -> bool:
	if spawns.size() != 8:
		return false
	for i in range(spawns.size()):
		var a: Dictionary = spawns[i]
		if a.id != i or not a.position.is_finite() or a.forward != Vector3.FORWARD or a.yaw_rad != 0.0:
			return false
		if absf(a.position.x + 52) + a.reserved_size_m.x * 0.5 > 5.0:
			return false
		for j in range(i + 1, spawns.size()):
			var b: Dictionary = spawns[j]
			var delta: Vector3 = a.position - b.position
			if absf(delta.x) < (a.reserved_size_m.x + b.reserved_size_m.x) * 0.5 and absf(delta.z) < (a.reserved_size_m.z + b.reserved_size_m.z) * 0.5:
				return false
	return true
