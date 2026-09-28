extends "res://capture_dimensional_foliage.gd"
## One controlled thin-caster normal-bias comparison on the corrected root mesh.
func shot(name:String,point:Vector3,distance:float,angle:Vector3) -> void:
	var sun:DirectionalLight3D
	for child in world.get_children():
		if child is DirectionalLight3D:sun=child;break
	for bias in [2.0,.5]:
		sun.shadow_normal_bias=bias
		await super.shot(("before-" if bias==2.0 else "after-")+name,point,distance,angle)
