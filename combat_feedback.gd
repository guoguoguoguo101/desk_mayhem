extends Node3D

const HIT_SOUND = preload("res://audio/hit.wav")
const HEAVY_SOUND = preload("res://audio/heavy_hit.wav")
const SWING_SOUND = preload("res://audio/swing.wav")
const SLASH_PUNCH = preload("res://assets/vfx/slash_punch.png")
const SLASH_LIGHT = preload("res://assets/vfx/slash_light.png")
const SLASH_FOLLOW = preload("res://assets/vfx/slash_follow.png")
const SLASH_AIR = preload("res://assets/vfx/slash_air.png")
const SLASH_KICK = preload("res://assets/vfx/slash_kick.png")
const KICK_CORE = preload("res://assets/vfx/kick_core.png")
const KICK_ARC = preload("res://assets/vfx/kick_arc.png")
const KICK_HIT = preload("res://assets/vfx/kick_hit.png")
const SLASH_UPPER = preload("res://assets/vfx/slash_upper.png")
const SLASH_UMBRELLA = preload("res://assets/vfx/slash_umbrella.png")
const SPARK_TEX = preload("res://assets/vfx/spark.png")
const SOFT_TEX = preload("res://assets/vfx/soft.png")
const RING_TEX = preload("res://assets/vfx/ring.png")
const DUST_TEX = preload("res://assets/vfx/dust.png")
const LIGHTNING_TEXTS: Array[Texture2D] = [
	preload("res://assets/vfx/lightning_jagged.png"),
	preload("res://assets/vfx/lightning_anime.png"),
	preload("res://assets/vfx/lightning_thin.png"),
	preload("res://assets/vfx/lightning_fork.png"),
]
const WIND_TEX = preload("res://assets/vfx/wind_streak.png")
const FOX_UMBRELLA_VFX = preload("res://vfx/FoxUmbrellaSpiritVFX.tscn")
const ADDITIVE = preload("res://vfx/additive_sprite.gdshader")

@onready var camera_rig: Node3D = get_node("../CameraRig")

var ghost_wait := 0.0
var blink_lightning_index := 0
var dash_points: Array[Vector3] = []
var dash_idle := 0.0
var dash_ribbon: MeshInstance3D
var wind_trails := {}
var limb_trails := {}
var spin_spirits := {}

func _process(delta: float) -> void:
	ghost_wait = maxf(0.0, ghost_wait - delta)
	_decay_dash(delta)
	_decay_wind(delta)
	_decay_limb(delta)
	for key in spin_spirits.keys():
		var spirit: FoxUmbrellaSpiritVFX = spin_spirits[key]
		if not is_instance_valid(spirit):
			spin_spirits.erase(key)
		elif not spirit.active:
			spirit.queue_free()
			spin_spirits.erase(key)

func _decay_dash(delta: float) -> void:
	if dash_points.is_empty():
		return
	dash_idle += delta
	if dash_idle <= 0.08:
		return
	dash_points.pop_back()
	if dash_points.size() < 2:
		dash_points.clear()
		if dash_ribbon:
			dash_ribbon.visible = false
		return
	_rebuild_dash_ribbon()

func play_swing() -> void:
	play_sound(SWING_SOUND, -8.0)

func present_attack(attack: String, origin: Vector3, forward: Vector3, body: Node3D = null) -> void:
	var flat := forward
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	match attack:
		"punch_light", "punch_follow", "punch_air", "punch_uppercut":
			play_melee(body, attack, flat, origin)
		"kick_front":
			play_kick(body, flat, origin)
		"umbrella_uppercut":
			attack_arc(origin + Vector3.UP * 0.9, flat, 1.7, Color("85e2dd"), true)
		"umbrella_spin":
			pass
		"pot_slam", "pot_slam_air":
			attack_arc(origin + Vector3.UP * 1.15, flat, 1.45, Color("ffb45a"), true)

