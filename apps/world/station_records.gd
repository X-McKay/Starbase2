extends "res://morning_briefing.gd"
## Native station inspection includes every resident role, not only V1 history.
const SignalsView = preload("res://station_signals.gd")
const MAX_STATION_RECORDS := 20
var stations: OptionButton
var selected_station := "review"
var source_records: Array = []
var source_disconnected := true
var source_observed := 0.0
var source_fixture := false
var freshness_details: Label
var freshness_toggle: Button

static func project_station(records: Array, station: String, disconnected: bool, observed_at: float, fixture: bool = false) -> Dictionary:
	var groups: Array = SignalsView.GROUPS.get(station, [])
	var aggregate: Dictionary = SignalsView.project(records, disconnected, observed_at, fixture).get(station, {})
	var unique: Dictionary = {}
	for record in records:
		if not record is Dictionary or not record.get("input") is Dictionary: continue
		var context := StateView.context(record)
		var id := str(record.input.get("id", ""))
		if context not in groups or id.is_empty(): continue
		var stamp: float = float(record.updated_at) if record.get("updated_at") is float or record.get("updated_at") is int else 0
		var key := context+":"+id
		if unique.has(key) and stamp <= float(unique[key].stamp): continue
		var state := str(record.get("state", "unknown"))
		var evidence: Dictionary = record.evidence if record.get("evidence") is Dictionary else {}
		var status := StateView.describe(record,disconnected)
		var summary_data: Dictionary = evidence.summary if evidence.get("summary") is Dictionary else {}
		if not str(summary_data.get("outcome", "")).is_empty(): status += " · "+str(summary_data.outcome).replace("_", " ")
		if state == "completed" and evidence.is_empty(): status += " · evidence missing"
		unique[key]={"id":id,"context":context,"crew":CREW.get(context,"Crew"),"stamp":stamp,
			"state":state,"status":status,"target":str(record.input.get("target",record.input.get("scenario","Target not reported"))),
			"advisory":context in ["watchkeeper","reviewer"],"open":state in OPEN,"evidence_available":not evidence.is_empty()}
	var entries: Array = unique.values()
	entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.open!=b.open: return a.open
		if a.stamp==b.stamp: return a.context+":"+a.id < b.context+":"+b.id
		return a.stamp>b.stamp)
	return {"reports":entries.slice(0,MAX_STATION_RECORDS),"total_count":entries.size(),"retained_count":aggregate.get("results",0),
		"active_count":aggregate.get("active",0),"unknown_count":aggregate.get("unknown",0),"stale_count":aggregate.get("stale",0),
		"disconnected":disconnected,"observed_at":observed_at,"fixture":fixture}

func _ready() -> void:
	super._ready()
	heading.text="STATION RECORDS"
	stations=OptionButton.new()
	for key in SignalsView.GROUPS: stations.add_item(SignalsView.TITLES[key])
	stations.custom_minimum_size.y=40
	stations.tooltip_text="Select a station to inspect its retained work"
	var column:=heading.get_parent()
	var title_row:=HBoxContainer.new()
	column.add_child(title_row); column.move_child(title_row,0)
	column.remove_child(heading); title_row.add_child(heading)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title_row.add_child(stations)
	stations.custom_minimum_size.x=220
	stations.item_selected.connect(func(index: int): selected_station=SignalsView.GROUPS.keys()[index]; rebuild())
	var freshness_row:=HBoxContainer.new()
	var freshness_parent:=freshness.get_parent()
	var freshness_index:=freshness.get_index()
	freshness_parent.remove_child(freshness)
	freshness_parent.add_child(freshness_row)
	freshness_parent.move_child(freshness_row,freshness_index)
	freshness_row.add_child(freshness)
	freshness.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	freshness_toggle=Button.new()
	freshness_toggle.text="Details"
	freshness_toggle.tooltip_text="Show observation details"
	freshness_toggle.custom_minimum_size=Vector2(100,36)
	freshness_toggle.pressed.connect(func():
		freshness_details.visible=not freshness_details.visible
		freshness_toggle.text="Hide" if freshness_details.visible else "Details"
		freshness_toggle.tooltip_text="Hide observation details" if freshness_details.visible else "Show observation details")
	freshness_row.add_child(freshness_toggle)
	freshness_details=make_label(freshness_parent,"",14)
	freshness_parent.move_child(freshness_details,freshness_row.get_index()+1)
	freshness_details.visible=false
	freshness_details.add_theme_color_override("font_color",ConsoleTheme.MUTED)
	refresh()

func present(context: String = "review") -> void:
	if SignalsView.GROUPS.has(context): selected_station=context
	if stations!=null: stations.select(SignalsView.GROUPS.keys().find(selected_station))
	rebuild(); show(); layout()
	stations.grab_focus()

func update_records(records: Array, disconnected: bool, observed_at: float, fixture: bool = false) -> void:
	source_records=records.duplicate(true); source_disconnected=disconnected; source_observed=observed_at; source_fixture=fixture
	rebuild()

func rebuild() -> void:
	model=project_station(source_records,selected_station,source_disconnected,source_observed,source_fixture)
	refresh()
	if is_inside_tree(): layout.call_deferred()

func refresh() -> void:
	super.refresh()
	if not is_instance_valid(reports): return
	heading.text="STATION RECORDS"
	if stations!=null: stations.add_theme_font_size_override("font_size",20 if large_text else 16)
	if model.is_empty(): return
	if float(model.observed_at)<=0: freshness.text=("FIXTURE · " if model.fixture else "")+("OFFLINE / STALE · " if model.disconnected else "")+"UNKNOWN · time unavailable"
	elif model.disconnected: freshness.text="OFFLINE / STALE · last-known snapshot"
	elif int(model.get("stale_count",0))>0: freshness.text="STALE records · observed timestamp available"
	else: freshness.text="CORE SNAPSHOT · fresh"
	freshness.tooltip_text="Observation: "+(Time.get_datetime_string_from_unix_time(int(model.observed_at)).replace("T", " ")+" UTC" if float(model.observed_at)>0 else "unavailable")
	if model.disconnected: freshness.tooltip_text += " · last known snapshot"
	if is_instance_valid(freshness_details): freshness_details.text="Observation timestamp: "+(Time.get_datetime_string_from_unix_time(int(model.observed_at)).replace("T", " ")+" UTC" if float(model.observed_at)>0 else "unavailable")+"\nThis view retains at most %d records; open work is shown first." % MAX_STATION_RECORDS
	summary.text="SNAPSHOT · %d open · %d terminal · %d unknown · showing %d/%d · %d retained%s" % [model.active_count,model.retained_count,model.unknown_count,filtered_reports().size(),model.reports.size(),model.total_count," · last known" if model.disconnected else ""]
	summary.tooltip_text="This station shows at most %d retained records, with open work first. Full record identity and timestamps remain available in each row and the selected detail." % MAX_STATION_RECORDS
	if model.reports.is_empty() and reports.get_child_count()>0:
		reports.get_child(0).text="No retained records for this station in this snapshot.\nThis does not claim that no work happened."

func reset() -> void:
	source_records.clear(); source_disconnected=true; source_observed=0; source_fixture=false
	super.reset()

func layout() -> void:
	super.layout()
