package ergo

import rego.v1

_expression_of(check) := check.expression if _written_expression(check)

_written_expression(check) if is_string(check.expression)

_expression_of(check) := "<invalid check>" if not is_object(check)

_one_of(parts) := "one of: <empty options>" if count(parts) == 0

_one_of(parts) := concat("", ["one of: ", concat(" | ", [p[1] | some p in sort(parts)])]) if count(parts) > 0

_option_text(nm, group, texts) := concat("", [_text(nm), "(", _option_body(group, texts), ")"])

_option_body(group, _) := "<invalid option>" if not is_array(group)

_option_body([], _) := "<empty option>"

_option_body(group, texts) := concat(" and ", texts) if {
	is_array(group)
	count(group) > 0
}

_check_inputs(subj, check) := [_echoed(subj, check.inputs[k]) | some k in _names(check.inputs)] if {
	check.inputs
}

_echoed(subj, spec) := _path_input(subj, spec) if is_array(spec)

_check_inputs(subj, check) := [
	_path_input(subj, check.left),
	_path_input(subj, check.right),
] if {
	not check.inputs
	check.op == "compare_time"
	is_array(check.left)
	is_array(check.right)
}

_check_inputs(subj, check) := [_path_input(subj, check.left)] if {
	not check.inputs
	check.op == "compare_time"
	is_array(check.left)
	_basic_form(check.right) == "literal"
}

_check_inputs(subj, check) := array.concat(_side_inputs(subj, object.get(check, "left", null)), _side_inputs(subj, object.get(check, "right", null))) if {
	not check.inputs
	check.op == "compare"
	every f in ["left", "right"] {
		_side_form(object.get(check, f, null))
	}
	not _derived_once(check)
	not _right_walks(check, subj)
}

_check_inputs(subj, check) := array.concat(_side_inputs(subj, object.get(check, "left", null)), [{"name": w.name, "value": w.value, "locations": w.locations}]) if {
	not check.inputs
	check.op == "compare"
	every f in ["left", "right"] {
		_side_form(object.get(check, f, null))
	}
	not _derived_once(check)
	_right_walks(check, subj)
	w := _rwalk(subj, check.right)
}

_check_inputs(subj, check) := _derived_eval(check, subj).inputs if {
	_derived_once(check)
}

_check_inputs(subj, check) := array.concat([_path_input(subj, check.path)], _right_ref_inputs(check)) if {
	not check.inputs
	not _two_sided(check)
	is_array(check.path)
}

_right_ref_ops := {"in", "not_in", "includes", "excludes", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}

_right_ref_inputs(check) := _ref_inputs(object.remove(check, ["path"])) if check.op in _right_ref_ops

_right_ref_inputs(check) := [] if not check.op in _right_ref_ops

_leaf_paths(leaf) := [side | some side in [leaf.left, leaf.right]; is_array(side)] if _two_sided(leaf)

_leaf_paths(leaf) := [leaf.path] if {
	not _two_sided(leaf)
	leaf.path
}

_row_inputs(subj, check) := _with_key_fields(subj, check, _check_inputs(subj, check))

_with_key_fields(subj, check, inputs) := inputs if count(_key_fields(check)) == 0

else := _once(array.concat(
	[x |
		some entry in inputs
		some x in array.concat([entry], [_path_input(subj, [f]) | some p in _field_paths(check); _names_path(entry, p); some f in _own_key_fields(p)])
	],
	[_path_input(subj, [f]) | some f in _key_fields(check)],
))

_names_path(entry, path) if entry.name == _input_name(path)

_names_path(entry, path) if entry.name == concat("", [_input_name(path), "[]"])

_field_paths(check) := [p |
	is_object(check)
	some p in array.concat([object.get(check, "path", [])], array.concat(_side_paths(object.get(check, "left", null)), _side_paths(object.get(check, "right", null))))
	is_array(p)
	count(_own_key_fields(p)) > 0
]

_own_key_fields(path) := [_fk(seg) |
	some seg in path
	_field_step(seg)
]

_key_fields(check) := sort({_fk(seg) |
	is_object(check)
	some p in array.concat([object.get(check, "path", [])], array.concat(_side_paths(object.get(check, "left", null)), _side_paths(object.get(check, "right", null))))
	is_array(p)
	some seg in p
	_field_step(seg)
})

_check_def(check, here) := _with_refs({"description": _reported_description(check), "meta": _reported_meta(check), "expression": check.expression}, check) if _s_read(check, here)

_check_def(check, here) := _with_refs(object.union(object.remove(_described(check), {"description", "meta"}), {"description": _reported_description(check), "meta": _reported_meta(check)}), check) if not _s_read(check, here)

