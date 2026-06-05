@tool
extends RefCounted

const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
const LANGUAGE_SYMBOLS := {
	"and": true,
	"as": true,
	"assert": true,
	"await": true,
	"break": true,
	"breakpoint": true,
	"class": true,
	"class_name": true,
	"const": true,
	"continue": true,
	"elif": true,
	"else": true,
	"enum": true,
	"export": true,
	"export_category": true,
	"export_color_no_alpha": true,
	"export_custom": true,
	"export_dir": true,
	"export_enum": true,
	"export_exp_easing": true,
	"export_file": true,
	"export_flags": true,
	"export_flags_2d_navigation": true,
	"export_flags_2d_physics": true,
	"export_flags_2d_render": true,
	"export_flags_3d_navigation": true,
	"export_flags_3d_physics": true,
	"export_flags_3d_render": true,
	"export_flags_avoidance": true,
	"export_global_dir": true,
	"export_global_file": true,
	"export_group": true,
	"export_multiline": true,
	"export_node_path": true,
	"export_placeholder": true,
	"export_range": true,
	"export_storage": true,
	"export_subgroup": true,
	"extends": true,
	"false": true,
	"for": true,
	"func": true,
	"icon": true,
	"if": true,
	"in": true,
	"is": true,
	"match": true,
	"not": true,
	"null": true,
	"onready": true,
	"or": true,
	"pass": true,
	"return": true,
	"rpc": true,
	"self": true,
	"signal": true,
	"static": true,
	"static_unload": true,
	"super": true,
	"tool": true,
	"true": true,
	"var": true,
	"void": true,
	"warning_ignore": true,
	"warning_ignore_restore": true,
	"warning_ignore_start": true,
	"while": true,
	"AABB": true,
	"Array": true,
	"Basis": true,
	"Callable": true,
	"Color": true,
	"Dictionary": true,
	"NodePath": true,
	"Object": true,
	"PackedByteArray": true,
	"PackedColorArray": true,
	"PackedFloat32Array": true,
	"PackedFloat64Array": true,
	"PackedInt32Array": true,
	"PackedInt64Array": true,
	"PackedStringArray": true,
	"PackedVector2Array": true,
	"PackedVector3Array": true,
	"PackedVector4Array": true,
	"Plane": true,
	"Projection": true,
	"Quaternion": true,
	"RID": true,
	"Rect2": true,
	"Rect2i": true,
	"Signal": true,
	"String": true,
	"StringName": true,
	"Transform2D": true,
	"Transform3D": true,
	"Variant": true,
	"Vector2": true,
	"Vector2i": true,
	"Vector3": true,
	"Vector3i": true,
	"Vector4": true,
	"Vector4i": true,
	"bool": true,
	"float": true,
	"int": true,
}


static func symbol_range_in_line(line: String, line_index: int, caret_column: int) -> Dictionary:
	var symbol_range := _identifier_range_at_or_before_column(line, line_index, caret_column)
	if symbol_range.is_empty() or is_language_symbol(symbol_range["symbol"]):
		return {}

	return symbol_range


static func is_member_call_symbol(line: String, symbol_column: int, end_column: int) -> bool:
	if symbol_column <= 0 or symbol_column > line.length():
		return false
	if line[symbol_column - 1] != ".":
		return false

	var probe_column := clampi(end_column, 0, line.length())
	while probe_column < line.length() and line[probe_column] == " ":
		probe_column += 1

	return probe_column < line.length() and line[probe_column] == "("


