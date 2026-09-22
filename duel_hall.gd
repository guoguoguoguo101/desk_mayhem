extends Node3D

# 地面、墙、瓦、木柱贴图来自 Poly Haven，CC0。
# https://polyhaven.com  wood_floor / clay_roof_tiles / plastered_wall / wooden_planks

const OFFICE_NODES := ["Architecture", "Furniture", "MeetingArea", "BreakArea", "ArenaCover"]

var shown := false
var hall_dummies: Array[Node] = []
var light_saved := false
var collision_backup: Array[Dictionary] = []
var lanterns: Array[Node3D] = []
var saved_sun_color := Color.WHITE
var saved_sun_energy := 1.0
var saved_bg := Color.WHITE
var saved_ambient := Color.WHITE
var saved_ambient_energy := 0.6

func _ready() -> void:
	name = "DuelHall"
	build()
	visible = false
	set_solid(false)

func show_hall() -> void:
	if shown:
		return
	shown = true
	hide_office()
	visible = true
	set_solid(true)
	warm_light(true)
	spawn_dummies()

func hide_hall() -> void:
	visible = false
	set_solid(false)
	clear_dummies()
	if not shown:
		return
	shown = false
	restore_office()
	warm_light(false)

func _process(_delta: float) -> void:
	if not visible:
		return
	var time := Time.get_ticks_msec() / 1000.0
	for index in lanterns.size():
		lanterns[index].rotation.z = sin(time * 0.85 + float(index) * 0.7) * 0.04

func build() -> void:
	var plaster := textured("res://assets/polyhaven/plastered_wall_diff_1k.jpg", "res://assets/polyhaven/plastered_wall_nor_gl_1k.jpg", Color(0.96, 0.94, 0.9), Vector3(0.55, 0.55, 0.55), 0.92)
	var yard := textured("res://assets/polyhaven/plastered_wall_diff_1k.jpg", "res://assets/polyhaven/plastered_wall_nor_gl_1k.jpg", Color(0.62, 0.56, 0.48), Vector3(0.45, 0.45, 0.45), 0.95)
	var floor_wood := textured("res://assets/polyhaven/wood_floor_diff_1k.jpg", "res://assets/polyhaven/wood_floor_nor_gl_1k.jpg", Color(0.92, 0.78, 0.58), Vector3(0.42, 0.42, 0.42), 0.62)
	var plank := textured("res://assets/polyhaven/wooden_planks_diff_1k.jpg", "res://assets/polyhaven/wooden_planks_nor_gl_1k.jpg", Color(0.78, 0.48, 0.28), Vector3(0.7, 0.7, 0.7), 0.7)
	var pillar_red := textured("res://assets/polyhaven/wooden_planks_diff_1k.jpg", "res://assets/polyhaven/wooden_planks_nor_gl_1k.jpg", Color(0.72, 0.16, 0.1), Vector3(0.85, 0.85, 0.85), 0.55)
	var roof := textured("res://assets/polyhaven/clay_roof_tiles_diff_1k.jpg", "res://assets/polyhaven/clay_roof_tiles_nor_gl_1k.jpg", Color(0.9, 0.48, 0.32), Vector3(16, 5, 5), 0.78)
	roof.uv1_triplanar = false
	var ink := flat_mat(Color(0.14, 0.08, 0.06), 0.7)
	var gold := flat_mat(Color(0.78, 0.6, 0.28), 0.4)
	var cinnabar := flat_mat(Color(0.62, 0.1, 0.08), 0.5)
	var glow := glow_mat(Color(0.9, 0.28, 0.1), Color(1.0, 0.48, 0.16), 2.2)

	add_static_box(Vector3(0, -0.2, 0), Vector3(56, 0.4, 44), yard)
	add_mesh(Vector3(0, 0.025, 0), Vector3(34, 0.05, 26), floor_wood)
	add_trim(gold)

	add_static_box(Vector3(0, 1.9, -20.75), Vector3(54.2, 3.8, 0.5), plaster)
	add_static_box(Vector3(0, 1.9, 20.75), Vector3(54.2, 3.8, 0.5), plaster)
	add_static_box(Vector3(-26.75, 1.9, 0), Vector3(0.5, 3.8, 41.5), plaster)
	add_static_box(Vector3(26.75, 1.9, 0), Vector3(0.5, 3.8, 41.5), plaster)
	add_wall_dressing(plank, ink, gold, cinnabar)
	add_roof(roof, gold, cinnabar)
	add_pillars(pillar_red, gold)
	add_moon(cinnabar, gold, ink)
	add_lattices(ink)
	add_benches(plank, ink)
	add_banners(cinnabar, gold, plank)
	var lantern_x: Array[float] = [-12.0, 0.0, 12.0]
	var lantern_z: Array[float] = [-9.0, 9.0]
	for lx in lantern_x:
		for lz in lantern_z:
			add_lantern(Vector3(lx, 2.55, lz), gold, glow)
	add_sign("比武大厅", Vector3(0, 3.35, -20.35), 180, 64)
	add_sign("以武会友", Vector3(0, 2.55, 20.35), 0, 72)
	add_carpet(cinnabar, gold)

