extends RefCounted
## One visual system for every native panel. Status is conveyed by shape and
## text as well as color; nothing here reads or invents operational state.

const COLORS := {
	"scrim":"0a1420a6","surface":"11243af7","raised":"1a3450","inset":"0c1a29",
	"border":"2f4d63","border_strong":"5f8398","accent":"f0cf95","accent_strong":"f6bf62",
	"ink":"0f1b26","text":"edf0e8","text_2":"bccbc9","muted":"8ea3a9",
}

# Tone → [color, shape]. Shapes stay distinct with color removed.
const TONES := {
	"live":["86e2ad","disc"],"verified":["86e2ad","check"],"pending":["8cc7ff","ring_dot"],
	"stale":["f2b45c","half"],"unknown":["c0c8ce","ring"],"offline":["c0c8ce","ring"],
	"failed":["ff8d84","cross"],"idle":["9fb2b8","dash"],"fixture":["d6a9ff","diamond"],
	"no_change":["86e2ad","equals"],"paused":["f2b45c","pause"],
}

const SIZES := {"display":26,"h1":20,"h2":16,"body":15,"small":13,"micro":11}

static func color(name: String) -> Color:
	return Color(COLORS[name])

static func tone_color(tone: String) -> Color:
	return Color(TONES.get(tone,TONES["unknown"])[0])

static func size(name: String, large: bool = false) -> int:
	return int(SIZES[name])+(3 if large else 0)

