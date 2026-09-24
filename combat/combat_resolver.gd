class_name CombatResolver
extends RefCounted

const AttackData = preload("res://combat/attack_catalog.gd")
const CombatResult = preload("res://combat/combat_event.gd")
const FloatRules = preload("res://float_rules.gd")

## Placeholder for future anti-infinite-combo tuning. Keeping the switch off
## preserves today's lift and damage behaviour while making the policy local.
const AIR_DECAY_ENABLED := false

static func resolve_hit(state: CombatState, attack_id: String, profile: String, attacker_combo := 0) -> CombatEvent:
	var event := CombatResult.new()
	event.attack_id = attack_id
	event.target_id = state.entity_id
	event.health_before = state.health
	event.juggle_hits = state.juggle_hits

	if state.downed or state.knockdown:
		event.event_type = "ignored"
		event.health_after = state.health
		return event
	if state.blocking and AttackData.is_ranged(attack_id):
		event.event_type = "blocked"
		event.blocked = true
		event.health_after = state.health
		return event

	var damage := AttackData.damage_for(attack_id, profile)
	if profile == AttackData.PROFILE_TRAINING:
		damage += mini(attacker_combo, 6)
	event.damage = damage
	state.health = maxi(0, state.health - damage)
	event.health_after = state.health
	event.lethal = state.health <= 0

	# Future lift / hitstun decay is calculated here, rather than inside every
	# weapon method. It intentionally has no effect until the switch is enabled.
	if AIR_DECAY_ENABLED and state.juggled:
		event.juggle_hits = state.juggle_hits + 1
	return event

## Applies only the combat-state transition after a confirmed hit. The caller
## has already used resolve_hit() to validate and deduct damage.
static func resolve_motion(
	state: CombatState, effect: String, direction: Vector3, profile: String, attacker_combo := 0
) -> CombatEvent:
	var event := CombatResult.new()
	event.event_type = "motion"
	event.attack_id = effect
	event.target_id = state.entity_id
	if state.downed or state.knockdown:
		event.event_type = "ignored"
		return event

	match effect:
		"uppercut_launch":
			begin_launch(state, 0.9 if profile == AttackData.PROFILE_PVP else 0.95)
			state.velocity = direction * (2.0 if profile == AttackData.PROFILE_PVP else 1.6) + Vector3.UP * 9.2
			if profile == AttackData.PROFILE_TRAINING:
				state.airborne = true
				state.airborne_lock = 0.18
		"umbrella_launch":
			begin_launch(state, 0.95)
			state.velocity = direction * 1.4 + Vector3.UP * FloatRules.UMBRELLA_LAUNCH_SPEED
			if profile == AttackData.PROFILE_TRAINING:
				state.airborne = true
				state.airborne_lock = 0.18
		"air_kick":
			state.juggled = false
			state.float_timer = 0.18
			state.bounce_pending = false
			state.kick_bounce = true
			state.airborne = true
			state.velocity = direction * (18.0 + kick_combo_bonus(attacker_combo, profile)) + Vector3.UP * (2.2 if profile == AttackData.PROFILE_PVP else 2.4)
			if profile == AttackData.PROFILE_TRAINING:
				state.airborne_lock = 0.16
				state.stun_time = 0.2
		"air_slam":
			state.float_timer = 0.0
			state.kick_bounce = false
			state.bounce_pending = true
			state.velocity = direction * (1.4 if profile == AttackData.PROFILE_PVP else 1.2) + Vector3.DOWN * 16.0
			if profile == AttackData.PROFILE_TRAINING:
				state.juggled = true
				state.airborne = true
				state.airborne_lock = 0.16
				state.bounce_stun = 0.55
		"ground_slam":
			state.velocity = Vector3.ZERO
			state.stun_time = maxf(state.stun_time, 1.2 if profile == AttackData.PROFILE_PVP else 1.8)
		_:
			push_error("Unknown combat motion effect: %s" % effect)

	event.juggle_hits = state.juggle_hits
	event.resulting_velocity = state.velocity
	event.resulting_juggled = state.juggled
	event.resulting_bounce = state.bounce_pending
	return event

static func begin_launch(state: CombatState, float_timer: float) -> void:
	state.float_session = true
	state.air_punch_hold_used = false
	state.float_apex = false
	state.juggled = true
	state.kick_bounce = false
	state.bounce_pending = false
	state.stun_time = 0.0
	state.float_timer = float_timer
	state.juggle_hits = 1

static func kick_combo_bonus(combo_count: int, profile: String) -> float:
	var capped := minf(float(combo_count), 6.0)
	return capped * (1.1 if profile == AttackData.PROFILE_PVP else 1.15)
