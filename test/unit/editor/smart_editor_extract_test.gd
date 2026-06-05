extends GdUnitTestSuite

const LocalVariableExtractionUseCase := preload("res://addons/smart-editor-plugin/features/local_variable_extraction/use_case.gd")


func test_suggest_name_uses_last_call_segment() -> void:
	var use_case := LocalVariableExtractionUseCase.new()

	assert_str(use_case.suggest_name("target.build_round_label()")).is_equal("build_round_label")


func test_suggest_name_falls_back_when_expression_cannot_be_identifier() -> void:
	var use_case := LocalVariableExtractionUseCase.new()

	assert_str(use_case.suggest_name("17 + 4")).is_equal("value")


func test_build_edit_plan_inserts_declaration_and_replaces_selection() -> void:
	var use_case := LocalVariableExtractionUseCase.new()
	var line := "\treturn target.build_round_label()"
	var expression := "target.build_round_label()"
	var variable_name := "round_label"
	var selection_range := {
		"from_line": 3,
		"from_col": line.find(expression),
		"to_line": 3,
		"to_col": line.find(expression) + expression.length(),
	}

	var plan := use_case.build_edit_plan(line, selection_range, expression, variable_name)

	assert_int(int(plan["line_index"])).is_equal(3)
	assert_str(plan["declaration"]).is_equal("\tvar round_label = target.build_round_label()")
	assert_str(plan["replaced_line"]).is_equal("\treturn round_label")
	assert_int(int(plan["selection_from_col"])).is_equal(line.find(expression))
	assert_int(int(plan["selection_to_col"])).is_equal(line.find(expression) + variable_name.length())
