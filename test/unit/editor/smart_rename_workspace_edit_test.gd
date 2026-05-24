extends GdUnitTestSuite

const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")


func test_workspace_edit_extracts_changes_by_uri() -> void:
	var player_uri := "file:///project/player.gd"
	var enemy_uri := "file:///project/enemy.gd"
	var player_edit := _edit(1, 5, 1, 16, "build_label_2")
	var enemy_edit := _edit(3, 8, 3, 19, "build_label_2")

	assert_dict(SmartRenameWorkspaceEdit.workspace_edit_to_edits_by_uri({
		"changes": {
			enemy_uri: [enemy_edit],
			player_uri: [player_edit],
		},
	})).is_equal({
		enemy_uri: [enemy_edit],
		player_uri: [player_edit],
	})


func test_workspace_edit_extracts_document_changes_by_uri() -> void:
	var player_uri := "file:///project/player.gd"
	var edit := _edit(1, 5, 1, 16, "build_label_2")

	assert_dict(SmartRenameWorkspaceEdit.workspace_edit_to_edits_by_uri({
		"documentChanges": [{
			"textDocument": {
				"uri": player_uri,
			},
			"edits": [edit],
		}],
	})).is_equal({
		player_uri: [edit],
	})


func test_references_can_be_converted_to_workspace_edit() -> void:
	var player_uri := "file:///project/player.gd"
	var enemy_uri := "file:///project/enemy.gd"
	var player_range := _range(1, 5, 1, 16)
	var enemy_range := _range(3, 8, 3, 19)

	assert_dict(SmartRenameWorkspaceEdit.references_to_workspace_edit([
		{
			"uri": player_uri,
			"range": player_range,
		},
		{
			"uri": enemy_uri,
			"range": enemy_range,
		},
	], "build_label_2")).is_equal({
		"changes": {
			player_uri: [{
				"range": player_range,
				"newText": "build_label_2",
			}],
			enemy_uri: [{
				"range": enemy_range,
				"newText": "build_label_2",
			}],
		},
	})


func test_text_edits_are_applied_from_bottom_to_top() -> void:
	var text := "\n".join([
		"func build_label() -> String:",
		"\treturn build_label()",
	])

	assert_str(SmartRenameWorkspaceEdit.apply_text_edits_to_text(text, [
		_edit(0, 5, 0, 16, "build_label_2"),
		_edit(1, 8, 1, 19, "build_label_2"),
	])).is_equal("\n".join([
		"func build_label_2() -> String:",
		"\treturn build_label_2()",
	]))


func test_text_edits_can_update_code_edit_buffer() -> void:
	var code := CodeEdit.new()
	code.text = "\n".join([
		"var first := value",
		"var second := value",
	])

	SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(code, [
		_edit(0, 13, 0, 18, "result"),
		_edit(1, 14, 1, 19, "result"),
	])

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

	SmartRenameWorkspaceEdit.apply_text_edits_to_code_edit(code, [
		_edit(0, 13, 0, 18, "result"),
		_edit(1, 14, 1, 19, "result"),
	], true)
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


func _edit(from_line: int, from_col: int, to_line: int, to_col: int, new_text: String) -> Dictionary:
	return {
		"range": _range(from_line, from_col, to_line, to_col),
		"newText": new_text,
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
