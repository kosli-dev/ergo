package ergo

import rego.v1

_assertion_kinds(kinds) if {
	every k in kinds {
		k == "assertion"
	}
}

_s_patterns := {
	"assertions": concat("", [`(`, assertion, `)(?: +and +|$)`]),
	"assertion": concat("", [`^(?:(every|some) +(`, qpath, `)|(`, left, `))(?: +(`, conds, `))?(, +if +any,)? +(`, phrase, `)$`]),
	"for_items": concat("", [`(`, for_item, `)(?:, +|$)`]),
	"for_item": concat("", [`^(?:(every|some) +)?(`, qpath, `)(?: +(`, conds, `))?(?: +sorted +by +(`, path, `)( +alphabetically)?)?(, +if +any,)? +as +(`, key, `)$`]),
	"from": concat("", [`^(`, qpath, `)(?: +named +by +each +of +(`, rpath, `))?(?: +(`, from_conds, `))?$`]),
	"from_conds": concat("", [`(`, from_cond, `)(?: +and +|$)`]),
	"from_cond": concat("", [`^(?:whose +(?:(every|some) +(`, qpath, `)(, +if +any,)?|(`, left, `)) +|that +)(`, phrase, `)$`]),
	"conds": concat("", [`(`, cond, `)(?: +and +|$)`]),
	"cond": concat("", [`^(?:whose +(`, left, `) +|that +)(`, phrase, `)$`]),
	"phrases": phrases,
	"kinds": object.union({kind[0]: concat("", [`^(?:`, kind[1], `)$`]) | some kind in kinds}, {"operand": concat("", [`^(?:`, joined, `)$`]), "operand_within": concat("", [`^(?:`, joined, `(?: +within +`, num, `)?)$`])}),
	"plain": concat("", [`^(`, path, `) +(\S.*)$`]),
	"quantified": concat("", [`^(every|some) +(`, qpath, `) +(\S.*)$`]),
	"path": concat("", [`^`, path, `$`]),
	"path_parts": concat("", [`^(?:(item +([1-9][0-9]*)( +from +last)?|first|last) +of +)?(`, start, `)((?:`, step, `)*)$`]),
	"steps": concat("", [`\.(`, key, `|`, dq, `)| +named +by +(`, ref, `)|\[(`, ref, `)\]|\[(`, dq, `)\]|\[(0|[1-9][0-9]*)\]`]),
	"terms": concat("", [`(`, term, `)(?: +plus +|$)`]),
	"number": concat("", [`^`, num, `$`]),
	"derived": concat("", [`^(count|sum) +of +(`, qpath, `)$`]),
	"elapsed": concat("", [`^(seconds|minutes|hours|days|weeks) +elapsed +from +(`, path, `) +to +(`, path, `)$`]),
	"value": concat("", [`^`, value, `$`]),
	"values": concat("", [`^`, values, `$`]),
	"each_value": value,
	"range": concat("", [`^(`, num, `) +and +(`, num, `)$`]),
	"operand_within": concat("", [`^(`, joined, `)(?: +within +(`, num, `))?$`]),
	"join": concat("", [`^(`, single, `)((?:`, later, `)+)$`]),
	"join_rest": concat("", [` +followed +by +(`, value, `|`, rpath, `)`]),
	"quotes": `^(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^"']+)*`,
	"strings": `"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'`,
	"string": concat("", [`^(?:`, dq, `|`, sq, `)$`]),
	"quantified_path": concat("", [`^(?:(?:every|some) +)?`, qpath, `$`]),
} if {
	key := `[A-Za-z_][A-Za-z0-9_-]*`
	dq := `"(?:[^"\\\x00-\x1f]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*"`
	sq := `'(?:[^'\\\x00-\x1f]|\\[^\x00-\x1f])*'`
	num := `-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?`
	name := `\$[A-Za-z_]\w*`
	ref := concat("", [name, `(?:\.(?:`, key, `|`, dq, `))?|`, key])
	step := concat("", [`\.(?:`, key, `|`, dq, `)| +named +by +(?:`, ref, `)|\[(?:`, ref, `|`, dq, `|0|[1-9][0-9]*)\]`])
	start := concat("", [name, `|\.?(?:`, key, `|`, dq, `)`])
	rstart := concat("", [name, `|`, key, `|\.(?:`, key, `|`, dq, `)`])
	pos := `(?:item +[1-9][0-9]*(?: +from +last)?|first|last) +of +`
	plain := concat("", [`(?:`, start, `)(?:`, step, `)*`])
	path := concat("", [`(?:`, pos, `)?`, plain])
	qpath := concat("", [`(?:distinct +)?`, path])
	rpath := concat("", [`(?:`, pos, `)?(?:`, rstart, `)(?:`, step, `)*`])
	elapsed := concat("", [`(?:seconds|minutes|hours|days|weeks) +elapsed +from +`, path, ` +to +`, path])
	derived := concat("", [`(?:(?:count|sum) +of +`, qpath, `|`, elapsed, `)`])
	term := concat("", [`(?:`, derived, `|`, rpath, `|`, num, `)`])
	terms := concat("", [term, `(?: +plus +`, term, `)*`])
	left := concat("", [`(?:`, path, `|`, terms, `)`])
	value := concat("", [`(?:`, dq, `|`, sq, `|`, num, `|true|false|null)`])
	values := concat("", [value, `(?:, *`, value, `)*`])
	single := concat("", [`(?:`, num, `(?: +plus +`, term, `)+|`, value, `|(?:`, derived, `|`, rpath, `)(?: +plus +`, term, `)*)`])
	later := concat("", [` +followed +by +(?:`, value, `|`, rpath, `)`])
	bit := `(?:[^\s"'\\]|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\\.)+`
	roughly := concat("", [` +followed +by +(?:`, pos, `)?`, bit, `(?: +named +by +`, bit, `)*`])
	operand := single
	joined := concat("", [single, `(?:`, later, `)*`])
	list := concat("", [`(?:`, values, `|`, rpath, `)`])
	type := `(?:list|string|number|boolean|object)`
	phrases := [
		["is not one of", `is +not +(?:one +of|in) +`, list, "list"],
		["is one of", `is +(?:one +of|in) +`, list, "list"],
		["is a non-empty string", `is +(?:not +)?a +non-empty +string`, ``, "none", [["not", "is not a non-empty string"]]],
		["is a", `is +(?:not +)?an? +`, type, "type", [["not", "is not a"]]],
		["is not empty", `is +not +empty`, ``, "none"],
		["is empty", `is +empty`, ``, "none"],
		["does not exist", `does +not +exist`, ``, "none"],
		["exists", `exists`, ``, "none"],
		["contains all of", `(?:contains|does +not +contain) +all +of +`, list, "list", [["not", "does not contain all of"]]],
		["contains none of", `contains +(?:none|some) +of +`, list, "list", [["some", "contains some of"]]],
		["does not contain", `does +not +contain +`, operand, "operand"],
		["contains", `contains +`, operand, "operand"],
		["does not match", `does +not +match +`, list, "list"],
		["matches", `matches +`, list, "list"],
		["starts with", `(?:starts|does +not +start) +with +`, operand, "operand", [["not", "does not start with"]]],
		["ends with", `(?:ends|does +not +end) +with +`, operand, "operand", [["not", "does not end with"]]],
		["is alphabetically before", `is +alphabetically +(?:on +or +)?before +`, operand, "operand", [["on", "is alphabetically on or before"]]],
		["is alphabetically after", `is +alphabetically +(?:on +or +)?after +`, operand, "operand", [["on", "is alphabetically on or after"]]],
		["is at least", `is +at +least +`, operand, "operand"],
		["is at most", `is +at +most +`, operand, "operand"],
		["is more than", `is +more +than +`, operand, "operand"],
		["is less than", `is +less +than +`, operand, "operand"],
		["is between", `is +(?:not +)?between +`, concat("", [num, ` +and +`, num]), "range", [["not", "is not between"]]],
		["is on or after", `is +on +or +after +`, operand, "operand"],
		["is on or before", `is +on +or +before +`, operand, "operand"],
		["is before", `is +before +`, operand, "operand"],
		["is after", `is +after +`, operand, "operand"],
		["is not", `(?:is +not|does +not +equal) +`, concat("", [operand, `(?: +within +`, num, `)?`]), "operand_within"],
		["is", `(?:is +equal +to|equals|is) +`, concat("", [operand, `(?: +within +`, num, `)?`]), "operand_within"],
	]
	kinds := [
		["none", ``],
		["type", type],
		["range", concat("", [num, ` +and +`, num])],
		["list", list],
		["operand", operand],
		["operand_within", concat("", [operand, `(?:`, roughly, `)*(?: +within +`, num, `)?`])],
	]
	phrase := concat("", [`(?:`, concat("|", [concat("", [`(?:`, concat("|", [ph[1] | some ph in phrases; ph[3] == kind[0]]), `)`, kind[1]]) | some kind in kinds]), `)(?:`, roughly, `)*`])
	cond := concat("", [`(?:whose +(?:`, derived, `|`, path, `) +|that +)(?:`, phrase, `)`])
	conds := concat("", [cond, `(?: +and +`, cond, `)*`])
	from_cond := concat("", [`(?:whose +(?:(?:every|some) +`, qpath, `(?:, +if +any,)?|(?:`, derived, `|`, path, `)) +|that +)(?:`, phrase, `)`])
	from_conds := concat("", [from_cond, `(?: +and +`, from_cond, `)*`])
	assertion := concat("", [`(?:(?:every|some) +`, qpath, `|`, left, `)(?: +`, conds, `)?(?:, +if +any,)? +(?:`, phrase, `)`])
	for_item := concat("", [`(?:(?:every|some) +)?`, qpath, `(?: +`, conds, `)?(?: +sorted +by +`, path, `(?: +alphabetically)?)?(?:, +if +any,)? +as +`, key])
}

