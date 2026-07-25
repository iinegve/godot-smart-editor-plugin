extends GdUnitTestSuite

const SymbolUsageController := preload("res://addons/smart-editor-plugin/features/highlights/smart_symbol_usage_controller.gd")
const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const SymbolUsageStripe := preload("res://addons/smart-editor-plugin/features/highlights/smart_symbol_usage_stripe.gd")


func test_folded_usages_collapse_to_signature_and_click_keeps_folded() -> void:
	var code := _create_code([
		"\tfunc folded_function() -> void:",
		"\t\tprint(value)",
		"\t\tvalue += 1",
		"var after := value",
	])
	code.fold_line(0)
	var stripe := _attach_stripe(code)
	var references: Array[Dictionary] = [
		_ref(1, 8, 13),
		_ref(2, 2, 7),
	]
	stripe.set_usage_references(references, code.get_line_count(), _ref(2, 2, 7))

	assert_int(stripe._markers.size()).is_equal(1)
	assert_dict(stripe._markers[0]["target"]).is_equal(_ref(0, 1, 1))
	assert_bool(stripe._markers[0]["is_current"]).is_true()

	var controller := SymbolUsageController.new()
	controller._code = code
	stripe.usage_clicked.connect(controller._on_stripe_usage_clicked)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(
		SymbolUsageStripe.STRIPE_WIDTH * 0.5,
		SymbolUsageModel.reference_y(0, stripe._visible_row_count, stripe.size.y)
	)
	stripe._gui_input(click)

	assert_int(code.get_caret_line()).is_equal(0)
	assert_int(code.get_caret_column()).is_equal(1)
	assert_bool(code.is_line_folded(0)).is_true()

	controller.free()
	code.free()


func test_fold_polling_rebuilds_once_per_state_change() -> void:
	var code := _create_code([
		"func folded_function() -> void:",
		"\tprint(value)",
		"\tvalue += 1",
		"var after := value",
	])
	var stripe := _attach_stripe(code)
	var references: Array[Dictionary] = [
		_ref(1, 7, 12),
		_ref(2, 1, 6),
		_ref(3, 13, 18),
	]
	stripe.set_usage_references(references, code.get_line_count(), _ref(1, 7, 12))

	assert_array(_marker_lines(stripe)).is_equal([1, 2, 3])
	assert_bool(stripe._sync_visual_state()).is_false()

	code.fold_line(0)
	assert_bool(stripe._sync_visual_state()).is_true()
	assert_array(_marker_lines(stripe)).is_equal([0, 3])
	assert_bool(stripe._sync_visual_state()).is_false()

	code.unfold_line(0)
	assert_bool(stripe._sync_visual_state()).is_true()
	assert_array(_marker_lines(stripe)).is_equal([1, 2, 3])
	assert_bool(stripe._sync_visual_state()).is_false()

	code.free()


func test_markers_use_visual_rows_around_folded_and_wrapped_content() -> void:
	var wrapped_line := "var wrapped := prefix prefix prefix prefix prefix prefix prefix prefix prefix value"
	var wrapped_column := wrapped_line.rfind("value")
	var code := _create_code([
		"var before := value",
		"func folded_function() -> void:",
		"\tprint(value)",
		"\tvalue += 1",
		wrapped_line,
		"var after := value",
	])
	code.size = Vector2(180, 320)
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(code.get_line_wrap_count(4)).is_greater(0)

	code.fold_line(1)
	var stripe := _attach_stripe(code)
	var references: Array[Dictionary] = [
		_ref(0, 14, 19),
		_ref(2, 7, 12),
		_ref(4, wrapped_column, wrapped_column + 5),
		_ref(5, 13, 18),
	]
	stripe.set_usage_references(references, code.get_line_count(), _ref(0, 14, 19))
	var rows_before_wrapped_line := (
		code.get_line_wrap_count(0) + 1
		+ code.get_line_wrap_count(1) + 1
	)

	assert_int(_marker_for_line(stripe, 0)["visual_row"]).is_equal(0)
	assert_int(_marker_for_line(stripe, 1)["visual_row"]).is_equal(1)
	assert_int(_marker_for_line(stripe, 4)["visual_row"]).is_equal(
		rows_before_wrapped_line + code.get_line_wrap_index_at_column(4, wrapped_column)
	)
	assert_int(_marker_for_line(stripe, 5)["visual_row"]).is_equal(
		rows_before_wrapped_line + code.get_line_wrap_count(4) + 1
	)

	code.free()


func _create_code(lines: Array[String]) -> CodeEdit:
	var code := CodeEdit.new()
	code.set_line_folding_enabled(true)
	code.text = "\n".join(lines)
	add_child(code)
	return code


func _attach_stripe(code: CodeEdit) -> Control:
	var stripe := SymbolUsageStripe.new()
	code.add_child(stripe)
	stripe.size = Vector2(SymbolUsageStripe.STRIPE_WIDTH, 200.0)
	stripe.attach_to_code(code)
	return stripe


func _marker_lines(stripe: Control) -> Array:
	return stripe._markers.map(func(marker: Dictionary) -> int: return int(marker["target"]["line"]))


func _marker_for_line(stripe: Control, line: int) -> Dictionary:
	for marker in stripe._markers:
		if int(marker["target"]["line"]) == line:
			return marker
	return {}


func _ref(line: int, column: int, end_column: int) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"end_line": line,
		"end_column": end_column,
	}
