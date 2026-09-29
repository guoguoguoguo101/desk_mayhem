extends RefCounted

## Shared fixed-step combat world. No transport, UI, or wall clock.
const DEFAULT_PORT := 24680
const ACTIVE_CAPACITY := 2
const RESERVED_CAPACITY := 4
const SNAPSHOT_INTERVAL_MS := 33
const PEER_TIMEOUT_MS := 5000
const POSE_HISTORY := 16
const MAX_REWIND_TICKS := 12
const MOVE_SPEED := 6.5
const ATTACK_COOLDOWN_MS := 250
const ROUND_RESET_MS := 2500
const ArenaLayout = preload("res://combat/arena_layout.gd")
const ArenaCatalog = preload("res://combat/arena_catalog.gd")
const SPAWNS := ArenaLayout.PLAYER_SPAWNS
var last_trace_snap := -1
const CombatStateData = preload("res://combat/combat_state.gd")
const Motion = preload("res://combat/arena_motion.gd")
const Direction = preload("res://combat/attack_direction.gd")
const Pot = preload("res://combat/battle_pot.gd")
const CombatResolverData = preload("res://combat/combat_resolver.gd")
const AttackCatalogData = preload("res://combat/attack_catalog.gd")
const BattleRules = preload("res://combat/battle_rules.gd")
const FloatRules = preload("res://float_rules.gd")
const ATTACKS := {
	"punch_light": {"name": "轻拳", "motion": ""},
	"punch_follow": {"name": "连拳", "motion": ""},
	"kick_front": {"name": "前踢", "motion": ""},
	"punch_uppercut": {"name": "上勾拳", "motion": "uppercut_launch"},
	"umbrella_uppercut": {"name": "雨伞挑飞", "motion": "umbrella_launch"},
	"umbrella_spin": {"name": "旋伞", "motion": ""},
	"pot_slam": {"name": "扣锅", "motion": "ground_slam"},
	"mouse_cast": {"name": "甩鼠标", "motion": ""},
	"mouse_cut": {"name": "剪切闪", "motion": "mouse_launch"},
}


const SCHEMA := 5
const DUMMY_SPAWNS := ArenaLayout.DUMMY_SPAWNS
var map_id := ArenaCatalog.COURTYARD
var arena_layout = ArenaLayout
var entities: Dictionary = {}
var pots: Dictionary = {}
var server_tick := 0
var round_id := 1
var round_reset_at := 0
var next_entity_id := 1
var next_pot_id := 1
var next_action_serial := 1
var world: Node3D
var viewport: SubViewport
var events: Array = []
var recent_events: Array = []

