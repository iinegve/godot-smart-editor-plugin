extends GdUnitTestSuite

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/smart_editor/smart_symbol_usage_model.gd")


func test_symbol_range_under_caret_finds_identifier_before_or_inside_caret() -> void:
	var line := "var selected := code.get_selected_text()"

	assert_dict(SymbolUsageModel.symbol_range_in_line(line, 0, 22)).is_equal({
		"symbol": "get_selected_text",
		"line": 0,
		"column": 21,
		"end_column": 38,
	})
	assert_dict(SymbolUsageModel.symbol_range_in_line(line, 0, 38)).is_equal({
		"symbol": "get_selected_text",
		"line": 0,
		"column": 21,
		"end_column": 38,
	})


func test_symbol_range_under_caret_finds_for_loop_variable() -> void:
	assert_dict(SymbolUsageModel.symbol_range_in_line("for reference in _references:", 0, 6)).is_equal({
		"symbol": "reference",
		"line": 0,
		"column": 4,
		"end_column": 13,
	})


func test_symbol_range_under_caret_finds_identifier_before_dot() -> void:
	assert_dict(SymbolUsageModel.symbol_range_in_line("_current_reference.clear()", 0, 18)).is_equal({
		"symbol": "_current_reference",
		"line": 0,
		"column": 0,
		"end_column": 18,
	})
	assert_dict(SymbolUsageModel.symbol_range_in_line("code.get_selected_text()", 0, 4)).is_equal({
		"symbol": "code",
		"line": 0,
		"column": 0,
		"end_column": 4,
	})


func test_symbol_range_under_caret_returns_empty_for_non_identifier_without_left_identifier() -> void:
	assert_dict(SymbolUsageModel.symbol_range_in_line(".get_selected_text()", 0, 0)).is_empty()


func test_symbol_range_under_caret_returns_empty_for_language_keywords() -> void:
	assert_dict(SymbolUsageModel.symbol_range_in_line("func refresh() -> void:", 0, 2)).is_empty()
	assert_dict(SymbolUsageModel.symbol_range_in_line("var selected := code.get_selected_text()", 0, 1)).is_empty()
	assert_dict(SymbolUsageModel.symbol_range_in_line("func refresh() -> void:", 0, 22)).is_empty()
	assert_dict(SymbolUsageModel.symbol_range_in_line("@export var health := 10", 0, 3)).is_empty()


func test_symbol_range_under_caret_returns_empty_inside_comments_and_strings() -> void:
	assert_dict(SymbolUsageModel.symbol_range_in_line("var key := \"to_col\"", 0, 13)).is_empty()
	assert_dict(SymbolUsageModel.symbol_range_in_line("# to_col in comment", 0, 4)).is_empty()


func test_symbol_context_detects_member_call_symbols() -> void:
	assert_bool(SymbolUsageModel.is_member_call_symbol("_references.clear()", 12, 17)).is_true()
	assert_bool(SymbolUsageModel.is_member_call_symbol("clear()", 0, 5)).is_false()
	assert_bool(SymbolUsageModel.is_member_call_symbol("GdUnitConstants.REPORT_DIR_PREFIX", 16, 33)).is_false()
	assert_bool(SymbolUsageModel.is_member_call_symbol("button.pressed.connect(refresh)", 24, 31)).is_false()


func test_references_for_symbol_in_text_returns_empty_for_language_keywords() -> void:
	var code := "\n".join([
		"func refresh() -> void:",
		"\tvar value := 1",
		"\treturn",
	])

	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "func")).is_empty()
	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "var")).is_empty()
	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "void")).is_empty()


func test_references_for_uri_filters_and_sorts_lsp_references() -> void:
	var uri := "file:///project/player.gd"
	var references := [
		_lsp_reference("file:///project/enemy.gd", 1, 4, 1, 10),
		_lsp_reference(uri, 4, 12, 4, 18),
		_lsp_reference(uri, 1, 8, 1, 14),
		_lsp_reference(uri, 1, 2, 1, 8),
	]

	assert_array(SymbolUsageModel.references_for_uri(references, uri)).is_equal([
		{"line": 1, "column": 2, "end_line": 1, "end_column": 8},
		{"line": 1, "column": 8, "end_line": 1, "end_column": 14},
		{"line": 4, "column": 12, "end_line": 4, "end_column": 18},
	])