func spawn_dummies() -> void:
	clear_dummies()
	var template := get_parent().get_node_or_null("TrainingDummy1")
	if template == null:
		return
	var spots: Array[Vector3] = [Vector3(-8, 0, -8), Vector3(8, 0, 8)]
	var names: Array[String] = ["稻草人甲", "稻草人乙"]
	for index in 2:
		var copy := template.duplicate()
		copy.name = "HallDummy%d" % index
		copy.remove_from_group("training_dummies")
		copy.add_to_group("hall_dummies")
		copy.add_to_group("combat_targets")
		get_parent().add_child(copy)
		copy.global_position = spots[index]
		copy.visible = true
		copy.set_process(true)
		copy.set_physics_process(true)
		var shape := copy.get_node_or_null("CollisionShape3D")
		if shape is CollisionShape3D and shape.shape != null:
			shape.shape = shape.shape.duplicate()
			shape.disabled = false
		copy.set("hall_dummy", true)
		copy.set("dummy_index", index)
		copy.set("display_name", names[index])
		copy.set("revive_delay", 3.0)
		copy.set("suppress_kill", true)
		copy.call("revive")
		copy.set("suppress_kill", false)
		hall_dummies.append(copy)

func clear_dummies() -> void:
	for dummy in hall_dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	hall_dummies.clear()

func dummy_by_index(index: int) -> Node:
	for dummy in hall_dummies:
		if is_instance_valid(dummy) and int(dummy.get("dummy_index")) == index:
			return dummy
	return null

func capture_dummies() -> Array:
	var rows: Array = []
	for dummy in hall_dummies:
		if not is_instance_valid(dummy):
			continue
		rows.append({
			"i": int(dummy.get("dummy_index")),
			"hp": int(dummy.get("health")),
			"down": bool(dummy.get("downed")),
			"p": dummy.global_position,
			"revive": float(dummy.get("revive_time")),
		})
	return rows

func apply_dummies(rows: Array) -> void:
	for row in rows:
		var dummy := dummy_by_index(int(row["i"]))
		if dummy == null:
			continue
		dummy.global_position = row["p"]
		dummy.set("suppress_kill", true)
		if bool(row["down"]):
			if not dummy.get("downed"):
				dummy.call("knock_down")
			dummy.set("health", 0)
			dummy.set("revive_time", float(row["revive"]))
		else:
			if dummy.get("downed"):
				dummy.call("revive")
			dummy.set("health", int(row["hp"]))
			dummy.call("refresh_idle_label")
		dummy.set("suppress_kill", false)

func add_trim(gold: Material) -> void:
	add_mesh(Vector3(0, 0.07, -12.9), Vector3(34.2, 0.08, 0.14), gold)
	add_mesh(Vector3(0, 0.07, 12.9), Vector3(34.2, 0.08, 0.14), gold)
	add_mesh(Vector3(-16.95, 0.07, 0), Vector3(0.14, 0.08, 26), gold)
	add_mesh(Vector3(16.95, 0.07, 0), Vector3(0.14, 0.08, 26), gold)