func attach(parent: Node) -> void:
	# Separate physics space: never collide with display models or another simulator.
	viewport = SubViewport.new()
	viewport.world_3d = World3D.new()
	viewport.size = Vector2i(2,2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	Motion.build(world, arena_layout)

func configure_arena(next_map_id: String) -> void:
	assert(viewport == null, "Arena must be selected before attaching the combat world.")
	map_id = ArenaCatalog.normalize(next_map_id)
	arena_layout = ArenaCatalog.layout(map_id)

func player_spawns() -> Array[Vector3]:
	return arena_layout.PLAYER_SPAWNS

func dummy_spawns() -> Array[Vector3]:
	return arena_layout.DUMMY_SPAWNS

func dispose() -> void:
	if is_instance_valid(viewport): viewport.queue_free()

func now_ms() -> int:
	return int(server_tick * 1000.0 / BattleRules.PHYSICS_HZ)

func remove_entity(id: String) -> void:
	if not entities.has(id): return
	entities[id].body.collision_layer = 0
	entities[id].body.free()
	entities.erase(id)
	pots.erase(id)

func step(commands: Array = []) -> Array:
	server_tick += 1
	events = []
	_reset_round_if_due()
	var ordered := commands.duplicate(true)
	ordered.sort_custom(func(a,b):
		if str(a.entity_id) == str(b.entity_id): return int(a.seq) < int(b.seq)
		return str(a.entity_id) < str(b.entity_id))
	var actions: Array = []
	for command in ordered:
		var id := str(command.entity_id)
		if not entities.has(id): continue
		var state: Dictionary = entities[id]
		if int(command.get("round_id",round_id))!=round_id or int(command.get("life",state.life))!=int(state.life): continue
		if int(command.seq) > int(state.input_seq):
			state.input_seq = int(command.seq)
			state.move = command.get("move",Vector3.ZERO)
			state.aim = command.get("aim",state.facing)
			state.last_input = now_ms()
		var receipts: Dictionary = state.get("command_receipts",{})
		for action in command.get("actions",[]):
			var seq := str(int(action.attack_seq))
			if receipts.has(seq): continue
			receipts[seq] = server_tick
			actions.append({"entity_id":id,"action":action})
		while receipts.size()>128: receipts.erase(receipts.keys()[0])
		state.command_receipts = receipts
	_simulate_players(Motion.DT)
	_tick_mouse_links()
	for request in actions:
		var action: Dictionary = request.action
		_resolve_attack(str(request.entity_id),str(action.attack),false,action.aim,false,-1,-1,int(action.attack_seq))
	_advance_mouse_cut()
	_advance_timelines(Motion.DT)
	_advance_mouse_projectiles()
	return events

func _simulate_players(delta: float) -> void:
	var ids: Array = entities.keys()
	ids.sort()
	var obstacles: Dictionary = {}
	for id in ids: obstacles[id] = dynamic_blockers(str(id))
	for id in ids:
		var state: Dictionary = entities[id]
		if bool(state.get("dead",false)):
			if state.kind=="dummy" and now_ms()>=int(state.respawn_at): _respawn_entity(state)
			continue
		if round_reset_at>0 and state.kind=="player": continue
		if now_ms()-int(state.get("last_input",0))>200: state.move = Vector3.ZERO
		var was_dashing := float(state.get("dash",0.0))>0.0
		Motion.step(state.body,state,state.move,delta,obstacles[id])
		if state.kind=="player" and was_dashing and not bool(state.get("dash_hit",false)):
			_resolve_dash_contact(id)
		_release_buffered_attack(id)

func _resolve_dash_contact(attacker_id: String) -> void:
	var attacker: Dictionary = entities[attacker_id]
	var direction: Vector3 = attacker.get("dash_direction",Vector3.FORWARD)
	var best_id := ""
	var best_distance := INF
	for victim_id in entities.keys():
		if victim_id==attacker_id: continue
		var victim: Dictionary = entities[victim_id]
		if bool(victim.get("dead",false)) or int(victim.get("health",0))<=0 or float(victim.get("protection",0.0))>0.0: continue
		var offset: Vector3 = victim.position-attacker.position
		if absf(offset.y)>2.2: continue
		offset.y = 0.0
		var distance := offset.length()
		if distance>1.25 or (distance>0.15 and offset.normalized().dot(direction)<=0.15): continue
		if distance<best_distance:
			best_distance = distance
			best_id = victim_id
	if best_id.is_empty(): return
	var victim: Dictionary = entities[best_id]
	var combat_state = CombatStateData.new()
	combat_state.health = int(victim.health)
	combat_state.max_health = int(victim.max_health)
	var resolved = CombatResolverData.resolve_hit(combat_state,"雨伞",AttackCatalogData.PROFILE_PVP)
	var velocity: Vector3 = victim.get("velocity",Vector3.ZERO)
	velocity.x = direction.x*3.0
	velocity.z = direction.z*3.0
	var hit := {"attacker_id":attacker_id,"victim_id":best_id,"attack":"dash","attack_seq":int(attacker.get("dash_seq",-1)),"serial":int(attacker.get("dash_serial",0)),"order":0,"damage":int(resolved.damage),"stun":0.15,"presented":{"velocity":velocity,"juggled":bool(victim.get("juggled",false)),"kick_bounce":bool(victim.get("kick_bounce",false)),"bounce_pending":bool(victim.get("bounce_pending",false)),"knockdown":false},"rank":0,"juggled_before":bool(victim.get("juggled",false))}
	attacker.dash_hit = true
	attacker.dash = 0.0
	attacker.velocity.x = 0.0
	attacker.velocity.z = 0.0
	_commit_hits([hit])

func dynamic_blockers(id: String) -> Array:
	var result: Array = []
	if entities[id].kind!="player": return result
	for other in entities:
		if entities[other].kind=="dummy" and not bool(entities[other].dead):
			result.append(entities[other].position)
	return result

func capture() -> Dictionary:
	var rows := {}
	for id in entities:
		var row: Dictionary = entities[id].duplicate(true)
		row.erase("body")
		row.erase("inputs")
		row.erase("pose_history")
		rows[id] = row
	var projectiles := {}
	for owner in pots: projectiles[owner] = pots[owner].capture()
	return {"schema":SCHEMA,"map_id":map_id,"tick":server_tick,"round_id":round_id,"round_reset_at":round_reset_at,
		"next_entity_id":next_entity_id,"next_pot_id":next_pot_id,"next_action_serial":next_action_serial,
		"entities":rows,"pots":projectiles,"events":recent_events.duplicate(true)}

func restore(snapshot: Dictionary) -> void:
	assert(int(snapshot.schema)==SCHEMA)
	assert(ArenaCatalog.normalize(str(snapshot.get("map_id", map_id))) == map_id)
	server_tick = int(snapshot.tick)
	round_id = int(snapshot.round_id)
	round_reset_at = int(snapshot.round_reset_at)
	next_entity_id = int(snapshot.next_entity_id)
	next_pot_id = int(snapshot.next_pot_id)
	next_action_serial = int(snapshot.next_action_serial)
	for id in entities.keys():
		if not snapshot.entities.has(id): remove_entity(id)
	var ids: Array = snapshot.entities.keys()
	ids.sort()
	for id in ids:
		var row: Dictionary = snapshot.entities[id].duplicate(true)
		var body: CharacterBody3D = entities[id].body if entities.has(id) else Motion.character(world,row.position)
		row.body = body
		row.inputs = {}
		body.global_position = row.position
		body.velocity = row.get("velocity",Vector3.ZERO)
		if row.kind=="dummy": Motion.configure_dummy(body,false)
		entities[id] = row
	pots.clear()
	for owner in snapshot.pots:
		var pot = Pot.new()
		pot.restore(snapshot.pots[owner])
		pots[owner] = pot
	recent_events = snapshot.get("events",[]).duplicate(true)
	events = []

func _broadcast(payload: Dictionary) -> void:
	payload.tick = server_tick
	payload.round_id = round_id
	if payload.get("type","")=="action_start":
		for state in entities.values():
			if int(state.slot)==int(payload.slot):
				payload.attack_seq = int(state.get("action_seq",-1))
				payload.actor_life = int(state.life)
				payload.entity_id = str(state.entity_id)
				payload.facing = [state.facing.x,state.facing.y,state.facing.z]
	events.append(payload)
	recent_events.append(payload.duplicate(true))
	while recent_events.size()>64: recent_events.pop_front()

func _rewind_tick(_view_tick: int, _windup: int) -> int:
	return -1 # One world time for geometry, airborne state and damage.

func _find_melee_target(attacker_id: String, definition: Dictionary, direction: Vector3, _tick := -1) -> String:
	return _select_melee_target(attacker_id,definition,direction)

func _create_entity(kind: String, slot: int, position: Vector3) -> String:
	var id := "entity_%d" % next_entity_id
	next_entity_id += 1
	var hp := 2000 if kind=="dummy" else 400
	entities[id] = {"entity_id":id,"kind":kind,"controller":"passive" if kind=="dummy" else "player","slot":slot,"team_id":-1 if kind=="dummy" else slot,"max_health":hp,"health":hp,"spawn":position,"position":position,"velocity":Vector3.ZERO,"move":Vector3.ZERO,"facing":Vector3.RIGHT if slot==0 else Vector3.LEFT,"input_seq":0,"inputs":{},"life":1,"dead":false,"death_count":0,"respawn_at":0,"body":Motion.character(world,position)}
	entities[id].mouse_projectile = {}
	entities[id].mouse_link_id = ""
	entities[id].mouse_link_life = 0
	entities[id].mouse_link_until = 0
	entities[id].mouse_cast_ready = 0
	entities[id].mouse_skill2_ready = 0
	entities[id].mouse_air_hold = 0.0
	entities[id].mouse_air_used = false
	entities[id].mouse_air_direction = Vector3.ZERO
	entities[id].mouse_cut_path = []
	entities[id].mouse_cut_targets = {}
	entities[id].mouse_cut_blocked = false
	entities[id].mouse_cut_start = position
	entities[id].mouse_cut_end = position
	if kind=="dummy":
		Motion.configure_dummy(entities[id].body,false)
	return id

func _link_closed(attacker: Dictionary, intent_id: String) -> bool:
	if intent_id == "umbrella_uppercut":
		return false
	if float(attacker.get("dash", 0.0)) > 0.0 and intent_id != "dash":
		return true
	if BattleRules.chainable(intent_id):
		return float(attacker.get("lock", 0.0)) > 0.0 and server_tick < int(attacker.get("cancel_tick", 0))
	return float(attacker.get("lock", 0.0)) > 0.0 or server_tick < int(attacker.get("cancel_tick", 0))

func _buffer_press(attacker: Dictionary, intent_id: String) -> bool:
	# A dash is not a recovery window. Remember presses that are waiting on the previous action.
	return not (float(attacker.get("dash", 0.0)) > 0.0 and float(attacker.get("lock", 0.0)) <= 0.0 and intent_id != "umbrella_uppercut")

func _remember_attack(attacker: Dictionary, intent_id: String, aim: Vector3, view_tick := -1, attack_seq := -1) -> void:
	var now := now_ms()
	if str(attacker.get("buffer_attack", "")) == intent_id and now <= int(attacker.get("buffer_until", 0)):
		if int(attacker.get("buffer_seq", -1)) > 0 and int(attacker.get("buffer_seq", -1)) != attack_seq:
			_deny_attack(str(attacker.get("entity_id", "")), int(attacker.buffer_seq))
		attacker.buffer_aim = aim
		attacker.buffer_view_tick = view_tick
		attacker.buffer_seq = attack_seq
		return
	if int(attacker.get("buffer_seq", -1)) > 0:
		_deny_attack(str(attacker.get("entity_id", "")), int(attacker.buffer_seq))
	attacker.buffer_attack = intent_id
	attacker.buffer_aim = aim
	attacker.buffer_view_tick = view_tick
	attacker.buffer_seq = attack_seq
	attacker.buffer_until = now + BattleRules.BUFFER_MS

func _attack_mark(state: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [state.get("action", ""), state.get("action_tick", 0), state.get("dash", 0), state.get("followup", 0), pots.has(str(state.get("entity_id", ""))), state.get("mouse_link_id", ""), state.get("mouse_cast_ready", 0), state.get("mouse_skill2_ready", 0), state.get("cooldown_blink", 0)]

func _release_buffered_attack(id: String) -> void:
	if not entities.has(id):
		return
	var state: Dictionary = entities[id]
	var intent := str(state.get("buffer_attack", ""))
	if intent == "":
		return
	if now_ms() > int(state.get("buffer_until", 0)) or int(state.health) <= 0 or bool(state.get("dead", false)):
		_deny_attack(id, int(state.get("buffer_seq", -1)))
		state.buffer_attack = ""
		state.buffer_seq = -1
		return
	if _link_closed(state, intent):
		return
	var aim: Vector3 = state.get("buffer_aim", state.facing)
	var mark := _attack_mark(state)
	_resolve_attack(id, intent, false, aim, true, int(state.get("buffer_view_tick", -1)), -1, int(state.get("buffer_seq", -1)))
	if _attack_mark(state) != mark:
		state.buffer_attack = ""

func _nearby_juggled(attacker_id: String, reach: float, height_limit: float) -> bool:
	var origin: Vector3 = entities[attacker_id].position
	for victim_id in entities.keys():
		if victim_id == attacker_id:
			continue
		var victim: Dictionary = entities[victim_id]
		if int(victim.health) <= 0 or bool(victim.get("dead", false)) or not bool(victim.get("juggled", false)):
			continue
		if float(victim.get("protection", 0.0)) > 0.0:
			continue
		var delta: Vector3 = victim.position - origin
		if absf(delta.y) <= height_limit and Vector2(delta.x, delta.z).length() <= reach:
			return true
	return false

func _try_blink(attacker: Dictionary, direction: Vector3, now: int, attack_seq: int, hit_reacting: bool) -> void:
	var attacker_id := str(attacker.get("entity_id", ""))
	if float(attacker.get("dash", 0.0)) > 0.0 or now < int(attacker.get("cooldown_blink", 0)):
		_deny_attack(attacker_id, attack_seq)
		return
	if not hit_reacting and float(attacker.get("lock", 0.0)) > 0.0:
		_deny_attack(attacker_id, attack_seq)
		return
	var start: Vector3 = attacker.position
	if not Motion.blink(attacker.body, attacker, direction, dynamic_blockers(attacker_id)):
		_deny_attack(attacker_id, attack_seq)
		return
	attacker.facing = direction
	attacker.cooldown_blink = now + BattleRules.cooldown_ms("blink")
	if hit_reacting:
		attacker.stun = 0.0
		attacker.protection = 0.0
		attacker.knockdown_time = 0.0
		attacker.juggled = false
		attacker.kick_bounce = false
		attacker.bounce_pending = false
		attacker.velocity = Vector3.ZERO
		attacker.lock = 0.0
		attacker.action = ""
		attacker.dash = 0.0
	_broadcast({"type":"blink","slot":attacker.slot,"attack_seq":attack_seq,"from":[start.x,start.y,start.z],"to":[attacker.position.x,attacker.position.y,attacker.position.z]})

func _mouse_link_valid(state: Dictionary) -> bool:
	var target_id := str(state.get("mouse_link_id", ""))
	if target_id.is_empty() or server_tick >= int(state.get("mouse_link_until", 0)) or not entities.has(target_id):
		return false
	var target: Dictionary = entities[target_id]
	return int(state.get("health", 0)) > 0 and not bool(state.get("dead", false)) and int(target.get("health", 0)) > 0 and not bool(target.get("dead", false)) and int(target.get("life", 0)) == int(state.get("mouse_link_life", -1))

func _clear_mouse_link(state: Dictionary) -> void:
	if str(state.get("mouse_link_id", "")).is_empty():
		return
	state.mouse_link_id = ""
	state.mouse_link_life = 0
	state.mouse_link_until = 0
	state.mouse_cast_ready = now_ms() + BattleRules.cooldown_ms("mouse_cast")

func _tick_mouse_links() -> void:
	for state in entities.values():
		if not str(state.get("mouse_link_id", "")).is_empty() and not _mouse_link_valid(state):
			_clear_mouse_link(state)

func _resolve_mouse_action(attacker_id: String, intent_id: String, requested_aim: Vector3, attack_seq: int, from_buffer: bool) -> void:
	if map_id != ArenaCatalog.MOUNTAIN_COURTYARD:
		_deny_attack(attacker_id, attack_seq)
		return
	var attacker: Dictionary = entities[attacker_id]
	var now := now_ms()
	if _link_closed(attacker, intent_id):
		if not from_buffer and _buffer_press(attacker, intent_id):
			_remember_attack(attacker, intent_id, requested_aim, -1, attack_seq)
		elif not from_buffer:
			_deny_attack(attacker_id, attack_seq)
		return
	if intent_id == "mouse_cast":
		if now < int(attacker.get("mouse_cast_ready", 0)) or not str(attacker.get("mouse_link_id", "")).is_empty() or not attacker.get("mouse_projectile", {}).is_empty():
			_deny_attack(attacker_id, attack_seq)
			return
		var horizontal := Direction.resolve(attacker.facing, requested_aim)
		var pitch_y := clampf(requested_aim.y, -sin(deg_to_rad(35.0)), sin(deg_to_rad(35.0)))
		var flight_direction := (horizontal * sqrt(maxf(0.0, 1.0 - pitch_y * pitch_y)) + Vector3.UP * pitch_y).normalized()
		attacker.facing = horizontal
		attacker.action = "mouse_cast"
		attacker.action_tick = server_tick
		attacker.action_cursor = 0
		attacker.action_serial = next_action_serial
		attacker.action_seq = attack_seq
		attacker.action_direction = flight_direction
		attacker.lock = float(BattleRules.MOUSE_CAST_STARTUP + 1) / BattleRules.PHYSICS_HZ
		attacker.end_tick = server_tick + BattleRules.MOUSE_CAST_STARTUP + 1
		attacker.cancel_tick = attacker.end_tick
		attacker.buffer_attack = ""
		attacker.buffer_seq = -1
		next_action_serial += 1
		_broadcast({"type":"action_start","slot":attacker.slot,"attack":"mouse_cast","tick":server_tick,"hit_tick":server_tick+BattleRules.MOUSE_CAST_STARTUP,"end_tick":attacker.end_tick})
		return
	if intent_id == "mouse_pull":
		if not _mouse_link_valid(attacker):
			_deny_attack(attacker_id, attack_seq)
			return
		var target_id := str(attacker.mouse_link_id)
		var target: Dictionary = entities[target_id]
		var previous: Vector3 = target.position
		var toward: Vector3 = attacker.position - target.position
		if not bool(target.get("juggled", false)):
			toward.y = 0.0
		elif absf(toward.y) > 2.0:
			toward.y = signf(toward.y) * 2.0
		var travel := toward.normalized() * minf(toward.length(), BattleRules.MOUSE_PULL_DISTANCE) if toward.length_squared() > 0.0001 else Vector3.ZERO
		if travel.length_squared() > 0.0001:
			target.body.move_and_collide(travel)
			target.position = target.body.global_position
		target.stun = maxf(float(target.get("stun", 0.0)), BattleRules.MOUSE_PULL_STUN)
		var velocity: Vector3 = target.get("velocity", Vector3.ZERO)
		velocity.x = 0.0
		velocity.z = 0.0
		target.velocity = velocity
		attacker.lock = 0.12
		attacker.action_seq = attack_seq
		_clear_mouse_link(attacker)
		_broadcast({"type":"mouse_pull","entity_id":attacker_id,"target_id":target_id,"attack_seq":attack_seq,"from":[previous.x,previous.y,previous.z],"to":[target.position.x,target.position.y,target.position.z]})
		return
	if now < int(attacker.get("mouse_skill2_ready", 0)):
		_deny_attack(attacker_id, attack_seq)
		return
	if intent_id == "mouse_swap":
		if not _mouse_link_valid(attacker):
			if not attacker.get("mouse_projectile", {}).is_empty():
				if not from_buffer:
					_remember_attack(attacker, intent_id, requested_aim, -1, attack_seq)
				return
			_deny_attack(attacker_id, attack_seq)
			return
		var target_id := str(attacker.mouse_link_id)
		var target: Dictionary = entities[target_id]
		if not _mouse_swap_clear(attacker, target):
			_deny_attack(attacker_id, attack_seq)
			return
		var source: Vector3 = attacker.position
		var destination: Vector3 = target.position
		attacker.body.global_position = destination
		target.body.global_position = source
		attacker.position = destination
		target.position = source
		for state in [attacker, target]:
			var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
			velocity.x = 0.0
			velocity.z = 0.0
			state.velocity = velocity
			state.stun = maxf(float(state.get("stun", 0.0)), BattleRules.MOUSE_SWAP_STUN)
		attacker.action_seq = attack_seq
		attacker.mouse_skill2_ready = now + BattleRules.cooldown_ms("mouse_swap")
		_clear_mouse_link(attacker)
		_broadcast({"type":"mouse_swap","entity_id":attacker_id,"target_id":target_id,"attack_seq":attack_seq,"from":[source.x,source.y,source.z],"to":[destination.x,destination.y,destination.z]})
		return
	if intent_id == "mouse_cut":
		if _mouse_link_valid(attacker):
			_deny_attack(attacker_id, attack_seq)
			return
		var cut_direction := Direction.resolve(attacker.facing, requested_aim)
		attacker.facing = cut_direction
		attacker.action = "mouse_cut"
		attacker.action_tick = server_tick
		attacker.action_cursor = 0
		attacker.action_serial = next_action_serial
		attacker.action_seq = attack_seq
		attacker.action_direction = cut_direction
		attacker.mouse_cut_start = attacker.position
		attacker.mouse_cut_end = attacker.position
		attacker.mouse_cut_path = []
		attacker.mouse_cut_targets = {}
		attacker.mouse_cut_blocked = false
		attacker.lock = float(BattleRules.MOUSE_CUT_END_TICK) / BattleRules.PHYSICS_HZ
		attacker.end_tick = server_tick + BattleRules.MOUSE_CUT_END_TICK
		attacker.cancel_tick = attacker.end_tick
		attacker.mouse_skill2_ready = now + BattleRules.cooldown_ms("mouse_cut")
		attacker.buffer_attack = ""
		attacker.buffer_seq = -1
		next_action_serial += 1
		_broadcast({"type":"action_start","slot":attacker.slot,"attack":"mouse_cut","tick":server_tick,"hit_tick":server_tick+BattleRules.MOUSE_CUT_DAMAGE_TICK,"end_tick":attacker.end_tick})
		return
	_deny_attack(attacker_id, attack_seq)

func _mouse_swap_clear(attacker: Dictionary, target: Dictionary) -> bool:
	var space := world.get_world_3d().direct_space_state
	for pair in [[attacker, target.position], [target, attacker.position]]:
		var actor: Dictionary = pair[0]
		var destination: Vector3 = pair[1]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = actor.body.get_child(0).shape
		query.transform = Transform3D(Basis(), destination)
		query.collision_mask = 128 | Motion.NPC_LAYER
		query.exclude = [attacker.body.get_rid(), target.body.get_rid()]
		for collision in space.intersect_shape(query, 8):
			var collider: Object = collision.get("collider")
			if collider is Node and str(collider.get_meta("arena_layout_id", "")) == "floor":
				continue
			return false
	return true

func _spawn_mouse_projectile(attacker_id: String, attack_seq: int) -> void:
	var attacker: Dictionary = entities[attacker_id]
	var direction: Vector3 = attacker.get("action_direction", attacker.facing)
	var flat := Direction.horizontal(direction)
	var origin: Vector3 = attacker.position + Vector3.UP * 0.46 + flat * 0.55
	attacker.mouse_projectile = {"position":origin,"direction":direction.normalized(),"distance":0.0,"attack_seq":attack_seq,"owner_life":int(attacker.life)}
	_broadcast({"type":"mouse_launch","entity_id":attacker_id,"attack_seq":attack_seq,"position":[origin.x,origin.y,origin.z],"direction":[direction.x,direction.y,direction.z]})

func _advance_mouse_projectiles() -> void:
	if map_id != ArenaCatalog.MOUNTAIN_COURTYARD:
		return
	for attacker_id in entities.keys():
		var attacker: Dictionary = entities[attacker_id]
		var flight: Dictionary = attacker.get("mouse_projectile", {})
		if flight.is_empty():
			continue
		if bool(attacker.get("dead", false)) or int(attacker.life) != int(flight.owner_life):
			attacker.mouse_projectile = {}
			continue
		var start: Vector3 = flight.position
		var remaining := BattleRules.MOUSE_RANGE - float(flight.distance)
		var amount := minf(BattleRules.MOUSE_SPEED * Motion.DT, remaining)
		if amount <= 0.001:
			_finish_mouse_miss(attacker_id, int(flight.attack_seq))
			continue
		var aimed: Vector3 = flight.direction
		var horizontal := Direction.horizontal(aimed)
		var pitch_blend := clampf((float(flight.distance) + amount * 0.5) / BattleRules.MOUSE_PITCH_RAMP_DISTANCE, 0.0, 1.0)
		var step_direction := (horizontal * sqrt(maxf(0.0, 1.0 - aimed.y * aimed.y * pitch_blend * pitch_blend)) + Vector3.UP * aimed.y * pitch_blend).normalized()
		var finish: Vector3 = start + step_direction * amount
		var wall_fraction := _mouse_wall_fraction(start, finish)
		var target_id := ""
		var first := wall_fraction
		for victim_id in entities.keys():
			if victim_id == attacker_id:
				continue
			var victim: Dictionary = entities[victim_id]
			if bool(victim.get("dead", false)) or int(victim.get("health", 0)) <= 0 or float(victim.get("protection", 0.0)) > 0.0:
				continue
			var radius := BattleRules.MOUSE_CATCH_RADIUS + (0.27 if str(victim.kind) == "dummy" else 0.0)
			var half_axis := BattleRules.MOUSE_CATCH_HALF_HEIGHT
			var fraction := _mouse_capsule_fraction(start, finish, victim.position, radius, half_axis)
			if fraction < first:
				first = fraction
				target_id = str(victim_id)
		flight.position = start.lerp(finish, first)
		flight.distance = float(flight.distance) + amount * first
		attacker.mouse_projectile = flight
		if not target_id.is_empty():
			var target: Dictionary = entities[target_id]
			attacker.mouse_projectile = {}
			attacker.mouse_link_id = target_id
			attacker.mouse_link_life = int(target.life)
			attacker.mouse_link_until = server_tick + BattleRules.MOUSE_LINK_TICKS
			target.stun = maxf(float(target.get("stun", 0.0)), 0.12)
			_broadcast({"type":"mouse_link","entity_id":attacker_id,"target_id":target_id,"target_life":int(target.life),"attack_seq":int(flight.attack_seq),"position":[flight.position.x,flight.position.y,flight.position.z]})
		elif wall_fraction < 1.0 or float(flight.distance) >= BattleRules.MOUSE_RANGE - 0.001:
			_finish_mouse_miss(attacker_id, int(flight.attack_seq))

func _finish_mouse_miss(attacker_id: String, seq: int) -> void:
	var attacker: Dictionary = entities[attacker_id]
	attacker.mouse_projectile = {}
	attacker.mouse_cast_ready = now_ms() + BattleRules.cooldown_ms("mouse_cast")
	_broadcast({"type":"mouse_miss","entity_id":attacker_id,"attack_seq":seq})

func _mouse_wall_fraction(start: Vector3, finish: Vector3) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BattleRules.MOUSE_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), start)
	query.motion = finish - start
	query.collision_mask = 128
	var cast := world.get_world_3d().direct_space_state.cast_motion(query)
	return clampf(cast[0], 0.0, 1.0) if cast.size() > 0 else 1.0

