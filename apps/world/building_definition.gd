@tool
extends Resource
## Art and spatial metadata only. No agent, backend or permission ownership.
@export var id: StringName
@export var title := ""
@export_file("*.png") var exterior_image := ""
@export_file("*.tscn") var exterior_scene := ""
@export var image_pixel_size := 0.007
## Pixel in source artwork that coincides with the world threshold.
@export var image_door_pixel := Vector2.ZERO
@export var threshold := Vector3(0,0,1.75)
@export var approach := Vector3(0,0,2.4)
@export var return_point := Vector3(0,0,3.1)
@export var collision_boxes: Array[Rect2] = []
@export var collision_height := 3.0
## Foundation margins: left, back, right, front. Independent of collision.
@export var pad_margin := Vector4(1.5,1.5,1.5,1.5)
@export_file("*.tscn") var yard_scene := ""
@export_file("*.tscn") var interior_scene := ""
@export var interior_bounds := Rect2(-4.6,-4.6,9.2,9.2)

func problems() -> PackedStringArray:
	var errors := PackedStringArray()
	if id==&"" or title.is_empty(): errors.append("ID and title are required")
	if exterior_image.is_empty()==exterior_scene.is_empty(): errors.append("Choose exactly one exterior image or scene")
	for path in [exterior_image,exterior_scene,yard_scene,interior_scene]:
		if not path.is_empty() and not ResourceLoader.exists(path): errors.append("Missing asset: "+path)
	if image_pixel_size<=0: errors.append("Image pixel size must be positive")
	if minf(minf(pad_margin.x,pad_margin.y),minf(pad_margin.z,pad_margin.w))<0: errors.append("Pad margins must be nonnegative")
	if collision_height<=0 or collision_boxes.is_empty(): errors.append("Collision footprint and height are required")
	for rect in collision_boxes:
		if rect.size.x<=0 or rect.size.y<=0: errors.append("Collision rectangle must have positive area")
		for point in [approach,return_point]:
			if rect.grow(0.4).has_point(Vector2(point.x,point.z)): errors.append("Entrance approach/return intersects collision")
	if not interior_scene.is_empty() and (interior_bounds.size.x<=0 or interior_bounds.size.y<=0): errors.append("Interior bounds must have positive area")
	return errors
