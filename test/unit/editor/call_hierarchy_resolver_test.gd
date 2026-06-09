extends GdUnitTestSuite

const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")
const CallHierarchyResolver := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_resolver.gd")
const GDScriptProjectIndex := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_project_index.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_references_to_call_sites_keeps_distinct_call_sites_in_same_function() -> void:
	var resolver := _resolver()
	var uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	resolver.project_index.file_cache[uri] = [
		"class_name Player",
		"",
		"func first() -> void:",
		"\ttarget()",
		"\ttarget()",
		"",
		"func second() -> void:",
		"\ttarget()",
	]

	var call_sites := resolver.references_to_call_sites([
		_lsp_reference(uri, 3, 1),
		_lsp_reference(uri, 4, 1),
		_lsp_reference(uri, 7, 1),
	], CallHierarchyMethod.create("target", uri, 20, 5))

	assert_int(call_sites.size()).is_equal(3)
	_assert_call_site(call_sites[0], "first", uri, 2, 5, 3, 1)
	_assert_call_site(call_sites[1], "first", uri, 2, 5, 4, 1)
	_assert_call_site(call_sites[2], "second", uri, 6, 5, 7, 1)


func test_engine_callback_methods_are_not_loaded_from_lsp() -> void:
	var resolver := _resolver()

	assert_bool(resolver.is_engine_callback_method("_ready")).is_true()
	assert_bool(resolver.is_constructor_method("_init")).is_true()
	assert_bool(resolver.is_engine_callback_method("_init")).is_false()
	assert_bool(resolver.is_engine_callback_method("custom_method")).is_false()


func test_call_hierarchy_root_uses_typed_member_receiver_definition() -> void:
	var resolver := _resolver()
	var level_uri := SmartEditorFiles.path_to_file_uri("/project/level.gd")
	var unit_uri := SmartEditorFiles.path_to_file_uri("/project/unit.gd")
	resolver.project_index.file_cache[level_uri] = [
		"class_name Level",
		"var _selected_squad_member: Unit",
		"",
		"func _process() -> void:",
		"\t_selected_squad_member.released()",
	]
	resolver.project_index.file_cache[unit_uri] = [
		"class_name Unit",
		"",
		"func released() -> void:",
		"\tpass",
	]

	var root_symbol := resolver.root_method(
		level_uri,
		CallHierarchyMethod.create("released", "", 4, 24)
	)

	assert_str(root_symbol.name).is_equal("released")
	assert_str(root_symbol.uri).is_equal(unit_uri)
	assert_int(root_symbol.line).is_equal(2)
	assert_int(root_symbol.character).is_equal(5)


func test_constructor_callers_keep_distinct_call_sites_in_same_function() -> void:
	var resolver := _resolver()
	var player_uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	var spawner_uri := SmartEditorFiles.path_to_file_uri("/project/spawner.gd")
	resolver.project_index.file_cache[player_uri] = [
		"class_name Player",
		"",
		"func _init() -> void:",
		"\tpass",
	]
	resolver.project_index.file_cache[spawner_uri] = [
		"class_name Spawner",
		"",
		"func spawn() -> void:",
		"\tvar player := Player.new()",
		"\tvar other := Player.new()",
	]

	var call_sites := resolver.constructor_call_sites_for_class_name("Player", player_uri, [player_uri, spawner_uri])

	assert_int(call_sites.size()).is_equal(2)
	_assert_call_site(call_sites[0], "spawn", spawner_uri, 2, 5, 3, 15)
	_assert_call_site(call_sites[1], "spawn", spawner_uri, 2, 5, 4, 14)


func _resolver() -> CallHierarchyResolver:
	var resolver := CallHierarchyResolver.new()
	resolver.configure(null, GDScriptProjectIndex.new())
	return resolver


func _lsp_reference(uri: String, line: int, character: int) -> Dictionary:
	return {
		"uri": uri,
		"range": {
			"start": {
				"line": line,
				"character": character,
			},
			"end": {
				"line": line,
				"character": character + 6,
			},
		},
	}


func _assert_call_site(call_site, method_name: String, uri: String, line: int, character: int, open_line: int, open_character: int) -> void:
	assert_str(call_site.method.name).is_equal(method_name)
	assert_str(call_site.method.uri).is_equal(uri)
	assert_int(call_site.method.line).is_equal(line)
	assert_int(call_site.method.character).is_equal(character)
	assert_int(call_site.open_line).is_equal(open_line)
	assert_int(call_site.open_character).is_equal(open_character)
