extends SceneTree

const MouseVFX = preload("res://vfx/mouse_skill_vfx.gd")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.34, 0.48)
	environment.glow_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 12.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.055, 0.07, 0.1)
	ground_material.roughness = 0.82
	ground.material_override = ground_material
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(9.0, 4.2, 3.4)
	camera.look_at(Vector3(1.5, 1.0, 0.0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.65, 0.5, 0.0)
	light.light_energy = 0.6
	stage.add_child(light)
	var effect := MouseVFX.new()
	stage.add_child(effect)
	var path: Array = []
	for i in 8:
		path.append([Vector3(-4.0 + float(i), 0.0, 0.0), Vector3(-3.0 + float(i), 0.0, 0.0)])
	var fake_world := {"player": {"kind":"player", "position":Vector3(4.0, 0.0, 0.0), "action":"mouse_cut", "action_tick":1, "mouse_cut_path":path}}
	for i in 4:
		effect.sync_world(fake_world, i + 2, 0.016)
		await process_frame
	await RenderingServer.frame_post_draw
	var trail_image := viewport.get_texture().get_image()
	var trail_error := trail_image.save_png("res://assets/vfx/mouse_cut_travel_preview.png")
	effect.burst_cut(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	for i in 10:
		effect.sync_world(fake_world, i + 6, 0.016)
		await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var error := result.save_png("res://assets/vfx/mouse_cut_runtime_preview.png")
	var target := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	target.mesh = capsule
	target.position = Vector3(0.0, 1.0, 0.0)
	var target_material := StandardMaterial3D.new()
	target_material.albedo_color = Color(0.92, 0.56, 0.26)
	target.material_override = target_material
	stage.add_child(target)
	camera.position = Vector3(2.6, 2.2, 5.8)
	camera.look_at(Vector3(1.2, 1.6, 0.0))
	effect.burst_cut(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	for i in 7:
		effect.sync_world(fake_world, i + 20, 0.016)
		await process_frame
	await RenderingServer.frame_post_draw
	var hold_error := viewport.get_texture().get_image().save_png("res://assets/vfx/mouse_cut_cinematic_hold_preview.png")
	for i in 26:
		effect.sync_world(fake_world, i + 27, 0.016)
		await process_frame
	target.position.y = 3.0
	camera.position.y = 2.64
	camera.look_at(Vector3(1.2, 2.5, 0.0))
	await RenderingServer.frame_post_draw
	var launch_error := viewport.get_texture().get_image().save_png("res://assets/vfx/mouse_cut_cinematic_launch_preview.png")
	var success := error == OK and trail_error == OK and hold_error == OK and launch_error == OK
	print("MOUSE_CUT_VFX_CAPTURE ", "PASS" if success else "FAIL")
	quit(0 if success else 1)
