extends GdUnitTestSuite

const SmartSelectionHistory := preload("res://addons/smart-editor-plugin/smart_selection_history.gd")


func test_shrink_selection_steps_back_through_expand_history() -> void:
	var history := SmartSelectionHistory.new()
	var caret := _range(0, 37, 0, 37)
	var default_value := _range(0, 33, 0, 46)
	var arguments := _range(0, 27, 0, 53)
	var method_call := _range(0, 9, 0, 54)

	history.record(caret)
	history.record(default_value)
	history.record(arguments)

	assert_dict(history.shrink_target(method_call, [])).is_equal(arguments)
	assert_dict(history.shrink_target(arguments, [])).is_equal(default_value)
	assert_dict(history.shrink_target(default_value, [])).is_equal(caret)
	assert_int(history.size()).is_equal(0)


func test_shrink_selection_skips_history_entries_outside_current_selection() -> void:
	var history := SmartSelectionHistory.new()
	var unrelated := _range(1, 0, 1, 10)
	var previous := _range(0, 27, 0, 53)
	var current := _range(0, 9, 0, 54)

	history.record(unrelated)
	history.record(previous)
	history.record(unrelated)

	assert_dict(history.shrink_target(current, [])).is_equal(previous)


func test_shrink_selection_falls_back_without_history() -> void:
	var history := SmartSelectionHistory.new()
	var current := _range(0, 9, 0, 54)
	var default_value := _range(0, 33, 0, 46)
	var arguments := _range(0, 27, 0, 53)

	assert_dict(history.shrink_target(current, [default_value, arguments])).is_equal(arguments)


func _range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return {
		"from_line": from_line,
		"from_col": from_col,
		"to_line": to_line,
		"to_col": to_col,
	}
