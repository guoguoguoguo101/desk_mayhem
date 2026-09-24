extends RefCounted

## Identical collision world and fixed-step character movement for prediction
## and authority. Decorative geometry never participates in this world.
const FloatRules = preload("res://float_rules.gd")
const DT := 1.0 / 60.0
const FLOOR_Y := 0.9
const NPC_LAYER := 256
const Direction = preload("res://combat/attack_direction.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
static func blink(body: CharacterBody3D, state: Dictionary, direction: Vector3, blockers: Array = []) -> bool:
	var start := body.global_position
	for step in range(10,0,-1):
		var offset := direction.normalized()*float(step)*0.45
		if not body.test_move(body.global_transform,offset) and float(dynamic_cast(start,start+offset,blockers).fraction)>=1.0:
			body.global_position += offset
			break
	if start.distance_to(body.global_position)<0.1:
		return false
	state.position = body.global_position
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	velocity.x = 0
	velocity.z = 0
	state.velocity = velocity
	return true

static func build(parent: Node3D) -> void:
	box(parent, Vector3(0,-0.2,0), Vector3(56,0.4,44))
	for z in [-20.75,20.75]:
		box(parent, Vector3(0,1.9,z), Vector3(54.2,3.8,0.5))
	for x in [-26.75,26.75]:
		box(parent, Vector3(x,1.9,0), Vector3(0.5,3.8,41.5))
	for x in [-15.0,-7.5,0.0,7.5,15.0]:
		for z in [-11.0,11.0]:
			var shape := CylinderShape3D.new()
			shape.radius = 0.28
			shape.height = 3.4
			collider(parent, Vector3(x,1.7,z), shape)
	for x in [-18.0,-9.0,0.0,9.0,18.0]:
		box(parent, Vector3(x,0.42,16.6), Vector3(1.8,0.12,0.55))
		if x != 0.0:
			box(parent, Vector3(x,0.42,-16.6), Vector3(1.8,0.12,0.55))

static func box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	collider(parent, at, shape)

static func collider(parent: Node3D, at: Vector3, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 128
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

static func character(parent: Node3D, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 128 | NPC_LAYER
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = at
	return body

static func configure_dummy(body: CharacterBody3D, alive: bool) -> void:
	body.collision_layer = NPC_LAYER if alive else 0
	body.collision_mask = 128
	var capsule: CapsuleShape3D = body.get_child(0).shape
	capsule.radius = 0.62

static func step(body: CharacterBody3D, state: Dictionary, move: Vector3, dt: float = DT, blockers: Array = []) -> void:
	var start := body.global_position
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var stunned: bool = float(state.get("stun",0.0)) > 0.0
	var airborne: bool = bool(state.get("juggled",false)) or bool(state.get("kick_bounce",false))
	var jumping := start.y > FLOOR_Y+0.12 or velocity.y > 0.1
	var speed := 6.5
	if float(state.get("dash",0.0)) > 0.0:
		move = state.get("dash_direction",state.get("facing",Vector3.FORWARD))
		speed = 15.0
	elif stunned or airborne or int(state.get("health",400)) <= 0:
		move = Vector3.ZERO
	elif float(state.get("lock",0.0)) > 0.0:
		speed *= BattleRules.action_move_scale(str(state.get("action","")))
	else:
		state.facing = Direction.turn(state.get("facing",Vector3.FORWARD),move,dt)
	var slam_hold := float(state.get("slam_hold", 0.0))
	if not airborne and slam_hold <= 0.0:
		var acceleration := (10.0 if move.length_squared()>0.001 else 2.0) if jumping else 28.0
		velocity.x = move_toward(velocity.x, move.x*speed, acceleration*dt)
		velocity.z = move_toward(velocity.z, move.z*speed, acceleration*dt)
	if slam_hold > 0.0:
		state.slam_hold = maxf(0.0, slam_hold - dt)
	velocity.y -= (20.0 if bool(state.get("bounce_pending",false)) or not airborne else FloatRules.AIR_GRAVITY)*dt
	var remaining := velocity*dt
	for _i in 4:
		var hit := body.move_and_collide(remaining)
		if hit == null:
			break
		var normal := hit.get_normal()
		if normal.y > 0.6:
			if bool(state.get("bounce_pending",false)):
				velocity.y = 5.0
				state.bounce_pending = false
			else:
				if airborne:
					state.stun = FloatRules.KNOCKDOWN_TIME
					state.protection = FloatRules.KNOCKDOWN_TIME
				state.juggled = false
				state.kick_bounce = false
				velocity.y = 0.0
		elif bool(state.get("kick_bounce",false)):
			velocity = velocity.bounce(normal)*0.55
			velocity.y = 5.0
			state.kick_bounce = false
			state.juggled = true
		else:
			velocity = velocity.slide(normal)
		remaining = hit.get_remainder().slide(normal)
	var dynamic := dynamic_cast(start,body.global_position,blockers)
	if float(dynamic.fraction)<1.0:
		body.global_position = start.lerp(body.global_position,float(dynamic.fraction))
		velocity = velocity.slide(dynamic.normal)
	state.position = body.global_position
	state.velocity = velocity
	for timer in ["stun","protection","dash","lock","knockdown_time"]:
		state[timer] = maxf(0.0,float(state.get(timer,0.0))-dt)

static func dynamic_cast(start: Vector3, finish: Vector3, blockers: Array) -> Dictionary:
	# Analytical swept capsule/capsule test. Unlike PhysicsServer broadphase,
	# restored NPC transforms are immediately queryable during multi-Tick replay.
	var travel := finish-start
	var best := 1.0
	var normal := Vector3.ZERO
	for center in blockers:
		var p: Vector3 = start-center
		var radius := 0.35+0.62
		var axis := (1.8/2.0-0.35)+(1.8/2.0-0.62)
		var closest := Vector3(0,clampf(p.y,-axis,axis),0)
		var gap := p-closest
		if gap.length_squared()<radius*radius-0.00001:
			if travel.dot(gap)<0 and gap.length_squared()>0.000001:
				best = 0
				normal = gap.normalized()
			continue
		var candidates: Array = []
		var a := travel.x*travel.x+travel.z*travel.z
		var b := 2.0*(p.x*travel.x+p.z*travel.z)
		var c := p.x*p.x+p.z*p.z-radius*radius
		if a>0.0000001 and b*b-4*a*c>=0:
			var t := (-b-sqrt(b*b-4*a*c))/(2*a)
			if t>=0 and t<=1 and absf(p.y+travel.y*t)<=axis: candidates.append(t)
		for cap in [-axis,axis]:
			var offset := p-Vector3(0,cap,0)
			a = travel.length_squared()
			b = 2.0*offset.dot(travel)
			c = offset.length_squared()-radius*radius
			if a>0.0000001 and b*b-4*a*c>=0:
				var t := (-b-sqrt(b*b-4*a*c))/(2*a)
				if t>=0 and t<=1: candidates.append(t)
		for t in candidates:
			if float(t)>=best: continue
			var contact: Vector3 = p+travel*float(t)
			normal = (contact-Vector3(0,clampf(contact.y,-axis,axis),0)).normalized()
			best = maxf(0,float(t)-0.0001/maxf(travel.length(),0.0001))
	return {"fraction":best,"normal":normal}
