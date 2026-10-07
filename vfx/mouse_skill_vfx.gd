extends Node3D
## Presentation for the mountain battle world's mouse weapon. Never feeds simulation.
const RIBBON_SHADER = preload("res://vfx/mouse_cut_ribbon.gdshader")
const ENERGY_SHADER = preload("res://vfx/mouse_cut_energy.gdshader")
const GHOST_SHADER = preload("res://vfx/mouse_cut_ghost.gdshader")
const STREAK_SHADER = preload("res://vfx/mouse_cut_streaks.gdshader")
const PIXEL_TEXTURE = preload("res://assets/vfx/mouse_cut_pixel.svg")
const DROP_TEXTURE = preload("res://assets/vfx/mouse_cut_raindrop.png")
const SPINDLE_TEXTURE = preload("res://assets/vfx/mouse_cut_spindle.png")
const DROP_PROCESS = preload("res://vfx/mouse_cut_drop_process.gdshader")
const DROP_DRAW = preload("res://vfx/mouse_cut_drop_draw.gdshader")
const RiftBurst = preload("res://vfx/mouse_cut_rift_burst.gd")

var views: Dictionary = {}
var bursts: Array = []
var clock := 0.0
var cut_sources: Dictionary = {}
var cut_tracks: Dictionary = {}
var rift_bursts: Array[Node3D] = []

func set_cut_source(id: String, source: Node3D) -> void:
	cut_sources[id] = source

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
	var ribbon := MeshInstance3D.new()
	ribbon.name = "MouseCutPathRibbon"
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ribbon_material := ShaderMaterial.new()
	ribbon_material.shader = RIBBON_SHADER
	ribbon.material_override = ribbon_material
	ribbon.visible = false
	add_child(ribbon)
	var streaks := MeshInstance3D.new()
	streaks.name = "MouseCutSpeedLines"
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streak_material := ShaderMaterial.new()
	streak_material.shader = STREAK_SHADER
	streaks.material_override = streak_material
	streaks.visible = false
	add_child(streaks)
	return {"mouse":mouse,"outer":outer,"mid":mid,"core":core,"beads":beads,"marker":marker,"ribbon":ribbon,"streaks":streaks,"cut_action_tick":-1,"cut_segments":0,"cut_fade":0.0}

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
		var pulling_id := ""
		for target_id in entities.keys():
			if str(entities[target_id].get("mouse_pull_owner", "")) == str(id) and int(entities[target_id].get("mouse_pull_ticks", 0)) > 0:
				pulling_id = str(target_id)
				break
		var pulling := not pulling_id.is_empty()
		var endpoint := Vector3.ZERO
		if not flight.is_empty():
			endpoint = flight.position
		elif linked:
			endpoint = entities[linked_id].position + Vector3.UP * 0.55
		elif pulling:
			endpoint = entities[pulling_id].position + Vector3.UP * 0.55
		var show_line := not flight.is_empty() or linked or pulling
		view.mouse.visible = show_line
		view.marker.visible = linked or pulling
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
			if linked or pulling:
				var marked_id := linked_id if linked else pulling_id
				view.marker.global_position = entities[marked_id].position + Vector3.UP * 1.1
				view.marker.rotation.y = clock*0.9
		else:
			for segment in [view.outer, view.mid, view.core]: segment.visible = false
			for bead in view.beads: bead.visible = false
		_sync_cut_track(str(id), state, view, tick, delta)

	for id in views.keys():
		if active.has(id): continue
		var old: Dictionary = views[id]
		for node in [old.mouse, old.outer, old.mid, old.core, old.marker, old.ribbon, old.streaks]: node.queue_free()
		for bead in old.beads: bead.queue_free()
		views.erase(id)
		_clear_cut_track(str(id))
		cut_sources.erase(str(id))
	for burst in bursts.duplicate():
		burst.age = float(burst.age) + delta
		var fraction := float(burst.age) / float(burst.duration)
		if fraction >= 1.0:
			burst.node.queue_free()
			bursts.erase(burst)
		else:
			if bool(burst.get("grow", true)):
				burst.node.scale = Vector3.ONE * (0.5 + (float(burst.get("peak", 1.7)) - 0.5) * minf(1.0, fraction*4.0))
			for child in burst.node.get_children():
				if child is GeometryInstance3D: child.transparency = clampf(fraction*fraction, 0.0, 1.0)

