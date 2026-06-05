@tool
extends Node

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")

const LocalVariableInliningUseCase := preload("res://addons/smart-editor-plugin/features/local_variable_inlining/use_case.gd")

var _code: CodeEdit
var _script_path := ""
var _uri := ""
var _symbol := ""
var _symbol_line := 0
var _symbol_column := 0
var _lsp := LspClient.new()
var _queued := false
var _use_case := LocalVariableInliningUseCase.new()


func _enter_tree() -> void:
	_lsp.configure("Inline Variable", SmartEditorSettings.HOST, SmartEditorSettings.PORT)
	set_process_shortcut_input(true)
	set_process(true)


func _exit_tree() -> void:
	_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	_process_connection()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_INLINE_SHORTCUT, event):
		_begin_inline()
		get_viewport().set_input_as_handled()


func _begin_inline() -> void:
	_code = _get_current_code_edit()
	if _code == null:
		return

	_script_path = _get_current_script_path()
	if _script_path.is_empty():
		print("Inline Variable: could not resolve current script path.")
		return

	var symbol_range := _get_symbol_range_under_caret(_code)
	if symbol_range.is_empty():
		print("Inline Variable: place the caret on a local variable.")
		return

	_symbol = symbol_range["symbol"]
	_symbol_line = symbol_range["line"]
	_symbol_column = symbol_range["column"]

	_uri = LspClient.path_to_file_uri(ProjectSettings.globalize_path(_script_path))
	_queued = true

	if _ensure_connection():
		_try_send_references_request()


func _process_connection() -> void:
	if _lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses := _lsp.poll()
	for response in responses:
		_handle_response(response)
	_try_send_references_request()


func _ensure_connection() -> bool:
	var connected := _lsp.ensure_connection(true)
	if not connected:
		print("Inline Variable: could not connect to the code analysis service.")
	return connected


func _try_send_references_request() -> void:
	if not _queued or not _lsp.is_initialized():
		return
	if _lsp.has_pending_kind("references"):
		return

	_send_document_sync_notification()
	_lsp.send_request("references", "textDocument/references", {
		"textDocument": {
			"uri": _uri,
		},
		"position": {
			"line": _symbol_line,
			"character": _symbol_column,
		},
		"context": {
			"includeDeclaration": true,
		},
	})


func _send_document_sync_notification() -> void:
	_lsp.sync_document(_uri, _get_code_text(_code))


func _handle_response(response: Dictionary) -> void:
	var request_kind := str(response.get("kind", ""))
	var message: Dictionary = response.get("message", {})

	if message.has("error"):
		print("Inline Variable: request failed: %s" % JSON.stringify(message["error"]))
		return

	if request_kind == "references":
		_apply_from_references(message.get("result", []))
		_queued = false


func _apply_from_references(references: Variant) -> void:
	var plan := _use_case.build_inline_plan(
		_get_code_text(_code),
		_uri,
		_symbol,
		_symbol_line,
		_symbol_column,
		references
	)
	if plan.has("error"):
		print("Inline Variable: %s" % str(plan["error"]))
		return

	var edits: Array = plan["edits"]
	_symbol_line = int(plan["declaration_line"])

	_code.begin_complex_operation()
	for edit in edits:
		_replace_range_in_code(
			_code,
			edit["line"],
			edit["from_col"],
			edit["line"],
			edit["to_col"],
			str(edit["replacement"])
		)
	_code.remove_line_at(_symbol_line)
	_code.end_complex_operation()
	_code.deselect()


func _replace_range_in_code(code: CodeEdit, from_line: int, from_col: int, to_line: int, to_col: int, new_text: String) -> void:
	if from_line == to_line:
		var line := code.get_line(from_line)
		code.set_line(from_line, line.substr(0, from_col) + new_text + line.substr(to_col))
		return

	var first_line := code.get_line(from_line)
	var last_line := code.get_line(to_line)
	var replacement_lines := new_text.split("\n")

	code.set_line(from_line, first_line.substr(0, from_col) + replacement_lines[0])
	for index in range(1, replacement_lines.size()):
		code.insert_line_at(from_line + index, replacement_lines[index])

	var final_line := from_line + replacement_lines.size() - 1
	code.set_line(final_line, code.get_line(final_line) + last_line.substr(to_col))
	for line_index in range(to_line + replacement_lines.size() - 1, final_line, -1):
		code.remove_line_at(line_index)


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


func _get_symbol_range_under_caret(code: CodeEdit) -> Dictionary:
	var symbol_range := SymbolUsageModel.symbol_range_in_line(
		code.get_line(code.get_caret_line()),
		code.get_caret_line(),
		code.get_caret_column()
	)
	if symbol_range.is_empty():
		return {}

	return {
		"symbol": symbol_range["symbol"],
		"line": symbol_range["line"],
		"column": symbol_range["column"],
	}
