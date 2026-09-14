extends Node3D
## Decorative ventilation only. No audio, operational state or collision.
const MODEL := preload("res://assets/environment/colony-vent/colony-vent.glb")
const ROOM_KINDS := ["review", "gym", "habitat", "greenhouse"]
var reduced_motion := false
var rotor: Node3D
var phase := 0.0

static func attach(station: Node3D) -> Node3D:
	if station.definition == null or str(station.definition.id) not in ROOM_KINDS or station.room == null: return null
	if station.room.has_node("ColonyVent"): return station.room.get_node("ColonyVent")
	var vent := load("res://colony_vent.gd").new() as Node3D
	vent.name = "ColonyVent"
	var bounds: Rect2 = station.definition.interior_bounds
	vent.position = Vector3(bounds.end.x - 1.25, 3.35, bounds.position.y + 0.22)
	station.room.add_child(vent)
	return vent

func _ready() -> void:
	add_child(MODEL.instantiate())
	rotor = find_child("Rotor", true, false) as Node3D
	assert(rotor != null, "Authored vent must retain its centered Rotor node")

func _process(delta: float) -> void:
	if reduced_motion or not is_visible_in_tree() or rotor == null: return
	phase = fmod(phase + delta * 0.32, TAU)
	rotor.rotation.z = phase
