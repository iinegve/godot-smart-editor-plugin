@tool
extends RefCounted

const SmartSelectionRange = preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")

var kind = ""
var selection_range: SmartSelectionRange
var children: Array = []
var data = {}


static func create(node_kind: String, from_line: int, from_col: int, to_line: int, to_col: int):
	var node = new()
	node.kind = node_kind
	node.selection_range = SmartSelectionRange.create(from_line, from_col, to_line, to_col)
	return node


func duplicate_tree():
	var node = create(
		kind,
		selection_range.from_line,
		selection_range.from_col,
		selection_range.to_line,
		selection_range.to_col
	)
	node.data = data.duplicate()
	for child in children:
		node.children.append(child.duplicate_tree())
	return node


func add_child(child) -> void:
	if child == null:
		return
	children.append(child)


func contains(other: SmartSelectionRange) -> bool:
	return selection_range.contains_or_equal(other)


func range_size() -> int:
	return selection_range.size()
