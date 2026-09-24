extends RefCounted
## A yaw-only cone, evaluated once per accepted action. Never writes the camera.
const CONE_DEGREES := 30.0
static func horizontal(value: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	var flat := Vector3(value.x,0,value.z)
	return flat.normalized() if flat.is_finite() and flat.length_squared()>0.000001 else fallback

static func resolve(body: Vector3, aim: Vector3) -> Vector3:
	var forward := horizontal(body)
	var desired := horizontal(aim,forward)
	return desired if forward.dot(desired)>=cos(deg_to_rad(CONE_DEGREES))-0.000001 else forward

static func turn(body: Vector3, move: Vector3, delta: float) -> Vector3:
	var forward := horizontal(body)
	if move.length_squared()<0.000001:
		return forward
	var desired := horizontal(move)
	var angle := lerp_angle(atan2(-forward.x,-forward.z),atan2(-desired.x,-desired.z),clampf(12.0*delta,0,1))
	return Vector3(-sin(angle),0,-cos(angle))
