extends SceneTree
var failures:Array[String]=[]
var capture_directory:=""
var api:=""
func check(value:bool,message:String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:run.call_deferred()
func picture(name:String) -> void:
	for frame in 4:await process_frame
	if capture_directory.is_empty():return
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))==OK,"Saved "+name)
func fixture() -> Dictionary:
	var build:={"digest":"fixture-practice-incumbent","manifest":{"profile":"joint-readiness-v1","inference":true}}
	var candidate:={"digest":"fixture-practice-candidate","manifest":{"profile":"joint-readiness-v1","inference":true}}
	var rows:Array=[];var results:Array=[]
	for pair in 4:
		for arm in ["baseline","candidate"]:
			var id:="learning-child-%d-%s" % [pair,arm]
			rows.append({"slot":"p%d-%s" % [pair,arm],"pair":pair,"arm":arm,"scenario":["route-mismatch","healthy","persistent-dependency","listening-but-broken"][pair],"mission_id":id,"requests":24,"tokens":384000})
			results.append({"mission_id":id,"outcome":"diagnostic-pass","tokens_accounted":4200})
	var cycle:={"id":"practice-fixture-cycle","state":"completed","source_opportunity":{"id":"trainer-review-fixture"},"source_build":build,"baseline":build,"candidate":candidate,"proposal":{"state":"completed","accounted_tokens":420,"result":{"procedure":"Inspect probe contract and useful work separately.","rationale":"Separate readiness from correctness."}},"trials":rows,"trial_order":rows.map(func(value):return value.slot),"summary":{"outcome":"practice-adopted","baseline_passes":3,"candidate_passes":4,"pairs":4,"paired_regression":false,"hard_gates":{"integrity":true},"trials":results,"xp":0},"deadline":Time.get_unix_time_from_system()+7200,"updated_at":Time.get_unix_time_from_system()}
	return {"schema_version":6,"enabled":true,"control":{"duty":{"id":"readiness-practice","generation":3,"enabled":true,"baseline":build.digest,"max_cycles":2,"cooldown_seconds":60,"budget":{"proposal_requests":1,"proposal_tokens":32768,"trial_requests":24,"trial_tokens":384000}},"practice_incumbent":{"build":candidate.digest,"generation":1,"source_cycle":cycle.id},"admitted_cycles":1,"last_started_at":Time.get_unix_time_from_system()},"cycles":[cycle],"policy":{"scope":"local-public-practice","xp":0}}
func settled(command:Node) -> void:
	var deadline:=Time.get_ticks_msec()+12000
	while command.phase!="" and Time.get_ticks_msec()<deadline:await process_frame
	check(command.phase=="","Bounded operator command completes")