_with_refs(def, checked) := _with_listed(def, checked, _listed_refs(checked))

_with_listed(def, checked, refs) := object.union(def, {"$refs_of": checked}) if {
	data.ergo_reading == true
	count(refs) > 0
} else := object.union(def, {"$refs": _ref_entries(refs)}) if count(refs) > 0

_with_listed(def, _, refs) := def if count(refs) == 0

_evaluation(doc, req, name, parts) := object.union({"well_formed": _well_formed_row(req, name, parts)}, _evaluation_with(doc, req, name, _fixed(req)))

_fixed(req) := {
	"filter_flaws": {n: _flaw(check, _from_names(req, here)) |
		some n, check in _applies_to_of(req)
		here := _s_written_here(req, "applies_to", n)
	},
	"check_flaws": {n: _flaw(check, _from_names(req, here)) |
		some n, check in _checks_of(req)
		here := _s_written_here(req, "checks", n)
	},
	"prepared": {n: _with_ref_answer(_as_plain(req, check)) | some n, check in _checks_of(req)},
}

_as_plain(req, check) := object.union(check, {"$plain": true, "checks": [object.union(c, {"$plain": true}) | some c in check.checks]}) if {
	_plain_shaped(req, check)
	is_array(check.checks)
} else := object.union(check, {"$plain": true}) if {
	_plain_shaped(req, check)
} else := check

_plain_shaped(req, check) if {
	is_array(data.ergo_document)
	is_object(check)
	not _chained(req)
	not _reads_by_item(check)
	every c in object.get(check, "checks", []) {
		is_object(c)
		not _reads_by_item(c)
	}
}

_reads_by_item(c) if _walks(c)

_reads_by_item(c) if c.op == "for"

_reads_by_item(c) if {
	walk(c, [_, x])
	is_object(x)
	some k in ["whose", "count_of", "sum_of"]
	k in object.keys(x)
}

_evaluation_with(doc, written, name, fixed) := {
	"min_subjects": [_min_subjects_row(doc, req, name, count(matching), _matching_ats(matching, req))],
	"unique_ids": [_unique_ids_row(raw, refs, req, name)],
	"applies": applies,
	"subject_rows": groups,
	"total": count(raw),
	"matching": count(matching),
	"scope_readable": _scope_readable(raw, applies, req),
	"rows_complete": _rows_complete(groups, matching, req),
} if {
	req := _with_fixed(written)
	raw := _raw_entries(doc, req)
	longs := _long_subjects(raw)
	refs := {i: _entry_ref_alone(entry, req, i in longs) | some i, entry in raw}
	evals := {i: _applies_evals_alone(req, entry, fixed.filter_flaws, i in longs) | some i, entry in raw}
	matches := {i: _subject_matches(evals[i], req) | some i, _ in raw}
	applies := _applies_rows(raw, refs, evals, req, name)
	matching := [raw[i] | some i, _ in raw; matches[i]]
	groups := [rows |
		some i, entry in raw
		matches[i]
		rows := _subject_rows_alone(entry, refs[i], req, name, fixed, i in longs)
	]
}

_long_subjects(raw) := set() if count({entry.subject | some entry in raw}) == count(raw)

else := set() if [s | some s in {entry.subject | some entry in raw}; _has_number(s)] == []

else := {i | some i, entry in raw; _has_number(entry.subject); _long_text(json.marshal(entry.subject))}

_entry_ref_alone(entry, req, false) := _entry_ref(entry, req)

_entry_ref_alone(entry, req, true) := r if r := _entry_ref(entry, req) with data.ergo_item as entry

_applies_evals_alone(req, entry, flaws, false) := _applies_evals(req, entry.subject, flaws)

_applies_evals_alone(req, entry, flaws, true) := r if r := _applies_evals(req, entry.subject, flaws) with data.ergo_item as entry

_subject_rows_alone(entry, ref, req, name, fixed, false) := _subject_rows(entry, ref, req, name, fixed.check_flaws, fixed.prepared)

_subject_rows_alone(entry, ref, req, name, fixed, true) := r if r := _subject_rows(entry, ref, req, name, fixed.check_flaws, fixed.prepared) with data.ergo_item as entry

_with_ref_answer(check) := _ref_answered_compare(check) if {
	is_object(check)
	check.op == "compare"
} else := object.union(check, {"checks": [_ref_answered_compare(c) | some c in check.checks]}) if {
	is_object(check)
	check.op in {"all_of", "sentence_any_of", "for"}
	is_array(check.checks)
} else := check

_ref_answered_compare(c) := object.union(c, {"$ref_cause": _ref_cause(c), "$once": true}) if {
	is_object(c)
	_once_shaped(c)
} else := object.union(c, {"$once": false}) if {
	is_object(c)
	c.op == "compare"
} else := c

