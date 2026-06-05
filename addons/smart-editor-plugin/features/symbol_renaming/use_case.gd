@tool
extends RefCounted

const SmartRenameWorkspaceEdit := preload("res://addons/smart-editor-plugin/common/smart_rename_workspace_edit.gd")
const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")

var _identifier_validator := GDScriptIdentifierValidator.new()


func workspace_edit_to_edits_by_uri(workspace_edit: Variant) -> Dictionary:
	return SmartRenameWorkspaceEdit.workspace_edit_to_edits_by_uri(workspace_edit)


func references_to_workspace_edit(references: Variant, new_name: String) -> Dictionary:
	return SmartRenameWorkspaceEdit.references_to_workspace_edit(references, new_name)


func non_empty_edit_file_count(edits_by_uri: Dictionary) -> int:
	var count := 0
	for uri in edits_by_uri:
		if edits_by_uri[uri] is Array and not edits_by_uri[uri].is_empty():
			count += 1

	return count


func should_use_native_rename_undo(edits_by_uri: Dictionary, open_script_buffers: Dictionary, uri: String) -> bool:
	if edits_by_uri.size() != 1:
		return false
	if not open_script_buffers.has(uri):
		return false

	var edit_uris: Array = edits_by_uri.keys()
	return str(edit_uris[0]) == uri


func compare_open_apply_items(a: Dictionary, b: Dictionary) -> bool:
	var a_score := int(a.get("definition_score", 0))
	var b_score := int(b.get("definition_score", 0))
	if a_score != b_score:
		return a_score > b_score

	var a_edits := int(a.get("edits", 0))
	var b_edits := int(b.get("edits", 0))
	if a_edits != b_edits:
		return a_edits > b_edits

	return str(a.get("uri", "")) < str(b.get("uri", ""))


func definition_score_for_text(text: String, edits: Array, symbol: String) -> int:
	if symbol.is_empty():
		return 0

	var lines := text.split("\n", true)
	var score := 0
	var seen_lines := {}
	for edit in edits:
		if typeof(edit) != TYPE_DICTIONARY:
			continue

		var edit_dict: Dictionary = edit
		var range_value: Variant = edit_dict.get("range", null)
		if typeof(range_value) != TYPE_DICTIONARY:
			continue

		var range_dict: Dictionary = range_value
		var start_value: Variant = range_dict.get("start", null)
		if typeof(start_value) != TYPE_DICTIONARY:
			continue

		var start_dict: Dictionary = start_value
		var line_index := int(start_dict.get("line", -1))
		if line_index < 0 or line_index >= lines.size() or seen_lines.has(line_index):
			continue

		seen_lines[line_index] = true
		var line_score := declaration_line_score(lines[line_index], symbol)
		if line_score > score:
			score = line_score

	return score


func apply_text_edits_to_text(text: String, edits: Array) -> String:
	return SmartRenameWorkspaceEdit.apply_text_edits_to_text(text, edits)


func line_col_to_offset(text: String, line: int, column: int) -> int:
	return SmartRenameWorkspaceEdit.line_col_to_offset(text, line, column)


func compare_text_edits_desc(a: Dictionary, b: Dictionary) -> bool:
	return SmartRenameWorkspaceEdit._compare_text_edits_desc(a, b)


func declaration_line_score(line: String, symbol: String) -> int:
	var trimmed := line.strip_edges()
	if line_starts_with_symbol_declaration(trimmed, "const ", symbol):
		return 100
	if line_starts_with_symbol_declaration(trimmed, "static func ", symbol):
		return 100
	if line_starts_with_symbol_declaration(trimmed, "func ", symbol):
		return 100
	if line_starts_with_symbol_declaration(trimmed, "var ", symbol):
		return 90
	if line_starts_with_symbol_declaration(trimmed, "signal ", symbol):
		return 90
	if line_starts_with_symbol_declaration(trimmed, "class_name ", symbol):
		return 90
	if line_contains_symbol_declaration(trimmed, " var ", symbol):
		return 85
	if line_contains_symbol_declaration(trimmed, " func ", symbol):
		return 80

	return 0


func line_starts_with_symbol_declaration(line: String, prefix: String, symbol: String) -> bool:
	var candidate := prefix + symbol
	if not line.begins_with(candidate):
		return false
	return symbol_has_boundary_after(line, candidate.length())


func line_contains_symbol_declaration(line: String, marker: String, symbol: String) -> bool:
	var candidate := marker + symbol
	var index := line.find(candidate)
	if index == -1:
		return false
	return symbol_has_boundary_after(line, index + candidate.length())


func symbol_has_boundary_after(line: String, column: int) -> bool:
	if column >= line.length():
		return true
	return not _identifier_validator.is_identifier_char(line[column])
