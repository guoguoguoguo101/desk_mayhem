extends Node3D

const Layout = preload("res://combat/mountain_arena_layout.gd")
const SHELL_PATH := "res://assets/environment/mountain_arena/mountain_arena_shell.obj"
const PLACEMENTS_PATH := "res://assets/environment/mountain_arena/kit_placements.json"
const KIT_DIR := "res://assets/environment/kits/"
const ARENA_FLOOR_DIR := "res://assets/environment/arena_floor/"
const ARENA_FLOOR_Y := 0.045

var built := false

func _ready() -> void:
	name = "MountainArena"
	build()
	visible = false
	set_solid(false)

func build() -> void:
	if built:
		return
	built = true
	var shell_loaded := add_shell()
	if not shell_loaded:
		build_fallback_visual()
	else:
		place_kits()
	place_arena_floor()
	for entry in Layout.collision_entries():
		add_layout_collider(entry)

func show_arena() -> void:
	var old_hall = get_parent().get_node_or_null("DuelHall")
	if old_hall:
		if not bool(old_hall.get("shown")):
			old_hall.show_hall()
		old_hall.visible = false
		old_hall.set_solid(false)
		old_hall.clear_dummies()
	visible = true
	set_solid(true)

func hide_arena() -> void:
	visible = false
	set_solid(false)
	var old_hall = get_parent().get_node_or_null("DuelHall")
	if old_hall and bool(old_hall.get("shown")):
		old_hall.hide_hall()

func add_shell() -> bool:
	if not ResourceLoader.exists(SHELL_PATH):
		return false
	var mesh: Mesh = load(SHELL_PATH)
	if mesh == null:
		return false
	var model := MeshInstance3D.new()
	model.name = "MountainArenaShell"
	model.mesh = mesh
	add_child(model)
	return true

