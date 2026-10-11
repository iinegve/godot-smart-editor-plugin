@tool
extends RefCounted

# Adapted from Script-IDE's quick-open resource traversal (Marius Hanl, MIT).
# See THIRD_PARTY_NOTICES.md in the addon root.

enum Category { ALL, SCENES, GDSCRIPT, RESOURCES, OTHER }

var entries: Array[Dictionary] = []


func rebuild(directory: EditorFileSystemDirectory) -> void:
	entries.clear()
	if directory != null:
		_collect_directory(directory)


func _collect_directory(directory: EditorFileSystemDirectory) -> void:
	for index in directory.get_file_count():
		entries.append(file_entry(directory.get_file_path(index), directory.get_file_type(index)))
	for index in directory.get_subdir_count():
		_collect_directory(directory.get_subdir(index))


static func file_entry(path: String, resource_type: StringName = &"") -> Dictionary:
	var name := path.get_file()
	var folder := path.get_base_dir().trim_prefix("res://")
	return {
		"name": name,
		"label": name if folder.is_empty() else "%s — (%s)" % [name, folder],
		"context": path.trim_prefix("res://"),
		"tooltip": path,
		"path": path,
		"icon": resource_type,
		"category": category_for_file(path),
		"addon": path.begins_with("res://addons/"),
	}


static func category_for_file(path: String) -> Category:
	match path.get_extension().to_lower():
		"tscn", "scn": return Category.SCENES
		"gd": return Category.GDSCRIPT
		"tres", "res", "gdshader", "gdshaderinc": return Category.RESOURCES
		_: return Category.OTHER
