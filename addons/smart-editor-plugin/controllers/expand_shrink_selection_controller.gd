@tool
extends Node

const SmartSelectionRange := preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const ExpandShrinkSelectionUseCase := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/use_case.gd")

var _use_case := ExpandShrinkSelectionUseCase.new()


func _enter_tree() -> void:
	set_process_shortcut_input(true)


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_SHRINK_SHORTCUT, event):
		var code := _get_current_code_edit()
		if code != null:
			_shrink_selection(code)
			get_viewport().set_input_as_handled()
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_EXPAND_SHORTCUT, event):
		var code := _get_current_code_edit()
		if code != null:
			_expand_selection(code)
			get_viewport().set_input_as_handled()
		return


func _expand_selection(code: CodeEdit) -> void:
	var current := _get_current_range(code)
	var target := _use_case.next_expand_range(_get_code_text(code), current)
	if not target.is_empty():
		_select_range(code, target)


func _shrink_selection(code: CodeEdit) -> void:
	var current := _get_current_range(code)
	var target := _use_case.next_shrink_range(_get_code_text(code), current)
	if not target.is_empty():
		_select_range(code, target)


func _get_current_range(code: CodeEdit) -> Dictionary:
	if code.has_selection():
		return SmartSelectionRange.make_range(
			code.get_selection_from_line(),
			code.get_selection_from_column(),
			code.get_selection_to_line(),
			code.get_selection_to_column()
		)

	return SmartSelectionRange.make_range(
		code.get_caret_line(),
		code.get_caret_column(),
		code.get_caret_line(),
		code.get_caret_column()
	)


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


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)
