extends GdUnitTestSuite

const SmartEditorController := preload("res://addons/smart-editor-plugin/smart_editor/smart_editor_controller.gd")


func test_parse_declaration_expression_supports_typed_and_inferred_vars() -> void:
	var controller := SmartEditorController.new()

	var plain := "\tvar inline_candidate = target.build_label(\"plain\")"
	var typed := "\tvar inline_candidate: String = target.build_label(\"typed\")"
	var inferred := "\tvar inline_candidate := target.build_label(\"inferred\")"

	assert_str(controller._parse_declaration_expression(plain, "inline_candidate", plain.find("inline_candidate"))).is_equal("target.build_label(\"plain\")")
	assert_str(controller._parse_declaration_expression(typed, "inline_candidate", typed.find("inline_candidate"))).is_equal("target.build_label(\"typed\")")
	assert_str(controller._parse_declaration_expression(inferred, "inline_candidate", inferred.find("inline_candidate"))).is_equal("target.build_label(\"inferred\")")

	controller.free()


func test_inline_can_start_from_usage_when_lsp_references_include_declaration() -> void:
	var controller := SmartEditorController.new()
	var code := CodeEdit.new()
	var uri := "file:///project/demo.gd"
	code.text = "\n".join([
		"func demo() -> void:",
		"\tvar value: int = source + 1",
		"\tprint(value)",
		"\treturn value",
	])
	controller._inline_code = code
	controller._inline_uri = uri
	controller._inline_symbol = "value"
	controller._inline_symbol_line = 2
	controller._inline_symbol_column = code.get_line(2).find("value")

	controller._inline_apply_from_references([
		_lsp_reference(uri, 2, code.get_line(2).find("value"), "value"),
		_lsp_reference(uri, 1, code.get_line(1).find("value"), "value"),
		_lsp_reference(uri, 3, code.get_line(3).find("value"), "value"),
	])

	assert_str(code.get_text()).is_equal("\n".join([
		"func demo() -> void:",
		"\tprint(source + 1)",
		"\treturn source + 1",
	]))

	code.free()
	controller.free()


func test_inline_uses_lsp_reference_set_for_same_name_variables_in_different_branches() -> void:
	var controller := SmartEditorController.new()
	var code := CodeEdit.new()
	var uri := "file:///project/demo.gd"
	code.text = "\n".join([
		"func demo(flag: bool) -> void:",
		"\tif flag:",
		"\t\tvar blah: int = 17",
		"\t\tprint(blah)",
		"\telse:",
		"\t\tvar blah: int = 23",
		"\t\tprint(blah)",
	])
	controller._inline_code = code
	controller._inline_uri = uri
	controller._inline_symbol = "blah"
	controller._inline_symbol_line = 6
	controller._inline_symbol_column = code.get_line(6).find("blah")

	controller._inline_apply_from_references([
		_lsp_reference(uri, 5, code.get_line(5).find("blah"), "blah"),
		_lsp_reference(uri, 6, code.get_line(6).find("blah"), "blah"),
	])

	assert_str(code.get_text()).is_equal("\n".join([
		"func demo(flag: bool) -> void:",
		"\tif flag:",
		"\t\tvar blah: int = 17",
		"\t\tprint(blah)",
		"\telse:",
		"\t\tprint(23)",
	]))

	code.free()
	controller.free()


func test_inline_refuses_reassignment_after_resolving_declaration_from_usage() -> void:
	var controller := SmartEditorController.new()
	var code := CodeEdit.new()
	var uri := "file:///project/demo.gd"
	var original := "\n".join([
		"func demo() -> void:",
		"\tvar value = source + 1",
		"\tvalue = 3",
		"\tprint(value)",
	])
	code.text = original
	controller._inline_code = code
	controller._inline_uri = uri
	controller._inline_symbol = "value"
	controller._inline_symbol_line = 3
	controller._inline_symbol_column = code.get_line(3).find("value")

	controller._inline_apply_from_references([
		_lsp_reference(uri, 1, code.get_line(1).find("value"), "value"),
		_lsp_reference(uri, 2, code.get_line(2).find("value"), "value"),
		_lsp_reference(uri, 3, code.get_line(3).find("value"), "value"),
	])

	assert_str(code.get_text()).is_equal(original)

	code.free()
	controller.free()


func test_inline_rejects_ambiguous_declarations_from_reference_set() -> void:
	var controller := SmartEditorController.new()
	var code := CodeEdit.new()
	var uri := "file:///project/demo.gd"
	code.text = "\n".join([
		"func demo() -> void:",
		"\tvar value = 1",
		"\tprint(value)",
		"\tvar value = 2",
		"\tprint(value)",
	])
	controller._inline_code = code
	controller._inline_uri = uri
	controller._inline_symbol = "value"

	assert_dict(controller._inline_find_declaration_from_references([
		_lsp_reference(uri, 1, code.get_line(1).find("value"), "value"),
		_lsp_reference(uri, 3, code.get_line(3).find("value"), "value"),
	])).is_empty()

	code.free()
	controller.free()


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
