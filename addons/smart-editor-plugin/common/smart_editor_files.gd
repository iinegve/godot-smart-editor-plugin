@tool
extends RefCounted


static func path_to_file_uri(path: String) -> String:
	var encoded_path := path.uri_encode().replace("%2F", "/").lstrip("/")
	return "file:///" + encoded_path


static func file_uri_to_path(uri: String) -> String:
	return _file_uri_to_path(uri, OS.has_feature("windows"))


static func _file_uri_to_path(uri: String, is_windows: bool) -> String:
	var path := uri.trim_prefix("file://").uri_decode()
	if is_windows and _has_windows_drive_with_leading_slash(path):
		return path.substr(1)

	return path


static func _has_windows_drive_with_leading_slash(path: String) -> bool:
	if path.length() < 3 or path[0] != "/" or path[2] != ":":
		return false
	if path.length() > 3 and path[3] != "/":
		return false

	var drive_letter := path.unicode_at(1)
	return (
		(drive_letter >= "A".unicode_at(0) and drive_letter <= "Z".unicode_at(0))
		or (drive_letter >= "a".unicode_at(0) and drive_letter <= "z".unicode_at(0))
	)
