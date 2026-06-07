extends RefCounted

var ok := false
var result: Variant = null
var error: Variant = null


static func success(response_result: Variant = null):
	var response := new()
	response.ok = true
	response.result = response_result
	return response


static func failure(response_error: Variant = null):
	var response := new()
	response.ok = false
	response.error = response_error
	return response
