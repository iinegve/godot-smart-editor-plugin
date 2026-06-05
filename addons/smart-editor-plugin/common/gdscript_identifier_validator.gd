@tool
extends RefCounted

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")

const IDENTIFIER_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


func is_valid_identifier(value: String) -> bool:
	return identifier_validation_error(value).is_empty()


func identifier_validation_error(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return "Name is required."

	var first := trimmed[0]
	if not is_identifier_start_char(first):
		return "Name must start with a letter or underscore."

	for col in range(1, trimmed.length()):
		if not is_identifier_char(trimmed[col]):
			return "Name can only contain letters, digits, and underscores."

	if SymbolUsageModel.is_language_symbol(trimmed):
		return "'%s' is reserved by GDScript." % trimmed

	return ""


func is_identifier_start_char(ch: String) -> bool:
	return (
		(ch >= "a" and ch <= "z")
		or (ch >= "A" and ch <= "Z")
		or ch == "_"
	)


func is_identifier_char(ch: String) -> bool:
	return IDENTIFIER_CHARS.contains(ch)
