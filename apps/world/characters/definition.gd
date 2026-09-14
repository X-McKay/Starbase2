extends Resource
## Cosmetic asset contract. Collision and operational permissions live elsewhere.
@export var id := ""
## Personal name; asset IDs and operational roles remain stable.
@export var display_name := ""
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
## Keep authored PBR channels/colors; role color still applies to separate equipment.
@export var preserve_source_materials := false
@export var animation_family := ""
## Independent rigs supply clips baked against their own bind/rest transforms.
## Keys are library namespaces (e.g. social/work), values are PackedScenes.
@export var model_animation_sources: Dictionary = {}
@export var use_legacy_animation_libraries := true
@export var upper_spine_bone := "Spine02"
## Cosmetic rotation-only bones; empty disables secondary motion for rigid art.
@export var secondary_motion_bones := PackedStringArray(["HairSwing"])
## Qualify each model's deformation envelope in native front/side captures.
@export_range(0.0,10.0,0.05) var secondary_motion_strength := 1.0
@export_range(0.0,1.5,0.005) var secondary_motion_limit := 0.10
@export var motion_profile := "operator"
@export var model_scale := 1.5
@export var model_floor_offset := -0.10
@export var label_height := 3.65
@export var model_stride := 1.8
@export var model_run_stride := 2.8
## Authored palm attachment in across/up/forward axes; legacy wrist defaults retained.
@export var work_slate_palm_offset := Vector3(0,0.035,0.055)
@export_range(0.1,2.0,0.01) var work_slate_grip_span_scale := 1.0
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
