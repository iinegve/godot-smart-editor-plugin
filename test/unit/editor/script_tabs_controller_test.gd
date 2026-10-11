extends GdUnitTestSuite

const ScriptTabsController := preload("res://addons/smart-editor-plugin/features/script_tabs/script_tabs_controller.gd")


class EditableDocument extends Control:
	var code := CodeEdit.new()

	func _init() -> void:
		add_child(code)
		code.text = "original"
		code.tag_saved_version()

	func get_base_editor() -> CodeEdit:
		return code


func test_tabs_mirror_document_names_paths_and_native_selection() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]

	assert_int(controller._tabs.tab_count).is_equal(3)
	assert_str(controller._tabs.get_tab_title(0)).is_equal("third.gd")
	assert_str(controller._tabs.get_tab_tooltip(1)).is_equal("res://first.gd")
	assert_int(controller._tabs.current_tab).is_equal(1)
	assert_array(fixture["selections"]).is_empty()


func test_click_resolves_filtered_list_indices_to_native_documents() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]
	var list: ItemList = fixture["list"]
	list.clear()
	_add_item(list, "third.gd", 2)
	controller._refresh()

	controller._tabs.tab_selected.emit(0)

	assert_int(source.current_tab).is_equal(2)
	assert_array(fixture["selections"]).is_equal([0])


func test_native_selection_updates_tabs_without_triggering_another_navigation() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]

	source.current_tab = 1
	controller._refresh()
	controller._refresh()

	assert_int(controller._tabs.current_tab).is_equal(2)
	assert_array(fixture["selections"]).is_empty()
	assert_int(controller._tabs.tab_count).is_equal(3)


func test_document_names_update_without_switching_documents() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var list: ItemList = fixture["list"]

	list.set_item_text(1, "renamed.gd")
	controller._refresh()

	assert_str(controller._tabs.get_tab_title(1)).is_equal("renamed.gd")
	assert_int(controller._tabs.current_tab).is_equal(1)
	assert_array(fixture["selections"]).is_empty()


func test_dirty_marker_tracks_editing_and_saving_before_native_names_refresh() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]
	var list: ItemList = fixture["list"]
	var document := source.get_tab_control(0) as EditableDocument

	document.code.insert_text_at_caret("changed")
	controller._refresh()

	assert_str(controller._tabs.get_tab_title(1)).is_equal("first.gd(*)")
	list.set_item_text(1, "first.gd(*)")
	document.code.tag_saved_version()
	controller._refresh()
	assert_str(controller._tabs.get_tab_title(1)).is_equal("first.gd")
	assert_array(fixture["selections"]).is_empty()


func test_close_requests_native_save_handling_without_removing_the_document() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]

	controller._tabs.tab_close_pressed.emit(2)

	assert_array(fixture["clicks"]).is_equal([[2, MOUSE_BUTTON_MIDDLE]])
	assert_int(source.get_tab_count()).is_equal(3)


func test_reordering_between_refresh_and_click_keeps_document_identity() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]
	var list: ItemList = fixture["list"]
	var third := source.get_tab_control(2)
	source.move_child(third, 0)
	list.clear()
	_add_item(list, "first.gd", 1)
	_add_item(list, "third.gd", 0)
	_add_item(list, "second.gd", 2)

	controller._activate_tab(0)
	controller._close_tab(1)

	assert_object(source.get_current_tab_control()).is_same(third)
	assert_array(fixture["selections"]).is_equal([1])
	assert_array(fixture["clicks"]).is_equal([[0, MOUSE_BUTTON_MIDDLE]])


func test_closed_document_cannot_activate_or_close_a_different_document() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]
	var list: ItemList = fixture["list"]
	source.get_tab_control(2).free()
	list.clear()
	_add_item(list, "first.gd", 0)
	_add_item(list, "second.gd", 1)

	controller._activate_tab(0)
	controller._close_tab(0)
	controller._refresh()

	assert_array(fixture["selections"]).is_empty()
	assert_array(fixture["clicks"]).is_empty()
	assert_int(controller._tabs.tab_count).is_equal(2)


func test_empty_document_list_hides_tabs_and_clears_stale_entries() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var list: ItemList = fixture["list"]
	list.clear()

	controller._refresh()
	controller._activate_tab(0)

	assert_bool(controller._tabs.visible).is_false()
	assert_int(controller._tabs.tab_count).is_equal(0)
	assert_array(fixture["selections"]).is_empty()
	_add_item(list, "first.gd", 0)
	controller._refresh()
	assert_bool(controller._tabs.visible).is_true()
	assert_int(controller._tabs.current_tab).is_equal(0)


func test_detach_removes_only_plugin_tabs_and_disconnects_native_signals() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]
	var parent := source.get_parent()
	var tabs := controller._tabs
	assert_int(tabs.get_index()).is_less(source.get_index())

	controller._detach()
	await get_tree().process_frame

	assert_bool(is_instance_valid(tabs)).is_false()
	assert_object(source.get_parent()).is_same(parent)
	assert_int(source.get_tab_count()).is_equal(3)
	assert_bool(source.tabs_visible).is_false()
	assert_bool(source.tab_changed.is_connected(controller._native_tab_changed)).is_false()
	assert_bool(source.child_order_changed.is_connected(controller._schedule_refresh)).is_false()


func test_right_click_selects_document_before_opening_native_menu() -> void:
	var fixture := _fixture()
	var controller: ScriptTabsController = fixture["controller"]
	var source: TabContainer = fixture["source"]

	controller._tabs.tab_rmb_clicked.emit(0)

	assert_int(source.current_tab).is_equal(2)
	assert_array(fixture["selections"]).is_equal([0])
	assert_array(fixture["clicks"]).is_equal([[0, MOUSE_BUTTON_RIGHT]])


func _fixture() -> Dictionary:
	var parent := VBoxContainer.new()
	add_child(auto_free(parent))
	var source := TabContainer.new()
	source.tabs_visible = false
	parent.add_child(source)
	for name in ["First", "Second", "Third"]:
		var document := EditableDocument.new()
		document.name = name
		source.add_child(document)
	var list := ItemList.new()
	parent.add_child(list)
	_add_item(list, "third.gd", 2)
	_add_item(list, "first.gd", 0)
	_add_item(list, "second.gd", 1)
	var selections: Array[int] = []
	var clicks: Array = []
	list.item_selected.connect(func(index: int):
		selections.append(index)
		source.current_tab = list.get_item_metadata(index)
	)
	list.item_clicked.connect(func(index: int, _position: Vector2, button: int): clicks.append([index, button]))
	var controller := ScriptTabsController.new()
	parent.add_child(controller)
	controller._attach(source, list)
	return {"source": source, "list": list, "controller": controller, "selections": selections, "clicks": clicks}


func _add_item(list: ItemList, title: String, native_index: int) -> void:
	var index := list.add_item(title)
	list.set_item_metadata(index, native_index)
	list.set_item_tooltip(index, "res://" + title)
