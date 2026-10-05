@tool
extends Node

const GitBaselineProvider := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_baseline_provider.gd"
)
const GitLineDiff := preload("res://addons/smart-editor-plugin/features/git_changes/git_line_diff.gd")
const GitChangeGutter := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_change_gutter.gd"
)
const GitPreviousVersionPopup := preload(
	"res://addons/smart-editor-plugin/features/git_changes/git_previous_version_popup.gd"
)

const TEXT_DEBOUNCE_SECONDS := 0.30

var _enabled_setting: StringName = &""
var _baseline_provider = null
var _script_editor = null
var _code: CodeEdit
var _gutter = null
var _popup = null
var _script_path := ""
var _baseline_text := ""
var _has_baseline := false
var _refresh_pending := false
var _debounce_remaining := 0.0
var _git_availability_checked := false
var _git_available := true


func configure(new_enabled_setting: StringName, provider = null) -> void:
	_enabled_setting = new_enabled_setting
	_baseline_provider = provider if provider != null else GitBaselineProvider.new()
	set_process(true)
	if not _is_enabled() or not _ensure_git_available():
		return
	_connect_script_editor()
	_attach_to_current_code_edit()


func _exit_tree() -> void:
	_disconnect_script_editor()
	_detach_code_edit()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_IN
		and _code != null
		and is_instance_valid(_code)
		and _is_enabled()
	):
		_reload_baseline()


func _process(delta: float) -> void:
	if not _is_enabled():
		_detach_code_edit()
		return
	if not _ensure_git_available():
		return

	_connect_script_editor()
	_attach_to_current_code_edit()
	_advance_pending_refresh(delta)


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
	if (
		_script_editor.has_signal("editor_script_changed")
		and _script_editor.editor_script_changed.is_connected(_on_editor_script_changed)
	):
		_script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	_script_editor = null


func _attach_to_current_code_edit() -> void:
	var next_code := _get_current_code_edit()
	var next_script_path := _get_current_script_path()
	_attach_to_code(next_code, next_script_path)


func _attach_to_code(new_code: CodeEdit, new_script_path: String) -> void:
	if new_code == _code and new_script_path == _script_path:
		return

	_detach_code_edit()
	_code = new_code
	_script_path = new_script_path
	if _code == null or _script_path.is_empty():
		return

	if not _code.text_changed.is_connected(_on_code_text_changed):
		_code.text_changed.connect(_on_code_text_changed)
	_reload_baseline()


func _detach_code_edit() -> void:
	if _code != null and is_instance_valid(_code):
		if _code.text_changed.is_connected(_on_code_text_changed):
			_code.text_changed.disconnect(_on_code_text_changed)
	_remove_views()

	_code = null
	_script_path = ""
	_baseline_text = ""
	_has_baseline = false
	_refresh_pending = false
	_debounce_remaining = 0.0


func _remove_views() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.hide()
		_popup.queue_free()
	if _gutter != null and is_instance_valid(_gutter):
		_gutter.detach()
		_gutter.queue_free()
	_popup = null
	_gutter = null


func _advance_pending_refresh(delta: float) -> void:
	if not _refresh_pending:
		return
	_debounce_remaining -= delta
	if _debounce_remaining > 0.0:
		return
	_refresh_pending = false
	_refresh_changes()


func _reload_baseline() -> void:
	if _code == null or not is_instance_valid(_code) or _script_path.is_empty():
		return
	if _baseline_provider == null:
		_baseline_provider = GitBaselineProvider.new()
	if not _ensure_git_available():
		_remove_views()
		return

	var absolute_path := ProjectSettings.globalize_path(_script_path)
	var result: Dictionary = _baseline_provider.load_baseline(absolute_path)
	var status: StringName = result.get("status", GitBaselineProvider.STATUS_UNAVAILABLE)
	if status == GitBaselineProvider.STATUS_LOADED:
		_baseline_text = str(result.get("text", ""))
		_has_baseline = true
	elif status == GitBaselineProvider.STATUS_NEW:
		_baseline_text = ""
		_has_baseline = false
	else:
		_baseline_text = ""
		_has_baseline = false
		_remove_views()
		return

	_ensure_gutter()
	_refresh_pending = false
	_debounce_remaining = 0.0
	_refresh_changes()


func _ensure_git_available() -> bool:
	if _git_availability_checked:
		return _git_available
	_git_availability_checked = true
	var availability: Dictionary = _baseline_provider.check_availability()
	_git_available = bool(availability.get("available", false))
	if _git_available:
		return true

	var error := str(availability.get("error", "Git is unavailable")).strip_edges()
	push_warning("Smart Editor Git change markers are disabled: %s" % error)
	set_process(false)
	return false


func _ensure_gutter() -> void:
	if _gutter != null and is_instance_valid(_gutter):
		return
	_gutter = GitChangeGutter.new()
	_gutter.name = "SmartGitChangeGutter"
	_gutter.change_clicked.connect(_on_change_clicked)
	_code.add_child(_gutter)
	_gutter.attach_to_code(_code)


func _refresh_changes() -> void:
	if (
		_code == null
		or not is_instance_valid(_code)
		or _gutter == null
		or not is_instance_valid(_gutter)
	):
		return
	var changes: Array[Dictionary] = GitLineDiff.changes(
		_baseline_text,
		_code.text,
		_has_baseline
	)
	_gutter.set_changes(changes)


func _on_code_text_changed() -> void:
	_refresh_pending = true
	_debounce_remaining = TEXT_DEBOUNCE_SECONDS


func _on_change_clicked(change: Dictionary) -> void:
	if _code == null or not is_instance_valid(_code):
		return
	if _popup == null or not is_instance_valid(_popup):
		_popup = GitPreviousVersionPopup.new()
		_popup.name = "SmartGitPreviousVersionPopup"
		_code.add_child(_popup)
	var click_position := _code.get_screen_transform() * _code.get_local_mouse_position()
	_popup.show_change(
		change,
		Vector2i(roundi(click_position.x), roundi(click_position.y)),
		Rect2i(
			Vector2i(_code.get_screen_position()),
			Vector2i(_code.size)
		)
	)


func _on_editor_script_changed(_script: Script) -> void:
	_attach_to_current_code_edit()


func _is_enabled() -> bool:
	if _enabled_setting == &"":
		return true
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(_enabled_setting):
		return true
	return bool(settings.get_setting(_enabled_setting))


func _get_current_code_edit() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return null
	var current_editor := script_editor.get_current_editor()
	if current_editor == null:
		return null
	var base := current_editor.get_base_editor()
	return base if base is CodeEdit else null


func _get_current_script_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""
	var current_script: Script = script_editor.get_current_script()
	return current_script.resource_path if current_script != null else ""
