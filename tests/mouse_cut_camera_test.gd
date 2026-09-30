extends SceneTree

const FollowCamera = preload("res://follow_camera.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := CharacterBody3D.new()
	player.name = "Player"
	stage.add_child(player)
	var visual := Node3D.new()
	visual.name = "Visual"
	player.add_child(visual)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(FollowCamera)
	var pivot := Node3D.new()
	pivot.name = "PitchPivot"
	rig.add_child(pivot)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	pivot.add_child(arm)
	var shaker := Node3D.new()
	shaker.name = "Shaker"
	arm.add_child(shaker)
	var normal := Camera3D.new()
	normal.name = "Camera3D"
	normal.current = true
	shaker.add_child(normal)
	stage.add_child(rig)
	var victim := Node3D.new()
	stage.add_child(victim)
	victim.global_position = Vector3(0.0, 1.0, 0.0)
	await process_frame
	rig.begin_mouse_cut_cinematic(Vector3(-4, 0, 0), Vector3(4, 0, 0), victim, 0.56)
	assert(rig.cut_camera.current and rig.is_mouse_cut_cinematic_active())
	var normal_start: Vector3 = normal.global_position
	assert(rig.cut_camera.global_position.distance_to(normal_start) < 0.01)
	rig._update_mouse_cut_cinematic(0.06)
	var entering: Vector3 = rig.cut_camera.global_position
	assert(entering.distance_to(normal_start) > 0.01)
	assert(rig.cut_cinematic_phase == "enter")
	victim.global_position.y = 3.0
	rig._update_mouse_cut_cinematic(0.07)
	assert(rig.cut_cinematic_phase == "hold" and rig.cut_camera.global_position.y > entering.y)
	rig._update_mouse_cut_cinematic(0.44)
	assert(rig.cut_cinematic_phase == "exit" and rig.cut_camera.current)
	var side_position: Vector3 = rig.cut_camera.global_position
	rig._update_mouse_cut_cinematic(0.1)
	assert(rig.cut_camera.current and rig.cut_camera.global_position.distance_to(side_position) > 0.01)
	assert(rig.cut_camera.global_position.distance_to(normal.global_position) > 0.01)
	rig._update_mouse_cut_cinematic(0.11)
	assert(not rig.is_mouse_cut_cinematic_active() and normal.current)
	print("MOUSE_CUT_CAMERA PASS")
	quit()
