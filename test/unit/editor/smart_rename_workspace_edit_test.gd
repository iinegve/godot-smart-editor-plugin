extends GdUnitTestSuite

const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")
const RenameEditSet := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_edit_set.gd")
const RenameTextEdit := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_text_edit.gd")


func test_workspace_edit_extracts_changes_by_uri() -> void:
	var player_uri := "file:///project/player.gd"
	var enemy_uri := "file:///project/enemy.gd"
	var player_edit := _edit(1, 5, 1, 16, "build_label_2")
	var enemy_edit := _edit(3, 8, 3, 19, "build_label_2")

	var edit_set: RenameEditSet = RenameEditSet.from_lsp_workspace_edit({
		"changes": {
			enemy_uri: [_lsp_edit(enemy_edit)],
			player_uri: [_lsp_edit(player_edit)],
		},
	})

	assert_int(edit_set.file_count()).is_equal(2)
	_assert_file_edit(edit_set, enemy_uri, enemy_edit)
	_assert_file_edit(edit_set, player_uri, player_edit)


func test_workspace_edit_extracts_document_changes_by_uri() -> void:
	var player_uri := "file:///project/player.gd"
	var edit := _edit(1, 5, 1, 16, "build_label_2")

	var edit_set: RenameEditSet = RenameEditSet.from_lsp_workspace_edit({
		"documentChanges": [{
			"textDocument": {
				"uri": player_uri,
			},
			"edits": [_lsp_edit(edit)],
		}],
	})

	assert_int(edit_set.file_count()).is_equal(1)
	_assert_file_edit(edit_set, player_uri, edit)


func test_workspace_edit_returns_empty_edit_set_for_invalid_input() -> void:
	assert_bool(RenameEditSet.from_lsp_workspace_edit("not a workspace edit").is_empty()).is_true()
	assert_bool(RenameEditSet.from_lsp_workspace_edit({}).is_empty()).is_true()
	assert_bool(RenameEditSet.from_lsp_workspace_edit({
		"changes": {
			"file:///project/player.gd": ["not a text edit"],
		},
	}).is_empty()).is_true()


func test_text_edits_are_applied_from_bottom_to_top() -> void:
	var text := "\n".join([
		"func build_label() -> String:",
		"\treturn build_label()",
	])

	assert_str(SmartRenameWorkspaceEdit.apply_text_edits_to_text(text, _edits([
		_edit(0, 5, 0, 16, "build_label_2"),
		_edit(1, 8, 1, 19, "build_label_2"),
	]))).is_equal("\n".join([
		"func build_label_2() -> String:",
		"\treturn build_label_2()",
	]))


func test_line_col_to_offset_rejects_columns_outside_target_line() -> void:
	var text := "ab\ncde"

	assert_int(SmartRenameWorkspaceEdit.line_col_to_offset(text, 0, 0)).is_equal(0)
	assert_int(SmartRenameWorkspaceEdit.line_col_to_offset(text, 0, 2)).is_equal(2)
	assert_int(SmartRenameWorkspaceEdit.line_col_to_offset(text, 1, 3)).is_equal(6)
	assert_int(SmartRenameWorkspaceEdit.line_col_to_offset(text, 0, 3)).is_equal(-1)
	assert_int(SmartRenameWorkspaceEdit.line_col_to_offset(text, 1, 4)).is_equal(-1)


func test_text_edits_ignore_same_line_edit_with_columns_outside_target_line() -> void:
	var text := "ab\ncde"

	assert_str(SmartRenameWorkspaceEdit.apply_text_edits_to_text(text, _edits([
		_edit(0, 3, 0, 3, "X"),
	]))).is_equal(text)


func test_text_edits_can_update_code_edit_buffer() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"var first := value",
		"var second := value",
	])

	SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(code, _edits([
		_edit(0, 13, 0, 18, "result"),
		_edit(1, 14, 1, 19, "result"),
	]))

	assert_str(code.get_text()).is_equal("\n".join([
		"var first := result",
		"var second := result",
	]))

	code.free()


func test_text_edits_can_update_code_edit_buffer_as_one_undo_operation() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"var first := value",
		"var second := value",
	])

	SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(code, _edits([
		_edit(0, 13, 0, 18, "result"),
		_edit(1, 14, 1, 19, "result"),
	]))
	code.undo()

	assert_str(code.get_text()).is_equal("\n".join([
		"var first := value",
		"var second := value",
	]))

	code.free()


func test_sync_script_from_code_edit_updates_script_source_code() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"extends Node",
		"",
		"func renamed() -> void:",
		"\tpass",
	])
	var script := GDScript.new()
	script.set_source_code("\n".join([
		"extends Node",
		"",
		"func original() -> void:",
		"\tpass",
	]))

	SmartRenameWorkspaceEdit.sync_script_from_code_edit(script, code)

	assert_str(script.get_source_code()).is_equal(code.get_text())

	code.free()


func test_save_code_edit_to_script_path_writes_buffer_to_disk() -> void:
	var path := "user://smart_rename_save_probe.gd"
	var code := CodeEdit.new()
	code.text = "\n".join([
		"extends Node",
		"",
		"func renamed() -> void:",
		"\tpass",
	])
	var script := GDScript.new()
	script.take_over_path(path)

	assert_bool(SmartRenameWorkspaceEdit.save_code_edit_to_script_path(script, code)).is_true()
	assert_str(FileAccess.get_file_as_string(path)).is_equal(code.get_text())

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	code.free()


func _edit(from_line: int, from_col: int, to_line: int, to_col: int, new_text: String) -> RenameTextEdit:
	return RenameTextEdit.create(from_line, from_col, to_line, to_col, new_text)


func _edits(items: Array) -> Array[RenameTextEdit]:
	var result: Array[RenameTextEdit] = []
	result.assign(items)
	return result


func _lsp_edit(edit: RenameTextEdit) -> Dictionary:
	return {
		"range": _range(edit.start_line, edit.start_column, edit.end_line, edit.end_column),
		"newText": edit.new_text,
	}


func _range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return {
		"start": {
			"line": from_line,
			"character": from_col,
		},
		"end": {
			"line": to_line,
			"character": to_col,
		},
	}


func _assert_file_edit(edit_set: RenameEditSet, uri: String, expected_edit: RenameTextEdit) -> void:
	var file_edits = edit_set.file_for_uri(uri)
	assert_bool(file_edits != null).is_true()
	assert_int(file_edits.edits.size()).is_equal(1)
	_assert_edit(file_edits.edits[0], expected_edit)


func _assert_edit(actual: RenameTextEdit, expected: RenameTextEdit) -> void:
	assert_int(actual.start_line).is_equal(expected.start_line)
	assert_int(actual.start_column).is_equal(expected.start_column)
	assert_int(actual.end_line).is_equal(expected.end_line)
	assert_int(actual.end_column).is_equal(expected.end_column)
	assert_str(actual.new_text).is_equal(expected.new_text)
