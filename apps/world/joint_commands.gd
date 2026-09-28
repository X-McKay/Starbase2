extends "res://commands.gd"
## V5 acknowledgements require exact intent; a matching ID cannot prove cancellation.
var receipt:Dictionary={}

static func decode(body:PackedByteArray) -> Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(body.get_string_from_utf8())==OK else null

static func launch_matches(record:Variant, request:Dictionary) -> bool:
	if not record is Dictionary or not record.get("input") is Dictionary:return false
	var value:Dictionary=record.input
	for key in ["id","opportunity","build","scenario","inference"]:
		if value.get(key)!=request.get(key):return false
	if not value.get("budget") is Dictionary or not request.get("budget") is Dictionary:return false
	return value.budget.get("requests")==request.budget.get("requests") and value.budget.get("tokens")==request.budget.get("tokens")

func acknowledgement(record:Variant) -> String:
	if path=="/v5/missions":
		return "Exact mission input reconciled · following Core state." if launch_matches(record,payload) else ""
	if not record is Dictionary or not record.get("input") is Dictionary or record.input.get("id")!=run_id:return ""
	if record.get("state")=="cancelled":return "Cancellation recorded · future dispatch is fenced. Started work remains in evidence."
	if record.get("state") in ["completed","failed"]:return "Mission already terminal · cancellation did not stop completed work. Inspect its outcome."
	return ""

func _response(result:int,code:int,headers:PackedStringArray,body:PackedByteArray) -> void:
	if path.begins_with("/v5/missions") and phase in ["write","reconcile"]:
		var success:=result==HTTPRequest.RESULT_SUCCESS and code>=200 and code<300
		if success:
			var record=decode(body)
			var message:=acknowledgement(record)
			if not message.is_empty():
				receipt=record.duplicate(true);phase="";uncertain=false
				accepted.emit(run_id);feedback.emit(message,false);return
		if phase=="reconcile":
			phase="";uncertain=true
			feedback.emit("Outcome unknown · no retry. Exact intent or terminal cancellation state was not found for "+run_id+". Reconcile this request.",false)
			return
		if success:
			uncertain=true;phase="reconcile"
			_request(api+record_path,PackedStringArray(),HTTPClient.METHOD_GET)
			return
	super._response(result,code,headers,body)
