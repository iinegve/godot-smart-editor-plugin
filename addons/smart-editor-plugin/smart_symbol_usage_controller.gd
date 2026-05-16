@tool
extends Node

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/smart_symbol_usage_model.gd")
const SymbolUsageStripe := preload("res://addons/smart-editor-plugin/smart_symbol_usage_stripe.gd")
const STRIPE_WIDTH := 8.0
const DEBOUNCE_SECONDS := 0.25

var _enabled_setting: StringName = &""
var _debug_setting: StringName = &""
var _host := "127.0.0.1"
var _port := 6005
var _script_editor = null
var _code: CodeEdit
var _stripe = null
var _script_path := ""
var _uri := ""
var _refresh_pending := false
var _debounce_remaining := 0.0
var _current_symbol_key := ""
var _request_generation := 0

var _tcp := StreamPeerTCP.new()
var _read_buffer := PackedByteArray()
var _next_id := 1
var _pending_requests := {}
var _queued_request := {}
var _initialized := false
var _last_status := StreamPeerTCP.STATUS_NONE
var _opened_documents := {}
var _document_versions := {}


func configure(enabled_setting: StringName, debug_setting: StringName, host: String, port: int) -> void:
	_enabled_setting = enabled_setting
	_debug_setting = debug_setting
	_host = host
	_port = port
	set_process(true)
	_connect_script_editor()
	_attach_to_current_code_edit()
	_schedule_refresh()


func _exit_tree() -> void:
	_disconnect_script_editor()
	_detach_code_edit()
	_tcp.disconnect_from_host()


func _process(delta: float) -> void:
	if _enabled_setting == &"":
		return

	if not _is_enabled():
		_disable_feature()
		return

	_connect_script_editor()
	_attach_to_current_code_edit()
	_layout_stripe()
	_process_connection()

	if _refresh_pending:
		_debounce_remaining -= delta
		if _debounce_remaining <= 0.0:
			_refresh_pending = false
			_refresh_references()


func _connect_script_editor() -> void:
	if _script_editor != null and is_instance_valid(_script_editor):
		return

	_script_editor = EditorInterface.get_script_editor()
	if _script_editor == null or not _script_editor.has_signal("editor_script_changed"):
		return

	if not _script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.connect(_on_editor_script_changed)


func _disconnect_script_editor() -> void:
	if _script_editor == null or not is_instance_valid(_script_editor):
		_script_editor = null
		return

	if _script_editor.has_signal("editor_script_changed") and _script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	_script_editor = null


func _attach_to_current_code_edit() -> void:
	var next_code := _get_current_code_edit()
	var next_script_path := _get_current_script_path()
	if next_code == _code and next_script_path == _script_path:
		return

	_detach_code_edit()
	_code = next_code
	_script_path = next_script_path
	_uri = _path_to_file_uri(ProjectSettings.globalize_path(_script_path)) if not _script_path.is_empty() else ""

	if _code == null:
		return

	_code.caret_changed.connect(_on_code_caret_changed)
	_code.text_changed.connect(_on_code_text_changed)
	_code.resized.connect(_on_code_resized)

	_stripe = SymbolUsageStripe.new()
	_stripe.name = "SmartSymbolUsageStripe"
	_stripe.usage_clicked.connect(_on_stripe_usage_clicked)
	_code.add_child(_stripe)
	_layout_stripe()
	_schedule_refresh()


func _detach_code_edit() -> void:
	if _code != null and is_instance_valid(_code):
		if _code.caret_changed.is_connected(_on_code_caret_changed):
			_code.caret_changed.disconnect(_on_code_caret_changed)
		if _code.text_changed.is_connected(_on_code_text_changed):
			_code.text_changed.disconnect(_on_code_text_changed)
		if _code.resized.is_connected(_on_code_resized):
			_code.resized.disconnect(_on_code_resized)

	if _stripe != null and is_instance_valid(_stripe):
		_stripe.queue_free()

	_code = null
	_stripe = null
	_script_path = ""
	_uri = ""
	_current_symbol_key = ""
	_refresh_pending = false
	_queued_request.clear()


func _disable_feature() -> void:
	if _code != null or _stripe != null:
		_detach_code_edit()
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_reset_connection()


func _schedule_refresh() -> void:
	_refresh_pending = true
	_debounce_remaining = DEBOUNCE_SECONDS


