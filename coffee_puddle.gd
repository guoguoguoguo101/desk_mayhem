extends Node3D

var remaining := 8.0
var authoritative := true

func _ready() -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.35
	mesh.bottom_radius = 1.35
	mesh.height = 0.025
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.17, 0.08, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	disc.material_override = material
	add_child(disc)
	disc.scale = Vector3(0.1, 1.0, 0.1)
	var tween := create_tween()
	tween.tween_property(disc, "scale", Vector3.ONE, 0.22)
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 1.27
	ring.outer_radius = 1.33
	ring.rings = 32
	ring.ring_segments = 8
	rim.mesh = ring
	rim.material_override = preload("res://art_direction.gd").material(Color("c49a66"), 0.25)
	add_child(rim)
	rim.position.y = 0.025
	rim.scale.y = 0.18
	for i in 5:
		var angle := float(i) * TAU / 5
		preload("res://art_direction.gd").ball(self, Vector3(cos(angle) * 0.7, 0.03, sin(angle) * 0.7), Vector3(0.11, 0.025, 0.16), Color("d7b787"))

func burst() -> void:
	splash()
	if not authoritative:
		return
	var attacker := get_tree().get_first_node_in_group("player")
	for target in get_tree().get_nodes_in_group("combat_targets"):
		var flat: Vector3 = target.global_position - global_position
		flat.y = 0.0
		if flat.length() > 1.5:
			continue
		if attacker and attacker.has_method("connect_hit"):
			attacker.connect_hit(target, "", Vector3.ZERO, "咖啡")
		elif target.has_method("take_hit"):
			target.take_hit("咖啡")
	var feedback := get_parent().get_node_or_null("CombatFeedback")
	if feedback and feedback.has_method("impact"):
		feedback.impact(global_position + Vector3.UP * 0.2, false)

func splash() -> void:
	for i in 6:
		var drop := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.08
		mesh.height = 0.16
		drop.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.42, 0.2, 0.1, 0.9)
		drop.material_override = material
		add_child(drop)
		var angle := TAU * float(i) / 6.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(drop, "position", Vector3(cos(angle), 0.05, sin(angle)) * 1.15, 0.28)
		tween.tween_property(drop, "scale", Vector3.ZERO, 0.28)
		tween.chain().tween_callback(drop.queue_free)

func _process(delta: float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
