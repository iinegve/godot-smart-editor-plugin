extends RefCounted

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")


var symbol := ""
var line := -1
var column := -1


static func create(target_symbol: String, target_line: int, target_column: int):
	var target := new()
	target.symbol = target_symbol
	target.line = target_line
	target.column = target_column
	return target


static func from_symbol_range(symbol_range: Dictionary):
	if symbol_range.is_empty():
		return new()
	return create(
		str(symbol_range.get("symbol", "")),
		int(symbol_range.get("line", -1)),
		int(symbol_range.get("column", -1))
	)


static func is_selection_reference_in_text(
	text: String,
	selected: String,
	from_line: int,
	from_column: int,
	to_line: int,
	to_column: int
) -> bool:
	return SymbolUsageModel.is_identifier_reference_in_text(text, {
		"line": from_line,
		"column": from_column,
		"end_line": to_line,
		"end_column": to_column,
	}, selected)


func is_empty() -> bool:
	return symbol.is_empty() or line < 0 or column < 0
