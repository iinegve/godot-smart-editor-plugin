@tool
extends Node

const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")
const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")
const SymbolRenamingUseCase := preload("res://addons/smart-editor-plugin/features/symbol_renaming/use_case.gd")

const IDENTIFIER_DIALOG_WIDTH := 560
const IDENTIFIER_DIALOG_HEIGHT := 150
const RENAME_PREWARM_RETRY_USEC := 1_000_000

var _rename_dialog: ConfirmationDialog
var _rename_name_edit: LineEdit
var _rename_prompt_label: Label
var _rename_error_label: Label
var _rename_multi_file_warning_dialog: ConfirmationDialog
var _rename_multi_file_warning_icon: TextureRect
var _rename_multi_file_warning_label: Label
var _rename_multi_file_warning_check_box: CheckBox
var _rename_pending_workspace_edit: Variant = null
var _rename_pending_new_name := ""
var _rename_code: CodeEdit
var _rename_script_path := ""
var _rename_symbol := ""
var _rename_symbol_line := 0
var _rename_symbol_column := 0
var _rename_lsp := LspClient.new()
var _rename_queued := {}
var _rename_prewarm_pending := false
var _rename_last_prewarm_attempt_usec := 0
var _symbol_renaming_use_case := SymbolRenamingUseCase.new()
var _identifier_validator := GDScriptIdentifierValidator.new()


func _enter_tree() -> void:
	_configure_lsp_client()
	_create_rename_multi_file_warning_dialog()
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
	_dispose_rename_dialog()
	_free_dialog(_rename_multi_file_warning_dialog)
	_rename_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	_rename_prewarm_lsp_connection()
	_rename_process_connection()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_RENAME_SHORTCUT, event):
		_begin_rename()
		get_viewport().set_input_as_handled()


func _is_rename_multi_file_warning_enabled() -> bool:
	return bool(SmartEditorSettings.get_setting(SmartEditorSettings.SETTING_RENAME_MULTI_FILE_WARNING_ENABLED, true))


func _set_rename_multi_file_warning_enabled(enabled: bool) -> void:
	SmartEditorSettings.set_setting(SmartEditorSettings.SETTING_RENAME_MULTI_FILE_WARNING_ENABLED, enabled)


func _get_editor_icon(icon_names: Array) -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return null

	for icon_name in icon_names:
		if base_control.has_theme_icon(icon_name, &"EditorIcons"):
			return base_control.get_theme_icon(icon_name, &"EditorIcons")

	return null


func _dialog_width() -> int:
	return int(SmartEditorSettings.get_setting(SmartEditorSettings.SETTING_DIALOG_WIDTH, 420))


func _identifier_dialog_width() -> int:
	return maxi(_dialog_width(), IDENTIFIER_DIALOG_WIDTH)


func _rename_warning_dialog_width() -> int:
	return maxi(_dialog_width() * 2, 760)


func _create_rename_dialog() -> bool:
	_dispose_rename_dialog()

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Symbol"
	_rename_dialog.ok_button_text = "Rename"
	_rename_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_rename_dialog.confirmed.connect(_apply_rename)
	_rename_dialog.canceled.connect(_cancel_rename_dialog)
	_rename_dialog.close_requested.connect(_cancel_rename_dialog)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	_rename_prompt_label = Label.new()
	box.add_child(_rename_prompt_label)

	_rename_name_edit = LineEdit.new()
	_rename_name_edit.placeholder_text = "New identifier"
	_rename_name_edit.keep_editing_on_text_submit = true
	_rename_name_edit.text_submitted.connect(_apply_rename_from_submit)
	_rename_name_edit.text_changed.connect(_on_rename_name_changed)
	box.add_child(_rename_name_edit)

	_rename_error_label = _make_identifier_error_label()
	box.add_child(_rename_error_label)

	_rename_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_rename_dialog)
	return true


func _free_dialog(dialog: Window) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return

	var parent: Node = dialog.get_parent()
	if parent != null:
		parent.remove_child(dialog)
	dialog.queue_free()


