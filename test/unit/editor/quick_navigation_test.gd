extends GdUnitTestSuite

const DoubleShift := preload("res://addons/smart-editor-plugin/features/quick_navigation/double_shift.gd")
const NavigationFileIndex := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_file_index.gd")
const NavigationPopup := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_popup.gd")
const NavigationSearch := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_search.gd")
const NavigationSymbols := preload("res://addons/smart-editor-plugin/features/quick_navigation/navigation_symbols.gd")
const SmartEditorSettings := preload("res://addons/smart-editor-plugin/settings/smart_editor_settings.gd")


func test_search_prioritizes_exact_prefix_substring_and_abbreviation() -> void:
	var exact := NavigationSearch.score("move", "move")
	var prefix := NavigationSearch.score("move", "move_unit")
	var substring := NavigationSearch.score("move", "can_move_unit")
	var abbreviation := NavigationSearch.score("move", "my_old_velocity")

	assert_int(exact).is_less(prefix)
	assert_int(prefix).is_less(substring)
	assert_int(substring).is_less(abbreviation)
	assert_int(abbreviation).is_greater_equal(0)


func test_search_ignores_case_and_accepts_snake_case_abbreviations() -> void:
	assert_int(NavigationSearch.score("UCgt", "unit_can_go_there")).is_greater_equal(0)
	assert_int(NavigationSearch.score("MOVE", "move")).is_equal(0)
	assert_int(NavigationSearch.score("no_match", "move")).is_equal(-1)


func test_search_matches_all_space_separated_terms_and_paths() -> void:
	assert_int(NavigationSearch.score("unit player", "player.gd", "units/player.gd")).is_greater_equal(0)
	assert_int(NavigationSearch.score("unit missing", "player.gd", "units/player.gd")).is_equal(-1)
	assert_int(NavigationSearch.score("units\\player", "player.gd", "units/player.gd")).is_greater_equal(0)
	assert_int(NavigationSearch.score("   ", "player.gd")).is_equal(0)
	assert_int(NavigationSearch.score("player", "player")).is_less(NavigationSearch.score("player", "enemy.gd", "player/enemy.gd"))


func test_file_categories_include_binary_scenes_resources_and_shaders() -> void:
	for path in ["res://world.tscn", "res://world.scn"]:
		assert_int(NavigationFileIndex.category_for_file(path)).is_equal(NavigationFileIndex.Category.SCENES)
	assert_int(NavigationFileIndex.category_for_file("res://unit.GD")).is_equal(NavigationFileIndex.Category.GDSCRIPT)
	for path in ["res://unit.tres", "res://unit.res", "res://water.gdshader", "res://shared.gdshaderinc"]:
		assert_int(NavigationFileIndex.category_for_file(path)).is_equal(NavigationFileIndex.Category.RESOURCES)
	for path in ["res://icon.svg", "res://note.txt", "res://unit.cs"]:
		assert_int(NavigationFileIndex.category_for_file(path)).is_equal(NavigationFileIndex.Category.OTHER)


func test_file_labels_and_addon_scope_use_directory_boundaries() -> void:
	var addon := NavigationFileIndex.file_entry("res://addons/tool/plugin.gd")
	var project := NavigationFileIndex.file_entry("res://addons_backup/unit.gd")
	var root := NavigationFileIndex.file_entry("res://unit.gd")

	assert_bool(addon["addon"]).is_true()
	assert_bool(project["addon"]).is_false()
	assert_str(addon["label"]).is_equal("plugin.gd — (addons/tool)")
	assert_str(root["label"]).is_equal("unit.gd")


func test_live_symbols_include_static_private_functions_and_member_fields() -> void:
	var source := "@export var speed: float = 3\nconst LIMIT := 10\nstatic var count := 0\nfunc _ready():\n\tvar local := 0\nstatic func unsaved(\n\tvalue: int\n) -> void:\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_array(_names(symbols)).is_equal(["speed", "LIMIT", "count", "_ready", "unsaved"])
	assert_int(symbols[0]["category"]).is_equal(NavigationSymbols.Category.FIELDS)
	assert_int(symbols[4]["category"]).is_equal(NavigationSymbols.Category.FUNCTIONS)
	assert_int(symbols[4]["line"]).is_equal(5)
	assert_int(symbols[4]["column"]).is_equal(12)


