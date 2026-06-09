@tool
extends Node

# Feature shell: registers settings/shortcuts and coordinates editor state, dock, index, and resolver.

const CallHierarchyCallSite := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_call_site.gd")
const CallHierarchyDock := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_dock.gd")
const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")
const CallHierarchyResolver := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_resolver.gd")
const CallHierarchyTreeNode := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_tree_node.gd")
const GDScriptProjectIndex := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_project_index.gd")
const GDScriptTextIntrospection := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_text_introspection.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")

const SETTINGS_PREFIX := &"plugin/smart_editor/"
const SETTING_CALL_HIERARCHY_PREFIX := SETTINGS_PREFIX + &"call_hierarchy/"
const STANDALONE_SETTINGS_PREFIX := &"plugin/call_hierarchy/"
const SETTING_ENABLED := SETTING_CALL_HIERARCHY_PREFIX + &"enabled"
const SETTING_TREE_FONT_SIZE := SETTING_CALL_HIERARCHY_PREFIX + &"tree_font_size"
const SETTING_MAX_NODES := SETTING_CALL_HIERARCHY_PREFIX + &"max_nodes"
const SETTING_SHOW_SHORTCUT := SETTING_CALL_HIERARCHY_PREFIX + &"show_call_hierarchy"
const SETTING_GO_TO_SHORTCUT := SETTING_CALL_HIERARCHY_PREFIX + &"go_to_selected_method"
const LEGACY_SETTING_ENABLED := SETTINGS_PREFIX + &"call_hierarchy_enabled"
const LEGACY_SETTING_TREE_FONT_SIZE := SETTINGS_PREFIX + &"call_hierarchy_tree_font_size"
const LEGACY_SETTING_MAX_NODES := SETTINGS_PREFIX + &"call_hierarchy_max_nodes"
const LEGACY_SETTING_SHOW_SHORTCUT := SETTINGS_PREFIX + &"show_call_hierarchy"
const LEGACY_SETTING_GO_TO_SHORTCUT := SETTINGS_PREFIX + &"call_hierarchy_go_to_selected_method"
const STANDALONE_SETTING_ENABLED := STANDALONE_SETTINGS_PREFIX + &"enabled"
const STANDALONE_SETTING_TREE_FONT_SIZE := STANDALONE_SETTINGS_PREFIX + &"tree_font_size"
const STANDALONE_SETTING_MAX_NODES := STANDALONE_SETTINGS_PREFIX + &"max_nodes"
const STANDALONE_SETTING_SHOW_SHORTCUT := STANDALONE_SETTINGS_PREFIX + &"show_call_hierarchy"
const STANDALONE_SETTING_GO_TO_SHORTCUT := STANDALONE_SETTINGS_PREFIX + &"go_to_selected_method"
const STANDALONE_SETTING_DEBUG_LOGS := STANDALONE_SETTINGS_PREFIX + &"debug_logs"
const STANDALONE_SETTING_DEBUG_LOGS_ENABLED := STANDALONE_SETTINGS_PREFIX + &"debug_logs_enabled"
const STANDALONE_SETTING_DIAGNOSTICS_DEBUG_LOGS := STANDALONE_SETTINGS_PREFIX + &"diagnostics/debug_logs_enabled"
const REMOVED_SETTING_DEBUG_LOGS := SETTINGS_PREFIX + &"debug_logs"
const REMOVED_SETTING_DIAGNOSTICS_DEBUG_LOGS := SETTINGS_PREFIX + &"diagnostics/debug_logs_enabled"
const DEFAULT_TREE_FONT_SIZE := 28

var _code: CodeEdit
var _current_uri := ""
var _dock: CallHierarchyDock
var _lsp_service: Node
var _node_count := 0
var _plugin: EditorPlugin
var _project_index: GDScriptProjectIndex
var _resolver: CallHierarchyResolver


func configure(plugin: EditorPlugin, lsp_service: Node) -> void:
	_plugin = plugin
	_lsp_service = lsp_service
	_ensure_collaborators()


func _enter_tree() -> void:
	_ensure_collaborators()
	_init_settings()
	set_process_shortcut_input(true)
	set_process(true)


func _exit_tree() -> void:
	if _dock != null:
		_dock.destroy()


func _process(_delta: float) -> void:
	if not _call_hierarchy_enabled() and _dock != null:
		_dock.destroy()


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if _is_focus_editor_shortcut(event) and _dock_has_focus():
		_focus_editor()
		get_viewport().set_input_as_handled()
		return

	if not _is_call_hierarchy_shortcut(event):
		return

	if not _call_hierarchy_enabled():
		return

	_begin_call_hierarchy()
	get_viewport().set_input_as_handled()


func _is_call_hierarchy_shortcut(event: InputEvent) -> bool:
	var shortcut = _get_plugin_setting(SETTING_SHOW_SHORTCUT, null)
	return shortcut is Shortcut and shortcut.matches_event(event)


