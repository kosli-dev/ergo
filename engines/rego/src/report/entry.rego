package ergo

import rego.v1

report(doc, policy, params) := _run(doc, c.policy, _from_compiled(c), params) if {
	c := _compiled(policy)
} else := _run(doc, c.policy, _stale_read(c), params) if {
	c := _stale_compiled(policy)
} else := _run(doc, policy, _read(policy), params)

_run(doc, policy, rd, params) := r if {
	raw := _section(policy, "requirements")
	reqs := rd.reqs
	unreadable := _unreadable_inputs(doc, params)
	written := object.union(_report_of(doc, reqs, object.get(rd.ahead, "requirements", {})), {"description": _reported_description(policy), "meta": _reported_meta(policy), "subjects": _listed_of(policy, rd)}) with data.ergo_reading as false with data.ergo_policy_problems as _policy_problems_of(policy, rd) with data.ergo_document as doc with data.ergo_params as params with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_unreadable as unreadable with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences with input as {"ergo/names": {}}
	used := _used_subjects(reqs, rd.subjects, rd.resolved)
	r := _with_policy_row(object.union(_reported(written, unreadable, [raw, used]), {"ergo": _spec, "engine": _engine}), policy)
}

_with_policy_row(report, _) := report if count(report.requirements) > 0

_with_policy_row(report, policy) := object.union(report, {
	"requirements": {"$policy": _policy_requirement},
	"results": array.concat(report.results, [_m_problems_row(_policy_row(policy))]),
}) if count(report.requirements) == 0

_policy_requirement := {
	"description": "",
	"meta": {},
	"require": "every",
	"subject": "$policy",
	"status": "not_met",
	"subjects": {"matching": 0, "total": 0},
	"checks": {"$well_formed": {
		"description": "The policy is written correctly",
		"expression": "count(problems) == 0",
		"meta": {},
	}},
	"causes": [{"cause": "value", "rows": 1}],
}

_policy_row(policy) := {
	"requirement": "$policy",
	"subject": {"type": "$policy", "id": "$policy"},
	"check": "$well_formed",
	"passed": false,
	"cause": "value",
	"inputs": [i | some i in sort(array.concat(_policy_problem_inputs(policy), _requirements_input(policy)))],
}

_requirements_input(policy) := [{"name": "policy", "value": ["not an object"], "locations": []}] if not is_object(policy)

_requirements_input(policy) := [{"name": "requirements", "value": [_requirements_problem(policy)], "locations": []}] if is_object(policy)

_requirements_problem(policy) := "missing" if not _has_requirements(policy)

_requirements_problem(policy) := "not an object" if {
	_has_requirements(policy)
	not is_object(policy.requirements)
}

_requirements_problem(policy) := "empty" if {
	_has_requirements(policy)
	is_object(policy.requirements)
	count(policy.requirements) == 0
}

default _has_requirements(_) := false

_has_requirements(policy) if {
	is_object(policy)
	policy.requirements != null
}

_used_subjects(reqs, subjects, resolved) := {name: subjects[name] |
	some req in reqs
	_names_a_subject(req)
	some name in resolved[req.subject].members
}

_reported_subject_name(req) := req.subject if {
	_names_a_subject(req)
	is_object(data.ergo_subjects)
	req.subject in object.keys(data.ergo_subjects)
} else := null

_listed_subject_graph := {name: array.concat(array.concat(_of_edges(def, data.ergo_subjects), [chains[name] | name in object.keys(chains)]), [follows[name] | name in object.keys(follows)]) |
	some name, def in data.ergo_subjects
	chains := object.get(data.ergo_subject_sentences, "listed", {})
	follows := object.get(data.ergo_subject_sentences, "follows", {})
}

_listed_subject_names(reqs) := graph.reachable(_listed_subject_graph, {req.subject |
	some req in reqs
	_reported_subject_name(req) != null
})

_reported_subjects(written, reqs) := {name: _reported_subject(name, written[name], flagged) | some name in names} if {
	is_object(written)
	names := _listed_subject_names(reqs)
	flagged := {name | some name in names; _from_check_problem(name)}
}

_reported_subjects(written, _) := {} if not is_object(written)

_reported_subject(name, def, flagged) := {
	"description": _reported_description(def),
	"from": _subject_from_text(name, def, flagged),
	"identified_by": _subject_id_text(name),
	"parts": _reported_parts(name),
}

_reported_parts(name) := {alias: {"from": _part_from_text(read.from), "identified_by": _part_id_text(read.identified_by)} |
	some alias, read in object.get(object.get(data.ergo_subject_sentences, "parts", {}), name, {})
	is_string(alias)
}

_part_from_text(read) := read.text if "text" in object.keys(read)

_part_from_text(read) := "<invalid from>" if not "text" in object.keys(read)

_part_id_text(null) := null

_part_id_text(read) := read.text if {
	read != null
	"text" in object.keys(read)
}

_part_id_text(read) := "<invalid identified_by>" if {
	read != null
	not "text" in object.keys(read)
}

_subject_from_text(name, null, _) := _path_name([_subject_step(name)])

_subject_step(name) := {"literal": name} if startswith(name, "$")

_subject_step(name) := name if not startswith(name, "$")

_parent_step(name) := {"parent": name}

_subject_from_text(_, def, _) := "<invalid from>" if {
	def != null
	not is_object(def)
}

_subject_from_text(name, def, flagged) := "<invalid from>" if {
	is_object(def)
	_subject_from_unreadable(name, def, flagged)
} else := _subject_text(name, def) if is_object(def)

default _subject_from_invalid(_, _) := false

