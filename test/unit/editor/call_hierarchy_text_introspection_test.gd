extends GdUnitTestSuite

const GDScriptTextIntrospection := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_text_introspection.gd")


func test_symbol_range_uses_selected_identifier() -> void:
	var code := CodeEdit.new()
	code.text = "func caller() -> void:\n\tcallee()"
	code.select(1, 1, 1, 7)

	var symbol_range = GDScriptTextIntrospection.selected_or_current_symbol_range(code)

	assert_str(symbol_range.name).is_equal("callee")
	assert_int(symbol_range.line).is_equal(1)
	assert_int(symbol_range.character).is_equal(1)

	code.free()


func test_enclosing_function_symbol_range_finds_nearest_function() -> void:
	var code := CodeEdit.new()
	code.text = "func first() -> void:\n\tpass\n\nfunc second() -> void:\n\tcallee()"

	var symbol_range = GDScriptTextIntrospection.enclosing_function_symbol_range(code, 4)

	assert_str(symbol_range.name).is_equal("second")
	assert_int(symbol_range.line).is_equal(3)
	assert_int(symbol_range.character).is_equal(5)

	code.free()


func test_enclosing_function_for_lines_ignores_top_level_comment_between_functions() -> void:
	var lines := [
		"func clear() -> void:",
		"\t_values.clear()",
		"",
		"## Returns set values as a typed Array.",
		"## `var units: Array[Unit] = set.values([] as Array[Unit])`",
		"func values() -> Array:",
		"\treturn _values",
	]

	var symbol_range = GDScriptTextIntrospection.enclosing_function_for_lines(lines, "file:///project/set.gd", 4)

	assert_bool(symbol_range.is_empty()).is_true()


func test_is_identifier_position_in_code_ignores_comments_and_strings() -> void:
	var lines := [
		"set.values()",
		"## `var units = set.values()`",
		"print(\"values\")",
	]

	assert_bool(GDScriptTextIntrospection.is_identifier_position_in_code(lines, 0, 4)).is_true()
	assert_bool(GDScriptTextIntrospection.is_identifier_position_in_code(lines, 1, 21)).is_false()
	assert_bool(GDScriptTextIntrospection.is_identifier_position_in_code(lines, 2, 7)).is_false()


func test_constructor_call_columns_find_class_name_new_calls() -> void:
	assert_array(GDScriptTextIntrospection.constructor_call_columns("var player := Player.new()", "Player")).is_equal([14])
	assert_array(GDScriptTextIntrospection.constructor_call_columns("var player := NotPlayer.new()", "Player")).is_empty()
	assert_array(GDScriptTextIntrospection.constructor_call_columns("# var player := Player.new()", "Player")).is_empty()


func test_strip_line_comment_keeps_hash_inside_double_quoted_string() -> void:
	var line := "var label := \"value # still string\""

	assert_str(GDScriptTextIntrospection.strip_line_comment(line)).is_equal(line)


func test_strip_line_comment_removes_real_comment_after_double_quoted_string() -> void:
	assert_str(GDScriptTextIntrospection.strip_line_comment("var label := \"value # still string\" # real comment")).is_equal("var label := \"value # still string\" ")


func test_strip_line_comment_removes_real_comment_after_single_quoted_string() -> void:
	assert_str(GDScriptTextIntrospection.strip_line_comment("var label := 'value # still string' # real comment")).is_equal("var label := 'value # still string' ")


func test_strip_line_comment_keeps_hash_inside_escaped_quoted_string() -> void:
	assert_str(GDScriptTextIntrospection.strip_line_comment("var label := \"escaped \\\"#\\\"\" # real comment")).is_equal("var label := \"escaped \\\"#\\\"\" ")
