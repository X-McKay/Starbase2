extends SceneTree
const Commands=preload("res://commands.gd")
class RecordingCommands extends "res://commands.gd":
	var requests:Array=[]
	func _request(url:String,headers:PackedStringArray,method:int,body:String="") -> void:
		requests.append({"url":url,"headers":headers,"method":method,"body":body})
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var spin:=SpinBox.new(); spin.min_value=30; spin.max_value=86400; spin.value=300; root.add_child(spin)
	spin.get_line_edit().text="45"
	spin.get_line_edit().text_changed.emit("45")
	check(Commands.commit_integer_spinbox(spin)==45 and int(spin.value)==45,"Typed SpinBox interval is committed before dispatch")
	spin.get_line_edit().text="45.5"
	spin.get_line_edit().text_changed.emit("45.5")
	check(Commands.commit_integer_spinbox(spin)<0 and int(spin.value)==45,"Non-integral interval is rejected instead of rounded")
	check(Commands.http_error_reason(JSON.stringify({"detail":"interval_seconds must be an integer"}).to_utf8_buffer(),422)=="interval_seconds must be an integer","Structured HTTP rejection reason is surfaced")
	check(Commands.http_error_reason("plain server reason".to_utf8_buffer(),400)=="plain server reason","Plain HTTP rejection reason is surfaced")
	var payload:Dictionary={"id":"duty-one","target":"fixture/review","profile":"balanced","interval_seconds":60,"enabled":true,"generation":4}
	var exact:=payload.duplicate(); exact.generation=5
	check(Commands.duty_reconciled({"duties":[exact]},payload,"duty-one"),"Exact next generation and settings match")
	for key in ["id","target","profile","interval_seconds","enabled","generation"]:
		var mismatch:=exact.duplicate()
		match key:
			"interval_seconds": mismatch[key]=90
			"enabled": mismatch[key]=false
			"generation": mismatch[key]=6
			_: mismatch[key]="different"
		check(not Commands.duty_reconciled({"duties":[mismatch]},payload,"duty-one"),"Mismatch remains uncertain: "+key)
	for malformed in [{},{"duties":null},{"duties":[]},{"duties":[null,"broken",{}]},null]:
		check(not Commands.duty_reconciled(malformed,payload,"duty-one"),"Missing/malformed records remain uncertain")
	for invalid_generation in [4,3,6,5.5,"5",null]:
		var wrong:=exact.duplicate(); wrong.generation=invalid_generation
		check(not Commands.duty_reconciled({"duties":[wrong]},payload,"duty-one"),"Only exact numeric next generation can reconcile")
	var client:=RecordingCommands.new()
	var accepted:Array[String]=[]
	client.accepted.connect(func(id:String):accepted.append(id))
	client.submit("/v2/duties",payload,"duty-one","/v2/duties/duty-one")
	check(client.record_path=="/v2/snapshot","Duties reconcile against snapshot even if caller supplies detail lookup")
	client._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(["Set-Cookie: starbase_session=fixture; HttpOnly"]),PackedByteArray())
	check(client.requests.size()==2 and client.requests[1].method==HTTPClient.METHOD_POST,"Initial authorized attempt dispatches once")
	client._response(HTTPRequest.RESULT_TIMEOUT,0,PackedStringArray(),PackedByteArray())
	check(client.uncertain and client.phase=="reconcile" and client.requests[-1].method==HTTPClient.METHOD_GET and client.requests[-1].url.ends_with("/v2/snapshot"),"Lost write response performs GET snapshot")
	var later:=exact.duplicate(); later.generation=6
	client._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"duties":[later]}).to_utf8_buffer())
	check(client.uncertain and accepted.is_empty(),"Newer revision does not acknowledge original write")
	client.submit("/v3/repairs",{"id":"never-dispatched"},"never-dispatched")
	check(client.requests[-1].method==HTTPClient.METHOD_GET and client.run_id=="duty-one" and client.payload==payload,"Uncertain submit retains original identity and performs only GET")
	client._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"duties":[]}).to_utf8_buffer())
	check(client.uncertain and accepted.is_empty(),"Missing record never clears uncertainty")
	client.submit("/v2/duties",payload,"duty-one")
	client._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"duties":[exact]}).to_utf8_buffer())
	check(not client.uncertain and accepted==["duty-one"],"Exact record acknowledges once")
	check(client.requests.filter(func(r):return r.method==HTTPClient.METHOD_POST).size()==1,"Reconciliation never redispatches")
	client.http.free();client.free()
	spin.queue_free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("DUTY_COMMANDS_PASSED: exact settings and next generation, mismatch/missing/newer preserved, GET-only uncertainty reconciliation")
	quit(0 if failures.is_empty() else 1)
