extends GdUnitTestSuite

const GitBaselineProvider := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_baseline_provider.gd"
)
const GitLineDiff := preload("res://addons/smart-editor-plugin/features/git_changes/git_line_diff.gd")
const GitChangeGutter := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_change_gutter.gd"
)
const GitChangesController := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_changes_controller.gd"
)


class FakeBaselineProvider extends RefCounted:
	var calls: Array[String] = []
	var responses: Array[Dictionary] = []
	var availability_checks := 0
	var availability := {
		"available": true,
		"executable": "git",
		"version": "git version test",
		"error": "",
	}

	func _init(new_responses: Array[Dictionary], new_availability: Dictionary = {}) -> void:
		responses = new_responses.duplicate(true)
		if not new_availability.is_empty():
			availability = new_availability.duplicate(true)

	func check_availability() -> Dictionary:
		availability_checks += 1
		return availability.duplicate(true)

	func load_baseline(path: String) -> Dictionary:
		calls.append(path)
		if responses.is_empty():
			return _baseline_result(GitBaselineProvider.STATUS_UNAVAILABLE, "", "No response")
		return responses.pop_front()

	func _baseline_result(status: StringName, text: String, error: String = "") -> Dictionary:
		return {
			"status": status,
			"text": text,
			"repository_root": "/project",
			"relative_path": "scripts/player.gd",
			"error": error,
		}


func test_configure_keeps_controller_inactive_when_git_is_unavailable() -> void:
	var provider := FakeBaselineProvider.new([], {
		"available": false,
		"executable": "git",
		"version": "",
		"error": "The 'git' executable is not available in PATH.",
	})
	var controller := GitChangesController.new()
	add_child(controller)

	controller.configure(&"", provider)

	assert_int(provider.availability_checks).is_equal(1)
	assert_bool(controller._git_available).is_false()
	assert_bool(controller.is_processing()).is_false()
	assert_array(provider.calls).is_empty()
	assert_object(controller._gutter).is_null()

	controller.free()


func test_attach_loads_head_once_and_paints_current_buffer_changes() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_LOADED, "before\nold\nafter"),
	])
	var code := _create_code(["before", "new", "after"])
	var controller := _create_controller(provider)

	controller._attach_to_code(code, "res://scripts/player.gd")

	assert_int(provider.calls.size()).is_equal(1)
	assert_str(provider.calls[0]).is_equal(
		ProjectSettings.globalize_path("res://scripts/player.gd")
	)
	assert_object(controller._gutter).is_not_null()
	var marker := _marker(code, 1)
	assert_str(marker.type).is_equal(GitLineDiff.TYPE_MODIFIED)
	assert_array(marker.old_lines).is_equal(["old"])

	controller.free()
	code.free()


func test_typing_recomputes_after_debounce_without_running_git_again() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_LOADED, "before"),
	])
	var code := _create_code(["before"])
	var controller := _create_controller(provider)
	controller._attach_to_code(code, "res://scripts/player.gd")

	code.text = "before\nadded"
	controller._on_code_text_changed()
	controller._advance_pending_refresh(GitChangesController.TEXT_DEBOUNCE_SECONDS * 0.5)

	assert_bool(controller._refresh_pending).is_true()
	assert_bool(_marker(code, 1).is_empty()).is_true()

	controller._advance_pending_refresh(GitChangesController.TEXT_DEBOUNCE_SECONDS)

	assert_bool(controller._refresh_pending).is_false()
	assert_str(_marker(code, 1).type).is_equal(GitLineDiff.TYPE_ADDED)
	assert_int(provider.calls.size()).is_equal(1)

	controller.free()
	code.free()


func test_path_missing_from_head_marks_the_whole_file_as_added() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_NEW, ""),
	])
	var code := _create_code(["first", "second"])
	var controller := _create_controller(provider)

	controller._attach_to_code(code, "res://scripts/new_player.gd")

	assert_str(_marker(code, 0).type).is_equal(GitLineDiff.TYPE_ADDED)
	assert_str(_marker(code, 1).type).is_equal(GitLineDiff.TYPE_ADDED)

	controller.free()
	code.free()


