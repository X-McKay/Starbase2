extends SceneTree
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
var failures:Array[String]=[]
func check(ok:bool,message:String):
 if not ok:failures.append(message)
func _initialize():run.call_deferred()
func run():
 var definition=Catalog.get_definition("cybercat")
 check(definition.id=="cybercat","Cybercat has its own catalog identity")
 check(definition.model_scene.resource_path=="res://assets/characters/cybercat-player/character.glb","Explicit alternate asset")
 check(not definition.use_legacy_animation_libraries,"No inferred legacy libraries")
 for key in ["social","work"]:check(definition.model_animation_sources.get(key)==definition.model_scene,"Own-source "+key)
 var visual=Visual.new();root.add_child(visual);visual.configure_definition(definition);visual.set_motion_profile(definition.motion_profile)
 check(visual.animation.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"Project owns sampling")
 for name in ["idle","walk","run","console","field_slate","sit_down","seated","stand_up","social/sit_down","social/seated","social/stand_up","work/field_slate"]:
  check(visual.animation.has_animation(name),"Full own clip parity "+name)
 var hips=visual.skeleton.find_bone("Hips")
 for name in ["idle","walk","run","console","field_slate","sit_down","seated","stand_up"]:
  visual.animation.play(name);visual.animation.seek(.2,true)
  check(visual.skeleton.get_bone_pose_scale(hips).distance_to(Vector3.ONE)<.0001,"Stable body scale in "+name)
 visual.animation.stop()
 var mesh=visual.find_children("*","MeshInstance3D",true,false)[0]
 var material=mesh.get_active_material(0);visual.apply_role(Color.RED)
 check(mesh.get_active_material(0)==material and definition.preserve_source_materials,"Teal source material preserved")
 visual.project(Vector3.ZERO,false,0,false,1.0/30)
 for i in 12:visual.project(Vector3.ZERO,false,0,false,1.0/30)
 var arm=visual.skeleton.find_bone("LeftArm");var before=visual.skeleton.get_bone_pose_rotation(arm)
 visual.project(Vector3(0,0,.067),true,.2,false,1.0/30)
 var after=visual.skeleton.get_bone_pose_rotation(arm)
 check(before.angle_to(after)<.2,"Walk begins from prior rendered posture")
 var poses=[]
 for bone in visual.skeleton.get_bone_count():poses.append(visual.skeleton.get_bone_pose(bone))
 await process_frame
 for bone in visual.skeleton.get_bone_count():check(poses[bone].is_equal_approx(visual.skeleton.get_bone_pose(bone)),"Rendered frame preserves projected bone "+str(bone))
 for phase in [["console",120,"work/field_slate"],["sit",120,"social/seated"],["stand",90,"social/stand_up"]]:
  for i in phase[1]:visual.project(Vector3.ZERO,false,0,false,1.0/30,phase[0])
  check(visual.clip==phase[2],"Semantic clip "+phase[0])
  check(visual.work_slate.visible==(phase[0]=="console"),"Slate bound to work only")
 for i in 30:visual.project(Vector3(.15,0,.05),true,.4,false,1.0/30)
 visual.project(Vector3.ZERO,false,0,true,1.0/30)
 for bone in visual.secondary_bones:
  check(visual.skeleton.get_bone_pose_rotation(bone).is_equal_approx(visual.secondary_rest_rotations[bone]),"Reduced motion restores imported hair rest")
 check(visual.secondary_bones.size()==definition.secondary_motion_bones.size(),"All configured hair joints exist")
 visual.free()
 for failure in failures:push_error(failure)
 print("CYBERCAT_PLAYER_PARITY_PASSED" if failures.is_empty() else "CYBERCAT_PLAYER_PARITY_FAILED")
 quit(0 if failures.is_empty() else 1)
