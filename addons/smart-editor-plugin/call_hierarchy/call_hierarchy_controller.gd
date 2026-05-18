@tool
extends Node

const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const SETTINGS_PREFIX := &"plugin/smart_editor/"
const SETTING_ENABLED := SETTINGS_PREFIX + &"call_hierarchy_enabled"
const SETTING_TREE_FONT_SIZE := SETTINGS_PREFIX + &"call_hierarchy_tree_font_size"
const SETTING_MAX_NODES := SETTINGS_PREFIX + &"call_hierarchy_max_nodes"
const SETTING_DEBUG_LOGS := SETTINGS_PREFIX + &"debug_logs"
const SETTING_SHOW_SHORTCUT := SETTINGS_PREFIX + &"show_call_hierarchy"
const SETTING_GO_TO_SHORTCUT := SETTINGS_PREFIX + &"call_hierarchy_go_to_selected_method"
const DEFAULT_TREE_FONT_SIZE := 28
const HOST := "127.0.0.1"
const PORT := 6005
const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
const ENGINE_CALLBACK_METHODS := {
	"_can_drop_data": true,
	"_draw": true,
	"_drop_data": true,
	"_enter_tree": true,
	"_exit_tree": true,
	"_get": true,
	"_get_configuration_warnings": true,
	"_get_cursor_shape": true,
	"_get_drag_data": true,
	"_get_minimum_size": true,
	"_get_property_list": true,
	"_get_tooltip": true,
	"_gui_input": true,
	"_has_point": true,
	"_input": true,
	"_input_event": true,
	"_integrate_forces": true,
	"_iter_get": true,
	"_iter_init": true,
	"_iter_next": true,
	"_make_custom_tooltip": true,
	"_notification": true,
	"_physics_process": true,
	"_process": true,
	"_property_can_revert": true,
	"_property_get_revert": true,
	"_ready": true,
	"_set": true,
	"_shortcut_input": true,
	"_tile_data_runtime_update": true,
	"_to_string": true,
	"_unhandled_input": true,
	"_unhandled_key_input": true,
	"_use_tile_data_runtime_update": true,
	"_validate_property": true,
}

var _panel: VBoxContainer
var _toolbar: HBoxContainer
var _go_to_button: Button
var _tree: Tree
var _code: CodeEdit
var _current_uri := ""
var _lsp := LspClient.new()
var _queued_requests: Array[Dictionary] = []
var _file_cache := {}
var _script_display_name_cache := {}
var _node_count := 0
var _plugin: EditorPlugin


func configure(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_lsp.configure("Call Hierarchy", HOST, PORT, {}, _debug)


func _enter_tree() -> void:
	_init_settings()
	set_process_shortcut_input(true)
	set_process(true)


func _exit_tree() -> void:
	_destroy_dock()
	_lsp.disconnect_from_host()


func _process(_delta: float) -> void:
	if not _call_hierarchy_enabled():
		_destroy_dock()
		_reset_connection()
		return

	_process_connection()


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
	_init_setting(SETTING_ENABLED, true, TYPE_BOOL)
	_init_setting(SETTING_TREE_FONT_SIZE, DEFAULT_TREE_FONT_SIZE, TYPE_INT, PROPERTY_HINT_RANGE, "8,48,1")
	_init_setting(SETTING_MAX_NODES, 250, TYPE_INT, PROPERTY_HINT_RANGE, "25,2000,25")
	_init_setting(SETTING_DEBUG_LOGS, false, TYPE_BOOL)
	_init_shortcut_setting(SETTING_SHOW_SHORTCUT, _make_shortcut(KEY_H, false, true, true))
	_init_shortcut_setting(SETTING_GO_TO_SHORTCUT, _make_shortcut(KEY_F4, false, false))


func _init_setting(path: StringName, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		settings.set_setting(path, default_value)
	settings.set_initial_value(path, default_value, false)
	settings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})


func _init_shortcut_setting(path: StringName, default_shortcut: Shortcut) -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		settings.set_setting(path, default_shortcut)
	settings.set_initial_value(path, default_shortcut, false)
	settings.add_property_info({
		"name": path,
		"type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "Shortcut",
	})


func _get_plugin_setting(path: StringName, default_value: Variant) -> Variant:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(path):
		return default_value
	return settings.get_setting(path)


func _tree_font_size() -> int:
	return clampi(int(_get_plugin_setting(SETTING_TREE_FONT_SIZE, DEFAULT_TREE_FONT_SIZE)), 8, 48)


