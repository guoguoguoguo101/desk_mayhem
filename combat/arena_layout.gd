extends RefCounted

## Single source of truth for gameplay-relevant arena geometry. Client visuals
## and prediction/authority collision builders consume these descriptors.
## Decorative meshes, materials, lights and distant scenery do not belong here.
const ENTITY_CENTER_Y := 0.96
const PLAYER_SPAWNS: Array[Vector3] = [
	Vector3(-12.0, ENTITY_CENTER_Y, 0.0),
	Vector3(12.0, ENTITY_CENTER_Y, 0.0),
	Vector3(-12.0, ENTITY_CENTER_Y, -8.0),
	Vector3(12.0, ENTITY_CENTER_Y, 8.0),
]
const DUMMY_SPAWNS: Array[Vector3] = [
	Vector3(-8.0, ENTITY_CENTER_Y, -8.0),
	Vector3(8.0, ENTITY_CENTER_Y, 8.0),
]

static func collision_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		box_entry("floor", "floor", Vector3(0, -0.2, 0), Vector3(56, 0.4, 44)),
		box_entry("wall_north", "wall", Vector3(0, 1.9, -20.75), Vector3(54.2, 3.8, 0.5)),
		box_entry("wall_south", "wall", Vector3(0, 1.9, 20.75), Vector3(54.2, 3.8, 0.5)),
		box_entry("wall_west", "wall", Vector3(-26.75, 1.9, 0), Vector3(0.5, 3.8, 41.5)),
		box_entry("wall_east", "wall", Vector3(26.75, 1.9, 0), Vector3(0.5, 3.8, 41.5)),
	]
	for x in [-15.0, -7.5, 0.0, 7.5, 15.0]:
		for z in [-11.0, 11.0]:
			entries.append(cylinder_entry("pillar_%s_%s" % [coordinate_id(x), coordinate_id(z)], "pillar", Vector3(x, 1.7, z), 0.28, 3.4))
	for x in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		entries.append(box_entry("bench_south_%s" % coordinate_id(x), "bench", Vector3(x, 0.42, 16.6), Vector3(1.8, 0.12, 0.55)))
		if x != 0.0:
			entries.append(box_entry("bench_north_%s" % coordinate_id(x), "bench", Vector3(x, 0.42, -16.6), Vector3(1.8, 0.12, 0.55)))
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