func add_wall_dressing(plank: Material, ink: Material, gold: Material, cinnabar: Material) -> void:
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var z := side * 20.75
		add_mesh(Vector3(0, 0.32, z), Vector3(53.4, 0.5, 0.58), ink)
		add_mesh(Vector3(0, 3.72, z), Vector3(54.4, 0.28, 0.72), plank)
		add_mesh(Vector3(0, 3.9, z), Vector3(54.6, 0.08, 0.8), gold)
	for side in sides:
		var x := side * 26.75
		add_mesh(Vector3(x, 0.32, 0), Vector3(0.58, 0.5, 40.8), ink)
		add_mesh(Vector3(x, 3.72, 0), Vector3(0.72, 0.28, 41.6), plank)
		add_mesh(Vector3(x, 3.9, 0), Vector3(0.8, 0.08, 41.8), gold)
	var corner_x: Array[float] = [-26.3, 26.3]
	var corner_z: Array[float] = [-20.3, 20.3]
	for x in corner_x:
		for z in corner_z:
			add_mesh(Vector3(x, 2.3, z), Vector3(0.7, 0.7, 0.7), cinnabar)
			add_mesh(Vector3(x, 4.35, z), Vector3(0.9, 0.7, 0.9), plank)

func add_roof(roof: Material, gold: Material, cinnabar: Material) -> void:
	add_mesh(Vector3(0, 4.15, -19.8), Vector3(56.4, 0.16, 3.6), roof, Vector3(16, 0, 0))
	add_mesh(Vector3(0, 4.15, 19.8), Vector3(56.4, 0.16, 3.6), roof, Vector3(-16, 0, 0))
	add_mesh(Vector3(-25.6, 4.15, 0), Vector3(3.6, 0.16, 37.2), roof, Vector3(0, 0, 16))
	add_mesh(Vector3(25.6, 4.15, 0), Vector3(3.6, 0.16, 37.2), roof, Vector3(0, 0, -16))
	add_mesh(Vector3(0, 4.32, -18.15), Vector3(55.2, 0.08, 0.18), gold)
	add_mesh(Vector3(0, 4.32, 18.15), Vector3(55.2, 0.08, 0.18), gold)
	add_mesh(Vector3(-23.95, 4.32, 0), Vector3(0.18, 0.08, 35.6), gold)
	add_mesh(Vector3(23.95, 4.32, 0), Vector3(0.18, 0.08, 35.6), gold)
	var finial_x: Array[float] = [-26.2, 26.2]
	var finial_z: Array[float] = [-20.2, 20.2]
	for x in finial_x:
		for z in finial_z:
			add_mesh(Vector3(x, 4.7, z), Vector3(0.55, 0.28, 0.55), cinnabar)

func add_pillars(pillar_red: Material, gold: Material) -> void:
	var spots: Array[Vector3] = []
	var pillar_x: Array[float] = [-15.0, -7.5, 0.0, 7.5, 15.0]
	var pillar_z: Array[float] = [-11.0, 11.0]
	for px in pillar_x:
		for pz in pillar_z:
			spots.append(Vector3(px, 0, pz))
	for spot in spots:
		add_pillar(spot, pillar_red, gold)
	add_mesh(Vector3(0, 3.48, -11.0), Vector3(30.4, 0.22, 0.34), pillar_red)
	add_mesh(Vector3(0, 3.48, 11.0), Vector3(30.4, 0.22, 0.34), pillar_red)
	add_mesh(Vector3(-15.0, 3.48, 0), Vector3(0.34, 0.22, 22.4), pillar_red)
	add_mesh(Vector3(15.0, 3.48, 0), Vector3(0.34, 0.22, 22.4), pillar_red)

