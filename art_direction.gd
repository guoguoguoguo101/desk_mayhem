@tool
extends Node3D

const INK := Color("263c50")
const TEAL := Color("397c80")
const CREAM := Color("e9dfcb")
const CORAL := Color("dc795d")
static var rounded_cache: Dictionary = {}

static func rounded_box(size: Vector3) -> ArrayMesh:
	if rounded_cache.has(size):
		return rounded_cache[size]
	var bevel := minf(0.09, minf(size.x, minf(size.y, size.z)) * 0.28)
	var inner := size * 0.5 - Vector3.ONE * bevel
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var u: Vector3 = Vector3.UP if absf(normal.y) < 0.5 else Vector3.RIGHT
		var v: Vector3 = normal.cross(u)
		for x in 6:
			for y in 6:
				for offset in [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)]:
					var p: Vector3 = (normal * 0.5 + u * ((x + offset.x) / 6.0 - 0.5) + v * ((y + offset.y) / 6.0 - 0.5)) * size
					var center := p.clamp(-inner, inner)
					var n := (p - center).normalized()
					surface.set_normal(n)
					surface.add_vertex(center + n * bevel)
	var mesh := surface.commit()
	mesh.surface_set_material(0, material(Color.WHITE))
	rounded_cache[size] = mesh
	return mesh

static func material(color: Color, roughness := 0.75) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

static func paint(node: MeshInstance3D, color: Color) -> void:
	node.material_override = material(color)

