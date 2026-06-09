extends RefCounted

# Identity of a GDScript method in one file. Line and character point to the method definition.

var name := ""
var uri := ""
var line := -1
var character := -1


static func create(new_name: String, new_uri: String = "", new_line: int = -1, new_character: int = -1):
	var method := new()
	method.configure(new_name, new_uri, new_line, new_character)
	return method


func configure(new_name: String, new_uri: String, new_line: int, new_character: int) -> void:
	name = new_name
	uri = new_uri
	line = new_line
	character = new_character


func duplicate_method():
	return create(name, uri, line, character)


func is_empty() -> bool:
	return name.is_empty() or line < 0 or character < 0


func symbol_key() -> String:
	return "%s:%d:%s" % [uri, line, name]
