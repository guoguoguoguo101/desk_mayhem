extends Node3D

enum ItemKind { FOLDER, COFFEE, POT }

var kind: ItemKind
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO
var owner_rid: RID
var lifetime := 0.0
var visual: MeshInstance3D
var cosmetic := false

const POT_HIT_RADIUS := 0.85
const POT_HIT_NEAR := 1.2
const POT_HIT_AIR := 2.9
const POT_GRAVITY := 8.0

func launch_with_velocity(item_kind: ItemKind, projectile_velocity: Vector3, thrower_rid: RID) -> void:
	kind = item_kind
	owner_rid = thrower_rid
	velocity = projectile_velocity
	direction = Vector3(velocity.x, 0.0, velocity.z)
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	create_visual()

func launch(item_kind: ItemKind, throw_direction: Vector3, thrower_rid: RID) -> void:
	kind = item_kind
	direction = throw_direction
	owner_rid = thrower_rid
	match kind:
		ItemKind.FOLDER:
			velocity = direction * 12.0
		ItemKind.COFFEE:
			velocity = direction * 8.5 + Vector3.UP * 4.2
		ItemKind.POT:
			velocity = direction * 13.0
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
	elif kind == ItemKind.POT:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.34
		pot.bottom_radius = 0.28
		pot.height = 0.16
		visual.mesh = pot
		material.albedo_color = Color("3e454c")
		material.metallic = 0.55
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
	if kind == ItemKind.POT:
		velocity.y -= POT_GRAVITY * delta
	var from := global_position
	var next_position := from + velocity * delta
	if kind == ItemKind.COFFEE:
		velocity.y -= 13.0 * delta
		visual.rotate_x(6.0 * delta)
		if next_position.y <= 0.12:
			make_puddle(Vector3(next_position.x, 0.025, next_position.z))
			queue_free()
			return
	elif kind == ItemKind.POT:
		visual.rotate_x(10.0 * delta)
	else:
		visual.rotate_y(16.0 * delta)
	var ray := PhysicsRayQueryParameters3D.create(from, next_position)
	ray.exclude = [owner_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if kind == ItemKind.POT:
		var person := pot_body_along(from, next_position, hit)
		if person != null:
			if not cosmetic:
				connect_throw_hit(person, "锅")
			queue_free()
			return
	if hit.is_empty():
		global_position = next_position
		return
	if kind == ItemKind.COFFEE:
		make_puddle(Vector3(hit.position.x, 0.025, hit.position.z))
	elif not cosmetic:
		var attack_name := "锅" if kind == ItemKind.POT else "文件夹"
		connect_throw_hit(hit.collider, attack_name)
	queue_free()

func pot_body_along(from: Vector3, to: Vector3, world_hit: Dictionary) -> Object:
	var block := INF
	if not world_hit.is_empty():
		var blocker: Object = world_hit.collider
		if blocker == null or not blocker.has_method("take_hit"):
			block = from.distance_to(world_hit.position)
	var best: Object = null
	var best_travel := block
	for node in get_tree().get_nodes_in_group("combat_targets"):
		if not node is CollisionObject3D:
			continue
		var body := node as CollisionObject3D
		if body.get_rid() == owner_rid:
			continue
		var center := body.global_position
		var shape_node := body.get_node_or_null("CollisionShape3D") as Node3D
		if shape_node:
			center += shape_node.position
		var closest := closest_point_on_segment(from, to, center)
		var gap := center - closest
		var above := POT_HIT_AIR if body_in_air(body) else POT_HIT_NEAR
		if Vector2(gap.x, gap.z).length() > POT_HIT_RADIUS:
			continue
		if gap.y > above or gap.y < -POT_HIT_NEAR:
			continue
		var travel := from.distance_to(closest)
		if travel >= best_travel:
			continue
		best = body
		best_travel = travel
	return best

func body_in_air(body: Object) -> bool:
	return body.get("juggled") == true or body.get("kick_bounce") == true or body.get("airborne") == true or body.get("float_session") == true

func closest_point_on_segment(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var segment := to - from
	var length_sq := segment.length_squared()
	if length_sq < 0.0001:
		return from
	var amount := clampf((point - from).dot(segment) / length_sq, 0.0, 1.0)
	return from + segment * amount

func connect_throw_hit(target: Object, attack_name: String) -> void:
	if target.get("downed") or target.get("knockdown"):
		return
	var juggled: bool = target.get("juggled") == true
	var falling: bool = target.get("bounce_pending") == true
	var float_pot: bool = attack_name == "锅" and juggled and not falling and target.has_method("pot_float")
	if target.get("net_puppet") or (target is Node and (target as Node).is_in_group("hall_dummies")):
		var attacker := get_tree().get_first_node_in_group("player")
		if attacker and attacker.has_method("connect_hit"):
			if float_pot:
				attacker.connect_hit(target, "pot_float", direction)
			else:
				attacker.connect_hit(target, "", Vector3.ZERO, attack_name)
	elif float_pot:
		target.pot_float(direction)
	elif target.has_method("take_hit"):
		target.take_hit(attack_name)

func make_puddle(at: Vector3) -> void:
	var puddle := preload("res://coffee_puddle.gd").new()
	puddle.authoritative = not cosmetic
	get_parent().add_child(puddle)
	puddle.global_position = at
	puddle.burst()
