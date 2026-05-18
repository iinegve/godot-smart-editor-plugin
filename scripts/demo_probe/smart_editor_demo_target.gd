@tool
class_name SmartEditorDemoTarget
extends RefCounted

const SHARED_ROUND_LIMIT := 5

var score_multiplier: int = 10
var last_call_site: String = ""


func build_round_label(prefix: String, round_count: int) -> String:
	# Rename this function to demonstrate a cross-file method rename.
	var scored_round: int = score_round(round_count)
	return "%s_%d" % [prefix, scored_round]


func score_round(round_count: int) -> int:
	# Rename SHARED_ROUND_LIMIT or score_multiplier to demo member and constant renames.
	var capped_round: int = mini(round_count, SHARED_ROUND_LIMIT)
	return capped_round * score_multiplier


func record_call_site(source_name: String) -> String:
	# Run Call Hierarchy here; callers from both demo files should appear.
	last_call_site = "%s:%s" % [source_name, build_round_label("hierarchy", 1)]
	return last_call_site


func replay_call_site() -> String:
	# Same-file caller for the Call Hierarchy dock.
	return record_call_site("replay")
