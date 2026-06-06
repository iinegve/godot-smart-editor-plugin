extends RefCounted

const RenameTextEdit := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_text_edit.gd")


var uri := ""
var edits: Array[RenameTextEdit] = []


static func create(new_uri: String):
	var file_edits := new()
	file_edits.uri = new_uri
	return file_edits


func add_edit(edit: RenameTextEdit) -> void:
	if edit == null or not edit.is_valid():
		return
	edits.append(edit)


func is_empty() -> bool:
	return edits.is_empty()