func add_pillar(at: Vector3, wood: Material, gold: Material) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, 1.7, at.z)
	add_child(body)
	var mesh_node := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.28
	cyl.height = 3.4
	cyl.radial_segments = 12
	mesh_node.mesh = cyl
	mesh_node.material_override = wood
	body.add_child(mesh_node)
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.28
	shape.height = 3.4
	shape_node.shape = shape
	body.add_child(shape_node)
	add_mesh(Vector3(at.x, 0.12, at.z), Vector3(0.78, 0.24, 0.78), gold)
	add_mesh(Vector3(at.x, 3.42, at.z), Vector3(0.7, 0.16, 0.7), gold)

func add_moon(cinnabar: Material, gold: Material, ink: Material) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.05
	cyl.height = 0.06
	disc.mesh = cyl
	disc.material_override = ink
	disc.position = Vector3(0, 1.9, -20.4)
	disc.rotation_degrees.x = 90
	add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.08
	torus.outer_radius = 1.28
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = cinnabar
	ring.position = Vector3(0, 1.9, -20.32)
	ring.rotation_degrees.x = 90
	add_child(ring)
	add_mesh(Vector3(-2.4, 1.15, -19.7), Vector3(0.7, 1.5, 0.7), cinnabar)
	add_mesh(Vector3(2.4, 1.15, -19.7), Vector3(0.7, 1.5, 0.7), cinnabar)
	add_mesh(Vector3(-2.4, 2.05, -19.7), Vector3(0.85, 0.28, 0.85), gold)
	add_mesh(Vector3(2.4, 2.05, -19.7), Vector3(0.85, 0.28, 0.85), gold)

func add_lattices(ink: Material) -> void:
	var lattice_z: Array[float] = [-12.0, 0.0, 12.0]
	for lz in lattice_z:
		add_lattice(Vector3(-26.4, 2.05, lz), 90.0, ink)
		add_lattice(Vector3(26.4, 2.05, lz), -90.0, ink)

func add_lattice(origin: Vector3, yaw: float, ink: Material) -> void:
	var root := Node3D.new()
	root.position = origin
	root.rotation_degrees.y = yaw
	add_child(root)
	for row in 5:
		add_mesh_on(root, Vector3(0, float(row) * 0.38 - 0.76, 0), Vector3(1.7, 0.05, 0.05), ink)
	for column in 5:
		add_mesh_on(root, Vector3(float(column) * 0.38 - 0.76, 0, 0), Vector3(0.05, 1.7, 0.05), ink)

func add_benches(plank: Material, ink: Material) -> void:
	var south: Array[float] = [-18.0, -9.0, 0.0, 9.0, 18.0]
	for x in south:
		add_bench(Vector3(x, 0, 16.6), plank, ink)
	var north: Array[float] = [-18.0, -9.0, 9.0, 18.0]
	for x in north:
		add_bench(Vector3(x, 0, -16.6), plank, ink)

func add_bench(at: Vector3, plank: Material, ink: Material) -> void:
	add_static_box(Vector3(at.x, 0.42, at.z), Vector3(1.8, 0.12, 0.55), plank)
	add_mesh(Vector3(at.x - 0.7, 0.2, at.z), Vector3(0.1, 0.4, 0.4), ink)
	add_mesh(Vector3(at.x + 0.7, 0.2, at.z), Vector3(0.1, 0.4, 0.4), ink)

func add_banners(cinnabar: Material, gold: Material, plank: Material) -> void:
	var banner_x: Array[float] = [-12.0, 12.0]
	var banner_z: Array[float] = [-5.0, 5.0]
	for x in banner_x:
		for z in banner_z:
			add_mesh(Vector3(x, 1.35, z), Vector3(0.08, 2.7, 0.08), plank)
			add_mesh(Vector3(x, 2.55, z), Vector3(0.22, 0.22, 0.22), gold)
			var flip := 0.34 if x > 0.0 else -0.34
			add_mesh(Vector3(x + flip, 1.85, z), Vector3(0.62, 1.15, 0.04), cinnabar)

