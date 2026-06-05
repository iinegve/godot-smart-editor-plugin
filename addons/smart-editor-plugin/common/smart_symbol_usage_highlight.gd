@tool
extends Control

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const CODE_RECT_COLUMN_OFFSET := 1
const HORIZONTAL_PADDING := 1.0
const VERTICAL_PADDING := 0.0
const DEFAULT_HIGHLIGHT_COLOR := Color(0.58, 0.36, 0.08, 0.20)
const DEFAULT_CURRENT_HIGHLIGHT_COLOR := Color(0.68, 0.44, 0.10, 0.20)
const DEFAULT_CURRENT_OUTLINE_COLOR := Color(0.76, 0.56, 0.18, 0.74)

var _code: CodeEdit
var _references: Array[Dictionary] = []
var _line_count := 0
var _current_reference := {}
var _highlight_color_setting: StringName = &""
var _current_highlight_color_setting: StringName = &""
var _current_outline_color_setting: StringName = &""
var _v_scroll_bar: VScrollBar
var _h_scroll_bar: HScrollBar
var _rect_cache: Array[Dictionary] = []
var _rect_cache_dirty := true
var _rect_cache_size := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_invalidate_rect_cache()


func _exit_tree() -> void:
	_disconnect_scrollbars()
	_disconnect_editor_settings()


func configure(
	highlight_color_setting: StringName,
	current_highlight_color_setting: StringName,
	current_outline_color_setting: StringName
) -> void:
	_disconnect_editor_settings()
	_highlight_color_setting = highlight_color_setting
	_current_highlight_color_setting = current_highlight_color_setting
	_current_outline_color_setting = current_outline_color_setting
	_connect_editor_settings()
	_invalidate_rect_cache()


func attach_to_code(code: CodeEdit) -> void:
	_disconnect_scrollbars()
	_code = code
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_connect_scrollbars()
	_invalidate_rect_cache()

func set_usage_references(references: Array[Dictionary], line_count: int, current_reference: Dictionary) -> void:
	_references = references.duplicate()
	_line_count = line_count
	_current_reference = current_reference.duplicate()
	_invalidate_rect_cache()

func clear_references() -> void:
	_references.clear()
	_line_count = 0
	_current_reference.clear()
	_invalidate_rect_cache()

func _draw() -> void:
	if _code == null or not is_instance_valid(_code) or _line_count <= 0:
		return

	if _rect_cache_dirty or _rect_cache_size != size:
		_rebuild_rect_cache()

	var highlight_color := _highlight_color()
	var current_highlight_color := _current_highlight_color()
	var current_outline_color := _current_outline_color()
	for entry in _rect_cache:
		var rect: Rect2 = entry["rect"]
		var is_current := bool(entry["current"])
		draw_rect(rect, current_highlight_color if is_current else highlight_color)
		if is_current:
			draw_rect(rect, current_outline_color, false, 1.0)


func _rebuild_rect_cache() -> void:
	_rect_cache.clear()
	_rect_cache_size = size
	_rect_cache_dirty = false

	var visible_lines := _visible_line_range()
	for reference in _references:
		var line := int(reference.get("line", -1))
		if line < visible_lines.x or line > visible_lines.y:
			continue

		var rect := _reference_rect(reference)
		if not rect.has_area():
			continue

		_rect_cache.append({
			"rect": rect,
			"current": SymbolUsageModel.same_position(reference, _current_reference),
		})


func _reference_rect(reference: Dictionary) -> Rect2:
	var line := int(reference.get("line", -1))
	if line < 0 or line >= _code.get_line_count():
		return Rect2()

	var line_text := _code.get_line(line)
	var column := clampi(int(reference.get("column", 0)), 0, line_text.length())
	var end_column := clampi(int(reference.get("end_column", column + 1)), column + 1, line_text.length())
	var start_rect := _code_rect_to_overlay_rect(Rect2(_code.get_rect_at_line_column(line, _rect_lookup_column(column, line_text))))
	var end_rect := _code_rect_to_overlay_rect(Rect2(_code.get_rect_at_line_column(line, _rect_lookup_column(end_column - 1, line_text))))
	if _is_outside_view(start_rect) or _is_outside_view(end_rect):
		return Rect2()

	var rect := Rect2(
		Vector2(start_rect.position.x - HORIZONTAL_PADDING, start_rect.position.y - VERTICAL_PADDING),
		Vector2(
			end_rect.position.x + end_rect.size.x - start_rect.position.x + HORIZONTAL_PADDING * 2.0,
			maxf(start_rect.size.y, end_rect.size.y) + VERTICAL_PADDING * 2.0
		)
	)
	var visible_rect := Rect2(Vector2.ZERO, size)
	if not visible_rect.intersects(rect):
		return Rect2()

	return rect

