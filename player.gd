extends CharacterBody3D

const THROWN_ITEM = preload("res://thrown_item.gd")
const RETURNING_POT = preload("res://returning_pot.gd")
var active_pot: Node3D
const RUSHING_CHAIR = preload("res://rushing_chair.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
const FloatRules = preload("res://float_rules.gd")
const CombatStateData = preload("res://combat/combat_state.gd")
const CombatRules = preload("res://combat/combat_resolver.gd")
const AttackData = preload("res://combat/attack_catalog.gd")
const HitIntentData = preload("res://combat/hit_intent.gd")
const HitDetection = preload("res://combat/hit_detector.gd")

enum Weapon { UMBRELLA, COFFEE, POT, CHAIR }

const WEAPON_NAMES: Array[String] = ["雨伞", "咖啡杯", "锅", "办公椅"]
const CD_PUNCH := 0.4
const CD_KICK := BattleRules.CD_KICK
const CD_DASH := BattleRules.CD_DASH
const CD_BLOCK := 4.0
const CD_SPIN := BattleRules.CD_SPIN
const SPIN_DURATION := BattleRules.SPIN_DURATION
const SPIN_HIT_AT := BattleRules.SPIN_HIT_AT
const SPIN_REACH := 2.4
const SPIN_HEIGHT := 3.2
const SPIN_PUSH := BattleRules.SPIN_PUSH
const CD_COFFEE := 0.85
const CD_DRINK := 8.0
const CD_POT := BattleRules.CD_POT
const CD_SLAM := BattleRules.CD_SLAM
const CD_CHAIR := 2.4
const CD_MOUNT := 0.35
const BLOCK_DURATION := 1.5
const BUFF_DURATION := 5.0
const FOLLOWUP_WINDOW := BattleRules.FOLLOWUP_WINDOW
const PUNCH_LINK := 0.55
const HITSTUN := 0.45

@export var move_speed := 6.5
@export var acceleration := 28.0

@onready var visual: Node3D = $Visual
@onready var umbrella_visual: Node3D = $Visual/Umbrella
@onready var chair_visual: Node3D = $Visual/ChairWeapon
@onready var kicking_foot: MeshInstance3D = $Visual/FootR
@onready var punch_arm: MeshInstance3D = $Visual/ArmR
@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var feedback: Node3D = get_node("../CombatFeedback")

var loadout: Array[int] = [Weapon.UMBRELLA, Weapon.POT]
var edit_slot := 0
var health := 100
var max_health := 100
var downed := false
var knockdown := false
var knockdown_time := 0.0
var revive_time := 0.0
var spawn_point := Vector3.ZERO
var mounted := false
var banner := ""
var banner_time := 0.0
var last_combat_event: CombatEvent
var last_hit_intent

var cd := {
	"punch": 0.0,
	"kick": 0.0,
	"dash": 0.0,
	"block": 0.0,
	"spin": 0.0,
	"coffee": 0.0,
	"drink": 0.0,
	"pot": 0.0,
	"slam": 0.0,
	"chair": 0.0,
	"mount": 0.0,
}

var hit_pause := 0.0
var flinch_time := 0.0
var flinch_side := 1.0
var blink_cooldown := 0.0
var dash_time := 0.0
var dash_trail_time := 0.0
var dash_direction := Vector3.ZERO
var dash_targets: Array[Node] = []
var dash_followup_timer := 0.0
var uppercut_time := 0.0
var spin_time := 0.0
var spin_facing := 0.0
var spin_hit_done := false
var spin_ghost_time := 0.0
var buffered_attack := ""
var buffered_until := 0
var umbrella_rest := Vector3.ZERO
var kick_time := 0.0
var punch_time := 0.0
var cancel_time := 0.0
var combo_count := 0
var combo_timer := 0.0
var punch_index := 0
var punch_chain := 0.0
var stagger_time := 0.0
var juggled := false
var victim_float := 0.0
var float_apex := false
var bounce_pending := false
var juggle_hits := 0
var float_session := false
var air_punch_hold_used := false
var kick_bounce := false
var airborne := false
var body_exceptions: Array = []
var crouching := false
var net_crouch := false
var head_carrier: Node = null
var head_rider: Node = null
var head_lock := 0.0
var capsule: CapsuleShape3D
var capsule_node: CollisionShape3D
var stand_height := 1.7
var stand_shape_y := 0.0
var block_time := 0.0
var speed_buff_time := 0.0
var action_lock := 0.0
var forced_facing := 0.0
var pot_time := 0.0
var drink_time := 0.0
var push_cd := {}
var controls_locked := true
var net_puppet := false
var net_simulated := false
var net_move := Vector3.ZERO
var net_aim := Vector3.ZERO
var scripted_drive := false
var scripted_move := Vector3.ZERO
var scripted_aim := Vector3.ZERO
var net_samples: Array = []
var owner_peer := 0
var team_id := -1
var slot_index := 0
var seated := false
var chair_ride := false
var net_pinned := false
var net_goal := Vector3.ZERO
var has_net_goal := false
var net_send_seq := 0
var net_recv_seq := 0
var net_hold_correction := false
var net_hold_until_msec := 0

var chair_rest_position := Vector3.ZERO
var arm_rest := Vector3.ZERO
var arm_l_rest := Vector3.ZERO
var foot_l_rest := Vector3.ZERO
var foot_r_rest := Vector3.ZERO
var body_rest := Vector3.ZERO
var pot_span := 0.7
var walk_phase := 0.0
var arm_l: MeshInstance3D
var foot_l: MeshInstance3D
var body_mesh: MeshInstance3D
var tail_mesh: MeshInstance3D
var ear_l: MeshInstance3D
var ear_r: MeshInstance3D
var pot_visual: Node3D
var cup_visual: Node3D
var aim_marker: MeshInstance3D
var aim_marker_material: StandardMaterial3D

func _ready() -> void:
	if net_puppet:
		remove_from_group("player")
		add_to_group("combat_targets")
		add_to_group("fighters")
	else:
		add_to_group("player")
	setup_capsule()
	spawn_point = global_position
	chair_rest_position = chair_visual.position
	umbrella_rest = umbrella_visual.position
	arm_rest = punch_arm.position
	arm_l = visual.get_node("ArmL")
	foot_l = visual.get_node("FootL")
	body_mesh = visual.get_node("Body")
	tail_mesh = visual.get_node("Tail")
	ear_l = visual.get_node("EarL")
	ear_r = visual.get_node("EarR")
	arm_l_rest = arm_l.position
	foot_l_rest = foot_l.position
	foot_r_rest = kicking_foot.position
	body_rest = body_mesh.position
	strip_runtime_props()
	paint_character()
	pot_visual = make_pot_prop()
	cup_visual = make_cup_prop()
	cup_visual.position = Vector3(0.18, 0.42, -0.62)
	if net_puppet:
		return
	aim_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.28
	aim_marker.mesh = ring
	aim_marker_material = StandardMaterial3D.new()
	aim_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_marker_material.albedo_color = Color(1, 0.95, 0.8, 0.9)
	aim_marker.material_override = aim_marker_material
	aim_marker.visible = false
	get_parent().add_child.call_deferred(aim_marker)

func strip_runtime_props() -> void:
	var keep := {
		"Body": true, "Head": true, "Muzzle": true, "Nose": true,
		"EarL": true, "EyeL": true, "ArmL": true, "FootL": true,
		"EarR": true, "EyeR": true, "ArmR": true, "FootR": true,
		"Collar": true, "Badge": true, "Tail": true,
		"Umbrella": true, "ChairWeapon": true,
	}
	var extra: Array[Node] = []
	for child in visual.get_children():
		if not keep.has(child.name):
			extra.append(child)
	for child in extra:
		visual.remove_child(child)
		child.free()

func paint_mesh(node: Node, color: Color, roughness := 0.62) -> void:
	if not node is MeshInstance3D:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	(node as MeshInstance3D).material_override = material

func paint_character() -> void:
	paint_mesh(body_mesh, Color("f3d2a4"))
	paint_mesh(visual.get_node("Head"), Color("efc99a"))
	paint_mesh(visual.get_node("Muzzle"), Color("fff4e4"), 0.45)
	paint_mesh(visual.get_node("Nose"), Color("2b241e"), 0.35)
	paint_mesh(ear_l, Color("e2b27c"))
	paint_mesh(ear_r, Color("e2b27c"))
	paint_mesh(visual.get_node("EyeL"), Color("1c1c1c"), 0.25)
	paint_mesh(visual.get_node("EyeR"), Color("1c1c1c"), 0.25)
	paint_mesh(punch_arm, Color("f3d2a4"))
	paint_mesh(arm_l, Color("f3d2a4"))
	paint_mesh(kicking_foot, Color("c4844a"), 0.5)
	paint_mesh(foot_l, Color("c4844a"), 0.5)
	paint_mesh(tail_mesh, Color("e8c08a"))
	paint_mesh(visual.get_node("Collar"), Color("c43737"), 0.4)
	paint_mesh(visual.get_node("Badge"), Color("f0c84a"), 0.35)
	preload("res://art_direction.gd").dress_player(visual)

func add_cylinder(parent: Node3D, radius: float, height: float, color: Color, at: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.86
	mesh.height = height
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	paint_mesh(mesh_instance, color, 0.42)
	parent.add_child(mesh_instance)

func make_pot_prop() -> Node3D:
	var prop := Node3D.new()
	prop.visible = false
	visual.add_child(prop)
	add_cylinder(prop, 0.28, 0.16, Color("5c656e"), Vector3.ZERO)
	add_cylinder(prop, 0.32, 0.035, Color("d7dde2"), Vector3(0, 0.09, 0))
	var handle := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.48, 0.09, 0.12)
	handle.mesh = preload("res://art_direction.gd").rounded_box(box.size)
	handle.position = Vector3(0.48, 0.02, 0)
	paint_mesh(handle, Color("a86b45"), 0.4)
	prop.add_child(handle)
	prop.position = Vector3(0.28, 0.25, -0.7)
	return prop

func make_cup_prop() -> Node3D:
	var prop := Node3D.new()
	prop.visible = false
	visual.add_child(prop)
	add_cylinder(prop, 0.1, 0.2, Color("f6efe2"), Vector3.ZERO)
	add_cylinder(prop, 0.055, 0.12, Color("6b3a28"), Vector3(0, 0.02, 0))
	var handle := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.047
	ring.outer_radius = 0.066
	handle.mesh = ring
	handle.rotation.x = PI / 2
	handle.position = Vector3(0.12, 0, 0)
	paint_mesh(handle, Color("f6efe2"), 0.4)
	prop.add_child(handle)
	prop.position = Vector3(0.18, 0.42, -0.62)
	return prop

var external_combat_view := false

func _process(delta: float) -> void:
	if external_combat_view:
		# Independent battle mode: simulation and action phases belong to CombatWorld.
		# This branch only animates; no legacy hits, correction, cooldowns or respawn.
		flinch_time = maxf(0.0,flinch_time-delta)
		banner_time = maxf(0.0,banner_time-delta)
		combo_timer = maxf(0.0,combo_timer-delta)
		if combo_timer<=0: combo_count = 0
		walk_phase += delta*Vector2(velocity.x,velocity.z).length()*2.4
		if not net_puppet: refresh_aim()
		if spin_time>0:
			spin_ghost_time -= delta
			if spin_ghost_time<=0:
				spin_ghost_time = 0.05
				feedback.spin_ghost(global_position+Vector3.UP*0.35,visual.rotation.y)
		apply_body_pose(delta)
		update_visuals()
		return
	tick_cooldowns(delta)
	blink_cooldown = maxf(0.0, blink_cooldown - delta)
	dash_followup_timer = maxf(0.0, dash_followup_timer - delta)
	uppercut_time = maxf(0.0, uppercut_time - delta)
	kick_time = maxf(0.0, kick_time - delta)
	punch_time = maxf(0.0, punch_time - delta)
	cancel_time = maxf(0.0, cancel_time - delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	punch_chain = maxf(0.0, punch_chain - delta)
	stagger_time = maxf(0.0, stagger_time - delta)
	victim_float = maxf(0.0, victim_float - delta)
	if combo_timer <= 0.0:
		combo_count = 0
	if punch_chain <= 0.0 and action_lock <= 0.0:
		punch_index = 0
	block_time = maxf(0.0, block_time - delta)
	speed_buff_time = maxf(0.0, speed_buff_time - delta)
	action_lock = maxf(0.0, action_lock - delta)
	forced_facing = maxf(0.0, forced_facing - delta)
	pot_time = maxf(0.0, pot_time - delta)
	drink_time = maxf(0.0, drink_time - delta)
	banner_time = maxf(0.0, banner_time - delta)
	flinch_time = maxf(0.0, flinch_time - delta)
	var spin_before := spin_time
	spin_time = maxf(0.0, spin_time - delta)
	if (not net_puppet or net_simulated) and not spin_hit_done and spin_before > SPIN_HIT_AT and spin_time <= SPIN_HIT_AT:
		spin_hit_done = true
		resolve_umbrella_spin()
	if spin_time > 0.0:
		spin_ghost_time -= delta
		if spin_ghost_time <= 0.0:
			spin_ghost_time = 0.05
			feedback.spin_ghost(global_position + Vector3.UP * 0.35, visual.rotation.y)
	if net_puppet and not net_simulated:
		present_remote()
		var shown := Vector2(velocity.x, velocity.z).length()
		if shown > 0.6 and kick_time <= 0.0 and punch_time <= 0.0:
			walk_phase += delta * shown * 2.4
		apply_body_pose(delta)
		apply_crouch_shape()
		update_visuals()
		return
	var moving := Vector2(velocity.x, velocity.z).length()
	if moving > 0.6 and action_lock <= 0.0 and kick_time <= 0.0 and dash_time <= 0.0:
		walk_phase += delta * moving * 2.4
	refresh_aim()
	if banner_time <= 0.0:
		banner = ""
	tick_push_cooldowns(delta)
	if downed:
		mounted = false
		dash_time = 0.0
		dash_followup_timer = 0.0
		cancel_time = 0.0
		combo_count = 0
		combo_timer = 0.0
		punch_chain = 0.0
		punch_index = 0
		stagger_time = 0.0
		juggled = false
		knockdown = false
		knockdown_time = 0.0
		victim_float = 0.0
		bounce_pending = false
		revive_time -= delta
		if revive_time <= 0.0:
			revive()
	elif knockdown:
		knockdown_time -= delta
		if knockdown_time <= 0.0:
			knockdown = false
			knockdown_time = 0.0
	apply_body_pose(delta)
	apply_crouch_shape()
	update_visuals()

func tick_cooldowns(delta: float) -> void:
	for key in cd.keys():
		cd[key] = maxf(0.0, float(cd[key]) - delta)

func tick_push_cooldowns(delta: float) -> void:
	var stale: Array = []
	for who in push_cd.keys():
		if not is_instance_valid(who):
			stale.append(who)
			continue
		push_cd[who] = float(push_cd[who]) - delta
		if float(push_cd[who]) <= 0.0:
			stale.append(who)
	for who in stale:
		push_cd.erase(who)

func apply_body_pose(delta: float) -> void:
	var laying := downed or knockdown
	var floating := (juggled or kick_bounce) and not laying
	var speed := 14.0
	if laying:
		visual.rotation.x = lerp_angle(visual.rotation.x, 0.0, speed * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, deg_to_rad(88.0), speed * delta)
		visual.position.y = lerpf(visual.position.y, -0.46, speed * delta)
	elif floating:
		var lean := deg_to_rad(50.0) if kick_bounce else deg_to_rad(35.0)
		visual.rotation.x = lerp_angle(visual.rotation.x, lean, speed * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, 0.0, speed * delta)
		visual.position.y = lerpf(visual.position.y, 0.0, speed * delta)
	else:
		visual.rotation.x = lerp_angle(visual.rotation.x, 0.0, 16.0 * delta)
		visual.rotation.z = lerp_angle(visual.rotation.z, flinch_tilt(), 16.0 * delta)
		visual.position.y = lerpf(visual.position.y, 0.0, 16.0 * delta)

func flinch_tilt() -> float:
	if flinch_time <= 0.0 or downed:
		return 0.0
	var amount := clampf(flinch_time / 0.2, 0.0, 1.0)
	return sin(amount * PI) * 0.28 * flinch_side

func update_visuals() -> void:
	var spinning := spin_time > 0.0
	if spinning:
		var progress := 1.0 - spin_time / SPIN_DURATION
		var flare := sin(progress * PI)
		visual.scale = Vector3(1.0 + flare * 0.22, 1.0 - flare * 0.14, 1.0 + flare * 0.22)
		visual.rotation.y = spin_facing + progress * TAU * 2.0
	elif flinch_time > 0.0 and not downed and not knockdown:
		var amount := clampf(flinch_time / 0.2, 0.0, 1.0)
		visual.scale = Vector3(1.0 + amount * 0.2, 1.0 - amount * 0.16, 1.0 + amount * 0.2)
	else:
		visual.scale = Vector3.ONE
	umbrella_visual.visible = spinning or dash_time > 0.0 or uppercut_time > 0.0 or block_time > 0.0
	umbrella_visual.scale = Vector3.ONE
	umbrella_visual.position = umbrella_rest
	if spinning:
		var flare := sin((1.0 - spin_time / SPIN_DURATION) * PI)
		umbrella_visual.rotation.x = -0.4 - flare * 1.15
		umbrella_visual.scale = Vector3.ONE * (1.15 + flare * 0.95)
		umbrella_visual.position = umbrella_rest + Vector3(0.15, 0.42 * flare, -0.25)
	elif uppercut_time > 0.0:
		umbrella_visual.rotation.x = -sin((1.0 - uppercut_time / 0.3) * PI) * 0.8
	elif block_time > 0.0:
		umbrella_visual.rotation.x = -1.05
	else:
		umbrella_visual.rotation.x = 0.0
	chair_visual.visible = mounted
	chair_visual.position = Vector3(0, -0.62, 0.05) if mounted else chair_rest_position
	chair_visual.rotation = Vector3.ZERO
	var moving := Vector2(velocity.x, velocity.z).length()
	var stride := sin(walk_phase) if moving > 0.6 and kick_time <= 0.0 and action_lock <= 0.0 else 0.0
	body_mesh.position = body_rest + Vector3(0, absf(stride) * 0.035, 0)
	foot_l.position = foot_l_rest + Vector3(0, maxf(0.0, stride) * 0.12, stride * 0.08)
	kicking_foot.position = foot_r_rest
	kicking_foot.rotation = Vector3.ZERO
	if kick_time > 0.0:
		var kick_swing := sin((1.0 - kick_time / 0.3) * PI)
		kicking_foot.position.z = foot_r_rest.z - kick_swing * 0.62
		kicking_foot.position.y = foot_r_rest.y + kick_swing * 0.18
		kicking_foot.rotation.x = -kick_swing * 0.9
	else:
		kicking_foot.position.z = foot_r_rest.z - stride * 0.08
		kicking_foot.position.y = foot_r_rest.y + maxf(0.0, -stride) * 0.12
	punch_arm.position = arm_rest
	punch_arm.rotation = Vector3.ZERO
	arm_l.position = arm_l_rest
	arm_l.rotation = Vector3.ZERO
	if uppercut_time > 0.0:
		var up_swing := sin((1.0 - uppercut_time / 0.3) * PI)
		punch_arm.rotation.x = -0.5 - up_swing * 1.7
		punch_arm.position.y = arm_rest.y + up_swing * 0.42
		punch_arm.position.z = arm_rest.z - up_swing * 0.2
	elif spinning:
		var flare := sin((1.0 - spin_time / SPIN_DURATION) * PI)
		punch_arm.rotation.z = -1.15 * flare
		arm_l.rotation.z = 1.15 * flare
		punch_arm.position.x = arm_rest.x + 0.22 * flare
		arm_l.position.x = arm_l_rest.x - 0.22 * flare
	elif punch_time > 0.0:
		var punch_swing := sin((1.0 - punch_time / 0.2) * PI)
		punch_arm.rotation.x = -punch_swing * 1.25
		punch_arm.position.z = arm_rest.z - punch_swing * 0.5
		arm_l.rotation.x = punch_swing * 0.35
	elif moving > 0.6:
		punch_arm.rotation.x = stride * 0.45
		arm_l.rotation.x = -stride * 0.45
	if tail_mesh:
		tail_mesh.rotation.z = sin(walk_phase * 0.5) * 0.25
	if ear_l:
		ear_l.rotation.z = sin(walk_phase) * 0.08
		ear_r.rotation.z = -sin(walk_phase) * 0.08
	pot_visual.visible = pot_time > 0.0
	if pot_time > 0.0:
		var swing := sin((1.0 - pot_time / maxf(pot_span, 0.05)) * PI)
		pot_visual.position = Vector3(0.2, 0.15 + swing * 0.85, -0.45 - swing * 0.35)
		pot_visual.rotation.x = -swing * 1.4
	cup_visual.visible = drink_time > 0.0
	if crouching and not downed and not knockdown and not juggled and not kick_bounce:
		visual.scale = Vector3(visual.scale.x, visual.scale.y * 0.62, visual.scale.z)
		visual.position.y -= 0.2

func _unhandled_input(event: InputEvent) -> void:
	if net_puppet or controls_locked:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	else:
		return
	if not pressed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var battle_net := get_tree().get_first_node_in_group("network")
	if battle_net and battle_net.has_method("using_battle_server") and battle_net.using_battle_server():
		var action := ""
		if event is InputEventMouseButton:
			action = "punch" if event.button_index == MOUSE_BUTTON_LEFT else ("kick" if event.button_index == MOUSE_BUTTON_RIGHT else "")
		elif event is InputEventKey:
			action = str({KEY_Q:"skill_a0",KEY_E:"skill_a1",KEY_F:"skill_b0",KEY_C:"skill_b1",KEY_SPACE:"jump",KEY_SHIFT:"blink"}.get(event.physical_keycode,""))
		if not action.is_empty():
			battle_net.request_action(action,aim_direction())
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			replicate_action("punch")
			punch()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			replicate_action("kick")
			kick()
		return
	if event is InputEventKey:
		match event.physical_keycode:
			KEY_1:
				equip_focused(Weapon.UMBRELLA)
			KEY_2:
				equip_focused(Weapon.COFFEE)
			KEY_3:
				equip_focused(Weapon.POT)
			KEY_4:
				equip_focused(Weapon.CHAIR)
			KEY_TAB:
				edit_slot = 1 - edit_slot
				banner = "更换武器 %s" % ("A" if edit_slot == 0 else "B")
				banner_time = 0.8
			KEY_Q:
				replicate_action("skill_a0")
				cast_weapon_skill(0, 0)
			KEY_E:
				replicate_action("skill_a1")
				cast_weapon_skill(0, 1)
			KEY_F:
				replicate_action("skill_b0")
				cast_weapon_skill(1, 0)
			KEY_C:
				replicate_action("skill_b1")
				cast_weapon_skill(1, 1)
			KEY_SHIFT:
				replicate_action("blink")
				short_blink()
			KEY_SPACE:
				replicate_action("jump")
				jump()

func can_act() -> bool:
	return not downed and not knockdown and not mounted and not juggled and dash_time <= 0.0 and action_lock <= 0.0 and block_time <= 0.0 and stagger_time <= 0.0

func can_chain() -> bool:
	if downed or knockdown or mounted or juggled or dash_time > 0.0 or block_time > 0.0 or stagger_time > 0.0:
		return false
	return action_lock <= 0.0 or cancel_time > 0.0

func _buffer_attack(id: String) -> void:
	if downed or knockdown or mounted or juggled or kick_bounce or stagger_time > 0.0:
		return
	var now := Time.get_ticks_msec()
	if buffered_attack == id and now <= buffered_until:
		return
	buffered_attack = id
	buffered_until = now + BattleRules.BUFFER_MS

func _clear_attack_buffer() -> void:
	buffered_attack = ""
	buffered_until = 0

func _buffer_ready(id: String) -> bool:
	match id:
		"spin":
			return can_act() and float(cd["spin"]) <= 0.0
		"slam":
			return can_chain() and float(cd["slam"]) <= 0.0
		"pot":
			return can_act() and float(cd["pot"]) <= 0.0 and not is_instance_valid(active_pot)
		"dash":
			return dash_followup_timer <= 0.0 and can_act() and float(cd["dash"]) <= 0.0
		"uppercut":
			return dash_followup_timer > 0.0 and not downed and not mounted and not (action_lock > 0.0 and cancel_time <= 0.0)
	return false

func _release_buffered_attack() -> void:
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("using_battle_server") and net.using_battle_server():
		return
	if buffered_attack == "":
		return
	if Time.get_ticks_msec() > buffered_until:
		_clear_attack_buffer()
		return
	if not _buffer_ready(buffered_attack):
		return
	var id := buffered_attack
	_clear_attack_buffer()
	match id:
		"spin":
			umbrella_spin()
		"slam":
			pot_slam()
		"pot":
			throw_pot()
		"dash":
			umbrella_action()
		"uppercut":
			umbrella_uppercut()

func equip_focused(next: int) -> void:
	if not can_act():
		return
	var other := 1 - edit_slot
	if loadout[edit_slot] == next:
		return
	if loadout[other] == next:
		loadout[other] = loadout[edit_slot]
	loadout[edit_slot] = next
	banner = "武器%s %s" % ["A" if edit_slot == 0 else "B", WEAPON_NAMES[next]]
	banner_time = 0.9

func cast_weapon_skill(slot: int, skill_index: int) -> void:
	var chosen: int = loadout[slot]
	if skill_index == 0:
		match chosen:
			Weapon.UMBRELLA:
				umbrella_action()
			Weapon.COFFEE:
				throw_coffee()
			Weapon.POT:
				throw_pot()
			Weapon.CHAIR:
				summon_chair()
		return
	if chosen == Weapon.CHAIR and mounted:
		chair_mount_toggle()
		return
	match chosen:
		Weapon.UMBRELLA:
			umbrella_spin()
		Weapon.COFFEE:
			drink_coffee()
		Weapon.POT:
			pot_slam()
		Weapon.CHAIR:
			chair_mount_toggle()

func punch() -> void:
	if foe_juggled(1.95, 3.2):
		air_punch()
		return
	var chaining := punch_chain > 0.0
	if not can_chain() or (not chaining and float(cd["punch"]) > 0.0):
		return
	var step := mini(punch_index + 1, 2) if chaining else 0
	cancel_time = 0.0
	punch_chain = 0.0
	punch_index = step
	cd["punch"] = 0.45 if step >= 2 else 0.28
	action_lock = 0.22 if step >= 2 else 0.16
	punch_time = 0.2 if step >= 2 else 0.14
	var forward := facing_direction()
	feedback.play_swing()
	await get_tree().create_timer(0.08 if step >= 2 else 0.05).timeout
	if not is_inside_tree() or downed:
		return
	var intent_id := "punch_light"
	if step == 1:
		intent_id = "punch_follow"
	elif step >= 2:
		intent_id = "punch_uppercut"
	var hits := strike_targets(intent_id, forward)
	feedback.attack_arc(global_position + Vector3.UP * 0.35, forward, 1.05, Color("ffe1a4"), step >= 2)
	if hits > 0 and step < 2:
		punch_chain = PUNCH_LINK
		punch_index = step
	else:
		punch_chain = 0.0
		punch_index = 0

func air_punch() -> void:
	if not can_chain():
		return
	punch_chain = 0.0
	punch_index = 0
	cancel_time = 0.0
	cd["punch"] = 0.28
	action_lock = 0.16
	punch_time = 0.14
	var forward := facing_direction()
	feedback.play_swing()
	await get_tree().create_timer(0.05).timeout
	if not is_inside_tree() or downed:
		return
	strike_targets("punch_air", forward)
	feedback.attack_arc(global_position + Vector3.UP * 0.5, forward, 1.1, Color("ffe1a4"))

func kick() -> void:
	if not can_chain() or float(cd["kick"]) > 0.0:
		return
	cancel_time = 0.0
	cd["kick"] = CD_KICK
	action_lock = 0.26
	kick_time = 0.3
	var forward := facing_direction()
	feedback.play_swing()
	await get_tree().create_timer(0.08).timeout
	if not is_inside_tree() or downed:
		return
	strike_targets("kick_front", forward)
	feedback.attack_arc(global_position, forward, 1.4, Color("f5be86"))

func umbrella_action() -> void:
	if downed or knockdown or mounted:
		return
	if dash_followup_timer > 0.0:
		block_time = 0.0
		umbrella_uppercut()
		return
	if dash_time > 0.0 or action_lock > 0.0 or float(cd["dash"]) > 0.0:
		if action_lock > 0.0:
			_buffer_attack("dash")
		return
	block_time = 0.0
	start_dash()

func start_dash() -> void:
	if not can_act() or float(cd["dash"]) > 0.0:
		return
	drop_from_head()
	drop_rider()
	dash_direction = facing_direction()
	dash_time = 0.38
	dash_trail_time = 0.0
	cd["dash"] = CD_DASH
	dash_followup_timer = 0.0
	dash_targets.clear()
	feedback.dash_start()

func umbrella_uppercut() -> void:
	if downed or mounted or block_time > 0.0:
		return
	if action_lock > 0.0 and cancel_time <= 0.0:
		_buffer_attack("uppercut")
		return
	cancel_time = 0.0
	dash_followup_timer = 0.0
	dash_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	uppercut_time = 0.3
	action_lock = BattleRules.UPPERCUT_LOCK
	feedback.play_swing()
	var forward := facing_direction()
	await get_tree().create_timer(BattleRules.UPPERCUT_HIT).timeout
	if not is_inside_tree() or downed:
		return
	strike_targets("umbrella_uppercut", forward)
	feedback.attack_arc(global_position + Vector3.UP * 0.4, forward, 1.7, Color("85e2dd"), true)

func start_block() -> void:
	if not can_act() or float(cd["block"]) > 0.0:
		return
	block_time = BLOCK_DURATION
	cd["block"] = CD_BLOCK
	feedback.play_swing()

func umbrella_spin() -> void:
	if not can_act() or float(cd["spin"]) > 0.0:
		if action_lock > 0.0 and dash_time <= 0.0:
			_buffer_attack("spin")
		return
	cd["spin"] = CD_SPIN
	spin_time = SPIN_DURATION
	spin_facing = visual.rotation.y
	spin_hit_done = false
	spin_ghost_time = 0.0
	action_lock = SPIN_DURATION
	forced_facing = SPIN_DURATION
	velocity.x = 0.0
	velocity.z = 0.0
	feedback.play_swing()
	feedback.spin_burst(global_position + Vector3.UP * 0.2, false)

func resolve_umbrella_spin() -> void:
	feedback.spin_burst(global_position + Vector3.UP * 0.25, true)
	var facing := Vector3(-sin(spin_facing), 0.0, -cos(spin_facing))
	strike_radial_targets("umbrella_spin", facing)

func throw_coffee() -> void:
	if not can_act() or float(cd["coffee"]) > 0.0:
		return
	var forward := throw_horizontal_direction()
	cd["coffee"] = CD_COFFEE
	action_lock = 0.16
	spawn_projectile(THROWN_ITEM.ItemKind.COFFEE, coffee_velocity(forward), forward)
	feedback.play_swing()

func drink_coffee() -> void:
	if not can_act() or float(cd["drink"]) > 0.0:
		return
	cd["drink"] = CD_DRINK
	speed_buff_time = BUFF_DURATION
	drink_time = 0.45
	banner = "加速"
	banner_time = 1.0
	feedback.play_swing()

func throw_pot() -> void:
	if is_instance_valid(active_pot):
		if not downed and not knockdown:
			active_pot.recall(true)
			var net := get_tree().get_first_node_in_group("network")
			if in_net_match() and multiplayer.is_server():
				net.rpc("recall_remote_pot", owner_peer if net_puppet else multiplayer.get_unique_id())
		return
	if not can_act() or float(cd["pot"]) > 0.0:
		if action_lock > 0.0 and dash_time <= 0.0:
			_buffer_attack("pot")
		return
	var forward := facing_direction()
	cd["pot"] = CD_POT
	action_lock = 0.18
	pot_span = 0.22
	pot_time = 0.22
	if not in_net_match() or multiplayer.is_server():
		active_pot = RETURNING_POT.new()
		get_parent().add_child(active_pot)
		active_pot.global_position = global_position + Vector3.UP * 0.85 + forward * 0.65
		active_pot.launch(self, forward)
		var net := get_tree().get_first_node_in_group("network")
		if in_net_match():
			net.rpc("spawn_remote_pot", owner_peer if net_puppet else multiplayer.get_unique_id(), active_pot.global_position, forward)
	feedback.play_swing()

func pot_outbound(direction: Vector3) -> void:
	FloatRules.pot_hit(self, direction, false)

func pot_return(direction: Vector3) -> void:
	FloatRules.pot_hit(self, direction, true)

func pot_slam() -> void:
	if not can_chain() or float(cd["slam"]) > 0.0:
		if action_lock > 0.0 and cancel_time <= 0.0:
			_buffer_attack("slam")
		return
	var forward := aim_direction()
	var aerial := foe_juggled(BattleRules.SLAM_RANGE, BattleRules.SLAM_HEIGHT)
	face_to(forward)
	forced_facing = 0.55 if aerial else 0.65
	cancel_time = 0.0
	cd["slam"] = CD_SLAM
	pot_span = BattleRules.SLAM_AIR_ANIM if aerial else BattleRules.SLAM_GROUND_ANIM
	action_lock = BattleRules.timing("pot_slam",aerial).y
	pot_time = pot_span
	velocity = BattleRules.slam_startup(velocity, forward, aerial, is_on_floor())
	feedback.play_swing()
	await get_tree().create_timer(BattleRules.timing("pot_slam",aerial).x).timeout
	if not is_inside_tree() or downed:
		return
	strike_targets("pot_slam", forward)

func summon_chair() -> void:
	if not can_act() or float(cd["chair"]) > 0.0:
		return
	if not get_tree().get_nodes_in_group("rushing_chairs").is_empty():
		return
	var forward := aim_direction()
	face_to(forward)
	forced_facing = 0.35
	cd["chair"] = CD_CHAIR
	feedback.play_swing()
	if in_net_match() and not multiplayer.is_server():
		return
	var chair := RUSHING_CHAIR.new()
	get_parent().add_child(chair)
	chair.global_position = global_position + forward * 1.15
	chair.global_position.y = 0.0
	chair.launch(self, forward)
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("announce_chair") and net.in_match():
		net.announce_chair(chair.global_position, chair.direction)

func chair_mount_toggle() -> void:
	if downed or knockdown or float(cd["mount"]) > 0.0:
		return
	if mounted:
		drop_from_head()
		drop_rider()
		mounted = false
		cd["mount"] = CD_MOUNT
		return
	if not can_act():
		return
	drop_from_head()
	drop_rider()
	mounted = true
	cd["mount"] = CD_MOUNT
	velocity.x = 0.0
	velocity.z = 0.0
	feedback.play_swing()

func spawn_projectile(kind: int, projectile_velocity: Vector3, forward: Vector3) -> void:
	if in_net_match() and not multiplayer.is_server():
		return
	var item := THROWN_ITEM.new()
	get_parent().add_child(item)
	item.global_position = global_position + Vector3.UP * 0.45 + forward * 0.7
	item.launch_with_velocity(kind, projectile_velocity, get_rid())
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("announce_throw") and net.in_match():
		net.announce_throw(kind, item.global_position, projectile_velocity)

func can_hurt(target: Node) -> bool:
	if target == self or (net_puppet and not net_simulated):
		return false
	var other_team = target.get("team_id")
	if team_id < 0 or other_team == null or int(other_team) < 0:
		return true
	if int(other_team) == team_id and (target.get("net_puppet") or target.is_in_group("fighters")):
		return false
	return true

func connect_hit(target: Node, method: String, direction: Vector3, attack_name := "") -> bool:
	if target == null or not is_instance_valid(target) or not can_hurt(target):
		return false
	if target.get("downed") or target.get("knockdown"):
		return false
	if target.is_in_group("hall_dummies"):
		var hall_net := get_tree().get_first_node_in_group("network")
		if hall_net and hall_net.in_match() and hall_net.has_method("relay_dummy_hit"):
			return hall_net.relay_dummy_hit(target, method, direction, attack_name)
	if in_net_match() and (target.get("net_puppet") or target.is_in_group("fighters") or target.is_in_group("player")):
		var fight_net := get_tree().get_first_node_in_group("network")
		if fight_net and fight_net.has_method("host_apply_hit"):
			if not multiplayer.is_server():
				return false
			return fight_net.host_apply_hit(self, target, method, direction, attack_name)
	if target.get("net_puppet"):
		var net := get_tree().get_first_node_in_group("network")
		if net and net.in_match() and net.has_method("relay_hit"):
			return net.relay_hit(target, method, direction, attack_name)
	if method != "" and target.has_method(method):
		target.call(method, direction)
		return true
	if attack_name != "" and target.has_method("take_hit"):
		target.take_hit(attack_name)
		return true
	return false

func in_net_match() -> bool:
	var net := get_tree().get_first_node_in_group("network")
	return net != null and net.has_method("in_match") and net.in_match()

func replicate_action(action: String) -> void:
	if net_puppet or not in_net_match():
		return
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("using_battle_server") and net.using_battle_server():
		net.request_action(action, aim_direction())
		return
	if multiplayer.is_server():
		return
	if net and net.has_method("request_action"):
		net.request_action(action, aim_direction())

func call_action(action: String) -> void:
	match action:
		"punch":
			punch()
		"kick":
			kick()
		"skill_a0":
			cast_weapon_skill(0, 0)
		"skill_a1":
			cast_weapon_skill(0, 1)
		"skill_b0":
			cast_weapon_skill(1, 0)
		"skill_b1":
			cast_weapon_skill(1, 1)
		"blink":
			short_blink()
		"jump":
			jump()

func capture_control() -> Dictionary:
	if scripted_drive:
		var aim := scripted_aim if scripted_aim.length_squared() > 0.001 else scripted_move
		return {"move": scripted_move, "aim": aim, "crouch": false}
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
	return {"move": direction, "aim": aim_direction(), "crouch": Input.is_key_pressed(KEY_CTRL)}

func push_net_sample(state: Dictionary) -> void:
	net_samples.append({
		"t": Time.get_ticks_msec(),
		"p": state["p"],
		"f": float(state["f"]),
		"jug": bool(state["jug"]),
		"down": bool(state["down"]),
		"kd": bool(state.get("kd", false)),
		"kb": bool(state.get("kb", false)),
		"cr": bool(state.get("cr", false)),
		"hp": int(state["hp"]),
	})
	var cutoff := Time.get_ticks_msec() - 500
	while net_samples.size() > 2 and int(net_samples[0]["t"]) < cutoff:
		net_samples.remove_at(0)

func present_remote() -> void:
	if net_samples.is_empty():
		return
	var show_t := Time.get_ticks_msec() - 100
	var newest: Dictionary = net_samples[net_samples.size() - 1]
	juggled = bool(newest["jug"])
	kick_bounce = bool(newest.get("kb", false))
	crouching = bool(newest.get("cr", false))
	downed = bool(newest["down"])
	knockdown = bool(newest["kd"])
	health = int(newest["hp"])
	if int(newest["t"]) <= show_t or net_samples.size() == 1:
		global_position = newest["p"]
		visual.rotation.y = float(newest["f"])
		return
	var older: Dictionary = net_samples[0]
	var newer: Dictionary = newest
	for index in range(net_samples.size() - 1):
		var left: Dictionary = net_samples[index]
		var right: Dictionary = net_samples[index + 1]
		if int(left["t"]) <= show_t and show_t <= int(right["t"]):
			older = left
			newer = right
			break
	var span := maxi(1, int(newer["t"]) - int(older["t"]))
	var weight := clampf(float(show_t - int(older["t"])) / float(span), 0.0, 1.0)
	global_position = (older["p"] as Vector3).lerp(newer["p"], weight)
	visual.rotation.y = lerp_angle(float(older["f"]), float(newer["f"]), weight)

func reconcile_owner(state: Dictionary) -> void:
	health = int(state["hp"])
	air_punch_hold_used = bool(state.get("fph", air_punch_hold_used))
	var host_down := bool(state["down"])
	var host_kd := bool(state.get("kd", false))
	if host_down != downed:
		downed = host_down
	if host_kd != knockdown:
		knockdown = host_kd
	var host_pos: Vector3 = state["p"]
	var gap := global_position.distance_to(host_pos)
	if gap > 3.0:
		global_position = host_pos
		velocity = state["v"]
	elif gap > 1.2:
		global_position = global_position.lerp(host_pos, 0.2)

func capture_net_state() -> Dictionary:
	net_send_seq += 1
	return {
		"seq": net_send_seq,
		"p": global_position,
		"v": velocity,
		"bf": bounce_pending,
		"vf": victim_float,
		"f": spin_facing if spin_time > 0.0 else visual.rotation.y,
		"hp": health,
		"down": downed,
		"kd": knockdown,
		"jug": juggled,
		"fs": float_session,
		"fph": air_punch_hold_used,
		"kb": kick_bounce,
		"cr": crouching,
		"mount": mounted,
		"block": block_time,
		"punch": punch_time,
		"kick": kick_time,
		"dash": dash_time,
		"spin": spin_time,
		"up": uppercut_time,
		"pot": pot_time,
		"drink": drink_time,
		"stag": stagger_time,
	}

func apply_net_state(state: Dictionary) -> void:
	if not net_puppet or not state.has("p"):
		return
	var seq := int(state.get("seq", 0))
	if seq > 0 and seq <= net_recv_seq:
		return
	if seq > 0:
		net_recv_seq = seq
	health = int(state["hp"])
	downed = bool(state["down"])
	knockdown = bool(state.get("kd", false))
	var snapshot_air := bool(state["jug"]) or bool(state.get("kb", false)) or bool(state.get("bf", false))
	if downed or knockdown or snapshot_air or Time.get_ticks_msec() >= net_hold_until_msec:
		net_hold_correction = false
		net_hold_until_msec = 0
	elif net_hold_correction:
		return
	juggled = bool(state["jug"])
	float_session = bool(state.get("fs", false))
	air_punch_hold_used = bool(state.get("fph", false))
	kick_bounce = bool(state.get("kb", false))
	bounce_pending = bool(state.get("bf", false))
	victim_float = float(state.get("vf", victim_float))
	mounted = bool(state["mount"])
	block_time = float(state["block"])
	punch_time = float(state["punch"])
	kick_time = float(state["kick"])
	dash_time = float(state["dash"])
	spin_time = float(state.get("spin", 0.0))
	if spin_time > 0.0:
		spin_facing = float(state["f"])
	uppercut_time = float(state["up"])
	pot_time = float(state["pot"])
	drink_time = float(state["drink"])
	stagger_time = float(state["stag"])
	velocity = state["v"]
	if spin_time <= 0.0:
		visual.rotation.y = float(state["f"])
	net_goal = state["p"]
	var gap := global_position.distance_to(net_goal)
	if not has_net_goal or gap > 8.0:
		global_position = net_goal
	has_net_goal = true

func airborne_net() -> bool:
	return juggled or kick_bounce or bounce_pending

func predict_net_hit(method: String, direction: Vector3) -> void:
	if not net_puppet or downed or knockdown:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3(-sin(visual.rotation.y), 0.0, -cos(visual.rotation.y))
	else:
		flat = flat.normalized()
	match method:
		"launch_up":
			juggled = true
			kick_bounce = false
			bounce_pending = false
			FloatRules.start_launch(self)
			FloatRules.begin_float(self)
			victim_float = 0.95
			velocity = flat * 1.4 + Vector3.UP * FloatRules.UMBRELLA_LAUNCH_SPEED
		"punch_launch":
			if juggled or kick_bounce:
				predict_net_hit("punch_from", direction)
				return
			juggled = true
			kick_bounce = false
			bounce_pending = false
			FloatRules.start_launch(self)
			FloatRules.begin_float(self)
			victim_float = 0.9
			velocity = flat * 2.0 + Vector3.UP * FloatRules.PUNCH_LAUNCH_SPEED
		"kick_from":
			if juggled or kick_bounce:
				juggled = false
				kick_bounce = true
				bounce_pending = false
				victim_float = 0.18
				velocity = flat * 18.0 + Vector3.UP * 2.2
			else:
				velocity = flat * 7.5 + Vector3.UP * 0.4
		"punch_from", "punch_follow":
			if juggled or kick_bounce:
				juggled = true
				FloatRules.extend(self, FloatRules.PUNCH_HOLD)
				victim_float = maxf(victim_float, 0.35)
			else:
				velocity.x = flat.x * 3.0
				velocity.z = flat.z * 3.0
		"slam_from_pot":
			if juggled or kick_bounce:
				juggled = true
				kick_bounce = false
				bounce_pending = true
				victim_float = 0.0
				velocity = flat * 1.4 + Vector3.DOWN * 16.0
			else:
				velocity = Vector3.ZERO
		"pot_float":
			if juggled and not bounce_pending and not kick_bounce:
				FloatRules.extend(self, FloatRules.POT_LIFT)
				victim_float = maxf(victim_float, 0.35)
		"umbrella_spin_from":
			if juggled and not bounce_pending and not kick_bounce:
				FloatRules.extend(self, FloatRules.SPIN_LIFT)
				victim_float = maxf(victim_float, 0.35)
		"shove_from":
			if not juggled:
				velocity = flat * 8.0 + Vector3.UP * 0.6
		"dash_hit_from":
			velocity.x = flat.x * 3.0
			velocity.z = flat.z * 3.0
	net_hold_correction = true
	net_hold_until_msec = Time.get_ticks_msec() + 90

func step_puppet_air(delta: float) -> void:
	if net_pinned or downed or knockdown or not airborne_net():
		return
	var gravity := 20.0
	if kick_bounce:
		gravity = 16.0
	elif juggled or bounce_pending:
		FloatRules.step_float(self, delta)
		slide_body()
		if net_hold_correction or not has_net_goal:
			return
		var error := net_goal - global_position
		if error.length() > 8.0:
			global_position = net_goal
		elif error.length() > 0.08:
			global_position += error * minf(1.0, 5.0 * delta)
		return
	velocity.y -= gravity * delta
	slide_body()
	if net_hold_correction or not has_net_goal:
		return
	var error := net_goal - global_position
	if error.length() > 8.0:
		global_position = net_goal
	elif error.length() > 0.08:
		global_position += error * minf(1.0, 5.0 * delta)

func reset_for_round() -> void:
	if is_instance_valid(active_pot):
		active_pot.queue_free()
	active_pot = null
	health = max_health
	downed = false
	knockdown = false
	knockdown_time = 0.0
	revive_time = 0.0
	mounted = false
	seated = false
	chair_ride = false
	net_pinned = false
	has_net_goal = false
	net_hold_correction = false
	net_hold_until_msec = 0
	juggled = false
	bounce_pending = false
	victim_float = 0.0
	float_apex = false
	juggle_hits = 0
	float_session = false
	air_punch_hold_used = false
	kick_bounce = false
	crouching = false
	head_lock = 0.0
	stagger_time = 0.0
	action_lock = 0.0
	block_time = 0.0
	dash_time = 0.0
	dash_followup_timer = 0.0
	punch_time = 0.0
	kick_time = 0.0
	uppercut_time = 0.0
	spin_time = 0.0
	spin_hit_done = true
	pot_time = 0.0
	drink_time = 0.0
	speed_buff_time = 0.0
	cancel_time = 0.0
	combo_count = 0
	combo_timer = 0.0
	punch_chain = 0.0
	punch_index = 0
	blink_cooldown = 0.0
	hit_pause = 0.0
	forced_facing = 0.0
	banner = ""
	banner_time = 0.0
	velocity = Vector3.ZERO
	drop_from_head(0.0)
	drop_rider()
	if capsule != null:
		apply_crouch_shape()
	for key in cd.keys():
		cd[key] = 0.0

func strike_targets(intent_id: String, forward: Vector3) -> int:
	var intent = HitIntentData.melee(intent_id, get_instance_id(), forward, Engine.get_physics_frames())
	last_hit_intent = intent
	var targets := HitDetection.find_melee_targets(self, intent)
	var hits := 0
	for target in targets:
		if connect_hit(target, intent.effect_method, intent.direction):
			hits += 1
	if hits > 0:
		register_combo(hits)
	return hits

func strike_radial_targets(intent_id: String, fallback_direction: Vector3) -> int:
	var intent = HitIntentData.melee(intent_id, get_instance_id(), fallback_direction, Engine.get_physics_frames())
	var targets := HitDetection.find_melee_targets(self, intent)
	var hits := 0
	for target in targets:
		var outward: Vector3 = target.global_position - global_position
		outward.y = 0.0
		if outward.length_squared() < 0.0025:
			outward = fallback_direction
		else:
			outward = outward.normalized()
		intent.direction = outward
		last_hit_intent = intent
		if connect_hit(target, intent.effect_method, outward):
			hits += 1
	if hits > 0:
		register_combo(hits)
	return hits

func register_combo(hits: int) -> void:
	if hits <= 0 or downed:
		return
	combo_count += hits
	combo_timer = 1.7
	cancel_time = maxf(cancel_time, 0.42)

func foe_juggled(reach: float, height_limit: float) -> bool:
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("using_battle_server") and net.using_battle_server():
		return net.get_node("BattleClientSession").foe_juggled(reach,height_limit)
	for target in get_tree().get_nodes_in_group("combat_targets"):
		if target.get("downed") or not target.has_method("is_juggled") or not target.is_juggled():
			continue
		var to_target: Vector3 = target.global_position - global_position
		var height_gap := absf(to_target.y)
		to_target.y = 0.0
		if height_gap <= height_limit and to_target.length() <= reach:
			return true
	return false

func short_blink() -> void:
	if downed or knockdown or mounted or dash_time > 0.0 or action_lock > 0.0 or block_time > 0.0 or blink_cooldown > 0.0:
		return
	drop_from_head()
	drop_rider()
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
	if downed or knockdown or mounted or dash_time > 0.0 or action_lock > 0.0 or juggled or kick_bounce:
		return
	if head_carrier != null:
		drop_from_head(0.0)
		velocity.y = 7.5
		return
	if is_on_floor():
		velocity.y = 7.5

func hit_locked() -> bool:
	return downed or knockdown

func begin_knockdown() -> void:
	if downed or knockdown:
		return
	knockdown = true
	knockdown_time = FloatRules.KNOCKDOWN_TIME
	_clear_attack_buffer()
	airborne = false
	juggled = false
	kick_bounce = false
	bounce_pending = false
	victim_float = 0.0
	stagger_time = 0.0
	flinch_time = 0.0
	action_lock = 0.0
	dash_time = 0.0
	block_time = 0.0
	punch_time = 0.0
	kick_time = 0.0
	uppercut_time = 0.0
	spin_time = 0.0
	pot_time = 0.0
	drink_time = 0.0
	mounted = false
	chair_ride = false
	seated = false
	drop_from_head()
	drop_rider()
	velocity = Vector3.ZERO
	FloatRules.end_session(self)
	feedback.impact(global_position + Vector3.UP * 0.2, false)

func take_hit(attack_name: String = "文件夹") -> void:
	if hit_locked():
		return
	_clear_attack_buffer()
	var state := CombatStateData.from_body(self)
	state.blocking = block_time > 0.0
	var result := CombatRules.resolve_hit(state, attack_name, AttackData.PROFILE_PVP)
	last_combat_event = result
	if result.blocked:
		banner = "格挡"
		banner_time = 0.7
		feedback.play_swing()
		return
	drop_from_head()
	drop_rider()
	var damage := result.damage
	state.apply_health_to(self)
	banner = "%s -%d" % [attack_name, damage]
	banner_time = 1.2
	flinch_time = 0.2
	flinch_side = 1.0 if randf() > 0.5 else -1.0
	var heavy := attack_name in ["雨伞挑飞", "扣锅", "空中扣锅", "踢飞", "上勾拳"]
	feedback.impact(global_position + Vector3.UP * 0.9, heavy, 0, "-%d" % damage)
	stagger_time = maxf(stagger_time, 0.28 if attack_name == "踢飞" else HITSTUN)
	if health <= 0:
		health = 0
		mounted = false
		block_time = 0.0
		dash_time = 0.0
		action_lock = 0.0
		downed = true
		knockdown = false
		knockdown_time = 0.0
		revive_time = 3.0
		banner = "3秒后复活"
		FloatRules.end_session(self)
		bounce_pending = false
		victim_float = 0.0
		chair_ride = false
		seated = false
		velocity = Vector3.ZERO

func revive() -> void:
	downed = false
	health = max_health
	global_position = spawn_point
	velocity = Vector3.ZERO
	banner = "复活"
	banner_time = 0.8

func is_juggled() -> bool:
	return juggled and not downed and not knockdown

func punch_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if juggled:
		take_hit("补拳")
		if downed or bounce_pending:
			return
		velocity.x = direction.x * 2.0
		velocity.z = direction.z * 2.0
		FloatRules.extend(self, FloatRules.PUNCH_HOLD)
		return
	if kick_bounce:
		take_hit("补拳")
		return
	take_hit("轻拳")
	if downed:
		return
	velocity.x = direction.x * 3.0
	velocity.z = direction.z * 3.0

func punch_follow(direction: Vector3) -> void:
	if hit_locked():
		return
	if juggled or kick_bounce:
		punch_from(direction)
		return
	take_hit("连拳")
	if downed:
		return
	velocity.x = direction.x * 3.0
	velocity.z = direction.z * 3.0

func punch_launch(direction: Vector3) -> void:
	if hit_locked():
		return
	if juggled or kick_bounce:
		punch_from(direction)
		return
	take_hit("上勾拳")
	if downed:
		return
	resolve_combat_motion("uppercut_launch", direction)

func kick_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if juggled:
		take_hit("踢飞")
		if downed:
			return
		resolve_combat_motion("air_kick", direction, combo_count)
		return
	take_hit("前踢")
	if downed:
		return
	velocity = direction * 7.5 + Vector3.UP * 0.4

func launch_up(direction: Vector3) -> void:
	if hit_locked():
		return
	take_hit("雨伞挑飞")
	if downed:
		return
	resolve_combat_motion("umbrella_launch", direction)

func slam_from_pot(direction: Vector3) -> void:
	if hit_locked():
		return
	if juggled or kick_bounce:
		take_hit("空中扣锅")
		if downed:
			return
		resolve_combat_motion("air_slam", direction)
		return
	take_hit("扣锅")
	if downed:
		return
	resolve_combat_motion("ground_slam", direction)

func capture_combat_state() -> CombatState:
	var state := CombatStateData.from_body(self)
	state.float_session = float_session
	state.air_punch_hold_used = air_punch_hold_used
	state.float_apex = float_apex
	state.float_timer = victim_float
	state.airborne = airborne
	state.stun_time = stagger_time
	return state

func apply_combat_motion(state: CombatState) -> void:
	velocity = state.velocity
	juggled = state.juggled
	kick_bounce = state.kick_bounce
	bounce_pending = state.bounce_pending
	float_session = state.float_session
	air_punch_hold_used = state.air_punch_hold_used
	float_apex = state.float_apex
	victim_float = state.float_timer
	airborne = state.airborne
	stagger_time = state.stun_time
	juggle_hits = state.juggle_hits

func resolve_combat_motion(effect: String, direction: Vector3, attacker_combo := 0) -> void:
	var state := capture_combat_state()
	last_combat_event = CombatRules.resolve_motion(state, effect, direction, AttackData.PROFILE_PVP, attacker_combo)
	apply_combat_motion(state)

func bump(direction: Vector3, speed: float) -> void:
	if hit_locked() or chair_ride:
		return
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func dash_hit_from(direction: Vector3) -> void:
	if hit_locked():
		return
	take_hit("雨伞")
	if downed or chair_ride:
		return
	bump(direction, 3.0)

func umbrella_spin_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if chair_ride or seated:
		drop_from_chair(Vector3.ZERO)
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	if juggled and not bounce_pending and not kick_bounce:
		take_hit("旋伞")
		if downed or bounce_pending or kick_bounce or not juggled:
			return
		velocity = BattleRules.apply_spin_velocity(velocity, flat, true, false, false)
		float_apex = false
		return
	take_hit("旋伞")
	if downed:
		return
	velocity = BattleRules.apply_spin_velocity(velocity, flat, false, kick_bounce, bounce_pending)
	if not kick_bounce and not bounce_pending:
		stagger_time = BattleRules.SPIN_GROUND_STUN

func shove_from(direction: Vector3) -> void:
	if hit_locked() or chair_ride:
		return
	take_hit("椅推")
	if downed or juggled:
		return
	velocity = direction * 8.0 + Vector3.UP * 0.6

func pot_float(_direction: Vector3 = Vector3.ZERO) -> void:
	if hit_locked():
		return
	take_hit("锅")
	if downed or bounce_pending or kick_bounce or not juggled:
		return
	FloatRules.extend(self, FloatRules.POT_LIFT)

func begin_chair_ride(_direction: Vector3) -> void:
	if hit_locked() or chair_ride:
		return
	take_hit("办公椅")
	if downed:
		return
	chair_ride = true
	seated = true
	juggled = false
	kick_bounce = false
	stagger_time = 0.0
	velocity = Vector3.ZERO

func drop_from_chair(_direction: Vector3 = Vector3.ZERO) -> void:
	var was_riding := chair_ride or seated
	chair_ride = false
	seated = false
	net_pinned = false
	velocity = Vector3.ZERO
	airborne = false
	if was_riding:
		FloatRules.end_session(self)

func end_chair_ride(throw_velocity: Vector3) -> void:
	var was_riding := chair_ride or seated
	chair_ride = false
	seated = false
	net_pinned = false
	if not was_riding or downed:
		return
	if not float_session:
		velocity = Vector3.ZERO
		airborne = false
		return
	FloatRules.begin_float(self)
	stagger_time = 0.0
	juggled = true
	kick_bounce = false
	bounce_pending = false
	airborne = true
	victim_float = 0.5
	var pop := throw_velocity
	velocity = pop

func apply_chair_control_event(event) -> void:
	match str(event.control):
		"grab":
			begin_chair_ride(event.direction)
		"release":
			drop_from_chair(event.direction)
		"throw":
			end_chair_ride(event.direction)
		_:
			return
	# Keep local animation and feedback from the existing methods, then replace
	# their approximated state with the server's control decision.
	health = event.health
	downed = event.downed
	velocity = event.velocity
	juggled = event.juggled
	kick_bounce = event.kick_bounce
	bounce_pending = event.bounce_pending
	victim_float = event.float_timer
	float_session = event.float_session
	airborne = event.airborne
	seated = event.seated
	chair_ride = event.chair_ride
	net_pinned = event.pinned
	global_position = event.position

func facing_direction() -> Vector3:
	var forward := -visual.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()

func wants_throw_aim() -> bool:
	return has_coffee() or has_pot()

func has_coffee() -> bool:
	return loadout[0] == Weapon.COFFEE or loadout[1] == Weapon.COFFEE

func has_pot() -> bool:
	return loadout[0] == Weapon.POT or loadout[1] == Weapon.POT

func camera_look() -> Vector3:
	if net_simulated and net_aim.length_squared() > 0.001:
		return net_aim
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return facing_direction()
	return -cam.global_transform.basis.z

func center_flat_direction() -> Vector3:
	var look := camera_look()
	look.y = 0.0
	if look.length_squared() < 0.001:
		return facing_direction()
	return look.normalized()

func uses_center_aim() -> bool:
	return facing_direction().dot(center_flat_direction()) >= cos(deg_to_rad(30.0))

func throw_horizontal_direction() -> Vector3:
	if uses_center_aim():
		return center_flat_direction()
	return facing_direction()

func coffee_launch_angle() -> float:
	if not uses_center_aim():
		return deg_to_rad(28.0)
	var look := camera_look()
	var flat_length := Vector2(look.x, look.z).length()
	var pitch := atan2(look.y, maxf(flat_length, 0.001))
	if pitch >= 0.0:
		var upward := clampf(pitch / deg_to_rad(40.0), 0.0, 1.0)
		return lerpf(deg_to_rad(26.0), deg_to_rad(70.0), upward)
	var downward := clampf(-pitch / deg_to_rad(55.0), 0.0, 1.0)
	return lerpf(deg_to_rad(26.0), deg_to_rad(-38.0), downward)

func coffee_velocity(horizontal: Vector3) -> Vector3:
	var angle := coffee_launch_angle()
	return horizontal * cos(angle) * 11.0 + Vector3.UP * sin(angle) * 11.0

func refresh_aim() -> void:
	if aim_marker == null or not aim_marker.is_inside_tree():
		return
	if not has_coffee() or downed:
		aim_marker.visible = false
		return
	var forward := throw_horizontal_direction()
	var origin := global_position + Vector3.UP * 0.45 + forward * 0.7
	var landing := predict_coffee_landing(origin, coffee_velocity(forward))
	aim_marker.visible = true
	aim_marker.global_position = Vector3(landing.x, 0.06, landing.z)
	aim_marker.scale = Vector3.ONE
	aim_marker_material.albedo_color = Color(1.0, 0.95, 0.82, 0.85)

func predict_coffee_landing(origin: Vector3, projectile_velocity: Vector3) -> Vector3:
	var pos := origin
	var vel := projectile_velocity
	var space := get_world_3d().direct_space_state
	for _i in 70:
		var next := pos + vel * 0.05
		vel.y -= 13.0 * 0.05
		var query := PhysicsRayQueryParameters3D.create(pos, next)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit.position
		if next.y <= 0.05:
			return Vector3(next.x, 0.05, next.z)
		pos = next
	return pos

func aim_direction() -> Vector3:
	if net_simulated and net_aim.length_squared() > 0.001:
		return net_aim
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	if cam == null:
		return facing_direction()
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return facing_direction()
	return forward.normalized()

func face_to(direction: Vector3) -> void:
	if direction.length_squared() < 0.001:
		return
	visual.rotation.y = atan2(-direction.x, -direction.z)

func current_speed() -> float:
	var speed := 10.0 if mounted else move_speed
	if speed_buff_time > 0.0:
		speed *= 1.4
	if crouching:
		speed *= 0.55
	return speed

func slide_body() -> void:
	move_and_slide()
	FloatRules.slip_off_bodies(self)
	if head_lock <= 0.0 and head_carrier == null and not FloatRules.launched_air(self):
		try_mount_head()

func setup_capsule() -> void:
	capsule_node = $CollisionShape3D
	capsule = (capsule_node.shape as CapsuleShape3D).duplicate()
	capsule_node.shape = capsule
	stand_height = capsule.height
	stand_shape_y = capsule_node.position.y

func crouch_held() -> bool:
	if net_simulated:
		return net_crouch
	if net_puppet or controls_locked or scripted_drive:
		return false
	return Input.is_key_pressed(KEY_CTRL)

func refresh_crouch() -> void:
	var want := crouch_held()
	if downed or knockdown or juggled or kick_bounce or bounce_pending or head_carrier != null or mounted or chair_ride:
		want = false
	if crouching == want:
		return
	crouching = want
	apply_crouch_shape()

func apply_crouch_shape() -> void:
	if capsule == null or capsule_node == null:
		return
	if crouching:
		capsule.height = maxf(stand_height * 0.68, capsule.radius * 2.0 + 0.05)
		capsule_node.position.y = stand_shape_y - (stand_height - capsule.height) * 0.5
	else:
		capsule.height = stand_height
		capsule_node.position.y = stand_shape_y

func launched_air() -> bool:
	return FloatRules.launched_air(self)

func ride_move_input() -> Vector3:
	if net_simulated:
		return net_move
	if scripted_drive:
		return scripted_move
	if net_puppet or controls_locked:
		return Vector3.ZERO
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if wasd.length_squared() > 0.0:
		input_vector = wasd.normalized()
	if camera == null or input_vector.length_squared() <= 0.0:
		return Vector3.ZERO
	var right := camera.global_transform.basis.x
	var forward := -camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	if right.length_squared() < 0.001 or forward.length_squared() < 0.001:
		return Vector3.ZERO
	return (right.normalized() * input_vector.x + forward.normalized() * -input_vector.y).normalized()

func foot_offset() -> float:
	return global_position.y - FloatRules.capsule_bottom_y(self)

func stick_to_carrier() -> void:
	if head_carrier == null or not is_instance_valid(head_carrier):
		return
	var stand_y := FloatRules.capsule_top_y(head_carrier) + foot_offset()
	global_position = Vector3(head_carrier.global_position.x, stand_y, head_carrier.global_position.z)
	velocity = Vector3.ZERO

func try_mount_head() -> void:
	if head_lock > 0.0 or head_carrier != null or launched_air() or downed or knockdown:
		return
	try_mount_dummy_head()
	if head_carrier != null or not is_on_floor():
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().y < 0.65:
			continue
		var other := hit.get_collider()
		if other is Node and is_head_platform(other):
			mount_head(other)
			return
	try_mount_dummy_head()

func is_head_platform(other: Node) -> bool:
	if other == self:
		return false
	if not other.is_in_group("player") and not other.is_in_group("fighters") and not other.is_in_group("training_dummies") and not other.is_in_group("hall_dummies"):
		return false
	if other.get("downed") or other.get("knockdown") or other.get("juggled") or other.get("kick_bounce"):
		return false
	if other.get("head_carrier") != null:
		return false
	var rider = other.get("head_rider")
	return rider == null or not is_instance_valid(rider) or rider == self

func try_mount_dummy_head() -> void:
	if velocity.y > 0.35:
		return
	var feet := FloatRules.capsule_bottom_y(self)
	for group_name in ["training_dummies", "hall_dummies"]:
		for dummy in get_tree().get_nodes_in_group(group_name):
			if not dummy is Node3D or not is_head_platform(dummy):
				continue
			var body := dummy as Node3D
			var flat := global_position - body.global_position
			flat.y = 0.0
			if flat.length() > 0.72:
				continue
			var top := FloatRules.capsule_top_y(body)
			if feet < top - 0.62 or feet > top + 0.2:
				continue
			mount_head(body)
			return

func mount_head(carrier: Node) -> void:
	head_carrier = carrier
	carrier.head_rider = self
	if carrier is CollisionObject3D:
		add_collision_exception_with(carrier)
		(carrier as CollisionObject3D).add_collision_exception_with(self)
	stick_to_carrier()

func drop_from_head(hop := 0.8) -> void:
	if head_carrier == null:
		return
	var carrier := head_carrier
	head_carrier = null
	head_lock = 0.28
	if is_instance_valid(carrier):
		if carrier.get("head_rider") == self:
			carrier.head_rider = null
		if carrier is CollisionObject3D:
			remove_collision_exception_with(carrier)
			(carrier as CollisionObject3D).remove_collision_exception_with(self)
	velocity.y = hop

func drop_rider() -> void:
	if head_rider == null or not is_instance_valid(head_rider):
		head_rider = null
		return
	if head_rider.has_method("drop_from_head"):
		head_rider.drop_from_head()
	else:
		head_rider = null

func place_rider() -> void:
	if head_rider == null or not is_instance_valid(head_rider):
		head_rider = null
		return
	if head_rider.get("head_carrier") != self:
		head_rider = null
		return
	if head_rider.has_method("stick_to_carrier"):
		head_rider.stick_to_carrier()

func _physics_process(delta: float) -> void:
	if net_puppet and not net_simulated:
		return
	if controls_locked and not net_simulated:
		return
	_release_buffered_attack()
	head_lock = maxf(0.0, head_lock - delta)
	refresh_crouch()
	if chair_ride:
		drop_rider()
		velocity = Vector3.ZERO
		return
	if head_carrier != null and (not is_instance_valid(head_carrier) or launched_air() or downed or knockdown):
		drop_from_head()
	if head_carrier != null and ride_move_input().length_squared() > 0.01:
		drop_from_head(0.2)
	if head_carrier != null:
		stick_to_carrier()
		if not net_simulated and not scripted_drive:
			var look := aim_direction()
			if look.length_squared() > 0.001:
				face_to(look)
		return
	if hit_pause > 0.0:
		hit_pause = maxf(0.0, hit_pause - delta)
		velocity = Vector3.ZERO
		slide_body()
		return
	if downed or knockdown:
		drop_rider()
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 20.0 * delta
		slide_body()
		return
	if spin_time > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 20.0 * delta
		slide_body()
		return
	if kick_bounce and dash_time <= 0.0:
		velocity.y -= 16.0 * delta
		slide_body()
		if FloatRules.try_kick_wall(self):
			juggled = true
			airborne = true
			FloatRules.begin_float(self)
			victim_float = 0.48
		elif FloatRules.on_arena_floor(self) and victim_float <= 0.0:
			begin_knockdown()
		return
	if juggled and dash_time <= 0.0:
		FloatRules.step_float(self, delta)
		slide_body()
		if FloatRules.on_arena_floor(self):
			if bounce_pending:
				bounce_pending = false
				FloatRules.begin_float(self)
				victim_float = 0.4
				velocity.y = 5.0
			elif float_apex and velocity.y <= 0.2:
				begin_knockdown()
		return
	if stagger_time > 0.0 and dash_time <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		velocity.y -= 20.0 * delta
		slide_body()
		return
	var direction := Vector3.ZERO
	if net_simulated:
		direction = net_move
		if dash_time <= 0.0 and forced_facing <= 0.0 and net_aim.length_squared() > 0.001:
			face_to(net_aim)
	elif scripted_drive:
		direction = scripted_move
		if dash_time <= 0.0 and forced_facing <= 0.0 and scripted_aim.length_squared() > 0.001:
			face_to(scripted_aim)
	else:
		var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var wasd := Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		)
		if wasd.length_squared() > 0.0:
			input_vector = wasd.normalized()
		if camera and input_vector.length_squared() > 0.0:
			var right := camera.global_transform.basis.x
			var forward := -camera.global_transform.basis.z
			right.y = 0.0
			forward.y = 0.0
			direction = (right.normalized() * input_vector.x + forward.normalized() * -input_vector.y).normalized()
	var target_velocity := direction * current_speed()
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
	slide_body()
	if was_dashing:
		resolve_dash_hits()
	elif mounted:
		push_nearby()
	elif not net_simulated and direction.length_squared() > 0.01 and forced_facing <= 0.0:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 12.0 * delta)
	place_rider()

