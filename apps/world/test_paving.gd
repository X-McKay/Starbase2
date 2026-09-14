extends SceneTree
const Paving=preload("res://colony_paving.gd")
const Navigation=preload("res://navigation.gd")
const Surface=preload("res://surface_layout.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var tiles=Paving.cells()
	check(not tiles.is_empty(),"Colony needs paved foundations and walkways")
	for pad in Paving.foundation_cells():
		check(pad.has_area(),"Each pad must have a positive rectangular area")
		for x in range(pad.position.x,pad.end.x):
			for y in range(pad.position.y,pad.end.y):
				check(tiles.has(Vector2i(x,y)),"Rectangular pad has a missing tile or clipped corner")
	var pads=Paving.foundation_cells()
	for i in range(pads.size()):
		for j in range(i+1,pads.size()):
			check(not pads[i].intersects(pads[j]),"Every structure must retain its own non-overlapping rectangular pad")
	for i in range(Paving.Structures.placements().size()):
		for j in range(i+1,Paving.Structures.placements().size()):
			check(not pads[i].grow(1).intersects(pads[j].grow(1)),"Structures need at least two tiles between their pads")
	for strip in Paving.route_cells():
		check(mini(strip.size.x,strip.size.y)==2,"Every walkway segment must be exactly two tiles across")
		for x in range(strip.position.x,strip.end.x):
			for y in range(strip.position.y,strip.end.y):
				check(tiles.has(Vector2i(x,y)),"Walkway width or square corner has been clipped")
	# An exposed landing approach must be two tiles across, with no ragged extras.
	for x in range(-19,-13):
		check(Paving.road_tiles().has(Vector2i(x,8))==(x in [-17,-16]),"Landing walkway has an uneven cross-section")
	var connected := {}
	var queue: Array[Vector2i]=[Paving.cell_at(Vector2(0,5.5))]
	connected[queue[0]]=true
	var cursor := 0
	while cursor<queue.size():
		var cell=queue[cursor]
		cursor+=1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i=cell+direction
			if not tiles.has(next) or connected.has(next): continue
			var clear := true
			# Check the complete cell-center link, not just destination occupancy.
			for step in range(5):
				var point=Paving.center(cell).lerp(Paving.center(next),step/4.0)
				for block in Navigation.BLOCKS:
					if block.has_point(point): clear=false
			if clear:
				connected[next]=true
				queue.append(next)
	for placement in Paving.Structures.placements():
		var origin=Vector2(placement.position.x,placement.position.z)
		for box in placement.definition.collision_boxes:
			check(Paving.contains(origin+box.get_center()),"Building lacks a tile foundation: "+placement.name)
		for local in [placement.definition.approach,placement.definition.return_point]:
			check(connected.has(Paving.cell_at(origin+Vector2(local.x,local.z))),"Door lacks a connected, obstacle-free tile walkway: "+placement.name)
	for line in Paving.Paths.LINES:
		for point in Paving.Paths.points(line):
			check(Paving.contains(Vector2(point.x,point.z)),"Authored walkway has a paving hole: "+str(point))
	check(connected.has(Paving.cell_at(Surface.LANDING_CENTER)),"Landing apron must join the walkable tile network")
	for footprint in Navigation.STRUCTURES:
		var landing=Rect2(Surface.LANDING_CENTER-Vector2.ONE*Surface.LANDING_RADIUS,Vector2.ONE*Surface.LANDING_RADIUS*2)
		check(not landing.intersects(footprint.grow(5)),"Landing apron needs five metres of building clearance")
	for cell in tiles:
		var rect=Rect2(Vector2(cell)*Paving.TILE,Vector2.ONE*Paving.TILE)
		for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
			check(Paving.Geography.contains(corner,0.35),"Paving crosses the cliff boundary")
		for obstacle in Paving.exclusions(): check(not rect.intersects(obstacle),"Paving at %s overlaps terrain exclusion %s" % [rect,obstacle])
	var drawn=Paving.new()
	root.add_child(drawn)
	check(drawn.get_child_count()==4,"Pads, roads, joints and paint each use one batched mesh")
	check(drawn.get_node("TileField").material_override.shader==load("res://foundation_surface.gdshader"),"Pads use the restrained foundation treatment")
	check(drawn.get_node("TileField").material_override.get_shader_parameter("atlas")==Paving.Kit.material("floor").get_shader_parameter("atlas"),"Foundation retains authored tile source")
	check(drawn.get_node("RoadTiles").material_override.shader==load("res://road_surface.gdshader"),"Roads need their separate light-grey material")
	for cell in Paving.road_tiles():
		check(not Paving.pad_tiles().has(cell),"Road tiles must never overwrite a dark foundation")
	var dashes=Paving.centerline_rectangles()
	check(not dashes.is_empty(),"Roads need dashed centerlines")
	for dash in dashes:
		check(dash.size==Vector2(0.9,0.14) or dash.size==Vector2(0.14,0.9),"Road paint must use consistent orthogonal dashes")
		for point in [dash.position,dash.end,Vector2(dash.position.x,dash.end.y),Vector2(dash.end.x,dash.position.y)]:
			check(Paving.road_tiles().has(Paving.cell_at(point)),"Yellow paint must stay on grey roads")
	var counts={"TileField":Paving.pad_tiles().size(),"RoadTiles":Paving.road_tiles().size(),"JointBed":tiles.size(),"Centerline":dashes.size()}
	check(not drawn.is_processing() and not drawn.is_physics_processing(),"Static paving must not poll")
	for mesh in drawn.get_children():
		var arrays=mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		check(vertices.size()==counts[str(mesh.name)]*6,"Each tile or dash appears exactly once in its mesh")
		for i in range(0,vertices.size(),3):
			check((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).y<0,"Paving face folds downward")
	drawn.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Paving checks passed: ",tiles.size()," unique tiles, rectangular pads, two-tile corridors, separate pad/road materials, yellow dashes, four batched meshes, connected door/landing walks, terrain clearance")
	quit(0 if failures.is_empty() else 1)
