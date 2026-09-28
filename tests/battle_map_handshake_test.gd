extends SceneTree

const Codec = preload("res://network/world_codec.gd")
const Core = preload("res://combat/combat_world.gd")
const Catalog = preload("res://combat/arena_catalog.gd")

var transport := PacketPeerUDP.new()
var codec = Codec.new()
var started := 0
var next_hello := 0
var session := ""
var expected_map := Catalog.MOUNTAIN_COURTYARD

func _initialize() -> void:
	started = Time.get_ticks_msec()
	expected_map = arg_value("--expect-map=", Catalog.MOUNTAIN_COURTYARD)
	var error := transport.connect_to_host("127.0.0.1", port_from_args())
	if error != OK:
		push_error("BATTLE_MAP_HANDSHAKE connect failed")
		quit(1)

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if now >= next_hello and session.is_empty():
		next_hello = now + 200
		send({"type":"hello"})
	while transport.get_available_packet_count() > 0:
		var packet = JSON.parse_string(transport.get_packet().get_string_from_utf8())
		if not packet is Dictionary:
			continue
		if str(packet.get("type","")) == "admitted":
			session = str(packet.get("session",""))
			if int(packet.get("protocol",0)) != Core.SCHEMA:
				return fail("protocol mismatch")
		if session.is_empty() or str(packet.get("session","")) != session:
			continue
		var encoded := codec.receive(packet)
		if encoded.is_empty():
			continue
		var snapshot := Codec.unpack(encoded)
		if str(snapshot.get("map_id","")) != expected_map:
			return fail("wrong map id")
		var own: Dictionary = snapshot.get("entities",{}).get(str(packet.get("entity_id","")),{})
		if own.is_empty():
			return fail("missing player")
		if (own.position as Vector3) != Catalog.player_spawns(expected_map)[0]:
			return fail("wrong spawn")
		print("BATTLE_MAP_HANDSHAKE PASS map=%s protocol=%d" % [snapshot.map_id,Core.SCHEMA])
		send({"type":"leave"})
		quit()
		return true
	if now - started > 5000:
		return fail("timeout")
	return false

func send(payload: Dictionary) -> void:
	payload.session = session
	transport.put_packet(JSON.stringify(payload).to_utf8_buffer())

func fail(reason: String) -> bool:
	push_error("BATTLE_MAP_HANDSHAKE FAIL " + reason)
	quit(1)
	return true

func port_from_args() -> int:
	return int(arg_value("--port=", "24791"))

func arg_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
