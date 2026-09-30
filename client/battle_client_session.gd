extends Node
## Transport/input and presentation only. No skill-specific prediction here.
const Prediction = preload("res://client/world_prediction.gd")
const Core = preload("res://combat/combat_world.gd")
const Codec = preload("res://network/world_codec.gd")
const Reliable = preload("res://network/reliable_events.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
const PotVisual = preload("res://returning_pot.gd")
const MouseVFX = preload("res://vfx/mouse_skill_vfx.gd")
const DummyView = preload("res://client/battle_dummy_view.gd")
const LOCAL_SMALL_CORRECTION := 0.15
const LOCAL_SNAP_DISTANCE := 0.8
const LOCAL_SMALL_CORRECTION_TIME := 0.08
const LOCAL_MEDIUM_CORRECTION_TIME := 0.05
var replay = Prediction.new()
var world_packets = Codec.new()
var manager: Node
var transport: PacketPeerUDP
var lane = Reliable.new()
var slot := -1
var entity_id := ""
var joined := false
var session := ""
var closing := false
var input_seq := 0
var next_attack_seq := 0
var queued_actions: Array = []
var history: Array:
	get: return replay.history
var predicted: Dictionary = {}
var local_render_offset := Vector3.ZERO
var local_correction_remaining := 0.0
var motor: CharacterBody3D
var snapshot_tick := -1
var last_packet := 0
var next_hello := 0
var next_ping := 0
var rtt_ms := 0
var round_id := 0
var round_over := false
var pending_snapshot: Dictionary = {}
var npc_views: Dictionary = {}
var pot_visuals: Dictionary = {}
var pot_targets: Dictionary = {}
var mouse_vfx: Node3D
var mouse_ghost_tick: Dictionary = {}
var mouse_cut_burst_paths: Dictionary = {}
var mouse_cut_camera_key := ""
var render_lives: Dictionary = {}
var seen_events: Dictionary = {}
var blink_events := 0
var original_layer := 0
var original_mask := 0
var next_diagnostic := 0
var snapshot_received_at := 0

func _process(delta: float) -> void:
	if closing or transport==null: return
	var now := Time.get_ticks_msec()
	if now-last_packet>6000:
		_fail("战斗服连接超时，已返回菜单。")
		return
	if not joined and now>=next_hello:
		next_hello = now+250
		_send({"type":"hello"})
	if joined and now>=next_ping:
		next_ping = now+1000
		_send({"type":"ping","sent":now})
	var budget := 256
	while transport.get_available_packet_count()>0 and budget>0:
		budget -= 1
		var packet = JSON.parse_string(transport.get_packet().get_string_from_utf8())
		if not packet is Dictionary: continue
		if packet.get("type","")=="rejected" and not joined:
			_fail(str(packet.get("reason","房间已满")))
			return
		if packet.get("type","")=="admitted" and session.is_empty():
			if int(packet.get("protocol",0))!=Core.SCHEMA:
				_fail("战斗服协议不匹配，请重启新版战斗服务器。")
				return
			session = str(packet.session)
			slot = int(packet.slot)
			entity_id = str(packet.entity_id)
		if session.is_empty() or packet.get("session","")!=session: continue
		last_packet = now
		if packet.has("ack"): lane.acknowledge(int(packet.ack))
		elif packet.has("reliable") and packet.get("payload") is Dictionary:
			var id := int(packet.reliable)
			if id>0 and id<lane.next_receive+Reliable.WINDOW:
				_send({"ack":id})
				for message in lane.receive(id,packet.payload): _message(message)
		else: _message(packet)
	for packet in lane.outgoing(now): _send(packet)
	if joined: _render(delta)

func _message(packet: Dictionary) -> void:
	match str(packet.get("type","")):
		"pong": rtt_ms = clampi(Time.get_ticks_msec()-int(packet.get("sent",Time.get_ticks_msec())),0,2000)
		"admitted","snapshot":
			if int(packet.get("tick",-1))<=maxi(snapshot_tick,int(pending_snapshot.get("tick",-1))): return
			var encoded: String = world_packets.receive(packet)
			if encoded.is_empty(): return
			var snapshot := Codec.unpack(encoded)
			if int(snapshot.get("schema",0))!=Core.SCHEMA or not snapshot.get("entities",{}).has(entity_id): return
			pending_snapshot = snapshot
		"round_end","round_reset","entity_death","entity_respawn":
			# Reliable notifications cannot mutate simulation; full snapshots do that.
			if joined: _present_events([packet],true)

func _physics_process(_delta: float) -> void:
	if closing: return
	if not pending_snapshot.is_empty():
		var first := not joined
		if first: _enter()
		var previous_local_display: Vector3 = manager.local_player.global_position
		var previous_render_life := int(render_lives.get(entity_id, -1))
		snapshot_tick = int(pending_snapshot.tick)
		snapshot_received_at = Time.get_ticks_msec()
		round_id = int(pending_snapshot.round_id)
		var next_own: Dictionary = pending_snapshot.entities.get(entity_id,{})
		if not predicted.is_empty() and int(predicted.get("life",0))!=int(next_own.get("life",0)): queued_actions.clear()
		var lead := clampi(int(ceil(float(rtt_ms)*0.06))+3,3,15)
		var emitted: Array = replay.receive(pending_snapshot,lead)
		pending_snapshot = {}
		if Time.get_ticks_msec()>=next_diagnostic:
			next_diagnostic = Time.get_ticks_msec()+5000
			print("BATTLE_SYNC tick=%d ahead=%d rtt=%d pending=%d same_tick_error=%.4f correction=%.4f rebases=%d replay_steps=%d" % [snapshot_tick,replay.sim.server_tick-snapshot_tick,rtt_ms,replay.history.size(),replay.same_tick_error,replay.last_correction,replay.timeline_rebases,replay.replay_steps])
		_sync_views()
		if not first:
			_present_events(replay.authority.get("events",[]),true)
			_present_events(emitted,false)
		else:
			for event in replay.authority.get("events",[]): seen_events[_event_key(event)] = true
		var corrected: Dictionary = replay.sim.entities.get(entity_id, {})
		var same_render_life := previous_render_life == int(corrected.get("life", -2))
		_begin_local_correction(previous_local_display, corrected.get("position", previous_local_display), not first and same_render_life)
	if not joined: return
	# Bound speculation during outages. Never silently drop an unconfirmed action.
	if replay.sim.server_tick>=snapshot_tick+Prediction.MAX_LEAD: return
	var desired_lead := clampi(int(ceil(float(rtt_ms)*0.06))+3,3,15)
	var estimate := snapshot_tick+desired_lead+int((Time.get_ticks_msec()-snapshot_received_at)*0.06)
	if replay.sim.server_tick>estimate+2: return
	var control: Dictionary = manager.local_player.capture_control()
	var move: Vector3 = control.move if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or manager.local_player.scripted_drive else Vector3.ZERO
	var aim: Vector3 = control.aim
	if aim.length_squared()<0.001: aim = Vector3.FORWARD
	input_seq += 1
	var command := {"entity_id":entity_id,"seq":input_seq,"tick":replay.sim.server_tick+1,
		"round_id":round_id,"life":int(predicted.get("life",1)),"move":move,"aim":aim,"actions":queued_actions.duplicate(true)}
	queued_actions.clear()
	var emitted: Array = replay.predict(command)
	if not command.actions.is_empty():
		if not lane.queue({"type":"input","frames":[_wire_frame(command)]}):
			_fail("出招队列积压，请重新连接。")
			return
	var frames: Array = []
	for frame in replay.history.slice(maxi(0,replay.history.size()-8)): frames.append(_wire_frame(frame))
	_send({"type":"input","frames":frames})
	_sync_views()
	_present_events(emitted,false)

func _wire_frame(frame: Dictionary) -> Dictionary:
	var actions: Array = []
	for action in frame.actions:
		var action_aim: Vector3 = action.aim
		var packed_aim := [action_aim.x, action_aim.y, action_aim.z] if str(action.attack) == "mouse_cast" else [action_aim.x, action_aim.z]
		actions.append({"attack_seq":action.attack_seq,"attack":action.attack,"aim":packed_aim})
	return {"seq":frame.seq,"tick":frame.tick,"round_id":frame.round_id,"life":frame.life,"move":[frame.move.x,frame.move.z],"aim":[frame.aim.x,frame.aim.z],"actions":actions}

func _enter() -> void:
	joined = true
	var server_map := str(pending_snapshot.get("map_id", "courtyard"))
	replay.sim.configure_arena(server_map)
	manager.battle_map_id = server_map
	manager.room_kind = "duel"
	manager.begin_play(slot,true)
	manager.local_player.loadout[0] = 0
	manager.local_player.loadout[1] = 2
	if server_map == "mountain_courtyard":
		mouse_vfx = MouseVFX.new()
		manager.get_parent().add_child(mouse_vfx)
	manager.clear_arena_dummies()
	original_layer = manager.local_player.collision_layer
	original_mask = manager.local_player.collision_mask
	manager.local_player.collision_layer = 0
	manager.local_player.collision_mask = 0
	manager.local_player.set_physics_process(false)
	replay.entity_id = entity_id
	replay.sim.attach(self)

func request_action(action: String, aim: Vector3) -> void:
	if not joined or round_over or queued_actions.size()>=4: return
	var mapping := {"punch":"punch","kick":"kick_front","skill_a0":"umbrella_primary","skill_a1":"umbrella_spin","skill_b0":"returning_pot","skill_b1":"pot_slam","jump":"jump","blink":"blink"}
	if action in ["mouse_primary", "mouse_secondary"]:
		if replay.sim.map_id != "mountain_courtyard": return
		var linked: bool = not str(predicted.get("mouse_link_id", "")).is_empty() and replay.sim.server_tick < int(predicted.get("mouse_link_until", 0))
		var flying: bool = not predicted.get("mouse_projectile", {}).is_empty() or str(predicted.get("action", "")) == "mouse_cast"
		if action == "mouse_primary":
			mapping[action] = "mouse_pull" if linked else "mouse_cast"
		else:
			mapping[action] = "mouse_swap" if linked or flying else "mouse_cut"
	if not mapping.has(action): return
	next_attack_seq += 1
	if mapping[action] == "mouse_cast":
		var view: Vector3 = manager.local_player.camera_look().normalized()
		var flat := Vector3(view.x, 0.0, view.z)
		if flat.length_squared() < 0.001: flat = predicted.get("facing", Vector3.FORWARD)
		flat = flat.normalized()
		var vertical := clampf(view.y, -sin(deg_to_rad(35.0)), sin(deg_to_rad(35.0)))
		aim = flat * sqrt(maxf(0.0, 1.0-vertical*vertical)) + Vector3.UP * vertical
	else:
		aim.y = 0
		if aim.length_squared()<0.001: aim = predicted.get("facing",Vector3.FORWARD)
	queued_actions.append({"attack_seq":next_attack_seq,"attack":mapping[action],"aim":aim.normalized()})
	# Applied at the next local physics Tick (<=16.7ms), never waits for network.

func foe_juggled(reach: float, height_limit: float) -> bool:
	return joined and replay.sim.entities.has(entity_id) and replay.sim._nearby_juggled(entity_id,reach,height_limit)

func _sync_views() -> void:
	var active_players := {}
	var active_npcs := {}
	var authority_entities: Dictionary = replay.authority.get("entities",{})
	round_over = int(replay.authority.get("round_reset_at",0))>0
	predicted = replay.sim.entities.get(entity_id,{})
	motor = predicted.get("body")
	for id in replay.sim.entities:
		var state: Dictionary = replay.sim.entities[id]
		var authoritative: Dictionary = authority_entities.get(id,state)
		var body: Node
		if state.kind=="dummy":
			active_npcs[id] = true
			if not npc_views.has(id):
				var view = DummyView.new()
				view.setup(manager.get_parent().get_node("TrainingDummy1"))
				manager.get_parent().add_child(view)
				view.chase = false
				npc_views[id] = view
			body = npc_views[id]
			var row := state.duplicate()
			row.position = [state.position.x,state.position.y,state.position.z]
			row.health = authoritative.health
			row.dead = authoritative.dead
			row.life = authoritative.life
			row.juggled = bool(state.get("juggled",false))
			row.respawn_ms = maxi(0,int(authoritative.get("respawn_at",0))-replay.sim.now_ms())
			body.apply_snapshot(row)
		else:
			var index := int(state.slot)
			active_players[index+1] = true
			if index==slot: body = manager.local_player
			else:
				if manager.puppet_for(index+1)==null: manager.spawn_puppet(index+1,index,index)
				body = manager.puppet_for(index+1)
			body.set_physics_process(false)
			body.external_combat_view = true
			body.collision_layer = 0
			body.collision_mask = 0
			body.health = int(authoritative.health)
			body.downed = bool(authoritative.dead)
			body.revive_time = 999.0
			body.juggled = bool(state.get("juggled",false))
			body.kick_bounce = bool(state.get("kick_bounce",false))
			body.velocity = state.velocity
			body.action_lock = float(state.get("lock",0))
			body.spin_hit_done = true
			body.dash_time = float(state.get("dash",0))
			body.dash_followup_timer = maxf(0,float(int(state.get("followup",0))-replay.sim.now_ms())/1000)
			body.knockdown = float(state.get("knockdown_time",0))>0 or (float(state.get("protection",0))>0 and float(state.get("stun",0))>0)
			body.knockdown_time = float(state.get("stun",0))
			for pair in [["dash","dash_ready"],["spin","cooldown_umbrella_spin"],["slam","cooldown_pot_slam"],["pot","cooldown_returning_pot"]]:
				body.cd[pair[0]] = maxf(0,float(int(state.get(pair[1],0))-replay.sim.now_ms())/1000)
			body.blink_cooldown = maxf(0,float(int(state.get("cooldown_blink",0))-replay.sim.now_ms())/1000)
			_sync_action_pose(body,state)
		if int(render_lives.get(id,-1))!=int(authoritative.life):
			body.global_position = state.position
			render_lives[id] = int(authoritative.life)
	for id in manager.puppets.keys():
		if not active_players.has(id): manager.free_puppet(id)
	for id in npc_views.keys():
		if not active_npcs.has(id):
			npc_views[id].queue_free()
			npc_views.erase(id)
			render_lives.erase(id)
	var scores: Array = []
	for state in authority_entities.values():
		if state.kind=="player": scores.append({"slot":state.slot,"score":state.get("score",0)})
	manager.apply_battle_server_scores(scores)
	_sync_pots()

func _sync_action_pose(body: Node, state: Dictionary) -> void:
	# Pose phase is derived from simulation time, including correction/cancellation.
	var attack := str(state.get("action",""))
	body.fox_attack_id = attack
	var left := maxf(0,float(int(state.get("end_tick",0))-replay.sim.server_tick)/60.0)
	body.punch_time = left if BattleRules.is_punch(attack) else 0.0
	body.kick_time = left if attack=="kick_front" else 0.0
	body.uppercut_time = left if attack=="umbrella_uppercut" else 0.0
	body.spin_time = left if attack=="umbrella_spin" else 0.0
	if attack=="umbrella_spin":
		var facing: Vector3 = state.get("action_direction",state.facing)
		body.spin_facing = atan2(-facing.x,-facing.z)
	if attack=="pot_slam":
		body.pot_span = BattleRules.SLAM_AIR_ANIM if bool(state.get("aerial",false)) else BattleRules.SLAM_GROUND_ANIM
		body.pot_time = maxf(0,body.pot_span-float(replay.sim.server_tick-int(state.get("action_tick",0)))/60.0)
	else:
		body.pot_span = 0.22
		body.pot_time = maxf(0,0.22-float(replay.sim.server_tick-int(state.get("pot_pose_tick",-1000)))/60.0)

func _body(id: String) -> Node:
	if npc_views.has(id): return npc_views[id]
	if not replay.sim.entities.has(id): return null
	var index := int(replay.sim.entities[id].slot)
	return manager.local_player if index==slot else manager.puppet_for(index+1)

func _render(delta: float) -> void:
	if is_instance_valid(mouse_vfx):
		mouse_vfx.sync_world(replay.sim.entities, replay.sim.server_tick, delta)
	var camera_rig := manager.get_parent().get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("set_mouse_cut_focus"):
		var local_state: Dictionary = replay.sim.entities.get(entity_id, {})
		var cut_phase := ""
		if str(local_state.get("action", "")) == "mouse_cut":
			var cut_age: int = replay.sim.server_tick - int(local_state.get("action_tick", replay.sim.server_tick))
			if cut_age >= BattleRules.MOUSE_CUT_STARTUP and cut_age < BattleRules.MOUSE_CUT_STARTUP + BattleRules.MOUSE_CUT_TRAVEL_TICKS:
				cut_phase = "travel"
		camera_rig.set_mouse_cut_focus(cut_phase, local_state.get("mouse_cut_start", Vector3.ZERO), local_state.get("mouse_cut_end", Vector3.ZERO))
	for id in replay.sim.entities:
		var body := _body(str(id))
		if body==null: continue
		var state: Dictionary = replay.sim.entities[id]
		var target: Vector3 = state.position
		# Smoothing is display-only. Neither collision nor aiming reads these transforms.
		if str(id) == entity_id and state.kind == "player":
			# Own movement is already predicted. Display it immediately and smooth only
			# the temporary visual offset created by an authoritative correction.
			body.global_position = _local_render_position(target, delta)
		else:
			body.global_position = target if body.global_position.distance_to(target)>2.0 else body.global_position.lerp(target,1.0-exp(-35.0*delta))
		if state.kind=="player": _present_facing(body,state.facing,delta)
		if state.kind=="player" and body.get("visual"):
			var cut_age: int = replay.sim.server_tick - int(state.get("action_tick", replay.sim.server_tick))
			var cutting := str(state.get("action", "")) == "mouse_cut" and cut_age >= BattleRules.MOUSE_CUT_STARTUP and cut_age < BattleRules.MOUSE_CUT_STARTUP + BattleRules.MOUSE_CUT_TRAVEL_TICKS
			var fox_visual: Node = body.visual.get_node_or_null("FoxVisual")
			if fox_visual != null:
				fox_visual.mouse_cut_pose = cutting
			body.visual.rotation.x = -0.34 if cutting else 0.0
		if is_instance_valid(mouse_vfx) and str(state.get("action", "")) == "mouse_cut":
			var path: Array = state.get("mouse_cut_path", [])
			var action_tick := int(state.get("action_tick", -1))
			var ghost_state: Dictionary = mouse_ghost_tick.get(id, {})
			var seen := int(ghost_state.get("segments", 0)) if int(ghost_state.get("action_tick", -2)) == action_tick else 0
			if body.get("visual"):
				for segment_index in range(seen, path.size()):
					if segment_index % 2 != 1 or segment_index >= 9:
						continue
					var segment: Array = path[segment_index]
					var end: Vector3 = segment[1]
					mouse_vfx.spawn_cut_ghost(body.visual, end - body.global_position, end - segment[0], segment_index / 2)
			mouse_ghost_tick[id] = {"action_tick":action_tick,"segments":path.size()}
	for id in pot_visuals:
		var visual = pot_visuals[id]
		visual.global_position = visual.global_position.lerp(pot_targets[id],1.0-exp(-35.0*delta))
		visual.rotor.rotate_y(delta*(38.0 if visual.recalled else 26.0))
		visual.update_trail(delta)

func _begin_local_correction(display_position: Vector3, target: Vector3, preserve_continuity: bool) -> void:
	var offset := display_position - target
	if not preserve_continuity or not offset.is_finite() or offset.length() > LOCAL_SNAP_DISTANCE:
		local_render_offset = Vector3.ZERO
		local_correction_remaining = 0.0
		return
	local_render_offset = offset
	if offset.length_squared() < 0.000001:
		local_render_offset = Vector3.ZERO
		local_correction_remaining = 0.0
	else:
		local_correction_remaining = LOCAL_SMALL_CORRECTION_TIME if offset.length() < LOCAL_SMALL_CORRECTION else LOCAL_MEDIUM_CORRECTION_TIME

func _local_render_position(target: Vector3, delta: float) -> Vector3:
	if local_correction_remaining <= 0.0 or local_render_offset.length_squared() < 0.000001:
		local_render_offset = Vector3.ZERO
		local_correction_remaining = 0.0
		return target
	if delta >= local_correction_remaining:
		local_render_offset = Vector3.ZERO
		local_correction_remaining = 0.0
		return target
	var remaining := local_correction_remaining - delta
	local_render_offset *= remaining / local_correction_remaining
	local_correction_remaining = remaining
	return target + local_render_offset

func _event_key(event: Dictionary) -> String:
	var type := str(event.get("type",""))
	if type.begins_with("mouse_"):
		return "%s|%s|%s|%s|%s" % [event.get("round_id",0),type,event.get("entity_id",""),event.get("attack_seq",-1),event.get("target_id","")]
	if type=="combat":
		return "%s|%s|%s|%s|%s|%s|%s" % [event.get("round_id",0),type,event.get("attacker_id",""),event.get("attack_seq",-1),event.get("victim_id",""),event.get("victim_life",0),event.get("attack","")]
	if type in ["action_start","blink"]:
		return "%s|%s|%s|%s|%s" % [event.get("round_id",0),type,event.get("slot",-1),event.get("attack_seq",-1),event.get("actor_life",0)]
	return "%s|%s|%s|%s" % [event.get("round_id",0),type,event.get("entity_id",""),event.get("life",0)]

func _present_events(events: Array, authoritative: bool) -> void:
	for event in events:
		var type := str(event.get("type",""))
		if type not in ["combat","blink","action_start","mouse_launch","mouse_link","mouse_pull","mouse_pull_launch","mouse_swap","mouse_cut_burst","mouse_miss"] and not authoritative: continue
		if type=="attack_result": continue
		if int(event.get("round_id",round_id))<round_id: continue
		var key := _event_key(event)
		if seen_events.has(key): continue
		seen_events[key] = true
		while seen_events.size()>512: seen_events.erase(seen_events.keys()[0])
		match type:
			"mouse_launch":
				manager.feedback.play_swing()
			"mouse_link":
				if is_instance_valid(mouse_vfx): mouse_vfx.burst_link(vector(event.get("position", [])))
				manager.feedback.impact(vector(event.get("position", [])), false)
			"mouse_pull":
				if is_instance_valid(mouse_vfx): mouse_vfx.burst_link(vector(event.get("from", [])) + Vector3.UP * 0.8)
			"mouse_pull_launch":
				if is_instance_valid(mouse_vfx): mouse_vfx.burst_launch(vector(event.get("position", [])) + Vector3.UP * 0.8)
			"mouse_swap":
				if is_instance_valid(mouse_vfx): mouse_vfx.burst_swap(vector(event.get("from", [])), vector(event.get("to", [])))
			"mouse_cut_burst":
				if is_instance_valid(mouse_vfx): mouse_vfx.burst_cut(vector(event.get("from", [])), vector(event.get("to", [])))
				if str(event.get("entity_id", "")) == entity_id:
					mouse_cut_burst_paths[int(event.get("attack_seq", -1))] = {"from":vector(event.get("from", [])), "to":vector(event.get("to", []))}
					while mouse_cut_burst_paths.size() > 32:
						mouse_cut_burst_paths.erase(mouse_cut_burst_paths.keys()[0])
			"combat":
				var body := _body(str(event.get("victim_id","")))
				if body==null: continue
				body.flinch_time = 0.15
				var attack_name := str(event.get("attack",""))
				if attack_name == "mouse_cut" and str(event.get("attacker_id", "")) == entity_id:
					var cut_key := "%d:%d" % [int(event.get("round_id", round_id)), int(event.get("attack_seq", -1))]
					if mouse_cut_camera_key != cut_key:
						mouse_cut_camera_key = cut_key
						var camera_rig := manager.get_parent().get_node_or_null("CameraRig")
						if camera_rig != null and camera_rig.has_method("begin_mouse_cut_cinematic"):
							var path: Dictionary = mouse_cut_burst_paths.get(int(event.get("attack_seq", -1)), {})
							var attacker_state: Dictionary = replay.sim.entities.get(entity_id, {})
							var start: Vector3 = path.get("from", attacker_state.get("mouse_cut_start", body.global_position))
							var finish: Vector3 = path.get("to", attacker_state.get("mouse_cut_end", body.global_position))
							camera_rig.begin_mouse_cut_cinematic(start, finish, body, BattleRules.MOUSE_AIR_HOLD + 0.14)
				var heavy := attack_name in ["punch_uppercut", "kick_front", "umbrella_uppercut", "umbrella_spin", "pot_slam", "pot_slam_air"]
				var damage := int(event.get("damage", 0))
				if attack_name == "umbrella_spin":
					var attacker := _body(str(event.get("attacker_id", "")))
					manager.feedback.spirit_hit(attacker, body.global_position + Vector3.UP * 0.9)
					manager.feedback.spirit_hit_feedback(body.global_position + Vector3.UP * 0.9, "-%d" % damage if damage > 0 else "")
				else:
					manager.feedback.impact(body.global_position + Vector3.UP * 0.9, heavy, 2 if heavy else 0, "-%d" % damage if damage > 0 else "", vector(event.get("velocity", [])))
				if str(event.get("attacker_id",""))==entity_id:
					manager.local_player.combo_count += 1
					manager.local_player.combo_timer = 1.2
			"blink":
				blink_events += 1
				var blink_slot := int(event.get("slot", -1))
				var blinker: Node = manager.local_player if blink_slot == slot else manager.puppet_for(blink_slot + 1)
				var blink_visual: Node3D = blinker.visual if blinker and blinker.get("visual") else null
				manager.feedback.blink_effect(vector(event.get("from",[]))+Vector3.UP,vector(event.get("to",[]))+Vector3.UP, blink_visual)
			"action_start":
				var index := int(event.get("slot",-1))
				var actor: Node = manager.local_player if index==slot else manager.puppet_for(index+1)
				if str(event.get("attack",""))=="returning_pot":
					if actor: _play_action(actor,"returning_pot")
				elif actor:
					_present_action_fx(actor, event)
			"round_end":
				manager.local_player.banner = "本回合平局" if bool(event.get("draw",false)) else "本回合结束：玩家%d 获胜" % (int(event.get("winner_slot",-1))+1)
				manager.local_player.banner_time = 2.5

func _sync_pots() -> void:
	var active := {}
	for owner in replay.sim.pots:
		var pot = replay.sim.pots[owner]
		var id := "%s:%d" % [owner,int(pot.attack_seq)]
		var body := _body(str(owner))
		if body==null: continue
		active[id] = true
		if not pot_visuals.has(id):
			var visual = PotVisual.new()
			visual.cosmetic = true
			manager.get_parent().add_child(visual)
			visual.global_position = pot.position
			visual.launch(body,pot.direction)
			visual.set_physics_process(false)
			pot_visuals[id] = visual
			body.active_pot = visual
		pot_targets[id] = pot.position
		var visual = pot_visuals[id]
		visual.returning = pot.returning
		visual.recalled = pot.recalled
	for id in pot_visuals.keys():
		if not active.has(id): _remove_pot(id)

func _remove_pot(id) -> void:
	var visual = pot_visuals[id]
	if is_instance_valid(visual.thrower) and visual.thrower.active_pot==visual: visual.thrower.active_pot = null
	visual.queue_free()
	pot_visuals.erase(id)
	pot_targets.erase(id)

func shutdown() -> void:
	closing = true
	var camera_rig := manager.get_parent().get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("set_mouse_cut_focus"):
		camera_rig.set_mouse_cut_focus("", Vector3.ZERO, Vector3.ZERO)
		camera_rig.cancel_mouse_cut_cinematic()
	local_render_offset = Vector3.ZERO
	local_correction_remaining = 0.0
	for view in npc_views.values(): view.queue_free()
	for id in pot_visuals.keys(): _remove_pot(id)
	if is_instance_valid(mouse_vfx): mouse_vfx.queue_free()
	replay.sim.dispose()
	if transport:
		_send({"type":"leave"})
		transport.close()
	if joined:
		manager.local_player.external_combat_view = false
		manager.local_player.collision_layer = original_layer
		manager.local_player.collision_mask = original_mask
		manager.local_player.set_physics_process(true)
	queue_free()

func join(address: String, port: int) -> Error:
	transport = PacketPeerUDP.new()
	last_packet = Time.get_ticks_msec()
	return transport.connect_to_host(address,port)

func _send(packet: Dictionary) -> void:
	if transport:
		packet.session = session
		transport.put_packet(JSON.stringify(packet).to_utf8_buffer())

static func vector(value) -> Vector3:
	if value is Array and value.size()==3:
		return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func _fail(reason: String) -> void:
	manager.leave_room(reason)

func _present_facing(body: Node, direction: Vector3, delta: float) -> void:
	# Spin owns the visual yaw while active. Logical facing never reads it back.
	if body.spin_time>0 or direction.length_squared()<0.001:
		return
	var yaw := atan2(-direction.x,-direction.z)
	body.visual.rotation.y = lerp_angle(body.visual.rotation.y,yaw,clampf(12.0*delta,0,1))

func _present_action_fx(body: Node, event: Dictionary) -> void:
	var attack := str(event.get("attack", ""))
	if attack in ["mouse_cast", "mouse_cut"]:
		manager.feedback.play_swing()
		return
	var facing := vector(event.get("facing", []))
	var delay := maxf(0.0, float(int(event.get("hit_tick", 0)) - int(event.get("tick", 0))) / 60.0)
	if attack == "umbrella_spin":
		manager.feedback.play_spin_fox(body, facing)
	if attack == "dash":
		return
	if attack == "kick_front":
		manager.feedback.play_swing()
		manager.feedback.play_kick(body, facing)
		return
	manager.feedback.play_swing()
	var feedback: Node = manager.feedback
	var play := func() -> void:
		if not is_instance_valid(body) or not is_instance_valid(feedback):
			return
		feedback.present_attack(attack, body.global_position, facing, body)
	if delay <= 0.02:
		play.call()
	else:
		get_tree().create_timer(delay).timeout.connect(play)

func _play_action(body: Node, attack: String, direction := Vector3.ZERO, aerial := false) -> void:
	if attack == "returning_pot":
		body.pot_span = 0.22
		body.pot_time = 0.22
	elif attack.begins_with("punch"):
		body.punch_time = BattleRules.punch_seconds(attack) if BattleRules.is_punch(attack) else 0.2
	elif attack == "kick_front":
		body.kick_time = BattleRules.skill_seconds(attack)
	elif attack == "umbrella_uppercut":
		body.uppercut_time = BattleRules.skill_seconds(attack)
	elif attack == "umbrella_spin":
		body.spin_facing = atan2(-direction.x,-direction.z) if direction.length_squared()>0.001 else body.visual.rotation.y
		body.spin_hit_done = true
		body.spin_time = BattleRules.skill_seconds(attack)
	elif attack == "pot_slam":
		body.pot_span = BattleRules.SLAM_AIR_ANIM if aerial else BattleRules.SLAM_GROUND_ANIM
		body.pot_time = body.pot_span
