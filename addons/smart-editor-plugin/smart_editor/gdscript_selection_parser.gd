@tool
extends RefCounted

const SmartSelectionRange := preload("res://addons/smart-editor-plugin/smart_editor/smart_selection_range.gd")
const GDScriptTokenizer := preload("res://addons/smart-editor-plugin/smart_editor/gdscript_tokenizer.gd")
const GDScriptExpressionParser := preload("res://addons/smart-editor-plugin/smart_editor/gdscript_expression_parser.gd")
const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

const KIND_FILE := "file"
const KIND_BLOCK := "block"
const KIND_FUNCTION := "function"
const KIND_STATEMENT := "statement"
const KIND_INLINE_STATEMENT := "inline_statement"
const KIND_IDENTIFIER := "identifier"
const KIND_STRING_LITERAL := "string_literal"
const KIND_MEMBER := "member_access"
const KIND_CALL := "call"
const KIND_BINARY := "binary"
const KIND_UNARY := "unary"
const KIND_GROUP := "group"
const KIND_COLLECTION := "collection"
const KIND_SUBSCRIPT := "subscript"
const KIND_PARAMETER_LIST := "parameter_list"
const KIND_PARAMETER := "parameter"
const KIND_DECLARATION := "declaration"
const KIND_TYPE := "type"
const KIND_COMMENT := "comment"

func build_candidates(text: String, current: Dictionary) -> Array[Dictionary]:
	var root := _parse_file(text)
	var path := _find_smallest_path(root, current)
	var candidates: Array[Dictionary] = []
	var member_suffix := _member_suffix_range_for_path(path, current)

	for index in path.size():
		var node: Dictionary = path[index]
		if node.get("kind", "") == KIND_FILE:
			continue
		if _is_member_left_prefix_to_skip(path, index, current):
			continue
		if _is_call_callee_member_to_skip(path, index, current):
			continue
		if _is_collection_value_inline_statement_to_skip(path, index):
			continue
		if node.get("kind", "") == KIND_CALL:
			if not _is_await_operand_call(path, index):
				_append_range(candidates, _call_arguments_content_range(node, current))
			_append_range(candidates, _call_suffix_range_for_arguments(node, current))
			if _is_call_followed_by_member(path, index) or _is_member_call_callee_selected(node, current):
				_append_range(candidates, _call_suffix_range_for_callee(node, current))
				_append_range(candidates, _call_callee_range_for_selected_member_call(node, current))
		if node.get("kind", "") == KIND_BINARY:
			_append_range(candidates, _binary_left_operand_range_for_right(node, current))
		if node.get("kind", "") == KIND_STATEMENT:
			_append_range(candidates, _statement_expression_range(node, current))
		if node.get("kind", "") == KIND_PARAMETER_LIST:
			_append_range(candidates, _parameter_list_content_range(node, current))
		if [KIND_BLOCK, KIND_FUNCTION].has(node.get("kind", "")):
			_append_range(candidates, _block_body_range(node, current))
		_append_range(candidates, _node_selection_range(node, current))
		if index == 0:
			_append_range(candidates, member_suffix)

	return candidates


func _parse_file(text: String) -> Dictionary:
	var lines := text.split("\n", true)
	var last_line := maxi(lines.size() - 1, 0)
	var last_col := 0
	if not lines.is_empty():
		last_col = String(lines[last_line]).length()

	var root := _make_node(KIND_FILE, 0, 0, last_line, last_col)
	var container_stack: Array[Dictionary] = [root]
	var collection_stack: Array[Dictionary] = []
	var explicit_continuation_statement: Dictionary = {}
	var active_comment: Dictionary = {}
	var multiline_string_statement: Dictionary = {}
	var multiline_string_literal: Dictionary = {}
	for line_index in lines.size():
		var line := String(lines[line_index])
		var code_end := _line_code_end(line)
		var comment_start := _line_comment_start(line, code_end)
		var code_start := _line_indent_chars(line)
		while code_end > code_start and (line[code_end - 1] == " " or line[code_end - 1] == "\t"):
			code_end -= 1
		if _is_full_line_comment(line, code_start, comment_start):
			var appended_comment := _append_full_line_comment(line, line_index, code_start, comment_start, container_stack, collection_stack, active_comment)
			if not appended_comment.is_empty():
				active_comment = appended_comment
				continue
		active_comment = {}
		if code_start >= code_end:
			continue

		if not multiline_string_statement.is_empty():
			if _continue_multiline_string_statement(
				line,
				line_index,
				code_start,
				code_end,
				multiline_string_statement,
				multiline_string_literal,
				collection_stack
			):
				multiline_string_statement = {}
				multiline_string_literal = {}
			continue

		if _line_closes_collection(line, line_index, code_start, code_end, collection_stack):
			continue
		if _line_closes_brace_block(line, line_index, code_start, code_end, container_stack):
			continue

		var is_explicit_continuation := not explicit_continuation_statement.is_empty()
		if not is_explicit_continuation:
			while container_stack.size() > 1:
				var top: Dictionary = container_stack.back()
				if code_start > int(top["indent"]):
					break
				container_stack.pop_back()

		var multiline_string_start := _multiline_string_start_col(line, code_start, code_end)
		if multiline_string_start != -1:
			var parent_for_multiline: Dictionary = container_stack.back()
			if not collection_stack.is_empty():
				parent_for_multiline = collection_stack.back()
			var multiline_statement := _make_node(KIND_STATEMENT, line_index, code_start, line_index, code_end)
			var string_literal := _make_node(KIND_STRING_LITERAL, line_index, multiline_string_start, line_index, code_end)
			_add_child(multiline_statement, string_literal)
			_add_child(parent_for_multiline, multiline_statement)
			multiline_string_statement = multiline_statement
			multiline_string_literal = string_literal
			continue

		var statement := _make_node(KIND_STATEMENT, line_index, code_start, line_index, code_end)
		for expression in _parse_line_expressions(line, line_index, code_start, code_end):
			_add_child(statement, expression)
		if comment_start != -1:
			_add_child(statement, _make_node(KIND_COMMENT, line_index, comment_start, line_index, _line_comment_end(line, comment_start)))

		var parent: Dictionary = explicit_continuation_statement
		if parent.is_empty():
			parent = container_stack.back()
		if parent.is_empty() and not collection_stack.is_empty():
			parent = collection_stack.back()
		elif not is_explicit_continuation and not collection_stack.is_empty():
			parent = collection_stack.back()
		_add_child(parent, statement)

		var opened_collection := _find_unclosed_collection_node(statement)
		if not opened_collection.is_empty():
			opened_collection["owner_statement"] = statement
			collection_stack.append(opened_collection)
		_close_collection_stack_from_line(line, line_index, code_start, code_end, collection_stack)

		if not is_explicit_continuation and _starts_block(line, code_start, code_end):
			var block := _make_block_node(line, line_index, code_start, code_end, statement)
			_add_child(parent, block)
			container_stack.append(block)
		elif not is_explicit_continuation and _starts_brace_block(line, code_start, code_end):
			var brace_block := _make_brace_block_node(line, line_index, code_start, code_end, statement)
			_add_child(parent, brace_block)
			container_stack.append(brace_block)

		if _line_has_explicit_continuation(line, code_start, code_end):
			if explicit_continuation_statement.is_empty():
				statement["explicit_continuation"] = true
				explicit_continuation_statement = statement
		elif is_explicit_continuation:
			explicit_continuation_statement = {}

	_refresh_container_ranges(root)
	return root