func test_symbols_ignore_comments_strings_and_anonymous_function_locals() -> void:
	var source := "# func commented():\nconst TEXT = \"\"\"\nfunc fake():\nvar fake_field = 0\n\"\"\"\nvar callback = func():\n\tvar local = 1\n\tpass\nfunc real():\n\tvar text = 'func ignored():'\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_array(_names(symbols)).is_equal(["TEXT", "callback", "real"])
	assert_int(symbols[2]["line"]).is_equal(8)


func test_inner_class_symbols_have_qualified_labels_and_distinct_locations() -> void:
	var source := "class Inner:\n\tvar member := 0\n\tfunc move():\n\t\tvar local := 0\nfunc move():\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_array(_names(symbols)).is_equal(["member", "move", "move"])
	assert_str(symbols[1]["label"]).is_equal("Inner.move()")
	assert_int(symbols[1]["column"]).is_equal(6)
	assert_str(symbols[2]["context"]).is_empty()
	assert_int(symbols[2]["line"]).is_equal(4)


func test_multiline_annotations_and_property_accessors_do_not_leak_locals() -> void:
	var source := "@export_range(\n\t0, max(1, 10)\n) var speed: float = 0\nvar value: int:\n\tget:\n\t\tvar local := 0\n\t\treturn local\n\tset(new_value):\n\t\tvalue = new_value\nfunc after():\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_array(_names(symbols)).is_equal(["speed", "value", "after"])
	assert_int(symbols[0]["line"]).is_equal(2)
	assert_int(symbols[0]["column"]).is_equal(6)


func test_symbols_ignore_fake_declarations_in_multiline_expressions() -> void:
	var source := "var values = [\n\t'var fake := 0',\n\t\"func fake():\"\n]\n@rpc(\"any_peer\") func remote_move():\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_array(_names(symbols)).is_equal(["values", "remote_move"])
	assert_int(symbols[1]["line"]).is_equal(4)
	assert_int(symbols[1]["column"]).is_equal(22)


func test_function_signatures_show_parameter_names_types_and_return_type() -> void:
	var source := "func move(target: Vector2, speed: float = 2.0) -> bool:\n\treturn true\nstatic func reset() -> void:\n\tpass\nfunc dynamic(value, callback = null):\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_str(symbols[0]["label"]).is_equal("move(target: Vector2, speed: float): bool")
	assert_str(symbols[1]["label"]).is_equal("reset(): void")
	assert_str(symbols[2]["label"]).is_equal("dynamic(value, callback)")
	assert_int(symbols[0]["line"]).is_equal(0)
	assert_int(symbols[0]["column"]).is_equal(5)


func test_multiline_signatures_handle_nested_types_and_commas_in_defaults() -> void:
	var source := "@rpc(\"any_peer\") static func build(\n\tvalues: Dictionary[\n\t\tString, Array[int]\n\t] = {\"(,):\": [1, 2]},\n\tpoint: Vector2 = Vector2(1, 2),\n\tmessage: String = \"comma, parentheses() -> fake:\", # punctuation\n\toptions = [true, false],\n) -> Dictionary[String, int]:\n\treturn {}"

	var symbols := NavigationSymbols.collect(source)

	assert_int(symbols.size()).is_equal(1)
	assert_str(symbols[0]["label"]).is_equal("build(values: Dictionary[String, Array[int]], point: Vector2, message: String, options): Dictionary[String, int]")
	assert_str(symbols[0]["tooltip"]).contains("Vector2(1, 2)")


func test_member_labels_show_declared_types_and_exclude_initializers_and_accessors() -> void:
	var source := "@export var health: int = 100\nstatic var units: Array[Node2D] = []\nconst LIMIT: int = 10\nvar dynamic = Vector2(1, 2)\nvar inferred := 5\nvar value: Dictionary[String, int]:\n\tget:\n\t\treturn {}\nclass Inner:\n\tvar target: Node\n\tfunc find(id: int) -> Node:\n\t\treturn null"

	var symbols := NavigationSymbols.collect(source)

	var labels: Array[String] = []
	for symbol in symbols:
		labels.append(symbol["label"])
	assert_array(labels).is_equal(["health: int", "units: Array[Node2D]", "LIMIT: int", "dynamic", "inferred", "value: Dictionary[String, int]", "Inner.target: Node", "Inner.find(id: int): Node"])


