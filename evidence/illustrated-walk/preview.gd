extends SceneTree
## Raw illustrated-sheet review. No shader masking, image cleanup or live game state.
var sprite:=Sprite2D.new()
var label:=Label.new()
var source:Image
var frame:=0
var ticks:=0
var output:=""
const ANCHORS=[Vector2(270,410),Vector2(704,411),Vector2(1110,411),Vector2(1538,411),Vector2(264,852),Vector2(704,852),Vector2(1110,852),Vector2(1538,852)]
func _initialize() -> void:
	root.size=Vector2i(960,720)
	root.content_scale_size=Vector2i(960,720)
	root.title="Illustrated walk / raw frame review"
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sheet="): path=arg.trim_prefix("--sheet=")
		if arg.begins_with("--capture="): output=arg.trim_prefix("--capture=")
	assert(not path.is_empty())
	source=Image.load_from_file(path)
	assert(source.get_size()==Vector2i(1774,887))
	var background:=ColorRect.new(); background.color=Color("101e2e"); background.size=Vector2(960,720); root.add_child(background)
	sprite.texture=ImageTexture.create_from_image(source); sprite.region_enabled=true
	sprite.position=Vector2(480,585); sprite.scale=Vector2.ONE*1.1
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(sprite)
	label.position=Vector2(24,20); label.add_theme_font_size_override("font_size",24); root.add_child(label)
	var note:=Label.new(); note.position=Vector2(24,630)
	note.text="RAW ILLUSTRATED DRAFT / 8 frames, 7.5 fps\nPainted background remains visible. No cleanup or production rollout."
	root.add_child(note)
	set_pose(0)

func set_pose(index:int) -> void:
	var x0:=roundi((index%4)*source.get_width()/4.0)
	var x1:=roundi((index%4+1)*source.get_width()/4.0)
	var y0:=roundi((index/4)*source.get_height()/2.0)
	var y1:=roundi((index/4+1)*source.get_height()/2.0)
	var origin:=Vector2(x0,y0)
	var size:=Vector2(x1-x0,y1-y0)
	sprite.region_rect=Rect2(origin,size)
	# A common authored anchor is metadata, not per-frame image rescaling.
	sprite.offset=size*.5-(ANCHORS[index]-origin)
	label.text="CAPTAIN / ILLUSTRATED WALK STUDY\nFrame %d of 8" % [index+1]

func _process(_delta:float) -> bool:
	ticks+=1
	set_pose((ticks/4)%8)
	if ticks==48 and output!="":
		capture.call_deferred()
	if ticks==192: quit()
	return false

func capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output)
