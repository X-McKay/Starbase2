extends RefCounted
## Local cosmetic selection only; never alters the operator's domain identity.
const PATH="user://starbase2-player.cfg"
static func valid_id(value:Variant)->String:
	return str(value) if value in ["operator","cybercat"] else "operator"
static func read_character(path:String=PATH)->String:
	if path.is_empty():return "operator"
	var config=ConfigFile.new()
	if config.load(path)!=OK:return "operator"
	return valid_id(config.get_value("player","character","operator"))
static func write_character(value:String,path:String=PATH)->Error:
	if path.is_empty():return OK
	var config=ConfigFile.new()
	config.load(path)
	config.set_value("player","character",valid_id(value))
	return config.save(path)
