extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_member_chain_expands_one_segment_at_a_time() -> void:
	_assert_expansions({
		"code": "unit.global_position.x",
		"caret": Vector2i(0, 8),
		"expected": [
			"global_position",
			"global_position.x",
			"unit.global_position.x",
		],
	})


func test_subscript_key_expands_to_string_and_subscript() -> void:
	_assert_expansions({
		"code": "b[\"from_col\"]",
		"caret": Vector2i(0, 4),
		"expected": [
			"from_col",
			"\"from_col\"",
			"b[\"from_col\"]",
		],
	})


func test_call_argument_member_chain_expands_before_call() -> void:
	_assert_expansions({
		"code": "grid_overlay.to_grid_coords(_selected_squad_member.global_position)",
		"caret": Vector2i(0, 35),
		"expected": [
			"_selected_squad_member",
			"_selected_squad_member.global_position",
			"to_grid_coords(_selected_squad_member.global_position)",
			"grid_overlay.to_grid_coords(_selected_squad_member.global_position)",
		],
	})


func test_chained_subscript_member_call() -> void:
	_assert_expansions({
		"code": "unit.grid[path[index]].get_neighbor().position",
		"caret": Vector2i(0, 17),
		"expected": [
			"index",
			"path[index]",
			"unit.grid[path[index]]",
			"unit.grid[path[index]].get_neighbor()",
			"unit.grid[path[index]].get_neighbor().position",
		],
	})


func test_chained_subscript_method_name_expands_to_method_call_before_receiver_call() -> void:
	_assert_expansions({
		"code": "unit.grid[path[index]].get_neighbor().position",
		"caret": Vector2i(0, 25),
		"expected": [
			"get_neighbor",
			"get_neighbor()",
			"unit.grid[path[index]].get_neighbor()",
			"unit.grid[path[index]].get_neighbor().position",
		],
	})
