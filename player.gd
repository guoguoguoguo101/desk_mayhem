extends CharacterBody3D

const THROWN_ITEM = preload("res://thrown_item.gd")

@export var move_speed := 6.5
@export var acceleration := 28.0

@onready var visual: Node3D = $Visual
@onready var umbrella_visual: Node3D = $Visual/Umbrella
@onready var chair_visual: Node3D = $Visual/ChairWeapon
@onready var kicking_foot: MeshInstance3D = $Visual/FootR
@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var feedback: Node3D = get_node("../CombatFeedback")
var throw_cooldown := 0.0
var hit_pause := 0.0
var blink_cooldown := 0.0
var dash_cooldown := 0.0
var dash_time := 0.0
var dash_trail_time := 0.0
var dash_direction := Vector3.ZERO
var dash_targets: Array[Node] = []
var dash_followup_timer := 0.0
var uppercut_time := 0.0
var chair_cooldown := 0.0
var chair_time := 0.0
var kick_cooldown := 0.0
var kick_time := 0.0

func _process(delta: float) -> void:
	throw_cooldown = maxf(0.0, throw_cooldown - delta)
	blink_cooldown = maxf(0.0, blink_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	dash_followup_timer = maxf(0.0, dash_followup_timer - delta)
	uppercut_time = maxf(0.0, uppercut_time - delta)
	umbrella_visual.visible = dash_time > 0.0 or uppercut_time > 0.0
	umbrella_visual.rotation.x = -sin((1.0 - uppercut_time / 0.3) * PI) * 0.8 if uppercut_time > 0.0 else 0.0
	chair_cooldown = maxf(0.0, chair_cooldown - delta)
	chair_time = maxf(0.0, chair_time - delta)
	chair_visual.visible = chair_time > 0.0
	if chair_time > 0.0:
		chair_visual.rotation.x = -sin((1.0 - chair_time / 0.42) * PI) * 1.2
	else:
		chair_visual.rotation.x = 0.0
	kick_cooldown = maxf(0.0, kick_cooldown - delta)
	kick_time = maxf(0.0, kick_time - delta)
	kicking_foot.position.z = -0.1 - sin((1.0 - kick_time / 0.3) * PI) * 0.58 if kick_time > 0.0 else -0.1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.physical_keycode == KEY_Q:
			umbrella_action()
		elif event.physical_keycode == KEY_E:
			chair_attack()
		elif event.physical_keycode == KEY_F:
			kick_attack()
		elif event.physical_keycode == KEY_SHIFT:
			short_blink()
		elif event.physical_keycode == KEY_SPACE:
			jump()
	if not (event is InputEventMouseButton and event.pressed):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or throw_cooldown > 0.0:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		throw_item(THROWN_ITEM.ItemKind.FOLDER)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		throw_item(THROWN_ITEM.ItemKind.COFFEE)

func throw_item(kind: int) -> void:
	var forward := facing_direction()
	var item := THROWN_ITEM.new()
	get_parent().add_child(item)
	item.global_position = global_position + Vector3.UP * 0.25 + forward * 0.8
	item.launch(kind, forward, get_rid())
	throw_cooldown = 0.45 if kind == THROWN_ITEM.ItemKind.FOLDER else 0.75

func facing_direction() -> Vector3:
	var forward := -visual.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()

func short_blink() -> void:
	if blink_cooldown > 0.0 or dash_time > 0.0:
		return
	var direction := facing_direction()
	var start_position := global_position
	for step in range(10, 0, -1):
		var offset := direction * (float(step) * 0.45)
		if not test_move(global_transform, offset):
			global_position += offset
			break
	if global_position.distance_to(start_position) < 0.1:
		return
	velocity.x = 0.0
	velocity.z = 0.0
	blink_cooldown = 1.8
	feedback.blink_effect(start_position + Vector3.UP, global_position + Vector3.UP)

func jump() -> void:
	if is_on_floor() and dash_time <= 0.0:
		velocity.y = 7.5

func umbrella_action() -> void:
	if dash_followup_timer > 0.0:
		umbrella_uppercut()
	else:
		start_dash()

func start_dash() -> void:
	if dash_cooldown > 0.0 or dash_time > 0.0:
		return
	dash_direction = facing_direction()
	dash_time = 0.38
	dash_cooldown = 1.6
	dash_followup_timer = 1.45
	dash_targets.clear()
	umbrella_visual.visible = true
	feedback.dash_start()

func umbrella_uppercut() -> void:
	dash_followup_timer = 0.0
	dash_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	uppercut_time = 0.3
	feedback.play_swing()
	var forward := facing_direction()
	await get_tree().create_timer(0.1).timeout
	for target in get_tree().get_nodes_in_group("combat_targets"):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= 2.4 and to_target.normalized().dot(forward) > 0.2:
			target.launch_up(forward)

func kick_attack() -> void:
	if kick_cooldown > 0.0 or dash_time > 0.0:
		return
	kick_cooldown = 0.65
	kick_time = 0.3
	feedback.play_swing()
	var forward := facing_direction()
	await get_tree().create_timer(0.1).timeout
	for target in get_tree().get_nodes_in_group("combat_targets"):
		var to_target: Vector3 = target.global_position - global_position
		var height_difference: float = absf(to_target.y)
		to_target.y = 0.0
		if to_target.length() <= 2.3 and height_difference < 3.2 and to_target.normalized().dot(forward) > 0.3:
			target.kick_from(forward)

func chair_attack() -> void:
	if chair_cooldown > 0.0 or dash_time > 0.0:
		return
	var forward := facing_direction()
	chair_time = 0.42
	chair_cooldown = 0.8
	chair_visual.visible = true
	feedback.play_swing()
	await get_tree().create_timer(0.13).timeout
	for target in get_tree().get_nodes_in_group("combat_targets"):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= 2.1 and to_target.normalized().dot(forward) > 0.35:
			if target.airborne:
				target.spike_down(forward)
			else:
				target.take_hit("椅子")

func _physics_process(delta: float) -> void:
	if hit_pause > 0.0:
		hit_pause = maxf(0.0, hit_pause - delta)
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if wasd.length_squared() > 0.0:
		input_vector = wasd.normalized()
	var direction := Vector3.ZERO
	if camera and input_vector.length_squared() > 0.0:
		var right := camera.global_transform.basis.x
		var forward := -camera.global_transform.basis.z
		right.y = 0.0
		forward.y = 0.0
		direction = (right.normalized() * input_vector.x + forward.normalized() * -input_vector.y).normalized()
	var target_velocity := direction * move_speed
	var was_dashing := dash_time > 0.0
	if was_dashing:
		dash_time -= delta
		dash_trail_time -= delta
		if dash_trail_time <= 0.0:
			feedback.dash_trail(global_position + Vector3.UP * 0.1)
			dash_trail_time = 0.06
		target_velocity = dash_direction * 15.0
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	if was_dashing:
		velocity.x = target_velocity.x
		velocity.z = target_velocity.z
	velocity.y -= 20.0 * delta
	move_and_slide()
	if was_dashing:
		for i in get_slide_collision_count():
			var target := get_slide_collision(i).get_collider()
			if target is Node and target.has_method("take_hit") and not dash_targets.has(target):
				target.take_hit("雨伞")
				dash_targets.append(target)
		if dash_time <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
	elif direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 12.0 * delta)
