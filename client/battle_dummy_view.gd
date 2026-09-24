extends Node3D
## Presentation only: no hit detection, physics, AI or local respawn timer.
var visual: Node3D
var label: Label3D
var target := Vector3.ZERO
var life := 0
var health := 0
var flinch_time := 0.0
var tilt := 0.0
var juggled := false
var chase := true

func setup(template: Node3D) -> void:
	visual = template.get_node("Visual").duplicate()
	add_child(visual)
	visual.position.y -= 0.9
	label = Label3D.new()
	label.position.y = 2.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	add_child(label)

func apply_snapshot(state: Dictionary) -> void:
	var p: Array = state.position
	target = Vector3(p[0],p[1],p[2])
	if life != int(state.life):
		global_position = target
		flinch_time = 0
	life = int(state.life)
	health = int(state.health)
	var dead := bool(state.dead)
	var grounded := float(state.get("knockdown_time",0))>0 or (float(state.get("protection",0))>0 and float(state.get("stun",0))>0)
	juggled = bool(state.get("juggled", false)) and not dead and not grounded
	tilt = PI/2 if dead or grounded else (0.35 if juggled else 0.0)
	label.text = "训练稻草人  %d/%d" % [health,int(state.max_health)]
	if dead:
		label.text += "\n%.1f 秒后复活" % (float(state.respawn_ms)/1000.0)
	elif bool(state.juggled):
		label.text += " · 浮空"
	elif grounded:
		label.text += " · 倒地"
	elif float(state.get("stun",0))>0:
		label.text += " · 受击硬直"

func _process(delta: float) -> void:
	if chase:
		global_position = global_position.lerp(target,1.0-exp(-16.0*delta))
	flinch_time = maxf(0,flinch_time-delta)
	visual.rotation.z = lerp_angle(visual.rotation.z,tilt+flinch_time,clampf(delta*16,0,1))
	# Lift the foot pivot as the model lies down, instead of rotating into the floor.
	visual.position.y = -0.84+0.64*absf(sin(visual.rotation.z))
