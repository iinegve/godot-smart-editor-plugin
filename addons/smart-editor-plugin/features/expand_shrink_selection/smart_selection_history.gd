@tool
extends RefCounted

const SmartSelectionRange := preload("res://addons/smart-editor-plugin/common/smart_selection_range.gd")

var _history: Array[SmartSelectionRange] = []


func record(selection_range: SmartSelectionRange) -> void:
	_history.append(selection_range.duplicate_range())


func shrink_target(current: SmartSelectionRange, candidates: Array[SmartSelectionRange]) -> SmartSelectionRange:
	var previous := pop_contained_in(current)
	if previous != null:
		return previous
	return fallback_inside(current, candidates)


func pop_contained_in(current: SmartSelectionRange) -> SmartSelectionRange:
	while not _history.is_empty():
		var previous: SmartSelectionRange = _history.pop_back()
		if current.contains_or_equal(previous):
			return previous
	return null


func fallback_inside(current: SmartSelectionRange, candidates: Array[SmartSelectionRange]) -> SmartSelectionRange:
	var result: SmartSelectionRange = null
	for candidate in candidates:
		if current.strictly_contains(candidate):
			result = candidate
	return result


func size() -> int:
	return _history.size()


func clear() -> void:
	_history.clear()
