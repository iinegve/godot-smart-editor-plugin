extends GdUnitTestSuite

const LspClient := preload("res://addons/smart-editor-plugin/common/lsp_client.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")


func test_extracts_complete_lsp_body() -> void:
	var body := "{\"jsonrpc\":\"2.0\",\"id\":1}"
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]

	assert_str(LspClient.try_extract_lsp_body(packet.to_utf8_buffer())).is_equal(body)


func test_does_not_extract_incomplete_lsp_body() -> void:
	var body := "{\"jsonrpc\":\"2.0\",\"id\":1}"
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size() + 10, body]

	assert_str(LspClient.try_extract_lsp_body(packet.to_utf8_buffer())).is_empty()


func test_consumes_one_lsp_message_and_leaves_next_message() -> void:
	var first := "{\"id\":1}"
	var second := "{\"id\":2}"
	var first_packet := "Content-Length: %d\r\n\r\n%s" % [first.to_utf8_buffer().size(), first]
	var second_packet := "Content-Length: %d\r\n\r\n%s" % [second.to_utf8_buffer().size(), second]

	var remaining := LspClient.consume_lsp_message((first_packet + second_packet).to_utf8_buffer())

	assert_str(LspClient.try_extract_lsp_body(remaining)).is_equal(second)


func test_file_uri_round_trip_keeps_spaces_and_slashes() -> void:
	var path := "/Users/example/My Project/player.gd"
	var uri := SmartEditorFiles.path_to_file_uri(path)

	assert_str(uri).is_equal("file:///Users/example/My%20Project/player.gd")
	assert_str(SmartEditorFiles.file_uri_to_path(uri)).is_equal(path)
