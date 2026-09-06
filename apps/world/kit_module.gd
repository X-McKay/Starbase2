@tool
extends Node3D
## Place packed modules in the editor. Artwork never owns collision or interaction.
const Art = preload("res://art.gd")
const Kit = preload("res://kit_art.gd")
@export_enum("floor","wall","hull","console","roof") var kind := "wall":
	set(value):
		kind=value
		if is_inside_tree(): rebuild.call_deferred()
@export var solid := true:
	set(value):
		solid=value
		if is_inside_tree(): rebuild.call_deferred()
var built: Node3D
func _ready() -> void: rebuild()
func rebuild() -> void:
	if is_instance_valid(built):
		remove_child(built)
		built.queue_free()
	built=Node3D.new()
	add_child(built)
	if kind=="floor" or kind=="roof":
		Art.box(built,Vector3(0,-0.09,0),Vector3(2,0.18,2),"263747")
		Kit.panel(built,"floor",Vector3(0,0.011,0),Vector2(1.98,1.98),Vector3(-90,0,0))
		if solid: Art.collider(built,Vector3(0,-0.10,0),Vector3(2,0.2,2))
	elif kind=="console":
		Art.box(built,Vector3(0,0.5,0),Vector3(1.6,1,0.85),"2a4050")
		Kit.panel(built,"hull",Vector3(0,0.5,0.435),Vector2(1.52,0.92))
		Art.box(built,Vector3(0,1.38,-0.15),Vector3(1.85,1.85,0.20),"1c2c3c")
		Kit.panel(built,"console",Vector3(0,1.38,-0.035),Vector2(1.78,1.78))
		for x in [-0.64,0.64]: Art.box(built,Vector3(x,0.1,0.1),Vector3(0.16,0.2,0.75),"566775")
		if solid: Art.collider(built,Vector3(0,1,0),Vector3(1.85,2,0.85))
	else:
		Art.box(built,Vector3(0,1.5,-0.1),Vector3(2,3,0.28),"354958")
		Kit.panel(built,kind,Vector3(0,1.5,0.055),Vector2(1.91,2.88))
		for x in [-0.96,0.96]: Art.box(built,Vector3(x,1.5,0.065),Vector3(0.08,3.1,0.12),"789096")
		if solid: Art.collider(built,Vector3(0,1.5,0),Vector3(2,3,0.3))
