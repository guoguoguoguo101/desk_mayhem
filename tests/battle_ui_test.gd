extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://office_demo.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var network = scene.get_node("Network")
	var hud = scene.get_node("HUD")
	if network.address_input.text != "127.0.0.1":
		push_error("BATTLE_UI default IP missing")
		quit(1)
		return
	# Exercise the real HUD in dedicated-session state without a network match.
	var session = load("res://client/battle_client_session.gd").new()
	session.name = "BattleClientSession"
	network.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	network.phase = "play"
	scene.get_node("Player").downed = false
	await process_frame
	await process_frame
	if not hud.crosshair.visible:
		push_error("BATTLE_UI crosshair hidden in battle")
		quit(1)
		return
	network.address_input.text = "192.168.1.20"
	network.phase = "menu"
	await process_frame
	await process_frame
	if hud.crosshair.visible or network.address_input.text != "192.168.1.20":
		push_error("BATTLE_UI menu visibility or editable address failed")
		quit(1)
		return
	print("BATTLE_UI PASS default_ip editable_ip battle_crosshair menu_hidden")
	quit()
