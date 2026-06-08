@tool
extends Node

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const SymbolUsageHighlight := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_highlight.gd")
const SmartEditorFiles := preload("res://addons/smart-editor-plugin/common/smart_editor_files.gd")

const SymbolUsageStripe := preload("res://addons/smart-editor-plugin/features/highlights/smart_symbol_usage_stripe.gd")

const STRIPE_WIDTH := 8.0
const CARET_DEBOUNCE_SECONDS := 0.04
const NAVIGATION_SETTLE_SECONDS := 0.08
const TEXT_DEBOUNCE_SECONDS := 0.40

var _enabled_setting: StringName = &""
var _highlight_enabled_setting: StringName = &""
var _highlight_color_setting: StringName = &""
var _current_highlight_color_setting: StringName = &""
var _current_outline_color_setting: StringName = &""
var _script_editor = null
var _code: CodeEdit
var _highlight = null
var _stripe = null
var _script_path := ""
var _uri := ""
var _refresh_pending := false
var _debounce_remaining := 0.0
var _text_change_pending := false
var _current_symbol_key := ""
var _request_generation := 0
var _overlays_dirty := false
var _last_references: Array[Dictionary] = []
var _last_line_count := 0
var _last_current_reference := {}
var _lsp_service: Node


func configure(
	enabled_setting: StringName,
	lsp_service: Node,
	highlight_enabled_setting: StringName = &"",
	highlight_color_setting: StringName = &"",
	current_highlight_color_setting: StringName = &"",
	current_outline_color_setting: StringName = &""
) -> void:
	_enabled_setting = enabled_setting
	_lsp_service = lsp_service
	_highlight_enabled_setting = highlight_enabled_setting
	_highlight_color_setting = highlight_color_setting
	_current_highlight_color_setting = current_highlight_color_setting
	_current_outline_color_setting = current_outline_color_setting
	set_process(true)
	_connect_script_editor()
	_attach_to_current_code_edit()
	_schedule_caret_refresh()


func _exit_tree() -> void:
	_disconnect_script_editor()
	_detach_code_edit()


func _process(delta: float) -> void:
	if _enabled_setting == &"" and _highlight_enabled_setting == &"":
		return

	if not _is_enabled():
		_disable_feature()
		return

	_connect_script_editor()
	_attach_to_current_code_edit()
	_sync_stripe_overlay()
	_sync_highlight_overlay()

	if _overlays_dirty:
		_layout_overlays()

	if _refresh_pending:
		if _should_delay_caret_refresh_for_navigation():
			_debounce_remaining = maxf(_debounce_remaining, NAVIGATION_SETTLE_SECONDS)
			return

		_debounce_remaining -= delta
		if _debounce_remaining <= 0.0:
			_refresh_pending = false
			_text_change_pending = false
			_refresh_references()


func _connect_script_editor() -> void:
	if _script_editor != null and is_instance_valid(_script_editor):
		return

	_script_editor = EditorInterface.get_script_editor()
	if _script_editor == null or not _script_editor.has_signal("editor_script_changed"):
		return

	if not _script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.connect(_on_editor_script_changed)


func _disconnect_script_editor() -> void:
	if _script_editor == null or not is_instance_valid(_script_editor):
		_script_editor = null
		return

	if _script_editor.has_signal("editor_script_changed") and _script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	_script_editor = null


func _attach_to_current_code_edit() -> void:
	var next_code := _get_current_code_edit()
	var next_script_path := _get_current_script_path()
	if next_code == _code and next_script_path == _script_path:
		return

	_detach_code_edit()
	_code = next_code
	_script_path = next_script_path
	_uri = SmartEditorFiles.path_to_file_uri(ProjectSettings.globalize_path(_script_path)) if not _script_path.is_empty() else ""

	if _code == null:
		return

	_code.caret_changed.connect(_on_code_caret_changed)
	_code.text_changed.connect(_on_code_text_changed)
	_code.resized.connect(_on_code_resized)

	_sync_stripe_overlay()
	_sync_highlight_overlay()
	_layout_overlays()
	_schedule_caret_refresh()


func _detach_code_edit() -> void:
	if _code != null and is_instance_valid(_code):
		if _code.caret_changed.is_connected(_on_code_caret_changed):
			_code.caret_changed.disconnect(_on_code_caret_changed)
		if _code.text_changed.is_connected(_on_code_text_changed):
			_code.text_changed.disconnect(_on_code_text_changed)
		if _code.resized.is_connected(_on_code_resized):
			_code.resized.disconnect(_on_code_resized)

	if _stripe != null and is_instance_valid(_stripe):
		_stripe.queue_free()
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.queue_free()

	_code = null
	_highlight = null
	_stripe = null
	_script_path = ""
	_uri = ""
	_current_symbol_key = ""
	_refresh_pending = false
	_text_change_pending = false
	_last_references.clear()
	_last_line_count = 0
	_last_current_reference.clear()
	_overlays_dirty = false