_s_words := {"a", "after", "alphabetically", "an", "and", "as", "at", "before", "between", "count", "days", "distinct", "each", "empty", "equal", "every", "false", "first", "hours", "in", "item", "last", "less", "minutes", "more", "named", "not", "null", "of", "on", "one", "or", "plus", "seconds", "some", "sorted", "sum", "that", "to", "true", "weeks", "whose", "within"}

_s_pieces(pattern, text) := [m[1] | some m in matches] if {
	matches := regex.find_all_string_submatch_n(pattern, text, -1)
	concat("", [m[0] | some m in matches]) == text
}

_sentence(raw) := {"assertions": [assertion]} if {
	pat := _s_patterns
	m := regex.find_all_string_submatch_n(pat.plain, trim_space(raw), 1)[0]
	assertion := {"path": _s_path_of(m[1], pat), "phrase": _s_phrase_of(m[2], pat)}
	count(_s_sentence_problems({"assertions": [assertion]})) == 0
	count(_s_text_names(trim_space(raw))) == 0
} else := {"assertions": [assertion]} if {
	pat := _s_patterns
	m := regex.find_all_string_submatch_n(pat.quantified, trim_space(raw), 1)[0]
	assertion := object.union({m[1]: _s_qpath_of(m[2], pat), "phrase": _s_phrase_of(m[3], pat)}, _s_distinct_of(m[2]))
	count(_s_sentence_problems({"assertions": [assertion]})) == 0
	count(_s_text_names(trim_space(raw))) == 0
} else := {"assertions": assertions} if {
	pat := _s_patterns
	text := trim_space(raw)
	pieces := _s_pieces(pat.assertions, text)
	assertions := [_s_assertion_of(a, pat) | some a in pieces]
	count(assertions) == count(pieces)
	count(pieces) > 0
	count(_s_sentence_problems({"assertions": assertions})) == 0
	count(_s_text_names(text)) == 0
} else := {"problems": _s_problems(trim_space(raw), _s_patterns)}

