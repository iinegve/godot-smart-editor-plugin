extends RefCounted

# A single place where a target method is called: caller method plus call-site position.

const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")


var method: CallHierarchyMethod
var open_line := -1
var open_character := -1


static func create(new_method: CallHierarchyMethod, new_open_line: int, new_open_character: int):
	var call_site := new()
	call_site.configure(new_method, new_open_line, new_open_character)
	return call_site


func configure(new_method: CallHierarchyMethod, new_open_line: int, new_open_character: int) -> void:
	method = new_method
	open_line = new_open_line
	open_character = new_open_character


func is_valid() -> bool:
	return method != null and not method.is_empty() and open_line >= 0 and open_character >= 0


func call_site_key() -> String:
	if method == null:
		return ":-1::-1:-1"
	return "%s:%d:%s:%d:%d" % [method.uri, method.line, method.name, open_line, open_character]
