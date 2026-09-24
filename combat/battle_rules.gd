extends RefCounted
## Values copied from the local player/FloatRules, not balance changes.
const FloatLift = preload("res://float_rules.gd")
const BUFFER_MS := 150
const CD_DASH := 1.5
const CD_SPIN := 2.2
const CD_POT := 0.75
const CD_SLAM := 2.0
const CD_KICK := 0.65
const FOLLOWUP_WINDOW := 1.2
const SPIN_DURATION := 0.48
const SPIN_HIT_AT := 0.24
const SLAM_AIR_HIT := 0.2
const SLAM_GROUND_HIT := 0.46
const SLAM_AIR_LOCK := 0.34
const SLAM_GROUND_LOCK := 0.72
const SLAM_AIR_ANIM := 0.4
const SLAM_GROUND_ANIM := 0.7
const SLAM_CHASE := 4.2
const SLAM_AIR_JUMP := 6.2
const SLAM_GROUND_JUMP := 8.2
const SLAM_RANGE := 2.6
const SLAM_HEIGHT := 3.5
const SPIN_PUSH := 5.5
const SPIN_GROUND_STUN := 0.28
const UPPERCUT_HIT := 0.1
const UPPERCUT_LOCK := 0.32
const PHYSICS_HZ := 60.0
const PUNCH_LINK_MS := 650
const PUNCH_ORDER := ["punch_light", "punch_follow", "punch_uppercut"]
## One melee timing table. startup is the hit delay, active is the single
## query frame, recovery fills out the lock. Tick counts match the previous
## to_ticks() rounding. A missed punch does not advance the string.
## pot_slam_air is the airborne startup of the same slam, not a separate weapon.
const SKILLS := {
	"punch_light": {"startup": 3, "active": 1, "recovery": 6, "cancel_delay": 3, "chainable": true, "reach": 1.95, "dot": 0.15, "height": 3.2, "air_hold": true, "name": "轻拳", "air_name": "补拳", "motion": "", "air_motion": ""},
	"punch_follow": {"startup": 3, "active": 1, "recovery": 6, "cancel_delay": 3, "chainable": true, "reach": 1.95, "dot": 0.15, "height": 3.2, "air_hold": true, "name": "连拳", "air_name": "补拳", "motion": "", "air_motion": ""},
	"punch_uppercut": {"startup": 5, "active": 1, "recovery": 7, "cancel_delay": 3, "chainable": true, "reach": 1.95, "dot": 0.15, "height": 3.2, "air_hold": true, "name": "上勾拳", "air_name": "补拳", "motion": "uppercut_launch", "air_motion": ""},
	"kick_front": {"startup": 5, "active": 1, "recovery": 10, "cancel_delay": 3, "chainable": true, "reach": 2.5, "dot": 0.12, "height": 3.4, "name": "前踢", "air_name": "踢飞", "motion": "", "air_motion": "air_kick"},
	"umbrella_uppercut": {"startup": 6, "active": 1, "recovery": 12, "cancel_delay": 3, "chainable": true, "reach": 2.4, "dot": 0.2, "height": 3.2, "name": "雨伞挑飞", "air_name": "雨伞挑飞", "motion": "umbrella_launch", "air_motion": "umbrella_launch"},
	"umbrella_spin": {"startup": 14, "active": 1, "recovery": 14, "cancel_delay": 3, "chainable": false, "reach": 3.0, "dot": -1.0, "height": 2.8, "effect": "spin", "name": "旋伞", "air_name": "旋伞", "motion": "", "air_motion": ""},
	"pot_slam": {"startup": 28, "active": 1, "recovery": 14, "cancel_delay": 3, "chainable": true, "reach": 2.5, "dot": 0.1, "height": 3.5, "hop": "slam", "name": "扣锅", "air_name": "空中扣锅", "motion": "ground_slam", "air_motion": "air_slam"},
	"pot_slam_air": {"startup": 12, "active": 1, "recovery": 7, "cancel_delay": 3, "chainable": true, "reach": 2.5, "dot": 0.1, "height": 3.5, "hop": "slam", "name": "扣锅", "air_name": "空中扣锅", "motion": "ground_slam", "air_motion": "air_slam"},
}

static func is_punch(attack: String) -> bool:
	return attack in PUNCH_ORDER

