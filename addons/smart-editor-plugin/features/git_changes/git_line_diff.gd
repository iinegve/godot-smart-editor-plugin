extends RefCounted

const TYPE_ADDED := &"added"
const TYPE_MODIFIED := &"modified"
const TYPE_DELETED := &"deleted"
const MAX_EDIT_DISTANCE := 512

const EDIT_EQUAL := 0
const EDIT_INSERT := 1
const EDIT_DELETE := 2


static func changes(previous_text: String, current_text: String, has_baseline: bool = true) -> Array[Dictionary]:
	var current_lines := _lines(current_text)
	if not has_baseline:
		if current_lines.is_empty():
			return []
		return [_change(TYPE_ADDED, 0, [], 0, current_lines)]

	var previous_lines := _lines(previous_text)
	if previous_lines == current_lines:
		return []

	return _edits_to_changes(_line_edits(previous_lines, current_lines))


static func _lines(text: String) -> Array[String]:
	if text.is_empty():
		return []

	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	var result: Array[String] = []
	for line in normalized.split("\n", true):
		result.append(line)
	if normalized.ends_with("\n"):
		result.remove_at(result.size() - 1)
	return result


static func _line_edits(previous_lines: Array[String], current_lines: Array[String]) -> Array[Dictionary]:
	var prefix_count := _common_prefix_count(previous_lines, current_lines)
	var suffix_count := _common_suffix_count(previous_lines, current_lines, prefix_count)
	var previous_middle := _line_slice(
		previous_lines,
		prefix_count,
		previous_lines.size() - suffix_count
	)
	var current_middle := _line_slice(
		current_lines,
		prefix_count,
		current_lines.size() - suffix_count
	)
	var edits: Array[Dictionary] = []

	for index in prefix_count:
		edits.append(_edit(EDIT_EQUAL, previous_lines[index]))
	edits.append_array(_myers_edits(previous_middle, current_middle))
	for index in range(previous_lines.size() - suffix_count, previous_lines.size()):
		edits.append(_edit(EDIT_EQUAL, previous_lines[index]))

	return edits


static func _common_prefix_count(previous_lines: Array[String], current_lines: Array[String]) -> int:
	var limit := mini(previous_lines.size(), current_lines.size())
	var count := 0
	while count < limit and previous_lines[count] == current_lines[count]:
		count += 1
	return count


static func _common_suffix_count(
	previous_lines: Array[String],
	current_lines: Array[String],
	prefix_count: int
) -> int:
	var limit := mini(previous_lines.size(), current_lines.size()) - prefix_count
	var count := 0
	while (
		count < limit
		and previous_lines[previous_lines.size() - 1 - count] == current_lines[current_lines.size() - 1 - count]
	):
		count += 1
	return count


static func _line_slice(lines: Array[String], begin: int, end: int) -> Array[String]:
	var result: Array[String] = []
	for index in range(begin, end):
		result.append(lines[index])
	return result


static func _myers_edits(previous_lines: Array[String], current_lines: Array[String]) -> Array[Dictionary]:
	if previous_lines.is_empty():
		return _single_type_edits(EDIT_INSERT, current_lines)
	if current_lines.is_empty():
		return _single_type_edits(EDIT_DELETE, previous_lines)

	var previous_count := previous_lines.size()
	var current_count := current_lines.size()
	var maximum_distance := previous_count + current_count
	var search_limit := mini(maximum_distance, MAX_EDIT_DISTANCE)
	var diagonal_offset := search_limit + 1
	var furthest_x := PackedInt32Array()
	furthest_x.resize(search_limit * 2 + 3)
	furthest_x.fill(-1)
	furthest_x[diagonal_offset + 1] = 0
	var trace: Array[PackedInt32Array] = []

	for distance in range(search_limit + 1):
		trace.append(furthest_x.duplicate())
		for diagonal in range(-distance, distance + 1, 2):
			var diagonal_index := diagonal + diagonal_offset
			var x: int
			if (
				diagonal == -distance
				or (
					diagonal != distance
					and furthest_x[diagonal_index - 1] < furthest_x[diagonal_index + 1]
				)
			):
				x = furthest_x[diagonal_index + 1]
			else:
				x = furthest_x[diagonal_index - 1] + 1

			var y := x - diagonal
			while (
				x < previous_count
				and y < current_count
				and previous_lines[x] == current_lines[y]
			):
				x += 1
				y += 1
			furthest_x[diagonal_index] = x

			if x >= previous_count and y >= current_count:
				return _backtrack_edits(
					previous_lines,
					current_lines,
					trace,
					distance,
					diagonal_offset
				)

	return _fallback_replacement_edits(previous_lines, current_lines)


