extends SceneTree
## Isolated art preview/load fixture. Never loads the operations world or API.
const Station=preload("res://station.gd")
const Art=preload("res://art.gd")
var capture := ""
var count := 1
var frame := 0
var intervals: Array[float]=[]
var last_usec := 0
var start_usec := Time.get_ticks_usec()
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://buildings/definitions/repair.tres"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--definition="): path=arg.trim_prefix("--definition=")
		if arg.begins_with("--count="): count=clampi(int(arg.trim_prefix("--count=")),1,100)
		if arg.begins_with("--capture="): capture=arg.trim_prefix("--capture=")
	var definition=load(path)
	if definition==null or not definition.problems().is_empty():
		push_error("Invalid gallery definition: "+path)
		quit(1)
		return
	root.size=Vector2i(1280,800)
	var world=Node3D.new()
	root.add_child(world)
	var columns=ceili(sqrt(count))
	var rows=ceili(float(count)/columns)
	for i in count:
		var station=Station.new()
		station.definition=definition
		station.position=Vector3((i%columns-(columns-1)*0.5)*14,0,(floori(float(i)/columns)-(rows-1)*0.5)*12)
		world.add_child(station)
	Art.box(world,Vector3(0,-0.2,0),Vector3(columns*15,0.3,rows*13),"664a43")
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=18 if count==1 else maxf(columns*15,rows*14)
	world.add_child(camera)
	camera.position=Vector3(10,36,46)+Vector3(0,1,0)
	camera.look_at(Vector3(0,1,0))
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-52,-32,-8)
	light.light_energy=0.8
	world.add_child(light)
	var environment=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("101c29")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("97b3d8")
	environment.environment.ambient_light_energy=0.5
	world.add_child(environment)
	var title=Label.new()
	title.position=Vector2(24,20)
	title.text="BUILDING ART PREVIEW / "+definition.title+"\n%d instances · shared artwork · no operational activity" % count
	title.add_theme_font_size_override("font_size",20)
	root.add_child(title)
	process_frame.connect(tick)
func tick() -> void:
	frame+=1
	var now=Time.get_ticks_usec()
	if frame>30 and last_usec>0: intervals.append((now-last_usec)/1000.0)
	last_usec=now
	if frame==120 and not capture.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
		intervals.sort()
		var report={"instances":count,"unique_exterior_textures":1,"fixture":"shared-art rendering, not 50 unique artworks","frames":intervals.size(),"median_ms":intervals[intervals.size()/2],"p95_ms":intervals[int(intervals.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"elapsed_ms":(now-start_usec)/1000.0,"engine":Engine.get_version_info(),"measurement":"capped native process intervals, not GPU timings"}
		FileAccess.open(capture+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		quit()
