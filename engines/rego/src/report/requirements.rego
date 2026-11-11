package ergo

import rego.v1

_described(check) := {"expression": _expression_of(check)} if not is_object(check)

_chain_part(req) if data.ergo_subject_sentences.from_parts[req.subject]

_chain_part_name(req) := concat("", [_s_parent_key(data.ergo_subject_sentences.chains[req.subject]), ".", _s_key_text(alias), _tail_after_part(req, alias)]) if alias := data.ergo_subject_sentences.from_parts[req.subject]

_tail_after_part(req, alias) := concat("", [_step_name(i + 2, rest[i]) | some i in _names(rest)]) if {
	rest := array.slice(_from_of(req), count(data.ergo_subject_sentences.parts[data.ergo_subject_sentences.chains[req.subject]][alias].from.path), count(_from_of(req)))
}

_matching_count_name(req) := concat("", ["count(matching(", _from_text(req), "))"])

_from_text(req) := concat("", [_every_word(req), _with_from_dot(req, _from_name(_from_path(req)))]) if {
	_from_well_formed(req)
	_from_path(req) != []
	not _chained(req)
	not _chain_part(req)
}

_with_from_dot(req, name) := concat("", [at, _from_dot(substring(name, count(at), -1)), substring(name, count(at), -1)]) if {
	object.get(object.get(data.ergo_subject_sentences, "dotted", {}), req.subject, false) == true
	at := regex.find_all_string_submatch_n(`^(?:(?:item [1-9][0-9]*(?: from last)?|first|last) of )?`, name, 1)[0][0]
} else := name

_from_dot(rest) := "" if startswith(rest, ".")

else := "."

_every_word(req) := "every distinct " if _distinct_from(req)

else := "every " if _every_from(req)

else := ""

_from_text(req) := concat("", [_every_word(req), _chain_part_name(req)]) if {
	_from_well_formed(req)
	_from_path(req) != []
	_chain_part(req)
}

_from_text(req) := concat("", [_every_word(req), _path_name(array.concat([_parent_step(data.ergo_subject_sentences.chains[req.subject])], _from_path(req)))]) if {
	_from_well_formed(req)
	_chained(req)
	not _chain_part(req)
}

_from_text(req) := concat("", [_every_word(req), "$input"]) if {
	_from_well_formed(req)
	_from_path(req) == []
	not _chained(req)
}

_from_text(req) := "<invalid from>" if not _from_well_formed(req)

_from_name(p) := concat("", ["item ", _literal_text(p[count(p) - 1] + 1), " of ", _ref_steps_name(array.slice(p, 0, count(p) - 1))]) if {
	_ref_start(p)
	count(p) > 1
	_index_step(p[count(p) - 1])
}

_from_name(p) := _ref_steps_name(p) if {
	_ref_start(p)
	not _ends_with_index(p)
}

_ends_with_index(p) if {
	count(p) > 1
	_index_step(p[count(p) - 1])
}

_ref_steps_name(p) := concat("", array.concat(["$input"], [_ref_step_name(i + 1, p[i]) | some i in _names(p)]))

_ref_step_name(_, p) := concat("", [" named by ", _ref_name(p.ref)]) if _is_ref(p)

_ref_step_name(i, p) := _step_name(i, p) if not _is_ref(p)

_from_name(p) := _input_path_name(_from_steps(p)) if not _ref_start(p)

_ref_start(p) if _is_ref(p[0])

_from_steps(p) := array.concat([{"literal": p[0]}], array.slice(p, 1, count(p))) if _starts_with_dollar_key(p)

_from_steps(p) := p if not _starts_with_dollar_key(p)

_starts_with_dollar_key(p) if _first_dollar_key(0, p[0])

_min_subjects_def(req) := {"$min_subjects": _with_refs(
	{
		"description": _min_subjects_description(req),
		"expression": _min_subjects_expression(req),
	},
	{"from": _listed_from(req)},
)}

