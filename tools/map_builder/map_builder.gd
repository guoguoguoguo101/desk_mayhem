class_name MapBuilder
extends Node3D

# 在 Godot 中打开本场景后按 F6。摆放写回 kit_placements.json，不改碰撞。

const CATALOG_PATH := "res://assets/environment/kits/catalog.json"
const PLACEMENTS_PATH := "res://assets/environment/mountain_arena/kit_placements.json"
const SHELL_PATH := "res://assets/environment/mountain_arena/mountain_arena_shell.obj"
const KIT_DIR := "res://assets/environment/kits/"
const PANEL_WIDTH := 400.0
const PALETTE_COLUMNS := 4
const PREVIEW_SIZE := 160
const SNAP_STEP := 0.5
const LIFT_STEP := 0.05
const BUILDINGS := {
	"main_hall": true,
	"wood_pillar": true,
	"martial_banner": true,
	"palace_lantern": true,
	"cinnabar_pillar": true,
	"roof_tile": true,
	"roof_ridge": true,
	"stone_lantern": true,
	"weapon_rack": true,
}
const CATEGORIES := ["building", "paving", "plant", "rock", "bamboo"]
const PAVING_Y := 0.045
const LAYER_NAMES := {
	"building": "建筑",
	"paving": "铺砖",
	"plant": "花木",
	"rock": "山石",
	"bamboo": "竹",
}

var catalog: Array = []
var descriptions := {}
var records: Array = []
var by_id := {}
var next_id := 1
var kit_cache := {}
var load_queue: Array = []
var load_index := 0
var loading := true
var missing_kits := 0
var paving_kept := 0

var armed := ""
var selected_id := -1
var file_dirty := false
var leave_armed := false
var notice := ""
var snap_on := true
var layer_on := {"building": true, "paving": true, "plant": true, "rock": true, "bamboo": true}

var undo_stack: Array = []
var redo_stack: Array = []
var field_before := {}

var pointer_down := false
var pointer_start := Vector2.ZERO
var pointer_id := -1
var dragging := false
var lifting := false
var drag_before := {}
var grab_offset := Vector3.ZERO
var lift_start_y := 0.0
var lift_start_mouse_y := 0.0
var orbiting := false
var panning := false
var held_keys := {}

var focus := Vector3.ZERO
var yaw := 0.75
var pitch := 0.58
var distance := 48.0

var world: Node3D
var camera: Camera3D
var kit_list: ItemList
var search_box: LineEdit
var palette_category := "building"
var preview_textures := {}
var preview_placeholders := {}
var preview_queue: Array[String] = []
var preview_tries := {}
var preview_vp: SubViewport
var preview_holder: Node3D
var preview_cam: Camera3D
var preview_subject: Node3D
var preview_phase := 0
var preview_busy_id := ""
var status_label: Label
var detail_label: Label
var help_label: Label
var save_button: Button
var pos_spins: Array[SpinBox] = []
var yaw_spin: SpinBox
var scale_spins: Array[SpinBox] = []
var ghost: Node3D
var selection_view: MeshInstance3D
var pad: Control


func _ready() -> void:
	_build_world()
	_build_ui()
	_load_catalog()
	_build_preview_rig()
	_queue_previews()
	_refill_palette()
	_queue_placements()
	_apply_camera()
	_refresh_status()


func _process(delta: float) -> void:
	if loading:
		_load_some()
	_preview_step()
	_pan_keyboard(delta)


static func category_for(kit_id: String) -> String:
	if kit_id.begins_with("paving_"):
		return "paving"
	if BUILDINGS.has(kit_id):
		return "building"
	if kit_id.begins_with("bamboo_"):
		return "bamboo"
	if kit_id.begins_with("rock_") or kit_id.begins_with("cliff_") or kit_id.begins_with("peak_") or kit_id.begins_with("pine_") or kit_id.begins_with("shrub_") or kit_id == "vine_01":
		return "rock"
	return "plant"


static func export_item(source: Dictionary, dirty: bool, kit: String, position: Vector3, rotation: Quaternion, scale: Vector3) -> Dictionary:
	if not dirty and not source.is_empty():
		return source
	return {
		"kit": kit,
		"position": _nums(position),
		"quaternion": [snappedf(rotation.x, 0.0001), snappedf(rotation.y, 0.0001), snappedf(rotation.z, 0.0001), snappedf(rotation.w, 0.0001)],
		"scale": _nums(scale),
	}


static func document_for(items: Array) -> Dictionary:
	return {"authored": true, "placements": items}


static func _nums(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.55, 0.68, 0.82)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(1.0, 0.9, 0.76)
	sky.ambient_light_energy = 0.38
	sky.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sky.tonemap_exposure = 0.9
	environment.environment = sky
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -52, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 0.85
	sun.shadow_enabled = false
	add_child(sun)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_add_shell()
	_add_grid()
	selection_view = MeshInstance3D.new()
	selection_view.name = "Selection"
	var selection_material := StandardMaterial3D.new()
	selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_material.albedo_color = Color(1.0, 0.82, 0.25)
	selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_view.material_override = selection_material
	selection_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection_view)
	camera = Camera3D.new()
	camera.fov = 50
	camera.current = true
	add_child(camera)


func _add_shell() -> void:
	if not ResourceLoader.exists(SHELL_PATH):
		push_warning("场地外壳未找到")
		return
	var mesh: Mesh = load(SHELL_PATH)
	if mesh == null:
		return
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = mesh
	world.add_child(shell)


