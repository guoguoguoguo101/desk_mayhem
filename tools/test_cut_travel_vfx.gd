extends SceneTree

const VFX = preload("res://vfx/mouse_skill_vfx.gd")
var effect: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	effect = VFX.new()
	root.add_child(effect)
	var source := Node3D.new()
	root.add_child(source)
	effect.set_cut_source("fox", source)
	var path: Array = []
	for i in 9: path.append([Vector3(i, 1, 0), Vector3(i + 1, 1, 0)])
	var state := {"kind":"player", "position":Vector3(9, 1, 0), "action":"mouse_cut", "action_tick":10, "life":1, "mouse_cut_path":path}
	effect.sync_world({"fox":state}, 22, 0.15)
	assert(effect.cut_tracks.fox.ghosts.size() == 3, "Skipped frames must generate all three ghosts")
	var old_ghost: Node3D = effect.cut_tracks.fox.ghosts[0].node
	path[3] = [Vector3(3, 1, 0), Vector3(4, 1, 0.25)]
	effect.sync_world({"fox":state}, 22, 0.016)
	assert(old_ghost.is_queued_for_deletion(), "Same-count coordinate correction must remove old visuals")
	assert(effect.cut_tracks.fox.path[3] == path[3])
	path.resize(3)
	effect.sync_world({"fox":state}, 22, 0.016)
	assert(effect.cut_tracks.fox.ghosts.size() == 1, "Wall/path rollback must remove untraveled ghosts")
	state.life = 2
	state.mouse_cut_path = []
	effect.sync_world({"fox":state}, 23, 0.016)
	assert(effect.cut_tracks.fox.ghosts.is_empty())
	state.dead = true
	effect.sync_world({"fox":state}, 24, 0.016)
	assert(not effect.cut_tracks.has("fox"))
	print("CUT_TRAVEL_VFX: skipped frames, coordinate correction, path rollback, life and death passed")
	quit()
