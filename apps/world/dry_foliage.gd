extends Node3D
## Decorative closed mesh tufts. Four shared batches; never a collider or work state.
var placements:Array[Dictionary]=[]
var pending:=false
var batches:Array[MultiMeshInstance3D]=[]
var meshes:Array[Mesh]=[]
var imported:Array[Transform3D]=[]
func add_tuft(point:Vector3,size:float,heading:float) -> void:
	placements.append({"position":point,"size":size,"heading":heading,"variant":mini(3,int(heading/TAU*4))})
	if not pending:pending=true;rebuild.call_deferred()
func load_meshes() -> void:
	if not meshes.is_empty():return
	for variant in 4:
		var scene=load("res://assets/environment/aster-vegetation/dry-tuft-%d.glb" % variant).instantiate()
		var mesh:MeshInstance3D=scene if scene is MeshInstance3D else scene.find_children("*","MeshInstance3D",true,false)[0]
		var transform:=Transform3D.IDENTITY
		var item:Node=mesh
		while item!=null:
			if item is Node3D:transform=item.transform*transform
			item=item.get_parent()
		var shared:Mesh=mesh.mesh.duplicate()
		for surface in shared.get_surface_count():
			var material:StandardMaterial3D=mesh.get_active_material(surface).duplicate()
			# The shared mesh keeps COLOR_0, but importer instance flags are not retained by MultiMesh.
			material.vertex_color_use_as_albedo=true
			material.cull_mode=BaseMaterial3D.CULL_BACK
			shared.surface_set_material(surface,material)
		meshes.append(shared);imported.append(transform);scene.free()
func rebuild() -> void:
	pending=false;load_meshes()
	for node in batches:remove_child(node);node.queue_free()
	batches.clear()
	for variant in 4:
		var selected:=placements.filter(func(record):return record.variant==variant)
		if selected.is_empty():continue
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=meshes[variant];multi.instance_count=selected.size()
		for index in selected.size():
			var record:Dictionary=selected[index]
			var basis:=Basis(Vector3.UP,record.heading).scaled(Vector3.ONE*float(record.size))
			multi.set_instance_transform(index,Transform3D(basis,Vector3(record.position.x,-0.045,record.position.z))*imported[variant])
		var instance:=MultiMeshInstance3D.new();instance.name="ClosedDryTufts%d" % variant;instance.multimesh=multi
		add_child(instance);batches.append(instance)
