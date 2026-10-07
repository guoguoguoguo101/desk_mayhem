extends Node3D
## Visual-only slit geometry and debris; never modifies combat or cameras.
const RIFT_SHADER = preload("res://vfx/mouse_cut_rift.gdshader")
const HALO_SHADER = preload("res://vfx/mouse_cut_rift_halo.gdshader")
const SPACE_TEXTURE = preload("res://assets/vfx/mouse_cut_space.png")
const BLADE_TEXTURE = preload("res://assets/vfx/mouse_cut_rift_blade.png")
const CRYSTAL_TEXTURE = preload("res://assets/vfx/mouse_cut_crystal_shard.png")
const ROCK_TEXTURE = preload("res://assets/vfx/mouse_cut_basalt.png")
const DETAIL_SHADER = preload("res://vfx/mouse_cut_rift_detail.gdshader")
const RING_SHADER = preload("res://vfx/mouse_cut_rift_ring.gdshader")
const GROW_SECONDS := 11.0 / 60.0
const END_SECONDS := GROW_SECONDS + 0.44

var age := 0.0
var confirmed := false
var peak_done := false
var materials: Array[ShaderMaterial] = []
var debris: Array[Dictionary] = []
var ring: MeshInstance3D
var flash: MeshInstance3D
var light: OmniLight3D
var ground_y := 0.0
var from := Vector3.ZERO
var to := Vector3.ZERO
var meshes: Array[MeshInstance3D] = []

func configure(a: Vector3, b: Vector3, initial_age := 0.0) -> void:
	from = a
	to = b
	age = initial_age
	var direction := b - a
	direction.y = 0.0
	if direction.length_squared() < 0.001: direction = Vector3.FORWARD
	direction = direction.normalized()
	# The X lies in the vertical plane parallel to the locked travel direction.
	global_position = b + Vector3.UP * 1.95
	ground_y = a.y
	var depth := direction.cross(Vector3.UP).normalized()
	for blade in 2:
		var axis := (direction + Vector3.UP * (1.0 if blade == 0 else -1.0)).normalized()
		var cross_axis := depth.cross(axis).normalized()
		_build_blade(axis, cross_axis, depth, blade)
	flash = _mesh(SphereMesh.new(), _glow(Color(0.65, 0.88, 1.0), 5.0))
	flash.scale = Vector3.ONE * 0.05
	flash.visible = false
	light = OmniLight3D.new()
	light.light_color = Color(0.15, 0.55, 1.0)
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)

func confirm_peak() -> void:
	if confirmed: return
	confirmed = true
	age = GROW_SECONDS
	_peak()

func _build_blade(axis: Vector3, cross_axis: Vector3, depth: Vector3, blade: int) -> void:
	var curve := Curve3D.new()
	curve.add_point(-axis * 2.65, Vector3.ZERO, axis * 1.75 + cross_axis * 0.15)
	curve.add_point(axis * 2.65, -axis * 1.75 + cross_axis * 0.1, Vector3.ZERO)
	var rings: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 823 + blade * 127
	for i in 49:
		var t := float(i) / 48.0
		var center := curve.sample(0, t) + depth * float(blade) * 0.055
		var width := pow(maxf(sin(PI * t), 0.0), 0.85) * (0.21 + rng.randf_range(-0.035, 0.035)) + 0.003
		var inset := width * 0.62
		# Outer edges, recessed dark floor and distinct narrow gold trim.
		rings.append([center - cross_axis * width, center - cross_axis * inset - depth * 0.12, center + cross_axis * inset - depth * 0.12, center + cross_axis * width, width])
	for kind in 4:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var a: Array = rings[i]
			var b: Array = rings[i + 1]
			var t0 := float(i) / 48.0
			var t1 := float(i + 1) / 48.0
			if kind == 0:
				_quad(vertices, normals, uvs, a[1], a[2], b[1], b[2], t0, t1)
			elif kind == 1:
				_quad(vertices, normals, uvs, a[0], a[1], b[0], b[1], t0, t1)
				_quad(vertices, normals, uvs, a[2], a[3], b[2], b[3], t0, t1)
			else:
				for edge in [0, 3]:
					var band := 0.06 if kind == 3 else 0.016
					_quad(vertices, normals, uvs, a[edge] - cross_axis * band, a[edge] + cross_axis * band, b[edge] - cross_axis * band, b[edge] + cross_axis * band, t0, t1)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := ShaderMaterial.new()
		material.shader = HALO_SHADER if kind == 3 else RIFT_SHADER
		if kind != 3:
			material.set_shader_parameter("space_texture", SPACE_TEXTURE)
			material.set_shader_parameter("surface_kind", float(kind))
		materials.append(material)
		_mesh(mesh, material)
	# Detailed art carries the torn facets, wisps and gold fragments, on both faces.
	for face in [-1.0, 1.0]:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var t0 := float(i) / 48.0
			var t1 := float(i + 1) / 48.0
			var a: Vector3 = curve.sample(0,t0) + depth * (float(blade)*0.055 + float(face) * 0.16)
			var b: Vector3 = curve.sample(0,t1) + depth * (float(blade)*0.055 + float(face) * 0.16)
			_quad(vertices,normals,uvs,a-cross_axis*0.85,a+cross_axis*0.85,b-cross_axis*0.85,b+cross_axis*0.85,t0,t1)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := ShaderMaterial.new()
		material.shader = DETAIL_SHADER
		material.set_shader_parameter("detail_texture", BLADE_TEXTURE)
		material.render_priority = 1
		materials.append(material)
		_mesh(mesh,material)

