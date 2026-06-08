extends GdUnitTestSuite

const SmartSelectionRange := preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")
const SmartSelectionHistory := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/smart_selection_history.gd")


func test_shrink_selection_steps_back_through_expand_history() -> void:
	var history := SmartSelectionHistory.new()
	var caret := _range(0, 37, 0, 37)
	var default_value := _range(0, 33, 0, 46)
	var arguments := _range(0, 27, 0, 53)
	var method_call := _range(0, 9, 0, 54)

	history.record(caret)
	history.record(default_value)
	history.record(arguments)

	_assert_range(history.shrink_target(method_call, []), arguments)
	_assert_range(history.shrink_target(arguments, []), default_value)
	_assert_range(history.shrink_target(default_value, []), caret)
	assert_int(history.size()).is_equal(0)


func test_shrink_selection_skips_history_entries_outside_current_selection() -> void:
	var history := SmartSelectionHistory.new()
	var unrelated := _range(1, 0, 1, 10)
	var previous := _range(0, 27, 0, 53)
	var current := _range(0, 9, 0, 54)

	history.record(unrelated)
	history.record(previous)
	history.record(unrelated)

	_assert_range(history.shrink_target(current, []), previous)


func test_shrink_selection_falls_back_without_history() -> void:
	var history := SmartSelectionHistory.new()
	var current := _range(0, 9, 0, 54)
	var default_value := _range(0, 33, 0, 46)
	var arguments := _range(0, 27, 0, 53)

	_assert_range(history.shrink_target(current, [default_value, arguments]), arguments)


func _range(from_line: int, from_col: int, to_line: int, to_col: int) -> SmartSelectionRange:
	return SmartSelectionRange.create(from_line, from_col, to_line, to_col)


func _assert_range(actual: SmartSelectionRange, expected: SmartSelectionRange) -> void:
	assert_bool(actual != null).is_true()
	assert_int(actual.from_line).is_equal(expected.from_line)
	assert_int(actual.from_col).is_equal(expected.from_col)
	assert_int(actual.to_line).is_equal(expected.to_line)
	assert_int(actual.to_col).is_equal(expected.to_col)
