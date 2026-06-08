extends GdUnitTestSuite

const SelectionParser := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/gdscript_selection_parser.gd")
const SmartSelectionRange := preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")


func _assert_expansions(test_case: Dictionary) -> void:
	var parser := SelectionParser.new()
	var caret: Vector2i = test_case["caret"]
	var current: SmartSelectionRange = SmartSelectionRange.create(caret.x, caret.y, caret.x, caret.y)
	var candidates := parser.build_candidates(test_case["code"], current)
	var actual: Array[String] = []
	for candidate in candidates:
		actual.append(_slice_range(test_case["code"], candidate))

	assert_array(actual).is_equal(test_case["expected"])


func _assert_first_plugin_expansion(test_case: Dictionary) -> void:
	var parser := SelectionParser.new()
	var caret: Vector2i = test_case["caret"]
	var current: SmartSelectionRange = SmartSelectionRange.create(caret.x, caret.y, caret.x, caret.y)

	for candidate in parser.build_candidates(test_case["code"], current):
		if _range_strictly_contains(candidate, current):
			assert_str(_slice_range(test_case["code"], candidate)).is_equal(test_case["expected"])
			return

	fail("No plugin-style expansion candidate found.")


func _assert_next_plugin_expansion(test_case: Dictionary) -> void:
	var parser := SelectionParser.new()
	var current: SmartSelectionRange = _range_from_dictionary(test_case["current"])

	for candidate in parser.build_candidates(test_case["code"], current):
		if _range_strictly_contains(candidate, current):
			assert_str(_slice_range(test_case["code"], candidate)).is_equal(test_case["expected"])
			return

	fail("No plugin-style expansion candidate found.")


func _slice_range(text: String, selection_range: SmartSelectionRange) -> String:
	var lines := text.split("\n", true)
	var from_line := selection_range.from_line
	var from_col := selection_range.from_col
	var to_line := selection_range.to_line
	var to_col := selection_range.to_col

	if from_line == to_line:
		return String(lines[from_line]).substr(from_col, to_col - from_col)

	var parts: Array[String] = []
	parts.append(String(lines[from_line]).substr(from_col))
	for line_index in range(from_line + 1, to_line):
		parts.append(lines[line_index])
	parts.append(String(lines[to_line]).substr(0, to_col))
	return "\n".join(parts)


func _range_strictly_contains(outer: SmartSelectionRange, inner: SmartSelectionRange) -> bool:
	return outer.strictly_contains(inner)


func _ranges_equal(a: SmartSelectionRange, b: SmartSelectionRange) -> bool:
	return a.equals(b)


func _compare_positions(line_a: int, col_a: int, line_b: int, col_b: int) -> int:
	return SmartSelectionRange.compare_positions(line_a, col_a, line_b, col_b)


func _range_from_dictionary(selection_range: Dictionary) -> SmartSelectionRange:
	return SmartSelectionRange.create(
		int(selection_range["from_line"]),
		int(selection_range["from_col"]),
		int(selection_range["to_line"]),
		int(selection_range["to_col"])
	)
