extends SceneTree
var failures: Array[String] = []
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var Spring=load("res://characters/secondary_motion.gd")
	var spring=Spring.new()
	for i in range(240): spring.step(Vector3(.1,0,0),.08,1.0/60.0,false)
	check(spring.angles.length()<=.10001 and spring.angles.length()>.01,"Secondary response is nonzero and bounded")
	spring.step(Vector3.ZERO,0,1.0/60.0,true)
	check(spring.angles==Vector2.ZERO and spring.velocity==Vector2.ZERO,"Reduced motion clears spring immediately")
	spring.step(Vector3(8,0,0),0,1.0/60.0,false)
	check(spring.angles==Vector2.ZERO,"Teleport cannot kick hair")
	var Visual=load("res://characters/model_visual.gd")
	var old=Visual.new()
	var candidate=Visual.new()
	root.add_child(old); root.add_child(candidate)
	old.configure(load("res://assets/characters/cybercat-vanguard/vanguard.glb"),1.0)
	candidate.configure(load("res://assets/characters/cybercat-vanguard-secondary/vanguard-secondary.glb"),1.0)
	check(candidate.hair_bone>=0 and old.hair_bone==-1,"Secondary joint exists only in new variant")
	for i in range(90):
		var travel=Vector3(.1,0,0) if i<45 else Vector3(0,0,.1)
		old.project(travel,true,float(i%60)/60.0,false,1.0/60.0)
		candidate.project(travel,true,float(i%60)/60.0,false,1.0/60.0)
		var a:Transform3D=old.skeleton.get_bone_global_pose(old.skeleton.find_bone("Head"))
		var b:Transform3D=candidate.skeleton.get_bone_global_pose(candidate.skeleton.find_bone("Head"))
		check(a.origin.distance_to(b.origin)<.0001 and a.basis.is_equal_approx(b.basis),"Helmet bone remains identical to original animation")
	candidate.project(Vector3.ZERO,false,0,true,1.0/60.0)
	check(candidate.skeleton.get_bone_pose_rotation(candidate.hair_bone).is_equal_approx(Quaternion.IDENTITY),"Reduced motion resets actual hair joint")
	var Foley=load("res://footfall.gd")
	check(Foley.surface_at(Vector3(-7,0,21))=="wood","Commons terrace has wooden footfalls")
	check(Foley.surface_at(Vector3(35,0,-18),true)=="wood","Habitat authored plank zone has wooden footfalls")
	check(Foley.surface_at(Vector3(-20,0,10.5))=="metal","Colony road has metal footfalls")
	check(Foley.surface_at(Vector3(-30,0,-32))=="soil","Unpaved ground has soil footfalls")
	var signatures: Array[int]=[]
	for kind in ["metal","wood","soil"]:
		var stream:AudioStreamWAV=Foley.sound(kind)
		check(stream.data.decode_s16(0)==0,"Footfall onset has no discontinuity")
		signatures.append(hash(stream.data))
	check(signatures[0]!=signatures[1] and signatures[1]!=signatures[2],"Three ground sounds are distinct")
	var actor=load("res://actor.gd").new(); actor.position=Vector3(-20,0,10.5); root.add_child(actor)
	var foley=Foley.new(); foley.actor=actor; root.add_child(foley)
	check(not foley.enabled and not foley.player.playing,"Foley starts muted")
	await physics_frame
	actor.motion=Vector3(6,0,0)
	var start:Vector3=actor.position
	for i in range(60): await physics_frame
	check(absf(actor.position.distance_to(start)-6.0)<.2,"Secondary motion preserves six metres per second")
	check(foley.contact_count>=3 and foley.contact_count<=5,"Foley uses actual displacement contact cadence")
	actor.motion=Vector3.ZERO
	await physics_frame
	await physics_frame
	var before:int=foley.contact_count
	for i in range(20): await physics_frame
	check(foley.contact_count==before and not foley.dust.emitting,"Stopped actor emits no footsteps or dust")
	foley.reduced=true
	check(not foley.dust.emitting,"Reduced motion stops dust immediately")
	foley.enabled=true
	foley.player.stream=foley.samples.wood; foley.player.play()
	await create_timer(0.08).timeout
	foley.enabled=false
	check(not foley.player.playing and not foley.ambience.playing,"Sound mute stops current audio immediately")
	old.queue_free(); candidate.queue_free(); actor.queue_free(); foley.queue_free()
	await create_timer(0.08).timeout
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("INHABITED_CHARACTER_PASSED: bounded hair; unchanged helmet; reduced motion; wood/metal/soil; contacts; 6m/s; mute")
	quit(0 if failures.is_empty() else 1)
