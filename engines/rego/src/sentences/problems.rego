package ergo

import rego.v1

_s_sentence_problems(parsed) := _s_base_problems(parsed) | _s_join_problems(parsed)

_s_join_problems(parsed) := set() if not _s_joins(parsed)

_s_join_problems(parsed) := _s_join_flaws([node |
	_s_joins(parsed)
	some node in _s_nodes(parsed)
	is_object(node)
	_s_has_join(node)
])

_s_joins(x) if contains(json.marshal(x), `"join":`)

_s_has_join(node) if "join" in object.keys(node)

_s_has_join(node) if {
	"terms" in object.keys(node)
	"phrase" in object.keys(node)
	"join" in object.keys(node.phrase)
}

_s_join_flaws(nodes) := ((({`"followed by" takes text` |
	some node in nodes
	some piece in object.get(node, "join", [])
	"value" in object.keys(piece)
	not is_string(piece.value)
} | {`"followed by" can't take a count of, a sum of or a plus` |
	some node in nodes
	some piece in object.get(node, "join", [])
	"terms" in object.keys(piece)
	not _s_one_path(piece.terms)
}) | {concat("", [`"`, node.op, `" can't take followed by`]) |
	some node in nodes
	"join" in object.keys(node)
	node.op in object.keys(_s_takes)
}) | {`"within" can't take followed by` |
	some node in nodes
	"join" in object.keys(node)
	"within" in object.keys(node)
}) | {`"followed by" can't follow a count of, a sum of or a plus` |
	some node in nodes
	"terms" in object.keys(node)
	"join" in object.keys(object.get(node, "phrase", {}))
}

_s_text_names(text) := {concat("", ["unknown name ", m[1]]) |
	some m in regex.find_all_string_submatch_n(concat("", [_s_patterns.strings, `|(?:^|[ ,\[])(\$[A-Za-z_]\w*)`]), text, -1)
	not m[1] in {"", "$params", "$input"}
} if contains(text, "$")

else := set()

