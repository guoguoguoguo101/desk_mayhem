extends SceneTree

const Builder = preload("res://tools/map_builder/map_builder.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("MAP_BUILDER FAIL " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Builder.category_for("stone_lantern") == "building", "lantern is building")
	check(Builder.category_for("main_hall") == "building", "hall is building")
	check(Builder.category_for("bamboo_leaf") == "bamboo", "leaf is bamboo")
	check(Builder.category_for("maple_large") == "plant", "maple is plant")
	check(Builder.category_for("rock_base_01") == "rock", "rock is rock")
	check(Builder.category_for("pine_trunk_01") == "rock", "pine is rock")
	check(Builder.category_for("paving_square") == "paving", "paver is paving")
	check(Builder.category_for("weapon_rack") == "building", "weapon rack is building")
	var source := {"kit": "stone_lantern", "position": [1, 0, 2], "quaternion": [0, 0, 0, 1], "scale": [1, 1, 1]}
	var kept: Dictionary = Builder.export_item(source, false, "stone_lantern", Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE)
	source["kit"] = "changed"
	check(str(kept.get("kit", "")) == "changed", "clean export keeps the original record")
	var made: Dictionary = Builder.export_item(source, true, "maple_large", Vector3(1.25, 2, 3), Quaternion.IDENTITY, Vector3(2, 2, 2))
	check(str(made.get("kit", "")) == "maple_large", "dirty export uses the new kit")
	check(is_equal_approx(float(made.position[0]), 1.25), "dirty export writes position")
	check(str(kept.get("kit", "")) == "changed", "dirty export does not rewrite the original record")
	var document := Builder.document_for([made])
	check(bool(document.get("authored", false)), "saved document is marked authored")
	check(document.get("placements", []).size() == 1, "saved document keeps placements")
	var scene: Node3D = load("res://tools/map_builder/map_builder.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.get_node_or_null("World/Shell") != null, "shell is on the ground")
	check(scene.load_queue.size() > 100, "placements queued")
	check(scene.catalog.size() > 10, "catalog listed")
	var listed_lantern := false
	var listed_maple := false
	var listed_paver := false
	var catalog_paver := false
	for item in scene.catalog:
		if str(item.get("id", "")) == "paving_square":
			catalog_paver = true
	check(catalog_paver, "palette includes paving")
	for index in scene.kit_list.item_count:
		var listed := str(scene.kit_list.get_item_metadata(index))
		if listed == "stone_lantern":
			listed_lantern = true
		if listed == "maple_large":
			listed_maple = true
		if listed == "paving_square":
			listed_paver = true
	check(listed_lantern and not listed_maple and not listed_paver, "building tab lists the lantern and hides maple and paving")
	check(scene.kit_list.item_count > 0 and scene.kit_list.get_item_icon(0) != null, "palette rows have an icon")
	var ground = scene._ground_point(Vector2(640, 400), 0.0)
	check(ground != null, "center view hits the ground")
	scene.loading = false
	scene._place_at("stone_lantern", Vector3(3, 0, 4))
	check(scene.file_dirty, "placing marks the file dirty")
	var placed: Node = scene.get_node_or_null("World/stone_lantern_1")
	if scene.records.size() > 0:
		placed = scene.records[scene.records.size() - 1].node
	check(placed != null and is_equal_approx(placed.position.x, 3.0), "new lantern sits at the click")
	scene._undo()
	check(not scene.file_dirty, "undo removes the unsaved lantern")
	ground = scene._ground_point(Vector2(640, 400), 0.0)
	scene._place_at("stone_lantern", ground)
	var hit: int = scene._pick(Vector2(640, 400))
	check(hit >= 0, "center ray hits the lantern")
	scene.armed = "wood_pillar"
	scene._pointer_down(Vector2(640, 400), false)
	check(scene.pointer_id < 0, "armed click does not grab the nearby lantern")
	var count: int = scene.records.size()
	scene._pointer_up(Vector2(640, 400))
	check(scene.records.size() == count + 1, "armed click places even on top of a prop")
	check(str(scene.records[scene.records.size() - 1].kit) == "wood_pillar", "placed the armed kit")
	scene._place_at("paving_square", Vector3(1, 0, 2))
	var paver_y: float = scene.records[scene.records.size() - 1].position.y
	check(is_equal_approx(paver_y, 0.045), "paver sits on the courtyard height")
	var before: Vector3 = scene.focus
	scene._note_key(KEY_D, true)
	scene._pan_keyboard(0.5)
	var moved: Vector3 = scene.focus
	scene._note_key(KEY_D, false)
	scene._pan_keyboard(0.5)
	check(moved.distance_to(before) > 0.01, "holding D pans the view")
	check(scene.focus.distance_to(moved) < 0.001, "releasing D stops the view")
	print("MAP_BUILDER %s queued=%d kits=%d" % ["PASS" if failures == 0 else "FAIL", scene.load_queue.size(), scene.catalog.size()])
	quit(0 if failures == 0 else 1)
