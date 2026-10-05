@tool
extends Node

signal change_clicked(change: Dictionary)

const GUTTER_NAME := "smart_git_changes"
const GUTTER_WIDTH := 4
const ADDED_COLOR := Color("3fb950bf")
const MODIFIED_COLOR := Color("58a6ffbf")
const DELETED_COLOR := Color("8b949ebf")

var _code: CodeEdit
var _gutter_index := -1


func _exit_tree() -> void:
	detach()


func attach_to_code(new_code: CodeEdit) -> void:
	if _code == new_code and _current_gutter_index() >= 0:
		return

	detach()
	_code = new_code
	if _code == null:
		return

	_gutter_index = _find_gutter_index(_code)
	if _gutter_index < 0:
		_code.add_gutter(0)
		_gutter_index = 0
		_code.set_gutter_name(_gutter_index, GUTTER_NAME)

	_code.set_gutter_type(_gutter_index, TextEdit.GUTTER_TYPE_CUSTOM)
	_code.set_gutter_width(_gutter_index, GUTTER_WIDTH)
	_code.set_gutter_draw(_gutter_index, true)
	_code.set_gutter_clickable(_gutter_index, false)
	_code.set_gutter_overwritable(_gutter_index, false)
	_code.set_gutter_custom_draw(_gutter_index, Callable(self, "_draw_marker"))
	if not _code.gutter_clicked.is_connected(_on_gutter_clicked):
		_code.gutter_clicked.connect(_on_gutter_clicked)


func set_changes(changes: Array[Dictionary]) -> void:
	clear_changes()
	var gutter := _current_gutter_index()
	if gutter < 0:
		return

	for change in changes:
		var type: StringName = change.get("type", &"")
		if type == &"deleted":
			_mark_deleted_change(change, gutter)
		elif type == &"added" or type == &"modified":
			_mark_current_lines(change, gutter)
	_code.queue_redraw()


func clear_changes() -> void:
	var gutter := _current_gutter_index()
	if gutter < 0:
		return

	for line in _code.get_line_count():
		_code.set_line_gutter_metadata(line, gutter, null)
		_code.set_line_gutter_clickable(line, gutter, false)
		_code.set_line_gutter_item_color(line, gutter, Color.WHITE)
	_code.queue_redraw()


func detach() -> void:
	if _code == null or not is_instance_valid(_code):
		_code = null
		_gutter_index = -1
		return

	if _code.gutter_clicked.is_connected(_on_gutter_clicked):
		_code.gutter_clicked.disconnect(_on_gutter_clicked)
	var gutter := _current_gutter_index()
	if gutter >= 0:
		_code.remove_gutter(gutter)
	_code = null
	_gutter_index = -1


func _mark_current_lines(change: Dictionary, gutter: int) -> void:
	var first_line := maxi(0, int(change.get("new_start", 0)))
	var end_line := mini(
		_code.get_line_count(),
		first_line + maxi(0, int(change.get("new_count", 0)))
	)
	for line in range(first_line, end_line):
		_mark_line(line, change, gutter)


func _mark_deleted_change(change: Dictionary, gutter: int) -> void:
	var boundary := int(change.get("new_start", 0))
	var line := clampi(boundary, 0, maxi(0, _code.get_line_count() - 1))
	_mark_line(line, change, gutter)


func _mark_line(line: int, change: Dictionary, gutter: int) -> void:
	_code.set_line_gutter_metadata(line, gutter, change.duplicate(true))
	_code.set_line_gutter_clickable(line, gutter, true)
	_code.set_line_gutter_item_color(line, gutter, _color_for_type(change.get("type", &"")))


func _draw_marker(line: int, gutter: int, region: Rect2) -> void:
	if _code == null or not is_instance_valid(_code):
		return
	var change: Variant = _code.get_line_gutter_metadata(line, gutter)
	if change is not Dictionary:
		return

	var color := _code.get_line_gutter_item_color(line, gutter)
	if change.get("type", &"") != &"deleted":
		_code.draw_rect(region, color)
		return

	var height := minf(3.0, region.size.y)
	var at_end_of_file := int(change.get("new_start", 0)) >= _code.get_line_count()
	var y := region.end.y - height if at_end_of_file else region.position.y
	_code.draw_rect(Rect2(region.position.x, y, region.size.x, height), color)


func _on_gutter_clicked(line: int, gutter: int) -> void:
	if gutter != _current_gutter_index():
		return
	var change: Variant = _code.get_line_gutter_metadata(line, gutter)
	if change is Dictionary:
		change_clicked.emit(change.duplicate(true))


func _current_gutter_index() -> int:
	if _code == null or not is_instance_valid(_code):
		_gutter_index = -1
		return -1
	_gutter_index = _find_gutter_index(_code)
	return _gutter_index


func _find_gutter_index(code: CodeEdit) -> int:
	for index in code.get_gutter_count():
		if code.get_gutter_name(index) == GUTTER_NAME:
			return index
	return -1


func _color_for_type(type: StringName) -> Color:
	if type == &"added":
		return ADDED_COLOR
	if type == &"modified":
		return MODIFIED_COLOR
	return DELETED_COLOR
