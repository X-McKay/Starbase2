extends RefCounted
## Only named roof-reveal batches use this visual clip. Meshes include both rear
## arches and middle spans, so whole-node hiding would erase the room silhouette.
static func configure(material: ShaderMaterial, mesh: MeshInstance3D, station: Node3D) -> void:
	if not (str(mesh.name).begins_with("InteriorRevealBridge") or str(mesh.name).begins_with("InteriorRevealVault")): return
	material.set_shader_parameter("sightline_clip", true)
	material.set_shader_parameter("sightline_to_station", station.global_transform.affine_inverse()*mesh.global_transform)
	material.set_shader_parameter("sightline_ceiling", 3.2)
	material.set_shader_parameter("sightline_rear", station.definition.interior_bounds.position.y+1.0)
