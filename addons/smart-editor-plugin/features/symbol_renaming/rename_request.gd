extends RefCounted


var uri := ""
var line := -1
var column := -1
var new_name := ""


static func create(request_uri: String, request_line: int, request_column: int, request_new_name: String):
	var request := new()
	request.configure(request_uri, request_line, request_column, request_new_name)
	return request


func configure(request_uri: String, request_line: int, request_column: int, request_new_name: String) -> void:
	uri = request_uri
	line = request_line
	column = request_column
	new_name = request_new_name


func is_empty() -> bool:
	return uri.is_empty() or line < 0 or column < 0 or new_name.is_empty()


func clear() -> void:
	uri = ""
	line = -1
	column = -1
	new_name = ""
