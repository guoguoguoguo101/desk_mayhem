extends SceneTree

const Catalog = preload("res://combat/arena_catalog.gd")
const Layout = preload("res://combat/mountain_arena_layout.gd")
const Motion = preload("res://combat/arena_motion.gd")
const CombatWorld = preload("res://combat/combat_world.gd")
const MountainArena = preload("res://mountain_arena.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MOUNTAIN_ARENA FAIL " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var prediction_root := Node3D.new()
	root.add_child(prediction_root)
	Motion.build(prediction_root, Layout)
	var visual := MountainArena.new()
	root.add_child(visual)
	var expected := index_entries()
	var prediction := indexed_bodies(prediction_root)
	var client := indexed_bodies(visual)
	check(expected.size() == 14, "expected collider count")
	check(prediction.size() == expected.size(), "prediction consumes all colliders")
	check(client.size() == expected.size(), "client consumes all colliders")
	for id in expected:
		check(prediction.has(id), "prediction collider " + id)
		check(client.has(id), "client collider " + id)
		if prediction.has(id) and client.has(id):
			check(same_collider(prediction[id], client[id]), "matching collider " + id)
	var sim = CombatWorld.new()
	sim.configure_arena(Catalog.MOUNTAIN_COURTYARD)
	check(sim.player_spawns() == Layout.PLAYER_SPAWNS, "combat player spawns")
	check(sim.dummy_spawns() == Layout.DUMMY_SPAWNS, "combat dummy spawns")
	sim.attach(root)
	var snapshot: Dictionary = sim.capture()
	check(str(snapshot.get("map_id", "")) == Catalog.MOUNTAIN_COURTYARD, "snapshot carries map id")
	check(FileAccess.file_exists(MountainArena.SHELL_PATH), "shell model exists")
	check(FileAccess.file_exists(MountainArena.PLACEMENTS_PATH), "kit placements exist")
	check(FileAccess.file_exists("res://assets/environment/kits/catalog.json"), "kit catalog exists")
	check(FileAccess.file_exists("res://assets/environment/kits/bamboo_culm_tall.glb"), "bamboo kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/stone_lantern.glb"), "lantern kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/cinnabar_pillar.glb"), "pillar kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/roof_tile.glb"), "roof kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/maple_large.glb"), "maple kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/azalea_large.glb"), "azalea kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/peony_mixed.glb"), "peony kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/hedge_white.glb"), "hedge kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/main_hall.glb"), "main hall kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/wood_pillar.glb"), "wood pillar kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/martial_banner.glb"), "banner kit exists")
	check(FileAccess.file_exists("res://assets/environment/kits/palace_lantern.glb"), "palace lantern kit exists")
	print("MOUNTAIN_ARENA %s colliders=%d" % ["PASS" if failures == 0 else "FAIL", expected.size()])
	quit(0 if failures == 0 else 1)

func index_entries() -> Dictionary:
	var result := {}
	for entry in Layout.collision_entries():
		check(not result.has(str(entry.id)), "unique id " + str(entry.id))
		result[str(entry.id)] = entry
	return result

func indexed_bodies(parent: Node) -> Dictionary:
	var result := {}
	for node in parent.find_children("*", "StaticBody3D", true, false):
		if node.has_meta("arena_layout_id"):
			result[str(node.get_meta("arena_layout_id"))] = node
	return result

func same_collider(a: StaticBody3D, b: StaticBody3D) -> bool:
	if a.position != b.position or a.rotation_degrees != b.rotation_degrees:
		return false
	var a_shape := collider_shape(a)
	var b_shape := collider_shape(b)
	if a_shape is BoxShape3D and b_shape is BoxShape3D:
		return a_shape.size == b_shape.size
	if a_shape is CylinderShape3D and b_shape is CylinderShape3D:
		return is_equal_approx(a_shape.radius, b_shape.radius) and is_equal_approx(a_shape.height, b_shape.height)
	return false

func collider_shape(body: StaticBody3D) -> Shape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child.shape
	return null
