class_name CombatState
extends RefCounted

## Only state that can affect a combat result belongs here. Visuals, HUD text,
## camera shake, particles, and animation transforms stay on the client.

var entity_id := 0
var health := 0
var max_health := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var facing := Vector3.FORWARD

var downed := false
var knockdown := false
var juggled := false
var kick_bounce := false
var bounce_pending := false
var seated := false
var blocking := false
var airborne := false
var float_session := false
var air_punch_hold_used := false
var float_apex := false

var stun_time := 0.0
var revive_time := 0.0
var float_timer := 0.0
var airborne_lock := 0.0
var bounce_stun := 0.0
var juggle_hits := 0

static func from_body(body: Node) -> CombatState:
	var state := CombatState.new()
	state.entity_id = body.get_instance_id()
	state.health = int(body.get("health"))
	state.max_health = int(body.get("max_health"))
	state.position = body.global_position
	state.velocity = body.get("velocity")
	state.downed = bool(body.get("downed"))
	state.knockdown = bool(body.get("knockdown"))
	state.juggled = bool(body.get("juggled"))
	state.kick_bounce = bool(body.get("kick_bounce"))
	state.bounce_pending = bool(body.get("bounce_pending"))
	state.seated = bool(body.get("seated"))
	state.juggle_hits = int(body.get("juggle_hits"))
	state.revive_time = float(body.get("revive_time"))
	return state

func apply_health_to(body: Node) -> void:
	body.set("health", health)
	body.set("downed", downed)
