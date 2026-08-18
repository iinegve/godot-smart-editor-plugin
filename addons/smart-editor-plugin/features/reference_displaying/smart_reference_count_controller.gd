## Scans the active GDScript file for top-level declarations and counts
## how many times each symbol is used in the file.
## Drives SmartReferenceCountLabel to show "N references" on declaration lines.
@tool
extends Node

const SymbolUsageModel := preload("res://addons/smart-editor-plugin/common/smart_symbol_usage_model.gd")
const ReferenceCountLabel := preload("res://addons/smart-editor-plugin/features/reference_displaying/smart_reference_count_label.gd")

const TEXT_DEBOUNCE_SECONDS  := 0.40
const LIGHT_DEBOUNCE_SECONDS := 0.08

const DECLARATION_KEYWORDS := ["func", "static func", "var", "const", "signal", "class"]

var _enabled_setting: StringName = &""
var _color_setting:   StringName = &""

var _call_hierarchy_controller: Node

var _script_editor = null
var _code: CodeEdit  = null
var _label           = null
var _script_path     := ""

var _debounce_remaining := 0.0
var _refresh_pending    := false

var _last_line_height := 0.0
var _last_font_size := 0


func configure(call_hierarchy_controller: Node, enabled_setting: StringName, color_setting: StringName = &"") -> void:
	_call_hierarchy_controller = call_hierarchy_controller
	_enabled_setting = enabled_setting
	_color_setting = color_setting
	
	set_process(true)
	_connect_script_editor()
	_attach_to_current_code_edit()
	_schedule_refresh(LIGHT_DEBOUNCE_SECONDS)


func _exit_tree() -> void:
	_disconnect_script_editor()
	_detach_code_edit()


func _process(delta: float) -> void:
	if _enabled_setting != &"" and not _is_enabled():
		_detach_code_edit()
		return

	_connect_script_editor()
	_attach_to_current_code_edit()

	if _label != null and is_instance_valid(_label) and _code != null and is_instance_valid(_code):
		var current_lh := float(_code.get_line_height())
		var current_fs := int(_code.get_theme_font_size(&"font_size"))
		if current_lh != _last_line_height or current_fs != _last_font_size:
			_last_line_height = current_lh
			_last_font_size = current_fs
			_label.queue_redraw()

	if _refresh_pending:
		_debounce_remaining -= delta
		if _debounce_remaining <= 0.0:
			_refresh_pending = false
			_refresh()


func _connect_script_editor() -> void:
	if _script_editor != null and is_instance_valid(_script_editor):
		return
	_script_editor = EditorInterface.get_script_editor()
	if _script_editor == null or not _script_editor.has_signal("editor_script_changed"):
		return
	if not _script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.connect(_on_editor_script_changed)


func _disconnect_script_editor() -> void:
	if _script_editor == null or not is_instance_valid(_script_editor):
		_script_editor = null
		return
	if _script_editor.has_signal("editor_script_changed") and \
			_script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		_script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	_script_editor = null


func _attach_to_current_code_edit() -> void:
	var next_code := _get_current_code_edit()
	var next_path := _get_current_script_path()
	if next_code == _code and next_path == _script_path:
		return

	_detach_code_edit()
	_code        = next_code
	_script_path = next_path

	if _code == null:
		return

	_last_line_height = 0.0
	_last_font_size = 0

	_label = ReferenceCountLabel.new()
	_label.name    = "SmartReferenceCountLabel"
	_label.z_index = 8
	_label.configure(_enabled_setting, _color_setting)
	_code.add_child(_label)
	_layout_label()
	_label.attach_to_code(_code)
	_label.label_clicked.connect(_on_label_clicked)
	
	if not _code.text_changed.is_connected(_on_text_changed):
		_code.text_changed.connect(_on_text_changed)
	if not _code.resized.is_connected(_on_resized):
		_code.resized.connect(_on_resized)
	
	_schedule_refresh(LIGHT_DEBOUNCE_SECONDS)


func _on_label_clicked(line: int, symbol: String) -> void:
	_on_reference_clicked(line, symbol)


func _on_reference_clicked(line: int, symbol: String) -> void:
	var code := _get_active_code_edit()
	if code == null:
		return

	var line_text := code.get_line(line)
	var col := line_text.find(symbol)
	if col == -1:
		return

	code.set_caret_line(line)
	code.set_caret_column(col)

	var has_method__begin_call_hierarchy = _call_hierarchy_controller and _call_hierarchy_controller.has_method("_begin_call_hierarchy")
	if has_method__begin_call_hierarchy:
		_call_hierarchy_controller._begin_call_hierarchy()
	


