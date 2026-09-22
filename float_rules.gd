extends RefCounted

const MAX_LOAD := 5.0
const KNOCKDOWN_TIME := 0.8
const RISE_GRAVITY := 9.6
const FALL_GRAVITY := 13.0
const STALL_TIME := 0.52
const STALL_HEIGHT := 2.35
const HIT_HANG := 0.25
const HIT_LIFT := 1.8

static func start_launch(body) -> void:
	if not body.float_session:
		body.float_load = 0.0
		body.float_session = true

static func add_hit(body) -> void:
	body.float_session = true
	body.float_load = minf(MAX_LOAD, float(body.float_load) + 0.8)

static func tick(body, delta: float) -> void:
	if not body.float_session or body.downed or body.get("knockdown"):
		return
	body.float_load = minf(MAX_LOAD, float(body.float_load) + delta * 0.65)

static func lift_mul(body) -> float:
	return clampf(1.0 - float(body.float_load) / MAX_LOAD, 0.0, 1.0)

static func hang_gravity(body) -> float:
	return 6.2 + float(body.float_load) * 2.4

static func can_lift(body) -> bool:
	return lift_mul(body) > 0.08

static func end_session(body) -> void:
	body.float_session = false
	body.float_load = 0.0
	body.juggled = false
	body.kick_bounce = false
	if body.get("float_stall") != null:
		body.float_stall = 0.0
		body.float_apex = false
		body.float_held = false

static func begin_float(body) -> void:
	body.float_apex = false
	body.float_held = false
	body.float_stall = 0.0

static func step_float(body, delta: float) -> void:
	if body.bounce_pending:
		body.velocity.y -= 20.0 * delta
		return
	if not body.float_apex:
		var bottom := capsule_bottom_y(body)
		if body.velocity.y > 0.15 and bottom < STALL_HEIGHT:
			body.velocity.y -= RISE_GRAVITY * delta
			return
		var hang := STALL_TIME if bottom >= 1.55 else 0.22
		body.float_apex = true
		body.velocity.y = 0.0
		if not body.float_held:
			body.float_held = true
			body.float_stall = maxf(float(body.float_stall), hang)
	if body.float_stall > 0.0:
		body.float_stall = maxf(0.0, float(body.float_stall) - delta)
		body.velocity.y = 0.0
		return
	body.velocity.y -= FALL_GRAVITY * delta

static func extend(body, _base_lift: float) -> void:
	add_hit(body)
	var mul := lift_mul(body)
	if mul <= 0.08:
		return
	var vel: Vector3 = body.velocity
	vel.y = maxf(vel.y, HIT_LIFT * mul)
	body.velocity = vel
	body.float_stall = float(body.float_stall) + HIT_HANG
	if vel.y > 0.2:
		body.float_apex = false

static func try_kick_wall(body: CharacterBody3D) -> bool:
	if not body.kick_bounce:
		return false
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var normal := hit.get_normal()
		if normal.y > 0.45:
			continue
		var collider := hit.get_collider()
		if not (collider is Node) or not (collider as Node).is_in_group("arena_walls"):
			continue
		var bounced := body.velocity.bounce(normal) * 0.6
		var flat := Vector3(bounced.x, 0.0, bounced.z)
		if flat.length() > 8.5:
			flat = flat.normalized() * 8.5
		var mul := lift_mul(body)
		bounced.x = flat.x
		bounced.z = flat.z
		bounced.y = maxf(bounced.y, 4.4 * maxf(mul, 0.18))
		body.velocity = bounced
		body.kick_bounce = false
		add_hit(body)
		return true
	return false

static func is_combat_body(collider: Object) -> bool:
	if not collider is Node:
		return false
	var node := collider as Node
	return node.is_in_group("player") or node.is_in_group("fighters") or node.is_in_group("combat_targets") or node.is_in_group("training_dummies")

static func capsule_bottom_y(body: Node3D) -> float:
	var bottom := body.global_position.y
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		var capsule := shape_node.shape as CapsuleShape3D
		bottom = body.global_position.y + shape_node.position.y - capsule.height * 0.5
	return bottom

static func capsule_top_y(body: Node3D) -> float:
	var top := body.global_position.y + 0.8
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		var capsule := shape_node.shape as CapsuleShape3D
		top = body.global_position.y + shape_node.position.y + capsule.height * 0.5
	return top

static func launched_air(body) -> bool:
	return bool(body.get("juggled")) or bool(body.get("kick_bounce")) or bool(body.get("bounce_pending"))

static func on_arena_floor(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	var saw_body := false
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		if hit.get_normal().y < 0.45:
			continue
		if is_combat_body(hit.get_collider()):
			saw_body = true
		else:
			return true
	if saw_body:
		return false
	return capsule_bottom_y(body) <= 0.4

static func slip_off_bodies(body: CharacterBody3D) -> void:
	if body.get("body_exceptions") == null:
		return
	if not launched_air(body) or on_arena_floor(body):
		release_body_exceptions(body)
		return
	var riding := false
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		if hit.get_normal().y < 0.55:
			continue
		var collider := hit.get_collider()
		if not is_combat_body(collider) or not collider is CollisionObject3D:
			continue
		riding = true
		var listed: Array = body.body_exceptions
		if not listed.has(collider):
			body.add_collision_exception_with(collider)
			listed.append(collider)
	if riding:
		body.velocity.y = minf(body.velocity.y, -4.0)

static func release_body_exceptions(body: CharacterBody3D) -> void:
	var listed: Array = body.body_exceptions
	var kept: Array = []
	for node in listed:
		if not is_instance_valid(node) or not node is CollisionObject3D:
			continue
		var other := node as Node3D
		var still_inside := body.global_position.distance_to(other.global_position) < 1.15
		if still_inside and capsule_bottom_y(body) > 0.45:
			kept.append(node)
			continue
		body.remove_collision_exception_with(node)
	body.body_exceptions = kept

static func make_bar(parent: Node3D, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "FloatBar"
	root.position = Vector3(0, height, 0)
	parent.add_child(root)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.72, 0.07, 0.02)
	back.mesh = back_mesh
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.08, 0.08, 0.1, 0.85)
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = back_mat
	root.add_child(back)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.68, 0.045, 0.025)
	fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color("ffb03a")
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.material_override = fill_mat
	fill.position = Vector3(-0.34, 0, 0.01)
	root.add_child(fill)
	root.visible = false
	return root

static func show_bar(bar: Node3D, body) -> void:
	if bar == null:
		return
	var active: bool = body.float_session and float(body.float_load) > 0.04 and not body.downed and not body.get("knockdown")
	bar.visible = active
	if not active:
		return
	var mul := clampf(float(body.float_load) / MAX_LOAD, 0.04, 1.0)
	var fill := bar.get_node("Fill") as MeshInstance3D
	fill.scale = Vector3(mul, 1.0, 1.0)
	fill.position.x = -0.34 + 0.34 * mul
	var mat := fill.material_override as StandardMaterial3D
	mat.albedo_color = Color("ff5a3a") if mul > 0.82 else Color("ffb03a")
