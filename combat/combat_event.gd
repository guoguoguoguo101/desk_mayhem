class_name CombatEvent
extends RefCounted

## A serializable description of a resolved combat fact. It deliberately does
## not contain references to scene nodes, particles, audio, or cameras.

var event_type := "hit"
var event_id := 0
var server_tick := 0
var intent_id := ""
var attacker_peer := 0
var victim_peer := 0
var attack_id := ""
var effect_method := ""
var direction := Vector3.ZERO
var target_id := 0
var health_before := 0
var health_after := 0
var damage := 0
var blocked := false
var lethal := false
var juggle_hits := 0
var resulting_velocity := Vector3.ZERO
var resulting_juggled := false
var resulting_downed := false
var resulting_kick_bounce := false
var resulting_float_timer := 0.0
var resulting_bounce := false

func to_payload() -> Dictionary:
	return {
		"id": event_id,
		"tick": server_tick,
		"intent": intent_id,
		"attacker": attacker_peer,
		"victim": victim_peer,
		"attack": attack_id,
		"method": effect_method,
		"dir": direction,
		"target": target_id,
		"before": health_before,
		"after": health_after,
		"damage": damage,
		"blocked": blocked,
		"lethal": lethal,
		"juggle": juggle_hits,
		"velocity": resulting_velocity,
		"juggled": resulting_juggled,
		"downed": resulting_downed,
		"kick_bounce": resulting_kick_bounce,
		"float_timer": resulting_float_timer,
		"bounce": resulting_bounce,
	}

static func from_payload(payload: Dictionary):
	var event = load("res://combat/combat_event.gd").new()
	event.event_id = int(payload.get("id", 0))
	event.server_tick = int(payload.get("tick", 0))
	event.intent_id = str(payload.get("intent", ""))
	event.attacker_peer = int(payload.get("attacker", 0))
	event.victim_peer = int(payload.get("victim", 0))
	event.attack_id = str(payload.get("attack", ""))
	event.effect_method = str(payload.get("method", ""))
	event.direction = payload.get("dir", Vector3.ZERO)
	event.target_id = int(payload.get("target", 0))
	event.health_before = int(payload.get("before", 0))
	event.health_after = int(payload.get("after", 0))
	event.damage = int(payload.get("damage", 0))
	event.blocked = bool(payload.get("blocked", false))
	event.lethal = bool(payload.get("lethal", false))
	event.juggle_hits = int(payload.get("juggle", 0))
	event.resulting_velocity = payload.get("velocity", Vector3.ZERO)
	event.resulting_juggled = bool(payload.get("juggled", false))
	event.resulting_downed = bool(payload.get("downed", false))
	event.resulting_kick_bounce = bool(payload.get("kick_bounce", false))
	event.resulting_float_timer = float(payload.get("float_timer", 0.0))
	event.resulting_bounce = bool(payload.get("bounce", false))
	return event
