extends RefCounted
## Authored, cosmetic home locations. Marker transforms remain owned by each room.
static func collect(world:Node3D) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for marker in world.find_children("*","Marker3D",true,false):
		if not marker.get_meta("activity_anchor",false): continue
		var parent:Node3D=marker.get_parent()
		result.append({"id":str(marker.name),"position":marker.global_position,
			"pose":str(marker.get_meta("pose","")),"zone":str(marker.get_meta("zone","")),
			"facing":parent.to_global(marker.get_meta("facing",marker.position+Vector3.FORWARD))})
	return result
