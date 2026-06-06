extends RefCounted

const RenameFileEdits := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_file_edits.gd")
const RenameTextEdit := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_text_edit.gd")


var files: Array[RenameFileEdits] = []


static func from_lsp_workspace_edit(raw_workspace_edit: Variant):
	var edit_set := new()
	edit_set._read_lsp_workspace_edit(raw_workspace_edit)
	return edit_set


func is_empty() -> bool:
	return files.is_empty()


func file_count() -> int:
	return files.size()


func contains_uri(uri: String) -> bool:
	return file_for_uri(uri) != null


func file_for_uri(uri: String) -> RenameFileEdits:
	for file_edits in files:
		if file_edits.uri == uri:
			return file_edits
	return null


func add_file_edits(file_edits: RenameFileEdits) -> void:
	if file_edits == null or file_edits.uri.is_empty() or file_edits.is_empty():
		return

	var existing_file_edits := file_for_uri(file_edits.uri)
	if existing_file_edits != null:
		for edit in file_edits.edits:
			existing_file_edits.add_edit(edit)
		return

	files.append(file_edits)


func _read_lsp_workspace_edit(raw_workspace_edit: Variant) -> void:
	if typeof(raw_workspace_edit) != TYPE_DICTIONARY:
		return

	var workspace_edit: Dictionary = raw_workspace_edit
	if workspace_edit.has("changes"):
		_read_lsp_changes(workspace_edit["changes"])
	elif workspace_edit.has("documentChanges"):
		_read_lsp_document_changes(workspace_edit["documentChanges"])


func _read_lsp_changes(raw_changes: Variant) -> void:
	if typeof(raw_changes) != TYPE_DICTIONARY:
		return

	var changes: Dictionary = raw_changes
	for uri in changes:
		add_file_edits(_file_edits_from_lsp_edits(str(uri), changes[uri]))


func _read_lsp_document_changes(raw_document_changes: Variant) -> void:
	if typeof(raw_document_changes) != TYPE_ARRAY:
		return

	for raw_document_change in raw_document_changes:
		if typeof(raw_document_change) != TYPE_DICTIONARY:
			continue

		var document_change: Dictionary = raw_document_change
		var raw_text_document: Variant = document_change.get("textDocument", null)
		var raw_edits: Variant = document_change.get("edits", null)
		if typeof(raw_text_document) != TYPE_DICTIONARY:
			continue

		var text_document: Dictionary = raw_text_document
		add_file_edits(_file_edits_from_lsp_edits(str(text_document.get("uri", "")), raw_edits))


func _file_edits_from_lsp_edits(uri: String, raw_edits: Variant) -> RenameFileEdits:
	var file_edits: RenameFileEdits = RenameFileEdits.create(uri)
	if uri.is_empty() or typeof(raw_edits) != TYPE_ARRAY:
		return file_edits

	for raw_edit in raw_edits:
		var edit := _text_edit_from_lsp(raw_edit)
		if edit != null:
			file_edits.add_edit(edit)

	return file_edits


func _text_edit_from_lsp(raw_edit: Variant) -> RenameTextEdit:
	if typeof(raw_edit) != TYPE_DICTIONARY:
		return null

	var edit: Dictionary = raw_edit
	var raw_range: Variant = edit.get("range", null)
	if typeof(raw_range) != TYPE_DICTIONARY:
		return null

	var edit_range: Dictionary = raw_range
	var raw_start: Variant = edit_range.get("start", null)
	var raw_end: Variant = edit_range.get("end", null)
	if typeof(raw_start) != TYPE_DICTIONARY or typeof(raw_end) != TYPE_DICTIONARY:
		return null

	var start: Dictionary = raw_start
	var end: Dictionary = raw_end
	var text_edit: RenameTextEdit = RenameTextEdit.create(
		int(start.get("line", -1)),
		int(start.get("character", -1)),
		int(end.get("line", -1)),
		int(end.get("character", -1)),
		str(edit.get("newText", ""))
	)
	if not text_edit.is_valid():
		return null

	return text_edit