func _mouse_capsule_fraction(start: Vector3, finish: Vector3, center: Vector3, radius: float, half_axis: float) -> float:
	var low := 0.0
	var high := 1.0
	for _i in 12:
		var left := lerpf(low, high, 0.333333)
		var right := lerpf(low, high, 0.666667)
		if _mouse_capsule_distance_sq(start.lerp(finish, left), center, half_axis) < _mouse_capsule_distance_sq(start.lerp(finish, right), center, half_axis):
			high = right
		else:
			low = left
	var closest := (low + high) * 0.5
	if _mouse_capsule_distance_sq(start.lerp(finish, closest), center, half_axis) > radius * radius:
		return INF
	low = 0.0
	high = closest
	for _i in 14:
		var mid := (low + high) * 0.5
		if _mouse_capsule_distance_sq(start.lerp(finish, mid), center, half_axis) <= radius * radius:
			high = mid
		else:
			low = mid
	return high

func _mouse_capsule_distance_sq(point: Vector3, center: Vector3, half_axis: float) -> float:
	var axis := center + Vector3.UP * clampf(point.y - center.y, -half_axis, half_axis)
	return point.distance_squared_to(axis)

func _advance_mouse_cut() -> void:
	if map_id != ArenaCatalog.MOUNTAIN_COURTYARD:
		return
	for attacker_id in entities.keys():
		var attacker: Dictionary = entities[attacker_id]
		if str(attacker.get("action", "")) != "mouse_cut" or bool(attacker.get("dead", false)):
			continue
		var elapsed := server_tick - int(attacker.action_tick)
		if elapsed < BattleRules.MOUSE_CUT_STARTUP or elapsed >= BattleRules.MOUSE_CUT_STARTUP + BattleRules.MOUSE_CUT_TRAVEL_TICKS or bool(attacker.get("mouse_cut_blocked", false)):
			continue
		var start: Vector3 = attacker.position
		var direction: Vector3 = attacker.action_direction
		var distance := BattleRules.MOUSE_CUT_DISTANCE / float(BattleRules.MOUSE_CUT_TRAVEL_TICKS)
		var body: CharacterBody3D = attacker.body
		var previous_mask := body.collision_mask
		body.collision_mask = 128
		var wall := body.move_and_collide(direction * distance)
		body.collision_mask = previous_mask
		var finish: Vector3 = body.global_position
		attacker.position = finish
		attacker.mouse_cut_end = finish
		var path: Array = attacker.get("mouse_cut_path", [])
		path.append([start, finish])
		attacker.mouse_cut_path = path
		for victim_id in entities.keys():
			if victim_id == attacker_id:
				continue
			var victim: Dictionary = entities[victim_id]
			if bool(victim.get("dead", false)) or int(victim.get("health", 0)) <= 0 or float(victim.get("protection", 0.0)) > 0.0:
				continue
			if _mouse_cut_touches(start, finish, victim.position):
				var targets: Dictionary = attacker.mouse_cut_targets
				targets[str(victim_id)] = int(victim.life)
				attacker.mouse_cut_targets = targets
		if wall != null:
			attacker.mouse_cut_blocked = true