func wait_poll(panel:Node) -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while panel.pending and Time.get_ticks_msec()<deadline:await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_directory=arg.trim_prefix("--capture=")
		if arg.begins_with("--api="):api=arg.trim_prefix("--api=")
	if not capture_directory.is_empty():DirAccess.make_dir_recursive_absolute(capture_directory)
	var hud=load("res://hud.gd").new();hud.board_fixture="__empty_visual_fixture__";root.add_child(hud);await process_frame
	hud.connection.text="Preview fixture · local practice only · no training dispatched"
	hud.open_operations();hud.operations.tabs.current_tab=5
	var panel=hud.operations.learning;var data:=fixture()
	panel.apply_fixture(data)
	check(panel.enable_button.disabled and panel.stop_button.disabled and panel.cancel_button.disabled,"Fixtures cannot mutate duty or cycles")
	check(panel.make_duty(false).generation==4 and panel.make_duty(false).baseline=="fixture-practice-candidate","Stop uses next exact duty generation and current practice incumbent")
	check(panel.cycle_summary.text.contains("practice-adopted") and panel.cycle_summary.text.contains("no operational qualification or XP"),"Practice adoption cannot claim operational qualification")
	check(panel.trials.text.contains("learning-child-3-candidate") and panel.trials.text.contains("4200 tokens accounted"),"All paired trial identities and retained accounting remain inspectable")
	check(panel.baseline_detail.text.contains("3104768"),"Combined proposal and eight-trial reservation is explicit")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size;root.content_scale_size=size;hud.large_text=size.x<1000;hud.scale_text()
		panel.scroll.scroll_vertical=0;await picture("practice-%d-duty" % size.x)
		check(panel.scroll.get_h_scroll_bar().max_value<=panel.scroll.size.x,"Practice panel has no horizontal overflow")
		panel.scroll.scroll_vertical=int(panel.cycle_summary.position.y);await picture("practice-%d-cycle" % size.x)
		panel.raw_toggle.grab_focus();await picture("practice-%d-trials" % size.x)
		var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;root.push_input(event);await process_frame
		event=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event);await process_frame
		check(panel.raw.visible,"Keyboard reveals exact cycle record")
		panel.raw.hide();panel.raw_toggle.text="Show exact practice records"
	var stopped:=data.duplicate(true);stopped.control.duty.enabled=false
	panel.apply_fixture(stopped,[data.cycles[0].baseline,{"digest":"fixture-practice-upgrade","manifest":{"profile":"joint-readiness-v1","inference":true}}])
	panel.baseline.select(1);panel.refresh_controls();panel.scroll.scroll_vertical=0
	check(panel.rebase_button.visible and panel.rebase_button.disabled and panel.replacement_detail.text.contains("keeps duty stopped"),"Rebase fixture exposes exact replacement choice without enabling or mutating")
	await picture("practice-stopped-baseline")
	panel.scroll.grab_focus()
	var page:=InputEventKey.new();page.keycode=KEY_PAGEDOWN;page.pressed=true;root.push_input(page);await process_frame
	await picture("practice-stopped-baseline-action")
	check(panel.scroll.get_global_rect().intersects(panel.rebase_button.get_global_rect()),"Keyboard Page Down reaches stopped-baseline action")
	panel.apply_fixture(data)
	panel.received_at=Time.get_ticks_msec()-31000;panel.refresh_controls();panel.render_cycle()
	check(panel.notice.text.contains("preview fixture") and panel.cycle_summary.text.contains("LAST KNOWN"),"Stale cycle evidence is qualified")
	panel.scroll.scroll_vertical=int(panel.cycle_summary.position.y);await picture("practice-stale")
	var initial:=data.duplicate(true);initial.control=null;initial.cycles=[]
	panel.apply_fixture(initial,[data.cycles[0].baseline]);panel.scroll.scroll_vertical=0
	check(panel.chosen_baseline()=="fixture-practice-incumbent" and panel.make_duty(true).generation==0,"Initial baseline comes from registered build and starts generation0")
	await picture("practice-initial")
	var retained:Dictionary=panel.snapshot.duplicate(true)
	panel.received(0,404,[],PackedByteArray(),panel.epoch)
	check(panel.unsupported and panel.snapshot==retained and not panel.online,"Optional V6 unavailable preserves evidence as unknown")
	panel.poll();check(not panel.pending,"Unavailable optional V6 does not repeatedly poll")
	panel.apply_fixture(initial,[data.cycles[0].baseline])
	panel.received(0,200,[],JSON.stringify({"schema_version":6,"enabled":true,"control":{"practice_incumbent":null},"cycles":[]}).to_utf8_buffer(),panel.epoch)
	check(not panel.online and panel.snapshot==initial,"Malformed control cannot replace retained evidence or enable a command")
	panel.apply_fixture(initial,[data.cycles[0].baseline])
	var command_script=load("res://learning_commands.gd")
	var request:Dictionary=panel.make_duty(true)
	var control:={"duty":request.duplicate(true)}
	check(command_script.duty_matches(control,request),"Exact normalized duty can acknowledge mutation")
	control.duty.generation=1
	check(not command_script.duty_matches(control,request),"Another generation cannot acknowledge original duty")
	if not api.is_empty():
		panel.configure(api,"");panel.poll(true);await wait_poll(panel)
		var deadline:=Time.get_ticks_msec()+9000
		while panel.chosen_baseline().is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		panel.enable_duty();await settled(panel.duty_commands)
		check(panel.duty_commands.uncertain,"Lost enable and stale control stay unknown")
		check(not hud.operations.configure("http://127.0.0.1:1",""),"Unresolved practice duty blocks endpoint change")
		panel.reconcile();await settled(panel.duty_commands)
		check(not panel.duty_commands.uncertain and panel.control().duty.enabled,"Exact duty reconciles enable without another POST")
		await wait_poll(panel)
		check(panel.snapshot.enabled==false and not panel.stop_button.disabled,"Stop remains usable when installation admission is disabled")
		panel.stop_future();await settled(panel.stop_commands)
		check(panel.stop_commands.uncertain,"Newer conflicting generation cannot acknowledge stop")
		panel.reconcile();await settled(panel.stop_commands)
		check(not panel.stop_commands.uncertain and not panel.control().duty.enabled,"Exact stopped generation reconciles future dispatch stop")
		await wait_poll(panel)
		check(panel.rebase_button.disabled,"Stopped duty with active cycle cannot change baseline")
		panel.selected="practice-http-cycle";panel.render();panel.cancel_cycle();await settled(panel.cancel_commands)
		check(panel.cancel_commands.uncertain,"Same-ID evaluating cycle cannot acknowledge cancellation")
		panel.reconcile();await settled(panel.cancel_commands)
		check(not panel.cancel_commands.uncertain and panel.current().state=="cancelled","Retained cancelled cycle resolves cancellation")
		await wait_poll(panel)
		deadline=Time.get_ticks_msec()+9000
		while panel.baseline.item_count<2 and Time.get_ticks_msec()<deadline:await process_frame
		panel.baseline.select(1);panel.refresh_controls()
		check(not panel.rebase_button.disabled,"Terminal cycles permit explicit stopped-baseline change")
		panel.rebase_duty();await settled(panel.duty_commands)
		check(panel.duty_commands.uncertain,"Old baseline cannot acknowledge a lost rebase")
		panel.reconcile();await settled(panel.duty_commands)
		check(not panel.duty_commands.uncertain and panel.chosen_baseline()=="fixture-practice-upgrade" and not panel.control().duty.enabled,"Exact rebase changes incumbent but does not enable duty")
		check(panel.feedback.text.contains("duty remains stopped"),"Rebase receipt explains separate enable")
		var old_epoch:int=panel.epoch;panel.configure(api,"fixture")
		panel.received(0,200,[],JSON.stringify(data).to_utf8_buffer(),old_epoch)
		check(panel.snapshot.is_empty(),"Old endpoint callback is fenced")
	hud.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("LEARNING_PANEL_PASSED: local-practice scope, exact duty CAS/current incumbent, eight paired trial records, budget visibility, fixture/stale, compact keyboard, command reconciliation")
	quit(0 if failures.is_empty() else 1)