_min_subjects_expression(req) := concat("", [_matching_count_name(req), " >= ", _literal_text(_min_subjects_of(req))]) if not _only_reads_from(req)

_min_subjects_expression(req) := concat("", [_from_text(req), " can be read"]) if _only_reads_from(req)

_only_reads_from(req) if {
	_min_subjects_of(req) == 0
	not _keys_step(req)
}

_listed_from(req) := _from_of(req) if is_array(_from_of(req))

_listed_from(req) := [] if not is_array(_from_of(req))

_min_subjects_description(req) := concat("", ["The ", _subject_count_name(req), " is at least ", _literal_text(_min_subjects_of(req))]) if not _only_reads_from(req)

_min_subjects_description(req) := concat("", ["The ", _text(_subject_type_of(req)), " list can be read"]) if _only_reads_from(req)

_subject_count_name(req) := concat(" ", ["in-scope", _text(_subject_type_of(req)), "count"])

_unique_ids_def(req) := {"$unique_ids": _with_refs(
	{
		"description": concat("", ["Every ", _text(_subject_type_of(req)), " id is unique"]),
		"expression": concat("", ["count(repeated(ids(", _from_text(req), "))) == 0"]),
	},
	{"from": _listed_from(req), "id": _id_of(req)},
)}

_unique_ancestor_ids_def(req) := {"$unique_ancestor_ids": _with_refs(
	{
		"description": concat(" and ", [_unique_ancestor_description(i, a) | some i, a in levels]),
		"expression": concat(" and ", [concat("", ["count(repeated(ids(", _from_text({"subject": a, "checks": {}}), "))) == 0"]) | some a in levels]),
	},
	[{"from": _listed_from({"subject": a, "checks": {}}), "id": _id_of({"subject": a, "checks": {}})} | some a in levels],
)} if {
	levels := array.reverse(_ancestors_of(req))
	count(levels) > 0
} else := {}

_unique_ancestor_description(0, a) := concat("", ["Every ", _text(a), " id is unique"])

_unique_ancestor_description(i, a) := concat("", ["every ", _text(a), " id is unique"]) if i > 0

_repeated_ids_name(req) := concat(" ", ["repeated", _text(_subject_type_of(req)), "ids"])

_well_formed_def := {"$well_formed": {
	"description": "The requirement is written correctly",
	"expression": "count(problems) == 0",
}}

default _well_formed_with(_, _) := false

_well_formed_with(req, name_inputs) if {
	count(name_inputs) == 0
	_well_formed(req)
}

_name_problem_inputs(name) := [{"name": "requirement name", "value": ["not a string"], "locations": []}] if not is_string(name)

else := [] if not _bad_name(name)

else := [{"name": "requirement name", "value": sort(_written_name_problems(name)), "locations": []}]

_bad_name(name) if _dollar_name(name)

_bad_name(name) if _edge_name(name)

_bad_name(name) if _empty_name(name)

default _well_formed(_) := false

_well_formed(req) if {
	_typed(req)
	_subject_problems(req) == set()
	_req_meta_problems(req) == set()
	_unknown_req_fields(req) == []
	count(_checks_of(req)) > 0
	_require_of(req) in {"every", "some"}
	_from_well_formed(req)
	not _out_of_range([_from_of(req), _id_of(req), _min_subjects_of(req)])
	_wrapped_in_where(_id_of(req)) == set()
	_req_json_problems(req) == set()
	_check_problem_inputs(req) == []
	_policy_problems == []
}

_check_problem_inputs(req) := [{"name": name, "value": sort({p[1] | some p in problems; p[0] == name}), "locations": []} | some name in sort({p[0] | some p in problems})] if {
	problems := (_own_check_problems(req) | _reserved_name_problems(req)) | {p | some a in _ancestors_of(req); some p in _own_check_problems({"subject": a, "checks": {}})}
}

