extends Node
## Local operator session only. Never reads a worker credential or persists cookies.
signal feedback(message: String, pending: bool)
signal accepted(id: String)
var api := "http://127.0.0.1:8787"
var http := HTTPRequest.new()
var cookie := ""
var phase := ""
var path := ""
var payload: Dictionary = {}
var run_id := ""
var uncertain := false
var record_path := ""

func _ready() -> void:
	add_child(http)
	http.timeout = 4.0
	http.max_redirects = 0
	http.body_size_limit = 2097152
	http.request_completed.connect(_response)

static func local_origin(value: String) -> bool:
	var prefix := "http://127.0.0.1:"
	if not value.begins_with(prefix): return false
	var port := value.trim_prefix(prefix)
	return port.is_valid_int() and str(int(port)) == port and int(port) > 0 and int(port) <= 65535

func submit(endpoint: String, data: Dictionary, id: String, lookup: String = "") -> void:
	if phase != "":
		return
	if not local_origin(api):
		feedback.emit("Native commands require the local loopback core. Use its journal.",false)
		return
	if uncertain:
		phase = "reconcile"
		feedback.emit("Reconciling the previous request; no new dispatch.",true)
		_request(api + record_path, PackedStringArray(), HTTPClient.METHOD_GET)
		return
	path = endpoint
	record_path = endpoint.trim_suffix("/cancel") if endpoint.ends_with("/cancel") else endpoint + "/" + id
	if not lookup.is_empty(): record_path = lookup
	payload = data.duplicate()
	run_id = id
	phase = "session"
	feedback.emit("Opening a local operator session…",true)
	_request(api + "/", PackedStringArray(), HTTPClient.METHOD_GET)

func _request(url: String, headers: PackedStringArray, method: int, body: String = "") -> void:
	var result := http.request(url, headers, method, body)
	if result != OK:
		_response(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())

func _response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var success := result == HTTPRequest.RESULT_SUCCESS
	if phase == "session":
		cookie = ""
		if success and code == 200:
			for header in headers:
				if header.to_lower().begins_with("set-cookie: starbase_session="):
					cookie = header.substr(header.find(":")+1).strip_edges().split(";")[0]
		if cookie.is_empty():
			phase = ""
			feedback.emit("Could not obtain a local operator session. Nothing dispatched.",false)
			return
		phase = "write"
		feedback.emit("Request pending · awaiting the core record…",true)
		_request(api+path,PackedStringArray(["Content-Type: application/json","Cookie: "+cookie,"Origin: "+api]),HTTPClient.METHOD_POST,JSON.stringify(payload))
		cookie = ""
		return
	if phase == "write":
		if success and code >= 200 and code < 300:
			phase = ""
			accepted.emit(run_id)
			feedback.emit("Request accepted · watching authoritative state.",false)
		elif success and code >= 400 and code < 500:
			phase = ""
			var data = JSON.parse_string(body.get_string_from_utf8())
			feedback.emit("Request rejected: " + str(data.get("error","see journal")) if data is Dictionary else "Request rejected; see journal.",false)
		else:
			uncertain = true
			phase = "reconcile"
			_request(api+record_path,PackedStringArray(),HTTPClient.METHOD_GET)
		return
	if phase == "reconcile":
		phase = ""
		if success and code == 200:
			var record = JSON.parse_string(body.get_string_from_utf8())
			if record is Dictionary and path in ["/v4/repositories", "/v4/memory/review"]:
				var items: Array = record.get("repositories",[]) if path=="/v4/repositories" else record.get("memory",[])
				for item in items:
					var matched: bool = item.get("config",{}).get("repository","")==str(payload.get("repository","!")).strip_edges().to_lower() if path=="/v4/repositories" else item.get("id")==payload.get("id")
					var revision: int = int(item.get("config",{}).get("generation",-1)) if path=="/v4/repositories" else int(item.get("revision",-1))-1
					var expected: int = int(payload.get("generation",payload.get("revision",0)))
					if matched and revision >= expected:
						uncertain=false
						accepted.emit(run_id)
						feedback.emit("Record found · inspect current revision before another change.",false)
						return
			if record is Dictionary and record.get("input",{}).get("request",record.get("input",{})).get("id") == run_id:
				uncertain = false
				accepted.emit(run_id)
				feedback.emit("Record reconciled · inspect current state before another action.",false)
				return
		# Keep uncertainty even for a temporary 404: a slow handler may still commit.
		feedback.emit("Outcome unknown · no retry. Repeat the action to reconcile this ID, or open the journal: " + run_id,false)
