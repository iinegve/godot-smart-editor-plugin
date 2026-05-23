@tool
extends Node

const FunctionBoundaryGuides := preload("res://addons/smart-editor-plugin/smart_editor/smart_function_boundary_guides.gd")

var _function_separator_guides_enabled_setting: StringName = &""
var _indent_guides_enabled_setting: StringName = &""
var _color_setting: StringName = &""
var _script_editor = null
var _code: CodeEdit
var _guides = null
var _script_path := ""


func configure(
	function_separator_guides_enabled_setting: StringName,
	indent_guides_enabled_setting: StringName,
	color_setting: StringName
) -> void:
	_function_separator_guides_enabled_setting = function_separator_guides_enabled_setting
	_indent_guides_enabled_setting = indent_guides_enabled_setting
	_color_setting = color_setting
	set_process(true)
	_connect_script_editor()
	_attach_to_current_code_edit()


func _exit_tree() -> void:
	_disconnect_script_editor()
	_detach_code_edit()


func _process(_delta: float) -> void:
	if not _any_guides_enabled():
		_detach_code_edit()
		return

	_connect_script_editor()
	_attach_to_current_code_edit()


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

	if _code == null:
		return

	_guides = FunctionBoundaryGuides.new()
	_guides.name = "SmartFunctionBoundaryGuides"
	_guides.z_index = 6
	_guides.configure(_function_separator_guides_enabled_setting, _indent_guides_enabled_setting, _color_setting)
	_code.add_child(_guides)
	_layout_guides()
	_guides.attach_to_code(_code)


func _detach_code_edit() -> void:
	if _guides != null and is_instance_valid(_guides):
		_guides.queue_free()

	_code = null
	_guides = null
	_script_path = ""


func _layout_guides() -> void:
	if _guides == null or not is_instance_valid(_guides):
		return

	_guides.anchor_left = 0.0
	_guides.anchor_right = 1.0
	_guides.anchor_top = 0.0
	_guides.anchor_bottom = 1.0
	_guides.offset_left = 0.0
	_guides.offset_right = 0.0
	_guides.offset_top = 0.0
	_guides.offset_bottom = 0.0


func _any_guides_enabled() -> bool:
	return (
		_bool_setting(_function_separator_guides_enabled_setting, true)
		or _bool_setting(_indent_guides_enabled_setting, true)
	)


func _bool_setting(path: StringName, default_value: bool) -> bool:
	if path == &"":
		return default_value

	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(path):
		return default_value

	return bool(settings.get_setting(path))


func _on_editor_script_changed(_script: Script) -> void:
	_attach_to_current_code_edit()


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