func _max_nodes() -> int:
	return int(_get_plugin_setting(SETTING_MAX_NODES, 250))


func _debug_logs_enabled() -> bool:
	return bool(_get_plugin_setting(SETTING_DEBUG_LOGS, false))


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


func _create_dock() -> void:
	if _panel != null:
		return

	_panel = VBoxContainer.new()
	_panel.name = "Call Hierarchy"
	_panel.add_theme_constant_override("separation", 6)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	_panel.add_child(_toolbar)

	_go_to_button = Button.new()
	_go_to_button.tooltip_text = "Go to selected method"
	_go_to_button.focus_mode = Control.FOCUS_NONE
	_apply_go_to_button_icon()
	_go_to_button.pressed.connect(_open_selected_item)
	_toolbar.add_child(_go_to_button)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = false
	_tree.columns = 1
	_apply_tree_font_size()
	_tree.item_activated.connect(_open_selected_item)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_tree.gui_input.connect(_on_tree_gui_input)
	_panel.add_child(_tree)

	if _plugin != null:
		_plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _panel)
	call_deferred("_apply_dock_tab_icon")


func _apply_go_to_button_icon() -> void:
	var base_control := EditorInterface.get_base_control()
	for icon_name in ["ExternalLink", "MoveRight", "ArrowRight", "Forward", "Play"]:
		if base_control.has_theme_icon(icon_name, "EditorIcons"):
			_go_to_button.icon = base_control.get_theme_icon(icon_name, "EditorIcons")
			_go_to_button.text = ""
			return
	_go_to_button.text = "Go"


func _apply_dock_tab_icon() -> void:
	if _panel == null:
		return

	var icon := _get_call_hierarchy_icon()
	if icon == null:
		return

	if _plugin != null:
		_plugin.set_dock_tab_icon(_panel, icon)


func _destroy_dock() -> void:
	if _panel == null:
		return

	_queued_requests.clear()
	_file_cache.clear()
	_script_display_name_cache.clear()
	_current_uri = ""
	_code = null
	_node_count = 0
	if _plugin != null:
		_plugin.remove_control_from_docks(_panel)
	_panel.queue_free()
	_panel = null
	_toolbar = null
	_go_to_button = null
	_tree = null


func _get_call_hierarchy_icon() -> Texture2D:
	var base_control := EditorInterface.get_base_control()
	for icon_name in ["ClassList", "Hierarchy", "Tree", "GraphNode", "Callable", "MethodOverride", "MemberMethod", "Signals"]:
		if base_control.has_theme_icon(icon_name, "EditorIcons"):
			return base_control.get_theme_icon(icon_name, "EditorIcons")
	return null


func _apply_tree_font_size() -> void:
	if _tree == null:
		return

	var font_size := _tree_font_size()
	_tree.add_theme_font_size_override("font_size", font_size)
	_tree.add_theme_font_size_override("title_button_font_size", font_size)


func _set_item_text(item: TreeItem, text: String) -> void:
	item.set_text(0, text)
	item.set_custom_font_size(0, _tree_font_size())


func _begin_call_hierarchy() -> void:
	if not _call_hierarchy_enabled():
		return
	if _panel == null:
		_create_dock()

	_show_dock()

	_code = _get_current_code_edit()
	if _code == null:
		return

	var script_path := _get_current_script_path()
	if script_path.is_empty():
		print("Call Hierarchy: could not resolve current script path.")
		return

	_current_uri = _path_to_file_uri(ProjectSettings.globalize_path(script_path))
	_file_cache.clear()
	_script_display_name_cache.clear()
	_tree.clear()
	_node_count = 0

	var symbol_range := _get_selected_or_current_symbol_range(_code)
	if symbol_range.is_empty():
		symbol_range = _get_enclosing_function_symbol_range(_code, _code.get_caret_line())
	if symbol_range.is_empty():
		print("Call Hierarchy: place the caret on a function name or call.")
		return

	var root_symbol := _call_hierarchy_root_symbol(_current_uri, symbol_range)
	var root_visited := {}
	root_visited[_symbol_key(root_symbol["uri"], root_symbol["line"], root_symbol["symbol"])] = true

	var root := _tree.create_item()
	var root_text := _format_method_label(root_symbol["uri"], root_symbol["symbol"])
	_set_item_text(root, root_text)
	root.set_metadata(0, {
		"name": root_symbol["symbol"],
		"uri": root_symbol["uri"],
		"line": root_symbol["line"],
		"character": root_symbol["column"],
		"open_line": root_symbol["line"],
		"open_character": root_symbol["column"],
		"base_text": root_text,
		"loaded": _is_engine_callback_method(root_symbol["symbol"]),
		"visited": root_visited,
	})
	root.set_collapsed(false)
	root.select(0)
	_node_count = 1

	if _is_engine_callback_method(root_symbol["symbol"]):
		_add_engine_callback_leaf(root)
	elif _is_constructor_method(root_symbol["symbol"]):
		_apply_constructor_callers({
			"item": root,
			"uri": root_symbol["uri"],
			"line": root_symbol["line"],
			"visited": root_visited,
		})
	else:
		_queue_request(root)


