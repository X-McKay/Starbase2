extends SceneTree
## Isolated native keyboard journeys for exploration and observation details.
var directory:=""
func _initialize():run.call_deferred()
func press(code:Key) -> void:
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
 root.push_input(event);await process_frame
 event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false
 root.push_input(event);await process_frame
func picture(name:String) -> void:
 for frame in 3:await process_frame
 RenderingServer.force_draw(false)
 assert(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK)
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):directory=arg.trim_prefix("--capture-dir=")
 if directory.is_empty():push_error("Explicit capture directory required");quit(1);return
 DirAccess.make_dir_recursive_absolute(directory)
 var w=load("res://main.tscn").instantiate()
 w.fixture_path="res://../../fixtures/world/stale.json";w.board_fixture="__empty_visual_fixture__"
 root.add_child(w)
 for frame in 3:await process_frame
 await press(KEY_F1)
 assert(w.hud.exploration_hud_collapsed and not w.hud.navigation_bar.visible and w.hud.chrome_toggle.visible,"F1 collapses world chrome with a restore action")
 await picture("collapsed-hud")
 await press(KEY_F1)
 assert(not w.hud.exploration_hud_collapsed and w.hud.navigation_bar.visible,"F1 restores exploration")
 root.size=Vector2i(800,640);root.content_scale_size=Vector2i(800,640)
 w.hud.large_text=true;w.hud.scale_text();w.hud.station_records.present("review")
 for frame in 3:await process_frame
 w.hud.station_records.freshness_toggle.grab_focus()
 await press(KEY_ENTER)
 assert(w.hud.station_records.freshness_details.visible,"Keyboard expands observation timestamp")
 await picture("keyboard-observation-details")
 print("UI_POLISH_KEYBOARD_PASSED");w.queue_free();await process_frame;quit()
