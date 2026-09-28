extends RefCounted

const COURTYARD := "courtyard"
const MOUNTAIN_COURTYARD := "mountain_courtyard"
const DefaultLayout = preload("res://combat/arena_layout.gd")
const MountainLayout = preload("res://combat/mountain_arena_layout.gd")

static func normalize(map_id: String) -> String:
	return MOUNTAIN_COURTYARD if map_id == MOUNTAIN_COURTYARD else COURTYARD

static func layout(map_id: String):
	return MountainLayout if normalize(map_id) == MOUNTAIN_COURTYARD else DefaultLayout

static func player_spawns(map_id: String) -> Array[Vector3]:
	return layout(map_id).PLAYER_SPAWNS

static func dummy_spawns(map_id: String) -> Array[Vector3]:
	return layout(map_id).DUMMY_SPAWNS
