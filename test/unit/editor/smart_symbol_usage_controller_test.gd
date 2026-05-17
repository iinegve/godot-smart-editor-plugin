extends GdUnitTestSuite

const SymbolUsageController := preload("res://addons/smart-editor-plugin/smart_symbol_usage_controller.gd")


class FakeSymbolUsageView:
	var references: Array = []
	var line_count := 0
	var current_reference := {}
	var clear_count := 0


	func set_usage_references(new_references: Array, new_line_count: int, new_current_reference: Dictionary) -> void:
		references = new_references.duplicate()
		line_count = new_line_count
		current_reference = new_current_reference.duplicate()


	func clear_references() -> void:
		clear_count += 1
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


func test_caret_changes_use_fast_debounce() -> void:
	var controller := SymbolUsageController.new()

	controller._on_code_caret_changed()

	assert_bool(controller._refresh_pending).is_true()
	assert_bool(controller._text_change_pending).is_false()
	assert_float(controller._debounce_remaining).is_equal_approx(
		SymbolUsageController.CARET_DEBOUNCE_SECONDS,
		0.001
	)

	controller.free()


func test_caret_changes_reset_existing_caret_debounce() -> void:
	var controller := SymbolUsageController.new()

	controller._on_code_caret_changed()
	controller._debounce_remaining = 0.01
	controller._on_code_caret_changed()

	assert_bool(controller._refresh_pending).is_true()
	assert_bool(controller._text_change_pending).is_false()
	assert_float(controller._debounce_remaining).is_equal_approx(
		SymbolUsageController.CARET_DEBOUNCE_SECONDS,
		0.001
	)

	controller.free()


func test_text_changes_clear_references_and_use_slow_debounce() -> void:
	var stripe := FakeSymbolUsageView.new()
	var highlight := FakeSymbolUsageView.new()
	stripe.set_usage_references([_ref(0, 1, 4)], 1, _ref(0, 1, 4))
	highlight.set_usage_references([_ref(0, 1, 4)], 1, _ref(0, 1, 4))

	var controller := SymbolUsageController.new()
	controller._stripe = stripe
	controller._highlight = highlight

	controller._on_code_text_changed()

	assert_bool(controller._refresh_pending).is_true()
	assert_bool(controller._text_change_pending).is_true()
	assert_float(controller._debounce_remaining).is_equal_approx(
		SymbolUsageController.TEXT_DEBOUNCE_SECONDS,
		0.001
	)
	assert_array(stripe.references).is_empty()
	assert_array(highlight.references).is_empty()
	assert_int(stripe.clear_count).is_equal(1)
	assert_int(highlight.clear_count).is_equal(1)

	controller.free()


func test_caret_changes_do_not_shorten_pending_text_debounce() -> void:
	var controller := SymbolUsageController.new()

	controller._on_code_text_changed()
	controller._debounce_remaining = 0.5
	controller._on_code_caret_changed()

	assert_bool(controller._refresh_pending).is_true()
	assert_bool(controller._text_change_pending).is_true()
	assert_float(controller._debounce_remaining).is_equal_approx(0.5, 0.001)

	controller.free()


func test_reference_request_waits_for_pending_caret_debounce() -> void:
	var controller := SymbolUsageController.new()
	controller._initialized = true
	controller._refresh_pending = true
	controller._debounce_remaining = SymbolUsageController.CARET_DEBOUNCE_SECONDS
	controller._queued_request = {
		"request_kind": "references",
		"uri": "file:///project/player.gd",
		"symbol": "health",
	}

	controller._try_send_references_request()

	assert_dict(controller._queued_request).is_not_empty()

	controller.free()


func test_reference_request_waits_for_pending_reference_response() -> void:
	var controller := SymbolUsageController.new()
	controller._initialized = true
	controller._queued_request = {
		"request_kind": "references",
		"uri": "file:///project/player.gd",
		"symbol": "health",
	}
	controller._pending_requests[7] = {
		"request_kind": "references",
		"uri": "file:///project/player.gd",
		"symbol": "previous",
	}

	controller._try_send_references_request()

	assert_dict(controller._queued_request).is_not_empty()

	controller.free()


