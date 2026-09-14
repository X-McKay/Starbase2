extends RefCounted
## Select transport once by platform; preserve the native HTTPRequest path.
static func create():
	return preload("res://web_request.gd").new() if OS.has_feature("web") else HTTPRequest.new()

static func default_origin() -> String:
	if not OS.has_feature("web"): return "http://127.0.0.1:8787"
	var location := JavaScriptBridge.get_interface("location")
	return str(location.origin) if location != null else ""

static func web_origin(value: String) -> bool:
	return OS.has_feature("web") and value == default_origin() and (value.begins_with("https://") or value == "http://127.0.0.1" or value.begins_with("http://127.0.0.1:"))
