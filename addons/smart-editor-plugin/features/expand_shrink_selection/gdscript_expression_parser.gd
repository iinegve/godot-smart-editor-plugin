@tool
extends RefCounted

const KIND_IDENTIFIER := "identifier"
const KIND_LITERAL := "literal"
const KIND_STRING_CONTENT := "string_content"
const KIND_STRING_LITERAL := "string_literal"
const KIND_MEMBER := "member_access"
const KIND_CALL := "call"
const KIND_BINARY := "binary"
const KIND_UNARY := "unary"
const KIND_GROUP := "group"
const KIND_COLLECTION := "collection"
const KIND_SUBSCRIPT := "subscript"
const KIND_SPECIAL_IDENTIFIER := "special_identifier"

const BINARY_PRECEDENCE := {
	"or": 1,
	"||": 1,
	"and": 2,
	"&&": 2,
	"in": 3,
	"is": 3,
	"==": 4,
	"!=": 4,
	"<": 4,
	"<=": 4,
	">": 4,
	">=": 4,
	"|": 5,
	"^": 6,
	"&": 7,
	"<<": 8,
	">>": 8,
	"+": 9,
	"-": 9,
	"*": 10,
	"/": 10,
	"%": 10,
	"**": 11,
}

var _tokens: Array[Dictionary] = []
var _pos := 0


static func parse(tokens: Array[Dictionary]) -> Dictionary:
	var parser := new()
	parser._tokens = tokens
	return parser._parse_expression(1)


func _parse_expression(min_precedence: int) -> Dictionary:
	var left := _parse_prefix()
	if left.is_empty():
		return {}

	while not _is_at_end():
		var token := _peek()
		var op := String(token["text"])
		if not BINARY_PRECEDENCE.has(op):
			break

		var precedence := int(BINARY_PRECEDENCE[op])
		if precedence < min_precedence:
			break

		_advance()
		var next_min_precedence := precedence + 1
		if op == "**":
			next_min_precedence = precedence
		var right := _parse_expression(next_min_precedence)
		if right.is_empty():
			break

		var binary := _make_node(KIND_BINARY, left["from_line"], left["from_col"], right["to_line"], right["to_col"])
		binary["operator"] = op
		_add_child(binary, left)
		_add_child(binary, right)
		left = binary

	return left


func _parse_prefix() -> Dictionary:
	if _is_at_end():
		return {}

	var token := _advance()
	var text := String(token["text"])
	var node := {}

	if ["+", "-", "!", "not", "await"].has(text):
		var operand := _parse_expression(11)
		if operand.is_empty():
			node = _make_node(KIND_LITERAL, token["line"], token["from_col"], token["line"], token["to_col"])
		else:
			node = _make_node(KIND_UNARY, token["line"], token["from_col"], operand["to_line"], operand["to_col"])
			node["operator"] = text
			_add_child(node, operand)
	elif token["type"] == "identifier":
		node = _make_node(KIND_IDENTIFIER, token["line"], token["from_col"], token["line"], token["to_col"])
	elif token["type"] == "literal":
		node = _make_node(KIND_LITERAL, token["line"], token["from_col"], token["line"], token["to_col"])
	elif token["type"] == "string":
		node = _make_string_node(token)
	elif text == "(":
		node = _parse_group(")")
	elif text == "[":
		node = _parse_collection("]")
	elif text == "{":
		node = _parse_collection("}")
	elif ["$", "%"].has(text) and not _is_at_end() and _peek()["type"] == "identifier":
		node = _parse_special_identifier(token)
	else:
		node = _make_node(KIND_LITERAL, token["line"], token["from_col"], token["line"], token["to_col"])

	return _parse_postfix(node)


func _parse_special_identifier(prefix_token: Dictionary) -> Dictionary:
	var identifier_token := _advance()
	var identifier := _make_node(
		KIND_IDENTIFIER,
		identifier_token["line"],
		identifier_token["from_col"],
		identifier_token["line"],
		identifier_token["to_col"]
	)
	var special := _make_node(
		KIND_SPECIAL_IDENTIFIER,
		prefix_token["line"],
		prefix_token["from_col"],
		identifier["to_line"],
		identifier["to_col"]
	)
	_add_child(special, identifier)
	return special


func _parse_postfix(node: Dictionary) -> Dictionary:
	var current := node

	while not _is_at_end():
		var token := _peek()
		var text := String(token["text"])

		if text == ".":
			_advance()
			if _is_at_end() or _peek()["type"] != "identifier":
				return current
			var member_token := _advance()
			var member := _make_node(KIND_IDENTIFIER, member_token["line"], member_token["from_col"], member_token["line"], member_token["to_col"])
			var access := _make_node(KIND_MEMBER, current["from_line"], current["from_col"], member["to_line"], member["to_col"])
			_add_child(access, current)
			_add_child(access, member)
			current = access
			continue

		if text == "(":
			current = _parse_call(current)
			continue

		if text == "[":
			current = _parse_subscript(current)
			continue

		break

	return current


