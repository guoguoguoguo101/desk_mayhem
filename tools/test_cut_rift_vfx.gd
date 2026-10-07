extends SceneTree
const Rift = preload("res://vfx/mouse_cut_rift_burst.gd")
const VFX = preload("res://vfx/mouse_skill_vfx.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var effect := Rift.new()
	root.add_child(effect)
	effect.configure(Vector3.ZERO, Vector3(8,0,0))
	effect.set_process(false)
	assert(effect.materials.size() == 12)
	var first_mesh: ArrayMesh = effect.meshes[0].mesh
	var vertices: PackedVector3Array = first_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		assert(absf(vertex.z) < 0.25, "X must lie parallel to X travel, not across it")
	effect._process(0.1)
	assert(effect.meshes[0].mesh == first_mesh, "Animation must not rebuild meshes")
	assert(effect.debris.is_empty(), "No debris before original burst confirmation")
	effect.confirm_peak()
	assert(effect.debris.size() == 34)
	effect.confirm_peak()
	assert(effect.debris.size() == 34, "Peak confirmation must not duplicate debris")
	for i in 22: effect._process(0.016)
	var bounced := false
	for piece in effect.debris:
		if piece.rock and piece.bounce: bounced = true
	assert(bounced, "Some rocks must bounce during the short presentation")
	effect._process(0.1)
	assert(effect.is_queued_for_deletion(), "Effect must release its nodes and mesh references")
	var presenter := VFX.new()
	root.add_child(presenter)
	var path: Array = []
	for i in 9: path.append([Vector3(i,0.95,0),Vector3(i+1,0.95,0)])
	var state := {"kind":"player","position":Vector3(9,0.95,0),"action":"mouse_cut","action_tick":100,"life":1,"mouse_cut_path":path,"mouse_cut_start":Vector3(0,0.95,0),"mouse_cut_end":Vector3(8,0.95,0)}
	presenter.sync_world({"fox":state},112,0.016)
	assert(presenter.rift_bursts.is_empty(), "Do not anchor anticipation before travel finishes")
	state.mouse_cut_end = Vector3(9,0.95,0)
	presenter.sync_world({"fox":state},113,0.016)
	assert(presenter.rift_bursts.size() == 1)
	presenter.burst_cut(Vector3(0,0.95,0),Vector3(9,0.95,0))
	assert(presenter.rift_bursts.size() == 1, "Original burst must reuse the anticipated X, not spawn a second")
	assert(presenter.rift_bursts[0].confirmed)
	presenter.queue_free()
	print("CUT_RIFT_VFX: parallel plane, fixed meshes, event peak, single spawn, rock bounce and cleanup passed")
	quit()