static func skill_frame(attack: String, aerial := false) -> Dictionary:
	if attack == "pot_slam" and aerial:
		return SKILLS.get("pot_slam_air", {})
	return SKILLS.get(attack, {})

static func skill_total(attack: String, aerial := false) -> int:
	var frame: Dictionary = skill_frame(attack, aerial)
	if frame.is_empty():
		return 0
	return int(frame.startup) + int(frame.active) + int(frame.recovery)

## Combat timeline only: hit, cancel, and end. Ticks are offsets from action_tick.
## Equal ticks run in this order. Animation and audio stay on the client.
static func combat_timeline(attack: String, aerial := false) -> Array:
	var frame := skill_frame(attack, aerial)
	if frame.is_empty():
		return []
	var startup := int(frame.startup)
	return [
		{"tick": startup, "kind": "hit"},
		{"tick": startup + int(frame.get("cancel_delay", 0)), "kind": "cancel_open"},
		{"tick": skill_total(attack, aerial), "kind": "end"},
	]

static func skill_seconds(attack: String, aerial := false) -> float:
	return float(skill_total(attack, aerial)) / PHYSICS_HZ

## Movement during an action is independent of its attack/cancel lock.
## Directional attacks keep their aim locked; only translation uses this scale.
static func action_move_scale(attack: String) -> float:
	if is_punch(attack): return 0.7
	match attack:
		"umbrella_spin": return 0.6
		"kick_front", "umbrella_uppercut": return 0.55
		"pot_slam": return 0.35
		_: return 0.65

static func punch_frame(attack: String) -> Dictionary:
	return skill_frame(attack) if is_punch(attack) else {}

static func punch_total(attack: String) -> int:
	return skill_total(attack) if is_punch(attack) else 0

static func punch_seconds(attack: String) -> float:
	return skill_seconds(attack) if is_punch(attack) else 0.0

static func punch_id_for(combo: int, link_open: bool) -> String:
	var index := combo if link_open else 0
	return PUNCH_ORDER[clampi(index, 0, PUNCH_ORDER.size() - 1)]

static func punch_id_at(combo: int, combo_until: int, now: int) -> String:
	return punch_id_for(combo, now < combo_until)

static func confirm_punch(combo: int) -> int:
	return (combo + 1) % PUNCH_ORDER.size()

static func timing(attack: String, aerial := false) -> Vector2:
	var frame := skill_frame(attack, aerial)
	if frame.is_empty():
		return Vector2(0.05, 0.16)
	return Vector2(float(frame.startup) / PHYSICS_HZ, skill_seconds(attack, aerial))

static func chainable(attack: String) -> bool:
	return bool(skill_frame(attack).get("chainable", false))

static func melee_reach(frame: Dictionary, airborne: bool) -> float:
	var reach := float(frame.get("reach", 0.0))
	if airborne:
		reach += FloatLift.AIR_HIT_REACH
	return reach

static func melee_height(frame: Dictionary, airborne: bool) -> float:
	var height := float(frame.get("height", 0.0))
	if airborne:
		height = maxf(height, FloatLift.AIR_HIT_HEIGHT)
	return height

## Presentation-only touch test. The server still applies protection, walls, and rewind.
static func melee_touch(origin: Vector3, facing: Vector3, target: Vector3, attack: String, airborne: bool) -> bool:
	var frame := skill_frame(attack)
	if frame.is_empty() or not frame.has("reach"):
		return false
	var delta := target - origin
	if absf(delta.y) > melee_height(frame, airborne):
		return false
	var flat := Vector3(delta.x, 0.0, delta.z)
	var distance := flat.length()
	if distance > melee_reach(frame, airborne) or distance < 0.01:
		return false
	return facing.dot(flat / distance) >= float(frame.get("dot", -1.0))

