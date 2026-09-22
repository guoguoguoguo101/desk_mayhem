extends Node3D

@export var follow_speed := 9.0
@export var mouse_sensitivity := 0.006

@onready var player: CharacterBody3D = get_node("../Player")
@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D
@onready var camera: Camera3D = $PitchPivot/SpringArm3D/Shaker/Camera3D

var shake_amount := 0.0
var shake_clock := 0.0

func _ready() -> void:
	global_position = player.global_position + Vector3.UP * 1.15
	spring_arm.add_excluded_object(player.get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("has_menu_open") and net.has_menu_open():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		rotation.y = player.get_node("Visual").rotation.y
		pitch_pivot.rotation.x = deg_to_rad(-30.0)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		pitch_pivot.rotation.x = clampf(
			pitch_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-60.0), deg_to_rad(40.0)
		)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = maxf(3.8, spring_arm.spring_length - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = minf(8.0, spring_arm.spring_length + 0.5)

func _process(delta: float) -> void:
	global_position = global_position.lerp(player.global_position + Vector3.UP * 1.15, minf(1.0, follow_speed * delta))
	shake_amount = maxf(0.0, shake_amount - delta * 3.2)
	shake_clock += delta * 57.0
	camera.position = Vector3(sin(shake_clock * 1.7), cos(shake_clock * 2.3), 0.0) * shake_amount * 0.12

func add_shake(amount: float) -> void:
	shake_amount = minf(0.55, shake_amount + amount)
