package ergo

import rego.v1

_params_said_first(doc, req, name, ev) := object.union(ev, {
	"applies": [_params_first_row(r, _applies_to_of(req), nat.applies) | some r in ev.applies],
	"subject_rows": [[_params_first_row(r, _checks_of(req)[r.check], [x | some xs in nat.subject_rows; some x in xs]) | some r in rows] | some rows in ev.subject_rows],
}) if {
	_params_not_an_object
	nat := _evaluation_with(doc, req, name, _fixed(req)) with data.ergo_params as null
		with data.ergo_unreadable as _unreadable_but_params
} else := ev

_unreadable_but_params := [u | some u in data.ergo_unreadable; u.name != "$params"]

_params_first_row(row, check, nat) := object.union(row, {"message": _params_first_message(row, check, nat)}) if {
	row.passed == false
} else := row

_params_first_message(row, check, nat) := _params_joined([row.message], _params_said_rest(check, row.message), [n.message |
	some n in nat
	_same_row(n, row)
	n.passed == false
])

_same_row(a, b) if {
	a.subject == b.subject
	a.check == b.check
	object.get(a, "in", null) == object.get(b, "in", null)
}

_params_applies_message(evals, req, matched, entry) := {"message": _params_joined(said, extra, rest)} if {
	matched == false
	_params_not_an_object
	nat := _applies_evals(req, entry.subject, _fixed(req).filter_flaws) with data.ergo_params as null
		with data.ergo_unreadable as _unreadable_but_params
	failed := [n | some n in _applies_to_names(req); evals[n].passed == false]
	said := [evals[n].message | some n in failed]
	extra := [c | some n in failed; some c in _params_said_rest(_applies_to_of(req)[n], evals[n].message)]
	rest := [nat[n].message | some n in failed; nat[n].passed == false]
} else := _m_applies(evals, req, matched)

_params_joined(said, extra, rest) := concat("; ", _once(array.concat(
	array.concat([_params_problem(said)], [c | some m in rest; some c in _params_rest(m)]),
	extra,
)))

_params_said_rest(check, m) := [c |
	_m_reads_params(check)
	some chunk in split(m, "; ")
	not chunk in _params_fallbacks(check)
	c := concat(", and ", [p | some p in split(chunk, ", and "); not _params_problem_part(p)])
	c != ""
]

_params_fallbacks(check) := {"the check is false", concat("", [_text(object.get(check, "expression", "")), " is false"])}

_params_problem_part(part) if regex.match(`(?:^|: )(?:item [0-9]+ of )?\$params is .+, which isn't (?:an object|a list|a list of text|a list or an object)$`, part)

_params_problem(said) := ps[0] if {
	ps := _params_problems(said)
	ps != []
} else := _m_isnt("$params", data.ergo_params, "an object")

_params_problems(said) := [p |
	some m in said
	some chunk in split(m, "; ")
	some part in split(chunk, ", and ")
	some found in regex.find_all_string_submatch_n(`(?:^|: )((?:item [0-9]+ of )?\$params is .+, which isn't (?:an object|a list|a list of text|a list or an object))$`, part, 1)
	p := found[1]
]

_params_rest(m) := [c |
	some chunk in split(m, "; ")
	c := _params_rest_chunk(split(chunk, ", and "))
	c != ""
	not _params_cap_after_drop(m, c)
]

_params_cap_after_drop(m, c) if {
	regex.match(`^and [0-9]+ more$`, c)
	some chunk in split(m, "; ")
	some part in split(chunk, ", and ")
	_params_missing_part(part)
}

_params_rest_chunk(parts) := concat(", and ", keep) if {
	not _params_missing_part(parts[0])
	keep := [p | some p in parts; not _params_missing_part(p)]
} else := concat(", and ", array.concat([concat("", [_params_item_prefix(parts[0]), keep[0]])], array.slice(keep, 1, count(keep)))) if {
	keep := [p | some p in parts; not _params_missing_part(p)]
	keep != []
} else := ""

_params_item_prefix(part) := regex.find_all_string_submatch_n(`^(?:item [0-9]+ of [^:]+: )+`, part, 1)[0][0] if {
	regex.match(`^(?:item [0-9]+ of [^:]+: )+`, part)
} else := ""

_params_missing_part(part) if {
	endswith(part, " is missing")
	contains(trim_suffix(part, " is missing"), "$params")
}
