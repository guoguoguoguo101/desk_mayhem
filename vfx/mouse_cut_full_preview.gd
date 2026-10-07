extends Node3D
## A looping recording stage for the visual sequence of Mouse Cut. No combat rules run.

const BattleRules = preload("res://combat/battle_rules.gd")
const START := Vector3(-4.0, 0.95, 0.0)
const END := Vector3(4.0, 0.95, 0.0)
const TICK := 1.0 / 60.0
const TRAVEL_START := BattleRules.MOUSE_CUT_STARTUP * TICK
const TRAVEL_END := (BattleRules.MOUSE_CUT_STARTUP + BattleRules.MOUSE_CUT_TRAVEL_TICKS) * TICK
const BURST_AT := BattleRules.MOUSE_CUT_DAMAGE_TICK * TICK
const ACTION_END := BattleRules.MOUSE_CUT_END_TICK * TICK
const LAUNCH_AT := BURST_AT + BattleRules.MOUSE_AIR_HOLD
const RESET_AT := LAUNCH_AT + 1.0

@export_range(0.1, 1.0, 0.05) var speed_scale := 0.35
@export var auto_loop := true

@onready var actor: Node3D = $Actor
@onready var fox_visual: Node3D = $Actor/FoxVisual
@onready var dummy: Node3D = $StrawDummy
@onready var dummy_visual: Node3D = $StrawDummy/DummyVisual
@onready var effect: Node3D = $MouseSkillVFX
@onready var camera: Camera3D = $Camera3D
@onready var canvas: CanvasLayer = $CanvasLayer
@onready var instructions: Label = $CanvasLayer/Instructions

var elapsed := 0.0
var action_tick := 0
var path: Array = []
var state: Dictionary = {}
var burst_played := false
var paused := false
var cinematic_camera := true
var camera_yaw := 0.0
var camera_height := 3.0
var dummy_label: Label3D

func _ready() -> void:
	_build_dummy()
	_set_speed(speed_scale)
	_replay()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	if paused:
		return
	elapsed += delta
	var travel_progress := clampf((elapsed - TRAVEL_START) / (TRAVEL_END - TRAVEL_START), 0.0, 1.0)
	actor.global_position = START.lerp(END, travel_progress)
	actor.rotation.x = -0.34 if elapsed >= TRAVEL_START and elapsed < TRAVEL_END else 0.0
	fox_visual.mouse_cut_pose = elapsed >= TRAVEL_START and elapsed < TRAVEL_END
	var required := mini(BattleRules.MOUSE_CUT_TRAVEL_TICKS, int(floor(travel_progress * BattleRules.MOUSE_CUT_TRAVEL_TICKS)))
	while path.size() < required:
		var index := path.size()
		var from := START.lerp(END, float(index) / BattleRules.MOUSE_CUT_TRAVEL_TICKS)
		var to := START.lerp(END, float(index + 1) / BattleRules.MOUSE_CUT_TRAVEL_TICKS)
		path.append([from, to])
	state.position = actor.global_position
	state.mouse_cut_path = path
	state.action = "mouse_cut" if elapsed < ACTION_END else ""
	effect.set_cut_source("preview_fox", actor)
	state.mouse_cut_end = actor.global_position
	effect.sync_world({"preview_fox":state}, action_tick + int(elapsed / TICK), delta)
	if elapsed >= BURST_AT and not burst_played:
		burst_played = true
		# The stage puts the fox's body origin at 0.95 m; the burst is grounded.
		effect.burst_cut(START, END)
	_animate_dummy()
	_update_camera(delta)
	if auto_loop and elapsed >= RESET_AT:
		_replay()

func _replay() -> void:
	action_tick += 100
	elapsed = 0.0
	path = []
	burst_played = false
	actor.global_position = START
	actor.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	dummy.global_position = Vector3.ZERO
	dummy_visual.rotation = Vector3.ZERO
	dummy_visual.scale = Vector3.ONE
	state = {"kind":"player", "position":START, "action":"mouse_cut", "action_tick":action_tick, "mouse_cut_path":path,"mouse_cut_start":START,"mouse_cut_end":START}
	_set_animation(&"UmbrellaDash")
	_update_label()

func _animate_dummy() -> void:
	if elapsed < BURST_AT:
		return
	if elapsed < LAUNCH_AT:
		var hold := (elapsed - BURST_AT) / BattleRules.MOUSE_AIR_HOLD
		dummy_visual.rotation.z = sin(hold * 35.0) * 0.08 * (1.0 - hold)
		dummy_visual.scale = Vector3(1.0 + sin(hold * 25.0) * 0.035, 1.0 - sin(hold * 25.0) * 0.045, 1.0)
		return
	var flight := clampf((elapsed - LAUNCH_AT) / 0.72, 0.0, 1.0)
	dummy.global_position.y = sin(flight * PI) * 2.2
	dummy_visual.rotation.z = 0.37 * sin(flight * PI)
	dummy_visual.scale = Vector3.ONE

