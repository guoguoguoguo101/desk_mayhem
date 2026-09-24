extends SceneTree

const PORT := 24680
var transport: PacketPeerUDP
var admitted := false
var rejected := false
var snapshot_received := false
var started_at := 0
var completed_at := 0
var expected_slot := 0
var expect_rejection := false
var hold_ms := 0
var next_hello_at := 0

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	expected_slot = int(arg_value("--expect-slot=", "0"))
	expect_rejection = arg_value("--expect=", "admitted") == "rejected"
	hold_ms = maxi(0, int(arg_value("--hold-ms=", "0")))
	transport = PacketPeerUDP.new()
	var error := transport.connect_to_host("127.0.0.1", port_from_args())
	if error != OK:
		push_error("Battle transport client could not start.")
		quit(1)
		return
	print("BATTLE_CLIENT_RAW joining port=%d expected=%s" % [port_from_args(), "rejected" if expect_rejection else "slot_%d" % expected_slot])

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() >= next_hello_at and not rejected:
		next_hello_at = Time.get_ticks_msec() + 250
		transport.put_packet(JSON.stringify({"type": "hello"}).to_utf8_buffer())
	while transport.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(transport.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			if parsed.get("type", "") == "admitted":
				admitted = int(parsed.get("slot", -1)) == expected_slot
			elif parsed.get("type", "") == "rejected":
				rejected = true
			elif parsed.get("type", "") == "snapshot" and not parsed.get("players", []).is_empty():
				snapshot_received = true
	var passed := rejected if expect_rejection else admitted and snapshot_received
	if passed:
		if completed_at == 0:
			completed_at = Time.get_ticks_msec()
			print("BATTLE_TRANSPORT_SMOKE passed")
		if Time.get_ticks_msec() - completed_at >= hold_ms:
			quit()
			return true
	if Time.get_ticks_msec() - started_at > 7000:
		push_error("BATTLE_TRANSPORT_SMOKE timeout admitted=%s rejected=%s snapshot=%s" % [admitted, rejected, snapshot_received])
		quit(1)
	return false

func port_from_args() -> int:
	return maxi(1, int(arg_value("--port=", str(PORT))))

func arg_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
