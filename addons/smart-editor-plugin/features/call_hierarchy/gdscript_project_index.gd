extends RefCounted

# Per-run cache of GDScript file text, class names, and display names. The current editor buffer overrides disk text.

const GDScriptTextIntrospection := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_text_introspection.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


var current_uri := ""
var current_code: CodeEdit
var file_cache := {}
var script_display_name_cache := {}


func clear() -> void:
	current_uri = ""
	current_code = null
	file_cache.clear()
	script_display_name_cache.clear()


func configure_current_buffer(uri: String, code: CodeEdit) -> void:
	current_uri = uri
	current_code = code


func get_text_for_uri(uri: String) -> String:
	if uri == current_uri and current_code != null:
		return get_code_text(current_code)
	if file_cache.has(uri):
		return "\n".join(file_cache[uri])

	var path := SmartEditorFiles.file_uri_to_path(uri)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""

	var text := file.get_as_text()
	file_cache[uri] = Array(text.split("\n"))
	return text


func get_lines_for_uri(uri: String) -> Array:
	if uri == current_uri and current_code != null:
		return get_code_lines(current_code)
	if file_cache.has(uri):
		return file_cache[uri]

	var text := get_text_for_uri(uri)
	if text.is_empty():
		return []

	return file_cache.get(uri, Array(text.split("\n")))


func get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


func get_code_lines(code: CodeEdit) -> Array:
	var lines := []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return lines


func gdscript_file_uris() -> Array[String]:
	var uris: Array[String] = []
	_append_gdscript_file_uris("res://", uris)
	return uris


func display_location(uri: String, line_index: int) -> String:
	var raw_path := SmartEditorFiles.file_uri_to_path(uri)
	var path := ProjectSettings.localize_path(raw_path)
	if path == raw_path:
		path = path.get_file()
	return "%s:%d" % [path, line_index + 1]


func script_display_name(uri: String) -> String:
	if script_display_name_cache.has(uri):
		return script_display_name_cache[uri]

	var display_name := find_class_name_for_uri(uri)
	if display_name.is_empty():
		display_name = "Unknown"

	script_display_name_cache[uri] = display_name
	return display_name


func format_method_label(uri: String, method_name: String) -> String:
	return "%s.%s()" % [script_display_name(uri), method_name]


func find_class_name_for_uri(uri: String) -> String:
	for line in get_lines_for_uri(uri):
		var code_line := GDScriptTextIntrospection.strip_line_comment(str(line)).strip_edges()
		if not code_line.begins_with("class_name "):
			continue

		var name_start := GDScriptTextIntrospection.skip_spaces(code_line, "class_name ".length())
		var name_end := name_start
		while name_end < code_line.length() and GDScriptTextIntrospection.is_identifier_char(code_line[name_end]):
			name_end += 1
		if name_start != name_end:
			return code_line.substr(name_start, name_end - name_start)

	return ""


func find_uri_for_class_name(target_class_name: String) -> String:
	if target_class_name.is_empty():
		return ""

	for uri in file_cache.keys():
		if find_class_name_for_uri(str(uri)) == target_class_name:
			return str(uri)

	for uri in gdscript_file_uris():
		if find_class_name_for_uri(uri) == target_class_name:
			return uri

	return ""


func _append_gdscript_file_uris(directory_path: String, uris: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue

		var child_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_append_gdscript_file_uris(child_path, uris)
		elif entry.get_extension().to_lower() == "gd":
			uris.append(SmartEditorFiles.path_to_file_uri(ProjectSettings.globalize_path(child_path)))

		entry = directory.get_next()
	directory.list_dir_end()
