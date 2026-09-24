extends Node

var started_at := 0

func _ready() -> void:
	started_at = Time.get_ticks_msec()
	call_deferred("join_server")

func join_server() -> void:
	var network: Node = get_parent()
	network.session_port = test_port()
	network.address_input.text = test_address()
	print("DEDICATED_JOIN_SMOKE joining %s:%d" % [network.address_input.text, network.session_port])
	network.start_join()

func test_port() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			return int(arg.trim_prefix("--port="))
	return 24683

func test_address() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--address="):
			return arg.trim_prefix("--address=")
	return "127.0.0.1"

func _process(_delta: float) -> void:
	var network: Node = get_parent()
	if network.in_match():
		assert(network.local_player.slot_index == 0)
		print("DEDICATED_JOIN_SMOKE passed")
		get_tree().quit()
		return
	if Time.get_ticks_msec() - started_at > 7000:
		push_error("DEDICATED_JOIN_SMOKE timeout phase=%s peer=%s" % [network.phase, str(network.multiplayer.multiplayer_peer)])
		get_tree().quit(1)