func add_lantern(at: Vector3, gold: Material, glow: Material) -> void:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	lanterns.append(root)
	add_mesh_on(root, Vector3(0, 0.7, 0), Vector3(0.03, 0.9, 0.03), gold)
	add_mesh_on(root, Vector3(0, 0.24, 0), Vector3(0.36, 0.08, 0.36), gold)
	add_mesh_on(root, Vector3(0, 0, 0), Vector3(0.28, 0.38, 0.28), glow)
	add_mesh_on(root, Vector3(0, -0.24, 0), Vector3(0.32, 0.08, 0.32), gold)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 0.8
	light.omni_range = 11.0
	light.shadow_enabled = false
	root.add_child(light)

func add_sign(text: String, at: Vector3, yaw: float, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.012
	label.modulate = Color(0.55, 0.08, 0.06)
	label.outline_modulate = Color(0.96, 0.88, 0.62)
	label.outline_size = 10
	label.position = at
	label.rotation_degrees.y = yaw
	add_child(label)

func add_carpet(cinnabar: Material, gold: Material) -> void:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.4
	cyl.bottom_radius = 3.4
	cyl.height = 0.02
	disc.mesh = cyl
	disc.material_override = cinnabar
	disc.position = Vector3(0, 0.06, 0)
	add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.5
	torus.outer_radius = 3.78
	torus.rings = 28
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = gold
	ring.position = Vector3(0, 0.07, 0)
	add_child(ring)

func add_static_box(at: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	add_child(body)
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = mat
	body.add_child(mesh_node)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)

func add_mesh(at: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	add_mesh_on(self, at, size, mat, rot)

func add_mesh_on(parent: Node3D, at: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = mat
	mesh_node.position = at
	mesh_node.rotation_degrees = rot
	parent.add_child(mesh_node)

func textured(diff_path: String, nor_path: String, tint: Color, scale: Vector3, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(diff_path)
	mat.albedo_color = tint
	mat.roughness = roughness
	mat.normal_enabled = true
	mat.normal_texture = load(nor_path)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = scale
	return mat

func flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func glow_mat(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat

func set_solid(enabled: bool) -> void:
	set_solid_tree(self, enabled)

func set_solid_tree(node: Node, enabled: bool) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 1 if enabled else 0
		body.collision_mask = 1 if enabled else 0
	for child in node.get_children():
		set_solid_tree(child, enabled)

func hide_office() -> void:
	collision_backup.clear()
	var root := get_parent()
	for node_name in OFFICE_NODES:
		var node := root.get_node_or_null(node_name)
		if node == null:
			continue
		node.visible = false
		mute_collision(node)

func mute_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		collision_backup.append({
			"id": body.get_instance_id(),
			"layer": body.collision_layer,
			"mask": body.collision_mask,
		})
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		mute_collision(child)

func restore_office() -> void:
	var root := get_parent()
	for node_name in OFFICE_NODES:
		var node := root.get_node_or_null(node_name)
		if node:
			node.visible = true
	for item in collision_backup:
		var body := instance_from_id(int(item["id"])) as CollisionObject3D
		if body:
			body.collision_layer = int(item["layer"])
			body.collision_mask = int(item["mask"])
	collision_backup.clear()

func warm_light(on: bool) -> void:
	var root := get_parent()
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	var world := root.get_node_or_null("Environment") as WorldEnvironment
	if on:
		if light_saved:
			return
		if sun:
			saved_sun_color = sun.light_color
			saved_sun_energy = sun.light_energy
			sun.light_color = Color(1.0, 0.86, 0.68)
			sun.light_energy = 1.2
		if world and world.environment:
			saved_bg = world.environment.background_color
			saved_ambient = world.environment.ambient_light_color
			saved_ambient_energy = world.environment.ambient_light_energy
			world.environment.background_color = Color(0.55, 0.68, 0.82)
			world.environment.ambient_light_color = Color(1.0, 0.9, 0.76)
			world.environment.ambient_light_energy = 0.38
		light_saved = true
		return
	if not light_saved:
		return
	if sun:
		sun.light_color = saved_sun_color
		sun.light_energy = saved_sun_energy
	if world and world.environment:
		world.environment.background_color = saved_bg
		world.environment.ambient_light_color = saved_ambient
		world.environment.ambient_light_energy = saved_ambient_energy
	light_saved = false
