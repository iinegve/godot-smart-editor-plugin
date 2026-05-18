@tool
extends RefCounted

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 6005

var _name := "LSP"
var _host := DEFAULT_HOST
var _port := DEFAULT_PORT
var _capabilities := {}
var _debug_callback := Callable()
var _tcp := StreamPeerTCP.new()
var _read_buffer := PackedByteArray()
var _next_id := 1
var _pending_requests := {}
var _initialized := false
var _last_status := StreamPeerTCP.STATUS_NONE
var _opened_documents := {}
var _document_versions := {}
var _document_text_signatures := {}


func configure(name: String, host: String = DEFAULT_HOST, port: int = DEFAULT_PORT, capabilities: Dictionary = {}, debug_callback: Callable = Callable()) -> void:
	_name = name
	_host = host
	_port = port
	_capabilities = capabilities
	_debug_callback = debug_callback


func poll() -> Array[Dictionary]:
	var responses: Array[Dictionary] = []
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE:
		return responses

	_tcp.poll()
	var status := _tcp.get_status()
	if status != _last_status:
		_debug("TCP status changed to %d." % status)
		_last_status = status

	if status == StreamPeerTCP.STATUS_CONNECTED:
		responses.append_array(_read_available_messages())
		if not _initialized and not has_pending_kind("initialize"):
			_send_initialize_request()
	elif status == StreamPeerTCP.STATUS_ERROR:
		_debug("connection error.")
		reset()

	return responses


func ensure_connection(report_errors: bool = false) -> bool:
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return true

	reset()
	var err := _tcp.connect_to_host(_host, _port)
	if err != OK:
		if report_errors:
			_debug("could not connect to the code analysis service, error %d." % err)
		return false

	_debug("connecting to code analysis service at %s:%d..." % [_host, _port])
	return true


func send_request(kind: String, method: String, params: Dictionary, context: Dictionary = {}) -> int:
	if not _initialized:
		return -1

	var id := _next_request_id()
	_pending_requests[id] = {
		"kind": kind,
		"context": context,
	}
	_send_message({
		"jsonrpc": "2.0",
		"id": id,
		"method": method,
		"params": params,
	})
	return id


func send_notification(method: String, params: Dictionary) -> void:
	_send_message({
		"jsonrpc": "2.0",
		"method": method,
		"params": params,
	})


func sync_document(uri: String, text: String, language_id: String = "gdscript") -> bool:
	var signature := text_signature(text)
	if _opened_documents.has(uri) and str(_document_text_signatures.get(uri, "")) == signature:
		return false

	var version := int(_document_versions.get(uri, 0)) + 1
	_document_versions[uri] = version

	if not _opened_documents.has(uri):
		_opened_documents[uri] = true
		_document_text_signatures[uri] = signature
		send_notification("textDocument/didOpen", {
			"textDocument": {
				"uri": uri,
				"languageId": language_id,
				"version": version,
				"text": text,
			},
		})
		return true

	_document_text_signatures[uri] = signature
	send_notification("textDocument/didChange", {
		"textDocument": {
			"uri": uri,
			"version": version,
		},
		"contentChanges": [{
			"text": text,
		}],
	})
	return true


func is_initialized() -> bool:
	return _initialized


func get_status() -> int:
	return _tcp.get_status()


func has_pending_kind(kind: String) -> bool:
	for request in _pending_requests.values():
		if typeof(request) == TYPE_DICTIONARY and str(request.get("kind", "")) == kind:
			return true
	return false


func has_pending_requests() -> bool:
	return not _pending_requests.is_empty()


func reset() -> void:
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_read_buffer.clear()
	_pending_requests.clear()
	_initialized = false
	_last_status = StreamPeerTCP.STATUS_NONE
	_opened_documents.clear()
	_document_versions.clear()
	_document_text_signatures.clear()


func disconnect_from_host() -> void:
	_tcp.disconnect_from_host()