func play_melee(body: Node3D, attack: String, forward: Vector3, fallback := Vector3.INF) -> void:
	var profile := _melee_profile(attack)
	if profile.is_empty():
		return
	var flat := forward
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var limb := _limb_world(body, str(profile.bone))
	var at := limb if limb.is_finite() else fallback
	if not at.is_finite() and body != null:
		at = body.global_position
	if not at.is_finite():
		return
	var texture: Texture2D = profile.texture
	var tint: Color = profile.tint
	var mat := _additive_material(texture, tint, float(profile.energy))
	mat.set_shader_parameter("reveal", 0.02)
	var slash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = profile.size
	slash.mesh = quad
	slash.material_override = mat
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slash)
	var yaw := atan2(-flat.x, -flat.z)
	slash.rotation = Vector3(float(profile.tilt), yaw, float(profile.roll_from))
	slash.global_position = at
	var sweep := create_tween().set_parallel(true)
	sweep.tween_property(slash, "rotation:z", float(profile.roll_to), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sweep.tween_property(slash, "global_position", at + flat * float(profile.travel) + Vector3.UP * float(profile.lift), 0.12)
	sweep.tween_method(func(amount: float) -> void:
		mat.set_shader_parameter("reveal", amount)
	, 0.02, 1.0, 0.1)
	sweep.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 1.0, 0.0, 0.14).set_delay(0.05)
	sweep.chain().tween_callback(slash.queue_free)
	var side := flat.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var gust_dir := (flat + side * float(profile.side) + Vector3.UP * float(profile.up)).normalized()
	_gust(at, gust_dir, tint, int(profile.gust))
	var tip_from := at
	var tip_to := at + flat * float(profile.travel) + side * float(profile.side) * 0.35 + Vector3.UP * float(profile.lift)
	_moving_spark(tip_from, tip_to, tint)

func _melee_profile(attack: String) -> Dictionary:
	match attack:
		"punch_light":
			return {"texture": SLASH_LIGHT, "size": Vector2(1.05, 0.38), "tint": Color("ffe7b0"), "energy": 1.55, "tilt": -0.12, "roll_from": -0.2, "roll_to": 0.28, "travel": 0.22, "lift": 0.02, "side": 0.8, "up": 0.1, "gust": 5, "bone": "DEF-hand.R"}
		"punch_follow":
			return {"texture": SLASH_FOLLOW, "size": Vector2(1.45, 0.72), "tint": Color("ff8a3a"), "energy": 1.65, "tilt": -0.18, "roll_from": 0.48, "roll_to": -0.22, "travel": 0.34, "lift": 0.06, "side": -0.9, "up": 0.2, "gust": 6, "bone": "DEF-hand.R"}
		"punch_uppercut":
			return {"texture": SLASH_UPPER, "size": Vector2(0.62, 1.35), "tint": Color("ffd27a"), "energy": 1.7, "tilt": 0.05, "roll_from": -0.08, "roll_to": 0.12, "travel": 0.08, "lift": 0.42, "side": 0.1, "up": 1.0, "gust": 6, "bone": "DEF-hand.R"}
		"punch_air":
			return {"texture": SLASH_AIR, "size": Vector2(0.72, 0.42), "tint": Color("fff6d2"), "energy": 1.5, "tilt": -0.08, "roll_from": 0.2, "roll_to": -0.18, "travel": 0.18, "lift": -0.04, "side": 0.25, "up": 0.05, "gust": 4, "bone": "DEF-hand.R"}
		"kick_front":
			return {"texture": KICK_ARC, "size": Vector2(1.7, 0.5), "tint": Color("ffc14a"), "energy": 1.6, "tilt": -0.28, "roll_from": 0.4, "roll_to": -0.3, "travel": 0.48, "lift": -0.05, "side": 0.15, "up": -0.1, "gust": 0, "bone": "DEF-foot.R"}
	return {}

func play_kick(body: Node3D, forward: Vector3, fallback := Vector3.INF) -> void:
	var flat := _flat_forward(forward)
	_kick_card(body, flat, fallback, KICK_CORE, Vector2(1.15, 0.22), Color("fff3cf"), 1.45, 0.28, -0.08, 0.16, 0.0, 0.1)
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_kick_card(body, flat, fallback, KICK_ARC, Vector2(1.9, 0.58), Color("ffc14a"), 1.65, 0.4, -0.34, 0.5, -0.04, 0.16)
	)
	get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_kick_burst(body, flat, fallback)
	)

