extends RefCounted
## Sparse deformed-skin support probes, selected from dense native gait samples.
## These follow the final blended skeleton; clip phase and bone origins are not contact.
var skeleton:Skeleton3D
var probes:Array=[]
var binds:Array=[]

func configure(visual:Node3D, indices:Dictionary) -> void:
	skeleton=visual.skeleton
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		if mesh.skin==null:continue
		var key:=str(visual.get_path_to(mesh))
		if not indices.has(key):continue
		var bind_offset:=binds.size()
		for i in mesh.skin.get_bind_count():
			var bone:int=mesh.skin.get_bind_bone(i)
			if bone<0:bone=skeleton.find_bone(mesh.skin.get_bind_name(i))
			binds.append([bone,mesh.skin.get_bind_pose(i)])
		for surface_key in indices[key]:
			var a:Array=mesh.mesh.surface_get_arrays(int(surface_key))
			var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=a[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=a[Mesh.ARRAY_WEIGHTS]
			var influences:int=bones.size()/vertices.size()
			for index in indices[key][surface_key]:
				var terms:Array=[]
				for j in influences:
					var w:float=weights[int(index)*influences+j]
					if w>0:terms.append([bind_offset+bones[int(index)*influences+j],w])
				probes.append([vertices[int(index)],terms])

func minimum_y(visual:Node3D) -> float:
	if probes.is_empty():return 0.0
	skeleton.force_update_all_bone_transforms()
	var transforms:Array[Transform3D]=[]
	var to_visual:Transform3D=visual.global_transform.affine_inverse()*skeleton.global_transform
	for bind in binds:transforms.append(to_visual*skeleton.get_bone_global_pose(bind[0])*bind[1])
	var minimum:=INF
	for probe in probes:
		var y:=0.0
		for term in probe[1]:y+=(transforms[term[0]]*probe[0]).y*term[1]
		minimum=minf(minimum,y)
	return minimum

func required_lift(visual:Node3D, surface:Callable) -> float:
	if probes.is_empty():return 0.0
	skeleton.force_update_all_bone_transforms()
	var transforms:Array[Transform3D]=[]
	for bind in binds:transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bind[0])*bind[1])
	var lift:=0.0
	for probe in probes:
		var point:=Vector3.ZERO
		for term in probe[1]:point+=(transforms[term[0]]*probe[0])*term[1]
		# Accepted walkable surfaces are at most 0.35 m above the navigation plane.
		if point.y>=0.352+lift:continue
		lift=maxf(lift,float(surface.call(point))+0.002-point.y)
	return lift