static func _backtrack_edits(
	previous_lines: Array[String],
	current_lines: Array[String],
	trace: Array[PackedInt32Array],
	distance: int,
	diagonal_offset: int
) -> Array[Dictionary]:
	var edits: Array[Dictionary] = []
	var x := previous_lines.size()
	var y := current_lines.size()

	for depth in range(distance, -1, -1):
		var furthest_x: PackedInt32Array = trace[depth]
		var diagonal := x - y
		var diagonal_index := diagonal + diagonal_offset
		var previous_diagonal: int
		if (
			diagonal == -depth
			or (
				diagonal != depth
				and furthest_x[diagonal_index - 1] < furthest_x[diagonal_index + 1]
			)
		):
			previous_diagonal = diagonal + 1
		else:
			previous_diagonal = diagonal - 1

		var previous_x := furthest_x[previous_diagonal + diagonal_offset]
		var previous_y := previous_x - previous_diagonal
		while x > previous_x and y > previous_y:
			x -= 1
			y -= 1
			edits.append(_edit(EDIT_EQUAL, previous_lines[x]))

		if depth <= 0:
			continue
		if x == previous_x:
			y -= 1
			edits.append(_edit(EDIT_INSERT, current_lines[y]))
		else:
			x -= 1
			edits.append(_edit(EDIT_DELETE, previous_lines[x]))

	edits.reverse()
	return edits


static func _single_type_edits(type: int, lines: Array[String]) -> Array[Dictionary]:
	var edits: Array[Dictionary] = []
	for line in lines:
		edits.append(_edit(type, line))
	return edits


static func _fallback_replacement_edits(
	previous_lines: Array[String],
	current_lines: Array[String]
) -> Array[Dictionary]:
	var edits := _single_type_edits(EDIT_DELETE, previous_lines)
	edits.append_array(_single_type_edits(EDIT_INSERT, current_lines))
	return edits


static func _edit(type: int, line: String) -> Dictionary:
	return {
		"type": type,
		"line": line,
	}


static func _edits_to_changes(edits: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var old_line := 0
	var new_line := 0
	var hunk := {}

	for edit in edits:
		var edit_type := int(edit["type"])
		if edit_type == EDIT_EQUAL:
			_append_hunk(result, hunk)
			hunk = {}
			old_line += 1
			new_line += 1
			continue

		if hunk.is_empty():
			hunk = _empty_hunk(old_line, new_line)
		if edit_type == EDIT_DELETE:
			var old_lines: Array[String] = hunk["old_lines"]
			old_lines.append(str(edit["line"]))
			old_line += 1
		else:
			var new_lines: Array[String] = hunk["new_lines"]
			new_lines.append(str(edit["line"]))
			new_line += 1

	_append_hunk(result, hunk)
	return result


static func _empty_hunk(old_start: int, new_start: int) -> Dictionary:
	var old_lines: Array[String] = []
	var new_lines: Array[String] = []
	return {
		"old_start": old_start,
		"old_lines": old_lines,
		"new_start": new_start,
		"new_lines": new_lines,
	}


static func _append_hunk(result: Array[Dictionary], hunk: Dictionary) -> void:
	if hunk.is_empty():
		return

	var old_lines: Array[String] = hunk["old_lines"]
	var new_lines: Array[String] = hunk["new_lines"]
	var type := TYPE_MODIFIED
	if old_lines.is_empty():
		type = TYPE_ADDED
	elif new_lines.is_empty():
		type = TYPE_DELETED
	result.append(_change(
		type,
		int(hunk["old_start"]),
		old_lines,
		int(hunk["new_start"]),
		new_lines
	))


static func _change(
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
		"old_lines": old_lines.duplicate(),
		"new_start": new_start,
		"new_count": new_lines.size(),
		"new_lines": new_lines.duplicate(),
	}
