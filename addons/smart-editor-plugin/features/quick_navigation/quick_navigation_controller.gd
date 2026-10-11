@tool
extends Node

const DoubleShift := preload("res://addons/smart-editor-plugin/features/quick_navigation/double_shift.gd")
const NavigationFileIndex := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_file_index.gd")
const NavigationPopup := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_popup.gd")
const NavigationSymbols := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_symbols.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")

var _files: NavigationPopup
var _symbols: NavigationPopup
var _file_index := NavigationFileIndex.new()
var _double_shift := DoubleShift.new()
var _filesystem: EditorFileSystem
var _files_dirty := true
var _symbol_code: CodeEdit


func _enter_tree() -> void:
	_files = NavigationPopup.new()
	_files.configure(true)
	_files.entry_activated.connect(_open_file)
	_symbols = NavigationPopup.new()
	_symbols.configure(false)
	_symbols.entry_activated.connect(_go_to_symbol)
	_symbols.popup_hide.connect(_restore_symbol_focus)
	var base := EditorInterface.get_base_control()
	base.add_child(_files)
	base.add_child(_symbols)
	_filesystem = EditorInterface.get_resource_filesystem()
	_filesystem.filesystem_changed.connect(_invalidate_files)
	set_process_input(true)


func _exit_tree() -> void:
	if is_instance_valid(_filesystem) and _filesystem.filesystem_changed.is_connected(_invalidate_files):
		_filesystem.filesystem_changed.disconnect(_invalidate_files)
	for popup in [_files, _symbols]:
		if is_instance_valid(popup):
			popup.queue_free()
	_files = null
	_symbols = null


func _input(event: InputEvent) -> void:
	if SmartEditorSettings.get_setting(SmartEditorSettings.SETTING_DOUBLE_SHIFT_ENABLED, true):
		if _double_shift.observe(event, Time.get_ticks_msec()):
			_show_files(NavigationFileIndex.Category.ALL)
			get_viewport().set_input_as_handled()
			return
	else:
		_double_shift.reset()
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var category := NavigationPopup.file_category_for_shortcut(event)
	if category >= 0:
		_show_files(category)
	elif SmartEditorSettings.shortcut_matches(SmartEditorSettings.SETTING_NAVIGATE_SYMBOLS, event):
		if not _show_symbols():
			return
	else:
		return
	get_viewport().set_input_as_handled()


func _invalidate_files() -> void:
	_files_dirty = true


func _show_files(category: int) -> void:
	if _files_dirty:
		_file_index.rebuild(_filesystem.get_filesystem())
		_files_dirty = false
	_symbols.hide()
	_files.show_entries(_file_index.entries, category)


func _show_symbols() -> bool:
	var editor := EditorInterface.get_script_editor()
	var script := editor.get_current_script()
	var current := editor.get_current_editor()
	if not script is GDScript or current == null:
		return false
	var base := current.get_base_editor()
	if not base is CodeEdit:
		return false
	_symbol_code = base
	_files.hide()
	_symbols.show_entries(NavigationSymbols.collect(_symbol_code.text))
	return true


func _open_file(entry: Dictionary) -> void:
	var path: String = entry["path"]
	if not FileAccess.file_exists(path):
		_invalidate_files()
		return
	if entry["category"] == NavigationFileIndex.Category.SCENES:
		EditorInterface.open_scene_from_path(path)
	elif ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Script:
			EditorInterface.edit_script(resource)
			EditorInterface.set_main_screen_editor.call_deferred("Script")
		elif resource != null:
			EditorInterface.edit_resource(resource)
	else:
		# Godot does not expose a generic text-file editor to plugins.
		EditorInterface.select_file(path)


func _go_to_symbol(entry: Dictionary) -> void:
	if not is_instance_valid(_symbol_code):
		return
	var line := clampi(entry["line"], 0, _symbol_code.get_line_count() - 1)
	# Use the editor navigation API to preserve Back/Forward history.
	EditorInterface.get_script_editor().goto_line(line)
	_symbol_code.unfold_line(line)
	_symbol_code.deselect()
	_symbol_code.set_caret_line(line)
	_symbol_code.set_caret_column(entry["column"])
	_symbol_code.center_viewport_to_caret()
	_restore_symbol_focus()


func _restore_symbol_focus() -> void:
	if is_instance_valid(_symbol_code):
		_symbol_code.grab_focus.call_deferred()
