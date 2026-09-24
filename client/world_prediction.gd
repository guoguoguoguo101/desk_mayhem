extends RefCounted
## A complete speculative world, restored atomically before replaying commands.
const Core = preload("res://combat/combat_world.gd")
const MAX_HISTORY := 180
const MAX_LEAD := 18
var sim = Core.new()
var authority: Dictionary = {}
var history: Array = []
var snapshots: Dictionary = {}
var entity_id := ""
var snapshot_tick := -1
var replay_steps := 0
var corrections := 0
var max_correction := 0.0
var last_correction := 0.0
var same_tick_error := 0.0
var compared_entities := 0
var timeline_rebases := 0

func receive(snapshot: Dictionary, lead := 3) -> Array:
	if int(snapshot.get("schema",0))!=Core.SCHEMA or int(snapshot.tick)<=snapshot_tick: return []
	var old_tick: int = sim.server_tick
	var old_position: Vector3 = sim.entities.get(entity_id,{}).get("position",Vector3.ZERO)
	var historical: Dictionary = snapshots.get(int(snapshot.tick),{}).get("entities",{})
	same_tick_error = 0.0
	for id in historical:
		if not snapshot.entities.has(id) or int(historical[id].life)!=int(snapshot.entities[id].life): continue
		compared_entities += 1
		same_tick_error = maxf(same_tick_error,(historical[id].position as Vector3).distance_to(snapshot.entities[id].position))
	var prior_life := int(authority.get("entities",{}).get(entity_id,{}).get("life",0))
	authority = snapshot.duplicate(true)
	snapshot_tick = int(snapshot.tick)
	var own: Dictionary = snapshot.entities.get(entity_id,{})
	var same_life := prior_life==0 or prior_life==int(own.get("life",0))
	var kept: Array = []
	for command in history:
		if not same_life or int(command.get("round_id",snapshot.round_id))!=int(snapshot.round_id): continue
		var frame: Dictionary = command.duplicate(true)
		var actions: Array = []
		for action in frame.actions:
			if not own.get("command_receipts",{}).has(str(int(action.attack_seq))): actions.append(action)
		frame.actions = actions
		if int(frame.seq)<=int(own.get("input_seq",0)) and actions.is_empty(): continue
		# A late command is still pending, not an already-confirmed impulse.
		if int(frame.tick)<=snapshot_tick: timeline_rebases += 1
		frame.tick = maxi(int(frame.tick),snapshot_tick+1)
		kept.append(frame)
	history = kept
	sim.restore(snapshot)
	snapshots.clear()
	_save()
	var horizon := clampi(maxi(old_tick,snapshot_tick+lead),snapshot_tick,snapshot_tick+MAX_LEAD)
	var emitted: Array = []
	while sim.server_tick<horizon:
		emitted.append_array(_step_history())
	last_correction = old_position.distance_to(sim.entities.get(entity_id,{}).get("position",old_position))
	if prior_life>0 and same_life:
		max_correction = maxf(max_correction,last_correction)
		if last_correction>0.05: corrections += 1
	return emitted

func predict(command: Dictionary) -> Array:
	history.append(command.duplicate(true))
	while history.size()>MAX_HISTORY: history.pop_front()
	var commands := _scheduled(sim.server_tick+1)
	commands.append(command)
	var result: Array = sim.step(commands)
	_save()
	return result

func _step_history() -> Array:
	var commands: Array = _scheduled(sim.server_tick+1)
	for frame in history:
		if int(frame.tick)==sim.server_tick+1: commands.append(frame)
	replay_steps += 1
	var result: Array = sim.step(commands)
	_save()
	return result

func _scheduled(tick: int) -> Array:
	var commands: Array = []
	for frame in authority.get("scheduled_commands",[]):
		if int(frame.tick)==tick: commands.append(frame)
	return commands

func _save() -> void:
	snapshots[sim.server_tick] = sim.capture()
	while snapshots.size()>MAX_HISTORY: snapshots.erase(snapshots.keys()[0])
