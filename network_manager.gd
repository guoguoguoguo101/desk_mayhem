extends Node

const PORT := 24680
var session_port := PORT
const ROOM_DUEL := "duel"
const ROOM_TEAMS := "teams"
const ROOM_FFA := "ffa"

const SPAWNS: Array[Vector3] = [
	Vector3(-12.0, 0.96, 0.0),
	Vector3(12.0, 0.96, 0.0),
	Vector3(-12.0, 0.96, -8.0),
	Vector3(12.0, 0.96, 8.0),
]

const HIT_METHODS := {
	"punch_from": true,
	"punch_follow": true,
	"punch_launch": true,
	"kick_from": true,
	"launch_up": true,
	"slam_from_pot": true,
	"shove_from": true,
	"dash_hit_from": true,
	"umbrella_spin_from": true,
	"begin_chair_ride": true,
	"end_chair_ride": true,
	"drop_from_chair": true,
	"pot_float": true,
}

const NAMED_HITS := {
	"咖啡": true,
	"锅": true,
	"文件夹": true,
}

const THROWN_ITEM := preload("res://thrown_item.gd")
const RUSHING_CHAIR := preload("res://rushing_chair.gd")

var phase := "menu"
var room_kind := "solo"
var slots: Array = []
var puppets := {}
var home_spawn := Vector3(0, 0.96, 4.8)
var next_state_at_msec := 0
var closing := false

var lobby: CanvasLayer
var lobby_status: Label
var address_input: LineEdit
var match_label: Label
var ip_field: LineEdit
var score_panel: PanelContainer
var score_label: Label
var kills := {}
var deaths := {}
var last_kill_line := ""
var last_kill_until := 0
var net_debug: Label
var action_seq := 0
var seen_action := {}
var input_seq := 0
var seen_input := {}
var snapshot_seq := 0
var last_snapshot_msec := 0
var snapshots_sent := 0
var snapshots_seen := 0
var last_action_name := ""
var last_hit_line := ""

@onready var local_player: CharacterBody3D = get_node("../Player")
@onready var feedback: Node3D = get_node("../CombatFeedback")

func _ready() -> void:
	add_to_group("network")
	home_spawn = local_player.global_position
	reset_slots()
	build_lobby()
	build_match_label()
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	local_player.controls_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	build_scoreboard()
	if pvp_test_role() != "":
		var tester: Node = load("res://pvp_net_test.gd").new()
		tester.name = "PvpNetTest"
		add_child(tester)

func pvp_test_role() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pvp-test="):
			return arg.trim_prefix("--pvp-test=")
	return ""

func has_menu_open() -> bool:
	return phase == "menu" or phase == "joining"

func in_match() -> bool:
	return phase == "play" and room_kind != "solo"

func capacity_of(kind: String) -> int:
	if kind == ROOM_TEAMS or kind == ROOM_FFA:
		return 4
	return 2

func team_of(kind: String, slot: int) -> int:
	if kind == ROOM_TEAMS:
		return 0 if slot < 2 else 1
	return slot

func reset_slots() -> void:
	slots.clear()
	for _i in 4:
		slots.append({"peer": 0, "team": -1})

func build_lobby() -> void:
	lobby = CanvasLayer.new()
	lobby.layer = 20
	add_child(lobby)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.04, 0.03, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	lobby.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_top = -250
	panel.offset_right = 280
	panel.offset_bottom = 250
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", wood_panel_style())
	lobby.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	box.add_child(title_label("工位失控"))
	var sub := body_label("单人练习在这台电脑打稻草人。比武大厅由你这台当主机，同事用你的 IP 连进来就会直接出现。现在是 1v1，房间以后可以开成 2v2 或四人乱战。")
	box.add_child(sub)
	var solo := Button.new()
	solo.text = "单人练习"
	solo.pressed.connect(start_solo)
	style_button(solo, Color(0.28, 0.16, 0.1))
	box.add_child(solo)
	var host := Button.new()
	host.text = "开设比武大厅"
	host.pressed.connect(start_hall)
	style_button(host, Color(0.5, 0.12, 0.09))
	box.add_child(host)
	address_input = LineEdit.new()
	address_input.placeholder_text = "同事主机的 IP，例如 192.168.1.20"
	address_input.custom_minimum_size = Vector2(0, 40)
	style_line(address_input)
	box.add_child(address_input)
	var join := Button.new()
	join.text = "加入比武大厅"
	join.pressed.connect(start_join)
	style_button(join, Color(0.5, 0.12, 0.09))
	box.add_child(join)
	lobby_status = body_label("")
	box.add_child(lobby_status)
	refresh_lobby_status("同一 Wi-Fi 或网线。连不上时，允许游戏通过 Windows 防火墙，端口 %d。" % PORT)