func _add_grid() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(-54, 55):
		var major := x % 4 == 0
		mesh.surface_set_color(Color(0.85, 0.9, 0.82, 0.55 if major else 0.18))
		mesh.surface_add_vertex(Vector3(x, 0.08, -44))
		mesh.surface_add_vertex(Vector3(x, 0.08, 44))
	for z in range(-44, 45):
		var major := z % 4 == 0
		mesh.surface_set_color(Color(0.85, 0.9, 0.82, 0.55 if major else 0.18))
		mesh.surface_add_vertex(Vector3(-54, 0.08, z))
		mesh.surface_add_vertex(Vector3(54, 0.08, z))
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.name = "Grid"
	lines.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lines.material_override = material
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(lines)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	pad = ViewportPad.new()
	pad.host = self
	pad.anchor_left = 0
	pad.anchor_top = 0
	pad.anchor_right = 1
	pad.anchor_bottom = 1
	pad.offset_left = PANEL_WIDTH
	pad.focus_mode = Control.FOCUS_ALL
	layer.add_child(pad)
	help_label = _label("", 15)
	help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_label.position = Vector2(14, 10)
	help_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	help_label.add_theme_constant_override("outline_size", 4)
	pad.add_child(help_label)

	var panel := PanelContainer.new()
	panel.anchor_left = 0
	panel.anchor_top = 0
	panel.anchor_right = 0
	panel.anchor_bottom = 1
	panel.offset_right = PANEL_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.16, 0.96)
	style.border_color = Color(0.72, 0.58, 0.32, 0.85)
	style.border_width_right = 2
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := _label("地图搭建", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.46))
	box.add_child(title)
	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索全部资产"
	search_box.text_changed.connect(func(_text): _refill_palette())
	_style_search(search_box)
	box.add_child(search_box)
	var tabs := GridContainer.new()
	tabs.columns = 5
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	box.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for category in CATEGORIES:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.text = LAYER_NAMES[category]
		tab.button_pressed = category == palette_category
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_mode = Control.FOCUS_NONE
		_style_tab(tab)
		tab.toggled.connect(_on_palette_tab.bind(category))
		tabs.add_child(tab)
	kit_list = KitList.new()
	kit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	kit_list.custom_minimum_size = Vector2(0, 390)
	kit_list.icon_mode = ItemList.ICON_MODE_TOP
	kit_list.fixed_icon_size = Vector2(72, 72)
	kit_list.max_columns = PALETTE_COLUMNS
	kit_list.fixed_column_width = 90
	kit_list.same_column_width = true
	kit_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kit_list.add_theme_font_size_override("font_size", 12)
	kit_list.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	kit_list.add_theme_color_override("font_hovered_color", Color(0.98, 0.94, 0.84))
	kit_list.add_theme_color_override("font_selected_color", Color(0.16, 0.12, 0.06))
	kit_list.add_theme_constant_override("h_separation", 4)
	kit_list.add_theme_constant_override("v_separation", 4)
	var tray := StyleBoxFlat.new()
	tray.bg_color = Color(0.05, 0.07, 0.09)
	tray.border_color = Color(0.35, 0.3, 0.2, 0.7)
	tray.set_border_width_all(1)
	tray.set_corner_radius_all(4)
	tray.content_margin_left = 4
	tray.content_margin_right = 4
	tray.content_margin_top = 4
	tray.content_margin_bottom = 4
	kit_list.add_theme_stylebox_override("panel", tray)
	var cell := StyleBoxFlat.new()
	cell.bg_color = Color(0.78, 0.64, 0.36)
	cell.set_corner_radius_all(3)
	cell.content_margin_left = 2
	cell.content_margin_right = 2
	cell.content_margin_top = 2
	cell.content_margin_bottom = 2
	var hover_cell := cell.duplicate() as StyleBoxFlat
	hover_cell.bg_color = Color(0.22, 0.26, 0.3)
	kit_list.add_theme_stylebox_override("hovered", hover_cell)
	kit_list.add_theme_stylebox_override("selected", cell)
	kit_list.add_theme_stylebox_override("selected_focus", cell)
	kit_list.item_selected.connect(_on_kit_selected)
	kit_list.allow_reselect = true
	box.add_child(kit_list)
	detail_label = _label("从列表点选，或拖到场地上。", 13)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 18)
	box.add_child(detail_label)
	box.add_child(_field_row("位置", pos_spins, -120, 120, 0.01, _on_position_changed))
	var yaw_row := HBoxContainer.new()
	yaw_row.add_child(_label("朝向", 13))
	yaw_spin = _spin(-180, 180, 1)
	yaw_spin.value_changed.connect(_on_yaw_changed)
	yaw_spin.focus_entered.connect(_begin_field_edit)
	yaw_spin.focus_exited.connect(_end_field_edit)
	yaw_row.add_child(yaw_spin)
	box.add_child(yaw_row)
	box.add_child(_field_row("缩放", scale_spins, 0.01, 30, 0.01, _on_scale_changed))
	var snap := CheckButton.new()
	snap.text = "吸附 0.5 米（Shift 暂时关闭）"
	snap.button_pressed = true
	snap.toggled.connect(func(on): snap_on = on)
	box.add_child(snap)
	var layer_title := _label("场上可点选", 13)
	box.add_child(layer_title)
	var checks := HFlowContainer.new()
	checks.add_theme_constant_override("h_separation", 8)
	box.add_child(checks)
	for category in CATEGORIES:
		var check := CheckButton.new()
		check.text = LAYER_NAMES[category]
		check.button_pressed = true
		check.toggled.connect(_on_layer_toggled.bind(category))
		checks.add_child(check)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)
	buttons.add_child(_button("撤销", _undo))
	buttons.add_child(_button("重做", _redo))
	buttons.add_child(_button("复制", _duplicate_selected))
	buttons.add_child(_button("删除", _delete_selected))
	var exit_row := HBoxContainer.new()
	exit_row.add_theme_constant_override("separation", 4)
	box.add_child(exit_row)
	save_button = _button("保存", _save, true)
	exit_row.add_child(save_button)
	exit_row.add_child(_button("返回菜单", _return_to_menu))
	status_label = _label("", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	_set_fields_enabled(false)


func _field_row(title: String, spins: Array[SpinBox], min_value: float, max_value: float, step: float, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_label(title, 13))
	for axis in 3:
		var spin := _spin(min_value, max_value, step)
		spin.value_changed.connect(handler.bind(axis))
		spin.focus_entered.connect(_begin_field_edit)
		spin.focus_exited.connect(_end_field_edit)
		spins.append(spin)
		row.add_child(spin)
	return row


func _spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.rounded = false
	spin.custom_minimum_size = Vector2(64, 26)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _button(text: String, handler: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.42, 0.2) if accent else Color(0.16, 0.2, 0.24)
	normal.border_color = Color(0.72, 0.58, 0.32, 0.9)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.12)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78))
	button.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.88))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.94, 0.84))
	return button


