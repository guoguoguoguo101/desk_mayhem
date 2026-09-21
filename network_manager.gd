extends Node

const PORT := 24680

@onready var local_player: CharacterBody3D = get_node("../Player")
@onready var lobby: CanvasLayer = get_node("../Lobby")
@onready var address_input: LineEdit = get_node("../Lobby/Panel/Address")
@onready var lobby_status: Label = get_node("../Lobby/Panel/Status")
@onready var match_status: Label = get_node("../HUD/MatchStatus")

var mode := "menu"
var remote_player: CharacterBody3D
var remote_peer_id := 0
var next_state_at_msec := 0
var state_receipts := 0
var state_sends := 0

func _ready() -> void:
	get_node("../Lobby/Panel/SoloButton").pressed.connect(start_solo)
	get_node("../Lobby/Panel/HostButton").pressed.connect(start_host)
	get_node("../Lobby/Panel/JoinButton").pressed.connect(start_join)
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	local_player.spawn_point = local_player.global_position
	call_deferred("release_mouse")

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func has_menu_open() -> bool:
	return mode == "menu" or mode == "joining"

func start_solo() -> void:
	mode = "solo"
	lobby.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("0.0.0.0")
	var error := peer.create_server(PORT, 2)
	if error != OK:
		lobby_status.text = "创建失败：端口 %d 无法使用" % PORT
		return
	multiplayer.multiplayer_peer = peer
	mode = "host"
	local_player.global_position = Vector3(-3, 0.96, 4.8)
	local_player.spawn_point = local_player.global_position
	lobby.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_join() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		lobby_status.text = "请输入主机的局域网 IP"
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		lobby_status.text = "连接失败，请检查 IP"
		return
	multiplayer.multiplayer_peer = peer
	mode = "joining"
	lobby_status.text = "正在连接 %s ..." % address

func on_connected_to_server() -> void:
	mode = "client"
	local_player.global_position = Vector3(3, 0.96, 4.8)
	local_player.spawn_point = local_player.global_position
	spawn_remote(1)
	lobby.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func on_peer_connected(peer_id: int) -> void:
	if mode == "host":
		spawn_remote(peer_id)

func on_peer_disconnected(peer_id: int) -> void:
	if peer_id == remote_peer_id:
		remove_remote()

func on_connection_failed() -> void:
	mode = "menu"
	lobby_status.text = "连接失败。请确认两台电脑在同一局域网。"
	multiplayer.multiplayer_peer = null

func on_server_disconnected() -> void:
	remove_remote()
	mode = "menu"
	lobby.show()
	lobby_status.text = "主机已断开。"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	multiplayer.multiplayer_peer = null

func spawn_remote(peer_id: int) -> void:
	if remote_player:
		return
	remote_peer_id = peer_id
	remote_player = local_player.duplicate()
	remote_player.name = "RemotePlayer"
	remote_player.is_remote = true
	get_parent().add_child(remote_player)
	remote_player.global_position = Vector3(3 if mode == "host" else -3, 0.96, 4.8)
	remote_player.add_to_group("combat_targets")
	remote_player.set_process(false)
	remote_player.set_physics_process(false)
	remote_player.set_process_unhandled_input(false)
	var label := Label3D.new()
	label.text = "对手"
	label.font_size = 48
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.35, 0.35)
	label.position.y = 1.25
	remote_player.add_child(label)
	for part in remote_player.get_node("Visual").get_children():
		if part is MeshInstance3D:
			var tint := StandardMaterial3D.new()
			tint.albedo_color = Color(1.0, 0.2, 0.18, 0.25)
			tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			part.material_overlay = tint

func remove_remote() -> void:
	if remote_player:
		remote_player.queue_free()
	remote_player = null
	remote_peer_id = 0

func _process(delta: float) -> void:
	if mode == "menu" or mode == "joining":
		return
	var status := "单人练习" if mode == "solo" else ("主机等待对手" if mode == "host" else "已连接主机")
	if remote_player:
		status = "联机对战  |  对手 HP %d/100" % remote_player.health
	match_status.text = "你的 HP %d/100  |  %s" % [local_player.health, status]
	if local_player.downed:
		match_status.text += "  |  倒地 %.1f 秒" % local_player.revive_time
	if mode == "solo" or remote_peer_id == 0:
		return
	var now := Time.get_ticks_msec()
	if now >= next_state_at_msec:
		next_state_at_msec = now + 50
		state_sends += 1
		send_state()

func send_state() -> void:
	if remote_peer_id == 0:
		return
	if mode == "host":
		rpc_id(remote_peer_id, "receive_server_state", local_player.global_position,
			local_player.get_node("Visual").rotation.y,
			not local_player.is_on_floor(), local_player.health, local_player.downed)
	else:
		rpc_id(remote_peer_id, "receive_client_state", local_player.global_position,
			local_player.get_node("Visual").rotation.y,
			not local_player.is_on_floor(), local_player.health, local_player.downed)

@rpc("any_peer", "call_remote", "unreliable")
func receive_client_state(position: Vector3, facing: float, is_airborne: bool, hp: int, is_downed: bool) -> void:
	apply_remote_state(position, facing, is_airborne, hp, is_downed)

@rpc("authority", "call_remote", "unreliable")
func receive_server_state(position: Vector3, facing: float, is_airborne: bool, hp: int, is_downed: bool) -> void:
	apply_remote_state(position, facing, is_airborne, hp, is_downed)

func apply_remote_state(position: Vector3, facing: float, is_airborne: bool, hp: int, is_downed: bool) -> void:
	state_receipts += 1
	if mode == "host" and state_receipts == 1:
		send_state()
	if multiplayer.get_remote_sender_id() != remote_peer_id or not remote_player:
		return
	remote_player.global_position = position
	remote_player.get_node("Visual").rotation.y = facing
	remote_player.get_node("Visual").rotation.x = -PI / 2.0 if is_downed else 0.0
	remote_player.airborne = is_airborne
	remote_player.health = hp
	remote_player.downed = is_downed

func send_hit(attack_name: String, force: Vector3) -> void:
	if remote_peer_id == 0 or not remote_player:
		return
	if mode == "host":
		rpc_id(remote_peer_id, "receive_server_hit", attack_name, force)
	else:
		rpc_id(remote_peer_id, "receive_client_hit", attack_name, force)
	get_node("../CombatFeedback").impact(remote_player.global_position + Vector3.UP * 1.2,
		attack_name == "雨伞挑飞" or attack_name == "空中追踢" or attack_name == "空中椅砸")
	local_player.hit_pause = maxf(local_player.hit_pause, 0.05)

@rpc("any_peer", "call_remote", "reliable")
func receive_client_hit(attack_name: String, force: Vector3) -> void:
	apply_remote_hit(attack_name, force)

@rpc("authority", "call_remote", "reliable")
func receive_server_hit(attack_name: String, force: Vector3) -> void:
	apply_remote_hit(attack_name, force)

func apply_remote_hit(attack_name: String, force: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != remote_peer_id:
		return
	local_player.apply_hit(attack_name, force)