func _dispose_rename_dialog() -> void:
	var dialog: Window = _rename_dialog
	_rename_dialog = null
	_rename_prompt_label = null
	_rename_name_edit = null
	_rename_error_label = null
	_free_dialog(dialog)


func _cancel_rename_dialog() -> void:
	_dispose_rename_dialog()
	_focus_code_edit(_rename_code)


func _make_identifier_error_label() -> Label:
	var label := Label.new()
	label.visible = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	return label


func _create_rename_multi_file_warning_dialog() -> void:
	_rename_multi_file_warning_dialog = ConfirmationDialog.new()
	_rename_multi_file_warning_dialog.title = "Rename Symbol"
	_rename_multi_file_warning_dialog.ok_button_text = "Rename"
	_rename_multi_file_warning_dialog.min_size = Vector2i(_rename_warning_dialog_width(), 0)
	_rename_multi_file_warning_dialog.confirmed.connect(_confirm_multi_file_rename_warning)
	_rename_multi_file_warning_dialog.canceled.connect(_clear_pending_multi_file_rename)
	_rename_multi_file_warning_dialog.close_requested.connect(_clear_pending_multi_file_rename)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var warning_row := HBoxContainer.new()
	warning_row.add_theme_constant_override("separation", 12)
	box.add_child(warning_row)

	_rename_multi_file_warning_icon = TextureRect.new()
	_rename_multi_file_warning_icon.custom_minimum_size = Vector2(64, 64)
	_rename_multi_file_warning_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rename_multi_file_warning_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	warning_row.add_child(_rename_multi_file_warning_icon)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 24)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_row.add_child(text_column)

	_rename_multi_file_warning_label = Label.new()
	_rename_multi_file_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_multi_file_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_column.add_child(_rename_multi_file_warning_label)

	_rename_multi_file_warning_check_box = CheckBox.new()
	_rename_multi_file_warning_check_box.text = "Don't show this warning again"
	text_column.add_child(_rename_multi_file_warning_check_box)

	_rename_multi_file_warning_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_rename_multi_file_warning_dialog)


func _begin_rename() -> void:
	_rename_code = _get_current_code_edit()
	if _rename_code == null:
		return

	_rename_script_path = _get_current_script_path_for_code(_rename_code)
	if _rename_script_path.is_empty():
		print("Rename Symbol: could not resolve current script path.")
		return

	var symbol_range := _get_selected_or_current_symbol_range(_rename_code)
	if symbol_range.is_empty():
		print("Rename Symbol: place the caret inside an identifier.")
		return

	_rename_symbol = symbol_range["symbol"]
	_rename_symbol_line = symbol_range["line"]
	_rename_symbol_column = symbol_range["column"]

	if not _create_rename_dialog():
		print("Rename Symbol: could not create dialog.")
		return

	_rename_prompt_label.text = "Rename '%s' to:" % _rename_symbol
	_rename_name_edit.text = _rename_symbol
	_rename_name_edit.select_all()
	_refresh_rename_identifier_validation()
	_rename_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_rename_dialog.popup_centered(Vector2i(_identifier_dialog_width(), IDENTIFIER_DIALOG_HEIGHT))
	call_deferred("_refresh_rename_identifier_validation")
	_rename_name_edit.grab_focus()


func _apply_rename_from_submit(_new_text: String) -> void:
	if not _refresh_rename_identifier_validation():
		_rename_name_edit.call_deferred("grab_focus")
		return

	_apply_rename()


