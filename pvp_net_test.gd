extends Node

const TEST_PORT := 24681

var role := ""
var born := 0
var match_at := 0
var notes: PackedStringArray = []
var saw_move := false
var saw_jump := false
var saw_snapshots := false
var asked_jump := false
var sent_hit := false
var hit_at := 0
var saw_combat_event := false
var finished := false

func _ready() -> void:
	role = get_parent().pvp_test_role()
	born = Time.get_ticks_msec()
	get_parent().session_port = TEST_PORT
	call_deferred("begin")

func begin() -> void:
	var net: Node = get_parent()
	if role == "host":
		net.start_hall()
		note("主机监听 %d" % TEST_PORT)
	elif role == "join":
		net.address_input.text = "127.0.0.1"
		net.start_join()
		note("客户端连接 127.0.0.1:%d" % TEST_PORT)
	else:
		fail("未知角色")
		finish()

func _process(_delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_msec()
	if now - born > 18000:
		fail("超时")
		finish()
		return
	var net: Node = get_parent()
	if role == "host":
		step_host(net, now)
	else:
		step_join(net, now)

func step_join(net: Node, now: int) -> void:
	if not net.in_match():
		return
	if match_at == 0:
		match_at = now
		note("已进入比武")
	var player: Node = net.local_player
	var foe: Node = net.first_puppet()
	var aim := Vector3(-1, 0, 0)
	if player.global_position.x < -10.0:
		aim = Vector3.ZERO
	if foe and foe.net_samples.size() >= 2:
		saw_snapshots = true
	player.scripted_drive = true
	player.scripted_move = aim
	player.scripted_aim = aim if aim.length_squared() > 0.001 else Vector3(-1, 0, 0)
	if not saw_move and player.global_position.x < 8.0:
		saw_move = true
		note("本机已移动 x=%.2f" % player.global_position.x)
	if not asked_jump and now - match_at > 400 and player.is_on_floor():
		asked_jump = true
		player.replicate_action("jump")
		player.jump()
		note("已发送跳跃")
	if asked_jump and not saw_jump and (player.velocity.y > 3.0 or player.global_position.y > 1.6):
		saw_jump = true
		note("本机跳起 y=%.2f" % player.global_position.y)
	if int(player.health) < int(player.max_health) and bool(player.juggled):
		var event = net.last_confirmed_combat_event
		if event and int(event.victim_peer) == multiplayer.get_unique_id() and str(event.effect_method) == "launch_up":
			saw_combat_event = true
		note("收到击飞 hp=%d" % int(player.health))
		if not saw_move:
			fail("没有观察到本机移动")
		if not saw_jump:
			fail("没有观察到本机跳跃")
		if not saw_snapshots:
			fail("对手位置没有插值缓冲")
		if not saw_combat_event:
			fail("没有收到服务器确认的 CombatEvent")
		finish()

func step_host(net: Node, now: int) -> void:
	if not net.in_match():
		return
	var foe: Node = net.first_puppet()
	if foe == null:
		return
	if match_at == 0:
		match_at = now
		note("傀儡模拟=%s 我=%s 锁=%s" % [
			str(bool(foe.net_simulated)), str(net.local_player.global_position), str(bool(net.local_player.controls_locked)),
		])
		if not bool(foe.net_simulated):
			fail("主机上的对手没有走权威模拟")
			finish()
			return
	if not saw_move and foe.global_position.x < 8.0:
		saw_move = true
		note("对手已移动 x=%.2f" % foe.global_position.x)
	if not saw_jump and (foe.velocity.y > 3.0 or foe.global_position.y > 1.6):
		saw_jump = true
		note("对手跳起 y=%.2f vy=%.2f" % [foe.global_position.y, foe.velocity.y])
	var foe_pos: Vector3 = foe.global_position
	var host_pos: Vector3 = net.local_player.global_position
	var gap: float = foe_pos.distance_to(host_pos)
	if saw_jump and saw_move and not sent_hit and gap < 2.6:
		sent_hit = true
		var dir: Vector3 = foe.global_position - net.local_player.global_position
		dir.y = 0.0
		if dir.length_squared() < 0.01:
			dir = Vector3(1, 0, 0)
		else:
			dir = dir.normalized()
		net.host_apply_hit(net.local_player, foe, "launch_up", dir, "")
		hit_at = now
		note("判定击飞 hp=%d vy=%.2f jug=%s gap=%.2f" % [int(foe.health), foe.velocity.y, str(bool(foe.juggled)), gap])
		var event = net.last_confirmed_combat_event
		if event == null or int(event.victim_peer) != int(foe.owner_peer) or str(event.effect_method) != "launch_up":
			fail("主机没有生成击飞 CombatEvent")
			finish()
			return
		if int(foe.health) >= 400 or not bool(foe.juggled) or foe.velocity.y < 2.0:
			fail("击飞结果不一致 hp=%d jug=%s vy=%.2f" % [int(foe.health), str(bool(foe.juggled)), foe.velocity.y])
			finish()
			return
	if sent_hit and hit_at > 0 and now - hit_at > 900:
		finish()

func note(line: String) -> void:
	notes.append(line)
	print("PVP_TEST %s %s" % [role, line])

func fail(line: String) -> void:
	notes.append("FAIL " + line)
	print("PVP_TEST %s FAIL %s" % [role, line])

func finish() -> void:
	if finished:
		return
	finished = true
	var ok := true
	for line in notes:
		if line.begins_with("FAIL"):
			ok = false
	if role == "host" and ok and not sent_hit:
		fail("主机没有完成击飞判定")
		ok = false
	if role == "join" and ok and not (saw_move and saw_jump and saw_snapshots):
		fail("客户端移动、跳跃或插值未完成")
		ok = false
	notes.insert(0, "PASS" if ok else "FAIL")
	notes.append("DONE")
	var folder := ProjectSettings.globalize_path("res://test_output")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("pvp_%s.txt" % role), FileAccess.WRITE)
	if file:
		file.store_string("\n".join(notes) + "\n")
		file.close()
	print("PVP_TEST %s %s" % [role, "PASS" if ok else "FAIL"])
	get_tree().quit()