func _refresh_references() -> void:
	if _code == null or not is_instance_valid(_code) or _uri.is_empty():
		_clear_references()
		return

	var symbol_range := SymbolUsageModel.symbol_range_in_line(
		_code.get_line(_code.get_caret_line()),
		_code.get_caret_line(),
		_code.get_caret_column()
	)
	if symbol_range.is_empty():
		_current_symbol_key = ""
		_queued_request.clear()
		_clear_references()
		return

	var code_version := _code.get_version()
	var symbol_key := "%s:%s:%d:%d:%d" % [
		_uri,
		symbol_range["symbol"],
		symbol_range["line"],
		symbol_range["column"],
		code_version,
	]
	if symbol_key == _current_symbol_key:
		return

	_request_generation += 1
	_current_symbol_key = symbol_key
	_clear_references()
	_queued_request = {
		"request_kind": "references",
		"uri": _uri,
		"symbol": symbol_range["symbol"],
		"line": symbol_range["line"],
		"column": symbol_range["column"],
		"end_line": symbol_range["line"],
		"end_column": symbol_range["end_column"],
		"code_version": code_version,
		"generation": _request_generation,
	}

	if not _ensure_connection():
		_debug("could not connect to the code analysis service.")
		var fallback_request := _queued_request.duplicate()
		_queued_request.clear()
		_apply_fallback_references(fallback_request)
		return

	_try_send_references_request()


func _process_connection() -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	_tcp.poll()
	var status := _tcp.get_status()
	if status != _last_status:
		_debug("TCP status changed to %d." % status)
		_last_status = status

	if status == StreamPeerTCP.STATUS_CONNECTED:
		_read_available_messages()
		if not _initialized and not _has_pending_initialize_request():
			_send_initialize_request()
		_try_send_references_request()
	elif status == StreamPeerTCP.STATUS_ERROR:
		_debug("connection error.")
		_clear_references()
		_reset_connection()


func _ensure_connection() -> bool:
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return true

	_reset_connection()
	var err := _tcp.connect_to_host(_host, _port)
	if err != OK:
		return false

	_debug("connecting to code analysis service at %s:%d..." % [_host, _port])
	return true


func _send_initialize_request() -> void:
	var root_path := ProjectSettings.globalize_path("res://")
	var root_uri := _path_to_file_uri(root_path)
	var id := _next_request_id()
	_pending_requests[id] = "initialize"

	_send_message({
		"jsonrpc": "2.0",
		"id": id,
		"method": "initialize",
		"params": {
			"processId": OS.get_process_id(),
			"rootUri": root_uri,
			"capabilities": {
				"textDocument": {
					"references": {
						"dynamicRegistration": false,
					},
				},
			},
			"workspaceFolders": [{
				"uri": root_uri,
				"name": ProjectSettings.get_setting("application/config/name", "Godot Project"),
			}],
		},
	})


func _send_initialized_notification() -> void:
	_send_message({
		"jsonrpc": "2.0",
		"method": "initialized",
		"params": {},
	})


func _try_send_references_request() -> void:
	if _queued_request.is_empty() or not _initialized:
		return

	var request := _queued_request.duplicate()
	if not _request_matches_current(request):
		_queued_request.clear()
		return

	_send_document_sync_notification(request)

	var id := _next_request_id()
	_pending_requests[id] = request
	_queued_request.clear()

	_send_message({
		"jsonrpc": "2.0",
		"id": id,
		"method": "textDocument/references",
		"params": {
			"textDocument": {
				"uri": request["uri"],
			},
			"position": {
				"line": request["line"],
				"character": request["column"],
			},
			"context": {
				"includeDeclaration": true,
			},
		},
	})
	_debug("sent references request for '%s'." % request["symbol"])


func _send_document_sync_notification(request: Dictionary) -> void:
	var uri: String = request["uri"]
	var version := int(_document_versions.get(uri, 0)) + 1
	_document_versions[uri] = version

	if not _opened_documents.has(uri):
		_opened_documents[uri] = true
		_send_message({
			"jsonrpc": "2.0",
			"method": "textDocument/didOpen",
			"params": {
				"textDocument": {
					"uri": uri,
					"languageId": "gdscript",
					"version": version,
					"text": _get_code_text(_code),
				},
			},
		})
		return

	_send_message({
		"jsonrpc": "2.0",
		"method": "textDocument/didChange",
		"params": {
			"textDocument": {
				"uri": uri,
				"version": version,
			},
			"contentChanges": [{
				"text": _get_code_text(_code),
			}],
		},
	})


