## Draws "N references" labels on declaration lines (func/var/const/signal/class),
## right-aligned after the code text — mimicking VS Code CodeLens.
##
## Positioning is mathematically bound to CodeEdit scroll values to completely
## eliminate frame lag ("floating text" effect) during scrolling.
## Uses real-time hot-path validation to prevent rendering stale labels on shifted lines.
@tool
extends Control

signal label_clicked(line: int, symbol: String)

const DEFAULT_LABEL_COLOR := Color(0.55, 0.55, 0.55, 0.75)

var _entries: Array[Dictionary] = []
var _code: CodeEdit = null

var _enabled_setting: StringName = &""
var _color_setting: StringName = &""

var _v_scroll_bar: VScrollBar
var _h_scroll_bar: HScrollBar

var _hit_rects: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _exit_tree() -> void:
	_disconnect_scrollbars()


func _has_point(point: Vector2) -> bool:
	for hr in _hit_rects:
		if (hr["rect"] as Rect2).has_point(point):
			return true
	return false


func configure(enabled_setting: StringName, color_setting: StringName) -> void:
	_enabled_setting = enabled_setting
	_color_setting = color_setting


func attach_to_code(code: CodeEdit) -> void:
	_disconnect_scrollbars()
	_code = code
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_connect_scrollbars()
	queue_redraw()


func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate()
	queue_redraw()


func clear_entries() -> void:
	_entries.clear()
	queue_redraw()


func _draw() -> void:
	_hit_rects.clear()
	if not _is_valid_drawing_state():
		return

	var font := _get_font()
	if font == null:
		return

	var font_size := _get_font_size()
	var label_size := maxi(8, font_size - 2)
	var label_color := _label_color()
	var hover_color := _get_hover_color(label_color)

	var visible_range := _get_visible_line_range()
	var horizontal_base := _get_horizontal_base()

	_draw_entries(
		visible_range, 
		horizontal_base, 
		font, 
		font_size, 
		label_size, 
		label_color, 
		hover_color
	)


func _is_valid_drawing_state() -> bool:
	return _code != null and is_instance_valid(_code) and not _entries.is_empty()


func _get_font() -> Font:
	return _code.get_theme_font(&"font")


func _get_font_size() -> int:
	var fs := _code.get_theme_font_size(&"font_size")
	return fs if fs > 0 else 16


func _get_hover_color(color: Color) -> Color:
	var hc := color * Color(1.4, 1.4, 1.4, 1.0)
	hc.a = minf(1.0, color.a * 1.4)
	return hc


func _get_visible_line_range() -> Vector2i:
	var first := 0
	var last := _code.get_line_count() - 1
	if _code.has_method("get_first_visible_line"):
		first = max(0, int(_code.get_first_visible_line()) - 2)
	if _code.has_method("get_last_full_visible_line"):
		last = mini(_code.get_line_count() - 1, int(_code.get_last_full_visible_line()) + 2)
	return Vector2i(first, last)


func _get_baseline(top_y: float, line_height: float, font_size: int, font: Font) -> float:
	var code_ascent := font.get_ascent(font_size)
	var code_descent := font.get_descent(font_size)
	return top_y + (line_height + code_ascent - code_descent) / 2.0


func _get_horizontal_base() -> float:
	var gutter_width := float(_code.get_total_gutter_width())
	var left_margin := _code_left_content_margin()
	var h_scroll := float(_code.get_h_scroll())
	return gutter_width + left_margin - h_scroll


