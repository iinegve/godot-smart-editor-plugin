extends RefCounted

# Focused text-only GDScript lookups for call hierarchy. This is not a full parser.

const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")

const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


static func selected_or_current_symbol_range(code: CodeEdit) -> CallHierarchyMethod:
	if code.has_selection():
		var selected := code.get_selected_text()
		if is_valid_identifier(selected):
			return CallHierarchyMethod.create(
				selected,
				"",
				code.get_selection_from_line(),
				code.get_selection_from_column()
			)

	return symbol_range_under_caret(code)


static func symbol_range_under_caret(code: CodeEdit) -> CallHierarchyMethod:
	var line := code.get_line(code.get_caret_line())
	if line.is_empty():
		return CallHierarchyMethod.new()

	var probe_col := clampi(code.get_caret_column(), 0, line.length())
	if probe_col == line.length() and probe_col > 0:
		probe_col -= 1
	elif probe_col < line.length() and not is_identifier_char(line[probe_col]) and probe_col > 0:
		probe_col -= 1

	if probe_col < 0 or probe_col >= line.length() or not is_identifier_char(line[probe_col]):
		return CallHierarchyMethod.new()

	var start := probe_col
	while start > 0 and is_identifier_char(line[start - 1]):
		start -= 1

	var end := probe_col + 1
	while end < line.length() and is_identifier_char(line[end]):
		end += 1

	return CallHierarchyMethod.create(line.substr(start, end - start), "", code.get_caret_line(), start)


static func enclosing_function_symbol_range(code: CodeEdit, line_index: int) -> CallHierarchyMethod:
	return enclosing_function_for_lines(_code_lines(code), "", line_index)


static func enclosing_function_for_lines(lines: Array, uri: String, line_index: int) -> CallHierarchyMethod:
	for index in range(mini(line_index, lines.size() - 1), -1, -1):
		var line := str(lines[index])
		var stripped := line.strip_edges()
		if not stripped.begins_with("func "):
			continue

		var name_start := line.find("func ") + 5
		name_start = skip_spaces(line, name_start)
		var name_end := name_start
		while name_end < line.length() and is_identifier_char(line[name_end]):
			name_end += 1
		if name_start == name_end:
			return CallHierarchyMethod.new()

		return CallHierarchyMethod.create(line.substr(name_start, name_end - name_start), uri, index, name_start)

	return CallHierarchyMethod.new()


static func method_symbol_range_for_lines(lines: Array, uri: String, method_name: String) -> CallHierarchyMethod:
	for index in lines.size():
		var line := strip_line_comment(str(lines[index]))
		var func_index := line.find("func ")
		if func_index == -1:
			continue
		if func_index > 0 and is_identifier_char(line[func_index - 1]):
			continue

		var name_start := skip_spaces_and_tabs(line, func_index + 5)
		var name_end := name_start
		while name_end < line.length() and is_identifier_char(line[name_end]):
			name_end += 1
		if name_start == name_end:
			continue
		if line.substr(name_start, name_end - name_start) != method_name:
			continue

		return CallHierarchyMethod.create(method_name, uri, index, name_start)

	return CallHierarchyMethod.new()


static func member_call_receiver_name(lines: Array, symbol_range: CallHierarchyMethod) -> String:
	var line_index := symbol_range.line
	if line_index < 0 or line_index >= lines.size():
		return ""

	var line := strip_line_comment(str(lines[line_index]))
	var symbol_start := symbol_range.character
	if symbol_start <= 0 or symbol_start > line.length():
		return ""

	var dot_col := skip_back_spaces(line, symbol_start - 1)
	if dot_col < 0 or line[dot_col] != ".":
		return ""

	var receiver_end := dot_col
	var receiver_start := receiver_end - 1
	while receiver_start >= 0 and is_identifier_char(line[receiver_start]):
		receiver_start -= 1
	receiver_start += 1
	if receiver_start == receiver_end:
		return ""

	var receiver_name := line.substr(receiver_start, receiver_end - receiver_start)
	if not is_valid_identifier(receiver_name):
		return ""
	return receiver_name


static func identifier_type_for_lines(lines: Array, uri: String, identifier_name: String, line_index: int) -> String:
	if lines.is_empty():
		return ""

	var enclosing_function := enclosing_function_for_lines(lines, uri, line_index)
	if not enclosing_function.is_empty():
		var function_line := enclosing_function.line
		for index in range(mini(line_index, lines.size() - 1), function_line, -1):
			var local_type := variable_type_from_line(str(lines[index]), identifier_name)
			if not local_type.is_empty():
				return local_type

		var parameter_type := function_parameter_type_from_line(str(lines[function_line]), identifier_name)
		if not parameter_type.is_empty():
			return parameter_type

	for index in lines.size():
		var line := str(lines[index])
		if line.begins_with(" ") or line.begins_with("\t"):
			continue

		var member_type := variable_type_from_line(line, identifier_name)
		if not member_type.is_empty():
			return member_type

	return ""


