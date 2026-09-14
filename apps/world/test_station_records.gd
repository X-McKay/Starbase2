extends SceneTree
const Records=preload("res://station_records.gd")
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
func record(id: String,kind: String,state: String,stamp: int=1) -> Dictionary:
	return {"input":{"id":id,"kind":kind,"target":"fixture"},"state":state,"updated_at":stamp,"stale":false,"evidence":{"summary":{"outcome":"partial"}}}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var source: Array=[record("review","review","completed"),record("field","watchkeeper","running"),record("pr","reviewer","failed"),record("repair","repair","queued")]
	var model=Records.project_station(source,"review",false,10)
	check(model.reports.size()==3 and model.reports[0].id=="field","Command includes all three roles; open work first")
	var many: Array=[]
	for i in range(25): many.append(record(str(i),"review","completed",i+1))
	many.append(record("open","review","queued",0))
	model=Records.project_station(many,"review",false,10)
	check(model.reports.size()==20 and model.total_count==26 and model.reports[0].id=="open","Bounded rows expose total and prioritize open work")
	var panel=Records.new(); root.add_child(panel)
	panel.update_records(source,false,10,true); panel.present("review")
	check(panel.freshness_toggle.text=="Details" and not panel.freshness_details.visible and panel.freshness_toggle.tooltip_text=="Show observation details","Freshness keeps a compact keyboard-accessible disclosure")
	panel.freshness_toggle.pressed.emit()
	check(panel.freshness_details.visible and panel.freshness_details.text.contains("Observation timestamp:") and panel.freshness_toggle.text=="Hide","Freshness disclosure exposes exact observation timestamp")
	var buttons=panel.reports.find_children("*","Button",true,false)
	var first=buttons[0]; first.grab_focus()
	var inspected: Array=[]
	panel.inspect_requested.connect(func(id: String,context: String): inspected.append([id,context]))
	first.pressed.emit()
	check(inspected==[["field","watchkeeper"]],"Exact field identity forwarded")
	check(panel.detail_metadata.text.contains("RECORD ID\nfield") and panel.detail_metadata.text.contains("watchkeeper"),"Selected detail retains exact identity and context")
	check(panel.detail_metadata.text.contains("advisory, not verified"),"Advisory qualification remains visible in selected detail")
	panel.detail_action.pressed.emit()
	check(inspected==[["field","watchkeeper"],["field","watchkeeper"]],"Dedicated selected action emits exact authoritative record")
	panel.set_large_text(false); panel.update_records(source,false,11,true)
	check(panel.reports.find_children("*","Button",true,false)[0]==first,"Unchanged polling preserves button identity")
	panel.update_records(source,true,11,true)
	var stale_button=panel.reports.find_children("*","Button",true,false)[0]
	check(root.gui_get_focus_owner()==stale_button,"Freshness transition preserves selected identity focus")
	panel.update_records(source,true,12,true)
	check(panel.reports.find_children("*","Button",true,false)[0]==stale_button,"Repeated stale polling preserves button identity")
	check(panel.freshness.text.contains("OFFLINE") and panel.summary.text.contains("last known"),"Stale inspection explicit")
	panel.search.text="field"; panel.refresh()
	check(panel.filtered_reports().size()==1 and panel.filtered_reports()[0].context=="watchkeeper","Search finds a resident field role by exact record ID")
	panel.search.text=""; panel.state_filter.select(1); panel.refresh()
	check(panel.filtered_reports().size()==1 and panel.filtered_reports()[0].id=="field","Open filter preserves authoritative active state")
	panel.state_filter.select(3); panel.refresh()
	check(panel.filtered_reports().size()==1 and panel.filtered_reports()[0].id=="pr","Failed filter distinguishes failed work")
	panel.state_filter.select(0); panel.refresh()
	panel.present("repair")
	check(panel.model.reports.size()==1 and panel.model.reports[0].id=="repair","Station selector filters owned records")
	for dimensions in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=dimensions; root.content_scale_size=dimensions
		panel.set_large_text(true); panel.layout(); await process_frame; await process_frame
		check(root.get_visible_rect().encloses(panel.get_global_rect()),"Large text panel fits viewport")
		check(panel.detail_scroll.visible == (dimensions.x >= 1100),"Detail column collapses on compact viewport without narrowing record rows")
		if dimensions.x < 1100:
			var visible_identity := false
			for label in panel.reports.find_children("*","Label",true,false):
				if label.is_visible_in_tree() and label.text.contains("ID repair"): visible_identity = true
			check(visible_identity,"Compact rows retain exact identity when the detail column is hidden")
	var one=record("single","reviewer","completed",int(Time.get_unix_time_from_system()))
	one.input.target="morning-offline-repository"
	panel.update_records([one],false,Time.get_unix_time_from_system(),true); panel.present("review")
	for frame in range(5): await process_frame
	var action:Button=panel.reports.find_children("*","Button",true,false)[0]
	check(panel.reports.get_parent().get_global_rect().encloses(action.get_global_rect()),"Single long field record exposes its whole Inspect button at compact large text without scrolling")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--records-capture-dir="):
			var destination:=arg.trim_prefix("--records-capture-dir=")
			DirAccess.make_dir_recursive_absolute(destination)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(destination+"/stations-800.png")==OK,"Native station capture saved")
	panel.reset(); check(panel.model.is_empty() and panel.source_records.is_empty(),"Reset discards retained installation records")
	panel.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STATION_RECORDS_PASSED: all resident roles, exact records, bounded list, freshness/focus/polling, large text")
	quit(0 if failures.is_empty() else 1)
