extends Node3D

## Inspector switch: show the actual cards, their numbers and the supporting parts.
@export var BILLBOARD_DEBUG := false:
	set(value):
		BILLBOARD_DEBUG = value
		if is_node_ready():
			$DebugRoot.visible = value

const SPARK_TEXTURE := preload("res://assets/vfx/spark.png")
const LAYERS := [
	{"node": "BillboardFire_A", "offset": Vector3(0.0, 0.78, 0.01), "size": Vector2(0.83, 1.0), "alpha": 0.94, "speed": 3.1, "phase": 0.0},
	{"node": "BillboardFire_B", "offset": Vector3(-0.34, 0.53, 0.16), "size": Vector2(0.58, 0.72), "alpha": 0.83, "speed": 3.9, "phase": 1.1},
	{"node": "BillboardFire_C", "offset": Vector3(0.32, 0.57, -0.13), "size": Vector2(0.62, 0.76), "alpha": 0.78, "speed": 2.7, "phase": 2.5},
	{"node": "BillboardFire_D", "offset": Vector3(-0.05, 0.53, -0.27), "size": Vector2(0.57, 0.68), "alpha": 0.67, "speed": 3.5, "phase": 4.2},
	{"node": "BillboardFire_E", "offset": Vector3(0.13, 0.99, 0.21), "size": Vector2(0.44, 0.94), "alpha": 0.68, "speed": 4.3, "phase": 3.3},
]

var elapsed := 0.0
var debug_cards: Array[Sprite3D] = []
var debug_labels: Array[Label3D] = []

func _ready() -> void:
	_setup_cards()
	_setup_sparks()
	_setup_debug()
	$DebugRoot.visible = BILLBOARD_DEBUG
	_animate()

func _process(delta: float) -> void:
	elapsed += delta
	_animate()

func _setup_cards() -> void:
	for layer in LAYERS:
		var card: Sprite3D = get_node(layer["node"])
		card.transparent = true
		card.shaded = false
		card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		card.no_depth_test = false
		card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _setup_sparks() -> void:
	var sparks: GPUParticles3D = $Sparks
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(0.29, 0.025, 0.21)
	motion.direction = Vector3.UP
	motion.spread = 17.0
	motion.initial_velocity_min = 0.55
	motion.initial_velocity_max = 1.05
	motion.gravity = Vector3(0, 0, 0)
	motion.damping_min = 0.3
	motion.damping_max = 0.7
	motion.scale_min = 0.5
	motion.scale_max = 0.9
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 0.7, 0.3, 0.0),
		Color(1, 0.75, 0.35, 0.75),
		Color(1, 0.41, 0.1, 0.38),
		Color(1, 0.25, 0.07, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	sparks.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2(0.095, 0.095)
	sparks.draw_pass_1 = quad
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	particle_material.no_depth_test = false
	particle_material.albedo_texture = SPARK_TEXTURE
	particle_material.vertex_color_use_as_albedo = true
	sparks.material_override = particle_material
	sparks.emitting = true

func _animate() -> void:
	for index in LAYERS.size():
		var layer: Dictionary = LAYERS[index]
		var card: Sprite3D = get_node(layer["node"])
		var wave: float = elapsed * layer["speed"] + layer["phase"]
		var base: Vector3 = layer["offset"]
		card.position = base + Vector3(sin(wave * 0.74) * 0.045, sin(wave) * 0.038, 0)
		var base_size: Vector2 = layer["size"]
		card.scale = Vector3(base_size.x * (1.0 + sin(wave * 0.91) * 0.055), base_size.y * (1.0 + sin(wave + 0.6) * 0.045), 1)
		card.rotation.z = sin(wave * 0.62) * 0.055
		card.modulate = Color(1, 1, 1, layer["alpha"] * (0.89 + 0.11 * sin(wave * 1.2)))
		if index < debug_cards.size():
			debug_cards[index].position = card.position
			debug_cards[index].scale = card.scale
			debug_cards[index].rotation.z = card.rotation.z
			debug_labels[index].position = card.position + Vector3(0, 0.76 * card.scale.y, 0)
	var light: OmniLight3D = $PointLight3D
	light.light_energy = 0.64 + 0.055 * sin(elapsed * 6.3) + 0.025 * sin(elapsed * 10.7 + 1.2)

func _setup_debug() -> void:
	var root: Node3D = $DebugRoot
	var border_image := Image.create(160, 224, false, Image.FORMAT_RGBA8)
	border_image.fill(Color.TRANSPARENT)
	for x in 160:
		for y in 224:
			if x < 3 or x >= 157 or y < 3 or y >= 221:
				border_image.set_pixel(x, y, Color(0.2, 1.0, 0.85, 0.9))
	var border_texture := ImageTexture.create_from_image(border_image)
	for index in LAYERS.size():
		var border := Sprite3D.new()
		border.name = "CardBoundary_%d" % (index + 1)
		border.texture = border_texture
		border.pixel_size = 0.007
		border.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		border.shaded = false
		border.no_depth_test = false
		border.double_sided = true
		root.add_child(border)
		debug_cards.append(border)
		var label := _debug_label(str(index + 1), Vector3.ZERO)
		root.add_child(label)
		debug_labels.append(label)
		root.add_child(_debug_label("%d  %s" % [index + 1, LAYERS[index]["node"]], Vector3(1.42, 1.65 - index * 0.18, 0)))
	_debug_line_box(root, Vector2(1.25, 1.05), 0.045, Color(0.4, 0.95, 0.28))
	root.add_child(_debug_label("GroundFire  |  PlaneMesh + Shader", Vector3(0, 0.07, 0.79)))
	root.add_child(_debug_label("Sparks  |  GPUParticles3D", Vector3(0, 0.25, 0.55)))
	root.add_child(_debug_label("PointLight3D  |  OmniLight3D, range 2.8 m", Vector3(0, 1.78, 0)))
	_debug_light_ring(root)

func _debug_label(value: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.pixel_size = 0.002
	label.font_size = 20
	label.outline_size = 3
	label.modulate = Color(0.65, 1.0, 0.87)
	return label

func _debug_line_box(root: Node3D, size: Vector2, height: float, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := size * 0.5
	var corners := [Vector3(-half.x, height, -half.y), Vector3(half.x, height, -half.y), Vector3(half.x, height, half.y), Vector3(-half.x, height, half.y)]
	for i in 4:
		mesh.surface_add_vertex(corners[i])
		mesh.surface_add_vertex(corners[(i + 1) % 4])
	mesh.surface_end()
	_add_debug_mesh(root, mesh, "GroundBoundary", color)

func _debug_light_ring(root: Node3D) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 48:
		var a := TAU * float(i) / 48.0
		var b := TAU * float(i + 1) / 48.0
		mesh.surface_add_vertex(Vector3(cos(a) * 2.8, 0.06, sin(a) * 2.8))
		mesh.surface_add_vertex(Vector3(cos(b) * 2.8, 0.06, sin(b) * 2.8))
	mesh.surface_end()
	_add_debug_mesh(root, mesh, "LightRange", Color(1, 0.63, 0.32))

func _add_debug_mesh(root: Node3D, mesh: Mesh, label: String, color: Color) -> void:
	var lines := MeshInstance3D.new()
	lines.name = label
	lines.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = color
	lines.material_override = material
	root.add_child(lines)
