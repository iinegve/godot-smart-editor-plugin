extends GdUnitTestSuite

const GDScriptIdentifierValidator := preload("res://addons/smart-editor-plugin/common/gdscript_identifier_validator.gd")


func test_identifier_validation_accepts_valid_names() -> void:
	var validator := GDScriptIdentifierValidator.new()

	assert_str(validator.identifier_validation_error("value")).is_empty()
	assert_str(validator.identifier_validation_error("_value")).is_empty()
	assert_str(validator.identifier_validation_error("value_2")).is_empty()
	assert_str(validator.identifier_validation_error(" value ")).is_empty()


func test_identifier_validation_rejects_invalid_names() -> void:
	var validator := GDScriptIdentifierValidator.new()

	assert_str(validator.identifier_validation_error("")).is_equal("Name is required.")
	assert_str(validator.identifier_validation_error("2value")).is_equal("Name must start with a letter or underscore.")
	assert_str(validator.identifier_validation_error("value-name")).is_equal("Name can only contain letters, digits, and underscores.")
	assert_str(validator.identifier_validation_error("value.name")).is_equal("Name can only contain letters, digits, and underscores.")
	assert_str(validator.identifier_validation_error("func")).is_equal("'func' is reserved by GDScript.")
	assert_str(validator.identifier_validation_error("var")).is_equal("'var' is reserved by GDScript.")
	assert_str(validator.identifier_validation_error("int")).is_equal("'int' is reserved by GDScript.")


func test_identifier_validation_allows_rename_no_op() -> void:
	var validator := GDScriptIdentifierValidator.new()

	assert_str(validator.identifier_validation_error("health")).is_empty()
