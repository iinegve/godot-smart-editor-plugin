@tool
extends Node

const GDScriptSelectionParser := preload("res://addons/smart-editor-plugin/smart_editor/gdscript_selection_parser.gd")
const SmartSelectionHistory := preload("res://addons/smart-editor-plugin/smart_editor/smart_selection_history.gd")
const SmartSelectionRange := preload("res://addons/smart-editor-plugin/smart_editor/smart_selection_range.gd")
const SmartFunctionBoundaryGuides := preload("res://addons/smart-editor-plugin/smart_editor/smart_function_boundary_guides.gd")
const SmartFunctionBoundaryGuidesController := preload("res://addons/smart-editor-plugin/smart_editor/smart_function_boundary_guides_controller.gd")
const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")
const SmartSymbolUsageHighlight := preload("res://addons/smart-editor-plugin/smart_editor/smart_symbol_usage_highlight.gd")
const SmartSymbolUsageController := preload("res://addons/smart-editor-plugin/smart_editor/smart_symbol_usage_controller.gd")
const SymbolUsageModel := preload("res://addons/smart-editor-plugin/smart_editor/smart_symbol_usage_model.gd")
const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const SETTINGS_PREFIX := &"plugin/smart_editor/"
const SETTING_EDITOR_PREFIX := SETTINGS_PREFIX + &"editor/"
const SETTING_HIGHLIGHTS_PREFIX := SETTINGS_PREFIX + &"highlights/"
const SETTING_FUNCTION_BOUNDARY_PREFIX := SETTINGS_PREFIX + &"function_boundary_guides/"
const SETTING_DIALOG_WIDTH := SETTING_EDITOR_PREFIX + &"dialog_width"
const SETTING_EXPAND_SHORTCUT := SETTING_EDITOR_PREFIX + &"expand_selection"
const SETTING_SHRINK_SHORTCUT := SETTING_EDITOR_PREFIX + &"shrink_selection"
const SETTING_EXTRACT_SHORTCUT := SETTING_EDITOR_PREFIX + &"extract_local_variable"
const SETTING_RENAME_SHORTCUT := SETTING_EDITOR_PREFIX + &"rename_symbol"
const SETTING_INLINE_SHORTCUT := SETTING_EDITOR_PREFIX + &"inline_variable"
const SETTING_SYMBOL_USAGE_STRIPE_ENABLED := SETTING_HIGHLIGHTS_PREFIX + &"stripe_highlights_enabled"
const SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED := SETTING_HIGHLIGHTS_PREFIX + &"in-editor_highlights_enabled"
const SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR := SETTING_HIGHLIGHTS_PREFIX + &"highlight_color"
const SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR := SETTING_HIGHLIGHTS_PREFIX + &"current_highlight_color"
const SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR := SETTING_HIGHLIGHTS_PREFIX + &"current_outline_color"
const SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED := SETTING_FUNCTION_BOUNDARY_PREFIX + &"show_guides"
const SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR := SETTING_FUNCTION_BOUNDARY_PREFIX + &"guide_color"
const LEGACY_SETTING_DIALOG_WIDTH := SETTINGS_PREFIX + &"dialog_width"
const LEGACY_SETTING_SYMBOL_USAGE_STRIPE_ENABLED := SETTINGS_PREFIX + &"symbol_usage_stripe_enabled"
const LEGACY_SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED := SETTINGS_PREFIX + &"symbol_usage_highlight_enabled"
const LEGACY_SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR := SETTINGS_PREFIX + &"symbol_usage_highlight_color"
const LEGACY_SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR := SETTINGS_PREFIX + &"symbol_usage_current_highlight_color"
const LEGACY_SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR := SETTINGS_PREFIX + &"symbol_usage_current_outline_color"
const PREVIOUS_SETTING_SYMBOL_USAGE_STRIPE_ENABLED := SETTINGS_PREFIX + &"symbol_usage/stripe_enabled"
const PREVIOUS_SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED := SETTINGS_PREFIX + &"symbol_usage/highlights_enabled"
const PREVIOUS_SETTING_HIGHLIGHTS_STRIPE_ENABLED := SETTINGS_PREFIX + &"highlights/stripe_enabled"
const PREVIOUS_SETTING_HIGHLIGHTS_ENABLED := SETTINGS_PREFIX + &"highlights/enabled"
const PREVIOUS_SETTING_HIGHLIGHTS_HIGHLIGHT_ENABLED := SETTINGS_PREFIX + &"highlights/highlights_enabled"
const PREVIOUS_SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR := SETTINGS_PREFIX + &"symbol_usage/highlight_color"
const PREVIOUS_SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR := SETTINGS_PREFIX + &"symbol_usage/current_highlight_color"
const PREVIOUS_SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR := SETTINGS_PREFIX + &"symbol_usage/current_outline_color"
const LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED := SETTINGS_PREFIX + &"function_boundary_guides_enabled"
const LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR := SETTINGS_PREFIX + &"function_boundary_guide_color"
const LEGACY_SETTING_EXPAND_SHORTCUT := SETTINGS_PREFIX + &"expand_selection"
const LEGACY_SETTING_SHRINK_SHORTCUT := SETTINGS_PREFIX + &"shrink_selection"
const LEGACY_SETTING_EXTRACT_SHORTCUT := SETTINGS_PREFIX + &"extract_local_variable"
const LEGACY_SETTING_RENAME_SHORTCUT := SETTINGS_PREFIX + &"rename_symbol"
const LEGACY_SETTING_INLINE_SHORTCUT := SETTINGS_PREFIX + &"inline_variable"
const REMOVED_SETTING_DEBUG_LOGS := SETTINGS_PREFIX + &"debug_logs"
const REMOVED_SETTING_DIAGNOSTICS_DEBUG_LOGS := SETTINGS_PREFIX + &"diagnostics/debug_logs_enabled"
const REMOVED_SETTING_RENAME_LSP_PROBE_ONLY := SETTINGS_PREFIX + &"rename_lsp_probe_only"
const REMOVED_SETTING_DIAGNOSTICS_RENAME_PROBE_ONLY := SETTINGS_PREFIX + &"diagnostics/rename_probe_only"
const REMOVED_SETTING_SYMBOL_USAGE_LSP_ENABLED := SETTINGS_PREFIX + &"symbol_usage_lsp_enabled"
const REMOVED_SETTING_SYMBOL_USAGE_LSP_ENABLED_GROUPED := SETTINGS_PREFIX + &"symbol_usage/use_code_analysis_service"
const REMOVED_SETTING_EXTRACT_METHOD := SETTINGS_PREFIX + &"extract_method"
const REMOVED_SETTING_SYMBOL_USAGE_PROFILE_LOGS := SETTINGS_PREFIX + &"symbol_usage_profile_logs"
const REMOVED_SETTING_RENAME_PROFILE_LOGS := SETTINGS_PREFIX + &"rename_profile_logs"
const HOST := "127.0.0.1"
const PORT := 6005
const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
const RENAME_PREWARM_RETRY_USEC := 1_000_000

