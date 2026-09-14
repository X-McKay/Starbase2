extends RefCounted
## Optional observation camera selection. Never changes crew or backend state.
var enabled := false
var elapsed := 0.0
var selected := ""
var cursor := 0
var seen_active: Dictionary = {}
var pending_active: Array = []

func start() -> void:
	enabled=true; elapsed=30.0; selected=""; cursor=0; seen_active.clear(); pending_active.clear()

func stop() -> void:
	enabled=false; selected=""; elapsed=0.0; seen_active.clear(); pending_active.clear()

func advance(delta:float, intents:Dictionary, reduced:bool) -> String:
	if not enabled or reduced: return ""
	elapsed+=delta
	var candidates:Array=intents.keys()
	if candidates.is_empty(): return ""
	var active:Array=[]
	for kind in candidates:
		var intent:Dictionary=intents[kind]
		if not intent.get("unknown",true) and int(intent.get("active_count",0))>0:
			active.append(kind)
	# A fresh assignment may interrupt a quiet shot, with a minimum shot duration.
	for kind in active:
		if not seen_active.has(kind) and kind not in pending_active: pending_active.append(kind)
	pending_active=pending_active.filter(func(kind):return kind in active and kind != selected)
	var newly_active:Array=pending_active
	var next:=selected
	if elapsed>=6.0 and not active.is_empty() and (selected not in active or not newly_active.is_empty()): next=str(newly_active[0] if not newly_active.is_empty() else active[0])
	elif elapsed>=18.0:
		var pool:Array=active if not active.is_empty() else candidates
		next=str(pool[cursor%pool.size()]); cursor+=1
	seen_active.clear()
	for kind in active: seen_active[kind]=true
	if next==selected: return ""
	selected=next; elapsed=0.0
	pending_active.erase(next)
	return selected
