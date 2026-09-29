extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.15, 0)
	root.add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 6.0
	pivot.add_child(arm)
	var cam := Camera3D.new()
	arm.add_child(cam)
	for degrees in [-60.0, -30.0, 20.0, 40.0]:
		pivot.rotation.x = deg_to_rad(degrees)
		await physics_frame
		await physics_frame
		print("pitch %.0f cam_global_y=%.2f local=%s" % [degrees, cam.global_position.y, cam.position])
	quit()
