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


func test_popup_size_keeps_code_near_half_editor_width_and_twelve_lines() -> void:
	var editor_size := Vector2i(1000, 800)
	var short := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		2,
		20
	)
	var wide := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		900,
		180,
		2,
		20
	)
	var twelve_lines := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		12,
		20
	)
	var many_lines := GitPreviousVersionPopup.popup_size_for_metrics(
		editor_size,
		120,
		180,
		100,
		20
	)

	assert_int(short.x).is_equal(420)
	assert_int(wide.x).is_equal(816)
	assert_int(short.y).is_less(twelve_lines.y)
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

	assert_vector(popup_size).is_equal(Vector2i(990, 326))
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
		popup._widest_content_width(old_lines)
		+ ceili(code_style_size.x)
		+ GitPreviousVersionPopup.TEXT_EDIT_CONTENT_PADDING
	)
	var required_code_height: int = (
		2 * popup._previous_code.get_line_height()
		+ ceili(code_style_size.y)
	)
	assert_int(popup.size.x).is_less_equal(900)
	assert_float(popup._previous_code.size.x).is_greater_equal(required_code_width)
	assert_float(popup._previous_code.size.y).is_greater_equal(required_code_height)
	assert_bool(popup._previous_code.get_h_scroll_bar().visible).is_false()
	assert_bool(popup._previous_code.get_v_scroll_bar().visible).is_false()
	assert_float(popup._margin.get_bound_minimum_size().x).is_less_equal(popup.size.x)
	assert_float(popup._margin.get_bound_minimum_size().y).is_less_equal(popup.size.y)
	assert_vector(popup.size).is_equal(popup.min_size)
	assert_vector(popup.min_size).is_equal(popup.max_size)

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