var _extract_dialog: ConfirmationDialog
var _extract_name_edit: LineEdit
var _extract_prompt_label: Label
var _extract_code: CodeEdit
var _extract_selection_range := {}
var _extract_expression := ""

var _rename_dialog: ConfirmationDialog
var _rename_name_edit: LineEdit
var _rename_prompt_label: Label
var _rename_code: CodeEdit
var _rename_script_path := ""
var _rename_symbol := ""
var _rename_symbol_line := 0
var _rename_symbol_column := 0
var _rename_lsp := LspClient.new()
var _rename_queued := {}
var _rename_prewarm_pending := false
var _rename_last_prewarm_attempt_usec := 0

var _inline_code: CodeEdit
var _inline_script_path := ""
var _inline_uri := ""
var _inline_symbol := ""
var _inline_symbol_line := 0
var _inline_symbol_column := 0
var _inline_expression := ""
var _inline_lsp := LspClient.new()
var _inline_queued := false
var _expand_selection_history := SmartSelectionHistory.new()
var _symbol_usage_controller = null
var _function_boundary_guides_controller = null


func _enter_tree() -> void:
	_init_settings()
	_configure_lsp_clients()
	_create_extract_dialog()
	_create_rename_dialog()
	_create_symbol_usage_controller()
	_rename_prewarm_pending = true
	set_process_shortcut_input(true)
	set_process(true)


func initialize_after_call_hierarchy_settings() -> void:
	_init_function_boundary_settings()
	_create_function_boundary_guides_controller()


