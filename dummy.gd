extends CharacterBody3D

var hit_count := 0
var wobble_time := 0.0
var airborne := false
var airborne_lock := 0.0
var max_health := 100
var health := 100
var downed := false
var revive_time := 0.0

@onready var visual: Node3D = $Visual
@onready var hit_label: Label3D = $HitLabel
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var feedback: Node3D = get_node("../CombatFeedback")
@onready var player: CharacterBody3D = get_node("../Player")

var flash_material := StandardMaterial3D.new()

func _ready() -> void:
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.6, 0.2, 0.0)
	for part in visual.get_children():
		if part is MeshInstance3D:
			part.material_overlay = flash_material

func take_hit(attack_name: String = "文件夹") -> void:
	if downed:
		return
	hit_count += 1
	var damage: int = {
		"文件夹": 18, "雨伞": 12, "雨伞挑飞": 25,
		"地面踢飞": 22, "空中追踢": 32,
		"椅子": 28, "空中椅砸": 40,
	}.get(attack_name, 15)
	health = maxi(0, health - damage)
	hit_label.text = "%s -%d  |  HP %d/%d" % [attack_name, damage, health, max_health]
	hit_label.modulate = Color(1.0, 0.35, 0.26)
	wobble_time = 0.55
	var heavy := attack_name == "雨伞挑飞" or attack_name == "空中追踢" or attack_name == "椅子"
	feedback.impact(global_position + Vector3.UP * 1.2, heavy)
	player.hit_pause = maxf(player.hit_pause, 0.065 if heavy else 0.035)
	if health <= 0:
		knock_down()

func knock_down() -> void:
	downed = true
	airborne = false
	revive_time = 5.0
	velocity = Vector3.ZERO
	visual.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	visual.position.y = 0.35
	collision.shape = collision.shape.duplicate()
	collision.shape.height = 0.7
	collision.position.y = 0.35
	hit_label.text = "倒地 · 5 秒后复活"
	hit_label.modulate = Color(1.0, 0.25, 0.25)

func revive() -> void:
	downed = false
	health = max_health
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	collision.shape.height = 1.8
	collision.position.y = 1.0
	hit_label.text = "训练稻草人  |  HP %d/%d" % [health, max_health]
	hit_label.modulate = Color(1.0, 0.9, 0.56)

func launch_up(direction: Vector3) -> void:
	take_hit("雨伞挑飞")
	if downed:
		return
	velocity = direction * 2.5 + Vector3.UP * 8.5
	airborne = true
	airborne_lock = 0.2

func kick_from(direction: Vector3) -> void:
	if downed:
		return
	if airborne:
		take_hit("空中追踢")
		if downed:
			return
		velocity = direction * 13.0 + Vector3.UP * 3.2
		airborne_lock = 0.2
	else:
		take_hit("地面踢飞")
		if downed:
			return
		velocity = direction * 10.0 + Vector3.UP * 2.2
		airborne = true
		airborne_lock = 0.2

func spike_down(direction: Vector3) -> void:
	if downed:
		return
	take_hit("空中椅砸")
	if downed:
		return
	velocity = direction * 4.0 + Vector3.DOWN * 12.0
	airborne_lock = 0.2

func _physics_process(delta: float) -> void:
	airborne_lock = maxf(0.0, airborne_lock - delta)
	velocity.y -= 19.0 * delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	move_and_slide()
	if is_on_floor() and airborne_lock <= 0.0:
		airborne = false

func _process(delta: float) -> void:
	if downed:
		revive_time -= delta
		hit_label.text = "倒地 · %.1f 秒后复活" % maxf(0.0, revive_time)
		if revive_time <= 0.0:
			revive()
		return
	if wobble_time > 0.0:
		wobble_time -= delta
		visual.rotation.z = sin(wobble_time * 35.0) * wobble_time * 0.65
		visual.scale = Vector3.ONE * (1.0 + sin(wobble_time * 25.0) * 0.08)
		flash_material.albedo_color = Color(1.0, 0.65, 0.2, minf(0.7, wobble_time * 2.5))
	else:
		visual.rotation.z = 0.0
		visual.scale = Vector3.ONE
		hit_label.modulate = Color(1.0, 0.9, 0.56)
		flash_material.albedo_color.a = 0.0
