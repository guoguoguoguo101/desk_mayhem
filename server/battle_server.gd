extends SceneTree
## Session/transport adapter. All battle decisions live in CombatWorld.
const Core = preload("res://combat/combat_world.gd")
const Codec = preload("res://network/world_codec.gd")
const Reliable = preload("res://network/reliable_events.gd")
const DEFAULT_PORT := 24680
const ACTIVE_CAPACITY := 2
const PEER_TIMEOUT_MS := 5000
const SPAWNS := [Vector3(-12,0.96,0),Vector3(12,0.96,0)]
const CRITICAL_TYPES := ["entity_death","entity_respawn","round_end","round_reset"]
var sim = Core.new()
var transport: PacketPeerUDP
var peers: Dictionary = {}
var next_snapshot_at := 0
var ready := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	sim.attach(root)
	for at in Core.DUMMY_SPAWNS: sim._create_entity("dummy",-1,at)
	transport = PacketPeerUDP.new()
	var error := transport.bind(port_from_args(),"*")
	if error != OK:
		push_error("BATTLE_SERVER bind failed: %d" % error)
		quit(1)
		return
	ready = true
	print("BATTLE_SERVER_RAW listening port=%d active_capacity=2 reserved=4 protocol=3" % port_from_args())

func _process(_delta: float) -> bool:
	if not ready: return false
	_read_client_packets()
	_expire_inactive_peers()
	for id in peers.keys():
		for packet in peers[id].lane.outgoing(Time.get_ticks_msec()): _send_to(id,packet)
	if not peers.is_empty() and Time.get_ticks_msec()>=next_snapshot_at:
		next_snapshot_at = Time.get_ticks_msec()+33
		_broadcast({"type":"snapshot"})
	return false

func _physics_process(_delta: float) -> bool:
	if not ready: return false
	var commands: Array = []
	for peer in peers.values():
		for seq in peer.pending.keys():
			var frame: Dictionary = peer.pending[seq]
			if int(frame.tick)<=sim.server_tick+1:
				commands.append(frame)
				peer.pending.erase(seq)
	for event in sim.step(commands): _broadcast(event)
	return false

func _handle_message(peer_id: String, payload: Dictionary) -> void:
	match str(payload.get("type","")):
		"ping": _send_to(peer_id,{"type":"pong","sent":payload.get("sent",0)})
		"input": _apply_input(peer_id,payload)
		"leave": _remove_peer(peer_id)

func _apply_input(peer_id: String, payload: Dictionary) -> void:
	var frames = payload.get("frames",[])
	if not frames is Array: return
	var peer: Dictionary = peers[peer_id]
	var state: Dictionary = sim.entities[peer.entity_id]
	for raw in frames.slice(0,8):
		if not raw is Dictionary: continue
		if not _number(raw.get("seq")) or not _number(raw.get("tick")): continue
		var seq := int(raw.seq)
		var tick := int(raw.tick)
		if int(raw.get("round_id",-1))!=sim.round_id or int(raw.get("life",-1))!=int(state.life): continue
		if seq<=0 or seq>int(state.input_seq)+600 or seq<int(state.input_seq)-128: continue
		if tick>sim.server_tick+18 or tick<sim.server_tick-180: continue
		if peer.pending.size()>=180 and not peer.pending.has(seq): continue
		var move = _direction(raw.get("move"),true)
		var aim = _direction(raw.get("aim"),false)
		if move==null or aim==null: continue
		var actions: Array = []
		var requested = raw.get("actions",[])
		if not requested is Array: continue
		for action in requested.slice(0,4):
			if not action is Dictionary or not _number(action.get("attack_seq")): continue
			var attack_seq := int(action.attack_seq)
			if attack_seq<=0 or attack_seq<int(peer.attack_high)-128 or attack_seq>int(peer.attack_high)+600: continue
			var direction = _direction(action.get("aim"),false)
			if direction==null: continue
			peer.attack_high = maxi(int(peer.attack_high),attack_seq)
			actions.append({"attack_seq":attack_seq,"attack":str(action.get("attack","")),"aim":direction})
		if seq<=int(state.input_seq) and actions.is_empty(): continue
		peer.pending[seq] = {"entity_id":peer.entity_id,"seq":seq,"tick":tick,"round_id":sim.round_id,"life":int(state.life),"move":move,"aim":aim,"actions":actions}

func _direction(value, allow_zero: bool):
	if not value is Array or value.size()!=2 or not _number(value[0]) or not _number(value[1]): return null
	var direction := Vector3(float(value[0]),0,float(value[1]))
	if not direction.is_finite() or direction.length_squared()>1.01: return null
	if not allow_zero and direction.length_squared()<0.001: return null
	return direction

