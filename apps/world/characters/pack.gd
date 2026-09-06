extends SceneTree
const Check=preload("res://characters/validate.gd")
const DIRECTIONS=["front","back","left","right"]
func _initialize() -> void:
	var root:=ProjectSettings.globalize_path("res://../..")
	var frame_root:=root+"/.local/character-frames/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames-dir="): frame_root=arg.trim_prefix("--frames-dir=").trim_suffix("/")+"/"
	var entries: Array=JSON.parse_string(FileAccess.get_file_as_string(root+"/art/characters/catalog.json"))
	for entry in entries:
		var id: String=entry.id
		var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(frame_root+id+"/source.json"))
		var size:=Vector2i(source.canvas[0],source.canvas[1])
		var cell:=size+Vector2i(4,4)
		var atlas:=Image.create(cell.x*9,cell.y*4,false,Image.FORMAT_RGBA8)
		var manifest: Dictionary=source.duplicate(true)
		manifest["frames"]=[]
		manifest["gutter"]=2
		for row in range(4):
			for column in range(9):
				var path: String=frame_root+id+"/"+DIRECTIONS[row]+"-"+str(column)+".png"
				var frame:=Image.load_from_file(path)
				var errors:=Check.frame_errors(frame,size)
				if not errors.is_empty():
					push_error(path+": "+str(errors)); quit(1); return
				var origin:=Vector2i(column*cell.x+2,row*cell.y+2)
				atlas.blit_rect(frame,Rect2i(Vector2i.ZERO,size),origin)
				manifest.frames.append({"direction":DIRECTIONS[row],"clip":"idle" if column==0 else "walk","index":maxi(0,column-1),"rect":[origin.x,origin.y,size.x,size.y],"sha256":FileAccess.get_sha256(path)})
		var out: String=root+"/apps/world/art/characters/"+id
		atlas.save_png(out+".png")
		manifest["atlas_sha256"]=FileAccess.get_sha256(out+".png")
		manifest["packer_sha256"]=FileAccess.get_sha256(root+"/apps/world/characters/pack.gd")
		manifest["source_sha256"]=FileAccess.get_sha256(root+"/"+source.source)
		FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  ")+"\n")
		var definition:="[gd_resource type=\"Resource\" load_steps=3 format=3]\n[ext_resource type=\"Script\" path=\"res://characters/definition.gd\" id=\"1\"]\n[ext_resource type=\"Texture2D\" path=\"res://art/characters/%s.png\" id=\"2\"]\n[resource]\nscript = ExtResource(\"1\")\nid = \"%s\"\natlas = ExtResource(\"2\")\ncanvas = Vector2i(%d,%d)\npivot = Vector2(%d,%d)\npixel_size = 0.011\nstride = %f\nsource = \"%s; %s\"\n" % [id,id,size.x,size.y,source.pivot[0],source.pivot[1],source.stride_m,source.source,source.tool]
		FileAccess.open(root+"/apps/world/characters/definitions/"+id+".tres",FileAccess.WRITE).store_string(definition)
		print("Packed ",id,": 36 RGBA frames, fixed pivot ",source.pivot)
	quit()
