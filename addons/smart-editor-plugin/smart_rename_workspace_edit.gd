extends RefCounted


static func workspace_edit_to_edits_by_uri(workspace_edit: Variant) -> Dictionary:
	var edits_by_uri := {}
	if typeof(workspace_edit) != TYPE_DICTIONARY:
		return edits_by_uri

	if workspace_edit.has("changes") and typeof(workspace_edit["changes"]) == TYPE_DICTIONARY:
		for uri in workspace_edit["changes"]:
			if typeof(workspace_edit["changes"][uri]) == TYPE_ARRAY:
				edits_by_uri[str(uri)] = workspace_edit["changes"][uri]
	elif workspace_edit.has("documentChanges") and typeof(workspace_edit["documentChanges"]) == TYPE_ARRAY:
		for document_change in workspace_edit["documentChanges"]:
			if typeof(document_change) != TYPE_DICTIONARY:
				continue
			if not document_change.has("textDocument") or not document_change.has("edits"):
				continue
			if typeof(document_change["textDocument"]) != TYPE_DICTIONARY or typeof(document_change["edits"]) != TYPE_ARRAY:
				continue

			edits_by_uri[str(document_change["textDocument"].get("uri", ""))] = document_change["edits"]

	return edits_by_uri


static func apply_text_edits_to_text(text: String, edits: Array) -> String:
	for edit in sorted_text_edits_desc(edits):
		if not _is_text_edit(edit):
			continue

		var edit_range: Dictionary = edit["range"]
		var start: Dictionary = edit_range["start"]
		var end: Dictionary = edit_range["end"]
		var from_offset := line_col_to_offset(text, int(start["line"]), int(start["character"]))
		var to_offset := line_col_to_offset(text, int(end["line"]), int(end["character"]))
		if from_offset < 0 or to_offset < from_offset:
			continue

		text = text.substr(0, from_offset) + str(edit["newText"]) + text.substr(to_offset)

	return text


static func apply_text_edits_to_code_edit(code: CodeEdit, edits: Array) -> void:
	for edit in sorted_text_edits_desc(edits):
		if not _is_text_edit(edit):
			continue

		var edit_range: Dictionary = edit["range"]
		var start: Dictionary = edit_range["start"]
		var end: Dictionary = edit_range["end"]
		_replace_range_in_code(
			code,
			int(start["line"]),
			int(start["character"]),
			int(end["line"]),
			int(end["character"]),
			str(edit["newText"])
		)


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


static func sorted_text_edits_desc(edits: Array) -> Array:
	var sorted := edits.duplicate()
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

	if offset + column > text.length():
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


static func _is_text_edit(edit: Variant) -> bool:
	if typeof(edit) != TYPE_DICTIONARY:
		return false
	if not edit.has("range") or not edit.has("newText"):
		return false
	if typeof(edit["range"]) != TYPE_DICTIONARY:
		return false

	var edit_range: Dictionary = edit["range"]
	return (
		typeof(edit_range.get("start", null)) == TYPE_DICTIONARY
		and typeof(edit_range.get("end", null)) == TYPE_DICTIONARY
	)


static func _compare_text_edits_desc(a: Dictionary, b: Dictionary) -> bool:
	var a_start: Dictionary = a["range"]["start"]
	var b_start: Dictionary = b["range"]["start"]
	if a_start["line"] == b_start["line"]:
		return a_start["character"] > b_start["character"]
	return a_start["line"] > b_start["line"]