func _flat_forward(forward: Vector3) -> Vector3:
	var flat := forward
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()

func _kick_point(body: Node3D, fallback: Vector3) -> Vector3:
	if body != null and not is_instance_valid(body):
		body = null
	var limb := _limb_world(body, "DEF-foot.R")
	if limb.is_finite():
		return limb
	if fallback.is_finite():
		return fallback + Vector3.DOWN * 0.35
	if body != null and is_instance_valid(body):
		return body.global_position + Vector3.DOWN * 0.35
	return Vector3.INF

func _kick_card(body: Node3D, forward: Vector3, fallback: Vector3, texture: Texture2D, size: Vector2, tint: Color, energy: float, roll_from: float, roll_to: float, travel: float, lift: float, life: float) -> void:
	var at := _kick_point(body, fallback)
	if not at.is_finite():
		return
	var mat := _additive_material(texture, tint, energy)
	mat.set_shader_parameter("reveal", 0.02)
	var slash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	slash.mesh = quad
	slash.material_override = mat
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slash)
	slash.rotation = Vector3(-0.22, atan2(-forward.x, -forward.z), roll_from)
	slash.global_position = at
	var sweep := create_tween().set_parallel(true)
	sweep.tween_property(slash, "rotation:z", roll_to, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sweep.tween_property(slash, "global_position", at + forward * travel + Vector3.UP * lift, life)
	sweep.tween_method(func(amount: float) -> void:
		mat.set_shader_parameter("reveal", amount)
	, 0.02, 1.0, life * 0.75)
	sweep.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 1.0, 0.0, life).set_delay(life * 0.35)
	sweep.chain().tween_callback(slash.queue_free)

func _kick_burst(body: Node3D, forward: Vector3, fallback: Vector3) -> void:
	var at := _kick_point(body, fallback)
	if not at.is_finite():
		return
	at += forward * 0.55
	var burst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.95, 0.7)
	burst.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = KICK_HIT
	mat.albedo_color = Color(1, 0.82, 0.45, 1)
	mat.emission_enabled = true
	mat.emission = Color("ffb15a")
	mat.emission_energy_multiplier = 1.3
	mat.emission_texture = KICK_HIT
	burst.material_override = mat
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(burst)
	burst.global_position = at
	burst.scale = Vector3(0.45, 0.45, 0.45)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(burst, "scale", Vector3(1.15, 1.15, 1.15), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.16)
	tween.chain().tween_callback(burst.queue_free)
	_dust(at + Vector3.DOWN * 0.15, 4, 0.4)

