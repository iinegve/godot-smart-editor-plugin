extends RefCounted

# UI tree metadata for one rendered call hierarchy row: display text, loading state, and visited methods.

const CallHierarchyCallSite := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_call_site.gd")
const CallHierarchyMethod := preload("res://addons/smart-editor-plugin/features/call_hierarchy/call_hierarchy_method.gd")


var method: CallHierarchyMethod
var open_line := -1
var open_character := -1
var base_text := ""
var loaded := false
var visited := {}
var leaf_text := ""


static func create(
	new_method: CallHierarchyMethod,
	new_open_line: int,
	new_open_character: int,
	new_base_text: String,
	new_loaded: bool = false,
	new_visited: Dictionary = {},
	new_leaf_text: String = ""
):
	var node := new()
	node.configure(
		new_method,
		new_open_line,
		new_open_character,
		new_base_text,
		new_loaded,
		new_visited,
		new_leaf_text
	)
	return node


static func from_call_site(
	call_site: CallHierarchyCallSite,
	new_base_text: String,
	new_loaded: bool,
	new_visited: Dictionary,
	new_leaf_text: String = ""
):
	return create(
		call_site.method,
		call_site.open_line,
		call_site.open_character,
		new_base_text,
		new_loaded,
		new_visited,
		new_leaf_text
	)


func configure(
	new_method: CallHierarchyMethod,
	new_open_line: int,
	new_open_character: int,
	new_base_text: String,
	new_loaded: bool,
	new_visited: Dictionary,
	new_leaf_text: String
) -> void:
	method = new_method
	open_line = new_open_line
	open_character = new_open_character
	base_text = new_base_text
	loaded = new_loaded
	visited = new_visited.duplicate()
	leaf_text = new_leaf_text


func is_valid() -> bool:
	return method != null and not method.is_empty()
