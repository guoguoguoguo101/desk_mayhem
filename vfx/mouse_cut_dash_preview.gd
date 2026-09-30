extends Node3D
## Runs the client-only X travel presentation in a loop. No battle world or hit rules.

const TRAVEL_SEGMENTS := 9
const TRAVEL_SECONDS := 0.15
const START := Vector3(-4.0, 0.95, 0.0)
const END := Vector3(4.0, 0.95, 0.0)

@export_range(0.1, 1.0, 0.05) var speed_scale := 0.2
@export var repeat_delay := 1.5

@onready var actor: Node3D = $Actor
@onready var fox_visual: Node3D = $Actor/FoxVisual
@onready var effect: Node3D = $MouseSkillVFX
@onready var camera: Camera3D = $Camera3D
@onready var instructions: Label = $CanvasLayer/Instructions

var elapsed := 0.0
var action_tick := 0
var path: Array = []
var running := false
var paused := false
var camera_yaw := 0.0
var camera_height := 3.3
var state: Dictionary = {}

func _ready() -> void:
	_replay()

func _process(delta: float) -> void:
	if paused:
		return
	elapsed += delta
	var finish_now := false
	if running:
		var duration := TRAVEL_SECONDS / speed_scale
		var progress := minf(elapsed / duration, 1.0)
		var required := mini(TRAVEL_SEGMENTS, int(floor(progress * TRAVEL_SEGMENTS)))
		actor.global_position = START.lerp(END, progress)
		while path.size() < required:
			var index := path.size()
			var from := START.lerp(END, float(index) / TRAVEL_SEGMENTS)
			var to := START.lerp(END, float(index + 1) / TRAVEL_SEGMENTS)
			path.append([from, to])
			if index % 2 == 1:
				effect.spawn_cut_ghost(actor, to - actor.global_position, to - from, index / 2)
		state.position = actor.global_position
		state.mouse_cut_path = path
		if progress >= 1.0:
			finish_now = true
	elif elapsed >= TRAVEL_SECONDS / speed_scale + repeat_delay:
		_replay()
	effect.sync_world({"preview_fox":state}, action_tick + path.size(), delta)
	if finish_now:
		running = false
		state.action = ""
		actor.rotation.x = 0.0
		_set_animation(&"Idle")

func _replay() -> void:
	action_tick += 100
	elapsed = 0.0
	path = []
	running = true
	actor.global_position = START
	actor.rotation = Vector3(-0.34, -PI * 0.5, 0.0)
	_set_animation(&"UmbrellaDash")
	state = {"kind":"player", "position":START, "action":"mouse_cut", "action_tick":action_tick, "mouse_cut_path":path}
	_update_label()

func _set_animation(name: StringName) -> void:
	var playback: AnimationNodeStateMachinePlayback = fox_visual.get("playback") as AnimationNodeStateMachinePlayback
	if playback != null:
		playback.travel(name)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_Q:
			get_tree().quit()
		KEY_E, KEY_SPACE:
			paused = false
			_replay()
		KEY_P:
			paused = not paused
			_update_label()
		KEY_1:
			speed_scale = 1.0
			_replay()
		KEY_2:
			speed_scale = 0.35
			_replay()
		KEY_3:
			speed_scale = 0.2
			_replay()
		KEY_4:
			speed_scale = 0.1
			_replay()
		KEY_A, KEY_LEFT:
			camera_yaw -= 0.16
			_update_camera()
		KEY_D, KEY_RIGHT:
			camera_yaw += 0.16
			_update_camera()
		KEY_W, KEY_UP:
			camera_height = minf(camera_height + 0.35, 7.0)
			_update_camera()
		KEY_S, KEY_DOWN:
			camera_height = maxf(camera_height - 0.35, 1.3)
			_update_camera()

func _update_camera() -> void:
	camera.position = Vector3(sin(camera_yaw) * 12.0, camera_height, cos(camera_yaw) * 12.0)
	camera.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)

func _update_label() -> void:
	var mode := "原速" if speed_scale >= 0.99 else "慢放 %.2fx" % speed_scale
	instructions.text = "X 穿梭预览｜循环播放｜%s%s｜Q 结束并保存录像｜E/空格 重播｜P 暂停｜1 原速 2 0.35× 3 0.2× 4 0.1×｜A/D 转视角｜W/S 调高低" % [mode, "（已暂停）" if paused else ""]