func _draw_entries(
	visible_range: Vector2i,
	horizontal_base: float,
	font: Font,
	font_size: int,
	label_size: int,
	label_color: Color,
	hover_color: Color
) -> void:
	var mouse_pos := get_local_mouse_position()
	var line_height := float(_code.get_line_height())
	var line_count := _code.get_line_count()

	for entry in _entries:
		var line := int(entry.get("line", -1))
		if line < 0 or line >= line_count or line < visible_range.x or line > visible_range.y:
			continue

		var symbol := str(entry.get("symbol", ""))
		var line_text := _code.get_line(line)
		if not symbol.is_empty() and line_text.find(symbol) == -1:
			continue

		var count := int(entry.get("count", 0))
		var top_y := _get_vertical_position(line, line_height)
		if top_y + line_height < 0.0 or top_y > size.y:
			continue

		var label_x := _get_horizontal_position(line_text, horizontal_base, font, font_size)
		var baseline := _get_baseline(top_y, line_height, font_size, font)

		var label_text := _format_label(count)
		var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
		var hit_rect := Rect2(label_x, top_y, text_w, line_height)

		var is_hovered := hit_rect.has_point(mouse_pos)

		draw_string(
			font,
			Vector2(label_x, baseline),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			label_size,
			hover_color if is_hovered else label_color
		)

		_hit_rects.append({"rect": hit_rect, "line": line, "symbol": symbol})


func _get_vertical_position(line: int, line_height: float) -> float:
	var scroll_pos := float(_code.get_scroll_pos_for_line(line))
	var v_scroll := float(_code.get_v_scroll())
	var top_margin := _code_top_content_margin()
	var micro_adjustment := 3
	return top_margin + (scroll_pos - v_scroll) * line_height + micro_adjustment


func _get_horizontal_position(line_text: String, horizontal_base: float, font: Font, font_size: int) -> float:
	var text_w := font.get_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var local_x := horizontal_base + text_w
	var dummy_overlay := _code_rect_to_overlay_rect(Rect2(local_x, 0, 1, 1))
	return dummy_overlay.position.x + 6.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for hr in _hit_rects:
				if (hr["rect"] as Rect2).has_point(mb.position):
					label_clicked.emit(int(hr["line"]), str(hr["symbol"]))
					return


func _code_rect_to_overlay_rect(r: Rect2) -> Rect2:
	var code_xform := _code.get_global_transform()
	var overlay_inv := get_global_transform().affine_inverse()
	var s: Vector2 = overlay_inv * (code_xform * r.position)
	var e: Vector2 = overlay_inv * (code_xform * (r.position + r.size))
	return Rect2(s, e - s).abs()


func _code_left_content_margin() -> float:
	var sb := _code.get_theme_stylebox(&"normal")
	return sb.get_content_margin(SIDE_LEFT) if sb != null else 0.0


func _code_top_content_margin() -> float:
	var sb := _code.get_theme_stylebox(&"normal")
	return sb.get_content_margin(SIDE_TOP) if sb != null else 0.0


func _format_label(count: int) -> String:
	return "1 reference" if count == 1 else str(count) + " references"


func _label_color() -> Color:
	if _color_setting != &"":
		var settings := EditorInterface.get_editor_settings()
		if settings != null and settings.has_setting(_color_setting):
			var v = settings.get_setting(_color_setting)
			if typeof(v) == TYPE_COLOR:
				return v
	return DEFAULT_LABEL_COLOR


func _connect_scrollbars() -> void:
	if _code == null or not is_instance_valid(_code):
		return
	_v_scroll_bar = _code.get_v_scroll_bar()
	_h_scroll_bar = _code.get_h_scroll_bar()
	_connect_scrollbar(_v_scroll_bar)
	_connect_scrollbar(_h_scroll_bar)


func _disconnect_scrollbars() -> void:
	_disconnect_scrollbar(_v_scroll_bar)
	_disconnect_scrollbar(_h_scroll_bar)
	_v_scroll_bar = null
	_h_scroll_bar = null


func _connect_scrollbar(bar: ScrollBar) -> void:
	if bar == null:
		return
	if not bar.value_changed.is_connected(_on_scroll_changed):
		bar.value_changed.connect(_on_scroll_changed)
	if not bar.changed.is_connected(_on_scroll_bar_changed):
		bar.changed.connect(_on_scroll_bar_changed)


func _disconnect_scrollbar(bar: ScrollBar) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	if bar.value_changed.is_connected(_on_scroll_changed):
		bar.value_changed.disconnect(_on_scroll_changed)
	if bar.changed.is_connected(_on_scroll_bar_changed):
		bar.changed.disconnect(_on_scroll_bar_changed)


func _on_scroll_changed(_value: float) -> void:
	queue_redraw()


func _on_scroll_bar_changed() -> void:
	queue_redraw()
