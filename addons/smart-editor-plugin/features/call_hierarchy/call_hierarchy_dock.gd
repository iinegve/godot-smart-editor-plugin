extends RefCounted

# Dock UI for Call Hierarchy: owns controls, tree rendering, focus behavior, and open callbacks.

const CallHierarchyTreeNode := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_tree_node.gd")


var plugin: EditorPlugin
var panel: VBoxContainer
var toolbar: HBoxContainer
var go_to_button: Button
var tree: Tree
var tree_font_size_provider: Callable
var go_to_shortcut_provider: Callable
var load_node_callback: Callable
var open_location_callback: Callable
var focus_editor_callback: Callable


func configure(
	new_plugin: EditorPlugin,
	new_tree_font_size_provider: Callable,
	new_go_to_shortcut_provider: Callable,
	new_load_node_callback: Callable,
	new_open_location_callback: Callable,
	new_focus_editor_callback: Callable
) -> void:
	plugin = new_plugin
	tree_font_size_provider = new_tree_font_size_provider
	go_to_shortcut_provider = new_go_to_shortcut_provider
	load_node_callback = new_load_node_callback
	open_location_callback = new_open_location_callback
	focus_editor_callback = new_focus_editor_callback


func ensure_created() -> void:
	if panel != null:
		return

	panel = VBoxContainer.new()
	panel.name = "Call Hierarchy"
	panel.add_theme_constant_override("separation", 6)

	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	panel.add_child(toolbar)

	go_to_button = Button.new()
	go_to_button.tooltip_text = "Go to selected method"
	go_to_button.focus_mode = Control.FOCUS_NONE
	_apply_go_to_button_icon()
	go_to_button.pressed.connect(_open_selected_item)
	toolbar.add_child(go_to_button)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = false
	tree.columns = 1
	apply_tree_font_size()
	tree.item_activated.connect(_open_selected_item)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.gui_input.connect(_on_tree_gui_input)
	panel.add_child(tree)

	if plugin != null:
		plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, panel)
	call_deferred("_apply_dock_tab_icon")


func destroy() -> void:
	if panel == null:
		return

	if plugin != null:
		plugin.remove_control_from_docks(panel)
	panel.queue_free()
	panel = null
	toolbar = null
	go_to_button = null
	tree = null


func show() -> void:
	if panel == null:
		return

	apply_tree_font_size()
	_apply_dock_tab_icon()
	panel.show()

	var parent := panel.get_parent()
	while parent != null:
		if parent is CanvasItem:
			(parent as CanvasItem).show()
		if parent is TabContainer:
			var tabs := parent as TabContainer
			for index in tabs.get_tab_count():
				if tabs.get_tab_control(index) == panel:
					tabs.current_tab = index
					call_deferred("focus_tree")
					return
		parent = parent.get_parent()

	call_deferred("focus_tree")


func clear() -> void:
	if tree != null:
		tree.clear()


func has_focus(viewport: Viewport) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false

	var focus_owner := viewport.gui_get_focus_owner()
	return focus_owner != null and (focus_owner == panel or panel.is_ancestor_of(focus_owner))


func focus_tree() -> void:
	if tree != null:
		tree.grab_focus()


func apply_tree_font_size() -> void:
	if tree == null:
		return

	var font_size := int(tree_font_size_provider.call())
	tree.add_theme_font_size_override("font_size", font_size)
	tree.add_theme_font_size_override("title_button_font_size", font_size)


func set_root(node: CallHierarchyTreeNode) -> void:
	if tree == null:
		return

	tree.clear()
	var root := tree.create_item()
	_write_item(root, node, false)
	root.select(0)


func mark_node_loading(node: CallHierarchyTreeNode) -> void:
	var item := _item_for_node(node)
	if item == null:
		return

	node.loaded = false
	_set_item_text(item, "%s (loading...)" % node.base_text)
	_clear_children(item)


func render_children(
	parent_node: CallHierarchyTreeNode,
	child_nodes: Array[CallHierarchyTreeNode],
	empty_text: String,
	limit_reached: bool = false
) -> void:
	var item := _item_for_node(parent_node)
	if item == null:
		return

	_clear_children(item)
	for child_node in child_nodes:
		var child := item.create_child()
		_write_item(child, child_node, true)

	if limit_reached:
		_add_leaf(item, "Stopped: call hierarchy node limit reached")
	elif item.get_first_child() == null:
		_add_leaf(item, empty_text)

	mark_node_loaded(parent_node)


