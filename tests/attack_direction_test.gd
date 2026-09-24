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
		push_error("DIRECTION FAIL "+label)
func run() -> void:
	for degrees in [-180.0,-90.0,-31.0,-30.0,-20.0,0.0,20.0,30.0,31.0,90.0,180.0]:
		var aim := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(degrees))
		var expected := aim if absf(degrees)<=30.0 else Vector3.FORWARD
		check(Direction.resolve(Vector3.FORWARD,aim).distance_to(expected)<0.0001,"cone %s" % degrees)
	check(Direction.resolve(Vector3.FORWARD,Vector3.UP)==Vector3.FORWARD,"vertical fallback")
	world = Node3D.new()
	root.add_child(world)
	Motion.build(world)
	for key in ["a","b"]:
		var slot := 0 if key=="a" else 1
		var position := Vector3(0,0.96,0) if slot==0 else Vector3(0,0.96,-1.5)
		entities[key] = {"kind":"player","life":1,"entity_id":key,"slot":slot,"health":400,"position":position,"facing":Vector3.FORWARD,"move":Vector3.ZERO,"input_seq":0,"inputs":{},"body":Motion.character(world,position)}
	await physics_frame
	await physics_frame
	_apply_input("a",{"seq":1,"move":[0,0],"aim":[1,0]})
	_simulate_players(Motion.DT)
	check(entities.a.facing.distance_to(Vector3.FORWARD)<0.001,"idle camera does not turn body")
	_apply_input("a",{"seq":2,"move":[1,0],"aim":[0,-1]})
	_simulate_players(Motion.DT)
	check(entities.a.facing.x>0.1 and entities.a.facing.x<0.9,"strafe smoothly turns toward movement")
	entities.a.facing = Vector3.FORWARD
	var aim := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(20))
	_resolve_attack("a","punch",false,aim)
	check(entities.a.action_direction.distance_to(aim)<0.001,"attack locks corrected direction")
	_apply_input("a",{"seq":3,"move":[0,0],"aim":[0,1]})
	_simulate_players(Motion.DT)
	check(entities.a.action_direction.distance_to(aim)<0.001,"camera cannot redirect startup")
	_resolve_attack("a","punch_light",true,entities.a.action_direction)
	check(entities.b.health==392,"hit uses saved direction")
	entities.a.cancel_tick = 0
	entities.a.lock = 0
	entities.a.facing = Vector3.FORWARD
	_resolve_attack("a","dash",false,aim)
	_apply_input("a",{"seq":4,"move":[1,0],"aim":[1,0]})
	_simulate_players(Motion.DT)
	check(entities.a.dash_direction.distance_to(aim)<0.001 and entities.a.facing.distance_to(aim)<0.001,"dash does not steer with camera")
	entities.a.dash = 0
	entities.a.facing = Vector3.FORWARD
	_resolve_attack("a","returning_pot",false,Vector3.RIGHT)
	check(pots.has("a") and pots.a.direction.distance_to(Vector3.FORWARD)<0.001,"pot falls back beyond cone")
	entities.a.lock = 0
	entities.a.cancel_tick = 0
	var start: Vector3 = entities.a.position
	_resolve_attack("a","blink",false,aim)
	check((entities.a.position-start).normalized().distance_to(aim)<0.001,"blink uses same cone")
	# Presentation must not overwrite a spin, and starts at the logical base yaw.
	var client = load("res://client/battle_client_session.gd").new()
	var body = load("res://player.gd").new()
	body.visual = Node3D.new()
	body.visual.rotation.y = 0.7
	client._play_action(body,"umbrella_spin",aim)
	check(absf(body.spin_facing-atan2(-aim.x,-aim.z))<0.001,"spin initializes from attack direction")
	body.visual.rotation.y = 1.4
	client._present_facing(body,Vector3.RIGHT,0.1)
	check(is_equal_approx(body.visual.rotation.y,1.4),"snapshot presentation does not override spin")
	body.visual.free()
	body.free()
	client.free()
	print("ATTACK_DIRECTION %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
