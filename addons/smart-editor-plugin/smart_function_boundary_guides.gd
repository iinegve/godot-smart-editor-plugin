@tool
extends Control

const DEFAULT_GUIDE_COLOR := Color(0.78, 0.78, 0.78, 0.18)
const GUIDE_WIDTH := 1.0

var _enabled_setting: StringName = &""
var _color_setting: StringName = &""
var _code: CodeEdit
var _v_scroll_bar: VScrollBar
var _h_scroll_bar: HScrollBar
var _boundaries: Array[Dictionary] = []
var _boundaries_dirty := true
var _folded_lines_signature := ""
var _line_top_offset := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func _process(_delta: float) -> void:
	if _code == null or not is_instance_valid(_code):
		return

	var next_signature := _current_folded_lines_signature()
	if next_signature == _folded_lines_signature:
		return

	_folded_lines_signature = next_signature
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_line_top_offset = -1.0
		_invalidate_boundaries()


func _exit_tree() -> void:
	_disconnect_code()
	_disconnect_editor_settings()


func configure(enabled_setting: StringName, color_setting: StringName) -> void:
	_disconnect_editor_settings()
	_enabled_setting = enabled_setting
	_color_setting = color_setting
	_connect_editor_settings()
	_invalidate_boundaries()


func attach_to_code(code: CodeEdit) -> void:
	_disconnect_code()
	_code = code
	_line_top_offset = -1.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_connect_code()
	_folded_lines_signature = _current_folded_lines_signature()
	set_process(true)
	_invalidate_boundaries()