_for_line(raw) := {"items": items} if {
	pat := _s_patterns
	text := trim_space(raw)
	pieces := _s_pieces(pat.for_items, text)
	items := [_s_for_item_of(a, pat) | some a in pieces]
	count(items) == count(pieces)
	count(pieces) in {1, 2}
	count(_s_sentence_problems({"items": items})) == 0
	count(_s_text_names(text)) == 0
} else := {"problems": sort(names)} if {
	pat := _s_patterns
	text := trim_space(raw)
	names := _s_text_names(text)
	count(names) > 0
	pieces := _s_pieces(pat.for_items, text)
	items := [_s_for_item_of(a, pat) | some a in pieces]
	count(items) == count(pieces)
	count(pieces) in {1, 2}
	count(_s_sentence_problems({"items": items})) == 0
} else := {"problems": _for_line_problems(trim_space(raw), _s_patterns)}

_for_line_problems(text, pat) := ["a for line holds two items at most"] if {
	pieces := _s_pieces(pat.for_items, text)
	count(pieces) > 2
	count([a | some a in pieces; _s_for_item_of(a, pat)]) == count(pieces)
} else := [`an item starts with "every", "some" or a position, like "last of"`] if {
	not regex.match(`^(?:every|some|first|last|item) `, text)
} else := [`an item ends with "as" and a name, like "every pull_requests as pr"`] if {
	not regex.match(` as +[^ ,]+$`, text)
} else := _s_problems(text, pat)