func _parse_call(callee: Dictionary) -> Dictionary:
	var open_token := _advance()
	var call := _make_node(KIND_CALL, callee["from_line"], callee["from_col"], open_token["line"], open_token["to_col"])
	call["close_text"] = ")"
	call["is_closed"] = false
	_add_child(call, callee)

	while not _is_at_end() and String(_peek()["text"]) != ")":
		if String(_peek()["text"]) == ",":
			_advance()
			continue
		var argument := _parse_expression(1)
		if argument.is_empty():
			break
		_add_child(call, argument)
		if not _is_at_end() and String(_peek()["text"]) == ",":
			_advance()

	if not _is_at_end() and String(_peek()["text"]) == ")":
		var close_token := _advance()
		call["to_line"] = close_token["line"]
		call["to_col"] = close_token["to_col"]
		call["is_closed"] = true

	return call


func _parse_subscript(base: Dictionary) -> Dictionary:
	var open_token := _advance()
	var subscript := _make_node(KIND_SUBSCRIPT, base["from_line"], base["from_col"], open_token["line"], open_token["to_col"])
	subscript["close_text"] = "]"
	subscript["is_closed"] = false
	_add_child(subscript, base)

	while not _is_at_end() and String(_peek()["text"]) != "]":
		if String(_peek()["text"]) == ",":
			_advance()
			continue
		var index := _parse_expression(1)
		if index.is_empty():
			break
		_add_child(subscript, index)

	if not _is_at_end() and String(_peek()["text"]) == "]":
		var close_token := _advance()
		subscript["to_line"] = close_token["line"]
		subscript["to_col"] = close_token["to_col"]
		subscript["is_closed"] = true

	return subscript


func _parse_group(close_text: String) -> Dictionary:
	var open_token := _previous()
	var group := _make_node(KIND_GROUP, open_token["line"], open_token["from_col"], open_token["line"], open_token["to_col"])
	group["close_text"] = close_text
	group["is_closed"] = false

	if not _is_at_end() and String(_peek()["text"]) != close_text:
		var inner := _parse_expression(1)
		if not inner.is_empty():
			_add_child(group, inner)
			group["to_line"] = inner["to_line"]
			group["to_col"] = inner["to_col"]

	if not _is_at_end() and String(_peek()["text"]) == close_text:
		var close_token := _advance()
		group["to_line"] = close_token["line"]
		group["to_col"] = close_token["to_col"]
		group["is_closed"] = true

	return group


func _parse_collection(close_text: String) -> Dictionary:
	var open_token := _previous()
	var collection := _make_node(KIND_COLLECTION, open_token["line"], open_token["from_col"], open_token["line"], open_token["to_col"])
	collection["close_text"] = close_text
	collection["is_closed"] = false

	while not _is_at_end() and String(_peek()["text"]) != close_text:
		if [",", ":"].has(String(_peek()["text"])):
			_advance()
			continue
		var element := _parse_expression(1)
		if element.is_empty():
			break
		_add_child(collection, element)
		if not _is_at_end() and [",", ":"].has(String(_peek()["text"])):
			_advance()

	if not _is_at_end() and String(_peek()["text"]) == close_text:
		var close_token := _advance()
		collection["to_line"] = close_token["line"]
		collection["to_col"] = close_token["to_col"]
		collection["is_closed"] = true

	return collection


func _make_string_node(token: Dictionary) -> Dictionary:
	var literal := _make_node(KIND_STRING_LITERAL, token["line"], token["from_col"], token["line"], token["to_col"])
	if int(token["to_col"]) - int(token["from_col"]) >= 2:
		var content := _make_node(KIND_STRING_CONTENT, token["line"], int(token["from_col"]) + 1, token["line"], int(token["to_col"]) - 1)
		_add_child(literal, content)
	return literal


func _make_node(kind: String, from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return {
		"kind": kind,
		"from_line": from_line,
		"from_col": from_col,
		"to_line": to_line,
		"to_col": to_col,
		"children": [],
	}


func _add_child(parent: Dictionary, child: Dictionary) -> void:
	if child.is_empty():
		return
	parent["children"].append(child)


func _peek() -> Dictionary:
	return _tokens[_pos]


func _previous() -> Dictionary:
	return _tokens[_pos - 1]


func _advance() -> Dictionary:
	var token := _tokens[_pos]
	_pos += 1
	return token


func _is_at_end() -> bool:
	return _pos >= _tokens.size()
