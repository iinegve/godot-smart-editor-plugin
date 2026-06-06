extends RefCounted


var start_line := 0
var start_column := 0
var end_line := 0
var end_column := 0
var new_text := ""


static func create(
	new_start_line: int,
	new_start_column: int,
	new_end_line: int,
	new_end_column: int,
	new_replacement_text: String
):
	var edit := new()
	edit.configure(
		new_start_line,
		new_start_column,
		new_end_line,
		new_end_column,
		new_replacement_text
	)
	return edit


func configure(
	new_start_line: int,
	new_start_column: int,
	new_end_line: int,
	new_end_column: int,
	new_replacement_text: String
) -> void:
	start_line = new_start_line
	start_column = new_start_column
	end_line = new_end_line
	end_column = new_end_column
	new_text = new_replacement_text


func is_valid() -> bool:
	if start_line < 0 or start_column < 0 or end_line < 0 or end_column < 0:
		return false
	if end_line < start_line:
		return false
	if end_line == start_line and end_column < start_column:
		return false
	return true
