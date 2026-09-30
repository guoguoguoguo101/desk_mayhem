extends Node3D

@export var follow_speed := 9.0
@export var mouse_sensitivity := 0.006

@onready var player: CharacterBody3D = get_node("../Player")
@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D
@onready var camera: Camera3D = $PitchPivot/SpringArm3D/Shaker/Camera3D

const MIN_CAMERA_Y := 0.45
const AIM_UP_LIMIT := 42.0

var shake_amount := 0.0
var shake_clock := 0.0
var aim_pitch := 0.0
var alt_released_mouse := false
var preferred_spring_length := 5.5
var cut_focus_offset := Vector3.ZERO
var cut_focus_target := Vector3.ZERO
var cut_zoom := 0.0
var cut_zoom_target := 0.0
var cut_camera: Camera3D
var cut_cinematic_target: WeakRef
var cut_cinematic_start := Vector3.ZERO
var cut_cinematic_end := Vector3.ZERO
var cut_cinematic_age := 0.0
var cut_cinematic_duration := 0.0
var cut_cinematic_phase := ""
var cut_blend_age := 0.0
var cut_blend_from := Transform3D.IDENTITY
var window_mode_before_fullscreen := DisplayServer.WINDOW_MODE_WINDOWED
const CUT_ENTER_TIME := 0.12
const CUT_EXIT_TIME := 0.2