func _disable_feature() -> void:
	if _code != null or _stripe != null or _highlight != null:
		_detach_code_edit()


func _sync_stripe_overlay() -> void:
	if _code == null or not is_instance_valid(_code):
		return

	if not _is_stripe_enabled():
		if _stripe != null and is_instance_valid(_stripe):
			_stripe.queue_free()
		_stripe = null
		return

	if _stripe != null and is_instance_valid(_stripe):
		return

	_stripe = SymbolUsageStripe.new()
	_stripe.name = "SmartSymbolUsageStripe"
	_stripe.usage_clicked.connect(_on_stripe_usage_clicked)
	_code.add_child(_stripe)
	_overlays_dirty = true


func _sync_highlight_overlay() -> void:
	if _code == null or not is_instance_valid(_code):
		return

	if not _is_highlight_enabled():
		if _highlight != null and is_instance_valid(_highlight):
			_highlight.queue_free()
		_highlight = null
		return

	if _highlight != null and is_instance_valid(_highlight):
		return

	_highlight = SymbolUsageHighlight.new()
	_highlight.name = "SmartSymbolUsageHighlight"
	_highlight.configure(
		_highlight_color_setting,
		_current_highlight_color_setting,
		_current_outline_color_setting
	)
	_code.add_child(_highlight)
	_highlight.attach_to_code(_code)
	_overlays_dirty = true


func _is_highlight_enabled() -> bool:
	if _highlight_enabled_setting == &"":
		return false

	var settings = _get_editor_settings()
	if settings == null or not settings.has_setting(_highlight_enabled_setting):
		return false

	return bool(settings.get_setting(_highlight_enabled_setting))


func _schedule_caret_refresh() -> void:
	if _text_change_pending:
		return

	_refresh_pending = true
	_debounce_remaining = CARET_DEBOUNCE_SECONDS


func _schedule_text_refresh() -> void:
	_refresh_pending = true
	_text_change_pending = true
	_debounce_remaining = TEXT_DEBOUNCE_SECONDS


func _should_delay_caret_refresh_for_navigation() -> bool:
	if _text_change_pending:
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true

	return (
		Input.is_key_pressed(KEY_UP)
		or Input.is_key_pressed(KEY_DOWN)
		or Input.is_key_pressed(KEY_LEFT)
		or Input.is_key_pressed(KEY_RIGHT)
		or Input.is_key_pressed(KEY_PAGEUP)
		or Input.is_key_pressed(KEY_PAGEDOWN)
		or Input.is_key_pressed(KEY_HOME)
		or Input.is_key_pressed(KEY_END)
	)


func _refresh_references() -> void:
	if _code == null or not is_instance_valid(_code) or _uri.is_empty():
		_clear_references()
		return

	var caret_line_index := _code.get_caret_line()
	var caret_column := _code.get_caret_column()
	var caret_line := _code.get_line(_code.get_caret_line())
	var symbol_range := SymbolUsageModel.symbol_range_in_line(
		caret_line,
		caret_line_index,
		caret_column
	)
	if symbol_range.is_empty():
		_current_symbol_key = ""
		_clear_references()
		return

	var code_version := _code.get_version()
	var symbol_key := "%s:%s:%d:%d:%d" % [
		_uri,
		symbol_range["symbol"],
		symbol_range["line"],
		symbol_range["column"],
		code_version,
	]
	if symbol_key == _current_symbol_key:
		return

	_request_generation += 1
	_current_symbol_key = symbol_key
	var request := {
		"uri": _uri,
		"symbol": symbol_range["symbol"],
		"line": symbol_range["line"],
		"column": symbol_range["column"],
		"end_line": symbol_range["line"],
		"end_column": symbol_range["end_column"],
		"code_version": code_version,
		"generation": _request_generation,
	}

	_clear_references()
	if _lsp_service == null:
		return

	_refresh_semantic_references(request)


func _refresh_semantic_references(request: Dictionary) -> void:
	if not _request_matches_current(request):
		return

	var uri := str(request["uri"])
	var code_text := _get_code_text(_code)
	await _lsp_service.sync_document(uri, code_text)
	var highlight_response = await _lsp_service.document_highlight(
		uri,
		int(request["line"]),
		int(request["column"])
	)
	if not _request_matches_current(request):
		return
	if not highlight_response.ok:
		_clear_references()
		return

	_apply_document_highlights(highlight_response.result, request)


