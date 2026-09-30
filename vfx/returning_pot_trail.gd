extends Node3D

const RUNE_TEXTURE = preload("res://assets/vfx/pot_talisman.svg")
const GOLD := Color(1.0, 0.68, 0.22)
const CYAN := Color(0.32, 0.9, 1.0)

var outer := MeshInstance3D.new()
var core := MeshInstance3D.new()
var runes := GPUParticles3D.new()
var points: Array[Vector3] = []
var point_ages: Array[float] = []
var returning := false
var recalled := false
var finished := false

func start(at: Vector3) -> void:
	global_transform = Transform3D.IDENTITY
	_setup_strip(outer, 0.5)
	_setup_strip(core, 1.0)
	_setup_runes(at)
	points.push_back(at)
	point_ages.push_back(0.0)

func _setup_strip(strip: MeshInstance3D, opacity: float) -> void:
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, opacity)
	strip.material_override = material
	add_child(strip)

func _setup_runes(at: Vector3) -> void:
	runes.emitting = false
	runes.amount = 18
	runes.lifetime = 0.58
	runes.local_coords = false
	runes.visibility_aabb = AABB(Vector3(-4, -3, -4), Vector3(8, 6, 8))
	runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.16
	process.direction = Vector3.UP
	process.spread = 80.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 1.25
	process.gravity = Vector3(0, -0.9, 0)
	process.damping_min = 0.5
	process.damping_max = 1.2
	process.scale_min = 0.55
	process.scale_max = 1.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	gradient.colors = PackedColorArray([Color(0.85, 1.0, 1.0, 0.0), Color(0.55, 0.95, 1.0, 0.9), Color(0.1, 0.65, 1.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	runes.process_material = process
	var card := QuadMesh.new()
	card.size = Vector2(0.22, 0.33)
	runes.draw_pass_1 = card
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = RUNE_TEXTURE
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(0.2, 0.85, 1.0)
	material.emission_energy_multiplier = 1.4
	runes.material_override = material
	add_child(runes)
	runes.global_position = at
	runes.emitting = true

func update_pot(at: Vector3, is_returning: bool, is_recalled: bool, delta: float) -> void:
	if finished:
		return
	if is_returning != returning or is_recalled != recalled:
		returning = is_returning
		recalled = is_recalled
		if returning:
			_pulse(at)
	runes.global_position = at
	for index in point_ages.size():
		point_ages[index] += delta
	if not points.is_empty() and points[0].distance_to(at) > 2.0:
		points.clear()
		point_ages.clear()
	if points.is_empty() or points[0].distance_to(at) >= 0.12:
		points.push_front(at)
		point_ages.push_front(0.0)
	else:
		points[0] = at
		point_ages[0] = 0.0
	var trail_life := 0.29 if recalled else 0.22
	while not point_ages.is_empty() and (point_ages[-1] > trail_life or points.size() > 24):
		points.pop_back()
		point_ages.pop_back()
	_rebuild_strip(outer, 0.27, GOLD if not returning else CYAN, trail_life)
	_rebuild_strip(core, 0.055, Color(1.0, 0.91, 0.68) if not returning else Color(0.82, 1.0, 1.0), trail_life)

func _rebuild_strip(strip: MeshInstance3D, width: float, tint: Color, trail_life: float) -> void:
	if points.size() < 2:
		strip.visible = false
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in points.size():
		var next := points[mini(index + 1, points.size() - 1)]
		var tangent := points[maxi(index - 1, 0)] - next
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var fade := pow(1.0 - clampf(point_ages[index] / trail_life, 0.0, 1.0), 1.35)
		var half_width := width * (0.25 + fade * 0.75)
		var color := Color(tint.r, tint.g, tint.b, fade)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(to_local(points[index] + side * half_width))
		mesh.surface_add_vertex(to_local(points[index] - side * half_width))
	mesh.surface_end()
	strip.mesh = mesh
	strip.visible = true

func _pulse(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var shape := TorusMesh.new()
	shape.inner_radius = 0.45
	shape.outer_radius = 0.49
	ring.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(0.55, 0.95, 1.0, 0.9)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 2.1, 0.2)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(ring.queue_free)

func finish() -> void:
	if finished:
		return
	finished = true
	runes.emitting = false
	var fade := create_tween().set_parallel(true)
	fade.tween_property(outer.material_override, "albedo_color:a", 0.0, 0.2)
	fade.tween_property(core.material_override, "albedo_color:a", 0.0, 0.2)
	var self_ref: WeakRef = weakref(self)
	get_tree().create_timer(runes.lifetime + 0.2).timeout.connect(func() -> void:
		var visual: Node = self_ref.get_ref() as Node
		if visual != null:
			visual.queue_free()
	)