func resolve_dash_hits() -> void:
	for target in get_tree().get_nodes_in_group("combat_targets"):
		if dash_targets.has(target) or not target.has_method("take_hit") or target.get("downed"):
			continue
		var to_target: Vector3 = target.global_position - global_position
		var height_gap := absf(to_target.y)
		to_target.y = 0.0
		if height_gap > 2.2 or to_target.length() > 1.25:
			continue
		if to_target.length() > 0.15 and to_target.normalized().dot(dash_direction) <= 0.15:
			continue
		if not connect_hit(target, "dash_hit_from", dash_direction):
			continue
		dash_targets.append(target)
		dash_time = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		break
	if dash_time <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		dash_followup_timer = FOLLOWUP_WINDOW

func push_nearby() -> void:
	if Vector2(velocity.x, velocity.z).length() < 1.5:
		return
	var push_dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	for i in get_slide_collision_count():
		var body := get_slide_collision(i).get_collider()
		if not (body is Node) or not body.has_method("shove_from") or push_cd.has(body):
			continue
		if body.get("downed") or body.get("seated") or body.get("chair_ride"):
			continue
		if not connect_hit(body, "shove_from", push_dir):
			continue
		push_cd[body] = 0.45

func has_umbrella() -> bool:
	return loadout[0] == Weapon.UMBRELLA or loadout[1] == Weapon.UMBRELLA