_from_line(raw) := line if {
	pat := _s_patterns
	line := _s_from_of(trim_space(raw), pat)
	count(_s_sentence_problems(line)) == 0
	count(_s_text_names(trim_space(raw))) == 0
} else := {"problems": sort(names), "parsed": line} if {
	line := _s_from_of(trim_space(raw), _s_patterns)
	count(_s_sentence_problems(line)) == 0
	names := _s_text_names(trim_space(raw))
	count(names) > 0
} else := {"problems": _from_problems(_s_after_every(trim_space(raw)), _s_patterns)}

_from_problems(text, pat) := ["a condition after whose can't have a whose of its own"] if {
	_s_problems(text, pat) in [["doesn't parse"], [_s_bare_and]]
	regex.match(` +whose +(?:.* +and +whose +)?(?:(?:every|some) +|(?:count|sum) +of +)\S+ +whose +`, text)
} else := _s_problems(text, pat)

_s_pick_problems(parsed) := (((({_s_distinct_misplaced |
	some item in object.get(parsed, "items", [])
	"pick" in object.keys(item)
	object.get(item, "distinct", false) == true
} | {`an item starts with "every", "some" or a position, like "last of"` |
	some item in object.get(parsed, "items", [])
	not "position" in object.keys(object.get(item, "pick", {"position": 1}))
}) | {`"sorted by" goes after a position, like "last of", not after every or some` |
	some item in object.get(parsed, "items", [])
	"sorted_by" in object.keys(item)
	not "pick" in object.keys(item)
}) | {"if any can't go with a position" |
	some item in object.get(parsed, "items", [])
	"pick" in object.keys(item)
	object.get(item, "if_any", false) == true
}) | {`"sorted by" reads a field of each item` |
	some item in object.get(parsed, "items", [])
	object.keys(item.sorted_by) & {"start", "position"} != set()
}) | {concat("", [`"sorted by" reads a field of the item, not `, name, ": write .", name]) |
	some item in object.get(parsed, "items", [])
	object.keys(item.sorted_by) & {"start", "position"} == set()
	object.get(item.sorted_by, "dot", false) != true
	name := item.sorted_by.steps[0]
	name in {i.as | some i in parsed.items}
}

