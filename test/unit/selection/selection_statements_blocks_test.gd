extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_local_typed_variable_name_expands_to_typed_declaration_before_line() -> void:
	_assert_expansions({
		"code": "var current: Dictionary = test_case[\"current\"]",
		"caret": Vector2i(0, 6),
		"expected": [
			"current",
			"current: Dictionary",
			"var current: Dictionary = test_case[\"current\"]",
		],
	})


func test_local_typed_variable_type_expands_to_typed_declaration_before_line() -> void:
	_assert_expansions({
		"code": "var current: Dictionary = test_case[\"current\"]",
		"caret": Vector2i(0, 15),
		"expected": [
			"Dictionary",
			"current: Dictionary",
			"var current: Dictionary = test_case[\"current\"]",
		],
	})


func test_inline_return_keyword() -> void:
	_assert_expansions({
		"code": "if unit_cell == Vector2i(grid_cell.x, grid_cell.y+1): return true",
		"caret": Vector2i(0, 57),
		"expected": [
			"return true",
			"if unit_cell == Vector2i(grid_cell.x, grid_cell.y+1): return true",
		],
	})


func test_for_loop_variable_expands_before_whole_line() -> void:
	_assert_expansions({
		"code": "for candidate in parser.build_candidates(test_case[\"code\"], current):",
		"caret": Vector2i(0, 6),
		"expected": [
			"candidate",
			"for candidate in parser.build_candidates(test_case[\"code\"], current):",
		],
	})


func test_for_loop_iterable_callee_expands_before_whole_line() -> void:
	_assert_expansions({
		"code": "for candidate in parser.build_candidates(test_case[\"code\"], current):",
		"caret": Vector2i(0, 18),
		"expected": [
			"parser",
			"parser.build_candidates",
			"parser.build_candidates(test_case[\"code\"], current)",
			"for candidate in parser.build_candidates(test_case[\"code\"], current):",
		],
	})


func test_for_loop_iterable_argument_expands_before_whole_line() -> void:
	_assert_expansions({
		"code": "for candidate in parser.build_candidates(test_case[\"code\"], current):",
		"caret": Vector2i(0, 63),
		"expected": [
			"current",
			"test_case[\"code\"], current",
			"build_candidates(test_case[\"code\"], current)",
			"parser.build_candidates(test_case[\"code\"], current)",
			"for candidate in parser.build_candidates(test_case[\"code\"], current):",
		],
	})


func test_caret_in_statement_indent_expands_to_statement_before_function() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\tvar from_line := int(selection_range[\"from_line\"])"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(1, 0),
		"expected": [
			"\tvar lines := text.split(\"\\n\", true)",
			code,
		],
	})


func test_caret_after_statement_indent_expands_to_statement_before_function() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\tvar from_line := int(selection_range[\"from_line\"])"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(1, 1),
		"expected": [
			"var lines := text.split(\"\\n\", true)",
			"var lines := text.split(\"\\n\", true)\n\tvar from_line := int(selection_range[\"from_line\"])",
			code,
		],
	})


func test_string_to_if_block_to_function() -> void:
	_assert_expansions({
		"code": "func _move(unit: Unit, path: Array[Vector2i]) -> bool:\n\tif path.is_empty():\n\t\tprint(\"Cannot go there\")\n\t\treturn false",
		"caret": Vector2i(2, 10),
		"expected": [
			"Cannot go there",
			"\"Cannot go there\"",
			"print(\"Cannot go there\")",
			"print(\"Cannot go there\")\n\t\treturn false",
			"if path.is_empty():\n\t\tprint(\"Cannot go there\")\n\t\treturn false",
			"func _move(unit: Unit, path: Array[Vector2i]) -> bool:\n\tif path.is_empty():\n\t\tprint(\"Cannot go there\")\n\t\treturn false",
		],
	})


func test_if_block_body_expands_before_header_block() -> void:
	var code := "if OS.is_stdout_verbose():\n\tprints(\"Finallize ..\")\n\tprints(\"-Orphan nodes report-----------------------\")\n\tWindow.print_orphan_nodes()\n\tprints(\"Finallize .. done\")"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(1, 11),
		"expected": [
			"Finallize ..",
			"\"Finallize ..\"",
			"prints(\"Finallize ..\")",
			"prints(\"Finallize ..\")\n\tprints(\"-Orphan nodes report-----------------------\")\n\tWindow.print_orphan_nodes()\n\tprints(\"Finallize .. done\")",
			code,
		],
	})


