class_name HitIntent
extends RefCounted

const AttackData = preload("res://combat/attack_catalog.gd")

## An unconfirmed request to test a melee attack. This is safe to serialize:
## it contains IDs and values only, never a scene-node reference.
var intent_id := ""
var attacker_id := 0
var issued_tick := 0
var direction := Vector3.FORWARD
var reach := 0.0
var dot_min := -1.0
var height_limit := 0.0
var effect_method := ""
var requires_line_of_sight := true
var requires_direction_match := true
var shape := "melee"
var segment_from := Vector3.ZERO
var segment_to := Vector3.ZERO
var segment_radius := 0.0
var ground_height_limit := 0.0
var airborne_height_limit := 0.0

static func melee(intent_name: String, source_id: int, forward: Vector3, tick := 0):
	var definition := AttackData.melee_definition(intent_name)
	var intent = load("res://combat/hit_intent.gd").new()
	intent.intent_id = intent_name
	intent.attacker_id = source_id
	intent.issued_tick = tick
	intent.direction = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	intent.reach = float(definition.get("reach", 0.0))
	intent.dot_min = float(definition.get("dot", -1.0))
	intent.height_limit = float(definition.get("height", 0.0))
	intent.effect_method = str(definition.get("method", ""))
	intent.requires_line_of_sight = bool(definition.get("line_of_sight", true))
	return intent

static func segment(intent_name: String, source_id: int, from: Vector3, to: Vector3, tick := 0):
	var definition := AttackData.segment_definition(intent_name)
	var intent = load("res://combat/hit_intent.gd").new()
	intent.intent_id = intent_name
	intent.attacker_id = source_id
	intent.issued_tick = tick
	intent.shape = "segment"
	intent.segment_from = from
	intent.segment_to = to
	intent.direction = (to - from).normalized() if from.distance_squared_to(to) > 0.0001 else Vector3.FORWARD
	intent.segment_radius = float(definition.get("radius", 0.0))
	intent.ground_height_limit = float(definition.get("ground_height", 0.0))
	intent.airborne_height_limit = float(definition.get("air_height", 0.0))
	intent.effect_method = str(definition.get("method", ""))
	intent.requires_line_of_sight = bool(definition.get("line_of_sight", true))
	# Returning pots pull toward their owner, so their resulting knockback is
	# intentionally different from the projectile flight direction.
	intent.requires_direction_match = false
	return intent

func is_valid() -> bool:
	if shape == "segment":
		return not effect_method.is_empty() and segment_radius > 0.0 and ground_height_limit > 0.0 and airborne_height_limit > 0.0
	return not effect_method.is_empty() and reach > 0.0 and height_limit > 0.0
