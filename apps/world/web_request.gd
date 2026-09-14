extends Node
## HTTPRequest-shaped Web adapter. Native consumers still receive HTTPRequest.
signal request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)
var timeout := 8.0
var max_redirects := 0
var body_size_limit := 4194304
var bridge: JavaScriptObject
var callback: JavaScriptObject

func _ready() -> void:
	JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web_request.js"), true)
	callback = JavaScriptBridge.create_callback(_completed)
	var factory := JavaScriptBridge.get_interface("StarbaseWebTransport")
	if factory != null: bridge = factory.create(callback)

func request(url: String, _headers: PackedStringArray = PackedStringArray(), method: int = HTTPClient.METHOD_GET, body: String = "") -> int:
	if bridge == null: return ERR_UNAVAILABLE
	if bridge.busy: return ERR_BUSY
	if method not in [HTTPClient.METHOD_GET, HTTPClient.METHOD_POST]: return ERR_INVALID_PARAMETER
	if bridge.request(url, "GET" if method == HTTPClient.METHOD_GET else "POST", body, timeout * 1000, body_size_limit): return OK
	return ERR_INVALID_PARAMETER

func cancel_request() -> void:
	if bridge != null: bridge.cancel()

func get_http_client_status() -> int:
	return HTTPClient.STATUS_REQUESTING if bridge != null and bridge.busy else HTTPClient.STATUS_DISCONNECTED

func _completed(args: Array) -> void:
	var response: Array = JSON.parse_string(str(args[0]))
	var results := {"success": HTTPRequest.RESULT_SUCCESS, "timeout": HTTPRequest.RESULT_TIMEOUT,
		"body_limit": HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "connection_error": HTTPRequest.RESULT_CANT_CONNECT}
	request_completed.emit(results[response[0]], int(response[1]), PackedStringArray(), Marshalls.base64_to_raw(response[2]))

func _exit_tree() -> void:
	cancel_request()