func _configure_lsp_clients() -> void:
	_rename_lsp.configure("Rename Symbol", HOST, PORT, {
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
	_inline_lsp.configure("Inline Variable", HOST, PORT)


func _exit_tree() -> void:
	if _extract_dialog != null:
		_extract_dialog.queue_free()
	if _rename_dialog != null:
		_rename_dialog.queue_free()
	if _symbol_usage_controller != null:
		_symbol_usage_controller.queue_free()
	if _function_boundary_guides_controller != null:
		_function_boundary_guides_controller.queue_free()
	_rename_lsp.disconnect_from_host()
	_inline_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	_rename_prewarm_lsp_connection()
	_rename_process_connection()
	_inline_process_connection()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if _shortcut_matches(SETTING_SHRINK_SHORTCUT, event):
		var code := _get_current_code_edit()
		if code != null:
			_shrink_selection(code)
			get_viewport().set_input_as_handled()
		return

	if _shortcut_matches(SETTING_EXPAND_SHORTCUT, event):
		var code := _get_current_code_edit()
		if code != null:
			_expand_selection(code)
			get_viewport().set_input_as_handled()
		return

	if _shortcut_matches(SETTING_EXTRACT_SHORTCUT, event):
		_begin_extract()
		get_viewport().set_input_as_handled()
		return

	if _shortcut_matches(SETTING_RENAME_SHORTCUT, event):
		_begin_rename()
		get_viewport().set_input_as_handled()
		return

	if _shortcut_matches(SETTING_INLINE_SHORTCUT, event):
		_begin_inline()
		get_viewport().set_input_as_handled()


func _init_settings() -> void:
	_init_setting(SETTING_DIALOG_WIDTH, 420, TYPE_INT, PROPERTY_HINT_RANGE, "300,900,10", LEGACY_SETTING_DIALOG_WIDTH)
	_init_shortcut_setting(SETTING_EXPAND_SHORTCUT, _make_shortcut(KEY_D, true, false), LEGACY_SETTING_EXPAND_SHORTCUT)
	_init_shortcut_setting(SETTING_SHRINK_SHORTCUT, _make_shortcut(KEY_D, true, false, false, true), LEGACY_SETTING_SHRINK_SHORTCUT)
	_init_shortcut_setting(SETTING_EXTRACT_SHORTCUT, _make_shortcut(KEY_V, true, true), LEGACY_SETTING_EXTRACT_SHORTCUT)
	_init_shortcut_setting(SETTING_RENAME_SHORTCUT, _make_shortcut(KEY_R, true, true), LEGACY_SETTING_RENAME_SHORTCUT)
	_init_shortcut_setting(SETTING_INLINE_SHORTCUT, _make_shortcut(KEY_N, true, true), LEGACY_SETTING_INLINE_SHORTCUT)
	_init_setting_from_legacy_paths(SETTING_SYMBOL_USAGE_STRIPE_ENABLED, false, TYPE_BOOL, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_SYMBOL_USAGE_STRIPE_ENABLED,
		PREVIOUS_SETTING_SYMBOL_USAGE_STRIPE_ENABLED,
		PREVIOUS_SETTING_HIGHLIGHTS_STRIPE_ENABLED,
	])
	_init_setting_from_legacy_paths(SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED, false, TYPE_BOOL, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED,
		PREVIOUS_SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED,
		PREVIOUS_SETTING_HIGHLIGHTS_ENABLED,
		PREVIOUS_SETTING_HIGHLIGHTS_HIGHLIGHT_ENABLED,
	])
	_init_setting_from_legacy_paths(SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR, SmartSymbolUsageHighlight.DEFAULT_HIGHLIGHT_COLOR, TYPE_COLOR, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR,
		PREVIOUS_SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR,
	])
	_init_setting_from_legacy_paths(SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR, SmartSymbolUsageHighlight.DEFAULT_CURRENT_HIGHLIGHT_COLOR, TYPE_COLOR, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR,
		PREVIOUS_SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR,
	])
	_init_setting_from_legacy_paths(SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR, SmartSymbolUsageHighlight.DEFAULT_CURRENT_OUTLINE_COLOR, TYPE_COLOR, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR,
		PREVIOUS_SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR,
	])
	_erase_removed_settings([
		REMOVED_SETTING_DEBUG_LOGS,
		REMOVED_SETTING_DIAGNOSTICS_DEBUG_LOGS,
		REMOVED_SETTING_RENAME_LSP_PROBE_ONLY,
		REMOVED_SETTING_DIAGNOSTICS_RENAME_PROBE_ONLY,
		REMOVED_SETTING_SYMBOL_USAGE_LSP_ENABLED,
		REMOVED_SETTING_SYMBOL_USAGE_LSP_ENABLED_GROUPED,
		REMOVED_SETTING_EXTRACT_METHOD,
		REMOVED_SETTING_SYMBOL_USAGE_PROFILE_LOGS,
		REMOVED_SETTING_RENAME_PROFILE_LOGS,
	])


func _init_function_boundary_settings() -> void:
	_init_setting(SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED, true, TYPE_BOOL, PROPERTY_HINT_NONE, "", LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED)
	_init_setting(SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR, SmartFunctionBoundaryGuides.DEFAULT_GUIDE_COLOR, TYPE_COLOR, PROPERTY_HINT_NONE, "", LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR)


func _init_setting(path: StringName, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", legacy_path: StringName = &"") -> void:
	var legacy_paths: Array = []
	if legacy_path != &"":
		legacy_paths.append(legacy_path)
	_init_setting_from_legacy_paths(path, default_value, type, hint, hint_string, legacy_paths)


func _init_setting_from_legacy_paths(path: StringName, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", legacy_paths: Array = []) -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		var value: Variant = default_value
		for legacy_path in legacy_paths:
			if settings.has_setting(legacy_path):
				value = settings.get_setting(legacy_path)
				break
		settings.set_setting(path, value)
	settings.set_initial_value(path, default_value, false)
	settings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})
	for legacy_path in legacy_paths:
		_erase_legacy_setting(path, legacy_path)


func _init_shortcut_setting(path: StringName, default_shortcut: Shortcut, legacy_path: StringName = &"") -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		var shortcut: Variant = default_shortcut
		if legacy_path != &"" and settings.has_setting(legacy_path):
			shortcut = settings.get_setting(legacy_path)
		settings.set_setting(path, shortcut)
	settings.set_initial_value(path, default_shortcut, false)
	settings.add_property_info({
		"name": path,
		"type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "Shortcut",
	})
	_erase_legacy_setting(path, legacy_path)


func _erase_legacy_setting(path: StringName, legacy_path: StringName) -> void:
	if legacy_path == &"" or legacy_path == path:
		return

	_erase_setting(legacy_path)


