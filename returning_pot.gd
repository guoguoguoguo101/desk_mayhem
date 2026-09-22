extends Node3D

const RANGE := 8.0
const OUT_SPEED := 14.0
const RETURN_SPEED := 16.0
const RECALL_SPEED := 22.0
const FLARE = preload("res://assets/kenney_particles/flare_01.png")
var thrower: Node3D
var direction := Vector3.FORWARD
var returning := false
var recalled := false
var cosmetic := false
var travelled := 0.0
var age := 0.0
var hit_out := {}
var hit_back := {}
var rotor := Node3D.new()
var ribbon := MeshInstance3D.new()
var points: Array[Vector3] = []
var glow := StandardMaterial3D.new()

func launch(body: Node3D, forward: Vector3) -> void:
	thrower = body
	direction = forward.normalized()
	add_to_group("returning_pots")
	add_child(rotor)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.44
	bowl.bottom_radius = 0.34
	bowl.height = 0.14
	part(bowl, Vector3.ZERO, Color("293b50"))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.39
	rim.outer_radius = 0.46
	part(rim, Vector3(0, 0.07, 0), Color("dce8ee"))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.14, 0.13, 0.65)
	part(handle, Vector3(0, 0, 0.65), Color("994829"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color("ffc65b")
	var halo := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.53
	ring.outer_radius = 0.57
	halo.mesh = ring
	halo.material_override = glow
	rotor.add_child(halo)
	get_parent().add_child(ribbon)
	ribbon.material_override = glow
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash(global_position, 0.65)

func part(mesh: Mesh, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.3
	node.material_override = mat
	rotor.add_child(node)
	node.position = at

func recall(fast := true) -> void:
	if returning and (recalled or not fast):
		return
	returning = true
	recalled = recalled or fast
	glow.albedo_color = Color("65edff")
	flash(global_position, 1.25 if fast else 0.8)
	var feedback := get_parent().get_node_or_null("CombatFeedback")
	if feedback:
		feedback.play_swing()
		feedback.burst_ring(global_position, 0.4, 2.8, glow.albedo_color)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(thrower) or thrower.get("downed") or thrower.get("controls_locked") == true or age > 4.0:
		queue_free()
		return
	age += delta
	var from := global_position
	var destination := thrower.global_position + Vector3.UP * 0.85
	var step := direction * OUT_SPEED * delta
	if returning:
		step = (destination - from).limit_length((RECALL_SPEED if recalled else RETURN_SPEED) * delta)
	var finish := from + step
	var exclude: Array[RID] = []
	for body in get_tree().get_nodes_in_group("combat_targets"):
		if body is CollisionObject3D:
			exclude.append(body.get_rid())
	if thrower is CollisionObject3D:
		exclude.append(thrower.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, finish)
	query.exclude = exclude
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		finish = wall.position
	check_hits(from, finish)
	global_position = finish
	travelled += step.length()
	if not wall.is_empty():
		flash(finish, 0.9)
		if returning:
			queue_free()
			return
		global_position += wall.normal * 0.12
		recall(false)
	elif not returning and travelled >= RANGE:
		recall(false)
	elif returning and global_position.distance_to(destination) < 0.5:
		flash(destination, 0.65)
		queue_free()
		return
	rotor.rotate_y(delta * (38.0 if recalled else 26.0))
	rotor.rotation.z = sin(age * 14.0) * 0.12
	update_trail()

func check_hits(from: Vector3, to: Vector3) -> void:
	var struck: Dictionary = hit_back if returning else hit_out
	for target in get_tree().get_nodes_in_group("combat_targets"):
		if target == thrower or struck.has(target.get_instance_id()) or target.get("downed") or target.get("knockdown"):
			continue
		if not thrower.can_hurt(target):
			continue
		var center: Vector3 = target.global_position + Vector3.UP * 0.7
		var closest := Geometry3D.get_closest_point_to_segment(center, from, to)
		var gap := center - closest
		var airborne: bool = target.get("juggled") == true or target.get("kick_bounce") == true
		if Vector2(gap.x, gap.z).length() > 0.85 or absf(gap.y) > (3.0 if airborne else 1.15):
			continue
		var sight := PhysicsRayQueryParameters3D.create(closest, center)
		sight.exclude = [thrower.get_rid()]
		var block := get_world_3d().direct_space_state.intersect_ray(sight)
		if not block.is_empty() and block.collider != target:
			continue
		struck[target.get_instance_id()] = true
		var push := direction
		if returning:
			push = thrower.global_position - target.global_position
			push.y = 0.0
			push = push.normalized() * minf(8.0, maxf(0.0, push.length() - 0.7) * 4.0)
		if not cosmetic and thrower.connect_hit(target, "pot_return" if returning else "pot_outbound", push):
			thrower.register_combo(1)
		flash(center, 1.35)
		var feedback := get_parent().get_node_or_null("CombatFeedback")
		if feedback:
			feedback.burst_ring(center, 0.25, 2.4, glow.albedo_color)

func flash(at: Vector3, size: float) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = FLARE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.006
	sprite.modulate = glow.albedo_color
	sprite.shaded = false
	get_parent().add_child(sprite)
	sprite.global_position = at
	sprite.scale = Vector3.ONE * size
	var tween := sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector3.ONE * size * 1.8, 0.18)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(sprite.queue_free)

func update_trail() -> void:
	points.push_front(global_position)
	if points.size() > (16 if recalled else 11):
		points.pop_back()
	if points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in points.size():
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := (points[maxi(0, i - 1)] - next).normalized()
		var side := tangent.cross(Vector3.UP).normalized() * 0.34 * (1.0 - float(i) / points.size())
		mesh.surface_add_vertex(points[i] + side)
		mesh.surface_add_vertex(points[i] - side)
	mesh.surface_end()
	ribbon.mesh = mesh

func _exit_tree() -> void:
	if is_instance_valid(ribbon):
		ribbon.queue_free()
