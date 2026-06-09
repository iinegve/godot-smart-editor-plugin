extends GdUnitTestSuite

const CallHierarchyDock := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_dock.gd")
const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")
const CallHierarchyTreeNode := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_tree_node.gd")


func test_dock_renders_root_and_children_with_metadata() -> void:
	var dock := CallHierarchyDock.new()
	dock.configure(null, func(): return 12, func(): return null, func(_node): pass, func(_uri, _line, _column): pass, func(): pass)
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
