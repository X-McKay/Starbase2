extends SceneTree
const CrewArt = preload("res://crew_art.gd")
func _initialize() -> void:
	var failures: Array[String] = []
	for appearance in CrewArt.Catalog.definitions():
		for direction in range(4):
			var texture := CrewArt.pose(appearance,direction)
			var image := texture.atlas.get_image()
			var region := Rect2i(texture.region)
			if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(region):
				failures.append("Atlas region outside image")
			if image.detect_alpha() == Image.ALPHA_NONE: failures.append("Sprite source lacks alpha")
			var opaque := 0
			var clipped := 0
			var cell_start := roundi(image.get_width()*direction/4.0)
			var cell_end := roundi(image.get_width()*(direction+1)/4.0)
			for y in range(region.position.y,region.end.y):
				for x in range(cell_start,cell_end):
					if image.get_pixel(x,y).a>0.95:
						opaque+=1
						if x<region.position.x or x>=region.end.x: clipped+=1
			if opaque<1000: failures.append("Missing sprite: "+appearance)
			if clipped>0: failures.append("Cropped opaque pixels: %s facing %d (%d pixels)" % [appearance,direction,clipped])
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("16 accepted sprite poses verified: alpha, nonempty content, atlas bounds, no clipped opaque pixels")
	quit(0 if failures.is_empty() else 1)
