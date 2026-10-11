@tool
extends PopupPanel

const NavigationSearch := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_search.gd")
const NavigationSymbols := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_symbols.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")

signal entry_activated(entry: Dictionary)

var _tabs: TabBar
var _file_filters: HBoxContainer
var _scope: OptionButton
var _query: LineEdit
var _results: ItemList
var _entries: Array[Dictionary] = []
var _file_mode := false
var _separator_index := -1


func _init() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_file_filters = HBoxContainer.new()
	box.add_child(_file_filters)
	_tabs = TabBar.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_refresh.unbind(1))
	_file_filters.add_child(_tabs)
	_scope = OptionButton.new()
	_scope.add_item("Project")
	_scope.add_item("Project + Add-ons")
	_scope.item_selected.connect(_refresh.unbind(1))
	_file_filters.add_child(_scope)
	_query = LineEdit.new()
	_query.clear_button_enabled = true
	_query.keep_editing_on_text_submit = true
	_query.text_changed.connect(_refresh.unbind(1))
	_query.text_submitted.connect(_activate_selected.unbind(1))
	_query.gui_input.connect(_query_input)
	box.add_child(_query)
	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.custom_minimum_size = Vector2(0, 320)
	_results.item_activated.connect(_activate)
	_results.draw.connect(_draw_symbol_separator)
	box.add_child(_results)
	close_requested.connect(hide)


func configure(file_mode: bool) -> void:
	_file_mode = file_mode
	_file_filters.visible = file_mode
	_query.placeholder_text = "Search files by name or path" if file_mode else "Search fields and methods by name"
	_tabs.clear_tabs()
	if file_mode:
		for tab_title in ["All", "Scenes", "GDScript", "Resources", "Other"]:
			_tabs.add_tab(tab_title)
	min_size = Vector2i(620, 400 if file_mode else 360)


func show_entries(entries: Array[Dictionary], category: int = 0) -> void:
	_entries = entries
	_query.text = ""
	_scope.select(0)
	if _file_mode:
		_tabs.current_tab = category
	_refresh()
	var scale := EditorInterface.get_editor_scale()
	popup_centered_clamped(Vector2i(Vector2(800, 480 if _file_mode else 440) * scale))
	_query.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE:
		hide()
	elif _file_mode and key.keycode == KEY_TAB and key.ctrl_pressed and not key.meta_pressed and not key.alt_pressed:
		_tabs.current_tab = posmod(_tabs.current_tab + (-1 if key.shift_pressed else 1), _tabs.tab_count)
	elif _file_mode:
		var category := file_category_for_shortcut(event)
		if category < 0:
			return
		_tabs.current_tab = category
	else:
		return
	get_viewport().set_input_as_handled()
	_query.grab_focus()


static func file_category_for_shortcut(event: InputEvent) -> int:
	var paths := [
		SmartEditorSettings.SETTING_NAVIGATE_ALL,
		SmartEditorSettings.SETTING_NAVIGATE_SCENES,
		SmartEditorSettings.SETTING_NAVIGATE_SCRIPTS,
		SmartEditorSettings.SETTING_NAVIGATE_RESOURCES,
		SmartEditorSettings.SETTING_NAVIGATE_OTHER,
	]
	for category in paths.size():
		if SmartEditorSettings.shortcut_matches(paths[category], event):
			return category
	return -1


func _refresh() -> void:
	if _results == null:
		return
	_results.clear()
	_separator_index = -1
	var matches: Array[Dictionary] = []
	for entry in _entries:
		if _file_mode and _scope.selected == 0 and entry.get("addon", false):
			continue
		if _file_mode and _tabs.current_tab != 0 and entry["category"] != _tabs.current_tab:
			continue
		var rank := NavigationSearch.score(_query.text, entry["name"], entry.get("context", ""))
		if rank >= 0:
			matches.append({"entry": entry, "score": rank})
	matches.sort_custom(_compare_matches)
	var previous_category := -1
	for match_entry in matches:
		var entry: Dictionary = match_entry["entry"]
		if not _file_mode and previous_category >= 0 and previous_category != entry["category"]:
			_separator_index = _results.add_item(" ", null, false)
			_results.set_item_disabled(_separator_index, true)
			_results.set_item_tooltip_enabled(_separator_index, false)
		previous_category = entry["category"]
		var icon: Texture2D
		if _file_mode:
			var icon_name := StringName(entry.get("icon", &""))
			var theme_base := EditorInterface.get_base_control()
			if icon_name == &"" or not theme_base.has_theme_icon(icon_name, &"EditorIcons"):
				icon_name = &"File"
			icon = theme_base.get_theme_icon(icon_name, &"EditorIcons")
		elif Engine.is_editor_hint():
			var icon_name := &"Lock" if entry.get("private", false) else &"Unlock"
			icon = EditorInterface.get_base_control().get_theme_icon(icon_name, &"EditorIcons")
		var index := _results.add_item(entry["label"], icon)
		if not _file_mode:
			_results.set_item_icon_modulate(index, Color(1, 1, 1, 0.4))
		_results.set_item_metadata(index, entry)
		_results.set_item_tooltip(index, entry.get("tooltip", entry["label"]))
	if _results.item_count > 0:
		_results.select(0)
		_results.ensure_current_is_visible()


func _compare_matches(left: Dictionary, right: Dictionary) -> bool:
	var left_entry: Dictionary = left["entry"]
	var right_entry: Dictionary = right["entry"]
	if not _file_mode and left_entry["category"] != right_entry["category"]:
		return left_entry["category"] == NavigationSymbols.Category.FIELDS
	if left["score"] != right["score"]:
		return left["score"] < right["score"]
	if not _file_mode:
		return left_entry["line"] < right_entry["line"]
	return str(left_entry["context"]).naturalnocasecmp_to(right_entry["context"]) < 0


func _draw_symbol_separator() -> void:
	if _separator_index < 0:
		return
	var rect := _results.get_item_rect(_separator_index)
	var y := rect.get_center().y - _results.get_v_scroll_bar().value
	var panel := _results.get_theme_stylebox("panel")
	if y < panel.get_margin(SIDE_TOP) or y > _results.size.y - panel.get_margin(SIDE_BOTTOM):
		return
	_results.draw_line(Vector2(rect.position.x + 6, y), Vector2(rect.end.x - 6, y), _results.get_theme_color("guide_color"))


func _query_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed():
		return
	var key := event as InputEventKey
	var step := 0
	match key.keycode:
		KEY_UP: step = -1
		KEY_DOWN: step = 1
		KEY_PAGEUP: step = -10
		KEY_PAGEDOWN: step = 10
		_: return
	_move_selection(step)
	_query.accept_event()


func _move_selection(step: int) -> void:
	if _results.item_count == 0 or step == 0:
		return
	var selection := _results.get_selected_items()
	var current := int(selection[0]) if not selection.is_empty() else 0
	var direction := 1 if step > 0 else -1
	for count in absi(step):
		var next := current + direction
		while next >= 0 and next < _results.item_count and not _results.is_item_selectable(next):
			next += direction
		if next < 0 or next >= _results.item_count:
			break
		current = next
	_results.select(current)
	_results.ensure_current_is_visible()


func _activate_selected() -> void:
	var selection := _results.get_selected_items()
	if not selection.is_empty():
		_activate(selection[0])


func _activate(index: int) -> void:
	if index < 0 or index >= _results.item_count:
		return
	if not _results.is_item_selectable(index) or _results.is_item_disabled(index):
		return
	var entry: Dictionary = _results.get_item_metadata(index)
	hide()
	entry_activated.emit(entry)