_s_after_every(text) := m[1] if {
	m := regex.find_all_string_submatch_n(`^every +(\S.*)$`, text, 1)[0]
} else := text

_s_from_of(text, pat) := object.union(_s_from_plain(m[1], pat), {"every": true}) if {
	m := regex.find_all_string_submatch_n(`^every +(\S.*)$`, text, 1)[0]
} else := _s_from_plain(text, pat)

_s_from_plain(text, pat) := object.union(object.union({"path": _s_qpath_of(m[1], pat)}, _s_distinct_of(m[1])), object.union(_s_each_of(m[2], pat), _s_from_where_of(m[3], pat))) if {
	m := regex.find_all_string_submatch_n(pat.from, text, 1)[0]
}

_s_each_of("", _) := {}

_s_each_of(text, pat) := {"named_by_each_of": _s_path_of(text, pat)} if text != ""

_s_assertion_of(text, pat) := out if {
	m := regex.find_all_string_submatch_n(pat.assertion, text, 1)[0]
	m[1] != ""
	out := object.union(
		object.union({m[1]: _s_qpath_of(m[2], pat), "phrase": _s_phrase_of(m[6], pat)}, _s_distinct_of(m[2])),
		object.union(_s_where_of(m[4], pat), _s_if_any(m[5])),
	)
}

_s_assertion_of(text, pat) := out if {
	m := regex.find_all_string_submatch_n(pat.assertion, text, 1)[0]
	m[1] == ""
	m[5] == ""
	out := object.union(_s_left_of(m[3], pat), object.union(_s_where_of(m[4], pat), {"phrase": _s_phrase_of(m[6], pat)}))
}

_s_for_item_of(text, pat) := out if {
	m := regex.find_all_string_submatch_n(pat.for_item, text, 1)[0]
	out := object.union(
		object.union({_s_item_word(m[1]): _s_item_path_of(m[1], _s_undistinct(m[2]), pat), "as": m[7]}, _s_distinct_of(m[2])),
		object.union(object.union(_s_where_of(m[3], pat), _s_if_any(m[6])), _s_sorted_by(m[4], m[5], pat)),
	)
}

_s_item_path_of("", text, pat) := _s_unlifted_path_of(text, pat)

_s_item_path_of(q, text, pat) := _s_path_of(text, pat) if q != ""

_s_item_word("") := "pick"

_s_item_word(q) := q if q != ""

_s_sorted_by("", _, _) := {}

_s_sorted_by(text, "", pat) := {"sorted_by": _s_unlifted_path_of(text, pat)} if text != ""

_s_sorted_by(text, alphabetically, pat) := {"sorted_by": _s_unlifted_path_of(text, pat), "alphabetically": true} if {
	text != ""
	alphabetically != ""
}

_s_alphabetically_text(item) := " alphabetically" if object.get(item, "alphabetically", false) == true

else := ""

_s_if_any("") := {}

_s_if_any(text) := {"if_any": true} if text != ""

_s_where_of("", _) := {}

_s_where_of(text, pat) := {"where": conds} if {
	text != ""
	pieces := _s_pieces(pat.conds, text)
	conds := [_s_cond_of(c, pat) | some c in pieces]
	count(conds) == count(pieces)
}

_s_from_where_of("", _) := {}

_s_from_where_of(text, pat) := {"where": conds} if {
	text != ""
	pieces := _s_pieces(pat.from_conds, text)
	conds := [_s_from_cond_of(c, pat) | some c in pieces]
	count(conds) == count(pieces)
}

_s_from_cond_of(text, pat) := object.union(object.union({m[1]: _s_qpath_of(m[2], pat), "phrase": _s_phrase_of(m[5], pat)}, _s_distinct_of(m[2])), _s_if_any(m[3])) if {
	m := regex.find_all_string_submatch_n(pat.from_cond, text, 1)[0]
	m[1] != ""
}

