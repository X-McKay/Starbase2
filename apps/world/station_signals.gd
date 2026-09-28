extends Node3D
## Exterior record aggregates. Rendering and inspection cannot dispatch work.
const StateView = preload("res://state.gd")
const OPEN := ["queued", "running", "cancel_requested", "executing", "analyzing", "evaluating", "verifying", "capturing", "reviewing"]
const TERMINAL := ["completed", "failed", "cancelled"]
const GROUPS := {"review":["review", "watchkeeper", "reviewer"], "repair":["repair"], "gym":["gym"]}
const TITLES := {"review":"COMMAND", "repair":"WORKSHOP", "gym":"TRIAL HALL"}
const NEAR_RANGE := 24.0
const RESTRAINED_RANGE := 48.0
const SAFE_CLEARANCE_PIXELS := 84.0
const SAFE_EDGE_PIXELS := 24.0
const SAFE_TOP_PIXELS := 168.0
signal inspect_requested(context: String)
var labels: Dictionary = {}
var model: Dictionary = {}
var visible_context := ""
var selected_context := ""
var anchors: Dictionary = {}

static func project(records: Array, disconnected: bool, observed_at: float, fixture: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for context in GROUPS:
		result[context] = {"active":0, "results":0, "evidence":0, "missing_evidence":0, "unknown":0, "stale":0,
			"failed":0, "blocked":0, "cancelled":0, "no_change":0,
			"disconnected":disconnected, "observed_at":observed_at, "fixture":fixture}
	var unique: Dictionary = {}
	for record in records:
		if not record is Dictionary or not record.get("input") is Dictionary: continue
		var id := str(record.input.get("id", ""))
		if id.is_empty(): continue
		var context := StateView.context(record)
		var group := ""
		for key in GROUPS:
			if context in GROUPS[key]: group = key; break
		if group.is_empty(): continue
		var stamp: float = float(record.updated_at) if record.get("updated_at") is float or record.get("updated_at") is int else 0.0
		var identity := context+":"+id
		if unique.has(identity) and stamp <= float(unique[identity].stamp): continue
		unique[identity] = {"record":record, "group":group, "stamp":stamp}
	for entry in unique.values():
		var record: Dictionary = entry.record
		var counts: Dictionary = result[entry.group]
		var state := str(record.get("state", "unknown"))
		if bool(record.get("stale", true)): counts.stale += 1
		if state in OPEN: counts.active += 1
		elif state in TERMINAL:
			counts.results += 1
			if record.get("evidence") is Dictionary and not record.evidence.is_empty(): counts.evidence += 1
			elif state == "completed": counts.missing_evidence += 1
			var evidence: Dictionary = record.evidence if record.get("evidence") is Dictionary else {}
			var summary: Dictionary = evidence.summary if evidence.get("summary") is Dictionary else {}
			# Retained failures are history, not an assertion about current open work.
			# Completion alone is never evidence of success or verified improvement.
			if state == "failed" or StateView.repair_execution_failed(record): counts.failed += 1
			elif state == "cancelled": counts.cancelled += 1
			elif summary.get("outcome") == "blocked": counts.blocked += 1
			elif summary.get("outcome") == "no_change": counts.no_change += 1
		else: counts.unknown += 1
	return result

static func signal_status(counts: Dictionary) -> Dictionary:
	# Symbols and explicit words carry the distinction without color or motion.
	# Freshness overrides history; the count lines still retain mixed outcomes.
	if counts.is_empty() or float(counts.get("observed_at", 0)) <= 0:
		return {"text":"[?] UNKNOWN", "color":Color("ddd6cc")}
	if counts.get("disconnected", false):
		return {"text":"[/] OFFLINE · last known", "color":Color("c7c8cc")}
	if int(counts.get("stale", 0)) > 0:
		return {"text":"[~] STALE · last known", "color":Color("edd0a5")}
	if int(counts.get("missing_evidence", 0)) > 0 or int(counts.get("unknown", 0)) > 0:
		return {"text":"[?] INCOMPLETE RECORDS", "color":Color("edd0a5")}
	if int(counts.get("failed", 0)) > 0:
		return {"text":"[!] FAILED RESULTS", "color":Color("f2b5a7")}
	if int(counts.get("blocked", 0)) > 0:
		return {"text":"[#] BLOCKED RESULTS", "color":Color("edd0a5")}
	if int(counts.get("active", 0)) > 0:
		return {"text":"[>] OPEN WORK", "color":Color("f3d0a9")}
	if int(counts.get("cancelled", 0)) > 0:
		return {"text":"[x] CANCELLED RESULTS", "color":Color("d7d0c6")}
	if int(counts.get("no_change", 0)) > 0:
		return {"text":"[=] NO CHANGE RECORDED", "color":Color("c7dcd7")}
	return {"text":"[-] RETAINED RECORDS" if int(counts.get("results", 0)) > 0 else "[-] NO RETAINED RECORDS", "color":Color("ddd6cc")}

static func label_text(context: String, counts: Dictionary, detailed: bool = true) -> String:
	var title := str(TITLES.get(context, "STATION"))
	var status := ("FIXTURE · " if counts.get("fixture", false) else "") + str(signal_status(counts).text)
	if counts.is_empty() or float(counts.get("observed_at", 0)) <= 0:
		return title+" · "+status if not detailed else title+" · I inspect\n"+status+"\nAwaiting records"
	if not detailed: return title+" · "+status
	var detail := "%d open · %d retained results" % [int(counts.get("active", 0)), int(counts.get("results", 0))]
	var outcomes: PackedStringArray = []
	for key in ["failed", "blocked", "cancelled", "no_change", "missing_evidence", "unknown"]:
		if int(counts.get(key, 0)) > 0: outcomes.append("%d %s" % [int(counts[key]),str(key).replace("_", " ")])
	# Keep the complete mixed breakdown without producing a single wide line.
	for start in range(0,outcomes.size(),3): detail += "\n"+" · ".join(outcomes.slice(start,start+3))
	return title+" · I inspect\n"+status+"\n"+detail

func configure(anchors: Dictionary) -> void:
	# Explicit world-space entrance anchors, provided by the owning scene.
	self.anchors = anchors.duplicate()
	for context in labels: labels[context].queue_free()
	labels.clear()
	for context in GROUPS:
		if not anchors.get(context) is Vector3: continue
		var label := Label3D.new()
		label.name = "Signal_"+context
		label.font_size = 30; label.outline_size = 6; label.pixel_size = 0.008
		label.modulate = Color("e2eada")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		add_child(label)
		label.global_position = anchors[context]
		label.text = label_text(context, model.get(context, {}))
		label.hide()
		labels[context] = label

func update_records(records: Array, disconnected: bool, observed_at: float, fixture: bool = false) -> void:
	model = project(records, disconnected, observed_at, fixture)
	for context in labels: labels[context].text = label_text(context, model.get(context, {}), context == visible_context or context == selected_context)

func set_selected_context(context: String) -> void:
	# Selection changes presentation only; it never dispatches or changes station state.
	selected_context = context if labels.has(context) else ""

func update_view(camera: Camera3D, focus_position: Vector3, suppressed: bool = false, large_text: bool = false) -> void:
	visible_context = ""
	var closest := RESTRAINED_RANGE
	var selection_active := false
	if not suppressed and camera != null:
		# A selected record wins within the same safe interaction range, so a
		# doorway/player cannot be covered by a competing station badge.
		if labels.has(selected_context):
			var selected_point: Vector3 = anchors.get(selected_context, labels[selected_context].global_position)
			var selected_distance := focus_position.distance_to(selected_point)
			if selected_distance < RESTRAINED_RANGE and not camera.is_position_behind(selected_point):
				closest = selected_distance; visible_context = selected_context; selection_active = true
		if not selection_active:
			for context in labels:
				var point: Vector3 = anchors.get(context,labels[context].global_position)
				var distance := focus_position.distance_to(point)
				if distance < closest and not camera.is_position_behind(point):
					closest = distance; visible_context = context
	for context in labels:
		var label: Label3D = labels[context]
		var point: Vector3 = anchors.get(context, label.global_position)
		var distance := focus_position.distance_to(point)
		var shown: bool = context == visible_context and distance < RESTRAINED_RANGE
		label.visible = shown
		var detailed: bool = shown and (distance <= NEAR_RANGE or context == selected_context)
		label.font_size = 36 if large_text and detailed else 30 if detailed else 20
		label.text = label_text(context, model.get(context, {}), detailed)
		label.modulate = signal_status(model.get(context, {})).color
		label.global_position = point
		if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			# Keep nearby detail legible while restrained/distant badges stay quiet.
			# Large text must enlarge apparent pixels, not just font texture resolution.
			var apparent_size := (21.0 if large_text else 17.0) if detailed else (16.0 if large_text else 13.0)
			label.pixel_size = camera.size / maxf(1.0, camera.get_viewport().get_visible_rect().size.y) * (apparent_size / float(label.font_size))
		if shown:
			_place_safely(camera, label, focus_position)

func _place_safely(camera: Camera3D, label: Label3D, focus_position: Vector3) -> void:
	if camera == null: return
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.y <= 0: return
	var anchor := label.global_position
	var anchor_screen := camera.unproject_position(anchor)
	var focus_screen := camera.unproject_position(focus_position)
	var desired := anchor_screen
	# Reserve a readable band above the operator and the entrance anchor.
	desired.y = minf(desired.y, focus_screen.y - SAFE_CLEARANCE_PIXELS)
	# Keep the world badge below the wide/compact navigation chrome.
	desired.y = maxf(desired.y, SAFE_TOP_PIXELS)
	var horizontal_clearance := minf(viewport_size.x * 0.5, SAFE_EDGE_PIXELS + _screen_half_size(camera,label).x)
	desired.x = clampf(desired.x, horizontal_clearance, viewport_size.x - horizontal_clearance)
	var depth := maxf(0.1, -camera.to_local(anchor).z)
	label.global_position = camera.project_position(desired, depth)

func _screen_half_size(camera: Camera3D, label: Label3D) -> Vector2:
	var center := camera.unproject_position(label.global_position)
	var dimensions := label.get_aabb().size
	var right := camera.unproject_position(label.global_position+camera.global_basis.x*dimensions.x*0.5)
	var top := camera.unproject_position(label.global_position+camera.global_basis.y*dimensions.y*0.5)
	return Vector2(center.distance_to(right),center.distance_to(top))

func hit(camera: Camera3D, point: Vector2) -> bool:
	if visible_context.is_empty() or camera == null: return false
	var label: Label3D = labels[visible_context]
	if not label.is_visible_in_tree() or camera.is_position_behind(label.global_position): return false
	var center := camera.unproject_position(label.global_position)
	var half_size := _screen_half_size(camera,label)+Vector2(8,8)
	half_size = half_size.max(Vector2(24,30))
	if not Rect2(center-half_size, half_size*2).has_point(point): return false
	var ray := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(center), label.global_position)
	ray.collide_with_areas = false
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	inspect_requested.emit(visible_context)
	return true