func test_identifier_references_for_uri_filters_strings_comments_and_sorts() -> void:
	var uri := "file:///project/player.gd"
	var code := "\n".join([
		"var to_col := 10",
		"col = int(result.back()[\"to_col\"])",
		"# to_col in comment",
		"print(to_col)",
	])
	var references := [
		_lsp_reference(uri, 1, 25, 1, 31),
		_lsp_reference(uri, 3, 6, 3, 12),
		_lsp_reference(uri, 2, 2, 2, 8),
		_lsp_reference(uri, 0, 4, 0, 10),
	]

	assert_array(SymbolUsageModel.identifier_references_for_uri(references, uri, code, "to_col")).is_equal([
		_ref(0, 4, 10),
		_ref(3, 6, 12),
	])


func test_references_for_symbol_in_text_finds_function_definition_and_calls() -> void:
	var code := "\n".join([
		"func refresh() -> void:",
		"\trefresh()",
		"\tbutton.pressed.connect(refresh)",
	])

	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "refresh")).is_equal([
		_ref(0, 5, 12),
		_ref(1, 1, 8),
		_ref(2, 24, 31),
	])


func test_references_for_symbol_in_text_finds_constants_and_class_fields() -> void:
	var code := "\n".join([
		"const REPORT_DIR_PREFIX = \"report_\"",
		"var _current_report_path := REPORT_DIR_PREFIX",
		"self._current_report_path = REPORT_DIR_PREFIX",
	])

	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "REPORT_DIR_PREFIX")).is_equal([
		_ref(0, 6, 23),
		_ref(1, 28, 45),
		_ref(2, 28, 45),
	])
	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "_current_report_path")).is_equal([
		_ref(1, 4, 24),
		_ref(2, 5, 25),
	])


func test_references_for_symbol_in_text_ignores_substrings_comments_and_strings() -> void:
	var code := "\n".join([
		"var value := 1",
		"var value_extra := value",
		"# value in comment",
		"var text := \"value\"",
	])

	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "value")).is_equal([
		_ref(0, 4, 9),
		_ref(1, 19, 24),
	])


func test_references_for_symbol_in_text_ignores_multiline_strings() -> void:
	var code := "\n".join([
		"var value := 1",
		"var text := \"\"\"",
		"value in string",
		"\"\"\"",
		"print(value)",
	])

	assert_array(SymbolUsageModel.references_for_symbol_in_text(code, "value")).is_equal([
		_ref(0, 4, 9),
		_ref(4, 6, 11),
	])


func test_reference_y_maps_lines_to_stripe_height() -> void:
	assert_float(SymbolUsageModel.reference_y(0, 11, 100.0)).is_equal_approx(0.0, 0.001)
	assert_float(SymbolUsageModel.reference_y(5, 11, 100.0)).is_equal_approx(50.0, 0.001)
	assert_float(SymbolUsageModel.reference_y(10, 11, 100.0)).is_equal_approx(100.0, 0.001)


func test_closest_reference_for_y_returns_nearest_usage() -> void:
	var references := [
		{"line": 2, "column": 1, "end_line": 2, "end_column": 4},
		{"line": 8, "column": 1, "end_line": 8, "end_column": 4},
	]

	assert_dict(SymbolUsageModel.closest_reference_for_y(references, 11, 100.0, 78.0)).is_equal(
		{"line": 8, "column": 1, "end_line": 8, "end_column": 4}
	)


func _lsp_reference(uri: String, line: int, column: int, end_line: int, end_column: int) -> Dictionary:
	return {
		"uri": uri,
		"range": _lsp_range(line, column, end_line, end_column),
	}


func _ref(line: int, column: int, end_column: int) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"end_line": line,
		"end_column": end_column,
	}


func _lsp_range(line: int, column: int, end_line: int, end_column: int) -> Dictionary:
	return {
		"start": {
			"line": line,
			"character": column,
		},
		"end": {
			"line": end_line,
			"character": end_column,
		},
	}