func _send_initialize_request() -> void:
	var root_path := ProjectSettings.globalize_path("res://")
	var root_uri := path_to_file_uri(root_path)
	var id := _next_request_id()
	_pending_requests[id] = {
		"kind": "initialize",
		"context": {},
	}

	_send_message({
		"jsonrpc": "2.0",
		"id": id,
		"method": "initialize",
		"params": {
			"processId": OS.get_process_id(),
			"rootUri": root_uri,
			"capabilities": _capabilities,
			"workspaceFolders": [{
				"uri": root_uri,
				"name": ProjectSettings.get_setting("application/config/name", "Godot Project"),
			}],
		},
	})


func _send_initialized_notification() -> void:
	send_notification("initialized", {})


func _send_message(message: Dictionary) -> void:
	var body := JSON.stringify(message)
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
	var err := _tcp.put_data(packet.to_utf8_buffer())
	if err != OK:
		_debug("failed sending request, error %d." % err)


func _read_available_messages() -> Array[Dictionary]:
	var responses: Array[Dictionary] = []
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return responses

	var read_result := _tcp.get_data(available)
	if read_result[0] != OK:
		_debug("failed reading response.")
		return responses

	_read_buffer.append_array(read_result[1])
	while true:
		var body := try_extract_lsp_body(_read_buffer)
		if body.is_empty():
			return responses

		_read_buffer = consume_lsp_message(_read_buffer)
		var message = JSON.parse_string(body)
		if typeof(message) == TYPE_DICTIONARY:
			var response := _handle_message(message)
			if not response.is_empty():
				responses.append(response)

	return responses


func _handle_message(message: Dictionary) -> Dictionary:
	if not message.has("id"):
		return {}

	var id := normalize_response_id(message["id"])
	if not _pending_requests.has(id):
		return {}

	var request: Dictionary = _pending_requests[id]
	_pending_requests.erase(id)

	if request.get("kind", "") == "initialize":
		if not message.has("error"):
			_initialized = true
			_send_initialized_notification()
		return {}

	return {
		"kind": str(request.get("kind", "")),
		"context": request.get("context", {}),
		"message": message,
	}


func _next_request_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _debug(message: String) -> void:
	if _debug_callback.is_valid():
		_debug_callback.call(message)


static func try_extract_lsp_body(buffer: PackedByteArray) -> String:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := find_bytes(buffer, marker)
	if header_end == -1:
		return ""

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := parse_content_length(header)
	if content_length <= 0:
		return ""

	var body_start := header_end + marker.size()
	var body_end := body_start + content_length
	if buffer.size() < body_end:
		return ""

	return buffer.slice(body_start, body_end).get_string_from_utf8()


static func consume_lsp_message(buffer: PackedByteArray) -> PackedByteArray:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := find_bytes(buffer, marker)
	if header_end == -1:
		return buffer

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := parse_content_length(header)
	if content_length <= 0:
		return buffer.slice(header_end + marker.size())

	var body_end := header_end + marker.size() + content_length
	if buffer.size() < body_end:
		return buffer

	return buffer.slice(body_end)


static func find_bytes(buffer: PackedByteArray, needle: PackedByteArray) -> int:
	for index in range(0, buffer.size() - needle.size() + 1):
		var found := true
		for needle_index in needle.size():
			if buffer[index + needle_index] != needle[needle_index]:
				found = false
				break
		if found:
			return index

	return -1


static func parse_content_length(header: String) -> int:
	for line in header.split("\r\n"):
		var parts := line.split(":", false, 1)
		if parts.size() == 2 and parts[0].strip_edges().to_lower() == "content-length":
			return parts[1].strip_edges().to_int()

	return -1


static func path_to_file_uri(path: String) -> String:
	return "file://" + path.uri_encode().replace("%2F", "/")


static func file_uri_to_path(uri: String) -> String:
	return uri.trim_prefix("file://").uri_decode()


static func normalize_response_id(id: Variant) -> int:
	if typeof(id) == TYPE_FLOAT:
		return int(id)
	if typeof(id) == TYPE_INT:
		return id

	return str(id).to_int()


static func text_signature(text: String) -> String:
	return "%d:%d" % [text.length(), text.hash()]
