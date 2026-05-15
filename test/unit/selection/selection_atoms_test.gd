extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_identifier_inside_call_expands_to_call() -> void:
	_assert_expansions({
		"code": "print(score)",
		"caret": Vector2i(0, 8),
		"expected": [
			"score",
			"print(score)",
		],
	})


func test_number_literal_expands_to_statement() -> void:
	_assert_expansions({
		"code": "var count := 42",
		"caret": Vector2i(0, 14),
		"expected": [
			"42",
			"var count := 42",
		],
	})


func test_null_literal_expands_to_return_statement() -> void:
	_assert_expansions({
		"code": "return null",
		"caret": Vector2i(0, 8),
		"expected": [
			"null",
			"return null",
		],
	})


func test_string_inside_call() -> void:
	_assert_expansions({
		"code": "if Input.is_action_just_pressed(\"focus_camera_on_target\"):",
		"caret": Vector2i(0, 40),
		"expected": [
			"focus_camera_on_target",
			"\"focus_camera_on_target\"",
			"is_action_just_pressed(\"focus_camera_on_target\")",
			"Input.is_action_just_pressed(\"focus_camera_on_target\")",
			"if Input.is_action_just_pressed(\"focus_camera_on_target\"):",
		],
	})


func test_boolean_keyword_in_inline_return() -> void:
	_assert_expansions({
		"code": "if unit_cell == Vector2i(grid_cell.x, grid_cell.y+1): return true",
		"caret": Vector2i(0, 63),
		"expected": [
			"true",
			"return true",
			"if unit_cell == Vector2i(grid_cell.x, grid_cell.y+1): return true",
		],
	})
