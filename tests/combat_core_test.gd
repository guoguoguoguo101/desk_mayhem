extends SceneTree

const CombatStateData = preload("res://combat/combat_state.gd")
const CombatRules = preload("res://combat/combat_resolver.gd")
const AttackData = preload("res://combat/attack_catalog.gd")
const HitIntentData = preload("res://combat/hit_intent.gd")
const HitDetection = preload("res://combat/hit_detector.gd")
const ChairControlEventData = preload("res://combat/chair_control_event.gd")

func _init() -> void:
	var pvp_target := CombatStateData.new()
	pvp_target.entity_id = 7
	pvp_target.health = 100
	var pvp_event := CombatRules.resolve_hit(pvp_target, "上勾拳", AttackData.PROFILE_PVP)
	assert(pvp_event.damage == 16)
	assert(pvp_target.health == 84)
	assert(not pvp_event.lethal)

	var training_target := CombatStateData.new()
	training_target.health = 100
	var training_event := CombatRules.resolve_hit(training_target, "上勾拳", AttackData.PROFILE_TRAINING, 3)
	assert(training_event.damage == 21)
	assert(training_target.health == 79)

	var blocker := CombatStateData.new()
	blocker.health = 100
	blocker.blocking = true
	var blocked_event := CombatRules.resolve_hit(blocker, "咖啡", AttackData.PROFILE_PVP)
	assert(blocked_event.blocked)
	assert(blocker.health == 100)

	var downed_target := CombatStateData.new()
	downed_target.health = 100
	downed_target.downed = true
	var ignored_event := CombatRules.resolve_hit(downed_target, "轻拳", AttackData.PROFILE_PVP)
	assert(ignored_event.event_type == "ignored")
	assert(downed_target.health == 100)

	var launched_target := CombatStateData.new()
	CombatRules.resolve_motion(launched_target, "uppercut_launch", Vector3.FORWARD, AttackData.PROFILE_PVP)
	assert(launched_target.juggled)
	assert(launched_target.velocity == Vector3(0.0, 9.2, -2.0))
	assert(launched_target.juggle_hits == 1)

	CombatRules.resolve_motion(launched_target, "air_kick", Vector3.FORWARD, AttackData.PROFILE_PVP, 3)
	assert(not launched_target.juggled)
	assert(launched_target.kick_bounce)
	assert(launched_target.velocity == Vector3(0.0, 2.2, -21.3))

	CombatRules.resolve_motion(launched_target, "air_slam", Vector3.FORWARD, AttackData.PROFILE_TRAINING)
	assert(launched_target.bounce_pending)
	assert(launched_target.velocity == Vector3(0.0, -16.0, -1.2))

	var punch_intent = HitIntentData.melee("punch_light", 3, Vector3.FORWARD, 12)
	assert(punch_intent.is_valid())
	assert(punch_intent.effect_method == "punch_from")
	assert(HitDetection.matches_melee_shape(Vector3.ZERO, Vector3(0.0, 0.0, -1.8), Vector3.FORWARD, punch_intent.reach, punch_intent.dot_min, punch_intent.height_limit))
	assert(not HitDetection.matches_melee_shape(Vector3.ZERO, Vector3(0.0, 0.0, 1.8), Vector3.FORWARD, punch_intent.reach, punch_intent.dot_min, punch_intent.height_limit))
	assert(not HitDetection.matches_melee_shape(Vector3.ZERO, Vector3(0.0, 3.3, -1.0), Vector3.FORWARD, punch_intent.reach, punch_intent.dot_min, punch_intent.height_limit))
	var pot_intent = HitIntentData.segment("returning_pot_out", 3, Vector3(0.0, 0.85, 0.0), Vector3(0.0, 0.85, -2.0), 12)
	assert(pot_intent.is_valid())
	assert(not pot_intent.requires_direction_match)

	var network_event := pvp_event
	network_event.event_id = 9
	network_event.server_tick = 120
	network_event.intent_id = "punch_uppercut"
	network_event.attacker_peer = 1
	network_event.victim_peer = 2
	network_event.effect_method = "punch_launch"
	network_event.direction = Vector3.FORWARD
	network_event.resulting_velocity = Vector3(0.0, 9.2, -2.0)
	network_event.resulting_downed = false
	network_event.resulting_kick_bounce = true
	network_event.resulting_float_timer = 0.9
	var restored_event = network_event.from_payload(network_event.to_payload())
	assert(restored_event.event_id == 9)
	assert(restored_event.intent_id == "punch_uppercut")
	assert(restored_event.resulting_velocity == Vector3(0.0, 9.2, -2.0))
	assert(restored_event.resulting_kick_bounce)
	assert(is_equal_approx(restored_event.resulting_float_timer, 0.9))

	var chair_event = ChairControlEventData.new()
	chair_event.event_id = 5
	chair_event.control = "throw"
	chair_event.attacker_peer = 1
	chair_event.victim_peer = 2
	chair_event.position = Vector3(3.0, 1.0, -2.0)
	chair_event.velocity = Vector3(-2.4, 5.4, 0.0)
	var restored_chair_event = chair_event.from_payload(chair_event.to_payload())
	assert(restored_chair_event.control == "throw")
	assert(restored_chair_event.position == Vector3(3.0, 1.0, -2.0))
	assert(restored_chair_event.velocity == Vector3(-2.4, 5.4, 0.0))

	print("combat_core_test: passed")
	quit()
