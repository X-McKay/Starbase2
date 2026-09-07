extends SceneTree
var failures: Array[String]=[]
func check(condition: bool, message: String) -> void:
 if not condition: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var actor=load("res://actor.gd").new()
 root.add_child(actor)
 await physics_frame
 await physics_frame
 actor.motion=Vector3(6,0,0)
 var start: Vector3=actor.position
 var contacts:=0
 var phase: float=actor.gait.phase
 for i in range(60):
  await physics_frame
  contacts+=actor.gait.contacts
 var distance: float=actor.position.distance_to(start)
 var expected: float=fposmod(phase+distance/actor.character_definition.model_run_stride,1.0)
 check(absf(actor.gait.phase-expected)<0.02,"Running phase follows actual distance / run stride")
 check(contacts>=3 and contacts<=5,"Six metres of running has a plausible contact cadence")
 check(actor.model_visual.clip=="run","Player uses the running clip")
 actor.motion=Vector3.ZERO
 await physics_frame
 await physics_frame
 check(actor.model_visual.clip=="idle","Stopping returns to idle")
 actor.queue_free()
 await process_frame
 for failure in failures: push_error(failure)
 if failures.is_empty(): print("RUN_CADENCE_PASSED: 6 m/s uses 2.8 m stride, physical contacts and stop-to-idle")
 quit(0 if failures.is_empty() else 1)
