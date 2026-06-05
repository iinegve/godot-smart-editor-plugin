@tool
extends RefCounted

const GDScriptSelectionParser := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/gdscript_selection_parser.gd")
const SmartSelectionHistory := preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/smart_selection_history.gd")
const SmartSelectionRange := preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")

var _history := SmartSelectionHistory.new()


func next_expand_range(code_text: String, current: Dictionary) -> Dictionary:
	var candidates := _build_expansion_candidates(code_text, current)

	for candidate in candidates:
		if (
			SmartSelectionRange.strictly_contains(candidate, current)
			or _candidate_starts_after_indent_caret(code_text, candidate, current)
		):
			_history.record(current)
			return candidate

	var file_range := _get_full_file_range(code_text)
	if not SmartSelectionRange.equal(current, file_range):
		_history.record(current)
		return file_range

	return {}


func next_shrink_range(code_text: String, current: Dictionary) -> Dictionary:
	return _history.shrink_target(current, _build_expansion_candidates(code_text, current))


func _build_expansion_candidates(code_text: String, current: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var parser := GDScriptSelectionParser.new()
	for candidate in parser.build_candidates(code_text, current):
		_append_candidate(candidates, candidate)

	return candidates


func _append_candidate(candidates: Array[Dictionary], candidate: Dictionary) -> void:
	if candidate.is_empty():
		return

	for existing in candidates:
		if SmartSelectionRange.equal(existing, candidate):
			return

	candidates.append(candidate)


func _get_full_file_range(code_text: String) -> Dictionary:
	var lines := code_text.split("\n", true)
	var last_line: int = maxi(0, lines.size() - 1)
	var last_line_text := "" if lines.is_empty() else str(lines[last_line])
	return SmartSelectionRange.make_range(0, 0, last_line, last_line_text.length())


func _candidate_starts_after_indent_caret(code_text: String, candidate: Dictionary, current: Dictionary) -> bool:
	if current["from_line"] != current["to_line"] or current["from_col"] != current["to_col"]:
		return false
	if candidate["from_line"] != current["from_line"]:
		return false
	if candidate["from_col"] <= current["from_col"]:
		return false
	if candidate["to_line"] != current["from_line"]:
		return false

	var lines := code_text.split("\n", true)
	var line_index := int(current["from_line"])
	if line_index < 0 or line_index >= lines.size():
		return false

	var line := str(lines[line_index])
	var current_col := int(current["from_col"])
	var candidate_col := int(candidate["from_col"])
	if candidate_col > line.length():
		return false

	for col in range(current_col, candidate_col):
		if line[col] != " " and line[col] != "\t":
			return false
	return true
