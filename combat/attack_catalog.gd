class_name AttackCatalog
extends RefCounted

## Damage remains intentionally profile-specific for now: training targets use
## the existing tuning, while PvP preserves the existing player values.

const PROFILE_PVP := "pvp"
const PROFILE_TRAINING := "training"
const DEFAULT_DAMAGE := 10

const ATTACKS := {
	"回旋锅": {"pvp": 12, "training": 14, "ranged": true},
	"回旋锅·回收": {"pvp": 10, "training": 12, "ranged": true},
	"文件夹": {"pvp": 12, "training": 18, "ranged": true},
	"锅": {"pvp": 18, "training": 20, "ranged": true},
	"咖啡": {"pvp": 12, "training": 12, "ranged": true},
	"轻拳": {"pvp": 8, "training": 8, "ranged": false},
	"连拳": {"pvp": 8, "training": 8, "ranged": false},
	"补拳": {"pvp": 10, "training": 10, "ranged": false},
	"上勾拳": {"pvp": 16, "training": 18, "ranged": false},
	"前踢": {"pvp": 12, "training": 12, "ranged": false},
	"踢飞": {"pvp": 22, "training": 26, "ranged": false},
	"雨伞": {"pvp": 12, "training": 12, "ranged": false},
	"雨伞挑飞": {"pvp": 20, "training": 25, "ranged": false},
	"扣锅": {"pvp": 28, "training": 35, "ranged": false},
	"空中扣锅": {"pvp": 26, "training": 32, "ranged": false},
	"办公椅": {"pvp": 8, "training": 8, "ranged": false},
	"椅推": {"pvp": 4, "training": 4, "ranged": false},
	"旋伞": {"pvp": 8, "training": 8, "ranged": false},
}

## These are hit-validation definitions, not animation timing. The attacker
## chooses an attack ID; the authoritative simulation resolves its targets.
const MELEE_INTENTS := {
	"punch_light": {"method": "punch_from", "reach": 1.95, "dot": 0.15, "height": 3.2, "line_of_sight": true},
	"punch_follow": {"method": "punch_follow", "reach": 1.95, "dot": 0.15, "height": 3.2, "line_of_sight": true},
	"punch_uppercut": {"method": "punch_launch", "reach": 1.95, "dot": 0.15, "height": 3.2, "line_of_sight": true},
	"punch_air": {"method": "punch_from", "reach": 1.95, "dot": 0.15, "height": 3.2, "line_of_sight": true},
	"kick_front": {"method": "kick_from", "reach": 2.5, "dot": 0.12, "height": 3.4, "line_of_sight": true},
	"umbrella_uppercut": {"method": "launch_up", "reach": 2.4, "dot": 0.2, "height": 3.2, "line_of_sight": true},
	"pot_slam": {"method": "slam_from_pot", "reach": 2.5, "dot": 0.1, "height": 3.5, "line_of_sight": false},
	"umbrella_spin": {"method": "umbrella_spin_from", "reach": 3.0, "dot": -1.0, "height": 2.8, "line_of_sight": true},
}

const SEGMENT_INTENTS := {
	"returning_pot_out": {"method": "pot_outbound", "radius": 0.85, "ground_height": 1.15, "air_height": 3.0, "line_of_sight": true},
	"returning_pot_back": {"method": "pot_return", "radius": 0.85, "ground_height": 1.15, "air_height": 3.0, "line_of_sight": true},
}

static func damage_for(attack_id: String, profile: String) -> int:
	var definition: Dictionary = ATTACKS.get(attack_id, {})
	return int(definition.get(profile, DEFAULT_DAMAGE))

static func is_ranged(attack_id: String) -> bool:
	var definition: Dictionary = ATTACKS.get(attack_id, {})
	return bool(definition.get("ranged", false))

static func melee_definition(intent_id: String) -> Dictionary:
	var legacy: Dictionary = MELEE_INTENTS.get(intent_id, {})
	var rules = preload("res://combat/battle_rules.gd")
	var frame: Dictionary = rules.skill_frame(intent_id)
	if frame.is_empty() or not frame.has("reach"):
		return legacy
	return {
		"method": legacy.get("method", ""),
		"reach": frame.reach,
		"dot": frame.dot,
		"height": frame.height,
		"line_of_sight": legacy.get("line_of_sight", true),
	}

static func segment_definition(intent_id: String) -> Dictionary:
	return SEGMENT_INTENTS.get(intent_id, {})
