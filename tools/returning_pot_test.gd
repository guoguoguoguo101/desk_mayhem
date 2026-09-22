extends SceneTree

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://office_demo.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	get_first_node_in_group("network").start_solo()
	var player = scene.get_node("Player")
	var dummy = scene.get_node("TrainingDummy1")
	player.global_position = Vector3(30, 0.95, 25)
	dummy.global_position = Vector3(30, 0.95, 21)
	player.set_physics_process(false)
	dummy.set_physics_process(false)
	player.face_to(Vector3.FORWARD)
	var before: int = dummy.hit_count
	player.throw_pot()
	var pot = player.active_pot
	assert(is_instance_valid(pot))
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		scene.add_child(camera)
		camera.global_position = Vector3(35, 7, 28)
		camera.look_at(Vector3(30, 1.3, 21))
		camera.current = true
		await create_timer(0.28).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/pot-preview.png")
		await create_timer(1.12).timeout
	else:
		await create_timer(1.4).timeout
	assert(dummy.hit_count - before == 2, "one outbound and one return hit required")
	assert(not is_instance_valid(player.active_pot), "pot must be caught")
	player.action_lock = 0.0
	player.cd["pot"] = 0.0
	player.throw_pot()
	await create_timer(0.12).timeout
	pot = player.active_pot
	player.throw_pot()
	assert(pot.returning and pot.recalled, "second press must recall immediately despite cooldown")
	await create_timer(0.5).timeout
	assert(not is_instance_valid(player.active_pot))
	dummy.begin_juggle(Vector3.UP * 4)
	dummy.velocity.y = -6.0
	dummy.pot_return(Vector3.RIGHT * 5)
	assert(is_equal_approx(dummy.velocity.y, -1.0), "return should catch fall without launching")
	dummy.velocity.y = 5.0
	dummy.pot_return(Vector3.RIGHT * 5)
	assert(is_equal_approx(dummy.velocity.y, 5.0), "return should preserve ascent")
	dummy.velocity.y = -5.0
	dummy.pot_outbound(Vector3.FORWARD)
	assert(dummy.velocity.y > 0.0, "outbound should lift")
	print("POT_PROBE_PASS")
	scene.queue_free()
	await process_frame
	quit()