func _ready() -> void:
	global_position = player.global_position + Vector3.UP * 1.15
	preferred_spring_length = spring_arm.spring_length
	spring_arm.add_excluded_object(player.get_rid())
	cut_camera = Camera3D.new()
	cut_camera.name = "MouseCutCinematicCamera"
	cut_camera.top_level = true
	cut_camera.current = false
	cut_camera.fov = camera.fov
	cut_camera.cull_mask = camera.cull_mask
	cut_camera.near = camera.near
	cut_camera.far = camera.far
	add_child(cut_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		alt_released_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or (event.keycode != KEY_ALT and event.physical_keycode != KEY_ALT):
		return
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("has_menu_open") and net.has_menu_open():
		return
	if event.pressed:
		if not event.echo and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			alt_released_mouse = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif alt_released_mouse:
		alt_released_mouse = false
		if get_window().has_focus():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	var net := get_tree().get_first_node_in_group("network")
	if net and net.has_method("has_menu_open") and net.has_menu_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		if Engine.is_embedded_in_editor():
			return
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(window_mode_before_fullscreen)
		else:
			window_mode_before_fullscreen = DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		alt_released_mouse = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if Input.is_key_pressed(KEY_ALT) or alt_released_mouse:
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		rotation.y = player.get_node("Visual").rotation.y
		pitch_pivot.rotation.x = deg_to_rad(-30.0)
		aim_pitch = 0.0
		camera.rotation.x = 0.0
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_mouse_cut_cinematic_active():
			return
		rotation.y -= event.relative.x * mouse_sensitivity
		_add_pitch(-event.relative.y * mouse_sensitivity)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			preferred_spring_length = maxf(3.8, preferred_spring_length - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preferred_spring_length = minf(8.0, preferred_spring_length + 0.5)

func set_mouse_cut_focus(phase: String, start: Vector3, finish: Vector3) -> void:
	cut_focus_target = Vector3.ZERO
	cut_zoom_target = 0.0
	if phase == "travel":
		var direction := finish - start
		direction.y = 0.0
		if direction.length_squared() > 0.01:
			cut_focus_target = -direction.normalized() * 0.48 + Vector3.DOWN * 0.28
	elif phase == "burst":
		var midpoint := (start + finish) * 0.5
		cut_focus_target = (midpoint - player.global_position) * 0.36 + Vector3.UP * 0.18
		cut_focus_target = cut_focus_target.limit_length(2.1)
		cut_zoom_target = 1.2

func begin_mouse_cut_cinematic(start: Vector3, finish: Vector3, victim: Node3D, duration: float) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	cut_cinematic_start = start
	cut_cinematic_end = finish
	cut_cinematic_target = weakref(victim)
	cut_cinematic_age = 0.0
	cut_cinematic_duration = duration
	cut_cinematic_phase = "enter"
	cut_blend_age = 0.0
	cut_blend_from = camera.global_transform
	cut_camera.global_transform = cut_blend_from
	cut_camera.make_current()

func end_mouse_cut_cinematic() -> void:
	if cut_cinematic_phase == "" or cut_cinematic_phase == "exit":
		return
	cut_cinematic_phase = "exit"
	cut_blend_age = 0.0
	cut_blend_from = cut_camera.global_transform

func cancel_mouse_cut_cinematic() -> void:
	cut_cinematic_phase = ""
	cut_cinematic_duration = 0.0
	cut_cinematic_target = null
	camera.make_current()

func is_mouse_cut_cinematic_active() -> bool:
	return cut_cinematic_phase != ""

func _update_mouse_cut_cinematic(delta: float) -> void:
	if cut_cinematic_phase == "":
		return
	if cut_cinematic_phase == "exit":
		cut_blend_age += delta
		var exit_weight := smoothstep(0.0, 1.0, minf(1.0, cut_blend_age / CUT_EXIT_TIME))
		cut_camera.global_transform = cut_blend_from.interpolate_with(camera.global_transform, exit_weight)
		if exit_weight >= 1.0:
			cancel_mouse_cut_cinematic()
		return
	cut_cinematic_age += delta
	var target: Node3D = cut_cinematic_target.get_ref() if cut_cinematic_target != null else null
	if cut_cinematic_age >= cut_cinematic_duration or target == null or not is_instance_valid(target):
		end_mouse_cut_cinematic()
		return
	var direction := cut_cinematic_end - cut_cinematic_start
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = -global_transform.basis.z
		direction.y = 0.0
	direction = direction.normalized()
	var side := direction.cross(Vector3.UP)
	var middle := (cut_cinematic_start + cut_cinematic_end) * 0.5
	var target_position := target.global_position
	var rising := maxf(0.0, target_position.y - cut_cinematic_start.y)
	var desired := Transform3D.IDENTITY
	desired.origin = middle + side * 5.8 + direction * 2.6 + Vector3.UP * (2.2 + minf(rising * 0.22, 0.9))
	var focus := cut_cinematic_end * 0.3 + middle * 0.25 + target_position * 0.45 + Vector3.UP * 1.15
	desired = desired.looking_at(focus)
	if cut_cinematic_phase == "enter":
		cut_blend_age += delta
		var enter_weight := smoothstep(0.0, 1.0, minf(1.0, cut_blend_age / CUT_ENTER_TIME))
		cut_camera.global_transform = cut_blend_from.interpolate_with(desired, enter_weight)
		if enter_weight >= 1.0:
			cut_cinematic_phase = "hold"
	else:
		cut_camera.global_transform = cut_camera.global_transform.interpolate_with(desired, minf(1.0, delta * 8.0))

func _max_orbit_pitch() -> float:
	# Positive pitch swings the camera down. Stop before it crosses the floor.
	var drop := global_position.y - MIN_CAMERA_Y
	if drop <= 0.05:
		return 0.0
	return asin(clampf(drop / maxf(spring_arm.spring_length, 0.5), 0.0, 0.95))

func _add_pitch(delta_pitch: float) -> void:
	var orbit_max := _max_orbit_pitch()
	if delta_pitch > 0.0:
		var orbit_room := orbit_max - pitch_pivot.rotation.x
		var use_orbit := minf(delta_pitch, maxf(orbit_room, 0.0))
		pitch_pivot.rotation.x += use_orbit
		aim_pitch = clampf(aim_pitch + delta_pitch - use_orbit, 0.0, deg_to_rad(AIM_UP_LIMIT))
	else:
		var use_aim := minf(-delta_pitch, aim_pitch)
		aim_pitch -= use_aim
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x + delta_pitch + use_aim, deg_to_rad(-60.0), orbit_max)
	camera.rotation.x = aim_pitch

func _process(delta: float) -> void:
	cut_focus_offset = cut_focus_offset.lerp(cut_focus_target, minf(1.0, 9.0 * delta))
	cut_zoom = lerpf(cut_zoom, cut_zoom_target, minf(1.0, 8.0 * delta))
	spring_arm.spring_length = lerpf(spring_arm.spring_length, minf(8.8, preferred_spring_length + cut_zoom), minf(1.0, 9.0 * delta))
	global_position = global_position.lerp(player.global_position + Vector3.UP * 1.15 + cut_focus_offset, minf(1.0, follow_speed * delta))
	pitch_pivot.rotation.x = minf(pitch_pivot.rotation.x, _max_orbit_pitch())
	camera.rotation.x = aim_pitch
	shake_amount = maxf(0.0, shake_amount - delta * 3.2)
	shake_clock += delta * 57.0
	camera.position = Vector3(sin(shake_clock * 1.7), cos(shake_clock * 2.3), 0.0) * shake_amount * 0.12
	_update_mouse_cut_cinematic(delta)

func add_shake(amount: float) -> void:
	shake_amount = minf(0.55, shake_amount + amount)
