extends SceneTree

const PORT := 26811
var role := ""
var started_at := 0
var connected := false
var api: MultiplayerAPI

func _initialize() -> void:
	print("ENET_PROBE args=%s user=%s" % [str(OS.get_cmdline_args()), str(OS.get_cmdline_user_args())])
	role = arg_value("--enet=")
	started_at = Time.get_ticks_msec()
	api = get_multiplayer()
	api.peer_connected.connect(func(peer_id: int) -> void:
		print("ENET_PROBE server_peer_connected=%d" % peer_id)
		connected = true
	)
	api.connected_to_server.connect(func() -> void:
		print("ENET_PROBE client_connected")
		connected = true
	)
	api.connection_failed.connect(func() -> void: print("ENET_PROBE client_failed"))
	if role == "server":
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_server(PORT, 4)
		if error != OK:
			push_error("ENET_PROBE server create failed=%d" % error)
			quit(1)
			return
		api.multiplayer_peer = peer
		print("ENET_PROBE server_listening port=%d" % PORT)
	elif role == "client":
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_client("127.0.0.1", PORT)
		if error != OK:
			push_error("ENET_PROBE client create failed=%d" % error)
			quit(1)
			return
		api.multiplayer_peer = peer
		print("ENET_PROBE client_connecting port=%d" % PORT)
	else:
		push_error("ENET_PROBE requires --enet=server or --enet=client")
		quit(1)

func _process(_delta: float) -> bool:
	if connected:
		quit()
		return true
	if Time.get_ticks_msec() - started_at > 8000:
		push_error("ENET_PROBE timeout role=%s" % role)
		quit(1)
	return false

func arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	for arg in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