func _apply_document_highlights(document_highlights: Variant, request: Dictionary) -> void:
	if not _request_matches_current(request):
		return

	var current_reference := {
		"line": int(request["line"]),
		"column": int(request["column"]),
		"end_line": int(request["end_line"]),
		"end_column": int(request["end_column"]),
	}
	var filtered_references := _references_from_document_highlights(document_highlights)
	if filtered_references.is_empty():
		_clear_references()
		return

	filtered_references = _references_including_current(filtered_references, current_reference)
	_set_usage_references(filtered_references, _code.get_line_count(), current_reference)


func _references_from_document_highlights(document_highlights: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(document_highlights) != TYPE_ARRAY:
		return result

	for document_highlight in document_highlights:
		if typeof(document_highlight) != TYPE_DICTIONARY:
			continue

		var highlight: Dictionary = document_highlight
		if not highlight.has("range") or typeof(highlight["range"]) != TYPE_DICTIONARY:
			continue

		var highlight_range: Dictionary = highlight["range"]
		if (
			not highlight_range.has("start")
			or not highlight_range.has("end")
			or typeof(highlight_range["start"]) != TYPE_DICTIONARY
			or typeof(highlight_range["end"]) != TYPE_DICTIONARY
		):
			continue

		var start: Dictionary = highlight_range["start"]
		var end: Dictionary = highlight_range["end"]
		result.append({
			"line": int(start.get("line", -1)),
			"column": int(start.get("character", -1)),
			"end_line": int(end.get("line", -1)),
			"end_column": int(end.get("character", -1)),
		})

	return result


func _request_matches_current(request: Dictionary) -> bool:
	if _code == null or not is_instance_valid(_code):
		return false
	if request.get("uri", "") != _uri:
		return false
	if int(request.get("code_version", -1)) != _code.get_version():
		return false
	if int(request.get("generation", -1)) != _request_generation:
		return false

	var current_symbol := SymbolUsageModel.symbol_range_in_line(
		_code.get_line(_code.get_caret_line()),
		_code.get_caret_line(),
		_code.get_caret_column()
	)
	return (
		not current_symbol.is_empty()
		and current_symbol["symbol"] == request.get("symbol", "")
		and int(current_symbol["line"]) == int(request.get("line", -1))
		and int(current_symbol["column"]) == int(request.get("column", -1))
	)


func _on_editor_script_changed(_script: Script) -> void:
	_attach_to_current_code_edit()
	_schedule_caret_refresh()


func _on_code_caret_changed() -> void:
	_schedule_caret_refresh()


func _on_code_text_changed() -> void:
	_request_generation += 1
	_current_symbol_key = ""
	_clear_references()
	_overlays_dirty = true
	_schedule_text_refresh()


func _on_code_resized() -> void:
	_overlays_dirty = true


func _on_stripe_usage_clicked(reference: Dictionary) -> void:
	if _code == null or not is_instance_valid(_code):
		return

	var line := clampi(int(reference["line"]), 0, max(0, _code.get_line_count() - 1))
	var column := clampi(int(reference["column"]), 0, _code.get_line(line).length())
	_code.set_caret_line(line)
	_code.set_caret_column(column)
	_code.center_viewport_to_caret()
	_code.grab_focus()


func _layout_overlays() -> void:
	_layout_highlight()
	_layout_stripe()
	_overlays_dirty = false


func _layout_highlight() -> void:
	if _code == null or _highlight == null or not is_instance_valid(_code) or not is_instance_valid(_highlight):
		return

	_highlight.anchor_left = 0.0
	_highlight.anchor_right = 1.0
	_highlight.anchor_top = 0.0
	_highlight.anchor_bottom = 1.0
	_highlight.offset_left = 0.0
	_highlight.offset_right = 0.0
	_highlight.offset_top = 0.0
	_highlight.offset_bottom = 0.0
	_highlight.z_index = 10


func _layout_stripe() -> void:
	if _code == null or _stripe == null or not is_instance_valid(_code) or not is_instance_valid(_stripe):
		return

	var vertical_scrollbar := _code.get_v_scroll_bar()
	var vertical_scrollbar_rect := Rect2()
	var has_visible_vertical_scrollbar := false
	if vertical_scrollbar != null:
		vertical_scrollbar_rect = Rect2(vertical_scrollbar.position, vertical_scrollbar.size)
		has_visible_vertical_scrollbar = vertical_scrollbar.visible

	var horizontal_scrollbar := _code.get_h_scroll_bar()
	var horizontal_scrollbar_rect := Rect2()
	var has_visible_horizontal_scrollbar := false
	if horizontal_scrollbar != null:
		horizontal_scrollbar_rect = Rect2(horizontal_scrollbar.position, horizontal_scrollbar.size)
		has_visible_horizontal_scrollbar = horizontal_scrollbar.visible

	var stripe_rect := stripe_rect_for_scrollbars(
		_code.size,
		vertical_scrollbar_rect,
		has_visible_vertical_scrollbar,
		horizontal_scrollbar_rect,
		has_visible_horizontal_scrollbar,
		STRIPE_WIDTH
	)

	_stripe.anchor_left = 0.0
	_stripe.anchor_right = 0.0
	_stripe.anchor_top = 0.0
	_stripe.anchor_bottom = 0.0
	_stripe.offset_left = stripe_rect.position.x
	_stripe.offset_right = stripe_rect.position.x + stripe_rect.size.x
	_stripe.offset_top = stripe_rect.position.y
	_stripe.offset_bottom = stripe_rect.position.y + stripe_rect.size.y
	_stripe.z_index = 20


func _set_usage_references(references: Array[Dictionary], line_count: int, current_reference: Dictionary) -> void:
	if _same_usage_references(references, line_count, current_reference):
		return

	_last_references = references.duplicate(true)
	_last_line_count = line_count
	_last_current_reference = current_reference.duplicate()

	if _stripe != null and is_instance_valid(_stripe):
		_stripe.set_usage_references(references, line_count, current_reference)
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.set_usage_references(references, line_count, current_reference)


func _clear_references() -> void:
	if _stripe != null and is_instance_valid(_stripe):
		_stripe.clear_references()
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.clear_references()
	_last_references.clear()
	_last_line_count = 0
	_last_current_reference.clear()


func _same_usage_references(references: Array[Dictionary], line_count: int, current_reference: Dictionary) -> bool:
	if line_count != _last_line_count:
		return false
	if not SymbolUsageModel.same_position(current_reference, _last_current_reference):
		return false
	if references.size() != _last_references.size():
		return false

	for index in references.size():
		if not SymbolUsageModel.same_position(references[index], _last_references[index]):
			return false

	return true


func _references_including_current(references: Array[Dictionary], current_reference: Dictionary) -> Array[Dictionary]:
	var result := references.duplicate()
	for reference in result:
		if SymbolUsageModel.same_position(reference, current_reference):
			return result

	for index in result.size():
		if _compare_reference_positions(current_reference, result[index]) < 0:
			result.insert(index, current_reference.duplicate())
			return result

	result.append(current_reference.duplicate())
	return result


func _compare_reference_positions(a: Dictionary, b: Dictionary) -> int:
	var line_delta := int(a.get("line", 0)) - int(b.get("line", 0))
	if line_delta != 0:
		return line_delta

	return int(a.get("column", 0)) - int(b.get("column", 0))


static func stripe_rect_for_scrollbars(
	code_size: Vector2,
	vertical_scrollbar_rect: Rect2,
	vertical_scrollbar_visible: bool,
	horizontal_scrollbar_rect: Rect2,
	horizontal_scrollbar_visible: bool,
	stripe_width: float
) -> Rect2:
	var top := 0.0
	var height := code_size.y
	var right := code_size.x

	if vertical_scrollbar_visible:
		top = vertical_scrollbar_rect.position.y
		height = vertical_scrollbar_rect.size.y
		right = vertical_scrollbar_rect.position.x
	elif horizontal_scrollbar_visible:
		height = minf(height, horizontal_scrollbar_rect.position.y)

	var width := minf(stripe_width, maxf(0.0, right))
	return Rect2(
		maxf(0.0, right - width),
		maxf(0.0, top),
		width,
		maxf(0.0, height)
	)


func _get_current_code_edit() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return null

	var current_editor := script_editor.get_current_editor()

	if current_editor == null:
		return null

	var base := current_editor.get_base_editor()
	if base is CodeEdit:
		return base

	return null


func _get_current_script_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""

	var current_script: Script = script_editor.get_current_script()
	if current_script != null:
		return current_script.resource_path

	return ""


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


func _is_enabled() -> bool:
	return should_run_controller(_is_stripe_enabled(), _is_highlight_enabled())


func _is_stripe_enabled() -> bool:
	if _enabled_setting == &"":
		return false

	var settings = _get_editor_settings()
	if settings == null or not settings.has_setting(_enabled_setting):
		return false

	return bool(settings.get_setting(_enabled_setting))


static func should_run_controller(stripe_enabled: bool, highlight_enabled: bool) -> bool:
	return stripe_enabled or highlight_enabled


func _get_editor_settings():
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton("EditorInterface"):
		return null

	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_editor_settings"):
		return null

	return editor_interface.get_editor_settings()
