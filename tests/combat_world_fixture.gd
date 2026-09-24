extends SceneTree
## Legacy rule regressions exercise the shared world, not a networking server.
const Core = preload("res://combat/combat_world.gd")
const Motion = Core.Motion
const Pot = Core.Pot
const Direction = Core.Direction
const BattleRules = Core.BattleRules
const AttackCatalogData = Core.AttackCatalogData
const DUMMY_SPAWNS = Core.DUMMY_SPAWNS
var sim = Core.new()
var peers := {}
var entities: Dictionary:
	get: return sim.entities
var pots: Dictionary:
	get: return sim.pots
var world: Node3D:
	get: return sim.world
	set(value): sim.world = value
var server_tick: int:
	get: return sim.server_tick
	set(value): sim.server_tick = value
var round_reset_at: int:
	get: return sim.round_reset_at
	set(value): sim.round_reset_at = value
var events: Array:
	get: return sim.events
func _build_world() -> void:
	Motion.build(world)
	for at in DUMMY_SPAWNS: sim._create_entity("dummy",-1,at)
func _pot_hit(owner: String, hit: Dictionary) -> void:
	var candidate: Dictionary = sim._probe_pot(owner,hit)
	if not candidate.is_empty(): sim._commit_hits([candidate])
func _apply_input(id: String, frame: Dictionary) -> void:
	var state: Dictionary = entities[id]
	state.move = Vector3(frame.move[0],0,frame.move[1])
	state.aim = Vector3(frame.aim[0],0,frame.aim[1])
	state.input_seq = int(frame.seq)
	state.last_input = sim.now_ms()
func _record_pose(_state: Dictionary) -> void:
	pass

func _create_entity(kind: String, slot: int, position: Vector3) -> String:
	return sim._create_entity(kind, slot, position)

func _resolve_attack(attacker_id: String, intent_id: String, at_hit_frame := false, requested_aim := Vector3.ZERO, from_buffer := false, view_tick := -1, rewind_tick := -1, attack_seq := -1) -> void:
	sim._resolve_attack(attacker_id, intent_id, at_hit_frame, requested_aim, from_buffer, view_tick, rewind_tick, attack_seq)

func _simulate_players(delta: float) -> void:
	sim._simulate_players(delta)

func _release_buffered_attack(id: String) -> void:
	sim._release_buffered_attack(id)

func _respawn_entity(state: Dictionary) -> void:
	sim._respawn_entity(state)

func _roster(kind := "player") -> Array:
	return sim._roster(kind)

func _scores() -> Array:
	return sim._scores()

func _on_entity_death(attacker_id: String, victim_id: String, award_round := true) -> void:
	sim._on_entity_death(attacker_id, victim_id, award_round)

func _reset_round_if_due() -> void:
	sim._reset_round_if_due()

func _advance_timelines(delta := 0.0) -> void:
	sim._advance_timelines(delta)

func _rewind_tick(_view_tick: int, _windup: int) -> int:
	return sim._rewind_tick(_view_tick, _windup)