## Shared hit presentation for the server and the local prediction overlay.
## Damage, protection, and rewind stay with the caller.
static func present_hit(attack: String, direction: Vector3, _height: float, velocity: Vector3, juggled: bool, kick_bounce: bool, bounce_pending: bool) -> Dictionary:
	var frame := skill_frame(attack)
	var motion := str(frame.get("motion", ""))
	if juggled:
		motion = str(frame.get("air_motion", ""))
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var result := {"velocity": velocity, "juggled": juggled, "kick_bounce": kick_bounce, "bounce_pending": bounce_pending, "stun": 0.15, "knockdown": false}
	if bool(frame.get("air_hold", false)) and juggled:
		var held := velocity
		held.x = flat.x * 1.6
		held.z = flat.z * 1.6
		held.y = maxf(held.y, FloatLift.PUNCH_HOLD_Y)
		result.velocity = held
	if motion == "uppercut_launch":
		result.velocity = flat * 2.0 + Vector3.UP * FloatLift.PUNCH_LAUNCH_SPEED
		result.juggled = true
		result.kick_bounce = false
		result.bounce_pending = false
	elif motion == "umbrella_launch":
		result.velocity = flat * 1.4 + Vector3.UP * FloatLift.UMBRELLA_LAUNCH_SPEED
		result.juggled = true
		result.kick_bounce = false
		result.bounce_pending = false
	elif motion == "air_kick":
		result.juggled = false
		result.kick_bounce = true
		result.bounce_pending = false
		result.velocity = flat * 18.0 + Vector3.UP * 2.2
	elif motion == "air_slam":
		result.kick_bounce = false
		result.bounce_pending = true
		result.velocity = flat * 1.4 + Vector3.DOWN * 16.0
	elif motion == "ground_slam":
		result.velocity = Vector3.ZERO
		result.stun = 1.2
		result.knockdown = true
	elif attack == "kick_front":
		result.velocity = flat * 7.5 + Vector3.UP * 0.4
	elif str(frame.get("effect", "")) == "spin":
		var spinning_air := juggled and not bounce_pending and not kick_bounce
		result.velocity = apply_spin_velocity(result.velocity, flat, juggled, kick_bounce, bounce_pending)
		if not spinning_air:
			result.stun = maxf(float(result.stun), SPIN_GROUND_STUN)
	return result

## Same-tick motion conflicts. Higher rank wins. Ties use attack serial, not arrival order.
## Slam, kick-away, launch, air sustain, then a plain push.
static func motion_rank(attack: String, juggled_before: bool) -> int:
	var frame := skill_frame(attack)
	var motion := str(frame.get("motion", ""))
	if juggled_before:
		motion = str(frame.get("air_motion", ""))
	if motion == "air_slam" or motion == "ground_slam":
		return 50
	if motion == "air_kick":
		return 40
	if motion in ["uppercut_launch", "umbrella_launch"]:
		return 30
	if juggled_before and (bool(frame.get("air_hold", false)) or str(frame.get("effect", "")) == "spin" or attack.begins_with("returning_pot")):
		return 20
	if attack == "kick_front" or str(frame.get("effect", "")) == "spin" or attack.begins_with("returning_pot"):
		return 10
	return 0

static func to_ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * PHYSICS_HZ)))

static func cooldown_ms(attack: String) -> int:
	return int(round(cooldown(attack) * 1000.0))

## Same velocity result as the local spin hit. A faster existing rise is kept.
static func apply_spin_velocity(velocity: Vector3, direction: Vector3, juggled: bool, kick_bounce: bool, bounce_pending: bool) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	if juggled and not bounce_pending and not kick_bounce:
		velocity.y = maxf(velocity.y, FloatLift.SPIN_LIFT_SPEED)
		return velocity
	if kick_bounce or bounce_pending:
		velocity.x += flat.x * SPIN_PUSH
		velocity.z += flat.z * SPIN_PUSH
		return velocity
	velocity.x = flat.x * SPIN_PUSH
	velocity.z = flat.z * SPIN_PUSH
	velocity.y = maxf(velocity.y, 0.2)
	return velocity

static func slam_startup(velocity: Vector3, direction: Vector3, aerial: bool, on_floor: bool) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	if aerial:
		velocity.x = flat.x * SLAM_CHASE
		velocity.z = flat.z * SLAM_CHASE
		if on_floor:
			velocity.y = SLAM_AIR_JUMP
	elif on_floor:
		velocity.y = SLAM_GROUND_JUMP
	return velocity

static func cooldown(attack: String) -> float:
	match attack:
		"dash": return CD_DASH
		"umbrella_spin": return CD_SPIN
		"pot_slam": return CD_SLAM
		"returning_pot": return CD_POT
		"kick_front": return CD_KICK
		"punch_uppercut": return 0.45
		"punch_light", "punch_follow": return 0.28
	return 0.0