func _show_dock() -> void:
	if _panel == null:
		return

	_apply_tree_font_size()
	_apply_dock_tab_icon()
	_panel.show()

	var parent := _panel.get_parent()
	while parent != null:
		if parent is CanvasItem:
			(parent as CanvasItem).show()
		if parent is TabContainer:
			var tabs := parent as TabContainer
			for index in tabs.get_tab_count():
				if tabs.get_tab_control(index) == _panel:
					tabs.current_tab = index
					call_deferred("_focus_tree")
					return
		parent = parent.get_parent()

	call_deferred("_focus_tree")


func _focus_tree() -> void:
	if _tree != null:
		_tree.grab_focus()


func _expand_selected_item() -> void:
	var item := _tree.get_selected()
	if item == null:
		return

	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	if bool(metadata.get("loaded", false)):
		return

	_load_callers_for_item(item, metadata)


func _on_item_collapsed(item: TreeItem) -> void:
	if item == null or item.is_collapsed():
		return

	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	if bool(metadata.get("loaded", false)):
		return

	_load_callers_for_item(item, metadata)


func _load_callers_for_item(item: TreeItem, metadata: Dictionary) -> void:
	if _is_constructor_method(str(metadata.get("name", ""))):
		var request := metadata.duplicate()
		request["item"] = item
		_apply_constructor_callers(request)
		return

	_queue_request(item)


func _on_tree_gui_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if _is_focus_editor_shortcut(event):
		_focus_editor()
		_tree.get_viewport().set_input_as_handled()
		return

	var shortcut = _get_plugin_setting(SETTING_GO_TO_SHORTCUT, null)
	if shortcut is Shortcut and shortcut.matches_event(event):
		_open_selected_item()
		_tree.get_viewport().set_input_as_handled()


func _open_selected_item() -> void:
	var item := _tree.get_selected()
	if item == null:
		return

	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	if not metadata.has("uri") or not metadata.has("line"):
		return

	_open_script_location(
		metadata["uri"],
		int(metadata.get("open_line", metadata["line"])),
		int(metadata.get("open_character", metadata.get("character", 0)))
	)


func _focus_editor() -> void:
	var code := _code
	if code == null or not is_instance_valid(code):
		code = _get_current_code_edit()
	if code == null:
		return

	code.grab_focus()


func _dock_has_focus() -> bool:
	if _panel == null or not is_instance_valid(_panel):
		return false

	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner != null and (focus_owner == _panel or _panel.is_ancestor_of(focus_owner))


static func _is_focus_editor_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false

	var key_event := event as InputEventKey
	return key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE


func _queue_request(item: TreeItem) -> void:
	var metadata: Dictionary = item.get_metadata(0)
	metadata["loaded"] = false
	item.set_metadata(0, metadata)
	_set_item_text(item, "%s (loading...)" % metadata.get("base_text", metadata.get("name", "symbol")))
	_clear_children(item)

	_queued_requests.append({
		"item": item,
		"name": metadata["name"],
		"uri": metadata["uri"],
		"line": metadata["line"],
		"character": metadata["character"],
		"visited": metadata.get("visited", {}),
	})

	if _ensure_connection():
		_try_send_queued_requests()


func _process_connection() -> void:
	if _lsp.get_status() == StreamPeerTCP.STATUS_NONE:
		return

	var responses := _lsp.poll()
	for response in responses:
		_handle_response(response)
	_try_send_queued_requests()


func _ensure_connection() -> bool:
	var connected := _lsp.ensure_connection(true)
	if not connected:
		print("Call Hierarchy: could not connect to the code analysis service.")
	return connected


