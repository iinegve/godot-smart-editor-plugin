@tool
extends RefCounted

const SmartSelectionRange := preload("res://addons/smart-editor-plugin/smart_selection_range.gd")

var _history: Array[Dictionary] = []


func record(selection_range: Dictionary) -> void:
	_history.append(selection_range.duplicate())


func shrink_target(current: Dictionary, candidates: Array[Dictionary]) -> Dictionary:
	var previous := pop_contained_in(current)
	if not previous.is_empty():
		return previous
	return fallback_inside(current, candidates)


func pop_contained_in(current: Dictionary) -> Dictionary:
	while not _history.is_empty():
		var previous := _history.pop_back()
		if SmartSelectionRange.contains_or_equal(current, previous):
			return previous
	return {}


func fallback_inside(current: Dictionary, candidates: Array[Dictionary]) -> Dictionary:
	var result := {}
	for candidate in candidates:
		if SmartSelectionRange.strictly_contains(current, candidate):
			result = candidate
	return result


func size() -> int:
	return _history.size()


func clear() -> void:
	_history.clear()
