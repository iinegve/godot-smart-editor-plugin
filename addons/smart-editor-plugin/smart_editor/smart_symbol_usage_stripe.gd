@tool
extends Control

signal usage_clicked(reference: Dictionary)

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/smart_editor/smart_symbol_usage_model.gd")
const STRIPE_WIDTH := 8.0
const MARK_HEIGHT := 3.0
const CURRENT_MARK_HEIGHT := 5.0

var _references: Array[Dictionary] = []
var _line_count := 0
var _current_reference := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(STRIPE_WIDTH, 0)
	tooltip_text = "Highlights Stripe"


func set_usage_references(references: Array[Dictionary], line_count: int, current_reference: Dictionary) -> void:
	_references = references.duplicate()
	_line_count = line_count
	_current_reference = current_reference.duplicate()
	queue_redraw()


func clear_references() -> void:
	_references.clear()
	_line_count = 0
	_current_reference.clear()
	queue_redraw()


func _draw() -> void:
	if _line_count <= 0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.12))
	for reference in _references:
		var is_current := SymbolUsageModel.same_position(reference, _current_reference)
		var mark_height := CURRENT_MARK_HEIGHT if is_current else MARK_HEIGHT
		var mark_width := STRIPE_WIDTH if is_current else STRIPE_WIDTH - 2.0
		var x := 0.0 if is_current else 1.0
		var y := SymbolUsageModel.reference_y(int(reference["line"]), _line_count, size.y) - mark_height * 0.5
		y = clampf(y, 0.0, maxf(0.0, size.y - mark_height))

		var color := Color(1.0, 0.82, 0.32, 0.95) if is_current else Color(0.45, 0.72, 1.0, 0.78)
		draw_rect(Rect2(Vector2(x, y), Vector2(mark_width, mark_height)), color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var reference := SymbolUsageModel.closest_reference_for_y(_references, _line_count, size.y, mouse_event.position.y)
			if not reference.is_empty():
				usage_clicked.emit(reference)
				accept_event()
