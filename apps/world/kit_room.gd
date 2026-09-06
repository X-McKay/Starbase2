@tool
extends Node3D
## Repeated floor is composition; walls and props are authored scene instances.
const Module = preload("res://scenes/kit/module.tscn")
const Art = preload("res://art.gd")
const Kit = preload("res://kit_art.gd")
func _ready() -> void:
	for x in range(-2,3):
		for z in range(-2,3):
			var tile := Module.instantiate()
			tile.kind="floor"
			tile.position=Vector3(x*2,0,z*2)
			add_child(tile)
	for x in [-3.8,3.8]:
		Art.box(self,Vector3(x,2.85,-4.65),Vector3(1.8,0.08,0.14),"93e6e4","",true)
		Art.box(self,Vector3(x,0.2,3),Vector3(1.2,0.4,1.1),"526c75")
		Kit.panel(self,"hull",Vector3(x,0.41,3),Vector2(1.16,1.06),Vector3(-90,0,0))
		Kit.panel(self,"wall",Vector3(x,0.21,3.56),Vector2(1.16,0.34))
	Art.box(self,Vector3(0,0.6,0.2),Vector3(2.4,1.2,1.1),"3d5665")
	Art.box(self,Vector3(0,1.24,0.2),Vector3(2.6,0.10,1.3),"93b7b9")
	Kit.panel(self,"console",Vector3(0,1.30,0.2),Vector2(2.48,1.18),Vector3(-90,0,0))
	Kit.panel(self,"hull",Vector3(0,0.6,0.76),Vector2(2.3,1.12))