_s_base_problems(parsed) := ((((((((((((((((({concat("", [node.bare_word, " is a word of the grammar: write .", node.bare_word]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bare_word" in object.keys(node)
} | {concat("", [node.bad_name, " can't be an alias"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bad_name" in object.keys(node)
}) | {concat("", [node.as, " can't be an alias"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	_s_bad_name(object.get(node, "as", ""))
}) | {concat("", [name, " is given twice"]) |
	some i, item in object.get(parsed, "items", [])
	name := item.as
	parsed.items[j].as == name
	j < i
}) | _s_pick_problems(parsed)) | {"if any can't go with some" |
	some node in _s_nodes(parsed)
	is_object(node)
	"some" in object.keys(node)
	object.get(node, "if_any", false) == true
}) | {concat("", ["a ", _s_place_word(node), " goes after every, some, count of or sum of"]) |
	some node in _s_nodes(parsed)
	node != parsed
	is_object(node)
	"where" in object.keys(node)
	object.keys(node) & {"every", "some", "pick"} == set()
	not _s_derived_term(object.get(node, "terms", [null])[count(object.get(node, "terms", [null])) - 1])
}) | {concat("", [node.phrase.op, " can't follow a count of, a sum of or a plus"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"terms" in object.keys(node)
	not node.phrase.op in {"is", "is not", "is at least", "is at most", "is more than", "is less than", "is between", "is not between"}
}) | {"a number can't start a sentence" |
	some node in _s_nodes(parsed)
	is_object(node)
	node.terms == [node.terms[0]]
	is_number(node.terms[0])
}) | {"min above max" |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op in {"is between", "is not between"}
	is_number(node.min)
	is_number(node.max)
	node.min > node.max
}) | {concat("", [node.bad_index, " can't be a list position"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bad_index" in object.keys(node)
}) | {concat("", ["number out of range: ", node.out_of_range]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"out_of_range" in object.keys(node)
}) | {concat("", ["invalid pattern ", _json_text(v)]) |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op in {"matches", "does not match"}
	some v in object.get(node, "values", [])
	not is_object(v)
	not _s_valid_pattern(v)
}) | {`"is not null" is written "exists"` |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op == "is not"
	"value" in object.keys(node)
	node.value == null
}) | {concat("", [`"`, node.op, `" takes text`]) |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op in _s_text_ops
	"value" in object.keys(node)
	not is_string(node.value)
}) | {concat("", [`"`, node.op, `" takes `, _s_takes[node.op]]) |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op in object.keys(_s_takes)
	"value" in object.keys(node)
	not _s_takes_value(node.op, node.value)
}) | {concat("", [`"`, node.phrase.op, `" after every or some would check each item of the last list, not the list: put the walk on a for line`]) |
	some node in _s_nodes(parsed)
	is_object(node)
	object.keys(node) & {"every", "some"} != set()
	node.phrase.op in {"contains", "does not contain", "contains all of", "contains none of", "contains some of", "does not contain all of"}
}) | {`"within" only compares numbers` |
	some node in _s_nodes(parsed)
	is_object(node)
	"within" in object.keys(node)
	"value" in object.keys(node)
	not is_number(node.value)
}) | {`"within" needs a number of 0 or more` |
	some node in _s_nodes(parsed)
	is_object(node)
	is_number(node.within)
	node.within < 0
}

_s_valid_pattern(v) if {
	is_string(v)
	regex.is_valid(v)
}

_s_derived_term(t) if {
	is_object(t)
	object.keys(t) & {"count", "sum"} != set()
}

_s_bad_name(name) if name in _s_words

_s_bad_name(name) if name in {"params", "input"}

_s_nodes(x) := {y | walk(x, [_, y])}

_s_text_ops := {"starts with", "ends with", "does not start with", "does not end with", "is alphabetically before", "is alphabetically after", "is alphabetically on or before", "is alphabetically on or after"}

_s_self_ops := {"is", "is not", "is at least", "is at most", "is more than", "is less than", "is before", "is after", "is on or after", "is on or before"} | _s_text_ops

_s_self_term(node) := node.phrase.terms[0] if {
	node.phrase.op in _s_self_ops
	count(node.phrase.terms) == 1
	is_object(node.phrase.terms[0])
	"steps" in object.keys(node.phrase.terms[0])
}

_s_self_compared(node) if {
	is_object(node.path)
	object.remove(node.path, ["dot", "own"]) == object.remove(_s_self_term(node), ["dot", "own"])
}

_s_self_problems(assertions) := ({concat("", [_s_path_text(a.path, "left"), " is compared with itself"]) |
	some a in assertions
	_s_self_compared(a)
} | _s_whose_self_problems(assertions)) | _s_sum_whose_problems(assertions)

_s_sum_whose_problems(assertions) := {concat("", ["whose ", names[0], ": sum of adds up numbers, which have no fields: to keep numbers by their value, write that instead of whose"]) |
	some a in assertions
	_s_sums(a)
	names := [n | some c in object.get(a, "where", []); not _s_that(c); some n in _s_focus_names(c)]
	count(names) > 0
} | {concat("", ["that ", names[0], ": sum of adds up numbers, which have no fields, so ", names[0], " can't be read from one: to read the subject's ", names[0], ", write ", _s_subject_mark, ".", names[0]]) |
	some a in assertions
	_s_sums(a)
	names := [n | some c in object.get(a, "where", []); _s_that(c); some n in _s_focus_names(c)]
	count(names) > 0
}

_s_sums(a) if {
	terms := object.get(a, "terms", [])
	count(terms) > 0
	is_object(terms[count(terms) - 1])
	"sum" in object.keys(terms[count(terms) - 1])
}

_s_focus_names(c) := array.concat(
	array.concat(
		[_s_unmarked_text(c.path) | is_object(object.get(c, "path", null)); not _s_that(c); not "start" in object.keys(c.path)],
		[_s_unmarked_text(t[k]) | some t in object.get(c, "terms", []); is_object(t); some k in ["count", "sum", "elapsed_from", "elapsed_to"]; is_object(object.get(t, k, null)); not "start" in object.keys(t[k])],
	),
	array.concat(
		[_s_unmarked_text(p) | some p in _s_cond_right_paths(c.phrase); _s_focus_read(p)],
		[_s_unmarked_text(s.named_by) |
			some p in _s_cond_paths(c)
			some s in object.get(p, "steps", [])
			is_object(s)
			is_object(object.get(s, "named_by", null))
			_s_focus_read(s.named_by)
			not _s_named_key(s.named_by, object.get(c, "names", set()))
		],
	),
)

_s_named_key(key, names) if {
	is_array(object.get(key, "steps", null))
	key.steps[0] in names
	object.get(key, "dot", false) != true
}

_s_cond_paths(c) := array.concat(
	array.concat(
		[c.path | is_object(object.get(c, "path", null))],
		[t[k] | some t in object.get(c, "terms", []); is_object(t); some k in ["count", "sum", "elapsed_from", "elapsed_to"]; is_object(object.get(t, k, null))],
	),
	_s_cond_right_paths(object.get(c, "phrase", {})),
)

_s_cond_right_paths(ph) := array.concat(array.concat([t | some t in object.get(ph, "terms", []); is_object(t); "steps" in object.keys(t)], [t[k] | some t in object.get(ph, "terms", []); is_object(t); some k in ["count", "sum", "elapsed_from", "elapsed_to"]; is_object(object.get(t, k, null))]), [ph.path | is_object(object.get(ph, "path", null))])

_s_focus_read(p) if {
	not "start" in object.keys(p)
	not _s_itself(p)
	object.get(p, "alias", false) != true
	object.get(p, "part", false) != true
}

_s_unmarked_text(p) := _s_path_text(object.remove(p, ["dot", "field", "own", "part", "alias"]), "left")

_s_whose_self_problems(holders) := {concat("", [_s_unmarked_text(w.path), " is compared with itself, because in a whose it's read from the item", _s_whose_advice(w)]) |
	some h in holders
	some w in object.get(h, "where", [])
	is_object(w)
	_s_self_compared(w)
}

_s_whose_advice(w) := concat("", [": to read the subject's ", _s_unmarked_text(w.path), ", write ", _s_subject_mark, ".", _s_unmarked_text(w.path)])

_s_subject_mark := "\u0001"

_s_marked(p, names, own) := object.union(p, {"field": true, "own": own}) if {
	_s_markable(p, names.all)
	_s_own_field(p, names.all, own)
} else := object.union(p, {"alias": true}) if {
	_s_markable(p, names.for)
	object.get(p, "dot", false) != true
} else := object.union(p, {"part": true}) if {
	own == false
	_s_markable(p, names.all)
	object.get(p, "dot", false) != true
} else := p

_s_markable(p, keys) if {
	is_object(p)
	not _s_itself(p)
	is_array(p.steps)
	not "start" in object.keys(p)
	p.steps[0] in keys
}

_s_own_field(p, aliases, true) if p.steps[0] in aliases

_s_own_field(p, _, _) if object.get(p, "dot", false) == true

_s_marked_term(t, names) := object.union(t, {f: _s_marked(t[f], names, false) |
	some f in ["count", "sum", "elapsed_from", "elapsed_to"]
	f in object.keys(t)
}) if {
	is_object(t)
	not "steps" in object.keys(t)
} else := _s_marked(t, names, false)

_s_marked_phrase(ph, names) := object.union(ph, {"terms": [_s_marked_term(t, names) | some t in ph.terms]}) if is_array(object.get(ph, "terms", null))

else := object.union(ph, {"path": _s_marked(ph.path, names, false)}) if is_object(object.get(ph, "path", null))

else := ph

_s_marked_cond(c, names) := object.union(c, {"path": _s_marked(c.path, names, true), "phrase": _s_marked_phrase(c.phrase, names), "names": names.all}) if "path" in object.keys(c)

else := object.union(c, {"terms": [_s_own_term(t, names) | some t in c.terms], "phrase": _s_marked_phrase(c.phrase, names), "names": names.all})

_s_own_term(t, names) := object.union(t, {f: _s_marked(t[f], names, true) |
	some f in ["count", "sum", "elapsed_from", "elapsed_to"]
	f in object.keys(t)
})

_s_aliased(a, names) := object.union(object.union(a, {k: _s_marked(a[k], names, false) | some k in ["path", "every", "some"]; k in object.keys(a)}), object.union(
	{"phrase": _s_marked_phrase(a.phrase, names)},
	object.union(
		{"terms": [_s_marked_term(t, names) | some t in a.terms] | is_array(object.get(a, "terms", null))},
		{"where": [_s_marked_cond(c, names) | some c in a.where] | is_array(object.get(a, "where", null))},
	),
))

_s_names(aliases, parts) := {"for": aliases, "all": (aliases | parts)}

_s_aliased_item(item, names) := object.union(object.union(item, {q: _s_marked(item[q], names, false) | some q in ["every", "some", "pick"]; q in object.keys(item)}), {"where": [_s_marked_cond(c, names) | some c in item.where] | is_array(object.get(item, "where", null))})

_s_problems(text, pat) := [concat("", ["unclosed quote at column ", _json_text(count(closed) + 1)])] if {
	closed := regex.find_all_string_submatch_n(pat.quotes, text, 1)[0][0]
	count(closed) < count(text)
} else := invalid if {
	tokens := [m[0] | some m in regex.find_all_string_submatch_n(concat("", [pat.strings, `|[^"']+`]), text, -1)]
	invalid := [concat("", ["invalid string at column ", _json_text(count(concat("", array.slice(tokens, 0, i))) + 1)]) |
		some i, token in tokens
		regex.match(`^["']`, token)
		not regex.match(pat.string, token)
	]
	count(invalid) > 0
} else := sort(problems) if {
	problems := _s_sentence_problems(_s_parsed_anyway(text, pat)) | _s_text_names(text)
	count(problems) > 0
} else := ["two quantifiers in one sentence: put them on a for line"] if {
	regex.match(`^(?:every|some) +\S+ +(?:every|some) `, text)
} else := [`"within" needs a number after it`] if {
	regex.match(` within$`, text)
} else := ["doesn't parse"] if {
	regex.match(`(?: named +by +|\[)\$(?:params|input)(?:[^.A-Za-z0-9_]|$)`, text)
} else := [concat("", ["nothing after the path at column ", _json_text(count(text) + 1), `: expected a phrase, like "is" or "exists"`])] if {
	regex.match(pat.quantified_path, text)
} else := [_s_bare_and] if {
	_s_bare_and_in(text, pat)
} else := [_s_distinct_misplaced] if {
	_s_distinct_misplaced_in(text, pat)
} else := ["doesn't parse"]

_s_distinct_misplaced := "distinct goes after every, some, count of or sum of"

_s_distinct_misplaced_in(text, pat) if {
	tokens := [m[0] | some m in regex.find_all_string_submatch_n(concat("", [`(?:`, pat.strings, `|[^ ])+`]), trim_space(text), -1)]
	some i, word in tokens
	word == "distinct"
	i > 0
	i + 1 < count(tokens)
	not _s_distinct_after(array.slice(tokens, max([0, i - 2]), i))
}

_s_distinct_after(before) if before[count(before) - 1] in {"every", "some"}

_s_distinct_after(before) if {
	count(before) == 2
	before[0] in {"count", "sum"}
	before[1] == "of"
}

_s_bare_and := "a condition after and starts with whose or that"

_s_bare_and_in(text, pat) if {
	tokens := [m[0] | some m in regex.find_all_string_submatch_n(concat("", [`(?:`, pat.strings, `|[^ ])+`]), trim_space(text), -1)]
	some i, word in tokens
	word in {"whose", "that"}
	some j, token in tokens
	j > i
	token == "and"
	before := array.slice(tokens, 0, j)
	count([1 | some t in before; t == "between"]) <= count([1 | some t in before; t == "and"])
	next := tokens[j + 1]
	not next in {"whose", "that", "every", "some", "count", "sum", "first", "last", "item"}
	not regex.match(`^["'$0-9-]`, next)
}

_s_parsed_anyway(text, pat) := {"assertions": assertions} if {
	pieces := _s_pieces(pat.assertions, text)
	assertions := [_s_assertion_of(a, pat) | some a in pieces]
	count(assertions) == count(pieces)
	count(pieces) > 0
} else := {"items": items} if {
	pieces := _s_pieces(pat.for_items, text)
	items := [_s_for_item_of(a, pat) | some a in pieces]
	count(items) == count(pieces)
	count(pieces) in {1, 2}
} else := _s_from_plain(text, pat)
