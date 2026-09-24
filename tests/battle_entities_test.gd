extends "res://tests/combat_world_fixture.gd"
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
		push_error("ENTITIES FAIL "+label)
func place(id: String, at: Vector3) -> void:
	entities[id].position = at
	entities[id].body.global_position = at

func _arm_due(id: String, attack: String, serial: int) -> void:
	var frame: Dictionary = BattleRules.skill_frame(attack)
	var startup := int(frame.startup)
	entities[id].action = attack
	entities[id].action_tick = server_tick - startup
	entities[id].action_cursor = 0
	entities[id].action_direction = entities[id].facing
	entities[id].action_serial = serial
	entities[id].action_view_tick = -1
	entities[id].action_windup = startup
	entities[id].action_seq = serial
	entities[id].aerial = false
	entities[id].stun = 0.0
	entities[id].juggled = false
	entities[id].kick_bounce = false
	entities[id].dead = false
	entities[id].lock = 0.0
func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_build_world()
	check(entities.size()==2 and peers.is_empty(),"dummies without connections")
	var dummy: String = entities.keys()[0]
	var other: String = entities.keys()[1]
	var a := _create_entity("player",0,Vector3(-1.5,0.96,0))
	var b := _create_entity("player",1,Vector3(1.5,0.96,0))
	place(dummy,Vector3(0,0.96,0))
	await physics_frame
	await physics_frame
	# Action lock limits speed but does not freeze translation or turn the attack.
	place(a,Vector3(-12,0.96,0))
	entities[a].velocity = Vector3.ZERO
	entities[a].facing = Vector3.RIGHT
	entities[a].action = "punch_light"
	entities[a].lock = 0.3
	Motion.step(entities[a].body,entities[a],Vector3.RIGHT)
	check(entities[a].position.x > -12.0 and entities[a].facing==Vector3.RIGHT,"punch can advance during action lock")
	place(a,Vector3(-12,0.96,0))
	entities[a].velocity = Vector3.ZERO
	entities[a].action = "umbrella_spin"
	entities[a].lock = 0.45
	Motion.step(entities[a].body,entities[a],Vector3.RIGHT)
	check(entities[a].position.x > -12.0,"spin can advance during action lock")
	place(a,Vector3(-12,0.96,0))
	entities[a].velocity = Vector3.ZERO
	entities[a].stun = 0.2
	Motion.step(entities[a].body,entities[a],Vector3.RIGHT)
	check(is_equal_approx(entities[a].position.x,-12.0),"hitstun still blocks voluntary movement")
	place(a,Vector3(-12,2.0,0))
	entities[a].stun = 0.0
	entities[a].action = "punch_light"
	entities[a].velocity = Vector3(5,0,0)
	Motion.step(entities[a].body,entities[a],Vector3.ZERO)
	check(entities[a].velocity.x>4.9,"air punch keeps forward momentum")
	entities[a].action = ""
	entities[a].lock = 0.0
	# Walking and a full dash stop in front of the live dummy.
	place(a,Vector3(-4,0.96,0))
	for i in 90:
		Motion.step(entities[a].body,entities[a],Vector3.RIGHT,Motion.DT,sim.dynamic_blockers(a))
	check(entities[a].position.x < -0.9,"walking cannot cross dummy")
	place(a,Vector3(-3,0.96,0))
	entities[a].velocity = Vector3.ZERO
	entities[a].facing = Vector3.RIGHT
	_resolve_attack(a,"umbrella_primary",false,Vector3.RIGHT)
	for i in 30:
		Motion.step(entities[a].body,entities[a],Vector3.ZERO,Motion.DT,sim.dynamic_blockers(a))
	check(entities[a].position.x < -0.9,"dash cannot cross dummy")
	_resolve_attack(a,"umbrella_primary",false,Vector3.RIGHT)
	check(entities[a].action=="umbrella_uppercut","second Q selected on server")
	_resolve_attack(a,entities[a].action,true,entities[a].action_direction)
	check(entities[dummy].juggled and entities[dummy].velocity.y>9,"Q Q launches dummy")
	_respawn_entity(entities[dummy])
	_respawn_entity(entities[a])
	place(dummy,Vector3(0,0.96,0))
	place(a,Vector3(-3,0.96,0))
	entities[a].facing = Vector3.RIGHT
	var dash_input := {"entity_id":a,"seq":1,"tick":sim.server_tick+1,"round_id":sim.round_id,"life":int(entities[a].life),"move":Vector3.ZERO,"aim":Vector3.RIGHT,"actions":[{"attack_seq":1,"attack":"umbrella_primary","aim":Vector3.RIGHT}]}
	sim.step([dash_input])
	var dash_hits := 0
	for i in 30:
		for event in sim.step():
			if event.get("type","")=="combat" and event.get("attack","")=="dash": dash_hits += 1
	check(dash_hits==1 and int(entities[dummy].health)==1988,"dash contact damages dummy exactly once")
	check(entities[a].position.x < -0.9,"dash contact stops in front of dummy")
	_respawn_entity(entities[dummy])
	_respawn_entity(entities[a])
	place(dummy,Vector3(0,0.96,0))
	place(a,Vector3(-1.5,0.96,0))
	_resolve_attack(a,"pot_slam",true,Vector3.RIGHT)
	check(entities[dummy].knockdown_time>1 and _roster("dummy")[0].knockdown_time>1,"ground slam state in snapshot")
	_respawn_entity(entities[dummy])
	place(dummy,Vector3(0,0.96,0))
	_resolve_attack(a,"punch_light",true,Vector3.RIGHT)
	_resolve_attack(b,"punch_light",true,Vector3.LEFT)
	check(entities[dummy].health==1984,"same tick two attackers share health")
	check(_roster().size()==2 and _roster("dummy").size()==2,"separate player roster")
	_resolve_attack(a,"punch_uppercut",true,Vector3.RIGHT)
	check(entities[dummy].juggled and entities[dummy].velocity.y>9,"shared launch")
	place(dummy,Vector3(25.8,2,0))
	place(a,Vector3(24.3,2,0))
	entities[dummy].juggled = true
	_resolve_attack(a,"kick_front",true,Vector3.RIGHT)
	for i in 8:
		Motion.step(entities[dummy].body,entities[dummy],Vector3.ZERO)
	check(entities[dummy].velocity.x<0 and entities[dummy].juggled,"dummy wall bounce")
	var saw_landing := false
	for i in 150:
		Motion.step(entities[dummy].body,entities[dummy],Vector3.ZERO)
		saw_landing = saw_landing or float(entities[dummy].get("protection",0))>0
	check(saw_landing and not entities[dummy].juggled,"landing and protection")
	_respawn_entity(entities[dummy])
	place(a,Vector3(0,0.96,0))
	place(b,Vector3(-8,0.96,4))
	place(dummy,Vector3(3,0.96,0))
	var pot = Pot.new()
	pot.owner = a
	pot.direction = Vector3.RIGHT
	pot.position = Vector3(0,1.81,0)
	var hits := 0
	for i in 180:
		for hit in pot.step(world.get_world_3d().direct_space_state,entities,Motion.DT):
			_pot_hit(a,hit)
			hits += 1
		if pot.finished: break
	check(hits==2 and entities[dummy].health==1978,"dummy pot once per leg")
	entities[dummy].health = 1
	_pot_hit(a,{"peer":dummy,"returning":false,"push":Vector3.ZERO})
	_pot_hit(b,{"peer":dummy,"returning":true,"push":Vector3.ZERO})
	_on_entity_death(b,dummy)
	check(entities[dummy].death_count==1 and entities[dummy].dead,"death exactly once")
	check(round_reset_at==0 and int(entities[a].get("score",0))==0,"dummy death no PvP score or round")
	check(_roster("dummy")[0].dead and _roster("dummy")[0].health==0,"dead snapshot")
	var life: int = entities[dummy].life
	entities[dummy].respawn_at = sim.now_ms()-1
	_simulate_players(Motion.DT)
	check(entities[dummy].life==life+1 and entities[dummy].health==2000,"independent timed respawn")
	check(entities[dummy].position==DUMMY_SPAWNS[0],"respawn home")
	entities[other].health = 1234
	entities[b].health = 0
	_on_entity_death(a,b)
	_on_entity_death(a,b)
	check(entities[a].score==1 and round_reset_at>0,"player death scores once")
	round_reset_at = sim.now_ms()-1
	_reset_round_if_due()
	check(entities[other].health==1234,"PvP reset preserves NPC")
	_respawn_entity(entities[dummy])
	_respawn_entity(entities[a])
	place(a,Vector3(-1.5,0.96,0))
	place(dummy,Vector3(0,0.96,0))
	entities[a].facing = Vector3.RIGHT
	server_tick = 200
	_record_pose(entities[dummy])
	server_tick = 208
	place(dummy,Vector3(8,0.96,0))
	_record_pose(entities[dummy])
	var hp := int(entities[dummy].health)
	_resolve_attack(a,"punch_light",true,Vector3.RIGHT)
	check(entities[dummy].health==hp,"present swing misses a target that already left")
	check(_rewind_tick(-1,3)==-1,"missing view tick stays on the present")
	check(_rewind_tick(100,0)==-1,"combat uses one world Tick, no partial pose rewind")
	_resolve_attack(a,"punch_light",true,Vector3.RIGHT,false,-1,200)
	check(entities[dummy].health==hp,"old target pose cannot hit a target that left")
	check(is_equal_approx(entities[dummy].position.x,8.0),"rewind restores the live position")
	hp = int(entities[dummy].health)
	_resolve_attack(a,"punch_light",true,Vector3.RIGHT,false,-1,100)
	check(entities[dummy].health==hp,"rewind older than the cap does not connect")
	check(BattleRules.punch_frame("punch_light").startup==3 and BattleRules.punch_total("punch_light")==10,"light punch keeps 3/10 ticks")
	check(BattleRules.punch_frame("punch_uppercut").startup==5 and BattleRules.punch_total("punch_uppercut")==13,"uppercut keeps 5/13 ticks")
	check(BattleRules.skill_frame("kick_front").startup==5 and BattleRules.skill_total("kick_front")==16,"kick keeps 5/16 ticks")
	check(BattleRules.skill_frame("umbrella_uppercut").startup==BattleRules.to_ticks(BattleRules.UPPERCUT_HIT) and BattleRules.skill_total("umbrella_uppercut")==BattleRules.to_ticks(BattleRules.UPPERCUT_LOCK),"umbrella uppercut matches the old timing")
	check(BattleRules.skill_frame("umbrella_spin").startup==BattleRules.to_ticks(BattleRules.SPIN_DURATION-BattleRules.SPIN_HIT_AT) and BattleRules.skill_total("umbrella_spin")==BattleRules.to_ticks(BattleRules.SPIN_DURATION),"spin matches the old timing")
	check(BattleRules.skill_frame("pot_slam").startup==BattleRules.to_ticks(BattleRules.SLAM_GROUND_HIT) and BattleRules.skill_total("pot_slam")==BattleRules.to_ticks(BattleRules.SLAM_GROUND_LOCK),"ground slam matches the old timing")
	check(BattleRules.skill_frame("pot_slam",true).startup==BattleRules.to_ticks(BattleRules.SLAM_AIR_HIT) and BattleRules.skill_total("pot_slam",true)==BattleRules.to_ticks(BattleRules.SLAM_AIR_LOCK),"aerial slam matches the old timing")
	check(not BattleRules.chainable("umbrella_spin") and BattleRules.chainable("kick_front"),"spin is not a chain link, kick is")
	check(is_equal_approx(BattleRules.skill_frame("punch_light").reach,1.95) and is_equal_approx(BattleRules.skill_frame("umbrella_spin").reach,3.0) and is_equal_approx(BattleRules.skill_frame("pot_slam").height,3.5),"melee shape lives on the skill record")
	var named := true
	for id in ["punch_light","punch_follow","punch_uppercut","kick_front","umbrella_uppercut","umbrella_spin","pot_slam"]:
		var skill: Dictionary = BattleRules.skill_frame(id)
		named = named and AttackCatalogData.ATTACKS.has(skill.name) and AttackCatalogData.ATTACKS.has(skill.air_name)
	check(named,"every melee skill name has a damage row")
	check(BattleRules.punch_id_at(1,0,1)=="punch_light","expired confirm restarts the string")
	check(BattleRules.punch_id_at(1,2,1)=="punch_follow","open confirm selects the second punch")
	_respawn_entity(entities[dummy])
	_respawn_entity(entities[a])
	place(a,Vector3(-1.5,0.96,0))
	place(dummy,Vector3(8,0.96,0))
	entities[a].facing = Vector3.RIGHT
	entities[a].lock = 0.0
	entities[a].cancel_tick = 0
	_resolve_attack(a,"punch",false,Vector3.RIGHT)
	check(entities[a].action=="punch_light" and int(entities[a].hit_tick)-int(entities[a].action_tick)==3,"punch request starts the string from the table")
	_resolve_attack(a,entities[a].action,true,entities[a].action_direction)
	check(int(entities[a].get("combo",0))==0,"whiff does not advance the punch string")
	entities[a].lock = 0.0
	entities[a].cancel_tick = 0
	place(dummy,Vector3(0,0.96,0))
	_resolve_attack(a,"punch",false,Vector3.RIGHT)
	var linked_attack := str(entities[a].action)
	var linked_direction: Vector3 = entities[a].action_direction
	_resolve_attack(a,linked_attack,true,linked_direction)
	check(int(entities[a].combo)==1 and linked_attack=="punch_light","landing the first punch opens the link")
	entities[a].lock = 0.0
	entities[a].cancel_tick = 0
	_resolve_attack(a,"punch",false,Vector3.RIGHT)
	check(entities[a].action=="punch_follow","next punch is the confirmed follow-up")
	var before_hit := int(entities[dummy].health)
	server_tick = int(entities[a].hit_tick)
	_advance_timelines()
	var once := int(entities[dummy].health)
	_advance_timelines()
	check(once < before_hit and int(entities[dummy].health)==once,"timeline hit runs once")
	var light := BattleRules.combat_timeline("punch_light")
	check(light.size()==3 and str(light[0].kind)=="hit" and int(light[0].tick)==3 and str(light[1].kind)=="cancel_open" and str(light[2].kind)=="end","timeline keeps startup, cancel, and end")
	_respawn_entity(entities[dummy])
	_respawn_entity(entities[a])
	_respawn_entity(entities[b])
	place(dummy, Vector3(0, 0.96, 0))
	place(a, Vector3(-1.2, 0.96, 0))
	place(b, Vector3(1.2, 0.96, 0))
	entities[a].facing = Vector3.RIGHT
	entities[b].facing = Vector3.LEFT
	entities[dummy].juggled = false
	_arm_due(a, "punch_uppercut", 1)
	_arm_due(b, "punch_light", 2)
	var shared_before := int(entities[dummy].health)
	events.clear()
	_advance_timelines()
	var light_damage := 0
	for event in events:
		if str(event.get("attack", "")) == "punch_light":
			light_damage = int(event.get("damage", 0))
	check(light_damage == 8, "same-tick punch stays a ground punch")
	check(int(entities[dummy].health) == shared_before - 24 and entities[dummy].juggled and entities[dummy].velocity.y > 9.0, "same-tick launch wins and both damages apply")
	_respawn_entity(entities[a])
	_respawn_entity(entities[b])
	place(dummy, Vector3(20, 0.96, 0))
	place(a, Vector3(0, 0.96, 0))
	place(b, Vector3(1.2, 0.96, 0))
	entities[a].facing = Vector3.RIGHT
	entities[b].facing = Vector3.LEFT
	_arm_due(a, "punch_uppercut", 3)
	_arm_due(b, "punch_uppercut", 4)
	_advance_timelines()
	check(entities[a].juggled and entities[b].juggled and entities[a].velocity.y > 9.0 and entities[b].velocity.y > 9.0 and int(entities[a].health) > 0 and int(entities[b].health) > 0, "mutual uppercuts both launch")
	_respawn_entity(entities[a])
	_respawn_entity(entities[b])
	place(dummy, Vector3(20, 0.96, 0))
	place(a, Vector3(0, 0.96, 0))
	place(b, Vector3(1.2, 0.96, 0))
	entities[a].facing = Vector3.RIGHT
	entities[b].facing = Vector3.LEFT
	entities[a].health = 16
	entities[b].health = 16
	entities[a].score = 0
	entities[b].score = 0
	round_reset_at = 0
	_arm_due(a, "punch_uppercut", 3)
	_arm_due(b, "punch_uppercut", 4)
	events.clear()
	_advance_timelines()
	var drew := false
	for event in events:
		drew = drew or bool(event.get("draw", false))
	check(entities[a].dead and entities[b].dead and int(entities[a].score) == 0 and int(entities[b].score) == 0 and drew, "mutual kill is a draw")
	print("BATTLE_ENTITIES %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
