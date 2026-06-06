extends GdUnitTestSuite

const RenameOpenScriptBuffer := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffer.gd")
const RenameOpenScriptBuffers := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_open_script_buffers.gd")
const RenameRequest := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_request.gd")
const RenameSymbolTarget := preload("res://addons/smart-editor-plugin/features/symbol_renaming/rename_symbol_target.gd")


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
