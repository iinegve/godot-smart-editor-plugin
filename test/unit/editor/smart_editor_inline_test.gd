extends GdUnitTestSuite

const LocalVariableInliningUseCase := preload("res://addons/smart-editor-plugin/features/local_variable_inlining/use_case.gd")


func test_parse_declaration_expression_supports_typed_and_inferred_vars() -> void:
	var use_case := LocalVariableInliningUseCase.new()

	var plain := "\tvar inline_candidate = target.build_label(\"plain\")"
	var typed := "\tvar inline_candidate: String = target.build_label(\"typed\")"
	var inferred := "\tvar inline_candidate := target.build_label(\"inferred\")"

	assert_str(use_case.parse_declaration_expression(plain, "inline_candidate", plain.find("inline_candidate"))).is_equal("target.build_label(\"plain\")")
	assert_str(use_case.parse_declaration_expression(typed, "inline_candidate", typed.find("inline_candidate"))).is_equal("target.build_label(\"typed\")")
	assert_str(use_case.parse_declaration_expression(inferred, "inline_candidate", inferred.find("inline_candidate"))).is_equal("target.build_label(\"inferred\")")


func test_inline_can_start_from_usage_when_lsp_references_include_declaration() -> void:
	var use_case := LocalVariableInliningUseCase.new()
	var uri := "file:///project/demo.gd"
	var text := "\n".join([
		"func demo() -> void:",
		"\tvar value: int = source + 1",
		"\tprint(value)",
		"\treturn value",
	])

	var plan := use_case.build_inline_plan(text, uri, "value", 2, _line(text, 2).find("value"), [
		_lsp_reference(uri, 2, _line(text, 2).find("value"), "value"),
		_lsp_reference(uri, 1, _line(text, 1).find("value"), "value"),
		_lsp_reference(uri, 3, _line(text, 3).find("value"), "value"),
	])

	assert_bool(plan.has("error")).is_false()
	assert_str(_apply_inline_plan(text, plan)).is_equal("\n".join([
		"func demo() -> void:",
		"\tprint(source + 1)",
		"\treturn source + 1",
	]))


func test_inline_uses_lsp_reference_set_for_same_name_variables_in_different_branches() -> void:
	var use_case := LocalVariableInliningUseCase.new()
	var uri := "file:///project/demo.gd"
	var text := "\n".join([
		"func demo(flag: bool) -> void:",
		"\tif flag:",
		"\t\tvar blah: int = 17",
		"\t\tprint(blah)",
		"\telse:",
		"\t\tvar blah: int = 23",
		"\t\tprint(blah)",
	])

	var plan := use_case.build_inline_plan(text, uri, "blah", 6, _line(text, 6).find("blah"), [
		_lsp_reference(uri, 5, _line(text, 5).find("blah"), "blah"),
		_lsp_reference(uri, 6, _line(text, 6).find("blah"), "blah"),
	])

	assert_bool(plan.has("error")).is_false()
	assert_str(_apply_inline_plan(text, plan)).is_equal("\n".join([
		"func demo(flag: bool) -> void:",
		"\tif flag:",
		"\t\tvar blah: int = 17",
		"\t\tprint(blah)",
		"\telse:",
		"\t\tprint(23)",
	]))


func test_inline_refuses_reassignment_after_resolving_declaration_from_usage() -> void:
	var use_case := LocalVariableInliningUseCase.new()
	var uri := "file:///project/demo.gd"
	var original := "\n".join([
		"func demo() -> void:",
		"\tvar value = source + 1",
		"\tvalue = 3",
		"\tprint(value)",
	])

	var plan := use_case.build_inline_plan(original, uri, "value", 3, _line(original, 3).find("value"), [
		_lsp_reference(uri, 1, _line(original, 1).find("value"), "value"),
		_lsp_reference(uri, 2, _line(original, 2).find("value"), "value"),
		_lsp_reference(uri, 3, _line(original, 3).find("value"), "value"),
	])

	assert_str(str(plan.get("error", ""))).is_equal("refusing to inline 'value' because it appears to be assigned again.")


func test_inline_rejects_ambiguous_declarations_from_reference_set() -> void:
	var use_case := LocalVariableInliningUseCase.new()
	var uri := "file:///project/demo.gd"
	var text := "\n".join([
		"func demo() -> void:",
		"\tvar value = 1",
		"\tprint(value)",
		"\tvar value = 2",
		"\tprint(value)",
	])

	assert_dict(use_case.find_declaration_from_references(text.split("\n", true), uri, "value", [
		_lsp_reference(uri, 1, _line(text, 1).find("value"), "value"),
		_lsp_reference(uri, 3, _line(text, 3).find("value"), "value"),
	])).is_empty()


func _lsp_reference(uri: String, line: int, character: int, symbol: String) -> Dictionary:
	return {
		"uri": uri,
		"range": {
			"start": {
				"line": line,
				"character": character,
			},
			"end": {
				"line": line,
				"character": character + symbol.length(),
			},
		},
	}


func _line(text: String, line_index: int) -> String:
	var lines := text.split("\n", true)
	return str(lines[line_index])


func _apply_inline_plan(text: String, plan: Dictionary) -> String:
	var code := CodeEdit.new()
	code.text = text
	for edit in plan["edits"]:
		_replace_range_in_code(
			code,
			int(edit["line"]),
			int(edit["from_col"]),
			int(edit["line"]),
			int(edit["to_col"]),
			str(edit["replacement"])
		)
	code.remove_line_at(int(plan["declaration_line"]))
	var result := code.get_text()
	code.free()
	return result


func _replace_range_in_code(code: CodeEdit, from_line: int, from_col: int, to_line: int, to_col: int, new_text: String) -> void:
	if from_line == to_line:
		var line := code.get_line(from_line)
		code.set_line(from_line, line.substr(0, from_col) + new_text + line.substr(to_col))
		return

	var first_line := code.get_line(from_line)
	var last_line := code.get_line(to_line)
	var replacement_lines := new_text.split("\n")

	code.set_line(from_line, first_line.substr(0, from_col) + replacement_lines[0])
	for index in range(1, replacement_lines.size()):
		code.insert_line_at(from_line + index, replacement_lines[index])

	var final_line := from_line + replacement_lines.size() - 1
	code.set_line(final_line, code.get_line(final_line) + last_line.substr(to_col))
	for line_index in range(to_line + replacement_lines.size() - 1, final_line, -1):
		code.remove_line_at(line_index)
