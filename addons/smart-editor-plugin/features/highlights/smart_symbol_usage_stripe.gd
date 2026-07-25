@tool
extends Control

signal usage_clicked(reference: Dictionary)

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const STRIPE_WIDTH := 8.0
const MARK_HEIGHT := 3.0
const CURRENT_MARK_HEIGHT := 5.0

var _code: CodeEdit
var _source_references: Array[Dictionary] = []
var _markers: Array[Dictionary] = []
var _current_reference := {}
var _folded_lines: Array = []
var _visible_row_count := -1
var _code_width := -1.0
var _layout_dirty := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(STRIPE_WIDTH, 0)
	tooltip_text = "Highlights Stripe"
	set_process(_code != null and not _source_references.is_empty())
	if is_processing():
		_sync_visual_state(true)


func _exit_tree() -> void:
	_disconnect_code()


func _process(_delta: float) -> void:
	_sync_visual_state()


func attach_to_code(code: CodeEdit) -> void:
	if _code == code:
		return

	_disconnect_code()
	_code = code
	_layout_dirty = true

	if _code != null:
		_code_width = _code.size.x
		if not _code.resized.is_connected(_on_code_resized):
			_code.resized.connect(_on_code_resized)

	set_process(_code != null and not _source_references.is_empty())
	if is_processing():
		_sync_visual_state(true)
	else:
		_markers.clear()
		queue_redraw()


func set_usage_references(references: Array[Dictionary], _line_count: int, current_reference: Dictionary) -> void:
	_source_references = references.duplicate(true)
	_current_reference = current_reference.duplicate()

	if _source_references.is_empty():
		_markers.clear()
		_folded_lines.clear()
		_visible_row_count = -1
		set_process(false)
		queue_redraw()
		return

	set_process(_code != null)
	_sync_visual_state(true)


func clear_references() -> void:
	_source_references.clear()
	_markers.clear()
	_current_reference.clear()
	_folded_lines.clear()
	_visible_row_count = -1
	_layout_dirty = true
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if _visible_row_count <= 0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.12))
	for marker in _markers:
		var is_current := bool(marker["is_current"])
		var mark_height := CURRENT_MARK_HEIGHT if is_current else MARK_HEIGHT
		var mark_width := STRIPE_WIDTH if is_current else STRIPE_WIDTH - 2.0
		var x := 0.0 if is_current else 1.0
		var y := SymbolUsageModel.reference_y(int(marker["visual_row"]), _visible_row_count, size.y) - mark_height * 0.5
		y = clampf(y, 0.0, maxf(0.0, size.y - mark_height))

		var color := Color(1.0, 0.82, 0.32, 0.95) if is_current else Color(0.45, 0.72, 1.0, 0.78)
		draw_rect(Rect2(Vector2(x, y), Vector2(mark_width, mark_height)), color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var marker := _closest_marker_for_y(mouse_event.position.y)
			if not marker.is_empty():
				usage_clicked.emit(marker["target"])
				accept_event()


func _sync_visual_state(force: bool = false) -> bool:
	if _code == null or not is_instance_valid(_code) or _source_references.is_empty():
		return false

	var next_folded_lines: Array = _code.get_folded_lines()
	var next_visible_row_count := _code.get_total_visible_line_count()
	var changed := (
		force
		or _layout_dirty
		or next_visible_row_count != _visible_row_count
		or not _same_folded_lines(_folded_lines, next_folded_lines)
	)
	if not changed:
		return false

	_folded_lines = next_folded_lines.duplicate()
	_visible_row_count = next_visible_row_count
	_layout_dirty = false
	_rebuild_markers()
	queue_redraw()
	return true


func _rebuild_markers() -> void:
	_markers.clear()
	if _code == null or not is_instance_valid(_code) or _visible_row_count <= 0:
		return

	var folded_header_set := {}
	for folded_line in _folded_lines:
		folded_header_set[int(folded_line)] = true

	var folded_marker_indices := {}
	for reference in _source_references:
		var line := clampi(int(reference.get("line", 0)), 0, maxi(0, _code.get_line_count() - 1))
		var fold_header := -1
		if _is_line_hidden(line):
			fold_header = _fold_header_for_line(line)
		elif folded_header_set.has(line):
			fold_header = line

		if fold_header >= 0:
			_append_folded_marker(fold_header, reference, folded_marker_indices)
			continue

		var target := reference.duplicate()
		var column := clampi(int(target.get("column", 0)), 0, _code.get_line(line).length())
		target["line"] = line
		target["column"] = column
		_markers.append({
			"visual_row": _visual_row_for_position(line, column),
			"target": target,
			"is_current": SymbolUsageModel.same_position(reference, _current_reference),
		})


func _append_folded_marker(fold_header: int, reference: Dictionary, folded_marker_indices: Dictionary) -> void:
	var is_current := SymbolUsageModel.same_position(reference, _current_reference)
	if folded_marker_indices.has(fold_header):
		var marker_index := int(folded_marker_indices[fold_header])
		if is_current:
			_markers[marker_index]["is_current"] = true
		return

	var column := _code.get_first_non_whitespace_column(fold_header)
	var target := {
		"line": fold_header,
		"column": column,
		"end_line": fold_header,
		"end_column": column,
	}
	folded_marker_indices[fold_header] = _markers.size()
	_markers.append({
		"visual_row": _visual_row_for_position(fold_header, column),
		"target": target,
		"is_current": is_current,
	})


func _visual_row_for_position(line: int, column: int) -> int:
	var rows_before := 0
	if line > 0:
		rows_before = _code.get_visible_line_count_in_range(0, line - 1)

	var wrap_index := _code.get_line_wrap_index_at_column(line, column)
	return clampi(rows_before + wrap_index, 0, maxi(0, _visible_row_count - 1))


func _is_line_hidden(line: int) -> bool:
	return _code.get_visible_line_count_in_range(line, line) == 0


func _fold_header_for_line(line: int) -> int:
	var candidate := maxi(0, line - 1)
	while candidate > 0 and _is_line_hidden(candidate):
		candidate -= 1
	return candidate


func _closest_marker_for_y(y: float) -> Dictionary:
	if _markers.is_empty():
		return {}

	var closest: Dictionary = _markers[0]
	var closest_distance := absf(
		SymbolUsageModel.reference_y(int(closest["visual_row"]), _visible_row_count, size.y) - y
	)
	for index in range(1, _markers.size()):
		var marker: Dictionary = _markers[index]
		var distance := absf(
			SymbolUsageModel.reference_y(int(marker["visual_row"]), _visible_row_count, size.y) - y
		)
		if distance < closest_distance:
			closest = marker
			closest_distance = distance

	return closest


func _disconnect_code() -> void:
	if _code != null and is_instance_valid(_code) and _code.resized.is_connected(_on_code_resized):
		_code.resized.disconnect(_on_code_resized)
	_code = null
	_markers.clear()
	_folded_lines.clear()
	_visible_row_count = -1
	_code_width = -1.0
	set_process(false)


func _on_code_resized() -> void:
	if _code == null or not is_instance_valid(_code) or is_equal_approx(_code.size.x, _code_width):
		return
	_code_width = _code.size.x
	_layout_dirty = true


static func _same_folded_lines(previous: Array, current: Array) -> bool:
	if previous.size() != current.size():
		return false
	for index in previous.size():
		if int(previous[index]) != int(current[index]):
			return false
	return true