func test_empty_lsp_references_fall_back_to_current_file_function_tokens() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"func refresh() -> void:",
		"\trefresh()",
		"\tbutton.pressed.connect(refresh)",
	])
	code.set_caret_line(0)
	code.set_caret_column(6)

	var stripe := FakeSymbolUsageView.new()
	var highlight := FakeSymbolUsageView.new()
	var controller := SymbolUsageController.new()
	controller._code = code
	controller._uri = "file:///project/player.gd"
	controller._stripe = stripe
	controller._highlight = highlight

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
	assert_array(highlight.references).is_equal(stripe.references)
	assert_int(highlight.line_count).is_equal(3)
	assert_dict(highlight.current_reference).is_equal(_ref(0, 5, 12))

	controller.free()
	code.free()


func test_empty_lsp_references_do_not_fall_back_for_member_method_names() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"func clear_references() -> void:",
		"\t_references.clear()",
		"\t_current_reference.clear()",
	])
	code.set_caret_line(1)
	code.set_caret_column(14)

	var stripe := FakeSymbolUsageView.new()
	var highlight := FakeSymbolUsageView.new()
	var controller := SymbolUsageController.new()
	controller._code = code
	controller._uri = "file:///project/player.gd"
	controller._stripe = stripe
	controller._highlight = highlight

	controller._apply_references([], {
		"uri": "file:///project/player.gd",
		"symbol": "clear",
		"line": 1,
		"column": 13,
		"end_line": 1,
		"end_column": 18,
		"code_version": code.get_version(),
		"is_member_call": true,
	})

	assert_array(stripe.references).is_empty()
	assert_int(stripe.line_count).is_equal(0)
	assert_dict(stripe.current_reference).is_empty()
	assert_array(highlight.references).is_empty()
	assert_int(highlight.line_count).is_equal(0)
	assert_dict(highlight.current_reference).is_empty()

	controller.free()
	code.free()


func test_lsp_references_include_current_for_loop_variable_declaration() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"for reference in _references:",
		"\tprint(reference)",
	])
	code.set_caret_line(0)
	code.set_caret_column(6)

	var stripe := FakeSymbolUsageView.new()
	var highlight := FakeSymbolUsageView.new()
	var controller := SymbolUsageController.new()
	controller._code = code
	controller._uri = "file:///project/player.gd"
	controller._stripe = stripe
	controller._highlight = highlight

	controller._apply_references([
		_lsp_reference("file:///project/player.gd", 1, 7, 1, 16),
	], {
		"uri": "file:///project/player.gd",
		"symbol": "reference",
		"line": 0,
		"column": 4,
		"end_line": 0,
		"end_column": 13,
		"code_version": code.get_version(),
	})

	assert_array(stripe.references).is_equal([
		_ref(0, 4, 13),
		_ref(1, 7, 16),
	])
	assert_dict(stripe.current_reference).is_equal(_ref(0, 4, 13))
	assert_array(highlight.references).is_equal(stripe.references)
	assert_dict(highlight.current_reference).is_equal(_ref(0, 4, 13))

	controller.free()
	code.free()


func test_stripe_rect_aligns_to_visible_vertical_scrollbar() -> void:
	assert_object(SymbolUsageController.stripe_rect_for_scrollbars(
		Vector2(800, 600),
		Rect2(784, 0, 16, 572),
		true,
		Rect2(0, 572, 784, 28),
		true,
		8.0
	)).is_equal(Rect2(776, 0, 8, 572))


func test_stripe_rect_without_vertical_scrollbar_excludes_horizontal_scrollbar() -> void:
	assert_object(SymbolUsageController.stripe_rect_for_scrollbars(
		Vector2(800, 600),
		Rect2(),
		false,
		Rect2(0, 572, 800, 28),
		true,
		8.0
	)).is_equal(Rect2(792, 0, 8, 572))


func _ref(line: int, column: int, end_column: int) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"end_line": line,
		"end_column": end_column,
	}


func _lsp_reference(uri: String, line: int, column: int, end_line: int, end_column: int) -> Dictionary:
	return {
		"uri": uri,
		"range": {
			"start": {
				"line": line,
				"character": column,
			},
			"end": {
				"line": end_line,
				"character": end_column,
			},
		},
	}
