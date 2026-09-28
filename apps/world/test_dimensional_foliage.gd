extends SceneTree
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:run.call_deferred()
func closed_surface(mesh:Mesh,surface:int) -> bool:
	var arrays:=mesh.surface_get_arrays(surface)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():for index in vertices.size():indices.append(index)
	var ids:Dictionary={};var remap:PackedInt32Array=[]
	for vertex in vertices:
		var point:=vertex.snapped(Vector3.ONE*0.000001)
		if not ids.has(point):ids[point]=ids.size()
		remap.append(ids[point])
	var edges:Dictionary={}
	for index in range(0,indices.size(),3):
		for pair in [[0,1],[1,2],[2,0]]:
			var a:int=remap[indices[index+pair[0]]];var b:int=remap[indices[index+pair[1]]]
			var key:=Vector2i(mini(a,b),maxi(a,b));edges[key]=int(edges.get(key,0))+1
	for uses in edges.values():
		if uses!=2:return false
	return not edges.is_empty()
func run() -> void:
	var foliage=load("res://dry_foliage.gd").new();root.add_child(foliage);foliage.load_meshes()
	check(foliage.meshes.size()==4,"Four shared dry-tuft mesh variants")
	for index in foliage.meshes.size():
		var mesh:Mesh=foliage.meshes[index];var bounds:AABB=foliage.imported[index]*mesh.get_aabb()
		check(mesh.get_surface_count()==1,"Each dry variant remains one opaque draw surface")
		check(closed_surface(mesh,0),"Dry blade surfaces are closed volumes, not alpha cards or open triangle fans")
		check(bounds.size.y>0.35 and bounds.size.y<1 and maxf(bounds.size.x,bounds.size.z)<1,"Imported tufts remain correctly oriented and bounded")
		var material:StandardMaterial3D=mesh.surface_get_material(0)
		check(material!=null and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and material.metallic==0,"Dry vegetation remains opaque nonmetal PBR")
		check(material.vertex_color_use_as_albedo,"Authored base-to-tip color variation survives import")
		var arrays:=mesh.surface_get_arrays(0);var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		check(arrays[Mesh.ARRAY_COLOR].size()>0,"Shared mesh retains authored vertex color data")
		check(indices.size()/3<=1000,"Dry mesh triangle budget stays bounded")
	var terrain=load("res://landscape.gd").new();root.add_child(terrain)
	await process_frame;await process_frame
	var actual=terrain.get_node("DryFoliage")
	check(actual.placements.size()==110,"Existing deterministic scatter count retained")
	# The headless dummy rendering server returns identity for all MultiMesh instances.
	# Exercise GPU transform readback in the native pass of this same test.
	if DisplayServer.get_name()!="headless":
		for batch in actual.batches:
			for index in batch.multimesh.instance_count:
				check(is_equal_approx(batch.multimesh.get_instance_transform(index).origin.y,-0.045),"Tuft root caps sit 1 cm beneath the soil surface, never float above it")
	check(actual.batches.size()==4,"All active tufts use four shared batches instead of per-tuft draw surfaces")
	check(actual.find_children("*","CollisionObject3D",true,false).is_empty(),"Groundcover remains nonblocking scenery")
	var probe:=RandomNumberGenerator.new();probe.seed=9921;terrain.rng.seed=9921
	for sample in 5:probe.randf_range(0,TAU);probe.randf_range(0.45,0.8)
	terrain.grass(Vector3(80,0,80),1)
	check(probe.state==terrain.rng.state,"Grass preserves prior RNG consumption and later scatter layout")
	var commons=load("res://living_commons.gd").new();root.add_child(commons);await process_frame
	var leaf_surfaces:=0
	for node in commons.find_children("*","MeshInstance3D",true,false):
		if not "Leaf" in str(node.name):continue
		for surface in node.mesh.get_surface_count():
			leaf_surfaces+=1;check(closed_surface(node.mesh,surface),"Commons foliage has a closed underside at every leaf surface")
	check(leaf_surfaces==3,"All three Commons leaf material batches were checked")
	var botanical=load("res://assets/structures/botanical/greenhouse-interior.glb").instantiate();root.add_child(botanical)
	var botanical_surfaces:=0
	for node in botanical.find_children("*","MeshInstance3D",true,false):
		if not ("Leaf" in str(node.name) or "Moss" in str(node.name)):continue
		for surface in node.mesh.get_surface_count():
			botanical_surfaces+=1;check(closed_surface(node.mesh,surface),"Botanical leaf surfaces remain closed after batching/export")
	check(botanical_surfaces>=2,"Botanical leaf and moss material batches checked")
	for node in [foliage,terrain,commons,botanical]:node.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("DIMENSIONAL_FOLIAGE_PASSED: closed imported geometry, opaque PBR, budgets, four batches, preserved scatter and nonblocking groundcover")
	quit(0 if failures.is_empty() else 1)
