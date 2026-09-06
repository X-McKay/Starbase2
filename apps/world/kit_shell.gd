@tool
extends Node3D
const Art = preload("res://art.gd")
const Kit = preload("res://kit_art.gd")
func _ready() -> void:
	Art.box(self,Vector3(0,-0.15,0),Vector3(6.6,0.3,6.6),"405565")
	Art.box(self,Vector3(0,1.3,3.0),Vector3(1.8,2.6,0.2),"1d3040")
	Kit.panel(self,"hull",Vector3(0,1.3,3.12),Vector2(1.55,2.35))
	Art.box(self,Vector3(0,1.3,3.15),Vector3(0.045,2.4,0.025),"263747")
	for x in [-0.9,0.9]: Art.box(self,Vector3(x,1.3,3.16),Vector3(0.06,2.6,0.06),"80d7db","",true)
	Art.box(self,Vector3(0,0.05,3.55),Vector3(2.5,0.10,0.9),"526878")
	Art.box(self,Vector3(0,2.85,3.12),Vector3(2.3,0.25,0.15),"26394b")
	var sign := Art.sign(self,"ASTER / FIELD LAB",Vector3(0,2.86,3.25),"d6e6db",14)
	sign.billboard=BaseMaterial3D.BILLBOARD_DISABLED