func _burst_group(duration := 0.5, grow := true, peak := 1.7) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	bursts.append({"node":root,"age":0.0,"duration":duration,"grow":grow,"peak":peak})
	return root

func _ribbon_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	surface.set_uv(ua)
	surface.add_vertex(a)
	surface.set_uv(ub)
	surface.add_vertex(b)
	surface.set_uv(uc)
	surface.add_vertex(c)

func _ribbon_strip(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float) -> void:
	_ribbon_triangle(surface, a, b, c, Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 0.0))
	_ribbon_triangle(surface, b, d, c, Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0))

func _update_cut_ribbon(ribbon: MeshInstance3D, path: Array) -> void:
	if path.is_empty():
		ribbon.visible = false
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var traveled := 0.0
	for segment in path:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var flat := b - a
		flat.y = 0.0
		if flat.length_squared() < 0.001:
			continue
		var side := flat.normalized().cross(Vector3.UP)
		var u0 := traveled * 0.5
		traveled += flat.length()
		var u1 := traveled * 0.5
		_ribbon_strip(surface, a + side * 0.42 + Vector3.UP * 0.11, a - side * 0.42 + Vector3.UP * 0.11, b + side * 0.42 + Vector3.UP * 0.11, b - side * 0.42 + Vector3.UP * 0.11, u0, u1)
	ribbon.mesh = surface.commit()
	ribbon.visible = ribbon.mesh != null

func _update_cut_streaks(streaks: MeshInstance3D, path: Array) -> void:
	if path.is_empty():
		streaks.visible = false
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in path.size():
		var segment: Array = path[index]
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var direction := (b - a).normalized()
		if a.distance_squared_to(b) < 0.0001: continue
		var side := direction.cross(Vector3.UP).normalized()
		var progress := float(index + 1) / 9.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 9127 + index * 271
		var count := int(lerpf(30.0, 2.0, smoothstep(0.1, 0.9, progress))) if progress < 0.95 else 0
		for lane in count:
			var height_progress := smoothstep(0.0, 0.9, progress)
			var height_low := lerpf(0.1, -0.65, height_progress)
			var height_high := lerpf(2.2, -0.35, height_progress)
			var spread := lerpf(0.95, 0.35, height_progress)
			var center := a.lerp(b, rng.randf()) + side * rng.randf_range(-spread, spread) + Vector3.UP * rng.randf_range(height_low, height_high)
			var large := rng.randf() < 0.22
			var length := rng.randf_range(1.1, 2.4) if large else rng.randf_range(0.25, 1.25)
			var width := rng.randf_range(0.35, 0.65) if large else rng.randf_range(0.1, 0.34)
			# Rain-like streaks point forward and downward, independent of world heading.
			var drop_direction := (direction + Vector3.DOWN * rng.randf_range(0.12, 0.7) + side * rng.randf_range(-0.18, 0.18)).normalized()
			var cross_axis := side.cross(drop_direction).normalized() * width
			var tint := Color(1.0, 0.62, 0.16, 0.8) if lane % 5 == 0 else Color(0.15, 0.65, 1.0, 0.85)
			surface.set_color(tint)
			_ribbon_strip(surface, center - drop_direction * length - cross_axis, center - drop_direction * length + cross_axis, center - cross_axis, center + cross_axis, 0.0, 1.0)
	streaks.mesh = surface.commit()
	(streaks.material_override as ShaderMaterial).set_shader_parameter("drop_profile", true)
	(streaks.material_override as ShaderMaterial).set_shader_parameter("drop_texture", DROP_TEXTURE)
	streaks.visible = streaks.mesh != null

