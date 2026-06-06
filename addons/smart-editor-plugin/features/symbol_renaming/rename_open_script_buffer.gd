extends RefCounted


var uri := ""
var source_script: Script
var code: CodeEdit


static func create(buffer_uri: String, buffer_script: Script, buffer_code: CodeEdit):
	var buffer := new()
	buffer.uri = buffer_uri
	buffer.source_script = buffer_script
	buffer.code = buffer_code
	return buffer


func is_valid() -> bool:
	return not uri.is_empty() and source_script != null and code != null
