class_name ServerRoomConfig
extends RefCounted

## Keep the future room shape explicit even while the public test room is 1v1.
const RESERVED_MAX_PLAYERS := 4

var room_id := "default"
var mode := "duel"
var active_capacity := 2
var friendly_fire := false
var team_count := 2

func team_for_slot(slot: int) -> int:
	if mode == "teams":
		return 0 if slot < 2 else 1
	return slot

func payload() -> Dictionary:
	return {
		"room_id": room_id,
		"mode": mode,
		"active_capacity": active_capacity,
		"reserved_max_players": RESERVED_MAX_PLAYERS,
		"friendly_fire": friendly_fire,
		"team_count": team_count,
	}