func _clear_cut_track(id: String) -> void:
	if not cut_tracks.has(id): return
	for node in cut_tracks[id].nodes:
		if is_instance_valid(node): node.queue_free()
	cut_tracks.erase(id)

func _sync_cut_track(id: String, state: Dictionary, view: Dictionary, tick: int, delta: float) -> void:
	var cutting := str(state.get("action", "")) == "mouse_cut" and not bool(state.get("dead", false))
	var key := "%s:%s" % [state.get("life", 0), state.get("action_tick", -1)]
	if cut_tracks.has(id) and (cut_tracks[id].key != key or bool(state.get("dead", false))):
		_clear_cut_track(id)
	if not cut_tracks.has(id):
		if not cutting:
			view.ribbon.visible = false
			view.streaks.visible = false
			return
		cut_tracks[id] = {"key":key, "path":[], "nodes":[], "ghosts":[], "age":0.0, "last_growth":0.0, "gold":false}
	var track: Dictionary = cut_tracks[id]
	var action_age := tick - int(state.get("action_tick", tick))
	# Presentation anticipation only; damage and the existing burst event stay at Tick 23.
	if cutting and state.has("mouse_cut_end") and action_age >= 13 and action_age < 23 and not track.has("rift"):
		var a: Vector3 = state.get("mouse_cut_start", state.position)
		var b: Vector3 = state.get("mouse_cut_end", state.position)
		a.y -= 0.95
		b.y -= 0.95
		var rift := _new_rift(a, b, float(action_age - 12) / 60.0)
		track.rift = rift
		track.nodes.append(rift)
	if track.has("rift") and is_instance_valid(track.rift) and not track.rift.confirmed:
		# Keep the anticipation attached to the final endpoint, including prediction corrections.
		var finish: Vector3 = state.get("mouse_cut_end", state.position)
		finish.y -= 0.95
		track.rift.to = finish
		track.rift.global_position = finish + Vector3.UP * 1.95
	track.age += delta
	var path: Array = state.get("mouse_cut_path", []) if cutting else track.path
	var changed := false
	for i in mini(path.size(), track.path.size()):
		if path[i] != track.path[i]:
			changed = true
			break
	if path.size() < track.path.size(): changed = true
	if changed:
		# Coordinates can change even when the number of segments is unchanged.
		for node in track.nodes:
			if is_instance_valid(node): node.queue_free()
		track.nodes = []
		track.ghosts = []
		track.path = []
		track.gold = false
		track.erase("rift")
	if path != track.path:
		for i in range(track.path.size(), path.size()):
			var segment: Array = path[i]
			var progress := float(i + 1) / 9.0
			if progress < 0.95:
				track.nodes.append(_spawn_drop_batch(segment, progress, float(path.size() - i - 1) / 60.0))
			if i == 0:
				var exhaust := _cut_streamers(segment[0], segment[1] - segment[0], true)
				track.nodes.append(exhaust)
			if i in [1, 3, 5] and is_instance_valid(cut_sources.get(id)):
				var source: Node3D = cut_sources[id]
				var ghost := spawn_cut_ghost(source, segment[1] - Vector3(state.position), segment[1] - segment[0], i / 2)
				track.nodes.append(ghost)
				var trail := _cut_streamers(segment[1], segment[1] - segment[0], false)
				track.nodes.append(trail)
				track.ghosts.append({"node":ghost, "trail":trail, "born":track.age - float(path.size() - i - 1) / 60.0, "index":i / 2, "travel":segment[1] - segment[0], "pixels":false})
			if progress >= 0.85 and not track.gold:
				track.gold = true
				track.nodes.append(_spawn_cut_pixels(segment[1], segment[1] - segment[0], 0, true))
		track.path = path.duplicate(true)
		track.last_growth = track.age
		_update_cut_ribbon(view.ribbon, path)
		view.streaks.visible = false
	var tail_age: float = track.age - float(track.last_growth)
	var fade := 1.0 - smoothstep(0.06, 0.48, tail_age)
	for mesh in [view.ribbon, view.streaks]:
		mesh.visible = mesh == view.ribbon and not track.path.is_empty() and fade > 0.0
		(mesh.material_override as ShaderMaterial).set_shader_parameter("time", clock)
		(mesh.material_override as ShaderMaterial).set_shader_parameter("opacity", fade)
	for ghost in track.ghosts:
		var age: float = track.age - float(ghost.born)
		var dissolve := smoothstep(0.12, 0.55, age)
		if is_instance_valid(ghost.node):
			for mesh in ghost.node.find_children("*", "MeshInstance3D", true, false):
				var material := mesh.material_override as ShaderMaterial
				if material != null:
					material.set_shader_parameter("dissolve", dissolve)
					material.set_shader_parameter("opacity", [0.9, 0.6, 0.35][int(ghost.index)] * (1.0 - smoothstep(0.25, 0.62, age)))
		if is_instance_valid(ghost.trail):
			(ghost.trail.material_override as ShaderMaterial).set_shader_parameter("opacity", (1.0 - smoothstep(0.12, 0.55, age)) * [0.9, 0.6, 0.35][int(ghost.index)])
		if not ghost.pixels and age >= 0.14 and (track.path.size() >= 5 or tail_age > 0.08):
			ghost.pixels = true
			track.nodes.append(_spawn_cut_pixels(ghost.node.global_position + Vector3.UP * 0.4, ghost.travel, int(ghost.index)))
	for node in track.nodes:
		if is_instance_valid(node) and node.name == "CutStartExhaust":
			(node.material_override as ShaderMaterial).set_shader_parameter("opacity", 1.0 - smoothstep(0.08, 0.42, track.age))
	if not cutting and tail_age > 1.0: _clear_cut_track(id)

