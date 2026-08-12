extends GdUnitTestSuite

const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_posix_file_uri_round_trip_keeps_spaces_and_slashes() -> void:
	var path := "/Users/example/My Project/player.gd"
	var uri := SmartEditorFiles.path_to_file_uri(path)

	assert_str(uri).is_equal("file:///Users/example/My%20Project/player.gd")
	assert_str(SmartEditorFiles.file_uri_to_path(uri)).is_equal(path)


func test_windows_file_uri_places_drive_letter_in_local_path() -> void:
	var path := "D:/Projects/My Project/src/player_spawner.gd"

	assert_str(SmartEditorFiles.path_to_file_uri(path)).is_equal(
		"file:///D%3A/Projects/My%20Project/src/player_spawner.gd"
	)


func test_windows_file_uri_round_trip_removes_uri_drive_slash() -> void:
	var path := "D:/Projects/My Project/src/player_spawner.gd"
	var uri := SmartEditorFiles.path_to_file_uri(path)

	assert_str(SmartEditorFiles._file_uri_to_path(uri, true)).is_equal(path)
