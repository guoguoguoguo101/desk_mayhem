extends SceneTree
const Core = preload("res://combat/combat_world.gd")
const Prediction = preload("res://client/world_prediction.gd")
const Codec = preload("res://network/world_codec.gd")
var failures := 0
var worlds: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("WORLD FAIL "+label)
func make_world():
	var sim = Core.new()
	sim.attach(root)
	worlds.append(sim)
	return sim
func command(id: String, tick: int, action := "", move := Vector3.ZERO, aim := Vector3.RIGHT) -> Dictionary:
	return {"entity_id":id,"seq":tick,"tick":tick,"round_id":1,"life":1,"move":move,"aim":aim,
		"actions":[] if action=="" else [{"attack_seq":tick,"attack":action,"aim":aim}]}
func equal_state(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equal_state(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equal_state(a[i],b[i]): return false
		return true
	if a is Vector3 and b is Vector3: return a.distance_to(b)<0.00001
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<0.00001
	return a==b
func run() -> void:
	var server = make_world()
	var npc: String = server._create_entity("dummy",-1,Vector3(0,0.96,0))
	var player: String = server._create_entity("player",0,Vector3(-2,0.96,0))
	var seed: Dictionary = server.capture()
	var client = Prediction.new()
	client.sim.attach(root)
	worlds.append(client.sim)
	client.entity_id = player
	client.receive(seed,0)
	await physics_frame
	await physics_frame
	var saved := {0:seed}
	var frames := {}
	var attacks := {1:"umbrella_primary",8:"umbrella_primary",25:"umbrella_spin",78:"returning_pot",93:"umbrella_primary",100:"umbrella_primary",119:"pot_slam",210:"blink",245:"jump",290:"kick_front"}
	var hit_types := {}
	var all_events: Array = []
	var checkpoint: Dictionary
	for tick in range(1,361):
		var gap: Vector3 = server.entities[npc].position-server.entities[player].position
		gap.y = 0
		var move: Vector3 = gap.normalized() if gap.length()>1.4 and tick<120 else Vector3.ZERO
		var frame := command(player,tick,str(attacks.get(tick,"")),move)
		frames[tick] = frame
		var events: Array = server.step([frame])
		all_events.append_array(events)
		for event in events:
			if event.type=="combat": hit_types[str(event.attack)] = true
		saved[tick] = server.capture()
		client.predict(frame)
		if tick%6==0:
			client.receive(saved[tick-6],0)
		check(equal_state(server.capture(),client.sim.capture()),"full-world parity tick=%d" % tick)
		if tick==50: checkpoint = server.capture()
	check(hit_types.has("umbrella_uppercut") and hit_types.has("umbrella_spin") and hit_types.has("returning_pot_out"),"real timeline launch-spin-pot combo connects")
	var launches := 0
	for event in all_events:
		if event.type=="combat" and event.attack=="umbrella_uppercut": launches += 1
	check(launches==2,"second dash-uppercut connects without changing cooldown or height")
	print("WORLD combo hits=",hit_types," launches=",launches)
	var packed := Codec.pack(saved[120])
	check(equal_state(saved[120],Codec.unpack(packed)),"wire roundtrip keeps full typed world")
	var assembler = Codec.new()
	var pieces := Codec.fragments(packed)
	pieces.reverse()
	var assembled := ""
	for piece in pieces:
		piece.tick = 120
		assembled = assembler.receive(piece)
	check(assembled==packed,"snapshot chunks reassemble out of order")
	var after_wire: Dictionary = Codec.unpack(assembled)
	after_wire.entities[player].health = 1
	check(int(saved[120].entities[player].health)!=1,"wire world does not alias simulation history")
	server.restore(checkpoint)
	for tick in range(51,361): server.step([frames[tick]])
	check(equal_state(saved[360],server.capture()),"restore/replay includes pots, hit sets, cooldowns, combo and NPC motion")
	# Restore while the pot is flying; both its legs remain once-only.
	server.restore(saved[84])
	for tick in range(85,361): server.step([frames[tick]])
	check(equal_state(saved[360],server.capture()),"midflight pot restoration")
	# Duplicate commands cannot replay an action.
	server.restore(seed)
	var spin := command(player,1,"umbrella_spin")
	server.step([spin,spin])
	check(server.next_action_serial==2,"duplicated attack sequence starts once")
	# Two attackers are judged before either receive the other's hit.
	var mutual = make_world()
	var a: String = mutual._create_entity("player",0,Vector3(0,0.96,0))
	var b: String = mutual._create_entity("player",1,Vector3(1.5,0.96,0))
	await physics_frame
	await physics_frame
	mutual.entities[a].followup = 1200
	mutual.entities[b].followup = 1200
	mutual.step([command(a,1,"umbrella_primary"),command(b,1,"umbrella_primary",Vector3.ZERO,Vector3.LEFT)])
	for tick in range(2,8): mutual.step([])
	check(mutual.entities[a].juggled and mutual.entities[b].juggled,"simultaneous launch survives batch resolution")
	# A wrong predicted target is discarded wholesale, not patched with another impulse.
	var wrong = Prediction.new()
	wrong.sim.attach(root)
	worlds.append(wrong.sim)
	wrong.entity_id = player
	wrong.receive(seed,0)
	for tick in range(1,22): wrong.predict(command(player,tick,"umbrella_spin" if tick==1 else ""))
	check(wrong.sim.entities[npc].health<2000,"speculative ground spin hit exists")
	var truth = make_world()
	truth.restore(seed)
	truth.entities[npc].position = Vector3(10,0.96,0)
	truth.entities[npc].body.global_position = truth.entities[npc].position
	await physics_frame
	await physics_frame
	for tick in range(1,22): truth.step([command(player,tick,"umbrella_spin" if tick==1 else "")])
	wrong.receive(truth.capture(),0)
	check(equal_state(truth.capture(),wrong.sim.capture()),"denied hit restores entire world without dependent-air special cases")
	check(wrong.sim.entities[npc].health==2000,"predicted damage never survives authoritative miss")
	# Complete death state, timer and next life survive replay.
	truth.entities[npc].health = 1
	truth._on_entity_death(player,npc,false)
	var death_seed: Dictionary = truth.capture()
	for i in 181: truth.step([])
	var respawned: Dictionary = truth.capture()
	truth.restore(death_seed)
	for i in 181: truth.step([])
	check(equal_state(respawned,truth.capture()) and int(truth.entities[npc].life)==2,"death/respawn replay once")
	check(int(truth.entities[player].get("score",0))==0 and truth.round_id==1,"NPC death leaves PvP score and round alone")
	# Old-life input is not allowed to trigger a skill after respawn.
	var before: int = truth.next_action_serial
	var stale := command(npc,999,"umbrella_spin")
	truth.step([stale])
	check(truth.next_action_serial==before,"old life command rejected")
	print("BATTLE_WORLD %s compressed_snapshot_bytes=%d replay_steps=%d" % ["PASS" if failures==0 else "FAIL",packed.length(),client.replay_steps])
	for sim in worlds: sim.dispose()
	await process_frame
	quit(0 if failures==0 else 1)