_s_from_cond_of(text, pat) := object.union(_s_left_of(m[4], pat), {"phrase": _s_phrase_of(m[5], pat)}) if {
	m := regex.find_all_string_submatch_n(pat.from_cond, text, 1)[0]
	m[1] == ""
	m[4] != ""
}

_s_from_cond_of(text, pat) := {"path": _s_that_path, "phrase": _s_phrase_of(m[5], pat)} if {
	m := regex.find_all_string_submatch_n(pat.from_cond, text, 1)[0]
	m[1] == ""
	m[4] == ""
}

_s_that_path := {"steps": ["that"], "that": true}

_s_place_word(node) := "that" if object.get(node.where[0], ["path", "that"], false) == true

else := "whose"

_s_cond_of(text, pat) := object.union(_s_left_of(m[1], pat), {"phrase": _s_phrase_of(m[2], pat)}) if {
	m := regex.find_all_string_submatch_n(pat.cond, text, 1)[0]
	m[1] != ""
}

_s_cond_of(text, pat) := {"path": _s_that_path, "phrase": _s_phrase_of(m[2], pat)} if {
	m := regex.find_all_string_submatch_n(pat.cond, text, 1)[0]
	m[1] == ""
}

_s_left_of(text, pat) := {"path": _s_path_of(text, pat)} if {
	regex.match(pat.path, text)
} else := {"terms": _s_terms_of(text, pat)}

_s_terms_of(text, pat) := terms if {
	pieces := _s_pieces(pat.terms, text)
	terms := [_s_term_of(t, pat) | some t in pieces]
	count(terms) == count(pieces)
}

_s_term_of(text, pat) := _s_number(text) if {
	regex.match(pat.number, text)
} else := object.union({m[1]: _s_qpath_of(m[2], pat)}, _s_distinct_of(m[2])) if {
	m := regex.find_all_string_submatch_n(pat.derived, text, 1)[0]
} else := {"unit": m[1], "elapsed_from": _s_path_of(m[2], pat), "elapsed_to": _s_path_of(m[3], pat)} if {
	m := regex.find_all_string_submatch_n(pat.elapsed, text, 1)[0]
} else := _s_path_of(text, pat)

_s_path_of(text, pat) := _s_lifted(_s_unlifted_path_of(text, pat))

_s_qpath_of(text, pat) := _s_path_of(_s_undistinct(text), pat)

_s_undistinct(text) := m[1] if {
	m := regex.find_all_string_submatch_n(`^distinct +(\S.*)$`, text, 1)[0]
} else := text

_s_distinct_of(text) := {"distinct": true} if _s_undistinct(text) != text

else := {}

_s_distinct_of_node(a) := {"distinct": true} if object.get(a, "distinct", false) == true

else := {}

_s_distinct_text(a) := "distinct " if object.get(a, "distinct", false) == true

else := ""

_s_unlifted_path_of(text, pat) := object.union(_s_position_of(m[1], m[2], m[3]), _s_start_of(m[4], _s_steps_of(m[5], pat))) if {
	m := regex.find_all_string_submatch_n(pat.path_parts, text, 1)[0]
}

_s_lifted(path) := object.union(object.union(object.remove(path, ["steps"]), object.remove(last, ["index"])), {"bracketed": true, "position": last.index + 1, "steps": array.slice(path.steps, 0, count(path.steps) - 1)}) if {
	not "position" in object.keys(path)
	not _s_itself(path)
	last := path.steps[count(path.steps) - 1]
	is_object(last)
	"index" in object.keys(last)
} else := path

_s_position_of("", _, _) := {}

_s_position_of(word, "", _) := {"position": word} if word != ""

_s_position_of(_, digits, "") := _s_counted("position", digits) if digits != ""

_s_position_of(_, digits, from_last) := object.union(_s_counted("position", digits), {"from_last": true}) if {
	digits != ""
	from_last != ""
}

