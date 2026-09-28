extends "res://commands.gd"
## Exact V6 duty CAS and cancellation acknowledgements over the existing operator session.
var receipt:Dictionary={}
var intention:=""
static func decode(body:PackedByteArray) -> Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(body.get_string_from_utf8())==OK else null
static func duty_matches(value:Variant,request:Dictionary) -> bool:
	if not value is Dictionary:return false
	var control=value.get("control",value)
	if not control is Dictionary or not control.get("duty") is Dictionary:return false
	var duty:Dictionary=control.duty
	for key in ["id","generation","enabled","baseline","max_cycles","cooldown_seconds"]:
		if duty.get(key)!=request.get(key):return false
	if not duty.get("budget") is Dictionary or not request.get("budget") is Dictionary:return false
	for key in ["proposal_requests","proposal_tokens","trial_requests","trial_tokens"]:
		if duty.budget.get(key)!=request.budget.get(key):return false
	return true
func acknowledgement(value:Variant) -> String:
	if path=="/v6/duty":
		if duty_matches(value,payload):
			if intention=="rebase":return "Practice baseline changed · duty remains stopped. Enable separately to admit new cycles."
			return "Practice duty enabled · bounded autonomous cycles may start." if payload.enabled else "Practice duty stopped · further dispatch is blocked; already-started calls remain subject to reconciliation."
		return ""
	if not value is Dictionary or value.get("id")!=run_id:return ""
	if value.get("state")=="cancelled":return "Cycle cancellation recorded · late usage remains accounted."
	if value.get("state") in ["completed","failed"]:return "Cycle already terminal · cancellation did not stop completed work."
	return ""
func _response(result:int,code:int,headers:PackedStringArray,body:PackedByteArray) -> void:
	if path.begins_with("/v6/") and phase in ["write","reconcile"]:
		var success:=result==HTTPRequest.RESULT_SUCCESS and code>=200 and code<300
		if success:
			var value=decode(body);var message:=acknowledgement(value)
			if not message.is_empty():
				receipt=value.duplicate(true);phase="";uncertain=false
				accepted.emit(run_id);feedback.emit(message,false);return
		if phase=="reconcile":
			phase="";uncertain=true
			feedback.emit("Outcome unknown · exact duty generation/settings or terminal cycle state not found. Reconcile before retry; no new write was sent.",false);return
		if success:
			uncertain=true;phase="reconcile";_request(api+record_path,PackedStringArray(),HTTPClient.METHOD_GET);return
	super._response(result,code,headers,body)
