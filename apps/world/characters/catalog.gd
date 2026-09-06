extends RefCounted
## Catalog maps identities to resources; adding a costume never changes actor logic.
const PATH := "res://characters/catalog.json"
static var entries: Dictionary = {}
static var cache: Dictionary = {}

static func definitions() -> Dictionary:
	if entries.is_empty(): entries=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return entries

static func get_definition(id: String, pilot: bool = false) -> Resource:
	var entry: Dictionary = definitions().get(id,definitions().operator)
	var path: String = entry.get("pilot",entry.production) if pilot else entry.production
	if not cache.has(path): cache[path]=load(path)
	return cache[path]
