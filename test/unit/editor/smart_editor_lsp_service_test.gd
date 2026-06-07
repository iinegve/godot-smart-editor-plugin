extends GdUnitTestSuite

const SmartEditorLspService := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_service.gd")

const URI := "file:///project/unit.gd"


class FakeLspTransport:
	extends RefCounted

	var status := StreamPeerTCP.STATUS_CONNECTED
	var connect_result := true
	var sent_messages: Array[Dictionary] = []
	var queued_messages: Array[Dictionary] = []
	var connect_calls := 0
	var disconnect_calls := 0


	func connect_to_host(_host: String, _port: int) -> bool:
		connect_calls += 1
		if connect_result:
			status = StreamPeerTCP.STATUS_CONNECTED
		return connect_result


	func disconnect_from_host() -> void:
		disconnect_calls += 1
		status = StreamPeerTCP.STATUS_NONE


	func get_status() -> int:
		return status


	func poll() -> Array[Dictionary]:
		var messages: Array[Dictionary] = []
		messages.assign(queued_messages)
		queued_messages.clear()
		return messages


	func send_message(message: Dictionary) -> void:
		sent_messages.append(message)


	func queue_response(id: int, result: Variant) -> void:
		queued_messages.append({
			"jsonrpc": "2.0",
			"id": id,
			"result": result,
		})


	func queue_error(id: int, error: Variant) -> void:
		queued_messages.append({
			"jsonrpc": "2.0",
			"id": id,
			"error": error,
		})


func test_ensure_ready_waits_until_initialize_response_arrives() -> void:
	var service := _service_with_fake_transport(false)
	var fake: FakeLspTransport = service._transport

	get_tree().create_timer(0.01).timeout.connect(func(): fake.queue_response(1, {"capabilities": {}}))
	var response = await service.ensure_ready()

	assert_bool(response.ok).is_true()
	assert_str(fake.sent_messages[0]["method"]).is_equal("initialize")
	assert_str(fake.sent_messages[1]["method"]).is_equal("initialized")

	service.free()


func test_rename_resolves_matching_response_id() -> void:
	var service := _service_with_fake_transport()
	var fake: FakeLspTransport = service._transport

	var pending = service.send_request_for_test("rename", "textDocument/rename", {
		"textDocument": {
			"uri": URI,
		},
		"position": {
			"line": 4,
			"character": 8,
		},
		"newName": "renamed",
	})
	fake.queue_response(1, {"changes": {}})
	service.process_lsp_messages_for_test()
	var response = pending.response

	assert_bool(response.ok).is_true()
	assert_dict(response.result).is_equal({"changes": {}})
	assert_str(fake.sent_messages[0]["method"]).is_equal("textDocument/rename")

	service.free()


func test_out_of_order_responses_resolve_the_correct_request() -> void:
	var service := _service_with_fake_transport()
	var fake: FakeLspTransport = service._transport

	var first_pending = service.send_request_for_test("rename", "textDocument/rename", {
		"textDocument": {
			"uri": URI,
		},
		"position": {
			"line": 1,
			"character": 2,
		},
		"newName": "first",
	})
	var second_pending = service.send_request_for_test("references", "textDocument/references", {
		"textDocument": {
			"uri": URI,
		},
		"position": {
			"line": 3,
			"character": 4,
		},
		"context": {
			"includeDeclaration": true,
		},
	})

	fake.queue_response(2, ["second"])
	fake.queue_response(1, {"first": true})
	service.process_lsp_messages_for_test()

	var first_response = first_pending.response
	var second_response = second_pending.response

	assert_bool(first_response.ok).is_true()
	assert_dict(first_response.result).is_equal({"first": true})
	assert_bool(second_response.ok).is_true()
	assert_array(second_response.result).is_equal(["second"])

	service.free()


func test_error_response_returns_failure() -> void:
	var service := _service_with_fake_transport()
	var fake: FakeLspTransport = service._transport

	var pending = service.send_request_for_test("prepare_rename", "textDocument/prepareRename", {
		"textDocument": {
			"uri": URI,
		},
		"position": {
			"line": 2,
			"character": 5,
		},
	})
	fake.queue_error(1, {"message": "not renameable"})
	service.process_lsp_messages_for_test()
	var response = pending.response

	assert_bool(response.ok).is_false()
	assert_dict(response.error).is_equal({"message": "not renameable"})

	service.free()


func test_duplicate_sync_document_with_unchanged_text_is_not_sent_twice() -> void:
	var service := _service_with_fake_transport()
	var fake: FakeLspTransport = service._transport

	var first_synced: bool = await service.sync_document(URI, "func value():\n\tpass")
	var second_synced: bool = await service.sync_document(URI, "func value():\n\tpass")

	assert_bool(first_synced).is_true()
	assert_bool(second_synced).is_false()
	assert_int(fake.sent_messages.size()).is_equal(1)
	assert_str(fake.sent_messages[0]["method"]).is_equal("textDocument/didOpen")

	service.free()


func _service_with_fake_transport(initialized: bool = true) -> SmartEditorLspService:
	var service := SmartEditorLspService.new()
	add_child(service)
	service.set_transport_for_test(FakeLspTransport.new())
	service._initialized = initialized
	return service