func _parse_line_expressions(line: String, line_index: int, code_start: int, code_end: int) -> Array[Dictionary]:
	var expressions: Array[Dictionary] = []
	var stripped := line.substr(code_start, code_end - code_start)
	if stripped.begins_with("func "):
		return _parse_function_signature_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("signal "):
		return _parse_signal_signature_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("for "):
		return _parse_for_loop_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("extends ") or stripped.begins_with("class_name "):
		return _parse_class_declaration_nodes(line, line_index, code_start, code_end)

	var annotation_declaration := _parse_annotation_declaration_node(line, line_index, code_start, code_end)
	if not annotation_declaration.is_empty():
		expressions.append(annotation_declaration)

	var declaration := _parse_local_declaration_node(line, line_index, code_start, code_end)
	if not declaration.is_empty():
		expressions.append(declaration)

	var primary_start := _line_expression_start(line, code_start, code_end)
	var primary_end := _line_expression_end(line, primary_start, code_end)
	_append_top_level_expression_segments(expressions, line, line_index, primary_start, primary_end)

	var inline_start := _inline_statement_start(line, primary_end, code_end)
	if inline_start != -1:
		var inline_expression_start := _line_expression_start(line, inline_start, code_end)
		var inline_expression_end := _line_expression_end(line, inline_expression_start, code_end)
		var inline_statement := _make_node(KIND_INLINE_STATEMENT, line_index, inline_start, line_index, code_end)
		var inline_expressions: Array[Dictionary] = []
		_append_top_level_expression_segments(inline_expressions, line, line_index, inline_expression_start, inline_expression_end)
		for inline_expression in inline_expressions:
			_add_child(inline_statement, inline_expression)
		expressions.append(inline_statement)

	return expressions


func _append_top_level_expression_segments(expressions: Array[Dictionary], line: String, line_index: int, from_col: int, to_col: int) -> void:
	var segment_start := _skip_spaces(line, from_col)
	while segment_start < to_col:
		var comma_col := _find_top_level_char(line, segment_start, to_col, ",")
		var segment_end := comma_col if comma_col != -1 else to_col
		while segment_end > segment_start and (line[segment_end - 1] == " " or line[segment_end - 1] == "\t"):
			segment_end -= 1

		if segment_start < segment_end:
			var expression := _parse_expression_range(line, line_index, segment_start, segment_end)
			if not expression.is_empty():
				expressions.append(expression)

		if comma_col == -1:
			break
		segment_start = _skip_spaces(line, comma_col + 1)