func _try_send_queued_requests() -> void:
	if not _lsp.is_initialized():
		return

	while not _queued_requests.is_empty():
		var request: Dictionary = _queued_requests.pop_front()
		_send_document_sync_notification(request["uri"])

		var context := {
			"kind": "references",
			"item": request["item"],
			"name": request["name"],
			"uri": request["uri"],
			"line": request["line"],
			"character": request["character"],
			"visited": request.get("visited", {}),
		}

		_lsp.send_request("references", "textDocument/references", {
			"textDocument": {
				"uri": request["uri"],
			},
			"position": {
				"line": request["line"],
				"character": request["character"],
			},
			"context": {
				"includeDeclaration": true,
			},
		}, context)
		_debug("sent references request for '%s'." % request["name"])


func _send_document_sync_notification(uri: String) -> void:
	_lsp.sync_document(uri, _get_text_for_uri(uri))


func _handle_response(response: Dictionary) -> void:
	var request: Dictionary = response.get("context", {})
	var message: Dictionary = response.get("message", {})

	if message.has("error"):
		print("Call Hierarchy: request failed: %s" % JSON.stringify(message["error"]))
		_mark_item_loaded(request, "request failed")
		return

	if request["kind"] == "references":
		_apply_references(request, message.get("result", []))


func _apply_references(request: Dictionary, references: Variant) -> void:
	if typeof(references) != TYPE_ARRAY:
		print("Call Hierarchy: could not read references.")
		_mark_item_loaded(request, "could not read references")
		return

	var item: TreeItem = request["item"]
	_clear_children(item)
	var callers := _references_to_callers(references, request)
	if callers.is_empty():
		_add_leaf(item, "No callers found")
		_mark_item_loaded(request)
		return

	var visited: Dictionary = request.get("visited", {})
	for caller in callers.values():
		var caller_key := _symbol_key(caller["uri"], caller["line"], caller["name"])
		if visited.has(caller_key):
			continue
		if _node_count >= _max_nodes():
			_add_leaf(item, "Stopped: call hierarchy node limit reached")
			break

		var child_visited := visited.duplicate()
		child_visited[caller_key] = true
		var child := item.create_child()
		var location := _display_location(caller["uri"], caller["open_line"])
		var base_text := "%s - %s" % [_format_method_label(caller["uri"], caller["name"]), location]
		var is_engine_callback := _is_engine_callback_method(caller["name"])
		var is_constructor := _is_constructor_method(caller["name"])
		_set_item_text(child, base_text)
		child.set_metadata(0, {
			"name": caller["name"],
			"uri": caller["uri"],
			"line": caller["line"],
			"character": caller["character"],
			"open_line": caller["open_line"],
			"open_character": caller["open_character"],
			"base_text": base_text,
			"loaded": is_engine_callback,
			"visited": child_visited,
		})
		child.set_collapsed(true)
		if is_engine_callback:
			_add_engine_callback_leaf(child)
		elif is_constructor:
			_add_lazy_leaf(child)
		else:
			_add_lazy_leaf(child)
		_node_count += 1

	if item.get_first_child() == null:
		_add_leaf(item, "No callers found")

	_mark_item_loaded(request)


func _apply_constructor_callers(request: Dictionary) -> void:
	var item: TreeItem = request["item"]
	_clear_children(item)

	var callers := _find_constructor_callers_for_uri(str(request["uri"]))
	if callers.is_empty():
		_add_leaf(item, "No constructor callers found")
		_mark_item_loaded(request)
		return

	var visited: Dictionary = request.get("visited", {})
	for caller in callers.values():
		var caller_key := _symbol_key(caller["uri"], caller["line"], caller["name"])
		if visited.has(caller_key):
			continue
		if _node_count >= _max_nodes():
			_add_leaf(item, "Stopped: call hierarchy node limit reached")
			break

		var child_visited := visited.duplicate()
		child_visited[caller_key] = true
		var child := item.create_child()
		var location := _display_location(caller["uri"], caller["open_line"])
		var base_text := "%s - %s" % [_format_method_label(caller["uri"], caller["name"]), location]
		var is_engine_callback := _is_engine_callback_method(caller["name"])
		_set_item_text(child, base_text)
		child.set_metadata(0, {
			"name": caller["name"],
			"uri": caller["uri"],
			"line": caller["line"],
			"character": caller["character"],
			"open_line": caller["open_line"],
			"open_character": caller["open_character"],
			"base_text": base_text,
			"loaded": is_engine_callback,
			"visited": child_visited,
		})
		child.set_collapsed(true)
		if is_engine_callback:
			_add_engine_callback_leaf(child)
		else:
			_add_lazy_leaf(child)
		_node_count += 1

	if item.get_first_child() == null:
		_add_leaf(item, "No constructor callers found")

	_mark_item_loaded(request)


