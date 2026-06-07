@tool
extends RefCounted


static func path_to_file_uri(path: String) -> String:
	return "file://" + path.uri_encode().replace("%2F", "/")


static func file_uri_to_path(uri: String) -> String:
	return uri.trim_prefix("file://").uri_decode()
