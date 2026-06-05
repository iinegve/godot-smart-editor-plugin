extends GdUnitTestSuite

const SymbolUsageHighlight := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_highlight.gd")


func test_default_colors_match_editor_setting_defaults() -> void:
	var highlight := SymbolUsageHighlight.new()

	_assert_color_approx(highlight._highlight_color(), SymbolUsageHighlight.DEFAULT_HIGHLIGHT_COLOR)
	_assert_color_approx(highlight._current_highlight_color(), SymbolUsageHighlight.DEFAULT_CURRENT_HIGHLIGHT_COLOR)
	_assert_color_approx(highlight._current_outline_color(), SymbolUsageHighlight.DEFAULT_CURRENT_OUTLINE_COLOR)

	highlight.free()


func test_set_and_clear_references_updates_highlight_state() -> void:
	var highlight := SymbolUsageHighlight.new()
	var reference := _ref(0, 4, 9)

	highlight.set_usage_references([reference], 3, reference)

	assert_array(highlight._references).is_equal([reference])
	assert_int(highlight._line_count).is_equal(3)
	assert_dict(highlight._current_reference).is_equal(reference)

	highlight.clear_references()

	assert_array(highlight._references).is_empty()
	assert_int(highlight._line_count).is_equal(0)
	assert_dict(highlight._current_reference).is_empty()

	highlight.free()


func test_set_and_clear_references_invalidates_cached_rectangles() -> void:
	var highlight := SymbolUsageHighlight.new()
	var reference := _ref(0, 4, 9)
	highlight._rect_cache = [{"rect": Rect2(1, 2, 3, 4), "current": false}]
	highlight._rect_cache_dirty = false

	highlight.set_usage_references([reference], 3, reference)

	assert_bool(highlight._rect_cache_dirty).is_true()
	assert_array(highlight._rect_cache).is_empty()

	highlight._rect_cache = [{"rect": Rect2(1, 2, 3, 4), "current": false}]
	highlight._rect_cache_dirty = false

	highlight.clear_references()

	assert_bool(highlight._rect_cache_dirty).is_true()
	assert_array(highlight._rect_cache).is_empty()

	highlight.free()


func test_editor_settings_changed_invalidates_cached_rectangles() -> void:
	var highlight := SymbolUsageHighlight.new()
	highlight._rect_cache = [{"rect": Rect2(1, 2, 3, 4), "current": false}]
	highlight._rect_cache_dirty = false

	highlight._on_editor_settings_changed()

	assert_bool(highlight._rect_cache_dirty).is_true()
	assert_array(highlight._rect_cache).is_empty()

	highlight.free()


func test_rect_lookup_column_uses_next_caret_column_for_character_rect() -> void:
	var highlight := SymbolUsageHighlight.new()

	assert_int(highlight._rect_lookup_column(4, "0123456789")).is_equal(5)
	assert_int(highlight._rect_lookup_column(9, "0123456789")).is_equal(10)
	assert_int(highlight._rect_lookup_column(10, "0123456789")).is_equal(10)

	highlight.free()


func _ref(line: int, column: int, end_column: int) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"end_line": line,
		"end_column": end_column,
	}


func _assert_color_approx(actual: Color, expected: Color) -> void:
	assert_float(actual.r).is_equal_approx(expected.r, 0.001)
	assert_float(actual.g).is_equal_approx(expected.g, 0.001)
	assert_float(actual.b).is_equal_approx(expected.b, 0.001)
	assert_float(actual.a).is_equal_approx(expected.a, 0.001)