static func function_boundaries(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines := text.split("\n", true)
	for line_index in lines.size():
		var line := lines[line_index]
		if not _is_function_header(line):
			continue

		var function_indent := _indent_columns(line)
		var signature_end_line := _function_signature_end_line(lines, line_index)
		var end_line := signature_end_line
		var search_line := signature_end_line + 1
		while search_line < lines.size():
			var body_line := lines[search_line]
			if body_line.strip_edges().is_empty():
				search_line += 1
				continue

			if _indent_columns(body_line) <= function_indent:
				break

			end_line = search_line
			search_line += 1

		result.append({
			"header_line": line_index,
			"end_line": end_line,
			"indent": function_indent,
		})

	return result


static func _function_signature_end_line(lines: PackedStringArray, header_line: int) -> int:
	var paren_depth := 0
	var bracket_depth := 0
	var brace_depth := 0
	var quote := ""
	var escaped := false

	var line_index := header_line
	while line_index < lines.size():
		var line := lines[line_index]
		for index in line.length():
			var ch := line[index]
			if not quote.is_empty():
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == quote:
					quote = ""
				continue

			if ch == "\"" or ch == "'":
				quote = ch
				continue

			if ch == "(":
				paren_depth += 1
			elif ch == ")":
				paren_depth = maxi(0, paren_depth - 1)
			elif ch == "[":
				bracket_depth += 1
			elif ch == "]":
				bracket_depth = maxi(0, bracket_depth - 1)
			elif ch == "{":
				brace_depth += 1
			elif ch == "}":
				brace_depth = maxi(0, brace_depth - 1)
			elif ch == ":" and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0:
				return line_index

		line_index += 1

	return header_line


func _draw() -> void:
	if _code == null or not is_instance_valid(_code) or not _is_enabled():
		return

	if _boundaries_dirty:
		_rebuild_boundaries()

	var guide_color := _guide_color()
	var visible_lines := _visible_line_range()
	for boundary in _boundaries:
		var header_line := int(boundary.get("header_line", -1))
		var end_line := int(boundary.get("end_line", -1))
		var guide_line := _boundary_guide_line(header_line, end_line)
		if guide_line < visible_lines.x or guide_line > visible_lines.y:
			continue

		var y := _boundary_guide_y(header_line, end_line)
		if y < 0.0 or y > size.y:
			continue

		var start_x := _guide_start_x()
		if start_x >= size.x:
			continue

		draw_line(Vector2(start_x, y), Vector2(size.x, y), guide_color, GUIDE_WIDTH)


func _rebuild_boundaries() -> void:
	_boundaries = function_boundaries(_get_code_text(_code))
	_boundaries_dirty = false


static func guide_y_for_gap_rects(
	end_line_rect: Rect2,
	first_blank_line_rect: Rect2,
	last_blank_line_rect: Rect2,
	has_blank_gap: bool
) -> float:
	if has_blank_gap:
		var gap_start := first_blank_line_rect.position.y
		var gap_end := last_blank_line_rect.position.y + last_blank_line_rect.size.y
		return (gap_start + gap_end) * 0.5

	return end_line_rect.position.y + end_line_rect.size.y


static func guide_start_x_for_gutter(total_gutter_width: float, left_margin: float) -> float:
	return maxf(0.0, total_gutter_width + left_margin)


static func line_rect_for_scroll_position(
	line_scroll_position: float,
	vertical_scroll: float,
	line_height: float,
	content_top: float,
	width: float
) -> Rect2:
	return Rect2(
		0.0,
		content_top + (line_scroll_position - vertical_scroll) * line_height,
		width,
		line_height
	)


static func guide_y_for_folded_function_rects(
	header_line_rect: Rect2,
	first_blank_line_rect: Rect2,
	last_blank_line_rect: Rect2,
	has_visible_blank_gap: bool
) -> float:
	if has_visible_blank_gap:
		return guide_y_for_gap_rects(header_line_rect, first_blank_line_rect, last_blank_line_rect, true)

	return header_line_rect.position.y + header_line_rect.size.y


static func folded_lines_signature(folded_lines: PackedInt32Array) -> String:
	var lines := Array(folded_lines)
	lines.sort()

	var parts: Array[String] = []
	for line in lines:
		parts.append(str(line))

	return ",".join(parts)


func _boundary_guide_line(header_line: int, end_line: int) -> int:
	if _is_line_folded(header_line):
		var gap := _blank_gap_after(end_line)
		if gap.x != -1:
			return int(floor((gap.x + gap.y) * 0.5))

		return header_line

	return _guide_line(end_line)


func _boundary_guide_y(header_line: int, end_line: int) -> float:
	if _is_line_folded(header_line):
		return _folded_function_guide_y(header_line, end_line)

	return _guide_y(end_line)


func _folded_function_guide_y(header_line: int, end_line: int) -> float:
	if _code == null or not is_instance_valid(_code):
		return -1.0
	if header_line < 0 or header_line >= _code.get_line_count():
		return -1.0

	var header_line_rect := _line_overlay_rect(header_line)
	if header_line_rect.position.y < 0.0:
		return -1.0

	var gap := _blank_gap_after(end_line)
	var has_visible_blank_gap := gap.x != -1
	var first_blank_line_rect := Rect2()
	var last_blank_line_rect := Rect2()
	if has_visible_blank_gap:
		first_blank_line_rect = _line_overlay_rect(gap.x)
		last_blank_line_rect = _line_overlay_rect(gap.y)
		if first_blank_line_rect.position.y < 0.0 or last_blank_line_rect.position.y < 0.0:
			has_visible_blank_gap = false

	return guide_y_for_folded_function_rects(
		header_line_rect,
		first_blank_line_rect,
		last_blank_line_rect,
		has_visible_blank_gap
	)


func _guide_line(line: int) -> int:
	var gap := _blank_gap_after(line)
	if gap.x != -1:
		return int(floor((gap.x + gap.y) * 0.5))

	return line


func _guide_y(line: int) -> float:
	if _code == null or not is_instance_valid(_code):
		return -1.0
	if line < 0 or line >= _code.get_line_count():
		return -1.0

	var end_line_rect := _line_overlay_rect(line)
	if end_line_rect.position.y < 0.0:
		return -1.0

	var gap := _blank_gap_after(line)
	var has_blank_gap := gap.x != -1
	var first_blank_line_rect := Rect2()
	var last_blank_line_rect := Rect2()
	if has_blank_gap:
		first_blank_line_rect = _line_overlay_rect(gap.x)
		last_blank_line_rect = _line_overlay_rect(gap.y)
		if first_blank_line_rect.position.y < 0.0 or last_blank_line_rect.position.y < 0.0:
			has_blank_gap = false

	return guide_y_for_gap_rects(end_line_rect, first_blank_line_rect, last_blank_line_rect, has_blank_gap)


func _guide_start_x() -> float:
	if _code == null or not is_instance_valid(_code):
		return 0.0

	return guide_start_x_for_gutter(float(_code.get_total_gutter_width()), _code_left_content_margin())


func _line_overlay_rect(line: int) -> Rect2:
	var direct_rect := Rect2(_code.get_rect_at_line_column(line, 0))
	if direct_rect.position.y >= 0.0 and direct_rect.size.y > 0.0:
		var overlay_rect := _code_rect_to_overlay_rect(direct_rect)
		_remember_line_top_offset(line, overlay_rect)
		return overlay_rect

	return _line_overlay_rect_from_scroll_position(line)


func _line_overlay_rect_from_scroll_position(line: int) -> Rect2:
	if _code == null or not is_instance_valid(_code):
		return Rect2()
	if not _code.has_method("get_scroll_pos_for_line"):
		return Rect2()

	var line_height := float(_code.get_line_height())
	if line_height <= 0.0:
		return Rect2()

	return line_rect_for_scroll_position(
		float(_code.get_scroll_pos_for_line(line)),
		float(_code.get_v_scroll()),
		line_height,
		_line_content_top_offset(),
		size.x
	)


func _remember_line_top_offset(line: int, overlay_rect: Rect2) -> void:
	if _code == null or not is_instance_valid(_code):
		return
	if not _code.has_method("get_scroll_pos_for_line"):
		return

	var line_height := float(_code.get_line_height())
	if line_height <= 0.0:
		return

	_line_top_offset = overlay_rect.position.y - (float(_code.get_scroll_pos_for_line(line)) - float(_code.get_v_scroll())) * line_height


func _line_content_top_offset() -> float:
	if _line_top_offset >= 0.0:
		return _line_top_offset

	return _code_top_content_margin() + 2.0


func _code_left_content_margin() -> float:
	if _code == null or not is_instance_valid(_code):
		return 0.0

	var stylebox := _code.get_theme_stylebox("normal")
	if stylebox == null:
		return 0.0

	return stylebox.get_content_margin(SIDE_LEFT)


func _code_top_content_margin() -> float:
	if _code == null or not is_instance_valid(_code):
		return 0.0

	var stylebox := _code.get_theme_stylebox("normal")
	if stylebox == null:
		return 0.0

	return stylebox.get_content_margin(SIDE_TOP)


func _is_line_folded(line: int) -> bool:
	if _code == null or not is_instance_valid(_code):
		return false
	if line < 0 or line >= _code.get_line_count():
		return false

	return _code.is_line_folded(line)


func _blank_gap_after(line: int) -> Vector2i:
	if _code == null or not is_instance_valid(_code):
		return Vector2i(-1, -1)
	if line + 1 >= _code.get_line_count():
		return Vector2i(-1, -1)

	var first_blank_line := -1
	var last_blank_line := -1
	var search_line := line + 1
	while search_line < _code.get_line_count():
		if not _code.get_line(search_line).strip_edges().is_empty():
			break

		if first_blank_line == -1:
			first_blank_line = search_line
		last_blank_line = search_line
		search_line += 1

	return Vector2i(first_blank_line, last_blank_line)


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
		return Vector2i(0, max(0, _code.get_line_count() - 1))

	var first := max(0, int(_code.call("get_first_visible_line")) - 1)
	var last := int(_code.call("get_last_full_visible_line"))
	if last < first:
		last = first + int(_code.call("get_visible_line_count")) + 1 if _code.has_method("get_visible_line_count") else _code.get_line_count() - 1
	last = mini(_code.get_line_count() - 1, last + 1)
	return Vector2i(first, last)


func _connect_code() -> void:
	if _code == null or not is_instance_valid(_code):
		return

	if not _code.text_changed.is_connected(_on_code_changed):
		_code.text_changed.connect(_on_code_changed)
	if not _code.resized.is_connected(_on_code_changed):
		_code.resized.connect(_on_code_changed)

	_v_scroll_bar = _code.get_v_scroll_bar()
	if _v_scroll_bar != null and not _v_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_v_scroll_bar.value_changed.connect(_on_scroll_changed)
	if _v_scroll_bar != null and not _v_scroll_bar.changed.is_connected(_on_scroll_bar_changed):
		_v_scroll_bar.changed.connect(_on_scroll_bar_changed)

	_h_scroll_bar = _code.get_h_scroll_bar()
	if _h_scroll_bar != null and not _h_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_h_scroll_bar.value_changed.connect(_on_scroll_changed)
	if _h_scroll_bar != null and not _h_scroll_bar.changed.is_connected(_on_scroll_bar_changed):
		_h_scroll_bar.changed.connect(_on_scroll_bar_changed)


func _disconnect_code() -> void:
	if _code != null and is_instance_valid(_code):
		if _code.text_changed.is_connected(_on_code_changed):
			_code.text_changed.disconnect(_on_code_changed)
		if _code.resized.is_connected(_on_code_changed):
			_code.resized.disconnect(_on_code_changed)

	if _v_scroll_bar != null and is_instance_valid(_v_scroll_bar) and _v_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_v_scroll_bar.value_changed.disconnect(_on_scroll_changed)
	if _v_scroll_bar != null and is_instance_valid(_v_scroll_bar) and _v_scroll_bar.changed.is_connected(_on_scroll_bar_changed):
		_v_scroll_bar.changed.disconnect(_on_scroll_bar_changed)
	if _h_scroll_bar != null and is_instance_valid(_h_scroll_bar) and _h_scroll_bar.value_changed.is_connected(_on_scroll_changed):
		_h_scroll_bar.value_changed.disconnect(_on_scroll_changed)
	if _h_scroll_bar != null and is_instance_valid(_h_scroll_bar) and _h_scroll_bar.changed.is_connected(_on_scroll_bar_changed):
		_h_scroll_bar.changed.disconnect(_on_scroll_bar_changed)

	_code = null
	_v_scroll_bar = null
	_h_scroll_bar = null
	_folded_lines_signature = ""
	set_process(false)


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


func _invalidate_boundaries() -> void:
	_boundaries.clear()
	_boundaries_dirty = true
	queue_redraw()


func _is_enabled() -> bool:
	if _enabled_setting == &"":
		return true

	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(_enabled_setting):
		return true

	return bool(settings.get_setting(_enabled_setting))


func _guide_color() -> Color:
	if _color_setting == &"":
		return DEFAULT_GUIDE_COLOR

	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(_color_setting):
		return DEFAULT_GUIDE_COLOR

	var value = settings.get_setting(_color_setting)
	if typeof(value) != TYPE_COLOR:
		return DEFAULT_GUIDE_COLOR

	return value


func _on_code_changed() -> void:
	_invalidate_boundaries()


func _on_scroll_changed(_value: float) -> void:
	queue_redraw()


func _on_scroll_bar_changed() -> void:
	queue_redraw()


func _on_editor_settings_changed() -> void:
	_invalidate_boundaries()


func _current_folded_lines_signature() -> String:
	if _code == null or not is_instance_valid(_code):
		return ""

	return folded_lines_signature(_code.get_folded_lines())


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for line_index in code.get_line_count():
		lines.append(code.get_line(line_index))
	return "\n".join(lines)


static func _is_function_header(line: String) -> bool:
	var trimmed := line.strip_edges(true, false)
	return (
		trimmed.begins_with("func ")
		or trimmed.begins_with("func\t")
		or trimmed.begins_with("static func ")
		or trimmed.begins_with("static func\t")
	)


static func _indent_columns(line: String) -> int:
	var result := 0
	for index in line.length():
		var ch := line[index]
		if ch != "\t" and ch != " ":
			break
		result += 1
	return result
