@tool
extends RefCounted

const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


static func tokenize_line(line: String, line_index: int, from_col: int, to_col: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var col := from_col

	while col < to_col:
		var ch := line[col]
		if ch == " " or ch == "\t":
			col += 1
			continue

		if _is_identifier_start_char(ch):
			var start := col
			col += 1
			while col < to_col and _is_identifier_char(line[col]):
				col += 1
			var text := line.substr(start, col - start)
			result.append(_make_token("identifier", text, line_index, start, col))
			continue

		if ch >= "0" and ch <= "9":
			var start := col
			col += 1
			while col < to_col and (_is_identifier_char(line[col]) or line[col] == "."):
				col += 1
			result.append(_make_token("literal", line.substr(start, col - start), line_index, start, col))
			continue

		if ch == "\"" or ch == "'":
			result.append(_scan_string_token(line, line_index, col, to_col))
			col = int(result.back()["to_col"])
			continue

		var two := ""
		if col < to_col - 1:
			two = line.substr(col, 2)
		if ["==", "!=", "<=", ">=", "&&", "||", "<<", ">>", "**", ":=", "+=", "-=", "*=", "/=", "%="].has(two):
			result.append(_make_token("operator", two, line_index, col, col + 2))
			col += 2
			continue

		if "$+-*/%<>&|^=.!?:,()[]{}".contains(ch):
			var type := "operator"
			if "()[]{}.,:".contains(ch):
				type = "punctuation"
			result.append(_make_token(type, ch, line_index, col, col + 1))
		col += 1

	return result


static func _scan_string_token(line: String, line_index: int, start_col: int, to_col: int) -> Dictionary:
	var quote := line[start_col]
	var col := start_col + 1
	var escaped := false

	while col < to_col:
		var ch := line[col]
		if escaped:
			escaped = false
		elif ch == "\\":
			escaped = true
		elif ch == quote:
			col += 1
			break
		col += 1

	return _make_token("string", line.substr(start_col, col - start_col), line_index, start_col, col)


static func _make_token(type: String, text: String, line: int, from_col: int, to_col: int) -> Dictionary:
	return {
		"type": type,
		"text": text,
		"line": line,
		"from_col": from_col,
		"to_col": to_col,
	}


static func _is_identifier_start_char(ch: String) -> bool:
	if ch == "_":
		return true
	if ch.is_empty():
		return false
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")


static func _is_identifier_char(ch: String) -> bool:
	return not ch.is_empty() and IDENTIFIER_CHARS.contains(ch)
