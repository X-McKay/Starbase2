extends RefCounted
## Orthographic gameplay needs a bounded depth, not the default 4 km frustum.
## A single map avoids perspective cascade boundaries at uniform pixel scale.
static func configure_sun(sun:DirectionalLight3D) -> void:
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL

static func depth_for_view(view_size:float,offset:Vector3) -> float:
	# Continuous with camera zoom; 80 m depth margin retains the lower coastline.
	# Wide Map views expand naturally rather than clipping at the gameplay depth.
	return maxf(160.0,offset.length()+view_size*.9+80.0)
