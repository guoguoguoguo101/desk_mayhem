extends Node3D
## Presentation for the mountain battle world's mouse weapon. Never feeds simulation.

var views: Dictionary = {}
var bursts: Array = []
var clock := 0.0

func _glow(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.5
	material.no_depth_test = false
	return material

func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.38
	material.roughness = 0.24
	material.emission_enabled = true
	material.emission = color * 0.48
	material.emission_energy_multiplier = 1.8
	return material

func _tube(parent: Node3D, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 10
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual

func _sphere(parent: Node3D, radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	parent.add_child(visual)
	return visual

func _beam(visual: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var delta := finish - start
	if delta.length_squared() < 0.0001:
		visual.visible = false
		return
	visual.visible = true
	visual.global_position = (start + finish) * 0.5
	visual.quaternion = Quaternion(Vector3.UP, delta.normalized())
	visual.scale = Vector3(1.0, delta.length(), 1.0)

func _make_mouse() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var shell := _sphere(root, 0.23, _solid(Color(0.12, 0.23, 0.34)))
	shell.scale = Vector3(0.85, 0.55, 1.4)
	_box(root, Vector3(0.16, 0.025, 0.22), Vector3(-0.09, 0.13, -0.1), _solid(Color(0.62, 0.96, 1.0)))
	_box(root, Vector3(0.16, 0.025, 0.22), Vector3(0.09, 0.13, -0.1), _solid(Color(0.21, 0.84, 1.0)))
	_box(root, Vector3(0.055, 0.075, 0.09), Vector3(0, 0.17, -0.11), _glow(Color(1.0, 0.93, 0.66)))
	var side := _sphere(root, 0.11, _glow(Color(0.18, 0.92, 1.0), 0.55))
	side.position = Vector3(0, -0.035, 0.13)
	side.scale = Vector3(1.8, 0.55, 0.55)
	var halo := _sphere(root, 0.25, _glow(Color(0.18, 0.82, 1.0), 0.18))
	halo.scale = Vector3(1.2, 0.8, 1.7)
	return root

func _make_view() -> Dictionary:
	var mouse := _make_mouse()
	var outer := _tube(self, 0.17, _glow(Color(0.05, 0.75, 1.0), 0.25))
	var mid := _tube(self, 0.105, _glow(Color(0.1, 0.94, 1.0), 0.58))
	var core := _tube(self, 0.045, _glow(Color(0.95, 1.0, 1.0), 0.98))
	var cut_outer := _tube(self, 0.21, _glow(Color(0.36, 0.35, 1.0), 0.25))
	var cut_core := _tube(self, 0.07, _glow(Color(0.63, 1.0, 1.0), 0.82))
	cut_outer.visible = false
	cut_core.visible = false
	var beads: Array = []
	for _i in 4:
		beads.append(_sphere(self, 0.075, _glow(Color(0.81, 1.0, 1.0), 0.82)))
	var marker := Node3D.new()
	add_child(marker)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			_box(marker, Vector3(0.27, 0.035, 0.035), Vector3(x*0.35, y*0.34, 0), _glow(Color(0.67, 1.0, 1.0)))
			_box(marker, Vector3(0.035, 0.27, 0.035), Vector3(x*0.35, y*0.34, 0), _glow(Color(0.67, 1.0, 1.0)))
	marker.visible = false
	return {"mouse":mouse,"outer":outer,"mid":mid,"core":core,"cut_outer":cut_outer,"cut_core":cut_core,"beads":beads,"marker":marker}

func sync_world(entities: Dictionary, tick: int, delta: float) -> void:
	clock += delta
	var active := {}
	for id in entities.keys():
		var state: Dictionary = entities[id]
		if str(state.get("kind", "")) != "player":
			continue
		active[id] = true
		if not views.has(id): views[id] = _make_view()
		var view: Dictionary = views[id]
		var flight: Dictionary = state.get("mouse_projectile", {})
		var linked_id := str(state.get("mouse_link_id", ""))
		var linked := not linked_id.is_empty() and entities.has(linked_id) and tick < int(state.get("mouse_link_until", 0))
		var endpoint := Vector3.ZERO
		if not flight.is_empty():
			endpoint = flight.position
		elif linked:
			endpoint = entities[linked_id].position + Vector3.UP * 0.55
		var show_line := not flight.is_empty() or linked
		view.mouse.visible = show_line
		view.marker.visible = linked
		if show_line:
			var origin: Vector3 = state.position + Vector3.UP * 0.48
			view.mouse.global_position = endpoint
			view.mouse.rotation = Vector3(sin(clock*15.0)*0.18, clock*5.0, cos(clock*11.0)*0.14)
			view.mouse.scale = Vector3.ONE * (1.25 + sin(clock*18.0)*0.08)
			for segment in [view.outer, view.mid, view.core]: _beam(segment, origin, endpoint)
			for i in view.beads.size():
				var bead: Node3D = view.beads[i]
				bead.visible = true
				bead.global_position = origin.lerp(endpoint, fposmod(clock*1.85 + float(i)*0.25, 1.0))
				bead.scale = Vector3.ONE * (0.7 + sin(clock*20.0 + float(i))*0.22)
			if linked:
				view.marker.global_position = entities[linked_id].position + Vector3.UP * 1.1
				view.marker.rotation.y = clock*0.9
		else:
			for segment in [view.outer, view.mid, view.core]: segment.visible = false
			for bead in view.beads: bead.visible = false
		var cutting := str(state.get("action", "")) == "mouse_cut" and tick - int(state.get("action_tick", tick)) >= 4
		if cutting:
			var start: Vector3 = state.get("mouse_cut_start", state.position) + Vector3.UP * 0.75
			var finish: Vector3 = state.get("mouse_cut_end", state.position) + Vector3.UP * 0.75
			_beam(view.cut_outer, start, finish)
			_beam(view.cut_core, start, finish)
		else:
			view.cut_outer.visible = false
			view.cut_core.visible = false
	for id in views.keys():
		if active.has(id): continue
		var old: Dictionary = views[id]
		for node in [old.mouse, old.outer, old.mid, old.core, old.cut_outer, old.cut_core, old.marker]: node.queue_free()
		for bead in old.beads: bead.queue_free()
		views.erase(id)
	for burst in bursts.duplicate():
		burst.age = float(burst.age) + delta
		var fraction := float(burst.age) / float(burst.duration)
		if fraction >= 1.0:
			burst.node.queue_free()
			bursts.erase(burst)
		else:
			burst.node.scale = Vector3.ONE * (0.5 + 1.2 * minf(1.0, fraction*4.0))
			for child in burst.node.get_children():
				if child is GeometryInstance3D: child.transparency = clampf(fraction*fraction, 0.0, 1.0)

func _burst_group(duration := 0.5) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	bursts.append({"node":root,"age":0.0,"duration":duration})
	return root

func _burst_beam(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, alpha := 0.85) -> void:
	var tube := _tube(root, radius, _glow(color, alpha))
	_beam(tube, a, b)

func burst_link(at: Vector3) -> void:
	var root := _burst_group(0.42)
	root.global_position = at
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_burst_beam(root, at-axis*0.7, at+axis*0.7, 0.075, Color(0.55, 1.0, 1.0))
	_sphere(root, 0.35, _glow(Color(0.15, 0.86, 1.0), 0.55)).global_position = at

func burst_swap(a: Vector3, b: Vector3) -> void:
	for at in [a, b]:
		var root := _burst_group(0.48)
		var center: Vector3 = at + Vector3.UP * 0.85
		root.global_position = center
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			_burst_beam(root, center-axis*0.8-Vector3.UP*0.7, center+axis*0.8+Vector3.UP*0.7, 0.15, Color(0.14, 0.9, 1.0), 0.8)
			_burst_beam(root, center-axis*0.8+Vector3.UP*0.7, center+axis*0.8-Vector3.UP*0.7, 0.08, Color(1.0, 0.95, 0.75))
	var bridge := _burst_group(0.28)
	bridge.global_position = (a+b)*0.5 + Vector3.UP
	_burst_beam(bridge, a+Vector3.UP, b+Vector3.UP, 0.2, Color(0.67, 1.0, 1.0))

func burst_cut(a: Vector3, b: Vector3) -> void:
	var root := _burst_group(0.62)
	var forward := b-a
	forward.y = 0.0
	if forward.length_squared() < 0.001: forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var center := (a+b)*0.5 + Vector3.UP * 1.25
	root.global_position = center
	for diagonal in [right*2.25+Vector3.UP*1.85, right*2.25-Vector3.UP*1.85]:
		_burst_beam(root, center-diagonal, center+diagonal, 0.31, Color(0.16, 0.58, 1.0), 0.34)
		_burst_beam(root, center-diagonal, center+diagonal, 0.16, Color(0.36, 0.95, 1.0), 0.78)
		_burst_beam(root, center-diagonal, center+diagonal, 0.055, Color(1.0, 1.0, 0.95))
	_burst_beam(root, a+Vector3.UP, b+Vector3.UP, 0.2, Color(0.4, 0.89, 1.0), 0.85)
	for i in 9:
		var spark := _sphere(root, 0.09, _glow(Color(0.72, 1.0, 1.0), 0.9))
		spark.global_position = center + right * sin(float(i)*2.4)*2.4 + Vector3.UP * cos(float(i)*1.7)*1.8 + forward * sin(float(i)*3.1)*0.35
