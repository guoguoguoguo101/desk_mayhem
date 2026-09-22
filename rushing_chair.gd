extends Node3D

var direction := Vector3.FORWARD
var speed := 12.0
var remain := 9.0
var passenger: Node
var seat: Node3D
var grab_spent := false
var cosmetic := false

func _ready() -> void:
	if not cosmetic:
		add_to_group("rushing_chairs")
	seat = Node3D.new()
	seat.position = Vector3(0, 0.42, 0)
	add_child(seat)
	build_visual()

func launch(dir: Vector3) -> void:
	direction = dir
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	look_at(global_position + direction, Vector3.UP)
	direction = -global_transform.basis.z
	direction.y = 0.0
	direction = direction.normalized()

func build_visual() -> void:
	add_box(Vector3(0, 0.32, 0), Vector3(0.7, 0.12, 0.7), Color("3f6d78"))
	add_box(Vector3(0, 0.72, 0.28), Vector3(0.7, 0.7, 0.1), Color("3f6d78"))
	add_box(Vector3(0, 0.16, 0), Vector3(0.1, 0.32, 0.1), Color("2a3338"))
	for x in [-0.38, 0.38]:
		add_box(Vector3(x, 0.51, 0), Vector3(0.1, 0.09, 0.46), Color("263c50"))
		for z in [-0.27, 0.27]:
			preload("res://art_direction.gd").ball(self, Vector3(x * 0.8, 0.07, z), Vector3(0.14, 0.14, 0.14), Color("263c50"))
	add_box(Vector3(0, 0.1, 0), Vector3(0.65, 0.055, 0.55), Color("263c50"))

func add_box(at: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = preload("res://art_direction.gd").rounded_box(size)
	mesh_instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	add_child(mesh_instance)

func _physics_process(delta: float) -> void:
	if not cosmetic:
		if passenger and (not is_instance_valid(passenger) or passenger.get("downed") or not passenger.get("seated")):
			if is_instance_valid(passenger) and passenger.get("net_puppet"):
				passenger.seated = false
				passenger.net_pinned = false
			passenger = null
		if passenger == null and not grab_spent:
			try_grab()
	var blocker := obstacle_kind(speed * delta + 0.45)
	if blocker > 0:
		finish(blocker == 2)
		return
	var step := minf(speed * delta, remain)
	global_position += direction * step
	remain -= step
	if not cosmetic and passenger and is_instance_valid(passenger) and passenger.get("seated"):
		passenger.global_position = seat.global_position
		if passenger.get("net_puppet"):
			passenger.net_pinned = true
			var net := get_tree().get_first_node_in_group("network")
			if net and net.has_method("push_carry"):
				net.push_carry(int(passenger.owner_peer), seat.global_position)
	if remain <= 0.0:
		finish(false)

func try_grab() -> void:
	var attacker := get_tree().get_first_node_in_group("player")
	for target in get_tree().get_nodes_in_group("combat_targets"):
		if target.get("downed") or target.get("knockdown") or target.get("seated"):
			continue
		var to_target: Vector3 = target.global_position - global_position
		var height_gap := absf(to_target.y)
		to_target.y = 0.0
		var height_limit := 3.3 if target.get("juggled") or target.get("float_session") else 2.0
		if height_gap > height_limit or to_target.length() > 1.35:
			continue
		if to_target.length() > 0.2 and to_target.normalized().dot(direction) <= 0.0:
			continue
		if target.get("net_puppet"):
			if attacker == null or not attacker.has_method("connect_hit"):
				continue
			if not attacker.connect_hit(target, "begin_chair_ride", direction):
				continue
			target.seated = true
			target.net_pinned = true
			passenger = target
			grab_spent = true
			return
		if not target.has_method("seat_on"):
			continue
		target.take_hit("办公椅")
		if target.get("downed") or target.get("knockdown"):
			continue
		passenger = target
		grab_spent = true
		target.seat_on(seat)
		return

func obstacle_kind(distance: float) -> int:
	var from := global_position + Vector3.UP * 0.45
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * distance)
	var exclude: Array[RID] = []
	var player := get_tree().get_first_node_in_group("player")
	if player:
		exclude.append(player.get_rid())
	for target in get_tree().get_nodes_in_group("combat_targets"):
		exclude.append(target.get_rid())
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	var collider: Object = hit.collider
	if collider is Node and (collider as Node).is_in_group("arena_walls"):
		return 2
	return 1

func finish(hit_arena_wall: bool) -> void:
	var pop := -direction * 2.4 + Vector3.UP * 5.4
	if passenger and is_instance_valid(passenger) and passenger.get("net_puppet"):
		passenger.seated = false
		passenger.net_pinned = false
		var attacker := get_tree().get_first_node_in_group("player")
		if attacker and attacker.has_method("connect_hit"):
			var method := "end_chair_ride" if hit_arena_wall else "drop_from_chair"
			attacker.connect_hit(passenger, method, pop if hit_arena_wall else Vector3.ZERO)
	elif passenger and is_instance_valid(passenger):
		if hit_arena_wall and passenger.has_method("wall_pop_from_chair"):
			passenger.wall_pop_from_chair(pop)
		elif passenger.has_method("drop_from_chair"):
			passenger.drop_from_chair(Vector3.ZERO)
		elif passenger.has_method("release_seat"):
			passenger.release_seat(Vector3.ZERO)
	queue_free()