func _find_constructor_callers_for_uri(target_uri: String) -> Dictionary:
	var target_class_name := _find_class_name_for_uri(target_uri)
	if target_class_name.is_empty():
		return {}

	return _find_constructor_callers_for_class_name(target_class_name, target_uri, _gdscript_file_uris())


func _find_constructor_callers_for_class_name(target_class_name: String, target_uri: String, uris: Array[String]) -> Dictionary:
	var callers := {}
	var init_line := _find_init_line_for_uri(target_uri)
	for uri in uris:
		var lines := _get_lines_for_uri(uri)
		for line_index in lines.size():
			var call_columns := _constructor_call_columns(str(lines[line_index]), target_class_name)
			for call_column in call_columns:
				var caller := _find_enclosing_function_for_uri(uri, line_index)
				if caller.is_empty():
					continue
				if caller["uri"] == target_uri and caller["line"] == init_line:
					continue

				var key := "%s:%d:%s" % [caller["uri"], caller["line"], caller["name"]]
				if not callers.has(key):
					caller["open_line"] = line_index
					caller["open_character"] = call_column
					callers[key] = caller

	return callers


func _constructor_call_columns(line: String, target_class_name: String) -> Array[int]:
	var columns: Array[int] = []
	if target_class_name.is_empty():
		return columns

	var code_line := _strip_line_comment(line)
	var needle := target_class_name + ".new"
	var search_from := 0
	while search_from < code_line.length():
		var index := code_line.find(needle, search_from)
		if index == -1:
			break

		var end_index := index + needle.length()
		if _constructor_call_has_boundaries(code_line, index, end_index):
			columns.append(index)

		search_from = end_index

	return columns


func _constructor_call_has_boundaries(line: String, start: int, end_index: int) -> bool:
	if start > 0 and _is_identifier_char(line[start - 1]):
		return false
	if end_index < line.length() and _is_identifier_char(line[end_index]):
		return false

	var after_new := _skip_spaces(line, end_index)
	return after_new < line.length() and line[after_new] == "("


func _find_init_line_for_uri(uri: String) -> int:
	var lines := _get_lines_for_uri(uri)
	for index in lines.size():
		var line := str(lines[index])
		var stripped := line.strip_edges()
		if stripped.begins_with("func _init"):
			return index
	return -1


func _references_to_callers(references: Array, request: Dictionary) -> Dictionary:
	var callers := {}
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY or not reference.has("uri") or not reference.has("range"):
			continue

		var uri: String = reference["uri"]
		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var line := int(start["line"])
		var character := int(start["character"])
		if uri == request["uri"] and line == int(request["line"]) and character == int(request["character"]):
			continue

		var caller := _find_enclosing_function_for_uri(uri, line)
		if caller.is_empty():
			continue
		if caller["uri"] == request["uri"] and caller["line"] == int(request["line"]):
			continue

		var key := "%s:%d:%s" % [caller["uri"], caller["line"], caller["name"]]
		if not callers.has(key):
			caller["open_line"] = line
			caller["open_character"] = character
			callers[key] = caller

	return callers


func _mark_item_loaded(request: Dictionary, suffix: String = "") -> void:
	if not request.has("item"):
		return

	var item: TreeItem = request["item"]
	var metadata: Dictionary = item.get_metadata(0)
	metadata["loaded"] = true
	item.set_metadata(0, metadata)

	var base_text: String = metadata.get("base_text", metadata.get("name", "symbol"))
	if suffix.is_empty():
		_set_item_text(item, base_text)
	else:
		_set_item_text(item, "%s (%s)" % [base_text, suffix])


func _add_leaf(parent: TreeItem, text: String) -> void:
	var child := parent.create_child()
	_set_item_text(child, text)
	child.set_selectable(0, false)


func _add_lazy_leaf(parent: TreeItem) -> void:
	var child := parent.create_child()
	_set_item_text(child, "Open branch to load callers")
	child.set_selectable(0, false)


func _add_engine_callback_leaf(parent: TreeItem) -> void:
	var child := parent.create_child()
	_set_item_text(child, "Godot engine callback")
	child.set_selectable(0, false)


func _clear_children(item: TreeItem) -> void:
	var child := item.get_first_child()
	while child != null:
		var next := child.get_next()
		child.free()
		child = next


