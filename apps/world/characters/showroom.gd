extends Node3D
## Isolated cosmetic review. No API, workflow, agent or credential access.
const Actor=preload("res://actor.gd")
const Art=preload("res://art.gd")
const Catalog=preload("res://characters/catalog.gd")
const Portrait=preload("res://crew_art.gd")
var actors: Array=[]
var camera:=Camera3D.new()
var environment:=Environment.new()
var direction:=Vector3.FORWARD
var walking:=false
var speed:=1.28
var reduced:=false
var alternate:=false
var dark:=true
var status:=Label.new()
var stage:=Label.new()
var frame:=0
var movie:=false
var capture:=""
var production:=false
var wall:=StaticBody3D.new()
var wall_visual: MeshInstance3D
var ground: MeshInstance3D
var foley:=preload("res://footfall.gd").new()
var times: Array[float]=[]
var last_usec:=0

func _ready() -> void:
	production="--production" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg=="--record": movie=true
		if arg.begins_with("--capture="): capture=arg.trim_prefix("--capture=")
	if "--compact" in OS.get_cmdline_user_args():
		get_window().size=Vector2i(960,720); get_window().content_scale_size=Vector2i(960,720)
	ground=Art.box(self,Vector3(0,-.10,0),Vector3(80,.1,80),"203443")
	for i in range(-40,41):
		Art.box(self,Vector3(i,-.038,0),Vector3(.012,.004,80),"496472")
		Art.box(self,Vector3(0,-.038,i),Vector3(80,.004,.012),"496472")
	for pair in [["operator","CAPTAIN",-2.2],["surveyor","EVA EXPLORER",2.2]]:
		var actor=Actor.new(); actor.appearance=pair[0]; actor.display_name=pair[1]
		actor.character_definition=Catalog.get_definition(pair[0],not production)
		actor.position=Vector3(pair[2],0,0); add_child(actor); actors.append(actor)
	foley.actor=actors[0]; foley.interior=true; add_child(foley); foley.enabled=movie
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=11
	add_child(camera); camera.current=true
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-52,-32,0); add_child(light)
	environment.background_mode=Environment.BG_COLOR; environment.background_color=Color("0e1927")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color.WHITE; environment.ambient_light_energy=.8
	var env:=WorldEnvironment.new(); env.environment=environment; add_child(env)
	var collider:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(30,2,.2)
	collider.shape=box; wall.add_child(collider); wall.position.z=30; add_child(wall)
	wall_visual=Art.box(wall,Vector3(0,.1,0),Vector3(30,.2,.2),"e4b455")
	var canvas:=CanvasLayer.new(); add_child(canvas)
	var panel:=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	canvas.add_child(panel)
	var style:=StyleBoxFlat.new(); style.bg_color=Color("101e2eef"); style.content_margin_left=16; style.content_margin_right=16; style.content_margin_top=12; style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new(); panel.add_child(column)
	var title:=Label.new(); title.text="  ASTER / CHARACTER LAB"; title.add_theme_font_size_override("font_size",26); column.add_child(title)
	var note:=Label.new(); note.text="  Illustrated crew · four-direction captain walk · EVA uses approved stills" if production else "  Technical prototype · visual direction rejected · decorative, no agent activity"; column.add_child(note)
	var buttons:=HFlowContainer.new(); column.add_child(buttons)
	for item in [["Space  Walk / idle",func(): walking=not walking],
		["1  Front",func(): direction=Vector3.BACK], ["2  Back",func(): direction=Vector3.FORWARD],
		["3  Left",func(): direction=Vector3.LEFT], ["4  Right",func(): direction=Vector3.RIGHT],
		["S  Speed",func(): speed=2.56 if speed<2 else 1.28],
		["C  Camera",func(): alternate=not alternate], ["L  Backdrop",func(): toggle_light()],
		["R  Reduced motion",func(): reduced=not reduced], ["W  Wall test",func(): wall_test()],
		["A  Sound",func(): foley.enabled=not foley.enabled], ["Home  Reset",func(): reset()]]:
		var button:=Button.new(); button.text=item[0]; button.custom_minimum_size.y=34
		button.pressed.connect(item[1]); buttons.add_child(button)
	stage.text="  Captain: four authored walking directions · EVA: approved stills · sound off by default" if production else "  256 × 320 RGBA · fixed foot anchor · 1.28 m stride"; column.add_child(stage)
	var footer:=PanelContainer.new(); footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top=-58; canvas.add_child(footer); footer.add_child(status); footer.add_theme_stylebox_override("panel",style)
	# Approved portrait reference remains visible without replacing the pilot.
	var refs:=HBoxContainer.new(); refs.position=Vector2(16,210); refs.add_theme_constant_override("separation",20); canvas.add_child(refs)
	for id in ["operator","surveyor"]:
		var col:=VBoxContainer.new(); refs.add_child(col)
		var label:=Label.new(); label.text="Approved still"; col.add_child(label)
		var texture:=TextureRect.new(); texture.texture=Portrait.pose(id)
		texture.custom_minimum_size=Vector2(90,130); texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; col.add_child(texture)

