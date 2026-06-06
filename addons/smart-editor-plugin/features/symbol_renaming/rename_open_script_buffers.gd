extends RefCounted

const RenameOpenScriptBuffer := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffer.gd")


var buffers: Array[RenameOpenScriptBuffer] = []


func add(buffer: RenameOpenScriptBuffer) -> void:
	if buffer == null or not buffer.is_valid():
		return
	buffers.append(buffer)


func has_uri(uri: String) -> bool:
	return buffer_for_uri(uri) != null


func buffer_for_uri(uri: String) -> RenameOpenScriptBuffer:
	for buffer in buffers:
		if buffer.uri == uri:
			return buffer
	return null
