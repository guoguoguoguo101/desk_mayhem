extends RefCounted

const MAX_LOAD := 5.0
const KNOCKDOWN_TIME := 0.8

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

static func extend(body, base_lift: float) -> void:
	add_hit(body)
	var mul := lift_mul(body)
	if mul <= 0.08:
		return
	var vel: Vector3 = body.velocity
	vel.y = maxf(vel.y, base_lift * mul)
	body.velocity = vel
	if body.get("float_time") != null:
		body.float_time = maxf(float(body.float_time), 0.4 * mul)
	if body.get("victim_float") != null:
		body.victim_float = maxf(float(body.victim_float), 0.4 * mul)

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
