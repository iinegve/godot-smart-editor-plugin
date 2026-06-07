@tool
extends Node

const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const SmartEditorLspPendingRequest := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_pending_request.gd")
const SmartEditorLspResponse := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_response.gd")

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 6005
const PREWARM_RETRY_USEC := 1_000_000

var _host := DEFAULT_HOST
var _port := DEFAULT_PORT
var _lsp = LspClient.new()
var _pending_requests := {}
var _prewarm_pending := true
var _last_prewarm_attempt_usec := 0


func configure(host: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> void:
	_host = host
	_port = port
	_configure_lsp_client()


func _enter_tree() -> void:
	_configure_lsp_client()
	set_process(true)


func _exit_tree() -> void:
	_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	_prewarm_lsp_connection()
	_process_lsp_messages()


func ensure_ready():
	if _lsp.is_initialized():
		return SmartEditorLspResponse.success(true)

	if not _lsp.ensure_connection(true):
		return SmartEditorLspResponse.failure("could not connect to the code analysis service")

	while is_inside_tree() and not _lsp.is_initialized():
		await get_tree().process_frame
		if _lsp.get_status() == StreamPeerTCP.STATUS_NONE:
			if not _lsp.ensure_connection(true):
				return SmartEditorLspResponse.failure("could not connect to the code analysis service")

	return SmartEditorLspResponse.success(true)


func sync_document(uri: String, text: String, language_id: String = "gdscript"):
	if uri.is_empty():
		return false

	var ready_response = await ensure_ready()
	if not ready_response.ok:
		return false

	return _lsp.sync_document(uri, text, language_id)


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

		var uri := LspClient.path_to_file_uri(ProjectSettings.globalize_path(script_path))
		if _lsp.sync_document(uri, _get_code_text(code)):
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


func _configure_lsp_client() -> void:
	_lsp.configure("Smart Editor", _host, _port, {
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
		},
	})


func _send_request(kind: String, method: String, params: Dictionary):
	var ready_response = await ensure_ready()
	if not ready_response.ok:
		return ready_response

	var pending_request = SmartEditorLspPendingRequest.create(kind)
	var request_id: int = _lsp.send_request(kind, method, params)
	if request_id == -1:
		return SmartEditorLspResponse.failure("code analysis service is not initialized")

	_pending_requests[request_id] = pending_request
	return await pending_request.completed


func _process_lsp_messages() -> void:
	if _lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses: Array = _lsp.poll()
	if _lsp.is_initialized():
		_prewarm_pending = false

	for response in responses:
		_handle_lsp_response(response)


func _handle_lsp_response(response: Dictionary) -> void:
	var message: Dictionary = response.get("message", {})
	var request_id := LspClient.normalize_response_id(message.get("id", -1))
	if not _pending_requests.has(request_id):
		return

	var pending_request = _pending_requests[request_id]
	_pending_requests.erase(request_id)

	if message.has("error"):
		pending_request.complete(SmartEditorLspResponse.failure(message["error"]))
		return

	pending_request.complete(SmartEditorLspResponse.success(message.get("result", null)))


func _prewarm_lsp_connection() -> void:
	if not _prewarm_pending:
		return
	if _lsp.is_initialized():
		_prewarm_pending = false
		return
	if _lsp.has_pending_requests():
		return

	var status := _lsp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return

	var now := Time.get_ticks_usec()
	if _last_prewarm_attempt_usec > 0 and now - _last_prewarm_attempt_usec < PREWARM_RETRY_USEC:
		return

	_last_prewarm_attempt_usec = now
	_lsp.ensure_connection(false)


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


func set_lsp_client_for_test(lsp_client) -> void:
	_lsp = lsp_client


func process_lsp_messages_for_test() -> void:
	_process_lsp_messages()


func send_request_for_test(kind: String, method: String, params: Dictionary):
	var pending_request = SmartEditorLspPendingRequest.create(kind)
	var request_id: int = _lsp.send_request(kind, method, params)
	_pending_requests[request_id] = pending_request
	return pending_request