func _send_message(message: Dictionary) -> void:
	var body := JSON.stringify(message)
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
	var err := _tcp.put_data(packet.to_utf8_buffer())
	if err != OK:
		_debug("failed sending request, error %d." % err)


func _read_available_messages() -> void:
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return

	var read_result := _tcp.get_data(available)
	if read_result[0] != OK:
		_debug("failed reading response.")
		return

	_read_buffer.append_array(read_result[1])
	while true:
		var body := _try_extract_lsp_body(_read_buffer)
		if body.is_empty():
			return

		_read_buffer = _consume_lsp_message(_read_buffer)
		var message = JSON.parse_string(body)
		if typeof(message) == TYPE_DICTIONARY:
			_handle_message(message)


func _handle_message(message: Dictionary) -> void:
	if not message.has("id"):
		return

	var id := _normalize_response_id(message["id"])
	if not _pending_requests.has(id):
		return

	var request = _pending_requests[id]
	_pending_requests.erase(id)

	if message.has("error"):
		_debug("request failed: %s" % JSON.stringify(message["error"]))
		if typeof(request) == TYPE_DICTIONARY and _request_matches_current(request):
			_apply_fallback_references(request)
		return

	if _is_initialize_request(request):
		_initialized = true
		_send_initialized_notification()
		_try_send_references_request()
	elif typeof(request) == TYPE_DICTIONARY:
		var request_kind := str(request.get("request_kind", "references"))
		if request_kind == "references":
			_apply_references(message.get("result", []), request)


func _apply_references(references: Variant, request: Dictionary) -> void:
	if not _request_matches_current(request):
		_debug("dropped stale references response.")
		return

	var current_reference := {
		"line": int(request["line"]),
		"column": int(request["column"]),
		"end_line": int(request["end_line"]),
		"end_column": int(request["end_column"]),
	}
	var filtered_references := SymbolUsageModel.references_for_uri(references, request["uri"])
	if filtered_references.is_empty():
		_debug("references response had no usages in current file; using token fallback.")
		_apply_fallback_references(request)
		return

	_stripe.set_usage_references(filtered_references, _code.get_line_count(), current_reference)


func _apply_fallback_references(request: Dictionary) -> void:
	if not _request_matches_current(request):
		return

	var fallback_references := SymbolUsageModel.references_for_symbol_in_text(
		_get_code_text(_code),
		str(request.get("symbol", ""))
	)
	if fallback_references.is_empty():
		_debug("token fallback had no usages in current file.")
		_clear_references()
		return

	_stripe.set_usage_references(fallback_references, _code.get_line_count(), {
		"line": int(request["line"]),
		"column": int(request["column"]),
		"end_line": int(request["end_line"]),
		"end_column": int(request["end_column"]),
	})


func _request_matches_current(request: Dictionary) -> bool:
	if _code == null or not is_instance_valid(_code):
		return false
	if request.get("uri", "") != _uri:
		return false
	if int(request.get("code_version", -1)) != _code.get_version():
		return false

	var current_symbol := SymbolUsageModel.symbol_range_in_line(
		_code.get_line(_code.get_caret_line()),
		_code.get_caret_line(),
		_code.get_caret_column()
	)
	return (
		not current_symbol.is_empty()
		and current_symbol["symbol"] == request.get("symbol", "")
		and int(current_symbol["line"]) == int(request.get("line", -1))
		and int(current_symbol["column"]) == int(request.get("column", -1))
	)


func _on_editor_script_changed(_script: Script) -> void:
	_attach_to_current_code_edit()
	_schedule_refresh()


func _on_code_caret_changed() -> void:
	_schedule_refresh()


func _on_code_text_changed() -> void:
	_schedule_refresh()


func _on_code_resized() -> void:
	_layout_stripe()


func _on_stripe_usage_clicked(reference: Dictionary) -> void:
	if _code == null or not is_instance_valid(_code):
		return

	var line := clampi(int(reference["line"]), 0, max(0, _code.get_line_count() - 1))
	var column := clampi(int(reference["column"]), 0, _code.get_line(line).length())
	_code.set_caret_line(line)
	_code.set_caret_column(column)
	_code.center_viewport_to_caret()
	_code.grab_focus()


