extends SceneTree
const Core = preload("res://combat/combat_world.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
const Prediction = preload("res://client/world_prediction.gd")
const MouseVFX = preload("res://vfx/mouse_skill_vfx.gd")
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
	sim.restore(seed)
	sim.step([command(owner,1,"mouse_cast")])
	for _i in 25: sim.step([])
	var pull_start: Vector3 = sim.entities[foe].position
	sim.step([command(owner,27,"mouse_pull")])
	check(sim.entities[foe].position.distance_to(sim.entities[owner].position) < pull_start.distance_to(sim.entities[owner].position),"recast pulls target toward current owner")
	check(str(sim.entities[owner].mouse_link_id).is_empty(),"pull consumes link")
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.0,0.96,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	var dummy: String = sim._create_entity("dummy",-1,Vector3(-2.0,0.96,0))
	sim.step([command(owner,1,"mouse_cut")])
	var cut_events := 0
	for _i in 30:
		for event in sim.step([]):
			if event.type=="mouse_cut_burst": cut_events += 1
	check(cut_events==1,"cut blast occurs once after travel")
	check(sim.entities[foe].health<400 and sim.entities[foe].juggled,"cut path launches target")
	check(sim.entities[dummy].health<2000,"one cut damages multiple path targets")
	sim.remove_entity(dummy)
	sim.restore(seed)
	sim.entities[foe].position = Vector3(-1.0,3.5,0)
	sim.entities[foe].body.global_position = sim.entities[foe].position
	sim.entities[foe].juggled = true
	sim.step([command(owner,1,"mouse_cut")])
	for _i in 18: sim.step([])
	check(sim.entities[foe].mouse_air_hold>0.0 and sim.entities[foe].mouse_air_used,"airborne cut starts a finite hover")
	var visual = MouseVFX.new()
	root.add_child(visual)
	visual.sync_world(sim.entities, sim.server_tick, 0.016)
	visual.burst_link(sim.entities[foe].position)
	visual.burst_swap(old_owner, old_foe)
	visual.burst_cut(old_owner, old_foe)
	visual.sync_world(sim.entities, sim.server_tick, 0.016)
	visual.queue_free()
	sim.restore(post_swap)
	var duplicate := command(owner,28,"mouse_swap")
	sim.step([duplicate])
	check(sim.entities[owner].position.distance_to(old_foe)<0.01,"swap without link cannot run again")
	for world in sims: world.dispose()
	print("BATTLE_MOUSE ","PASS" if failures==0 else "FAIL", " checks=17")
	quit(0 if failures==0 else 1)

func _height_catch_check(sim) -> bool:
	var start := Vector3.ZERO
	var finish := Vector3.RIGHT
	var center := Vector3(0.5, 1.6, 0.0)
	return sim._mouse_capsule_fraction(start, finish, center, BattleRules.MOUSE_CATCH_RADIUS, BattleRules.MOUSE_CATCH_HALF_HEIGHT) < INF
