@tool
extends PopupPanel

const MAX_POPUP_WIDTH_PERCENT := 90
const MAX_VISIBLE_LINES := 12
const POPUP_PADDING := 8
const CONTENT_SEPARATION := 6
const TEXT_EDIT_CONTENT_PADDING := 10
const ANCHOR_OFFSET := Vector2i(6, 6)

var _heading := Label.new()
var _message := Label.new()
var _previous_code := CodeEdit.new()
var _content := VBoxContainer.new()
var _panel_style_needs_update := true


func _init() -> void:
	title = "Git Change"
	transient = true
	unresizable = true
	# Size the viewport explicitly on both Godot 4.6 and 4.7, rather than letting
	# the contents' minimum size resize the window during deferred layout.
	wrap_controls = false

	_content.clip_contents = true
	_content.add_theme_constant_override("separation", CONTENT_SEPARATION)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_heading)
	_content.add_child(_message)
	_content.add_child(_previous_code)
	add_child(_content)

	_heading.clip_text = true
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.visible = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_previous_code.editable = false
	_previous_code.minimap_draw = false
	_previous_code.gutters_draw_line_numbers = false
	_previous_code.scroll_fit_content_width = false
	_previous_code.scroll_fit_content_height = false
	_previous_code.scroll_past_end_of_file = false
	_previous_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previous_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_previous_code.custom_minimum_size = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_panel_style_needs_update = true


func show_change(
	change: Dictionary,
	anchor_screen_position: Vector2i = Vector2i(-1, -1),
	editor_screen_rect: Rect2i = Rect2i()
) -> void:
	var source_code := get_parent() as CodeEdit
	if source_code != null:
		_previous_code.indent_size = source_code.indent_size
	var old_lines := _old_lines(change)
	var displayed_lines := preview_lines(old_lines, _previous_code.indent_size)
	if old_lines.is_empty():
		_heading.text = "Added code"
		_message.text = "This code has no previous version in HEAD."
		_message.visible = true
		_previous_code.text = ""
		_previous_code.visible = false
	else:
		_heading.text = _previous_lines_heading(
			int(change.get("old_start", 0)),
			old_lines.size()
		)
		_message.visible = false
		_previous_code.text = "\n".join(displayed_lines)
		_previous_code.visible = true
		_previous_code.set_caret_line(0, false)
		_previous_code.set_caret_column(0, false)
		_previous_code.scroll_vertical = 0
		_previous_code.scroll_horizontal = 0

	if is_inside_tree():
		_update_panel_style()
		if editor_screen_rect.size.x > 0 and editor_screen_rect.size.y > 0:
			_popup_near_anchor(displayed_lines, anchor_screen_position, editor_screen_rect)
		else:
			var available_size := Vector2i(get_parent().get_viewport().get_visible_rect().size)
			var popup_size := _size_for_content(displayed_lines, available_size)
			min_size = popup_size
			popup_centered_clamped(popup_size)


static func preview_lines(lines: Array[String], tab_size: int = 4) -> Array[String]:
	var safe_tab_size := maxi(1, tab_size)
	var common_indent := -1
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		var indent := _indentation(line, safe_tab_size)
		common_indent = indent.y if common_indent < 0 else mini(common_indent, indent.y)
	if common_indent <= 0:
		return lines.duplicate()

	var result: Array[String] = []
	for line in lines:
		if line.strip_edges().is_empty():
			result.append("")
		elif common_indent % safe_tab_size != 0:
			# Removing part of a tab stop shifts subsequent tabs. Use spaces in
			# this case to preserve the original relative visual indentation.
			var indent := _indentation(line, safe_tab_size)
			result.append(" ".repeat(indent.y - common_indent) + line.substr(indent.x))
		else:
			var removed_columns := 0
			var removed_chars := 0
			while removed_columns < common_indent:
				if line[removed_chars] == "\t":
					removed_columns += safe_tab_size - removed_columns % safe_tab_size
				else:
					removed_columns += 1
				removed_chars += 1
			result.append(line.substr(removed_chars))
	return result


static func _indentation(line: String, tab_size: int) -> Vector2i:
	var chars := 0
	var columns := 0
	while chars < line.length():
		if line[chars] == "\t":
			columns += tab_size - columns % tab_size
		elif line[chars] == " ":
			columns += 1
		else:
			break
		chars += 1
	return Vector2i(chars, columns)


static func popup_size_for_metrics(
	editor_size: Vector2i,
	content_width: int,
	heading_width: int,
	line_count: int,
	line_height: int,
	horizontal_chrome: int,
	vertical_chrome: int,
	horizontal_scrollbar_height: int = 0,
	vertical_scrollbar_width: int = 0,
	heading_horizontal_padding: int = 0
) -> Vector2i:
	var safe_editor_size := Vector2i(maxi(1, editor_size.x), maxi(1, editor_size.y))
	var max_width := maxi(1, safe_editor_size.x * MAX_POPUP_WIDTH_PERCENT / 100)
	var total_lines := maxi(1, line_count)
	var row_height := maxi(1, line_height)
	var visible_lines := mini(MAX_VISIBLE_LINES, total_lines)
	var needs_vertical_scroll := (
		total_lines > visible_lines
		or vertical_chrome + total_lines * row_height > safe_editor_size.y
	)
	var popup_size := Vector2i.ONE
	# A horizontal scrollbar can reduce the available height enough to require
	# a vertical one too. Reserve its width in a second sizing pass.
	for _pass in 2:
		var code_width := maxi(0, content_width) + horizontal_chrome
		if needs_vertical_scroll:
			code_width += vertical_scrollbar_width
		popup_size.x = mini(maxi(code_width, heading_width + heading_horizontal_padding), max_width)
		var scrollbar_height := horizontal_scrollbar_height if code_width > popup_size.x else 0
		popup_size.y = mini(
			vertical_chrome + visible_lines * row_height + scrollbar_height,
			safe_editor_size.y
		)
		needs_vertical_scroll = (
			needs_vertical_scroll
			or total_lines * row_height > popup_size.y - vertical_chrome - scrollbar_height
		)
	return popup_size


