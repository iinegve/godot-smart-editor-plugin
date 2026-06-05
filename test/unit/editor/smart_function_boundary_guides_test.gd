extends GdUnitTestSuite

const FunctionBoundaryGuides := preload("res://addons/smart-editor-plugin/features/function_boundary_guides/smart_function_boundary_guides.gd")


func test_function_boundaries_ignore_blank_lines_inside_functions() -> void:
	var code := "\n".join([
		"func first() -> void:",
		"\tvar a := 1",
		"",
		"\tvar b := 2",
		"",
		"func second() -> void:",
		"\tpass",
	])

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(0, 3, 0),
		_boundary(5, 6, 0),
	])


func test_function_boundary_stops_before_next_same_indent_statement() -> void:
	var code := "\n".join([
		"class_name Player",
		"",
		"func ready() -> void:",
		"\tif visible:",
		"\t\tshow()",
		"",
		"const VALUE := 1",
	])

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(2, 4, 0),
	])


func test_indented_class_functions_end_before_next_member() -> void:
	var code := "\n".join([
		"class Inner:",
		"\tvar value := 1",
		"",
		"\tfunc update() -> void:",
		"\t\tvalue += 1",
		"",
		"\tvar done := true",
	])

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(3, 4, 1),
	])


func test_one_line_function_boundary_is_the_header_line() -> void:
	var code := "func value() -> int: return 1"

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(0, 0, 0),
	])


func test_static_function_header_is_supported() -> void:
	var code := "\n".join([
		"static func make() -> void:",
		"\tpass",
	])

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(0, 1, 0),
	])


func test_multiline_function_signature_boundary_uses_body_end() -> void:
	var code := "\n".join([
		"func configure(",
		"\thighlight_color_setting: StringName,",
		"\tcurrent_highlight_color_setting: StringName,",
		"\tcurrent_outline_color_setting: StringName",
		") -> void:",
		"\t_disconnect_editor_settings()",
		"\t_highlight_color_setting = highlight_color_setting",
		"\t_current_highlight_color_setting = current_highlight_color_setting",
		"\t_current_outline_color_setting = current_outline_color_setting",
		"\t_connect_editor_settings()",
		"\t_invalidate_rect_cache()",
	])

	assert_array(FunctionBoundaryGuides.function_boundaries(code)).is_equal([
		_boundary(0, 10, 0),
	])


func test_function_separator_guide_y_uses_middle_of_single_blank_line() -> void:
	var previous_line_rect := Rect2(0, 20, 100, 12)
	var header_line_rect := Rect2(0, 44, 100, 12)

	assert_float(FunctionBoundaryGuides.function_separator_guide_y(
		previous_line_rect,
		header_line_rect,
		true
	)).is_equal(38.0)


func test_function_separator_guide_y_stays_above_function_with_multiple_blank_lines() -> void:
	var previous_line_rect := Rect2(0, 20, 100, 12)
	var header_line_rect := Rect2(0, 56, 100, 12)

	assert_float(FunctionBoundaryGuides.function_separator_guide_y(
		previous_line_rect,
		header_line_rect,
		true
	)).is_equal(50.0)


func test_function_separator_guide_y_uses_middle_between_adjacent_lines() -> void:
	var previous_line_rect := Rect2(0, 20, 100, 12)
	var header_line_rect := Rect2(0, 32, 100, 12)

	assert_float(FunctionBoundaryGuides.function_separator_guide_y(
		previous_line_rect,
		header_line_rect,
		false
	)).is_equal(32.0)


func test_guide_start_x_uses_gutter_and_left_margin() -> void:
	assert_float(FunctionBoundaryGuides.guide_start_x_for_gutter(42.0, 6.0)).is_equal(48.0)


func test_line_rect_from_scroll_position_is_independent_from_horizontal_scroll() -> void:
	assert_object(FunctionBoundaryGuides.line_rect_for_scroll_position(
		4.0,
		1.5,
		20.0,
		6.0,
		300.0
	)).is_equal(Rect2(0, 56, 300, 20))


func test_folded_lines_signature_is_stable_for_same_lines() -> void:
	assert_str(FunctionBoundaryGuides.folded_lines_signature(PackedInt32Array([8, 2, 5]))).is_equal("2,5,8")


func test_folded_lines_signature_changes_when_folded_lines_change() -> void:
	var initial := FunctionBoundaryGuides.folded_lines_signature(PackedInt32Array([2, 5]))
	var changed := FunctionBoundaryGuides.folded_lines_signature(PackedInt32Array([2, 8]))

	assert_str(initial).is_not_equal(changed)


func test_indent_guide_block_border_columns_use_full_indent_steps() -> void:
	assert_array(Array(FunctionBoundaryGuides.indent_guide_block_border_columns(10, 4))).is_equal([0, 4])


func test_indent_guide_block_border_columns_include_exact_indent_step() -> void:
	assert_array(Array(FunctionBoundaryGuides.indent_guide_block_border_columns(8, 4))).is_equal([0, 4])


func test_indent_guide_block_border_columns_mark_first_indent_at_column_zero() -> void:
	assert_array(Array(FunctionBoundaryGuides.indent_guide_block_border_columns(4, 4))).is_equal([0])


func test_indent_guide_block_border_columns_ignore_partial_indent() -> void:
	assert_array(Array(FunctionBoundaryGuides.indent_guide_block_border_columns(3, 4))).is_empty()


func test_indent_guide_x_uses_content_start_column_width_and_horizontal_scroll() -> void:
	assert_float(FunctionBoundaryGuides.indent_guide_x(48.0, 8, 7.5, 10.0)).is_equal(98.0)


func _boundary(header_line: int, end_line: int, indent: int) -> Dictionary:
	return {
		"header_line": header_line,
		"end_line": end_line,
		"indent": indent,
	}
