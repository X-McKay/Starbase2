extends SceneTree
## Deterministic sprite import: preserve source RGB, remove only connected matte.
## No background-color deletion from enclosed hair/armor details.
const Check=preload("res://characters/validate.gd")

static func remove_matte(image:Image, minimum:int, chroma:int) -> Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	var size:=image.get_size()
	var data:=image.get_data()
	var candidates:=PackedByteArray(); candidates.resize(size.x*size.y)
	var visited:=PackedByteArray(); visited.resize(candidates.size())
	for index in range(candidates.size()):
		var offset:=index*4
		var lo:=mini(data[offset],mini(data[offset+1],data[offset+2]))
		var hi:=maxi(data[offset],maxi(data[offset+1],data[offset+2]))
		candidates[index]=int(lo>=minimum and hi-lo<=chroma)
	var queue:=PackedInt32Array()
	for y in range(size.y):
		for x in [0,size.x-1]:
			var index:int=y*size.x+x
			if candidates[index] and not visited[index]: visited[index]=1; queue.append(index)
	for x in range(size.x):
		for y in [0,size.y-1]:
			var index:int=y*size.x+x
			if candidates[index] and not visited[index]: visited[index]=1; queue.append(index)
	var cursor:=0
	while cursor<queue.size():
		var index:=queue[cursor]; cursor+=1
		var x:=index%size.x
		for neighbor in [index-size.x,index+size.x,index-1 if x>0 else -1,index+1 if x<size.x-1 else -1]:
			if neighbor>=0 and neighbor<candidates.size() and candidates[neighbor] and not visited[neighbor]:
				visited[neighbor]=1; queue.append(neighbor)
	for index in queue: data[index*4+3]=0
	return {"image":Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,data),"removed_pixels":queue.size()}