func _spawn_drop_batch(segment: Array, progress: float, catchup: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "CutSpindleDrops"
	particles.one_shot = true
	particles.emitting = false
	particles.explosiveness = 0.85
	particles.amount = int(lerpf(18.0, 2.0, smoothstep(0.1, 0.9, progress)))
	particles.lifetime = 0.7
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 10, 20))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var start: Vector3 = segment[0]
	var direction: Vector3 = (segment[1] - start).normalized()
	var ground := start.y - 0.95
	var query := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 3.0, start + Vector3.DOWN * 5.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): ground = float(hit.position.y)
	var process := ShaderMaterial.new()
	process.shader = DROP_PROCESS
	process.set_shader_parameter("forward", direction)
	process.set_shader_parameter("progress", progress)
	process.set_shader_parameter("ground_y", ground)
	process.set_shader_parameter("catchup", catchup)
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	particles.draw_pass_1 = quad
	var draw := ShaderMaterial.new()
	draw.shader = DROP_DRAW
	draw.set_shader_parameter("sprite_texture", SPINDLE_TEXTURE)
	particles.material_override = draw
	add_child(particles)
	particles.global_position = start
	particles.restart()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles

func _cut_streamers(at: Vector3, travel: Vector3, exhaust: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "CutStartExhaust" if exhaust else "CutGhostTrail"
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = STREAK_SHADER
	mesh.material_override = material
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var forward := travel.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	for lane in (5 if exhaust else 4):
		var previous := Vector3.ZERO
		for step in 17:
			var t := float(step) / 16.0
			var point := at - forward * t * (2.5 if exhaust else 1.7) + side * (float(lane) - 2.0) * (0.09 + sin(t * PI) * 0.32) + Vector3.UP * (-0.4 + lane * 0.22 + sin(t * PI) * (0.65 if exhaust else 0.2))
			if step > 0:
				var width := (0.045 if exhaust else 0.07) * pow(1.0 - t, 0.8) + 0.002
				surface.set_color(Color(1.0, 0.63, 0.18, 0.9) if lane == 0 else Color(0.15, 0.68, 1.0, 0.85))
				_ribbon_strip(surface, previous - Vector3.UP * width, previous + Vector3.UP * width, point - Vector3.UP * width, point + Vector3.UP * width, float(step - 1) / 16.0, t)
			previous = point
	mesh.mesh = surface.commit()
	add_child(mesh)
	return mesh

func spawn_cut_ghost(source: Node3D, offset: Vector3, travel: Vector3, index: int) -> Node3D:
	if not is_instance_valid(source):
		return null
	var ghost := source.duplicate()
	ghost.set_script(null)
	ghost.name = "MouseCutFoxAfterimage"
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(ghost)
	ghost.global_transform = source.global_transform
	ghost.global_position += offset
	for node in ghost.find_children("*", "", true, false):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		if node is AnimationTree:
			(node as AnimationTree).active = false
		elif node is AnimationPlayer:
			(node as AnimationPlayer).active = false
		elif node is Skeleton3D:
			var original_skeleton := source.get_node_or_null(ghost.get_path_to(node)) as Skeleton3D
			if original_skeleton != null:
				for bone in node.get_bone_count():
					node.set_bone_pose_position(bone, original_skeleton.get_bone_pose_position(bone))
					node.set_bone_pose_rotation(bone, original_skeleton.get_bone_pose_rotation(bone))
					node.set_bone_pose_scale(bone, original_skeleton.get_bone_pose_scale(bone))
		elif node is MeshInstance3D and node.visible:
			var mesh_node := node as MeshInstance3D
			var original := mesh_node.get_active_material(0) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = GHOST_SHADER
			material.set_shader_parameter("opacity", 0.82 - float(index) * 0.07)
			material.set_shader_parameter("dissolve", float(index) * 0.07)
			material.set_shader_parameter("seed", float(index) * 7.17)
			if original != null and original.albedo_texture != null:
				material.set_shader_parameter("base_texture", original.albedo_texture)
				material.set_shader_parameter("has_texture", true)
			mesh_node.material_override = material
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ghost

func _spawn_cut_pixels(at: Vector3, travel: Vector3, index: int, gold := false) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "MouseCutGhostPixels"
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 7 if gold else 16 + index * 12
	particles.lifetime = 0.38
	particles.explosiveness = 0.95
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.65
	process.direction = -travel.normalized() + Vector3.UP * 0.25
	process.spread = 48.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 2.3
	process.gravity = Vector3(0.0, -0.5, 0.0)
	process.scale_min = 0.4
	process.scale_max = 1.0
	particles.process_material = process
	var square := QuadMesh.new()
	square.size = Vector2(0.12, 0.12)
	particles.draw_pass_1 = square
	var material := _glow(Color(1.0, 0.65, 0.18) if gold else Color(0.2, 0.7, 1.0), 0.82)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_texture = PIXEL_TEXTURE
	particles.material_override = material
	add_child(particles)
	particles.global_position = at
	particles.restart()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles

func _digital_frame(a: Vector3, b: Vector3, variant: int) -> void:
	var forward := b - a
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP)
	var center := (a + b) * 0.5 + Vector3.UP * (0.65 + float(variant % 3) * 0.17) + side * (0.35 if variant % 4 < 2 else -0.35)
	var root := _burst_group(0.38, false)
	root.global_position = center
	var half_width := 0.32 + float(variant % 2) * 0.12
	var half_height := 0.38
	var color := Color(0.24, 0.85, 1.0)
	for x in [-1.0, 1.0]:
		_burst_beam(root, center + side * (x * half_width) - Vector3.UP * half_height, center + side * (x * half_width) + Vector3.UP * half_height, 0.015, color, 0.7)
	for y in [-1.0, 1.0]:
		_burst_beam(root, center - side * half_width + Vector3.UP * (y * half_height), center + side * half_width + Vector3.UP * (y * half_height), 0.015, color, 0.7)
	if variant % 4 == 0:
		for x in [-1.0, 1.0]:
			_burst_beam(root, center + side * (x * 0.12) - Vector3.UP * 0.2, center + side * (x * 0.12) + Vector3.UP * 0.2, 0.018, Color(0.75, 1.0, 1.0), 0.8)
		for y in [-1.0, 1.0]:
			_burst_beam(root, center - side * 0.12 + Vector3.UP * (y * 0.2), center + side * 0.12 + Vector3.UP * (y * 0.2), 0.018, Color(0.75, 1.0, 1.0), 0.8)
	else:
		_burst_beam(root, center - Vector3.UP * 0.22, center + Vector3.UP * 0.22, 0.023, Color(0.75, 1.0, 1.0), 0.8)

