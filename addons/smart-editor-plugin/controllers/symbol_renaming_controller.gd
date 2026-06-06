@tool
extends Node

const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")
const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")
const RenameEditSet := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_edit_set.gd")
const RenameFileEdits := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_file_edits.gd")
const RenameModifiedClosedFile := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_modified_closed_file.gd")
const RenameModifiedOpenFile := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_modified_open_file.gd")
const RenameOpenScriptBuffer := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffer.gd")
const RenameOpenScriptBuffers := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffers.gd")
const RenameRequest := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_request.gd")
const RenameSymbolTarget := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_symbol_target.gd")
const RenameTextEdit := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_text_edit.gd")

const IDENTIFIER_DIALOG_WIDTH := 800
const IDENTIFIER_DIALOG_HEIGHT := 150
const RENAME_PREWARM_RETRY_USEC := 1_000_000

var _rename_code: CodeEdit

var _rename_lsp := LspClient.new()
var _rename_request: RenameRequest = RenameRequest.new()
var _rename_prewarm_pending := false
var _rename_last_prewarm_attempt_usec := 0
var _identifier_validator := GDScriptIdentifierValidator.new()


func _enter_tree() -> void:
	_configure_lsp_client()
	_rename_prewarm_pending = true
	set_process_shortcut_input(true)
	set_process(true)


func _configure_lsp_client() -> void:
	_rename_lsp.configure("Rename Symbol", SmartEditorSettings.HOST, SmartEditorSettings.PORT, {
		"workspace": {
			"applyEdit": true,
		},
		"textDocument": {
			"rename": {
				"dynamicRegistration": false,
				"prepareSupport": true,
			},
		},
	})


func _exit_tree() -> void:
	_rename_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	_prewarm_lsp_connection()
	_process_connection()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_RENAME_SHORTCUT, event):
		_begin_rename()
		get_viewport().set_input_as_handled()

func _begin_rename() -> void:
	_rename_code = _get_current_code_edit()
	if _rename_code == null:
		return

	var script_path := _get_current_script_path()
	if script_path.is_empty():
		print("Rename Symbol: could not resolve current script path.")
		return
	var target_uri := _path_to_file_uri(ProjectSettings.globalize_path(script_path))

	var symbol_target := _get_selected_or_current_symbol_range(_rename_code)
	if symbol_target.is_empty():
		print("Rename Symbol: place the caret inside an identifier.")
		return

	_create_rename_dialog(symbol_target.symbol, target_uri, symbol_target.line, symbol_target.column)
	pass


func _create_rename_dialog(rename_symbol: String, target_uri: String, line: int, column: int) -> void:
	var _rename_dialog = ConfirmationDialog.new()

	var _rename_prompt_label = Label.new()
	_rename_prompt_label.text = "Rename '%s' to:" % rename_symbol

	var _rename_error_label := Label.new()
	_rename_error_label.visible = false
	_rename_error_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_error_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_rename_error_label.text = " "
	_rename_error_label.visible = true

	var _rename_name_edit = LineEdit.new()
	_rename_name_edit.placeholder_text = "New identifier"
	_rename_name_edit.text_changed.connect(func(new_name: String):
		var validation_error = _identifier_validation_error(new_name, rename_symbol)
		_set_identifier_validation_state(_rename_dialog, _rename_error_label, validation_error)
	)
	_rename_name_edit.text = rename_symbol
	_rename_name_edit.select_all()

	_rename_dialog.title = "Rename Symbol"
	_rename_dialog.ok_button_text = "Rename"
	_rename_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_rename_dialog.confirmed.connect(func():
		_apply_rename(_rename_name_edit.text, rename_symbol, target_uri, line, column)
		_rename_dialog.queue_free()
	)
	_rename_dialog.canceled.connect(func(): 
		_rename_dialog.queue_free()
	)
	_rename_dialog.close_requested.connect(func():
		_rename_dialog.queue_free()
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_rename_prompt_label)
	box.add_child(_rename_name_edit)
	_rename_dialog.register_text_enter(_rename_name_edit)
	box.add_child(_rename_error_label)

	_rename_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_rename_dialog)

	var validation_error = _identifier_validation_error(_rename_name_edit.text, rename_symbol)
	_set_identifier_validation_state(_rename_dialog, _rename_error_label, validation_error)
	_rename_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_rename_dialog.popup_centered(Vector2i(_identifier_dialog_width(), IDENTIFIER_DIALOG_HEIGHT))

	_rename_name_edit.grab_focus()
	pass