_own_check_problems(req) := {[_field_path_name(_problem_at(req, f, n, p[0])), p[1]] |
	some f in ["applies_to", "checks"]
	some n, check in _req_checks(req, f)
	here := _s_written_here(req, f, n)
	found := _check_problems(check, _from_names(req, here), here)
	some p in found
	not _own_name_problem(req, f, n, p[1])
}

_own_name_problem(req, "applies_to", n, problem) if {
	owner := _resolution_of(req).filter_owners[n]
	_dollar_name(owner)
	problem == concat("", ["unknown alias ", owner])
}

_ancestors_of(req) := _s_ancestors(req.subject, data.ergo_subject_sentences.chains) if _chained(req)

else := []

_req_checks(req, "applies_to") := _applies_to_of(req)

_req_checks(req, "checks") := _checks_of(req)

_problem_at(req, "applies_to", n, _) := ["subjects", _resolution_of(req).filter_owners[n], "from"]

_problem_at(_, "checks", n, at) := array.concat(["checks", n], at)

_from_names(req, here) := ((({n |
	_from_well_formed(req)
	n := _each_step(req).each_as
} | {a | _chained(req); here; some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)}) | {a |
	here
	_resolves(req)
	some a in data.ergo_resolved[req.subject].members
}) | {a |
	is_string(object.get(req, "subject", null))
	a := req.subject
}) | {a |
	is_string(object.get(req, "subject", null))
	some a, _ in object.get(object.get(data.ergo_subject_sentences, "parts", {}), req.subject, {})
}

_well_formed_inputs(req) := array.concat(
	array.concat(
		[{"name": "count(checks)", "value": count(_checks_of(req)), "locations": []}],
		_require_input(req),
	),
	array.concat(array.concat(array.concat(_not_an_object_inputs(req), _field_problem_inputs(req)), _check_problem_inputs(req)), _policy_problems),
)

_require_input(req) := [{"name": "require", "value": _require_of(req), "locations": []}] if not _has_problems(req, "require")

_require_input(req) := [{"name": "require", "value": sort({p[1] | some p in _req_problems(req); p[0] == "require"}), "locations": []}] if _has_problems(req, "require")

_applies_description(req) := concat("", ["The ", _text(_subject_type_of(req)), " is in scope"])

_applies_def(req) := {"$applies": _with_refs(
	{
		"description": _applies_description(req),
		"expression": concat(" and ", [_expression_of(_applies_to_of(req)[name]) | some name in _applies_to_names(req)]),
	},
	_applies_to_of(req),
)} if _size(_applies_to_of(req)) > 0

_applies_def(req) := {} if {
	_size(_applies_to_of(req)) == 0
}

_applies_to_names(req) := sort(object.keys(_applies_to_of(req))) if is_object(_applies_to_of(req))

_requirement_check_defs(req) := {name: object.union({"meta": {}}, def) | some name, def in _requirement_checks_written_or_added(req)}

_requirement_checks_written_or_added(req) := object.union(
	object.union(
		{name: def |
			some name, check in _checks_of(req)
			not _dollar_name(name)
			def := _check_def(check, _s_written_here(req, "checks", name))
		},
		object.union(object.union(_min_subjects_def(req), _unique_ids_def(req)), _unique_ancestor_ids_def(req)),
	),
	object.union(_applies_def(req), _well_formed_def),
)

_subject_row_groups(matching, req, req_name, flaws, prepared) := [rows |
	some entry in matching
	ref := _entry_ref(entry, req)
	rows := _subject_rows(entry, ref, req, req_name, flaws, prepared)
]

_anchored(row, at) := object.union(row, {"inputs": _tie_sorted(_anchored_all(row.inputs, at))}) if not "failed_items" in object.keys(row)

else := object.union(row, {"inputs": _tie_sorted(_anchored_all(row.inputs, at)), "failed_items": [_anchored_failed(f, at) | some f in row.failed_items]})