func _parse_function_signature_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var name_start := _skip_spaces(line, code_start + 4)
	var name_end := name_start
	if name_start < code_end and _is_identifier_start_char(line[name_start]):
		name_end += 1
		while name_end < code_end and _is_identifier_char(line[name_end]):
			name_end += 1
		nodes.append(_make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var open_paren := _find_top_level_char(line, name_end, code_end, "(")
	if open_paren != -1:
		var close_paren := _find_matching_close_char(line, open_paren, code_end, "(", ")")
		if close_paren != -1:
			var parameter_list := _make_node(KIND_PARAMETER_LIST, line_index, open_paren, line_index, close_paren + 1)
			_add_function_parameter_nodes(parameter_list, line, line_index, open_paren + 1, close_paren)
			nodes.append(parameter_list)
			_append_function_return_type_node(nodes, line, line_index, close_paren + 1, code_end)

	return nodes


func _parse_signal_signature_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var name_start := _skip_spaces(line, code_start + 6)
	var name_end := name_start
	if name_start < code_end and _is_identifier_start_char(line[name_start]):
		name_end += 1
		while name_end < code_end and _is_identifier_char(line[name_end]):
			name_end += 1
		nodes.append(_make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var open_paren := _find_top_level_char(line, name_end, code_end, "(")
	if open_paren != -1:
		var close_paren := _find_matching_close_char(line, open_paren, code_end, "(", ")")
		if close_paren != -1:
			var parameter_list := _make_node(KIND_PARAMETER_LIST, line_index, open_paren, line_index, close_paren + 1)
			_add_function_parameter_nodes(parameter_list, line, line_index, open_paren + 1, close_paren)
			nodes.append(parameter_list)

	return nodes


func _parse_class_declaration_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var keyword_length := 0
	if line.substr(code_start, 8) == "extends ":
		keyword_length = 7
	elif line.substr(code_start, 11) == "class_name ":
		keyword_length = 10
	else:
		return nodes

	nodes.append(_make_node(KIND_IDENTIFIER, line_index, code_start, line_index, code_start + keyword_length))

	var target_start := _skip_spaces(line, code_start + keyword_length)
	var target_end := _line_expression_end(line, target_start, code_end)
	var target := _parse_expression_range(line, line_index, target_start, target_end)
	if not target.is_empty():
		nodes.append(target)

	return nodes


func _parse_annotation_declaration_node(line: String, line_index: int, code_start: int, code_end: int) -> Dictionary:
	if line[code_start] != "@":
		return {}

	var keyword_start := _annotation_declaration_keyword_start(line, code_start, code_end)
	if keyword_start == -1:
		return {}

	var keyword_length := 0
	if line.substr(keyword_start, 4) == "var ":
		keyword_length = 3
	elif line.substr(keyword_start, 6) == "const ":
		keyword_length = 5
	else:
		return {}

	var name_start := _skip_spaces(line, keyword_start + keyword_length)
	if name_start >= code_end or not _is_identifier_start_char(line[name_start]):
		return {}

	var name_end := name_start + 1
	while name_end < code_end and _is_identifier_char(line[name_end]):
		name_end += 1

	var name_declaration := _make_node(KIND_DECLARATION, line_index, name_start, line_index, code_end)
	_add_child(name_declaration, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var keyword_declaration := _make_node(KIND_DECLARATION, line_index, keyword_start, line_index, code_end)
	_add_child(keyword_declaration, name_declaration)

	var annotation_declaration := _make_node(KIND_DECLARATION, line_index, code_start, line_index, code_end)
	_add_child(annotation_declaration, keyword_declaration)
	return annotation_declaration


func _annotation_declaration_keyword_start(line: String, from_col: int, to_col: int) -> int:
	var col := from_col
	while col < to_col:
		if line[col] != "@":
			return -1
		col += 1
		while col < to_col and (_is_identifier_char(line[col]) or line[col] == "."):
			col += 1
		if col < to_col and line[col] == "(":
			var close_col := _find_matching_close_char(line, col, to_col, "(", ")")
			if close_col == -1:
				return -1
			col = close_col + 1
		col = _skip_spaces(line, col)
		if line.substr(col, 4) == "var " or line.substr(col, 6) == "const ":
			return col
	return -1


func _parse_for_loop_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var target_start := _skip_spaces(line, code_start + 3)
	var in_col := _find_top_level_word(line, target_start, code_end, "in")
	if in_col == -1:
		return nodes

	var target_end := in_col
	while target_end > target_start and (line[target_end - 1] == " " or line[target_end - 1] == "\t"):
		target_end -= 1
	if target_start < target_end and _is_identifier_start_char(line[target_start]):
		var target_name_end := target_start + 1
		while target_name_end < target_end and _is_identifier_char(line[target_name_end]):
			target_name_end += 1
		if target_name_end == target_end:
			nodes.append(_make_node(KIND_IDENTIFIER, line_index, target_start, line_index, target_end))

	var iterable_start := _skip_spaces(line, in_col + 2)
	var iterable_end := _find_top_level_colon(line, iterable_start, code_end)
	if iterable_end == -1:
		iterable_end = code_end
	var iterable := _parse_expression_range(line, line_index, iterable_start, iterable_end)
	if not iterable.is_empty():
		nodes.append(iterable)

	return nodes


func _parse_local_declaration_node(line: String, line_index: int, code_start: int, code_end: int) -> Dictionary:
	var stripped := line.substr(code_start, code_end - code_start)
	var keyword_length := 0
	if stripped.begins_with("var "):
		keyword_length = 3
	elif stripped.begins_with("const "):
		keyword_length = 5
	else:
		return {}

	var name_start := _skip_spaces(line, code_start + keyword_length)
	if name_start >= code_end or not _is_identifier_start_char(line[name_start]):
		return {}

	var name_end := name_start + 1
	while name_end < code_end and _is_identifier_char(line[name_end]):
		name_end += 1

	var declaration_end := _find_assignment_operator(line, name_start, code_end)
	if declaration_end == -1:
		declaration_end = code_end
	while declaration_end > name_start and (line[declaration_end - 1] == " " or line[declaration_end - 1] == "\t"):
		declaration_end -= 1

	var declaration := _make_node(KIND_DECLARATION, line_index, name_start, line_index, declaration_end)
	_add_child(declaration, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))
	_add_declaration_type_node(declaration, line, line_index, name_start, declaration_end)
	return declaration


func _add_declaration_type_node(declaration: Dictionary, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var colon_col := _find_top_level_colon(line, from_col, to_col)
	if colon_col == -1:
		return

	var type_start := _skip_spaces(line, colon_col + 1)
	var type_end := to_col
	while type_end > type_start and (line[type_end - 1] == " " or line[type_end - 1] == "\t"):
		type_end -= 1
	if type_start >= type_end:
		return

	var type_node := _make_node(KIND_TYPE, line_index, type_start, line_index, type_end)
	var type_expression := _parse_expression_range(line, line_index, type_start, type_end)
	if not type_expression.is_empty():
		_add_child(type_node, type_expression)
	_add_child(declaration, type_node)


func _add_function_parameter_nodes(parameter_list: Dictionary, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var parameter_start := _skip_spaces(line, from_col)
	while parameter_start < to_col:
		var comma_col := _find_top_level_char(line, parameter_start, to_col, ",")
		var parameter_end := comma_col if comma_col != -1 else to_col
		while parameter_end > parameter_start and (line[parameter_end - 1] == " " or line[parameter_end - 1] == "\t"):
			parameter_end -= 1

		if parameter_start < parameter_end:
			var parameter := _make_node(KIND_PARAMETER, line_index, parameter_start, line_index, parameter_end)
			_add_function_parameter_parts(parameter, line, line_index, parameter_start, parameter_end)
			_add_child(parameter_list, parameter)

		if comma_col == -1:
			break
		parameter_start = _skip_spaces(line, comma_col + 1)


func _add_function_parameter_parts(parameter: Dictionary, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var name_start := from_col
	if name_start < to_col and _is_identifier_start_char(line[name_start]):
		var name_end := name_start + 1
		while name_end < to_col and _is_identifier_char(line[name_end]):
			name_end += 1
		_add_child(parameter, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var colon_col := _find_top_level_colon(line, from_col, to_col)
	if colon_col == -1:
		return

	var type_start := _skip_spaces(line, colon_col + 1)
	var equals_col := _find_top_level_char(line, type_start, to_col, "=")
	var type_end := equals_col
	if equals_col == -1:
		type_end = to_col
	while type_end > type_start and (line[type_end - 1] == " " or line[type_end - 1] == "\t"):
		type_end -= 1
	if type_start >= type_end:
		return

	var type_node := _make_node(KIND_TYPE, line_index, type_start, line_index, type_end)
	var type_expression := _parse_expression_range(line, line_index, type_start, type_end)
	if not type_expression.is_empty():
		_add_child(type_node, type_expression)
	_add_child(parameter, type_node)

	if equals_col == -1:
		return

	var default_start := _skip_spaces(line, equals_col + 1)
	var default_end := to_col
	while default_end > default_start and (line[default_end - 1] == " " or line[default_end - 1] == "\t"):
		default_end -= 1
	if default_start >= default_end:
		return

	var typed_default := _make_node(KIND_TYPE, line_index, type_start, line_index, default_end)
	var default_expression := _parse_expression_range(line, line_index, default_start, default_end)
	if not default_expression.is_empty():
		_add_child(typed_default, default_expression)
	_add_child(parameter, typed_default)


func _append_function_return_type_node(nodes: Array[Dictionary], line: String, line_index: int, from_col: int, code_end: int) -> void:
	var arrow_col := _find_top_level_text(line, from_col, code_end, "->")
	if arrow_col == -1:
		return

	var type_start := _skip_spaces(line, arrow_col + 2)
	var type_end := _find_top_level_colon(line, type_start, code_end)
	if type_end == -1:
		type_end = code_end
	while type_end > type_start and (line[type_end - 1] == " " or line[type_end - 1] == "\t"):
		type_end -= 1
	if type_start >= type_end:
		return

	var type_node := _make_node(KIND_TYPE, line_index, arrow_col, line_index, type_end)
	var type_expression := _parse_expression_range(line, line_index, type_start, type_end)
	if not type_expression.is_empty():
		_add_child(type_node, type_expression)
	nodes.append(type_node)


func _parse_expression_range(line: String, line_index: int, expression_start: int, expression_end: int) -> Dictionary:
	if expression_start >= expression_end:
		return {}

	var tokens := GDScriptTokenizer.tokenize_line(line, line_index, expression_start, expression_end)
	if tokens.is_empty():
		return {}

	return GDScriptExpressionParser.parse(tokens)


func _inline_statement_start(line: String, from_col: int, code_end: int) -> int:
	var colon_col := _find_top_level_colon(line, from_col, code_end)
	if colon_col == -1:
		return -1
	return _skip_spaces(line, colon_col + 1)


func _starts_block(line: String, code_start: int, code_end: int) -> bool:
	var colon_col := _find_top_level_colon(line, code_start, code_end)
	if colon_col == -1:
		return false
	return _skip_spaces(line, colon_col + 1) >= code_end


func _starts_brace_block(line: String, code_start: int, code_end: int) -> bool:
	var stripped := line.substr(code_start, code_end - code_start)
	if not stripped.begins_with("enum"):
		return false

	var after_keyword_col := code_start + 4
	if after_keyword_col < code_end and _is_identifier_char(line[after_keyword_col]):
		return false

	var open_brace_col := _find_top_level_char(line, after_keyword_col, code_end, "{")
	if open_brace_col == -1:
		return false
	return _skip_spaces(line, open_brace_col + 1) >= code_end


func _make_block_node(line: String, line_index: int, code_start: int, code_end: int, header_statement: Dictionary) -> Dictionary:
	var kind := KIND_BLOCK
	if line.substr(code_start, code_end - code_start).begins_with("func "):
		kind = KIND_FUNCTION

	var block := _make_node(kind, line_index, code_start, line_index, code_end)
	block["indent"] = code_start
	_add_child(block, _duplicate_node(header_statement))
	return block


func _make_brace_block_node(line: String, line_index: int, code_start: int, code_end: int, header_statement: Dictionary) -> Dictionary:
	var block := _make_node(KIND_BLOCK, line_index, code_start, line_index, code_end)
	block["indent"] = code_start
	block["close_text"] = "}"
	_add_child(block, _duplicate_node(header_statement))
	return block


func _line_expression_start(line: String, code_start: int, code_end: int) -> int:
	var stripped := line.substr(code_start, code_end - code_start)
	if stripped.begins_with("."):
		return code_start + 1
	if stripped.begins_with("if "):
		return _skip_spaces(line, code_start + 2)
	if stripped.begins_with("elif "):
		return _skip_spaces(line, code_start + 4)
	if stripped.begins_with("while "):
		return _skip_spaces(line, code_start + 6)
	if stripped.begins_with("return"):
		return _skip_spaces(line, code_start + 6)
	if stripped.begins_with("await "):
		return code_start
	if stripped.begins_with("and "):
		return _skip_spaces(line, code_start + 3)
	if stripped.begins_with("or "):
		return _skip_spaces(line, code_start + 2)

	var assignment_col := _find_assignment_operator(line, code_start, code_end)
	if assignment_col != -1:
		return _skip_spaces(line, assignment_col + _assignment_operator_length_at(line, assignment_col))

	return code_start


func _line_expression_end(line: String, expression_start: int, code_end: int) -> int:
	var expression_end := _line_without_explicit_continuation_end(line, expression_start, code_end)
	var colon_col := _find_top_level_colon(line, expression_start, expression_end)
	if colon_col != -1:
		return colon_col
	return expression_end


func _line_has_explicit_continuation(line: String, from_col: int, code_end: int) -> bool:
	return _line_without_explicit_continuation_end(line, from_col, code_end) < code_end


func _multiline_string_start_col(line: String, code_start: int, code_end: int) -> int:
	var double_quote_start := line.find("\"\"\"", code_start)
	var single_quote_start := line.find("'''", code_start)
	var result := -1
	if double_quote_start != -1 and double_quote_start < code_end:
		result = double_quote_start
	if single_quote_start != -1 and single_quote_start < code_end and (result == -1 or single_quote_start < result):
		result = single_quote_start
	if result == -1:
		return -1

	var quote_text := line.substr(result, 3)
	var close_col := line.find(quote_text, result + 3)
	if close_col != -1 and close_col < code_end:
		return -1
	return result


func _continue_multiline_string_statement(
	line: String,
	line_index: int,
	code_start: int,
	code_end: int,
	statement: Dictionary,
	string_literal: Dictionary,
	collection_stack: Array[Dictionary]
) -> bool:
	var close_col := _multiline_string_close_col(line, code_start, code_end)
	if close_col == -1:
		string_literal["to_line"] = line_index
		string_literal["to_col"] = code_end
		statement["to_line"] = line_index
		statement["to_col"] = code_end
		return false

	var string_end := close_col + 3
	string_literal["to_line"] = line_index
	string_literal["to_col"] = string_end
	statement["to_line"] = line_index
	statement["to_col"] = code_end

	var percent_col := _find_top_level_char(line, string_end, code_end, "%")
	if percent_col == -1:
		return true

	var array_open_col := _find_top_level_char(line, percent_col + 1, code_end, "[")
	if array_open_col == -1:
		return true

	var left_end := percent_col
	while left_end > string_end and (line[left_end - 1] == " " or line[left_end - 1] == "\t"):
		left_end -= 1

	var left_expression := _make_node(
		KIND_STRING_LITERAL,
		int(string_literal["from_line"]),
		int(string_literal["from_col"]),
		line_index,
		left_end
	)
	_add_child(left_expression, string_literal)

	var collection := _make_node(KIND_COLLECTION, line_index, array_open_col, line_index, array_open_col + 1)
	collection["close_text"] = "]"
	collection["is_closed"] = false
	collection["owner_statement"] = statement

	var binary := _make_node(KIND_BINARY, left_expression["from_line"], left_expression["from_col"], line_index, array_open_col + 1)
	binary["operator"] = "%"
	_add_child(binary, left_expression)
	_add_child(binary, collection)
	collection["close_owner"] = binary

	statement["children"] = []
	statement["has_rhs_expression"] = true
	_add_child(statement, binary)
	collection_stack.append(collection)
	return true


func _multiline_string_close_col(line: String, from_col: int, to_col: int) -> int:
	var double_quote_close := line.find("\"\"\"", from_col)
	var single_quote_close := line.find("'''", from_col)
	var result := -1
	if double_quote_close != -1 and double_quote_close < to_col:
		result = double_quote_close
	if single_quote_close != -1 and single_quote_close < to_col and (result == -1 or single_quote_close < result):
		result = single_quote_close
	return result


func _line_without_explicit_continuation_end(line: String, from_col: int, code_end: int) -> int:
	if code_end <= from_col:
		return code_end
	if line[code_end - 1] != "\\":
		return code_end

	var expression_end := code_end - 1
	while expression_end > from_col and (line[expression_end - 1] == " " or line[expression_end - 1] == "\t"):
		expression_end -= 1
	return expression_end


func _line_comment_start(line: String, code_end: int) -> int:
	if code_end < line.length() and line[code_end] == "#":
		return code_end
	return -1


func _line_comment_end(line: String, comment_start: int) -> int:
	var comment_end := line.length()
	while comment_end > comment_start and (line[comment_end - 1] == " " or line[comment_end - 1] == "\t"):
		comment_end -= 1
	return comment_end


func _is_full_line_comment(line: String, code_start: int, comment_start: int) -> bool:
	return comment_start != -1 and _skip_spaces(line, code_start) == comment_start


func _append_full_line_comment(
	line: String,
	line_index: int,
	code_start: int,
	comment_start: int,
	container_stack: Array[Dictionary],
	collection_stack: Array[Dictionary],
	active_comment: Dictionary
) -> Dictionary:
	if comment_start == -1:
		return {}

	while container_stack.size() > 1:
		var top: Dictionary = container_stack.back()
		if code_start > int(top["indent"]):
			break
		container_stack.pop_back()

	var parent: Dictionary = container_stack.back()
	if not collection_stack.is_empty():
		parent = collection_stack.back()

	var comment_end := _line_comment_end(line, comment_start)

	if (
		not active_comment.is_empty()
		and int(active_comment["to_line"]) == line_index - 1
		and int(active_comment["from_col"]) == comment_start
	):
		active_comment["to_line"] = line_index
		active_comment["to_col"] = comment_end
		return active_comment

	var comment := _make_node(KIND_COMMENT, line_index, comment_start, line_index, comment_end)
	_add_child(parent, comment)
	return comment


func _find_smallest_path(root: Dictionary, current: Dictionary) -> Array[Dictionary]:
	if not _node_contains_range(root, current):
		return []

	var best_child_path: Array[Dictionary] = []
	for child in root.get("children", []):
		var child_path := _find_smallest_path(child, current)
		if not child_path.is_empty():
			if (
				best_child_path.is_empty()
				or _range_size(child_path[0]) < _range_size(best_child_path[0])
				or (
					_range_size(child_path[0]) == _range_size(best_child_path[0])
					and child_path.size() > best_child_path.size()
				)
			):
				best_child_path = child_path

	if best_child_path.is_empty():
		return [root]

	best_child_path.append(root)
	return best_child_path


func _member_suffix_range_for_path(path: Array[Dictionary], current: Dictionary) -> Dictionary:
	var chain := _member_chain_info_for_path(path, current)
	if chain.is_empty():
		return {}

	var segments: Array = chain["segments"]
	var segment_index := int(chain["segment_index"])
	var top_member: Dictionary = chain["top_member"]
	var suffix_start_index := segment_index
	if segment_index == segments.size() - 1:
		suffix_start_index = segment_index - 1
	if suffix_start_index <= 0:
		return {}

	var first_segment: Dictionary = segments[suffix_start_index]
	return {
		"from_line": first_segment["from_line"],
		"from_col": first_segment["from_col"],
		"to_line": top_member["to_line"],
		"to_col": top_member["to_col"],
	}


func _is_member_left_prefix_to_skip(path: Array[Dictionary], index: int, current: Dictionary) -> bool:
	var node: Dictionary = path[index]
	if node.get("kind", "") != KIND_MEMBER:
		return false

	var chain := _member_chain_info_for_path(path, current)
	if chain.is_empty():
		return false

	var segment_index := int(chain["segment_index"])
	if segment_index <= 0:
		return false

	var segments: Array = chain["segments"]
	if segment_index >= segments.size():
		return false

	var selected_segment: Dictionary = segments[segment_index]
	var top_member: Dictionary = chain["top_member"]
	return (
		_compare_positions(node["to_line"], node["to_col"], selected_segment["to_line"], selected_segment["to_col"]) == 0
		and _compare_positions(node["to_line"], node["to_col"], top_member["to_line"], top_member["to_col"]) < 0
	)


func _is_call_callee_member_to_skip(path: Array[Dictionary], index: int, current: Dictionary) -> bool:
	var node: Dictionary = path[index]
	if node.get("kind", "") != KIND_MEMBER:
		return false
	if index + 1 >= path.size():
		return false

	var parent: Dictionary = path[index + 1]
	if parent.get("kind", "") != KIND_CALL:
		return false

	var children: Array = parent.get("children", [])
	if children.is_empty() or not _ranges_equal(children[0], node):
		return false

	var member_segments := _flatten_member_segments(node)
	if member_segments.is_empty():
		return false

	if index + 2 < path.size() and path[index + 2].get("kind", "") == KIND_MEMBER:
		return true

	var chain := _member_chain_info_for_path(path, current)
	return not chain.is_empty() and int(chain["segment_index"]) == member_segments.size() - 1


func _call_callee_range_for_selected_member_call(call: Dictionary, current: Dictionary) -> Dictionary:
	if not _is_member_call_callee_selected(call, current):
		return {}

	var children: Array = call.get("children", [])
	if children.size() < 2:
		return {}

	return _node_range(children[0])


func _is_call_followed_by_member(path: Array[Dictionary], index: int) -> bool:
	return index + 1 < path.size() and path[index + 1].get("kind", "") == KIND_MEMBER


func _is_empty_call(call: Dictionary) -> bool:
	return call.get("kind", "") == KIND_CALL and call.get("children", []).size() == 1


func _is_member_call_callee_selected(call: Dictionary, current: Dictionary) -> bool:
	var children: Array = call.get("children", [])
	if children.is_empty():
		return false

	var callee: Dictionary = children[0]
	if callee.get("kind", "") != KIND_MEMBER:
		return false

	var callee_segments := _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return false

	return _range_contains(_node_range(callee_segments.back()), current)


func _is_collection_value_inline_statement_to_skip(path: Array[Dictionary], index: int) -> bool:
	var node: Dictionary = path[index]
	if node.get("kind", "") != KIND_INLINE_STATEMENT:
		return false

	var children: Array = node.get("children", [])
	if children.size() != 1:
		return false

	var child: Dictionary = children[0]
	if int(node["from_line"]) != int(child["from_line"]) or int(node["from_col"]) != int(child["from_col"]):
		return false
	if int(node["to_line"]) != int(child["to_line"]):
		return false

	return int(node["to_col"]) == int(child["to_col"]) + 1


func _is_await_operand_call(path: Array[Dictionary], index: int) -> bool:
	if path[index].get("kind", "") != KIND_CALL:
		return false
	if index + 1 >= path.size():
		return false

	var parent: Dictionary = path[index + 1]
	return parent.get("kind", "") == KIND_UNARY and String(parent.get("operator", "")) == "await"


func _member_chain_info_for_path(path: Array[Dictionary], current: Dictionary) -> Dictionary:
	if path.is_empty():
		return {}

	var top_member := {}
	for node in path:
		if node.get("kind", "") == KIND_MEMBER:
			top_member = node
	if top_member.is_empty():
		return {}

	var segments := _flatten_member_segments(top_member)
	var segment_index := -1
	var selected_node: Dictionary = path[0]
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if _ranges_equal(segment, selected_node) or _range_contains(_node_range(segment), current):
			segment_index = index
			break
	if segment_index == -1:
		return {}

	return {
		"top_member": top_member,
		"segments": segments,
		"segment_index": segment_index,
	}


func _flatten_member_segments(node: Dictionary) -> Array[Dictionary]:
	if node.get("kind", "") != KIND_MEMBER:
		return [node]

	var children: Array = node.get("children", [])
	if children.size() < 2:
		return [node]

	var result: Array[Dictionary] = []
	result.append_array(_flatten_member_segments(children[0]))
	result.append_array(_flatten_member_segments(children[1]))
	return result


func _call_suffix_range_for_arguments(call: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = call.get("children", [])
	if children.size() < 2:
		return {}

	var callee: Dictionary = children[0]
	if _range_contains(_node_range(callee), current):
		return {}

	var argument_content := _call_arguments_content_selection_range(call)
	if argument_content.is_empty() or not _range_contains(argument_content, current):
		return {}

	var callee_segments := _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return {}

	var method_segment: Dictionary = callee_segments.back()
	return {
		"from_line": method_segment["from_line"],
		"from_col": method_segment["from_col"],
		"to_line": call["to_line"],
		"to_col": call["to_col"],
	}


func _call_suffix_range_for_callee(call: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = call.get("children", [])
	if children.is_empty():
		return {}

	var callee: Dictionary = children[0]
	if callee.get("kind", "") != KIND_MEMBER:
		return {}

	var callee_segments := _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return {}

	var method_segment: Dictionary = callee_segments.back()
	if not _range_contains(_node_range(method_segment), current):
		return {}

	return {
		"from_line": method_segment["from_line"],
		"from_col": method_segment["from_col"],
		"to_line": call["to_line"],
		"to_col": call["to_col"],
	}


func _call_arguments_content_range(call: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = call.get("children", [])
	if children.size() < 3:
		return {}

	var argument_content := _call_arguments_content_selection_range(call)
	if argument_content.is_empty() or not _range_contains(argument_content, current):
		return {}

	return argument_content


func _call_arguments_content_selection_range(call: Dictionary) -> Dictionary:
	var children: Array = call.get("children", [])
	if children.size() < 2:
		return {}

	var first_argument: Dictionary = children[1]
	var last_argument: Dictionary = children[children.size() - 1]
	return {
		"from_line": first_argument["from_line"],
		"from_col": first_argument["from_col"],
		"to_line": last_argument["to_line"],
		"to_col": last_argument["to_col"],
	}


func _parameter_list_content_range(parameter_list: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = parameter_list.get("children", [])
	if children.is_empty():
		return {}

	var first_parameter: Dictionary = children[0]
	var last_parameter: Dictionary = children[children.size() - 1]
	var content_range := {
		"from_line": first_parameter["from_line"],
		"from_col": first_parameter["from_col"],
		"to_line": last_parameter["to_line"],
		"to_col": last_parameter["to_col"],
	}
	if not _range_contains(content_range, current):
		return {}
	return content_range


func _binary_left_operand_range_for_right(binary: Dictionary, current: Dictionary) -> Dictionary:
	if String(binary.get("operator", "")) != "%":
		return {}

	var children: Array = binary.get("children", [])
	if children.size() < 2:
		return {}

	var right: Dictionary = children[1]
	if not _range_contains(_node_range(right), current):
		return {}

	return _node_range(children[0])


func _block_body_range(block: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = block.get("children", [])
	if children.size() < 2:
		return {}

	var body_children := children.slice(1)
	var containing_index := -1
	for index in body_children.size():
		var child: Dictionary = body_children[index]
		if _range_contains(_node_range(child), current):
			containing_index = index
			break
	if containing_index == -1:
		return {}

	var chunk_start := containing_index
	while chunk_start > 0:
		var previous_child: Dictionary = body_children[chunk_start - 1]
		var current_child: Dictionary = body_children[chunk_start]
		if int(previous_child["to_line"]) + 1 < int(current_child["from_line"]):
			break
		chunk_start -= 1

	var chunk_end := containing_index
	while chunk_end < body_children.size() - 1:
		var current_child: Dictionary = body_children[chunk_end]
		var next_child: Dictionary = body_children[chunk_end + 1]
		if int(current_child["to_line"]) + 1 < int(next_child["from_line"]):
			break
		chunk_end += 1

	var first_body_child: Dictionary = body_children[chunk_start]
	var last_body_child: Dictionary = body_children[chunk_end]
	var body_range := {
		"from_line": first_body_child["from_line"],
		"from_col": first_body_child["from_col"],
		"to_line": last_body_child["to_line"],
		"to_col": last_body_child["to_col"],
	}
	if not _range_contains(body_range, current):
		return {}
	return body_range


func _statement_expression_range(statement: Dictionary, current: Dictionary) -> Dictionary:
	var children: Array = statement.get("children", [])
	if children.is_empty():
		return {}

	var first_child: Dictionary = children[0]
	if bool(statement.get("has_rhs_expression", false)):
		var rhs_range := _node_range(first_child)
		if _ranges_equal(rhs_range, _node_range(statement)):
			return {}
		if not _range_contains(rhs_range, current):
			return {}
		return rhs_range

	if not bool(statement.get("explicit_continuation", false)):
		return {}

	var expression_range := {
		"from_line": first_child["from_line"],
		"from_col": first_child["from_col"],
		"to_line": statement["to_line"],
		"to_col": statement["to_col"],
	}
	if _ranges_equal(expression_range, _node_range(statement)):
		return {}
	if not _range_contains(expression_range, current):
		return {}
	return expression_range


func _make_node(kind: String, from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return {
		"kind": kind,
		"from_line": from_line,
		"from_col": from_col,
		"to_line": to_line,
		"to_col": to_col,
		"children": [],
	}


func _duplicate_node(node: Dictionary) -> Dictionary:
	var duplicate := _make_node(
		node.get("kind", ""),
		int(node["from_line"]),
		int(node["from_col"]),
		int(node["to_line"]),
		int(node["to_col"])
	)
	for child in node.get("children", []):
		_add_child(duplicate, _duplicate_node(child))
	return duplicate


func _add_child(parent: Dictionary, child: Dictionary) -> void:
	if child.is_empty():
		return
	parent["children"].append(child)
	if _node_range_can_grow_from_children(parent):
		if _compare_positions(parent["to_line"], parent["to_col"], child["to_line"], child["to_col"]) < 0:
			parent["to_line"] = child["to_line"]
			parent["to_col"] = child["to_col"]


func _refresh_container_ranges(node: Dictionary) -> void:
	for child in node.get("children", []):
		_refresh_container_ranges(child)

	if not _node_range_can_grow_from_children(node):
		return

	for child in node.get("children", []):
		if _compare_positions(node["to_line"], node["to_col"], child["to_line"], child["to_col"]) < 0:
			node["to_line"] = child["to_line"]
			node["to_col"] = child["to_col"]


func _node_range_can_grow_from_children(node: Dictionary) -> bool:
	return [
		KIND_BLOCK,
		KIND_FUNCTION,
		KIND_STATEMENT,
		KIND_COLLECTION,
		KIND_CALL,
		KIND_GROUP,
		KIND_SUBSCRIPT,
		KIND_BINARY,
		KIND_UNARY,
	].has(node.get("kind", ""))


func _line_closes_collection(line: String, line_index: int, code_start: int, code_end: int, collection_stack: Array[Dictionary]) -> bool:
	if collection_stack.is_empty():
		return false

	var top: Dictionary = collection_stack.back()
	var close_text := String(top.get("close_text", ""))
	if close_text.is_empty() or line[code_start] != close_text:
		return false

	top["to_line"] = line_index
	top["to_col"] = code_start + 1
	top["is_closed"] = true
	if top.has("owner_statement"):
		var owner_statement: Dictionary = top["owner_statement"]
		owner_statement["to_line"] = line_index
		owner_statement["to_col"] = code_end
	if top.has("close_owner"):
		var close_owner: Dictionary = top["close_owner"]
		close_owner["to_line"] = line_index
		close_owner["to_col"] = code_end
	collection_stack.pop_back()
	return true


func _close_collection_stack_from_line(line: String, line_index: int, code_start: int, code_end: int, collection_stack: Array[Dictionary]) -> void:
	while not collection_stack.is_empty():
		var top: Dictionary = collection_stack.back()
		var close_text := String(top.get("close_text", ""))
		if close_text.is_empty():
			return

		var close_col := _find_top_level_collection_close(line, code_start, code_end, close_text)
		if close_col == -1:
			return

		top["to_line"] = line_index
		top["to_col"] = close_col + close_text.length()
		top["is_closed"] = true
		if top.has("owner_statement"):
			var owner_statement: Dictionary = top["owner_statement"]
			owner_statement["to_line"] = line_index
			owner_statement["to_col"] = code_end
		if top.has("close_owner"):
			var close_owner: Dictionary = top["close_owner"]
			close_owner["to_line"] = line_index
			close_owner["to_col"] = close_col + close_text.length()
		collection_stack.pop_back()


func _find_top_level_collection_close(line: String, from_col: int, to_col: int, close_text: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			if ch == close_text and depth == 0:
				return col
			depth = maxi(depth - 1, 0)

	return -1


func _line_closes_brace_block(line: String, line_index: int, code_start: int, code_end: int, container_stack: Array[Dictionary]) -> bool:
	if container_stack.size() <= 1:
		return false

	var top: Dictionary = container_stack.back()
	var close_text := String(top.get("close_text", ""))
	if close_text.is_empty() or line[code_start] != close_text:
		return false

	top["to_line"] = line_index
	top["to_col"] = code_end
	container_stack.pop_back()
	return true


func _find_unclosed_collection_node(node: Dictionary, parent: Dictionary = {}) -> Dictionary:
	var result := {}
	for child in node.get("children", []):
		var nested := _find_unclosed_collection_node(child, node)
		if not nested.is_empty():
			result = nested

	if (
		result.is_empty()
		and [KIND_CALL, KIND_SUBSCRIPT, KIND_COLLECTION, KIND_GROUP].has(node.get("kind", ""))
		and not bool(node.get("is_closed", true))
	):
		if not parent.is_empty():
			node["close_owner"] = parent
		result = node

	return result


func _node_range(node: Dictionary) -> Dictionary:
	return SmartSelectionRange.from_node(node)


func _node_selection_range(node: Dictionary, current: Dictionary) -> Dictionary:
	var selection_range := _node_range(node)
	if node.get("kind", "") == KIND_STATEMENT and _is_caret_in_statement_indent(node, current):
		selection_range["from_col"] = current["from_col"]
	return selection_range


func _append_range(ranges: Array[Dictionary], selection_range: Dictionary) -> void:
	if selection_range.is_empty():
		return
	for existing in ranges:
		if _ranges_equal(existing, selection_range):
			return
	ranges.append(selection_range)


func _node_contains_range(node: Dictionary, selection_range: Dictionary) -> bool:
	if node.get("kind", "") == KIND_STATEMENT and _is_caret_in_statement_indent(node, selection_range):
		return true
	return _range_contains(_node_range(node), selection_range)


func _is_caret_in_statement_indent(node: Dictionary, selection_range: Dictionary) -> bool:
	if not _is_zero_width_range(selection_range):
		return false
	if int(selection_range["from_line"]) != int(node["from_line"]):
		return false
	if int(selection_range["from_col"]) > int(node["from_col"]):
		return false
	return int(selection_range["from_col"]) >= 0


func _is_zero_width_range(selection_range: Dictionary) -> bool:
	return SmartSelectionRange.is_zero_width(selection_range)


func _range_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return SmartSelectionRange.contains_or_equal(outer, inner)


func _ranges_equal(a: Dictionary, b: Dictionary) -> bool:
	return SmartSelectionRange.equal(a, b)


func _range_size(selection_range: Dictionary) -> int:
	return SmartSelectionRange.size(selection_range)


func _compare_positions(line_a: int, col_a: int, line_b: int, col_b: int) -> int:
	return SmartSelectionRange.compare_positions(line_a, col_a, line_b, col_b)


func _line_indent_chars(line: String) -> int:
	var count := 0
	for col in line.length():
		if line[col] == " " or line[col] == "\t":
			count += 1
		else:
			break
	return count


func _skip_spaces(line: String, col: int) -> int:
	while col < line.length() and (line[col] == " " or line[col] == "\t"):
		col += 1
	return col


func _line_code_end(line: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in line.length():
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "#" and depth == 0:
			return col
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)

	return line.length()


func _find_top_level_colon(line: String, from_col: int, to_col: int) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)
		elif ch == ":" and depth == 0:
			return col

	return -1


func _find_top_level_char(line: String, from_col: int, to_col: int, target: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == target and depth == 0:
			return col
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)

	return -1


func _find_top_level_text(line: String, from_col: int, to_col: int, target: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and line.substr(col, target.length()) == target:
			return col

	return -1


func _find_top_level_word(line: String, from_col: int, to_col: int, target: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and line.substr(col, target.length()) == target:
			var before_ok := col == 0 or not _is_identifier_char(line[col - 1])
			var after_col := col + target.length()
			var after_ok := after_col >= to_col or not _is_identifier_char(line[after_col])
			if before_ok and after_ok:
				return col

	return -1


func _find_matching_close_char(line: String, open_col: int, to_col: int, open_text: String, close_text: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(open_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == open_text:
			depth += 1
		elif ch == close_text:
			depth -= 1
			if depth == 0:
				return col

	return -1


func _find_assignment_operator(line: String, from_col: int, to_col: int) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var escaped := false

	for col in range(from_col, to_col):
		var ch := line[col]
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == quote:
				in_string = false
			continue

		if ch == "#" and depth == 0:
			return -1
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			escaped = false
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and _is_assignment_operator_at(line, col):
			return col

	return -1


func _assignment_operator_length_at(line: String, col: int) -> int:
	if col < line.length() - 1 and line[col + 1] == "=":
		return 2
	return 1


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


func _is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


func _is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)