func _erase_removed_settings(paths: Array) -> void:
	for path in paths:
		_erase_setting(path)


func _erase_setting(path: StringName) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(path):
		settings.erase(path)


func _get_plugin_setting(path: StringName, default_value: Variant) -> Variant:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		return default_value
	return settings.get_setting(path)


func _dialog_width() -> int:
	return int(_get_plugin_setting(SETTING_DIALOG_WIDTH, 420))


func _shortcut_matches(path: StringName, event: InputEvent) -> bool:
	var shortcut = _get_plugin_setting(path, null)
	return shortcut is Shortcut and shortcut.matches_event(event)


func _make_shortcut(keycode: Key, meta_pressed: bool, ctrl_pressed: bool, alt_pressed: bool = false, shift_pressed: bool = false) -> Shortcut:
	var shortcut := Shortcut.new()
	var event := InputEventKey.new()
	event.device = -1
	event.keycode = keycode
	event.meta_pressed = meta_pressed
	event.ctrl_pressed = ctrl_pressed
	event.alt_pressed = alt_pressed
	event.shift_pressed = shift_pressed
	shortcut.events = [event]
	return shortcut


func _create_extract_dialog() -> void:
	_extract_dialog = ConfirmationDialog.new()
	_extract_dialog.title = "Extract Local Variable"
	_extract_dialog.ok_button_text = "Extract"
	_extract_dialog.min_size = Vector2i(_dialog_width(), 0)
	_extract_dialog.confirmed.connect(_apply_extract)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	_extract_prompt_label = Label.new()
	box.add_child(_extract_prompt_label)

	_extract_name_edit = LineEdit.new()
	_extract_name_edit.placeholder_text = "Variable name"
	_extract_name_edit.text_submitted.connect(_apply_extract_from_submit)
	box.add_child(_extract_name_edit)

	_extract_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_extract_dialog)


func _create_rename_dialog() -> void:
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Symbol"
	_rename_dialog.ok_button_text = "Rename"
	_rename_dialog.min_size = Vector2i(_dialog_width(), 0)
	_rename_dialog.confirmed.connect(_apply_rename)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	_rename_prompt_label = Label.new()
	box.add_child(_rename_prompt_label)

	_rename_name_edit = LineEdit.new()
	_rename_name_edit.placeholder_text = "New identifier"
	_rename_name_edit.text_submitted.connect(_apply_rename_from_submit)
	box.add_child(_rename_name_edit)

	_rename_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_rename_dialog)


func _create_symbol_usage_controller() -> void:
	_symbol_usage_controller = SmartSymbolUsageController.new()
	add_child(_symbol_usage_controller)
	_symbol_usage_controller.configure(
		SETTING_SYMBOL_USAGE_STRIPE_ENABLED,
		HOST,
		PORT,
		SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED,
		SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR,
		SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR,
		SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR
	)


func _create_function_boundary_guides_controller() -> void:
	_function_boundary_guides_controller = SmartFunctionBoundaryGuidesController.new()
	add_child(_function_boundary_guides_controller)
	_function_boundary_guides_controller.configure(
		SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED,
		SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR
	)


func _expand_selection(code: CodeEdit) -> void:
	var current := _get_current_range(code)
	var candidates := _build_expansion_candidates(code, current)

	for candidate in candidates:
		if _range_strictly_contains(candidate, current) or _candidate_starts_after_indent_caret(code, candidate, current):
			_expand_selection_history.record(current)
			_select_range(code, candidate)
			return

	var file_range := _get_full_file_range(code)
	if not _ranges_equal(current, file_range):
		_expand_selection_history.record(current)
		_select_range(code, file_range)


func _shrink_selection(code: CodeEdit) -> void:
	var current := _get_current_range(code)
	var target := _expand_selection_history.shrink_target(current, _build_expansion_candidates(code, current))
	if not target.is_empty():
		_select_range(code, target)


func _get_current_range(code: CodeEdit) -> Dictionary:
	if code.has_selection():
		return _make_range(
			code.get_selection_from_line(),
			code.get_selection_from_column(),
			code.get_selection_to_line(),
			code.get_selection_to_column()
		)

	return _make_range(
		code.get_caret_line(),
		code.get_caret_column(),
		code.get_caret_line(),
		code.get_caret_column()
	)


func _get_full_file_range(code: CodeEdit) -> Dictionary:
	var last_line: int = maxi(0, code.get_line_count() - 1)
	return _make_range(0, 0, last_line, code.get_line(last_line).length())


