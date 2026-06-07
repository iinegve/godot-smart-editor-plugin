extends RefCounted

signal completed(response)

var kind := ""
var response = null
var is_completed := false


static func create(request_kind: String):
	var request := new()
	request.kind = request_kind
	return request


func complete(completed_response) -> void:
	if is_completed:
		return

	response = completed_response
	is_completed = true
	completed.emit(response)
