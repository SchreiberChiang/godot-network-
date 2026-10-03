extends SceneTree

# Headless imported-mesh gate after the hidden chassis clearance correction.
# Does not render images, test physics or substitute for pixel review.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed := load("res://models/street_car_v2.glb") as PackedScene
	if packed == null:
		quit(2)
		return
	var car := packed.instantiate() as Node3D
	root.add_child(car)
	var chassis := car.find_child("Chassis_Visual",true,false) as MeshInstance3D
	var half_width: float = max(abs(chassis.get_aabb().position.x),abs(chassis.get_aabb().end.x))
	var smallest_gap := 100.0
	var samples := 0
	for angle in [-.44,-.22,0.0,.22,.44]:
		for roll in [0.0,.4,PI/2,PI,4.03,TAU-.1]:
			for suffix in ["Front_Left","Front_Right"]:
				var hub := car.find_child("Steer_"+suffix,true,false) as Node3D
				var wheel := car.find_child("Wheel_"+suffix,true,false) as MeshInstance3D
				var before := wheel.global_position
				hub.rotation.y = angle
				wheel.rotation.x = -roll
				if wheel.global_position.distance_to(before) > .00001: failures.append("Pivot moved")
				for surface in range(wheel.mesh.get_surface_count()):
					var vertices: PackedVector3Array = wheel.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex in vertices:
						var point: Vector3 = wheel.global_transform * vertex
						var gap: float = abs(point.x) - half_width
						smallest_gap = min(smallest_gap,gap)
						if gap <= .04: failures.append("Wheel/chassis envelope gap <= 4 cm")
				samples += 1
	var result := {"status":"PASS" if failures.is_empty() else "FAIL","engine":Engine.get_version_info().string,
		"test":"final GLB imported meshes; 5 steering x 6 rolling angles x 2 front wheels",
		"samples":samples,"minimum_vertex_lateral_gap_m":smallest_gap,"chassis_half_width_m":half_width,
		"failures":failures,"rendered":false,"physics_tested":false,"scope":"Chassis_Visual clearance only"}
	var file := FileAccess.open("res://../evidence/final_import_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")+"\n")
	print("FINAL_IMPORT_RESULT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