func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, t0: float, t1: float) -> void:
	var normal := (b-a).cross(c-a).normalized()
	for p in [a, b, c, b, d, c]: vertices.append(p); normals.append(normal)
	for uv in [Vector2(t0,0), Vector2(t0,1), Vector2(t1,0), Vector2(t0,1), Vector2(t1,1), Vector2(t1,0)]: uvs.append(uv)

func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	meshes.append(node)
	return node

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _peak() -> void:
	if peak_done: return
	peak_done = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 951
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.65, 0.7, 0.8)
	rock_material.albedo_texture = ROCK_TEXTURE
	rock_material.uv1_triplanar = true
	rock_material.uv1_scale = Vector3.ONE * 2.0
	rock_material.roughness = 0.92
	var crystal_material := StandardMaterial3D.new()
	crystal_material.albedo_color = Color(0.06,0.4,0.8)
	crystal_material.metallic = 0.55
	crystal_material.roughness = 0.12
	crystal_material.emission_enabled = true
	crystal_material.emission = Color(0.03,0.2,0.6)
	crystal_material.emission_energy_multiplier = 1.5
	for i in 34:
		var rock := i < 12
		var mesh := _shard_mesh(rock, i)
		var node := _mesh(mesh, rock_material if rock else crystal_material)
		var angle := rng.randf_range(0.0, TAU)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var size := rng.randf_range(0.16, 0.4) if rock else rng.randf_range(0.08, 0.23)
		node.scale = Vector3.ONE * size
		if not rock:
			var detail := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(2.0,3.0)
			detail.mesh = quad
			var material := _glow(Color(0.65,0.8,1.0),1.0)
			material.albedo_texture = CRYSTAL_TEXTURE
			material.emission_texture = CRYSTAL_TEXTURE
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.billboard_keep_scale = true
			detail.material_override = material
			detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(detail)
		node.global_position = global_position + radial * rng.randf_range(0.05, 0.65)
		var velocity := radial * rng.randf_range(2.0, 4.0) + Vector3.UP * rng.randf_range(2.2, 4.8)
		if rock:
			node.global_position.y = ground_y + rng.randf_range(0.15, 0.35)
			velocity.y = rng.randf_range(1.2, 2.3)
		if not rock:
			var direction := to-from
			direction.y = 0.0
			if direction.length_squared() < 0.001: direction = Vector3.FORWARD
			direction = direction.normalized()
			velocity = (direction * (-1.0 if i % 2 == 0 else 1.0) + Vector3.UP * (-0.7 if i % 4 < 2 else 0.7)).normalized() * rng.randf_range(5.0, 8.0)
		debris.append({"node":node,"velocity":velocity,"spin":Vector3(rng.randf(),rng.randf(),rng.randf())*12.0,"rock":rock,"bounce":false,"size":size})
	var plane := QuadMesh.new()
	plane.size = Vector2(2,2)
	var ring_material := ShaderMaterial.new()
	ring_material.shader = RING_SHADER
	ring = _mesh(plane,ring_material)
	ring.rotation.x = -PI * 0.5
	ring.global_position = Vector3(global_position.x, ground_y + 0.07, global_position.z)
	ring.scale = Vector3.ONE * 0.1