func _admit(peer_id: String, ip: String, port: int) -> void:
	if not peers.has(peer_id):
		if peers.size()>=ACTIVE_CAPACITY:
			_send(ip,port,{"type":"rejected","reason":"当前测试房只允许两名玩家。"})
			return
		var slot := 0
		for peer in peers.values():
			if int(peer.slot)==0: slot = 1
		var id: String = sim._create_entity("player",slot,SPAWNS[slot])
		peers[peer_id] = {"slot":slot,"entity_id":id,"ip":ip,"port":port,"session":Crypto.new().generate_random_bytes(16).hex_encode(),"lane":Reliable.new(),"last_seen":Time.get_ticks_msec(),"pending":{},"attack_high":0}
		print("BATTLE_SERVER admitted entity=%s slot=%d" % [id,slot])
	var peer: Dictionary = peers[peer_id]
	peer.last_seen = Time.get_ticks_msec()
	_send_to(peer_id,{"type":"admitted","slot":peer.slot,"entity_id":peer.entity_id})

func _remove_peer(peer_id: String) -> void:
	if not peers.has(peer_id): return
	sim.remove_entity(str(peers[peer_id].entity_id))
	peers.erase(peer_id)
	if peers.size()<2: sim.round_reset_at = sim.now_ms()+1

func _send_to(peer_id: String, payload: Dictionary) -> void:
	if not peers.has(peer_id): return
	var peer: Dictionary = peers[peer_id]
	var packet := payload.duplicate(true)
	packet.session = peer.session
	packet.protocol = Core.SCHEMA
	packet.round_id = sim.round_id
	if str(packet.get("type","")) in ["admitted","snapshot"]:
		packet.tick = sim.server_tick
		var snapshot: Dictionary = sim.capture()
		snapshot.scheduled_commands = []
		for connection in peers.values():
			snapshot.scheduled_commands.append_array(connection.pending.values())
		packet.world = Codec.pack(snapshot)
		packet.players = sim._roster()
		packet.npcs = sim._roster("dummy")
		packet.round_over = sim.round_reset_at>0
		if not bool(peer.get("debug_roster",false)):
			var encoded := str(packet.world)
			packet.erase("world")
			packet.erase("players")
			packet.erase("npcs")
			for part in Codec.fragments(encoded):
				var fragment := packet.duplicate()
				fragment.merge(part)
				_send(peer.ip,peer.port,fragment)
			return
	_send(peer.ip,peer.port,packet)

func _broadcast(payload: Dictionary) -> void:
	for id in peers.keys():
		if str(payload.get("type","")) in CRITICAL_TYPES:
			if not peers[id].lane.queue(payload): _remove_peer(id)
		else: _send_to(id,payload)

func _read_client_packets() -> void:
	var budget := 256
	while transport.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var payload = JSON.parse_string(transport.get_packet().get_string_from_utf8())
		if not payload is Dictionary:
			continue
		var peer_id := "%s:%d" % [transport.get_packet_ip(), transport.get_packet_port()]
		if payload.get("type", "") == "hello":
			_admit(peer_id, transport.get_packet_ip(), transport.get_packet_port())
			if peers.has(peer_id): peers[peer_id].debug_roster = bool(payload.get("debug_roster",false))
		elif peers.has(peer_id) and str(payload.get("session","")) == str(peers[peer_id].session):
			peers[peer_id]["last_seen"] = Time.get_ticks_msec()
			if payload.has("ack"):
				peers[peer_id].lane.acknowledge(int(payload.ack))
			elif payload.has("reliable") and payload.get("payload") is Dictionary:
				var id := int(payload.reliable)
				if id > 0 and id < peers[peer_id].lane.next_receive + Reliable.WINDOW:
					_send_to(peer_id, {"ack":id})
					for message in peers[peer_id].lane.receive(id,payload.payload):
						_handle_message(peer_id,message)
			elif payload.get("type", "") != "attack":
				_handle_message(peer_id,payload)

func _expire_inactive_peers() -> void:
	var now := Time.get_ticks_msec()
	for peer_id in peers.keys():
		if now - int(peers[peer_id].get("last_seen", 0)) > PEER_TIMEOUT_MS:
			_remove_peer(peer_id)
			print("BATTLE_SERVER_RAW removed peer=%s timeout" % peer_id)

func _send(ip: String, port: int, payload: Dictionary) -> void:
	transport.set_dest_address(ip, port)
	transport.put_packet(JSON.stringify(payload).to_utf8_buffer())

func port_from_args() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			return maxi(1, int(arg.trim_prefix("--port=")))
	return DEFAULT_PORT

func _number(value) -> bool:
	return value is float or value is int
