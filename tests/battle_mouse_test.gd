extends SceneTree
const Core = preload("res://combat/combat_world.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
const Prediction = preload("res://client/world_prediction.gd")
const MouseVFX = preload("res://vfx/mouse_skill_vfx.gd")
const Motion = preload("res://combat/arena_motion.gd")
var failures := 0
var sims: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: return
	failures += 1
	push_error("MOUSE FAIL " + label)

func make_world():
	var sim = Core.new()
	sim.configure_arena("mountain_courtyard")
	sim.attach(root)
	sims.append(sim)
	return sim

func command(id: String, tick: int, attack := "", aim := Vector3.RIGHT) -> Dictionary:
	return {"entity_id":id,"seq":tick,"tick":tick,"round_id":1,"life":1,"move":Vector3.ZERO,"aim":Vector3.RIGHT,
		"actions":[] if attack.is_empty() else [{"attack_seq":tick,"attack":attack,"aim":aim}]}

func run() -> void:
	var sim = make_world()
	var owner: String = sim._create_entity("player",0,Vector3(-4,0.96,0))
	var foe: String = sim._create_entity("player",1,Vector3(1.5,0.96,0))
	await physics_frame
	await physics_frame
	var seed := sim.capture()
	var client = Prediction.new()
	client.sim.configure_arena("mountain_courtyard")
	client.sim.attach(root)
	sims.append(client.sim)
	client.entity_id = owner
	client.receive(seed,0)
	var link_events := 0
	for tick in range(1,27):
		var frame := command(owner,tick,"mouse_cast" if tick==1 else "")
		var events: Array = sim.step([frame])
		client.predict(frame)
		for event in events:
			if event.type=="mouse_link": link_events += 1
	check(link_events==1 and str(sim.entities[owner].mouse_link_id)==foe,"projectile attaches once")
	check(str(client.sim.entities[owner].mouse_link_id)==foe,"prediction sees same link")
	check(int(sim.entities[owner].mouse_link_until)-sim.server_tick > 270,"link lasts about five seconds")
	var old_owner: Vector3 = sim.entities[owner].position
	var old_foe: Vector3 = sim.entities[foe].position
	var swap := command(owner,27,"mouse_swap")
	sim.step([swap])
	client.predict(swap)
	check(sim.entities[owner].position.distance_to(old_foe)<0.01 and sim.entities[foe].position.distance_to(old_owner)<0.01,"swap exchanges both positions")
	check(str(sim.entities[owner].mouse_link_id).is_empty(),"swap consumes link")
	check(client.sim.entities[owner].position.distance_to(sim.entities[owner].position)<0.01,"predicted swap agrees with authority")
	var post_swap := sim.capture()
	sim.restore(seed)
	sim.entities[owner].mouse_link_id = foe
	sim.entities[owner].mouse_link_life = int(sim.entities[foe].life)
	sim.entities[owner].mouse_link_until = sim.server_tick + 300
	sim.entities[foe].dash = 0.3
	sim.entities[foe].dash_direction = Vector3.RIGHT
	sim.step([command(owner,1,"mouse_swap")])
	check(float(sim.entities[foe].dash) == 0.0,"swap cancels target dash")
	var swapped_foe: Vector3 = sim.entities[foe].position
	sim.step([])
	check(sim.entities[foe].position.distance_to(swapped_foe) < 0.2,"swapped target does not resume dash")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(1.5,3.5,0.0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.entities[foe].velocity = Vector3(0,-2,0)
	sim.entities[owner].mouse_link_id = foe
	sim.entities[owner].mouse_link_life = int(sim.entities[foe].life)
	sim.entities[owner].mouse_link_until = sim.server_tick + 300
	sim.step([command(owner,1,"mouse_swap")])
	check(sim.entities[owner].position.y > 2.0 and sim.entities[foe].position.y < 1.1,"swap keeps full airborne height")
	check(not bool(sim.entities[foe].juggled) and float(sim.entities[foe].velocity.y) >= 0.0,"swap reconciles target on floor")
	sim.restore(seed)
	var miss := command(owner,1,"mouse_cast",Vector3(0,0.4,-0.916515))
	sim.step([miss])
	for _i in 50: sim.step([])
	check(str(sim.entities[owner].mouse_link_id).is_empty(),"pitched miss does not bind via visible rope")
	check(int(sim.entities[owner].mouse_cast_ready)>sim.now_ms(),"miss begins cooldown")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(9.0,0.96,0.0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.step([command(owner,1,"mouse_cast",Vector3(0.819152,-0.573576,0))])
	var downward_distance := 0.0
	for _i in 11:
		sim.step([])
		downward_distance = maxf(downward_distance, float(sim.entities[owner].mouse_projectile.get("distance", 0.0)))
	check(downward_distance > 2.5,"downward throw clears the caster's feet")
	check(_height_catch_check(sim),"catch volume reaches a target around human height above mouse")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.0,2.7,0.0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.step([command(owner,1,"mouse_cast")])
	for _i in 14: sim.step([])
	check(str(sim.entities[owner].mouse_link_id)==foe,"horizontal mouse can catch an elevated target")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(9.0,0.96,0.0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.step([command(owner,1,"mouse_cast")])
	for _i in 38: sim.step([])
	check(str(sim.entities[owner].mouse_link_id)==foe,"extended range can attach a distant target")
	sim.step([command(owner,40,"mouse_pull")])
	check(bool(sim.entities[owner].mouse_tug_used) and str(sim.entities[owner].mouse_link_id)==foe,"distant tug keeps the link")
	for _i in 8: sim.step([])
	var once_tugged: Vector3 = sim.entities[foe].position
	sim.step([command(owner,49,"mouse_pull")])
	check(sim.entities[foe].position.distance_to(once_tugged) < 0.05 and int(sim.entities[foe].mouse_pull_ticks) == 0,"second distant tug is rejected")
	sim.restore(seed)
	sim.step([command(owner,1,"mouse_cast")])
	for _i in 25: sim.step([])
	var pull_start: Vector3 = sim.entities[foe].position
	sim.step([command(owner,27,"mouse_pull")])
	check(sim.entities[foe].position.distance_to(pull_start) < 0.01 and int(sim.entities[foe].mouse_pull_ticks) == BattleRules.MOUSE_PULL_TICKS,"pull starts without teleporting")
	sim.step([])
	check(sim.entities[foe].position.distance_to(pull_start) > 0.1 and int(sim.entities[foe].mouse_pull_ticks) == BattleRules.MOUSE_PULL_TICKS - 1,"pull advances one tick at a time")
	for _i in range(BattleRules.MOUSE_PULL_TICKS - 1): sim.step([])
	check(sim.entities[foe].position.distance_to(sim.entities[owner].position) < pull_start.distance_to(sim.entities[owner].position) and int(sim.entities[foe].mouse_pull_ticks) == 0,"pull finishes near current owner")
	check(str(sim.entities[owner].mouse_link_id)==foe and bool(sim.entities[owner].mouse_tug_used),"distant pull preserves link for follow-up")
	for _i in 2: sim.step([])
	sim.step([command(owner,36,"mouse_pull")])
	check(str(sim.entities[owner].mouse_link_id).is_empty() and bool(sim.entities[foe].mouse_pull_launch),"close recast consumes link and prepares launch")
	var pending_launch := sim.capture()
	var launch_events := 0
	for _i in BattleRules.MOUSE_PULL_TICKS:
		for event in sim.step([]):
			if event.type == "mouse_pull_launch": launch_events += 1
	check(launch_events == 1 and sim.entities[foe].juggled and float(sim.entities[foe].velocity.y) >= BattleRules.MOUSE_PULL_LAUNCH_Y,"close recast launches target once")
	var launched_position: Vector3 = sim.entities[foe].position
	sim.restore(pending_launch)
	for _i in BattleRules.MOUSE_PULL_TICKS: sim.step([])
	check(sim.entities[foe].position.distance_to(launched_position) < 0.01 and sim.entities[foe].juggled,"snapshot replay reproduces delayed pull launch")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(0.5,3.5,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.entities[foe].velocity = Vector3(0,-1,0)
	sim.entities[owner].mouse_link_id = foe
	sim.entities[owner].mouse_link_life = int(sim.entities[foe].life)
	sim.entities[owner].mouse_link_until = sim.server_tick + 300
	sim.step([command(owner,1,"mouse_pull")])
	var airborne_y: float = sim.entities[foe].position.y
	sim.step([])
	check(sim.entities[foe].position.x < 0.5 and sim.entities[foe].position.y < airborne_y and sim.entities[foe].position.y > airborne_y - 0.1,"airborne pull changes XZ while gravity controls height")
	for _i in range(BattleRules.MOUSE_PULL_TICKS - 1): sim.step([])
	check(sim.entities[foe].juggled and float(sim.entities[foe].velocity.y) >= BattleRules.MOUSE_PULL_AIR_LIFT and float(sim.entities[foe].velocity.y) < BattleRules.MOUSE_PULL_LAUNCH_Y,"airborne recast receives a smaller lift")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.5,0.96,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[owner].mouse_link_id = foe
	sim.entities[owner].mouse_link_life = int(sim.entities[foe].life)
	sim.entities[owner].mouse_link_until = sim.server_tick + 300
	Motion.box(sim.world, Vector3(-2.5,1.5,0), Vector3(0.2,3.0,3.0), "mouse_pull_test_wall")
	var wall: Node = sim.world.get_child(sim.world.get_child_count() - 1)
	await physics_frame
	sim.step([command(owner,1,"mouse_pull")])
	var wall_launches := 0
	for _i in BattleRules.MOUSE_PULL_TICKS:
		for event in sim.step([]):
			if event.type == "mouse_pull_launch": wall_launches += 1
	check(wall_launches == 0 and not bool(sim.entities[foe].juggled) and sim.entities[foe].position.x > -2.3,"wall stops pull without launching through it")
	wall.free()
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.5,0.96,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[owner].mouse_link_id = foe
	sim.entities[owner].mouse_link_life = int(sim.entities[foe].life)
	sim.entities[owner].mouse_link_until = sim.server_tick + 300
	sim.step([command(owner,1,"mouse_pull")])
	sim.step([])
	sim._commit_hits([{"attacker_id":owner,"victim_id":foe,"attack":"punch_light","attack_seq":900,"serial":900,"order":0,"damage":1,"stun":0.2,"presented":{"velocity":Vector3.ZERO,"juggled":false,"kick_bounce":false,"bounce_pending":false,"knockdown":false},"rank":0,"juggled_before":false}])
	var interrupted_launches := 0
	for _i in BattleRules.MOUSE_PULL_TICKS:
		for event in sim.step([]):
			if event.type == "mouse_pull_launch": interrupted_launches += 1
	check(interrupted_launches == 0 and int(sim.entities[foe].mouse_pull_ticks) == 0,"new hit interrupts pending pull launch")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.0,0.96,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	var dummy: String = sim._create_entity("dummy",-1,Vector3(-2.0,0.96,0))
	sim.step([command(owner,1,"mouse_cut")])
	for _i in 5: sim.step([])
	var trail_visual = MouseVFX.new()
	root.add_child(trail_visual)
	trail_visual.sync_world(sim.entities, sim.server_tick, 0.016)
	check(trail_visual.bursts.size() > 0,"cut path emits short lightning afterimages")
	trail_visual.queue_free()
	var cut_events := 0
	for _i in BattleRules.MOUSE_CUT_DAMAGE_TICK:
		for event in sim.step([]):
			if event.type=="mouse_cut_burst": cut_events += 1
	check(cut_events==1,"cut blast occurs once after travel")
	check(sim.entities[owner].position.x > 3.0,"cut travels about eight meters in open space")
	check(sim.entities[foe].health<400 and not sim.entities[foe].juggled and sim.entities[foe].mouse_ground_launch,"ground cut holds target before launch")
	check(sim.entities[dummy].health<2000,"one cut damages multiple path targets")
	var stagger_position: Vector3 = sim.entities[foe].position
	for _i in 12: sim.step([])
	check(not sim.entities[foe].juggled and Vector2(sim.entities[foe].position.x, sim.entities[foe].position.z).distance_to(Vector2(stagger_position.x, stagger_position.z)) < 0.05,"ground target stays in place during cut stagger")
	for _i in BattleRules.to_ticks(BattleRules.MOUSE_AIR_HOLD) - 12: sim.step([])
	check(sim.entities[foe].juggled and sim.entities[foe].velocity.y > 0.0,"ground cut launches after the stagger")
	sim.remove_entity(dummy)
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.0,3.5,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.step([command(owner,1,"mouse_cut")])
	for _i in BattleRules.MOUSE_CUT_DAMAGE_TICK: sim.step([])
	check(sim.entities[foe].mouse_air_hold>0.0 and sim.entities[foe].mouse_air_used,"airborne cut starts a finite hover")
	var hover_y: float = sim.entities[foe].position.y
	var hover_xz: Vector2 = Vector2(sim.entities[foe].position.x, sim.entities[foe].position.z)
	for _i in 12: sim.step([])
	check(absf(sim.entities[foe].position.y - hover_y) < 0.05 and Vector2(sim.entities[foe].position.x, sim.entities[foe].position.z).distance_to(hover_xz) < 0.05,"airborne target pauses after cut damage")
	for _i in 15: sim.step([])
	check(float(sim.entities[foe].velocity.y) > 4.5 and sim.entities[foe].position.y > hover_y,"airborne target launches higher after pause")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-2.8, 6.0, 1.05)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.entities[foe].velocity = Vector3.ZERO
	sim.step([command(owner, 1, "mouse_cut")])
	for _i in BattleRules.MOUSE_CUT_DAMAGE_TICK: sim.step([])
	check(sim.entities[foe].health < 400 and sim.entities[foe].mouse_air_hold > 0.0,"close high airborne target beside cut path is hit")
	check(not sim._mouse_cut_touches(Vector3(-4, 0.96, 0), Vector3(4, 0.96, 0), Vector3(-2.8, 6.0, 1.8)),"target clearly outside cut width still misses")
	var visual = MouseVFX.new()
	root.add_child(visual)
	visual.sync_world(sim.entities, sim.server_tick, 0.016)
	visual.burst_link(sim.entities[foe].position)
	visual.burst_swap(old_owner, old_foe)
	visual.burst_cut(old_owner, old_foe)
	var cross_beams := 0
	var textured_quads := 0
	for piece in visual.bursts.back().node.get_children():
		if piece is MeshInstance3D and piece.mesh is CylinderMesh:
			cross_beams += 1
		elif piece is MeshInstance3D and piece.mesh is QuadMesh:
			textured_quads += 1
	check(cross_beams >= 32 and textured_quads == 0,"cut burst builds its crossing strokes from 3D geometry")
	visual.sync_world(sim.entities, sim.server_tick, 0.016)
	visual.queue_free()
	sim.restore(post_swap)
	var duplicate := command(owner,28,"mouse_swap")
	sim.step([duplicate])
	check(sim.entities[owner].position.distance_to(old_foe)<0.01,"swap without link cannot run again")
	for world in sims: world.dispose()
	print("BATTLE_MOUSE ","PASS" if failures==0 else "FAIL", " checks=40")
	quit(0 if failures==0 else 1)

func _height_catch_check(sim) -> bool:
	var start := Vector3.ZERO
	var finish := Vector3.RIGHT
	var center := Vector3(0.5, 1.6, 0.0)
	return sim._mouse_capsule_fraction(start, finish, center, BattleRules.MOUSE_CATCH_RADIUS, BattleRules.MOUSE_CATCH_HALF_HEIGHT) < INF
