extends Node3D
class_name FoxUmbrellaSpiritVFX

## One fox, twelve drawn poses and a staged 3D flight path. This scene never
## changes combat timing or queries targets; hit() only queues a visual cue.
const END_TIME := 1.6
const HIT_CUE_TIME := 1.32
const FEET_OFFSET := Vector3.DOWN * 0.85

const FOX_FRAMES = [
	preload("res://assets/vfx/fox_umbrella/fox/fox_01_hide.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_02_emerge.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_03_crouch.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_04_jump.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_05_fly.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_06_turn.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_07_spin.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_08_dive.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_09_sweep.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_10_attack.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_11_tail_sweep.png"),
	preload("res://assets/vfx/fox_umbrella/fox/fox_12_dissolve.png"),
]
const POSE_TIMES = [0.18, 0.24, 0.33, 0.42, 0.54, 0.66, 0.76, 0.87, 0.98, 1.05, 1.15, 1.30]
const POSE_FACES_LEFT = [false, false, false, false, false, true, false, false, false, false, false, false]

# Coordinates are (character-right, height from feet, character-forward).
# Catmull-Rom interpolation gives a continuous non-circular route; each leg
# has its own duration and easing so the fox darts, hangs, dives and lunges.
const PATH_TIMES = [0.18, 0.30, 0.39, 0.51, 0.64, 0.76, 0.86, 0.98, 1.08, 1.18, 1.31]
const PATH_POINTS = [
	Vector3(-0.62, 0.78, -1.25),
	Vector3(-1.28, 1.02, -0.82),
	Vector3(-1.04, 0.82, -0.18),
	Vector3(1.00, 2.22, -0.55),
	Vector3(1.72, 2.38, 0.18),
	Vector3(1.45, 1.98, 1.20),
	Vector3(0.28, 1.53, 1.58),
	Vector3(-1.25, 0.68, 0.96),
	Vector3(1.18, 0.96, 1.48),
	Vector3(1.72, 1.18, 2.72),
	Vector3(1.84, 1.34, 3.18),
]

@onready var fox: Sprite3D = $SpiritRoot/FoxSpirit
@onready var trail_short: Sprite3D = $SpiritRoot/FoxTrailShort
@onready var trail_long: Sprite3D = $SpiritRoot/FoxTrailLong
@onready var tail_energy: Sprite3D = $SpiritRoot/FoxTailEnergy
@onready var glow: Sprite3D = $SpiritRoot/FoxGlow
@onready var wisp: Sprite3D = $SpiritRoot/GlowWisp
@onready var ring: Sprite3D = $SpinRing
@onready var sub_ring: Sprite3D = $SubRing
@onready var arc: Sprite3D = $EnergyArc
@onready var slash: Sprite3D = $EnergySlash
@onready var petal_a: Sprite3D = $Petals/PetalA
@onready var petal_b: Sprite3D = $Petals/PetalB
@onready var petal_swirl: Sprite3D = $Petals/PetalSwirl
@onready var spark_a: Sprite3D = $Sparks/SparkA
@onready var spark_b: Sprite3D = $Sparks/SparkB
@onready var hit_ring: Sprite3D = $HitRing
@onready var impact_flash: Sprite3D = $ImpactFlash
@onready var impact_burst: Sprite3D = $ImpactBurst

var follow_target: Node3D
var direction := Vector3.FORWARD
var right := Vector3.RIGHT
var age := 0.0
var active := false
var hit_queued := false
var hit_started := false
var hit_start := 0.0
var hit_position := Vector3.ZERO
var pose_index := -1
var cards: Array[Sprite3D] = []

