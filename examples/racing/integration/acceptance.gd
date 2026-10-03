extends Node
var lab: Node3D
var passed := 0
var failed := 0
var checks: Array = []
var measurements: Dictionary = {}
var measuring_frames := false
var frame_times: Array[float] = []

func _process(delta: float) -> void:
	if measuring_frames: frame_times.append(delta)

func _ready() -> void:
	run.call_deferred()

func check(label: String, ok: bool, detail = null) -> void:
	checks.append({"name": label, "ok": ok, "detail": detail})
	if ok: passed += 1
	else:
		failed += 1
		print("FAILED ", label, " ", str(detail))

func ticks(count: int) -> void:
	# Existing durations are expressed as 60Hz ticks; collision sampling below
	# deliberately waits ONE actual physics frame, including before first contact.
	for _i in range(roundi(float(count) * Engine.physics_ticks_per_second / 60.0)):
		await get_tree().physics_frame

func projected_extent(box: CollisionShape3D, axis: Vector3) -> float:
	var half: Vector3 = (box.shape as BoxShape3D).size * 0.5
	var basis := box.global_basis
	return half.x * absf(axis.dot(basis.x)) + half.y * absf(axis.dot(basis.y)) + half.z * absf(axis.dot(basis.z))

func clip_face(points: Array[Vector3], axis: int, sign_axis: float, bound: float) -> Array[Vector3]:
	var clipped: Array[Vector3] = []
	if points.is_empty(): return clipped
	var previous := points[-1]
	var before := sign_axis * previous[axis] - bound
	for current in points:
		var after := sign_axis * current[axis] - bound
		if (before <= 0) != (after <= 0):
			clipped.append(previous.lerp(current, before / (before - after)))
		if after <= 0: clipped.append(current)
		previous = current
		before = after
	return clipped

func finite_rail_penetration(body_box: CollisionShape3D, rail_box: CollisionShape3D, sign_x: float) -> float:
	# Clip the body faces to the rail's actual finite height/length before
	# measuring normal intrusion. Projecting a whole box onto an infinite wall
	# falsely counts corners beyond the ends of short curved rail segments.
	var to_rail := rail_box.global_transform.affine_inverse() * body_box.global_transform
	var body_half := (body_box.shape as BoxShape3D).size * 0.5
	var rail_half := (rail_box.shape as BoxShape3D).size * 0.5
	return finite_box_depth(to_rail, body_half, rail_half, sign_x)

func finite_box_depth(to_rail: Transform3D, body_half: Vector3, rail_half: Vector3, sign_x: float) -> float:
	var corners: Array[Vector3] = []
	for i in range(8):
		corners.append(to_rail * Vector3(body_half.x * (1 if i & 1 else -1), body_half.y * (1 if i & 2 else -1), body_half.z * (1 if i & 4 else -1)))
	var depth := -100.0
	for face in [[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]]:
		var points: Array[Vector3] = []
		for index in face: points.append(corners[index])
		points = clip_face(points, 1, 1, rail_half.y)
		points = clip_face(points, 1, -1, rail_half.y)
		points = clip_face(points, 2, 1, rail_half.z)
		points = clip_face(points, 2, -1, rail_half.z)
		for point in points: depth = maxf(depth, sign_x * point.x + rail_half.x)
	return depth

func measurement_controls() -> void:
	var half := Vector3(0.225, 0.36, 0.5)
	var body := Vector3(0.5, 0.2, 0.4)
	check("measurement retains 3cm right intrusion", absf(finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(-0.695, 0, 0)), body, half, 1) - 0.03) < 0.00001)
	check("measurement retains 3cm left intrusion", absf(finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(0.695, 0, 0)), body, half, -1) - 0.03) < 0.00001)
	var deep := finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(-0.645, 0, 0)), body, half, 1)
	check("measurement still rejects genuine 8cm intrusion", absf(deep - 0.08) < 0.00001 and deep > 0.05)
	var corner: Array[Vector3] = [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 2), Vector3(0.1, 0, 2.2), Vector3(-0.9, 0, 0.2)]
	corner = clip_face(clip_face(corner, 2, 1, 0.5), 2, -1, 0.5)
	var greatest := -INF
	for point in corner: greatest = maxf(greatest, point.x)
	check("measurement excludes curved segment distant corner", absf(greatest + 0.225 - (-0.025)) < 0.00001)
	check("measurement creates intersection without original interior vertices", absf(finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(-0.715, 0, 0)), Vector3(0.5, 1, 1), half, 1) - 0.01) < 0.00001)
	check("measurement detects complete crossing", finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), body, half, 1) > 0.05)
	check("measurement rejects separated finite sections", finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(-0.695, 0, 2)), body, half, 1) < 0)
	check("measurement keeps tangent line intersection", absf(finite_box_depth(Transform3D(Basis.IDENTITY, Vector3(-0.695, 0.75, 0)), Vector3(0.5, 0.25, 0.4), Vector3(0.225, 0.5, 0.5), 1) - 0.03) < 0.00001)