func _init_settings() -> void:
	_init_setting_from_legacy_paths(SETTING_ENABLED, true, TYPE_BOOL, PROPERTY_HINT_NONE, "", [
		LEGACY_SETTING_ENABLED,
		STANDALONE_SETTING_ENABLED,
	])
	_init_setting_from_legacy_paths(SETTING_TREE_FONT_SIZE, DEFAULT_TREE_FONT_SIZE, TYPE_INT, PROPERTY_HINT_RANGE, "8,48,1", [
		LEGACY_SETTING_TREE_FONT_SIZE,
		STANDALONE_SETTING_TREE_FONT_SIZE,
	])
	_init_setting_from_legacy_paths(SETTING_MAX_NODES, 250, TYPE_INT, PROPERTY_HINT_RANGE, "25,2000,25", [
		LEGACY_SETTING_MAX_NODES,
		STANDALONE_SETTING_MAX_NODES,
	])
	_init_shortcut_setting_from_legacy_paths(SETTING_SHOW_SHORTCUT, _make_shortcut(KEY_H, false, true, true), [
		LEGACY_SETTING_SHOW_SHORTCUT,
		STANDALONE_SETTING_SHOW_SHORTCUT,
	])
	_init_shortcut_setting_from_legacy_paths(SETTING_GO_TO_SHORTCUT, _make_shortcut(KEY_F4, false, false), [
		LEGACY_SETTING_GO_TO_SHORTCUT,
		STANDALONE_SETTING_GO_TO_SHORTCUT,
	])
	_erase_removed_settings([
		REMOVED_SETTING_DEBUG_LOGS,
		REMOVED_SETTING_DIAGNOSTICS_DEBUG_LOGS,
		STANDALONE_SETTING_DEBUG_LOGS,
		STANDALONE_SETTING_DEBUG_LOGS_ENABLED,
		STANDALONE_SETTING_DIAGNOSTICS_DEBUG_LOGS,
	])


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
	var legacy_paths: Array = []
	if legacy_path != &"":
		legacy_paths.append(legacy_path)
	_init_shortcut_setting_from_legacy_paths(path, default_shortcut, legacy_paths)


func _init_shortcut_setting_from_legacy_paths(path: StringName, default_shortcut: Shortcut, legacy_paths: Array = []) -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		var shortcut: Variant = default_shortcut
		for legacy_path in legacy_paths:
			if settings.has_setting(legacy_path):
				shortcut = settings.get_setting(legacy_path)
				break
		settings.set_setting(path, shortcut)
	settings.set_initial_value(path, default_shortcut, false)
	settings.add_property_info({
		"name": path,
		"type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "Shortcut",
	})
	for legacy_path in legacy_paths:
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


func _tree_font_size() -> int:
	return clampi(int(_get_plugin_setting(SETTING_TREE_FONT_SIZE, DEFAULT_TREE_FONT_SIZE)), 8, 48)


func _max_nodes() -> int:
	return int(_get_plugin_setting(SETTING_MAX_NODES, 250))


func _call_hierarchy_enabled() -> bool:
	return bool(_get_plugin_setting(SETTING_ENABLED, true))


func _make_shortcut(keycode: Key, meta_pressed: bool, ctrl_pressed: bool, alt_pressed: bool = false) -> Shortcut:
	var shortcut := Shortcut.new()
	var event := InputEventKey.new()
	event.device = -1
	event.keycode = keycode
	event.meta_pressed = meta_pressed
	event.ctrl_pressed = ctrl_pressed
	event.alt_pressed = alt_pressed
	shortcut.events = [event]
	return shortcut


func _begin_call_hierarchy() -> void:
	if not _call_hierarchy_enabled():
		return

	_ensure_collaborators()
	_dock.ensure_created()
	_dock.show()

	_code = _get_current_code_edit()
	if _code == null:
		return

	var script_path := _get_current_script_path()
	if script_path.is_empty():
		print("Call Hierarchy: could not resolve current script path.")
		return

	_current_uri = SmartEditorFiles.path_to_file_uri(ProjectSettings.globalize_path(script_path))
	_project_index.clear()
	_project_index.configure_current_buffer(_current_uri, _code)
	_dock.clear()
	_node_count = 0

	var symbol_range := GDScriptTextIntrospection.selected_or_current_symbol_range(_code)
	if symbol_range.is_empty():
		symbol_range = GDScriptTextIntrospection.enclosing_function_symbol_range(_code, _code.get_caret_line())
	if symbol_range.is_empty():
		print("Call Hierarchy: place the caret on a function name or call.")
		return

	var root_method := _resolver.root_method(_current_uri, symbol_range)
	var root_visited := {}
	root_visited[root_method.symbol_key()] = true
	var is_engine_callback := _resolver.is_engine_callback_method(root_method.name)
	var root_node: CallHierarchyTreeNode = CallHierarchyTreeNode.create(
		root_method,
		root_method.line,
		root_method.character,
		_project_index.format_method_label(root_method.uri, root_method.name),
		is_engine_callback,
		root_visited,
		"Godot engine callback" if is_engine_callback else ""
	)
	_node_count = 1
	_dock.set_root(root_node)

	if _resolver.is_constructor_method(root_method.name):
		_load_constructor_callers(root_node)
	elif not is_engine_callback:
		_load_references_for_node(root_node)


