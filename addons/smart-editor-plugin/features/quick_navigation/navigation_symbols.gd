@tool
extends RefCounted

# Text-only declarations from the live GDScript buffer. No compilation or LSP
# round trip is needed, and locals, lambdas, comments and strings are excluded.
enum Category { FUNCTIONS, FIELDS }


static func collect(source: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var lines := _mask_strings_and_comments(source).split("\n")
	var original_lines := source.split("\n")
	var scopes: Array[Dictionary] = [{"indent": -1, "kind": "class", "name": ""}]
	var declaration := RegEx.new()
	declaration.compile("^(?:static\\s+)?(func|var|const|class)\\s+([\\p{L}_][\\p{L}\\p{N}_]*)")
	var statement := ""
	var start_line := 0
	var depth := 0
	for line_index in lines.size():
		var line: String = lines[line_index]
		if statement.is_empty():
			if line.strip_edges().is_empty():
				continue
			start_line = line_index
		else:
			statement += "\n"
		statement += line
		for character in line:
			if "([{".contains(character):
				depth += 1
			elif ")]}".contains(character):
				depth = maxi(0, depth - 1)
		if depth > 0 or line.strip_edges().ends_with("\\"):
			continue

		var indent := _indent_width(lines[start_line])
		while scopes.size() > 1 and indent <= int(scopes.back()["indent"]):
			scopes.pop_back()
		var content_start := _skip_annotations(statement)
		var content := statement.substr(content_start)
		var found := declaration.search(content)
		var scope_kind := "block"
		var scope_name := ""
		if found != null and scopes.back()["kind"] == "class":
			var kind := found.get_string(1)
			var name := found.get_string(2)
			if kind == "class":
				scope_kind = "class"
				scope_name = name
			else:
				var offset := content_start + found.get_start(2)
				var before := statement.substr(0, offset)
				var symbol_line := start_line + before.count("\n")
				var column := offset - before.rfind("\n") - 1
				var category := Category.FUNCTIONS if kind == "func" else Category.FIELDS
				var qualifier := _class_qualifier(scopes)
				var tail := content.substr(found.get_end(2))
				var display_name := _function_signature(name, tail) if kind == "func" else _typed_declaration(name + tail)
				if not qualifier.is_empty():
					display_name = qualifier + "." + display_name
				var is_private := name.begins_with("_")
				var access_hint := "Private by naming convention (_ prefix)" if is_private else "Public by naming convention"
				entries.append({
					"name": name,
					"label": display_name,
					"context": qualifier,
					"tooltip": "\n".join(original_lines.slice(start_line, line_index + 1)).strip_edges() + "\n" + access_hint,
					"line": symbol_line,
					"column": column,
					"category": category,
					"private": is_private,
				})
				if kind == "func":
					scope_kind = "function"
		if content.strip_edges().ends_with(":") or scope_kind == "function":
			scopes.append({"indent": indent, "kind": scope_kind, "name": scope_name})
		statement = ""
	return entries


static func _function_signature(name: String, tail: String) -> String:
	var opening := tail.find("(")
	if opening < 0:
		return name + "()"
	var depth := 1
	var closing := opening + 1
	while closing < tail.length() and depth > 0:
		if tail[closing] == "(":
			depth += 1
		elif tail[closing] == ")":
			depth -= 1
		if depth > 0:
			closing += 1
	if depth > 0:
		return name + "()"
	var parameters := PackedStringArray()
	var remaining := tail.substr(opening + 1, closing - opening - 1)
	while not remaining.strip_edges().is_empty():
		var comma := _top_level_index(remaining, ",")
		var parameter := remaining if comma < 0 else remaining.substr(0, comma)
		var label := _typed_declaration(parameter)
		if not label.is_empty():
			parameters.append(label)
		if comma < 0:
			break
		remaining = remaining.substr(comma + 1)
	var signature := name + "(" + ", ".join(parameters) + ")"
	var suffix := _compact_whitespace(tail.substr(closing + 1))
	if suffix.begins_with("->"):
		var return_type := suffix.substr(2)
		var body := _top_level_index(return_type, ":")
		if body >= 0:
			return_type = return_type.substr(0, body)
		return_type = _format_type(return_type)
		if not return_type.is_empty():
			signature += ": " + return_type
	return signature


# Drop initializers/default values, preserving explicitly declared types only.
static func _typed_declaration(declaration: String) -> String:
	var assignment := _top_level_index(declaration, "=")
	if assignment >= 0:
		declaration = declaration.substr(0, assignment)
	var colon := _top_level_index(declaration, ":")
	if colon < 0:
		return _compact_whitespace(declaration)
	var name := _compact_whitespace(declaration.substr(0, colon))
	var type := declaration.substr(colon + 1)
	var accessor := _top_level_index(type, ":")
	if accessor >= 0:
		type = type.substr(0, accessor)
	type = _format_type(type)
	return name if type.is_empty() else name + ": " + type


static func _top_level_index(text: String, delimiter: String) -> int:
	var depth := 0
	for cursor in text.length():
		var character := text[cursor]
		if depth == 0 and character == delimiter:
			return cursor
		if "([{".contains(character):
			depth += 1
		elif ")]}".contains(character):
			depth = maxi(0, depth - 1)
	return -1


static func _format_type(text: String) -> String:
	var type := _compact_whitespace(text)
	for delimiter in [".", "[", "]"]:
		type = type.replace(" " + delimiter, delimiter).replace(delimiter + " ", delimiter)
	return type.replace(" ,", ",").replace(", ", ",").replace(",", ", ")


static func _compact_whitespace(text: String) -> String:
	return " ".join(text.replace("\\", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ").split(" ", false))


static func _class_qualifier(scopes: Array[Dictionary]) -> String:
	var names := PackedStringArray()
	for scope in scopes:
		if scope["kind"] == "class" and not str(scope["name"]).is_empty():
			names.append(scope["name"])
	return ".".join(names)


static func _indent_width(line: String) -> int:
	var width := 0
	for character in line:
		if character == "\t":
			width += 4
		elif character == " ":
			width += 1
		else:
			break
	return width


static func _skip_annotations(statement: String) -> int:
	var cursor := 0
	while cursor < statement.length():
		if statement[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
			continue
		if statement[cursor] != "@":
			break
		cursor += 1
		while cursor < statement.length() and (statement[cursor] == "_" or statement[cursor].is_valid_identifier()):
			cursor += 1
		if cursor < statement.length() and statement[cursor] == "(":
			var depth := 1
			cursor += 1
			while cursor < statement.length() and depth > 0:
				if statement[cursor] == "(":
					depth += 1
				elif statement[cursor] == ")":
					depth -= 1
				cursor += 1
	return cursor


static func _mask_strings_and_comments(source: String) -> String:
	var output := PackedStringArray()
	var quote := ""
	var comment := false
	var cursor := 0
	while cursor < source.length():
		var character := source[cursor]
		if character == "\n":
			comment = false
			output.append("\n")
			cursor += 1
			continue
		if comment:
			output.append(" ")
			cursor += 1
			continue
		if not quote.is_empty():
			if character == "\\" and cursor + 1 < source.length():
				output.append(" \n" if source[cursor + 1] == "\n" else "  ")
				cursor += 2
			elif source.substr(cursor, quote.length()) == quote:
				output.append(" ".repeat(quote.length()))
				cursor += quote.length()
				quote = ""
			else:
				output.append(" ")
				cursor += 1
			continue
		if character == "#":
			comment = true
			output.append(" ")
		elif character in ["\"", "'"]:
			quote = character.repeat(3) if source.substr(cursor, 3) == character.repeat(3) else character
			output.append(" ".repeat(quote.length()))
			cursor += quote.length()
			continue
		else:
			output.append(character)
		cursor += 1
	return "".join(output)
