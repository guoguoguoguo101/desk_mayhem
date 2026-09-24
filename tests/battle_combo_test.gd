extends "res://tests/combat_world_fixture.gd"

const Rules = preload("res://combat/battle_rules.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	return false

func _physics_process(_delta: float) -> bool:
	return false

func _broadcast(payload: Dictionary) -> void:
	events.append(payload)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("COMBO FAIL " + label)

func place(id: String, at: Vector3) -> void:
	entities[id].position = at
	entities[id].body.global_position = at

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_build_world()
	var dummy: String = entities.keys()[0]
	var attacker := _create_entity("player", 0, Vector3(-1.2, 0.96, 0))
	place(dummy, Vector3(0, 0.96, 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	entities[attacker].facing = Vector3.RIGHT
	await physics_frame
	await physics_frame
	_resolve_attack(attacker, "umbrella_uppercut", true, Vector3.RIGHT)
	var launched: Vector3 = entities[dummy].velocity
	check(entities[dummy].juggled and launched.y > 9.0, "uppercut keeps local launch height")
	var health_after_launch: int = entities[dummy].health
	for _i in 6:
		Motion.step(entities[dummy].body, entities[dummy], Vector3.ZERO)
	var rising: Vector3 = entities[dummy].velocity
	check(entities[dummy].juggled and entities[dummy].position.y > 1.2, "launch is still airborne")
	entities[attacker].lock = 0.12
	entities[attacker].dash = 0.0
	entities[attacker].cancel_tick = server_tick + 30
	_resolve_attack(attacker, "umbrella_spin", false, Vector3.RIGHT)
	check(str(entities[attacker].get("action", "")) != "umbrella_spin" and str(entities[attacker].get("buffer_attack", "")) == "umbrella_spin", "early spin is buffered")
	entities[attacker].lock = 0.0
	entities[attacker].cancel_tick = 0
	_release_buffered_attack(attacker)
	check(entities[attacker].action == "umbrella_spin", "buffer releases spin")
	check(int(entities[attacker].cooldown_umbrella_spin) - sim.now_ms() > 2000, "spin cooldown matches local 2.2s")
	var expected: Vector3 = Rules.apply_spin_velocity(rising, Vector3.RIGHT, true, false, false)
	place(dummy, Vector3(0, entities[dummy].position.y, 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	_resolve_attack(attacker, "umbrella_spin", true, Vector3.RIGHT)
	var spun: Vector3 = entities[dummy].velocity
	check(absf(spun.y - expected.y) < 0.05 and absf(spun.x - expected.x) < 0.05, "spin keeps the faster rise")
	check(spun.y > 6.5, "spin does not flatten rise to 6")
	var health_after_spin: int = entities[dummy].health
	check(health_after_launch - health_after_spin == 8, "spin damage unchanged")
	for _i in 8:
		Motion.step(entities[dummy].body, entities[dummy], Vector3.ZERO)
	check(entities[dummy].juggled and entities[dummy].position.y > 1.5, "spin keeps the combo airborne")
	place(dummy, Vector3(1.2, entities[dummy].position.y, 0))
	var pot_before: int = entities[dummy].health
	_pot_hit(attacker, {"peer": dummy, "returning": false, "push": Vector3(3.8, 0, 0)})
	check(entities[dummy].juggled and entities[dummy].velocity.y >= 3.0, "outbound pot keeps the float")
	check(pot_before - int(entities[dummy].health) == 12, "pot damage unchanged")
	place(dummy, Vector3(0, maxf(entities[dummy].position.y, 2.0), 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	entities[attacker].followup = sim.now_ms() + 1200
	entities[attacker].lock = 0.0
	entities[attacker].cancel_tick = 0
	_resolve_attack(attacker, "umbrella_uppercut", true, Vector3.RIGHT)
	check(entities[dummy].juggled and entities[dummy].velocity.y > 9.0, "second uppercut relaunches at the same height")
	entities[attacker].cooldown_pot_slam = 0
	entities[attacker].lock = 0.0
	entities[attacker].cancel_tick = 0
	entities[attacker].dash = 0.0
	entities[dummy].juggled = true
	place(dummy, Vector3(1.0, 2.4, 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	_resolve_attack(attacker, "pot_slam", false, Vector3.RIGHT)
	check(int(entities[attacker].hit_tick) - int(entities[attacker].action_tick) == Rules.to_ticks(Rules.SLAM_AIR_HIT), "aerial slam uses the 0.2s startup")
	check(absf(entities[attacker].velocity.x - Rules.SLAM_CHASE) < 0.01 and absf(entities[attacker].velocity.y - Rules.SLAM_AIR_JUMP) < 0.01, "aerial slam chases and hops")
	check(bool(events.back().get("aerial", false)), "aerial slam is marked for its animation")
	check(int(entities[attacker].cooldown_pot_slam) - sim.now_ms() > 1800, "slam cooldown matches local 2s")
	place(dummy, Vector3(0, 1.2, 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	entities[dummy].juggled = true
	entities[dummy].velocity = Vector3(0, -4, 0)
	entities[attacker].lock = 0.0
	entities[attacker].stun = 0.0
	entities[attacker].cancel_tick = 0
	_resolve_attack(attacker, "punch_light", true, Vector3.RIGHT)
	check(is_equal_approx(entities[dummy].velocity.y, -0.35), "air punch lifts a falling target to -0.35")
	entities[dummy].velocity.y = -4.0
	_resolve_attack(attacker, "punch_follow", true, Vector3.RIGHT)
	check(is_equal_approx(entities[dummy].velocity.y, -0.35), "later air punches lift too")
	_resolve_attack(attacker, "pot_slam", true, Vector3.RIGHT)
	check(entities[dummy].bounce_pending and entities[dummy].velocity.y < 0.0, "aerial slam still spikes downward")
	var health_before := int(entities[dummy].health)
	place(dummy, Vector3(12, 0.96, 0))
	events.clear()
	_resolve_attack(attacker, "punch_light", true, Vector3.RIGHT, false, -1, -1, 11)
	var denied := false
	for event in events:
		if str(event.get("type", "")) == "attack_result" and not bool(event.get("confirmed", true)) and int(event.get("attack_seq", -1)) == 11:
			denied = true
	check(denied and int(entities[dummy].health) == health_before, "a miss is denied and does not change health")
	place(dummy, Vector3(0, 0.96, 0))
	place(attacker, Vector3(-1.2, 0.96, 0))
	entities[dummy].juggled = false
	entities[dummy].kick_bounce = false
	entities[dummy].bounce_pending = false
	entities[dummy].velocity = Vector3.ZERO
	entities[attacker].stun = 0.0
	_resolve_attack(attacker, "kick_front", true, Vector3.RIGHT)
	check(entities[dummy].velocity.x > 5.0 and not entities[dummy].juggled, "ground kick knocks away without floating")
	print("BATTLE_COMBO %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