func _find_enclosing_function_for_uri(uri: String, line_index: int) -> Dictionary:
	var lines := _get_lines_for_uri(uri)
	for index in range(mini(line_index, lines.size() - 1), -1, -1):
		var line: String = lines[index]
		var stripped := line.strip_edges()
		if not stripped.begins_with("func "):
			continue

		var name_start := line.find("func ") + 5
		name_start = _skip_spaces(line, name_start)
		var name_end := name_start
		while name_end < line.length() and _is_identifier_char(line[name_end]):
			name_end += 1
		if name_start == name_end:
			return {}

		return {
			"name": line.substr(name_start, name_end - name_start),
			"uri": uri,
			"line": index,
			"character": name_start,
		}

	return {}


func _get_enclosing_function_symbol_range(code: CodeEdit, line_index: int) -> Dictionary:
	for index in range(mini(line_index, code.get_line_count() - 1), -1, -1):
		var line := code.get_line(index)
		var stripped := line.strip_edges()
		if not stripped.begins_with("func "):
			continue

		var name_start := line.find("func ") + 5
		name_start = _skip_spaces(line, name_start)
		var name_end := name_start
		while name_end < line.length() and _is_identifier_char(line[name_end]):
			name_end += 1
		if name_start == name_end:
			return {}

		return {
			"symbol": line.substr(name_start, name_end - name_start),
			"line": index,
			"column": name_start,
		}

	return {}


func _call_hierarchy_root_symbol(current_uri: String, symbol_range: Dictionary) -> Dictionary:
	var resolved := _resolve_member_call_root_symbol(current_uri, symbol_range)
	if not resolved.is_empty():
		return resolved

	return {
		"symbol": str(symbol_range["symbol"]),
		"uri": current_uri,
		"line": int(symbol_range["line"]),
		"column": int(symbol_range["column"]),
	}


func _resolve_member_call_root_symbol(current_uri: String, symbol_range: Dictionary) -> Dictionary:
	var receiver_name := _member_call_receiver_name(current_uri, symbol_range)
	if receiver_name.is_empty():
		return {}

	var receiver_type := ""
	if receiver_name == "self":
		receiver_type = _find_class_name_for_uri(current_uri)
	else:
		receiver_type = _find_identifier_type_for_uri(current_uri, receiver_name, int(symbol_range["line"]))

	var target_uri := ""
	if receiver_type.is_empty():
		target_uri = _find_uri_for_class_name(receiver_name)
	else:
		target_uri = _find_uri_for_class_name(receiver_type)
	if target_uri.is_empty():
		return {}

	return _find_method_symbol_range_for_uri(target_uri, str(symbol_range["symbol"]))


func _member_call_receiver_name(uri: String, symbol_range: Dictionary) -> String:
	var lines := _get_lines_for_uri(uri)
	var line_index := int(symbol_range.get("line", -1))
	if line_index < 0 or line_index >= lines.size():
		return ""

	var line := _strip_line_comment(str(lines[line_index]))
	var symbol_start := int(symbol_range.get("column", -1))
	if symbol_start <= 0 or symbol_start > line.length():
		return ""

	var dot_col := _skip_back_spaces(line, symbol_start - 1)
	if dot_col < 0 or line[dot_col] != ".":
		return ""

	var receiver_end := dot_col
	var receiver_start := receiver_end - 1
	while receiver_start >= 0 and _is_identifier_char(line[receiver_start]):
		receiver_start -= 1
	receiver_start += 1
	if receiver_start == receiver_end:
		return ""

	var receiver_name := line.substr(receiver_start, receiver_end - receiver_start)
	if not _is_valid_identifier(receiver_name):
		return ""
	return receiver_name


func _find_identifier_type_for_uri(uri: String, identifier_name: String, line_index: int) -> String:
	var lines := _get_lines_for_uri(uri)
	if lines.is_empty():
		return ""

	var enclosing_function := _find_enclosing_function_for_uri(uri, line_index)
	if not enclosing_function.is_empty():
		var function_line := int(enclosing_function["line"])
		for index in range(mini(line_index, lines.size() - 1), function_line, -1):
			var local_type := _variable_type_from_line(str(lines[index]), identifier_name)
			if not local_type.is_empty():
				return local_type

		var parameter_type := _function_parameter_type_from_line(str(lines[function_line]), identifier_name)
		if not parameter_type.is_empty():
			return parameter_type

	for index in lines.size():
		var line := str(lines[index])
		if line.begins_with(" ") or line.begins_with("\t"):
			continue

		var member_type := _variable_type_from_line(line, identifier_name)
		if not member_type.is_empty():
			return member_type

	return ""