func _build_expansion_candidates(code: CodeEdit, current: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var parser := GDScriptSelectionParser.new()
	for candidate in parser.build_candidates(_get_code_text(code), current):
		_append_candidate(candidates, candidate)

	return candidates


func _append_candidate(candidates: Array[Dictionary], candidate: Dictionary) -> void:
	if candidate.is_empty():
		return

	for existing in candidates:
		if _ranges_equal(existing, candidate):
			return

	candidates.append(candidate)


func _begin_extract() -> void:
	_extract_code = _get_current_code_edit()
	if _extract_code == null:
		return

	if not _extract_code.has_selection():
		print("Extract Local Variable: select an expression first.")
		return

	_extract_selection_range = _get_selection_range(_extract_code)
	if _extract_selection_range["from_line"] != _extract_selection_range["to_line"]:
		print("Extract Local Variable: only single-line selections are supported for now.")
		return

	_extract_expression = _extract_code.get_selected_text().strip_edges()
	if _extract_expression.is_empty():
		print("Extract Local Variable: selected expression is empty.")
		return

	_extract_prompt_label.text = "Extract selected expression into local variable:"
	_extract_name_edit.text = _suggest_extract_name(_extract_expression)
	_extract_name_edit.select_all()
	_extract_dialog.min_size = Vector2i(_dialog_width(), 0)
	_extract_dialog.popup_centered(Vector2i(_dialog_width(), 120))
	_extract_name_edit.grab_focus()


func _apply_extract_from_submit(_new_text: String) -> void:
	_extract_dialog.hide()
	_apply_extract()


func _apply_extract() -> void:
	if _extract_code == null or _extract_selection_range.is_empty() or _extract_expression.is_empty():
		return

	var variable_name := _extract_name_edit.text.strip_edges()
	if not _is_valid_identifier(variable_name):
		print("Extract Local Variable: '%s' is not a valid identifier." % variable_name)
		return

	var line_index: int = _extract_selection_range["from_line"]
	var line := _extract_code.get_line(line_index)
	var indent := line.substr(0, _line_indent_chars(line))
	var declaration := "%svar %s = %s" % [indent, variable_name, _extract_expression]

	var from_col: int = _extract_selection_range["from_col"]
	var to_col: int = _extract_selection_range["to_col"]
	var replaced_line := line.substr(0, from_col) + variable_name + line.substr(to_col)

	_extract_code.begin_complex_operation()
	_extract_code.set_line(line_index, replaced_line)
	_extract_code.insert_line_at(line_index, declaration)
	_extract_code.end_complex_operation()

	_extract_code.set_caret_line(line_index + 1)
	_extract_code.set_caret_column(from_col + variable_name.length())
	_extract_code.select(line_index + 1, from_col, line_index + 1, from_col + variable_name.length())


func _get_selection_range(code: CodeEdit) -> Dictionary:
	return {
		"from_line": code.get_selection_from_line(),
		"from_col": code.get_selection_from_column(),
		"to_line": code.get_selection_to_line(),
		"to_col": code.get_selection_to_column(),
	}


func _suggest_extract_name(expression: String) -> String:
	var cleaned := expression.strip_edges()

	if cleaned.ends_with("()"):
		cleaned = cleaned.substr(0, cleaned.length() - 2)

	var dot_index := cleaned.rfind(".")
	if dot_index != -1 and dot_index < cleaned.length() - 1:
		cleaned = cleaned.substr(dot_index + 1)

	var result := ""
	var previous_was_separator := false

	for col in cleaned.length():
		var ch := cleaned[col]
		if _is_identifier_char(ch):
			result += ch.to_lower()
			previous_was_separator = false
		elif not previous_was_separator and not result.is_empty():
			result += "_"
			previous_was_separator = true

	result = result.trim_suffix("_")
	if _is_valid_identifier(result):
		return result

	return "value"


func _begin_rename() -> void:
	_rename_code = _get_current_code_edit()
	if _rename_code == null:
		return

	_rename_script_path = _get_current_script_path()
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

	_rename_prompt_label.text = "Rename '%s' to:" % _rename_symbol
	_rename_name_edit.text = _rename_symbol
	_rename_name_edit.select_all()
	_rename_dialog.min_size = Vector2i(_dialog_width(), 0)
	_rename_dialog.popup_centered(Vector2i(_dialog_width(), 120))
	_rename_name_edit.grab_focus()


func _apply_rename_from_submit(_new_text: String) -> void:
	_rename_dialog.hide()
	_apply_rename()


func _apply_rename() -> void:
	var replacement := _rename_name_edit.text.strip_edges()
	if replacement == _rename_symbol:
		return
	if not _is_valid_identifier(replacement):
		print("Rename Symbol: '%s' is not a valid identifier." % replacement)
		return

	_rename_queued = {
		"uri": _path_to_file_uri(ProjectSettings.globalize_path(_rename_script_path)),
		"line": _rename_symbol_line,
		"character": _rename_symbol_column,
		"new_name": replacement,
	}

	if _rename_ensure_connection():
		_rename_try_send_request()


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
	if _rename_lsp.has_pending_kind("prepare_rename") or _rename_lsp.has_pending_kind("rename"):
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


func _rename_send_open_document_sync_notifications() -> void:
	var target_uri := str(_rename_queued.get("uri", ""))
	var synced_target := false
	var open_script_buffers := _rename_open_script_buffers_by_uri()

	for uri in open_script_buffers:
		var uri_text := str(uri)
		var open_script_buffer: Dictionary = open_script_buffers[uri_text]
		var code: CodeEdit = open_script_buffer.get("code", null)
		if code == null:
			continue

		var text := _get_code_text(code)
		_rename_send_text_document_sync_notification(uri_text, text)
		if uri_text == target_uri:
			synced_target = true

	if not synced_target and not target_uri.is_empty() and _rename_code != null:
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
		call_deferred("_rename_apply_workspace_edit", workspace_edit, str(_rename_queued.get("new_name", "")))
	_rename_queued = {}


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
			SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(open_script_buffer["code"], edits)
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
		if _rename_save_open_script_buffer(open_script_buffer):
			disk_files_changed = true

	if disk_files_changed:
		_rename_scan_resource_filesystem_sources()


func _rename_open_script_buffers_by_uri() -> Dictionary:
	var buffers_by_uri := {}
	var script_editor := EditorInterface.get_script_editor()
	var scripts: Array = script_editor.get_open_scripts()
	var editors: Array = script_editor.get_open_script_editors()
	var count = mini(scripts.size(), editors.size())

	for index in range(count):
		var script: Script = scripts[index]
		if script == null:
			continue

		var script_path := str(script.resource_path)
		if script_path.is_empty() or script_path.contains("::"):
			continue
		if script_path.get_extension() != "gd":
			continue

		var editor = editors[index]
		if editor == null:
			continue

		var base = editor.get_base_editor()
		if not base is CodeEdit:
			continue

		var uri := _path_to_file_uri(ProjectSettings.globalize_path(script_path))
		buffers_by_uri[uri] = {
			"script": script,
			"code": base,
		}

	return buffers_by_uri


func _rename_workspace_edit_to_edits_by_uri(workspace_edit: Variant) -> Dictionary:
	return SmartRenameWorkspaceEdit.workspace_edit_to_edits_by_uri(workspace_edit)


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


func _rename_save_open_script_buffer(open_script_buffer: Dictionary) -> bool:
	var script: Script = open_script_buffer.get("script", null)
	var code: CodeEdit = open_script_buffer.get("code", null)
	if script == null or code == null:
		return false

	var script_path := str(script.resource_path)
	if not SmartRenameWorkspaceEdit.save_code_edit_to_script_path(script, code):
		print("Rename Symbol: could not save %s." % script_path)
		return false

	return true


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
	return SmartRenameWorkspaceEdit.apply_text_edits_to_text(text, edits)


func _rename_line_col_to_offset(text: String, line: int, column: int) -> int:
	return SmartRenameWorkspaceEdit.line_col_to_offset(text, line, column)


func _compare_text_edits_desc(a: Dictionary, b: Dictionary) -> bool:
	return SmartRenameWorkspaceEdit._compare_text_edits_desc(a, b)


func _compare_rename_open_apply_items(a: Dictionary, b: Dictionary) -> bool:
	var a_score := int(a.get("definition_score", 0))
	var b_score := int(b.get("definition_score", 0))
	if a_score != b_score:
		return a_score > b_score

	var a_edits := int(a.get("edits", 0))
	var b_edits := int(b.get("edits", 0))
	if a_edits != b_edits:
		return a_edits > b_edits

	return str(a.get("uri", "")) < str(b.get("uri", ""))


func _rename_definition_score_for_code(code: CodeEdit, edits: Array, symbol: String) -> int:
	if code == null or symbol.is_empty():
		return 0

	var score := 0
	var seen_lines := {}
	for edit in edits:
		if typeof(edit) != TYPE_DICTIONARY:
			continue

		var edit_dict: Dictionary = edit
		var range_value: Variant = edit_dict.get("range", null)
		if typeof(range_value) != TYPE_DICTIONARY:
			continue

		var range_dict: Dictionary = range_value
		var start_value: Variant = range_dict.get("start", null)
		if typeof(start_value) != TYPE_DICTIONARY:
			continue

		var start_dict: Dictionary = start_value
		var line_index := int(start_dict.get("line", -1))
		if line_index < 0 or line_index >= code.get_line_count() or seen_lines.has(line_index):
			continue

		seen_lines[line_index] = true
		var line_score := _rename_declaration_line_score(code.get_line(line_index), symbol)
		if line_score > score:
			score = line_score

	return score


func _rename_declaration_line_score(line: String, symbol: String) -> int:
	var trimmed := line.strip_edges()
	if _rename_line_starts_with_symbol_declaration(trimmed, "const ", symbol):
		return 100
	if _rename_line_starts_with_symbol_declaration(trimmed, "static func ", symbol):
		return 100
	if _rename_line_starts_with_symbol_declaration(trimmed, "func ", symbol):
		return 100
	if _rename_line_starts_with_symbol_declaration(trimmed, "var ", symbol):
		return 90
	if _rename_line_starts_with_symbol_declaration(trimmed, "signal ", symbol):
		return 90
	if _rename_line_starts_with_symbol_declaration(trimmed, "class_name ", symbol):
		return 90
	if _rename_line_contains_symbol_declaration(trimmed, " var ", symbol):
		return 85
	if _rename_line_contains_symbol_declaration(trimmed, " func ", symbol):
		return 80

	return 0


func _rename_line_starts_with_symbol_declaration(line: String, prefix: String, symbol: String) -> bool:
	var candidate := prefix + symbol
	if not line.begins_with(candidate):
		return false
	return _rename_symbol_has_boundary_after(line, candidate.length())


func _rename_line_contains_symbol_declaration(line: String, marker: String, symbol: String) -> bool:
	var candidate := marker + symbol
	var index := line.find(candidate)
	if index == -1:
		return false
	return _rename_symbol_has_boundary_after(line, index + candidate.length())


func _rename_symbol_has_boundary_after(line: String, column: int) -> bool:
	if column >= line.length():
		return true
	return not _is_identifier_char(line[column])


func _rename_reset_connection() -> void:
	_rename_lsp.reset()


func _begin_inline() -> void:
	_inline_code = _get_current_code_edit()
	if _inline_code == null:
		return

	_inline_script_path = _get_current_script_path()
	if _inline_script_path.is_empty():
		print("Inline Variable: could not resolve current script path.")
		return

	var symbol_range := _get_symbol_range_under_caret(_inline_code)
	if symbol_range.is_empty():
		print("Inline Variable: place the caret on a local variable declaration.")
		return

	_inline_symbol = symbol_range["symbol"]
	_inline_symbol_line = symbol_range["line"]
	_inline_symbol_column = symbol_range["column"]
	_inline_expression = _parse_declaration_expression(_inline_code.get_line(_inline_symbol_line), _inline_symbol, _inline_symbol_column)
	if _inline_expression.is_empty():
		print("Inline Variable: caret must be on the variable name in a single-line local var declaration.")
		return

	_inline_uri = _path_to_file_uri(ProjectSettings.globalize_path(_inline_script_path))
	_inline_queued = true

	if _inline_ensure_connection():
		_inline_try_send_references_request()


func _parse_declaration_expression(line: String, symbol: String, symbol_column: int) -> String:
	var stripped_start := _line_indent_chars(line)
	if not line.substr(stripped_start).begins_with("var "):
		return ""

	var declaration_name_start := _skip_spaces(line, stripped_start + 4)
	var declaration_name_end := declaration_name_start
	while declaration_name_end < line.length() and _is_identifier_char(line[declaration_name_end]):
		declaration_name_end += 1

	if declaration_name_start != symbol_column:
		return ""
	if line.substr(declaration_name_start, declaration_name_end - declaration_name_start) != symbol:
		return ""

	var equals_col := line.find("=")
	if equals_col == -1 or equals_col < symbol_column + symbol.length():
		return ""

	if equals_col > 0 and line[equals_col - 1] == "=":
		return ""
	if equals_col < line.length() - 1 and line[equals_col + 1] == "=":
		return ""

	return line.substr(equals_col + 1).strip_edges()


func _is_assignment_operator_at(line: String, col: int) -> bool:
	if col >= line.length():
		return false

	if line[col] == "=":
		if col > 0 and "=<>!".contains(line[col - 1]):
			return false
		return col + 1 >= line.length() or line[col + 1] != "="
	if col < line.length() - 1 and line[col] == ":" and line[col + 1] == "=":
		return true
	if col < line.length() - 1 and "+-*/%&|^".contains(line[col]) and line[col + 1] == "=":
		return true

	return false


func _inline_process_connection() -> void:
	if _inline_lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses := _inline_lsp.poll()
	for response in responses:
		_inline_handle_response(response)
	_inline_try_send_references_request()


func _inline_ensure_connection() -> bool:
	var connected := _inline_lsp.ensure_connection(true)
	if not connected:
		print("Inline Variable: could not connect to the code analysis service.")
	return connected


func _inline_try_send_references_request() -> void:
	if not _inline_queued or not _inline_lsp.is_initialized():
		return
	if _inline_lsp.has_pending_kind("references"):
		return

	_inline_send_document_sync_notification()
	_inline_lsp.send_request("references", "textDocument/references", {
		"textDocument": {
			"uri": _inline_uri,
		},
		"position": {
			"line": _inline_symbol_line,
			"character": _inline_symbol_column,
		},
		"context": {
			"includeDeclaration": true,
		},
	})


func _inline_send_document_sync_notification() -> void:
	_inline_lsp.sync_document(_inline_uri, _get_code_text(_inline_code))


func _inline_handle_response(response: Dictionary) -> void:
	var request_kind := str(response.get("kind", ""))
	var message: Dictionary = response.get("message", {})

	if message.has("error"):
		print("Inline Variable: request failed: %s" % JSON.stringify(message["error"]))
		return

	if request_kind == "references":
		_inline_apply_from_references(message.get("result", []))
		_inline_queued = false


func _inline_apply_from_references(references: Variant) -> void:
	if typeof(references) != TYPE_ARRAY:
		print("Inline Variable: could not read references.")
		return

	if _inline_references_include_reassignment(references):
		print("Inline Variable: refusing to inline '%s' because it appears to be assigned again." % _inline_symbol)
		return

	var edits := _inline_references_to_replacement_edits(references)
	if edits.is_empty():
		print("Inline Variable: no replaceable references found.")
		return

	edits.sort_custom(_compare_reference_edits_desc)

	_inline_code.begin_complex_operation()
	for edit in edits:
		_replace_range_in_code(_inline_code, edit["line"], edit["from_col"], edit["line"], edit["to_col"], _inline_expression)
	_inline_code.remove_line_at(_inline_symbol_line)
	_inline_code.end_complex_operation()
	_inline_code.deselect()


func _inline_references_include_reassignment(references: Array) -> bool:
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY:
			continue
		if reference.get("uri", "") != _inline_uri:
			continue

		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var line_index := int(start["line"])
		var from_col := int(start["character"])
		if line_index == _inline_symbol_line and from_col == _inline_symbol_column:
			continue

		var line := _inline_code.get_line(line_index)
		var after := _skip_spaces(line, from_col + _inline_symbol.length())
		if _is_assignment_operator_at(line, after):
			return true

	return false


func _inline_references_to_replacement_edits(references: Array) -> Array:
	var edits := []
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY:
			continue
		if reference.get("uri", "") != _inline_uri:
			continue

		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var end: Dictionary = range["end"]
		var line := int(start["line"])
		var from_col := int(start["character"])
		var to_col := int(end["character"])

		if line == _inline_symbol_line and from_col == _inline_symbol_column:
			continue
		if _is_member_access_at(_inline_code, line, from_col):
			continue

		edits.append({
			"line": line,
			"from_col": from_col,
			"to_col": to_col,
		})

	return edits


func _compare_reference_edits_desc(a: Dictionary, b: Dictionary) -> bool:
	if a["line"] == b["line"]:
		return a["from_col"] > b["from_col"]
	return a["line"] > b["line"]


func _inline_reset_connection() -> void:
	_inline_lsp.reset()


func _path_to_file_uri(path: String) -> String:
	return LspClient.path_to_file_uri(path)


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
	var current_editor := script_editor.get_current_editor()

	if current_editor == null:
		return null

	var base := current_editor.get_base_editor()
	if base is CodeEdit:
		return base

	return null


func _get_current_script_path() -> String:
	var current_script: Script = EditorInterface.get_script_editor().get_current_script()
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


func _get_selection_range_for_code(code: CodeEdit) -> Dictionary:
	return {
		"from_line": code.get_selection_from_line(),
		"from_col": code.get_selection_from_column(),
		"to_line": code.get_selection_to_line(),
		"to_col": code.get_selection_to_column(),
	}


func _line_indent_chars(line: String) -> int:
	var count := 0
	for col in line.length():
		var ch := line[col]
		if ch == " " or ch == "\t":
			count += 1
		else:
			break
	return count


func _skip_spaces(line: String, col: int) -> int:
	while col < line.length() and line[col] == " ":
		col += 1
	return col


func _is_member_access_at(code: CodeEdit, line_index: int, column: int) -> bool:
	if line_index < 0 or line_index >= code.get_line_count():
		return false

	var line := code.get_line(line_index)
	var previous := column - 1
	while previous >= 0 and line[previous] == " ":
		previous -= 1

	return previous >= 0 and line[previous] == "."


func _is_valid_identifier(value: String) -> bool:
	if value.is_empty():
		return false

	var first := value[0]
	if not _is_identifier_start_char(first):
		return false

	for col in range(1, value.length()):
		if not _is_identifier_char(value[col]):
			return false

	return true


func _is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


func _is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)


