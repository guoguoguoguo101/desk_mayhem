extends Node3D

const Layout = preload("res://combat/mountain_arena_layout.gd")
const SHELL_PATH := "res://assets/environment/mountain_arena/mountain_arena_shell.obj"
const PLACEMENTS_PATH := "res://assets/environment/mountain_arena/kit_placements.json"
const KIT_DIR := "res://assets/environment/kits/"
const ARENA_FLOOR_DIR := "res://assets/environment/arena_floor/"
const ARENA_FLOOR_Y := 0.045
const FIRE_PROP_SCENE := preload("res://assets/vfx/fire_prop/FireProp_BillboardDemo.tscn")
const PAVER_SPECULAR := 0.08
# 进演武场后按 F7 轮换。数值是太阳、环境光和背景色，不改战斗。
# 第 2 渲染层只给人物轮廓光，场景网格不在这一层。
const CHARACTER_RIM_LAYER := 2
const DAY_TIMES: Array[Dictionary] = [
	{
		"name": "白天",
		"sun_rotation": Vector3(-58, -24, 0),
		"sun_color": Color(1.0, 0.97, 0.9),
		"sun_energy": 0.7,
		"ambient_color": Color(0.84, 0.9, 0.96),
		"ambient_energy": 0.26,
		"background": Color(0.64, 0.78, 0.9),
	},
	{
		"name": "下午",
		"sun_rotation": Vector3(-34, -52, 0),
		"sun_color": Color(1.0, 0.86, 0.68),
		"sun_energy": 0.62,
		"ambient_color": Color(1.0, 0.9, 0.76),
		"ambient_energy": 0.22,
		"background": Color(0.55, 0.68, 0.82),
	},
	{
		"name": "傍晚",
		"sun_rotation": Vector3(-12, -78, 0),
		"sun_color": Color(1.0, 0.46, 0.2),
		"sun_energy": 0.36,
		"ambient_color": Color(0.72, 0.4, 0.3),
		"ambient_energy": 0.16,
		"background": Color(0.4, 0.26, 0.3),
	},
	{
		"name": "夜晚",
		"sun_rotation": Vector3(-68, 150, 0),
		"sun_color": Color(0.62, 0.72, 1.0),
		"sun_energy": 0.18,
		"ambient_color": Color(0.2, 0.26, 0.4),
		"ambient_energy": 0.26,
		"background": Color(0.04, 0.06, 0.12),
	},
]

var built := false
var day_index := 3
var light_captured := false
var saved_sun_rotation := Vector3(-48, -35, 0)
var saved_sun_color := Color(1, 0.94, 0.85)
var saved_sun_energy := 0.55
var saved_ambient_color := Color(0.77, 0.85, 0.9)
var saved_ambient_energy := 0.22
var saved_background := Color(0.57, 0.7, 0.75)
var saved_background_mode := Environment.BG_COLOR
const NIGHT_SKY_SHADER := "res://assets/environment/sky/night_sky.gdshader"
const MOON_TEXTURE := "res://assets/environment/sky/moon.png"
var night_sky: Sky
var night_lights: Node3D
var character_rim: DirectionalLight3D
var lantern_glow: Array[StandardMaterial3D] = []
var lantern_glow_base: Array[float] = []
var day_label: Label
var floor_materials: Dictionary = {}
var floor_albedo: Texture2D
var floor_material_template: StandardMaterial3D
var floor_rng := RandomNumberGenerator.new()

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
	_build_night_lights()
	place_arena_floor()
	var paving := preload("res://courtyard_paving.gd").new()
	add_child(paving)
	# Purely visual teaching prop near the west entrance, away from the duel circle.
	var fire_prop := FIRE_PROP_SCENE.instantiate()
	fire_prop.position = Vector3(-20.0, ARENA_FLOOR_Y + 0.02, 7.0)
	add_child(fire_prop)
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
	_apply_day_time()

func hide_arena() -> void:
	_restore_day_time()
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

static func mark_character_rim(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).layers |= CHARACTER_RIM_LAYER
	for child in root.get_children():
		mark_character_rim(child)