static func flat(bg: String, border: String = "", pad: Vector4 = Vector4(14,10,14,10), radius: int = 10, border_width: int = 1, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color=Color(bg)
	s.set_corner_radius_all(radius)
	s.anti_aliasing=true
	if border.is_empty(): s.set_border_width_all(0)
	else:
		s.border_color=Color(border)
		s.set_border_width_all(border_width)
	s.content_margin_left=pad.x; s.content_margin_top=pad.y
	s.content_margin_right=pad.z; s.content_margin_bottom=pad.w
	if shadow>0:
		s.shadow_size=shadow
		s.shadow_color=Color("00000059")
		s.shadow_offset=Vector2(0,shadow*0.35)
	return s

static func panel_style(kind: String = "panel", pad: int = 18) -> StyleBoxFlat:
	match kind:
		"card": return flat(COLORS.raised,COLORS.border,Vector4(pad,pad*0.75,pad,pad*0.75),10)
		"inset": return flat(COLORS.inset,COLORS.border,Vector4(pad,pad*0.75,pad,pad*0.75),8)
		"strip": return flat(COLORS.inset+"",COLORS.border,Vector4(pad,pad*0.5,pad,pad*0.5),8)
		"bar": return flat("0f2133f2",COLORS.border,Vector4(pad,pad*0.6,pad,pad*0.6),12,1,14)
		_: return flat(COLORS.surface,COLORS.border_strong,Vector4(pad,pad,pad,pad),12,1,18)

static func _button_styles(theme: Theme, variation: String, normal: String, hover: String, pressed: String, border: String, text_color: String, hover_border: String = "", pad: Vector4 = Vector4(16,8,16,8)) -> void:
	if variation!="Button": theme.set_type_variation(variation,"Button")
	theme.set_stylebox("normal",variation,flat(normal,border,pad,9))
	theme.set_stylebox("hover",variation,flat(hover,hover_border if not hover_border.is_empty() else COLORS.border_strong,pad,9))
	theme.set_stylebox("pressed",variation,flat(pressed,COLORS.accent_strong,pad,9))
	theme.set_stylebox("disabled",variation,flat("18293a99","2b4052",pad,9))
	var focus := flat("00000000",COLORS.accent,pad,9,2)
	focus.expand_margin_left=2; focus.expand_margin_right=2; focus.expand_margin_top=2; focus.expand_margin_bottom=2
	theme.set_stylebox("focus",variation,focus)
	for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:
		theme.set_color(state,variation,Color(text_color))
	theme.set_color("font_disabled_color",variation,Color("7f8f99"))

static func build(large: bool = false) -> Theme:
	var theme := Theme.new()
	theme.default_font_size=size("body",large)
	theme.set_color("font_color","Label",color("text"))
	theme.set_font_size("font_size","Label",size("body",large))
	theme.set_color("default_color","RichTextLabel",color("text"))
	theme.set_font_size("normal_font_size","RichTextLabel",size("small",large)+1)
	# Buttons: default, Primary (commitment), Ghost (quiet), Danger (stop), Nav (masthead).
	_button_styles(theme,"Button","24405a","2f5171","3a5e7c",COLORS.border,COLORS.text)
	_button_styles(theme,"PrimaryButton",COLORS.accent,"f8dcab",COLORS.accent_strong,"e9c17f",COLORS.ink,"ffffff")
	_button_styles(theme,"GhostButton","00000000","1b3348","24405a","3b5a70",COLORS.text_2)
	_button_styles(theme,"DangerButton","3a2530","553040","6a3a4c","7a4a58","ffd2cc")
	_button_styles(theme,"NavButton","13273cf0","1f3b55","2a4a66",COLORS.border_strong,COLORS.text)
	_button_styles(theme,"IconButton","00000000","1b3348","24405a","3b5a70",COLORS.text_2,"",Vector4(6,4,6,4))
	theme.set_font_size("font_size","Button",size("body",large))
	# Option buttons and their popup list.
	theme.set_stylebox("normal","OptionButton",flat("0c1a29",COLORS.border,Vector4(14,8,36,8),9))
	theme.set_stylebox("hover","OptionButton",flat("13273c",COLORS.border_strong,Vector4(14,8,36,8),9))
	theme.set_stylebox("pressed","OptionButton",flat("13273c",COLORS.accent,Vector4(14,8,36,8),9))
	theme.set_stylebox("disabled","OptionButton",flat("0c1a2999","2b4052",Vector4(14,8,36,8),9))
	theme.set_stylebox("focus","OptionButton",theme.get_stylebox("focus","Button"))
	theme.set_color("font_color","OptionButton",color("text"))
	theme.set_color("font_hover_color","OptionButton",color("text"))
	theme.set_color("font_focus_color","OptionButton",color("text"))
	theme.set_stylebox("panel","PopupMenu",flat(COLORS.raised,COLORS.border_strong,Vector4(6,6,6,6),10,1,16))
	theme.set_stylebox("hover","PopupMenu",flat("2f5171","",Vector4(10,4,10,4),6))
	theme.set_color("font_color","PopupMenu",color("text"))
	theme.set_color("font_hover_color","PopupMenu",color("accent"))
	theme.set_font_size("font_size","PopupMenu",size("body",large))
	# Text inputs.
	theme.set_stylebox("normal","LineEdit",flat(COLORS.inset,COLORS.border,Vector4(12,8,12,8),8))
	theme.set_stylebox("focus","LineEdit",flat(COLORS.inset,COLORS.accent,Vector4(12,8,12,8),8,2))
	theme.set_stylebox("read_only","LineEdit",flat("0c1a2999","2b4052",Vector4(12,8,12,8),8))
	theme.set_color("font_color","LineEdit",color("text"))
	theme.set_color("font_placeholder_color","LineEdit",color("muted"))
	theme.set_color("caret_color","LineEdit",color("accent"))
	theme.set_stylebox("normal","TextEdit",flat(COLORS.inset,COLORS.border,Vector4(12,10,12,10),8))
	theme.set_stylebox("focus","TextEdit",flat(COLORS.inset,COLORS.accent,Vector4(12,10,12,10),8,2))
	theme.set_stylebox("read_only","TextEdit",flat(COLORS.inset,COLORS.border,Vector4(12,10,12,10),8))
	theme.set_color("font_color","TextEdit",color("text_2"))
	theme.set_color("font_readonly_color","TextEdit",color("text_2"))
	theme.set_font_size("font_size","TextEdit",size("small",large))
	# Toggles.
	theme.set_color("font_color","CheckButton",color("text"))
	theme.set_color("font_hover_color","CheckButton",color("accent"))
	theme.set_color("font_focus_color","CheckButton",color("accent"))
	theme.set_stylebox("focus","CheckButton",theme.get_stylebox("focus","Button"))
	theme.set_stylebox("normal","CheckButton",flat("00000000","",Vector4(4,6,4,6),6))
	theme.set_stylebox("hover","CheckButton",flat("1b3348","",Vector4(4,6,4,6),6))
	theme.set_stylebox("pressed","CheckButton",flat("1b3348","",Vector4(4,6,4,6),6))
	# Tabs.
	theme.set_stylebox("panel","TabContainer",flat("0c1a2900",COLORS.border,Vector4(0,14,0,0),0))
	theme.set_stylebox("tab_selected","TabContainer",flat("1a3450",COLORS.accent,Vector4(18,8,18,8),8,2))
	theme.set_stylebox("tab_unselected","TabContainer",flat("00000000","",Vector4(18,8,18,8),8))
	theme.set_stylebox("tab_hovered","TabContainer",flat("152b40","",Vector4(18,8,18,8),8))
	theme.set_stylebox("tab_focus","TabContainer",theme.get_stylebox("focus","Button"))
	theme.set_stylebox("tabbar_background","TabContainer",flat("00000000","",Vector4(0,0,0,0),0))
	theme.set_color("font_selected_color","TabContainer",color("accent"))
	theme.set_color("font_unselected_color","TabContainer",color("text_2"))
	theme.set_color("font_hovered_color","TabContainer",color("text"))
	theme.set_font_size("font_size","TabContainer",size("body",large))
	# Scrollbars: slim, visible, no arrows.
	for bar in ["VScrollBar","HScrollBar"]:
		theme.set_stylebox("scroll",bar,flat("0c1a2966","",Vector4(3,3,3,3),4))
		theme.set_stylebox("grabber",bar,flat("4b6c83","",Vector4(0,0,0,0),4))
		theme.set_stylebox("grabber_highlight",bar,flat("6e93ac","",Vector4(0,0,0,0),4))
		theme.set_stylebox("grabber_pressed",bar,flat(COLORS.accent,"",Vector4(0,0,0,0),4))
	theme.set_stylebox("panel","ScrollContainer",flat("00000000","",Vector4(0,0,0,0),0))
	theme.set_stylebox("focus","ScrollContainer",flat("00000000","",Vector4(0,0,0,0),0))
	# Label variations.
	for pair in [["Eyebrow","muted","micro"],["Muted","muted","small"],["Secondary","text_2","small"],["Title","accent","h1"],["Section","accent","h2"],["Display","accent","display"]]:
		theme.set_type_variation(pair[0],"Label")
		theme.set_color("font_color",pair[0],color(pair[1]))
		theme.set_font_size("font_size",pair[0],size(pair[2],large))
	# Panel variations.
	theme.set_stylebox("panel","PanelContainer",panel_style())
	for pair in [["Card","card"],["Inset","inset"],["Strip","strip"],["Bar","bar"]]:
		theme.set_type_variation(pair[0],"PanelContainer")
		theme.set_stylebox("panel",pair[0],panel_style(pair[1]))
	theme.set_type_variation("Kbd","PanelContainer")
	theme.set_stylebox("panel","Kbd",flat("0c1a29",COLORS.border_strong,Vector4(7,1,7,2),5,1))
	theme.set_type_variation("Chip","PanelContainer")
	theme.set_stylebox("panel","Chip",flat("13273c","3b5a70",Vector4(10,4,12,4),14,1))
	theme.set_type_variation("Toast","PanelContainer")
	theme.set_stylebox("panel","Toast",flat("1a3450f5",COLORS.border_strong,Vector4(16,10,18,10),10,1,16))
	theme.set_constant("separation","VBoxContainer",8)
	theme.set_constant("separation","HBoxContainer",8)
	return theme

## Shape-coded status mark. Same shape, same meaning, at any color or font.
class Glyph extends Control:
	var tone := "unknown"
	var diameter := 12.0
	func _init(initial: String = "unknown", size_px: float = 12.0) -> void:
		tone=initial; diameter=size_px
		custom_minimum_size=Vector2(size_px+4,size_px+4)
		mouse_filter=Control.MOUSE_FILTER_IGNORE
	func set_tone(value: String) -> void:
		if tone!=value:
			tone=value; queue_redraw()
	func _draw() -> void:
		var c := Color(TONES.get(tone,TONES["unknown"])[0])
		var center := size*0.5
		var r := diameter*0.5
		var w := maxf(2.0,diameter*0.18)
		match str(TONES.get(tone,TONES["unknown"])[1]):
			"disc": draw_circle(center,r,c)
			"check":
				draw_circle(center,r,c)
				draw_polyline(PackedVector2Array([center+Vector2(-r*0.5,0),center+Vector2(-r*0.12,r*0.42),center+Vector2(r*0.55,-r*0.42)]),Color(COLORS["ink"]),w*0.9,true)
			"ring": draw_arc(center,r-w*0.5,0,TAU,32,c,w,true)
			"ring_dot":
				draw_arc(center,r-w*0.5,0,TAU,32,c,w,true)
				draw_circle(center,r*0.32,c)
			"half":
				draw_arc(center,r-w*0.5,0,TAU,32,c,w,true)
				var points := PackedVector2Array()
				for i in range(17): points.append(center+Vector2(cos(-PI/2+PI*i/16.0),sin(-PI/2+PI*i/16.0))*(r-w*0.5))
				draw_colored_polygon(points,c)
			"cross":
				draw_line(center+Vector2(-r*0.7,-r*0.7),center+Vector2(r*0.7,r*0.7),c,w,true)
				draw_line(center+Vector2(r*0.7,-r*0.7),center+Vector2(-r*0.7,r*0.7),c,w,true)
			"dash": draw_line(center+Vector2(-r*0.75,0),center+Vector2(r*0.75,0),c,w,true)
			"equals":
				draw_line(center+Vector2(-r*0.7,-r*0.35),center+Vector2(r*0.7,-r*0.35),c,w,true)
				draw_line(center+Vector2(-r*0.7,r*0.35),center+Vector2(r*0.7,r*0.35),c,w,true)
			"diamond":
				draw_polyline(PackedVector2Array([center+Vector2(0,-r),center+Vector2(r,0),center+Vector2(0,r),center+Vector2(-r,0),center+Vector2(0,-r)]),c,w,true)
			"pause":
				draw_line(center+Vector2(-r*0.35,-r*0.7),center+Vector2(-r*0.35,r*0.7),c,w,true)
				draw_line(center+Vector2(r*0.35,-r*0.7),center+Vector2(r*0.35,r*0.7),c,w,true)

static func label(parent: Node, value: String, variation: String = "", wrap: bool = true) -> Label:
	var l := Label.new()
	l.text=value
	if not variation.is_empty(): l.theme_type_variation=variation
	if wrap:
		l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

static func eyebrow(parent: Node, value: String) -> Label:
	return label(parent,value.to_upper(),"Eyebrow")

static func section(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	var l := label(row,title.to_upper(),"Eyebrow",false)
	l.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var rule := ColorRect.new()
	rule.color=color("border")
	rule.custom_minimum_size=Vector2(0,1)
	rule.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	rule.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row

static func divider(parent: Node) -> ColorRect:
	var rule := ColorRect.new()
	rule.color=color("border")
	rule.custom_minimum_size=Vector2(0,1)
	rule.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return rule

static func card(parent: Node, variation: String = "Card", separation: int = 6) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation=variation
	p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",separation)
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	p.add_child(col)
	return col

static func kbd(parent: Node, key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation="Kbd"
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	var l := Label.new()
	l.text=key
	l.theme_type_variation="Secondary"
	l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color",color("accent"))
	p.add_child(l)
	return p

static func hint(parent: Node, key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",7)
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	kbd(row,key)
	var l := label(row,text,"Secondary",false)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return row

## Glyph + text. The label keeps the state word so the tone is never color-only.
static func badge(parent: Node, tone: String, text: String, variation: String = "Secondary") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",7)
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var g := Glyph.new(tone,12)
	g.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	g.name="Glyph"
	row.add_child(g)
	var l := label(row,text,variation,false)
	l.name="Text"
	l.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.set_meta("tone",tone)
	return row

static func set_badge(row: HBoxContainer, tone: String, text: String) -> void:
	row.get_node("Glyph").set_tone(tone)
	row.get_node("Text").text=text
	row.set_meta("tone",tone)

static func chip(parent: Node, tone: String, name_text: String, activity: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation="Chip"
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var row := badge(p,tone,name_text+"  ·  "+activity)
	p.set_meta("badge",row)
	return p

static func icon_button(parent: Node, value: String, action: Callable, tooltip: String) -> Button:
	var b := button(parent,value,action,"IconButton")
	b.custom_minimum_size=Vector2(36,36)
	b.size_flags_horizontal=Control.SIZE_SHRINK_END
	b.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	b.tooltip_text=tooltip
	b.add_theme_font_size_override("font_size",22)
	return b

## Buttons keep their caption in their minimum size. Callers that place a
## button in a fixed-width row set clip_text so the row, not the text, wins.
static func button(parent: Node, value: String, action: Callable, variation: String = "", key: String = "") -> Button:
	var b := Button.new()
	b.text=value
	if not variation.is_empty(): b.theme_type_variation=variation
	b.custom_minimum_size=Vector2(96,40)
	b.tooltip_text=value+("  ["+key+"]" if not key.is_empty() else "")
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	if not key.is_empty():
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		var cap := kbd(b,key)
		cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		cap.grow_horizontal=Control.GROW_DIRECTION_BEGIN
		cap.offset_right=-10
		b.set_meta("kbd",cap)
		# Keep the caption clear of the key cap.
		var source := build()
		for state in ["normal","hover","pressed","disabled"]:
			var s: StyleBoxFlat=(source.get_stylebox(state,variation if not variation.is_empty() else "Button") as StyleBoxFlat).duplicate()
			s.content_margin_right=46
			b.add_theme_stylebox_override(state,s)
	return b

## Reveal a panel. Reduced motion shows it immediately; otherwise a short fade.
## Only modulate is animated: hidden anchored panels have stale layout, and
## writing position or size here would bake that stale size into their offsets.
static func reveal(panel: Control, reduced: bool, _from: Vector2 = Vector2.ZERO) -> void:
	panel.show()
	if reduced or not panel.is_inside_tree():
		panel.modulate=Color.WHITE
		return
	panel.modulate=Color(1,1,1,0)
	var tween := panel.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel,"modulate",Color.WHITE,0.16)