func _apply_rename() -> void:
	if _rename_name_edit == null:
		return

	var replacement := _rename_name_edit.text.strip_edges()
	if replacement == _rename_symbol:
		_dispose_rename_dialog()
		_focus_code_edit(_rename_code)
		return

	var validation_error := _identifier_validation_error(replacement, _rename_symbol)
	if not validation_error.is_empty():
		print("Rename Symbol: %s" % validation_error)
		_refresh_rename_identifier_validation()
		_rename_name_edit.call_deferred("grab_focus")
		return

	_dispose_rename_dialog()
	_rename_queued = {
		"uri": _path_to_file_uri(ProjectSettings.globalize_path(_rename_script_path)),
		"line": _rename_symbol_line,
		"character": _rename_symbol_column,
		"new_name": replacement,
	}

	if _rename_ensure_connection():
		_rename_try_send_request()


func _on_rename_name_changed(_new_text: String) -> void:
	_refresh_rename_identifier_validation()


func _refresh_rename_identifier_validation() -> bool:
	if _rename_name_edit == null:
		return false

	var validation_error := _identifier_validation_error(_rename_name_edit.text, _rename_symbol)
	_set_identifier_validation_state(_rename_dialog, _rename_error_label, validation_error)
	return validation_error.is_empty()


func _set_identifier_validation_state(
	dialog: ConfirmationDialog,
	error_label: Label,
	validation_error: String
) -> void:
	if error_label != null:
		error_label.text = validation_error
		error_label.visible = not validation_error.is_empty()

	if dialog != null:
		dialog.get_ok_button().disabled = not validation_error.is_empty()


func _focus_code_edit(code: CodeEdit) -> void:
	if code != null and is_instance_valid(code):
		code.call_deferred("grab_focus")


func _rename_process_connection() -> void:
	if _rename_lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses := _rename_lsp.poll()
	if _rename_lsp.is_initialized():
		_rename_prewarm_pending = false
	for response in responses:
		_rename_handle_response(response)
	_rename_try_send_request()


func _rename_prewarm_lsp_connection() -> void:
	if not _rename_prewarm_pending:
		return
	if _rename_lsp.is_initialized():
		_rename_prewarm_pending = false
		return
	if not _rename_queued.is_empty() or _rename_lsp.has_pending_requests():
		return

	var status := _rename_lsp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return

	var now := Time.get_ticks_usec()
	if _rename_last_prewarm_attempt_usec > 0 and now - _rename_last_prewarm_attempt_usec < RENAME_PREWARM_RETRY_USEC:
		return
	_rename_last_prewarm_attempt_usec = now
	_rename_ensure_connection(false)


func _rename_ensure_connection(report_errors: bool = true) -> bool:
	var connected := _rename_lsp.ensure_connection(report_errors)
	if not connected and report_errors:
		print("Rename Symbol: could not connect to the code analysis service.")
	return connected


func _rename_try_send_request() -> void:
	if _rename_queued.is_empty() or not _rename_lsp.is_initialized():
		return
	if (
		_rename_lsp.has_pending_kind("prepare_rename")
		or _rename_lsp.has_pending_kind("rename")
		or _rename_lsp.has_pending_kind("rename_references")
	):
		return

	_rename_send_open_document_sync_notifications()
	_rename_send_prepare_rename_request()


func _rename_send_prepare_rename_request() -> void:
	_rename_lsp.send_request("prepare_rename", "textDocument/prepareRename", {
		"textDocument": {
			"uri": _rename_queued["uri"],
		},
		"position": {
			"line": _rename_queued["line"],
			"character": _rename_queued["character"],
		},
	})


func _rename_send_rename_request() -> void:
	_rename_lsp.send_request("rename", "textDocument/rename", {
		"textDocument": {
			"uri": _rename_queued["uri"],
		},
		"position": {
			"line": _rename_queued["line"],
			"character": _rename_queued["character"],
		},
		"newName": _rename_queued["new_name"],
	})


func _rename_send_references_fallback_request() -> void:
	_rename_lsp.send_request("rename_references", "textDocument/references", {
		"textDocument": {
			"uri": _rename_queued["uri"],
		},
		"position": {
			"line": _rename_queued["line"],
			"character": _rename_queued["character"],
		},
		"context": {
			"includeDeclaration": true,
		},
	})


