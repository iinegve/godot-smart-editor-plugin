extends RefCounted


var uri := ""
var text := ""
var edit_count := 0


static func create(modified_uri: String, modified_text: String, modified_edit_count: int):
	var modified := new()
	modified.uri = modified_uri
	modified.text = modified_text
	modified.edit_count = modified_edit_count
	return modified


func is_valid() -> bool:
	return not uri.is_empty() and edit_count > 0
