@tool
extends RefCounted

const SmartSelectionRange = preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")
const GDScriptSyntaxNode = preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/gdscript_syntax_node.gd")
const GDScriptTokenizer = preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/gdscript_tokenizer.gd")
const GDScriptExpressionParser = preload("res://addons/smart-editor-plugin/features/expand_shrink_selection/gdscript_expression_parser.gd")

const IDENTIFIER_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

const KIND_FILE = "file"
const KIND_BLOCK = "block"
const KIND_FUNCTION = "function"
const KIND_STATEMENT = "statement"
const KIND_INLINE_STATEMENT = "inline_statement"
const KIND_IDENTIFIER = "identifier"
const KIND_STRING_CONTENT = "string_content"
const KIND_STRING_LITERAL = "string_literal"
const KIND_LITERAL = "literal"
const KIND_MEMBER = "member_access"
const KIND_CALL = "call"
const KIND_BINARY = "binary"
const KIND_UNARY = "unary"
const KIND_GROUP = "group"
const KIND_COLLECTION = "collection"
const KIND_SUBSCRIPT = "subscript"
const KIND_PARAMETER_LIST = "parameter_list"
const KIND_PARAMETER = "parameter"
const KIND_DECLARATION = "declaration"
const KIND_TYPE = "type"
const KIND_COMMENT = "comment"


func build_candidates(text: String, current: SmartSelectionRange) -> Array[SmartSelectionRange]:
	var root = _build_tree(text)
	var path = _find_smallest_path(root, current)
	var candidates: Array[SmartSelectionRange] = []
	var lines = text.split("\n", true)

	for index in path.size():
		var node = path[index]
		if node.kind == KIND_FILE:
			continue
		for selection_range in _ranges_for_node(path, index, current, lines):
			_append_range(candidates, selection_range)

	return candidates


func _build_tree(text: String):
	var lines = text.split("\n", true)
	var last_line = maxi(lines.size() - 1, 0)
	var last_col = 0
	if not lines.is_empty():
		last_col = String(lines[last_line]).length()

	var root = _make_node(KIND_FILE, 0, 0, last_line, last_col)
	var container_stack: Array = [root]
	var collection_stack: Array = []
	var explicit_continuation_statement = null
	var active_comment = null
	var multiline_string_statement = null
	var multiline_string_literal = null

	for line_index in lines.size():
		var line = String(lines[line_index])
		var code_end = _line_code_end(line)
		var comment_start = _line_comment_start(line, code_end)
		var code_start = _line_indent_chars(line)
		while code_end > code_start and (line[code_end - 1] == " " or line[code_end - 1] == "\t"):
			code_end -= 1

		if _is_full_line_comment(line, code_start, comment_start):
			active_comment = _append_full_line_comment(line, line_index, code_start, comment_start, container_stack, collection_stack, active_comment)
			continue
		active_comment = null

		if code_start >= code_end:
			continue

		if multiline_string_statement != null:
			if _continue_multiline_string_statement(
				line,
				line_index,
				code_start,
				code_end,
				multiline_string_statement,
				multiline_string_literal,
				collection_stack
			):
				multiline_string_statement = null
				multiline_string_literal = null
			continue

		if _line_closes_collection(line, line_index, code_start, code_end, collection_stack):
			continue
		if _line_closes_brace_block(line, line_index, code_start, code_end, container_stack):
			continue

		var is_explicit_continuation = explicit_continuation_statement != null
		if not is_explicit_continuation:
			while container_stack.size() > 1:
				var top = container_stack.back()
				if code_start > int(top.data.get("indent", 0)):
					break
				container_stack.pop_back()

		var multiline_string_start = _multiline_string_start_col(line, code_start, code_end)
		if multiline_string_start != -1:
			var parent_for_multiline = container_stack.back()
			if not collection_stack.is_empty():
				parent_for_multiline = collection_stack.back()
			var multiline_statement = _make_node(KIND_STATEMENT, line_index, code_start, line_index, code_end)
			var string_literal = _make_node(KIND_STRING_LITERAL, line_index, multiline_string_start, line_index, code_end)
			_add_child(multiline_statement, string_literal)
			_add_child(parent_for_multiline, multiline_statement)
			multiline_string_statement = multiline_statement
			multiline_string_literal = string_literal
			continue

		var statement = _make_node(KIND_STATEMENT, line_index, code_start, line_index, code_end)
		for expression in _parse_line_nodes(line, line_index, code_start, code_end):
			_add_child(statement, expression)
		if comment_start != -1:
			_add_child(statement, _make_node(KIND_COMMENT, line_index, comment_start, line_index, _line_comment_end(line, comment_start)))

		var parent = explicit_continuation_statement
		if parent == null:
			parent = container_stack.back()
		if parent == null and not collection_stack.is_empty():
			parent = collection_stack.back()
		elif not is_explicit_continuation and not collection_stack.is_empty():
			parent = collection_stack.back()
		_add_child(parent, statement)

		var opened_collection = _find_unclosed_collection_node(statement)
		if opened_collection != null:
			opened_collection.data["owner_statement"] = statement
			collection_stack.append(opened_collection)
		_close_collection_stack_from_line(line, line_index, code_start, code_end, collection_stack)

		if not is_explicit_continuation and _starts_block(line, code_start, code_end):
			var block = _make_block_node(line, line_index, code_start, code_end, statement)
			_add_child(parent, block)
			container_stack.append(block)
		elif not is_explicit_continuation and _starts_brace_block(line, code_start, code_end):
			var brace_block = _make_brace_block_node(line, line_index, code_start, code_end, statement)
			_add_child(parent, brace_block)
			container_stack.append(brace_block)

		if _line_has_explicit_continuation(line, code_start, code_end):
			if explicit_continuation_statement == null:
				statement.data["explicit_continuation"] = true
				explicit_continuation_statement = statement
		elif is_explicit_continuation:
			explicit_continuation_statement = null

	_refresh_container_ranges(root)
	return root