func _identifier_dialog_width() -> int:
	var dialog_width = int(SmartEditorSettings.get_setting(SmartEditorSettings.SETTING_DIALOG_WIDTH, 420))
	return maxi(dialog_width, IDENTIFIER_DIALOG_WIDTH)


func _apply_rename(
	new_text: String, original_text: String, 
	target_uri: String, line: int, column: int
) -> void:
	var replacement := new_text.strip_edges()
	if replacement == original_text:
		return

	_rename_request.configure(target_uri, line, column, replacement)

	if _ensure_connection():
		_try_send_request()


func _set_identifier_validation_state(dialog: ConfirmationDialog, error_label: Label,	validation_error: String) -> void:
	error_label.text = validation_error
	error_label.visible = not validation_error.is_empty()
	dialog.get_ok_button().disabled = not validation_error.is_empty()


func _process_connection() -> void:
	if _rename_lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses := _rename_lsp.poll()
	if _rename_lsp.is_initialized():
		_rename_prewarm_pending = false
	for response in responses:
		_handle_response(response)
	_try_send_request()


func _prewarm_lsp_connection() -> void:
	if not _rename_prewarm_pending:
		return
	if _rename_lsp.is_initialized():
		_rename_prewarm_pending = false
		return
	if not _rename_request.is_empty() or _rename_lsp.has_pending_requests():
		return

	var status := _rename_lsp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return

	var now := Time.get_ticks_usec()
	if _rename_last_prewarm_attempt_usec > 0 and now - _rename_last_prewarm_attempt_usec < RENAME_PREWARM_RETRY_USEC:
		return
	_rename_last_prewarm_attempt_usec = now
	_ensure_connection(false)


func _ensure_connection(report_errors: bool = true) -> bool:
	var connected := _rename_lsp.ensure_connection(report_errors)
	if not connected and report_errors:
		print("Rename Symbol: could not connect to the code analysis service.")
	return connected


func _try_send_request() -> void:
	if _rename_request.is_empty() or not _rename_lsp.is_initialized():
		return
	
	var pending_prepare_rename = _rename_lsp.has_pending_kind("prepare_rename")
	var pending_rename = _rename_lsp.has_pending_kind("rename")
	if (pending_prepare_rename or pending_rename):
		return

	_send_open_document_sync_notifications()
	_send_prepare_rename_request()


func _send_prepare_rename_request() -> void:
	_rename_lsp.send_request("prepare_rename", "textDocument/prepareRename", {
		"textDocument": {
			"uri": _rename_request.uri,
		},
		"position": {
			"line": _rename_request.line,
			"character": _rename_request.column,
		},
	})


func _send_rename_request() -> void:
	_rename_lsp.send_request("rename", "textDocument/rename", {
		"textDocument": {
			"uri": _rename_request.uri,
		},
		"position": {
			"line": _rename_request.line,
			"character": _rename_request.column,
		},
		"newName": _rename_request.new_name,
	})


func _send_open_document_sync_notifications() -> void:
	var target_uri := _rename_request.uri
	var open_script_buffers := _open_script_buffers_by_uri()

	for open_script_buffer in open_script_buffers.buffers:
		var text := _get_code_text(open_script_buffer.code)
		_rename_lsp.sync_document(open_script_buffer.uri, text)

	if not target_uri.is_empty() and not open_script_buffers.has_uri(target_uri) and _rename_code != null:
		var target_text := _get_code_text(_rename_code)
		_rename_lsp.sync_document(target_uri, target_text)


func _handle_response(response: Dictionary) -> void:
	var request_kind := str(response.get("kind", ""))
	var message: Dictionary = response.get("message", {})

	if message.has("error"):
		if request_kind == "prepare_rename":
			print("Rename Symbol: prepareRename failed: %s" % JSON.stringify(message["error"]))
			_send_rename_request()
			return

		print("Rename Symbol: request failed: %s" % JSON.stringify(message["error"]))
		return

	if request_kind == "prepare_rename":
		_send_rename_request()
	elif request_kind == "rename":
		var rename_edits: RenameEditSet = RenameEditSet.from_lsp_workspace_edit(message.get("result", {}))
		_apply_rename_edits(rename_edits)
	_rename_request.clear()


