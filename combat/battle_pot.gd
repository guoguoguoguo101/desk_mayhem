extends RefCounted
## Headless projectile simulation. Rendering is never involved in hit testing.
var id: int
var owner: String
var position: Vector3
var direction: Vector3
var returning := false
var recalled := false
var distance := 0.0
var age := 0.0
var finished := false
var hit_out := {}
var hit_back := {}
var attack_seq := -1
var serial := 0

const STATE_FIELDS := ["id","owner","position","direction","returning","recalled","distance","age","finished","hit_out","hit_back","attack_seq","serial"]

func capture() -> Dictionary:
	var state := {}
	for key in STATE_FIELDS: state[key] = get(key)
	return state.duplicate(true)

func restore(state: Dictionary) -> void:
	var restored := state.duplicate(true)
	for key in STATE_FIELDS: set(key,restored[key])

func step(space: PhysicsDirectSpaceState3D, fighters: Dictionary, dt: float) -> Array:
	var hits: Array = []
	if not fighters.has(owner) or int(fighters[owner].health)<=0:
		finished = true
		return hits
	age += dt
	if age>4.0:
		finished = true
		return hits
	var destination: Vector3 = fighters[owner].position + Vector3.UP*0.85
	var start := position
	var travel := direction*minf(14.0*dt,8.0-distance)
	if returning:
		travel = (destination-start).limit_length((22.0 if recalled else 16.0)*dt)
	var end := start+travel
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,128))
	if not wall.is_empty():
		end = wall.position
	var struck: Dictionary = hit_back if returning else hit_out
	for peer in fighters:
		var target: Dictionary = fighters[peer]
		if peer==owner or struck.has(peer) or int(target.health)<=0 or float(target.get("protection",0))>0:
			continue
		var center: Vector3 = target.position+Vector3.UP*0.7
		var nearest := Geometry3D.get_closest_point_to_segment(center,start,end)
		var gap := center-nearest
		var air: bool = bool(target.get("juggled",false)) or bool(target.get("kick_bounce",false))
		if Vector2(gap.x,gap.z).length()>0.85 or absf(gap.y)>(3.0 if air else 1.15):
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(nearest,center,128)).is_empty():
			continue
		struck[peer] = true
		var push := direction*3.8
		if returning:
			push = fighters[owner].position-target.position
			push.y = 0
			push = push.normalized()*minf(8.0,maxf(0,push.length()-0.7)*4.0)
		hits.append({"peer":peer,"returning":returning,"push":push})
	position = end
	distance += travel.length()
	if not wall.is_empty():
		if returning:
			finished = true
		else:
			position += wall.normal*0.12
			returning = true
	elif not returning and distance>=8.0:
		returning = true
	elif returning and position.distance_to(destination)<0.5:
		finished = true
	return hits

func snapshot(slot: int) -> Dictionary:
	return {"id":id,"slot":slot,"position":[position.x,position.y,position.z],"direction":[direction.x,direction.y,direction.z],"returning":returning,"recalled":recalled}