func _parse_line_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array:
	var nodes: Array = []
	var stripped = line.substr(code_start, code_end - code_start)
	if stripped.begins_with("func "):
		return _parse_function_signature_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("signal "):
		return _parse_signal_signature_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("for "):
		return _parse_for_loop_nodes(line, line_index, code_start, code_end)
	if stripped.begins_with("extends ") or stripped.begins_with("class_name "):
		return _parse_class_declaration_nodes(line, line_index, code_start, code_end)

	var annotation_declaration = _parse_annotation_declaration_node(line, line_index, code_start, code_end)
	if annotation_declaration != null:
		nodes.append(annotation_declaration)

	var declaration = _parse_local_declaration_node(line, line_index, code_start, code_end)
	if declaration != null:
		nodes.append(declaration)

	var primary_start = _line_expression_start(line, code_start, code_end)
	var primary_end = _line_expression_end(line, primary_start, code_end)
	_append_top_level_expression_segments(nodes, line, line_index, primary_start, primary_end)
	if declaration == null:
		var assignment_col = _find_assignment_operator(line, code_start, code_end)
		if assignment_col != -1:
			var lhs_end = assignment_col
			while lhs_end > code_start and (line[lhs_end - 1] == " " or line[lhs_end - 1] == "\t"):
				lhs_end -= 1
			if code_start < lhs_end:
				var lhs_expression = _parse_expression_range(line, line_index, code_start, lhs_end)
				if lhs_expression != null:
					nodes.append(lhs_expression)

	var inline_start = _inline_statement_start(line, primary_end, code_end)
	if inline_start != -1:
		var inline_expression_start = _line_expression_start(line, inline_start, code_end)
		var inline_expression_end = _line_expression_end(line, inline_expression_start, code_end)
		var inline_statement = _make_node(KIND_INLINE_STATEMENT, line_index, inline_start, line_index, code_end)
		var inline_expressions: Array = []
		_append_top_level_expression_segments(inline_expressions, line, line_index, inline_expression_start, inline_expression_end)
		for inline_expression in inline_expressions:
			_add_child(inline_statement, inline_expression)
		nodes.append(inline_statement)

	return nodes