func toggle_light() -> void:
	dark=not dark
	ground.material_override=Art.mat("203443" if dark else "bbc7cb")
	environment.background_color=Color("0e1927" if dark else "b6c6ce")

func reset() -> void:
	wall.position.z=30
	for i in range(actors.size()): actors[i].position=Vector3(-2.2+i*4.4,0,0)
	walking=false; reduced=false

func wall_test() -> void:
	reset(); wall.position.z=1.5; direction=Vector3.BACK; walking=true

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_SPACE: walking=not walking
		KEY_1: direction=Vector3.BACK
		KEY_2: direction=Vector3.FORWARD
		KEY_3: direction=Vector3.LEFT
		KEY_4: direction=Vector3.RIGHT
		KEY_S: speed=2.56 if speed<2 else 1.28
		KEY_C: alternate=not alternate
		KEY_L: toggle_light()
		KEY_R: reduced=not reduced
		KEY_W: wall_test()
		KEY_HOME: reset()
		KEY_A: foley.enabled=not foley.enabled

func _physics_process(_delta:float) -> void:
	foley.reduced=reduced
	for actor in actors:
		actor.reduced_motion=reduced
		actor.motion=direction*speed if walking else Vector3.ZERO

func _process(_delta:float) -> void:
	frame+=1
	var now:=Time.get_ticks_usec()
	if last_usec>0 and frame>30: times.append((now-last_usec)/1000.0)
	last_usec=now
	if movie:
		match frame:
			30: walking=true; direction=Vector3.BACK; stage.text="  FRONT / alternating contact and passing poses" if production else "  FRONT / one stride per second"
			120: direction=Vector3.RIGHT; speed=2.56; stage.text="  RIGHT / 2.56 m/s; phase retained through turn" if production else "  RIGHT / two strides per second; phase retained through turn"
			210: direction=Vector3.FORWARD; stage.text="  BACK / authored rear view" if production else "  BACK / asymmetric costume details retained"
			270: direction=Vector3.LEFT; speed=1.28; alternate=true; stage.text="  LEFT / authored side view; interior camera" if production else "  LEFT / interior camera angle"
			330: wall_test(); stage.text="  WALL / actual collision stops animation"
			390: reset(); walking=true; direction=Vector3.BACK; reduced=true; stage.text="  REDUCED MOTION / still poses during travel"
			420:
				walking=production; direction=Vector3.RIGHT; reduced=false; toggle_light()
				stage.text="  WALK / light background alpha review" if production else "  IDLE / light background alpha review"
	var center:Vector3=(actors[0].position+actors[1].position)*.5+Vector3(0,1.2,0)
	camera.position=center+(Vector3(5,14,18) if alternate else Vector3(10,36,46))
	camera.look_at(center)
	status.text=("  %s · %.2f m/s · phase %.2f · %s\n  Four-direction captain cycle; EVA remains on approved still artwork." if production else "  %s · %.2f m/s · phase %.2f · %s\n  Visual direction rejected. Approved illustrated crew remain the colony default.") % [actors[0].sprite.animation,speed,actors[0].gait.phase,"reduced motion" if reduced else "normal motion"]
	if capture!="" and ((movie and frame in [95,180,255,315,380,410,445]) or (not movie and frame==90)):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture+"-"+str(frame)+".png")
	if (movie and frame==450) or (not movie and frame==95 and capture!=""):
		times.sort()
		if capture!="":
			FileAccess.open(capture+".json",FileAccess.WRITE).store_string(JSON.stringify({"pilot":true,"distinct_atlases":5 if production else 2,"frames":times.size(),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"timing":"process intervals; capture/fixed-fps workload, not a performance benchmark","texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"viewport":str(get_viewport().get_visible_rect().size)},"  ")+"\n")
		get_tree().quit()
