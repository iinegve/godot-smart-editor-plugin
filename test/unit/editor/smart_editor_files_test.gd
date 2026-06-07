extends GdUnitTestSuite

const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_file_uri_round_trip_keeps_spaces_and_slashes() -> void:
	var path := "/Users/example/My Project/player.gd"
	var uri := SmartEditorFiles.path_to_file_uri(path)

	assert_str(uri).is_equal("file:///Users/example/My%20Project/player.gd")
	assert_str(SmartEditorFiles.file_uri_to_path(uri)).is_equal(path)
