@tool
extends PopupPanel

const MIN_POPUP_WIDTH := 280
const POPUP_SIZE_SCALE := 1.5
const MAX_POPUP_WIDTH_PERCENT := 90
const MAX_VISIBLE_LINES := 12
const POPUP_HORIZONTAL_PADDING := 24
const CODE_HORIZONTAL_CHROME := 44
const POPUP_VERTICAL_CHROME := 58
const SCROLLBAR_ALLOWANCE := 18
const POPUP_VERTICAL_PADDING := 22
const CONTENT_SEPARATION := 8
const TEXT_EDIT_CONTENT_PADDING := 10
const ANCHOR_OFFSET := Vector2i(6, 6)

var _heading := Label.new()
var _message := Label.new()
var _previous_code := CodeEdit.new()
var _margin := MarginContainer.new()
var _content := VBoxContainer.new()


func _init() -> void:
	title = "Git Change"
	transient = true
	unresizable = false

	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 12)
	_margin.add_theme_constant_override("margin_top", 10)
	_margin.add_theme_constant_override("margin_right", 12)
	_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(_margin)

	_content.add_theme_constant_override("separation", CONTENT_SEPARATION)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_heading)
	_content.add_child(_message)
	_content.add_child(_previous_code)
	_margin.add_child(_content)

	_heading.clip_text = true
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.visible = false
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_previous_code.editable = false
	_previous_code.minimap_draw = false
	_previous_code.gutters_draw_line_numbers = false
	_previous_code.scroll_fit_content_width = true
	_previous_code.scroll_fit_content_height = true
	_previous_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previous_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_previous_code.custom_minimum_size = Vector2.ZERO


func show_change(
	change: Dictionary,
	anchor_screen_position: Vector2i = Vector2i(-1, -1),
	editor_screen_rect: Rect2i = Rect2i()
) -> void:
	var old_lines := _old_lines(change)
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
		_previous_code.text = "\n".join(old_lines)
		_previous_code.visible = true
		_previous_code.set_caret_line(0, false)
		_previous_code.set_caret_column(0, false)
		_previous_code.scroll_vertical = 0
		_previous_code.scroll_horizontal = 0

	if is_inside_tree():
		if editor_screen_rect.size.x > 0 and editor_screen_rect.size.y > 0:
			_popup_near_anchor(old_lines, anchor_screen_position, editor_screen_rect)
		else:
			popup_centered_clamped()


static func popup_size_for_metrics(
	editor_size: Vector2i,
	content_width: int,
	heading_width: int,
	line_count: int,
	line_height: int,
	horizontal_chrome: int = CODE_HORIZONTAL_CHROME,
	vertical_chrome: int = POPUP_VERTICAL_CHROME,
	scrollbar_allowance: int = SCROLLBAR_ALLOWANCE
) -> Vector2i:
	var safe_editor_size := Vector2i(maxi(1, editor_size.x), maxi(1, editor_size.y))
	# Start near half the editor width, leave room for the popup and CodeEdit
	# chrome, then add breathing room because embedded popup coordinates and the
	# editor theme can be scaled independently on high-DPI displays.
	var max_width := mini(
		safe_editor_size.x,
		mini(
			ceili(
				(safe_editor_size.x / 2.0 + horizontal_chrome)
				* POPUP_SIZE_SCALE
			),
			safe_editor_size.x * MAX_POPUP_WIDTH_PERCENT / 100
		)
	)
	max_width = maxi(1, max_width)
	var min_width := mini(MIN_POPUP_WIDTH, max_width)
	var requested_width := maxi(
		min_width,
		maxi(
			maxi(0, content_width) + horizontal_chrome,
			maxi(0, heading_width) + POPUP_HORIZONTAL_PADDING
		)
	)
	var popup_width := mini(ceili(requested_width * POPUP_SIZE_SCALE), max_width)
	var visible_lines := mini(MAX_VISIBLE_LINES, maxi(1, line_count))
	var code_height := visible_lines * maxi(1, line_height)
	if content_width + horizontal_chrome > popup_width:
		code_height += scrollbar_allowance
	var popup_height := mini(
		ceili((vertical_chrome + code_height) * POPUP_SIZE_SCALE),
		safe_editor_size.y
	)
	return Vector2i(popup_width, popup_height)


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
	var content_width := _widest_content_width(old_lines)
	var heading_width := _label_text_width(_heading)
	if old_lines.is_empty():
		content_width = _label_text_width(_message)
	var layout_metrics := _layout_metrics(old_lines.size())
	var popup_size := popup_size_for_metrics(
		editor_screen_rect.size,
		content_width,
		heading_width,
		maxi(1, old_lines.size()),
		_previous_code.get_line_height(),
		int(layout_metrics.horizontal_chrome),
		int(layout_metrics.vertical_chrome),
		int(layout_metrics.horizontal_scrollbar_height)
	)
	var code_area_height := maxi(1, popup_size.y - int(layout_metrics.outer_vertical_chrome))
	var content_area_width := maxi(1, popup_size.x - POPUP_HORIZONTAL_PADDING)
	# PopupPanel otherwise shrinks a requested rectangle back to its contents'
	# natural minimum during the deferred window layout pass.
	max_size = Vector2i.ZERO
	min_size = popup_size
	max_size = popup_size
	# PopupPanel reads its direct child's cached minimum size before the deferred
	# maximum-size propagation reaches the full container tree. Bound the direct
	# child as well so the popup never opens larger internally and gets clipped.
	_margin.custom_maximum_size = Vector2(popup_size)
	_content.custom_maximum_size = Vector2(
		content_area_width,
		maxi(1, popup_size.y - POPUP_VERTICAL_PADDING)
	)
	_heading.custom_maximum_size = Vector2(content_area_width, -1)
	_message.custom_maximum_size = Vector2(content_area_width, -1)
	_previous_code.custom_minimum_size = Vector2.ZERO
	_previous_code.custom_maximum_size = Vector2(
		content_area_width,
		code_area_height
	)
	popup(popup_rect_for_anchor(
		anchor_screen_position,
		popup_size,
		editor_screen_rect
	))


func _layout_metrics(line_count: int) -> Dictionary:
	var code_style := _previous_code.get_theme_stylebox(&"read_only")
	var code_style_size := code_style.get_minimum_size()
	var outer_vertical_chrome := (
		POPUP_VERTICAL_PADDING
		+ CONTENT_SEPARATION
		+ ceili(_heading.get_combined_minimum_size().y)
	)
	var horizontal_chrome := (
		POPUP_HORIZONTAL_PADDING
		+ ceili(code_style_size.x)
		+ TEXT_EDIT_CONTENT_PADDING
	)
	if line_count > MAX_VISIBLE_LINES:
		horizontal_chrome += ceili(
			_previous_code.get_v_scroll_bar().get_combined_minimum_size().x
		)
	return {
		"horizontal_chrome": horizontal_chrome,
		"vertical_chrome": outer_vertical_chrome + ceili(code_style_size.y),
		"outer_vertical_chrome": outer_vertical_chrome,
		"horizontal_scrollbar_height": ceili(
			_previous_code.get_h_scroll_bar().get_combined_minimum_size().y
		),
	}


func _widest_content_width(lines: Array[String]) -> int:
	var font := _previous_code.get_theme_font(&"font")
	var font_size := _previous_code.get_theme_font_size(&"font_size")
	var width := 0.0
	for line in lines:
		width = maxf(
			width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	return ceili(width)


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
