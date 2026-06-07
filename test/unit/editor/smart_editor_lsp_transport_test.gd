extends GdUnitTestSuite

const SmartEditorLspTransport := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_transport.gd")


func test_extracts_complete_lsp_body() -> void:
	var body := "{\"jsonrpc\":\"2.0\",\"id\":1}"
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]

	assert_str(SmartEditorLspTransport.try_extract_lsp_body(packet.to_utf8_buffer())).is_equal(body)


func test_does_not_extract_incomplete_lsp_body() -> void:
	var body := "{\"jsonrpc\":\"2.0\",\"id\":1}"
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size() + 10, body]

	assert_str(SmartEditorLspTransport.try_extract_lsp_body(packet.to_utf8_buffer())).is_empty()


func test_consumes_one_lsp_message_and_leaves_next_message() -> void:
	var first := "{\"id\":1}"
	var second := "{\"id\":2}"
	var first_packet := "Content-Length: %d\r\n\r\n%s" % [first.to_utf8_buffer().size(), first]
	var second_packet := "Content-Length: %d\r\n\r\n%s" % [second.to_utf8_buffer().size(), second]

	var remaining := SmartEditorLspTransport.consume_lsp_message((first_packet + second_packet).to_utf8_buffer())

	assert_str(SmartEditorLspTransport.try_extract_lsp_body(remaining)).is_equal(second)
