extends SceneTree
# Render the arena floor under the courtyard's warm light for material review.

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("909da6")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(1, 0.9, 0.76)
	world.environment.ambient_light_energy = 0.38
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 1.2
	light.light_color = Color(1, 0.86, 0.68)
	light.shadow_enabled = true
	var arena := preload("res://mountain_arena.gd").new()
	scene.add_child(arena)
	arena.visible = true
	assert(arena.floor_materials.size() > 3, "floor material overrides were not applied")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = Vector3(6.5, 8, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await create_timer(0.8).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test_output/slate_floor_preview.png")
	print("SLATE_MATERIAL_PASS categories=", arena.floor_materials.size())
	quit()
