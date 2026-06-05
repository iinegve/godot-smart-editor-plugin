@tool
extends RefCounted

const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")

var _identifier_validator := GDScriptIdentifierValidator.new()


func suggest_name(expression: String) -> String:
	var cleaned := expression.strip_edges()

	if cleaned.ends_with("()"):
		cleaned = cleaned.substr(0, cleaned.length() - 2)

	var dot_index := cleaned.rfind(".")
	if dot_index != -1 and dot_index < cleaned.length() - 1:
		cleaned = cleaned.substr(dot_index + 1)

	var result := ""
	var previous_was_separator := false

	for col in cleaned.length():
		var ch := cleaned[col]
		if _identifier_validator.is_identifier_char(ch):
			result += ch.to_lower()
			previous_was_separator = false
		elif not previous_was_separator and not result.is_empty():
			result += "_"
			previous_was_separator = true

	result = result.trim_suffix("_")
	if _identifier_validator.is_valid_identifier(result):
		return result

	return "value"


func build_edit_plan(line: String, selection_range: Dictionary, expression: String, variable_name: String) -> Dictionary:
	var line_index := int(selection_range["from_line"])
	var from_col := int(selection_range["from_col"])
	var to_col := int(selection_range["to_col"])
	var indent := line.substr(0, _line_indent_chars(line))
	var declaration := "%svar %s = %s" % [indent, variable_name, expression]
	var replaced_line := line.substr(0, from_col) + variable_name + line.substr(to_col)

	return {
		"line_index": line_index,
		"declaration": declaration,
		"replaced_line": replaced_line,
		"selection_from_col": from_col,
		"selection_to_col": from_col + variable_name.length(),
	}


func _line_indent_chars(line: String) -> int:
	var count := 0
	for col in line.length():
		var ch := line[col]
		if ch == " " or ch == "\t":
			count += 1
		else:
			break
	return count
