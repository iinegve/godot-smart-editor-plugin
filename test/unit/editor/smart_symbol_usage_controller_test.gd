extends GdUnitTestSuite

const SymbolUsageController := preload("res://addons/smart-editor-plugin/smart_symbol_usage_controller.gd")


class FakeStripe:
	var references: Array = []
	var line_count := 0
	var current_reference := {}


	func set_usage_references(new_references: Array, new_line_count: int, new_current_reference: Dictionary) -> void:
		references = new_references.duplicate()
		line_count = new_line_count
		current_reference = new_current_reference.duplicate()


	func clear_references() -> void:
		references.clear()
		line_count = 0
		current_reference.clear()


func test_initialize_request_guard_rejects_dictionary_requests() -> void:
	assert_bool(SymbolUsageController._is_initialize_request({
		"uri": "file:///project/player.gd",
		"symbol": "health",
	})).is_false()


func test_initialize_request_guard_accepts_initialize_marker() -> void:
	assert_bool(SymbolUsageController._is_initialize_request("initialize")).is_true()


func test_empty_lsp_references_fall_back_to_current_file_function_tokens() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"func refresh() -> void:",
		"\trefresh()",
		"\tbutton.pressed.connect(refresh)",
	])
	code.set_caret_line(0)
	code.set_caret_column(6)

	var stripe := FakeStripe.new()
	var controller := SymbolUsageController.new()
	controller._code = code
	controller._uri = "file:///project/player.gd"
	controller._stripe = stripe

	controller._apply_references([], {
		"uri": "file:///project/player.gd",
		"symbol": "refresh",
		"line": 0,
		"column": 5,
		"end_line": 0,
		"end_column": 12,
		"code_version": code.get_version(),
	})

	assert_array(stripe.references).is_equal([
		_ref(0, 5, 12),
		_ref(1, 1, 8),
		_ref(2, 24, 31),
	])
	assert_int(stripe.line_count).is_equal(3)
	assert_dict(stripe.current_reference).is_equal(_ref(0, 5, 12))

	controller.free()
	code.free()


func _ref(line: int, column: int, end_column: int) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"end_line": line,
		"end_column": end_column,
	}
