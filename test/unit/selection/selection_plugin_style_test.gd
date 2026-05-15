extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_plugin_style_expand_from_statement_indent_selects_statement() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\tvar from_line := int(selection_range[\"from_line\"])"
	_assert_first_plugin_expansion({
		"code": code,
		"caret": Vector2i(1, 0),
		"expected": "\tvar lines := text.split(\"\\n\", true)",
	})


func test_plugin_style_expand_from_multiline_call_opening_line_selects_whole_call() -> void:
	var code := "func test_case() -> void:\n\tvar code := \"value\"\n\t_assert_expansions({\n\t\t\"code\": code,\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t})"
	_assert_next_plugin_expansion({
		"code": code,
		"current": {
			"from_line": 2,
			"from_col": 1,
			"to_line": 2,
			"to_col": 21,
		},
		"expected": "_assert_expansions({\n\t\t\"code\": code,\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t})",
	})
