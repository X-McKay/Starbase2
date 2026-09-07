extends SceneTree
const Definition=preload("res://building_definition.gd")
const Station=preload("res://station.gd")
const Catalog=preload("res://building_catalog.gd")
const Room=preload("res://colony_room.gd")
const Navigation=preload("res://navigation.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ids := {}
	var dir := DirAccess.open("res://buildings/definitions")
	for file in dir.get_files():
		if not file.ends_with(".tres"): continue
		var definition=load("res://buildings/definitions/"+file)
		check(definition.problems().is_empty(),file+": "+"; ".join(definition.problems()))
		check(not ids.has(definition.id),"Duplicate catalog ID: "+str(definition.id))
		ids[definition.id]=true
		if not definition.exterior_image.is_empty():
			var texture: Texture2D=load(definition.exterior_image)
			check(Rect2(Vector2.ZERO,texture.get_size()).has_point(definition.image_door_pixel),"Image door anchor outside source pixels")
			var pixels := texture.get_image()
			check(pixels.detect_alpha()!=Image.ALPHA_NONE,"Building image needs genuine transparency")
			for corner in [Vector2i.ZERO,Vector2i(pixels.get_width()-1,0),Vector2i(0,pixels.get_height()-1),Vector2i(pixels.get_width()-1,pixels.get_height()-1)]:
				check(pixels.get_pixelv(corner).a<0.01,"Opaque image corner")
		if not definition.interior_scene.is_empty():
			var room=Room.new()
			room.definition=definition
			root.add_child(room)
			for point in [room.spawn_point,room.console_point,room.crew_point]:
				check(room.clear(Vector2(point.x,point.z)),"Interior anchor obstructed: "+file)
				check(not room.route(room.spawn_point,point).is_empty(),"Interior anchor unreachable: "+file)
			room.free()
	var invalid=Definition.new()
	check(not invalid.problems().is_empty(),"Empty definition must fail validation")
	invalid=load("res://buildings/definitions/repair.tres").duplicate()
	invalid.exterior_image="res://buildings/art/engineering-hangar.png"
	invalid.exterior_scene="res://buildings/exteriors/review.tscn"
	check(not invalid.problems().is_empty(),"Two exterior modes must fail validation")
	invalid.exterior_scene=""
	invalid.return_point=Vector3(-2,0,-2)
	check(not invalid.problems().is_empty(),"Return inside solid footprint must fail validation")
	invalid=load("res://buildings/definitions/repair.tres").duplicate()
	invalid.pad_margin=Vector4(1.5,1.5,-1,1.5)
	check("Pad margins must be nonnegative" in invalid.problems(),"Negative foundation margins must fail validation")
	var nav=Navigation.new()
	var layout=Catalog.LAYOUT.instantiate()
	root.add_child(layout)
	await physics_frame
	var contexts := {}
	var exterior_images := {}
	var occupied: Array[Rect2]=[]
	for station in layout.get_children():
		var asset: String=station.definition.exterior_scene if station.definition.exterior_image.is_empty() else station.definition.exterior_image
		check(not asset.is_empty(),"Every colony building has an exterior asset")
		check(not exterior_images.has(asset),"Placed colony buildings must have unique exterior artwork")
		exterior_images[asset]=true
		for local_rect in station.definition.collision_boxes:
			var footprint: Rect2=Rect2(local_rect.position+Vector2(station.position.x,station.position.z),local_rect.size)
			for other in occupied:
				check(not footprint.grow(1.0).intersects(other.grow(1.0)),"Buildings need at least a two-metre clear corridor between footprints")
			occupied.append(footprint)
		check(station.rotation.is_zero_approx() and station.scale.is_equal_approx(Vector3.ONE),"Placement requires unrotated unit scale")
		if not station.interaction_kind.is_empty():
			check(station.interaction_kind in ["repair","review","gym"] and not contexts.has(station.interaction_kind),"Unknown/duplicate operational binding")
			contexts[station.interaction_kind]=true
		check(not nav.route(Vector3(0,0,5.5),station.entrance()).is_empty(),"Door approach unreachable: "+str(station.name))
		check(not nav.route(station.return_position(),Vector3(0,0,5.5)).is_empty(),"Door return unreachable")
		for rect in station.definition.navigation_bounds():
			var point=station.position+Vector3(rect.get_center().x,0,rect.get_center().y)
			check(nav.route(Vector3.ZERO,point).is_empty(),"Navigation entered declared building footprint")
			var query=PhysicsRayQueryParameters3D.create(point+Vector3(0,20,0),point-Vector3(0,1,0))
			check(not station.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"No physics under declared footprint")
	layout.free()
	# 50 unique IDs/definitions, sharing a deliberately single art fixture.
	# This tests extension/resource reuse, not 50 unique-texture memory capacity.
	var start=Time.get_ticks_usec()
	var group=Node3D.new()
	root.add_child(group)
	var shared: Texture2D
	for i in range(50):
		var definition=load("res://buildings/definitions/repair.tres").duplicate()
		definition.id=StringName("scale-fixture-%02d" % i)
		definition.title="Scale fixture %02d" % i
		# This remains the original shared-image fixture, independently of the
		# production hangar's move to a detailed mesh.
		definition.exterior_scene=""
		definition.exterior_image="res://buildings/art/engineering-hangar.png"
		definition.yard_scene=""
		definition.seamless=false
		definition.interior_scene="res://buildings/interiors/engineering-3d.tscn"
		var station=Station.new()
		station.definition=definition
		station.position=Vector3((i%8)*15,0,(i/8)*12)
		group.add_child(station)
		var texture: Texture2D=station.get_node("Illustration").texture
		if i==0: shared=texture
		check(texture==shared,"Repeated art must share imported texture")
		check(not station.is_processing() and not station.is_physics_processing(),"Static building must not poll per frame")
		check(station.find_children("*","Label3D",true,false).is_empty(),"No operational status may be inferred from building art")
		check(station.find_children("*","Marker3D",true,false).size()==3,"Every definition gets common doorway anchors")
		check(station.find_children("*","StaticBody3D",true,false).size()==definition.collision_boxes.size(),"One shared host owns declared physics")
	check(group.get_child_count()==50,"50 buildings instantiated")
	var hud=preload("res://hud.gd").new()
	root.add_child(hud)
	hud.set_buildings(group.get_children())
	check(hud.building_list.get_child_count()==50,"Directory includes 50 places without manual menu entries")
	hud.filter_buildings("fixture 49")
	check(hud.building_list.get_children().filter(func(entry): return entry.visible).size()==1,"50-place directory remains searchable")
	hud.free()
	print("50 definition/host fixture creation ms: ",(Time.get_ticks_usec()-start)/1000.0)
	group.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Building catalog checks passed: assets, alpha, malformed metadata, room anchors, placement physics/routes, 50 IDs, shared texture, no per-frame polling")
	quit(0 if failures.is_empty() else 1)
