extends SceneTree
## Actual imported leaves preserve their authored surface and render both faces.
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var commons=load("res://living_commons.gd").new()
	root.add_child(commons)
	await process_frame
	var count:=0
	for mesh in commons.find_children("*","MeshInstance3D",true,false):
		if not "Leaf" in str(mesh.name): continue
		for surface in mesh.mesh.get_surface_count():
			var source=mesh.mesh.surface_get_material(surface)
			var actual=mesh.get_surface_override_material(surface)
			check(source is StandardMaterial3D and actual is ShaderMaterial,"Imported leaf retains inspectable authored and runtime materials")
			if not source is StandardMaterial3D or not actual is ShaderMaterial: continue
			check(actual.shader.code.contains("render_mode cull_disabled"),"Actual leaf shader renders front and back faces")
			check(actual.get_shader_parameter("color")==source.albedo_color,"Leaf shader preserves authored color")
			check(is_equal_approx(actual.get_shader_parameter("roughness"),source.roughness),"Leaf shader preserves authored roughness")
			check(is_equal_approx(actual.get_shader_parameter("metallic"),source.metallic),"Leaf shader preserves authored metallic response")
			if source.albedo_texture!=null:
				check(actual.get_shader_parameter("albedo_map")==source.albedo_texture and actual.get_shader_parameter("use_albedo"),"Textured leaf retains source albedo")
			count+=1
	check(count>0 and count==commons.foliage_materials.size(),"Every real leaf surface participates in comfort settings")
	commons.set_reduced_motion(true)
	for material in commons.foliage_materials:
		check(material.get_shader_parameter("motion_enabled")==false,"Reduced motion disables every leaf breeze")
	commons.set_reduced_motion(false)
	for material in commons.foliage_materials:
		check(material.get_shader_parameter("motion_enabled")==true,"Normal motion restores every leaf breeze")
	commons.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("LIVING_FOLIAGE_PASSED: ",count," actual surfaces; two-sided rendering contract, authored PBR and reduced motion")
	quit(0 if failures.is_empty() else 1)
