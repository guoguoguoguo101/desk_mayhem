extends Node3D

const HIT_SOUND = preload("res://audio/hit.wav")
const HEAVY_SOUND = preload("res://audio/heavy_hit.wav")
const SWING_SOUND = preload("res://audio/swing.wav")

@onready var camera_rig: Node3D = get_node("../CameraRig")

func play_swing() -> void:
	play_sound(SWING_SOUND, -8.0)

func attack_arc(at: Vector3, forward: Vector3, reach: float, color: Color, vertical := false) -> void:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 25:
		var phase := float(i) / 24.0
		var angle := lerpf(-1.15, 1.15, phase)
		var width := sin(phase * PI) * 0.22
		for r in [reach - width, reach + width]:
			mesh.surface_add_vertex(Vector3(sin(angle) * r, 0, -cos(angle) * r))
	mesh.surface_end()
	slash.mesh = mesh
	var mat := effect_material(color, true)
	mesh.surface_set_material(0, mat)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	slash.material_override = mat
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slash)
	slash.global_position = at
	slash.rotation.y = atan2(-forward.x, -forward.z)
	if vertical:
		slash.rotate_object_local(Vector3.FORWARD, PI / 2)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(slash, "scale", Vector3.ONE * 1.18, 0.17)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(slash.queue_free)

func dash_start() -> void:
	play_swing()

func blink_effect(start: Vector3, finish: Vector3) -> void:
	play_sound(SWING_SOUND, -4.0)
	for point in [start, finish]:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.35
		mesh.outer_radius = 0.46
		ring.mesh = mesh
		ring.material_override = effect_material(Color("79d9ff"))
		add_child(ring)
		ring.global_position = point
		var tween := create_tween()
		tween.tween_property(ring, "scale", Vector3.ONE * 2.5, 0.2)
		tween.tween_callback(ring.queue_free)

func dash_trail(at: Vector3) -> void:
	var ghost := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.84
	ghost.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.87, 0.22, 0.25, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = material
	add_child(ghost)
	ghost.global_position = at
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ghost, "scale", Vector3.ZERO, 0.2)
	tween.tween_property(material, "albedo_color", Color(0.87, 0.22, 0.25, 0.0), 0.2)
	tween.chain().tween_callback(ghost.queue_free)

func impact(at: Vector3, heavy := false, combo := 0, popup := "") -> void:
	var power := (0.28 if heavy else 0.12) + minf(float(combo), 6.0) * 0.02
	camera_rig.add_shake(power)
	play_sound(HEAVY_SOUND if heavy else HIT_SOUND, 2.2 if heavy else -1.2)
	var color := Color("efaa62") if heavy else Color("fff1b8")
	burst_flash(at, 0.23 if heavy else 0.14, Color("fffaf0"))
	burst_ring(at, 0.32, 2.5 if heavy else 1.45, Color("fff6dc"))
	if heavy:
		burst_ring(at + Vector3.DOWN * 0.55, 0.42, 3.2, Color("ffd27a"))
	burst_slash(at, heavy)
	var sparks := 12 if heavy else 7
	for i in sparks:
		burst_spark(at, color, heavy)
	if popup != "":
		damage_popup(at, popup, heavy)

func burst_flash(at: Vector3, radius: float, color: Color) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	flash.mesh = mesh
	var material := effect_material(color, true)
	flash.material_override = material
	add_child(flash)
	flash.global_position = at
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.4, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.16)
	tween.chain().tween_callback(flash.queue_free)

func burst_ring(at: Vector3, inner: float, end_scale: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = inner + 0.08
	ring.mesh = mesh
	var material := effect_material(color, true)
	ring.material_override = material
	add_child(ring)
	ring.global_position = at
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * end_scale, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(ring.queue_free)

func burst_slash(at: Vector3, heavy: bool) -> void:
	var slash := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.15 if heavy else 0.7, 0.07, 0.07)
	slash.mesh = mesh
	var material := effect_material(Color("fffaf0"), true)
	slash.material_override = material
	add_child(slash)
	slash.global_position = at
	slash.rotation.z = randf_range(-0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(slash, "scale", Vector3(2.1 if heavy else 1.6, 0.35, 0.35), 0.07)
	tween.chain().set_parallel(true)
	tween.tween_property(slash, "scale", Vector3.ZERO, 0.08)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.08)
	tween.chain().tween_callback(slash.queue_free)

func burst_spark(at: Vector3, color: Color, heavy: bool) -> void:
	var shard := MeshInstance3D.new()
	var cube := BoxMesh.new()
	var size := randf_range(0.045, 0.1) * (1.4 if heavy else 1.0)
	cube.size = Vector3(size, size * randf_range(1.3, 2.6), size * 0.65)
	shard.mesh = cube
	var material := effect_material(color, true)
	shard.material_override = material
	add_child(shard)
	shard.global_position = at
	shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var yaw := randf() * TAU
	var direction := Vector3(cos(yaw), randf_range(0.35, 1.25), sin(yaw)).normalized()
	var reach := randf_range(0.75, 1.65) * (1.3 if heavy else 1.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(shard, "global_position", at + direction * reach + Vector3.DOWN * randf_range(0.0, 0.4), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shard, "scale", Vector3.ZERO, 0.24)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.24)
	tween.chain().tween_callback(shard.queue_free)

func damage_popup(at: Vector3, text: String, heavy: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64 if heavy else 48
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.modulate = Color("ffd27a") if heavy else Color("fff6d8")
	add_child(label)
	label.global_position = at + Vector3(randf_range(-0.15, 0.15), 0.15, 0.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(randf_range(-0.25, 0.25), 0.95, 0.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(label.queue_free)

func spin_burst(at: Vector3, powered: bool) -> void:
	if powered:
		play_sound(SWING_SOUND, -2.0)
	var color := Color("ffd36a") if powered else Color("9fd7ff")
	burst_ring(at, 0.5, 3.1 if powered else 1.7, color)
	burst_ring(at + Vector3.UP * 0.9, 0.22, 1.8 if powered else 1.05, Color("fffaf0"))
	if not powered:
		return
	for i in 14:
		burst_spark(at + Vector3.UP * 0.45, color, true)

func spin_ghost(at: Vector3, yaw: float) -> void:
	var ghost := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.72
	mesh.bottom_radius = 0.9
	mesh.height = 0.05
	ghost.mesh = mesh
	var material := effect_material(Color(0.75, 0.9, 1.0, 0.45), true)
	ghost.material_override = material
	add_child(ghost)
	ghost.global_position = at
	ghost.rotation.y = yaw
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ghost, "scale", Vector3(1.8, 1.0, 1.8), 0.16)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.16)
	tween.chain().tween_callback(ghost.queue_free)

func effect_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.7
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func play_sound(sound: AudioStream, volume_db: float) -> void:
	var speaker := AudioStreamPlayer.new()
	speaker.stream = sound
	speaker.volume_db = volume_db
	add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()