_anchored_failed(f, at) := object.union(_anchored_all([f], at)[0], object.union(_anchored_inner(f, at), _anchored_lines(f, at)))

_anchored_inner(f, at) := {"failed_items": _anchored_all(f.failed_items, at)} if "failed_items" in object.keys(f)

else := {}

_anchored_lines(f, at) := {"failed_assertions": [_anchored_line(l, at) | some l in f.failed_assertions]} if "failed_assertions" in object.keys(f)

else := {}

_anchored_line(l, at) := object.union(l, object.union(_anchored_line_inputs(l, at), _anchored_line_items(l, at)))

_anchored_line_inputs(l, at) := {"inputs": _anchored_inputs(l.inputs, at)} if "inputs" in object.keys(l)

else := {}

_anchored_line_items(l, at) := {"items": [object.union(x, {"inputs": _anchored_inputs(x.inputs, at)}) | some x in l.items]} if "items" in object.keys(l)

else := {}

_tie_sorted(xs) := xs if count(xs) < 2

else := xs if count({x.name | some x in xs}) == count(xs)

else := [xs[t[2]] | some t in sort([[_first_read(xs, xs[i]), xs[i].locations, i] | some i, _ in xs])]

_first_read(xs, x) := min({j | some j, y in xs; y.name == x.name; y.value == x.value; object.get(y, "part", null) == object.get(x, "part", null)})

_anchored_inputs(xs, at) := _once(_tie_sorted(_anchored_all(xs, at)))

_anchored_all(xs, at) := [object.union(x, {"locations": [replace(l, "~~", at) | some l in x.locations]}) | some x in xs] if is_string(at)

else := [object.union(x, {"locations": [m | some l in x.locations; some m in _anchored_copies(l, at)]}) | some x in xs]

_anchored_copies(l, ats) := [replace(l, "~~", a) | some a in ats] if contains(l, "~~")

else := [l]

_entry_anchor(entry) := entry.at if object.get(entry, "ats", null) == null

else := entry.ats

_subject_rows(entry, ref, req, req_name, flaws, prepared) := [row |
	anchor := _entry_anchor(entry)
	some check_name in _names(prepared)
	row := object.union(
		{
			"requirement": req_name,
			"subject": ref,
			"check": check_name,
		},
		_anchored(_outcome(req, prepared[check_name], flaws[check_name], entry.subject), anchor),
	)
]

_well_formed_row(req, name, parts) := v if {
	v := parts.well_formed
} else := _well_formed_row_of(req, name)

_well_formed_row_of(req, req_name) := row if {
	name_inputs := _name_problem_inputs(req_name)
	passed := _well_formed_with(req, name_inputs)
	row := {
		"requirement": req_name,
		"subject": _req_subject_ref(req),
		"check": "$well_formed",
		"inputs": array.concat(name_inputs, _well_formed_inputs(req)),
		"passed": passed,
		"cause": _verdict_cause(passed),
	}
}

_min_subjects_row(doc, req, req_name, matching, at) := _m_from_row(doc, req, object.union(
	{
		"requirement": req_name,
		"subject": _req_subject_ref(req),
		"check": "$min_subjects",
		"inputs": array.concat([{"name": _subject_count_name(req), "value": matching, "locations": at}], data.ergo_unreadable),
		"passed": _enough_subjects(doc, req, matching),
		"cause": _min_subjects_cause(doc, req, matching),
	},
	_every_failed_items(doc, req),
))

_m_from_row(doc, req, row) := object.union(row, _m_from_message(doc, req, row.passed, row.cause))

_every_failed_items(doc, req) := {"failed_items": _fl_items(req, _fl_failed(doc, req))} if {
	_every_from(req)
	not _fl_parent_unread(doc, req)
	_from_well_formed(req)
	not _from_unreadable(req)
} else := {"failed_items": []} if _every_from(req)

