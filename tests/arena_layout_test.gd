extends SceneTree

const ArenaLayout = preload("res://combat/arena_layout.gd")
const Motion = preload("res://combat/arena_motion.gd")
const CombatWorld = preload("res://combat/combat_world.gd")
const NetworkManager = preload("res://network_manager.gd")
const DuelHall = preload("res://duel_hall.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("ARENA_LAYOUT FAIL " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var collision_root := Node3D.new()
	root.add_child(collision_root)
	Motion.build(collision_root)
	var hall = DuelHall.new()
	hall.build()
	var expected := {}
	for entry in ArenaLayout.collision_entries():
		check(not expected.has(entry.id), "unique layout id %s" % entry.id)
		expected[entry.id] = entry
	var authority := indexed_bodies(collision_root)
	var visuals := indexed_bodies(hall)
	check(authority.size() == expected.size(), "authority consumes every layout collider")
	check(visuals.size() == expected.size(), "visual hall consumes every layout collider")
	for id in expected:
		check(authority.has(id), "authority collider %s" % id)
		check(visuals.has(id), "visual collider %s" % id)
		if authority.has(id) and visuals.has(id):
			check(same_collider(authority[id], visuals[id]), "matching transform and shape %s" % id)
	check(CombatWorld.SPAWNS == ArenaLayout.PLAYER_SPAWNS, "combat player spawns share layout")
	check(NetworkManager.SPAWNS == ArenaLayout.PLAYER_SPAWNS, "legacy lobby spawns share layout")
	check(CombatWorld.DUMMY_SPAWNS == ArenaLayout.DUMMY_SPAWNS, "dummy spawns share layout")
	hall.free()
	print("ARENA_LAYOUT %s colliders=%d" % ["PASS" if failures == 0 else "FAIL", expected.size()])
	quit(0 if failures == 0 else 1)

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