static func ellipsoid(node: MeshInstance3D, size: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 32
	mesh.rings = 16
	node.mesh = mesh
	node.scale = size
	paint(node, color)

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = rounded_box(size)
	paint(node, color)
	parent.add_child(node)
	node.position = at
	return node

static func ball(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	ellipsoid(node, size, color)
	parent.add_child(node)
	node.position = at
	return node

static func dress_player(visual: Node3D) -> void:
	var canopy: MeshInstance3D = visual.get_node("Umbrella/UmbrellaCanopy")
	var canopy_mat := ShaderMaterial.new()
	var canopy_shader := Shader.new()
	canopy_shader.code = "shader_type spatial; render_mode cull_disabled; uniform vec4 a:source_color=vec4(0.16,0.48,0.5,1); uniform vec4 b:source_color=vec4(0.95,0.84,0.61,1); varying vec3 p; void vertex(){p=VERTEX;} void fragment(){float stripe=step(0.5,fract((atan(p.z,p.x)+3.14159)/6.28318*6.0)); ALBEDO=mix(a.rgb,b.rgb,stripe); ROUGHNESS=0.65;}"
	canopy_mat.shader = canopy_shader
	canopy.material_override = canopy_mat
	ellipsoid(visual.get_node("Body"), Vector3(0.88, 0.94, 0.69), TEAL)
	ellipsoid(visual.get_node("Head"), Vector3(0.98, 0.86, 0.82), Color("dba569"))
	ellipsoid(visual.get_node("Muzzle"), Vector3(0.62, 0.36, 0.37), Color("fff0d6"))
	ellipsoid(visual.get_node("Nose"), Vector3(0.18, 0.13, 0.13), INK)
	for side in ["L", "R"]:
		ellipsoid(visual.get_node("Ear" + side), Vector3(0.25, 0.39, 0.22), Color("a96641"))
		ellipsoid(visual.get_node("Arm" + side), Vector3(0.26, 0.43, 0.29), Color("e2b37c"))
		ellipsoid(visual.get_node("Foot" + side), Vector3(0.3, 0.28, 0.42), INK)
		paint(visual.get_node("Eye" + side), INK)
	paint(visual.get_node("Collar"), CREAM)
	paint(visual.get_node("Badge"), Color("f5b951"))
	if visual.has_node("TailoredDetails"):
		return
	var details := Node3D.new()
	details.name = "TailoredDetails"
	visual.add_child(details)
	for x in [-0.2, 0.2]:
		ball(details, Vector3(x, 0.64, -0.517), Vector3(0.043, 0.043, 0.025), Color.WHITE)
		ball(details, Vector3(x * 1.6, 0.35, -0.44), Vector3(0.12, 0.055, 0.027), CORAL)
	box(details, Vector3(0, -0.06, -0.355), Vector3(0.065, 0.32, 0.045), CORAL).rotation.z = -0.12
	box(details, Vector3(0.19, -0.15, -0.51), Vector3(0.09, 0.12, 0.02), CREAM)
	box(details, Vector3(0.19, -0.18, -0.53), Vector3(0.06, 0.015, 0.01), INK)
	for x in [-0.21, 0.21]:
		ball(details, Vector3(x, 0.75, -0.41), Vector3(0.16, 0.045, 0.04), Color("855738"))

static func dress_dummy(visual: Node3D) -> void:
	ellipsoid(visual.get_node("Body"), Vector3(0.66, 0.8, 0.47), CORAL)
	ellipsoid(visual.get_node("Head"), Vector3(0.7, 0.62, 0.63), CREAM)
	ellipsoid(visual.get_node("Crossbar"), Vector3(1.22, 0.22, 0.24), INK)
	paint(visual.get_node("Post"), INK)
	paint(visual.get_node("Base"), TEAL)
	if visual.has_node("TargetDetails"):
		return
	var details := Node3D.new()
	details.name = "TargetDetails"
	visual.add_child(details)
	for x in [-0.13, 0.13]:
		ball(details, Vector3(x, 1.58, -0.3), Vector3(0.08, 0.075, 0.035), INK)
	for radius in [0.21, 0.12]:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius - 0.025
		mesh.outer_radius = radius
		ring.mesh = mesh
		paint(ring, CREAM)
		details.add_child(ring)
		ring.position = Vector3(0, 0.95, -0.24)
		ring.rotation.x = PI / 2

func _ready() -> void:
	call_deferred("build")

func build() -> void:
	var root := get_parent()
	if root == null or not root.has_node("Architecture"):
		return
	var env: Environment = root.get_node("Environment").environment
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.65
	env.background_color = Color("91b3bf")
	env.ambient_light_color = Color("c5d9e6")
	env.ambient_light_energy = 0.22
	var sun: DirectionalLight3D = root.get_node("Sun")
	sun.light_energy = 0.55
	sun.light_color = Color("fff0d8")
	sun.directional_shadow_max_distance = 75.0
	for section in ["Architecture", "Furniture", "MeetingArea", "BreakArea", "ArenaCover"]:
		for item in root.get_node(section).find_children("*", "MeshInstance3D", true, false):
			var name_string: String = item.name
			var color := CREAM
			if "FloorLine" in name_string:
				color = Color("b4c6c6")
				item.visible = false
			elif name_string == "Floor":
				color = Color("8eaaad")
			elif "Wall" in name_string or "Divider" in name_string:
				color = TEAL
			elif "Monitor" in name_string:
				color = INK
			elif "Leg" in name_string or "Stem" in name_string or "Base" in name_string:
				color = INK
			elif "Chair" in name_string or "Stool" in name_string:
				color = CORAL
			elif "Rug" in name_string:
				color = Color("497d82")
			elif "Plant" in name_string:
				color = Color("4d8d71") if not "Planter" in name_string else CREAM
			elif "Crate" in name_string:
				color = Color("c59160")
			elif "CoffeeCounter" in name_string or "Cabinet" in name_string:
				color = TEAL
			paint(item, color)
			if item.mesh is BoxMesh and not "Floor" in name_string and not "Wall" in name_string:
				item.mesh = rounded_box(item.mesh.size)
	var floor_material := ShaderMaterial.new()
	var floor_shader := Shader.new()
	floor_shader.code = "shader_type spatial; render_mode ambient_light_disabled, specular_disabled; uniform float grid_strength=0.5; uniform vec4 base:source_color=vec4(0.42,0.55,0.57,1.0); varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){vec2 g=abs(fract(wp.xz/2.0-0.5)-0.5)/max(fwidth(wp.xz/2.0),vec2(0.0001)); float line=1.0-min(min(g.x,g.y),1.0); ALBEDO=mix(base.rgb,base.rgb*0.85,line*grid_strength); ROUGHNESS=1.0;} void light(){DIFFUSE_LIGHT += ALBEDO * (vec3(0.6)+0.4*ATTENUATION);}"
	floor_material.shader = floor_shader
	root.get_node("Architecture/Floor").material_override = floor_material
	for node in root.get_children():
		if String(node.name).begins_with("TrainingDummy"):
			var label: Label3D = node.get_node("HitLabel")
			label.fixed_size = true
			label.pixel_size = 0.0015
			label.font_size = 22
			label.outline_size = 3
			label.modulate = Color("eaf3e6")
	var architecture: Node3D = root.get_node("Architecture")
	if architecture.has_node("StudioDecor"):
		return
	var decor := Node3D.new()
	decor.name = "StudioDecor"
	architecture.add_child(decor)
	for x in [5.0, 8.0]:
		box(decor, Vector3(x, 0.38, 2.2), Vector3(0.14, 0.75, 1.2), INK)
	for at in [Vector3(5.1, 0, 0.7), Vector3(7.8, 0, 0.7), Vector3(5.1, 0, 3.7), Vector3(7.8, 0, 3.7)]:
		box(decor, at + Vector3.UP * 0.2, Vector3(0.12, 0.4, 0.12), INK)
		box(decor, at + Vector3.UP * 0.07, Vector3(0.4, 0.08, 0.4), INK)
	# Thin floor inlays and graphics have no extra collision or camera obstruction.
	var carpet := box(decor, Vector3(0, 0.015, 1), Vector3(22, 0.012, 19), Color("b8b1a0"))
	carpet.material_override = floor_material.duplicate()
	carpet.material_override.set_shader_parameter("base", Color("b8b1a0"))
	carpet.material_override.set_shader_parameter("grid_strength", 0.0)
	var mat_zone := box(decor, Vector3(0, 0.028, 5), Vector3(9, 0.008, 7), Color("9c998b"))
	mat_zone.material_override = floor_material.duplicate()
	mat_zone.material_override.set_shader_parameter("base", Color("9c998b"))
	mat_zone.material_override.set_shader_parameter("grid_strength", 0.0)
	for x in [-11.2, 11.2]:
		box(decor, Vector3(x, 0.03, 1), Vector3(0.13, 0.015, 19), CORAL)
	for z in [-8.6, 10.6]:
		box(decor, Vector3(0, 0.03, z), Vector3(22.5, 0.015, 0.13), CORAL)
	for x in [-9.0, 9.0]:
		for z in [-7.0, 9.0]:
			plant(decor, Vector3(x, 0, z))
	for spec in [[Vector3(-29, 0, -19), "01  /  DESIGN", TEAL], [Vector3(29, 0, -19), "02  /  OPERATIONS", CORAL], [Vector3(-29, 0, 19), "03  /  LOUNGE", TEAL], [Vector3(29, 0, 19), "04  /  MEETING", CORAL]]:
		var at: Vector3 = spec[0]
		for dx in [-7.6, 7.6]:
			box(decor, at + Vector3(dx, 0.04, 0), Vector3(0.12, 0.01, 11), CREAM)
		floor_text(decor, at + Vector3(0, 0.06, 4.4), spec[1], 0.011)
		plant(decor, at + Vector3(-6, 0, -4))
		plant(decor, at + Vector3(6, 0, 4))
	floor_text(decor, Vector3(0, 0.05, 9.1), "DESK MAYHEM  /  TRAINING FLOOR", 0.007)
	# Put readable screen faces and stationery on the existing desks.
	for section in ["Furniture", "ArenaCover"]:
		for item in root.get_node(section).find_children("*", "MeshInstance3D", true, false):
			if "Monitor" in String(item.name) and not "Stem" in String(item.name):
				var screen := box(decor, Vector3.ZERO, Vector3(0.65, 0.38, 0.012), Color("63b4ba"))
				screen.global_position = item.global_position + Vector3(0, 0, 0.075)
				box(screen, Vector3(-0.12, 0.04, 0.011), Vector3(0.23, 0.04, 0.01), CREAM)
				box(screen, Vector3(-0.06, -0.05, 0.011), Vector3(0.35, 0.025, 0.01), CREAM)
	if Engine.is_editor_hint():
		dress_player(root.get_node("Player/Visual"))
		for node in root.get_children():
			if String(node.name).begins_with("TrainingDummy"):
				dress_dummy(node.get_node("Visual"))

func plant(parent: Node3D, at: Vector3) -> void:
	var pot := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.36
	mesh.bottom_radius = 0.27
	mesh.height = 0.6
	pot.mesh = mesh
	paint(pot, CREAM)
	parent.add_child(pot)
	pot.position = at + Vector3.UP * 0.3
	for i in 5:
		var angle := float(i) * TAU / 5
		var leaf := ball(parent, at + Vector3(cos(angle) * 0.18, 0.95, sin(angle) * 0.18), Vector3(0.27, 0.85, 0.19), Color("377e6c") if i % 2 else Color("73a078"))
		leaf.rotation.z = cos(angle) * 0.5
		leaf.rotation.x = sin(angle) * 0.5

func floor_text(parent: Node3D, at: Vector3, text: String, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel
	label.modulate = CREAM
	label.outline_size = 0
	parent.add_child(label)
	label.position = at
	label.rotation.x = -PI / 2
