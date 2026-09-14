extends SceneTree
var directory:="res://../../evidence/crew-guide-20260913"
func _initialize(): run.call_deferred()
func picture(name:String):
 for frame in 4: await process_frame
 RenderingServer.force_draw(false)
 assert(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK)
func run():
 DirAccess.make_dir_recursive_absolute(directory)
 var w=load("res://main.tscn").instantiate()
 w.fixture_path="res://../../fixtures/world/stale.json";w.board_fixture="__empty_visual_fixture__"
 root.add_child(w)
 for frame in 4: await process_frame
 for kind in ["repair","review","gym","watchkeeper","reviewer"]:
  w.hud.open_place(kind)
  assert(not w.hud.crew_purpose.text.is_empty())
  await picture(kind)
  w.hud.crew_action.grab_focus()
  var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;root.push_input(event)
  await process_frame
  event=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event)
  await process_frame
  if kind=="repair": assert(w.hud.dossier_tabs.current_tab==2)
  elif kind in ["review","gym"]: assert(w.hud.operations.visible and w.hud.operations.tabs.current_tab==(0 if kind=="review" else 1))
  else: assert(w.hud.board.visible and w.hud.board.tabs.current_tab==0)
 root.size=Vector2i(800,640);root.content_scale_size=Vector2i(800,640)
 w.hud.large_text=true;w.hud.scale_text();w.hud.open_place("repair")
 await picture("repair-compact")
 w.hud.dossier_tabs.current_tab=1
 await picture("evidence-compact")
 print("CREW_GUIDE_JOURNEYS_PASSED")
 w.queue_free();await process_frame;quit()
