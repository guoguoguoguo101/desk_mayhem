extends Node3D

const HIT_SOUND = preload("res://audio/hit.wav")
const HEAVY_SOUND = preload("res://audio/heavy_hit.wav")
const SWING_SOUND = preload("res://audio/swing.wav")

@onready var camera_rig: Node3D = get_node("../CameraRig")

func play_swing() -> void:
	play_sound(SWING_SOUND, -8.0)

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

func impact(at: Vector3, heavy := false) -> void:
	camera_rig.add_shake(0.35 if heavy else 0.18)
	play_sound(HEAVY_SOUND if heavy else HIT_SOUND, -1.0 if heavy else -4.0)
	var color := Color("ffb34a") if heavy else Color("fff0a6")
	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.22 if heavy else 0.15
	flash_mesh.height = flash_mesh.radius * 2.0
	flash.mesh = flash_mesh
	flash.material_override = effect_material(color)
	add_child(flash)
	flash.global_position = at
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.16)
	flash_tween.tween_callback(flash.queue_free)
	for i in range(9 if heavy else 6):
		var shard := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.07, 0.18, 0.06) * (1.4 if heavy else 1.0)
		shard.mesh = cube
		shard.material_override = effect_material(color)
		add_child(shard)
		shard.global_position = at
		var angle := TAU * float(i) / float(9 if heavy else 6)
		var direction := Vector3(cos(angle), 0.35 + float(i % 3) * 0.25, sin(angle))
		shard.rotation.z = angle
		var tween := create_tween().set_parallel(true)
		tween.tween_property(shard, "global_position", at + direction * (1.2 if heavy else 0.8), 0.24)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.24)
		tween.chain().tween_callback(shard.queue_free)

func effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	return material

func play_sound(sound: AudioStream, volume_db: float) -> void:
	var speaker := AudioStreamPlayer.new()
	speaker.stream = sound
	speaker.volume_db = volume_db
	add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()