func _rename_send_open_document_sync_notifications() -> void:
	var target_uri := str(_rename_queued.get("uri", ""))
	var open_script_buffers := _rename_open_script_buffers_by_uri()

	for uri in open_script_buffers:
		var uri_text := str(uri)
		var open_script_buffer: Dictionary = open_script_buffers[uri_text]
		var code: CodeEdit = open_script_buffer.get("code", null)
		if code == null:
			continue

		var text := _get_code_text(code)
		_rename_send_text_document_sync_notification(uri_text, text)

	if not target_uri.is_empty() and _rename_code != null:
		var target_text := _get_code_text(_rename_code)
		_rename_send_text_document_sync_notification(target_uri, target_text)


func _rename_send_text_document_sync_notification(uri: String, text: String) -> bool:
	return _rename_lsp.sync_document(uri, text)


func _rename_handle_response(response: Dictionary) -> void:
	var request_kind := str(response.get("kind", ""))
	var message: Dictionary = response.get("message", {})

	if message.has("error"):
		if request_kind == "prepare_rename":
			print("Rename Symbol: prepareRename failed: %s" % JSON.stringify(message["error"]))
			_rename_send_rename_request()
			return

		print("Rename Symbol: request failed: %s" % JSON.stringify(message["error"]))
		return

	if request_kind == "prepare_rename":
		_rename_send_rename_request()
	elif request_kind == "rename":
		var workspace_edit = message.get("result", {})
		if _rename_workspace_edit_to_edits_by_uri(workspace_edit).is_empty() and not _rename_queued.is_empty():
			_rename_send_references_fallback_request()
			return

		_rename_maybe_confirm_workspace_edit(workspace_edit, str(_rename_queued.get("new_name", "")))
	elif request_kind == "rename_references":
		var workspace_edit := _symbol_renaming_use_case.references_to_workspace_edit(
			message.get("result", []),
			str(_rename_queued.get("new_name", ""))
		)
		_rename_maybe_confirm_workspace_edit(workspace_edit, str(_rename_queued.get("new_name", "")))
	_rename_queued = {}


func _rename_maybe_confirm_workspace_edit(workspace_edit: Variant, new_name: String) -> void:
	var edits_by_uri := _rename_workspace_edit_to_edits_by_uri(workspace_edit)
	var file_count := _rename_non_empty_edit_file_count(edits_by_uri)
	if file_count <= 1 or not _is_rename_multi_file_warning_enabled():
		call_deferred("_rename_apply_workspace_edit", workspace_edit, new_name)
		return

	_rename_pending_workspace_edit = workspace_edit
	_rename_pending_new_name = new_name
	_rename_multi_file_warning_check_box.button_pressed = false
	_rename_multi_file_warning_icon.texture = _get_editor_icon([
		&"NodeWarning",
		&"StatusWarning",
		&"Warning",
	])
	var warning_dialog_width := _rename_warning_dialog_width()
	_rename_multi_file_warning_label.custom_minimum_size = Vector2(warning_dialog_width - 160, 112)
	_rename_multi_file_warning_label.text = (
		"Rename Symbol will update multiple files.\n"
		+ "Undo will not work properly for all of them.\n"
		+ "Godot can only undo the edit in the current open script.\n"
		+ "\n"
		+ "To get back to the original name, use Rename Symbol again."
	)
	_rename_multi_file_warning_dialog.min_size = Vector2i(warning_dialog_width, 0)
	_rename_multi_file_warning_dialog.popup_centered_clamped(Vector2i(warning_dialog_width, 260), 0.85)


func _confirm_multi_file_rename_warning() -> void:
	if _rename_multi_file_warning_check_box.button_pressed:
		_set_rename_multi_file_warning_enabled(false)

	var workspace_edit := _rename_pending_workspace_edit
	var new_name := _rename_pending_new_name
	_clear_pending_multi_file_rename()
	call_deferred("_rename_apply_workspace_edit", workspace_edit, new_name)


func _clear_pending_multi_file_rename() -> void:
	_rename_pending_workspace_edit = null
	_rename_pending_new_name = ""