func _apply_rename_edits(rename_edits: RenameEditSet) -> void:
	if rename_edits.is_empty():
		print("Rename Symbol: no changes found.")
		return

	var applied_edits := 0
	var any_file_written := false
	var open_script_buffers := _open_script_buffers_by_uri(rename_edits)
	var open_file_edits: Array[RenameFileEdits] = []
	var closed_file_edits: Array[RenameFileEdits] = []

	for file_edits in rename_edits.files:
		var uri_text := file_edits.uri
		if file_edits.edits.is_empty():
			continue

		if open_script_buffers.has_uri(uri_text):
			open_file_edits.append(file_edits)
		else:
			closed_file_edits.append(file_edits)

	var modified_open_buffers := _apply_open_rename_edits(open_file_edits, open_script_buffers)
	for open_item in modified_open_buffers:
		applied_edits += open_item.edit_count

	if _save_modified_open_buffers(modified_open_buffers):
		any_file_written = true

	var modified_closed_files := _apply_closed_rename_edits(closed_file_edits)
	if not modified_closed_files.is_empty():
		any_file_written = true
	for closed_item in modified_closed_files:
		applied_edits += closed_item.edit_count

	if applied_edits == 0:
		print("Rename Symbol: no changes were applied.")
		return

	_sync_modified_rename_resources(modified_open_buffers, modified_closed_files)

	if any_file_written:
		_scan_resource_filesystem_sources()

	_sync_modified_open_buffers_to_lsp(modified_open_buffers)


func _apply_open_rename_edits(
	open_file_edits: Array[RenameFileEdits],
	open_script_buffers: RenameOpenScriptBuffers
) -> Array[RenameModifiedOpenFile]:
	var modified_open_buffers: Array[RenameModifiedOpenFile] = []

	for file_edits in open_file_edits:
		var uri_text := file_edits.uri
		var edits: Array[RenameTextEdit] = file_edits.edits
		var open_script_buffer: RenameOpenScriptBuffer = open_script_buffers.buffer_for_uri(uri_text)
		if open_script_buffer == null:
			continue

		SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(
			open_script_buffer.code,
			edits
		)
		modified_open_buffers.append(RenameModifiedOpenFile.create_from_buffer(
			open_script_buffer,
			_get_code_text(open_script_buffer.code),
			edits.size()
		))

	return modified_open_buffers


func _save_modified_open_buffers(modified_open_buffers: Array[RenameModifiedOpenFile]) -> bool:
	var any_file_written := false

	for open_item in modified_open_buffers:
		if SmartRenameWorkspaceEdit.save_code_edit_to_script_path(open_item.source_script, open_item.code):
			any_file_written = true
		else:
			print("Rename Symbol: could not save %s." % _display_uri(open_item.uri))

	return any_file_written


func _apply_closed_rename_edits(closed_file_edits: Array[RenameFileEdits]) -> Array[RenameModifiedClosedFile]:
	var modified_closed_files: Array[RenameModifiedClosedFile] = []

	for file_edits in closed_file_edits:
		var uri_text := file_edits.uri
		var edits: Array[RenameTextEdit] = file_edits.edits
		var updated_text := _apply_text_edits_to_file(uri_text, edits)
		if not updated_text.is_empty():
			modified_closed_files.append(RenameModifiedClosedFile.create(uri_text, updated_text, edits.size()))

	return modified_closed_files


func _sync_modified_rename_resources(
	modified_open_buffers: Array[RenameModifiedOpenFile],
	modified_closed_files: Array[RenameModifiedClosedFile]
) -> void:
	for open_item in modified_open_buffers:
		_set_script_source_code(open_item.source_script, open_item.text)
		_reload_script_resource(open_item.source_script)
		_refresh_script_editor_state(open_item.source_script)

	for closed_item in modified_closed_files:
		_sync_script_resource_for_uri(closed_item.uri, closed_item.text)


func _sync_modified_open_buffers_to_lsp(modified_open_buffers: Array[RenameModifiedOpenFile]) -> void:
	for open_item in modified_open_buffers:
		_rename_lsp.sync_document(open_item.uri, open_item.text)


func _open_script_buffers_by_uri(affected_rename_edits: RenameEditSet = null) -> RenameOpenScriptBuffers:
	var buffers_by_uri := RenameOpenScriptBuffers.new()
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return buffers_by_uri

	# Godot's C++ ScriptEditorBase can expose its edited resource, but that API is
	# not available from GDScript. Pairing these two arrays is the only public
	# editor API path we have for mapping an open Script to its CodeEdit.
	var scripts: Array = script_editor.get_open_scripts()
	var code_editors := _open_code_editors(script_editor)
	var entry_count := mini(scripts.size(), code_editors.size())
	var filter_by_edits := affected_rename_edits != null and not affected_rename_edits.is_empty()

	for index in entry_count:
		var script_value: Variant = scripts[index]
		if not script_value is Script:
			continue

		var script: Script = script_value
		var script_path := _valid_script_path(script)
		if script_path.is_empty():
			continue

		var uri := _path_to_file_uri(ProjectSettings.globalize_path(script_path))
		if filter_by_edits and not affected_rename_edits.contains_uri(uri):
			continue

		var code: CodeEdit = code_editors[index]
		if code == null:
			continue

		buffers_by_uri.add(RenameOpenScriptBuffer.create(uri, script, code))

	return buffers_by_uri


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