func _variable_type_from_line(line: String, variable_name: String) -> String:
	var code_line := _strip_line_comment(line)
	var search_from := 0
	while search_from < code_line.length():
		var var_index := code_line.find("var ", search_from)
		if var_index == -1:
			return ""
		if var_index > 0 and _is_identifier_char(code_line[var_index - 1]):
			search_from = var_index + 4
			continue

		var name_start := _skip_spaces_and_tabs(code_line, var_index + 4)
		var name_end := name_start
		while name_end < code_line.length() and _is_identifier_char(code_line[name_end]):
			name_end += 1
		if name_start == name_end:
			search_from = var_index + 4
			continue
		if code_line.substr(name_start, name_end - name_start) != variable_name:
			search_from = name_end
			continue

		var colon_col := _skip_spaces_and_tabs(code_line, name_end)
		if colon_col >= code_line.length() or code_line[colon_col] != ":":
			return ""
		return _type_name_after_colon(code_line, colon_col)

	return ""


func _function_parameter_type_from_line(line: String, parameter_name: String) -> String:
	var code_line := _strip_line_comment(line)
	var open_paren := code_line.find("(")
	if open_paren == -1:
		return ""

	var close_paren := code_line.find(")", open_paren + 1)
	if close_paren == -1:
		return ""

	var parameters := code_line.substr(open_paren + 1, close_paren - open_paren - 1).split(",")
	for parameter in parameters:
		var parameter_text := str(parameter).strip_edges()
		var name_start := 0
		var name_end := name_start
		while name_end < parameter_text.length() and _is_identifier_char(parameter_text[name_end]):
			name_end += 1
		if name_start == name_end:
			continue
		if parameter_text.substr(name_start, name_end - name_start) != parameter_name:
			continue

		var colon_col := _skip_spaces_and_tabs(parameter_text, name_end)
		if colon_col >= parameter_text.length() or parameter_text[colon_col] != ":":
			return ""
		return _type_name_after_colon(parameter_text, colon_col)

	return ""


func _type_name_after_colon(line: String, colon_col: int) -> String:
	var type_start := _skip_spaces_and_tabs(line, colon_col + 1)
	var type_end := type_start
	while type_end < line.length() and (_is_identifier_char(line[type_end]) or line[type_end] == "."):
		type_end += 1
	if type_start == type_end:
		return ""

	var type_name := line.substr(type_start, type_end - type_start)
	var dot_col := type_name.rfind(".")
	if dot_col != -1:
		type_name = type_name.substr(dot_col + 1)
	return type_name


func _find_uri_for_class_name(target_class_name: String) -> String:
	if target_class_name.is_empty():
		return ""

	for uri in _file_cache.keys():
		if _find_class_name_for_uri(str(uri)) == target_class_name:
			return str(uri)

	for uri in _gdscript_file_uris():
		if _find_class_name_for_uri(uri) == target_class_name:
			return uri

	return ""


func _find_method_symbol_range_for_uri(uri: String, method_name: String) -> Dictionary:
	var lines := _get_lines_for_uri(uri)
	for index in lines.size():
		var line := _strip_line_comment(str(lines[index]))
		var func_index := line.find("func ")
		if func_index == -1:
			continue
		if func_index > 0 and _is_identifier_char(line[func_index - 1]):
			continue

		var name_start := _skip_spaces_and_tabs(line, func_index + 5)
		var name_end := name_start
		while name_end < line.length() and _is_identifier_char(line[name_end]):
			name_end += 1
		if name_start == name_end:
			continue
		if line.substr(name_start, name_end - name_start) != method_name:
			continue

		return {
			"symbol": method_name,
			"uri": uri,
			"line": index,
			"column": name_start,
		}

	return {}


func _get_text_for_uri(uri: String) -> String:
	if uri == _current_uri and _code != null:
		return _get_code_text(_code)
	if _file_cache.has(uri):
		return "\n".join(_file_cache[uri])

	var path := _file_uri_to_path(uri)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var text := file.get_as_text()
	_file_cache[uri] = Array(text.split("\n"))
	return text


func _get_lines_for_uri(uri: String) -> Array:
	if uri == _current_uri and _code != null:
		var lines := []
		for line_index in _code.get_line_count():
			lines.append(_code.get_line(line_index))
		return lines
	if _file_cache.has(uri):
		return _file_cache[uri]

	var text := _get_text_for_uri(uri)
	if text.is_empty():
		return []

	return _file_cache.get(uri, Array(text.split("\n")))


