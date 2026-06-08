extends GdUnitTestSuite

const CallHierarchyController := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_controller.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_symbol_range_uses_selected_identifier() -> void:
	var controller := CallHierarchyController.new()
	var code := CodeEdit.new()
	code.text = "func caller() -> void:\n\tcallee()"
	code.select(1, 1, 1, 7)

	assert_dict(controller._get_selected_or_current_symbol_range(code)).is_equal({
		"symbol": "callee",
		"line": 1,
		"column": 1,
	})

	code.free()
	controller.free()


func test_enclosing_function_symbol_range_finds_nearest_function() -> void:
	var controller := CallHierarchyController.new()
	var code := CodeEdit.new()
	code.text = "func first() -> void:\n\tpass\n\nfunc second() -> void:\n\tcallee()"

	assert_dict(controller._get_enclosing_function_symbol_range(code, 4)).is_equal({
		"symbol": "second",
		"line": 3,
		"column": 5,
	})

	code.free()
	controller.free()


func test_references_to_callers_keeps_distinct_call_sites_in_same_function() -> void:
	var controller := CallHierarchyController.new()
	var uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	controller._file_cache[uri] = [
		"class_name Player",
		"",
		"func first() -> void:",
		"\ttarget()",
		"\ttarget()",
		"",
		"func second() -> void:",
		"\ttarget()",
	]

	var callers := controller._references_to_callers([
		_lsp_reference(uri, 3, 1),
		_lsp_reference(uri, 4, 1),
		_lsp_reference(uri, 7, 1),
	], {
		"uri": uri,
		"line": 20,
		"character": 5,
	})

	assert_int(callers.size()).is_equal(3)
	assert_dict(callers["%s:2:first:3:1" % uri]).is_equal({
		"name": "first",
		"uri": uri,
		"line": 2,
		"character": 5,
		"open_line": 3,
		"open_character": 1,
	})
	assert_dict(callers["%s:2:first:4:1" % uri]).is_equal({
		"name": "first",
		"uri": uri,
		"line": 2,
		"character": 5,
		"open_line": 4,
		"open_character": 1,
	})
	assert_dict(callers["%s:6:second:7:1" % uri]).is_equal({
		"name": "second",
		"uri": uri,
		"line": 6,
		"character": 5,
		"open_line": 7,
		"open_character": 1,
	})
	controller.free()


func test_engine_callback_methods_are_not_loaded_from_lsp() -> void:
	var controller := CallHierarchyController.new()

	assert_bool(controller._is_engine_callback_method("_ready")).is_true()
	assert_bool(controller._is_engine_callback_method("_init")).is_false()
	assert_bool(controller._is_constructor_method("_init")).is_true()
	assert_bool(controller._is_engine_callback_method("custom_method")).is_false()
	controller.free()


func test_call_hierarchy_root_uses_typed_member_receiver_definition() -> void:
	var controller := CallHierarchyController.new()
	var level_uri := SmartEditorFiles.path_to_file_uri("/project/level.gd")
	var unit_uri := SmartEditorFiles.path_to_file_uri("/project/unit.gd")
	controller._file_cache[level_uri] = [
		"class_name Level",
		"var _selected_squad_member: Unit",
		"",
		"func _process() -> void:",
		"\t_selected_squad_member.released()",
	]
	controller._file_cache[unit_uri] = [
		"class_name Unit",
		"",
		"func released() -> void:",
		"\tpass",
	]

	var root_symbol := controller._call_hierarchy_root_symbol(level_uri, {
		"symbol": "released",
		"line": 4,
		"column": 24,
	})

	assert_dict(root_symbol).is_equal({
		"symbol": "released",
		"uri": unit_uri,
		"line": 2,
		"column": 5,
	})
	controller.free()


func test_escape_key_is_focus_editor_shortcut() -> void:
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER

	assert_bool(CallHierarchyController._is_focus_editor_shortcut(escape_event)).is_true()
	assert_bool(CallHierarchyController._is_focus_editor_shortcut(enter_event)).is_false()


func test_constructor_call_columns_find_class_name_new_calls() -> void:
	var controller := CallHierarchyController.new()

	assert_array(controller._constructor_call_columns("var player := Player.new()", "Player")).is_equal([14])
	assert_array(controller._constructor_call_columns("var player := NotPlayer.new()", "Player")).is_empty()
	assert_array(controller._constructor_call_columns("# var player := Player.new()", "Player")).is_empty()
	controller.free()


func test_constructor_callers_keep_distinct_call_sites_in_same_function() -> void:
	var controller := CallHierarchyController.new()
	var player_uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	var spawner_uri := SmartEditorFiles.path_to_file_uri("/project/spawner.gd")
	controller._file_cache[player_uri] = [
		"class_name Player",
		"",
		"func _init() -> void:",
		"\tpass",
	]
	controller._file_cache[spawner_uri] = [
		"class_name Spawner",
		"",
		"func spawn() -> void:",
		"\tvar player := Player.new()",
		"\tvar other := Player.new()",
	]

	var callers := controller._find_constructor_callers_for_class_name("Player", player_uri, [player_uri, spawner_uri])

	assert_int(callers.size()).is_equal(2)
	assert_dict(callers["%s:2:spawn:3:15" % spawner_uri]).is_equal({
		"name": "spawn",
		"uri": spawner_uri,
		"line": 2,
		"character": 5,
		"open_line": 3,
		"open_character": 15,
	})
	assert_dict(callers["%s:2:spawn:4:14" % spawner_uri]).is_equal({
		"name": "spawn",
		"uri": spawner_uri,
		"line": 2,
		"character": 5,
		"open_line": 4,
		"open_character": 14,
	})
	controller.free()


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
