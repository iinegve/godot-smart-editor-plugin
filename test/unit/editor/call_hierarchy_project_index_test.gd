extends GdUnitTestSuite

const GDScriptProjectIndex := preload("res://addons/smart-editor-plugin/features/call_hierarchy/gdscript_project_index.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_project_index_finds_class_name_and_display_name_from_cache() -> void:
	var index := GDScriptProjectIndex.new()
	var uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	index.file_cache[uri] = [
		"class_name Player",
		"",
		"func move() -> void:",
		"\tpass",
	]

	assert_str(index.find_class_name_for_uri(uri)).is_equal("Player")
	assert_str(index.script_display_name(uri)).is_equal("Player")
	assert_str(index.format_method_label(uri, "move")).is_equal("Player.move()")


func test_project_index_uses_current_open_buffer_before_cache() -> void:
	var index := GDScriptProjectIndex.new()
	var uri := SmartEditorFiles.path_to_file_uri("/project/player.gd")
	var code := CodeEdit.new()
	code.text = "class_name CurrentPlayer"
	index.file_cache[uri] = ["class_name CachedPlayer"]

	index.configure_current_buffer(uri, code)

	assert_str(index.find_class_name_for_uri(uri)).is_equal("CurrentPlayer")

	code.free()
