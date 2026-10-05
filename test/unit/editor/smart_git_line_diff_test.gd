extends GdUnitTestSuite

const GitLineDiff := preload("res://addons/smart-editor-plugin/features/git_changes/git_line_diff.gd")


func test_identical_text_has_no_changes() -> void:
	assert_array(GitLineDiff.changes("first\nsecond\n", "first\nsecond\n")).is_empty()


func test_trailing_newline_only_is_not_a_line_change() -> void:
	assert_array(GitLineDiff.changes("value\n", "value")).is_empty()


func test_added_line_in_the_middle_is_green_hunk() -> void:
	assert_array(GitLineDiff.changes("first\nthird", "first\nsecond\nthird")).is_equal([
		_change(GitLineDiff.TYPE_ADDED, 1, [], 1, ["second"]),
	])


func test_added_lines_at_beginning_and_end_are_separate_hunks() -> void:
	assert_array(GitLineDiff.changes("first\nsecond", "before\nfirst\nsecond\nafter")).is_equal([
		_change(GitLineDiff.TYPE_ADDED, 0, [], 0, ["before"]),
		_change(GitLineDiff.TYPE_ADDED, 2, [], 3, ["after"]),
	])


func test_deleted_line_in_the_middle_keeps_its_current_boundary() -> void:
	assert_array(GitLineDiff.changes("first\ndeleted\nthird", "first\nthird")).is_equal([
		_change(GitLineDiff.TYPE_DELETED, 1, ["deleted"], 1, []),
	])


func test_deleted_line_at_end_uses_end_of_file_boundary() -> void:
	assert_array(GitLineDiff.changes("first\nsecond\ndeleted", "first\nsecond")).is_equal([
		_change(GitLineDiff.TYPE_DELETED, 2, ["deleted"], 2, []),
	])


func test_replacement_is_one_modified_hunk_with_previous_text() -> void:
	assert_array(GitLineDiff.changes(
		"before\nold one\nold two\nafter",
		"before\nnew one\nnew two\nnew three\nafter"
	)).is_equal([
		_change(
			GitLineDiff.TYPE_MODIFIED,
			1,
			["old one", "old two"],
			1,
			["new one", "new two", "new three"]
		),
	])


func test_multiple_independent_changes_keep_stable_line_coordinates() -> void:
	var previous := "\n".join([
		"alpha",
		"keep",
		"remove one",
		"remove two",
		"middle",
		"tail",
	])
	var current := "\n".join([
		"start new",
		"alpha",
		"keep",
		"replacement",
		"middle",
		"tail",
		"end new",
	])

	assert_array(GitLineDiff.changes(previous, current)).is_equal([
		_change(GitLineDiff.TYPE_ADDED, 0, [], 0, ["start new"]),
		_change(
			GitLineDiff.TYPE_MODIFIED,
			2,
			["remove one", "remove two"],
			3,
			["replacement"]
		),
		_change(GitLineDiff.TYPE_ADDED, 6, [], 6, ["end new"]),
	])


func test_repeated_and_blank_lines_still_locate_replacement() -> void:
	var previous := "\n".join(["value", "", "value", "tail"])
	var current := "\n".join(["value", "", "changed", "tail"])

	assert_array(GitLineDiff.changes(previous, current)).is_equal([
		_change(GitLineDiff.TYPE_MODIFIED, 2, ["value"], 2, ["changed"]),
	])


func test_missing_baseline_marks_entire_non_empty_file_as_added() -> void:
	assert_array(GitLineDiff.changes("", "first\nsecond", false)).is_equal([
		_change(GitLineDiff.TYPE_ADDED, 0, [], 0, ["first", "second"]),
	])
	assert_array(GitLineDiff.changes("", "", false)).is_empty()


func test_deleting_all_content_keeps_previous_lines() -> void:
	assert_array(GitLineDiff.changes("first\nsecond", "")).is_equal([
		_change(GitLineDiff.TYPE_DELETED, 0, ["first", "second"], 0, []),
	])


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