func road_hit(position: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 12, position - Vector3.UP * 12, 1)
	return lab.get_world_3d().direct_space_state.intersect_ray(query)

func run() -> void:
	if lab.test_mode == "render":
		await render_run()
		finish()
		return
	measurement_controls()
	await ticks(120)
	var car: RigidBody3D = lab.car
	measurements.physics_hz = Engine.physics_ticks_per_second
	var layout: Dictionary = lab.track.layout
	check("single integrated car, no arena floor", lab.get_node_or_null("Arena") == null and not lab.track.grid_models.visible)
	check("four independent imported wheels", car.wheel_meshes.size() == 4 and car.wheel_visuals.size() == 4)
	check("V2 wheel dimensions", is_equal_approx(car.wheel_radius, 0.34) and car.wheel_mounts[0].is_equal_approx(Vector3(-0.82, 0, -1.23)))
	var normals: Array = []
	var surfaces: Array = []
	var good_normals := true
	for index in [0, 20, 70, 100, 140, 200, 280]:
		var hit := road_hit(layout.samples[index].position)
		var ok: bool = not hit.is_empty() and hit.collider.name == "DriveSurface" and hit.normal.dot(Vector3.UP) > cos(deg_to_rad(50))
		good_normals = good_normals and ok
		normals.append([] if hit.is_empty() else [hit.normal.x, hit.normal.y, hit.normal.z])
		surfaces.append("miss" if hit.is_empty() else str(hit.collider.name))
	check("actual drive surface upward ray normals", good_normals, normals)
	measurements.road_normals = normals
	measurements.road_colliders = surfaces
	check("flat four wheel support", car.telemetry.get("grounded", 0) == 4, car.telemetry.get("grounded"))
	check("static weight balance", absf(float(car.telemetry.get("support_sum", 0)) - 11760) < 1176, car.telemetry.get("support_sum"))
	check("static imported wheel centers match suspension", car.visual_wheel_error() < 0.001, car.visual_wheel_error())
	check("resting body motion small", car.linear_velocity.length() < 0.15, car.linear_velocity.length())
	if not good_normals or int(car.telemetry.get("grounded", 0)) == 0:
		finish()
		return
	car.set_command(0.7, 0, 0, false)
	await ticks(180)
	check("real propulsion on Port Loop", car.telemetry.speed > 3, car.telemetry.speed)
	check("wheel roll sign forwards", car.telemetry.forward_speed > 0 and car.wheel_meshes[0].rotation.x < 0, car.wheel_meshes[0].rotation.x)
	car.set_command(0.35, 1, 0, false)
	await ticks(30)
	check("front wheels steer independently of rear", absf(car.wheel_visuals[0].rotation.y) > 0.05 and absf(car.wheel_visuals[2].rotation.y) < 0.0001)
	check("moving wheel centers match suspension", car.visual_wheel_error() < 0.001, car.visual_wheel_error())
	car.set_command(0, 0, 1, false)
	await ticks(120)
	check("brake acts through physics", car.telemetry.speed < 1.0, car.telemetry.speed)
	# Place the body on the real rising ramp, then drive over its crest and down.
	var ramp_sample: Dictionary = layout.samples[0]
	for sample in layout.samples:
		if sample.position.x < -21 and sample.position.x > -25 and sample.position.z < -47:
			ramp_sample = sample
	var up := Vector3.UP
	var pose := Transform3D(Basis.looking_at(ramp_sample.forward, up), ramp_sample.position + up * 0.79)
	car.request_reset(pose)
	await ticks(120)
	check("ramp reset obtains wheel support", car.telemetry.grounded == 4)
	car.set_command(0.65, 0, 0, false)
	var highest := car.global_position.y
	var lowest_grounded := 4
	var finite_motion := true
	var crossed_end := false
	for _i in range(Engine.physics_ticks_per_second * 12):
		await get_tree().physics_frame
		highest = maxf(highest, car.global_position.y)
		lowest_grounded = mini(lowest_grounded, int(car.telemetry.get("grounded", 0)))
		finite_motion = finite_motion and car.global_position.is_finite() and car.linear_velocity.is_finite()
		if car.global_position.x > 22:
			crossed_end = true
			car.set_command(0, 0, 1, false)
			break
	check("drive over real crest and descend", crossed_end and highest > 2.45, {"end": crossed_end, "highest_root_y": highest})
	check("ramp motion finite, wheels reconnect", finite_motion and int(car.telemetry.get("grounded", 0)) >= 2, lowest_grounded)
	measurements.ramp = {"highest_root_y": highest, "minimum_grounded": lowest_grounded, "end_position": [car.position.x, car.position.y, car.position.z]}
	car.set_command(0, 0, 1, false)
	await ticks(90)
	# Actual rail collisions: two sides, seam and bend; fixed 5cm penetration gate.
	var guard_reports: Array = []
	var rails: Node3D = lab.track.get_node("ContinuousGuardrails")
	var body_boxes: Array[CollisionShape3D] = []
	for child in car.get_children():
		if child is CollisionShape3D: body_boxes.append(child)
	check("two convex car body collision proxies", body_boxes.size() == 2)
	for spec in [[8, -1.0, 6.0, 0.0], [8, 1.0, 12.0, 0.0], [20, -1.0, 12.0, 0.3], [35, 1.0, 8.0, 0.0], [22, -1.0, 12.0, 0.1], [60, 1.0, 8.0, 0.0], [8, 1.0, 25.0, 0.0]]:
		var index: int = spec[0]
		var side: float = spec[1]
		var a: Dictionary = layout.samples[index]
		var b: Dictionary = layout.samples[index + 1]
		var target := rails.get_child(index * 2 + (0 if side < 0 else 1)) as CollisionShape3D
		var outward := target.global_basis.x.normalized()
		if outward.dot((a.right + b.right) * side) < 0: outward = -outward
		var face := target.global_position - outward * (target.shape as BoxShape3D).size.x * 0.5
		var origin := face - outward * 5.0
		var floor_hit := road_hit(origin)
		origin.y = float(floor_hit.position.y) + 0.79
		var forward: Vector3 = outward.rotated(Vector3.UP, float(spec[3]))
		car.request_reset(Transform3D(Basis.looking_at(forward, Vector3.UP), origin))
		await ticks(100)
		car.apply_central_impulse(forward * car.mass * float(spec[2]))
		var max_penetration := -100.0
		var contacted := false
		var escaped := false
		var first_contact_speed := 0.0
		var previous_speed := 0.0
		var worst: Dictionary = {}
		var max_unclipped_projection := -100.0
		var first_contact_tick := -1
		for _j in range(Engine.physics_ticks_per_second * 4):
			await get_tree().physics_frame
			for body in car.get_colliding_bodies():
				if body.name == "ContinuousGuardrails":
					if not contacted:
						first_contact_speed = previous_speed
						first_contact_tick = _j
					contacted = true
			var penetration := -100.0
			# Use the actual finite rail boxes, including segment seams, and BOTH
			# body proxies. Do not project onto a distant infinite curve tangent.
			for neighbor in range(maxi(0, index - 3), mini(layout.samples.size() - 2, index + 3) + 1):
				var rail_box := rails.get_child(neighbor * 2 + (0 if side < 0 else 1)) as CollisionShape3D
				var half := (rail_box.shape as BoxShape3D).size * 0.5
				var rt := rail_box.global_transform
				var normal := rt.basis.x.normalized()
				if normal.dot(outward) < 0: normal = -normal
				for body_box in body_boxes:
					var delta := body_box.global_position - rt.origin
					if absf(delta.dot(rt.basis.z)) > half.z + projected_extent(body_box, rt.basis.z): continue
					if absf(delta.dot(rt.basis.y)) > half.y + projected_extent(body_box, rt.basis.y): continue
					var projected := delta.dot(normal) + half.x + projected_extent(body_box, normal)
					max_unclipped_projection = maxf(max_unclipped_projection, projected)
					# Exact finite depth cannot exceed its infinite-plane upper bound.
					if projected <= maxf(0, max_penetration): continue
					penetration = maxf(penetration, finite_rail_penetration(body_box, rail_box, 1 if normal.dot(rt.basis.x) > 0 else -1))
			if penetration > max_penetration:
				worst = {"tick": _j, "root": [car.position.x, car.position.y, car.position.z], "speed": car.linear_velocity.length(), "normal_speed": car.linear_velocity.dot(outward), "contacted": contacted}
			max_penetration = maxf(max_penetration, penetration)
			escaped = escaped or outward.dot(car.global_position - face) > 0.225 or car.global_position.y > face.y + 2.0
			previous_speed = car.linear_velocity.length()
		check("rail contact " + str(spec), contacted)
		var actual_shapes: Array = car.contacted_rail_shapes.keys()
		var measured_all := not actual_shapes.is_empty()
		for shape_index in actual_shapes:
			var segment := floori(float(shape_index) / 2)
			measured_all = measured_all and segment >= maxi(0, index - 3) and segment <= mini(layout.samples.size() - 2, index + 3) and int(shape_index) % 2 == (0 if side < 0 else 1)
		check("actual rail contact shapes covered by measured neighbors " + str(spec), measured_all, actual_shapes)
		check("rail body stays inside within 5cm " + str(spec), contacted and max_penetration <= 0.05 and not escaped, max_penetration)
		guard_reports.append({"spec": spec, "contacted": contacted, "contacted_shape_indices": actual_shapes, "all_contact_shapes_measured": measured_all, "max_penetration_m": max_penetration, "unclipped_plane_projection_m": max_unclipped_projection, "escaped": escaped, "pre_contact_speed_mps": first_contact_speed, "first_contact_tick": first_contact_tick, "sampled_actual_ticks": Engine.physics_ticks_per_second * 4, "worst": worst})
	measurements.guardrails = guard_reports
	finish()

