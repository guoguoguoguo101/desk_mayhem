extends CanvasLayer

@onready var player = get_node("../Player")
@onready var instructions: Label = $Instructions

var equip_ui: Array[Dictionary] = []
var skill_ui: Array[Dictionary] = []
var status_label: Label
var hp_fill: ColorRect
var hp_label: Label
var crosshair: Control
var crosshair_parts: Array[ColorRect] = []
var combo_label: Label
var shown_combo := 0
var combo_pop := 0.0

func _ready() -> void:
	instructions.text = "WASD 移动，鼠标转镜头，Shift 闪现，空格跳。Tab 选武器槽，1-4 装备，Q/E 与 F/C 是两把武器\n左键打中才能连：挥拳、连拳、上勾。上勾或雨伞挑飞后，扣锅会变快，右键踢中会踹得更远"
	instructions.offset_right = 1100.0
	instructions.offset_bottom = 78.0
	instructions.add_theme_font_size_override("font_size", 16)
	outline(instructions)
	instructions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_health_bar()
	build_crosshair()
	status_label = Label.new()
	status_label.position = Vector2(24, 150)
	status_label.size = Vector2(980, 32)
	status_label.add_theme_font_size_override("font_size", 20)
	outline(status_label)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)
	combo_label = Label.new()
	combo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	combo_label.offset_left = -220.0
	combo_label.offset_top = 78.0
	combo_label.offset_right = 220.0
	combo_label.offset_bottom = 156.0
	combo_label.pivot_offset = Vector2(220, 36)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 52)
	combo_label.add_theme_color_override("font_color", Color("ffd56a"))
	combo_label.visible = false
	outline(combo_label)
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combo_label)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07, 0.78)
	backdrop.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	backdrop.offset_top = -128.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -112.0
	bar.offset_bottom = -16.0
	bar.offset_left = 16.0
	bar.offset_right = -16.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	for _i in 4:
		var slot := make_slot(bar, Vector2(100, 78))
		equip_ui.append(slot)
	bar.add_child(gap())
	for _i in 6:
		var slot := make_slot(bar, Vector2(104, 78))
		skill_ui.append(slot)

func build_health_bar() -> void:
	var back := ColorRect.new()
	back.position = Vector2(24, 118)
	back.size = Vector2(280, 22)
	back.color = Color(0.08, 0.06, 0.06, 0.92)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(24, 118)
	hp_fill.size = Vector2(280, 22)
	hp_fill.color = Color(0.35, 0.75, 0.38, 1)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_fill)
	hp_label = Label.new()
	hp_label.position = Vector2(24, 116)
	hp_label.size = Vector2(280, 26)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 16)
	outline(hp_label)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_label)

func build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)
	for spec in [Vector4(-18, -1, 10, 2), Vector4(8, -1, 10, 2), Vector4(-1, -18, 2, 10), Vector4(-1, 8, 2, 10)]:
		var hair := ColorRect.new()
		hair.anchor_left = 0.5
		hair.anchor_top = 0.5
		hair.offset_left = spec.x
		hair.offset_top = spec.y
		hair.offset_right = spec.x + spec.z
		hair.offset_bottom = spec.y + spec.w
		hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hair.color = Color(1, 0.96, 0.86, 0.92)
		crosshair.add_child(hair)
		crosshair_parts.append(hair)

func outline(label: Label) -> void:
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))

func gap() -> Control:
	var spacer := ColorRect.new()
	spacer.custom_minimum_size = Vector2(16, 48)
	spacer.color = Color(1, 1, 1, 0.16)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func make_slot(parent: Node, size: Vector2) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = size
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.94)
	style.border_color = Color(0.93, 0.86, 0.72, 0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	panel.add_child(overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var key_label := make_label(15, Color(0.95, 0.82, 0.45))
	var name_label := make_label(18, Color.WHITE)
	var cd_label := make_label(16, Color(1, 0.85, 0.55))
	box.add_child(key_label)
	box.add_child(name_label)
	box.add_child(cd_label)
	return {
		"style": style,
		"overlay": overlay,
		"key": key_label,
		"name": name_label,
		"cd": cd_label,
	}

func make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _process(_delta: float) -> void:
	if player == null:
		return
	status_label.text = player.status_text()
	var count := int(player.combo_count)
	if count >= 2 and player.combo_timer > 0.0:
		combo_label.visible = true
		combo_label.text = "%d HIT" % count
		if count != shown_combo:
			shown_combo = count
			combo_pop = 0.14
		combo_pop = maxf(0.0, combo_pop - _delta)
		var pulse := 1.0 + combo_pop * 1.6
		combo_label.scale = Vector2(pulse, pulse)
		combo_label.modulate.a = clampf(player.combo_timer / 0.35, 0.0, 1.0)
	else:
		combo_label.visible = false
		shown_combo = 0
		combo_label.scale = Vector2.ONE
	var show_aim: bool = player.wants_throw_aim() and not player.downed
	crosshair.visible = show_aim
	for hair in crosshair_parts:
		hair.color = Color(1, 0.96, 0.86, 0.92)
	var ratio := 0.0 if player.max_health <= 0 else clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	hp_fill.size.x = 280.0 * ratio
	hp_label.text = "HP %d / %d" % [player.health, player.max_health]
	if ratio > 0.55:
		hp_fill.color = Color(0.35, 0.75, 0.38)
	elif ratio > 0.28:
		hp_fill.color = Color(0.86, 0.68, 0.22)
	else:
		hp_fill.color = Color(0.82, 0.28, 0.22)
	var weapons: Array = player.equipment_slots()
	for i in equip_ui.size():
		apply_slot(equip_ui[i], weapons[i])
	var skills: Array = player.skill_slots()
	for i in skill_ui.size():
		apply_slot(skill_ui[i], skills[i])

func apply_slot(ui: Dictionary, data: Dictionary) -> void:
	ui["key"].text = data["key"]
	ui["name"].text = data["name"]
	var remain: float = data["remain"]
	var maximum: float = data["max_cd"]
	ui["cd"].text = "%.1f" % remain if remain > 0.05 else ""
	var ratio := 0.0 if maximum <= 0.0 else clampf(remain / maximum, 0.0, 1.0)
	ui["overlay"].visible = ratio > 0.02
	ui["overlay"].anchor_top = 1.0 - ratio
	ui["name"].modulate = Color(1, 0.86, 0.42) if data["highlight"] else Color.WHITE
	var style: StyleBoxFlat = ui["style"]
	if data["selected"] or data["highlight"]:
		style.bg_color = Color(0.32, 0.22, 0.08, 0.96)
		style.border_color = Color(1.0, 0.78, 0.28)
		style.set_border_width_all(3)
	elif data["equipped"]:
		style.bg_color = Color(0.1, 0.16, 0.2, 0.96)
		style.border_color = Color(0.55, 0.78, 0.9)
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.07, 0.08, 0.1, 0.94)
		style.border_color = Color(0.93, 0.86, 0.72, 0.28)
		style.set_border_width_all(2)
