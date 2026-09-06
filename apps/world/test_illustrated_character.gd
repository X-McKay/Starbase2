extends SceneTree
const Import=preload("res://characters/illustrated_import.gd")
const Catalog=preload("res://characters/catalog.gd")
const Actor=preload("res://actor.gd")
const Check=preload("res://characters/validate.gd")
var contacts:=0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var input:=Image.create(20,20,false,Image.FORMAT_RGBA8); input.fill(Color(.95,.95,.95))
	input.fill_rect(Rect2i(4,4,12,12),Color.BLACK)
	input.fill_rect(Rect2i(6,6,8,8),Color.WHITE)
	var cutout:Image=Import.remove_matte(input,190,12).image
	assert(cutout.get_pixel(0,0).a==0,"Matte must be transparent")
	assert(cutout.get_pixel(8,8)==Color.WHITE,"Enclosed white armor/hair must survive")
	assert(cutout.get_pixel(4,4)==Color.BLACK,"Dark outlines must survive")
	cutout.set_pixel(0,0,Color(1,1,1,.01))
	assert(Check.visible_bounds(cutout)==Rect2i(4,4,12,12),"Sub-visible alpha must not move the artwork bounds")
	var definition=Catalog.get_definition("operator")
	var frames:SpriteFrames=definition.frames()
	assert(frames.has_animation("walk_right") and frames.get_frame_count("walk_right")==8)
	for direction in range(3):
		var clip:String="walk_"+definition.DIRECTIONS[direction]
		assert(definition.animation_for(true,direction)==clip and frames.get_frame_count(clip)==4,"Authored contact/passing poses in every direction")
	assert(definition.animation_for(false,3)=="idle_right")
	assert(Check.definition_errors(definition).is_empty())
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://art/characters/captain-illustrated.json"))
	assert(report.atlas_sha256==FileAccess.get_sha256("res://art/characters/captain-illustrated.png"))
	assert(report.source_sha256==FileAccess.get_sha256("res://../../evidence/illustrated-walk/side-cycle.png"))
	assert(report.manifest_sha256==FileAccess.get_sha256("res://../../art/characters/illustrated-captain.json"))
	assert(report.importer_sha256==FileAccess.get_sha256("res://characters/illustrated_import.gd"))
	assert(report.frames_sha256==FileAccess.get_sha256("res://characters/frames/captain-illustrated.tres"))
	assert(is_equal_approx(definition.stride,float(report.stride_m)))
	for direction in ["front","back","left"]:
		var prefix:String="res://art/characters/captain-"+direction
		var provenance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(prefix+".json"))
		assert(provenance.atlas_sha256==FileAccess.get_sha256(prefix+".png"))
		assert(provenance.source_sha256==FileAccess.get_sha256("res://../../evidence/illustrated-walk/captain-"+direction+".png"))
		assert(provenance.manifest_sha256==FileAccess.get_sha256("res://../../art/characters/illustrated-captain-"+direction+".json"))
		assert(provenance.importer_sha256==report.importer_sha256)
		assert(provenance.frames_sha256==FileAccess.get_sha256("res://characters/frames/captain-"+direction+".tres"))
		assert(provenance.automatic_mirroring==false)
	var first:AtlasTexture=frames.get_frame_texture("walk_right",0)
	var image:=first.atlas.get_image().get_region(Rect2i(first.region))
	assert(image.get_pixel(8,8).a<.01,"Baked checkerboard must be removed in actual texture")
	var actor=Actor.new(); root.add_child(actor); actor.foot_contact.connect(func(): contacts+=1)
	actor.motion=Vector3(3.2,0,0)
	var observed:Dictionary={}
	for i in range(80):
		await physics_frame
		if actor.sprite.animation=="walk_right": observed[actor.sprite.frame]=true
	assert(observed.size()==8,"All eight frames must actually play during travel")
	assert(contacts>=2,"Actual displacement must drive shared foot contacts")
	assert(actor.sprite.offset==Vector2(0,136) and is_equal_approx(actor.sprite.pixel_size,.009))
	actor.motion=Vector3.ZERO
	for i in range(3): await physics_frame
	assert(actor.sprite.animation=="idle_right" and actor.sprite.offset==Vector2.ZERO,"Stop restores approved still and its original layout")
	actor.motion=Vector3(3.2,0,0); actor.reduced_motion=true
	for i in range(3): await physics_frame
	assert(actor.sprite.animation=="idle_right")
	actor.reduced_motion=false
	for direction in range(3):
		actor.motion=[Vector3(0,0,3.2),Vector3(0,0,-3.2),Vector3(-3.2,0,0)][direction]
		var clip:String="walk_"+definition.DIRECTIONS[direction]
		observed.clear()
		for i in range(70):
			await physics_frame
			if actor.sprite.animation==clip: observed[actor.sprite.frame]=true
		assert(observed.size()==4,"All authored frames must play after direction change: "+clip)
		actor.reduced_motion=true
		for i in range(3): await physics_frame
		assert(actor.sprite.animation=="idle_"+definition.DIRECTIONS[direction])
		actor.reduced_motion=false
	# A character without an authored sheet keeps its corresponding original still.
	assert(Catalog.get_definition("surveyor").frames().get_frame_count("walk_front")==1)
	var wall:=StaticBody3D.new(); wall.position=actor.position+Vector3(.7,0,0)
	var collider:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=Vector3(.2,4,10)
	collider.shape=shape; wall.add_child(collider); root.add_child(wall)
	actor.motion=Vector3(3.7,0,0)
	for i in range(60): await physics_frame
	var phase:float=actor.gait.phase; var before:int=contacts
	for i in range(20): await physics_frame
	assert(is_equal_approx(phase,actor.gait.phase) and before==contacts,"Wall contact must not animate or emit footsteps")
	assert(actor.sprite.animation=="idle_right")
	print("Illustrated character passed: alpha, provenance, all four directions live, contacts, stop layout, wall and reduced motion")
	quit()
