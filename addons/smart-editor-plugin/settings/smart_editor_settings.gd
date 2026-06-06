@tool
extends RefCounted

const SmartFunctionBoundaryGuides := preload("res://addons/smart-editor-plugin/features/function_boundary_guides/smart_function_boundary_guides.gd")
const SmartSymbolUsageHighlight := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_highlight.gd")

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
const SETTING_FUNCTION_SEPARATOR_GUIDES_ENABLED := SETTING_FUNCTION_BOUNDARY_PREFIX + &"show_function_separator_guides"
const SETTING_FUNCTION_BOUNDARY_INDENT_GUIDES_ENABLED := SETTING_FUNCTION_BOUNDARY_PREFIX + &"show_indent_guides"
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
const PREVIOUS_SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED := SETTING_FUNCTION_BOUNDARY_PREFIX + &"show_guides"
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
const REMOVED_SETTING_RENAME_MULTI_FILE_WARNING_ENABLED := SETTING_EDITOR_PREFIX + &"show_multi_file_rename_warning"
const REMOVED_SETTING_RENAME_MULTI_FILE_WARNING_DISMISSED := SETTING_EDITOR_PREFIX + &"rename_multi_file_warning_dismissed"

const HOST := "127.0.0.1"
const PORT := 6005


static func init_editor_settings() -> void:
	_init_setting(SETTING_DIALOG_WIDTH, 420, TYPE_INT, PROPERTY_HINT_RANGE, "300,900,10", LEGACY_SETTING_DIALOG_WIDTH)
	_init_shortcut_setting(SETTING_EXPAND_SHORTCUT, _make_shortcut(KEY_D, true, false), LEGACY_SETTING_EXPAND_SHORTCUT)
	_init_shortcut_setting(SETTING_SHRINK_SHORTCUT, _make_shortcut(KEY_D, true, false, false, true), LEGACY_SETTING_SHRINK_SHORTCUT)
	_init_shortcut_setting(SETTING_EXTRACT_SHORTCUT, _make_shortcut(KEY_V, true, true), LEGACY_SETTING_EXTRACT_SHORTCUT)
	_init_shortcut_setting(SETTING_RENAME_SHORTCUT, _make_shortcut(KEY_R, true, true), LEGACY_SETTING_RENAME_SHORTCUT)
	_init_shortcut_setting(SETTING_INLINE_SHORTCUT, _make_shortcut(KEY_N, true, true), LEGACY_SETTING_INLINE_SHORTCUT)
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
		REMOVED_SETTING_RENAME_MULTI_FILE_WARNING_ENABLED,
		REMOVED_SETTING_RENAME_MULTI_FILE_WARNING_DISMISSED,
	])


static func init_highlight_settings() -> void:
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


static func init_function_boundary_settings() -> void:
	_init_setting(SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR, SmartFunctionBoundaryGuides.DEFAULT_GUIDE_COLOR, TYPE_COLOR, PROPERTY_HINT_NONE, "", LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR)
	_init_setting_from_legacy_paths(SETTING_FUNCTION_SEPARATOR_GUIDES_ENABLED, true, TYPE_BOOL, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED,
		PREVIOUS_SETTING_FUNCTION_BOUNDARY_GUIDES_ENABLED,
	])
	_init_setting(SETTING_FUNCTION_BOUNDARY_INDENT_GUIDES_ENABLED, true, TYPE_BOOL)


static func get_setting(path: StringName, default_value: Variant) -> Variant:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		return default_value
	return settings.get_setting(path)


static func set_setting(path: StringName, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_setting(path, value)


static func shortcut_matches(path: StringName, event: InputEvent) -> bool:
	var shortcut = get_setting(path, null)
	return shortcut is Shortcut and shortcut.matches_event(event)


static func _init_setting(path: StringName, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", legacy_path: StringName = &"") -> void:
	var legacy_paths: Array = []
	if legacy_path != &"":
		legacy_paths.append(legacy_path)
	_init_setting_from_legacy_paths(path, default_value, type, hint, hint_string, legacy_paths)


static func _init_setting_from_legacy_paths(path: StringName, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", legacy_paths: Array = []) -> void:
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


static func _init_shortcut_setting(path: StringName, default_shortcut: Shortcut, legacy_path: StringName = &"") -> void:
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


static func _erase_legacy_setting(path: StringName, legacy_path: StringName) -> void:
	if legacy_path == &"" or legacy_path == path:
		return

	_erase_setting(legacy_path)


static func _erase_removed_settings(paths: Array) -> void:
	for path in paths:
		_erase_setting(path)


static func _erase_setting(path: StringName) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(path):
		settings.erase(path)


static func _make_shortcut(keycode: Key, meta_pressed: bool, ctrl_pressed: bool, alt_pressed: bool = false, shift_pressed: bool = false) -> Shortcut:
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