func _layout_stripe() -> void:
	if _code == null or _stripe == null or not is_instance_valid(_code) or not is_instance_valid(_stripe):
		return

	var scrollbar_width := 0.0
	var scrollbar := _code.get_v_scroll_bar()
	if scrollbar != null and scrollbar.visible:
		scrollbar_width = scrollbar.size.x

	_stripe.anchor_left = 1.0
	_stripe.anchor_right = 1.0
	_stripe.anchor_top = 0.0
	_stripe.anchor_bottom = 1.0
	_stripe.offset_left = -scrollbar_width - STRIPE_WIDTH
	_stripe.offset_right = -scrollbar_width
	_stripe.offset_top = 0.0
	_stripe.offset_bottom = 0.0
	_stripe.z_index = 20


func _clear_references() -> void:
	if _stripe != null and is_instance_valid(_stripe):
		_stripe.clear_references()


func _reset_connection() -> void:
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_read_buffer.clear()
	_pending_requests.clear()
	_queued_request.clear()
	_initialized = false
	_last_status = StreamPeerTCP.STATUS_NONE
	_opened_documents.clear()
	_document_versions.clear()


func _has_pending_initialize_request() -> bool:
	for request in _pending_requests.values():
		if _is_initialize_request(request):
			return true

	return false


static func _is_initialize_request(request: Variant) -> bool:
	return typeof(request) == TYPE_STRING and request == "initialize"


func _next_request_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _get_current_code_edit() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return null

	var current_editor := script_editor.get_current_editor()

	if current_editor == null:
		return null

	var base := current_editor.get_base_editor()
	if base is CodeEdit:
		return base

	return null


func _get_current_script_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""

	var current_script: Script = script_editor.get_current_script()
	if current_script != null:
		return current_script.resource_path

	return ""


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


func _try_extract_lsp_body(buffer: PackedByteArray) -> String:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := _find_bytes(buffer, marker)
	if header_end == -1:
		return ""

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := _parse_content_length(header)
	if content_length <= 0:
		return ""

	var body_start := header_end + marker.size()
	var body_end := body_start + content_length
	if buffer.size() < body_end:
		return ""

	return buffer.slice(body_start, body_end).get_string_from_utf8()


func _consume_lsp_message(buffer: PackedByteArray) -> PackedByteArray:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := _find_bytes(buffer, marker)
	if header_end == -1:
		return buffer

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := _parse_content_length(header)
	if content_length <= 0:
		return buffer.slice(header_end + marker.size())

	var body_end := header_end + marker.size() + content_length
	if buffer.size() < body_end:
		return buffer

	return buffer.slice(body_end)


func _find_bytes(buffer: PackedByteArray, needle: PackedByteArray) -> int:
	for index in range(0, buffer.size() - needle.size() + 1):
		var found := true
		for needle_index in needle.size():
			if buffer[index + needle_index] != needle[needle_index]:
				found = false
				break
		if found:
			return index

	return -1


func _parse_content_length(header: String) -> int:
	for line in header.split("\r\n"):
		var parts := line.split(":", false, 1)
		if parts.size() == 2 and parts[0].strip_edges().to_lower() == "content-length":
			return parts[1].strip_edges().to_int()

	return -1


func _path_to_file_uri(path: String) -> String:
	return "file://" + path.uri_encode().replace("%2F", "/")


func _normalize_response_id(id: Variant) -> int:
	if typeof(id) == TYPE_FLOAT:
		return int(id)
	if typeof(id) == TYPE_INT:
		return id

	return str(id).to_int()


func _is_enabled() -> bool:
	var settings = _get_editor_settings()
	if settings == null:
		return true
	if not settings.has_setting(_enabled_setting):
		return true
	return bool(settings.get_setting(_enabled_setting))


func _debug_logs_enabled() -> bool:
	var settings = _get_editor_settings()
	if settings == null:
		return false
	if _debug_setting == &"" or not settings.has_setting(_debug_setting):
		return false
	return bool(settings.get_setting(_debug_setting))


func _get_editor_settings():
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton("EditorInterface"):
		return null

	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_editor_settings"):
		return null

	return editor_interface.get_editor_settings()


func _debug(message: String) -> void:
	if _debug_logs_enabled():
		print("Symbol Usage Stripe: " + message)