static func variable_type_from_line(line: String, variable_name: String) -> String:
	var code_line := strip_line_comment(line)
	var search_from := 0
	while search_from < code_line.length():
		var var_index := code_line.find("var ", search_from)
		if var_index == -1:
			return ""
		if var_index > 0 and is_identifier_char(code_line[var_index - 1]):
			search_from = var_index + 4
			continue

		var name_start := skip_spaces_and_tabs(code_line, var_index + 4)
		var name_end := name_start
		while name_end < code_line.length() and is_identifier_char(code_line[name_end]):
			name_end += 1
		if name_start == name_end:
			search_from = var_index + 4
			continue
		if code_line.substr(name_start, name_end - name_start) != variable_name:
			search_from = name_end
			continue

		var colon_col := skip_spaces_and_tabs(code_line, name_end)
		if colon_col >= code_line.length() or code_line[colon_col] != ":":
			return ""
		return type_name_after_colon(code_line, colon_col)

	return ""


static func function_parameter_type_from_line(line: String, parameter_name: String) -> String:
	var code_line := strip_line_comment(line)
	var open_paren := code_line.find("(")
	if open_paren == -1:
		return ""

	var close_paren := code_line.find(")", open_paren + 1)
	if close_paren == -1:
		return ""

	var parameters := code_line.substr(open_paren + 1, close_paren - open_paren - 1).split(",")
	for parameter in parameters:
		var parameter_text := str(parameter).strip_edges()
		var name_start := 0
		var name_end := name_start
		while name_end < parameter_text.length() and is_identifier_char(parameter_text[name_end]):
			name_end += 1
		if name_start == name_end:
			continue
		if parameter_text.substr(name_start, name_end - name_start) != parameter_name:
			continue

		var colon_col := skip_spaces_and_tabs(parameter_text, name_end)
		if colon_col >= parameter_text.length() or parameter_text[colon_col] != ":":
			return ""
		return type_name_after_colon(parameter_text, colon_col)

	return ""


static func type_name_after_colon(line: String, colon_col: int) -> String:
	var type_start := skip_spaces_and_tabs(line, colon_col + 1)
	var type_end := type_start
	while type_end < line.length() and (is_identifier_char(line[type_end]) or line[type_end] == "."):
		type_end += 1
	if type_start == type_end:
		return ""

	var type_name := line.substr(type_start, type_end - type_start)
	var dot_col := type_name.rfind(".")
	if dot_col != -1:
		type_name = type_name.substr(dot_col + 1)
	return type_name


static func constructor_call_columns(line: String, target_class_name: String) -> Array[int]:
	var columns: Array[int] = []
	if target_class_name.is_empty():
		return columns

	var code_line := strip_line_comment(line)
	var needle := target_class_name + ".new"
	var search_from := 0
	while search_from < code_line.length():
		var index := code_line.find(needle, search_from)
		if index == -1:
			break

		var end_index := index + needle.length()
		if constructor_call_has_boundaries(code_line, index, end_index):
			columns.append(index)

		search_from = end_index

	return columns


static func constructor_call_has_boundaries(line: String, start: int, end_index: int) -> bool:
	if start > 0 and is_identifier_char(line[start - 1]):
		return false
	if end_index < line.length() and is_identifier_char(line[end_index]):
		return false

	var after_new := skip_spaces(line, end_index)
	return after_new < line.length() and line[after_new] == "("


static func init_line_for_lines(lines: Array) -> int:
	for index in lines.size():
		var line := str(lines[index])
		var stripped := line.strip_edges()
		if stripped.begins_with("func _init"):
			return index
	return -1


static func strip_line_comment(line: String) -> String:
	var in_string := false
	var string_quote := ""
	var escaped := false

	for index in line.length():
		var character := line[index]
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == string_quote:
				in_string = false
			continue

		if character == "\"" or character == "'":
			in_string = true
			string_quote = character
		elif character == "#":
			return line.substr(0, index)

	return line


static func skip_spaces(line: String, col: int) -> int:
	while col < line.length() and line[col] == " ":
		col += 1
	return col


static func skip_spaces_and_tabs(line: String, col: int) -> int:
	while col < line.length() and (line[col] == " " or line[col] == "\t"):
		col += 1
	return col


static func skip_back_spaces(line: String, col: int) -> int:
	while col >= 0 and (line[col] == " " or line[col] == "\t"):
		col -= 1
	return col


static func is_valid_identifier(value: String) -> bool:
	if value.is_empty():
		return false

	var first := value[0]
	if not is_identifier_start_char(first):
		return false

	for col in range(1, value.length()):
		if not is_identifier_char(value[col]):
			return false

	return true


static func is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


static func is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)


static func _code_lines(code: CodeEdit) -> Array:
	var lines := []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return lines
