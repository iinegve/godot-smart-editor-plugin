extends GdUnitTestSuite

const CallHierarchyDock := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_dock.gd")
const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")
const CallHierarchyTreeNode := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_tree_node.gd")


class FakeEditorDock extends MarginContainer:
	var title := ""
	var layout_key := ""
	var default_slot := EditorDock.DOCK_SLOT_NONE
	var available_layouts := 0
	var dock_icon: Texture2D


	func close() -> void:
		hide()


	func make_visible() -> void:
		show()


func test_dock_configures_native_movable_editor_dock() -> void:
	var dock := _create_dock()
	dock.ensure_created()

	assert_bool(dock.editor_dock is FakeEditorDock).is_true()
	assert_str(dock.editor_dock.get("title")).is_equal("Call Hierarchy")
	assert_str(dock.editor_dock.get("layout_key")).is_equal("Call Hierarchy")
	assert_int(dock.editor_dock.get("default_slot")).is_equal(EditorDock.DOCK_SLOT_RIGHT_UL)
	assert_int(dock.editor_dock.get("available_layouts")).is_equal(EditorDock.DOCK_LAYOUT_ALL)
	assert_object(dock.panel.get_parent()).is_equal(dock.editor_dock)

	dock.destroy()


func test_dock_renders_root_and_children_with_metadata() -> void:
	var dock := _create_dock()
	dock.ensure_created()
	var root_node: CallHierarchyTreeNode = CallHierarchyTreeNode.create(
		CallHierarchyMethod.create("target", "file:///project/player.gd", 2, 5),
		2,
		5,
		"Player.target()"
	)
	var child_node: CallHierarchyTreeNode = CallHierarchyTreeNode.create(
		CallHierarchyMethod.create("caller", "file:///project/player.gd", 6, 5),
		7,
		1,
		"Player.caller() - player.gd:8"
	)

	dock.set_root(root_node)
	dock.render_children(root_node, [child_node], "No callers found")

	assert_object(dock.tree.get_root().get_metadata(0)).is_equal(root_node)
	assert_object(dock.tree.get_root().get_first_child().get_metadata(0)).is_equal(child_node)

	dock.destroy()


func _create_dock() -> CallHierarchyDock:
	var dock := CallHierarchyDock.new()
	dock.configure(
		null,
		func(): return 12,
		func(): return null,
		func(_node): pass,
		func(_uri, _line, _column): pass,
		func(): pass,
		func(): return FakeEditorDock.new()
	)
	return dock
