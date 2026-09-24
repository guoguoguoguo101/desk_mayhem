extends SceneTree

const PORT := 24680
var first := PacketPeerUDP.new()
var second := PacketPeerUDP.new()
var started_at := 0
var next_attack_at := 0
var attacks := 0
var round_end := false
var reset_seen := false

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
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
	else:
		_send(first, {"type": "input", "move": [0.0, 0.0]})
		_send(second, {"type": "input", "move": [0.0, 0.0]})
		if not round_end and Time.get_ticks_msec() >= next_attack_at:
			next_attack_at = Time.get_ticks_msec() + 270
			attacks += 1
			_send(first, {"type": "attack", "attack": "pot_slam"})
	_read(first)
	_read(second)
	if round_end and reset_seen:
		print("BATTLE_ROUND_SMOKE passed attacks=%d" % attacks)
		quit()
		return true
	if elapsed > 18000:
		push_error("BATTLE_ROUND_SMOKE timeout attacks=%d end=%s reset=%s" % [attacks, round_end, reset_seen])
		quit(1)
	return false

func _send(peer: PacketPeerUDP, payload: Dictionary) -> void:
	peer.put_packet(JSON.stringify(payload).to_utf8_buffer())

func _read(peer: PacketPeerUDP) -> void:
	while peer.get_available_packet_count() > 0:
		var payload = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if not payload is Dictionary:
			continue
		if payload.get("type", "") == "round_end":
			round_end = true
		elif payload.get("type", "") == "round_reset":
			reset_seen = true
