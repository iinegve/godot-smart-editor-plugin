extends GdUnitTestSuite

const GitLineDiff := preload("res://addons/smart-editor-plugin/features/git_changes/git_line_diff.gd")
const GitPreviousVersionPopup := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_previous_version_popup.gd"
)


func test_modified_hunk_shows_previous_head_lines_as_read_only_code() -> void:
	var popup := _create_popup()
	var change := _change(
		GitLineDiff.TYPE_MODIFIED,
		4,
		["func old_name() -> void:", "\tpass"],
		4,
		["func new_name() -> void:", "\tpass"]
	)

	popup.show_change(change)

	assert_str(popup._heading.text).is_equal("Previous version (HEAD) — lines 5–6")
	assert_str(popup._previous_code.text).is_equal("func old_name() -> void:\n\tpass")
	assert_bool(popup._previous_code.editable).is_false()
	assert_bool(popup._previous_code.visible).is_true()
	assert_bool(popup._message.visible).is_false()

	popup.free()


func test_single_previous_line_uses_singular_heading() -> void:
	var popup := _create_popup()
	popup.show_change(_change(
		GitLineDiff.TYPE_DELETED,
		2,
		["removed"],
		2,
		[]
	))

	assert_str(popup._heading.text).is_equal("Previous version (HEAD) — line 3")
	assert_str(popup._previous_code.text).is_equal("removed")

	popup.free()


func test_added_hunk_explains_that_no_previous_lines_exist() -> void:
	var popup := _create_popup()
	popup.show_change(_change(
		GitLineDiff.TYPE_ADDED,
		1,
		[],
		1,
		["new line"]
	))

	assert_str(popup._heading.text).is_equal("Added code")
	assert_bool(popup._previous_code.visible).is_false()
	assert_bool(popup._message.visible).is_true()
	assert_str(popup._message.text).is_equal("This code has no previous version in HEAD.")

	popup.free()


func test_popup_size_follows_content_and_caps_at_twelve_lines() -> void:
	var editor_size := Vector2i(1000, 800)
	var short := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		2,
		20,
		26,
		50,
		8,
		8,
		16
	)
	var wide := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		900,
		180,
		2,
		20,
		26,
		50,
		8,
		8,
		16
	)
	var twelve_lines := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		12,
		20,
		26,
		50,
		8,
		8,
		16
	)
	var many_lines := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		100,
		20,
		26,
		50,
		8,
		8,
		16
	)

	assert_vector(short).is_equal(Vector2i(196, 90))
	assert_vector(wide).is_equal(Vector2i(900, 98))
	assert_int(twelve_lines.y).is_equal(290)
	assert_int(many_lines.y).is_equal(twelve_lines.y)


func test_scaled_editor_theme_leaves_room_for_code_edit_chrome() -> void:
	var popup_size := GitPreviousVersionPopup.popup_size_for_metrics(
		Vector2i(1222, 631),
		578,
		561,
		2,
		45,
		82,
		127,
		28
	)

	assert_vector(popup_size).is_equal(Vector2i(660, 217))
	assert_int(578 + 82).is_less_equal(popup_size.x)


func test_popup_rect_starts_near_click_and_stays_inside_editor() -> void:
	var editor_rect := Rect2i(100, 80, 800, 600)
	var popup_size := Vector2i(360, 240)

	var near_top_left := GitPreviousVersionPopup.popup_rect_for_anchor(
		Vector2i(140, 120),
		popup_size,
		editor_rect
	)
	var near_bottom_right := GitPreviousVersionPopup.popup_rect_for_anchor(
		Vector2i(890, 670),
		popup_size,
		editor_rect
	)

	assert_vector(near_top_left.position).is_equal(
		Vector2i(140, 120) + GitPreviousVersionPopup.ANCHOR_OFFSET
	)
	assert_vector(near_bottom_right.end).is_equal(editor_rect.end)
	assert_vector(near_bottom_right.size).is_equal(popup_size)