func equipment_slots() -> Array:
	var slots: Array = []
	for i in WEAPON_NAMES.size():
		var equipped := loadout[0] == i or loadout[1] == i
		var focused := loadout[edit_slot] == i
		var title := WEAPON_NAMES[i]
		if loadout[0] == i:
			title = "A " + title
		elif loadout[1] == i:
			title = "B " + title
		slots.append({
			"key": str(i + 1),
			"name": title,
			"remain": 0.0,
			"max_cd": 0.0,
			"highlight": false,
			"selected": focused,
			"equipped": equipped,
		})
	return slots

func skill_slots() -> Array:
	var punch_name := "挥拳"
	var punch_hot := false
	var punch_remain := float(cd["punch"])
	if foe_juggled(2.2, 3.4):
		punch_name = "补拳"
		punch_hot = true
		punch_remain = 0.0
	elif punch_chain > 0.0:
		punch_name = "上勾" if punch_index >= 1 else "连拳"
		punch_hot = true
		punch_remain = 0.0
	var punch_slot := pack_slot("左键", punch_name, punch_remain, CD_PUNCH, punch_hot)
	var kick_slot := pack_slot("右键", "前踢", float(cd["kick"]), CD_KICK, foe_juggled(2.6, 3.5))
	var primary: Array = weapon_skill_pair(loadout[0], "Q", "E")
	var secondary: Array = weapon_skill_pair(loadout[1], "F", "C")
	return [punch_slot, kick_slot, primary[0], primary[1], secondary[0], secondary[1]]

