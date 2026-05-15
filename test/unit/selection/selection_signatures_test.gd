extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_function_signature_expands_to_function_before_file() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\treturn \"\\n\".join(lines)"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 6),
		"expected": [
			"_slice_range",
			"func _slice_range(text: String, selection_range: Dictionary) -> String:",
			code,
		],
	})


func test_function_parameter_name_expands_to_parameter_before_function() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\treturn \"\\n\".join(lines)"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 34),
		"expected": [
			"selection_range",
			"selection_range: Dictionary",
			"text: String, selection_range: Dictionary",
			"(text: String, selection_range: Dictionary)",
			"func _slice_range(text: String, selection_range: Dictionary) -> String:",
			code,
		],
	})


func test_function_parameter_type_expands_to_parameter_before_function() -> void:
	var code := "func _slice_range(text: String, selection_range: Dictionary) -> String:\n\tvar lines := text.split(\"\\n\", true)\n\treturn \"\\n\".join(lines)"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 50),
		"expected": [
			"Dictionary",
			"selection_range: Dictionary",
			"text: String, selection_range: Dictionary",
			"(text: String, selection_range: Dictionary)",
			"func _slice_range(text: String, selection_range: Dictionary) -> String:",
			code,
		],
	})


func test_function_parameter_default_value() -> void:
	var code := "func move_to(target: Vector2i = Vector2i.ZERO) -> void:\n\tpass"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 33),
		"expected": [
			"Vector2i",
			"Vector2i.ZERO",
			"Vector2i = Vector2i.ZERO",
			"target: Vector2i = Vector2i.ZERO",
			"(target: Vector2i = Vector2i.ZERO)",
			"func move_to(target: Vector2i = Vector2i.ZERO) -> void:",
			code,
		],
	})


func test_function_parameter_empty_dictionary_default_value() -> void:
	var code := "func shrink_target(current: Dictionary = {}, candidates: Array[Dictionary] = []) -> Dictionary:\n\treturn current"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 42),
		"expected": [
			"{}",
			"Dictionary = {}",
			"current: Dictionary = {}",
			"current: Dictionary = {}, candidates: Array[Dictionary] = []",
			"(current: Dictionary = {}, candidates: Array[Dictionary] = [])",
			"func shrink_target(current: Dictionary = {}, candidates: Array[Dictionary] = []) -> Dictionary:",
			code,
		],
	})


func test_function_parameter_empty_array_default_value() -> void:
	var code := "func shrink_target(current: Dictionary = {}, candidates: Array[Dictionary] = []) -> Dictionary:\n\treturn candidates"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 78),
		"expected": [
			"[]",
			"Array[Dictionary] = []",
			"candidates: Array[Dictionary] = []",
			"current: Dictionary = {}, candidates: Array[Dictionary] = []",
			"(current: Dictionary = {}, candidates: Array[Dictionary] = [])",
			"func shrink_target(current: Dictionary = {}, candidates: Array[Dictionary] = []) -> Dictionary:",
			code,
		],
	})


func test_function_parameter_list_content_expands_before_parenthesized_list() -> void:
	var code := "func _make_range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:\n\treturn {}"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 36),
		"expected": [
			"from_col",
			"from_col: int",
			"from_line: int, from_col: int, to_line: int, to_col: int",
			"(from_line: int, from_col: int, to_line: int, to_col: int)",
			"func _make_range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:",
			code,
		],
	})


func test_return_type_expands_to_signature() -> void:
	var code := "func is_valid() -> bool:\n\treturn true"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 20),
		"expected": [
			"bool",
			"-> bool",
			"func is_valid() -> bool:",
			code,
		],
	})
