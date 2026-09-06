extends SceneTree
## Reproducible native preview of the exact atlas regions used by the game/HUD.
const CrewArt = preload("res://crew_art.gd")
var capture := ""
var frame := 0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture=arg.trim_prefix("--capture=")
	root.size=Vector2i(1280,800)
	call_deferred("build")
func label(parent: Node,value: String,pos: Vector2,size: int,color: String) -> void:
	var node:=Label.new()
	node.text=value
	node.position=pos
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color(color))
	parent.add_child(node)
func build() -> void:
	var bg:=ColorRect.new()
	bg.color=Color("0b1424")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	label(bg,"STARBASE 02  /  EXPEDITION CREW",Vector2(36,26),15,"8dd6d9")
	label(bg,"Four silhouettes. One frontier.",Vector2(36,55),32,"f0e6d6")
	var rows := [["operator","THE CAPTAIN","Navy exploration suit · teal cape","e4b771"],["surveyor","SURVEYOR","Classic EVA suit · golden visor","d3e3ec"],["mender","MENDER","Copper exosuit · tool gauntlet","e79b5d"],["trainer","TRAINER","Ivory sentinel · blue markings","90c3ec"]]
	for i in range(rows.size()):
		var card:=Panel.new()
		card.position=Vector2(24+i*314,132)
		card.size=Vector2(290,566)
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("14253a")
		style.border_color=Color("36516a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(12)
		card.add_theme_stylebox_override("panel",style)
		bg.add_child(card)
		var art:=TextureRect.new()
		art.texture=CrewArt.pose(rows[i][0])
		art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		art.position=Vector2(5,20)
		art.size=Vector2(280,445)
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(art)
		label(card,rows[i][1],Vector2(20,481),23,rows[i][3])
		label(card,rows[i][2],Vector2(20,520),13,"b4c4cf")
	label(bg,"ART PREVIEW · Cosmetic appearances only. Agent capabilities and authority remain evidence-based.",Vector2(36,738),15,"91aabb")
func _process(_delta: float) -> bool:
	frame+=1
	if frame==20 and capture!="":
		save.call_deferred()
	return false
func save() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture)
	quit()
