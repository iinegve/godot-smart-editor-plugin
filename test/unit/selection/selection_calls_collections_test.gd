extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_nested_call_argument_expands_before_outer_call() -> void:
	_assert_expansions({
		"code": "print(Vector2i(grid_cell.x, grid_cell.y + 1))",
		"caret": Vector2i(0, 15),
		"expected": [
			"grid_cell",
			"grid_cell.x",
			"grid_cell.x, grid_cell.y + 1",
			"Vector2i(grid_cell.x, grid_cell.y + 1)",
			"print(Vector2i(grid_cell.x, grid_cell.y + 1))",
		],
	})


func test_empty_call_expands_from_callee_to_call() -> void:
	_assert_expansions({
		"code": "create_tween()",
		"caret": Vector2i(0, 3),
		"expected": [
			"create_tween",
			"create_tween()",
		],
	})


func test_empty_member_call_expands_to_method_call_before_receiver_call() -> void:
	_assert_expansions({
		"code": "var selected := code.get_selected_text()",
		"caret": Vector2i(0, 25),
		"expected": [
			"get_selected_text",
			"get_selected_text()",
			"code.get_selected_text()",
			"var selected := code.get_selected_text()",
		],
	})


func test_plugin_style_empty_member_call_expands_to_method_call_before_receiver_call() -> void:
	_assert_next_plugin_expansion({
		"code": "var selected := code.get_selected_text()",
		"current": {
			"from_line": 0,
			"from_col": 21,
			"to_line": 0,
			"to_col": 38,
		},
		"expected": "get_selected_text()",
	})


func test_member_call_argument_list_expands_to_method_call_before_receiver_call() -> void:
	_assert_expansions({
		"code": "settings.set_initial_value(path, default_value, false)",
		"caret": Vector2i(0, 37),
		"expected": [
			"default_value",
			"path, default_value, false",
			"set_initial_value(path, default_value, false)",
			"settings.set_initial_value(path, default_value, false)",
		],
	})


func test_member_call_method_name_expands_to_method_call_before_receiver() -> void:
	_assert_expansions({
		"code": "code.set_caret_line(selection_range[\"from_line\"])",
		"caret": Vector2i(0, 7),
		"expected": [
			"set_caret_line",
			"set_caret_line(selection_range[\"from_line\"])",
			"code.set_caret_line",
			"code.set_caret_line(selection_range[\"from_line\"])",
		],
	})


func test_plugin_style_argument_list_expands_to_method_call_before_receiver_call() -> void:
	_assert_next_plugin_expansion({
		"code": "settings.set_initial_value(path, default_value, false)",
		"current": {
			"from_line": 0,
			"from_col": 27,
			"to_line": 0,
			"to_col": 53,
		},
		"expected": "set_initial_value(path, default_value, false)",
	})


func test_multiline_call_callee_expands_to_call_before_statement() -> void:
	var code := "func set_current_report_path() -> void:\n\t# scan for latest report directory\n\tvar iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)\n\t_current_report_path = \"%s/%s%d\" % [_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX, iteration]"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(2, 40),
		"expected": [
			"find_last_path_index",
			"find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"GdUnitFileAccess.find_last_path_index",
			"GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"var iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"# scan for latest report directory\n\tvar iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)\n\t_current_report_path = \"%s/%s%d\" % [_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX, iteration]",
			code,
		],
	})


func test_multiline_call_second_argument_member_expands_before_argument_line() -> void:
	var code := "func set_current_report_path() -> void:\n\t# scan for latest report directory\n\tvar iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)\n\t_current_report_path = \"%s/%s%d\" % [_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX, iteration]"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 25),
		"expected": [
			"GdUnitConstants",
			"GdUnitConstants.REPORT_DIR_PREFIX",
			"_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX",
			"find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"var iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)",
			"# scan for latest report directory\n\tvar iteration := GdUnitFileAccess.find_last_path_index(\n\t\t_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX\n\t)\n\t_current_report_path = \"%s/%s%d\" % [_report_root_path, GdUnitConstants.REPORT_DIR_PREFIX, iteration]",
			code,
		],
	})


func test_backslash_continuation_member_call_argument_expands_before_line() -> void:
	var code := "func render_result() -> GdUnitResult:\n\tcontent += \"</pre>\"\n\tcontent = content\\\n\t\t.replace(\"ansi\", \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_ITALIC, \"\")\n\treturn GdUnitResult.success(content)"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(4, 36),
		"expected": [
			"CSI_BOLD",
			"GdUnitCSIMessageWriter.CSI_BOLD",
			"GdUnitCSIMessageWriter.CSI_BOLD, \"\"",
			"replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")",
			".replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")\\",
			"content\\\n\t\t.replace(\"ansi\", \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_ITALIC, \"\")",
			"content = content\\\n\t\t.replace(\"ansi\", \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_ITALIC, \"\")",
			"content += \"</pre>\"\n\tcontent = content\\\n\t\t.replace(\"ansi\", \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_BOLD, \"\")\\\n\t\t.replace(GdUnitCSIMessageWriter.CSI_ITALIC, \"\")\n\treturn GdUnitResult.success(content)",
			code,
		],
	})


func test_array_item_expands_to_array_literal() -> void:
	_assert_expansions({
		"code": "var path := [start, middle, goal]",
		"caret": Vector2i(0, 21),
		"expected": [
			"middle",
			"[start, middle, goal]",
			"var path := [start, middle, goal]",
		],
	})