func _rename_apply_workspace_edit(workspace_edit: Variant, new_name: String = "") -> void:
	if typeof(workspace_edit) != TYPE_DICTIONARY:
		print("Rename Symbol: rename returned no changes.")
		return

	var edits_by_uri := _rename_workspace_edit_to_edits_by_uri(workspace_edit)

	if edits_by_uri.is_empty():
		print("Rename Symbol: no changes found.")
		return

	var applied_edits := 0
	var applied_files := 0
	var disk_files_changed := false
	var open_script_buffers := _rename_open_script_buffers_by_uri()
	var open_applied_buffers: Array[Dictionary] = []
	for uri in edits_by_uri:
		var edits: Array = edits_by_uri[uri]
		if edits.is_empty():
			continue

		var uri_text := str(uri)
		if open_script_buffers.has(uri_text):
			var open_script_buffer: Dictionary = open_script_buffers[uri_text]
			SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(
				open_script_buffer["code"],
				edits,
				_should_use_native_rename_undo(edits_by_uri, open_script_buffers, uri_text)
			)
			var open_text := _get_code_text(open_script_buffer["code"])
			_rename_set_script_source_code(open_script_buffer["script"], open_text)
			var definition_score := _rename_definition_score_for_code(open_script_buffer["code"], edits, new_name)
			open_applied_buffers.append({
				"uri": uri_text,
				"buffer": open_script_buffer,
				"text": open_text,
				"edits": edits.size(),
				"definition_score": definition_score,
			})
			applied_edits += edits.size()
			applied_files += 1
			continue

		var updated_text := _rename_apply_text_edits_to_file(uri_text, edits)
		if not updated_text.is_empty():
			_rename_sync_script_resource_for_uri(uri_text, updated_text)
			disk_files_changed = true
			applied_edits += edits.size()
			applied_files += 1

	if applied_edits == 0:
		print("Rename Symbol: no changes were applied.")
		return

	open_applied_buffers.sort_custom(_compare_rename_open_apply_items)
	for open_item in open_applied_buffers:
		var open_script_buffer: Dictionary = open_item["buffer"]
		var open_script: Script = open_script_buffer.get("script", null)
		_rename_reload_script_resource(open_script)
		_rename_refresh_script_editor_state(open_script)
		_rename_send_text_document_sync_notification(str(open_item["uri"]), str(open_item["text"]))

	if disk_files_changed:
		_rename_scan_resource_filesystem_sources()


func _rename_open_script_buffers_by_uri() -> Dictionary:
	var buffers_by_uri := {}
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return buffers_by_uri

	var scripts: Array = script_editor.get_open_scripts()
	var code_editor_entries := _rename_open_code_editor_entries(script_editor)
	var used_editor_indices := {}

	for script_value in scripts:
		if not script_value is Script:
			continue

		var script: Script = script_value
		var script_path := _rename_valid_script_path(script)
		if script_path.is_empty():
			continue

		var editor_index := _rename_find_matching_code_editor_index(script, code_editor_entries, used_editor_indices)
		if editor_index == -1:
			continue

		used_editor_indices[editor_index] = true
		var editor_entry: Dictionary = code_editor_entries[editor_index]
		var code: CodeEdit = editor_entry.get("code", null)

		var uri := _path_to_file_uri(ProjectSettings.globalize_path(script_path))
		buffers_by_uri[uri] = {
			"script": script,
			"code": code,
		}

	_rename_add_target_open_script_buffer(buffers_by_uri)
	return buffers_by_uri


func _rename_open_code_editor_entries(script_editor: ScriptEditor) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var editors: Array = script_editor.get_open_script_editors()

	for editor in editors:
		if editor == null:
			continue

		var base = editor.get_base_editor()
		if not base is CodeEdit:
			continue

		entries.append({
			"editor": editor,
			"code": base,
		})

	return entries