func _style_search(line: LineEdit) -> void:
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.05, 0.07, 0.09)
	field.border_color = Color(0.45, 0.38, 0.24)
	field.set_border_width_all(1)
	field.set_corner_radius_all(3)
	field.content_margin_left = 8
	field.content_margin_right = 8
	field.content_margin_top = 3
	field.content_margin_bottom = 3
	line.add_theme_stylebox_override("normal", field)
	line.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	line.add_theme_color_override("font_placeholder_color", Color(0.55, 0.5, 0.4))
	line.add_theme_font_size_override("font_size", 14)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86))
	return label


func _load_catalog() -> void:
	catalog = []
	descriptions = {}
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("找不到资产清单")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for item in parsed.get("kits", []):
		var kit_id := str(item.get("id", ""))
		if kit_id == "":
			continue
		catalog.append(item)
		descriptions[kit_id] = str(item.get("description", kit_id))


func _refill_palette() -> void:
	if kit_list == null:
		return
	kit_list.clear()
	var query := ""
	if search_box != null:
		query = search_box.text.strip_edges().to_lower()
	for item in catalog:
		var kit_id := str(item.get("id", ""))
		var description := str(item.get("description", ""))
		var category := category_for(kit_id)
		var category_name := str(LAYER_NAMES.get(category, category))
		if query == "":
			if category != palette_category:
				continue
		elif query not in kit_id.to_lower() and query not in description.to_lower() and query not in category_name.to_lower():
			continue
		var title := _short_name(description, kit_id)
		var row := kit_list.add_item(title, _icon_for(kit_id, category))
		kit_list.set_item_metadata(row, kit_id)
		kit_list.set_item_tooltip(row, "%s · %s\n%s" % [category_name, kit_id, description])
		if kit_id == armed:
			kit_list.select(row)


func _on_palette_tab(on: bool, category: String) -> void:
	if not on or palette_category == category:
		return
	palette_category = category
	_queue_previews()
	_refill_palette()


func _short_name(description: String, kit_id: String) -> String:
	var text := description
	var comma := text.find("，")
	if comma > 0:
		text = text.substr(0, comma)
	text = text.strip_edges()
	if text.is_empty():
		text = kit_id
	if text.length() > 5:
		text = text.substr(0, 5)
	return text


func _style_tab(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.19, 0.2)
	normal.set_corner_radius_all(3)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.26, 0.27, 0.28)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.78, 0.64, 0.36)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.94, 0.92, 0.86))
	button.add_theme_color_override("font_hover_color", Color(0.98, 0.95, 0.86))
	button.add_theme_color_override("font_pressed_color", Color(0.16, 0.12, 0.06))
	button.add_theme_font_size_override("font_size", 14)


func _icon_for(kit_id: String, category: String) -> Texture2D:
	if preview_textures.has(kit_id):
		return preview_textures[kit_id]
	return _placeholder(category)


func _placeholder(category: String) -> Texture2D:
	if preview_placeholders.has(category):
		return preview_placeholders[category]
	var colors := {
		"building": Color(0.48, 0.34, 0.22),
		"plant": Color(0.28, 0.46, 0.24),
		"rock": Color(0.4, 0.4, 0.38),
		"bamboo": Color(0.48, 0.58, 0.22),
		"paving": Color(0.62, 0.58, 0.5),
	}
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(colors.get(category, Color(0.3, 0.3, 0.3)))
	var texture := ImageTexture.create_from_image(image)
	preview_placeholders[category] = texture
	return texture


func _build_preview_rig() -> void:
	if DisplayServer.get_name() == "headless":
		return
	preview_vp = SubViewport.new()
	preview_vp.name = "KitPreview"
	preview_vp.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	preview_vp.own_world_3d = true
	preview_vp.transparent_bg = false
	preview_vp.disable_3d = false
	preview_vp.gui_disable_input = true
	preview_vp.handle_input_locally = false
	preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.22, 0.24)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.86, 0.78)
	environment.ambient_light_energy = 0.65
	var world_3d := World3D.new()
	world_3d.environment = environment
	preview_vp.world_3d = world_3d
	add_child(preview_vp)
	preview_holder = Node3D.new()
	preview_holder.name = "Subject"
	preview_vp.add_child(preview_holder)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.35
	key.shadow_enabled = false
	preview_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 148, 0)
	fill.light_energy = 0.4
	fill.shadow_enabled = false
	preview_vp.add_child(fill)
	preview_cam = Camera3D.new()
	preview_cam.fov = 28
	preview_cam.near = 0.05
	preview_cam.far = 400
	preview_cam.current = true
	preview_vp.add_child(preview_cam)


func _queue_previews() -> void:
	if preview_vp == null:
		return
	var front: Array[String] = []
	var back: Array[String] = []
	for item in catalog:
		var kit_id := str(item.get("id", ""))
		if kit_id == "" or preview_textures.has(kit_id) or kit_id == preview_busy_id:
			continue
		if category_for(kit_id) == palette_category:
			front.append(kit_id)
		else:
			back.append(kit_id)
	preview_queue = front
	preview_queue.append_array(back)