func _mouse_cut_touches(start: Vector3, finish: Vector3, target: Vector3) -> bool:
	var flat := Vector2(finish.x-start.x, finish.z-start.z)
	var offset := Vector2(target.x-start.x, target.z-start.z)
	var ratio := clampf(offset.dot(flat) / maxf(flat.length_squared(), 0.00001), 0.0, 1.0)
	var nearest := start.lerp(finish, ratio)
	return Vector2(target.x-nearest.x, target.z-nearest.z).length() <= BattleRules.MOUSE_CUT_RADIUS and absf(target.y-nearest.y) <= BattleRules.MOUSE_CUT_HEIGHT

func _mouse_cut_hits(attacker_id: String, seq: int, serial: int) -> Array:
	var attacker: Dictionary = entities[attacker_id]
	var start: Vector3 = attacker.get("mouse_cut_start", attacker.position)
	var finish: Vector3 = attacker.get("mouse_cut_end", attacker.position)
	var direction: Vector3 = attacker.get("action_direction", attacker.facing)
	_broadcast({"type":"mouse_cut_burst","entity_id":attacker_id,"attack_seq":seq,"from":[start.x,start.y,start.z],"to":[finish.x,finish.y,finish.z]})
	var hits: Array = []
	var targets: Dictionary = attacker.get("mouse_cut_targets", {})
	for victim_id in targets.keys():
		if not entities.has(victim_id):
			continue
		var victim: Dictionary = entities[victim_id]
		if int(victim.life) != int(targets[victim_id]) or bool(victim.get("dead", false)) or int(victim.get("health", 0)) <= 0 or float(victim.get("protection", 0.0)) > 0.0:
			continue
		var juggled := bool(victim.get("juggled", false)) and not bool(victim.get("bounce_pending", false))
		var combat_state = CombatStateData.new()
		combat_state.health = int(victim.health)
		combat_state.max_health = int(victim.max_health)
		combat_state.juggled = juggled
		var resolved = CombatResolverData.resolve_hit(combat_state, "剪切闪", AttackCatalogData.PROFILE_PVP)
		var presented := BattleRules.present_hit("mouse_cut", direction, victim.position.y, victim.get("velocity", Vector3.ZERO), juggled, bool(victim.get("kick_bounce", false)), bool(victim.get("bounce_pending", false)))
		if juggled and bool(victim.get("mouse_air_used", false)):
			presented.velocity = victim.get("velocity", Vector3.ZERO)
		hits.append({"attacker_id":attacker_id,"victim_id":str(victim_id),"attack":"mouse_cut","attack_seq":seq,"serial":serial,"order":0,"damage":int(resolved.damage),"stun":float(presented.stun),"presented":presented,"rank":BattleRules.motion_rank("mouse_cut", juggled),"juggled_before":juggled})
	return hits

