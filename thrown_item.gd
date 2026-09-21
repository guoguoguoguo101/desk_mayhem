extends Node3D

enum ItemKind { FOLDER, COFFEE }

var kind: ItemKind
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO
var player_rid: RID
var lifetime := 0.0
var visual: MeshInstance3D

func launch(item_kind: ItemKind, throw_direction: Vector3, owner_rid: RID) -> void:
	kind = item_kind
	direction = throw_direction
	player_rid = owner_rid
	velocity = direction * (12.0 if kind == ItemKind.FOLDER else 8.5)
	if kind == ItemKind.COFFEE:
		velocity.y = 4.2
	create_visual()

func create_visual() -> void:
	visual = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if kind == ItemKind.FOLDER:
		var folder := BoxMesh.new()
		folder.size = Vector3(0.66, 0.07, 0.46)
		visual.mesh = folder
		material.albedo_color = Color("e1aa46")
		var label := Label3D.new()
		label.text = "FILE"
		label.font_size = 32
		label.pixel_size = 0.003
		label.position.y = 0.05
		label.rotation_degrees.x = -90
		add_child(label)
	else:
		var cup := CylinderMesh.new()
		cup.top_radius = 0.19
		cup.bottom_radius = 0.14
		cup.height = 0.33
		visual.mesh = cup
		material.albedo_color = Color("f3e0b6")
	visual.material_override = material
	add_child(visual)

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime > 3.0:
		queue_free()
		return
	var next_position := global_position + velocity * delta
	if kind == ItemKind.COFFEE:
		velocity.y -= 13.0 * delta
		visual.rotate_x(6.0 * delta)
		if next_position.y <= 0.12:
			make_puddle(Vector3(next_position.x, 0.025, next_position.z))
			queue_free()
			return
	else:
		visual.rotate_y(16.0 * delta)
	var ray := PhysicsRayQueryParameters3D.create(global_position, next_position)
	ray.exclude = [player_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		if kind == ItemKind.FOLDER and hit.collider.has_method("take_hit"):
			hit.collider.take_hit()
		if kind == ItemKind.COFFEE:
			make_puddle(Vector3(hit.position.x, 0.025, hit.position.z))
		queue_free()
		return
	global_position = next_position

func make_puddle(at: Vector3) -> void:
	var puddle := preload("res://coffee_puddle.gd").new()
	get_parent().add_child(puddle)
	puddle.global_position = at