func test_explicit_line_continuations_preserve_types_and_navigation_locations() -> void:
	var continuation := "\\" + "\n"
	var source := "var items: " + continuation + "\tArray[Node]\nfunc continued(value: int) " + continuation + "\t-> Node: return null"

	var symbols := NavigationSymbols.collect(source)

	assert_str(symbols[0]["label"]).is_equal("items: Array[Node]")
	assert_str(symbols[1]["label"]).is_equal("continued(value: int): Node")
	assert_int(symbols[1]["line"]).is_equal(2)
	assert_int(symbols[1]["column"]).is_equal(5)


func test_underscore_access_convention_applies_to_fields_and_methods() -> void:
	var source := "var visible: int\nvar _hidden: int\nfunc available(_argument: int) -> void:\n\tpass\nfunc _internal() -> void:\n\tpass"

	var symbols := NavigationSymbols.collect(source)

	assert_bool(symbols[0]["private"]).is_false()
	assert_bool(symbols[1]["private"]).is_true()
	assert_bool(symbols[2]["private"]).is_false()
	assert_bool(symbols[3]["private"]).is_true()
	assert_str(symbols[1]["tooltip"]).contains("Private by naming convention")
	assert_str(symbols[2]["tooltip"]).contains("Public by naming convention")


func test_double_shift_requires_two_complete_taps() -> void:
	var sequence := DoubleShift.new()
	assert_bool(sequence.observe(_key(KEY_SHIFT, true), 0)).is_false()
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 20)).is_false()
	assert_bool(sequence.observe(_key(KEY_SHIFT, true), 100)).is_false()
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 120)).is_true()
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 130)).is_false()


func test_shift_combination_cancels_pending_double_shift() -> void:
	var sequence := DoubleShift.new()
	sequence.observe(_key(KEY_SHIFT, true), 0)
	sequence.observe(_key(KEY_SHIFT, false), 20)
	sequence.observe(_key(KEY_SHIFT, true), 100)
	sequence.observe(_key(KEY_A, true), 110)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 120)).is_false()
	sequence.observe(_key(KEY_SHIFT, true), 150)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 170)).is_false()


func test_held_shift_and_expired_taps_do_not_open_navigation() -> void:
	var sequence := DoubleShift.new()
	sequence.observe(_key(KEY_SHIFT, true), 0)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 600)).is_false()
	sequence.observe(_key(KEY_SHIFT, true), 700)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 720)).is_false()
	sequence.observe(_key(KEY_SHIFT, true), 1200)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 1220)).is_false()


func test_modifier_shortcuts_and_mouse_clicks_cancel_double_shift() -> void:
	var sequence := DoubleShift.new()
	sequence.observe(_key(KEY_SHIFT, true), 0)
	sequence.observe(_key(KEY_SHIFT, false), 20)
	var modified := _key(KEY_SHIFT, true)
	modified.meta_pressed = true
	sequence.observe(modified, 100)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 120)).is_false()
	sequence.observe(_key(KEY_SHIFT, true), 150)
	sequence.observe(_key(KEY_SHIFT, false), 170)
	var click := InputEventMouseButton.new()
	click.pressed = true
	sequence.observe(click, 180)
	sequence.observe(_key(KEY_SHIFT, true), 200)
	assert_bool(sequence.observe(_key(KEY_SHIFT, false), 220)).is_false()


func test_default_navigation_shortcuts_use_platform_command_modifier() -> void:
	var event := _key(KEY_N, true)
	event.shift_pressed = true
	if OS.has_feature("macos"):
		event.meta_pressed = true
	else:
		event.ctrl_pressed = true
	assert_bool(SmartEditorSettings._make_navigation_shortcut(KEY_N, true).matches_event(event)).is_true()
	assert_bool(SmartEditorSettings._make_navigation_shortcut(KEY_N).matches_event(event)).is_false()


