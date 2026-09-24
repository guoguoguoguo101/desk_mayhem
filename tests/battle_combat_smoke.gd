extends SceneTree

const PORT := 24680
var first := PacketPeerUDP.new()
var second := PacketPeerUDP.new()
var started_at := 0
var attack_sent := false
var hit_confirmed := false
var attack_id := "punch_light"
var expect_launch := false

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	attack_id = arg_value("--attack=", attack_id)
	expect_launch = attack_id == "punch_uppercut"
	assert(first.connect_to_host("127.0.0.1", PORT) == OK)
	assert(second.connect_to_host("127.0.0.1", PORT) == OK)

func _process(_delta: float) -> bool:
	var elapsed := Time.get_ticks_msec() - started_at
	if elapsed < 300:
		_send(first, {"type": "hello"})
		_send(second, {"type": "hello"})
	elif elapsed < 2050:
		_send(first, {"type": "input", "move": [1.0, 0.0]})
		_send(second, {"type": "input", "move": [-1.0, 0.0]})
	elif not attack_sent:
		attack_sent = true
		_send(first, {"type": "attack", "attack": attack_id})
	_read(first)
	_read(second)
	if hit_confirmed:
		print("BATTLE_COMBAT_SMOKE passed")
		quit()
		return true
	if elapsed > 6000:
		push_error("BATTLE_COMBAT_SMOKE timeout attack_sent=%s hit=%s" % [attack_sent, hit_confirmed])
		quit(1)
	return false

func _send(peer: PacketPeerUDP, payload: Dictionary) -> void:
	peer.put_packet(JSON.stringify(payload).to_utf8_buffer())

func _read(peer: PacketPeerUDP) -> void:
	while peer.get_available_packet_count() > 0:
		var payload = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if payload is Dictionary and payload.get("type", "") == "combat" and int(payload.get("damage", 0)) > 0:
			var velocity = payload.get("velocity", [])
			hit_confirmed = not expect_launch or (velocity is Array and velocity.size() == 3 and float(velocity[1]) > 8.0)

func arg_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
