@tool
extends Node

const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")
const SmartEditorLspPendingRequest := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_pending_request.gd")
const SmartEditorLspResponse := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_response.gd")
const SmartEditorLspTransport := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_transport.gd")

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 6005
const PREWARM_RETRY_USEC := 1_000_000

var _host := DEFAULT_HOST
var _port := DEFAULT_PORT
var _transport = SmartEditorLspTransport.new()
var _pending_requests := {}
var _next_id := 1
var _initialized := false
var _initialize_request_id := -1
var _prewarm_pending := true
var _last_prewarm_attempt_usec := 0
var _opened_documents := {}
var _document_versions := {}
var _document_text_signatures := {}


func configure(host: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> void:
	_host = host
	_port = port


func _enter_tree() -> void:
	set_process(true)


func _exit_tree() -> void:
	_transport.disconnect_from_host()


func _process(_delta: float) -> void:
	_prewarm_lsp_connection()
	_process_lsp_messages()


func ensure_ready():
	if _is_ready():
		return SmartEditorLspResponse.success(true)

	if not _ensure_connection(true):
		return SmartEditorLspResponse.failure("could not connect to the code analysis service")

	_send_initialize_request_if_needed()
	while is_inside_tree() and not _initialized:
		await get_tree().process_frame
		if _is_ready():
			break
		if _transport.get_status() == StreamPeerTCP.STATUS_NONE:
			if not _ensure_connection(true):
				return SmartEditorLspResponse.failure("could not connect to the code analysis service")
		_send_initialize_request_if_needed()

	if not _is_ready():
		return SmartEditorLspResponse.failure("code analysis service is not initialized")

	return SmartEditorLspResponse.success(true)


func sync_document(uri: String, text: String, language_id: String = "gdscript"):
	if uri.is_empty():
		return false

	var ready_response = await ensure_ready()
	if not ready_response.ok:
		return false

	return _sync_document_now(uri, text, language_id)


func sync_open_scripts():
	var synced_any := false
	var ready_response = await ensure_ready()
	if not ready_response.ok:
		return false

	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return false

	# Godot's C++ ScriptEditorBase can expose its edited resource, but that API is
	# not available from GDScript. Pairing these two arrays is the only public
	# editor API path we have for mapping an open Script to its CodeEdit.
	var scripts: Array = script_editor.get_open_scripts()
	var code_editors := _open_code_editors(script_editor)
	var entry_count := mini(scripts.size(), code_editors.size())

	for index in entry_count:
		var script_value: Variant = scripts[index]
		if not script_value is Script:
			continue

		var script: Script = script_value
		var script_path := _valid_script_path(script)
		if script_path.is_empty():
			continue

		var code: CodeEdit = code_editors[index]
		if code == null:
			continue

		var uri := SmartEditorFiles.path_to_file_uri(ProjectSettings.globalize_path(script_path))
		if _sync_document_now(uri, _get_code_text(code)):
			synced_any = true

	return synced_any


func prepare_rename(uri: String, line: int, column: int):
	return await _send_request("prepare_rename", "textDocument/prepareRename", {
		"textDocument": {
			"uri": uri,
		},
		"position": {
			"line": line,
			"character": column,
		},
	})


func rename(uri: String, line: int, column: int, new_name: String):
	return await _send_request("rename", "textDocument/rename", {
		"textDocument": {
			"uri": uri,
		},
		"position": {
			"line": line,
			"character": column,
		},
		"newName": new_name,
	})


func references(uri: String, line: int, column: int, include_declaration: bool = true):
	return await _send_request("references", "textDocument/references", {
		"textDocument": {
			"uri": uri,
		},
		"position": {
			"line": line,
			"character": column,
		},
		"context": {
			"includeDeclaration": include_declaration,
		},
	})


func document_highlight(uri: String, line: int, column: int):
	return await _send_request("document_highlight", "textDocument/documentHighlight", {
		"textDocument": {
			"uri": uri,
		},
		"position": {
			"line": line,
			"character": column,
		},
	})


func _send_request(kind: String, method: String, params: Dictionary):
	var ready_response = await ensure_ready()
	if not ready_response.ok:
		return ready_response

	var pending_request = SmartEditorLspPendingRequest.create(kind)
	var request_id := _send_request_message(method, params)
	_pending_requests[request_id] = pending_request
	return await pending_request.completed


func _send_request_message(method: String, params: Dictionary) -> int:
	var request_id := _next_request_id()
	_transport.send_message({
		"jsonrpc": "2.0",
		"id": request_id,
		"method": method,
		"params": params,
	})
	return request_id


func _send_notification(method: String, params: Dictionary) -> void:
	_transport.send_message({
		"jsonrpc": "2.0",
		"method": method,
		"params": params,
	})


func _process_lsp_messages() -> void:
	var status := _transport.get_status()
	if status == StreamPeerTCP.STATUS_NONE:
		return

	var messages: Array = _transport.poll()
	if _transport.get_status() == StreamPeerTCP.STATUS_NONE:
		_reset_protocol_state()
		return

	if _transport.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_send_initialize_request_if_needed()

	for message in messages:
		_handle_lsp_message(message)


func _handle_lsp_message(message: Dictionary) -> void:
	if not message.has("id"):
		return

	var request_id := SmartEditorLspTransport.normalize_response_id(message.get("id", -1))
	if request_id == _initialize_request_id:
		_handle_initialize_response(message)
		return

	if not _pending_requests.has(request_id):
		return

	var pending_request = _pending_requests[request_id]
	_pending_requests.erase(request_id)

	if message.has("error"):
		pending_request.complete(SmartEditorLspResponse.failure(message["error"]))
		return

	pending_request.complete(SmartEditorLspResponse.success(message.get("result", null)))


func _handle_initialize_response(message: Dictionary) -> void:
	_initialize_request_id = -1
	if message.has("error"):
		_initialized = false
		_prewarm_pending = true
		return

	_initialized = true
	_prewarm_pending = false
	_send_notification("initialized", {})


func _prewarm_lsp_connection() -> void:
	if not _prewarm_pending:
		return
	if _is_ready():
		_prewarm_pending = false
		return
	if _has_pending_requests():
		return

	var status := _transport.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_send_initialize_request_if_needed()
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return

	var now := Time.get_ticks_usec()
	if _last_prewarm_attempt_usec > 0 and now - _last_prewarm_attempt_usec < PREWARM_RETRY_USEC:
		return

	_last_prewarm_attempt_usec = now
	_ensure_connection(false)


func _ensure_connection(_report_errors: bool = false) -> bool:
	var status := _transport.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return true

	_reset_protocol_state()
	return _transport.connect_to_host(_host, _port)


func _send_initialize_request_if_needed() -> void:
	if _initialized or _initialize_request_id != -1:
		return
	if _transport.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var root_path := ProjectSettings.globalize_path("res://")
	var root_uri := SmartEditorFiles.path_to_file_uri(root_path)
	_initialize_request_id = _send_request_message("initialize", {
		"processId": OS.get_process_id(),
		"rootUri": root_uri,
		"capabilities": _capabilities(),
		"workspaceFolders": [{
			"uri": root_uri,
			"name": ProjectSettings.get_setting("application/config/name", "Godot Project"),
		}],
	})


func _capabilities() -> Dictionary:
	return {
		"workspace": {
			"applyEdit": true,
		},
		"textDocument": {
			"rename": {
				"dynamicRegistration": false,
				"prepareSupport": true,
			},
			"references": {
				"dynamicRegistration": false,
			},
			"documentHighlight": {
				"dynamicRegistration": false,
			},
		},
	}


func _sync_document_now(uri: String, text: String, language_id: String = "gdscript") -> bool:
	var signature := SmartEditorLspTransport.text_signature(text)
	if _opened_documents.has(uri) and str(_document_text_signatures.get(uri, "")) == signature:
		return false

	var version := int(_document_versions.get(uri, 0)) + 1
	_document_versions[uri] = version

	if not _opened_documents.has(uri):
		_opened_documents[uri] = true
		_document_text_signatures[uri] = signature
		_send_notification("textDocument/didOpen", {
			"textDocument": {
				"uri": uri,
				"languageId": language_id,
				"version": version,
				"text": text,
			},
		})
		return true

	_document_text_signatures[uri] = signature
	_send_notification("textDocument/didChange", {
		"textDocument": {
			"uri": uri,
			"version": version,
		},
		"contentChanges": [{
			"text": text,
		}],
	})
	return true


func _is_ready() -> bool:
	return _initialized and _transport.get_status() == StreamPeerTCP.STATUS_CONNECTED


func _has_pending_requests() -> bool:
	return _initialize_request_id != -1 or not _pending_requests.is_empty()


func _reset_protocol_state() -> void:
	_initialize_request_id = -1
	_initialized = false
	_opened_documents.clear()
	_document_versions.clear()
	_document_text_signatures.clear()

	for pending_request in _pending_requests.values():
		pending_request.complete(SmartEditorLspResponse.failure("code analysis service disconnected"))
	_pending_requests.clear()


func _next_request_id() -> int:
	var request_id := _next_id
	_next_id += 1
	return request_id


func _open_code_editors(script_editor: ScriptEditor) -> Array[CodeEdit]:
	var code_editors: Array[CodeEdit] = []
	var editors: Array = script_editor.get_open_script_editors()

	for editor in editors:
		if editor == null:
			code_editors.append(null)
			continue

		var code: CodeEdit = null
		var base: Variant = editor.get_base_editor()
		if base is CodeEdit:
			code = base
		code_editors.append(code)

	return code_editors


func _valid_script_path(script: Script) -> String:
	if script == null:
		return ""

	var script_path := str(script.resource_path)
	if script_path.is_empty() or script_path.contains("::"):
		return ""
	if script_path.get_extension() != "gd":
		return ""

	return script_path


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


func set_transport_for_test(transport) -> void:
	_transport = transport


func process_lsp_messages_for_test() -> void:
	_process_lsp_messages()


func send_request_for_test(kind: String, method: String, params: Dictionary):
	var pending_request = SmartEditorLspPendingRequest.create(kind)
	var request_id := _send_request_message(method, params)
	_pending_requests[request_id] = pending_request
	return pending_request
