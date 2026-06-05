extends GdUnitTestSuite

const SmartEditorController := preload("res://addons/smart-editor-plugin/smart_editor/smart_editor_controller.gd")


func test_identifier_validation_accepts_valid_names() -> void:
	var controller := SmartEditorController.new()

	assert_str(controller._identifier_validation_error("value")).is_empty()
	assert_str(controller._identifier_validation_error("_value")).is_empty()
	assert_str(controller._identifier_validation_error("value_2")).is_empty()
	assert_str(controller._identifier_validation_error(" value ")).is_empty()

	controller.free()


func test_identifier_validation_rejects_invalid_names() -> void:
	var controller := SmartEditorController.new()

	assert_str(controller._identifier_validation_error("")).is_equal("Name is required.")
	assert_str(controller._identifier_validation_error("2value")).is_equal("Name must start with a letter or underscore.")
	assert_str(controller._identifier_validation_error("value-name")).is_equal("Name can only contain letters, digits, and underscores.")
	assert_str(controller._identifier_validation_error("value.name")).is_equal("Name can only contain letters, digits, and underscores.")
	assert_str(controller._identifier_validation_error("func")).is_equal("'func' is reserved by GDScript.")
	assert_str(controller._identifier_validation_error("var")).is_equal("'var' is reserved by GDScript.")
	assert_str(controller._identifier_validation_error("int")).is_equal("'int' is reserved by GDScript.")

	controller.free()


func test_identifier_validation_allows_rename_no_op() -> void:
	var controller := SmartEditorController.new()

	assert_str(controller._identifier_validation_error("health", "health")).is_empty()

	controller.free()
