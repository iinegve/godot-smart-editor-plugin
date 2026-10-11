@tool
extends Node

const REFRESH_INTERVAL := 0.2

var _enabled_setting: StringName = &""
var _settings: EditorSettings
var _source: TabContainer
var _script_list: ItemList
var _tabs: TabBar
var _entries: Array[Dictionary] = []
var _refresh_pending := false
var _elapsed := 0.0


func _init() -> void:
	set_process(false)


func configure(enabled_setting: StringName) -> void:
	_enabled_setting = enabled_setting
	_settings = EditorInterface.get_editor_settings()
	if not _settings.settings_changed.is_connected(_apply_settings):
		_settings.settings_changed.connect(_apply_settings)
	_apply_settings()


func _exit_tree() -> void:
	if is_instance_valid(_settings) and _settings.settings_changed.is_connected(_apply_settings):
		_settings.settings_changed.disconnect(_apply_settings)
	_detach()


func _apply_settings() -> void:
	var enabled := _enabled_setting == &"" or not _settings.has_setting(_enabled_setting) or bool(_settings.get_setting(_enabled_setting))
	set_process(enabled)
	if enabled:
		_schedule_refresh()
	else:
		_detach()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _try_attach() -> void:
	var editor := EditorInterface.get_script_editor()
	if editor == null:
		return
	# The native list owns document names, filters and sorting.
	# Identify it by its engine connection, not its position among other lists.
	var script_list: ItemList
	for candidate in editor.find_children("*", "ItemList", true, false):
		for connection in candidate.get_signal_connection_list("item_selected"):
			var callback: Callable = connection["callable"]
			var method := str(callback.get_method())
			if callback.get_object() == editor and (method == "_script_selected" or method.ends_with("::_script_selected")):
				script_list = candidate
				break
		if script_list != null:
			break
	if script_list == null:
		return
	for candidate in editor.find_children("*", "TabContainer", true, false):
		if candidate.get_parent() is VBoxContainer:
			_attach(candidate, script_list)
			return


func _attach(source: TabContainer, script_list: ItemList) -> void:
	_detach()
	_source = source
	_script_list = script_list
	_tabs = TabBar.new()
	_tabs.name = "SmartScriptTabs"
	_tabs.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.clip_tabs = true
	_tabs.deselect_enabled = true
	_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	_tabs.max_tab_width = roundi(260 * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0))
	_tabs.tab_selected.connect(_activate_tab)
	_tabs.tab_close_pressed.connect(_close_tab)
	_tabs.tab_rmb_clicked.connect(_tab_context_menu)
	_source.tab_changed.connect(_native_tab_changed)
	_source.child_order_changed.connect(_schedule_refresh)
	var parent := _source.get_parent()
	parent.add_child(_tabs)
	parent.move_child(_tabs, _source.get_index())
	_refresh()


func _detach() -> void:
	if is_instance_valid(_source):
		if _source.tab_changed.is_connected(_native_tab_changed):
			_source.tab_changed.disconnect(_native_tab_changed)
		if _source.child_order_changed.is_connected(_schedule_refresh):
			_source.child_order_changed.disconnect(_schedule_refresh)
	if is_instance_valid(_tabs):
		# The editor parent can already be removing children during shutdown.
		_tabs.hide()
		_tabs.queue_free()
	_tabs = null
	_source = null
	_script_list = null
	_entries.clear()


func _native_tab_changed(_index: int) -> void:
	_schedule_refresh()


func _schedule_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_pending = false
	if not is_instance_valid(_source):
		if is_processing() and Engine.is_editor_hint():
			_try_attach()
		return
	if not is_instance_valid(_source) or not is_instance_valid(_script_list) or not is_instance_valid(_tabs):
		return
	var entries: Array[Dictionary] = []
	for index in _script_list.item_count:
		var native_index = _script_list.get_item_metadata(index)
		if not native_index is int or native_index < 0 or native_index >= _source.get_tab_count():
			continue
		var document := _source.get_tab_control(native_index)
		entries.append({
			"editor_id": document.get_instance_id(),
			"title": _document_title(document, _script_list.get_item_text(index)),
			"tooltip": _script_list.get_item_tooltip(index),
			"icon": _script_list.get_item_icon(index),
		})
	_tabs.set_block_signals(true)
	if entries != _entries:
		_entries = entries
		_tabs.clear_tabs()
		for entry in _entries:
			_tabs.add_tab(entry["title"], entry["icon"])
			_tabs.set_tab_tooltip(_tabs.tab_count - 1, entry["tooltip"])
	var selected := -1
	var current := _source.get_current_tab_control()
	if current != null:
		for index in _entries.size():
			if _entries[index]["editor_id"] == current.get_instance_id():
				selected = index
				break
	_tabs.current_tab = selected
	_tabs.visible = not _entries.is_empty()
	_tabs.set_block_signals(false)


func _document_title(document: Control, title: String) -> String:
	if not document.has_method("get_base_editor"):
		return title
	var code := document.call("get_base_editor") as TextEdit
	if code == null:
		return title
	# Read live dirty state even while Godot's document-name refresh is pending.
	return title.trim_suffix("(*)") + ("(*)" if code.get_version() != code.get_saved_version() else "")


# Resolve again at click time: filtering, sorting or closing another document
# can change native indices between the last refresh and this event.
func _item_for_tab(index: int) -> int:
	if index < 0 or index >= _entries.size() or not is_instance_valid(_source) or not is_instance_valid(_script_list):
		return -1
	for item in _script_list.item_count:
		var native_index = _script_list.get_item_metadata(item)
		if not native_index is int or native_index < 0 or native_index >= _source.get_tab_count():
			continue
		if _source.get_tab_control(native_index).get_instance_id() == _entries[index]["editor_id"]:
			return item
	return -1


func _activate_tab(index: int) -> void:
	var item := _item_for_tab(index)
	if item < 0:
		return
	_script_list.select(item)
	# The engine's handler preserves focus, navigation history and edit state.
	_script_list.item_selected.emit(item)
	_schedule_refresh()


func _close_tab(index: int) -> void:
	var item := _item_for_tab(index)
	if item >= 0:
		# Reuse native middle-click closing, including unsaved-change prompts.
		_script_list.item_clicked.emit(item, _script_list.get_local_mouse_position(), MOUSE_BUTTON_MIDDLE)


func _tab_context_menu(index: int) -> void:
	_activate_tab(index)
	var item := _item_for_tab(index)
	if item >= 0:
		_script_list.item_clicked.emit(item, _script_list.get_local_mouse_position(), MOUSE_BUTTON_RIGHT)