func _get_active_code_edit() -> CodeEdit:
	var se := EditorInterface.get_script_editor()
	if se == null:
		return null
	var cur := se.get_current_editor()
	if cur == null:
		return null
	var base := cur.get_base_editor()
	if base is CodeEdit:
		return base
	return null


func _detach_code_edit() -> void:
	if _code != null and is_instance_valid(_code):
		if _code.text_changed.is_connected(_on_text_changed):
			_code.text_changed.disconnect(_on_text_changed)
		if _code.resized.is_connected(_on_resized):
			_code.resized.disconnect(_on_resized)

	if _label != null and is_instance_valid(_label):
		_label.queue_free()

	_code            = null
	_label           = null
	_script_path     = ""
	_refresh_pending = false


func _layout_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	_label.anchor_left   = 0.0
	_label.anchor_right  = 1.0
	_label.anchor_top    = 0.0
	_label.anchor_bottom = 1.0
	_label.offset_left   = 0.0
	_label.offset_right  = 0.0
	_label.offset_top    = 0.0
	_label.offset_bottom = 0.0


func _refresh() -> void:
	if _code == null or not is_instance_valid(_code):
		return
	if _label == null or not is_instance_valid(_label):
		return
	var full_text := _get_code_text(_code)
	_label.set_entries(_build_entries(full_text))


func _build_entries(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines := text.split("\n", true)
	var line_count := lines.size()

	for line_index in line_count:
		var line := lines[line_index]
		if line.is_empty():
			continue
		var first_ch := line[0]
		if first_ch == " " or first_ch == "\t":
			continue

		var decl := _parse_declaration(line)
		if decl.is_empty():
			continue

		var symbol: String = decl["symbol"]
		var refs := SymbolUsageModel.references_for_symbol_in_text(text, symbol)
		var usages := maxi(0, refs.size() - 1)

		result.append({
			"line":   line_index,
			"symbol": symbol,
			"count":  usages,
		})

	return result


static func _parse_declaration(line: String) -> Dictionary:
	for keyword in DECLARATION_KEYWORDS:
		if not line.begins_with(keyword):
			continue

		var kw_len: int = keyword.length()
		if line.length() <= kw_len:
			continue

		var ch := line[kw_len]
		if ch != " " and ch != "\t":
			continue

		var i := kw_len + 1
		while i < line.length() and (line[i] == " " or line[i] == "\t"):
			i += 1
		if i >= line.length() or not _is_id_start(line[i]):
			continue

		var start := i
		i += 1
		while i < line.length() and _is_id_char(line[i]):
			i += 1

		var symbol := line.substr(start, i - start)
		if symbol.is_empty():
			continue

		return {"symbol": symbol, "keyword": keyword}

	return {}


static func _is_id_start(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


static func _is_id_char(ch: String) -> bool:
	return _is_id_start(ch) or (ch >= "0" and ch <= "9")


func _schedule_refresh(delay: float) -> void:
	_refresh_pending    = true
	_debounce_remaining = maxf(_debounce_remaining, delay)


func _is_enabled() -> bool:
	if _enabled_setting == &"":
		return true
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(_enabled_setting):
		return true
	return bool(settings.get_setting(_enabled_setting))


func _get_code_text(code: CodeEdit) -> String:
	var lines: Array[String] = []
	for i in code.get_line_count():
		lines.append(code.get_line(i))
	return "\n".join(lines)


func _get_current_code_edit() -> CodeEdit:
	var se := EditorInterface.get_script_editor()
	if se == null:
		return null
	var cur := se.get_current_editor()
	if cur == null:
		return null
	var base := cur.get_base_editor()
	if base is CodeEdit:
		return base
	return null


func _get_current_script_path() -> String:
	var se := EditorInterface.get_script_editor()
	if se == null:
		return ""
	var s: Script = se.get_current_script()
	return s.resource_path if s != null else ""


func _on_editor_script_changed(_script: Script) -> void:
	_attach_to_current_code_edit()
	_schedule_refresh(LIGHT_DEBOUNCE_SECONDS)


func _on_text_changed() -> void:
	_schedule_refresh(TEXT_DEBOUNCE_SECONDS)


func _on_resized() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_redraw()