func _ready() -> void:
	cards = [fox, trail_short, trail_long, tail_energy, glow, wisp, ring, sub_ring,
		arc, slash, petal_a, petal_b, petal_swirl, spark_a, spark_b,
		hit_ring, impact_flash, impact_burst]
	_setup(fox, FOX_FRAMES[0], 0.0100)
	_setup(trail_short, preload("res://assets/vfx/fox_umbrella/trail/fox_trail_short.png"), 0.0095)
	_setup(trail_long, preload("res://assets/vfx/fox_umbrella/trail/fox_trail_long.png"), 0.0110)
	_setup(tail_energy, preload("res://assets/vfx/fox_umbrella/trail/fox_tail_energy.png"), 0.0080)
	_setup(glow, preload("res://assets/vfx/fox_umbrella/glow/glow_soft.png"), 0.0120)
	_setup(wisp, preload("res://assets/vfx/fox_umbrella/glow/glow_wisp.png"), 0.0085)
	_setup(ring, preload("res://assets/vfx/fox_umbrella/energy/spin_ring.png"), 0.0190, false)
	_setup(sub_ring, preload("res://assets/vfx/fox_umbrella/energy/sub_ring.png"), 0.0085, false)
	_setup(arc, preload("res://assets/vfx/fox_umbrella/energy/energy_arc.png"), 0.0110)
	_setup(slash, preload("res://assets/vfx/fox_umbrella/energy/energy_slash.png"), 0.0090)
	_setup(petal_a, preload("res://assets/vfx/fox_umbrella/particles/petal_01.png"), 0.0060)
	_setup(petal_b, preload("res://assets/vfx/fox_umbrella/particles/petal_02.png"), 0.0055)
	_setup(petal_swirl, preload("res://assets/vfx/fox_umbrella/particles/petal_swirl.png"), 0.0080)
	_setup(spark_a, preload("res://assets/vfx/fox_umbrella/particles/spark_small.png"), 0.0065)
	_setup(spark_b, preload("res://assets/vfx/fox_umbrella/particles/spark_medium.png"), 0.0070)
	_setup(hit_ring, preload("res://assets/vfx/fox_umbrella/impact/hit_ring.png"), 0.0120, false)
	_setup(impact_flash, preload("res://assets/vfx/fox_umbrella/impact/impact_flash.png"), 0.0080)
	_setup(impact_burst, preload("res://assets/vfx/fox_umbrella/impact/impact_burst.png"), 0.0090)
	ring.rotation.x = -PI * 0.5
	sub_ring.rotation.x = -PI * 0.5
	hit_ring.rotation.x = -PI * 0.5
	reset()

func _setup(sprite: Sprite3D, texture: Texture2D, pixel_size: float, face_camera := true) -> void:
	sprite.texture = texture
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_camera else BaseMaterial3D.BILLBOARD_DISABLED
	sprite.transparent = true
	sprite.shaded = false
	sprite.double_sided = true
	sprite.no_depth_test = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.modulate = Color(1, 1, 1, 0)

func play(body: Node3D = null, forward: Vector3 = Vector3.FORWARD) -> void:
	reset()
	follow_target = body
	direction = Vector3(forward.x, 0, forward.z).normalized()
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	right = direction.cross(Vector3.UP).normalized()
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position + FEET_OFFSET
	active = true
	set_process(true)

func stop() -> void:
	reset()

func hit(at: Vector3 = Vector3.INF) -> void:
	if not active:
		return
	hit_queued = true
	hit_position = at if at.is_finite() else global_position + direction * 2.6 + Vector3.UP

func reset() -> void:
	active = false
	age = 0.0
	pose_index = -1
	hit_queued = false
	hit_started = false
	for sprite in cards:
		sprite.modulate = Color(1, 1, 1, 0)
	set_process(false)

func _process(delta: float) -> void:
	if not active:
		return
	age += delta
	if age >= END_TIME:
		reset()
		return
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position + FEET_OFFSET
	_show_rings()
	_show_fox()
	_show_trails()
	_show_accents()
	_show_attack()
	_show_hit()