func title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.46))
	return label

func body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.78))
	return label

func wood_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.09, 0.06, 0.96)
	style.border_color = Color(0.78, 0.6, 0.28)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 16
	return style

func style_button(button: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(4)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.15)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.98, 0.93, 0.82))
	button.add_theme_font_size_override("font_size", 18)

func style_line(line: LineEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.06, 0.04)
	style.border_color = Color(0.62, 0.46, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	line.add_theme_stylebox_override("normal", style)
	line.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	line.add_theme_color_override("font_placeholder_color", Color(0.7, 0.6, 0.48))

func build_match_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	match_label = Label.new()
	match_label.position = Vector2(24, 78)
	match_label.size = Vector2(1200, 28)
	match_label.add_theme_font_size_override("font_size", 18)
	match_label.add_theme_constant_override("outline_size", 4)
	match_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	match_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match_label.visible = false
	layer.add_child(match_label)
	ip_field = LineEdit.new()
	ip_field.position = Vector2(24, 108)
	ip_field.size = Vector2(280, 32)
	ip_field.editable = false
	ip_field.focus_mode = Control.FOCUS_CLICK
	ip_field.placeholder_text = "这里是主机 IP，Esc 后可以选中复制"
	ip_field.visible = false
	layer.add_child(ip_field)
	net_debug = Label.new()
	net_debug.position = Vector2(320, 114)
	net_debug.size = Vector2(940, 48)
	net_debug.add_theme_font_size_override("font_size", 14)
	net_debug.add_theme_constant_override("outline_size", 4)
	net_debug.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	net_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	net_debug.visible = false
	layer.add_child(net_debug)

func refresh_lobby_status(extra: String) -> void:
	var ips := lan_ips()
	var ip_text := "、".join(ips) if not ips.is_empty() else "没有找到局域网 IP"
	lobby_status.text = "你的 IP：%s\n%s" % [ip_text, extra]

func lan_ips() -> PackedStringArray:
	var preferred: PackedStringArray = []
	var other: PackedStringArray = []
	for addr in IP.get_local_addresses():
		if addr.contains(":") or addr.begins_with("127."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			preferred.append(addr)
		else:
			other.append(addr)
	if preferred.is_empty():
		return other
	return preferred

func start_solo() -> void:
	if phase == "joining":
		return
	close_peer()
	room_kind = "solo"
	begin_play(0, false)

func start_hall() -> void:
	if phase == "joining":
		return
	close_peer()
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("0.0.0.0")
	var error := peer.create_server(session_port, 4)
	if error != OK:
		refresh_lobby_status("开设失败，端口 %d 正被占用。" % session_port)
		return
	multiplayer.multiplayer_peer = peer
	room_kind = ROOM_DUEL
	reset_slots()
	var self_id := multiplayer.get_unique_id()
	slots[0]["peer"] = self_id
	slots[0]["team"] = team_of(ROOM_DUEL, 0)
	begin_play(0, true)

func start_join() -> void:
	if phase == "joining":
		return
	var address := address_input.text.strip_edges()
	if address.is_empty():
		refresh_lobby_status("先填主机的局域网 IP。")
		return
	close_peer()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, session_port)
	if error != OK:
		refresh_lobby_status("连接失败，请检查 IP。")
		return
	multiplayer.multiplayer_peer = peer
	phase = "joining"
	refresh_lobby_status("正在连接 %s …" % address)

func begin_play(slot: int, networked: bool) -> void:
	phase = "play"
	lobby.hide()
	set_training(not networked)
	local_player.controls_locked = false
	local_player.remove_from_group("fighters")
	local_player.remove_from_group("combat_targets")
	if networked:
		local_player.team_id = team_of(room_kind, slot)
		local_player.add_to_group("fighters")
		local_player.add_to_group("combat_targets")
	else:
		local_player.team_id = -1
	local_player.slot_index = slot
	local_player.owner_peer = multiplayer.get_unique_id() if networked else 0
	local_player.max_health = 1000 if not networked else 400
	clear_scores()
	local_player.reset_for_round()
	var hall := get_parent().get_node_or_null("DuelHall")
	if hall:
		if networked:
			hall.show_hall()
		else:
			hall.hide_hall()
	if networked:
		local_player.global_position = SPAWNS[slot]
		local_player.spawn_point = local_player.global_position
		look_at_partner(slot)
		local_player.banner = "玩家%d 进入比武大厅" % (slot + 1)
		local_player.banner_time = 1.4
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh_match_label()

func look_at_partner(slot: int) -> void:
	var partner := 0 if slot % 2 == 1 else 1
	var direction: Vector3 = SPAWNS[partner] - SPAWNS[slot]
	direction.y = 0.0
	local_player.face_to(direction)

func on_peer_connected(peer_id: int) -> void:
	if closing or not multiplayer.is_server() or not in_match():
		return
	if puppet_for(peer_id):
		return
	var slot := claim_slot(peer_id)
	if slot < 0:
		rpc_id(peer_id, "room_refused", "比武大厅已经有两个人了。")
		get_tree().create_timer(0.4).timeout.connect(func () -> void: drop_peer(peer_id))
		return
	var team := int(slots[slot]["team"])
	spawn_puppet(peer_id, slot, team)
	rpc_id(peer_id, "enter_room", slot, room_kind, roster())
	rpc_id(peer_id, "sync_scores", score_payload())
	var hall := get_parent().get_node_or_null("DuelHall")
	if hall and hall.has_method("capture_dummies"):
		rpc_id(peer_id, "sync_dummies", hall.capture_dummies())
	for other in multiplayer.get_peers():
		if other != peer_id:
			rpc_id(other, "spawn_peer", peer_id, slot, team)
	local_player.banner = "玩家%d 进来了" % (slot + 1)
	local_player.banner_time = 1.4

func claim_slot(peer_id: int) -> int:
	var cap := capacity_of(room_kind)
	for i in cap:
		if int(slots[i]["peer"]) == 0:
			slots[i]["peer"] = peer_id
			slots[i]["team"] = team_of(room_kind, i)
			return i
	return -1

func roster() -> Array:
	var list: Array = []
	for i in slots.size():
		var peer_id := int(slots[i]["peer"])
		if peer_id == 0:
			continue
		list.append({
			"peer": peer_id,
			"slot": i,
			"team": int(slots[i]["team"]),
		})
	return list

func on_connected_to_server() -> void:
	phase = "joining"

func on_connection_failed() -> void:
	if closing:
		return
	close_peer()
	phase = "menu"
	lobby.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_lobby_status("连接失败。确认 IP、同一局域网，以及防火墙放行端口 %d。" % PORT)

func on_server_disconnected() -> void:
	if closing:
		return
	leave_room("主机已断开，比武大厅关闭了。")

func on_peer_disconnected(peer_id: int) -> void:
	if closing or not multiplayer.is_server():
		return
	free_puppet(peer_id)
	for i in slots.size():
		if int(slots[i]["peer"]) == peer_id:
			slots[i]["peer"] = 0
			slots[i]["team"] = -1
	if in_match():
		rpc("despawn_peer", peer_id)
		local_player.banner = "对手离开了，大厅还开着"
		local_player.banner_time = 1.6

@rpc("authority", "call_remote", "reliable")
func enter_room(slot: int, kind: String, members: Array) -> void:
	room_kind = kind
	for entry in members:
		note_member(int(entry["peer"]), int(entry["slot"]), int(entry["team"]))
		if int(entry["peer"]) == multiplayer.get_unique_id():
			continue
		spawn_puppet(int(entry["peer"]), int(entry["slot"]), int(entry["team"]))
	begin_play(slot, true)

@rpc("authority", "call_remote", "reliable")
func spawn_peer(peer_id: int, slot: int, team: int) -> void:
	note_member(peer_id, slot, team)
	if peer_id == multiplayer.get_unique_id():
		return
	spawn_puppet(peer_id, slot, team)

@rpc("authority", "call_remote", "reliable")
func despawn_peer(peer_id: int) -> void:
	free_puppet(peer_id)
	for i in slots.size():
		if int(slots[i]["peer"]) == peer_id:
			slots[i]["peer"] = 0
			slots[i]["team"] = -1

func note_member(peer_id: int, slot: int, team: int) -> void:
	if slot < 0 or slot >= slots.size():
		return
	slots[slot]["peer"] = peer_id
	slots[slot]["team"] = team

@rpc("authority", "call_remote", "reliable")
func room_refused(reason: String) -> void:
	leave_room(reason)

func spawn_puppet(peer_id: int, slot: int, team: int) -> void:
	if puppet_for(peer_id) or slot < 0 or slot >= SPAWNS.size():
		return
	var puppet := local_player.duplicate() as CharacterBody3D
	puppet.name = "Fighter%d" % peer_id
	puppet.net_puppet = true
	puppet.controls_locked = true
	puppet.owner_peer = peer_id
	puppet.team_id = team
	puppet.slot_index = slot
	puppet.position = SPAWNS[slot]
	for shape_node in puppet.find_children("*", "CollisionShape3D", true, false):
		var collision := shape_node as CollisionShape3D
		if collision.shape:
			collision.shape = collision.shape.duplicate()
	get_parent().add_child(puppet)
	puppet.global_position = SPAWNS[slot]
	puppet.force_update_transform()
	puppet.net_simulated = multiplayer.is_server()
	puppet.set_physics_process(puppet.net_simulated)
	puppet.set_process_unhandled_input(false)
	puppet.max_health = 400
	puppet.reset_for_round()
	puppet.global_position = SPAWNS[slot]
	puppet.spawn_point = puppet.global_position
	var partner := 0 if slot % 2 == 1 else 1
	var direction: Vector3 = SPAWNS[partner] - SPAWNS[slot]
	direction.y = 0.0
	puppet.face_to(direction)
	tint_fighter(puppet, team_color(team))
	var label := Label3D.new()
	label.text = "玩家%d" % (slot + 1)
	label.font_size = 48
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = team_color(team)
	label.position = Vector3(0, 1.35, 0)
	puppet.add_child(label)
	puppets[peer_id] = puppet

func team_color(team: int) -> Color:
	if team == 0:
		return Color("79c4ff")
	return Color("ff7a72")

func tint_fighter(body: Node, color: Color) -> void:
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(color.r, color.g, color.b, 0.22)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mesh in body.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = tint

func puppet_for(peer_id: int) -> Node:
	if not puppets.has(peer_id):
		return null
	var body: Node = puppets[peer_id]
	if not is_instance_valid(body):
		puppets.erase(peer_id)
		return null
	return body

func free_puppet(peer_id: int) -> void:
	var body := puppet_for(peer_id)
	if body:
		body.queue_free()
	puppets.erase(peer_id)

func drop_peer(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)

func set_training(enabled: bool) -> void:
	for dummy in get_tree().get_nodes_in_group("training_dummies"):
		dummy.visible = enabled
		dummy.set_process(enabled)
		dummy.set_physics_process(enabled)
		var shape := dummy.get_node_or_null("CollisionShape3D")
		if shape is CollisionShape3D:
			shape.disabled = not enabled
		if enabled:
			dummy.add_to_group("combat_targets")
		else:
			dummy.remove_from_group("combat_targets")

func _process(_delta: float) -> void:
	refresh_match_label()
	refresh_scoreboard()
	if not in_match():
		return
	var now := Time.get_ticks_msec()
	if now < next_state_at_msec:
		return
	var interval := 33
	next_state_at_msec = now + interval
	if multiplayer.is_server():
		broadcast_snapshot()
	else:
		send_control()

func refresh_match_label() -> void:
	if phase != "play":
		match_label.visible = false
		ip_field.visible = false
		if net_debug:
			net_debug.visible = false
		return
	match_label.visible = true
	if room_kind == "solo":
		match_label.text = "单人练习    F8 回大厅"
		ip_field.visible = false
		if net_debug:
			net_debug.visible = false
		return
	refresh_net_debug()
	var ips := lan_ips()
	var ip_text := "、".join(ips) if not ips.is_empty() else "无"
	ip_field.visible = true
	if not ips.is_empty() and ip_field.text != ips[0]:
		ip_field.text = ips[0]
	var foe := first_puppet()
	var foe_text := "等待对手加入"
	if foe:
		foe_text = "对手 HP %d/%d" % [foe.health, foe.max_health]
		if foe.downed:
			foe_text += " 倒地"
		elif foe.knockdown:
			foe_text += " 倒地保护"
	match_label.text = "比武大厅 1v1    你是玩家%d    %s    IP %s    端口 %d    F8 离开" % [
		local_player.slot_index + 1, foe_text, ip_text, PORT
	]

func first_puppet() -> Node:
	for peer_id in puppets.keys():
		var body := puppet_for(int(peer_id))
		if body:
			return body
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		if phase == "play":
			var note := "已回到大厅。" if room_kind == "solo" else "已离开比武大厅。"
			leave_room(note)
			get_viewport().set_input_as_handled()

func send_control() -> void:
	if local_player == null:
		return
	input_seq += 1
	var control: Dictionary = local_player.capture_control()
	rpc_id(1, "client_input", control["move"], control["aim"], input_seq, bool(control.get("crouch", false)))

@rpc("any_peer", "call_remote", "unreliable_ordered")
func client_input(move: Vector3, aim: Vector3, seq: int, crouch: bool = false) -> void:
	if not multiplayer.is_server() or not in_match():
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(seen_input.get(sender, 0)) >= seq:
		return
	seen_input[sender] = seq
	var puppet := puppet_for(sender)
	if puppet == null:
		return
	puppet.net_move = move
	puppet.net_aim = aim
	puppet.net_crouch = crouch

func request_action(action: String, aim: Vector3) -> void:
	if multiplayer.is_server() or not in_match():
		return
	action_seq += 1
	last_action_name = "%s #%d" % [action, action_seq]
	rpc_id(1, "host_action", action, aim, action_seq)

@rpc("any_peer", "call_remote", "reliable")
func host_action(action: String, aim: Vector3, seq: int) -> void:
	if not multiplayer.is_server() or not in_match():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peer_in_room(sender) or int(seen_action.get(sender, 0)) >= seq:
		return
	seen_action[sender] = seq
	var puppet := puppet_for(sender)
	if puppet == null or not puppet.has_method("call_action"):
		return
	puppet.net_aim = aim
	if aim.length_squared() > 0.001:
		puppet.face_to(aim)
	last_action_name = "收到 %s #%d" % [action, seq]
	puppet.call_action(action)

func broadcast_snapshot() -> void:
	var bodies: Array = []
	bodies.append(pack_body(local_player, multiplayer.get_unique_id()))
	for peer_id in puppets.keys():
		var body := puppet_for(int(peer_id))
		if body:
			bodies.append(pack_body(body, int(peer_id)))
	snapshot_seq += 1
	snapshots_sent += 1
	rpc("world_state", bodies, snapshot_seq)

func pack_body(body: Node, peer_id: int) -> Dictionary:
	var facing := 0.0
	var visual: Node3D = body.get("visual")
	if visual:
		facing = visual.rotation.y
	return {
		"id": peer_id,
		"p": body.global_position,
		"v": body.velocity,
		"f": facing,
		"hp": int(body.get("health")),
		"down": bool(body.get("downed")),
		"kd": bool(body.get("knockdown")),
		"jug": bool(body.get("juggled")),
	}

@rpc("authority", "call_remote", "unreliable_ordered")
func world_state(bodies: Array, seq: int) -> void:
	if multiplayer.is_server() or not in_match() or seq < snapshot_seq:
		return
	snapshot_seq = seq
	snapshots_seen += 1
	last_snapshot_msec = Time.get_ticks_msec()
	var self_id := multiplayer.get_unique_id()
	for state in bodies:
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var peer_id := int(state["id"])
		if peer_id == self_id:
			local_player.reconcile_owner(state)
			continue
		var puppet := puppet_for(peer_id)
		if puppet and puppet.has_method("push_net_sample"):
			puppet.push_net_sample(state)

func host_apply_hit(attacker: Node, target: Node, method: String, direction: Vector3, attack_name: String) -> bool:
	if not multiplayer.is_server() or attacker == null or target == null:
		return false
	if attacker.has_method("can_hurt") and not attacker.can_hurt(target):
		return false
	var before := int(target.get("health"))
	var attacker_peer := int(attacker.get("owner_peer"))
	if attacker_peer <= 0:
		attacker_peer = multiplayer.get_unique_id()
	var victim_peer := int(target.get("owner_peer"))
	if victim_peer <= 0:
		victim_peer = multiplayer.get_unique_id()
	if method != "" and target.has_method(method):
		target.call(method, direction)
	elif attack_name != "" and target.has_method("take_hit"):
		target.take_hit(attack_name)
	else:
		return false
	var after := int(target.get("health"))
	var at: Vector3 = attacker.global_position
	var hit_at: Vector3 = target.global_position
	var launch: Vector3 = target.velocity
	last_hit_line = "命中 %s→%s  t=%d  攻(%.1f,%.1f,%.1f) 受(%.1f,%.1f,%.1f) %s  %d→%d  v(%.1f,%.1f,%.1f)" % [
		peer_name(attacker_peer), peer_name(victim_peer), Time.get_ticks_msec(),
		at.x, at.y, at.z, hit_at.x, hit_at.y, hit_at.z,
		method if method != "" else attack_name, before, after, launch.x, launch.y, launch.z,
	]
	print(last_hit_line)
	if victim_peer != multiplayer.get_unique_id():
		rpc_id(
			victim_peer, "confirm_hit", method, attack_name, direction, after,
			bool(target.get("downed")), launch, bool(target.get("juggled")),
			bool(target.get("kick_bounce")), float(target.get("victim_float")),
			bool(target.get("bounce_pending"))
		)
	if before > 0 and after <= 0:
		rpc("register_kill", attacker_peer, "p:%d" % victim_peer)
	var heavy := method in ["punch_launch", "launch_up", "slam_from_pot", "kick_from"]
	if feedback and feedback.has_method("impact"):
		feedback.impact(hit_at + Vector3.UP * 1.15, heavy, int(attacker.get("combo_count")))
	attacker.hit_pause = maxf(float(attacker.get("hit_pause")), 0.05 if heavy else 0.03)
	return true

@rpc("authority", "call_remote", "reliable")
func confirm_hit(
	method: String, attack_name: String, direction: Vector3, host_health: int,
	host_downed: bool, host_velocity: Vector3, host_juggled: bool, host_kick_bounce: bool,
	host_float: float, host_bounce: bool
) -> void:
	if not in_match():
		return
	if method != "" and local_player.has_method(method):
		local_player.call(method, direction)
	elif attack_name != "" and local_player.has_method("take_hit"):
		local_player.take_hit(attack_name)
	local_player.health = host_health
	local_player.downed = host_downed and host_health <= 0
	local_player.velocity = host_velocity
	local_player.juggled = host_juggled
	local_player.kick_bounce = host_kick_bounce
	local_player.victim_float = host_float
	local_player.bounce_pending = host_bounce

func refresh_net_debug() -> void:
	if net_debug == null:
		return
	net_debug.visible = true
	var age := -1
	if last_snapshot_msec > 0:
		age = Time.get_ticks_msec() - last_snapshot_msec
	var foe := first_puppet()
	var foe_pos := "无"
	if foe:
		foe_pos = "(%.1f, %.1f, %.1f)" % [foe.global_position.x, foe.global_position.y, foe.global_position.z]
	var me := local_player.global_position
	net_debug.text = "Ping %d ms    快照 发%d 收%d    距上次 %s ms    我(%.1f, %.1f, %.1f) 对手%s    %s\n%s" % [
		ping_ms(), snapshots_sent, snapshots_seen, str(age), me.x, me.y, me.z, foe_pos, last_action_name, last_hit_line,
	]

func ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer == null or not (peer is ENetMultiplayerPeer):
		return -1
	var enet := peer as ENetMultiplayerPeer
	var target := 1
	if multiplayer.is_server():
		var foe := first_puppet()
		if foe == null:
			return -1
		target = int(foe.owner_peer)
	var packet := enet.get_peer(target)
	if packet == null:
		return -1
	return int(packet.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

@rpc("any_peer", "call_remote", "unreliable_ordered")
func receive_state(state: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var puppet := puppet_for(sender)
	if puppet and puppet.has_method("apply_net_state"):
		puppet.apply_net_state(state)

@rpc("any_peer", "call_remote", "reliable")
func receive_hit(method: String, attack_name: String, direction: Vector3, contact: Vector3) -> void:
	if not in_match() or local_player.downed or local_player.knockdown:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not peer_in_room(sender):
		return
	var trusted := method == "begin_chair_ride" or method == "end_chair_ride" or method == "drop_from_chair"
	var reach := 12.0 if local_player.airborne_net() else 8.0
	if not trusted and local_player.global_position.distance_to(contact) > reach:
		return
	var landed := false
	if method != "" and HIT_METHODS.has(method) and local_player.has_method(method):
		local_player.call(method, direction)
		landed = true
	elif method == "" and NAMED_HITS.has(attack_name):
		local_player.take_hit(attack_name)
		landed = true
	if landed and local_player.downed:
		rpc("register_kill", sender, "p:%d" % multiplayer.get_unique_id())
	if landed and feedback and feedback.has_method("impact"):
		var heavy := method in ["punch_launch", "launch_up", "slam_from_pot"]
		feedback.impact(local_player.global_position + Vector3.UP * 1.15, heavy)

func peer_in_room(peer_id: int) -> bool:
	for i in slots.size():
		if int(slots[i]["peer"]) == peer_id:
			return true
	return false

func relay_dummy_hit(target: Node, method: String, direction: Vector3, attack_name: String) -> bool:
	if not in_match() or target == null or not is_instance_valid(target):
		return false
	var attacker := multiplayer.get_unique_id()
	apply_dummy_hit(target, method, direction, attack_name, attacker)
	rpc("remote_dummy_hit", int(target.get("dummy_index")), method, attack_name, direction, attacker)
	return true

func apply_dummy_hit(target: Node, method: String, direction: Vector3, attack_name: String, attacker: int) -> void:
	target.set("pending_attacker", attacker)
	if method != "" and target.has_method(method):
		target.call(method, direction)
	elif attack_name != "" and target.has_method("take_hit"):
		target.take_hit(attack_name)

@rpc("any_peer", "call_remote", "reliable")
func remote_dummy_hit(index: int, method: String, attack_name: String, direction: Vector3, attacker: int) -> void:
	if not in_match():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender != attacker or not peer_in_room(sender):
		return
	var hall := get_parent().get_node_or_null("DuelHall")
	if hall == null or not hall.has_method("dummy_by_index"):
		return
	var dummy: Node = hall.dummy_by_index(index)
	if dummy == null:
		return
	apply_dummy_hit(dummy, method, direction, attack_name, attacker)

func report_dummy_kill(attacker_peer: int, dummy_name: String) -> void:
	if not in_match() or attacker_peer != multiplayer.get_unique_id():
		return
	rpc("register_kill", attacker_peer, "d:%s" % dummy_name)

@rpc("any_peer", "call_local", "reliable")
func register_kill(killer_id: int, victim_key: String) -> void:
	if not in_match() or killer_id <= 0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		var victim_id := -1
		if victim_key.begins_with("p:"):
			victim_id = int(victim_key.substr(2))
		if sender != killer_id and sender != victim_id:
			return
		if not peer_in_room(sender) or not peer_in_room(killer_id):
			return
	kills[killer_id] = int(kills.get(killer_id, 0)) + 1
	var victim_label := victim_key.substr(2) if victim_key.begins_with("d:") else ""
	if victim_key.begins_with("p:"):
		var fallen := int(victim_key.substr(2))
		deaths[fallen] = int(deaths.get(fallen, 0)) + 1
		victim_label = peer_name(fallen)
	last_kill_line = "%s 击败 %s" % [peer_name(killer_id), victim_label]
	last_kill_until = Time.get_ticks_msec() + 3200
	refresh_scoreboard()

@rpc("authority", "call_remote", "reliable")
func sync_scores(rows: Array) -> void:
	kills.clear()
	deaths.clear()
	for row in rows:
		var peer_id := int(row["peer"])
		kills[peer_id] = int(row["k"])
		deaths[peer_id] = int(row["d"])
	refresh_scoreboard()

@rpc("authority", "call_remote", "reliable")
func sync_dummies(rows: Array) -> void:
	var hall := get_parent().get_node_or_null("DuelHall")
	if hall and hall.has_method("apply_dummies"):
		hall.apply_dummies(rows)

func clear_scores() -> void:
	kills.clear()
	deaths.clear()
	last_kill_line = ""
	last_kill_until = 0

func score_payload() -> Array:
	var seen := {}
	var rows: Array = []
	for peer_id in kills.keys():
		seen[int(peer_id)] = true
		rows.append({
			"peer": int(peer_id),
			"k": int(kills[peer_id]),
			"d": int(deaths.get(peer_id, 0)),
		})
	for peer_id in deaths.keys():
		if seen.has(int(peer_id)):
			continue
		rows.append({"peer": int(peer_id), "k": 0, "d": int(deaths[peer_id])})
	return rows

func peer_name(peer_id: int) -> String:
	for i in slots.size():
		if int(slots[i]["peer"]) == peer_id:
			return "玩家%d" % (i + 1)
	return "玩家"

func build_scoreboard() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	score_panel = PanelContainer.new()
	score_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_panel.offset_left = -300
	score_panel.offset_top = 16
	score_panel.offset_right = -16
	score_panel.offset_bottom = 220
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.add_theme_stylebox_override("panel", wood_panel_style())
	score_panel.visible = false
	layer.add_child(score_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.add_child(margin)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.76))
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(score_label)

func refresh_scoreboard() -> void:
	if score_panel == null:
		return
	if not in_match():
		score_panel.visible = false
		return
	score_panel.visible = true
	var rows: Array = []
	var self_id := multiplayer.get_unique_id()
	for i in slots.size():
		var peer_id := int(slots[i]["peer"])
		if peer_id <= 0:
			continue
		rows.append({
			"name": "玩家%d" % (i + 1),
			"k": int(kills.get(peer_id, 0)),
			"d": int(deaths.get(peer_id, 0)),
			"self": peer_id == self_id,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["k"]) != int(b["k"]):
			return int(a["k"]) > int(b["k"])
		return int(a["d"]) < int(b["d"])
	)
	var lines := "击杀榜"
	for row in rows:
		var who: String = row["name"]
		if row["self"]:
			who = "你 · " + who
		lines += "\n%s    %d杀  %d死" % [who, int(row["k"]), int(row["d"])]
	if last_kill_line != "" and Time.get_ticks_msec() < last_kill_until:
		lines += "\n" + last_kill_line
	score_label.text = lines

func relay_hit(target: Node, method: String, direction: Vector3, attack_name: String = "") -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if local_player.has_method("can_hurt") and not local_player.can_hurt(target):
		return false
	if not target.get("net_puppet"):
		return false
	var peer_id := int(target.owner_peer)
	if peer_id <= 0:
		return false
	rpc_id(peer_id, "receive_hit", method, attack_name, direction, target.global_position)
	var heavy := method in ["punch_launch", "launch_up", "slam_from_pot"]
	if feedback and feedback.has_method("impact"):
		feedback.impact(target.global_position + Vector3.UP * 1.15, heavy, local_player.combo_count)
	local_player.hit_pause = maxf(local_player.hit_pause, 0.05 if heavy else 0.03)
	return true

func push_carry(peer_id: int, at: Vector3) -> void:
	if not in_match() or peer_id <= 0:
		return
	rpc_id(peer_id, "receive_carry", at)

@rpc("any_peer", "call_remote", "unreliable")
func receive_carry(at: Vector3) -> void:
	if not in_match() or not local_player.chair_ride:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not peer_in_room(sender):
		return
	local_player.global_position = at

func announce_throw(kind: int, origin: Vector3, projectile_velocity: Vector3) -> void:
	if not in_match():
		return
	rpc("spawn_remote_throw", kind, origin, projectile_velocity)

@rpc("any_peer", "call_remote", "reliable")
func spawn_remote_throw(kind: int, origin: Vector3, projectile_velocity: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not in_match():
		return
	var item := THROWN_ITEM.new()
	item.cosmetic = true
	get_parent().add_child(item)
	item.global_position = origin
	var owner := puppet_for(sender)
	var owner_rid: RID = owner.get_rid() if owner else RID()
	item.launch_with_velocity(kind, projectile_velocity, owner_rid)

func announce_chair(origin: Vector3, direction: Vector3) -> void:
	if not in_match():
		return
	rpc("spawn_remote_chair", origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func spawn_remote_chair(origin: Vector3, direction: Vector3) -> void:
	if multiplayer.get_remote_sender_id() == 0 or not in_match():
		return
	var chair := RUSHING_CHAIR.new()
	chair.cosmetic = true
	get_parent().add_child(chair)
	chair.global_position = origin
	chair.launch(direction)

func leave_room(reason: String) -> void:
	if closing:
		return
	closing = true
	var ids: Array = puppets.keys()
	for peer_id in ids:
		var body: Node = puppets[peer_id]
		if is_instance_valid(body):
			body.queue_free()
	puppets.clear()
	reset_slots()
	room_kind = "solo"
	phase = "menu"
	set_training(true)
	var hall := get_parent().get_node_or_null("DuelHall")
	if hall:
		hall.hide_hall()
	local_player.controls_locked = true
	local_player.team_id = -1
	local_player.chair_ride = false
	local_player.seated = false
	local_player.remove_from_group("fighters")
	local_player.remove_from_group("combat_targets")
	local_player.reset_for_round()
	local_player.global_position = home_spawn
	local_player.spawn_point = home_spawn
	local_player.velocity = Vector3.ZERO
	close_peer()
	clear_scores()
	if score_panel:
		score_panel.visible = false
	lobby.show()
	match_label.visible = false
	ip_field.visible = false
	if net_debug:
		net_debug.visible = false
	seen_action.clear()
	seen_input.clear()
	last_hit_line = ""
	last_action_name = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_lobby_status(reason)
	closing = false

func close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
