extends Node3D

@onready var actor: Node3D = $Actor
@onready var visual: Node3D = $Actor/FoxVisual
@onready var effect: FoxUmbrellaSpiritVFX = $FoxUmbrellaSpiritVFX
@onready var camera: Camera3D = $Camera3D

var spin_age := 0.0
var camera_yaw := 0.55
var camera_pitch := 0.0

func _ready() -> void:
	camera.look_at(Vector3(0, 0.9, 0))
	play_preview()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E, KEY_SPACE:
			play_preview()
		KEY_H:
			effect.hit(actor.global_position + Vector3(1.2, 0, -2.6))
		KEY_R:
			effect.stop()
			spin_age = 0.0
			visual.rotation.y = 0.0

func play_preview() -> void:
	visual.rotation.y = 0.0
	spin_age = 0.0
	effect.play(actor, Vector3.FORWARD)
	effect.hit(actor.global_position + Vector3(1.2, 0, -2.6))

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		camera_yaw -= delta * 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		camera_yaw += delta * 1.0
	if Input.is_key_pressed(KEY_UP):
		camera_pitch = clampf(camera_pitch + delta * 0.6, -0.25, 0.6)
	if Input.is_key_pressed(KEY_DOWN):
		camera_pitch = clampf(camera_pitch - delta * 0.6, -0.25, 0.6)
	camera.position = Vector3(sin(camera_yaw) * 5.2, 2.6 + camera_pitch * 2.0, cos(camera_yaw) * 5.2)
	camera.look_at(Vector3(0, 0.9, 0))
	if effect.active and spin_age < 0.55:
		spin_age = minf(spin_age + delta, 0.55)
		visual.rotation.y = spin_age / 0.55 * TAU * 2.0