func _load_node(node: CallHierarchyTreeNode) -> void:
	if node == null or node.method == null:
		return
	if _resolver.is_constructor_method(node.method.name):
		_load_constructor_callers(node)
	else:
		_load_references_for_node(node)


func _load_references_for_node(node: CallHierarchyTreeNode) -> void:
	if _lsp_service == null:
		print("Call Hierarchy: code analysis service is not configured.")
		_dock.mark_node_loaded(node, "request failed")
		return

	_dock.mark_node_loading(node)
	var response = await _resolver.references_for_method(node.method)
	if _dock == null:
		return
	if response == null:
		print("Call Hierarchy: code analysis service is not configured.")
		_dock.mark_node_loaded(node, "request failed")
		return
	if not response.ok:
		print("Call Hierarchy: request failed: %s" % JSON.stringify(response.error))
		_dock.mark_node_loaded(node, "request failed")
		return
	if typeof(response.result) != TYPE_ARRAY:
		print("Call Hierarchy: could not read references.")
		_dock.mark_node_loaded(node, "could not read references")
		return

	_render_call_sites(
		node,
		_resolver.references_to_call_sites(response.result, node.method),
		"No callers found"
	)


func _load_constructor_callers(node: CallHierarchyTreeNode) -> void:
	_dock.mark_node_loading(node)
	_render_call_sites(
		node,
		_resolver.constructor_call_sites_for_uri(node.method.uri),
		"No constructor callers found"
	)


func _render_call_sites(parent_node: CallHierarchyTreeNode, call_sites: Array[CallHierarchyCallSite], empty_text: String) -> void:
	var child_nodes: Array[CallHierarchyTreeNode] = []
	var limit_reached := false
	for call_site in call_sites:
		var caller_key := call_site.method.symbol_key()
		if parent_node.visited.has(caller_key):
			continue
		if _node_count >= _max_nodes():
			limit_reached = true
			break

		var child_visited := parent_node.visited.duplicate()
		child_visited[caller_key] = true
		var is_engine_callback := _resolver.is_engine_callback_method(call_site.method.name)
		var base_text := "%s - %s" % [
			_project_index.format_method_label(call_site.method.uri, call_site.method.name),
			_project_index.display_location(call_site.method.uri, call_site.open_line),
		]
		child_nodes.append(CallHierarchyTreeNode.from_call_site(
			call_site,
			base_text,
			is_engine_callback,
			child_visited,
			"Godot engine callback" if is_engine_callback else ""
		))
		_node_count += 1

	_dock.render_children(parent_node, child_nodes, empty_text, limit_reached)


func _focus_editor() -> void:
	var code := _code
	if code == null or not is_instance_valid(code):
		code = _get_current_code_edit()
	if code == null:
		return

	code.grab_focus()


func _dock_has_focus() -> bool:
	return _dock != null and _dock.has_focus(get_viewport())


static func _is_focus_editor_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false

	var key_event := event as InputEventKey
	return key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE


func _open_script_location(uri: String, line_index: int, column: int) -> void:
	var path := ProjectSettings.localize_path(SmartEditorFiles.file_uri_to_path(uri))
	var script := load(path)
	if script == null:
		print("Call Hierarchy: could not open %s." % path)
		return

	EditorInterface.edit_resource(script)
	call_deferred("_focus_script_location", line_index, column)


func _focus_script_location(line_index: int, column: int) -> void:
	var code := _get_current_code_edit()
	if code == null:
		return

	code.grab_focus()
	code.set_caret_line(clampi(line_index, 0, code.get_line_count() - 1))
	code.set_caret_column(maxi(column, 0))
	if code.has_method("center_viewport_to_caret"):
		code.center_viewport_to_caret()


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
	if current_script == null:
		return ""

	var script_path := current_script.resource_path
	if script_path.is_empty() or script_path.get_extension().to_lower() != "gd":
		return ""

	return script_path


func _ensure_collaborators() -> void:
	if _project_index == null:
		_project_index = GDScriptProjectIndex.new()
	if _resolver == null:
		_resolver = CallHierarchyResolver.new()
	_resolver.configure(_lsp_service, _project_index)
	if _dock == null:
		_dock = CallHierarchyDock.new()
	_dock.configure(
		_plugin,
		Callable(self, "_tree_font_size"),
		Callable(self, "_go_to_shortcut"),
		Callable(self, "_load_node"),
		Callable(self, "_open_script_location"),
		Callable(self, "_focus_editor")
	)


func _go_to_shortcut() -> Variant:
	return _get_plugin_setting(SETTING_GO_TO_SHORTCUT, null)