func test_multiline_string_format_array_item_expands_through_rhs() -> void:
	var code := "func build_failure(errorLog: Variant) -> void:\n\tvar failure := \"\"\"\n\t\t%s\n\t\t%s %s\n\t\t%s\"\"\".dedent().trim_prefix(\"\\n\") % [\n\t\tGdAssertMessages._error(\"Godot Runtime Error !\"),\n\t\tGdAssertMessages._error(\"Error:\"),\n\t\tGdAssertMessages._colored_value(errorLog._message),\n\t\tGdAssertMessages._colored(errorLog._details, GdAssertMessages.VALUE_COLOR)]"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(6, 31),
		"expected": [
			"Error:",
			"\"Error:\"",
			"_error(\"Error:\")",
			"GdAssertMessages._error(\"Error:\")",
			"GdAssertMessages._error(\"Error:\"),",
			"[\n\t\tGdAssertMessages._error(\"Godot Runtime Error !\"),\n\t\tGdAssertMessages._error(\"Error:\"),\n\t\tGdAssertMessages._colored_value(errorLog._message),\n\t\tGdAssertMessages._colored(errorLog._details, GdAssertMessages.VALUE_COLOR)]",
			"\"\"\"\n\t\t%s\n\t\t%s %s\n\t\t%s\"\"\".dedent().trim_prefix(\"\\n\")",
			"\"\"\"\n\t\t%s\n\t\t%s %s\n\t\t%s\"\"\".dedent().trim_prefix(\"\\n\") % [\n\t\tGdAssertMessages._error(\"Godot Runtime Error !\"),\n\t\tGdAssertMessages._error(\"Error:\"),\n\t\tGdAssertMessages._colored_value(errorLog._message),\n\t\tGdAssertMessages._colored(errorLog._details, GdAssertMessages.VALUE_COLOR)]",
			"var failure := \"\"\"\n\t\t%s\n\t\t%s %s\n\t\t%s\"\"\".dedent().trim_prefix(\"\\n\") % [\n\t\tGdAssertMessages._error(\"Godot Runtime Error !\"),\n\t\tGdAssertMessages._error(\"Error:\"),\n\t\tGdAssertMessages._colored_value(errorLog._message),\n\t\tGdAssertMessages._colored(errorLog._details, GdAssertMessages.VALUE_COLOR)]",
			code,
		],
	})


func test_multiline_dictionary_entry_expands_to_dictionary_before_function() -> void:
	var code := "func example() -> void:\n\tvar caret := Vector2i.ZERO\n\tvar current := {\n\t\t\"from_line\": caret.x,\n\t\t\"from_col\": caret.y,\n\t}\n\tprint(current)"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 18),
		"expected": [
			"caret",
			"caret.x",
			"\"from_line\": caret.x,",
			"{\n\t\t\"from_line\": caret.x,\n\t\t\"from_col\": caret.y,\n\t}",
			"var current := {\n\t\t\"from_line\": caret.x,\n\t\t\"from_col\": caret.y,\n\t}",
			"var caret := Vector2i.ZERO\n\tvar current := {\n\t\t\"from_line\": caret.x,\n\t\t\"from_col\": caret.y,\n\t}\n\tprint(current)",
			code,
		],
	})


func test_dictionary_entry_method_call_skips_value_only_trailing_comma() -> void:
	var code := "return {\n\t\"to_line\": code.get_selection_to_line(),\n}"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(1, 22),
		"expected": [
			"get_selection_to_line",
			"get_selection_to_line()",
			"code.get_selection_to_line()",
			"\"to_line\": code.get_selection_to_line(),",
			"{\n\t\"to_line\": code.get_selection_to_line(),\n}",
			code,
		],
	})


func test_multiline_call_dictionary_entry_expands_to_dictionary_before_call() -> void:
	var code := "func test_case() -> void:\n\tvar code := \"value\"\n\t_assert_expansions({\n\t\t\"code\": code,\n\t\t\"caret\": Vector2i(3, 18),\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t})"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 10),
		"expected": [
			"code",
			"\"code\": code,",
			"{\n\t\t\"code\": code,\n\t\t\"caret\": Vector2i(3, 18),\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t}",
			"_assert_expansions({\n\t\t\"code\": code,\n\t\t\"caret\": Vector2i(3, 18),\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t})",
			"var code := \"value\"\n\t_assert_expansions({\n\t\t\"code\": code,\n\t\t\"caret\": Vector2i(3, 18),\n\t\t\"expected\": [\n\t\t\t\"value\",\n\t\t],\n\t})",
			code,
		],
	})


func test_nested_multiline_collection() -> void:
	var code := "var data := {\n\t\"path\": [\n\t\tVector2i(1, 2),\n\t\tVector2i(3, 4),\n\t],\n}"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(2, 11),
		"expected": [
			"1",
			"1, 2",
			"Vector2i(1, 2)",
			"Vector2i(1, 2),",
			"[\n\t\tVector2i(1, 2),\n\t\tVector2i(3, 4),\n\t]",
			"\"path\": [\n\t\tVector2i(1, 2),\n\t\tVector2i(3, 4),\n\t],",
			"{\n\t\"path\": [\n\t\tVector2i(1, 2),\n\t\tVector2i(3, 4),\n\t],\n}",
			code,
		],
	})
