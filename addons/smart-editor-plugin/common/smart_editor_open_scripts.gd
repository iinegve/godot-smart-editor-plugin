extends RefCounted


class OpenScriptBuffer:
	extends RefCounted

	var source_script: Script
	var code: CodeEdit


	static func create(script: Script, code_edit: CodeEdit) -> OpenScriptBuffer:
		var buffer := OpenScriptBuffer.new()
		buffer.source_script = script
		buffer.code = code_edit
		return buffer


static func from_script_editor(script_editor: ScriptEditor) -> Array[OpenScriptBuffer]:
	if script_editor == null:
		return []

	return from_open_editors(script_editor.get_open_script_editors())


static func from_open_editors(open_editors: Array) -> Array[OpenScriptBuffer]:
	var buffers: Array[OpenScriptBuffer] = []

	for editor in open_editors:
		if editor == null or not editor.has_method("get_base_editor"):
			continue

		var base_editor: Variant = editor.get_base_editor()
		if not base_editor is CodeEdit:
			continue

		var code: CodeEdit = base_editor
		var source_script := _source_script_for_code(code)
		if source_script == null:
			continue

		buffers.append(OpenScriptBuffer.create(source_script, code))

	return buffers


static func _source_script_for_code(code: CodeEdit) -> Script:
	var highlighter := code.get_syntax_highlighter()
	if highlighter == null or not highlighter.has_method("_get_edited_resource"):
		return null

	var edited_resource: Variant = highlighter.call("_get_edited_resource")
	if edited_resource is Script:
		return edited_resource

	return null