static func popup_rect_for_anchor(
	anchor_screen_position: Vector2i,
	requested_size: Vector2i,
	editor_screen_rect: Rect2i
) -> Rect2i:
	var popup_size := Vector2i(
		mini(requested_size.x, editor_screen_rect.size.x),
		mini(requested_size.y, editor_screen_rect.size.y)
	)
	var position := anchor_screen_position + ANCHOR_OFFSET
	position.x = clampi(
		position.x,
		editor_screen_rect.position.x,
		editor_screen_rect.end.x - popup_size.x
	)
	position.y = clampi(
		position.y,
		editor_screen_rect.position.y,
		editor_screen_rect.end.y - popup_size.y
	)
	return Rect2i(position, popup_size)


func _popup_near_anchor(
	old_lines: Array[String],
	anchor_screen_position: Vector2i,
	editor_screen_rect: Rect2i
) -> void:
	var popup_size := _size_for_content(old_lines, editor_screen_rect.size)
	min_size = popup_size
	popup(popup_rect_for_anchor(
		anchor_screen_position,
		popup_size,
		editor_screen_rect
	))


func _size_for_content(lines: Array[String], available_size: Vector2i) -> Vector2i:
	var panel_size := get_theme_stylebox(&"panel").get_minimum_size()
	var heading_width := _label_text_width(_heading)
	if lines.is_empty():
		var popup_width := mini(
			maxi(heading_width, _label_text_width(_message)) + ceili(panel_size.x),
			maxi(1, available_size.x * MAX_POPUP_WIDTH_PERCENT / 100)
		)
		_message.size.x = maxi(1, popup_width - ceili(panel_size.x))
		var popup_height := ceili(
			panel_size.y + _heading.get_combined_minimum_size().y
			+ _content.get_theme_constant(&"separation") + _message.get_minimum_size().y
		)
		return Vector2i(popup_width, mini(popup_height, maxi(1, available_size.y)))
	var metrics := _layout_metrics()
	return popup_size_for_metrics(
		available_size,
		_widest_content_width(),
		heading_width,
		lines.size(),
		_previous_code.get_line_height(),
		int(metrics.horizontal_chrome),
		int(metrics.vertical_chrome),
		int(metrics.horizontal_scrollbar_height),
		int(metrics.vertical_scrollbar_width),
		ceili(panel_size.x)
	)


func _update_panel_style() -> void:
	if not _panel_style_needs_update:
		return
	if has_theme_stylebox_override(&"panel"):
		remove_theme_stylebox_override(&"panel")
	var style := get_theme_stylebox(&"panel").duplicate() as StyleBox
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	style.set_content_margin_all(roundf(POPUP_PADDING * editor_scale))
	add_theme_stylebox_override(&"panel", style)
	_content.add_theme_constant_override("separation", roundi(CONTENT_SEPARATION * editor_scale))
	_panel_style_needs_update = false


func _layout_metrics() -> Dictionary:
	var code_style := _previous_code.get_theme_stylebox(&"read_only")
	var code_style_size := code_style.get_minimum_size()
	var panel_size := get_theme_stylebox(&"panel").get_minimum_size()
	var vertical_chrome := (
		ceili(panel_size.y)
		+ _content.get_theme_constant(&"separation")
		+ ceili(_heading.get_combined_minimum_size().y)
		+ ceili(code_style_size.y)
	)
	var horizontal_chrome := (
		ceili(panel_size.x)
		+ ceili(code_style_size.x)
		+ TEXT_EDIT_CONTENT_PADDING
	)
	return {
		"horizontal_chrome": horizontal_chrome,
		"vertical_chrome": vertical_chrome,
		"horizontal_scrollbar_height": ceili(
			_previous_code.get_h_scroll_bar().get_combined_minimum_size().y
		),
		"vertical_scrollbar_width": ceili(
			_previous_code.get_v_scroll_bar().get_combined_minimum_size().x
		),
	}


func _widest_content_width() -> int:
	var width := 0
	for line in _previous_code.get_line_count():
		width = maxi(width, _previous_code.get_line_width(line))
	return width


func _label_text_width(label: Label) -> int:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	return ceili(font.get_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x)


func _old_lines(change: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var lines: Variant = change.get("old_lines", [])
	if lines is Array:
		for line in lines:
			result.append(str(line))
	return result


func _previous_lines_heading(old_start: int, old_count: int) -> String:
	var first_line := old_start + 1
	if old_count <= 1:
		return "Previous version (HEAD) — line %d" % first_line
	return "Previous version (HEAD) — lines %d–%d" % [
		first_line,
		first_line + old_count - 1,
	]