func _resolve_attack(attacker_id: String, intent_id: String, at_hit_frame := false, requested_aim := Vector3.ZERO, from_buffer := false, view_tick := -1, rewind_tick := -1, attack_seq := -1) -> void:
	if not entities.has(attacker_id):
		return
	if round_reset_at > 0:
		_deny_attack(attacker_id, attack_seq)
		return
	var attacker: Dictionary = entities[attacker_id]
	var attack_direction: Vector3 = requested_aim if at_hit_frame else Direction.resolve(attacker.facing,requested_aim)
	var now := now_ms()
	var hit_reacting := float(attacker.get("stun",0.0)) > 0.0 or bool(attacker.get("juggled",false)) or bool(attacker.get("kick_bounce",false))
	if int(attacker.health) <= 0 or (hit_reacting and intent_id != "blink"):
		attacker.buffer_attack = ""
		attacker.buffer_seq = -1
		_deny_attack(attacker_id, attack_seq)
		return
	if not at_hit_frame:
		# Q selection is authoritative; a second press can precede the next snapshot.
		if intent_id == "umbrella_primary":
			intent_id = "umbrella_uppercut" if now<int(attacker.get("followup",0)) else "dash"
		if intent_id.begins_with("mouse_"):
			_resolve_mouse_action(attacker_id, intent_id, requested_aim, attack_seq, from_buffer)
			return
		if intent_id == "returning_pot" and pots.has(attacker_id):
			pots[attacker_id].returning = true
			pots[attacker_id].recalled = true
			return
		if intent_id not in ["punch","kick_front","umbrella_uppercut","umbrella_spin","pot_slam","dash","jump","blink","returning_pot"]:
			return
		if intent_id == "blink":
			if str(attacker.get("action", "")) == "mouse_cast" and _link_closed(attacker, "blink") and not from_buffer:
				_remember_attack(attacker, "blink", attack_direction, view_tick, attack_seq)
				return
			_try_blink(attacker, attack_direction, now, attack_seq, hit_reacting)
			return
		if _link_closed(attacker, intent_id):
			if not from_buffer and _buffer_press(attacker, intent_id):
				_remember_attack(attacker, intent_id, attack_direction, view_tick, attack_seq)
			elif not from_buffer:
				_deny_attack(attacker_id, attack_seq)
			return
		if not from_buffer:
			attacker.buffer_attack = ""
		if intent_id == "returning_pot":
			if float(attacker.get("dash",0))>0 or now<int(attacker.get("cooldown_returning_pot",0)):
				_deny_attack(attacker_id, attack_seq)
				return
			var pot = Pot.new()
			pot.id = next_pot_id
			next_pot_id += 1
			pot.owner = attacker_id
			pot.direction = attack_direction
			pot.attack_seq = attack_seq
			pot.serial = next_action_serial
			next_action_serial += 1
			attacker.facing = attack_direction
			# Start at the hand height; step sweeps the whole path, including near walls.
			pot.position = attacker.position+Vector3.UP*0.85
			pots[attacker_id] = pot
			attacker.cooldown_returning_pot = now + BattleRules.cooldown_ms("returning_pot")
			attacker.action_seq = attack_seq
			attacker.pot_pose_tick = server_tick
			attacker.lock = 0.18
			attacker.cancel_tick = server_tick+11
			_broadcast({"type":"action_start","slot":attacker.slot,"attack":"returning_pot","tick":server_tick,"end_tick":server_tick+14})
			return
		if intent_id == "jump":
			if attacker.position.y < 1.0:
				var jump_velocity: Vector3 = attacker.get("velocity",Vector3.ZERO)
				jump_velocity.y = 7.5
				attacker.velocity = jump_velocity
			else:
				_deny_attack(attacker_id, attack_seq)
			return
		if intent_id == "dash":
			if now < int(attacker.get("dash_ready",0)):
				_deny_attack(attacker_id, attack_seq)
				return
			# Umbrella Q is committed movement, not a camera-aimed strike. Match the
			# local player path: lock the dash to the body's current horizontal facing.
			var dash_direction := Direction.horizontal(attacker.facing)
			attacker.dash = 0.38
			attacker.dash_hit = false
			attacker.dash_seq = attack_seq
			attacker.dash_serial = next_action_serial
			next_action_serial += 1
			attacker.dash_direction = dash_direction
			attacker.facing = dash_direction
			attacker.dash_ready = now + BattleRules.cooldown_ms("dash")
			attacker.followup = now + int(BattleRules.FOLLOWUP_WINDOW * 1000.0)
			return
		if intent_id == "umbrella_uppercut" and now >= int(attacker.get("followup",0)):
			_deny_attack(attacker_id, attack_seq)
			return
		if intent_id == "umbrella_uppercut":
			attacker.followup = 0
			attacker.dash = 0.0
		if intent_id == "punch":
			intent_id = BattleRules.punch_id_at(int(attacker.get("combo",0)), int(attacker.get("combo_until",0)), now)
		if not ATTACKS.has(intent_id):
			_deny_attack(attacker_id, attack_seq)
			return
		if now < int(attacker.get("cooldown_"+intent_id,0)):
			_deny_attack(attacker_id, attack_seq)
			return
		var aerial := intent_id == "pot_slam" and _nearby_juggled(attacker_id, BattleRules.SLAM_RANGE, BattleRules.SLAM_HEIGHT)
		if intent_id in ["umbrella_spin","pot_slam"]:
			attacker["cooldown_"+intent_id] = now + BattleRules.cooldown_ms(intent_id)
		var frame := BattleRules.skill_frame(intent_id, aerial)
		if frame.is_empty():
			_deny_attack(attacker_id, attack_seq)
			return
		var windup := int(frame.startup)
		var recovery := BattleRules.skill_total(intent_id, aerial)
		if str(frame.get("hop", "")) == "slam":
			attacker.aerial = aerial
			attacker.velocity = BattleRules.slam_startup(attacker.get("velocity", Vector3.ZERO), attack_direction, aerial, attacker.position.y < 1.3)
			attacker.slam_hold = float(windup) / BattleRules.PHYSICS_HZ
		else:
			attacker.aerial = false
		attacker.ready_at = now + int(recovery*1000.0/60.0)
		attacker.facing = attack_direction
		attacker.lock = float(recovery)/60.0
		attacker.action = intent_id
		attacker.action_tick = server_tick
		attacker.action_cursor = 0
		attacker.action_direction = attack_direction
		attacker.action_view_tick = view_tick
		attacker.action_windup = windup
		attacker.action_serial = next_action_serial
		attacker.action_seq = attack_seq
		next_action_serial += 1
		var hit_at := windup
		var cancel_at := windup + int(frame.cancel_delay)
		var end_at := recovery
		for event in BattleRules.combat_timeline(intent_id, aerial):
			match str(event.get("kind", "")):
				"hit":
					hit_at = int(event.tick)
				"cancel_open":
					cancel_at = int(event.tick)
				"end":
					end_at = int(event.tick)
		attacker.hit_tick = server_tick + hit_at
		attacker.end_tick = server_tick + end_at
		attacker.cancel_tick = server_tick + cancel_at
		attacker.buffer_attack = ""
		attacker.buffer_seq = -1
		_broadcast({"type":"action_start","slot":attacker.slot,"attack":intent_id,"tick":server_tick,"hit_tick":server_tick+windup,"end_tick":server_tick+recovery,"aerial":aerial,"facing":[attack_direction.x,attack_direction.y,attack_direction.z]})
		return
	var hit := _probe_melee(attacker_id, intent_id, attack_direction, rewind_tick, attack_seq, int(attacker.get("action_serial", 0)))
	if not hit.is_empty():
		_commit_hits([hit])

