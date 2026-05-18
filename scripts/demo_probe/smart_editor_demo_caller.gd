@tool
class_name SmartEditorDemoCaller
extends RefCounted

const LOCAL_ROUND_LIMIT_RENAMED := 3
const SHARED_ROUND_LIMIT := SmartEditorDemoTarget.SHARED_ROUND_LIMIT

var target: SmartEditorDemoTarget = SmartEditorDemoTarget.new()
var cached_summary: String = ""

## Introducing Smart Editor Plugin for Godot!!!

func demo_start_here() -> String:
	# Start the recording here so the demo has a clear first frame.
	cached_summary = "Smart Editor demo begins"
	return cached_summary


func demo_expand_selection() -> Dictionary:
	# Put the caret inside the nested call and expand selection outward.
	var round_report := {
		"label": target.build_round_label("expand", SHARED_ROUND_LIMIT + 1),
		"scores": [
			target.score_round(1),
			target.score_round(LOCAL_ROUND_LIMIT_RENAMED),
			target.score_round(SHARED_ROUND_LIMIT),
		],
	}
	return round_report


func demo_extract_variable() -> String:
	# Select the long expression and extract it into a named local variable.
	var round = LOCAL_ROUND_LIMIT_RENAMED + SHARED_ROUND_LIMIT
	var score_round = (round) * 2 + target.score_round(1)
	return target.build_round_label("extract", score_round)


func demo_inline_variable() -> String:
	# Put the caret on inline_candidate in this declaration and inline it below.
	return "inline result: %s" % target.build_round_label("inline", LOCAL_ROUND_LIMIT_RENAMED)


func demo_rename_local_variable() -> String:
	# Rename temporary_label and both references in this function should change.
	var round_label: String = target.build_round_label("local", LOCAL_ROUND_LIMIT_RENAMED)
	cached_summary = round_label
	# Unfortunately undo doesn't work as expected
	return round_label


func demo_rename_constant() -> int:
	# Rename LOCAL_ROUND_LIMIT_RENAMED to show a simple constant rename.
	return LOCAL_ROUND_LIMIT_RENAMED + target.score_round(LOCAL_ROUND_LIMIT_RENAMED)


func demo_rename_function() -> String:
	# Rename build_round_label; undo is not grouped into one editor action.
	return target.build_round_label("method", SHARED_ROUND_LIMIT)


func demo_highlights() -> int:
	# Put the caret on highlight_total to show stripe and in-editor highlights.
	var highlight_total: int = 0
	highlight_total += target.score_round(1)
	highlight_total += target.score_round(2)
	highlight_total += target.score_round(3)
	return highlight_total


func demo_call_hierarchy_entry() -> String:
	# Run Call Hierarchy on record_call_site to see this caller.
	return target.record_call_site("entry")


func demo_call_hierarchy_second_entry() -> String:
	# A second caller makes the hierarchy result more interesting.
	return target.record_call_site("second")


func demo_function_boundary_guides() -> Array[String]:
	# This compact function sits between others so boundary guide lines are visible.
	return [
		demo_inline_variable(),
		demo_rename_function(),
		target.replay_call_site(),
	]


func demo_end_here() -> String:
	# End the recording here so the gif has an obvious final frame.
	cached_summary = "Smart Editor demo complete"
	return cached_summary


func run_all_demos() -> Array[String]:
	# Keeps every demo path reachable for hierarchy, rename, and highlight demos.
	return [
		demo_start_here(),
		str(demo_expand_selection()),
		demo_extract_variable(),
		demo_inline_variable(),
		demo_rename_local_variable(),
		str(demo_rename_constant()),
		demo_rename_function(),
		str(demo_highlights()),
		demo_call_hierarchy_entry(),
		demo_call_hierarchy_second_entry(),
		str(demo_function_boundary_guides()),
		demo_end_here(),
	]