func mark_node_loaded(node: CallHierarchyTreeNode, suffix: String = "") -> void:
	var item := _item_for_node(node)
	if item == null:
		return

	node.loaded = true
	if suffix.is_empty():
		_set_item_text(item, node.base_text)
	else:
		_set_item_text(item, "%s (%s)" % [node.base_text, suffix])


func _write_item(item: TreeItem, node: CallHierarchyTreeNode, collapsed: bool) -> void:
	_set_item_text(item, node.base_text)
	item.set_metadata(0, node)
	item.set_collapsed(collapsed)
	if not node.leaf_text.is_empty():
		_add_leaf(item, node.leaf_text)
	elif not node.loaded:
		_add_lazy_leaf(item)


func _apply_go_to_button_icon() -> void:
	var theme_control := _theme_control()
	if theme_control == null:
		go_to_button.text = "Go"
		return

	for icon_name in ["ExternalLink", "MoveRight", "ArrowRight", "Forward", "Play"]:
		if theme_control.has_theme_icon(icon_name, "EditorIcons"):
			go_to_button.icon = theme_control.get_theme_icon(icon_name, "EditorIcons")
			go_to_button.text = ""
			return
	go_to_button.text = "Go"


func _apply_dock_tab_icon() -> void:
	if panel == null:
		return

	var icon := _get_call_hierarchy_icon()
	if icon == null:
		return

	if plugin != null:
		plugin.set_dock_tab_icon(panel, icon)


func _get_call_hierarchy_icon() -> Texture2D:
	var theme_control := _theme_control()
	if theme_control == null:
		return null

	for icon_name in ["ClassList", "Hierarchy", "Tree", "GraphNode", "Callable", "MethodOverride", "MemberMethod", "Signals"]:
		if theme_control.has_theme_icon(icon_name, "EditorIcons"):
			return theme_control.get_theme_icon(icon_name, "EditorIcons")
	return null


func _theme_control() -> Control:
	if panel != null:
		return panel
	return go_to_button


func _on_item_collapsed(item: TreeItem) -> void:
	if item == null or item.is_collapsed():
		return

	var node := _node_from_item(item)
	if node == null or node.loaded:
		return

	load_node_callback.call(node)


func _on_tree_gui_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if _is_focus_editor_shortcut(event):
		focus_editor_callback.call()
		tree.get_viewport().set_input_as_handled()
		return

	var shortcut = go_to_shortcut_provider.call()
	if shortcut is Shortcut and shortcut.matches_event(event):
		_open_selected_item()
		tree.get_viewport().set_input_as_handled()


func _open_selected_item() -> void:
	if tree == null:
		return

	var item := tree.get_selected()
	if item == null:
		return

	var node := _node_from_item(item)
	if node == null or node.method == null:
		return

	open_location_callback.call(node.method.uri, node.open_line, node.open_character)


func _set_item_text(item: TreeItem, text: String) -> void:
	item.set_text(0, text)
	item.set_custom_font_size(0, int(tree_font_size_provider.call()))


func _add_leaf(parent: TreeItem, text: String) -> void:
	var child := parent.create_child()
	_set_item_text(child, text)
	child.set_selectable(0, false)


func _add_lazy_leaf(parent: TreeItem) -> void:
	_add_leaf(parent, "Open branch to load callers")


func _clear_children(item: TreeItem) -> void:
	var child := item.get_first_child()
	while child != null:
		var next := child.get_next()
		child.free()
		child = next


func _item_for_node(node: CallHierarchyTreeNode) -> TreeItem:
	if tree == null:
		return null
	return _find_item_for_node(tree.get_root(), node)


func _find_item_for_node(item: TreeItem, node: CallHierarchyTreeNode) -> TreeItem:
	if item == null:
		return null
	if _node_from_item(item) == node:
		return item

	var child := item.get_first_child()
	while child != null:
		var found := _find_item_for_node(child, node)
		if found != null:
			return found
		child = child.get_next()

	return null


func _node_from_item(item: TreeItem) -> CallHierarchyTreeNode:
	var metadata = item.get_metadata(0)
	if metadata is CallHierarchyTreeNode:
		return metadata
	return null


static func _is_focus_editor_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false

	var key_event := event as InputEventKey
	return key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
