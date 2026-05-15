@tool
extends RefCounted


static func make_range(from_line: int, from_col: int, to_line: int, to_col: int) -> Dictionary:
	return {
		"from_line": from_line,
		"from_col": from_col,
		"to_line": to_line,
		"to_col": to_col,
	}


static func from_node(node: Dictionary) -> Dictionary:
	return make_range(
		int(node["from_line"]),
		int(node["from_col"]),
		int(node["to_line"]),
		int(node["to_col"])
	)


static func contains_or_equal(outer: Dictionary, inner: Dictionary) -> bool:
	if compare_positions(outer["from_line"], outer["from_col"], inner["from_line"], inner["from_col"]) > 0:
		return false
	if compare_positions(outer["to_line"], outer["to_col"], inner["to_line"], inner["to_col"]) < 0:
		return false
	return true


static func strictly_contains(outer: Dictionary, inner: Dictionary) -> bool:
	return contains_or_equal(outer, inner) and not equal(outer, inner)


static func equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		a["from_line"] == b["from_line"]
		and a["from_col"] == b["from_col"]
		and a["to_line"] == b["to_line"]
		and a["to_col"] == b["to_col"]
	)


static func is_zero_width(selection_range: Dictionary) -> bool:
	return (
		selection_range["from_line"] == selection_range["to_line"]
		and selection_range["from_col"] == selection_range["to_col"]
	)


static func size(selection_range: Dictionary) -> int:
	return (
		(int(selection_range["to_line"]) - int(selection_range["from_line"])) * 10000
		+ int(selection_range["to_col"])
		- int(selection_range["from_col"])
	)


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