func _preview_step() -> void:
	if preview_vp == null:
		return
	if preview_phase == 1 or preview_phase == 2:
		preview_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		preview_phase += 1
		return
	if preview_phase == 3:
		_capture_preview()
		return
	if preview_queue.is_empty():
		return
	var kit_id: String = preview_queue.pop_front()
	if preview_textures.has(kit_id):
		return
	if not _stage_preview(kit_id):
		return
	preview_busy_id = kit_id
	preview_phase = 1


func _stage_preview(kit_id: String) -> bool:
	_clear_preview_subject()
	var packed := _kit_scene(kit_id)
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	preview_holder.add_child(node)
	preview_subject = node
	var box := _local_aabb(node)
	var radius := maxf(box.size.length() * 0.5, 0.2)
	var center := box.get_center()
	preview_cam.position = center + Vector3(0.9, 0.62, 1.0).normalized() * radius * 2.4
	preview_cam.look_at(center, Vector3.UP)
	return true


func _capture_preview() -> void:
	var kit_id := preview_busy_id
	var image: Image = preview_vp.get_texture().get_image()
	_clear_preview_subject()
	preview_phase = 0
	preview_busy_id = ""
	if kit_id == "":
		return
	if image == null or image.is_empty():
		var tries := int(preview_tries.get(kit_id, 0)) + 1
		preview_tries[kit_id] = tries
		if tries < 2:
			preview_queue.push_front(kit_id)
		return
	preview_textures[kit_id] = ImageTexture.create_from_image(image)
	_paint_icon(kit_id)


func _paint_icon(kit_id: String) -> void:
	if kit_list == null or not preview_textures.has(kit_id):
		return
	for index in kit_list.item_count:
		if str(kit_list.get_item_metadata(index)) == kit_id:
			kit_list.set_item_icon(index, preview_textures[kit_id])


func _clear_preview_subject() -> void:
	if preview_subject != null:
		preview_subject.free()
		preview_subject = null


func _on_kit_selected(index: int) -> void:
	var kit_id := str(kit_list.get_item_metadata(index))
	if kit_id == "":
		return
	armed = kit_id
	_rebuild_ghost()
	_refresh_status()


func _on_layer_toggled(on: bool, category: String) -> void:
	layer_on[category] = on


func _queue_placements() -> void:
	load_queue = []
	if not FileAccess.file_exists(PLACEMENTS_PATH):
		loading = false
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PLACEMENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		loading = false
		return
	load_queue = parsed.get("placements", [])
	loading = load_index < load_queue.size()


func _load_some() -> void:
	var budget := 8
	while budget > 0 and load_index < load_queue.size():
		_load_existing(load_queue[load_index])
		load_index += 1
		budget -= 1
	if load_index >= load_queue.size():
		loading = false
		if "载入" in notice:
			notice = ""
	_refresh_status()


func _load_existing(item: Dictionary) -> void:
	var rec := _record_from_item(item, false)
	records.append(rec)
	by_id[rec.id] = rec
	if rec.locked:
		paving_kept += 1
		return
	if not _attach_node(rec):
		missing_kits += 1


func _record_from_item(item: Dictionary, dirty: bool) -> Dictionary:
	var position: Array = item.get("position", [0, 0, 0])
	var rotation: Array = item.get("quaternion", [0, 0, 0, 1])
	var scale: Array = item.get("scale", [1, 1, 1])
	var kit_id := str(item.get("kit", ""))
	var rec := {
		"id": next_id,
		"kit": kit_id,
		"position": Vector3(float(position[0]), float(position[1]), float(position[2])),
		"rotation": Quaternion(float(rotation[0]), float(rotation[1]), float(rotation[2]), float(rotation[3])),
		"scale": Vector3(float(scale[0]), float(scale[1]), float(scale[2])),
		"source": {} if dirty else item,
		"dirty": dirty,
		"category": category_for(kit_id),
		"locked": false,
		"node": null,
		"aabb": AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1)),
	}
	next_id += 1
	return rec


func _attach_node(rec: Dictionary) -> bool:
	if rec.locked:
		return false
	var packed := _kit_scene(str(rec.kit))
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	node.name = "%s_%d" % [rec.kit, rec.id]
	world.add_child(node)
	rec.node = node
	_apply_transform(rec)
	rec.aabb = _local_aabb(node)
	return true


func _kit_scene(kit_id: String) -> PackedScene:
	if kit_cache.has(kit_id):
		return kit_cache[kit_id]
	var path := KIT_DIR + kit_id + ".glb"
	var packed = load(path) if ResourceLoader.exists(path) else null
	kit_cache[kit_id] = packed if packed is PackedScene else null
	return kit_cache[kit_id]


func _local_aabb(root: Node3D) -> AABB:
	var inverse := root.global_transform.affine_inverse()
	var box := AABB()
	var found := false
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	for mesh_node in meshes:
		if mesh_node.mesh == null:
			continue
		var transformed := inverse * mesh_node.global_transform
		var local := mesh_node.get_aabb()
		for corner in 8:
			var point: Vector3 = transformed * local.get_endpoint(corner)
			if not found:
				box = AABB(point, Vector3.ZERO)
				found = true
			else:
				box = box.expand(point)
	return box if found else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))


func _apply_transform(rec: Dictionary) -> void:
	var node := rec.node as Node3D
	if node == null:
		return
	node.position = rec.position
	node.quaternion = rec.rotation
	node.scale = rec.scale


