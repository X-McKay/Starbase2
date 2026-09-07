extends Resource
## Cosmetic asset contract. Collision and operational permissions live elsewhere.
@export var id := ""
@export var atlas: Texture2D
@export var canvas := Vector2i(256,320)
@export var pivot := Vector2(128,300)
@export var pixel_size := 0.01
@export var stride := 1.28
@export var gutter := 2
@export var animated := true
@export var legacy_row := 0
@export var source := ""
@export var sprite_frames: SpriteFrames
@export var additional_frames: Array[SpriteFrames] = []
@export var clip_layouts: Dictionary = {}
@export var model_scene: PackedScene
@export var model_tint := Color.WHITE
@export var model_scale := 1.5
@export var model_floor_offset := -0.10
@export var label_height := 3.65
@export var model_stride := 1.8
@export var model_run_stride := 2.8
var cached_frames: SpriteFrames
const DIRECTIONS := ["front","back","left","right"]

func frames() -> SpriteFrames:
	if cached_frames: return cached_frames
	if sprite_frames:
		cached_frames=sprite_frames.duplicate()
		for library in additional_frames:
			for clip in library.get_animation_names():
				assert(not cached_frames.has_animation(clip),"Duplicate character clip: "+clip)
				cached_frames.add_animation(clip)
				cached_frames.set_animation_loop(clip,library.get_animation_loop(clip))
				cached_frames.set_animation_speed(clip,library.get_animation_speed(clip))
				for index in range(library.get_frame_count(clip)):
					cached_frames.add_frame(clip,library.get_frame_texture(clip,index),library.get_frame_duration(clip,index))
		return cached_frames
	cached_frames=SpriteFrames.new()
	cached_frames.remove_animation("default")
	for direction in range(4):
		for clip in ["idle","walk"]:
			var key: String = clip+"_"+DIRECTIONS[direction]
			cached_frames.add_animation(key)
			cached_frames.set_animation_loop(key,true)
			for frame in range(8 if animated and clip=="walk" else 1):
				var texture := AtlasTexture.new(); texture.atlas=atlas; texture.filter_clip=true
				if animated:
					var column: int = frame+1 if clip=="walk" else 0
					texture.region=Rect2(Vector2(column*(canvas.x+gutter*2)+gutter,direction*(canvas.y+gutter*2)+gutter),Vector2(canvas))
				else:
					var x0:=roundi(atlas.get_width()*direction/4.0)
					var x1:=roundi(atlas.get_width()*(direction+1)/4.0)
					var y0:=roundi(atlas.get_height()*legacy_row/4.0)
					var y1:=roundi(atlas.get_height()*(legacy_row+1)/4.0)
					var padding:=floori((x1-x0)*0.13)
					texture.region=Rect2(x0+padding,y0,x1-x0-padding*2,y1-y0)
				cached_frames.add_frame(key,texture)
	return cached_frames

func animation_for(walking:bool, direction:int) -> String:
	var name: String=("walk_" if walking else "idle_")+DIRECTIONS[direction]
	return name if frames().has_animation(name) else "idle_"+DIRECTIONS[direction]

func layout_for(animation:String) -> Dictionary:
	if clip_layouts.has(animation): return clip_layouts[animation]
	if animated: return {"canvas":canvas,"pivot":pivot,"pixel_size":pixel_size,"shaded":false}
	return {}

func frame_for_phase(animation:String, phase:float) -> int:
	var library:=frames()
	var total:=0.0
	for index in range(library.get_frame_count(animation)): total+=library.get_frame_duration(animation,index)
	var remaining:=fposmod(phase,1.0)*total
	for index in range(library.get_frame_count(animation)):
		remaining-=library.get_frame_duration(animation,index)
		if remaining<0: return index
	return 0
