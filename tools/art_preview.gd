extends SceneTree

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://office_demo.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	get_first_node_in_group("network").start_solo()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/art-gameplay.png")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = Vector3(3.1, 2.8, 0.8)
	camera.look_at(Vector3(0, 1, 4.8))
	camera.current = true
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/art-character.png")
	scene.get_node("Player").umbrella_spin()
	await create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/art-skill.png")
	print("ART_PREVIEW_PASS")
	quit()
