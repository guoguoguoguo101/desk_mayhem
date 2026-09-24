class_name HitDetector
extends RefCounted

## Server-safe melee query. It only identifies candidates; damage and launch
## are still resolved by CombatResolver after this validation succeeds.

static func find_melee_targets(attacker: Node3D, intent) -> Array[Node]:
	var targets: Array[Node] = []
	if attacker == null or not is_instance_valid(attacker) or not intent.is_valid():
		return targets
	for candidate in attacker.get_tree().get_nodes_in_group("combat_targets"):
		if not candidate is Node3D:
			continue
		var target := candidate as Node3D
		if not is_valid_target(attacker, target, intent):
			continue
		targets.append(target)
	return targets

static func is_valid_target(attacker: Node3D, target: Node3D, intent) -> bool:
	if target == attacker or target.get("downed") or target.get("knockdown"):
		return false
	if attacker.has_method("can_hurt") and not attacker.call("can_hurt", target):
		return false
	if not target.has_method(intent.effect_method):
		return false
	if intent.shape == "segment":
		if not matches_segment_shape(target, intent):
			return false
		return not intent.requires_line_of_sight or has_segment_line_of_sight(attacker, target, intent)
	if not matches_melee_shape(attacker.global_position, target.global_position, intent.direction, intent.reach, intent.dot_min, intent.height_limit):
		return false
	return not intent.requires_line_of_sight or has_line_of_sight(attacker, target)

static func matches_melee_shape(
	origin: Vector3, target_position: Vector3, forward: Vector3, reach: float, dot_min: float, height_limit: float
) -> bool:
	var to_target := target_position - origin
	var height_gap := absf(to_target.y)
	to_target.y = 0.0
	if height_gap > height_limit or to_target.length() > reach:
		return false
	return to_target.length() <= 0.05 or to_target.normalized().dot(forward) > dot_min

static func has_line_of_sight(attacker: Node3D, target: Node3D) -> bool:
	if not attacker is CollisionObject3D or not target is CollisionObject3D:
		return true
	var from := attacker.global_position + Vector3.UP * 0.85
	var to := target.global_position + Vector3.UP * 0.85
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [attacker.get_rid()]
	var hit := attacker.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

static func matches_segment_shape(target: Node3D, intent) -> bool:
	var center := target.global_position + Vector3.UP * 0.7
	var closest := Geometry3D.get_closest_point_to_segment(center, intent.segment_from, intent.segment_to)
	var gap := center - closest
	var airborne := bool(target.get("juggled")) or bool(target.get("kick_bounce"))
	return Vector2(gap.x, gap.z).length() <= intent.segment_radius and absf(gap.y) <= (intent.airborne_height_limit if airborne else intent.ground_height_limit)

static func has_segment_line_of_sight(attacker: Node3D, target: Node3D, intent) -> bool:
	if not attacker is CollisionObject3D or not target is CollisionObject3D:
		return true
	var center := target.global_position + Vector3.UP * 0.7
	var closest := Geometry3D.get_closest_point_to_segment(center, intent.segment_from, intent.segment_to)
	var query := PhysicsRayQueryParameters3D.create(closest, center)
	query.exclude = [attacker.get_rid()]
	var hit := attacker.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target
