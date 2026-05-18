@tool
class_name RenameProbeCaller
extends RefCounted

const TARGET_LIMIT123 := RenameProbeTarget.SHARED_LIMIT111231

var target := RenameProbeTarget.new()
var cached_label := ""


func run_probe() -> String:
	var local_seed := TARGET_LIMIT123
	cached_label = target.build_label12311(local_seed)
	cached_label = _decorate_probe_label1323(cached_label)
	return cached_label


func call_target_twice() -> Array[String]:
	return [
		target.build_label12311(1),
		target.call_self(2),
	]


func _decorate_probe_label1323(value: String) -> String:
	return "caller:%s" % value
