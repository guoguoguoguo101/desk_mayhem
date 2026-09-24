class_name ChairControlEvent
extends RefCounted

## A reliable server decision for the chair's non-damage state machine.
## Carry positions themselves remain frequent state updates; this event marks
## the discrete transitions that clients must never decide for themselves.

var event_id := 0
var server_tick := 0
var control := ""
var attacker_peer := 0
var victim_peer := 0
var direction := Vector3.ZERO
var position := Vector3.ZERO
var health := 0
var downed := false
var velocity := Vector3.ZERO
var juggled := false
var kick_bounce := false
var bounce_pending := false
var float_timer := 0.0
var float_session := false
var airborne := false
var seated := false
var chair_ride := false
var pinned := false

func to_payload() -> Dictionary:
	return {
		"id": event_id, "tick": server_tick, "control": control,
		"attacker": attacker_peer, "victim": victim_peer, "dir": direction,
		"position": position, "health": health, "downed": downed,
		"velocity": velocity, "juggled": juggled, "kick_bounce": kick_bounce,
		"bounce": bounce_pending, "float_timer": float_timer,
		"float_session": float_session, "airborne": airborne,
		"seated": seated, "chair_ride": chair_ride, "pinned": pinned,
	}

static func from_payload(payload: Dictionary):
	var event = load("res://combat/chair_control_event.gd").new()
	event.event_id = int(payload.get("id", 0))
	event.server_tick = int(payload.get("tick", 0))
	event.control = str(payload.get("control", ""))
	event.attacker_peer = int(payload.get("attacker", 0))
	event.victim_peer = int(payload.get("victim", 0))
	event.direction = payload.get("dir", Vector3.ZERO)
	event.position = payload.get("position", Vector3.ZERO)
	event.health = int(payload.get("health", 0))
	event.downed = bool(payload.get("downed", false))
	event.velocity = payload.get("velocity", Vector3.ZERO)
	event.juggled = bool(payload.get("juggled", false))
	event.kick_bounce = bool(payload.get("kick_bounce", false))
	event.bounce_pending = bool(payload.get("bounce", false))
	event.float_timer = float(payload.get("float_timer", 0.0))
	event.float_session = bool(payload.get("float_session", false))
	event.airborne = bool(payload.get("airborne", false))
	event.seated = bool(payload.get("seated", false))
	event.chair_ride = bool(payload.get("chair_ride", false))
	event.pinned = bool(payload.get("pinned", false))
	return event
