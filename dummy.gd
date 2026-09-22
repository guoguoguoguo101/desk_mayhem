extends CharacterBody3D

var hit_count := 0
var wobble_time := 0.0
var hit_side := 1.0
var airborne := false
var airborne_lock := 0.0
var max_health := 300
var health := 300
var downed := false
var knockdown := false
var knockdown_time := 0.0
var revive_time := 0.0
var stun_time := 0.0
var seated := false
var seat_anchor: Node3D
var bounce_pending := false
var bounce_stun := 0.0
var float_time := 0.0
var juggle_hits := 0
var juggled := false
var float_load := 0.0
var float_session := false
var kick_bounce := false
var float_bar: Node3D
var can_throw := false
var throw_cooldown := 2.0
var display_name := ""
var revive_delay := 5.0
var hall_dummy := false
var dummy_index := -1
var pending_attacker := 0
var suppress_kill := false

@onready var visual: Node3D = $Visual
@onready var hit_label: Label3D = $HitLabel
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var feedback: Node3D = get_node("../CombatFeedback")
@onready var player: CharacterBody3D = get_node("../Player")

var flash_material := StandardMaterial3D.new()
const THROWN_ITEM = preload("res://thrown_item.gd")
const FloatRules = preload("res://float_rules.gd")

func dress_dummy() -> void:
	paint_part("Post", Color("3c434a"))
	paint_part("Head", Color("f0d3b4"))
	paint_part("Body", Color("3f6e8c"))
	paint_part("Crossbar", Color("2f363c"))
	paint_part("Base", Color("2a3036"))

func paint_part(part_name: String, color: Color) -> void:
	var part := visual.get_node_or_null(part_name)
	if not part is MeshInstance3D:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	(part as MeshInstance3D).material_override = material

func _ready() -> void:
	can_throw = name == "TrainingDummy7" or name == "TrainingDummy8"
	throw_cooldown = 1.5 if name == "TrainingDummy7" else 2.3
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.6, 0.2, 0.0)
	for part in visual.get_children():
		if part is MeshInstance3D:
			part.material_overlay = flash_material
	dress_dummy()
	float_bar = FloatRules.make_bar(self, 2.05)
	if can_throw:
		var head := visual.get_node_or_null("Head")
		if head is MeshInstance3D:
			var tint := StandardMaterial3D.new()
			tint.albedo_color = Color(0.45, 0.72, 0.95)
			head.set_surface_override_material(0, tint)

func hit_locked() -> bool:
	return downed or knockdown

func begin_knockdown() -> void:
	if downed or knockdown:
		return
	knockdown = true
	knockdown_time = FloatRules.KNOCKDOWN_TIME
	airborne = false
	juggled = false
	kick_bounce = false
	bounce_pending = false
	bounce_stun = 0.0
	float_time = 0.0
	juggle_hits = 0
	airborne_lock = 0.0
	stun_time = 0.0
	velocity = Vector3.ZERO
	FloatRules.end_session(self)
	feedback.impact(global_position + Vector3.UP * 0.25, false)

func take_hit(attack_name: String = "文件夹") -> void:
	if hit_locked():
		return
	hit_count += 1
	var damage: int = {
		"轻拳": 8,
		"文件夹": 18,
		"雨伞": 12,
		"雨伞挑飞": 25,
		"前踢": 12,
		"连拳": 8,
		"补拳": 10,
		"上勾拳": 18,
		"踢飞": 26,
		"咖啡": 12,
		"锅": 20,
		"扣锅": 35,
		"空中扣锅": 32,
		"旋伞": 8,
		"办公椅": 8,
		"椅推": 4,
	}.get(attack_name, 10)
	var combo := 0
	if player != null:
		combo = int(player.combo_count)
	damage += mini(combo, 6)
	health = maxi(0, health - damage)
	hit_label.text = "%s -%d  |  HP %d/%d" % [attack_name, damage, health, max_health]
	hit_label.modulate = Color(1.0, 0.35, 0.26)
	wobble_time = 0.26
	hit_side = 1.0 if randf() > 0.5 else -1.0
	var heavy := attack_name in ["雨伞挑飞", "扣锅", "空中扣锅", "踢飞", "上勾拳"] or combo >= 4
	var shake_combo := combo
	if attack_name == "踢飞":
		heavy = true
		shake_combo = maxi(combo, 6)
	feedback.impact(global_position + Vector3.UP * 1.2, heavy, shake_combo, "-%d" % damage)
	if player != null and attack_name != "椅推" and attack_name != "办公椅":
		var pause := 0.09 if heavy else 0.055
		if attack_name == "踢飞":
			pause = 0.14
		elif combo >= 3:
			pause += 0.02
		player.hit_pause = maxf(player.hit_pause, pause)
	if health <= 0:
		knock_down()