default _scope_readable(_, _, _) := false

_scope_readable(_, _, req) if {
	_size(_applies_to_of(req)) == 0
}

_scope_readable(raw, applies, _) if count([row | some row in applies; row.cause in {"satisfied", "value"}]) == count(raw)

default _rows_complete(_, _, _) := false

_rows_complete(groups, matching, req) if {
	count(groups) == count(matching)
	every group in groups {
		count(group) == count(_checks_of(req))
	}
}

default _holds(_, _) := false

_holds(req, e) if {
	e.well_formed.passed
	_all_passed(e.unique_ids)
	_all_passed(e.unique_ancestor_ids)
	_all_passed(e.min_subjects)
	e.scope_readable
	e.rows_complete
	_required(_require_of(req), e.subject_rows)
}

_required("every", groups) if {
	every group in groups {
		_all_passed(group)
	}
}

_required("some", groups) if {
	pairs := _parent_passes(groups)
	count({parent | some [parent, _] in pairs} - {parent | some [parent, true] in pairs}) == 0
}

_group_parent(group) := object.get(group[0].subject, "in", {})

_parent_passes(groups) := {[_group_parent(group), _group_passed(group)] | some group in groups; count(group) > 0}

_group_passed(group) if _all_passed(group)

else := false

_shadowing_parents(req, e) := {parent | some [parent, true] in _parent_passes(e.subject_rows)} - {{}} if _require_of(req) == "some"

else := set()

_all_passed(rows) if {
	every row in rows {
		row.passed
	}
}

_status(req, e) := "met" if {
	_holds(req, e)
	e.matching > 0
}

_status(req, e) := "not_applicable" if {
	_holds(req, e)
	e.matching == 0
}

_status(req, e) := "not_met" if not _holds(req, e)

_causes(status, _, _) := [] if status in {"met", "not_applicable"}

_causes("not_met", e, req) := _counted_causes(e, _shadowing_parents(req, e))

_counted_causes(e, shadowing) := _cause_counts([row.cause | some row in _failing_rows(e, shadowing)])

_cause_counts(causes) := [{"cause": cause, "rows": n} |
	some cause in array.concat(_cause_precedence, ["value"])
	n := count([found | some found in causes; found == cause])
	n > 0
]

_failing_rows(e, shadowing) := [row |
	some row in _requirement_rows(e)
	row.passed == false
	not _out_of_scope_row(row)
] if count(shadowing) == 0

else := [row |
	some row in _requirement_rows(e)
	row.passed == false
	not _out_of_scope_row(row)
	not _shadowed(row, shadowing)
]

_shadowed(row, shadowing) if {
	count(shadowing) > 0
	not startswith(row.check, "$")
	object.get(row.subject, "in", {}) in shadowing
}

_requirement_rows(e) := array.concat(
	array.concat(array.concat([e.well_formed], array.concat(e.min_subjects, array.concat(e.unique_ids, e.unique_ancestor_ids))), e.applies),
	[row | some group in e.subject_rows; some row in group],
)

default _policy_compliant(_, _) := false

_policy_compliant(policy, evaluations) if {
	is_object(policy)
	_size(policy) > 0
	every name, req in policy {
		_holds(req, evaluations[name])
	}
}

_results(policy, evaluations) := [_m_row_one_line(row) | some row in rows] if {
	rows := array.concat(
		array.concat(
			[_m_problems_row(evaluations[name].well_formed) | some name in _names(policy)],
			array.concat(
				[_m_count_row(row) | some name in _names(policy); some row in evaluations[name].min_subjects],
				array.concat(
					[_m_count_row(row) | some name in _names(policy); some row in evaluations[name].unique_ids],
					[_m_count_row(row) | some name in _names(policy); some row in evaluations[name].unique_ancestor_ids],
				),
			),
		),
		array.concat(
			[_inputs_once(row) | some name in _names(policy); some row in evaluations[name].applies],
			[_inputs_once(row) | some name in _names(policy); some group in evaluations[name].subject_rows; some row in group],
		),
	)
}

_m_row_one_line(row) := object.union(row, {"message": _m_one_line(row.message)}) if {
	is_string(object.get(row, "message", null))
	_m_separator_in(row.message)
}

else := row

_m_separator_in(m) if contains(m, "\u2028")

_m_separator_in(m) if contains(m, "\u2029")

_m_separator_in(m) if contains(m, "\u0085")

_inputs_once(row) := object.union(row, {"inputs": _once(row.inputs)})

_names(x) := sort(object.keys(x)) if is_object(x)

_names(x) := [i | some i, _ in x] if is_array(x)