func _probe_melee(attacker_id: String, intent_id: String, attack_direction: Vector3, rewind_tick: int, attack_seq: int, serial: int) -> Dictionary:
	if not entities.has(attacker_id) or not ATTACKS.has(intent_id):
		_deny_attack(attacker_id, attack_seq)
		return {}
	var attacker: Dictionary = entities[attacker_id]
	var definition := BattleRules.skill_frame(intent_id)
	if definition.is_empty() or not definition.has("reach"):
		_deny_attack(attacker_id, attack_seq)
		return {}
	if rewind_tick >= 0:
		rewind_tick = clampi(rewind_tick, server_tick - MAX_REWIND_TICKS, server_tick)
	var target_id := _find_melee_target(attacker_id, definition, attack_direction, rewind_tick)
	if target_id.is_empty():
		_deny_attack(attacker_id, attack_seq)
		return {}
	var victim: Dictionary = entities[target_id]
	var juggled := bool(victim.get("juggled", false))
	var frame := BattleRules.skill_frame(intent_id)
	if BattleRules.is_punch(intent_id):
		attacker.combo = BattleRules.confirm_punch(int(attacker.get("combo", 0)))
		attacker.combo_until = now_ms() + BattleRules.PUNCH_LINK_MS
	var attack: Dictionary = ATTACKS[intent_id]
	var damage_name := str(frame.name) if not frame.is_empty() else str(attack["name"])
	if not frame.is_empty() and juggled:
		damage_name = str(frame.air_name)
	var combat_state = CombatStateData.new()
	combat_state.health = int(victim["health"])
	combat_state.max_health = int(victim.get("max_health", 400))
	combat_state.juggled = juggled
	var hit_event = CombatResolverData.resolve_hit(combat_state, damage_name, AttackCatalogData.PROFILE_PVP)
	var direction: Vector3 = victim["position"] - attacker["position"]
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	var incoming: Vector3 = victim.get("velocity", Vector3.ZERO)
	var presented := BattleRules.present_hit(intent_id, direction, victim.position.y, incoming, juggled, bool(victim.get("kick_bounce", false)), bool(victim.get("bounce_pending", false)))
	return {
		"attacker_id": attacker_id,
		"victim_id": target_id,
		"attack": intent_id,
		"attack_seq": attack_seq,
		"serial": serial,
		"order": 0,
		"damage": int(hit_event.damage),
		"stun": float(presented.stun),
		"presented": presented,
		"rank": BattleRules.motion_rank(intent_id, juggled),
		"juggled_before": juggled,
	}

func _probe_pot(owner: String, hit: Dictionary) -> Dictionary:
	if not entities.has(owner) or not entities.has(hit.peer):
		return {}
	var victim: Dictionary = entities[hit.peer]
	if int(victim.health) <= 0 or bool(victim.get("dead", false)):
		return {}
	var juggled := bool(victim.get("juggled", false)) and not bool(victim.get("bounce_pending", false))
	var state = CombatStateData.new()
	state.health = victim.health
	var event = CombatResolverData.resolve_hit(state, "回旋锅·回收" if hit.returning else "回旋锅", AttackCatalogData.PROFILE_PVP)
	var velocity: Vector3 = victim.get("velocity", Vector3.ZERO)
	velocity.x = hit.push.x
	velocity.z = hit.push.z
	if juggled:
		if hit.returning:
			velocity.y = maxf(velocity.y, -1.0)
		else:
			velocity.y = maxf(velocity.y, FloatRules.POT_LIFT_SPEED)
	var attack := "returning_pot_back" if hit.returning else "returning_pot_out"
	var presented := {"velocity": velocity, "juggled": bool(victim.get("juggled", false)), "kick_bounce": bool(victim.get("kick_bounce", false)), "bounce_pending": bool(victim.get("bounce_pending", false)), "stun": 0.25, "knockdown": false}
	var pot_seq := int(pots[owner].attack_seq) if pots.has(owner) else -1
	var serial := int(pots[owner].serial) if pots.has(owner) else 0
	return {
		"attacker_id": owner,
		"victim_id": hit.peer,
		"attack": attack,
		"attack_seq": pot_seq,
		"serial": serial,
		"order": 1 if hit.returning else 0,
		"damage": int(event.damage),
		"stun": 0.25,
		"presented": presented,
		"rank": BattleRules.motion_rank(attack, juggled),
		"juggled_before": juggled,
	}