func attack_arc(at: Vector3, forward: Vector3, reach: float, color: Color, vertical := false) -> void:
	var texture: Texture2D = SLASH_PUNCH
	var size := Vector2(1.85, 0.95)
	var tilt := -0.38
	var energy := 2.4
	if vertical and color.b > color.r:
		texture = SLASH_UMBRELLA
		size = Vector2(2.45, 1.05)
		tilt = -0.62
		energy = 2.6
	elif vertical:
		texture = SLASH_UPPER
		size = Vector2(1.25, 2.25)
		tilt = -0.22
		energy = 2.5
	elif reach >= 1.25:
		texture = SLASH_KICK
		size = Vector2(2.7, 1.0)
		tilt = -0.22
	var scale := clampf(reach / 1.15, 0.9, 1.45)
	var kick := not vertical and reach >= 1.25
	var slash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size * scale
	slash.mesh = quad
	var tint := Color(color.r, color.g, color.b, 1.0)
	var mat := _additive_material(texture, tint, energy)
	mat.set_shader_parameter("reveal", 0.02)
	slash.material_override = mat
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slash)
	var yaw := atan2(-forward.x, -forward.z)
	slash.rotation = Vector3(tilt, yaw, -0.65 if not kick else 0.5)
	slash.global_position = at + forward * (0.2 if kick else 0.28)
	slash.scale = Vector3(0.84, 0.84, 0.84)
	var sweep := create_tween().set_parallel(true)
	sweep.tween_property(slash, "scale", Vector3(1.06, 1.06, 1.06), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sweep.tween_property(slash, "rotation:z", 0.42 if not kick else -0.38, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sweep.tween_property(slash, "global_position", at + forward * (0.72 if kick else 0.5), 0.14)
	sweep.tween_method(func(amount: float) -> void:
		mat.set_shader_parameter("reveal", amount)
	, 0.02, 1.0, 0.12)
	sweep.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 1.0, 0.0, 0.16).set_delay(0.06)
	sweep.chain().tween_callback(slash.queue_free)
	var right := forward.cross(Vector3.UP)
	if right.length_squared() > 0.0001:
		right = right.normalized()
		var tip_from := at + forward * 0.35 + right * (-0.45 if not kick else 0.15) + Vector3.UP * (0.05 if not kick else -0.02)
		var tip_to := at + forward * (0.85 if kick else 0.6) + right * (0.7 if kick else 0.55)
		_moving_spark(tip_from, tip_to, tint)

func dash_start() -> void:
	play_swing()
	dash_points.clear()
	dash_idle = 0.0

func blink_effect(start: Vector3, finish: Vector3) -> void:
	play_sound(SWING_SOUND, -4.0)
	var travel := finish - start
	var flat := Vector3(travel.x, 0.0, travel.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var length := flat.length()
	var mid := (start + finish) * 0.5 + Vector3.UP * 0.12
	var streak := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.orientation = QuadMesh.FACE_Y
	quad.size = Vector2(maxf(length, 0.8), 1.15)
	streak.mesh = quad
	var bolt: Texture2D = LIGHTNING_TEXTS[blink_lightning_index]
	blink_lightning_index = (blink_lightning_index + 1) % LIGHTNING_TEXTS.size()
	var tint := Color(1.0, 1.0, 1.0, 1.0)
	streak.material_override = _additive_material(bolt, tint, 2.4)
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)
	var travel_dir := flat.normalized()
	streak.global_transform = Transform3D(Basis(travel_dir, Vector3.UP, travel_dir.cross(Vector3.UP)), mid)
	var mat := streak.material_override as ShaderMaterial
	var tween := create_tween().set_parallel(true)
	tween.tween_property(streak, "scale", Vector3(1.05, 1.35, 1.0), 0.16)
	tween.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 1.0, 0.0, 0.18)
	tween.chain().tween_callback(streak.queue_free)
	for point in [start, finish]:
		_billboard(point + Vector3.UP * 0.2, SOFT_TEX, 0.7, Color(0.7, 0.95, 1.0), 2.4, 0.16)
		_dust(point + Vector3.UP * 0.05, 8, 0.7)

func dash_trail(at: Vector3) -> void:
	dash_idle = 0.0
	dash_points.push_front(at + Vector3.UP * 0.45)
	if dash_points.size() > 14:
		dash_points.pop_back()
	_rebuild_dash_ribbon()
	if dash_points.size() % 3 == 0:
		_dust(at, 5, 0.45)

func impact(at: Vector3, heavy := false, combo := 0, popup := "", direction := Vector3.ZERO) -> void:
	var power := (0.28 if heavy else 0.12) + minf(float(combo), 6.0) * 0.02
	camera_rig.add_shake(power)
	play_sound(HEAVY_SOUND if heavy else HIT_SOUND, 2.2 if heavy else -1.2)
	var color := Color("ffb15a") if heavy else Color("fff1b8")
	burst_flash(at, 0.42 if heavy else 0.26, Color("fffaf0"))
	burst_ring(at + Vector3.UP * 0.05, 0.32, 2.2 if heavy else 1.35, Color("fff6dc"))
	if heavy:
		burst_ring(at + Vector3.DOWN * 0.35, 0.42, 2.8, Color("ffd27a"))
	burst_slash(at, heavy)
	_sparks(at, 8 if heavy else 5, color, heavy, direction)
	_dust(at + Vector3.DOWN * 0.55, 10 if heavy else 5, 0.85 if heavy else 0.5)
	if popup != "":
		damage_popup(at, popup, heavy)