func render_run() -> void:
	await ticks(120)
	check("real window has imported car and four wheels", lab.car.wheel_visuals.size() == 4 and get_viewport().get_visible_rect().size == Vector2(1280, 800))
	measuring_frames = true
	lab.car.set_command(0.7, 0, 0, false)
	await ticks(180)
	measuring_frames = false
	check("real window car moves under force", float(lab.car.telemetry.get("speed", 0)) > 3)
	lab.car.set_command(0, 0, 1, false)
	await ticks(120)
	check("real window car stops under braking", float(lab.car.telemetry.get("speed", 0)) < 1)
	lab.reset_car()
	await ticks(150)
	check("reset returns imported wheels to supported spawn", lab.car.telemetry.get("grounded", 0) == 4 and lab.car.visual_wheel_error() < 0.001)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check("real driver screenshot saved", image.save_png(lab.evidence_dir.path_join("driving.png")) == OK and image.get_width() == 1280)
	lab.overview = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check("real track overview saved", get_viewport().get_texture().get_image().save_png(lab.evidence_dir.path_join("track.png")) == OK)
	var sum := 0.0
	var slowest := 0.0
	for delta in frame_times:
		sum += delta
		slowest = maxf(slowest, delta)
	measurements.render = {"frames": frame_times.size(), "seconds": sum, "average_fps": frame_times.size() / sum if sum > 0 else 0, "slowest_frame_ms": slowest * 1000, "physics_hz": Engine.physics_ticks_per_second}
	check("render measurement has real frames", frame_times.size() > 30 and sum > 1)

func finish() -> void:
	var result := {"passed": passed, "failed": failed, "mode": lab.test_mode, "checks": checks, "measurements": measurements, "engine": Engine.get_version_info().string, "lap_completed": false, "network_used": false}
	var file := FileAccess.open(lab.evidence_dir.path_join(lab.test_mode + "-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("RACING_INTEGRATION_RESULT passed=", passed, " failed=", failed)
	get_tree().quit(0 if failed == 0 else 1)