func _commit_hits(hits: Array) -> void:
	if hits.is_empty():
		return
	var groups := {}
	for hit in hits:
		var victim_id := str(hit.victim_id)
		if not groups.has(victim_id):
			groups[victim_id] = []
		groups[victim_id].append(hit)
	var fallen_players: Array = []
	for victim_id in groups.keys():
		if not entities.has(victim_id):
			continue
		var list: Array = groups[victim_id]
		list.sort_custom(func(a, b):
			if int(a.rank) != int(b.rank):
				return int(a.rank) > int(b.rank)
			if int(a.serial) != int(b.serial):
				return int(a.serial) < int(b.serial)
			return int(a.order) < int(b.order)
		)
		var chosen: Dictionary = list[0]
		var damage := 0
		var stun := 0.0
		for hit in list:
			damage += int(hit.damage)
			stun = maxf(stun, float(hit.stun))
		var victim: Dictionary = entities[victim_id]
		var health := maxi(0, int(victim.health) - damage)
		victim.health = health
		var presented: Dictionary = chosen.presented
		var velocity: Vector3 = presented.velocity
		victim.velocity = velocity
		victim.juggled = bool(presented.juggled)
		victim.kick_bounce = bool(presented.kick_bounce)
		victim.bounce_pending = bool(presented.bounce_pending)
		victim.stun = stun
		if bool(presented.knockdown):
			victim.knockdown_time = stun
		victim.dash = 0.0
		victim.buffer_attack = ""
		victim.buffer_seq = -1
		victim.action = ""
		victim.end_tick = server_tick
		if str(chosen.attack) == "mouse_cut" and bool(chosen.juggled_before) and not bool(victim.get("mouse_air_used", false)):
			victim.mouse_air_hold = BattleRules.MOUSE_AIR_HOLD
			victim.mouse_air_used = true
			victim.mouse_air_direction = entities[chosen.attacker_id].get("action_direction", Vector3.FORWARD)
		elif str(chosen.attack) != "mouse_cut":
			victim.mouse_air_hold = 0.0
		victim.last_attacker = str(chosen.attacker_id)
		victim.last_attack = str(chosen.attack)
		victim.last_hit_tick = server_tick
		for hit in list:
			var attacker: Dictionary = entities[hit.attacker_id]
			var receipts: Array = victim.get("hit_receipts",[])
			receipts.append({"attacker":hit.attacker_id,"seq":int(hit.attack_seq),"attack":hit.attack,"tick":server_tick})
			if receipts.size()>32: receipts.pop_front()
			victim.hit_receipts = receipts
			_broadcast({
				"type": "combat",
				"attacker_slot": attacker["slot"],
				"attacker_id": hit.attacker_id,
				"victim_id": victim_id,
				"victim_life": victim.get("life", 1),
				"victim_slot": victim["slot"],
				"attack": hit.attack,
				"damage": int(hit.damage),
				"health": health,
				"lethal": health <= 0,
				"velocity": [velocity.x, velocity.y, velocity.z],
				"attack_seq": int(hit.attack_seq),
			})
		if health <= 0 and not bool(victim.get("dead", false)):
			if str(victim.get("kind", "player")) == "player":
				fallen_players.append({"victim_id": victim_id, "attacker_id": str(chosen.attacker_id)})
			else:
				_on_entity_death(str(chosen.attacker_id), victim_id, false)
	if fallen_players.size() >= 2:
		for row in fallen_players:
			_on_entity_death(str(row.attacker_id), str(row.victim_id), false)
		_finish_draw()
	elif fallen_players.size() == 1:
		_on_entity_death(str(fallen_players[0].attacker_id), str(fallen_players[0].victim_id), true)

func _finish_round(attacker: Dictionary) -> void:
	attacker["score"] = int(attacker.get("score",0))+1
	round_reset_at = now_ms()+ROUND_RESET_MS
	_broadcast({"type":"round_end","winner_slot":attacker.slot,"scores":_scores()})

func _finish_draw() -> void:
	if round_reset_at > 0:
		return
	round_reset_at = now_ms() + ROUND_RESET_MS
	_broadcast({"type": "round_end", "draw": true, "winner_slot": -1, "scores": _scores()})

func _advance_timelines(delta := 0.0) -> void:
	var due: Array = []
	for id in entities.keys():
		var state: Dictionary = entities[id]
		var attack := str(state.get("action", ""))
		if attack == "":
			continue
		var timeline := BattleRules.combat_timeline(attack, bool(state.get("aerial", false)))
		var elapsed := server_tick - int(state.get("action_tick", server_tick))
		var cursor := int(state.get("action_cursor", 0))
		var serial := int(state.get("action_serial", 0))
		var order := 0
		while cursor < timeline.size() and int(timeline[cursor].get("tick", 0)) <= elapsed:
			due.append({
				"id": id,
				"kind": str(timeline[cursor].get("kind", "")),
				"attack": attack,
				"action_tick": int(state.get("action_tick", 0)),
				"serial": serial,
				"order": order,
				"direction": state.get("action_direction", state.get("facing", Vector3.FORWARD)),
				"view_tick": int(state.get("action_view_tick", -1)),
				"windup": int(state.get("action_windup", 0)),
				"attack_seq": int(state.get("action_seq", -1)),
			})
			order += 1
			cursor += 1
		state.action_cursor = cursor
	due.sort_custom(func(a, b):
		if int(a.serial) == int(b.serial):
			return int(a.order) < int(b.order)
		return int(a.serial) < int(b.serial)
	)
	var eligible := {}
	for id in entities.keys():
		var actor: Dictionary = entities[id]
		eligible[id] = int(actor.get("health", 0)) > 0 and not bool(actor.get("dead", false)) and float(actor.get("stun", 0.0)) <= 0.0 and not bool(actor.get("juggled", false)) and not bool(actor.get("kick_bounce", false))
	var hits: Array = []
	for item in due:
		if str(item.kind) != "hit":
			continue
		if not entities.has(item.id):
			continue
		var swinger: Dictionary = entities[item.id]
		if int(swinger.get("action_tick", -1)) != int(item.action_tick):
			continue
		if str(swinger.get("action", "")) != "" and str(swinger.get("action", "")) != str(item.attack):
			continue
		if not bool(eligible.get(item.id, false)):
			_deny_attack(str(item.id), int(item.get("attack_seq", -1)))
			continue
		if str(item.attack) == "mouse_cast":
			_spawn_mouse_projectile(str(item.id), int(item.get("attack_seq", -1)))
			continue
		if str(item.attack) == "mouse_cut":
			hits.append_array(_mouse_cut_hits(str(item.id), int(item.get("attack_seq", -1)), int(item.serial)))
			continue
		var rewind := _rewind_tick(int(item.view_tick), int(item.windup))
		var hit := _probe_melee(str(item.id), str(item.attack), item.direction, rewind, int(item.get("attack_seq", -1)), int(item.serial))
		if not hit.is_empty():
			hit.order = int(item.order)
			hits.append(hit)
	if delta > 0.0 and round_reset_at == 0:
		hits.append_array(_gather_pot_hits(delta))
	_commit_hits(hits)
	for item in due:
		if str(item.kind)=="end" and entities.has(item.id):
			var state: Dictionary = entities[item.id]
			if int(state.get("action_serial",-1))==int(item.serial):
				state.action = ""
				state.lock = 0.0