func place_kits() -> void:
	if not FileAccess.file_exists(PLACEMENTS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PLACEMENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var cache := {}
	for item in parsed.get("placements", []):
		var kit_id := str(item.get("kit", ""))
		var packed: PackedScene = cached_kit(cache, kit_id)
		if packed == null:
			continue
		var node := packed.instantiate()
		node.name = kit_id
		var position: Array = item.position
		var rotation: Array = item.quaternion
		var scale: Array = item.scale
		node.position = Vector3(float(position[0]), float(position[1]), float(position[2]))
		node.quaternion = Quaternion(float(rotation[0]), float(rotation[1]), float(rotation[2]), float(rotation[3]))
		node.scale = Vector3(float(scale[0]), float(scale[1]), float(scale[2]))
		add_child(node)

func place_arena_floor() -> void:
	var root := Node3D.new()
	root.name = "ArenaFloor"
	add_child(root)
	var cache := {}
	_floor_piece(root, cache, "arena_center", Vector3(0, ARENA_FLOOR_Y, 0), 0.0)
	for index in 8:
		var yaw := float(index) * TAU / 8.0
		for piece in ["arena_inner_segment", "arena_middle_segment", "arena_outer_decor_segment", "arena_outer_plain_segment"]:
			_floor_piece(root, cache, piece, Vector3(0, ARENA_FLOOR_Y, 0), yaw)
	for index in 4:
		var yaw := float(index) * TAU / 4.0
		var radius := 5.05
		_floor_piece(root, cache, "arena_separator", Vector3(0, ARENA_FLOOR_Y, 0), yaw)
		_floor_piece(root, cache, "arena_anchor_tile", Vector3(cos(yaw) * radius, ARENA_FLOOR_Y + 0.02, -sin(yaw) * radius), 0.0)
	_floor_piece(root, cache, "arena_transition_left", Vector3(6.7, ARENA_FLOOR_Y, 0), 0.0)
	_floor_piece(root, cache, "arena_transition_right", Vector3(-6.7, ARENA_FLOOR_Y, 0), 0.0)
	_floor_piece(root, cache, "arena_transition_left", Vector3(0, ARENA_FLOOR_Y, -6.7), PI * 0.5)
	_floor_piece(root, cache, "arena_transition_right", Vector3(0, ARENA_FLOOR_Y, 6.7), PI * 0.5)
	_floor_piece(root, cache, "arena_notch_ring", Vector3(0, ARENA_FLOOR_Y, 0), 0.0)
	var variants := ["floor_tile_A", "floor_tile_B", "floor_tile_C"]
	for ix in range(-9, 10):
		for iz in range(-9, 10):
			var x := float(ix) + 0.5
			var z := float(iz) + 0.5
			if not _floor_tile_fits(x, z):
				continue
			_floor_piece(root, cache, variants[posmod(ix + iz * 2, 3)], Vector3(x, ARENA_FLOOR_Y, z), 0.0)

func _floor_piece(root: Node3D, cache: Dictionary, piece: String, at: Vector3, yaw: float) -> void:
	if not cache.has(piece):
		var path := ARENA_FLOOR_DIR + piece + ".glb"
		var loaded = load(path) if ResourceLoader.exists(path) else null
		cache[piece] = loaded if loaded is PackedScene else null
		if cache[piece] == null:
			push_warning("演武场地面模块未导入: %s" % path)
	var packed: PackedScene = cache[piece]
	if packed == null:
		return
	var node := packed.instantiate()
	node.name = "%s_%d" % [piece, root.get_child_count()]
	node.position = at
	node.rotation.y = yaw
	root.add_child(node)

func _floor_tile_fits(x: float, z: float) -> bool:
	if Vector2(x, z).length() < 6.32:
		return false
	for corner_x in [x - 0.5, x + 0.5]:
		for corner_z in [z - 0.5, z + 0.5]:
			if Vector2(corner_x, corner_z).length() > 9.65:
				return false
	for site in [Vector2(6.7, 0.0), Vector2(-6.7, 0.0), Vector2(0.0, -6.7), Vector2(0.0, 6.7)]:
		if absf(x - site.x) < 1.1 and absf(z - site.y) < 1.1:
			return false
	return true

func cached_kit(cache: Dictionary, kit_id: String) -> PackedScene:
	if cache.has(kit_id):
		return cache[kit_id]
	var resource_path := KIT_DIR + kit_id + ".glb"
	var packed = load(resource_path) if ResourceLoader.exists(resource_path) else null
	cache[kit_id] = packed if packed is PackedScene else null
	return cache[kit_id]

func add_layout_collider(entry: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.position = entry.position
	body.rotation_degrees = entry.rotation_degrees
	body.set_meta("arena_layout_id", str(entry.id))
	var shape_node := CollisionShape3D.new()
	if str(entry.shape) == "cylinder":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = float(entry.radius)
		cylinder.height = float(entry.height)
		shape_node.shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = entry.size
		shape_node.shape = box
	body.add_child(shape_node)
	add_child(body)

func set_solid(enabled: bool) -> void:
	for node in find_children("*", "StaticBody3D", true, false):
		node.collision_layer = 1 if enabled else 0
		node.collision_mask = 1 if enabled else 0

func build_fallback_visual() -> void:
	var stone := material(Color("8f826c"), 0.92)
	var stone_light := material(Color("c2b395"), 0.88)
	var plaster := material(Color("d8c7a8"), 0.86)
	var red := material(Color("7c1d12"), 0.65)
	var roof := material(Color("18262d"), 0.7)
	var green := material(Color("28531e"), 0.82)
	add_box(Vector3(0,-0.22,0),Vector3(108,0.44,88),stone)
	add_box(Vector3(0,0.02,0),Vector3(74,0.05,56),stone_light)
	add_cylinder(Vector3(0,0.07,0),14.5,0.06,stone,64)
	for entry in Layout.entries_for_role("wall"):
		add_box(entry.position,entry.size,plaster)
	var buildings := Layout.entries_for_role("building")
	for entry in buildings:
		add_box(entry.position,entry.size,plaster)
		add_box(entry.position+Vector3(0,float(entry.size.y)*0.55,0),Vector3(float(entry.size.x)+1.2,0.28,float(entry.size.z)+1.2),roof)
	for x in [-12.0,-4.0,4.0,12.0]:
		add_cylinder(Vector3(x,2.5,-30.2),0.28,4.8,red,12)
	for entry in Layout.entries_for_role("lantern"):
		add_cylinder(entry.position,float(entry.radius),float(entry.height),stone_light,8)
	for x in [-48.0,-39.0,39.0,48.0]:
		for z in [-26.0,24.0]:
			for offset in [-1.2,0.0,1.2]:
				add_cylinder(Vector3(x+offset,3.3,z),0.12,6.6,green,8)

func material(color: Color, roughness: float) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = roughness
	return value

func add_box(at: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)

func add_cylinder(at: Vector3, radius: float, height: float, mat: Material, segments: int) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)
