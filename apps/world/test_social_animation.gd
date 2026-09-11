extends SceneTree
var output:=""
var side_view:=false
var actors:Array=[]
var records:Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--social-side": side_view=true
		if arg.begins_with("--capture-social="): output=arg.trim_prefix("--capture-social=")
	run.call_deferred()
func box(parent:Node,position:Vector3,size:Vector3,color:Color) -> void:
	var node:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=size
	var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=.8
	mesh.material=mat; node.mesh=mesh; node.position=position; parent.add_child(node)
func sample(name:String) -> void:
	var states:Array=[]
	for actor in actors:
		var visual=actor.model_visual
		var skeleton:Skeleton3D=visual.skeleton
		var points:Dictionary={}
		for bone in ["Hips","Head","LeftUpLeg","LeftLeg","RightLeg","LeftFoot","RightFoot","LeftHand","RightHand"]:
			var point:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin)-actor.position
			points[bone]=[point.x,point.y,point.z]
		if name=="seated":
			assert(absf(points.Hips[1]-(.76 if actor.appearance=="surveyor" else .63))<.03 and absf(points.Hips[2]+.55)<.03,"Seated pelvis must match authored bench contact")
			assert(points.Head[1]>1.05 and points.Head[1]<1.6 and absf(points.Head[2])<1.0,"Head must remain above torso, without accumulated child transforms")
			assert(points.LeftLeg[1]>=.48 and points.RightLeg[1]>=.48,"Knees and thighs must clear the seat slab")
			for foot in ["LeftFoot","RightFoot"]: assert(points[foot][1]>0.03 and points[foot][1]<.3 and absf(points[foot][2])<.4,"Feet remain near the planted floor contact")
		states.append({"id":actor.appearance,"clip":visual.clip,"points":points,"transition_finished":visual.social_transition_finished})
	records.append({"phase":name,"actors":states})
	if not output.is_empty():
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1280,800)
	var stage:=Node3D.new(); root.add_child(stage)
	var camera:=Camera3D.new(); stage.add_child(camera); camera.position=Vector3(3.6,2.7,6); camera.look_at(Vector3(0,.8,0)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=6.6
	if side_view: camera.position=Vector3(6,1.2,-.1); camera.look_at(Vector3(0,.8,-.2)); camera.size=2.7
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-25,0); sun.light_energy=1.5; stage.add_child(sun)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("273342"); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color("cad9e7"); environment.environment.ambient_light_energy=.5; stage.add_child(environment)
	box(stage,Vector3(0,-.05,0),Vector3(8,.1,5),Color("566774"))
	for i in range(1 if side_view else 3):
		var actor=preload("res://actor.gd").new(); actor.appearance=["surveyor","repair","operator"][i]
		actor.character_definition=load(["res://characters/definitions/surveyor.tres","res://characters/definitions/mender.tres","res://characters/definitions/operator.tres"][i])
		actor.position.x=0.0 if side_view else (i-1)*2.0; stage.add_child(actor); actors.append(actor)
		box(stage,Vector3(actor.position.x,.43,-.55),Vector3(.8,.1,.4),Color("a68257"))
		box(stage,Vector3(actor.position.x,.76,-.8),Vector3(.8,.5,.09),Color("a68257"))
		assert(actor.model_visual.animation.has_animation("social/seated"),"Baked social clips must load on actual selected skeleton")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for tick in range(12): await physics_frame
	await sample("standing")
	for actor in actors: actor.presentation_pose="sit"
	for tick in range(42): await physics_frame
	await sample("sit-mid")
	for tick in range(55): await physics_frame
	await sample("seated")
	for actor in actors:
		assert(actor.model_visual.clip=="social/seated" and actor.model_visual.social_transition_finished)
		actor.presentation_pose="stand"
	for tick in range(30): await physics_frame
	await sample("stand-mid")
	for tick in range(38): await physics_frame
	await sample("standing-return")
	for actor in actors: assert(actor.model_visual.social_transition_finished)
	for i in actors.size():
		for foot in ["LeftFoot","RightFoot"]:
			assert(absf(records[2].actors[i].points[foot][1]-records[4].actors[i].points[foot][1])<.002,"Sitting retains each rig own standing ankle-to-sole offset")
	for actor in actors: actor.presentation_pose="sit"; actor.reduced_motion=true
	for tick in range(3): await physics_frame
	for actor in actors: assert(actor.model_visual.clip=="social/seated" and actor.model_visual.social_transition_finished,"Reduced motion snaps to stable seated contact")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("poses.json"),FileAccess.WRITE); file.store_string(JSON.stringify(records,"  ")); file.close()
	stage.queue_free(); await process_frame
	print("SOCIAL_ANIMATION_CHECK_PASSED")
	quit()