_subject_from_invalid(name, _) if {
	some p in data.ergo_resolved[name].problems
	some f in ["from", "of"]
	p[0] == ["subjects", name, f]
}

_subject_from_invalid(name, flagged) if name in flagged

_from_check_problem(name) if {
	some p in _own_check_problems({"subject": name, "checks": {}})
	p[0] == _field_path_name(["subjects", name, "from"])
}

_subject_from_unreadable(name, _, flagged) if _subject_from_invalid(name, flagged)

_subject_from_unreadable(name, def, _) if not _subject_readable(name, def)

_subject_readable(name, def) if _subject_text(name, def)

_subject_text(name, def) := _s_from_line_text(_s_marked_line(name, _s_dotted_line(name, data.ergo_subject_sentences.lines[name]))) if {
	is_string(object.get(def, "from", null))
	object.keys(def) & {"of", "applies_to"} == set()
}

_subject_text(name, def) := _path_name([_subject_step(name)]) if {
	not "from" in object.keys(def)
	object.keys(def) & {"of", "applies_to"} == set()
}

_s_marked_line(name, line) := object.union(line, {"where": [_s_from_cond(c, set(), ancestors | object.keys(object.get(data.ergo_subject_sentences.parts, name, {}))) | some c in line.where]}) if {
	is_array(object.get(line, "where", null))
	wrap := {n: [p] | some n, p in object.get(data.ergo_subject_sentences, "chains", {})}
	ancestors := {m | some m in graph.reachable(object.union({n: object.get(wrap, n, []) | some n, _ in data.ergo_resolved}, {p: [] | some _, ps in wrap; some p in ps; not p in object.keys(wrap)}), [name]); m != name}
} else := line

_subject_id_text(name) := _top_id_text(tops[0]) if {
	narrowing := object.get(data.ergo_subject_sentences, "narrowing", {})
	tops := [m |
		some m in graph.reachable({n: object.get(narrowing, n, []) | some n, _ in data.ergo_resolved}, [name])
		m != name
		object.get(narrowing, m, []) == []
	]
	count(tops) == 1
} else := "<invalid identified_by>" if {
	object.get(object.get(data.ergo_subject_sentences, "narrowing", {}), name, []) != []
	"identified_by" in object.keys(data.ergo_resolved[name].def)
} else := _id_text(data.ergo_resolved[name].def.identified_by) if {
	"identified_by" in object.keys(data.ergo_resolved[name].def)
} else := null

_top_id_text(top) := _id_text(data.ergo_resolved[top].def.identified_by) if {
	"identified_by" in object.keys(data.ergo_resolved[top].def)
} else := null

_id_text(p) := _path_name(p) if {
	is_array(p)
	count(p) > 0
}

_id_text(p) := "<invalid identified_by>" if not is_array(p)

_section(policy, name) := object.get(policy, name, {}) if is_object(policy)

_section(policy, _) := null if not is_object(policy)

_policy_problem_inputs(policy) := [{"name": concat(" ", ["policy", f]), "value": sort(problems), "locations": []} |
	is_object(policy)
	some f in ["description", "ergo_spec", "meta"]
	problems := _policy_problems_at(f, policy)
	count(problems) > 0
]

_policy_problems_at("ergo_spec", policy) := _spec_problems(object.get(policy, "ergo_spec", null))

_policy_problems_at(f, policy) := _policy_field_problems(f, policy[f]) if f in {"description", "meta"}

_spec_problems(v) := {"missing"} if v == null

else := {"not a string"} if not is_string(v)

else := {concat("", ["not a version ", v])} if not _is_version(v)

else := {concat("", ["unsupported version ", v, ", expected ", _spec])} if v != _spec

else := set()

_policy_field_problems(f, v) := {_wrong_type_problems[f]} if not _has_type(f, v)

else := _meta_problems(v) if is_object(v)

else := set()

default _policy_problems := []

_policy_problems := data.ergo_policy_problems

_reported(written, unreadable, sections) := _plain_numbers(written) if {
	count(unreadable) == 0
	is_object(sections[0])
	count(_json_problems(sections)) == 0
} else := written

_unreadable_inputs(doc, params) := [{"name": name, "value": sort(problems), "locations": []} |
	some [name, problems] in [["$input", _json_problems(doc)], ["$params", (_json_problems(params) | _params_shape_problems(params))]]
	count(problems) > 0
]

_params_shape_problems(params) := set() if is_object(params)

else := set() if params == null

else := {"not an object"}

_report_of(doc, policy, compiled) := {
	"compliant": _policy_compliant(policy, evaluations),
	"requirements": {name: {
		"description": _reported_description(req),
		"meta": _reported_meta(req),
		"require": _require_of(req),
		"subject": _reported_subject_name(req),
		"status": status,
		"causes": _causes(status, evaluations[name], req),
		"subjects": {"total": evaluations[name].total, "matching": evaluations[name].matching},
		"checks": _ahead_check_defs(req, object.get(compiled, name, {})),
	} |
		some name, req in policy
		status := _status(req, evaluations[name])
	},
	"results": _results(policy, evaluations),
} if {
	evaluations := {name: _checked(doc, policy[name], name, object.get(compiled, name, {})) | some name in _names(policy)}
}

_checked(doc, req, name, parts) := _checked_with(doc, req, name, parts, _well_formed_row(req, name, parts))

_checked_with(_, _, _, _, row) := _written_wrong(row) if not row.passed

_checked_with(doc, req, name, parts, row) := _evaluated(doc, req, name, object.union(parts, {"well_formed": row})) if row.passed

_written_wrong(row) := {
	"well_formed": row,
	"min_subjects": [],
	"unique_ids": [],
	"unique_ancestor_ids": [],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
}