func test_else_block_expands_to_if_else_chain_before_function_body() -> void:
	var code := "func attack(source: Unit, target: Unit):\n\tvar a = 4\n\tif a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\tpass"
	_assert_next_plugin_expansion({
		"code": code,
		"current": {
			"from_line": 6,
			"from_col": 1,
			"to_line": 9,
			"to_col": 14,
		},
		"expected": "if a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)",
	})


func test_if_block_expands_to_if_else_chain_before_function_body() -> void:
	var code := "func attack(source: Unit, target: Unit):\n\tvar a = 4\n\tif a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\tpass"
	_assert_next_plugin_expansion({
		"code": code,
		"current": {
			"from_line": 2,
			"from_col": 1,
			"to_line": 5,
			"to_col": 14,
		},
		"expected": "if a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)",
	})


func test_if_else_chain_expands_to_function_body_before_function_header() -> void:
	var code := "func attack(source: Unit, target: Unit):\n\tprint(source, \" attacking \", target)\n\tvar a = 4\n\tif a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\tpass"
	_assert_next_plugin_expansion({
		"code": code,
		"current": {
			"from_line": 3,
			"from_col": 1,
			"to_line": 10,
			"to_col": 14,
		},
		"expected": "print(source, \" attacking \", target)\n\tvar a = 4\n\tif a > 5:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\telse:\n\t\tprint(17)\n\t\tvar blah2 = 17 * 2\n\t\tprint(blah2)\n\tpass",
	})


func test_function_body_expands_before_signature_block() -> void:
	var code := "func _finalize() -> void:\n\tqueue_delete(_cli_runner)\n\tif OS.is_stdout_verbose():\n\t\tprints(\"Finallize ..\")"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 11),
		"expected": [
			"Finallize ..",
			"\"Finallize ..\"",
			"prints(\"Finallize ..\")",
			"if OS.is_stdout_verbose():\n\t\tprints(\"Finallize ..\")",
			"queue_delete(_cli_runner)\n\tif OS.is_stdout_verbose():\n\t\tprints(\"Finallize ..\")",
			code,
		],
	})


func test_comment_inside_function_expands_to_comment_before_function_body() -> void:
	var code := "func _parse_modifier(line: String) -> bool:\n\tvar modifier := &\"static\"\n\t# We have an modifier, e.g. 'static'\n\tif modifier != &\"\" && line.begins_with(modifier):\n\t\treturn true"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(2, 7),
		"expected": [
			"# We have an modifier, e.g. 'static'",
			"var modifier := &\"static\"\n\t# We have an modifier, e.g. 'static'\n\tif modifier != &\"\" && line.begins_with(modifier):\n\t\treturn true",
			code,
		],
	})


func test_top_level_comment_block_expands_before_file() -> void:
	var code := "# First note\n# Second note\n\nclass_name Notes"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(1, 4),
		"expected": [
			"# First note\n# Second note",
		],
	})


func test_trailing_comment_expands_to_comment_segment_before_statement() -> void:
	_assert_expansions({
		"code": "var value := 1 # keep this note",
		"caret": Vector2i(0, 22),
		"expected": [
			"# keep this note",
			"var value := 1 # keep this note",
		],
	})


func test_await_expression_expands_to_statement() -> void:
	_assert_expansions({
		"code": "var is_completed = await _move_better(unit, path)",
		"caret": Vector2i(0, 40),
		"expected": [
			"unit",
			"_move_better(unit, path)",
			"await _move_better(unit, path)",
			"var is_completed = await _move_better(unit, path)",
		],
	})


func test_blank_line_separated_function_chunk() -> void:
	var code := "func example() -> void:\n\tvar setup := true\n\n\tprint(setup)\n\tprint(\"done\")\n\n\treturn"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 8),
		"expected": [
			"setup",
			"print(setup)",
			"print(setup)\n\tprint(\"done\")",
			code,
		],
	})
