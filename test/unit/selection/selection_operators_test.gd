extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_assignment_rhs_from_left_identifier() -> void:
	_assert_expansions({
		"code": "var next = cell + dir",
		"caret": Vector2i(0, 11),
		"expected": [
			"cell",
			"cell + dir",
			"var next = cell + dir",
		],
	})


func test_assignment_rhs_from_right_identifier() -> void:
	_assert_expansions({
		"code": "var next = cell + dir",
		"caret": Vector2i(0, 18),
		"expected": [
			"dir",
			"cell + dir",
			"var next = cell + dir",
		],
	})


func test_comparison_rhs_expands_to_comparison() -> void:
	_assert_expansions({
		"code": "if action_points >= max_path_length:",
		"caret": Vector2i(0, 21),
		"expected": [
			"max_path_length",
			"action_points >= max_path_length",
			"if action_points >= max_path_length:",
		],
	})


func test_arithmetic_precedence_keeps_multiplication_before_addition() -> void:
	_assert_expansions({
		"code": "var cost := base + step * multiplier",
		"caret": Vector2i(0, 20),
		"expected": [
			"step",
			"step * multiplier",
			"base + step * multiplier",
			"var cost := base + step * multiplier",
		],
	})


func test_multiline_return_condition_continuation_expands_from_subscript_key() -> void:
	var code := "func _ranges_equal(a: Dictionary, b: Dictionary) -> bool:\n\treturn (\n\t\ta[\"from_line\"] == b[\"from_line\"]\n\t\tand a[\"from_col\"] == b[\"from_col\"]\n\t\tand a[\"to_line\"] == b[\"to_line\"]\n\t\tand a[\"to_col\"] == b[\"to_col\"]\n\t)"
	var condition := "(\n\t\ta[\"from_line\"] == b[\"from_line\"]\n\t\tand a[\"from_col\"] == b[\"from_col\"]\n\t\tand a[\"to_line\"] == b[\"to_line\"]\n\t\tand a[\"to_col\"] == b[\"to_col\"]\n\t)"
	var return_statement := "return " + condition
	_assert_expansions({
		"code": code,
		"caret": Vector2i(3, 29),
		"expected": [
			"from_col",
			"\"from_col\"",
			"b[\"from_col\"]",
			"a[\"from_col\"] == b[\"from_col\"]",
			"and a[\"from_col\"] == b[\"from_col\"]",
			condition,
			return_statement,
			code,
		],
	})
