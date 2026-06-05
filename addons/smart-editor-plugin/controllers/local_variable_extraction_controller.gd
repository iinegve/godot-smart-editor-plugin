@tool
extends Node

const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")
const LocalVariableExtractionUseCase := preload("res://addons/smart-editor-plugin/features/local_variable_extraction/use_case.gd")

const IDENTIFIER_DIALOG_WIDTH := 560
const IDENTIFIER_DIALOG_HEIGHT := 150

var _dialog: ConfirmationDialog
var _name_edit: LineEdit
var _prompt_label: Label
var _error_label: Label
var _code: CodeEdit
var _selection_range := {}
var _expression := ""
var _use_case := LocalVariableExtractionUseCase.new()
var _identifier_validator := GDScriptIdentifierValidator.new()


func _enter_tree() -> void:
	_create_dialog()
	set_process_shortcut_input(true)


func _exit_tree() -> void:
	_free_dialog(_dialog)


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_EXTRACT_SHORTCUT, event):
		_begin_extract()
		get_viewport().set_input_as_handled()


func _begin_extract() -> void:
	if not _ensure_dialog():
		print("Extract Local Variable: could not create dialog.")
		return

	_code = _get_current_code_edit()
	if _code == null:
		return

	if not _code.has_selection():
		print("Extract Local Variable: select an expression first.")
		return

	_selection_range = _get_selection_range(_code)
	if _selection_range["from_line"] != _selection_range["to_line"]:
		print("Extract Local Variable: only single-line selections are supported for now.")
		return

	_expression = _code.get_selected_text().strip_edges()
	if _expression.is_empty():
		print("Extract Local Variable: selected expression is empty.")
		return

	_prompt_label.text = "Extract selected expression into local variable:"
	_name_edit.text = _use_case.suggest_name(_expression)
	_name_edit.select_all()
	_refresh_identifier_validation()
	_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_dialog.popup_centered(Vector2i(_identifier_dialog_width(), IDENTIFIER_DIALOG_HEIGHT))
	call_deferred("_refresh_identifier_validation")
	_name_edit.grab_focus()


func _apply_extract_from_submit(_new_text: String) -> void:
	if not _refresh_identifier_validation():
		_name_edit.grab_focus()
		return

	_dialog.hide()
	_apply_extract()


func _apply_extract() -> void:
	if _code == null or _selection_range.is_empty() or _expression.is_empty():
		return

	var variable_name := _name_edit.text.strip_edges()
	var validation_error := _identifier_validation_error(variable_name)
	if not validation_error.is_empty():
		print("Extract Local Variable: %s" % validation_error)
		_refresh_identifier_validation()
		return

	var line_index: int = _selection_range["from_line"]
	var line := _code.get_line(line_index)
	var edit_plan := _use_case.build_edit_plan(
		line,
		_selection_range,
		_expression,
		variable_name
	)
	var declaration := str(edit_plan["declaration"])
	var replaced_line := str(edit_plan["replaced_line"])
	var selection_from_col := int(edit_plan["selection_from_col"])
	var selection_to_col := int(edit_plan["selection_to_col"])

	_code.begin_complex_operation()
	_code.set_line(line_index, replaced_line)
	_code.insert_line_at(line_index, declaration)
	_code.end_complex_operation()

	_code.set_caret_line(line_index + 1)
	_code.set_caret_column(selection_to_col)
	_code.select(line_index + 1, selection_from_col, line_index + 1, selection_to_col)


func _on_name_changed(_new_text: String) -> void:
	_refresh_identifier_validation()


func _refresh_identifier_validation() -> bool:
	if _name_edit == null:
		return false

	var validation_error := _identifier_validation_error(_name_edit.text)
	_set_identifier_validation_state(validation_error)
	return validation_error.is_empty()


func _set_identifier_validation_state(validation_error: String) -> void:
	if _error_label != null:
		_error_label.text = validation_error
		_error_label.visible = not validation_error.is_empty()

	if _dialog != null:
		_dialog.get_ok_button().disabled = not validation_error.is_empty()


func _identifier_validation_error(value: String) -> String:
	return _identifier_validator.identifier_validation_error(value)


func _create_dialog() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Extract Local Variable"
	_dialog.ok_button_text = "Extract"
	_dialog.min_size = Vector2i(_identifier_dialog_width(), 0)
	_dialog.confirmed.connect(_apply_extract)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	_prompt_label = Label.new()
	box.add_child(_prompt_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Variable name"
	_name_edit.keep_editing_on_text_submit = true
	_name_edit.text_submitted.connect(_apply_extract_from_submit)
	_name_edit.text_changed.connect(_on_name_changed)
	box.add_child(_name_edit)

	_error_label = _make_identifier_error_label()
	box.add_child(_error_label)

	_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_dialog)


func _ensure_dialog() -> bool:
	if (
		_dialog != null
		and is_instance_valid(_dialog)
		and _prompt_label != null
		and is_instance_valid(_prompt_label)
		and _name_edit != null
		and is_instance_valid(_name_edit)
		and _error_label != null
		and is_instance_valid(_error_label)
	):
		return true

	_free_dialog(_dialog)
	_dialog = null
	_prompt_label = null
	_name_edit = null
	_error_label = null
	_create_dialog()
	return _dialog != null and is_instance_valid(_dialog)


func _make_identifier_error_label() -> Label:
	var label := Label.new()
	label.visible = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	return label


func _free_dialog(dialog: Window) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return

	var parent: Node = dialog.get_parent()
	if parent != null:
		parent.remove_child(dialog)
	dialog.queue_free()


func _dialog_width() -> int:
	return int(SmartEditorSettings.get_setting(SmartEditorSettings.SETTING_DIALOG_WIDTH, 420))


func _identifier_dialog_width() -> int:
	return maxi(_dialog_width(), IDENTIFIER_DIALOG_WIDTH)


func _get_selection_range(code: CodeEdit) -> Dictionary:
	return {
		"from_line": code.get_selection_from_line(),
		"from_col": code.get_selection_from_column(),
		"to_line": code.get_selection_to_line(),
		"to_col": code.get_selection_to_column(),
	}


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
