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
	var identity := Panel.new()
	identity.position = Vector2(16, 12)
	identity.size = Vector2(320, 106)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var identity_style := StyleBoxFlat.new()
	identity_style.bg_color = Color(0.075, 0.14, 0.19, 0.93)
	identity_style.set_corner_radius_all(14)
	identity_style.border_color = Color("496471")
	identity_style.set_border_width_all(1)
	identity.add_theme_stylebox_override("panel", identity_style)
	add_child(identity)
	instructions.text = "WASD 移动   ·   Shift 闪现   ·   空格 跳跃   ·   Tab 换槽 / 1–4 装备"
	instructions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	instructions.offset_left = 330
	instructions.offset_right = -120
	instructions.offset_top = -144
	instructions.offset_bottom = -118
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 13)
	instructions.modulate = Color("d3e4e8")
	instructions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_health_bar()
	build_crosshair()
	status_label = Label.new()
	status_label.position = Vector2(28, 153)
	status_label.size = Vector2(980, 32)
	status_label.add_theme_font_size_override("font_size", 16)
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
	var brand := Label.new()
	brand.position = Vector2(28, 20)
	brand.text = "工位失控  /  DESK MAYHEM"
	brand.add_theme_font_size_override("font_size", 23)
	brand.modulate = Color("e8f0e8")
	outline(brand)
	add_child(brand)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -116
	bar.offset_bottom = -18
	bar.offset_left = 320
	bar.offset_right = -100
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var equipment := HBoxContainer.new()
	equipment.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	equipment.offset_left = 24
	equipment.offset_top = -91
	equipment.offset_bottom = -18
	equipment.add_theme_constant_override("separation", 5)
	add_child(equipment)
	for _i in 4:
		equip_ui.append(make_slot(equipment, Vector2(62, 72)))
	for _i in 6:
		var slot := make_slot(bar, Vector2(88, 98))
		skill_ui.append(slot)

func build_health_bar() -> void:
	var back := ColorRect.new()
	back.position = Vector2(28, 70)
	back.size = Vector2(240, 9)
	back.color = Color(0.08, 0.06, 0.06, 0.92)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(28, 70)
	hp_fill.size = Vector2(240, 9)
	hp_fill.color = Color("6edbc0")
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_fill)
	hp_label = Label.new()
	hp_label.position = Vector2(28, 92)
	hp_label.size = Vector2(240, 22)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	label.add_theme_constant_override("outline_size", 2)
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
	style.bg_color = Color("1b2d3e")
	style.border_color = Color("435966")
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
	var key_label := make_label(12, Color("a6bfc8"))
	var name_label := make_label(13, Color.WHITE)
	var cd_label := make_label(12, Color("f3c97d"))
	box.add_child(key_label)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28) if size.x < 70 else Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	box.add_child(name_label)
	box.add_child(cd_label)
	return {
		"panel": panel,
		"style": style,
		"icon": icon,
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
	hp_fill.size.x = 240.0 * ratio
	hp_label.text = "HP %d / %d" % [player.health, player.max_health]
	if ratio > 0.55:
		hp_fill.color = Color("6edbc0")
	elif ratio > 0.28:
		hp_fill.color = Color(0.86, 0.68, 0.22)
	else:
		hp_fill.color = Color(0.82, 0.28, 0.22)
	var weapons: Array = player.equipment_slots()
	for i in equip_ui.size():
		apply_slot(equip_ui[i], weapons[i])
	var skills: Array = player.skill_slots()
	var network := get_node_or_null("../Network")
	# The dedicated test room uses fixed equipment, but always shows its aim reference.
	var dedicated: bool = network != null and network.using_battle_server()
	instructions.text = "WASD 移动 · Shift 闪现 · 空格 跳跃 · Q 冲锋/挑飞 · E 旋伞 · F 回旋锅/召回 · C 扣锅" if dedicated else "WASD 移动 · Shift 闪现 · 空格 跳跃 · Tab 换槽 / 1–4 装备"
	if dedicated:
		crosshair.visible = network.phase == "play" and not player.downed
	for item in equip_ui:
		item["panel"].visible = not dedicated
	for i in skill_ui.size():
		apply_slot(skill_ui[i], skills[i])

func apply_slot(ui: Dictionary, data: Dictionary) -> void:
	var title: String = data["name"]
	var symbol := "punch"
	if "伞" in title or "冲锋" in title or "挑飞" in title: symbol = "spin" if "旋" in title else "umbrella"
	elif "扣锅" in title: symbol = "slam"
	elif "锅" in title or "召回" in title: symbol = "pot"
	elif "咖啡" in title or "投掷" in title: symbol = "drink" if "喝" in title else "coffee"
	elif "椅" in title: symbol = "chair"
	elif "踢" in title: symbol = "kick"
	if ui.get("symbol", "") != symbol:
		ui["icon"].texture = load("res://assets/ui/%s.svg" % symbol)
		ui["symbol"] = symbol
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
		style.bg_color = Color("355b60")
		style.border_color = Color("f1bb68")
		style.set_border_width_all(3)
	elif data["equipped"]:
		style.bg_color = Color("263f50")
		style.border_color = Color(0.55, 0.78, 0.9)
		style.set_border_width_all(2)
	else:
		style.bg_color = Color("1b2d3e")
		style.border_color = Color("435966")
		style.set_border_width_all(2)
