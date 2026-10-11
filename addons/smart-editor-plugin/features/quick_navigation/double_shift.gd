@tool
extends RefCounted

const INTERVAL_MS := 400

var _pressed_at := -1
var _released_at := -1
var _second_tap := false


func observe(event: InputEvent, now_ms: int) -> bool:
	if not event is InputEventKey:
		if event.is_pressed():
			reset()
		return false
	var key := event as InputEventKey
	if key.is_echo():
		return false
	if key.keycode != KEY_SHIFT and key.physical_keycode != KEY_SHIFT:
		if key.pressed:
			reset()
		return false
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		reset()
		return false
	if key.pressed:
		_second_tap = _released_at >= 0 and now_ms - _released_at <= INTERVAL_MS
		_pressed_at = now_ms
		_released_at = -1
		return false
	if _pressed_at < 0 or now_ms - _pressed_at > INTERVAL_MS:
		reset()
		return false
	if _second_tap:
		reset()
		return true
	_pressed_at = -1
	_released_at = now_ms
	return false


func reset() -> void:
	_pressed_at = -1
	_released_at = -1
	_second_tap = false