else := {"failed_items": _fl_items(req, _fl_plain_typed(doc, req).items)} if _fl_plain_typed(doc, req)

else := {}

default _enough_subjects(_, _, _) := false

_enough_subjects(doc, req, matching) if {
	not _from_unreadable(req)
	not _target_cause(doc, req)
	is_number(_min_subjects_of(req))
	matching >= _min_subjects_of(req)
}

_min_subjects_cause(doc, req, matching) := _verdict_cause(_enough_subjects(doc, req, matching)) if {
	not _from_unreadable(req)
	not _target_cause(doc, req)
}

_min_subjects_cause(doc, req, _) := _target_cause(doc, req)

_min_subjects_cause(_, req, _) := _from_cause(req) if {
	_from_well_formed(req)
	_from_unreadable(req)
}

_unique_ids_row(raw, refs, req, req_name) := {
	"requirement": req_name,
	"subject": _req_subject_ref(req),
	"check": "$unique_ids",
	"inputs": [{"name": _repeated_ids_name(req), "value": repeated, "locations": [l |
		some id in repeated
		some i, entry in raw
		refs[i].id == id
		some l in _copied_id_locations(entry, req)
	]}],
	"passed": count(repeated) == 0,
	"cause": _verdict_cause(count(repeated) == 0),
} if {
	repeated := _repeated_ids(refs)
}

_copied_id_locations(entry, req) := _id_locations(entry, req) if object.get(entry, "ats", null) == null

else := [l | some a in entry.ats; some l in _id_locations(object.union(entry, {"at": a}), req)]

_id_locations(entry, req) := ls if ls := _locations_of(entry.subject, _id_of(req)) with input as _id_input(entry, req)

_id_input(entry, req) := scope if {
	_scoped(req)
	scope := _scope_of(req, entry.subject) with input as _row_input(entry.at)
} else := _row_input(entry.at)

_repeated_ids(refs) := [pair[1] | some pair in sort({[_literal_text(id), id] | some id in _repeats(sort([ref.id | some ref in refs]))})]

_repeats(sorted) := {x |
	some i, x in sorted
	i > 0
	x == sorted[i - 1]
}

_applies_rows(raw, refs, evals, req, req_name) := [row |
	some i, entry in raw
	row := _applies_row(refs[i], entry, evals[i], req, req_name)
] if {
	_size(_applies_to_of(req)) > 0
}

_applies_rows(_, _, _, req, _) := [] if {
	_size(_applies_to_of(req)) == 0
}

_applies_row(ref, entry, evals, req, req_name) := object.union(
	{
		"requirement": req_name,
		"subject": ref,
		"check": "$applies",
		"inputs": _tie_sorted(_anchored_all(_applies_inputs(evals, req), _entry_anchor(entry))),
		"passed": matched,
		"cause": _applies_cause(evals, matched),
	},
	object.union(_applies_failures(evals, req, _entry_anchor(entry)), _m_applies(evals, req, matched)),
) if {
	matched := _subject_matches(evals, req)
}

_applies_failures(evals, req, at) := {"failed_items": [_anchored_failed(f, at) | some f in e.failed_items]} if {
	count(evals) == 1
	some e in evals
	"failed_items" in object.keys(e)
} else := {"failed_assertions": [{"assertion": _expression_of(_applies_to_of(req)[name]), "cause": evals[name].assertion_cause} |
	some name in _applies_to_names(req)
	evals[name].assertion_cause != "satisfied"
]} if {
	count(evals) > 1
} else := {}

_applies_inputs(evals, req) := _merged_inputs([inp |
	some name in _applies_to_names(req)
	some inp in evals[name].inputs
]) if count(evals) != 1

_applies_inputs(evals, _) := [inputs[t[4]] | some t in sort([[i.name, i.value, object.get(i, "part", null), i.locations, idx] | some idx, i in inputs])] if {
	count(evals) == 1
	some e in evals
	inputs := e.inputs
}
