extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var world=load("res://main.tscn").instantiate()
 root.add_child(world)
 await process_frame
 if not world.has_method("adjust_zoom"):
  printerr("UNMET: visible zoom controls must work in colony, room and map views")
  quit(1)
  return
 world.fixture_path="test-only"
 world.http.cancel_request()
 world.hud.reduced=true
 var buttons=world.hud.root.find_children("Zoom*","Button",true,false)
 assert(buttons.size()==2)
 for mode in ["outside","repair","map"]:
  if mode=="repair": world.enter_room("repair")
  if mode=="map": world.toggle_map()
  world._process(1.0)
  var size: float=world.camera.size
  buttons[0].pressed.emit()
  world._process(1.0)
  assert(world.camera.size<size)
  buttons[1].pressed.emit()
  world._process(1.0)
  assert(is_equal_approx(world.camera.size,size))
 world.colony_overview=false
 world.hud.reduced=false
 var actor=world.get_node("Operator")
 actor.position=Vector3(0,0,12)
 world.route=PackedVector3Array([Vector3(0,0,18)])
 await physics_frame
 await physics_frame
 assert(actor.motion.length()>5.5)
 world.route.clear()
 actor.motion=Vector3.ZERO
 var geography=load("res://geography.gd")
 assert(geography.bounds().size.x>120 and geography.bounds().size.y>100)
 for target in [Vector3(-50,0,0),Vector3(50,0,0),Vector3(0,0,48),Vector3(-70,0,-30),Vector3(70,0,-30)]:
  assert(not world.navigator.route(Vector3(0,0,12),target).is_empty())
 assert(world.commands.payload.is_empty())
 world.queue_free()
 await process_frame
 print("Exploration passed: faster travel, buttons in all camera modes, expanded navigable land, no dispatch")
 quit()
