@tool
class_name RenameProbeTarget
extends RefCounted

const SHARED_LIMIT111231 := 3

var class_counter := 0
var last_label := ""


func build_label12311(seed: int) -> String:
	var local_total := seed + SHARED_LIMIT111231
	class_counter += local_total
	last_label = _format_label(local_total)
	return last_label

func call_self(seed: int) -> String:
	return build_label12311(seed + 1)

func _format_label(value: int) -> String:
	var b = "value"
	return "target_%d" % value
