@tool
extends RefCounted


# Exact names, prefixes and contiguous matches precede abbreviation matches.
# Match the name first so a directory/signature cannot outrank an exact name.
static func score(query: String, name: String, context: String = "") -> int:
	var terms := query.strip_edges().to_lower().replace("\\", "/").split(" ", false)
	var total := 0
	for term in terms:
		var name_score := _term_score(term, name.to_lower())
		if name_score >= 0:
			total += name_score
			continue
		var context_score := _term_score(term, context.to_lower())
		if context_score < 0:
			return -1
		total += 10000 + context_score
	return total


static func _term_score(term: String, value: String) -> int:
	if term == value:
		return 0
	if value.begins_with(term):
		return 100 + value.length() - term.length()
	var substring := value.find(term)
	if substring >= 0:
		return 200 + substring + value.length() - term.length()
	var cursor := 0
	var first := -1
	var last := -1
	for character in term:
		var found := value.find(character, cursor)
		if found < 0:
			return -1
		if first < 0:
			first = found
		last = found
		cursor = found + 1
	return 1000 + first + (last - first + 1 - term.length()) * 10 + value.length()
