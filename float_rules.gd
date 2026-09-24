extends RefCounted

const KNOCKDOWN_TIME := 0.8
const AIR_GRAVITY := 16.5
const PUNCH_LAUNCH_SPEED := 9.2
const UMBRELLA_LAUNCH_SPEED := 9.3
const AIR_HIT_HEIGHT := 4.8
const AIR_HIT_REACH := 0.45
const PUNCH_HOLD := 0
const PUNCH_HOLD_Y := -0.35
const SPIN_LIFT := 1
const SPIN_LIFT_SPEED := 7.0
const POT_LIFT := 2
const POT_LIFT_SPEED := 3.0

static func start_launch(body) -> void:
	if not body.float_session:
		body.float_session = true
		body.air_punch_hold_used = false

static func pot_hit(body, direction: Vector3, returning: bool) -> void:
	if body.hit_locked():
		return
	# Keep ranged blocking consistent with the existing pot attack.
	if body.get("block_time") != null and body.block_time > 0.0:
		body.take_hit("锅")
		return
	body.take_hit("回旋锅·回收" if returning else "回旋锅")
	if body.downed:
		return
	if body.get("seated") == true:
		if body.has_method("release_seat"):
			body.release_seat(Vector3.ZERO)
		elif body.has_method("drop_from_chair"):
			body.drop_from_chair(Vector3.ZERO)
	body.velocity.x = direction.x if returning else direction.x * 3.8
	body.velocity.z = direction.z if returning else direction.z * 3.8
	if body.juggled and not body.bounce_pending and not body.kick_bounce:
		if returning:
			body.velocity.y = maxf(body.velocity.y, -1.0)
		else:
			extend(body, POT_LIFT)
	elif not body.kick_bounce and not body.bounce_pending:
		if body.get("stun_time") != null:
			body.stun_time = maxf(body.stun_time, 0.25)
		else:
			body.stagger_time = maxf(body.stagger_time, 0.25)

static func end_session(body) -> void:
	body.float_session = false
	body.juggled = false
	body.kick_bounce = false
	body.air_punch_hold_used = false
	body.float_apex = false

static func begin_float(body) -> void:
	body.float_apex = false

static func step_float(body, delta: float) -> void:
	if body.bounce_pending:
		body.velocity.y -= 20.0 * delta
		return
	body.velocity.y -= AIR_GRAVITY * delta
	if body.velocity.y <= 0.0:
		body.float_apex = true

static func extend(body, kind: int) -> void:
	if kind == PUNCH_HOLD:
		body.velocity.y = maxf(body.velocity.y, PUNCH_HOLD_Y)
		body.float_apex = false
		return
	if kind == POT_LIFT:
		body.velocity.y = maxf(body.velocity.y, POT_LIFT_SPEED)
		body.float_apex = false
		return
	body.velocity.y = maxf(body.velocity.y, SPIN_LIFT_SPEED)
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
		bounced.x = flat.x
		bounced.z = flat.z
		bounced.y = maxf(bounced.y, 4.4)
		body.velocity = bounced
		body.kick_bounce = false
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