func burst_flash(at: Vector3, radius: float, color: Color) -> void:
	_billboard(at, SOFT_TEX, radius * 3.2, color, 3.2, 0.14)

func burst_ring(at: Vector3, _inner: float, end_scale: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	ring.mesh = quad
	var tint := Color(color.r, color.g, color.b, 1.0)
	ring.material_override = _additive_material(RING_TEX, tint, 2.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at
	ring.rotation.x = -PI * 0.5
	var mat := ring.material_override as ShaderMaterial
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * end_scale, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 0.9, 0.0, 0.22)
	tween.chain().tween_callback(ring.queue_free)

func burst_slash(at: Vector3, heavy: bool) -> void:
	var slash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35 if heavy else 0.9, 0.55 if heavy else 0.38)
	slash.mesh = quad
	var tint := Color(1.0, 0.95, 0.85, 1.0)
	slash.material_override = _additive_material(SLASH_PUNCH if heavy else SPARK_TEX, tint, 2.8)
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(slash)
	slash.global_position = at
	slash.rotation.y = randf() * TAU
	slash.rotation.z = randf_range(-0.6, 0.6)
	var mat := slash.material_override as ShaderMaterial
	var tween := create_tween().set_parallel(true)
	tween.tween_property(slash, "scale", Vector3(1.35, 0.7, 1.0), 0.08)
	tween.tween_method(func(alpha: float) -> void:
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))
	, 1.0, 0.0, 0.12)
	tween.chain().tween_callback(slash.queue_free)

func burst_spark(at: Vector3, color: Color, heavy: bool) -> void:
	_sparks(at, 4 if heavy else 2, color, heavy, Vector3.ZERO)

