extends GdUnitTestSuite

const CallHierarchyController := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_controller.gd")


func test_escape_key_is_focus_editor_shortcut() -> void:
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER

	assert_bool(CallHierarchyController._is_focus_editor_shortcut(escape_event)).is_true()
	assert_bool(CallHierarchyController._is_focus_editor_shortcut(enter_event)).is_false()