func _cross_stroke(root: Node3D, a: Vector3, b: Vector3, forward: Vector3, variant: int, tint: Color) -> void:
	var side := forward.cross(Vector3.UP)
	var previous := a
	for i in range(1, 9):
		var fraction := float(i) / 8.0
		var point := a.lerp(b, fraction)
		if i < 8:
			point += forward * sin(float(i * 11 + variant * 7)) * 0.07
			point += side * sin(float(i * 7 + variant * 5)) * 0.025
		_burst_beam(root, root.to_global(previous), root.to_global(point), 0.17, tint, 0.25)
		_burst_beam(root, root.to_global(previous), root.to_global(point), 0.055, Color(0.94, 1.0, 1.0), 0.95)
		previous = point

func _burst_beam(root: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, alpha := 0.85) -> void:
	var tube := _tube(root, radius, _glow(color, alpha))
	_beam(tube, a, b)

func _ground_fissure(a: Vector3, b: Vector3) -> void:
	var forward := b - a
	forward.y = 0.0
	var distance := forward.length()
	if distance < 0.05:
		return
	forward /= distance
	var side := forward.cross(Vector3.UP)
	var root := _burst_group(0.68, false)
	var steps := maxi(2, int(ceil(distance * 1.7)))
	var previous := a + Vector3.UP * 0.12
	for i in range(1, steps + 1):
		var fraction := float(i) / float(steps)
		var point := a.lerp(b, fraction) + Vector3.UP * 0.12
		if i < steps:
			point += side * sin(float(i) * 2.75) * 0.16
		_burst_beam(root, previous, point, 0.13, Color(0.1, 0.64, 1.0), 0.3)
		_burst_beam(root, previous, point, 0.035, Color(0.92, 1.0, 1.0), 0.94)
		if i % 3 == 0:
			var branch := point + side * (0.55 if i % 2 == 0 else -0.55) + forward * 0.28
			_burst_beam(root, point, branch, 0.026, Color(0.24, 0.84, 1.0), 0.72)
		previous = point