func _build_night_lights() -> void:
	night_lights = Node3D.new()
	night_lights.name = "NightLights"
	night_lights.visible = false
	add_child(night_lights)
	character_rim = DirectionalLight3D.new()
	character_rim.name = "CharacterRim"
	character_rim.rotation_degrees = Vector3(-22, -40, 0)
	character_rim.light_color = Color(0.78, 0.86, 1.0)
	character_rim.light_energy = 0.55
	character_rim.shadow_enabled = false
	character_rim.light_cull_mask = CHARACTER_RIM_LAYER
	night_lights.add_child(character_rim)
	# 兼容渲染每个网格大约只吃进 8 盏点光。灯按灯群各放一盏，不给每只石灯各挂一盏。
	for pool in [
		[Vector3(-4.8, 3.35, -29.6), 1.25, 12.0],
		[Vector3(4.8, 3.35, -29.6), 1.25, 12.0],
		[Vector3(-34.5, 1.4, -24.0), 1.05, 12.0],
		[Vector3(-31.0, 1.4, -27.0), 1.05, 10.0],
		[Vector3(34.5, 1.4, -24.0), 1.05, 12.0],
		[Vector3(31.0, 1.4, -27.0), 1.05, 10.0],
		[Vector3(-29.0, 1.4, 18.0), 1.05, 9.0],
		[Vector3(30.0, 1.4, 24.0), 1.05, 14.0],
	]:
		var light := OmniLight3D.new()
		light.position = pool[0]
		light.light_energy = pool[1]
		light.omni_range = pool[2]
		light.light_color = Color(1.0, 0.72, 0.38)
		light.shadow_enabled = false
		night_lights.add_child(light)
	for child in get_children():
		var kit_name := String(child.name)
		if kit_name == "palace_lantern" or kit_name == "stone_lantern":
			_collect_lantern_glow(child)

