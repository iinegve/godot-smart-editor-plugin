@tool
extends EditorPlugin

const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")
const ExpandShrinkSelectionController := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/expand_shrink_selection_controller.gd")
const LocalVariableExtractionController := preload("res://addons/smart-editor-plugin/features/local_variable_extraction/local_variable_extraction_controller.gd")
const SymbolRenamingController := preload("res://addons/smart-editor-plugin/features/symbol_renaming/symbol_renaming_controller.gd")
const LocalVariableInliningController := preload("res://addons/smart-editor-plugin/features/local_variable_inlining/local_variable_inlining_controller.gd")
const SmartSymbolUsageController := preload("res://addons/smart-editor-plugin/features/highlights/smart_symbol_usage_controller.gd")
const LspSymbolUsageController := preload("res://addons/smart-editor-plugin/features/highlights/lsp_symbol_usage_controller.gd")
const SmartFunctionBoundaryGuidesController := preload("res://addons/smart-editor-plugin/features/function_boundary_guides/smart_function_boundary_guides_controller.gd")
const CallHierarchyController := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_controller.gd")
const SmartEditorLspService := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_service.gd")

var _lsp_service: Node
var _expand_shrink_selection_controller: Node
var _local_variable_extraction_controller: Node
var _symbol_renaming_controller: Node
var _local_variable_inlining_controller: Node
var _symbol_usage_controller: Node
var _call_hierarchy_controller: Node
var _function_boundary_guides_controller: Node


func _enter_tree() -> void:
	SmartEditorSettings.init_editor_settings()
	SmartEditorSettings.init_highlight_settings()

	_lsp_service = SmartEditorLspService.new()
	_lsp_service.name = "SmartEditorLspService"
	_lsp_service.configure(SmartEditorSettings.HOST, SmartEditorSettings.PORT)
	add_child(_lsp_service)

	_expand_shrink_selection_controller = ExpandShrinkSelectionController.new()
	_expand_shrink_selection_controller.name = "ExpandShrinkSelectionController"
	add_child(_expand_shrink_selection_controller)

	_local_variable_extraction_controller = LocalVariableExtractionController.new()
	_local_variable_extraction_controller.name = "LocalVariableExtractionController"
	add_child(_local_variable_extraction_controller)

	_symbol_renaming_controller = SymbolRenamingController.new()
	_symbol_renaming_controller.name = "SymbolRenamingController"
	_symbol_renaming_controller.configure(_lsp_service)
	add_child(_symbol_renaming_controller)

	_local_variable_inlining_controller = LocalVariableInliningController.new()
	_local_variable_inlining_controller.name = "LocalVariableInliningController"
	_local_variable_inlining_controller.configure(_lsp_service)
	add_child(_local_variable_inlining_controller)

	if _supports_lsp_document_highlight():
		_symbol_usage_controller = LspSymbolUsageController.new()
		_symbol_usage_controller.name = "LspSymbolUsageController"
		add_child(_symbol_usage_controller)
		_symbol_usage_controller.configure(
			SmartEditorSettings.SETTING_SYMBOL_USAGE_STRIPE_ENABLED,
			_lsp_service,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR
		)
	else:
		_symbol_usage_controller = SmartSymbolUsageController.new()
		_symbol_usage_controller.name = "SmartSymbolUsageController"
		add_child(_symbol_usage_controller)
		_symbol_usage_controller.configure(
			SmartEditorSettings.SETTING_SYMBOL_USAGE_STRIPE_ENABLED,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_HIGHLIGHT_ENABLED,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_HIGHLIGHT_COLOR,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_CURRENT_HIGHLIGHT_COLOR,
			SmartEditorSettings.SETTING_SYMBOL_USAGE_CURRENT_OUTLINE_COLOR
		)

	_call_hierarchy_controller = CallHierarchyController.new()
	_call_hierarchy_controller.name = "SmartCallHierarchyController"
	_call_hierarchy_controller.configure(self, _lsp_service)
	add_child(_call_hierarchy_controller)

	SmartEditorSettings.init_function_boundary_settings()

	_function_boundary_guides_controller = SmartFunctionBoundaryGuidesController.new()
	_function_boundary_guides_controller.name = "SmartFunctionBoundaryGuidesController"
	add_child(_function_boundary_guides_controller)
	_function_boundary_guides_controller.configure(
		SmartEditorSettings.SETTING_FUNCTION_SEPARATOR_GUIDES_ENABLED,
		SmartEditorSettings.SETTING_FUNCTION_BOUNDARY_INDENT_GUIDES_ENABLED,
		SmartEditorSettings.SETTING_FUNCTION_BOUNDARY_GUIDE_COLOR
	)


func _exit_tree() -> void:
	if _function_boundary_guides_controller != null:
		_function_boundary_guides_controller.queue_free()
		_function_boundary_guides_controller = null
	if _call_hierarchy_controller != null:
		_call_hierarchy_controller.queue_free()
		_call_hierarchy_controller = null
	if _symbol_usage_controller != null:
		_symbol_usage_controller.queue_free()
		_symbol_usage_controller = null
	if _local_variable_inlining_controller != null:
		_local_variable_inlining_controller.queue_free()
		_local_variable_inlining_controller = null
	if _symbol_renaming_controller != null:
		_symbol_renaming_controller.queue_free()
		_symbol_renaming_controller = null
	if _local_variable_extraction_controller != null:
		_local_variable_extraction_controller.queue_free()
		_local_variable_extraction_controller = null
	if _expand_shrink_selection_controller != null:
		_expand_shrink_selection_controller.queue_free()
		_expand_shrink_selection_controller = null
	if _lsp_service != null:
		_lsp_service.queue_free()
		_lsp_service = null


func _supports_lsp_document_highlight() -> bool:
	var version := Engine.get_version_info()
	var major := int(version.get("major", 0))
	var minor := int(version.get("minor", 0))

	return major > 4 or (major == 4 and minor >= 7)
