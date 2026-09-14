extends RefCounted
## Original Starbase2 instrument UI. Decoration never implies operational state.
const INK := Color("e7e7e4")
const MUTED := Color("b5b6b5")
const ACCENT := Color("ff653f")

static func box(fill: Color, border: Color, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.set_content_margin_all(padding)
	return style

static func panel_style() -> StyleBoxFlat:
	var style := box(Color("101010f2"), Color("777c8066"), 18)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 10
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "RichTextLabel", "TabBar", "PopupMenu", "ItemList"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, MUTED)
	for type in ["Button", "OptionButton", "LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, box(Color("191919bf"), Color("73797d66"), 10))
		result.set_stylebox("hover", type, box(Color("30241fcc"), ACCENT, 10))
		result.set_stylebox("pressed", type, box(Color("ff653f22"), ACCENT, 10))
		result.set_stylebox("disabled", type, box(Color("171717bb"), Color("555a5d55"), 10))
		var focus := box(Color(0, 0, 0, 0), ACCENT, 10)
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type, focus)
	for type in ["CheckButton", "CheckBox"]:
		var focus := box(Color(0, 0, 0, 0), ACCENT, 8)
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type, focus)
	for type in ["TabBar", "TabContainer"]:
		result.set_stylebox("tab_unselected", type, box(Color("12121255"), Color("646b6f55"), 10))
		var selected := box(Color("ff653f18"), ACCENT, 10)
		selected.set_border_width_all(0)
		selected.border_width_bottom = 3
		result.set_stylebox("tab_selected", type, selected)
		result.set_color("font_selected_color", type, Color.WHITE)
		result.set_color("font_unselected_color", type, MUTED)
	result.set_stylebox("panel", "TabContainer", box(Color("080808e8"), Color("71787b55"), 14))
	result.set_stylebox("panel", "PopupMenu", panel_style())
	result.set_stylebox("panel", "ItemList", box(Color("101010df"), Color("71787b55"), 10))
	result.set_stylebox("selected", "ItemList", box(Color("ff653f22"), ACCENT, 6))
	result.set_stylebox("selected_focus", "ItemList", box(Color("ff653f22"), ACCENT, 6))
	result.set_constant("v_separation", "ItemList", 10)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("selection_color", "LineEdit", Color("a33c27"))
	result.set_color("caret_color", "LineEdit", ACCENT)
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 10)
	return result

static func apply(control: Control) -> void:
	control.theme = make_theme()
	if control is PanelContainer:
		control.add_theme_stylebox_override("panel", panel_style())
		smoke(control)

static func primary(control: Button) -> void:
	control.add_theme_stylebox_override("normal",box(Color("ff653f"),ACCENT,10))
	control.add_theme_stylebox_override("hover",box(Color("ff825f"),Color("ffab91"),10))
	control.add_theme_stylebox_override("pressed",box(Color("d74728"),ACCENT,10))
	control.add_theme_stylebox_override("disabled",box(Color("252525e8"),Color("666a6b99"),10))
	control.add_theme_color_override("font_color",Color("101010"))
	control.add_theme_color_override("font_hover_color",Color("101010"))
	control.add_theme_color_override("font_pressed_color",Color("101010"))
	control.add_theme_color_override("font_disabled_color",MUTED)
	control.custom_minimum_size.y=40

static func section(parent: Node, title: String) -> Label:
	var item:=Label.new()
	item.text=title.to_upper()
	item.add_theme_color_override("font_color",MUTED)
	item.add_theme_font_size_override("font_size",16)
	parent.add_child(item)
	return item

static func metadata(parent: Node, rows: Array) -> GridContainer:
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",20)
	grid.add_theme_constant_override("v_separation",8)
	parent.add_child(grid)
	for row in rows:
		var key:=Label.new(); key.text=str(row[0]); key.add_theme_color_override("font_color",MUTED); grid.add_child(key)
		var value:=Label.new(); value.text=str(row[1]); value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; grid.add_child(value)
	return grid

static func smoke(control: Control) -> void:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://console_smoke.gdshader")
	control.material=material