func _set_animation(name: StringName) -> void:
	var playback: AnimationNodeStateMachinePlayback = fox_visual.get("playback") as AnimationNodeStateMachinePlayback
	if playback != null:
		playback.travel(name)

func _set_speed(value: float) -> void:
	speed_scale = value
	Engine.time_scale = 0.0 if paused else speed_scale
	_update_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.fov = maxf(15.0, camera.fov / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.fov = minf(90.0, camera.fov * 1.12)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_Q:
			get_tree().quit()
		KEY_E, KEY_SPACE:
			paused = false
			Engine.time_scale = speed_scale
			_replay()
		KEY_P:
			paused = not paused
			Engine.time_scale = 0.0 if paused else speed_scale
			_update_label()
		KEY_1, KEY_2, KEY_3, KEY_4:
			var speeds := {KEY_1:1.0, KEY_2:0.35, KEY_3:0.2, KEY_4:0.1}
			_set_speed(float(speeds[event.physical_keycode]))
			_replay()
		KEY_C:
			cinematic_camera = not cinematic_camera
			_update_label()
		KEY_H:
			canvas.visible = not canvas.visible
			dummy_label.visible = canvas.visible
		KEY_L:
			auto_loop = not auto_loop
			_update_label()
		KEY_A, KEY_LEFT:
			camera_yaw -= 0.16
		KEY_D, KEY_RIGHT:
			camera_yaw += 0.16
		KEY_W, KEY_UP:
			camera_height = minf(camera_height + 0.35, 7.0)
		KEY_S, KEY_DOWN:
			camera_height = maxf(camera_height - 0.35, 1.3)

func _update_camera(delta: float) -> void:
	var wide := Vector3(sin(camera_yaw) * 8.5, camera_height, cos(camera_yaw) * 8.5)
	var focus := cinematic_camera and elapsed >= BURST_AT and elapsed < LAUNCH_AT + 0.28
	var target_position := Vector3(1.8, 2.15, 5.7) if focus else wide
	var weight := 1.0 - exp(-8.0 * delta / maxf(speed_scale, 0.1))
	camera.global_position = camera.global_position.lerp(target_position, weight)
	camera.look_at(Vector3(0.0, 1.45, 0.0) if focus else Vector3(0.0, 0.9, 0.0), Vector3.UP)

func _update_label() -> void:
	if not is_instance_valid(instructions):
		return
	var mode := "原速" if speed_scale >= 0.99 else "%.2f×" % speed_scale
	instructions.text = "X 完整技能｜%s%s｜Q 结束并保存录像｜E/空格 重播 P 暂停｜1 原速 2 0.35× 3 0.2× 4 0.1×｜C 镜头 H 隐藏文字 L 循环｜滚轮 缩放｜A/D/W/S 调视角" % [mode, "（已暂停）" if paused else ""]

func _build_dummy() -> void:
	_add_mesh(CylinderMesh.new(), Vector3(0.0, 0.87, 0.0), Vector3(0.11, 0.9, 0.11), Color(0.3, 0.2, 0.13))
	_add_mesh(BoxMesh.new(), Vector3(0.0, 1.05, 0.0), Vector3(0.72, 0.9, 0.38), Color(0.66, 0.51, 0.31))
	_add_mesh(BoxMesh.new(), Vector3(0.0, 1.38, 0.0), Vector3(1.65, 0.12, 0.14), Color(0.43, 0.28, 0.16))
	_add_mesh(SphereMesh.new(), Vector3(0.0, 1.77, 0.0), Vector3(0.62, 0.66, 0.56), Color(0.78, 0.65, 0.4))
	for side in [-1.0, 1.0]:
		_add_mesh(SphereMesh.new(), Vector3(side * 0.87, 1.37, 0.0), Vector3(0.5, 0.32, 0.38), Color(0.83, 0.69, 0.38))
		_add_mesh(BoxMesh.new(), Vector3(side * 0.18, 1.78, 0.29), Vector3(0.1, 0.12, 0.035), Color(0.1, 0.11, 0.13))
	_add_mesh(BoxMesh.new(), Vector3(0.0, 1.7, 0.29), Vector3(0.16, 0.06, 0.035), Color(0.1, 0.11, 0.13))
	var target := TorusMesh.new()
	target.inner_radius = 0.15
	target.outer_radius = 0.18
	var ring := _add_mesh(target, Vector3(0.0, 1.05, 0.23), Vector3.ONE, Color(0.2, 0.85, 1.0))
	ring.rotation.x = PI * 0.5
	dummy_label = Label3D.new()
	dummy_label.text = "训练稻草人"
	dummy_label.position = Vector3(0.0, 2.35, 0.0)
	dummy_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dummy_label.font_size = 32
	dummy_visual.add_child(dummy_label)

func _add_mesh(mesh: Mesh, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.scale = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	dummy_visual.add_child(node)
	return node
