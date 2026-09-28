extends SceneTree
const Quality=preload("res://shadow_quality.gd")
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	for offset in [Vector3(10,36,46),Vector3(5,14,18),Vector3(8,18,23)]:
		camera.position=offset;camera.look_at(Vector3.ZERO)
		for size in [3.52,8.8,16.25,23.61,142.0,284.0]:
			camera.size=size;camera.far=Quality.depth_for_view(size,offset)
			for y in [-45.0,0.0]:
				for point in [Vector2.ZERO,Vector2(1280,0),Vector2(0,800),Vector2(1280,800)]:
					var ground=Plane(Vector3.UP,y).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
					if ground!=null:
						var depth:float=-camera.to_local(ground).z
						check(depth<camera.far,"Visible ground/coast remains before far plane at "+str(size))
		var previous:=Quality.depth_for_view(.01,offset)
		for step in range(1,28500):
			var next:=Quality.depth_for_view(float(step)*.01,offset)
			check(next>=previous and next-previous<=.0101,"Continuous zoom has no depth boundary jump")
			previous=next
	camera.queue_free();await process_frame
	var world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	var sun:DirectionalLight3D
	for child in world.get_children():
		if child is DirectionalLight3D:sun=child;break
	check(sun!=null and sun.shadow_enabled and sun.directional_shadow_mode==DirectionalLight3D.SHADOW_ORTHOGONAL,"Real world uses one enabled directional shadow map")
	world.hud.reduced=true;world.colony_overview=true;world.zoom_factor=2.0;world._process(1)
	check(absf(world.camera.size-284)<.01 and world.camera.far>350 and world.camera.far<500,"Largest Map view expands finite shadow depth")
	check(world.commands.payload.is_empty(),"Shadow changes never dispatch work")
	world.queue_free();await process_frame
	if failures.is_empty():print("SHADOW_QUALITY_PASSED")
	quit(0 if failures.is_empty() else 1)