func _scan_resource_filesystem_sources() -> void:
	var resource_filesystem := EditorInterface.get_resource_filesystem()
	if resource_filesystem == null: return
	if resource_filesystem.has_method("scan_sources"):
		resource_filesystem.scan_sources()
	elif resource_filesystem.has_method("scan"):
		resource_filesystem.scan()


func _refresh_script_editor_state(script: Script) -> void:
	if script == null: return
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null: return

	if script_editor.has_method("clear_docs_from_script"):
		script_editor.call("clear_docs_from_script", script)
	if script_editor.has_method("update_docs_from_script"):
		script_editor.call("update_docs_from_script", script)
	if script_editor.has_method("trigger_live_script_reload"):
		script_editor.call("trigger_live_script_reload", script.resource_path)


func _set_script_source_code(script: Script, text: String) -> void:
	if script == null:
		return

	script.set_source_code(text)


func _reload_script_resource(script: Script) -> void:
	if script == null:
		return

	if script.has_method("reload"):
		script.call("reload", true)
	if script.has_method("update_exports"):
		script.call("update_exports")


func _sync_script_resource_for_uri(uri: String, text: String) -> void:
	var path := _file_uri_to_path(uri)
	if path.get_extension() != "gd":
		return

	var script = load(ProjectSettings.localize_path(path))
	if script is Script:
		SmartRenameWorkspaceEdit.sync_script_from_text(script, text)
		_refresh_script_editor_state(script)
		return


func _file_uri_to_path(uri: String) -> String:
	return LspClient.file_uri_to_path(uri)


func _display_uri(uri: String) -> String:
	var path := _file_uri_to_path(uri)
	var localized := ProjectSettings.localize_path(path)
	if localized == path:
		return path

	return localized


func _apply_text_edits_to_file(uri: String, edits: Array[RenameTextEdit]) -> String:
	var path := _file_uri_to_path(uri)
	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null:
		print("Rename Symbol: could not read %s." % _display_uri(uri))
		return ""

	var source_text := source_file.get_as_text()
	source_file = null
	var updated_text := SmartRenameWorkspaceEdit.apply_text_edits_to_text(source_text, edits)
	if not SmartRenameWorkspaceEdit.write_text_to_file(path, updated_text):
		print("Rename Symbol: could not write %s." % _display_uri(uri))
		return ""

	return updated_text


func _reset_connection() -> void:
	_rename_lsp.reset()


func _path_to_file_uri(path: String) -> String:
	return LspClient.path_to_file_uri(path)


func _get_current_code_edit() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	if not script_editor: return null
	var current_editor := script_editor.get_current_editor()
	if not current_editor: return null
	return current_editor.get_base_editor() as CodeEdit


func _get_current_script_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""

	var current_script: Script = script_editor.get_current_script()
	return _valid_script_path(current_script)


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


func _get_symbol_range_under_caret(code: CodeEdit) -> RenameSymbolTarget:
	# todo: seems like this thing checks if symbol at the caret is 
	#  available for manipulation (not part of the gdscript language)
	var symbol_range := SymbolUsageModel.symbol_range_in_line(
		code.get_line(code.get_caret_line()),
		code.get_caret_line(),
		code.get_caret_column()
	)
	return RenameSymbolTarget.from_symbol_range(symbol_range)


func _get_selected_or_current_symbol_range(code: CodeEdit) -> RenameSymbolTarget:
	if code.has_selection():
		var selected := code.get_selected_text()
		var from_line := code.get_selection_from_line()
		var from_col := code.get_selection_from_column()
		var to_line := code.get_selection_to_line()
		var to_col := code.get_selection_to_column()
		if (
			# todo: what this if actually mean? what does it check?
			_is_valid_identifier(selected) # todo: why do we need to check if it's valid if I want to rename it anyway?
			and from_line == to_line
			and RenameSymbolTarget.is_selection_reference_in_text(
				_get_code_text(code), selected, from_line, from_col, to_line, to_col
			)
		):
			return RenameSymbolTarget.create(selected, from_line, from_col)

	# todo: how is this thing different from what's under if statement
	return _get_symbol_range_under_caret(code)


func _is_valid_identifier(value: String) -> bool:
	return _identifier_validator.is_valid_identifier(value)


func _identifier_validation_error(value: String, _current_name: String = "") -> String:
	return _identifier_validator.identifier_validation_error(value)
