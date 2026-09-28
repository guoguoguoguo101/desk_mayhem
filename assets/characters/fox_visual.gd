extends Node3D

## Visual-only animation. Combat timing, hit checks and movement stay in the
## existing simulation. The tail/ears clip is a separate additive layer.
@onready var animation_tree: AnimationTree = $AnimationTree

var playback: AnimationNodeStateMachinePlayback
var current_body := ""
var previous_airborne := false
var previous_knockdown := false
var previous_blink_cooldown := 0.0
var land_time := 0.0
var get_up_time := 0.0
var blink_time := 0.0

func _ready() -> void:
	animation_tree.active = true
	animation_tree.set("parameters/TailAdd/add_amount", 1.0)
	playback = animation_tree.get("parameters/Body/playback") as AnimationNodeStateMachinePlayback
	if playback != null:
		playback.start(&"Idle")
		current_body = "Idle"

func _process(delta: float) -> void:
	var player := get_parent().get_parent()
	if not player is CharacterBody3D or playback == null:
		return
	var in_air := _is_airborne(player)
	if previous_airborne and not in_air:
		land_time = 0.22
	if previous_knockdown and not player.knockdown:
		get_up_time = 0.45
	if player.blink_cooldown > previous_blink_cooldown + 0.25:
		blink_time = 0.2
	previous_airborne = in_air
	previous_knockdown = player.knockdown
	previous_blink_cooldown = player.blink_cooldown
	land_time = maxf(0.0, land_time - delta)
	get_up_time = maxf(0.0, get_up_time - delta)
	blink_time = maxf(0.0, blink_time - delta)
	var next := _body_action(player)
	if next != current_body:
		playback.travel(next)
		current_body = next

func _body_action(player: CharacterBody3D) -> StringName:
	if player.downed:
		return &"Death"
	if player.knockdown:
		return &"Knockdown"
	if player.flinch_time > 0.0:
		return &"Hit"
	if get_up_time > 0.0:
		return &"GetUp"
	if blink_time > 0.0:
		return &"Blink"
	if player.uppercut_time > 0.0:
		return &"UmbrellaUppercut"
	if player.spin_time > 0.0:
		return &"UmbrellaSpin"
	if player.kick_time > 0.0:
		return &"KickFront"
	if player.punch_time > 0.0:
		if player.fox_attack_id == "punch_uppercut":
			return &"PunchUppercut"
		if player.fox_attack_id == "punch_follow":
			return &"PunchFollow"
		if player.fox_attack_id == "punch_air":
			return &"PunchAir"
		if player.punch_index >= 3:
			return &"PunchUppercut"
		if player.punch_index == 2:
			return &"PunchFollow"
		return &"PunchLight"
	if player.pot_time > 0.0:
		if player.pot_span > 0.3:
			return &"PotSlamAir" if player.pot_span < 0.55 else &"PotSlam"
		return &"PotThrow"
	if player.dash_time > 0.0:
		return &"UmbrellaDash"
	if player.crouching:
		return &"Crouch"
	if _is_airborne(player):
		return &"JumpStart" if player.velocity.y > 1.5 else &"Airborne"
	if land_time > 0.0:
		return &"Land"
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.6:
		return &"Run"
	return &"Idle"

func _is_airborne(player: CharacterBody3D) -> bool:
	var in_air: bool = player.airborne or player.juggled or player.kick_bounce
	if player.external_combat_view:
		in_air = in_air or absf(player.velocity.y) > 0.25 or player.global_position.y > player.spawn_point.y + 0.15
	else:
		in_air = in_air or (not player.is_on_floor() and absf(player.velocity.y) > 0.25)
	return in_air
