extends Node
var network: Node
var started := 0
var combo_tick := -1
var sent := {}
var hits := {}
var target_id := ""
var seen := {}
const PRESS := {1:"skill_a0",8:"skill_a0",25:"skill_a1",78:"skill_b0",93:"skill_a0",100:"skill_a0",119:"skill_b1"}
func _ready() -> void:
	started = Time.get_ticks_msec()
	network = get_parent()
	await get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): network.session_port = int(arg.trim_prefix("--port="))
	network.start_battle_client()
func _process(_delta: float) -> void:
	if Time.get_ticks_msec()-started>22000:
		push_error("NETWORK_COMBO timeout")
		get_tree().quit(1)
		return
	var session = network.get_node_or_null("BattleClientSession")
	if session==null or not session.joined or session.replay.authority.is_empty(): return
	var sim = session.replay.sim
	var player = network.local_player
	player.scripted_drive = true
	if target_id=="":
		var ids: Array = session.npc_views.keys()
		ids.sort()
		if ids.size()!=2: return
		target_id = str(ids[session.slot])
	if not sim.entities.has(target_id) or session.predicted.is_empty(): return
	var gap: Vector3 = sim.entities[target_id].position-session.predicted.position
	gap.y = 0
	player.scripted_aim = gap.normalized()
	player.scripted_move = gap.normalized() if gap.length()>1.4 else Vector3.ZERO
	if combo_tick<0 and gap.length()<1.7 and session.rtt_ms>0: combo_tick = sim.server_tick
	for event in session.replay.authority.get("events",[]):
		if event.get("type","")!="combat" or event.get("attacker_id","")!=session.entity_id or event.get("victim_id","")!=target_id: continue
		var key := "%s:%s" % [event.get("attack_seq",0),event.get("attack","")]
		if seen.has(key): continue
		seen[key] = true
		var attack := str(event.attack)
		hits[attack] = int(hits.get(attack,0))+1
	if combo_tick<0: return
	var elapsed: int = sim.server_tick-combo_tick
	for tick in PRESS:
		if elapsed>=int(tick) and not sent.has(tick):
			sent[tick] = true
			session.request_action(PRESS[tick],player.scripted_aim)
	if elapsed>119: player.scripted_move = Vector3.ZERO
	if elapsed<230: return
	var ok := int(hits.get("umbrella_uppercut",0))>=2 and hits.has("umbrella_spin") and hits.has("returning_pot_out") and hits.has("pot_slam")
	print("NETWORK_COMBO slot=%d authority_hits=%s rtt=%d rebases=%d" % [session.slot,hits,session.rtt_ms,session.replay.timeline_rebases])
	if not ok: push_error("NETWORK_COMBO authoritative sequence incomplete")
	else: print("BATTLE_GAME_CLIENT PASS full-world network combo")
	network.leave_room("combo test finished")
	get_tree().quit(0 if ok else 1)
