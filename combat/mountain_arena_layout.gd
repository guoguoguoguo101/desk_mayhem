extends RefCounted

## Gameplay layout for the larger mountain sect courtyard. The Blender GLB is
## presentation only; prediction and the Headless server consume these shapes.
const MAP_ID := "mountain_courtyard"
const ENTITY_CENTER_Y := 0.96
const PLAYER_SPAWNS: Array[Vector3] = [
	Vector3(-16.0, ENTITY_CENTER_Y, 0.0),
	Vector3(16.0, ENTITY_CENTER_Y, 0.0),
	Vector3(-16.0, ENTITY_CENTER_Y, -10.0),
	Vector3(16.0, ENTITY_CENTER_Y, 10.0),
]
const DUMMY_SPAWNS: Array[Vector3] = [
	Vector3(-10.0, ENTITY_CENTER_Y, -10.0),
	Vector3(10.0, ENTITY_CENTER_Y, 10.0),
]

static func collision_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		box_entry("floor", "floor", Vector3(0, -0.2, 0), Vector3(108, 0.4, 88)),
		box_entry("wall_north", "wall", Vector3(0, 2.0, -43.5), Vector3(108, 4.0, 1.0)),
		box_entry("wall_south", "wall", Vector3(0, 2.0, 43.5), Vector3(108, 4.0, 1.0)),
		box_entry("wall_west", "wall", Vector3(-53.5, 2.0, 0), Vector3(1.0, 4.0, 86)),
		box_entry("wall_east", "wall", Vector3(53.5, 2.0, 0), Vector3(1.0, 4.0, 86)),
		box_entry("temple", "building", Vector3(0, 2.0, -35.0), Vector3(32, 4.0, 9.0)),
		box_entry("pavilion_west", "building", Vector3(-43.0, 1.8, 2.0), Vector3(9.0, 3.6, 12.0)),
		box_entry("pavilion_east", "building", Vector3(43.0, 1.8, 2.0), Vector3(9.0, 3.6, 12.0)),
		box_entry("gate_south_west", "building", Vector3(-15.0, 2.0, 38.0), Vector3(19.0, 4.0, 7.0)),
		box_entry("gate_south_east", "building", Vector3(15.0, 2.0, 38.0), Vector3(19.0, 4.0, 7.0)),
	]
	for x in [-29.0, 29.0]:
		for z in [-18.0, 18.0]:
			entries.append(cylinder_entry("stone_lantern_%s_%s" % [coordinate_id(x), coordinate_id(z)], "lantern", Vector3(x, 0.85, z), 0.55, 1.7))
	return entries

static func entries_for_role(role: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in collision_entries():
		if str(entry.role) == role:
			result.append(entry)
	return result

static func box_entry(id: String, role: String, position: Vector3, size: Vector3) -> Dictionary:
	return {"id": id, "role": role, "shape": "box", "position": position, "size": size, "rotation_degrees": Vector3.ZERO}

static func cylinder_entry(id: String, role: String, position: Vector3, radius: float, height: float) -> Dictionary:
	return {"id": id, "role": role, "shape": "cylinder", "position": position, "radius": radius, "height": height, "rotation_degrees": Vector3.ZERO}

static func coordinate_id(value: float) -> String:
	return ("m" if value < 0.0 else "p") + str(int(absf(value) * 10.0))