func test_unavailable_git_baseline_keeps_the_editor_free_of_an_empty_gutter() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_UNAVAILABLE, "", "not a repository"),
	])
	var code := _create_code(["first"])
	var original_gutter_count := code.get_gutter_count()
	var controller := _create_controller(provider)

	controller._attach_to_code(code, "res://scripts/player.gd")

	assert_object(controller._gutter).is_null()
	assert_int(code.get_gutter_count()).is_equal(original_gutter_count)

	controller.free()
	code.free()


func test_reloading_baseline_updates_after_an_external_commit() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_LOADED, "old"),
		_baseline_result(GitBaselineProvider.STATUS_LOADED, "committed"),
	])
	var code := _create_code(["committed"])
	var controller := _create_controller(provider)
	controller._attach_to_code(code, "res://scripts/player.gd")
	assert_str(_marker(code, 0).type).is_equal(GitLineDiff.TYPE_MODIFIED)

	controller._reload_baseline()

	assert_int(provider.calls.size()).is_equal(2)
	assert_bool(_marker(code, 0).is_empty()).is_true()

	controller.free()
	code.free()


func test_repeated_marker_clicks_reuse_one_popup_and_replace_its_contents() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_LOADED, "old"),
	])
	var code := _create_code(["new"])
	var controller := _create_controller(provider)
	controller._attach_to_code(code, "res://scripts/player.gd")
	var first_change := _marker(code, 0)

	controller._on_change_clicked(first_change)
	var first_popup = controller._popup
	controller._on_change_clicked(_change(GitLineDiff.TYPE_DELETED, 2, ["removed"], 2, []))

	assert_object(first_popup).is_same(controller._popup)
	assert_str(controller._popup._previous_code.text).is_equal("removed")

	controller._popup.hide()
	controller.free()
	code.free()


func test_detach_removes_the_native_gutter_immediately() -> void:
	var provider := FakeBaselineProvider.new([
		_baseline_result(GitBaselineProvider.STATUS_NEW, ""),
	])
	var code := _create_code(["first"])
	var original_names := _gutter_names(code)
	var controller := _create_controller(provider)
	controller._attach_to_code(code, "res://scripts/new_player.gd")

	controller._detach_code_edit()

	assert_array(_gutter_names(code)).is_equal(original_names)
	assert_object(controller._gutter).is_null()

	controller.free()
	code.free()


func _create_controller(provider: FakeBaselineProvider) -> Node:
	var controller := GitChangesController.new()
	controller._baseline_provider = provider
	add_child(controller)
	return controller


func _create_code(lines: Array[String]) -> CodeEdit:
	var code := CodeEdit.new()
	code.text = "\n".join(lines)
	add_child(code)
	return code


func _marker(code: CodeEdit, line: int) -> Dictionary:
	var gutter := _git_gutter_index(code)
	if gutter < 0:
		return {}
	var marker: Variant = code.get_line_gutter_metadata(line, gutter)
	return marker if marker is Dictionary else {}


func _git_gutter_index(code: CodeEdit) -> int:
	for gutter in code.get_gutter_count():
		if code.get_gutter_name(gutter) == GitChangeGutter.GUTTER_NAME:
			return gutter
	return -1


func _gutter_names(code: CodeEdit) -> Array:
	var result := []
	for gutter in code.get_gutter_count():
		result.append(code.get_gutter_name(gutter))
	return result


func _baseline_result(status: StringName, text: String, error: String = "") -> Dictionary:
	return {
		"status": status,
		"text": text,
		"repository_root": "/project",
		"relative_path": "scripts/player.gd",
		"error": error,
	}


func _change(
	type: StringName,
	old_start: int,
	old_lines: Array[String],
	new_start: int,
	new_lines: Array[String]
) -> Dictionary:
	return {
		"type": type,
		"old_start": old_start,
		"old_count": old_lines.size(),
		"old_lines": old_lines,
		"new_start": new_start,
		"new_count": new_lines.size(),
		"new_lines": new_lines,
	}