func handle_view(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var screen: Vector2 = button.global_position
		if button.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = button.pressed
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			panning = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			if button.ctrl_pressed:
				_scale_selected(1.1)
			else:
				_zoom(0.88, screen)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.ctrl_pressed:
				_scale_selected(1.0 / 1.1)
			else:
				_zoom(1.0 / 0.88, screen)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pointer_down(screen, button.alt_pressed)
			else:
				_pointer_up(screen)
		pad.accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if orbiting:
			_orbit(motion.relative)
		elif panning:
			_pan_mouse(motion.relative)
		elif pointer_down:
			_pointer_move(motion.global_position, motion.alt_pressed)
		else:
			_move_ghost(motion.global_position)


func drop_kit(kit_id: String) -> void:
	if loading:
		_set_status("还在载入已有摆放")
		return
	armed = kit_id
	_select_palette_row(kit_id)
	_rebuild_ghost()
	var screen := pad.get_viewport().get_mouse_position()
	var point = _ground_point(screen, 0.0)
	if point == null:
		_refresh_status()
		return
	_place_at(kit_id, _snap_xz(point))


func _pointer_down(screen: Vector2, alt: bool) -> void:
	pointer_down = true
	pointer_start = screen
	dragging = false
	lifting = alt
	drag_before = {}
	# 正在放置时左键只落地，不抓已经摆在旁边的物件。
	pointer_id = -1 if armed != "" else _pick(screen)
	if pointer_id >= 0:
		_select(pointer_id)
		var rec: Dictionary = by_id[pointer_id]
		var ground = _ground_point(screen, 0.0)
		grab_offset = rec.position - ground if ground != null else Vector3.ZERO
		lift_start_y = rec.position.y
		lift_start_mouse_y = screen.y


func _pointer_move(screen: Vector2, alt: bool) -> void:
	if pointer_id >= 0 and not dragging and screen.distance_to(pointer_start) > 5.0:
		dragging = true
		lifting = lifting or alt
		drag_before = _snapshot(by_id[pointer_id])
	if dragging:
		_drag_selected(screen, lifting or alt)
	_move_ghost(screen)


func _pointer_up(screen: Vector2) -> void:
	if armed != "" and not dragging:
		var point = _ground_point(screen, 0.0)
		if point == null:
			_set_status("射线没有落到地面")
		else:
			_place_at(armed, _snap_xz(point))
	elif dragging:
		_commit_drag()
	elif screen.distance_to(pointer_start) <= 5.0 and pointer_id < 0:
		_select(-1)
	pointer_down = false
	dragging = false
	lifting = false


func _drag_selected(screen: Vector2, lift: bool) -> void:
	if not by_id.has(pointer_id):
		return
	var rec: Dictionary = by_id[pointer_id]
	if rec.node == null:
		return
	if lift:
		var y := lift_start_y + (lift_start_mouse_y - screen.y) * 0.02
		if _snap_active():
			y = snapped(y, LIFT_STEP)
		var lifted: Vector3 = rec.position
		lifted.y = y
		rec.position = lifted
	else:
		var ground = _ground_point(screen, 0.0)
		if ground == null:
			return
		var point: Vector3 = ground + grab_offset
		point.y = rec.position.y
		point = _snap_xz(point)
		rec.position = point
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()
	_sync_fields()


func _commit_drag() -> void:
	if drag_before.is_empty() or not by_id.has(pointer_id):
		drag_before = {}
		return
	var rec: Dictionary = by_id[pointer_id]
	var before_position: Vector3 = drag_before.position
	if before_position.distance_to(rec.position) > 0.0001:
		_push_op({"op": "xform", "id": pointer_id, "before": drag_before, "after": _snapshot(rec)})
	else:
		rec.dirty = drag_before.dirty
	drag_before = {}
	_recompute_file_dirty()
	_refresh_status()


func _place_at(kit_id: String, point: Vector3) -> void:
	if loading:
		_set_status("还在载入已有摆放")
		return
	if category_for(kit_id) == "paving":
		point.y = PAVING_Y
	var rec := _record_from_item({
		"kit": kit_id,
		"position": [point.x, point.y, point.z],
		"quaternion": [0.0, 0.0, 0.0, 1.0],
		"scale": [1.0, 1.0, 1.0],
	}, true)
	if not _attach_node(rec):
		_set_status("读不到模型 %s" % kit_id)
		return
	records.append(rec)
	by_id[rec.id] = rec
	_select(rec.id)
	_push_op({"op": "add", "id": rec.id, "index": records.size() - 1, "snap": _snapshot(rec)})
	_recompute_file_dirty()
	_refresh_status()


func _pick(screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var best_id := -1
	var best_distance := INF
	for rec in records:
		if rec.node == null or rec.locked:
			continue
		if not layer_on.get(str(rec.category), true):
			continue
		var distance := _ray_aabb(origin, direction, rec.node.global_transform, rec.aabb)
		if distance >= 0.0 and distance < best_distance:
			best_distance = distance
			best_id = int(rec.id)
	return best_id


func _ray_aabb(origin: Vector3, direction: Vector3, transform: Transform3D, box: AABB) -> float:
	var inverse := transform.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	var t_min := 0.0
	var t_max := 1.0e20
	var corners := [box.position, box.position + box.size]
	for axis in 3:
		var start: float = local_origin[axis]
		var delta: float = local_direction[axis]
		var low: float = min(corners[0][axis], corners[1][axis])
		var high: float = max(corners[0][axis], corners[1][axis])
		if abs(delta) < 0.000001:
			if start < low or start > high:
				return -1.0
			continue
		var t1 := (low - start) / delta
		var t2 := (high - start) / delta
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		t_min = max(t_min, t1)
		t_max = min(t_max, t2)
		if t_min > t_max:
			return -1.0
	return t_min


func _ground_point(screen: Vector2, plane_y: float):
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if abs(direction.y) < 0.00001:
		return null
	var distance_along := (plane_y - origin.y) / direction.y
	if distance_along < 0.0:
		return null
	return origin + direction * distance_along


func _snap_xz(point: Vector3) -> Vector3:
	if not _snap_active():
		return point
	return Vector3(snapped(point.x, SNAP_STEP), point.y, snapped(point.z, SNAP_STEP))


func _snap_active() -> bool:
	return snap_on and not _key_held(KEY_SHIFT)


func _select(id: int) -> void:
	selected_id = id if by_id.has(id) else -1
	_refresh_selection_box()
	_sync_fields()
	_refresh_status()


func _snapshot(rec: Dictionary) -> Dictionary:
	return {
		"kit": rec.kit,
		"position": rec.position,
		"rotation": rec.rotation,
		"scale": rec.scale,
		"source": rec.source,
		"dirty": rec.dirty,
		"category": rec.category,
	}


func _apply_snapshot(rec: Dictionary, snap: Dictionary) -> void:
	rec.kit = snap.kit
	rec.position = snap.position
	rec.rotation = snap.rotation
	rec.scale = snap.scale
	rec.source = snap.source
	rec.dirty = snap.dirty
	rec.category = snap.category
	_apply_transform(rec)
	_refresh_selection_box()
	_sync_fields()


func _refresh_selection_box() -> void:
	if selected_id < 0 or not by_id.has(selected_id) or by_id[selected_id].node == null:
		selection_view.visible = false
		return
	var rec: Dictionary = by_id[selected_id]
	var transform: Transform3D = rec.node.global_transform
	var box: AABB = rec.aabb
	var corners: Array[Vector3] = []
	for index in 8:
		corners.append(transform * box.get_endpoint(index))
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in [0, 1, 0, 2, 0, 4, 1, 3, 1, 5, 2, 3, 2, 6, 3, 7, 4, 5, 4, 6, 5, 7, 6, 7]:
		mesh.surface_add_vertex(corners[edge])
	mesh.surface_end()
	selection_view.mesh = mesh
	selection_view.visible = true


func _sync_fields() -> void:
	var enabled := selected_id >= 0 and by_id.has(selected_id)
	_set_fields_enabled(enabled)
	if not enabled or _field_focused():
		return
	var rec: Dictionary = by_id[selected_id]
	for axis in 3:
		pos_spins[axis].set_block_signals(true)
		pos_spins[axis].value = rec.position[axis]
		pos_spins[axis].set_block_signals(false)
		scale_spins[axis].set_block_signals(true)
		scale_spins[axis].value = rec.scale[axis]
		scale_spins[axis].set_block_signals(false)
	yaw_spin.set_block_signals(true)
	yaw_spin.value = rad_to_deg(wrapf(Basis(rec.rotation).get_euler().y, -PI, PI))
	yaw_spin.set_block_signals(false)


func _set_fields_enabled(enabled: bool) -> void:
	for spin in pos_spins:
		spin.editable = enabled
	for spin in scale_spins:
		spin.editable = enabled
	if yaw_spin:
		yaw_spin.editable = enabled


func _field_focused() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner is SpinBox or owner is LineEdit


func _begin_field_edit() -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		field_before = {}
		return
	field_before = _snapshot(by_id[selected_id])


func _end_field_edit() -> void:
	if field_before.is_empty() or selected_id < 0 or not by_id.has(selected_id):
		field_before = {}
		return
	var rec: Dictionary = by_id[selected_id]
	var moved: bool = (rec.position - field_before.position).length() > 0.0001
	var scaled: bool = (rec.scale - field_before.scale).length() > 0.0001
	var turned: bool = Basis(rec.rotation).get_euler().distance_to(Basis(field_before.rotation).get_euler()) > 0.0001
	if moved or scaled or turned:
		rec.dirty = true
		_push_op({"op": "xform", "id": selected_id, "before": field_before, "after": _snapshot(rec)})
		_recompute_file_dirty()
		_refresh_status()
	field_before = {}


func _on_position_changed(value: float, axis: int) -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	var position: Vector3 = rec.position
	position[axis] = value
	rec.position = position
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()


func _on_scale_changed(value: float, axis: int) -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	var scale: Vector3 = rec.scale
	scale[axis] = value
	rec.scale = scale
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()


func _on_yaw_changed(degrees: float) -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	var current := wrapf(Basis(rec.rotation).get_euler().y, -PI, PI)
	var delta := wrapf(deg_to_rad(degrees) - current, -PI, PI)
	rec.rotation = Quaternion(Vector3.UP, delta) * rec.rotation
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()


func _rebuild_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	if armed == "":
		return
	var packed := _kit_scene(armed)
	if packed == null:
		return
	ghost = packed.instantiate() as Node3D
	if ghost == null:
		return
	ghost.name = "Ghost"
	world.add_child(ghost)


func _move_ghost(screen: Vector2) -> void:
	if ghost == null:
		return
	var point = _ground_point(screen, 0.0)
	if point == null:
		ghost.visible = false
		return
	point = _snap_xz(point)
	if category_for(armed) == "paving":
		point.y = PAVING_Y
	ghost.visible = true
	ghost.position = point + Vector3(0, 0.02, 0)
	ghost.rotation = Vector3.ZERO
	ghost.scale = Vector3.ONE


func _clear_ghost() -> void:
	armed = ""
	if kit_list:
		kit_list.deselect_all()
	if ghost:
		ghost.queue_free()
		ghost = null


func _select_palette_row(kit_id: String) -> void:
	if kit_list == null:
		return
	for index in kit_list.item_count:
		if str(kit_list.get_item_metadata(index)) == kit_id:
			kit_list.select(index)
			kit_list.ensure_current_is_visible()
			return


func _orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.005
	pitch = clampf(pitch + relative.y * 0.004, 0.08, 1.35)
	_apply_camera()


func _pan_mouse(relative: Vector2) -> void:
	var right := camera.global_basis.x
	var look := -camera.global_basis.z
	look.y = 0
	if look.length_squared() < 0.0001:
		look = Vector3(0, 0, -1)
	look = look.normalized()
	var scale := distance * 0.0014
	focus -= right * relative.x * scale
	focus -= look * relative.y * scale
	_apply_camera()


func _zoom(factor: float, screen: Vector2) -> void:
	var before = _ground_point(screen, 0.0)
	distance = clampf(distance * factor, 3.0, 160.0)
	_apply_camera()
	var after = _ground_point(screen, 0.0)
	if before != null and after != null:
		focus += Vector3(before.x - after.x, 0, before.z - after.z)
		_apply_camera()


func _apply_camera() -> void:
	var horizontal := cos(pitch)
	var offset := Vector3(sin(yaw) * horizontal, sin(pitch), cos(yaw) * horizontal) * distance
	camera.global_position = focus + offset
	if camera.global_position.distance_squared_to(focus) > 0.01:
		camera.look_at(focus, Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		_note_key(code, key.pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held_keys.clear()


func _note_key(code: Key, down: bool) -> void:
	if down:
		held_keys[code] = true
	else:
		held_keys.erase(code)


func _key_held(code: Key) -> bool:
	return held_keys.has(code)


func _pan_keyboard(delta: float) -> void:
	if _field_focused() or _key_held(KEY_CTRL) or _key_held(KEY_ALT):
		return
	var x := 0.0
	var z := 0.0
	if _key_held(KEY_A) or _key_held(KEY_LEFT):
		x -= 1.0
	if _key_held(KEY_D) or _key_held(KEY_RIGHT):
		x += 1.0
	if _key_held(KEY_W) or _key_held(KEY_UP):
		z -= 1.0
	if _key_held(KEY_S) or _key_held(KEY_DOWN):
		z += 1.0
	if x == 0.0 and z == 0.0:
		return
	var right := camera.global_basis.x
	right.y = 0
	var look := -camera.global_basis.z
	look.y = 0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	if look.length_squared() > 0.0001:
		look = look.normalized()
	var speed := 18.0 * (2.4 if _key_held(KEY_SHIFT) else 1.0)
	focus += (right * x + look * -z) * speed * delta
	_apply_camera()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F8:
		_return_to_menu()
		get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_ESCAPE:
		if dragging and not drag_before.is_empty() and by_id.has(pointer_id):
			_apply_snapshot(by_id[pointer_id], drag_before)
			drag_before = {}
		dragging = false
		pointer_down = false
		_clear_ghost()
		_select(-1)
		get_viewport().set_input_as_handled()
		return
	if _field_focused() and not key.ctrl_pressed:
		return
	if key.keycode == KEY_S and key.ctrl_pressed:
		_save()
	elif key.keycode == KEY_Z and key.ctrl_pressed and key.shift_pressed:
		_redo()
	elif key.keycode == KEY_Z and key.ctrl_pressed:
		_undo()
	elif key.keycode == KEY_Y and key.ctrl_pressed:
		_redo()
	elif key.keycode == KEY_D and key.ctrl_pressed:
		_duplicate_selected()
	elif key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
		if not _field_focused():
			_delete_selected()
	elif key.keycode == KEY_Q:
		_yaw_selected(deg_to_rad(-90.0 if key.shift_pressed else -15.0))
	elif key.keycode == KEY_E:
		_yaw_selected(deg_to_rad(90.0 if key.shift_pressed else 15.0))
	elif key.keycode == KEY_F:
		_frame_selection()
	else:
		return
	get_viewport().set_input_as_handled()


func _yaw_selected(angle: float) -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	var before := _snapshot(rec)
	rec.rotation = Quaternion(Vector3.UP, angle) * rec.rotation
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()
	_sync_fields()
	_push_op({"op": "xform", "id": selected_id, "before": before, "after": _snapshot(rec)})
	_recompute_file_dirty()
	_refresh_status()


func _scale_selected(factor: float) -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	var before := _snapshot(rec)
	var scale: Vector3 = rec.scale * factor
	scale.x = clampf(scale.x, 0.01, 30)
	scale.y = clampf(scale.y, 0.01, 30)
	scale.z = clampf(scale.z, 0.01, 30)
	rec.scale = scale
	rec.dirty = true
	_apply_transform(rec)
	_refresh_selection_box()
	_sync_fields()
	_push_op({"op": "xform", "id": selected_id, "before": before, "after": _snapshot(rec)})
	_recompute_file_dirty()
	_refresh_status()


func _duplicate_selected() -> void:
	if loading or selected_id < 0 or not by_id.has(selected_id):
		return
	var source: Dictionary = by_id[selected_id]
	if source.locked:
		return
	var offset := Vector3(SNAP_STEP if snap_on else 1.0, 0, 0)
	var copy := _record_from_item({
		"kit": source.kit,
		"position": [source.position.x + offset.x, source.position.y, source.position.z],
		"quaternion": [source.rotation.x, source.rotation.y, source.rotation.z, source.rotation.w],
		"scale": [source.scale.x, source.scale.y, source.scale.z],
	}, true)
	if not _attach_node(copy):
		return
	records.append(copy)
	by_id[copy.id] = copy
	_select(copy.id)
	_push_op({"op": "add", "id": copy.id, "index": records.size() - 1, "snap": _snapshot(copy)})
	_recompute_file_dirty()
	_refresh_status()


func _delete_selected() -> void:
	if selected_id < 0 or not by_id.has(selected_id):
		return
	var rec: Dictionary = by_id[selected_id]
	if rec.locked:
		return
	var index := records.find(rec)
	var snap := _snapshot(rec)
	var id := int(rec.id)
	_release_node(rec)
	records.remove_at(index)
	by_id.erase(id)
	_select(-1)
	_push_op({"op": "remove", "id": id, "index": index, "snap": snap})
	_recompute_file_dirty()
	_refresh_status()


func _release_node(rec: Dictionary) -> void:
	var node := rec.node as Node
	rec.node = null
	if node:
		node.free()


func _frame_selection() -> void:
	if selected_id >= 0 and by_id.has(selected_id):
		focus = by_id[selected_id].position
		distance = 16
	else:
		focus = Vector3.ZERO
		yaw = 0.75
		pitch = 0.58
		distance = 48
	_apply_camera()


func _push_op(op: Dictionary) -> void:
	undo_stack.append(op)
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	redo_stack.clear()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var op: Dictionary = undo_stack.pop_back()
	_run_op(op, false)
	redo_stack.append(op)
	_recompute_file_dirty()
	_refresh_status()


func _redo() -> void:
	if redo_stack.is_empty():
		return
	var op: Dictionary = redo_stack.pop_back()
	_run_op(op, true)
	undo_stack.append(op)
	_recompute_file_dirty()
	_refresh_status()


func _run_op(op: Dictionary, redo: bool) -> void:
	var kind := str(op.op)
	if kind == "xform":
		if by_id.has(op.id):
			_apply_snapshot(by_id[op.id], op.after if redo else op.before)
			_select(int(op.id))
		return
	if (kind == "add" and redo) or (kind == "remove" and not redo):
		_revive(op.snap, int(op.id), int(op.index))
		return
	if by_id.has(op.id):
		var rec: Dictionary = by_id[op.id]
		var index := records.find(rec)
		_release_node(rec)
		if index >= 0:
			records.remove_at(index)
		by_id.erase(op.id)
		if selected_id == int(op.id):
			_select(-1)


func _revive(snap: Dictionary, id: int, index: int) -> void:
	var rec := {
		"id": id,
		"kit": snap.kit,
		"position": snap.position,
		"rotation": snap.rotation,
		"scale": snap.scale,
		"source": snap.source,
		"dirty": snap.dirty,
		"category": snap.category,
		"locked": false,
		"node": null,
		"aabb": AABB(),
	}
	_attach_node(rec)
	var at := clampi(index, 0, records.size())
	records.insert(at, rec)
	by_id[id] = rec
	_select(id)


func _recompute_file_dirty() -> void:
	leave_armed = false
	file_dirty = false
	for rec in records:
		if rec.dirty:
			file_dirty = true
			return


func _return_to_menu() -> void:
	if file_dirty and not leave_armed:
		leave_armed = true
		_set_status("还有未保存的改动，再按一次返回菜单")
		return
	get_tree().change_scene_to_file("res://office_demo.tscn")


func _save() -> void:
	if loading:
		_set_status("还在载入，载入完成后再保存")
		return
	var items: Array = []
	for rec in records:
		items.append(export_item(rec.source, rec.dirty, str(rec.kit), rec.position, rec.rotation, rec.scale))
	var file := FileAccess.open(PLACEMENTS_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("保存失败：%s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(document_for(items), "\t") + "\n")
	file.close()
	for index in records.size():
		var rec: Dictionary = records[index]
		rec.source = items[index]
		rec.dirty = false
	file_dirty = false
	_set_status("已保存。之后 Blender 全量重建会保留这份摆放。")


func _refresh_status() -> void:
	if status_label == null:
		return
	var placed := 0
	for rec in records:
		if rec.node != null:
			placed += 1
	var lines: PackedStringArray = []
	if notice != "":
		lines.append(notice)
	if loading:
		lines.append("正在载入 %d / %d" % [load_index, load_queue.size()])
	else:
		lines.append("场上 %d 件" % placed)
		if file_dirty:
			lines.append("有未保存的修改")
		else:
			lines.append("已是保存状态")
	if paving_kept > 0:
		lines.append("另有 %d 块铺砖样块只保留数据，这里不显示" % paving_kept)
	if missing_kits > 0:
		lines.append("%d 条摆放读不到模型，保存时会原样留下" % missing_kits)
	if armed != "":
		lines.append("放置 %s" % descriptions.get(armed, armed))
	elif selected_id >= 0 and by_id.has(selected_id):
		lines.append("选中 %s" % str(by_id[selected_id].kit))
	status_label.text = "\n".join(lines)
	if detail_label:
		if armed != "":
			detail_label.text = descriptions.get(armed, armed)
		elif selected_id >= 0 and by_id.has(selected_id):
			detail_label.text = descriptions.get(str(by_id[selected_id].kit), str(by_id[selected_id].kit))
		else:
			detail_label.text = "从列表点选后在地面点击，或把资产拖到场地上。"
	if save_button:
		save_button.text = "保存 *" if file_dirty else "保存"
	if help_label:
		help_label.text = "选了素材后左键只放置，贴着别的物件也能放。Esc 取消后再点选场上的。\nAlt 改高度    Shift 不吸附    右键转视角    中键平移    滚轮远近    Q/E 转向（Shift 为 90°）\nCtrl+滚轮缩放    Ctrl+D 复制    Delete 删除    Ctrl+Z 撤销    Ctrl+S 保存    F 对准。WASD 平移视角。"
	get_window().title = "地图搭建 *" if file_dirty else "地图搭建"


func _set_status(text: String) -> void:
	notice = text
	_refresh_status()


class ViewportPad:
	extends Control
	var host

	func _gui_input(event: InputEvent) -> void:
		if host:
			host.handle_view(event)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("kit")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if host and data is Dictionary:
			host.drop_kit(str((data as Dictionary)["kit"]))


class KitList:
	extends ItemList

	func _get_drag_data(at_position: Vector2) -> Variant:
		var index := get_item_at_position(at_position, true)
		if index < 0:
			return null
		var kit_id := str(get_item_metadata(index))
		if kit_id == "":
			return null
		var icon := get_item_icon(index)
		if icon != null:
			var preview := TextureRect.new()
			preview.texture = icon
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.custom_minimum_size = Vector2(72, 72)
			set_drag_preview(preview)
		else:
			var preview := Label.new()
			preview.text = get_item_text(index)
			set_drag_preview(preview)
		return {"kit": kit_id}