func knock_down() -> void:
	downed = true
	knockdown = false
	knockdown_time = 0.0
	airborne = false
	bounce_pending = false
	float_time = 0.0
	juggle_hits = 0
	FloatRules.end_session(self)
	stun_time = 0.0
	seated = false
	seat_anchor = null
	revive_time = revive_delay
	velocity = Vector3.ZERO
	visual.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	visual.position.y = 0.35
	collision.shape = collision.shape.duplicate()
	collision.shape.height = 0.7
	collision.position.y = 0.35
	hit_label.text = "倒地 · %.0f 秒后复活" % revive_delay
	hit_label.modulate = Color(1.0, 0.25, 0.25)
	if hall_dummy and not suppress_kill:
		var net := get_tree().get_first_node_in_group("network")
		if net and net.has_method("report_dummy_kill"):
			net.report_dummy_kill(pending_attacker, display_name)

func revive() -> void:
	downed = false
	knockdown = false
	knockdown_time = 0.0
	health = max_health
	stun_time = 0.0
	bounce_pending = false
	float_time = 0.0
	juggle_hits = 0
	FloatRules.end_session(self)
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	collision.shape.height = 1.8
	collision.position.y = 1.0
	refresh_idle_label()

func is_juggled() -> bool:
	return juggled and not downed and not knockdown

func punch_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	if juggled:
		take_hit("补拳")
		if downed or bounce_pending:
			return
		FloatRules.extend(self, 3.4)
		return
	if kick_bounce:
		take_hit("补拳")
		return
	take_hit("轻拳" if stun_time <= 0.0 else "连拳")
	if hit_locked():
		return
	apply_hitstun(direction, 3.0, 0.45)