func _rename_find_matching_code_editor_index(script: Script, entries: Array[Dictionary], used_indices: Dictionary) -> int:
	var script_source := _rename_normalize_editor_text(script.get_source_code())
	var disk_source := _rename_read_script_file_text(str(script.resource_path))
	if not disk_source.is_empty():
		disk_source = _rename_normalize_editor_text(disk_source)

	var matching_index := -1
	var matching_count := 0
	for index in entries.size():
		if used_indices.has(index):
			continue

		var entry: Dictionary = entries[index]
		var code: CodeEdit = entry.get("code", null)
		if code == null:
			continue

		var code_text := _rename_normalize_editor_text(_get_code_text(code))
		var matches_script_source := not script_source.is_empty() and code_text == script_source
		var matches_disk_source := not disk_source.is_empty() and code_text == disk_source
		if matches_script_source or matches_disk_source:
			matching_index = index
			matching_count += 1

	return matching_index if matching_count == 1 else -1


func _rename_add_target_open_script_buffer(buffers_by_uri: Dictionary) -> void:
	if _rename_code == null or _rename_script_path.is_empty():
		return

	var script := _rename_script_for_path(_rename_script_path)
	if script == null:
		return

	var uri := _path_to_file_uri(ProjectSettings.globalize_path(_rename_script_path))
	buffers_by_uri[uri] = {
		"script": script,
		"code": _rename_code,
	}


func _rename_script_for_path(script_path: String) -> Script:
	if script_path.is_empty() or script_path.contains("::") or script_path.get_extension() != "gd":
		return null

	var script_editor := EditorInterface.get_script_editor()
	if script_editor != null:
		var current_script: Script = script_editor.get_current_script()
		if current_script != null and str(current_script.resource_path) == script_path:
			return current_script

		var scripts: Array = script_editor.get_open_scripts()
		for script_value in scripts:
			if not script_value is Script:
				continue

			var script: Script = script_value
			if str(script.resource_path) == script_path:
				return script

	var loaded: Resource = load(script_path)
	if loaded is Script:
		return loaded

	return null


func _rename_valid_script_path(script: Script) -> String:
	if script == null:
		return ""

	var script_path := str(script.resource_path)
	if script_path.is_empty() or script_path.contains("::"):
		return ""
	if script_path.get_extension() != "gd":
		return ""

	return script_path


func _rename_read_script_file_text(script_path: String) -> String:
	if script_path.is_empty():
		return ""

	var source_file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(script_path), FileAccess.READ)
	if source_file == null:
		return ""

	var text := source_file.get_as_text()
	source_file = null
	return text


func _rename_normalize_editor_text(text: String) -> String:
	text = text.replace("\r\n", "\n")
	while text.ends_with("\n"):
		text = text.trim_suffix("\n")

	return text


func _rename_workspace_edit_to_edits_by_uri(workspace_edit: Variant) -> Dictionary:
	return _symbol_renaming_use_case.workspace_edit_to_edits_by_uri(workspace_edit)


func _rename_non_empty_edit_file_count(edits_by_uri: Dictionary) -> int:
	return _symbol_renaming_use_case.non_empty_edit_file_count(edits_by_uri)


func _should_use_native_rename_undo(edits_by_uri: Dictionary, open_script_buffers: Dictionary, uri: String) -> bool:
	return _symbol_renaming_use_case.should_use_native_rename_undo(edits_by_uri, open_script_buffers, uri)


func _rename_scan_resource_filesystem_sources() -> void:
	var resource_filesystem := EditorInterface.get_resource_filesystem()
	if resource_filesystem == null:
		return

	if resource_filesystem.has_method("scan_sources"):
		resource_filesystem.scan_sources()
	elif resource_filesystem.has_method("scan"):
		resource_filesystem.scan()


func _rename_refresh_script_editor_state(script: Script) -> void:
	if script == null:
		return

	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return

	if script_editor.has_method("clear_docs_from_script"):
		script_editor.call("clear_docs_from_script", script)
	if script_editor.has_method("update_docs_from_script"):
		script_editor.call("update_docs_from_script", script)
	if script_editor.has_method("trigger_live_script_reload"):
		script_editor.call("trigger_live_script_reload", script.resource_path)