func _initialize() -> void:
	var path:="res://../../art/characters/illustrated-captain.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): path=arg.trim_prefix("--manifest=")
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var identifier:=RegEx.new(); identifier.compile("^[a-z][a-z0-9-]+$")
	assert(identifier.search(config.id)!=null,"Unsafe asset id")
	var original:=Image.load_from_file(ProjectSettings.globalize_path(config.source))
	var size:=Vector2i(config.canvas[0],config.canvas[1])
	var pivot:=Vector2i(config.pivot[0],config.pivot[1])
	var columns:int=config.grid[0]; var rows:int=config.grid[1]
	assert(config.anchors.size()==columns*rows)
	var cell:=size+Vector2i(4,4)
	var atlas:=Image.create(cell.x*columns,cell.y*rows,false,Image.FORMAT_RGBA8)
	var regions:Array=[]
	var removals:Array=[]
	for index in range(columns*rows):
		var column:=index%columns; var row:=index/columns
		var origin:=Vector2i(roundi(column*original.get_width()/float(columns)),roundi(row*original.get_height()/float(rows)))
		var end:=Vector2i(roundi((column+1)*original.get_width()/float(columns)),roundi((row+1)*original.get_height()/float(rows)))
		if config.has("cells"):
			var rect:Array=config.cells[index]
			origin=Vector2i(rect[0],rect[1]); end=origin+Vector2i(rect[2],rect[3])
		assert(Rect2i(Vector2i.ZERO,original.get_size()).encloses(Rect2i(origin,end-origin)),"Source cell outside sheet")
		var frame:=original.get_region(Rect2i(origin,end-origin))
		var cutout:=remove_matte(frame,config.matte.minimum,config.matte.max_chroma)
		frame=cutout.image; removals.append(cutout.removed_pixels)
		# Uniform scale for the entire sheet. Never auto-fit individual poses.
		frame.resize(roundi(frame.get_width()*config.scale),roundi(frame.get_height()*config.scale),Image.INTERPOLATE_LANCZOS)
		var anchor:Vector2=(Vector2(config.anchors[index][0],config.anchors[index][1])-Vector2(origin))*float(config.scale)
		var offset:=pivot-Vector2i(roundi(anchor.x),roundi(anchor.y))
		var normalized:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
		normalized.blit_rect(frame,Rect2i(Vector2i.ZERO,frame.get_size()),offset)
		# Verify clipping before packing: source opaque pixels must fit the canvas.
		var bounds:=Check.visible_bounds(frame); bounds.position+=offset
		assert(Rect2i(Vector2i.ZERO,size).encloses(bounds),"Frame %d exceeds canvas (%s); fix scale/anchor" % [index,bounds])
		var errors:=Check.frame_errors(normalized,size)
		assert(errors.is_empty(),str(errors))
		var target:=Vector2i(column*cell.x+2,row*cell.y+2)
		atlas.blit_rect(normalized,Rect2i(Vector2i.ZERO,size),target)
		regions.append(Rect2i(target,size))
	var output:String="res://art/characters/"+config.id+".png"
	assert(atlas.save_png(ProjectSettings.globalize_path(output))==OK)
	# External PNG references keep the SpriteFrames resource small and editable.
	var resources:Array[String]=[]
	var animations:Array[String]=[]
	var idle:Texture2D=load(config.idle_atlas)
	var next_id:=1
	for direction in range(4 if config.get("include_idle",true) else 0):
		var x0:=roundi(direction*idle.get_width()/4.0)
		var x1:=roundi((direction+1)*idle.get_width()/4.0)
		var y0:=roundi(config.idle_row*idle.get_height()/4.0)
		var y1:=roundi((config.idle_row+1)*idle.get_height()/4.0)
		var padding:=floori((x1-x0)*.13)
		resources.append(region_resource(next_id,2,Rect2i(x0+padding,y0,x1-x0-padding*2,y1-y0)))
		animations.append(animation_resource("idle_"+["front","back","left","right"][direction],[next_id],[1]))
		next_id+=1
	for clip in config.clips:
		var ids:Array=[]
		for index in config.clips[clip].frames:
			resources.append(region_resource(next_id,1,regions[index])); ids.append(next_id); next_id+=1
		animations.append(animation_resource(clip,ids,config.clips[clip].durations))
	var text:="[gd_resource type=\"SpriteFrames\" load_steps=%d format=3]\n" % [resources.size()+3]
	text+="[ext_resource type=\"Texture2D\" path=%s id=\"1\"]\n" % JSON.stringify(output)
	text+="[ext_resource type=\"Texture2D\" path=%s id=\"2\"]\n" % JSON.stringify(config.idle_atlas)
	text+="\n".join(resources)+"\n[resource]\nanimations = ["+",\n".join(animations)+"]\n"
	var frames_path:String="res://characters/frames/"+config.id+".tres"
	FileAccess.open(frames_path,FileAccess.WRITE).store_string(text)
	var report:={"source_sha256":FileAccess.get_sha256(config.source),"manifest_sha256":FileAccess.get_sha256(path),"importer_sha256":FileAccess.get_sha256("res://characters/illustrated_import.gd"),"atlas_sha256":FileAccess.get_sha256(output),"frames_sha256":FileAccess.get_sha256(frames_path),"matte_removed_pixels":removals,"canvas":config.canvas,"pivot":config.pivot,"scale":config.scale,"stride_m":config.stride_m,"provenance":config.provenance,"implemented_clips":config.clips.keys(),"missing_walk_directions":["front","back","left","right"].filter(func(direction): return not config.clips.has("walk_"+direction)),"automatic_mirroring":false}
	FileAccess.open(output.trim_suffix(".png")+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print("Imported ",config.id," / clips ",config.clips.keys()," / retained enclosed light pixels; RGBA and canvas checks passed")
	quit()

static func region_resource(id:int, atlas:int, region:Rect2i) -> String:
	return "[sub_resource type=\"AtlasTexture\" id=\"Frame_%d\"]\natlas = ExtResource(\"%d\")\nregion = Rect2(%d,%d,%d,%d)\nfilter_clip = true\n" % [id,atlas,region.position.x,region.position.y,region.size.x,region.size.y]

static func animation_resource(name:String, ids:Array, durations:Array) -> String:
	assert(ids.size()==durations.size())
	var frames:Array[String]=[]
	for index in range(ids.size()):
		frames.append("{\"duration\": %f, \"texture\": SubResource(\"Frame_%d\")}" % [durations[index],ids[index]])
	return "{\"name\": &%s, \"loop\": true, \"speed\": 8.0, \"frames\": [%s]}" % [JSON.stringify(name),",".join(frames)]