func _collect_lantern_glow(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material is StandardMaterial3D and (material as StandardMaterial3D).emission_enabled:
					var glow := material as StandardMaterial3D
					if not lantern_glow.has(glow):
						lantern_glow.append(glow)
						lantern_glow_base.append(glow.emission_energy_multiplier)
	for child in node.get_children():
		_collect_lantern_glow(child)

func _set_night_lights(enabled: bool) -> void:
	if night_lights:
		night_lights.visible = enabled
	for index in lantern_glow.size():
		lantern_glow[index].emission_energy_multiplier = lantern_glow_base[index] * (1.4 if enabled else 1.0)

func _set_night_sky(environment: Environment, enabled: bool) -> void:
	if not enabled:
		environment.sky = null
		environment.background_mode = saved_background_mode
		return
	if night_sky == null:
		var shader := load(NIGHT_SKY_SHADER) as Shader
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("moon_tex", load(MOON_TEXTURE))
		night_sky = Sky.new()
		night_sky.sky_material = material
	var moon_dir := Vector3(0.0, 0.38, 0.925)
	(night_sky.sky_material as ShaderMaterial).set_shader_parameter("moon_dir", moon_dir.normalized())
	environment.background_mode = Environment.BG_SKY
	environment.sky = night_sky

func place_arena_floor() -> void:
	# Stable appearance across clients and scene reloads.
	floor_rng.seed = 29417
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
			_floor_piece(root, cache, variants[floor_rng.randi_range(0, 2)], Vector3(x, ARENA_FLOOR_Y, z), float(floor_rng.randi_range(0, 3)) * PI * 0.5)

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
	_apply_floor_stone(node, floor_rng.randi_range(0, 23))

func _apply_floor_stone(node: Node, variant: int) -> void:
	# Imported GLBs embed the old texture: override only this arena's floor instances.
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(surface)
			if original == null:
				continue
			var category := String(original.resource_name)
			if category not in ["M_Stone_Light", "M_Stone_Dark", "M_Gold_Trim"]:
				continue
			var key := category + str(variant)
			if not floor_materials.has(key):
				if floor_albedo == null:
					floor_albedo = load(ARENA_FLOOR_DIR + "textures/slate_moss_albedo.png")
					# Also cover fresh checkouts whose default PNG import has no mipmaps.
					var pixels := floor_albedo.get_image()
					if not pixels.has_mipmaps():
						if pixels.is_compressed():
							pixels.decompress()
						pixels.generate_mipmaps()
						floor_albedo = ImageTexture.create_from_image(pixels)
				if floor_material_template == null:
					floor_material_template = _sample_paving_material()
				var stone := floor_material_template.duplicate() as StandardMaterial3D
				stone.resource_name = "WeatheredSlate_" + key
				stone.albedo_texture = floor_albedo
				# Arena UVs tile beyond 0..1; the sample's clamped UVs would smear edges.
				stone.texture_repeat = true
				# Different crops create quiet, lightly cracked and weathered slabs.
				var rng := RandomNumberGenerator.new()
				rng.seed = 8317 + variant * 173
				var scale_uv := rng.randf_range(0.45, 0.95)
				var offset := Vector3(rng.randf(), rng.randf(), 0)
				if variant % 4 == 0:
					# A clean patch of the source, without the branching mossy cracks.
					scale_uv = 0.12
					offset = Vector3(0.65, 0.10, 0)
				stone.uv1_scale = Vector3(scale_uv * (-1.0 if variant % 2 else 1.0), scale_uv, 1)
				stone.uv1_offset = offset
				if category == "M_Stone_Dark":
					# Recessed medallion / ornamental band needs contrast with its relief.
					stone.albedo_color = Color(0.60, 0.60, 0.60)
				elif category == "M_Gold_Trim":
					# Quiet pale stone inlay keeps the concentric rails legible.
					stone.uv1_scale = Vector3(0.10, 0.10, 1)
					stone.uv1_offset = Vector3(0.65, 0.10, 0)
				floor_materials[key] = stone
			node.set_surface_override_material(surface, floor_materials[key])
	for child in node.get_children():
		_apply_floor_stone(child, variant)

func _sample_paving_material() -> StandardMaterial3D:
	# Inherit Godot's imported sample material, including specular conversion.
	var packed := load(KIT_DIR + "paving_square.glb") as PackedScene
	if packed != null:
		var sample := packed.instantiate()
		for mesh_node in sample.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh_node.mesh.get_surface_count():
				var source: Material = mesh_node.mesh.surface_get_material(surface)
				if source is StandardMaterial3D and source.resource_name == "paving_square":
					var result := source.duplicate() as StandardMaterial3D
					result.metallic_specular = PAVER_SPECULAR
					sample.free()
					return result
		sample.free()
	push_warning("Sample paving material unavailable; using neutral stone fallback.")
	var fallback := StandardMaterial3D.new()
	fallback.roughness = 0.84
	fallback.metallic_specular = PAVER_SPECULAR
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	return fallback

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

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_F7:
		return
	day_index = (day_index + 1) % DAY_TIMES.size()
	_apply_day_time()
	get_viewport().set_input_as_handled()

func _apply_day_time() -> void:
	var sun := _sun()
	var world := _world()
	if sun == null or world == null or world.environment == null:
		return
	if not light_captured:
		saved_sun_rotation = sun.rotation_degrees
		saved_sun_color = sun.light_color
		saved_sun_energy = sun.light_energy
		saved_ambient_color = world.environment.ambient_light_color
		saved_ambient_energy = world.environment.ambient_light_energy
		saved_background = world.environment.background_color
		saved_background_mode = world.environment.background_mode
		light_captured = true
	var preset: Dictionary = DAY_TIMES[day_index]
	sun.rotation_degrees = preset.sun_rotation
	sun.light_color = preset.sun_color
	sun.light_energy = preset.sun_energy
	world.environment.ambient_light_color = preset.ambient_color
	world.environment.ambient_light_energy = preset.ambient_energy
	world.environment.background_color = preset.background
	var night := str(preset.name) == "夜晚"
	_set_night_lights(night)
	_set_night_sky(world.environment, night)
	_show_day_label(preset)
	print("演武场灯光 %s 太阳能量 %.2f 颜色 %s 俯仰 %.0f 环境能量 %.2f" % [
		preset.name, preset.sun_energy, preset.sun_color, preset.sun_rotation.x, preset.ambient_energy
	])

func _restore_day_time() -> void:
	if not light_captured:
		return
	var sun := _sun()
	var world := _world()
	if sun:
		sun.rotation_degrees = saved_sun_rotation
		sun.light_color = saved_sun_color
		sun.light_energy = saved_sun_energy
	if world and world.environment:
		world.environment.ambient_light_color = saved_ambient_color
		world.environment.ambient_light_energy = saved_ambient_energy
		world.environment.background_color = saved_background
		world.environment.background_mode = saved_background_mode
		world.environment.sky = null
	_set_night_lights(false)
	light_captured = false
	if day_label:
		day_label.visible = false

func _show_day_label(preset: Dictionary) -> void:
	if day_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		add_child(layer)
		day_label = Label.new()
		day_label.position = Vector2(24, 24)
		day_label.add_theme_font_size_override("font_size", 18)
		day_label.add_theme_color_override("font_color", Color(1, 0.95, 0.86))
		layer.add_child(day_label)
	var rotation: Vector3 = preset.sun_rotation
	day_label.text = "%s  F7切换\n太阳能量 %.2f  颜色 %s  俯仰 %.0f°\n环境能量 %.2f  颜色 %s" % [
		preset.name,
		preset.sun_energy,
		preset.sun_color,
		rotation.x,
		preset.ambient_energy,
		preset.ambient_color,
	]
	day_label.visible = true

func _sun() -> DirectionalLight3D:
	var root := get_parent()
	if root == null:
		return null
	return root.get_node_or_null("Sun") as DirectionalLight3D

func _world() -> WorldEnvironment:
	var root := get_parent()
	if root == null:
		return null
	return root.get_node_or_null("Environment") as WorldEnvironment

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
