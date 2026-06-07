extends GdUnitTestSuite

const SmartEditorLspService := preload("res://addons/smart-editor-plugin/common/lsp/smart_editor_lsp_service.gd")

const URI := "file:///project/unit.gd"


class FakeLspClient:
	extends RefCounted

	var initialized := true
	var sent_requests: Array[Dictionary] = []
	var queued_responses: Array[Dictionary] = []
	var synced_documents: Array[Dictionary] = []
	var signatures := {}

	func configure(_name: String, _host: String, _port: int, _capabilities: Dictionary, _debug_callback: Callable = Callable()) -> void:
		pass

	func disconnect_from_host() -> void:
		pass

	func is_initialized() -> bool:
		return initialized

	func ensure_connection(_report_errors: bool = false) -> bool:
		return true

	func get_status() -> int:
		return StreamPeerTCP.STATUS_CONNECTED

	func has_pending_requests() -> bool:
		return false

	func poll() -> Array[Dictionary]:
		var responses: Array[Dictionary] = []
		responses.assign(queued_responses)
		queued_responses.clear()
		return responses

	func send_request(kind: String, method: String, params: Dictionary, context: Dictionary = {}) -> int:
		var request_id := sent_requests.size() + 1
		sent_requests.append({
			"id": request_id,
			"kind": kind,
			"method": method,
			"params": params,
			"context": context,
		})
		return request_id

	func sync_document(uri: String, text: String, language_id: String = "gdscript") -> bool:
		var signature := "%d:%d" % [text.length(), text.hash()]
		if str(signatures.get(uri, "")) == signature:
			return false

		signatures[uri] = signature
		synced_documents.append({
			"uri": uri,
			"text": text,
			"language_id": language_id,
		})
		return true

	func queue_response(id: int, result: Variant) -> void:
		queued_responses.append({
			"message": {
				"id": id,
				"result": result,
			},
		})

	func queue_error(id: int, error: Variant) -> void:
		queued_responses.append({
			"message": {
				"id": id,
				"error": error,
			},
		})


func test_ensure_ready_waits_until_client_is_initialized() -> void:
	var service := _service_with_fake_lsp()
	var fake: FakeLspClient = service._lsp
	fake.initialized = false

	get_tree().create_timer(0.01).timeout.connect(func(): fake.initialized = true)
	var response = await service.ensure_ready()

	assert_bool(response.ok).is_true()

	service.free()


func test_rename_resolves_matching_response_id() -> void:
	var service := _service_with_fake_lsp()
	var fake: FakeLspClient = service._lsp

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
	assert_str(fake.sent_requests[0]["method"]).is_equal("textDocument/rename")

	service.free()


func test_out_of_order_responses_resolve_the_correct_request() -> void:
	var service := _service_with_fake_lsp()
	var fake: FakeLspClient = service._lsp

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
	var service := _service_with_fake_lsp()
	var fake: FakeLspClient = service._lsp

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
	var service := _service_with_fake_lsp()
	var fake: FakeLspClient = service._lsp

	var first_synced: bool = await service.sync_document(URI, "func value():\n\tpass")
	var second_synced: bool = await service.sync_document(URI, "func value():\n\tpass")

	assert_bool(first_synced).is_true()
	assert_bool(second_synced).is_false()
	assert_int(fake.synced_documents.size()).is_equal(1)

	service.free()


func _service_with_fake_lsp() -> SmartEditorLspService:
	var service := SmartEditorLspService.new()
	add_child(service)
	service.set_lsp_client_for_test(FakeLspClient.new())
	return service