func test_short_two_line_popup_does_not_show_scrollbars_after_layout() -> void:
	var popup := _create_popup()
	var old_lines: Array[String] = [
		"var sphere2 := SphereShape3D.new()",
		"params.shape = sphere2",
	]
	popup.show_change(
		_change(
			GitLineDiff.TYPE_MODIFIED,
			326,
			old_lines,
			326,
			["changed", "changed again"]
		),
		Vector2i(120, 100),
		Rect2i(0, 0, 1000, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var code_style_size: Vector2 = popup._previous_code.get_theme_stylebox(&"read_only").get_minimum_size()
	var required_code_width: int = (
		popup._widest_content_width()
		+ ceili(code_style_size.x)
		+ GitPreviousVersionPopup.TEXT_EDIT_CONTENT_PADDING
	)
	var required_code_height: int = (
		2 * popup._previous_code.get_line_height()
		+ ceili(code_style_size.y)
	)
	assert_int(popup.size.x).is_less_equal(900)
	assert_float(popup._previous_code.size.x).is_greater_equal(required_code_width)
	assert_float(popup._previous_code.size.y).is_equal(float(required_code_height))
	assert_bool(popup._previous_code.get_h_scroll_bar().visible).is_false()
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_false()
	assert_object(popup._content.get_parent()).is_same(popup)
	assert_bool(popup._previous_code.scroll_fit_content_width).is_false()
	assert_bool(popup._previous_code.scroll_fit_content_height).is_false()

	popup.hide()
	popup.free()


func test_narrow_editor_caps_popup_at_ninety_percent_after_layout() -> void:
	var popup := _create_popup()
	popup.show_change(
		_change(
			GitLineDiff.TYPE_MODIFIED,
			326,
			["short"],
			326,
			["changed"]
		),
		Vector2i(20, 20),
		Rect2i(0, 0, 400, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(popup.size.x).is_less_equal(360)

	popup.hide()
	popup.free()


func test_preview_removes_common_tabs_but_preserves_relative_indentation_and_source() -> void:
	var popup := _create_popup()
	var old_lines: Array[String] = ["\t\tif ready:", "\t\t\tpass", "\t\treturn"]
	var change := _change(GitLineDiff.TYPE_MODIFIED, 4, old_lines, 4, ["changed"])

	popup.show_change(change)

	assert_str(popup._previous_code.text).is_equal("if ready:\n\tpass\nreturn")
	assert_array(change.old_lines).is_equal(old_lines)
	assert_array(old_lines).is_equal(["\t\tif ready:", "\t\t\tpass", "\t\treturn"])
	assert_str(popup._heading.text).is_equal("Previous version (HEAD) — lines 5–7")

	popup.free()


func test_preview_ignores_blank_lines_when_removing_common_spaces() -> void:
	var lines: Array[String] = ["", "    if ready:", "        pass", "  ", "    return", ""]

	assert_array(GitPreviousVersionPopup.preview_lines(lines)).is_equal([
		"", "if ready:", "    pass", "", "return", "",
	])


func test_preview_preserves_visual_indentation_with_mixed_tabs_and_spaces() -> void:
	var lines: Array[String] = ["  if ready:", "\t\tpass", "  \treturn"]

	assert_array(GitPreviousVersionPopup.preview_lines(lines, 4)).is_equal([
		"if ready:", "      pass", "  return",
	])


func test_preview_keeps_unindented_fragments_and_whitespace_only_hunks() -> void:
	var lines: Array[String] = ["func example():", "\tpass"]
	var whitespace: Array[String] = ["", "\t", "  "]

	assert_array(GitPreviousVersionPopup.preview_lines(lines)).is_equal(lines)
	assert_array(GitPreviousVersionPopup.preview_lines(whitespace)).is_equal(whitespace)


func test_preview_uses_the_source_editors_tab_size() -> void:
	var source := CodeEdit.new()
	source.indent_size = 8
	add_child(source)
	var popup := GitPreviousVersionPopup.new()
	source.add_child(popup)

	popup.show_change(_change(
		GitLineDiff.TYPE_MODIFIED, 0, ["    if ready:", "\tpass"], 0, ["new"]
	))

	assert_int(popup._previous_code.indent_size).is_equal(8)
	assert_str(popup._previous_code.text).is_equal("if ready:\n    pass")

	popup.hide()
	source.free()


func test_short_editor_reserves_space_for_both_scrollbars() -> void:
	var popup := _create_popup()
	popup.show_change(
		_change(GitLineDiff.TYPE_MODIFIED, 0, ["very_long_line".repeat(30), "second"], 0, ["new"]),
		Vector2i(20, 20),
		Rect2i(0, 0, 180, 90)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(popup.size.x).is_less_equal(162)
	assert_int(popup.size.y).is_less_equal(90)
	assert_bool(popup._previous_code.get_h_scroll_bar().visible).is_true()
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_true()

	popup.hide()
	popup.free()


func test_long_hunk_scrolls_with_a_twelve_line_viewport() -> void:
	var popup := _create_popup()
	var old_lines: Array[String] = []
	for line in 30:
		old_lines.append("\t\tvar line_%d = 1" % line)
	popup.show_change(
		_change(GitLineDiff.TYPE_DELETED, 0, old_lines, 0, []),
		Vector2i(20, 20),
		Rect2i(0, 0, 1000, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var style_size: Vector2 = popup._previous_code.get_theme_stylebox(&"read_only").get_minimum_size()
	assert_float(popup._previous_code.size.y).is_equal(
		float(12 * popup._previous_code.get_line_height() + ceili(style_size.y))
	)
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_true()
	assert_bool(popup._previous_code.get_h_scroll_bar().visible).is_false()
	popup._previous_code.scroll_vertical = 20
	assert_float(popup._previous_code.scroll_vertical).is_greater(0)

	popup.hide()
	popup.free()


func test_wide_line_scrolls_instead_of_enlarging_a_narrow_popup() -> void:
	var popup := _create_popup()
	popup.show_change(
		_change(GitLineDiff.TYPE_MODIFIED, 0, ["\t\tvar value = " + "long_text".repeat(30)], 0, ["new"]),
		Vector2i(20, 20),
		Rect2i(0, 0, 400, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(popup.size.x).is_less_equal(360)
	assert_bool(popup._previous_code.get_h_scroll_bar().visible).is_true()
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_false()
	assert_int(popup._previous_code.get_visible_line_count()).is_greater_equal(1)

	popup.hide()
	popup.free()


func test_reopening_a_large_popup_with_one_line_removes_the_extra_height() -> void:
	var popup := _create_popup()
	var old_lines: Array[String] = []
	for line in 30:
		old_lines.append("var line_%d = 1" % line)
	popup.show_change(
		_change(GitLineDiff.TYPE_DELETED, 0, old_lines, 0, []),
		Vector2i(20, 20),
		Rect2i(0, 0, 1000, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame
	popup.show_change(
		_change(GitLineDiff.TYPE_MODIFIED, 0, ["\t\tvar value = 1"], 0, ["new"]),
		Vector2i(20, 20),
		Rect2i(0, 0, 1000, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var style_size: Vector2 = popup._previous_code.get_theme_stylebox(&"read_only").get_minimum_size()
	assert_float(popup._previous_code.size.y).is_equal(
		float(popup._previous_code.get_line_height() + ceili(style_size.y))
	)
	assert_str(popup._previous_code.text).is_equal("var value = 1")
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_false()

	popup.hide()
	popup.free()


func test_added_code_message_wraps_in_a_narrow_popup() -> void:
	var popup := _create_popup()
	popup.show_change(
		_change(GitLineDiff.TYPE_ADDED, 0, [], 0, ["new"]),
		Vector2i(20, 20),
		Rect2i(0, 0, 180, 700)
	)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(popup.size.x).is_less_equal(162)
	assert_int(popup._message.get_line_count()).is_greater(1)
	assert_float(popup._message.size.y).is_equal(popup._message.get_minimum_size().y)
	assert_float(popup._message.get_global_rect().end.y).is_less_equal(popup.size.y)

	popup.hide()
	popup.free()


func _create_popup() -> PopupPanel:
	var popup := GitPreviousVersionPopup.new()
	add_child(popup)
	return popup


func _change(
	type: StringName,
	old_start: int,
	old_lines: Array[String],
	new_start: int,
	new_lines: Array[String]
) -> Dictionary:
	return {
		"type": type,
		"old_start": old_start,
		"old_count": old_lines.size(),
		"old_lines": old_lines,
		"new_start": new_start,
		"new_count": new_lines.size(),
		"new_lines": new_lines,
	}
