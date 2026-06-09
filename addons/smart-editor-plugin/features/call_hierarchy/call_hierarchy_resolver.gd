extends RefCounted

# Finds call hierarchy callers by combining LSP references with GDScript text lookups and special cases.

const CallHierarchyCallSite := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_call_site.gd")
const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")
const GDScriptProjectIndex := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_project_index.gd")
const GDScriptTextIntrospection := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_text_introspection.gd")

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

var lsp_service: Node
var project_index: GDScriptProjectIndex


func configure(new_lsp_service: Node, new_project_index: GDScriptProjectIndex) -> void:
	lsp_service = new_lsp_service
	project_index = new_project_index


func references_for_method(method: CallHierarchyMethod):
	if lsp_service == null:
		return null

	await lsp_service.sync_open_scripts()
	await lsp_service.sync_document(method.uri, project_index.get_text_for_uri(method.uri))

	return await lsp_service.references(method.uri, method.line, method.character, true)


func references_to_call_sites(references: Array, request_method: CallHierarchyMethod) -> Array[CallHierarchyCallSite]:
	var call_sites: Array[CallHierarchyCallSite] = []
	var seen := {}
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY or not reference.has("uri") or not reference.has("range"):
			continue

		var uri: String = reference["uri"]
		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var line := int(start["line"])
		var character := int(start["character"])
		if uri == request_method.uri and line == request_method.line and character == request_method.character:
			continue

		var caller := GDScriptTextIntrospection.enclosing_function_for_lines(
			project_index.get_lines_for_uri(uri),
			uri,
			line
		)
		if caller.is_empty():
			continue
		if caller.uri == request_method.uri and caller.line == request_method.line:
			continue

		var call_site: CallHierarchyCallSite = CallHierarchyCallSite.create(caller, line, character)
		var key := call_site.call_site_key()
		if not seen.has(key):
			seen[key] = true
			call_sites.append(call_site)

	return call_sites


func constructor_call_sites_for_uri(target_uri: String) -> Array[CallHierarchyCallSite]:
	var target_class_name := project_index.find_class_name_for_uri(target_uri)
	if target_class_name.is_empty():
		return []

	return constructor_call_sites_for_class_name(target_class_name, target_uri, project_index.gdscript_file_uris())


func constructor_call_sites_for_class_name(target_class_name: String, target_uri: String, uris: Array[String]) -> Array[CallHierarchyCallSite]:
	var call_sites: Array[CallHierarchyCallSite] = []
	var seen := {}
	var init_line := init_line_for_uri(target_uri)
	for uri in uris:
		var lines := project_index.get_lines_for_uri(uri)
		for line_index in lines.size():
			var call_columns := GDScriptTextIntrospection.constructor_call_columns(str(lines[line_index]), target_class_name)
			for call_column in call_columns:
				var caller := GDScriptTextIntrospection.enclosing_function_for_lines(lines, uri, line_index)
				if caller.is_empty():
					continue
				if caller.uri == target_uri and caller.line == init_line:
					continue

				var call_site: CallHierarchyCallSite = CallHierarchyCallSite.create(caller, line_index, call_column)
				var key := call_site.call_site_key()
				if not seen.has(key):
					seen[key] = true
					call_sites.append(call_site)

	return call_sites


func init_line_for_uri(uri: String) -> int:
	return GDScriptTextIntrospection.init_line_for_lines(project_index.get_lines_for_uri(uri))


func root_method(current_uri: String, symbol_range: CallHierarchyMethod) -> CallHierarchyMethod:
	var resolved := resolve_member_call_root_method(current_uri, symbol_range)
	if not resolved.is_empty():
		return resolved

	return CallHierarchyMethod.create(symbol_range.name, current_uri, symbol_range.line, symbol_range.character)


func resolve_member_call_root_method(current_uri: String, symbol_range: CallHierarchyMethod) -> CallHierarchyMethod:
	var current_lines := project_index.get_lines_for_uri(current_uri)
	var receiver_name := GDScriptTextIntrospection.member_call_receiver_name(current_lines, symbol_range)
	if receiver_name.is_empty():
		return CallHierarchyMethod.new()

	var receiver_type := ""
	if receiver_name == "self":
		receiver_type = project_index.find_class_name_for_uri(current_uri)
	else:
		receiver_type = GDScriptTextIntrospection.identifier_type_for_lines(
			current_lines,
			current_uri,
			receiver_name,
			symbol_range.line
		)

	var target_uri := ""
	if receiver_type.is_empty():
		target_uri = project_index.find_uri_for_class_name(receiver_name)
	else:
		target_uri = project_index.find_uri_for_class_name(receiver_type)
	if target_uri.is_empty():
		return CallHierarchyMethod.new()

	return GDScriptTextIntrospection.method_symbol_range_for_lines(
		project_index.get_lines_for_uri(target_uri),
		target_uri,
		symbol_range.name
	)


func is_engine_callback_method(method_name: String) -> bool:
	return ENGINE_CALLBACK_METHODS.has(method_name)


func is_constructor_method(method_name: String) -> bool:
	return method_name == "_init"
