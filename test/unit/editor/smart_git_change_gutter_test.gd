extends GdUnitTestSuite

const GitLineDiff := preload("res://addons/smart-editor-plugin/features/git_changes/git_line_diff.gd")
const GitChangeGutter := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_change_gutter.gd"
)


func test_attach_inserts_a_narrow_named_gutter_before_builtin_gutters() -> void:
	var code := _create_code(["first"])
	var original_names := _gutter_names(code)
	var gutter := _attach_gutter(code)

	assert_int(code.get_gutter_count()).is_equal(original_names.size() + 1)
	assert_str(code.get_gutter_name(0)).is_equal(GitChangeGutter.GUTTER_NAME)
	assert_int(code.get_gutter_width(0)).is_equal(GitChangeGutter.GUTTER_WIDTH)
	assert_int(code.get_gutter_type(0)).is_equal(TextEdit.GUTTER_TYPE_CUSTOM)
	assert_bool(code.is_gutter_drawn(0)).is_true()
	assert_array(_gutter_names(code).slice(1)).is_equal(original_names)

	code.free()


func test_added_and_modified_hunks_mark_each_current_line_with_their_color() -> void:
	var code := _create_code(["zero", "one", "two", "three", "four"])
	var gutter := _attach_gutter(code)
	var added := _change(GitLineDiff.TYPE_ADDED, 1, [], 1, ["one", "two"])
	var modified := _change(GitLineDiff.TYPE_MODIFIED, 3, ["old"], 3, ["three"])

	gutter.set_changes(_changes([added, modified]))

	_assert_marker(code, 1, added, GitChangeGutter.ADDED_COLOR)
	_assert_marker(code, 2, added, GitChangeGutter.ADDED_COLOR)
	_assert_marker(code, 3, modified, GitChangeGutter.MODIFIED_COLOR)
	assert_bool(code.get_line_gutter_metadata(0, 0) is Dictionary).is_false()
	assert_bool(code.get_line_gutter_metadata(4, 0) is Dictionary).is_false()

	code.free()


func test_deleted_hunk_marks_its_current_boundary_in_gray() -> void:
	var code := _create_code(["before", "after"])
	var gutter := _attach_gutter(code)
	var deleted := _change(GitLineDiff.TYPE_DELETED, 1, ["removed"], 1, [])

	gutter.set_changes(_changes([deleted]))

	_assert_marker(code, 1, deleted, GitChangeGutter.DELETED_COLOR)
	assert_bool(code.get_line_gutter_metadata(0, 0) is Dictionary).is_false()

	code.free()


func test_deletion_at_end_of_file_anchors_to_last_current_line() -> void:
	var code := _create_code(["before", "last"])
	var gutter := _attach_gutter(code)
	var deleted := _change(GitLineDiff.TYPE_DELETED, 2, ["removed"], 2, [])

	gutter.set_changes(_changes([deleted]))

	_assert_marker(code, 1, deleted, GitChangeGutter.DELETED_COLOR)

	code.free()


func test_replacing_changes_clears_stale_line_metadata_and_clickability() -> void:
	var code := _create_code(["zero", "one", "two"])
	var gutter := _attach_gutter(code)
	gutter.set_changes(_changes([
		_change(GitLineDiff.TYPE_ADDED, 1, [], 1, ["one"]),
	]))

	gutter.set_changes(_changes([
		_change(GitLineDiff.TYPE_MODIFIED, 2, ["old"], 2, ["two"]),
	]))

	assert_bool(code.get_line_gutter_metadata(1, 0) is Dictionary).is_false()
	assert_bool(code.is_line_gutter_clickable(1, 0)).is_false()
	assert_bool(code.get_line_gutter_metadata(2, 0) is Dictionary).is_true()
	assert_bool(code.is_line_gutter_clickable(2, 0)).is_true()

	code.free()


func test_clicking_own_marker_emits_its_hunk_and_other_gutters_are_ignored() -> void:
	var code := _create_code(["zero", "one"])
	var gutter := _attach_gutter(code)
	var added := _change(GitLineDiff.TYPE_ADDED, 1, [], 1, ["one"])
	var clicked: Array[Dictionary] = []
	gutter.change_clicked.connect(func(change: Dictionary) -> void: clicked.append(change))
	gutter.set_changes(_changes([added]))

	gutter._on_gutter_clicked(1, 1)
	gutter._on_gutter_clicked(0, 0)
	gutter._on_gutter_clicked(1, 0)

	assert_array(clicked).is_equal([added])

	code.free()


func test_detach_removes_only_plugin_gutter_and_preserves_builtin_order() -> void:
	var code := _create_code(["first"])
	var original_names := _gutter_names(code)
	var gutter := _attach_gutter(code)

	gutter.detach()

	assert_array(_gutter_names(code)).is_equal(original_names)
	assert_int(gutter._gutter_index).is_equal(-1)

	code.free()


func _create_code(lines: Array[String]) -> CodeEdit:
	var code := CodeEdit.new()
	code.text = "\n".join(lines)
	add_child(code)
	return code


func _attach_gutter(code: CodeEdit) -> Node:
	var gutter := GitChangeGutter.new()
	code.add_child(gutter)
	gutter.attach_to_code(code)
	return gutter


func _assert_marker(code: CodeEdit, line: int, change: Dictionary, color: Color) -> void:
	assert_dict(code.get_line_gutter_metadata(line, 0)).is_equal(change)
	assert_bool(code.is_line_gutter_clickable(line, 0)).is_true()
	_assert_color_approx(code.get_line_gutter_item_color(line, 0), color)


func _assert_color_approx(actual: Color, expected: Color) -> void:
	assert_float(actual.r).is_equal_approx(expected.r, 0.001)
	assert_float(actual.g).is_equal_approx(expected.g, 0.001)
	assert_float(actual.b).is_equal_approx(expected.b, 0.001)
	assert_float(actual.a).is_equal_approx(expected.a, 0.001)


func _gutter_names(code: CodeEdit) -> Array:
	var names := []
	for index in code.get_gutter_count():
		names.append(code.get_gutter_name(index))
	return names


func _changes(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in values:
		result.append(value)
	return result


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