_s_start_of("$params", steps) := {"start": "params", "steps": steps}

_s_start_of("$input", steps) := {"start": "input", "steps": steps}

_s_start_of(key, steps) := {"start": key, "steps": steps} if {
	startswith(key, "$")
	not key in {"$params", "$input"}
}

_s_start_of(key, steps) := {"steps": array.concat([key], steps), "bare_word": key} if {
	key in _s_words
}

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(key)], steps)} if {
	not key in _s_words
	not startswith(key, "$")
	not startswith(key, ".")
}

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(substring(key, 1, -1))], steps), "dot": true} if startswith(key, ".")

_s_key_of(text) := json.unmarshal(text) if startswith(text, `"`)

_s_key_of(text) := text if not startswith(text, `"`)

_s_steps_of(text, pat) := steps if {
	matches := regex.find_all_string_submatch_n(pat.steps, text, -1)
	concat("", [m[0] | some m in matches]) == text
	steps := [_s_step_of(m) | some m in matches]
	count(steps) == count(matches)
}

_s_step_of(m) := _s_key_of(m[1]) if m[1] != ""

_s_step_of(m) := {"named_by": _s_ref_of(m[2])} if m[2] != ""

_s_step_of(m) := {"named_by": _s_ref_of(m[3])} if m[3] != ""

_s_step_of(m) := _s_key_of(m[4]) if m[4] != ""

_s_step_of(m) := _s_counted("index", m[5]) if m[5] != ""

_s_counted(f, digits) := {f: to_number(digits)} if to_number(digits) <= 9007199254740991

_s_counted(f, digits) := {f: to_number(digits), "bad_index": digits} if to_number(digits) > 9007199254740991

_s_ref_of(text) := {"start": "params", "steps": [_s_key_of(substring(text, 8, -1))]} if startswith(text, "$params.")

_s_ref_of(text) := {"start": "input", "steps": [_s_key_of(substring(text, 7, -1))]} if startswith(text, "$input.")

_s_ref_of(text) := {"start": name, "steps": steps} if {
	m := regex.find_all_string_submatch_n(`^(\$[A-Za-z_][A-Za-z0-9_]*)(?:\.(.*))?$`, text, 1)[0]
	name := m[1]
	not name in {"$params", "$input"}
	steps := [_s_key_of(m[2]) | m[2] != ""]
}

_s_ref_of(text) := {"steps": [text]} if {
	not startswith(text, "$")
	not _s_bad_name(text)
}

_s_ref_of(text) := {"steps": [text], "bad_name": text} if _s_bad_name(text)

_s_phrase_of(text, pat) := object.union({"op": _s_op_of(pat.phrases[hit[0]], text, hit[1])}, _s_args_of(pat.phrases[hit[0]][3], hit[1], pat)) if {
	hits := [[i, m[1]] |
		some i, ph in pat.phrases
		m := regex.find_all_string_submatch_n(concat("", [`^(?:`, ph[1], `)(.*)$`]), text, 1)[0]
		regex.match(pat.kinds[ph[3]], m[1])
	]
	hit := hits[0]
}

_s_op_of(phrase, _, _) := phrase[0] if count(phrase) == 4

_s_op_of(phrase, text, rest) := phrase[0] if {
	count(phrase) == 5
	prefix := substring(text, 0, count(text) - count(rest))
	every choice in phrase[4] {
		not contains(prefix, choice[0])
	}
}

_s_op_of(phrase, text, rest) := choice[1] if {
	count(phrase) == 5
	some choice in phrase[4]
	contains(substring(text, 0, count(text) - count(rest)), choice[0])
}

_s_args_of("none", _, _) := {}

_s_args_of("type", text, _) := {"type": text}

_s_args_of("list", text, pat) := {"values": _s_values_of(text, pat)} if {
	regex.match(pat.values, text)
} else := {"path": _s_path_of(text, pat)}