func _gather_pot_hits(delta: float) -> Array:
	var hits: Array = []
	for owner in pots.keys():
		if not pots.has(owner):
			continue
		var pot = pots[owner]
		for hit in pot.step(world.get_world_3d().direct_space_state, entities, delta):
			var probed := _probe_pot(str(owner), hit)
			if not probed.is_empty():
				hits.append(probed)
		if pot.finished:
			pots.erase(owner)
	return hits

func _deny_attack(attacker_id: String, seq: int) -> void:
	if seq <= 0 or not entities.has(attacker_id):
		return
	_broadcast({"type": "attack_result", "attack_seq": seq, "confirmed": false, "slot": int(entities[attacker_id].get("slot", -1))})

func _select_melee_target(attacker_id: String, definition: Dictionary, attack_direction: Vector3) -> String:
	var attacker: Dictionary = entities[attacker_id]
	var best_id := ""
	var best_distance := INF
	for victim_id in entities.keys():
		if victim_id == attacker_id:
			continue
		var victim: Dictionary = entities[victim_id]
		if int(victim["health"]) <= 0:
			continue
		if float(victim.get("protection",0.0)) > 0:
			continue
		var airborne := bool(victim.get("juggled", false))
		var delta: Vector3 = victim["position"] - attacker["position"]
		if absf(delta.y) > BattleRules.melee_height(definition, airborne):
			continue
		var flat := Vector3(delta.x, 0.0, delta.z)
		var distance := flat.length()
		if distance > BattleRules.melee_reach(definition, airborne) or distance < 0.01:
			continue
		var facing: Vector3 = attack_direction
		if facing.dot(flat / distance) < float(definition.get("dot", -1.0)):
			continue
		var query := PhysicsRayQueryParameters3D.create(attacker.position, victim.position, 128)
		if not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		if distance < best_distance:
			best_distance = distance
			best_id = victim_id
	return best_id

func _roster(kind := "player") -> Array:
	var result: Array = []
	for peer_id in entities.keys():
		var state: Dictionary = entities[peer_id]
		if state.get("kind","player") != kind:
			continue
		var position: Vector3 = state["position"]
		var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
		result.append({"entity_id":peer_id,"kind":state.get("kind","player"),"life":state.get("life",1),"dead":state.get("dead",false),"max_health":state.get("max_health",400),"respawn_ms":maxi(0,int(state.get("respawn_at",0))-now_ms()),"slot": state["slot"], "position": [position.x, position.y, position.z], "velocity": [velocity.x, velocity.y, velocity.z], "health": state["health"], "score": state.get("score", 0), "juggled": state.get("juggled", false)})
		var row: Dictionary = result.back()
		row.hit_receipts = state.get("hit_receipts",[])
		row.slam_hold = state.get("slam_hold",0.0)
		var control: Vector3 = state.get("move",Vector3.ZERO)
		row.move = [control.x,control.y,control.z]
		for key in ["input_seq","action","action_tick","hit_tick","end_tick","cancel_tick","lock","dash","stun","protection","kick_bounce","bounce_pending","knockdown_time"]:
			row[key] = state.get(key, "" if key == "action" else 0)
		var facing: Vector3 = state.facing
		row.facing = [facing.x,facing.y,facing.z]
		var dash_direction: Vector3 = state.get("dash_direction",facing)
		row.dash_direction = [dash_direction.x,dash_direction.y,dash_direction.z]
		row.aerial = bool(state.get("aerial", false))
		row.followup = maxf(0.0, float(int(state.get("followup",0))-now_ms())/1000.0)
		row.combo = int(state.get("combo", 0))
		row.combo_left = maxf(0.0, float(int(state.get("combo_until",0))-now_ms())/1000.0)
		row.last_attacker = str(state.get("last_attacker", ""))
		row.last_attack = str(state.get("last_attack", ""))
		row.last_hit_tick = int(state.get("last_hit_tick", 0))
		row.cooldowns = {}
		for ability in ["dash","umbrella_spin","pot_slam","blink","returning_pot"]:
			var key: String = "dash_ready" if ability=="dash" else "cooldown_"+ability
			row.cooldowns[ability] = maxf(0.0,float(int(state.get(key,0))-now_ms())/1000.0)
	return result

func _scores() -> Array:
	var result: Array = []
	for peer_id in entities.keys():
		if entities[peer_id].get("kind","player")!="player":
			continue
		result.append({"slot": entities[peer_id]["slot"], "score": entities[peer_id].get("score", 0)})
	return result

func _reset_round_if_due() -> void:
	if round_reset_at==0 or now_ms()<round_reset_at:
		return
	round_reset_at = 0
	round_id += 1
	for state in entities.values():
		if state.kind=="player":
			_respawn_entity(state)
	pots.clear()
	_broadcast({"type":"round_reset","players":_roster(),"npcs":_roster("dummy")})

func _on_entity_death(attacker_id: String, victim_id: String, award_round := true) -> void:
	var victim: Dictionary = entities[victim_id]
	if bool(victim.get("dead",false)):
		return
	victim.dead = true
	if victim.get("kind","")=="dummy":
		Motion.configure_dummy(victim.body,false)
	victim.death_count = int(victim.get("death_count",0))+1
	victim.health = 0
	victim.velocity = Vector3.ZERO
	victim.juggled = false
	victim.kick_bounce = false
	victim.bounce_pending = false
	victim.action = ""
	victim.mouse_projectile = {}
	victim.mouse_air_hold = 0.0
	_clear_mouse_link(victim)
	for owner in entities.values():
		if str(owner.get("mouse_link_id", "")) == victim_id:
			_clear_mouse_link(owner)
	pots.erase(victim_id)
	if victim.get("kind","player")=="dummy":
		victim.respawn_at = now_ms()+3000
	_broadcast({"type":"entity_death","entity_id":victim_id,"life":victim.get("life",1),"attacker_id":attacker_id})
	if award_round and victim.get("kind","player")=="player" and entities.has(attacker_id) and entities[attacker_id].get("kind","player")=="player" and round_reset_at==0:
		_finish_round(entities[attacker_id])

func _respawn_entity(state: Dictionary) -> void:
	state.life = int(state.get("life",1))+1
	state.health = state.max_health
	state.dead = false
	state.hit_receipts = []
	if state.kind=="dummy":
		Motion.configure_dummy(state.body,false)
	state.position = state.spawn
	state.body.global_position = state.spawn
	state.velocity = Vector3.ZERO
	state.move = Vector3.ZERO
	state.inputs.clear()
	for key in ["stun","lock","cancel_tick","end_tick","action_tick","hit_tick","ready_at","followup","dash_ready","combo","combo_until","dash","protection","respawn_at","cooldown_blink","cooldown_returning_pot","cooldown_pot_slam","cooldown_umbrella_spin","mouse_cast_ready","mouse_skill2_ready","mouse_link_until","mouse_link_life","mouse_air_hold"]:
		state[key] = 0
	for key in ["juggled","kick_bounce","bounce_pending","air_hold_used"]:
		state[key] = false
	state.buffer_attack = ""
	state.buffer_seq = -1
	state.slam_hold = 0.0
	state.pot_pose_tick = -1000
	state.action = ""
	state.mouse_projectile = {}
	state.mouse_link_id = ""
	state.mouse_air_used = false
	state.mouse_air_direction = Vector3.ZERO
	state.mouse_cut_path = []
	state.mouse_cut_targets = {}
	state.mouse_cut_blocked = false
	state.action_cursor = 0
	state.last_attacker = ""
	state.last_attack = ""
	state.last_hit_tick = 0
	state.knockdown_time = 0.0
	state.pose_history = []
	state.facing = Vector3.RIGHT if int(state.slot)==0 else Vector3.LEFT
	_broadcast({"type":"entity_respawn","entity_id":state.entity_id,"life":state.life})
