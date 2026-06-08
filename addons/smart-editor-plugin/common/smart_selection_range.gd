@tool
extends RefCounted

var from_line := 0
var from_col := 0
var to_line := 0
var to_col := 0


static func create(new_from_line: int, new_from_col: int, new_to_line: int, new_to_col: int):
	var selection_range := new()
	selection_range.configure(new_from_line, new_from_col, new_to_line, new_to_col)
	return selection_range


static func from_node(node: Dictionary):
	if node.is_empty():
		return null
	return create(
		int(node["from_line"]),
		int(node["from_col"]),
		int(node["to_line"]),
		int(node["to_col"])
	)


func configure(new_from_line: int, new_from_col: int, new_to_line: int, new_to_col: int) -> void:
	from_line = new_from_line
	from_col = new_from_col
	to_line = new_to_line
	to_col = new_to_col


func duplicate_range():
	return create(from_line, from_col, to_line, to_col)


func contains_or_equal(inner) -> bool:
	if compare_positions(from_line, from_col, inner.from_line, inner.from_col) > 0:
		return false
	if compare_positions(to_line, to_col, inner.to_line, inner.to_col) < 0:
		return false
	return true


func strictly_contains(inner) -> bool:
	return contains_or_equal(inner) and not equals(inner)


func equals(other) -> bool:
	return (
		from_line == other.from_line
		and from_col == other.from_col
		and to_line == other.to_line
		and to_col == other.to_col
	)


func is_zero_width() -> bool:
	return from_line == to_line and from_col == to_col


func size() -> int:
	return (to_line - from_line) * 10000 + to_col - from_col


static func compare_positions(line_a: int, col_a: int, line_b: int, col_b: int) -> int:
	if line_a < line_b:
		return -1
	if line_a > line_b:
		return 1
	if col_a < col_b:
		return -1
	if col_a > col_b:
		return 1
	return 0