func _gdscript_file_uris() -> Array[String]:
	var uris: Array[String] = []
	_append_gdscript_file_uris("res://", uris)
	return uris


func _append_gdscript_file_uris(directory_path: String, uris: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue

		var child_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_append_gdscript_file_uris(child_path, uris)
		elif entry.get_extension().to_lower() == "gd":
			uris.append(_path_to_file_uri(ProjectSettings.globalize_path(child_path)))

		entry = directory.get_next()
	directory.list_dir_end()


func _file_uri_to_path(uri: String) -> String:
	return LspClient.file_uri_to_path(uri)


func _display_location(uri: String, line_index: int) -> String:
	var path := ProjectSettings.localize_path(_file_uri_to_path(uri))
	if path == _file_uri_to_path(uri):
		path = path.get_file()
	return "%s:%d" % [path, line_index + 1]


func _format_method_label(uri: String, method_name: String) -> String:
	return "%s.%s()" % [_script_display_name(uri), method_name]


func _script_display_name(uri: String) -> String:
	if _script_display_name_cache.has(uri):
		return _script_display_name_cache[uri]

	var display_name := _find_class_name_for_uri(uri)
	if display_name.is_empty():
		display_name = "Unknown"

	_script_display_name_cache[uri] = display_name
	return display_name


func _find_class_name_for_uri(uri: String) -> String:
	for line in _get_lines_for_uri(uri):
		var code_line := _strip_line_comment(str(line)).strip_edges()
		if not code_line.begins_with("class_name "):
			continue

		var name_start := _skip_spaces(code_line, "class_name ".length())
		var name_end := name_start
		while name_end < code_line.length() and _is_identifier_char(code_line[name_end]):
			name_end += 1
		if name_start != name_end:
			return code_line.substr(name_start, name_end - name_start)

	return ""


func _strip_line_comment(line: String) -> String:
	var comment_start := line.find("#")
	if comment_start == -1:
		return line
	return line.substr(0, comment_start)


func _symbol_key(uri: String, line_index: int, symbol_name: String) -> String:
	return "%s:%d:%s" % [uri, line_index, symbol_name]


func _is_engine_callback_method(method_name: String) -> bool:
	return ENGINE_CALLBACK_METHODS.has(method_name)


func _is_constructor_method(method_name: String) -> bool:
	return method_name == "_init"


func _open_script_location(uri: String, line_index: int, column: int) -> void:
	var path := ProjectSettings.localize_path(_file_uri_to_path(uri))
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


func _reset_connection() -> void:
	_lsp.reset()


func _path_to_file_uri(path: String) -> String:
	return LspClient.path_to_file_uri(path)


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
	var line := code.get_line(code.get_caret_line())
	if line.is_empty():
		return {}

	var probe_col := clampi(code.get_caret_column(), 0, line.length())
	if probe_col == line.length() and probe_col > 0:
		probe_col -= 1
	elif probe_col < line.length() and not _is_identifier_char(line[probe_col]) and probe_col > 0:
		probe_col -= 1

	if probe_col < 0 or probe_col >= line.length() or not _is_identifier_char(line[probe_col]):
		return {}

	var start := probe_col
	while start > 0 and _is_identifier_char(line[start - 1]):
		start -= 1

	var end := probe_col + 1
	while end < line.length() and _is_identifier_char(line[end]):
		end += 1

	return {
		"symbol": line.substr(start, end - start),
		"line": code.get_caret_line(),
		"column": start,
	}


func _get_selected_or_current_symbol_range(code: CodeEdit) -> Dictionary:
	if code.has_selection():
		var selected := code.get_selected_text()
		if _is_valid_identifier(selected):
			return {
				"symbol": selected,
				"line": code.get_selection_from_line(),
				"column": code.get_selection_from_column(),
			}

	return _get_symbol_range_under_caret(code)


func _skip_spaces(line: String, col: int) -> int:
	while col < line.length() and line[col] == " ":
		col += 1
	return col


func _skip_spaces_and_tabs(line: String, col: int) -> int:
	while col < line.length() and (line[col] == " " or line[col] == "\t"):
		col += 1
	return col


func _skip_back_spaces(line: String, col: int) -> int:
	while col >= 0 and (line[col] == " " or line[col] == "\t"):
		col -= 1
	return col


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


func _debug(message: String) -> void:
	if _debug_logs_enabled():
		print("Call Hierarchy: " + message)