func _append_top_level_expression_segments(nodes: Array, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var segment_start = _skip_spaces(line, from_col)
	while segment_start < to_col:
		var comma_col = _find_top_level_char(line, segment_start, to_col, ",")
		var segment_end = comma_col if comma_col != -1 else to_col
		while segment_end > segment_start and (line[segment_end - 1] == " " or line[segment_end - 1] == "\t"):
			segment_end -= 1
		if segment_start < segment_end:
			var expression = _parse_expression_range(line, line_index, segment_start, segment_end)
			if expression != null:
				nodes.append(expression)
		if comma_col == -1:
			break
		segment_start = _skip_spaces(line, comma_col + 1)


func _parse_expression_range(line: String, line_index: int, expression_start: int, expression_end: int):
	if expression_start >= expression_end:
		return null
	var tokens = GDScriptTokenizer.tokenize_line(line, line_index, expression_start, expression_end)
	if tokens.is_empty():
		return null
	var expression: Dictionary = GDScriptExpressionParser.parse(tokens)
	if expression.is_empty():
		return null
	return _node_from_expression_dictionary(expression)


func _node_from_expression_dictionary(expression: Dictionary):
	var node = _make_node(
		String(expression.get("kind", "")),
		int(expression["from_line"]),
		int(expression["from_col"]),
		int(expression["to_line"]),
		int(expression["to_col"])
	)
	for key in ["operator", "close_text", "is_closed"]:
		if expression.has(key):
			node.data[key] = expression[key]
	for child in expression.get("children", []):
		_add_child(node, _node_from_expression_dictionary(child))
	return node


func _parse_function_signature_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array:
	var nodes: Array = []
	var name_start = _skip_spaces(line, code_start + 4)
	var name_end = name_start
	if name_start < code_end and _is_identifier_start_char(line[name_start]):
		name_end += 1
		while name_end < code_end and _is_identifier_char(line[name_end]):
			name_end += 1
		nodes.append(_make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var open_paren = _find_top_level_char(line, name_end, code_end, "(")
	if open_paren != -1:
		var close_paren = _find_matching_close_char(line, open_paren, code_end, "(", ")")
		if close_paren != -1:
			var parameter_list = _make_node(KIND_PARAMETER_LIST, line_index, open_paren, line_index, close_paren + 1)
			_add_function_parameter_nodes(parameter_list, line, line_index, open_paren + 1, close_paren)
			nodes.append(parameter_list)
			_append_function_return_type_node(nodes, line, line_index, close_paren + 1, code_end)
	return nodes


func _parse_signal_signature_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array:
	var nodes: Array = []
	var name_start = _skip_spaces(line, code_start + 6)
	var name_end = name_start
	if name_start < code_end and _is_identifier_start_char(line[name_start]):
		name_end += 1
		while name_end < code_end and _is_identifier_char(line[name_end]):
			name_end += 1
		nodes.append(_make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var open_paren = _find_top_level_char(line, name_end, code_end, "(")
	if open_paren != -1:
		var close_paren = _find_matching_close_char(line, open_paren, code_end, "(", ")")
		if close_paren != -1:
			var parameter_list = _make_node(KIND_PARAMETER_LIST, line_index, open_paren, line_index, close_paren + 1)
			_add_function_parameter_nodes(parameter_list, line, line_index, open_paren + 1, close_paren)
			nodes.append(parameter_list)
	return nodes


func _parse_class_declaration_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array:
	var nodes: Array = []
	var keyword_length = 0
	if line.substr(code_start, 8) == "extends ":
		keyword_length = 7
	elif line.substr(code_start, 11) == "class_name ":
		keyword_length = 10
	else:
		return nodes
	nodes.append(_make_node(KIND_IDENTIFIER, line_index, code_start, line_index, code_start + keyword_length))

	var target_start = _skip_spaces(line, code_start + keyword_length)
	var target_end = _line_expression_end(line, target_start, code_end)
	var target = _parse_expression_range(line, line_index, target_start, target_end)
	if target != null:
		nodes.append(target)
	return nodes


func _parse_annotation_declaration_node(line: String, line_index: int, code_start: int, code_end: int):
	if line[code_start] != "@":
		return null
	var keyword_start = _annotation_declaration_keyword_start(line, code_start, code_end)
	if keyword_start == -1:
		return null

	var keyword_length = 0
	if line.substr(keyword_start, 4) == "var ":
		keyword_length = 3
	elif line.substr(keyword_start, 6) == "const ":
		keyword_length = 5
	else:
		return null

	var name_start = _skip_spaces(line, keyword_start + keyword_length)
	if name_start >= code_end or not _is_identifier_start_char(line[name_start]):
		return null
	var name_end = name_start + 1
	while name_end < code_end and _is_identifier_char(line[name_end]):
		name_end += 1

	var name_declaration = _make_node(KIND_DECLARATION, line_index, name_start, line_index, code_end)
	_add_child(name_declaration, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))
	var keyword_declaration = _make_node(KIND_DECLARATION, line_index, keyword_start, line_index, code_end)
	_add_child(keyword_declaration, name_declaration)
	var annotation_declaration = _make_node(KIND_DECLARATION, line_index, code_start, line_index, code_end)
	_add_child(annotation_declaration, keyword_declaration)
	return annotation_declaration


func _annotation_declaration_keyword_start(line: String, from_col: int, to_col: int) -> int:
	var col = from_col
	while col < to_col:
		if line[col] != "@":
			return -1
		col += 1
		while col < to_col and (_is_identifier_char(line[col]) or line[col] == "."):
			col += 1
		if col < to_col and line[col] == "(":
			var close_col = _find_matching_close_char(line, col, to_col, "(", ")")
			if close_col == -1:
				return -1
			col = close_col + 1
		col = _skip_spaces(line, col)
		if line.substr(col, 4) == "var " or line.substr(col, 6) == "const ":
			return col
	return -1


func _parse_for_loop_nodes(line: String, line_index: int, code_start: int, code_end: int) -> Array:
	var nodes: Array = []
	var target_start = _skip_spaces(line, code_start + 3)
	var in_col = _find_top_level_word(line, target_start, code_end, "in")
	if in_col == -1:
		return nodes
	var target_end = in_col
	while target_end > target_start and (line[target_end - 1] == " " or line[target_end - 1] == "\t"):
		target_end -= 1
	if target_start < target_end and _is_identifier_start_char(line[target_start]):
		var target_name_end = target_start + 1
		while target_name_end < target_end and _is_identifier_char(line[target_name_end]):
			target_name_end += 1
		if target_name_end == target_end:
			nodes.append(_make_node(KIND_IDENTIFIER, line_index, target_start, line_index, target_end))

	var iterable_start = _skip_spaces(line, in_col + 2)
	var iterable_end = _line_expression_end(line, iterable_start, code_end)
	var iterable = _parse_expression_range(line, line_index, iterable_start, iterable_end)
	if iterable != null:
		nodes.append(iterable)
	return nodes


func _parse_local_declaration_node(line: String, line_index: int, code_start: int, code_end: int):
	var stripped = line.substr(code_start, code_end - code_start)
	var keyword_length = 0
	if stripped.begins_with("var "):
		keyword_length = 3
	elif stripped.begins_with("const "):
		keyword_length = 5
	else:
		return null

	var name_start = _skip_spaces(line, code_start + keyword_length)
	if name_start >= code_end or not _is_identifier_start_char(line[name_start]):
		return null
	var name_end = name_start + 1
	while name_end < code_end and _is_identifier_char(line[name_end]):
		name_end += 1

	var declaration_end = _find_assignment_operator(line, name_start, code_end)
	if declaration_end == -1:
		declaration_end = code_end
	while declaration_end > name_start and (line[declaration_end - 1] == " " or line[declaration_end - 1] == "\t"):
		declaration_end -= 1

	var declaration = _make_node(KIND_DECLARATION, line_index, name_start, line_index, declaration_end)
	_add_child(declaration, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))
	_add_declaration_type_node(declaration, line, line_index, name_start, declaration_end)
	return declaration


func _add_declaration_type_node(declaration, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var colon_col = _find_top_level_colon(line, from_col, to_col)
	if colon_col == -1:
		return
	var type_start = _skip_spaces(line, colon_col + 1)
	var type_end = to_col
	while type_end > type_start and (line[type_end - 1] == " " or line[type_end - 1] == "\t"):
		type_end -= 1
	if type_start >= type_end:
		return
	var type_node = _make_node(KIND_TYPE, line_index, type_start, line_index, type_end)
	var type_expression = _parse_expression_range(line, line_index, type_start, type_end)
	if type_expression != null:
		_add_child(type_node, type_expression)
	_add_child(declaration, type_node)


func _add_function_parameter_nodes(parameter_list, line: String, line_index: int, from_col: int, to_col: int) -> void:
	var parameter_start = _skip_spaces(line, from_col)
	while parameter_start < to_col:
		var comma_col = _find_top_level_char(line, parameter_start, to_col, ",")
		var parameter_end = comma_col if comma_col != -1 else to_col
		while parameter_end > parameter_start and (line[parameter_end - 1] == " " or line[parameter_end - 1] == "\t"):
			parameter_end -= 1
		if parameter_start < parameter_end:
			var parameter = _parse_parameter_node(line, line_index, parameter_start, parameter_end)
			if parameter != null:
				_add_child(parameter_list, parameter)
		if comma_col == -1:
			break
		parameter_start = _skip_spaces(line, comma_col + 1)


func _parse_parameter_node(line: String, line_index: int, from_col: int, to_col: int):
	var name_start = from_col
	if name_start >= to_col or not _is_identifier_start_char(line[name_start]):
		return null
	var name_end = name_start + 1
	while name_end < to_col and _is_identifier_char(line[name_end]):
		name_end += 1

	var parameter = _make_node(KIND_PARAMETER, line_index, from_col, line_index, to_col)
	_add_child(parameter, _make_node(KIND_IDENTIFIER, line_index, name_start, line_index, name_end))

	var type_col = _find_top_level_colon(line, name_end, to_col)
	var default_col = _find_assignment_operator(line, name_end, to_col)
	if type_col != -1 and (default_col == -1 or type_col < default_col):
		var type_start = _skip_spaces(line, type_col + 1)
		var type_end = default_col if default_col != -1 else to_col
		while type_end > type_start and (line[type_end - 1] == " " or line[type_end - 1] == "\t"):
			type_end -= 1
		if type_start < type_end:
			var type_node = _make_node(KIND_TYPE, line_index, type_start, line_index, type_end)
			var type_expression = _parse_expression_range(line, line_index, type_start, type_end)
			if type_expression != null:
				_add_child(type_node, type_expression)
			_add_child(parameter, type_node)

	if default_col != -1:
		var default_start = _skip_spaces(line, default_col + _assignment_operator_length_at(line, default_col))
		var default_expression = _parse_expression_range(line, line_index, default_start, to_col)
		if default_expression != null:
			_add_child(parameter, default_expression)
	return parameter


func _append_function_return_type_node(nodes: Array, line: String, line_index: int, from_col: int, code_end: int) -> void:
	var arrow_col = _find_top_level_text(line, from_col, code_end, "->")
	if arrow_col == -1:
		return
	var type_start = _skip_spaces(line, arrow_col + 2)
	var type_end = _line_expression_end(line, type_start, code_end)
	if type_start >= type_end:
		return
	var type_node = _make_node(KIND_TYPE, line_index, arrow_col, line_index, type_end)
	var type_expression = _parse_expression_range(line, line_index, type_start, type_end)
	if type_expression != null:
		_add_child(type_node, type_expression)
	nodes.append(type_node)


func _ranges_for_node(path: Array, index: int, current: SmartSelectionRange, lines: Array) -> Array[SmartSelectionRange]:
	var node = path[index]
	var ranges: Array[SmartSelectionRange] = []
	if _is_member_left_prefix_to_skip(path, index, current):
		return ranges
	if _is_call_callee_member_to_skip(path, index, current):
		return ranges
	if _is_collection_value_inline_statement_to_skip(path, index):
		return ranges

	if node.kind == KIND_CALL:
		if not _is_await_operand_call(path, index):
			_append_range(ranges, _call_arguments_content_range(node, current))
		_append_range(ranges, _call_suffix_range_for_arguments(node, current))
		if _is_call_followed_by_member(path, index) or _is_member_call_callee_selected(node, current):
			_append_range(ranges, _call_suffix_range_for_callee(node, current))
			_append_range(ranges, _call_callee_range_for_selected_member_call(node, current))
	if node.kind == KIND_BINARY:
		_append_range(ranges, _binary_left_operand_range_for_right(node, current))
	if node.kind == KIND_STATEMENT:
		_append_range(ranges, _statement_expression_range(node, current))
	if node.kind == KIND_PARAMETER:
		_append_range(ranges, _parameter_type_default_range(node, current))
	if node.kind == KIND_PARAMETER_LIST:
		_append_range(ranges, _parameter_list_content_range(node, current))
	if [KIND_BLOCK, KIND_FUNCTION].has(node.kind):
		_append_range(ranges, _conditional_chain_range_for_path(path, index, lines, current))
		_append_range(ranges, _block_body_range(node, current))
	_append_range(ranges, _node_selection_range(node, current))
	if index == 0:
		_append_range(ranges, _member_suffix_range_for_path(path, current))
	return ranges


func _find_smallest_path(root, current: SmartSelectionRange) -> Array:
	if not _node_contains_range(root, current):
		return []
	var best_child_path: Array = []
	for child in root.children:
		var child_path = _find_smallest_path(child, current)
		if not child_path.is_empty():
			if (
				best_child_path.is_empty()
				or child_path[0].range_size() < best_child_path[0].range_size()
				or (
					child_path[0].range_size() == best_child_path[0].range_size()
					and child_path.size() > best_child_path.size()
				)
			):
				best_child_path = child_path
	if best_child_path.is_empty():
		return [root]
	best_child_path.append(root)
	return best_child_path


func _node_contains_range(node, selection_range: SmartSelectionRange) -> bool:
	if node.kind == KIND_STATEMENT and _is_caret_in_statement_indent(node, selection_range):
		return true
	return node.contains(selection_range)


func _member_suffix_range_for_path(path: Array, current: SmartSelectionRange) -> SmartSelectionRange:
	var chain = _member_chain_info_for_path(path, current)
	if chain.is_empty():
		return null
	var segments: Array = chain["segments"]
	var segment_index = int(chain["segment_index"])
	var top_member = chain["top_member"]
	var suffix_start_index = segment_index
	if segment_index == segments.size() - 1:
		suffix_start_index = segment_index - 1
	if suffix_start_index <= 0:
		return null
	var first_segment = segments[suffix_start_index]
	return SmartSelectionRange.create(
		first_segment.selection_range.from_line,
		first_segment.selection_range.from_col,
		top_member.selection_range.to_line,
		top_member.selection_range.to_col
	)


func _is_member_left_prefix_to_skip(path: Array, index: int, current: SmartSelectionRange) -> bool:
	var node = path[index]
	if node.kind != KIND_MEMBER:
		return false
	var chain = _member_chain_info_for_path(path, current)
	if chain.is_empty():
		return false
	var segment_index = int(chain["segment_index"])
	if segment_index <= 0:
		return false
	var segments: Array = chain["segments"]
	if segment_index >= segments.size():
		return false
	var selected_segment = segments[segment_index]
	var top_member = chain["top_member"]
	return (
		_compare_positions(
			node.selection_range.to_line,
			node.selection_range.to_col,
			selected_segment.selection_range.to_line,
			selected_segment.selection_range.to_col
		) == 0
		and _compare_positions(
			node.selection_range.to_line,
			node.selection_range.to_col,
			top_member.selection_range.to_line,
			top_member.selection_range.to_col
		) < 0
	)


func _is_call_callee_member_to_skip(path: Array, index: int, current: SmartSelectionRange) -> bool:
	var node = path[index]
	if node.kind != KIND_MEMBER:
		return false
	if index + 1 >= path.size():
		return false
	var parent = path[index + 1]
	if parent.kind != KIND_CALL:
		return false
	if parent.children.is_empty() or parent.children[0] != node:
		return false
	var member_segments = _flatten_member_segments(node)
	if member_segments.is_empty():
		return false
	if index + 2 < path.size() and path[index + 2].kind == KIND_MEMBER:
		return true
	var chain = _member_chain_info_for_path(path, current)
	return not chain.is_empty() and int(chain["segment_index"]) == member_segments.size() - 1


func _member_chain_info_for_path(path: Array, current: SmartSelectionRange) -> Dictionary:
	if path.is_empty():
		return {}
	var top_member = null
	for node in path:
		if node.kind == KIND_MEMBER:
			top_member = node
	if top_member == null:
		return {}
	var segments = _flatten_member_segments(top_member)
	var segment_index = -1
	var selected_node = path[0]
	for index in segments.size():
		var segment = segments[index]
		if segment == selected_node or segment.contains(current):
			segment_index = index
			break
	if segment_index == -1:
		return {}
	return {
		"top_member": top_member,
		"segments": segments,
		"segment_index": segment_index,
	}


func _flatten_member_segments(node) -> Array:
	if node.kind != KIND_MEMBER:
		return [node]
	if node.children.size() < 2:
		return [node]
	var result: Array = []
	result.append_array(_flatten_member_segments(node.children[0]))
	result.append_array(_flatten_member_segments(node.children[1]))
	return result


func _is_call_followed_by_member(path: Array, index: int) -> bool:
	return index + 1 < path.size() and path[index + 1].kind == KIND_MEMBER


func _is_member_call_callee_selected(call, current: SmartSelectionRange) -> bool:
	if call.children.is_empty():
		return false
	var callee = call.children[0]
	if callee.kind != KIND_MEMBER:
		return false
	var callee_segments = _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return false
	return callee_segments.back().contains(current)


func _is_collection_value_inline_statement_to_skip(path: Array, index: int) -> bool:
	var node = path[index]
	if node.kind != KIND_INLINE_STATEMENT:
		return false
	if node.children.size() != 1:
		return false
	var child = node.children[0]
	return (
		node.selection_range.from_line == child.selection_range.from_line
		and node.selection_range.from_col == child.selection_range.from_col
		and node.selection_range.to_line == child.selection_range.to_line
		and node.selection_range.to_col == child.selection_range.to_col + 1
	)


func _is_await_operand_call(path: Array, index: int) -> bool:
	if path[index].kind != KIND_CALL:
		return false
	if index + 1 >= path.size():
		return false
	var parent = path[index + 1]
	return parent.kind == KIND_UNARY and String(parent.data.get("operator", "")) == "await"


func _call_callee_range_for_selected_member_call(call, current: SmartSelectionRange) -> SmartSelectionRange:
	if not _is_member_call_callee_selected(call, current):
		return null
	if call.children.size() < 2:
		return null
	return call.children[0].selection_range.duplicate_range()


func _call_suffix_range_for_arguments(call, current: SmartSelectionRange) -> SmartSelectionRange:
	if call.children.size() < 2:
		return null
	var callee = call.children[0]
	if callee.contains(current):
		return null
	var argument_content = _call_arguments_content_selection_range(call)
	if argument_content == null or not argument_content.contains_or_equal(current):
		return null
	var callee_segments = _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return null
	var method_segment = callee_segments.back()
	return SmartSelectionRange.create(
		method_segment.selection_range.from_line,
		method_segment.selection_range.from_col,
		call.selection_range.to_line,
		call.selection_range.to_col
	)


func _call_suffix_range_for_callee(call, current: SmartSelectionRange) -> SmartSelectionRange:
	if call.children.is_empty():
		return null
	var callee = call.children[0]
	if callee.kind != KIND_MEMBER:
		return null
	var callee_segments = _flatten_member_segments(callee)
	if callee_segments.size() < 2:
		return null
	var method_segment = callee_segments.back()
	if not method_segment.contains(current):
		return null
	return SmartSelectionRange.create(
		method_segment.selection_range.from_line,
		method_segment.selection_range.from_col,
		call.selection_range.to_line,
		call.selection_range.to_col
	)


func _call_arguments_content_range(call, current: SmartSelectionRange) -> SmartSelectionRange:
	if call.children.size() < 3:
		return null
	var argument_content = _call_arguments_content_selection_range(call)
	if argument_content == null or not argument_content.contains_or_equal(current):
		return null
	return argument_content


func _call_arguments_content_selection_range(call) -> SmartSelectionRange:
	if call.children.size() < 2:
		return null
	var first_argument = call.children[1]
	var last_argument = call.children.back()
	return SmartSelectionRange.create(
		first_argument.selection_range.from_line,
		first_argument.selection_range.from_col,
		last_argument.selection_range.to_line,
		last_argument.selection_range.to_col
	)


func _parameter_type_default_range(parameter, current: SmartSelectionRange) -> SmartSelectionRange:
	var type_node = null
	var default_node = null
	for child in parameter.children:
		if child.kind == KIND_TYPE:
			type_node = child
		elif type_node != null and child.kind != KIND_IDENTIFIER:
			default_node = child
	if type_node == null or default_node == null:
		return null
	if not default_node.contains(current):
		return null
	return SmartSelectionRange.create(
		type_node.selection_range.from_line,
		type_node.selection_range.from_col,
		default_node.selection_range.to_line,
		default_node.selection_range.to_col
	)


func _binary_left_operand_range_for_right(binary, current: SmartSelectionRange) -> SmartSelectionRange:
	if String(binary.data.get("operator", "")) != "%":
		return null
	if binary.children.size() < 2:
		return null
	var right = binary.children[1]
	if not right.contains(current):
		return null
	return binary.children[0].selection_range.duplicate_range()


func _statement_expression_range(statement, current: SmartSelectionRange) -> SmartSelectionRange:
	if statement.children.is_empty():
		return null
	var first_child = statement.children[0]
	if bool(statement.data.get("has_rhs_expression", false)):
		var rhs_range: SmartSelectionRange = first_child.selection_range
		if rhs_range.equals(statement.selection_range):
			return null
		if not rhs_range.contains_or_equal(current):
			return null
		return rhs_range.duplicate_range()
	if not bool(statement.data.get("explicit_continuation", false)):
		return null
	var expression_range: SmartSelectionRange = SmartSelectionRange.create(
		first_child.selection_range.from_line,
		first_child.selection_range.from_col,
		statement.selection_range.to_line,
		statement.selection_range.to_col
	)
	if expression_range.equals(statement.selection_range):
		return null
	if not expression_range.contains_or_equal(current):
		return null
	return expression_range


func _parameter_list_content_range(parameter_list, current: SmartSelectionRange) -> SmartSelectionRange:
	if parameter_list.children.is_empty():
		return null
	var content = SmartSelectionRange.create(
		parameter_list.children[0].selection_range.from_line,
		parameter_list.children[0].selection_range.from_col,
		parameter_list.children.back().selection_range.to_line,
		parameter_list.children.back().selection_range.to_col
	)
	if content.equals(parameter_list.selection_range):
		return null
	if not content.contains_or_equal(current):
		return null
	return content


func _conditional_chain_range_for_path(path: Array, index: int, lines: Array, current: SmartSelectionRange) -> SmartSelectionRange:
	var block = path[index]
	var keyword = _block_header_keyword(block, lines)
	if not ["if", "elif", "else"].has(keyword):
		return null
	var chain_start = block
	var chain_end = block
	if index + 1 < path.size():
		var parent = path[index + 1]
		var siblings: Array = parent.children
		var block_index = siblings.find(block)
		if block_index != -1:
			var scan = block_index
			while scan > 0:
				var previous = siblings[scan - 1]
				if not [KIND_BLOCK, KIND_FUNCTION].has(previous.kind):
					scan -= 1
					continue
				var previous_keyword = _block_header_keyword(previous, lines)
				if previous_keyword == "if" or previous_keyword == "elif":
					chain_start = previous
					scan -= 1
					continue
				break
			scan = block_index + 1
			while scan < siblings.size():
				var next = siblings[scan]
				if not [KIND_BLOCK, KIND_FUNCTION].has(next.kind):
					scan += 1
					continue
				var next_keyword = _block_header_keyword(next, lines)
				if next_keyword == "elif" or next_keyword == "else":
					chain_end = next
					scan += 1
					continue
				break
	if chain_start == block and chain_end == block:
		return null
	var chain_range = SmartSelectionRange.create(
		chain_start.selection_range.from_line,
		chain_start.selection_range.from_col,
		chain_end.selection_range.to_line,
		chain_end.selection_range.to_col
	)
	if not chain_range.contains_or_equal(current):
		return null
	return chain_range


func _block_body_range(block, current: SmartSelectionRange) -> SmartSelectionRange:
	if block.children.size() <= 1:
		return null
	var body_children = block.children.slice(1)
	var first_body = body_children[0]
	var last_body = body_children.back()
	var body = SmartSelectionRange.create(
		first_body.selection_range.from_line,
		first_body.selection_range.from_col,
		last_body.selection_range.to_line,
		last_body.selection_range.to_col
	)
	if body.equals(block.selection_range):
		return null
	if not body.contains_or_equal(current):
		return null
	return body


func _block_header_keyword(block, lines: Array) -> String:
	if block.selection_range.from_line < 0 or block.selection_range.from_line >= lines.size():
		return ""
	var line = String(lines[block.selection_range.from_line])
	var from_col = block.selection_range.from_col
	if _line_begins_with_keyword(line, from_col, "if"):
		return "if"
	if _line_begins_with_keyword(line, from_col, "elif"):
		return "elif"
	if _line_begins_with_keyword(line, from_col, "else"):
		return "else"
	return ""


func _node_selection_range(node, current: SmartSelectionRange) -> SmartSelectionRange:
	var selection_range: SmartSelectionRange = node.selection_range.duplicate_range()
	if node.kind == KIND_STATEMENT and _is_caret_in_statement_indent(node, current):
		selection_range.from_col = current.from_col
	return selection_range


func _append_range(ranges: Array[SmartSelectionRange], selection_range: SmartSelectionRange) -> void:
	if selection_range == null:
		return
	for existing in ranges:
		if existing.equals(selection_range):
			return
	ranges.append(selection_range)


func _ranges_overlap(a: SmartSelectionRange, b: SmartSelectionRange) -> bool:
	return (
		_compare_positions(a.from_line, a.from_col, b.to_line, b.to_col) < 0
		and _compare_positions(b.from_line, b.from_col, a.to_line, a.to_col) < 0
	)


func _make_node(kind: String, from_line: int, from_col: int, to_line: int, to_col: int):
	return GDScriptSyntaxNode.create(kind, from_line, from_col, to_line, to_col)


func _add_child(parent, child) -> void:
	if parent == null or child == null:
		return
	parent.add_child(child)
	if _node_range_can_grow_from_children(parent):
		if _compare_positions(
			parent.selection_range.to_line,
			parent.selection_range.to_col,
			child.selection_range.to_line,
			child.selection_range.to_col
		) < 0:
			parent.selection_range.to_line = child.selection_range.to_line
			parent.selection_range.to_col = child.selection_range.to_col


func _refresh_container_ranges(node) -> void:
	for child in node.children:
		_refresh_container_ranges(child)
	if not _node_range_can_grow_from_children(node):
		return
	for child in node.children:
		if _compare_positions(
			node.selection_range.to_line,
			node.selection_range.to_col,
			child.selection_range.to_line,
			child.selection_range.to_col
		) < 0:
			node.selection_range.to_line = child.selection_range.to_line
			node.selection_range.to_col = child.selection_range.to_col


func _node_range_can_grow_from_children(node) -> bool:
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
	].has(node.kind)


func _line_closes_collection(line: String, line_index: int, code_start: int, code_end: int, collection_stack: Array) -> bool:
	if collection_stack.is_empty():
		return false
	var top = collection_stack.back()
	var close_text = String(top.data.get("close_text", ""))
	if close_text.is_empty() or line[code_start] != close_text:
		return false
	top.selection_range.to_line = line_index
	top.selection_range.to_col = code_start + 1
	top.data["is_closed"] = true
	if top.data.has("owner_statement"):
		var owner_statement = top.data["owner_statement"]
		owner_statement.selection_range.to_line = line_index
		owner_statement.selection_range.to_col = code_end
	if top.data.has("close_owner"):
		var close_owner = top.data["close_owner"]
		close_owner.selection_range.to_line = line_index
		close_owner.selection_range.to_col = code_end
	collection_stack.pop_back()
	return true


func _close_collection_stack_from_line(line: String, line_index: int, code_start: int, code_end: int, collection_stack: Array) -> void:
	while not collection_stack.is_empty():
		var top = collection_stack.back()
		var close_text = String(top.data.get("close_text", ""))
		if close_text.is_empty():
			return
		var close_col = _find_top_level_collection_close(line, code_start, code_end, close_text)
		if close_col == -1:
			return
		top.selection_range.to_line = line_index
		top.selection_range.to_col = close_col + close_text.length()
		top.data["is_closed"] = true
		if top.data.has("owner_statement"):
			var owner_statement = top.data["owner_statement"]
			owner_statement.selection_range.to_line = line_index
			owner_statement.selection_range.to_col = code_end
		if top.data.has("close_owner"):
			var close_owner = top.data["close_owner"]
			close_owner.selection_range.to_line = line_index
			close_owner.selection_range.to_col = close_col + close_text.length()
		collection_stack.pop_back()


func _find_unclosed_collection_node(node, parent = null):
	var result = null
	for child in node.children:
		var nested = _find_unclosed_collection_node(child, node)
		if nested != null:
			result = nested
	if result == null and [KIND_CALL, KIND_SUBSCRIPT, KIND_COLLECTION, KIND_GROUP].has(node.kind) and not bool(node.data.get("is_closed", true)):
		if parent != null:
			node.data["close_owner"] = parent
		result = node
	return result


func _make_block_node(line: String, line_index: int, code_start: int, code_end: int, header_statement):
	var kind = KIND_BLOCK
	if line.substr(code_start, code_end - code_start).begins_with("func "):
		kind = KIND_FUNCTION
	var block = _make_node(kind, line_index, code_start, line_index, code_end)
	block.data["indent"] = code_start
	_add_child(block, header_statement.duplicate_tree())
	return block


func _make_brace_block_node(line: String, line_index: int, code_start: int, code_end: int, header_statement):
	var block = _make_node(KIND_BLOCK, line_index, code_start, line_index, code_end)
	block.data["indent"] = code_start
	block.data["close_text"] = "}"
	_add_child(block, header_statement.duplicate_tree())
	return block


func _line_closes_brace_block(line: String, line_index: int, code_start: int, code_end: int, container_stack: Array) -> bool:
	if container_stack.size() <= 1:
		return false
	var top = container_stack.back()
	var close_text = String(top.data.get("close_text", ""))
	if close_text.is_empty() or line[code_start] != close_text:
		return false
	top.selection_range.to_line = line_index
	top.selection_range.to_col = code_end
	container_stack.pop_back()
	return true


func _append_full_line_comment(line: String, line_index: int, code_start: int, comment_start: int, container_stack: Array, collection_stack: Array, active_comment):
	var comment_end = _line_comment_end(line, comment_start)
	if active_comment != null and active_comment.selection_range.to_line == line_index - 1:
		active_comment.selection_range.to_line = line_index
		active_comment.selection_range.to_col = comment_end
		return active_comment
	var parent = container_stack.back()
	if not collection_stack.is_empty():
		parent = collection_stack.back()
	var comment = _make_node(KIND_COMMENT, line_index, comment_start, line_index, comment_end)
	_add_child(parent, comment)
	return comment


func _continue_multiline_string_statement(line: String, line_index: int, code_start: int, code_end: int, statement, string_literal, collection_stack: Array) -> bool:
	var close_col = _multiline_string_close_col(line, code_start, code_end)
	if close_col == -1:
		string_literal.selection_range.to_line = line_index
		string_literal.selection_range.to_col = code_end
		statement.selection_range.to_line = line_index
		statement.selection_range.to_col = code_end
		return false
	var string_end = close_col + 3
	string_literal.selection_range.to_line = line_index
	string_literal.selection_range.to_col = string_end
	statement.selection_range.to_line = line_index
	statement.selection_range.to_col = code_end
	var percent_col = _find_top_level_char(line, string_end, code_end, "%")
	if percent_col == -1:
		return true
	var array_open_col = _find_top_level_char(line, percent_col + 1, code_end, "[")
	if array_open_col == -1:
		return true
	var left_end = percent_col
	while left_end > string_end and (line[left_end - 1] == " " or line[left_end - 1] == "\t"):
		left_end -= 1
	var left_expression = _make_node(
		KIND_STRING_LITERAL,
		string_literal.selection_range.from_line,
		string_literal.selection_range.from_col,
		line_index,
		left_end
	)
	_add_child(left_expression, string_literal)
	var collection = _make_node(KIND_COLLECTION, line_index, array_open_col, line_index, array_open_col + 1)
	collection.data["close_text"] = "]"
	collection.data["is_closed"] = false
	collection.data["owner_statement"] = statement
	var binary = _make_node(KIND_BINARY, left_expression.selection_range.from_line, left_expression.selection_range.from_col, line_index, array_open_col + 1)
	binary.data["operator"] = "%"
	_add_child(binary, left_expression)
	_add_child(binary, collection)
	collection.data["close_owner"] = binary
	statement.children = []
	statement.data["has_rhs_expression"] = true
	_add_child(statement, binary)
	collection_stack.append(collection)
	return true


func _is_full_line_comment(line: String, code_start: int, comment_start: int) -> bool:
	return comment_start != -1 and code_start == comment_start


func _line_comment_start(line: String, code_end: int) -> int:
	if code_end < line.length() and line[code_end] == "#":
		return code_end
	return -1


func _line_comment_end(line: String, comment_start: int) -> int:
	return line.length()


func _line_indent_chars(line: String) -> int:
	var count = 0
	for col in line.length():
		if line[col] == " " or line[col] == "\t":
			count += 1
		else:
			break
	return count


func _line_code_end(line: String) -> int:
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in line.length():
		var ch = line[col]
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


func _line_expression_start(line: String, code_start: int, code_end: int) -> int:
	var stripped = line.substr(code_start, code_end - code_start)
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
	var assignment_col = _find_assignment_operator(line, code_start, code_end)
	if assignment_col != -1:
		return _skip_spaces(line, assignment_col + _assignment_operator_length_at(line, assignment_col))
	return code_start


func _line_expression_end(line: String, expression_start: int, code_end: int) -> int:
	var expression_end = _line_without_explicit_continuation_end(line, expression_start, code_end)
	var colon_col = _find_top_level_colon(line, expression_start, expression_end)
	if colon_col != -1:
		return colon_col
	return expression_end


func _line_has_explicit_continuation(line: String, from_col: int, code_end: int) -> bool:
	return _line_without_explicit_continuation_end(line, from_col, code_end) < code_end


func _line_without_explicit_continuation_end(line: String, from_col: int, code_end: int) -> int:
	if code_end <= from_col:
		return code_end
	if line[code_end - 1] != "\\":
		return code_end
	var expression_end = code_end - 1
	while expression_end > from_col and (line[expression_end - 1] == " " or line[expression_end - 1] == "\t"):
		expression_end -= 1
	return expression_end


func _multiline_string_start_col(line: String, code_start: int, code_end: int) -> int:
	var double_quote_start = line.find("\"\"\"", code_start)
	var single_quote_start = line.find("'''", code_start)
	var result = -1
	if double_quote_start != -1 and double_quote_start < code_end:
		result = double_quote_start
	if single_quote_start != -1 and single_quote_start < code_end and (result == -1 or single_quote_start < result):
		result = single_quote_start
	if result == -1:
		return -1
	var quote_text = line.substr(result, 3)
	var close_col = line.find(quote_text, result + 3)
	if close_col != -1 and close_col < code_end:
		return -1
	return result


func _multiline_string_close_col(line: String, from_col: int, to_col: int) -> int:
	var double_quote_close = line.find("\"\"\"", from_col)
	var single_quote_close = line.find("'''", from_col)
	var result = -1
	if double_quote_close != -1 and double_quote_close < to_col:
		result = double_quote_close
	if single_quote_close != -1 and single_quote_close < to_col and (result == -1 or single_quote_close < result):
		result = single_quote_close
	return result


func _inline_statement_start(line: String, from_col: int, code_end: int) -> int:
	var colon_col = _find_top_level_colon(line, from_col, code_end)
	if colon_col == -1:
		return -1
	return _skip_spaces(line, colon_col + 1)


func _starts_block(line: String, code_start: int, code_end: int) -> bool:
	var colon_col = _find_top_level_colon(line, code_start, code_end)
	if colon_col == -1:
		return false
	return _skip_spaces(line, colon_col + 1) >= code_end


func _starts_brace_block(line: String, code_start: int, code_end: int) -> bool:
	var stripped = line.substr(code_start, code_end - code_start)
	if not stripped.begins_with("enum"):
		return false
	var after_keyword_col = code_start + 4
	if after_keyword_col < code_end and _is_identifier_char(line[after_keyword_col]):
		return false
	var open_brace_col = _find_top_level_char(line, after_keyword_col, code_end, "{")
	if open_brace_col == -1:
		return false
	return _skip_spaces(line, open_brace_col + 1) >= code_end


func _skip_spaces(line: String, col: int) -> int:
	while col < line.length() and (line[col] == " " or line[col] == "\t"):
		col += 1
	return col


func _find_top_level_colon(line: String, from_col: int, to_col: int) -> int:
	return _find_top_level_char(line, from_col, to_col, ":")


func _find_top_level_char(line: String, from_col: int, to_col: int, target: String) -> int:
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(from_col, to_col):
		var ch = line[col]
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
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(from_col, to_col):
		var ch = line[col]
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
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(from_col, to_col):
		var ch = line[col]
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
			var before_ok = col == 0 or not _is_identifier_char(line[col - 1])
			var after_col = col + target.length()
			var after_ok = after_col >= to_col or not _is_identifier_char(line[after_col])
			if before_ok and after_ok:
				return col
	return -1


func _find_matching_close_char(line: String, open_col: int, to_col: int, open_text: String, close_text: String) -> int:
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(open_col, to_col):
		var ch = line[col]
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


func _find_top_level_collection_close(line: String, from_col: int, to_col: int, close_text: String) -> int:
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(from_col, to_col):
		var ch = line[col]
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


func _find_assignment_operator(line: String, from_col: int, to_col: int) -> int:
	var depth = 0
	var in_string = false
	var quote = ""
	var escaped = false
	for col in range(from_col, to_col):
		var ch = line[col]
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


func _is_caret_in_statement_indent(node, selection_range: SmartSelectionRange) -> bool:
	if not selection_range.is_zero_width():
		return false
	if selection_range.from_line != node.selection_range.from_line:
		return false
	if selection_range.from_col > node.selection_range.from_col:
		return false
	return selection_range.from_col >= 0


func _line_begins_with_keyword(line: String, from_col: int, keyword: String) -> bool:
	if line.substr(from_col, keyword.length()) != keyword:
		return false
	var after_keyword_col = from_col + keyword.length()
	if after_keyword_col >= line.length():
		return true
	return not _is_identifier_char(line[after_keyword_col])


func _compare_positions(line_a: int, col_a: int, line_b: int, col_b: int) -> int:
	return SmartSelectionRange.compare_positions(line_a, col_a, line_b, col_b)


func _is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


func _is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)
