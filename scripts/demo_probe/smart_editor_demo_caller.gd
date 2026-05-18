@tool
class_name SmartEditorDemoCaller
extends RefCounted

const LOCAL_ROUND_LIMIT := 3
const SHARED_ROUND_LIMIT := SmartEditorDemoTarget.SHARED_ROUND_LIMIT

var target: SmartEditorDemoTarget = SmartEditorDemoTarget.new()
var cached_summary: String = ""


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
			target.score_round(LOCAL_ROUND_LIMIT),
			target.score_round(SHARED_ROUND_LIMIT),
		],
	}
	return round_report


func demo_extract_variable() -> String:
	# Select the long expression and extract it into a named local variable.
	return target.build_round_label("extract", (LOCAL_ROUND_LIMIT + SHARED_ROUND_LIMIT) * 2 + target.score_round(1))


func demo_inline_variable() -> String:
	# Put the caret on inline_candidate and inline it into the return statement.
	var inline_candidate: String = target.build_round_label("inline", LOCAL_ROUND_LIMIT)
	return "inline result: %s" % inline_candidate


func demo_rename_local_variable() -> String:
	# Rename temporary_label and both references in this function should change.
	var temporary_label: String = target.build_round_label("local", LOCAL_ROUND_LIMIT)
	cached_summary = temporary_label
	return temporary_label


func demo_rename_constant() -> int:
	# Rename LOCAL_ROUND_LIMIT to show a simple constant rename.
	return LOCAL_ROUND_LIMIT + target.score_round(LOCAL_ROUND_LIMIT)


func demo_rename_function() -> String:
	# Rename build_round_label from this call or from its definition.
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