func weapon_skill_pair(chosen: int, key_one: String, key_two: String) -> Array:
	match chosen:
		Weapon.UMBRELLA:
			var dash_name := "冲锋"
			var dash_remain := float(cd["dash"])
			if dash_followup_timer > 0.0:
				dash_name = "挑飞 %.1f" % dash_followup_timer
				dash_remain = 0.0
			return [
				pack_slot(key_one, dash_name, dash_remain, CD_DASH, dash_followup_timer > 0.0),
				pack_slot(key_two, "旋伞", float(cd["spin"]), CD_SPIN, foe_juggled(SPIN_REACH, SPIN_HEIGHT)),
			]
		Weapon.COFFEE:
			return [
				pack_slot(key_one, "投掷", float(cd["coffee"]), CD_COFFEE),
				pack_slot(key_two, "喝咖啡", float(cd["drink"]), CD_DRINK),
			]
		Weapon.POT:
			var slam_name := "扣锅"
			var slam_hot := false
			if foe_juggled(2.6, 3.5):
				slam_name = "空中扣锅"
				slam_hot = true
			return [
				pack_slot(key_one, "快速召回" if is_instance_valid(active_pot) else "回旋锅", 0.0 if is_instance_valid(active_pot) else float(cd["pot"]), CD_POT, is_instance_valid(active_pot)),
				pack_slot(key_two, slam_name, float(cd["slam"]), CD_SLAM, slam_hot),
			]
		_:
			return [
				pack_slot(key_one, "冲椅", float(cd["chair"]), CD_CHAIR),
				pack_slot(key_two, "下椅" if mounted else "坐下", float(cd["mount"]), CD_MOUNT),
			]

func pack_slot(key: String, slot_name: String, remain: float, max_cd: float, highlight := false) -> Dictionary:
	return {
		"key": key,
		"name": slot_name,
		"remain": remain,
		"max_cd": max_cd,
		"highlight": highlight,
		"selected": false,
		"equipped": false,
	}

func status_text() -> String:
	var parts: PackedStringArray = []
	if downed:
		parts.append("倒地 %.1f" % maxf(revive_time, 0.0))
	elif knockdown:
		parts.append("倒地保护 %.1f" % maxf(knockdown_time, 0.0))
	if crouching:
		parts.append("下蹲")
	if head_carrier != null:
		parts.append("站在头上")
	if speed_buff_time > 0.0:
		parts.append("加速 %.1f" % speed_buff_time)
	if block_time > 0.0:
		parts.append("格挡 %.1f" % block_time)
	if mounted:
		parts.append("坐在椅子上")
	if dash_followup_timer > 0.0 and has_umbrella():
		parts.append("可挑飞")
	if stagger_time > 0.0:
		parts.append("硬直")
	if combo_count >= 2:
		parts.append("%d HIT" % combo_count)
	if banner != "":
		parts.append(banner)
	return "  |  ".join(parts)