func test_symbol_popup_filters_functions_and_fields_without_activation() -> void:
	var popup := NavigationPopup.new()
	popup.configure(false)
	popup._entries = NavigationSymbols.collect("var field := 0\nfunc move():\n\tpass\nfunc remove():\n\tpass")
	var activations: Array = []
	popup.entry_activated.connect(func(entry: Dictionary): activations.append(entry))
	popup._query.text = "MOVE"
	popup._refresh()

	assert_int(popup._results.item_count).is_equal(2)
	assert_str(popup._results.get_item_metadata(0)["name"]).is_equal("move")
	assert_array(activations).is_empty()
	popup._activate_selected()
	assert_int(activations.size()).is_equal(1)
	assert_int(activations[0]["line"]).is_equal(1)
	popup._query.text = ""
	popup._query.text_changed.emit("")
	assert_int(popup._results.item_count).is_equal(4)
	assert_str(popup._results.get_item_metadata(0)["name"]).is_equal("field")
	assert_bool(popup._results.is_item_selectable(1)).is_false()
	assert_str(popup._results.get_item_metadata(2)["name"]).is_equal("move")
	assert_str(popup._results.get_item_metadata(3)["name"]).is_equal("remove")
	popup.free()


func test_symbol_search_filters_both_groups_with_fields_before_methods() -> void:
	var popup := NavigationPopup.new()
	popup.configure(false)
	popup._entries = NavigationSymbols.collect("func move():\n\tpass\nvar move_speed := 0\nvar health := 0")
	popup._query.text = "move"
	popup._refresh()

	assert_int(popup._results.item_count).is_equal(3)
	assert_str(popup._results.get_item_metadata(0)["name"]).is_equal("move_speed")
	assert_int(popup._separator_index).is_equal(1)
	assert_str(popup._results.get_item_metadata(2)["name"]).is_equal("move")
	popup._query.text = "health"
	popup._query.text_changed.emit("health")
	assert_int(popup._results.item_count).is_equal(1)
	assert_int(popup._separator_index).is_equal(-1)
	assert_str(popup._results.get_item_metadata(0)["name"]).is_equal("health")
	popup._query.text = "missing"
	popup._query.text_changed.emit("missing")
	assert_int(popup._results.item_count).is_equal(0)
	assert_int(popup._separator_index).is_equal(-1)
	popup.free()


func test_symbol_keyboard_navigation_skips_separator_in_both_directions() -> void:
	var popup := NavigationPopup.new()
	popup.configure(false)
	popup._entries = NavigationSymbols.collect("var field := 0\nfunc first():\n\tpass\nfunc last():\n\tpass")
	popup._refresh()

	popup._move_selection(1)
	assert_array(Array(popup._results.get_selected_items())).is_equal([2])
	popup._move_selection(-1)
	assert_array(Array(popup._results.get_selected_items())).is_equal([0])
	popup._move_selection(10)
	assert_array(Array(popup._results.get_selected_items())).is_equal([3])
	popup._move_selection(-10)
	assert_array(Array(popup._results.get_selected_items())).is_equal([0])
	popup.free()


func test_symbol_separator_cannot_activate_a_navigation_target() -> void:
	var popup := NavigationPopup.new()
	popup.configure(false)
	popup._entries = NavigationSymbols.collect("var field := 0\nfunc method():\n\tpass")
	var activations: Array = []
	popup.entry_activated.connect(func(entry: Dictionary): activations.append(entry))
	popup._refresh()

	popup._activate(popup._separator_index)
	assert_array(activations).is_empty()
	popup._activate_selected()
	assert_int(activations.size()).is_equal(1)
	assert_str(activations[0]["name"]).is_equal("field")
	popup.free()


func test_empty_search_results_do_not_activate_stale_selection() -> void:
	var popup := NavigationPopup.new()
	popup.configure(false)
	popup._entries = NavigationSymbols.collect("func move():\n\tpass")
	var activations: Array = []
	popup.entry_activated.connect(func(entry: Dictionary): activations.append(entry))
	popup._refresh()
	popup._query.text = "missing"
	popup._query.text_changed.emit("missing")
	popup._activate_selected()

	assert_int(popup._results.item_count).is_equal(0)
	assert_array(activations).is_empty()
	popup.free()


func _names(symbols: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for symbol in symbols:
		names.append(symbol["name"])
	return names


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event
