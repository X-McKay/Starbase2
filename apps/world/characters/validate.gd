extends RefCounted
## Technical acceptance only. Anatomy, costume fidelity and gait still need review.
static func visible_bounds(image:Image) -> Rect2i:
	# Match the margin check below. Generated RGBA may contain sub-visible alpha
	# in otherwise empty margins; those pixels are discarded by the actor shader.
	var minimum:=image.get_size()
	var maximum:=Vector2i(-1,-1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a>.1:
				minimum=minimum.min(Vector2i(x,y)); maximum=maximum.max(Vector2i(x,y))
	return Rect2i(minimum,maximum-minimum+Vector2i.ONE) if maximum.x>=0 else Rect2i()

static func frame_errors(image: Image, size: Vector2i) -> Array[String]:
	var errors: Array[String]=[]
	if image==null or image.is_empty(): return ["Missing frame"]
	if image.get_size()!=size: return ["Wrong canvas dimensions"]
	if image.detect_alpha()==Image.ALPHA_NONE: errors.append("Missing usable transparency")
	var opaque:=0
	var transparent:=0
	var clipped:=false
	for y in range(size.y):
		for x in range(size.x):
			var alpha:=image.get_pixel(x,y).a
			if alpha>.95: opaque+=1
			if alpha<.01: transparent+=1
			if alpha>.1 and (x<2 or y<2 or x>=size.x-2 or y>=size.y-2): clipped=true
	if opaque<100: errors.append("Empty or translucent frame")
	if transparent<100: errors.append("Opaque background")
	if clipped: errors.append("Artwork clips canvas margin")
	return errors

static func definition_errors(definition: Resource) -> Array[String]:
	var errors: Array[String]=[]
	if definition.id.is_empty() or definition.source.is_empty(): errors.append("Missing identity/provenance")
	if definition.stride<=0 or definition.pixel_size<=0: errors.append("Invalid physical scale")
	if not Rect2(Vector2.ZERO,Vector2(definition.canvas)).has_point(definition.pivot): errors.append("Pivot outside canvas")
	if definition.atlas==null: return ["Missing atlas"]
	if definition.atlas.get_width()>4096 or definition.atlas.get_height()>4096: errors.append("Atlas exceeds 4096 pixel budget")
	var frames: SpriteFrames=definition.frames()
	for direction in definition.DIRECTIONS:
		if not frames.has_animation("idle_"+direction): errors.append("Missing idle fallback "+direction)
	for key in frames.get_animation_names():
		var walk:bool=key.begins_with("walk_")
		var layout:Dictionary=definition.layout_for(key)
		var expected:int=layout.get("frames",8 if walk and definition.animated else 1)
		if frames.get_frame_count(key)!=expected: errors.append("Wrong frame count "+key)
		var seen: Dictionary={}
		for index in range(frames.get_frame_count(key)):
			var texture:AtlasTexture=frames.get_frame_texture(key,index)
			if texture==null or texture.atlas==null: errors.append("Missing texture "+key); continue
			if texture.atlas.get_width()>4096 or texture.atlas.get_height()>4096: errors.append("Atlas exceeds budget")
			if not Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region):
				errors.append("Frame outside atlas"); continue
			var image:=texture.atlas.get_image().get_region(Rect2i(texture.region))
			if not layout.is_empty():
				if not Rect2(Vector2.ZERO,Vector2(layout.canvas)).has_point(Vector2(layout.pivot)): errors.append("Clip pivot outside canvas")
				if float(layout.pixel_size)<=0: errors.append("Invalid clip scale")
				for error in frame_errors(image,Vector2i(layout.canvas)): errors.append(key+": "+error)
				var digest:=hash(image.get_data())
				if seen.has(digest): errors.append("Duplicate stride pose in "+key)
				seen[digest]=true
	return errors