func _rect_lookup_column(column: int, line_text: String) -> int:
	return clampi(column + CODE_RECT_COLUMN_OFFSET, 0, line_text.length())

func _code_rect_to_overlay_rect(code_rect: Rect2) -> Rect2:
	if _code == null or not is_instance_valid(_code):
		return Rect2()

	var code_transform := _code.get_global_transform()
	var overlay_inverse := get_global_transform().affine_inverse()
	var start: Vector2 = overlay_inverse * (code_transform * code_rect.position)
	var end: Vector2 = overlay_inverse * (code_transform * (code_rect.position + code_rect.size))
	return Rect2(start, end - start).abs()

func _visible_line_range() -> Vector2i:
	if _code == null or not is_instance_valid(_code):
		return Vector2i(0, -1)

	if not _code.has_method("get_first_visible_line") or not _code.has_method("get_last_full_visible_line"):
		return Vector2i(0, maxi(0, _code.get_line_count() - 1))

	var first: int = maxi(0, int(_code.call("get_first_visible_line")) - 1)
	var last := int(_code.call("get_last_full_visible_line"))
	if last < first:
		last = first + int(_code.call("get_visible_line_count")) + 1 if _code.has_method("get_visible_line_count") else _code.get_line_count() - 1
	last = mini(_code.get_line_count() - 1, last + 1)
	return Vector2i(first, last)


func _connect_scrollbars() -> void:
	if _code == null or not is_instance_valid(_code):
		return

	_v_scroll_bar = _code.get_v_scroll_bar()
	if _v_scroll_bar != null and not _v_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_v_scroll_bar.value_changed.connect(_on_scroll_changed)

	_h_scroll_bar = _code.get_h_scroll_bar()
	if _h_scroll_bar != null and not _h_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_h_scroll_bar.value_changed.connect(_on_scroll_changed)


func _disconnect_scrollbars() -> void:
	if _v_scroll_bar != null and is_instance_valid(_v_scroll_bar) and _v_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_v_scroll_bar.value_changed.disconnect(_on_scroll_changed)
	if _h_scroll_bar != null and is_instance_valid(_h_scroll_bar) and _h_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_h_scroll_bar.value_changed.disconnect(_on_scroll_changed)

	_v_scroll_bar = null
	_h_scroll_bar = null


func _connect_editor_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_signal(&"settings_changed"):
		return
	if not settings.is_connected(&"settings_changed", _on_editor_settings_changed):
		settings.connect(&"settings_changed", _on_editor_settings_changed)


func _disconnect_editor_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_signal(&"settings_changed"):
		return
	if settings.is_connected(&"settings_changed", _on_editor_settings_changed):
		settings.disconnect(&"settings_changed", _on_editor_settings_changed)


func _invalidate_rect_cache() -> void:
	_rect_cache.clear()
	_rect_cache_dirty = true
	queue_redraw()


func _highlight_color() -> Color:
	return _editor_color_setting(_highlight_color_setting, DEFAULT_HIGHLIGHT_COLOR)


func _current_highlight_color() -> Color:
	return _editor_color_setting(_current_highlight_color_setting, DEFAULT_CURRENT_HIGHLIGHT_COLOR)


func _current_outline_color() -> Color:
	return _editor_color_setting(_current_outline_color_setting, DEFAULT_CURRENT_OUTLINE_COLOR)


func _editor_color_setting(path: StringName, default_color: Color) -> Color:
	if path == &"":
		return default_color

	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(path):
		return default_color

	var value = settings.get_setting(path)
	if typeof(value) != TYPE_COLOR:
		return default_color

	return value


func _on_editor_settings_changed() -> void:
	_invalidate_rect_cache()


func _on_scroll_changed(_value: float) -> void:
	_invalidate_rect_cache()


func _is_outside_view(rect: Rect2) -> bool:
	return rect.position.x < 0.0 or rect.position.y < 0.0