func _shard_mesh(rock: bool, seed_value: int) -> ArrayMesh:
	if rock: return _rock_mesh(seed_value)
	var points: Array[Vector3] = [Vector3(0,1.2,0),Vector3(0,-0.8,0),Vector3(-0.65,0,0),Vector3(0,0,0.6),Vector3(0.65,0,0),Vector3(0,0,-0.6)]
	if rock:
		for i in points.size(): points[i] *= 0.7 + float((i * 7 + seed_value * 3) % 11) * 0.06
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in [[0,2,3],[0,3,4],[0,4,5],[0,5,2],[1,3,2],[1,4,3],[1,5,4],[1,2,5]]:
		var normal := (points[face[1]]-points[face[0]]).cross(points[face[2]]-points[face[0]]).normalized()
		for index in face: vertices.append(points[index]); normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _rock_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 718 + seed_value * 31
	var points: Array[Vector3] = []
	for level in 4:
		for i in 7:
			var angle := TAU * float(i)/7.0 + float(level)*0.18
			var radius := rng.randf_range(0.45,0.9) * (0.65 if level in [0,3] else 1.0)
			points.append(Vector3(cos(angle)*radius,float(level)*0.5-0.75+rng.randf_range(-0.1,0.1),sin(angle)*radius))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for level in 3:
		for i in 7:
			var next := (i+1)%7
			_quad(vertices,normals,uvs,points[level*7+i],points[level*7+next],points[(level+1)*7+i],points[(level+1)*7+next],float(level)/3.0,float(level+1)/3.0)
	for top in [false,true]:
		var base := 21 if top else 0
		for i in range(1,6):
			var a: Vector3 = points[base]
			var b: Vector3 = points[base+i]
			var c: Vector3 = points[base+i+1]
			if not top:
				var temp := b; b = c; c = temp
			var normal := (b-a).cross(c-a).normalized()
			for p in [a,b,c]: vertices.append(p); normals.append(normal); uvs.append(Vector2(p.x,p.z))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _process(delta: float) -> void:
	age += delta
	if not confirmed:
		age = minf(age, GROW_SECONDS)
	var grow := smoothstep(0.0, GROW_SECONDS, age)
	var dissolve := smoothstep(GROW_SECONDS + 0.18, END_SECONDS, age)
	for material in materials:
		material.set_shader_parameter("grow_t", grow)
		material.set_shader_parameter("dissolve", dissolve)
		material.set_shader_parameter("age", age)
	var peak_age := age - GROW_SECONDS
	flash.visible = confirmed and peak_age < 0.06
	flash.scale = Vector3.ONE * (0.2 + maxf(0.0, 1.0 - peak_age / 0.06) * 0.35)
	light.light_energy = 3.0 * maxf(0.0, 1.0 - peak_age / 0.2) if confirmed else 0.0
	if ring != null:
		ring.scale = Vector3.ONE * lerpf(0.2, 3.0, clampf(peak_age / 0.3, 0.0, 1.0))
		ring.transparency = smoothstep(0.1, 0.34, peak_age)
		(ring.material_override as ShaderMaterial).set_shader_parameter("opacity",1.0-smoothstep(0.1,0.34,peak_age))
	for piece in debris:
		var node: MeshInstance3D = piece.node
		piece.velocity += Vector3.DOWN * (18.0 if piece.rock else 3.0) * delta
		node.global_position += Vector3(piece.velocity) * delta
		node.rotation += Vector3(piece.spin) * delta
		if node.global_position.y < ground_y + 0.08:
			node.global_position.y = ground_y + 0.08
			if piece.rock and not piece.bounce:
				piece.velocity.y = absf(piece.velocity.y) * 0.25
				piece.velocity.x *= 0.65
				piece.velocity.z *= 0.65
				piece.bounce = true
			else: piece.velocity = Vector3.ZERO
		node.transparency = smoothstep(0.24, 0.44, peak_age)
		for detail in node.get_children():
			if detail is GeometryInstance3D: detail.transparency = node.transparency
	if confirmed and age >= END_SECONDS:
		# Nodes own these ArrayMesh resources; release them with the whole effect.
		queue_free()