func _show_rings() -> void:
	var fade := _window(0.08, 0.18, 1.10, 1.34)
	ring.position = Vector3(0, 0.10, 0)
	ring.scale = Vector3.ONE * lerpf(0.8, 1.0, smoothstep(0.08, 0.18, age))
	ring.rotation.y = age * TAU * 1.1
	ring.modulate.a = 0.43 * fade
	sub_ring.position = Vector3(0, 1.36, 0)
	sub_ring.scale = Vector3.ONE * (0.84 + 0.08 * sin(age * 9.0))
	sub_ring.rotation.y = -age * TAU * 0.8
	sub_ring.modulate.a = 0.19 * _window(0.12, 0.26, 0.96, 1.18)

func _show_fox() -> void:
	if age < 0.18:
		return
	var index := 0
	for i in POSE_TIMES.size():
		if age >= POSE_TIMES[i]:
			index = i
	if index != pose_index:
		pose_index = index
		fox.texture = FOX_FRAMES[index]
	var p := _path_at(age)
	var velocity := _path_at(minf(age + 0.012, 1.31)) - _path_at(maxf(age - 0.012, 0.18))
	var desired_left := _screen_motion_left(velocity)
	fox.flip_h = bool(POSE_FACES_LEFT[index]) != desired_left
	fox.position = _world_local(p)
	var depth_scale := clampf(1.0 - p.z * 0.09, 0.78, 1.14)
	var leap_scale := lerpf(0.72, 1.0, smoothstep(0.18, 0.40, age))
	fox.scale = Vector3.ONE * depth_scale * leap_scale
	fox.rotation.z = _screen_roll(velocity) * 0.35
	fox.modulate.a = 0.86 * _window(0.18, 0.34, 1.28, 1.47)
	if index == 11:
		fox.modulate.a *= 1.0 - smoothstep(1.32, 1.47, age)
	# Fox motion is genuinely in 3D. Depth testing lets the character occlude
	# the fox when it passes behind, while the billboard stays readable.

func _show_trails() -> void:
	var p := _path_at(age)
	var near := _path_at(maxf(0.18, age - 0.075))
	var far := _path_at(maxf(0.18, age - 0.16))
	var motion := p - near
	var speed := motion.length() / 0.075
	var motion_roll := _screen_roll(_world_local(p) - _world_local(near))
	var trail_alpha := _window(0.32, 0.47, 1.14, 1.36)
	trail_short.position = _world_local((p + near) * 0.5)
	trail_short.rotation.z = motion_roll
	trail_short.flip_h = fox.flip_h
	trail_short.scale = Vector3.ONE * clampf(speed / 7.0, 0.75, 1.20)
	trail_short.modulate.a = 0.37 * trail_alpha
	trail_long.position = _world_local((near + far) * 0.5)
	trail_long.rotation.z = motion_roll
	trail_long.flip_h = fox.flip_h
	trail_long.scale = Vector3.ONE * clampf(speed / 7.5, 0.72, 1.25)
	trail_long.modulate.a = 0.27 * trail_alpha * smoothstep(3.0, 7.0, speed)
	tail_energy.position = _world_local(near)
	tail_energy.flip_h = fox.flip_h
	tail_energy.modulate.a = 0.22 * trail_alpha
	glow.position = _world_local(p)
	glow.scale = Vector3.ONE * 0.85
	glow.modulate.a = 0.12 * _window(0.24, 0.42, 1.20, 1.43)
	wisp.position = _world_local(far)
	wisp.modulate.a = 0.10 * trail_alpha

func _show_accents() -> void:
	var p := _path_at(age)
	var accent := _window(0.50, 0.62, 1.04, 1.18)
	petal_a.position = _world_local(p + Vector3(-0.35, -0.25, 0.24))
	petal_b.position = _world_local(p + Vector3(0.42, 0.15, -0.18))
	petal_swirl.position = _world_local(p + Vector3(0.06, -0.38, 0.10))
	petal_a.modulate.a = 0.28 * accent
	petal_b.modulate.a = 0.22 * accent
	petal_swirl.modulate.a = 0.14 * accent
	spark_a.position = _world_local(p + Vector3(0.20, 0.12, 0.0))
	spark_a.modulate.a = 0.30 * _window(0.48, 0.60, 0.76, 0.86)
	spark_b.position = _world_local(p + Vector3(-0.22, -0.12, 0.12))
	spark_b.modulate.a = 0.24 * _window(0.90, 1.02, 1.12, 1.22)