func damage_popup(at: Vector3, text: String, heavy: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64 if heavy else 48
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.modulate = Color("ffd27a") if heavy else Color("fff6d8")
	add_child(label)
	label.global_position = at + Vector3(randf_range(-0.15, 0.15), 0.15, 0.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(randf_range(-0.25, 0.25), 0.95, 0.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(label.queue_free)

func play_spin_fox(body: Node3D, forward := Vector3.ZERO) -> void:
	if body == null or not is_instance_valid(body):
		return
	var key := body.get_instance_id()
	if spin_spirits.has(key) and is_instance_valid(spin_spirits[key]):
		(spin_spirits[key] as FoxUmbrellaSpiritVFX).queue_free()
	var spirit := FOX_UMBRELLA_VFX.instantiate() as FoxUmbrellaSpiritVFX
	add_child(spirit)
	spirit.play(body, _spin_forward(body, forward))
	spin_spirits[key] = spirit

func spirit_hit(body: Node3D, at: Vector3) -> void:
	if body == null or not is_instance_valid(body):
		return
	var key := body.get_instance_id()
	if spin_spirits.has(key) and is_instance_valid(spin_spirits[key]):
		(spin_spirits[key] as FoxUmbrellaSpiritVFX).hit(at)

func spirit_hit_feedback(at: Vector3, popup := "") -> void:
	camera_rig.add_shake(0.18)
	play_sound(HEAVY_SOUND, -0.5)
	if popup != "":
		damage_popup(at, popup, true)

func _spin_forward(body: Node3D, forward: Vector3) -> Vector3:
	var flat := forward
	flat.y = 0.0
	if flat.length_squared() < 0.0001 and body != null and is_instance_valid(body) and body.get("spin_facing") != null:
		var yaw := float(body.spin_facing)
		flat = Vector3(-sin(yaw), 0.0, -cos(yaw))
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()

func body_ghost(source: Node3D, tint := Color(0.62, 0.88, 1.0, 0.42)) -> void:
	if ghost_wait > 0.0 or source == null or not is_instance_valid(source):
		return
	ghost_wait = 0.09
	var ghost := source.duplicate()
	ghost.set_script(null)
	ghost.name = "Afterimage"
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(ghost)
	ghost.global_transform = source.global_transform
	for node in ghost.find_children("*", "", true, false):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is AnimationTree:
			(node as AnimationTree).active = false
		elif node is AnimationPlayer:
			(node as AnimationPlayer).active = false
		elif node is MeshInstance3D and node.visible:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_color = tint
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			create_tween().tween_property(mat, "albedo_color:a", 0.0, 0.22)
	var done := create_tween()
	done.tween_interval(0.24)
	done.tween_callback(ghost.queue_free)

func effect_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.7
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func play_sound(sound: AudioStream, volume_db: float) -> void:
	var speaker := AudioStreamPlayer.new()
	speaker.stream = sound
	speaker.volume_db = volume_db
	add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()

func _additive_material(texture: Texture2D, tint: Color, energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ADDITIVE
	mat.set_shader_parameter("tex", texture)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("energy", energy)
	return mat

func _moving_spark(from: Vector3, to: Vector3, color: Color) -> void:
	var spark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	spark.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = SPARK_TEX
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.emission_texture = SPARK_TEX
	spark.material_override = mat
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spark)
	spark.global_position = from
	var tween := create_tween().set_parallel(true)
	tween.tween_property(spark, "global_position", to, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(spark, "scale", Vector3(1.4, 1.4, 1.4), 0.12)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tween.chain().tween_callback(spark.queue_free)

func _billboard(at: Vector3, texture: Texture2D, size: float, color: Color, energy: float, life: float) -> void:
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	sprite.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = texture
	mat.albedo_color = Color(color.r, color.g, color.b, 1.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.emission_texture = texture
	sprite.material_override = mat
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	sprite.global_position = at
	sprite.scale = Vector3(0.45, 0.45, 0.45)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector3.ONE, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, life)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, life)
	tween.chain().tween_callback(sprite.queue_free)

func _sparks(at: Vector3, amount: int, color: Color, heavy: bool, direction: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.34 if heavy else 0.26
	particles.explosiveness = 0.96
	particles.visibility_aabb = AABB(Vector3(-2.5, -2.5, -2.5), Vector3(5, 5, 5))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	var spray := direction
	if spray.length_squared() < 0.04:
		spray = Vector3(0.15, 0.45, 0.75)
	process.direction = spray.normalized()
	process.spread = 22.0 if heavy else 28.0
	process.initial_velocity_min = 1.4
	process.initial_velocity_max = 3.6 if heavy else 2.6
	process.gravity = Vector3(0, -4.5, 0)
	process.damping_min = 1.4
	process.damping_max = 2.8
	process.scale_min = 0.18
	process.scale_max = 0.42 if heavy else 0.3
	process.angle_min = -PI
	process.angle_max = PI
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(color.r, color.g, color.b, 1),
		Color(color.r, color.g * 0.45, color.b * 0.2, 0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	particles.draw_pass_1 = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = SPARK_TEX
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	mat.emission_texture = SPARK_TEX
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat
	add_child(particles)
	particles.global_position = at
	particles.restart()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

func _dust(at: Vector3, amount: int, size: float) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = 0.38
	particles.explosiveness = 0.9
	particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 2.5, 4))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, -1.2, 0)
	process.scale_min = size * 0.45
	process.scale_max = size
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(0.85, 0.78, 0.66, 0.55), Color(0.7, 0.64, 0.55, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	particles.draw_pass_1 = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = DUST_TEX
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat
	add_child(particles)
	particles.global_position = at
	particles.restart()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

func _rebuild_dash_ribbon() -> void:
	if dash_ribbon == null:
		dash_ribbon = MeshInstance3D.new()
		dash_ribbon.name = "DashRibbon"
		dash_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dash_ribbon.material_override = _additive_material(SLASH_KICK, Color(1.0, 0.72, 0.38, 0.85), 1.8)
		add_child(dash_ribbon)
	if dash_points.size() < 2:
		dash_ribbon.visible = false
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := dash_points.size()
	for index in count - 1:
		var current := to_local(dash_points[index])
		var nxt := to_local(dash_points[index + 1])
		var tangent := current - nxt
		tangent.y = 0.0
		if tangent.length_squared() < 0.0004:
			continue
		var side := tangent.normalized().cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized()
		var width_a := 0.34 * (1.0 - float(index) / count)
		var width_b := 0.34 * (1.0 - float(index + 1) / count)
		var u0 := float(index) / float(count - 1)
		var u1 := float(index + 1) / float(count - 1)
		var a := current + side * width_a
		var b := current - side * width_a
		var c := nxt + side * width_b
		var d := nxt - side * width_b
		_ribbon_vertex(surface, a, Vector2(u0, 0.0))
		_ribbon_vertex(surface, b, Vector2(u0, 1.0))
		_ribbon_vertex(surface, c, Vector2(u1, 0.0))
		_ribbon_vertex(surface, b, Vector2(u0, 1.0))
		_ribbon_vertex(surface, d, Vector2(u1, 1.0))
		_ribbon_vertex(surface, c, Vector2(u1, 0.0))
	dash_ribbon.mesh = surface.commit()
	dash_ribbon.visible = true

func _ribbon_vertex(surface: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(point)

func present_wind(source: Node3D, velocity: Vector3) -> void:
	if source == null or not is_instance_valid(source):
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var id := source.get_instance_id()
	if flat.length() < 2.4:
		return
	if not wind_trails.has(id):
		wind_trails[id] = {"points": [], "idle": 0.0, "meshes": []}
	var trail: Dictionary = wind_trails[id]
	trail.idle = 0.0
	var dir := flat.normalized()
	var sample := source.global_position - dir * 0.25
	var points: Array = trail.points
	if points.is_empty() or (points[0] as Vector3).distance_to(sample) > 0.16:
		points.push_front(sample)
		while points.size() > 7:
			points.pop_back()
	_rebuild_wind(trail, dir)

func _decay_wind(delta: float) -> void:
	var stale: Array[int] = []
	for id in wind_trails:
		var trail: Dictionary = wind_trails[id]
		trail.idle = float(trail.idle) + delta
		if float(trail.idle) <= 0.06:
			continue
		var points: Array = trail.points
		if not points.is_empty():
			points.pop_back()
		if points.size() < 2:
			_clear_wind(trail)
			stale.append(int(id))
		else:
			var newest: Vector3 = points[0]
			var older: Vector3 = points[mini(1, points.size() - 1)]
			var dir := newest - older
			dir.y = 0.0
			if dir.length_squared() < 0.0001:
				dir = Vector3.FORWARD
			_rebuild_wind(trail, dir.normalized())
	for id in stale:
		wind_trails.erase(id)

func _clear_wind(trail: Dictionary) -> void:
	for mesh in trail.meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	trail.meshes = []
	trail.points = []

func _rebuild_wind(trail: Dictionary, dir: Vector3) -> void:
	var points: Array = trail.points
	var meshes: Array = trail.meshes
	if meshes.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = _additive_material(WIND_TEX, Color(0.75, 0.9, 1.0, 0.28), 0.42)
		add_child(mesh)
		meshes.append(mesh)
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var strands := [
		{"height": -0.68, "lateral": 0.0, "width": 0.09},
	]
	for strand_index in strands.size():
		var strand: Dictionary = strands[strand_index]
		var mesh := meshes[strand_index] as MeshInstance3D
		if points.size() < 2:
			mesh.visible = false
			continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := points.size()
		var wrote := false
		for index in count - 1:
			var current: Vector3 = points[index]
			var nxt: Vector3 = points[index + 1]
			var tangent := current - nxt
			tangent.y = 0.0
			if tangent.length_squared() < 0.0004:
				continue
			var width_a := float(strand.width) * (1.0 - float(index) / count)
			var width_b := float(strand.width) * (1.0 - float(index + 1) / count)
			var lift := Vector3.UP * float(strand.height) + side * float(strand.lateral)
			var u0 := float(index) / float(count - 1)
			var u1 := float(index + 1) / float(count - 1)
			var a := to_local(current + lift + side * width_a)
			var b := to_local(current + lift - side * width_a)
			var c := to_local(nxt + lift + side * width_b)
			var d := to_local(nxt + lift - side * width_b)
			_ribbon_vertex(surface, a, Vector2(u0, 0.0))
			_ribbon_vertex(surface, b, Vector2(u0, 1.0))
			_ribbon_vertex(surface, c, Vector2(u1, 0.0))
			_ribbon_vertex(surface, b, Vector2(u0, 1.0))
			_ribbon_vertex(surface, d, Vector2(u1, 1.0))
			_ribbon_vertex(surface, c, Vector2(u1, 0.0))
			wrote = true
		if not wrote:
			mesh.visible = false
			continue
		mesh.mesh = surface.commit()
		mesh.visible = true

func _limb_world(body: Node3D, bone_name: String) -> Vector3:
	if body == null:
		return Vector3.INF
	var root := body.get_node_or_null("Visual")
	if root == null:
		return Vector3.INF
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return Vector3.INF
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.INF
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin

func _gust(at: Vector3, direction: Vector3, color: Color, amount: int) -> void:
	_sparks(at, maxi(amount, 1), color, false, direction)

func sample_limb(source: Node3D, bone_name: String, style: String) -> void:
	if source == null or not is_instance_valid(source):
		return
	var point := _limb_world(source, bone_name)
	if not point.is_finite():
		return
	var id := source.get_instance_id()
	if not limb_trails.has(id):
		limb_trails[id] = {"points": [], "idle": 0.0, "mesh": null, "tint": Color(1, 0.9, 0.7, 0.45)}
	var trail: Dictionary = limb_trails[id]
	trail.idle = 0.0
	var profile := _melee_profile(style)
	if not profile.is_empty():
		var tint: Color = profile.tint
		trail.tint = Color(tint.r, tint.g, tint.b, 0.4)
	var points: Array = trail.points
	if points.is_empty() or (points[0] as Vector3).distance_to(point) > 0.04:
		points.push_front(point)
		while points.size() > 5:
			points.pop_back()
	_rebuild_limb(trail)

func _decay_limb(delta: float) -> void:
	var stale: Array[int] = []
	for id in limb_trails:
		var trail: Dictionary = limb_trails[id]
		trail.idle = float(trail.idle) + delta
		if float(trail.idle) <= 0.04:
			continue
		var points: Array = trail.points
		if not points.is_empty():
			points.pop_back()
		if points.size() < 2:
			var mesh = trail.mesh
			if is_instance_valid(mesh):
				mesh.queue_free()
			stale.append(int(id))
		else:
			_rebuild_limb(trail)
	for id in stale:
		limb_trails.erase(id)

func _rebuild_limb(trail: Dictionary) -> void:
	var points: Array = trail.points
	var mesh := trail.mesh as MeshInstance3D
	if mesh == null or not is_instance_valid(mesh):
		mesh = MeshInstance3D.new()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tint: Color = trail.tint
		mesh.material_override = _additive_material(WIND_TEX, tint, 0.65)
		add_child(mesh)
		trail.mesh = mesh
	if points.size() < 2:
		mesh.visible = false
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := points.size()
	var wrote := false
	for index in count - 1:
		var current: Vector3 = points[index]
		var nxt: Vector3 = points[index + 1]
		var tangent := current - nxt
		if tangent.length_squared() < 0.00005:
			continue
		var side := tangent.normalized().cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var width_a := 0.045 * (1.0 - float(index) / count)
		var width_b := 0.045 * (1.0 - float(index + 1) / count)
		var u0 := float(index) / float(count - 1)
		var u1 := float(index + 1) / float(count - 1)
		var a := to_local(current + side * width_a)
		var b := to_local(current - side * width_a)
		var c := to_local(nxt + side * width_b)
		var d := to_local(nxt - side * width_b)
		_ribbon_vertex(surface, a, Vector2(u0, 0.0))
		_ribbon_vertex(surface, b, Vector2(u0, 1.0))
		_ribbon_vertex(surface, c, Vector2(u1, 0.0))
		_ribbon_vertex(surface, b, Vector2(u0, 1.0))
		_ribbon_vertex(surface, d, Vector2(u1, 1.0))
		_ribbon_vertex(surface, c, Vector2(u1, 0.0))
		wrote = true
	if not wrote:
		mesh.visible = false
		return
	mesh.mesh = surface.commit()
	mesh.visible = true