func _rename_set_script_source_code(script: Script, text: String) -> void:
	if script == null:
		return

	script.set_source_code(text)


func _rename_reload_script_resource(script: Script) -> void:
	if script == null:
		return

	if script.has_method("reload"):
		script.call("reload", true)
	if script.has_method("update_exports"):
		script.call("update_exports")


func _rename_sync_script_resource_for_uri(uri: String, text: String) -> void:
	var path := _file_uri_to_path(uri)
	if path.get_extension() != "gd":
		return

	var script = load(ProjectSettings.localize_path(path))
	if script is Script:
		SmartRenameWorkspaceEdit.sync_script_from_text(script, text)
		_rename_refresh_script_editor_state(script)
		return


func _file_uri_to_path(uri: String) -> String:
	return LspClient.file_uri_to_path(uri)


func _rename_display_uri(uri: String) -> String:
	var path := _file_uri_to_path(uri)
	var localized := ProjectSettings.localize_path(path)
	if localized == path:
		return path

	return localized


func _rename_text_signature(text: String) -> String:
	return LspClient.text_signature(text)


func _rename_apply_text_edits_to_file(uri: String, edits: Array) -> String:
	var path := _file_uri_to_path(uri)
	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null:
		print("Rename Symbol: could not read %s." % _rename_display_uri(uri))
		return ""

	var source_text := source_file.get_as_text()
	source_file = null
	var updated_text := _rename_apply_text_edits_to_text(source_text, edits)
	if not SmartRenameWorkspaceEdit.write_text_to_file(path, updated_text):
		print("Rename Symbol: could not write %s." % _rename_display_uri(uri))
		return ""

	return updated_text


func _rename_apply_text_edits_to_text(text: String, edits: Array) -> String:
	return _symbol_renaming_use_case.apply_text_edits_to_text(text, edits)


func _compare_rename_open_apply_items(a: Dictionary, b: Dictionary) -> bool:
	return _symbol_renaming_use_case.compare_open_apply_items(a, b)


func _rename_definition_score_for_code(code: CodeEdit, edits: Array, symbol: String) -> int:
	if code == null or symbol.is_empty():
		return 0
	return _symbol_renaming_use_case.definition_score_for_text(_get_code_text(code), edits, symbol)


func _rename_reset_connection() -> void:
	_rename_lsp.reset()


func _path_to_file_uri(path: String) -> String:
	return LspClient.path_to_file_uri(path)


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


func _get_current_script_path_for_code(code: CodeEdit) -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""

	var current_editor := script_editor.get_current_editor()
	if current_editor != null and current_editor.get_base_editor() == code:
		var current_script: Script = script_editor.get_current_script()
		if current_script != null:
			return current_script.resource_path

	return _get_current_script_path()


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


func _get_selected_or_current_symbol_range(code: CodeEdit) -> Dictionary:
	if code.has_selection():
		var selected := code.get_selected_text()
		var from_line := code.get_selection_from_line()
		var from_col := code.get_selection_from_column()
		var to_line := code.get_selection_to_line()
		var to_col := code.get_selection_to_column()
		if (
			_is_valid_identifier(selected)
			and from_line == to_line
			and SymbolUsageModel.is_identifier_reference_in_text(
				_get_code_text(code),
				{
					"line": from_line,
					"column": from_col,
					"end_line": to_line,
					"end_column": to_col,
				},
				selected
			)
		):
			return {
				"symbol": selected,
				"line": from_line,
				"column": from_col,
			}

	return _get_symbol_range_under_caret(code)


func _is_valid_identifier(value: String) -> bool:
	return _identifier_validator.is_valid_identifier(value)


func _identifier_validation_error(value: String, _current_name: String = "") -> String:
	return _identifier_validator.identifier_validation_error(value)