func _show_attack() -> void:
	var strike := _window(1.04, 1.09, 1.17, 1.30)
	var p := _path_at(1.12)
	arc.position = _world_local(p + Vector3(0.10, 0.10, 0.28))
	arc.flip_h = fox.flip_h
	arc.modulate.a = 0.54 * strike
	slash.position = _world_local(_path_at(1.18))
	slash.flip_h = fox.flip_h
	slash.modulate.a = 0.45 * _window(1.10, 1.15, 1.21, 1.34)

func _show_hit() -> void:
	if not hit_queued or age < HIT_CUE_TIME:
		return
	if not hit_started:
		hit_started = true
		hit_start = age
	var elapsed := age - hit_start
	var pulse := smoothstep(0.0, 0.025, elapsed) * (1.0 - smoothstep(0.11, 0.19, elapsed))
	var local_hit := to_local(hit_position)
	hit_ring.position = Vector3(local_hit.x, 0.12, local_hit.z)
	hit_ring.scale = Vector3.ONE * lerpf(0.58, 1.12, clampf(elapsed / 0.19, 0, 1))
	hit_ring.modulate.a = 0.66 * pulse
	impact_flash.position = local_hit
	impact_flash.modulate.a = 0.62 * pulse
	impact_burst.position = local_hit
	impact_burst.modulate.a = 0.72 * pulse
	spark_a.position = local_hit + Vector3(0.22, 0.12, 0)
	spark_b.position = local_hit + Vector3(-0.16, -0.08, 0)
	spark_a.modulate.a = 0.55 * pulse
	spark_b.modulate.a = 0.42 * pulse

func _path_at(t: float) -> Vector3:
	if t <= PATH_TIMES[0]:
		return PATH_POINTS[0]
	if t >= PATH_TIMES[-1]:
		return PATH_POINTS[-1]
	for i in PATH_TIMES.size() - 1:
		if t > PATH_TIMES[i + 1]:
			continue
		var u: float = (t - PATH_TIMES[i]) / (PATH_TIMES[i + 1] - PATH_TIMES[i])
		if i in [0, 2, 7, 8]:
			u = pow(u, 1.35)
		elif i in [3, 6, 9]:
			u = 1.0 - pow(1.0 - u, 1.45)
		var a: Vector3 = PATH_POINTS[maxi(i - 1, 0)]
		var b: Vector3 = PATH_POINTS[i]
		var c: Vector3 = PATH_POINTS[i + 1]
		var d: Vector3 = PATH_POINTS[mini(i + 2, PATH_POINTS.size() - 1)]
		return 0.5 * ((2.0 * b) + (-a + c) * u +
			(2.0 * a - 5.0 * b + 4.0 * c - d) * u * u +
			(-a + 3.0 * b - 3.0 * c + d) * u * u * u)
	return PATH_POINTS[-1]

func _world_local(p: Vector3) -> Vector3:
	return right * p.x + Vector3.UP * p.y + direction * p.z

func _window(start: float, full: float, leave: float, end: float) -> float:
	return smoothstep(start, full, age) * (1.0 - smoothstep(leave, end, age))

func _screen_motion_left(motion: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and motion.dot(camera.global_basis.x) < -0.01

func _screen_roll(motion: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or motion.length_squared() < 0.0001:
		return 0.0
	var horizontal := motion.dot(camera.global_basis.x)
	var vertical := motion.dot(camera.global_basis.y)
	return clampf(atan2(vertical, horizontal), -0.85, 0.85)
