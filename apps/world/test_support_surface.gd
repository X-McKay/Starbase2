extends SceneTree
const Support=preload("res://support_surface.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value: failures.append(message)

func floor_mesh(name:String,points:PackedVector3Array,transform:Transform3D=Transform3D.IDENTITY)->MeshInstance3D:
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=points
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance:=MeshInstance3D.new(); instance.name=name; instance.mesh=mesh; instance.transform=transform; return instance

func _initialize()->void: run.call_deferred()
func run()->void:
	var root_3d:=Node3D.new(); root.add_child(root_3d)
	var floor:=floor_mesh("Floor_main",PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(-1,0.2,1)]),Transform3D(Basis.IDENTITY,Vector3(4,0,2)))
	root_3d.add_child(floor)
	var raised:=floor_mesh("Floor_prop",PackedVector3Array([Vector3(-1,0.6,-1),Vector3(1,0.6,-1),Vector3(-1,0.6,1)]),Transform3D(Basis.IDENTITY,Vector3(4,0,2)))
	root_3d.add_child(raised)
	var sampler:=Support.new(); sampler.configure(root_3d,[Rect2(-3,-3,2,2)],[{"position":Vector3(0,0.14,0),"size":Vector3(1,0.1,1),"height":0.14},{"position":Vector3(4,0.14,2),"size":Vector3(1,0.1,1),"height":0.14}])
	check(absf(sampler.height_at(Vector3(4,0.2,1.25))-0.025)<0.001,"Floor triangle height is barycentrically interpolated")
	check(absf(sampler.height_at(Vector3(4,0.2,2))-0.14)<0.001,"Raised sill wins over its underlying floor triangle")
	check(absf(sampler.height_at(Vector3(-2,0,-2))-Support.PAVING_HEIGHT)<0.001,"Paving fallback reports rendered height")
	check(absf(sampler.height_at(Vector3(0,0,0))-0.14)<0.001,"Threshold sill takes precedence at the doorway")
	check(absf(sampler.height_at(Vector3(20,0,20))-Support.TERRAIN_HEIGHT)<0.001,"Terrain fallback remains zero outside authored surfaces")
	root_3d.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("SUPPORT_SURFACE_PASSED: floor triangle interpolation, raised-floor filtering, paving, sill and terrain fallbacks")
	quit(0 if failures.is_empty() else 1)