func _make_range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return SmartSelectionRange.make_range(from_line, from_col, to_line, to_col)


func _select_range(code: CodeEdit, selection_range: Dictionary) -> void:
	if selection_range["from_line"] == selection_range["to_line"] and selection_range["from_col"] == selection_range["to_col"]:
		code.deselect()
		code.set_caret_line(selection_range["from_line"])
		code.set_caret_column(selection_range["from_col"])
		return

	code.select(
		selection_range["from_line"],
		selection_range["from_col"],
		selection_range["to_line"],
		selection_range["to_col"]
	)


func _range_contains_or_equal(outer: Dictionary, inner: Dictionary) -> bool:
	return SmartSelectionRange.contains_or_equal(outer, inner)


func _range_strictly_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return SmartSelectionRange.strictly_contains(outer, inner)


func _candidate_starts_after_indent_caret(code: CodeEdit, candidate: Dictionary, current: Dictionary) -> bool:
	if current["from_line"] != current["to_line"] or current["from_col"] != current["to_col"]:
		return false
	if candidate["from_line"] != current["from_line"]:
		return false
	if candidate["from_col"] <= current["from_col"]:
		return false
	if candidate["to_line"] != current["from_line"]:
		return false

	var line := code.get_line(current["from_line"])
	var current_col := int(current["from_col"])
	var candidate_col := int(candidate["from_col"])
	if candidate_col > line.length():
		return false

	for col in range(current_col, candidate_col):
		if line[col] != " " and line[col] != "\t":
			return false
	return true


func _ranges_equal(a: Dictionary, b: Dictionary) -> bool:
	return SmartSelectionRange.equal(a, b)


func _compare_positions(line_a: int, col_a: int, line_b: int, col_b: int) -> int:
	return SmartSelectionRange.compare_positions(line_a, col_a, line_b, col_b)
