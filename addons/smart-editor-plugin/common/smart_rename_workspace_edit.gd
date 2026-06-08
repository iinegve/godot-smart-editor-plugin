extends RefCounted

const RenameTextEdit := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_text_edit.gd")


static func apply_text_edits_to_text(text: String, edits: Array[RenameTextEdit]) -> String:
	for edit in sorted_text_edits_desc(edits):
		if edit == null or not edit.is_valid():
			continue

		var from_offset := line_col_to_offset(text, edit.start_line, edit.start_column)
		var to_offset := line_col_to_offset(text, edit.end_line, edit.end_column)
		if from_offset < 0 or to_offset < from_offset:
			continue

		text = text.substr(0, from_offset) + edit.new_text + text.substr(to_offset)

	return text


static func apply_text_edits_to_code_edit(code: CodeEdit, edits: Array[RenameTextEdit]) -> void:
	code.begin_complex_operation()

	for edit in sorted_text_edits_desc(edits):
		if edit == null or not edit.is_valid():
			continue

		_replace_range_in_code(
			code,
			edit.start_line,
			edit.start_column,
			edit.end_line,
			edit.end_column,
			edit.new_text
		)

	code.end_complex_operation()


static func sync_script_from_code_edit(script: Script, code: CodeEdit) -> void:
	if script == null or code == null:
		return

	sync_script_from_text(script, code.get_text())


static func sync_script_from_text(script: Script, text: String) -> void:
	if script == null:
		return

	script.set_source_code(text)
	if script.has_method("reload"):
		script.call("reload", true)
	if script.has_method("update_exports"):
		script.call("update_exports")


static func save_code_edit_to_script_path(script: Script, code: CodeEdit) -> bool:
	if script == null or code == null:
		return false

	var script_path := str(script.resource_path)
	if script_path.is_empty() or script_path.contains("::"):
		return false

	var global_path := ProjectSettings.globalize_path(script_path)
	if not write_text_to_file(global_path, code.get_text()):
		return false

	if code.has_method("tag_saved_version"):
		code.call("tag_saved_version")
	return true


static func write_text_to_file(path: String, text: String) -> bool:
	var target_file := FileAccess.open(path, FileAccess.WRITE)
	if target_file == null:
		return false

	target_file.store_string(text)
	target_file = null
	return true


static func sorted_text_edits_desc(edits: Array[RenameTextEdit]) -> Array[RenameTextEdit]:
	var sorted: Array[RenameTextEdit] = []
	sorted.assign(edits)
	sorted.sort_custom(_compare_text_edits_desc)
	return sorted


static func line_col_to_offset(text: String, line: int, column: int) -> int:
	if line < 0 or column < 0:
		return -1

	var offset := 0
	for _line_index in line:
		var next_newline := text.find("\n", offset)
		if next_newline == -1:
			return -1
		offset = next_newline + 1

	var line_end := text.find("\n", offset)
	if line_end == -1:
		line_end = text.length()

	if column > line_end - offset:
		return -1

	return offset + column


static func _replace_range_in_code(code: CodeEdit, from_line: int, from_col: int, to_line: int, to_col: int, new_text: String) -> void:
	if from_line < 0 or to_line < from_line:
		return
	if from_line >= code.get_line_count() or to_line >= code.get_line_count():
		return

	if from_line == to_line:
		var line := code.get_line(from_line)
		code.set_line(from_line, line.substr(0, from_col) + new_text + line.substr(to_col))
		return

	var first_line := code.get_line(from_line)
	var last_line := code.get_line(to_line)
	var replacement_lines := new_text.split("\n")

	code.set_line(from_line, first_line.substr(0, from_col) + replacement_lines[0])
	for index in range(1, replacement_lines.size()):
		code.insert_line_at(from_line + index, replacement_lines[index])

	var final_line := from_line + replacement_lines.size() - 1
	code.set_line(final_line, code.get_line(final_line) + last_line.substr(to_col))
	for line_index in range(to_line + replacement_lines.size() - 1, final_line, -1):
		code.remove_line_at(line_index)


static func _compare_text_edits_desc(a: RenameTextEdit, b: RenameTextEdit) -> bool:
	if a.start_line == b.start_line:
		return a.start_column > b.start_column
	return a.start_line > b.start_line
