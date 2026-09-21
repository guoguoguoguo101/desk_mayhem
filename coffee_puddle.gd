extends Node3D

var remaining := 12.0

func _ready() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.025
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.17, 0.08, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	disc.material_override = material
	add_child(disc)
	var tween := create_tween()
	disc.scale = Vector3(0.1, 1.0, 0.1)
	tween.tween_property(disc, "scale", Vector3.ONE, 0.25)

func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
