extends Node3D
## Pave only InnerCourt (74 x 56 m). Preserve the complete existing arena insert.
const KIT_DIR := "res://assets/environment/kits/"
const FLOOR_Y := 0.045
# GLB 里的高光是 0.32。Compatibility 渲染下太阳会在大片平地打出白斑，铺进场里时压低。
const PAVER_SPECULAR := 0.08
var placements: Dictionary = {}

func _ready() -> void:
	name = "CourtyardPaving"
	build_layout()
	for kit in placements:
		var packed := load(KIT_DIR + str(kit) + ".glb") as PackedScene
		if packed == null:
			push_error("Missing courtyard paver: " + str(kit))
			continue
		var sample := packed.instantiate()
		_batch_meshes(sample, Transform3D.IDENTITY, placements[kit], str(kit))
		sample.free()

func build_layout() -> void:
	placements.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 74156
	# L notch points into the courtyard; the missing quarter is filled below.
	_add("paving_corner", -36, 27, 0)
	_add("paving_corner", 36, 27, PI * 0.5)
	_add("paving_corner", 36, -27, PI)
	_add("paving_corner", -36, -27, -PI * 0.5)
	# 70 m between the corner arms, using 2 x 1 m long pavers.
	for x in range(-34, 35, 2):
		_add("paving_rect", x, -27.5, 0)
		_add("paving_rect", x, 27.5, PI)
	for z in range(-25, 26, 2):
		_add("paving_rect", -36.5, z, PI * 0.5)
		_add("paving_rect", 36.5, z, -PI * 0.5)
	for x in range(-36, 36):
		for z in range(-27, 27):
			if arena_cell(x, z):
				continue
			var kit := "paving_square" if rng.randf() < 0.58 else "paving_square_crack"
			_add(kit, float(x) + 0.5, float(z) + 0.5, float(rng.randi_range(0, 3)) * PI * 0.5)

static func arena_cell(x: int, z: int) -> bool:
	# Same cell envelope as arena_notch_ring + the existing outer square tiles.
	# Keeping entire cells avoids both seams and coplanar overlapping surfaces.
	for dx in [0, 1]:
		for dz in [0, 1]:
			if Vector2(x + dx, z + dz).length() > 9.65:
				return false
	return true

func _add(kit: String, x: float, z: float, yaw: float) -> void:
	if not placements.has(kit):
		placements[kit] = []
	placements[kit].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, FLOOR_Y, z)))

func _batch_meshes(node: Node, parent_transform: Transform3D, instances: Array, kit: String) -> void:
	var local := parent_transform
	if node is Node3D:
		local = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		# Keep the imported mesh/material/UVs; batch thousands of bricks in four groups.
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = _dull_paver_mesh(node.mesh)
		batch.instance_count = instances.size()
		for index in instances.size():
			batch.set_instance_transform(index, instances[index] * local)
		var visual := MultiMeshInstance3D.new()
		visual.name = kit
		visual.multimesh = batch
		visual.material_override = node.material_override
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	for child in node.get_children():
		_batch_meshes(child, local, instances, kit)

func _dull_paver_mesh(mesh: Mesh) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for surface in copy.get_surface_count():
		var source: Material = copy.surface_get_material(surface)
		if source is StandardMaterial3D:
			var stone := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			stone.metallic_specular = PAVER_SPECULAR
			copy.surface_set_material(surface, stone)
	return copy
