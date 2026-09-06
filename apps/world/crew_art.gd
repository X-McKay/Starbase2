extends RefCounted
## Portraits retain the approved static art while walk candidates are reviewed.
const Catalog = preload("res://characters/catalog.gd")
static func pose(appearance: String, direction: int = 0) -> AtlasTexture:
	var definition=Catalog.get_definition(appearance)
	return definition.frames().get_frame_texture("idle_"+definition.DIRECTIONS[direction],0)
