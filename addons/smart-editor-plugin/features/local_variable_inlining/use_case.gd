@tool
extends RefCounted

const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")

var _identifier_validator := GDScriptIdentifierValidator.new()


func build_inline_plan(
	code_text: String,
	uri: String,
	symbol: String,
	_symbol_line: int,
	_symbol_column: int,
	references: Variant
) -> Dictionary:
	if typeof(references) != TYPE_ARRAY:
		return {
			"error": "could not read references.",
		}

	var reference_array: Array = references
	var lines := code_text.split("\n", true)
	var declaration := find_declaration_from_references(lines, uri, symbol, reference_array)
	if declaration.is_empty():
		return {
			"error": "could not find a single-line local var declaration for '%s'." % symbol,
		}

	var declaration_line := int(declaration["line"])
	var declaration_column := int(declaration["column"])
	var expression := str(declaration["expression"])

	if references_include_reassignment(lines, uri, symbol, declaration_line, declaration_column, reference_array):
		return {
			"error": "refusing to inline '%s' because it appears to be assigned again." % symbol,
		}

	var edits := references_to_replacement_edits(
		lines,
		uri,
		symbol,
		declaration_line,
		declaration_column,
		expression,
		reference_array
	)
	if edits.is_empty():
		return {
			"error": "no replaceable references found.",
		}

	edits.sort_custom(compare_reference_edits_desc)
	return {
		"edits": edits,
		"declaration_line": declaration_line,
	}


func parse_declaration_expression(line: String, symbol: String, symbol_column: int) -> String:
	var stripped_start := _line_indent_chars(line)
	if not line.substr(stripped_start).begins_with("var "):
		return ""

	var declaration_name_start := _skip_spaces(line, stripped_start + 4)
	var declaration_name_end := declaration_name_start
	while declaration_name_end < line.length() and _identifier_validator.is_identifier_char(line[declaration_name_end]):
		declaration_name_end += 1

	if declaration_name_start != symbol_column:
		return ""
	if line.substr(declaration_name_start, declaration_name_end - declaration_name_start) != symbol:
		return ""

	var equals_col := line.find("=")
	if equals_col == -1 or equals_col < symbol_column + symbol.length():
		return ""

	if equals_col > 0 and line[equals_col - 1] == "=":
		return ""
	if equals_col < line.length() - 1 and line[equals_col + 1] == "=":
		return ""

	return line.substr(equals_col + 1).strip_edges()


func find_declaration_from_references(lines: PackedStringArray, uri: String, symbol: String, references: Array) -> Dictionary:
	var declaration: Dictionary = {}
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY:
			continue

		var candidate := declaration_from_reference(lines, uri, symbol, reference)
		if candidate.is_empty():
			continue
		if not declaration.is_empty() and not _same_declaration(declaration, candidate):
			return {}

		declaration = candidate

	return declaration


func declaration_from_reference(lines: PackedStringArray, uri: String, symbol: String, reference: Dictionary) -> Dictionary:
	if reference.get("uri", "") != uri:
		return {}
	if not reference.has("range") or typeof(reference["range"]) != TYPE_DICTIONARY:
		return {}

	var range: Dictionary = reference["range"]
	if not range.has("start") or typeof(range["start"]) != TYPE_DICTIONARY:
		return {}

	var start: Dictionary = range["start"]
	var line_index := int(start.get("line", -1))
	var column := int(start.get("character", -1))
	if line_index < 0 or line_index >= lines.size():
		return {}

	var expression := parse_declaration_expression(lines[line_index], symbol, column)
	if expression.is_empty():
		return {}

	return {
		"line": line_index,
		"column": column,
		"expression": expression,
	}


func references_include_reassignment(
	lines: PackedStringArray,
	uri: String,
	symbol: String,
	declaration_line: int,
	declaration_column: int,
	references: Array
) -> bool:
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY:
			continue
		if reference.get("uri", "") != uri:
			continue

		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var line_index := int(start["line"])
		var from_col := int(start["character"])
		if line_index == declaration_line and from_col == declaration_column:
			continue
		if line_index < 0 or line_index >= lines.size():
			continue

		var line := str(lines[line_index])
		var after := _skip_spaces(line, from_col + symbol.length())
		if _is_assignment_operator_at(line, after):
			return true

	return false


func references_to_replacement_edits(
	lines: PackedStringArray,
	uri: String,
	symbol: String,
	declaration_line: int,
	declaration_column: int,
	expression: String,
	references: Array
) -> Array[Dictionary]:
	var edits: Array[Dictionary] = []
	for reference in references:
		if typeof(reference) != TYPE_DICTIONARY:
			continue
		if reference.get("uri", "") != uri:
			continue

		var range: Dictionary = reference["range"]
		var start: Dictionary = range["start"]
		var end: Dictionary = range["end"]
		var line := int(start["line"])
		var from_col := int(start["character"])
		var to_col := int(end["character"])

		if line == declaration_line and from_col == declaration_column:
			continue
		if _is_member_access_at(lines, line, from_col):
			continue

		edits.append({
			"line": line,
			"from_col": from_col,
			"to_col": to_col,
			"replacement": expression,
		})

	return edits


func compare_reference_edits_desc(a: Dictionary, b: Dictionary) -> bool:
	if a["line"] == b["line"]:
		return a["from_col"] > b["from_col"]
	return a["line"] > b["line"]


func _same_declaration(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("line", -1)) == int(b.get("line", -2))
		and int(a.get("column", -1)) == int(b.get("column", -2))
	)


func _line_indent_chars(line: String) -> int:
	var count := 0
	for col in line.length():
		var ch := line[col]
		if ch == " " or ch == "\t":
			count += 1
		else:
			break
	return count


func _skip_spaces(line: String, col: int) -> int:
	while col < line.length() and line[col] == " ":
		col += 1
	return col


func _is_assignment_operator_at(line: String, col: int) -> bool:
	if col >= line.length():
		return false

	if line[col] == "=":
		if col > 0 and "=<>!".contains(line[col - 1]):
			return false
		return col + 1 >= line.length() or line[col + 1] != "="
	if col < line.length() - 1 and line[col] == ":" and line[col + 1] == "=":
		return true
	if col < line.length() - 1 and "+-*/%&|^".contains(line[col]) and line[col + 1] == "=":
		return true

	return false


func _is_member_access_at(lines: PackedStringArray, line_index: int, column: int) -> bool:
	if line_index < 0 or line_index >= lines.size():
		return false

	var line := str(lines[line_index])
	var previous := column - 1
	while previous >= 0 and line[previous] == " ":
		previous -= 1

	return previous >= 0 and line[previous] == "."
