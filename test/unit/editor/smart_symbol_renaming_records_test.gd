extends GdUnitTestSuite

const SmartEditorOpenScripts := preload("res://addons/smart-editor-plugin/common/smart_editor_open_scripts.gd")
const RenameOpenScriptBuffer := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffer.gd")
const RenameOpenScriptBuffers := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffers.gd")
const RenameRequest := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_request.gd")
const RenameSymbolTarget := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_symbol_target.gd")


class FakeOpenEditor:
	extends RefCounted

	var base_editor: Control


	func _init(editor: Control) -> void:
		base_editor = editor


	func get_base_editor() -> Control:
		return base_editor


class FakeResourceSyntaxHighlighter:
	extends SyntaxHighlighter

	var edited_resource: Resource


	func _init(resource: Resource) -> void:
		edited_resource = resource


	func _get_edited_resource() -> Resource:
		return edited_resource


func test_rename_request_can_be_configured_and_cleared() -> void:
	var request := RenameRequest.new()

	assert_bool(request.is_empty()).is_true()

	request.configure("file:///project/unit.gd", 4, 12, "renamed")

	assert_bool(request.is_empty()).is_false()
	assert_str(request.uri).is_equal("file:///project/unit.gd")
	assert_int(request.line).is_equal(4)
	assert_int(request.column).is_equal(12)
	assert_str(request.new_name).is_equal("renamed")

	request.clear()

	assert_bool(request.is_empty()).is_true()
	assert_str(request.uri).is_empty()
	assert_int(request.line).is_equal(-1)
	assert_int(request.column).is_equal(-1)
	assert_str(request.new_name).is_empty()


func test_rename_symbol_target_converts_symbol_range() -> void:
	var target: RenameSymbolTarget = RenameSymbolTarget.from_symbol_range({
		"symbol": "health",
		"line": 8,
		"column": 5,
	})

	assert_bool(target.is_empty()).is_false()
	assert_str(target.symbol).is_equal("health")
	assert_int(target.line).is_equal(8)
	assert_int(target.column).is_equal(5)


func test_rename_symbol_target_handles_empty_symbol_range() -> void:
	var target: RenameSymbolTarget = RenameSymbolTarget.from_symbol_range({})

	assert_bool(target.is_empty()).is_true()


func test_open_script_buffers_can_find_buffer_by_uri() -> void:
	var uri := "file:///project/unit.gd"
	var code := CodeEdit.new()
	var script := GDScript.new()
	var buffer: RenameOpenScriptBuffer = RenameOpenScriptBuffer.create(uri, script, code)
	var buffers := RenameOpenScriptBuffers.new()

	buffers.add(buffer)

	assert_bool(buffers.has_uri(uri)).is_true()
	assert_bool(buffers.has_uri("file:///project/other.gd")).is_false()
	assert_bool(buffers.buffer_for_uri(uri) == buffer).is_true()
	assert_bool(buffers.buffer_for_uri("file:///project/other.gd") == null).is_true()

	code.free()


func test_open_script_buffers_keep_scripts_mapped_when_non_script_editor_is_open() -> void:
	var first_script := GDScript.new()
	var second_script := GDScript.new()
	var first_code := _code_edit_for_resource(first_script)
	var non_script_code := _code_edit_for_resource(Resource.new())
	var second_code := _code_edit_for_resource(second_script)
	var open_editors := [
		FakeOpenEditor.new(first_code),
		FakeOpenEditor.new(non_script_code),
		FakeOpenEditor.new(second_code),
	]

	var buffers := SmartEditorOpenScripts.from_open_editors(open_editors)

	assert_int(buffers.size()).is_equal(2)
	assert_bool(buffers[0].source_script == first_script).is_true()
	assert_bool(buffers[0].code == first_code).is_true()
	assert_bool(buffers[1].source_script == second_script).is_true()
	assert_bool(buffers[1].code == second_code).is_true()

	first_code.free()
	non_script_code.free()
	second_code.free()


func _code_edit_for_resource(resource: Resource) -> CodeEdit:
	var code := CodeEdit.new()
	code.set_syntax_highlighter(FakeResourceSyntaxHighlighter.new(resource))
	return code
