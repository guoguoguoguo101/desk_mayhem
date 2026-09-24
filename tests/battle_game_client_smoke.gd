extends Node

var network: Node
var started_at := 0
var entered := false
var entered_at := 0
var next_attack := 0
var saw_damage := false
var saw_air := false
var saw_peer := false
var saw_pot := false
var sent_pot := false
var sent_blink := false
var sent_recall := false
var saw_crosshair := false
var saw_npcs := false

func _ready() -> void:
	started_at = Time.get_ticks_msec()
	network = get_parent()
	await get_tree().process_frame
	if network.address_input.text != "127.0.0.1":
		push_error("BATTLE_GAME_CLIENT default address missing")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			network.session_port = int(arg.trim_prefix("--port="))
	network.start_battle_client()

func _process(_delta: float) -> void:
	if network.phase == "play" and network.using_battle_server():
		if not entered:
			entered = true
			entered_at = Time.get_ticks_msec()
			print("BATTLE_GAME_CLIENT_SMOKE entered slot=%d" % network.local_player.slot_index)
		var player: Node = network.local_player
		saw_crosshair = saw_crosshair or network.get_parent().get_node("HUD").crosshair.visible
		player.scripted_drive = true
		var session: Node = network.get_node("BattleClientSession")
		saw_npcs = saw_npcs or session.npc_views.size()==2
		saw_pot = saw_pot or not session.pot_visuals.is_empty()
		var elapsed := Time.get_ticks_msec()-entered_at
		if session.slot==0:
			if elapsed>500 and not sent_pot:
				session.request_action("skill_b0",Vector3.RIGHT)
				sent_pot = true
			if elapsed>800 and not sent_blink:
				session.request_action("blink",Vector3.RIGHT)
				sent_blink = true
			if elapsed>1000 and not sent_recall:
				session.request_action("skill_b0",Vector3.RIGHT)
				sent_recall = true
		var target: Node = network.puppet_for(2 if session.slot == 0 else 1)
		if target:
			saw_peer = true
			var difference: Vector3 = target.global_position-player.global_position
			difference.y = 0
			player.scripted_aim = difference.normalized()
			player.scripted_move = difference.normalized() if session.slot==0 and difference.length()>1.65 else Vector3.ZERO
			saw_damage = saw_damage or player.health < 400 or target.health < 400
			saw_air = saw_air or player.juggled or target.juggled
			if session.slot == 0 and difference.length()<1.9 and Time.get_ticks_msec()>next_attack:
				session.request_action("punch",difference.normalized())
				next_attack = Time.get_ticks_msec()+260
		if Time.get_ticks_msec() - entered_at > 14000:
			if not (saw_npcs and saw_peer and saw_damage and saw_air and saw_pot and session.blink_events>0 and saw_crosshair):
				push_error("BATTLE_GAME_CLIENT FAIL peer=%s damage=%s air=%s" % [saw_peer,saw_damage,saw_air])
				get_tree().quit(1)
				return
			print("BATTLE_GAME_CLIENT PASS default_ip crosshair peer damage air pot blink prediction_seq=%d pending=%d" % [session.input_seq,session.history.size()])
			network.leave_room("test finished")
			get_tree().quit()
			return
	if not entered and Time.get_ticks_msec() - started_at > 8000:
		push_error("BATTLE_GAME_CLIENT_SMOKE timeout phase=%s" % network.phase)
		get_tree().quit(1)