_s_args_of("operand", text, pat) := _s_operand_of(text, pat)

_s_args_of("range", text, pat) := {"min": _s_number(m[1]), "max": _s_number(m[2])} if {
	m := regex.find_all_string_submatch_n(pat.range, text, 1)[0]
}

_s_args_of("operand_within", text, pat) := object.union(_s_operand_of(m[1], pat), _s_within_of(m[2])) if {
	m := regex.find_all_string_submatch_n(pat.operand_within, text, 1)[0]
}

_s_within_of("") := {}

_s_within_of(number) := {"within": _s_number(number)} if number != ""

_s_operand_of(text, pat) := {"value": _s_value_of(text)} if {
	regex.match(pat.value, text)
} else := {"join": array.concat([_s_piece_of(first, pat)], [_s_piece_of(m[1], pat) | some m in rest])} if {
	joined := regex.find_all_string_submatch_n(pat.join, text, 1)[0]
	first := joined[1]
	rest := regex.find_all_string_submatch_n(pat.join_rest, joined[2], -1)
	concat("", [m[0] | some m in rest]) == joined[2]
} else := {"terms": _s_terms_of(text, pat)}

_s_piece_of(text, pat) := {"value": _s_value_of(text)} if regex.match(pat.value, text)

_s_piece_of(text, pat) := {"terms": _s_terms_of(text, pat)} if not regex.match(pat.value, text)

_s_values_of(text, pat) := [_s_value_of(m[0]) | some m in regex.find_all_string_submatch_n(pat.each_value, text, -1)]

_s_value_of(text) := _s_number(text) if regex.match(`^-?[0-9]`, text)

_s_value_of(text) := json.unmarshal(text) if {
	not startswith(text, "'")
	not regex.match(`^-?[0-9]`, text)
}

_s_value_of(text) := concat("", [_s_sq_char(m[0]) | some m in regex.find_all_string_submatch_n(`\\'|\\\\|\\.|[^\\]`, substring(text, 1, count(text) - 2), -1)]) if startswith(text, "'")

_s_number(text) := 0 if {
	regex.match(`^-?[0.]+[eE]`, text)
} else := {"too_long": text} if {
	not _s_above_max(text)
	not _s_below_min(text)
	count(_s_significant(text)) > 15
} else := n if {
	not _s_above_max(text)
	not _s_below_min(text)
	n := to_number(text)
	_fits_a_float(n)
} else := {"out_of_range": text}

_s_magnitude(text) := (count(m[1]) + _exponent(m[3])) - (count(digits) - count(trim_left(digits, "0"))) if {
	m := regex.find_all_string_submatch_n(`^-?([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$`, text, 1)[0]
	digits := concat("", [m[1], m[2]])
}

_s_above_max(text) if _s_magnitude(text) > 309

_s_above_max(text) if {
	_s_magnitude(text) == 309
	digits := _s_significant(text)
	width := max({count(digits), 17})
	_s_padded(digits, width) > _s_padded("17976931348623157", width)
}

_s_below_min(text) if {
	_s_significant(text) != ""
	_s_magnitude(text) < -307
}

_s_below_min(text) if {
	_s_magnitude(text) == -307
	digits := _s_significant(text)
	width := max({count(digits), 17})
	_s_padded(digits, width) < _s_padded("22250738585072014", width)
}

_s_significant(text) := trim_right(trim_left(concat("", [m[1], m[2]]), "0"), "0") if {
	m := regex.find_all_string_submatch_n(`^-?([0-9]+)(?:\.([0-9]*))?`, text, 1)[0]
}

_s_padded(digits, width) := concat("", array.concat([digits], ["0" | some i in numbers.range(count(digits), width); i < width]))

_s_sq_char(`\'`) := "'"

_s_sq_char(`\\`) := `\`

_s_sq_char(c) := c if not c in {`\'`, `\\`}
