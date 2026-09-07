extends RefCounted
## One placement scene owns render placement AND navigation footprints.
const LAYOUT = preload("res://structures/colony.tscn")
static var _placements: Array[Dictionary] = []
static func placements() -> Array[Dictionary]:
	if _placements.is_empty():
		var layout := LAYOUT.instantiate()
		for node in layout.get_children():
			_placements.append({"name":str(node.name),"position":node.position,"definition":node.definition,"interaction_kind":node.interaction_kind})
		layout.free()
	return _placements
static func structure_bounds() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for placement in placements():
		for rect in placement.definition.collision_boxes:
			result.append(Rect2(rect.position+Vector2(placement.position.x,placement.position.z),rect.size))
	return result
static func station_paths() -> Dictionary:
	var result := {}
	for placement in placements():
		if not placement.interaction_kind.is_empty(): result[placement.interaction_kind]="Structures/"+placement.name
	return result

static func navigation_bounds() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for placement in placements():
		for rect in placement.definition.navigation_bounds():
			result.append(Rect2(rect.position+Vector2(placement.position.x,placement.position.z),rect.size))
	return result
