@tool
extends EditorPlugin

const SmartEditorController := preload("res://addons/smart-editor-plugin/smart_editor/smart_editor_controller.gd")
const CallHierarchyController := preload("res://addons/smart-editor-plugin/call_hierarchy/call_hierarchy_controller.gd")

var _smart_editor_controller: Node
var _call_hierarchy_controller: Node


func _enter_tree() -> void:
	_smart_editor_controller = SmartEditorController.new()
	_smart_editor_controller.name = "SmartEditorController"
	add_child(_smart_editor_controller)

	_call_hierarchy_controller = CallHierarchyController.new()
	_call_hierarchy_controller.name = "SmartCallHierarchyController"
	_call_hierarchy_controller.configure(self)
	add_child(_call_hierarchy_controller)


func _exit_tree() -> void:
	if _call_hierarchy_controller != null:
		_call_hierarchy_controller.queue_free()
		_call_hierarchy_controller = null
	if _smart_editor_controller != null:
		_smart_editor_controller.queue_free()
		_smart_editor_controller = null
