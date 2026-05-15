extends "res://test/unit/selection/selection_parser_test_base.gd"


func test_preload_path_expands_to_call() -> void:
	_assert_expansions({
		"code": "const UnitScene := preload(\"res://scenes/unit.tscn\")",
		"caret": Vector2i(0, 34),
		"expected": [
			"res://scenes/unit.tscn",
			"\"res://scenes/unit.tscn\"",
			"preload(\"res://scenes/unit.tscn\")",
			"const UnitScene := preload(\"res://scenes/unit.tscn\")",
		],
	})


func test_typed_array_in_signature() -> void:
	var code := "func _move(unit: Unit, path: Array[Vector2i]) -> bool:\n\treturn true"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(0, 35),
		"expected": [
			"Vector2i",
			"Array[Vector2i]",
			"path: Array[Vector2i]",
			"unit: Unit, path: Array[Vector2i]",
			"(unit: Unit, path: Array[Vector2i])",
			"func _move(unit: Unit, path: Array[Vector2i]) -> bool:",
			code,
		],
	})


func test_node_path_dollar_access() -> void:
	_assert_expansions({
		"code": "$Camera2D.global_position",
		"caret": Vector2i(0, 3),
		"expected": [
			"Camera2D",
			"$Camera2D",
			"$Camera2D.global_position",
		],
	})


func test_unique_node_percent_access() -> void:
	_assert_expansions({
		"code": "%GridOverlay.unit_selected(coords, max_path_length)",
		"caret": Vector2i(0, 3),
		"expected": [
			"GridOverlay",
			"%GridOverlay",
			"%GridOverlay.unit_selected",
			"%GridOverlay.unit_selected(coords, max_path_length)",
		],
	})


func test_extends_target_expands_before_line() -> void:
	_assert_expansions({
		"code": "extends PanelContainer",
		"caret": Vector2i(0, 10),
		"expected": [
			"PanelContainer",
			"extends PanelContainer",
		],
	})


func test_class_name_target_expands_before_line() -> void:
	_assert_expansions({
		"code": "class_name PanelContainer",
		"caret": Vector2i(0, 14),
		"expected": [
			"PanelContainer",
			"class_name PanelContainer",
		],
	})


func test_enum_entry_expands_to_enum_body_before_file() -> void:
	var code := "class_name Comparison\n\nenum {\n\tEQUAL,\n\tLESS_THAN,\n\tLESS_EQUAL,\n\tGREATER_THAN,\n}"
	_assert_expansions({
		"code": code,
		"caret": Vector2i(5, 3),
		"expected": [
			"LESS_EQUAL",
			"LESS_EQUAL,",
			"EQUAL,\n\tLESS_THAN,\n\tLESS_EQUAL,\n\tGREATER_THAN,",
			"enum {\n\tEQUAL,\n\tLESS_THAN,\n\tLESS_EQUAL,\n\tGREATER_THAN,\n}",
		],
	})


func test_export_annotation_variable() -> void:
	_assert_expansions({
		"code": "@export var action_points := 4",
		"caret": Vector2i(0, 13),
		"expected": [
			"action_points",
			"action_points := 4",
			"var action_points := 4",
			"@export var action_points := 4",
		],
	})


func test_signal_parameter() -> void:
	_assert_expansions({
		"code": "signal unit_selected(unit: Unit, grid_coords: Vector2i)",
		"caret": Vector2i(0, 40),
		"expected": [
			"grid_coords",
			"grid_coords: Vector2i",
			"unit: Unit, grid_coords: Vector2i",
			"(unit: Unit, grid_coords: Vector2i)",
			"signal unit_selected(unit: Unit, grid_coords: Vector2i)",
		],
	})
