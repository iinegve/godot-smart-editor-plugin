@tool
extends RefCounted

const RUSSIAN_KEYS := "ёйцукенгшщзхъфывапролджэячсмитьбю"
const ENGLISH_KEYS := "`qwertyuiop[]asdfghjkl;'zxcvbnm,."


# Exact names, prefixes and contiguous matches precede abbreviation matches.
# Match the name first so a directory/signature cannot outrank an exact name.
static func score(query: String, name: String, context: String = "") -> int:
	query = query.strip_edges().to_lower().replace("\\", "/")
	name = name.to_lower()
	context = context.to_lower()
	var rank := _query_score(query, name, context)
	var alternative := _english_layout(query)
	if alternative != query:
		var alternative_rank := _query_score(alternative, name, context)
		if alternative_rank >= 0:
			# Prefer the literal spelling when both interpretations rank equally.
			alternative_rank += 1
			if rank < 0 or alternative_rank < rank:
				rank = alternative_rank
	return rank


static func _query_score(query: String, name: String, context: String) -> int:
	var terms := query.split(" ", false)
	var total := 0
	for term in terms:
		var name_score := _term_score(term, name)
		if name_score >= 0:
			total += name_score
			continue
		var context_score := _term_score(term, context)
		if context_score < 0:
			return -1
		total += 10000 + context_score
	return total


static func _english_layout(query: String) -> String:
	var output := ""
	for character in query:
		var key := RUSSIAN_KEYS.find(character)
		output += ENGLISH_KEYS[key] if key >= 0 else character
	return output


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
