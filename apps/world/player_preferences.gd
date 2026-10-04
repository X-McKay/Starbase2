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
## Comfort settings (Display and Audio pages). Unknown keys and wrong types are
## ignored so a hand-edited or older file cannot break startup.
const COMFORT_KEYS:=["reduced_motion","large_text","sound","crew_summary"]
static func read_comfort(path:String=PATH)->Dictionary:
	if path.is_empty():return {}
	var config=ConfigFile.new()
	if config.load(path)!=OK:return {}
	var values:={}
	for key in COMFORT_KEYS:
		if not config.has_section_key("comfort",key):continue
		var value=config.get_value("comfort",key)
		if value is bool:values[key]=value
	return values
static func write_comfort(values:Dictionary,path:String=PATH)->Error:
	if path.is_empty():return OK
	var config=ConfigFile.new()
	config.load(path)
	for key in COMFORT_KEYS:
		if values.get(key) is bool:config.set_value("comfort",key,values[key])
	return config.save(path)
