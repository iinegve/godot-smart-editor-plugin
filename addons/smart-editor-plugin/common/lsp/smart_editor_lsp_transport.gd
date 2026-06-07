@tool
extends RefCounted

var _tcp := StreamPeerTCP.new()
var _read_buffer := PackedByteArray()


func connect_to_host(host: String, port: int) -> bool:
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return true

	disconnect_from_host()
	return _tcp.connect_to_host(host, port) == OK


func disconnect_from_host() -> void:
	_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_read_buffer.clear()


func get_status() -> int:
	return _tcp.get_status()


func poll() -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	if _tcp.get_status() == StreamPeerTCP.STATUS_NONE:
		return messages

	_tcp.poll()
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		messages.append_array(_read_available_messages())
	elif _tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
		disconnect_from_host()

	return messages


func send_message(message: Dictionary) -> void:
	var body := JSON.stringify(message)
	var packet := "Content-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
	_tcp.put_data(packet.to_utf8_buffer())


func _read_available_messages() -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return messages

	var read_result := _tcp.get_data(available)
	if read_result[0] != OK:
		return messages

	_read_buffer.append_array(read_result[1])
	while true:
		var body := try_extract_lsp_body(_read_buffer)
		if body.is_empty():
			return messages

		_read_buffer = consume_lsp_message(_read_buffer)
		var message = JSON.parse_string(body)
		if typeof(message) == TYPE_DICTIONARY:
			messages.append(message)

	return messages


static func try_extract_lsp_body(buffer: PackedByteArray) -> String:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := find_bytes(buffer, marker)
	if header_end == -1:
		return ""

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := parse_content_length(header)
	if content_length <= 0:
		return ""

	var body_start := header_end + marker.size()
	var body_end := body_start + content_length
	if buffer.size() < body_end:
		return ""

	return buffer.slice(body_start, body_end).get_string_from_utf8()


static func consume_lsp_message(buffer: PackedByteArray) -> PackedByteArray:
	var marker := "\r\n\r\n".to_utf8_buffer()
	var header_end := find_bytes(buffer, marker)
	if header_end == -1:
		return buffer

	var header := buffer.slice(0, header_end).get_string_from_utf8()
	var content_length := parse_content_length(header)
	if content_length <= 0:
		return buffer.slice(header_end + marker.size())

	var body_end := header_end + marker.size() + content_length
	if buffer.size() < body_end:
		return buffer

	return buffer.slice(body_end)


static func find_bytes(buffer: PackedByteArray, needle: PackedByteArray) -> int:
	for index in range(0, buffer.size() - needle.size() + 1):
		var found := true
		for needle_index in needle.size():
			if buffer[index + needle_index] != needle[needle_index]:
				found = false
				break
		if found:
			return index

	return -1


static func parse_content_length(header: String) -> int:
	for line in header.split("\r\n"):
		var parts := line.split(":", false, 1)
		if parts.size() == 2 and parts[0].strip_edges().to_lower() == "content-length":
			return parts[1].strip_edges().to_int()

	return -1


static func normalize_response_id(id: Variant) -> int:
	if typeof(id) == TYPE_FLOAT:
		return int(id)
	if typeof(id) == TYPE_INT:
		return id

	return str(id).to_int()


static func text_signature(text: String) -> String:
	return "%d:%d" % [text.length(), text.hash()]
