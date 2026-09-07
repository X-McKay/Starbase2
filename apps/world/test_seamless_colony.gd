extends SceneTree
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
 if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func walk(world: Node3D, target: Vector3, context: Node3D) -> void:
 world.route=world.travel_route(target)
 check(not world.route.is_empty(),"Route exists to "+str(target))
 var actor=world.get_node("Operator")
 var before: Vector3=actor.position
 for tick in range(600):
  await physics_frame
  check(actor.position.distance_to(before)<0.2,"Walking must not teleport")
  before=actor.position
  if world.route.is_empty(): break
 check(actor.position.distance_to(target)<0.45,"Physical arrival "+str(target)+" got "+str(actor.position))
 check(world.active_building==context,"Physical crossing sets matching context")
func run() -> void:
 var world=load("res://main.tscn").instantiate()
 root.add_child(world)
 await process_frame
 await physics_frame
 world.fixture_path="test-only"
 world.http.cancel_request()
 var actor=world.get_node("Operator")
 for station in world.get_node("Buildings").get_children():
  actor.position=station.return_position()
  actor.motion=Vector3.ZERO
  await physics_frame
  var room=station.room
  check(room!=null,"Persistent room exists")
  if room==null: continue
  await walk(world,room.content.get_node("WalkTarget").global_position,station)
  check(station.cutaway<0.01,"Interior roof cutaway is complete")
  check(world.get_node("Terrace").visible and world.sky_layer.visible,"World remains visible")
  await walk(world,room.to_global(room.console_point),station)
  check(world.commands.payload.is_empty(),"Travel never dispatches work")
  await walk(world,station.return_position()+Vector3(0,0,3),null)
  for i in 60: await physics_frame
  check(station.openness==0 and not station.door_collision.disabled,"Airlock closes after clear exit")
  world.hud.reduced=true
  world.enter_room(str(station.name))
  await physics_frame
  await physics_frame
  check(world.active_building==station and station.cutaway==0,"Direct visit and reduced motion")
  world.exit_room()
  world.hud.reduced=false
  print("JOURNEY ",station.name)
 world.queue_free()
 await process_frame
 for failure in failures: push_error(failure)
 if failures.is_empty(): print("Seamless colony passed: five continuous journeys, console routes, airlocks, cutaways, direct visits, reduced motion, no dispatch")
 quit(0 if failures.is_empty() else 1)