func _shock_ring(at: Vector3) -> void:
	var root := _burst_group(0.44, true, 1.35)
	root.global_position = at + Vector3.UP * 0.16
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 32:
		var angle0 := TAU * float(i) / 32.0
		var angle1 := TAU * float(i + 1) / 32.0
		var inner0 := Vector3(cos(angle0), 0.0, sin(angle0)) * 0.82
		var outer0 := Vector3(cos(angle0), 0.0, sin(angle0)) * 1.04
		var inner1 := Vector3(cos(angle1), 0.0, sin(angle1)) * 0.82
		var outer1 := Vector3(cos(angle1), 0.0, sin(angle1)) * 1.04
		for point in [inner0, outer0, inner1, outer0, outer1, inner1]:
			surface.add_vertex(point)
	var ring := MeshInstance3D.new()
	ring.mesh = surface.commit()
	ring.material_override = _glow(Color(0.34, 0.9, 1.0), 0.78)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

func _impact_pillar(at: Vector3, seed: int) -> void:
	var root := _burst_group(0.52, true, 1.2)
	root.global_position = at
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + float(seed) * 0.28
		var side := Vector3(cos(angle), 0.0, sin(angle))
		var bottom_left := side * -0.62 + Vector3.UP * 0.12
		var bottom_right := side * 0.62 + Vector3.UP * 0.12
		var top_left := side * -0.1 + Vector3.UP * 3.4
		var top_right := side * 0.1 + Vector3.UP * 3.4
		_ribbon_triangle(surface, bottom_left, bottom_right, top_left, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1))
		_ribbon_triangle(surface, bottom_right, top_right, top_left, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var shell := MeshInstance3D.new()
	shell.mesh = surface.commit()
	var energy := ShaderMaterial.new()
	energy.shader = ENERGY_SHADER
	shell.material_override = energy
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	_burst_beam(root, at + Vector3.UP * 0.12, at + Vector3.UP * 3.3, 0.035, Color(0.74, 0.98, 1.0), 0.72)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + float(seed) * 0.41
		var offset := Vector3(cos(angle), 0.0, sin(angle))
		_burst_beam(root, at + offset * 0.28 + Vector3.UP * 0.2, at + offset * 0.72 + Vector3.UP * (2.0 + float(i % 2) * 0.7), 0.025, Color(0.22, 0.82, 1.0), 0.7)

func _cut_particles(at: Vector3, rocks: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "MouseCutRocks" if rocks else "MouseCutSparks"
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 12 if rocks else 22
	particles.lifetime = 0.7 if rocks else 0.38
	particles.explosiveness = 0.95
	particles.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.23
	process.direction = Vector3.UP
	process.spread = 68.0 if rocks else 85.0
	process.initial_velocity_min = 2.0 if rocks else 3.5
	process.initial_velocity_max = 5.2 if rocks else 7.0
	process.gravity = Vector3(0.0, -12.0 if rocks else -5.0, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.3
	particles.process_material = process
	if rocks:
		var rock := BoxMesh.new()
		rock.size = Vector3(0.13, 0.18, 0.1)
		particles.draw_pass_1 = rock
		particles.material_override = _solid(Color(0.1, 0.16, 0.22))
	else:
		var spark := PrismMesh.new()
		spark.size = Vector3(0.05, 0.16, 0.05)
		particles.draw_pass_1 = spark
		particles.material_override = _glow(Color(1.0, 0.48, 0.14), 0.94)
	add_child(particles)
	particles.global_position = at + Vector3.UP * 0.35
	particles.restart()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

func burst_link(at: Vector3) -> void:
	var root := _burst_group(0.42)
	root.global_position = at
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_burst_beam(root, at-axis*0.7, at+axis*0.7, 0.075, Color(0.55, 1.0, 1.0))
	_sphere(root, 0.35, _glow(Color(0.15, 0.86, 1.0), 0.55)).global_position = at

func burst_launch(at: Vector3) -> void:
	var root := _burst_group(0.36, false)
	root.global_position = at
	_sphere(root, 0.42, _glow(Color(0.34, 0.86, 1.0), 0.62)).global_position = at
	for i in 6:
		var angle := float(i) * TAU / 6.0
		var side := Vector3(cos(angle), 0.0, sin(angle))
		_burst_beam(root, at + side * 0.25 - Vector3.UP * 0.25, at + side * 0.55 + Vector3.UP * 1.3, 0.045, Color(0.7, 0.96, 1.0), 0.8)

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
	# Events contain capsule/body origins, while this presentation is grounded.
	a.y -= 0.95
	b.y -= 0.95
	for rift in rift_bursts.duplicate():
		if not is_instance_valid(rift) or rift.is_queued_for_deletion():
			rift_bursts.erase(rift)
			continue
		if not rift.confirmed and Vector2(rift.to.x, rift.to.z).distance_to(Vector2(b.x, b.z)) < 0.3 and Vector2(rift.from.x, rift.from.z).distance_to(Vector2(a.x, a.z)) < 0.3:
			rift.confirm_peak()
			return
	# If a remote action arrives late, show the peak immediately rather than delaying its feedback.
	var rift := _new_rift(a, b, RiftBurst.GROW_SECONDS)
	rift.confirm_peak()

func _new_rift(a: Vector3, b: Vector3, initial_age: float) -> Node3D:
	for old in rift_bursts.duplicate():
		if not is_instance_valid(old): rift_bursts.erase(old)
	var rift := RiftBurst.new()
	add_child(rift)
	rift.configure(a, b, initial_age)
	rift_bursts.append(rift)
	return rift
