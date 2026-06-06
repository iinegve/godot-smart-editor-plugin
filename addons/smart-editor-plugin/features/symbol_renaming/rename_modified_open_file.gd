extends RefCounted

const RenameOpenScriptBuffer := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffer.gd")


var uri := ""
var source_script: Script
var code: CodeEdit
var text := ""
var edit_count := 0


static func create(
	modified_uri: String,
	modified_script: Script,
	modified_code: CodeEdit,
	modified_text: String,
	modified_edit_count: int
):
	var modified := new()
	modified.uri = modified_uri
	modified.source_script = modified_script
	modified.code = modified_code
	modified.text = modified_text
	modified.edit_count = modified_edit_count
	return modified


static func create_from_buffer(buffer: RenameOpenScriptBuffer, modified_text: String, modified_edit_count: int):
	if buffer == null:
		return new()
	return create(buffer.uri, buffer.source_script, buffer.code, modified_text, modified_edit_count)


func is_valid() -> bool:
	return not uri.is_empty() and source_script != null and code != null and edit_count > 0