static func references_for_uri(references: Variant, uri: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(references) != TYPE_ARRAY:
		return result

	for reference in references:
		var normalized := _normalize_reference(reference, uri)
		if normalized.is_empty():
			continue
		_insert_sorted(result, normalized)

	return result


static func identifier_references_for_uri(references: Variant, uri: String, text: String, symbol: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reference in references_for_uri(references, uri):
		if is_identifier_reference_in_text(text, reference, symbol):
			result.append(reference)

	return result


static func is_identifier_reference_in_text(text: String, reference: Dictionary, symbol: String) -> bool:
	if symbol.is_empty() or is_language_symbol(symbol):
		return false
	if int(reference.get("line", -1)) != int(reference.get("end_line", -2)):
		return false

	var line_index := int(reference.get("line", -1))
	var column := int(reference.get("column", -1))
	var end_column := int(reference.get("end_column", -1))
	var lines := text.split("\n", true)
	if line_index < 0 or line_index >= lines.size():
		return false

	var line := lines[line_index]
	if column < 0 or end_column > line.length() or column >= end_column:
		return false
	if line.substr(column, end_column - column) != symbol:
		return false

	var symbol_range := _identifier_range_at_code_column(line, line_index, column)
	return (
		not symbol_range.is_empty()
		and symbol_range["symbol"] == symbol
		and int(symbol_range["column"]) == column
		and int(symbol_range["end_column"]) == end_column
	)


static func references_for_symbol_in_text(text: String, symbol: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if symbol.is_empty() or not _is_identifier_start_char(symbol[0]) or is_language_symbol(symbol):
		return result

	var lines := text.split("\n", true)
	var multiline_quote := ""
	for line_index in lines.size():
		multiline_quote = _append_symbol_references_in_line(
			result,
			lines[line_index],
			line_index,
			symbol,
			multiline_quote
		)

	return result


static func reference_y(line: int, line_count: int, stripe_height: float) -> float:
	if line_count <= 1 or stripe_height <= 0.0:
		return 0.0

	var max_line := line_count - 1
	var clamped_line := clampi(line, 0, max_line)
	return float(clamped_line) / float(max_line) * stripe_height


static func closest_reference_for_y(references: Array, line_count: int, stripe_height: float, y: float) -> Dictionary:
	if references.is_empty():
		return {}

	var closest: Dictionary = references[0]
	var closest_distance := absf(reference_y(int(closest["line"]), line_count, stripe_height) - y)
	for index in range(1, references.size()):
		var reference: Dictionary = references[index]
		var distance := absf(reference_y(int(reference["line"]), line_count, stripe_height) - y)
		if distance < closest_distance:
			closest = reference
			closest_distance = distance

	return closest


static func same_position(a: Dictionary, b: Dictionary) -> bool:
	return (
		not a.is_empty()
		and not b.is_empty()
		and int(a.get("line", -1)) == int(b.get("line", -2))
		and int(a.get("column", -1)) == int(b.get("column", -2))
	)


static func _normalize_reference(reference: Variant, uri: String) -> Dictionary:
	if typeof(reference) != TYPE_DICTIONARY:
		return {}
	if reference.get("uri", "") != uri:
		return {}
	if not reference.has("range") or typeof(reference["range"]) != TYPE_DICTIONARY:
		return {}

	var reference_range: Dictionary = reference["range"]
	if (
		not reference_range.has("start")
		or not reference_range.has("end")
		or typeof(reference_range["start"]) != TYPE_DICTIONARY
		or typeof(reference_range["end"]) != TYPE_DICTIONARY
	):
		return {}

	var start: Dictionary = reference_range["start"]
	var end: Dictionary = reference_range["end"]
	return {
		"line": int(start.get("line", 0)),
		"column": int(start.get("character", 0)),
		"end_line": int(end.get("line", start.get("line", 0))),
		"end_column": int(end.get("character", start.get("character", 0))),
	}


static func _append_symbol_references_in_line(
	result: Array[Dictionary],
	line: String,
	line_index: int,
	symbol: String,
	multiline_quote: String
) -> String:
	var index := 0
	if not multiline_quote.is_empty():
		var close_quote := line.find(multiline_quote)
		if close_quote == -1:
			return multiline_quote

		index = close_quote + multiline_quote.length()
		multiline_quote = ""

	while index < line.length():
		var triple_quote := _triple_quote_at(line, index)
		if not triple_quote.is_empty():
			var close_triple_quote := line.find(triple_quote, index + triple_quote.length())
			if close_triple_quote == -1:
				return triple_quote

			index = close_triple_quote + triple_quote.length()
			continue

		var ch := line[index]
		if ch == "#":
			break
		if ch == "\"" or ch == "'":
			index = _skip_quoted_string(line, index, ch)
			continue
		if _is_identifier_start_char(ch):
			var start := index
			index += 1
			while index < line.length() and _is_identifier_char(line[index]):
				index += 1

			if line.substr(start, index - start) == symbol:
				result.append({
					"line": line_index,
					"column": start,
					"end_line": line_index,
					"end_column": index,
				})
			continue

		index += 1

	return ""


static func _identifier_range_at_or_before_column(line: String, line_index: int, caret_column: int) -> Dictionary:
	if line.is_empty():
		return {}

	var probe_col := clampi(caret_column, 0, line.length())
	if probe_col == line.length() and probe_col > 0:
		probe_col -= 1
	elif probe_col < line.length() and not _is_identifier_char(line[probe_col]):
		if probe_col == 0 or not _is_identifier_char(line[probe_col - 1]):
			return {}
		probe_col -= 1

	if probe_col < 0 or probe_col >= line.length() or not _is_identifier_char(line[probe_col]):
		return {}

	return _identifier_range_at_code_column(line, line_index, probe_col)


static func _identifier_range_at_code_column(line: String, line_index: int, column: int) -> Dictionary:
	var index := 0
	while index < line.length():
		var triple_quote := _triple_quote_at(line, index)
		if not triple_quote.is_empty():
			var close_triple_quote := line.find(triple_quote, index + triple_quote.length())
			if close_triple_quote == -1:
				return {}

			var string_end := close_triple_quote + triple_quote.length()
			if column >= index and column < string_end:
				return {}

			index = string_end
			continue

		var ch := line[index]
		if ch == "#":
			return {}
		if ch == "\"" or ch == "'":
			var string_end := _skip_quoted_string(line, index, ch)
			if column >= index and column < string_end:
				return {}

			index = string_end
			continue
		if _is_identifier_start_char(ch):
			var start := index
			index += 1
			while index < line.length() and _is_identifier_char(line[index]):
				index += 1

			if column >= start and column < index:
				return {
					"symbol": line.substr(start, index - start),
					"line": line_index,
					"column": start,
					"end_column": index,
				}
			continue

		index += 1

	return {}


static func _triple_quote_at(line: String, index: int) -> String:
	if index + 3 > line.length():
		return ""
	var value := line.substr(index, 3)
	if value == "\"\"\"" or value == "'''":
		return value

	return ""


static func _skip_quoted_string(line: String, index: int, quote: String) -> int:
	index += 1
	while index < line.length():
		var ch := line[index]
		if ch == "\\":
			index += 2
			continue
		if ch == quote:
			return index + 1
		index += 1

	return line.length()


static func _insert_sorted(references: Array[Dictionary], reference: Dictionary) -> void:
	for index in references.size():
		if _compare_references(reference, references[index]) < 0:
			references.insert(index, reference)
			return

	references.append(reference)


static func _compare_references(a: Dictionary, b: Dictionary) -> int:
	var line_a := int(a["line"])
	var line_b := int(b["line"])
	if line_a != line_b:
		return line_a - line_b

	return int(a["column"]) - int(b["column"])


static func _is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


static func _is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)


static func is_language_symbol(symbol: String) -> bool:
	return LANGUAGE_SYMBOLS.has(symbol)
