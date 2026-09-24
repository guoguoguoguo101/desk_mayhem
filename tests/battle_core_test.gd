extends SceneTree
const Motion = preload("res://combat/arena_motion.gd")
const Reliable = preload("res://network/reliable_events.gd")
const Pot = preload("res://combat/battle_pot.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("BATTLE_CORE FAIL " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sender = Reliable.new()
	var receiver = Reliable.new()
	sender.queue({"value":1})
	sender.queue({"value":2})
	var packets: Array = sender.outgoing(0)
	check(receiver.receive(2,packets[1].payload).is_empty(),"out of order held")
	check(sender.outgoing(119).is_empty(),"retry interval")
	check(sender.outgoing(120).size()==2,"lost packets retried")
	check(receiver.receive(1,packets[0].payload).size()==2,"ordered delivery")
	check(receiver.receive(1,packets[0].payload).is_empty(),"duplicate ignored")
	sender.acknowledge(1)
	sender.acknowledge(2)
	check(sender.pending.is_empty(),"acks release queue")
	var world := Node3D.new()
	root.add_child(world)
	Motion.build(world)
	var body := Motion.character(world,Vector3(0,0.96,0))
	await physics_frame
	await physics_frame
	var state := {"health":400,"velocity":Vector3.ZERO}
	for i in 600:
		Motion.step(body,state,Vector3.RIGHT)
	check(body.position.x < 26.3 and body.position.x > 26.0,"wall blocks walking")
	check(absf(body.position.y-0.9)<0.1,"floor supports capsule")
	body.position = Vector3(25.8,2,0)
	state.velocity = Vector3(18,2,0)
	state.kick_bounce = true
	for i in 8:
		Motion.step(body,state,Vector3.ZERO)
	check(state.velocity.x<0 and state.juggled,"kick wall bounce")
	for i in 120:
		Motion.step(body,state,Vector3.ZERO)
	check(not state.juggled and body.position.y<1.0,"airborne lands")
	body.position = Vector3(-15,0.96,-8)
	state.velocity = Vector3.ZERO
	for i in 90:
		Motion.step(body,state,Vector3.FORWARD)
	check(body.position.z > -10.5,"pillar blocks walking")
	body.position = Vector3(0,0.96,0)
	check(Motion.blink(body,state,Vector3.RIGHT) and absf(body.position.x-4.5)<0.01,"blink 4.5m")
	body.position = Vector3(25,0.96,0)
	Motion.blink(body,state,Vector3.RIGHT)
	check(body.position.x<26.3,"blink cannot cross wall")
	var fighters := {"a":{"position":Vector3(0,0.96,0),"health":400},"b":{"position":Vector3(3,0.96,0),"health":400}}
	var pot = Pot.new()
	pot.owner = "a"
	pot.direction = Vector3.RIGHT
	pot.position = Vector3(0,1.81,0)
	var out_hits := 0
	var back_hits := 0
	for i in 180:
		for hit in pot.step(world.get_world_3d().direct_space_state,fighters,Motion.DT):
			if hit.returning: back_hits += 1
			else: out_hits += 1
		if pot.finished: break
	check(out_hits==1 and back_hits==1 and pot.finished,"pot once each leg and auto return")
	pot = Pot.new()
	pot.owner = "a"
	pot.direction = Vector3.RIGHT
	pot.position = Vector3(26,1.81,0)
	fighters.a.position = Vector3(25,0.96,0)
	fighters.b.position = Vector3(27,0.96,0)
	var wall_hits := 0
	for i in 40:
		wall_hits += pot.step(world.get_world_3d().direct_space_state,fighters,Motion.DT).size()
		if pot.finished: break
	check(wall_hits==0 and pot.returning and pot.finished,"pot wall return no through-wall damage")
	pot = Pot.new()
	pot.owner = "a"
	pot.position = Vector3(22,1.81,0)
	pot.returning = true
	pot.recalled = true
	var from: Vector3 = pot.position
	pot.step(world.get_world_3d().direct_space_state,fighters,Motion.DT)
	check(absf(pot.position.distance_to(from)-22.0/60.0)<0.01,"fast recall 22m/s")
	fighters.a.health = 0
	pot.step(world.get_world_3d().direct_space_state,fighters,Motion.DT)
	check(pot.finished,"owner death removes pot")
	print("BATTLE_CORE %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