func punch_follow(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	if juggled or kick_bounce:
		punch_from(direction)
		return
	take_hit("连拳")
	if hit_locked():
		return
	apply_hitstun(direction, 3.2, 0.45)

func punch_launch(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	if juggled or kick_bounce:
		punch_from(direction)
		return
	take_hit("上勾拳")
	if hit_locked():
		return
	begin_juggle(direction * 1.6 + Vector3.UP * 6.5)

func bump(direction: Vector3, speed: float) -> void:
	if hit_locked() or seated:
		return
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

func dash_hit_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	take_hit("雨伞")
	if hit_locked():
		return
	bump(direction, 3.0)

func launch_up(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	take_hit("雨伞挑飞")
	if hit_locked():
		return
	begin_juggle(direction * 1.4 + Vector3.UP * 6.6)

func kick_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	if juggled:
		take_hit("踢飞")
		if downed:
			return
		var bonus := 0.0
		if player != null:
			bonus = minf(float(player.combo_count), 6.0) * 1.15
		juggled = false
		bounce_pending = false
		float_time = 0.0
		kick_bounce = true
		airborne = true
		airborne_lock = 0.16
		stun_time = 0.2
		velocity = direction * (18.0 + bonus) + Vector3.UP * 2.4
		return
	take_hit("前踢")
	if hit_locked():
		return
	apply_hitstun(direction, 7.6, 0.45)

func slam_from_pot(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	if juggled or airborne:
		take_hit("空中扣锅")
		if downed:
			return
		float_time = 0.0
		juggled = true
		velocity = direction * 1.2 + Vector3.DOWN * 16.0
		airborne = true
		airborne_lock = 0.16
		bounce_pending = true
		bounce_stun = 0.55
	else:
		take_hit("扣锅")
		if downed:
			return
		velocity = Vector3.ZERO
		stun_time = 1.8

func pot_float(_direction: Vector3 = Vector3.ZERO) -> void:
	if hit_locked():
		return
	take_hit("锅")
	if downed or bounce_pending or kick_bounce or not juggled:
		return
	FloatRules.extend(self, 3.6)

func umbrella_spin_from(direction: Vector3) -> void:
	if hit_locked():
		return
	if seated:
		release_seat(Vector3.ZERO)
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	if juggled and not bounce_pending and not kick_bounce:
		take_hit("旋伞")
		if downed or bounce_pending or kick_bounce or not juggled:
			return
		FloatRules.extend(self, 2.6)
		return
	take_hit("旋伞")
	if hit_locked():
		return
	if kick_bounce or bounce_pending:
		velocity.x += flat.x * 5.5
		velocity.z += flat.z * 5.5
		return
	velocity.x = flat.x * 5.5
	velocity.z = flat.z * 5.5
	velocity.y = maxf(velocity.y, 0.2)

func juggle_poke(direction: Vector3 = Vector3.ZERO) -> void:
	if hit_locked() or not airborne or bounce_pending:
		return
	hold_juggle(direction, 3.0)

func apply_hitstun(direction: Vector3, push: float, duration: float) -> void:
	airborne = false
	juggled = false
	bounce_pending = false
	float_time = 0.0
	stun_time = maxf(stun_time, duration)
	velocity.x = direction.x * push
	velocity.z = direction.z * push
	velocity.y = 0.15

func begin_juggle(launch_velocity: Vector3) -> void:
	FloatRules.start_launch(self)
	velocity = launch_velocity
	airborne = true
	juggled = true
	kick_bounce = false
	airborne_lock = 0.18
	bounce_pending = false
	float_time = 0.95
	juggle_hits = 1
	stun_time = 0.0

func hold_juggle(direction: Vector3, lift: float) -> void:
	juggle_hits += 1
	float_time = maxf(float_time, 0.55 - minf(float(juggle_hits) * 0.04, 0.25))
	velocity.y = maxf(velocity.y, lift)
	airborne_lock = maxf(airborne_lock, 0.12)
	if direction.length_squared() > 0.01:
		var flat := direction.normalized()
		velocity.x = flat.x * 2.2
		velocity.z = flat.z * 2.2

func shove_from(direction: Vector3) -> void:
	if hit_locked() or seated:
		return
	take_hit("椅推")
	if hit_locked():
		return
	velocity = direction * 8.0 + Vector3.UP * 0.6
	airborne_lock = 0.12

func seat_on(anchor: Node3D) -> void:
	if hit_locked():
		return
	seated = true
	seat_anchor = anchor
	airborne = false
	bounce_pending = false
	float_time = 0.0
	juggle_hits = 0
	juggled = false
	kick_bounce = false
	velocity = Vector3.ZERO

func drop_from_chair(_direction: Vector3 = Vector3.ZERO) -> void:
	var was_seated := seated
	seated = false
	seat_anchor = null
	if not was_seated or downed:
		FloatRules.end_session(self)
		return
	velocity = Vector3.ZERO
	airborne = false
	FloatRules.end_session(self)

func wall_pop_from_chair(throw_velocity: Vector3) -> void:
	seated = false
	seat_anchor = null
	if hit_locked():
		return
	if not float_session:
		velocity = Vector3.ZERO
		airborne = false
		return
	FloatRules.add_hit(self)
	var mul := FloatRules.lift_mul(self)
	juggled = true
	kick_bounce = false
	bounce_pending = false
	airborne = true
	airborne_lock = 0.16
	stun_time = 0.0
	var pop := throw_velocity
	pop.y *= maxf(mul, 0.16)
	velocity = pop
	float_time = 0.5 * maxf(mul, 0.16)

func release_seat(throw_velocity: Vector3) -> void:
	var was_seated := seated
	seated = false
	seat_anchor = null
	if not was_seated or downed:
		return
	velocity = throw_velocity
	if throw_velocity.length() > 0.1:
		airborne = true
		airborne_lock = 0.16

func _physics_process(delta: float) -> void:
	if player != null and player.hit_pause > 0.0:
		return
	if seated:
		if seat_anchor and is_instance_valid(seat_anchor):
			global_position = seat_anchor.global_position
			velocity = Vector3.ZERO
			return
		seated = false
		seat_anchor = null
	airborne_lock = maxf(0.0, airborne_lock - delta)
	float_time = maxf(0.0, float_time - delta)
	if downed or knockdown:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 19.0 * delta
		move_and_slide()
		return
	if kick_bounce:
		velocity.y -= 16.0 * delta
		move_and_slide()
		if FloatRules.try_kick_wall(self):
			juggled = true
			airborne = true
			airborne_lock = 0.14
			float_time = 0.48 * maxf(FloatRules.lift_mul(self), 0.16)
		elif is_on_floor() and airborne_lock <= 0.0:
			begin_knockdown()
		return
	var gravity := 19.0
	if juggled and float_time > 0.0 and not bounce_pending:
		gravity = FloatRules.hang_gravity(self)
	velocity.y -= gravity * delta
	if is_on_floor():
		var drag := 14.0 if stun_time > 0.0 else 8.0
		velocity.x = move_toward(velocity.x, 0.0, drag * delta)
		velocity.z = move_toward(velocity.z, 0.0, drag * delta)
	move_and_slide()
	if is_on_floor() and airborne_lock <= 0.0:
		if bounce_pending:
			bounce_pending = false
			airborne = true
			airborne_lock = 0.12
			FloatRules.add_hit(self)
			velocity.y = 5.0 * maxf(FloatRules.lift_mul(self), 0.18)
			float_time = 0.42 * maxf(FloatRules.lift_mul(self), 0.18)
			juggled = true
			stun_time = maxf(stun_time, bounce_stun)
			feedback.impact(global_position + Vector3.UP * 0.35, true, 2)
		elif juggled or airborne:
			begin_knockdown()
		elif float_session:
			FloatRules.end_session(self)

func _process(delta: float) -> void:
	FloatRules.tick(self, delta)
	FloatRules.show_bar(float_bar, self)
	stun_time = maxf(0.0, stun_time - delta)
	if downed:
		revive_time -= delta
		hit_label.text = "倒地 · %.1f 秒后复活" % maxf(0.0, revive_time)
		if revive_time <= 0.0:
			revive()
		return
	if knockdown:
		knockdown_time -= delta
		visual.rotation.z = 0.0
		visual.scale = Vector3.ONE
		visual.rotation.x = lerp_angle(visual.rotation.x, -1.15, 10.0 * delta)
		visual.position.y = lerpf(visual.position.y, 0.28, 10.0 * delta)
		flash_material.albedo_color = Color(0.75, 0.88, 1.0, 0.35)
		hit_label.text = "倒地保护 %.1f" % maxf(knockdown_time, 0.0)
		hit_label.modulate = Color(0.75, 0.88, 1.0)
		if knockdown_time <= 0.0:
			knockdown = false
			knockdown_time = 0.0
			visual.rotation.x = 0.0
			visual.position.y = 0.0
		return
	update_throw(delta)
	if wobble_time > 0.0:
		wobble_time -= delta
		var punch := clampf(wobble_time / 0.26, 0.0, 1.0)
		visual.scale = Vector3(1.0 + punch * 0.36, maxf(0.68, 1.0 - punch * 0.3), 1.0 + punch * 0.36)
		visual.rotation.z = hit_side * sin(punch * PI) * 0.48
		var flash_color := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.42, 0.12), 1.0 - punch)
		flash_color.a = 0.28 + punch * 0.62
		flash_material.albedo_color = flash_color
		return
	visual.rotation.z = 0.0
	visual.scale = Vector3.ONE
	if juggled:
		flash_material.albedo_color = Color(1.0, 0.62, 0.28, 0.45)
		hit_label.text = "击飞  |  HP %d/%d" % [health, max_health]
		hit_label.modulate = Color(1.0, 0.78, 0.42)
	elif stun_time > 0.8:
		flash_material.albedo_color = Color(0.65, 0.78, 1.0, 0.35 + sin(stun_time * 18.0) * 0.12)
		hit_label.text = "眩晕 %.1f  |  HP %d/%d" % [stun_time, health, max_health]
		hit_label.modulate = Color(0.75, 0.86, 1.0)
	elif stun_time > 0.0:
		flash_material.albedo_color = Color(1.0, 0.9, 0.55, 0.28)
		hit_label.text = "硬直  |  HP %d/%d" % [health, max_health]
		hit_label.modulate = Color(1.0, 0.92, 0.7)
	else:
		flash_material.albedo_color.a = 0.0
		refresh_idle_label()

func refresh_idle_label() -> void:
	var title := display_name if display_name != "" else "训练稻草人"
	if seated:
		title = "坐在椅子上"
	elif can_throw and throw_cooldown <= 0.75 and can_see_player():
		title = "即将扔出"
	elif can_throw:
		title = "远程稻草人"
	hit_label.text = "%s  |  HP %d/%d" % [title, health, max_health]
	hit_label.modulate = Color(0.7, 0.9, 1.0) if can_throw else Color(1.0, 0.9, 0.56)

func update_throw(delta: float) -> void:
	if not can_throw or seated or stun_time > 0.0 or juggled:
		return
	throw_cooldown -= delta
	if throw_cooldown > 0.0:
		return
	if not can_see_player():
		throw_cooldown = 0.45
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var direction := to_player.normalized()
	var item := THROWN_ITEM.new()
	get_parent().add_child(item)
	item.global_position = global_position + Vector3.UP * 1.35 + direction * 0.85
	item.launch(THROWN_ITEM.ItemKind.FOLDER, direction, get_rid())
	throw_cooldown = 3.4

func can_see_player() -> bool:
	if player == null or player.get("downed") or player.get("knockdown"):
		return false
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance < 1.2 or distance > 28.0:
		return false
	var from := global_position + Vector3.UP * 1.3
	var to := player.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player
