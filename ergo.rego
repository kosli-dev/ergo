# Copyright 2026 Kosli, Inc
# SPDX-License-Identifier: Apache-2.0

# METADATA
# scope: package
# schemas:
#   - input["ergo/names"]: {"type": "object"}
package ergo

import rego.v1

_req_field(req, f, d) := object.get(req, f, d) if is_object(req)

_req_field(req, _, d) := d if not is_object(req)

_object_or_empty(x) := x if is_object(x)

_object_or_empty(x) := {} if not is_object(x)

_checks_of(req) := _object_or_empty(_req_field(req, "checks", {}))

_raw_subject(name) := def if {
	is_object(data.ergo_subjects)
	def := object.get(data.ergo_subjects, name, null)
	is_object(def)
}

_of_graph := {name: _of_edges(def, data.ergo_subjects) | some name, def in data.ergo_subjects} if is_object(data.ergo_subjects)

_of_edges(def, subjects) := [def.of] if {
	is_object(def)
	_has_type("of", object.get(def, "of", null))
	def.of in object.keys(subjects)
} else := []

default _is_root(_) := false

_is_root(name) if {
	def := _raw_subject(name)
	not "of" in object.keys(def)
}

_filters_of(name) := object.get(_raw_subject(name), "applies_to", {})

_built_on_count(name) := count(graph.reachable(_of_graph, [name]))

_resolved_subjects := {name: _resolution(name) | some name, _ in data.ergo_subjects} if is_object(data.ergo_subjects)

default _resolved_subjects := {}

_resolution(name) := object.union({"members": members, "problems": problems}, resolved) if {
	members := {m | some m in graph.reachable(_of_graph, [name])}
	resolved := _resolved_def(members)
	problems := _member_problems(members)
}

_resolved_def(members) := {"def": def, "filter_owners": owners} if {
	some r in members
	_is_root(r)
	root := _raw_subject(r)
	owners := {n: _filter_owner_in(members, n) | some m in members; some n, _ in _object_or_empty(_filters_of(m))}
	def := object.union(
		{f: _root_field(f, root[f], r, members) | some f in ["from", "identified_by"]; f in object.keys(root)},
		{"applies_to": _merged_filters(members, owners)},
	)
} else := {}

_root_field("from", _, r, members) := "<built on a subject read from another subject>" if {
	count(members) > 1
	r in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
} else := v if {
	v := _raw_subject(r).from
}

_root_field("identified_by", v, _, _) := v

_merged_filters(members, owners) := {n: _filters_of(owner)[n] | some n, owner in owners} if {
	every m in members {
		is_object(_filters_of(m))
	}
}

_filter_owner_in(members, n) := owners[count(owners) - 1][1] if {
	owners := sort([[_built_on_count(m), m] |
		some m in members
		n in object.keys(_object_or_empty(_filters_of(m)))
	])
	count(owners) > 0
}

_resolution_of(req) := data.ergo_resolved[req.subject] if _names_a_subject(req)

_subject_def(req) := _resolution_of(req).def

default _resolves(_) := false

_resolves(req) if _subject_def(req)

default _names_a_subject(_) := false

_names_a_subject(req) if {
	is_object(req)
	_has_type("subject", object.get(req, "subject", null))
}

_subject_field(req, f, d) := object.get(_subject_def(req), f, d)

_applies_to_of(req) := _object_or_empty(_subject_field(req, "applies_to", {})) if _resolves(req)

_applies_to_of(req) := {} if not _resolves(req)

_from_of(req) := _subject_field(req, "from", []) if _resolves(req)

_from_of(req) := null if not _resolves(req)

_id_of(req) := _subject_field(req, "identified_by", []) if _resolves(req)

_id_of(req) := [] if not _resolves(req)

_subject_type_of(req) := _req_field(req, "subject", "subject")

_min_subjects_of(req) := _req_field(req, "min_subjects", 1)

_require_of(req) := _req_field(req, "require", "every")

_wrong_typed_fields(req) := _wrong_typed(req, _wrong_type_problems)

_wrong_typed(x, problems) := [f |
	is_object(x)
	some f in sort(object.keys(problems))
	f in object.keys(x)
	not _has_type(f, x[f])
]

_has_type("applies_to", v) if is_object(v)

_has_type("checks", v) if is_object(v)

_has_type("from", v) if is_array(v)

_has_type("from", v) if is_string(v)

_has_type("identified_by", v) if is_array(v)

_has_type("identified_by", v) if is_string(v)

_has_type("min_subjects", v) if {
	is_number(v)
	v >= 0
	v == floor(v)
}

_has_type("subject", v) if {
	is_string(v)
	trim_space(v) != ""
}

_has_type("of", v) if {
	is_string(v)
	trim_space(v) != ""
}

_has_type("description", v) if is_string(v)

_has_type("description", null)

_has_type("meta", v) if is_object(v)

_has_type("meta", null)

_json_problems(v) := {"holds a key that isn't a string" |
	walk(v, [_, x])
	is_object(x)
	some k in object.keys(x)
	not is_string(k)
} | {"holds a set" |
	walk(v, [_, x])
	is_set(x)
}

_meta_problems(m) := _json_problems(m) | {"number out of range" | _out_of_range(m)}

_meta_shaped(v) if {
	is_object(v)
	count(_meta_problems(v)) == 0
}

_req_meta_problems(req) := {["meta", p] |
	is_object(req)
	is_object(object.get(req, "meta", null))
	some p in _meta_problems(req.meta)
}

_reported_description(x) := object.get(x, "description", "") if {
	is_object(x)
	is_string(object.get(x, "description", ""))
} else := ""

_reported_meta(x) := json.unmarshal(_json_text(x.meta)) if {
	is_object(x)
	_meta_shaped(object.get(x, "meta", null))
} else := {}

_typed(req) if {
	is_object(req)
	_wrong_typed_fields(req) == []
}

_unknown_req_fields(req) := sort([f |
	some f in object.keys(req)
	not f in (object.keys(_wrong_type_problems) | {"require"})
]) if is_object(req)

_unknown_subject_fields(def) := sort([f |
	some f in object.keys(def)
	not f in (object.keys(_subject_wrong_type_problems) | {"has"})
])

_unknown_req_fields(req) := [] if not is_object(req)

_not_an_object_inputs(req) := [{"name": "requirement", "value": req, "locations": []}] if not is_object(req)

_not_an_object_inputs(req) := [] if is_object(req)

_wrong_type_problems := {
	"checks": "not an object",
	"min_subjects": "not a whole number of 0 or more",
	"subject": "empty or not a string",
	"description": "not a string",
	"meta": "not an object",
}

_subject_wrong_type_problems := {
	"applies_to": "not an object",
	"from": "not a string",
	"identified_by": "not a string",
	"description": "not a string",
	"of": "empty or not a string",
}

_req_problems(req) := union({_req_meta_problems(req), _type_problems(req), _range_problems(req), _unknown_problems(req), _checks_problems(req), _require_problems(req), _req_json_problems(req), _subject_problems(req)})

_subject_problems(req) := (_subject_ref_problems(req) | _resolution_problems(req)) | _parent_problems(req)

_parent_problems(req) := union({_resolution_problems({"subject": a}) | some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)}) if _chained(req)

_parent_problems(req) := set() if not _chained(req)

_resolution_problems(req) := r.problems if {
	r := _resolution_of(req)
} else := set()

_member_problems(members) := union({
	{[array.concat(["subjects", m], [p[0]]), p[1]] |
		some m in members
		some p in _def_problems(_raw_subject(m))
	},
	{[["subjects", m, "from"], "can't build on a subject read from another subject yet"] |
		some m in members
		of := object.get(_raw_subject(m), "of", null)
		is_string(of)
		of in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
	},
	{[["subjects", m, "of"], "not in subjects"] |
		some m in members
		of := object.get(_raw_subject(m), "of", null)
		_has_type("of", of)
		not of in object.keys(data.ergo_subjects)
	},
	{[["subjects", m], "not an object"] |
		some m in members
		not _raw_subject(m)
	},
	{[["subjects", m], "it is a word of the grammar, so a subject can't be called it"] |
		some m in members
		m == "it"
	},
	{[["subjects", m, f], p] |
		some m in members
		some f, ps in object.get(data.ergo_subject_sentences.problems, m, {})
		some p in ps
	},
	{[array.concat(["subjects", m], p[0]), p[1]] |
		some m in members
		some p in object.get(object.get(data.ergo_subject_sentences, "has_problems", {}), m, set())
	},
	{[["subjects", m, "applies_to", n], "also a filter of a subject it builds on"] |
		some m in members
		some n in object.keys(_object_or_empty(_filters_of(m)))
		some other in graph.reachable(_of_graph, [m])
		other != m
		n in object.keys(_object_or_empty(_filters_of(other)))
	},
})

_subject_ref_problems(req) := (({["subject", "missing"] |
	is_object(req)
	not "subject" in object.keys(req)
} | {[["subjects"], "not an object"] |
	_names_a_subject(req)
	not is_object(data.ergo_subjects)
}) | {["subject", "not in subjects"] |
	_names_a_subject(req)
	is_object(data.ergo_subjects)
	not req.subject in object.keys(data.ergo_subjects)
}) | {[["subjects", req.subject], "not an object"] |
	_names_a_subject(req)
	is_object(data.ergo_subjects)
	req.subject in object.keys(data.ergo_subjects)
	not is_object(data.ergo_subjects[req.subject])
}

_def_problems(def) := union({
	{[f, _subject_wrong_type_problems[f]] | some f in _wrong_typed(def, _subject_wrong_type_problems)},
	{[f, "unknown field"] | some f in _unknown_subject_fields(def)},
	{["identified_by", "not allowed on a subject that narrows another"] | "of" in object.keys(def); "identified_by" in object.keys(def)},
	_path_problems(def, "from"),
	_path_problems(def, "identified_by"),
	_def_json_problems(def),
})

_req_json_problems(req) := {["checks", "holds a key that isn't a string"] |
	v := _req_field(req, "checks", null)
	is_object(v)
	some k in object.keys(v)
	not is_string(k)
}

_def_json_problems(def) := {[f, p] |
	some f in ["from", "identified_by"]
	v := object.get(def, f, null)
	is_array(v)
	some p in _json_problems(v)
} | {["applies_to", "holds a key that isn't a string"] |
	v := object.get(def, "applies_to", null)
	is_object(v)
	some k in object.keys(v)
	not is_string(k)
}

_type_problems(req) := {[f, _wrong_type_problems[f]] |
	some f in _wrong_typed_fields(req)
	not _min_subjects_out_of_range(req, f)
}

_min_subjects_out_of_range(req, "min_subjects") if {
	is_number(req.min_subjects)
	_out_of_range(req.min_subjects)
}

_range_problems(req) := {["min_subjects", "number out of range"] |
	is_number(_min_subjects_of(req))
	_out_of_range(_min_subjects_of(req))
}

_unknown_problems(req) := {[f, "unknown field"] | some f in _unknown_req_fields(req)}

_checks_problems(req) := {["checks", "missing"] | is_object(req); not "checks" in object.keys(req)} | {["checks", "empty"] | req.checks == {}}

_reserved_name_problems(req) := {[_field_path_name(["checks", name]), "name reserved"] | some name, _ in _checks_of(req); name in _reserved_checks}

_reserved_checks := {"$applies", "$min_subjects", "$unique_ids", "$well_formed"}

_require_problems(req) := {["require", "neither every nor some"] | is_object(req); not _require_of(req) in {"every", "some"}}

_path_problems(req, f) := {[f, "number out of range"] | is_array(_req_field(req, f, null)); _out_of_range(req[f])}

_field_problem_inputs(req) := [{"name": _field_name(f), "value": sort({p[1] | some p in problems; p[0] == f}), "locations": []} | some f in sort({p[0] | some p in problems})] if {
	problems := _req_problems(req)
}

_field_name(f) := _field_path_name([f]) if is_string(f)

_field_name(f) := _field_path_name(f) if {
	is_array(f)
	is_string(f[count(f) - 1])
}

_field_name(f) := concat(".", [_field_path_name(array.slice(f, 0, count(f) - 1)), _invalid_key_name(f[count(f) - 1])]) if {
	is_array(f)
	not is_string(f[count(f) - 1])
}

_field_name(f) := _invalid_key_name(f) if {
	not is_string(f)
	not is_array(f)
}

_invalid_key_name(k) := concat("", ["<invalid key ", _literal_text(k), ">"])

_has_problems(req, f) if {
	some p in _req_problems(req)
	p[0] == f
}

_size(x) := count(x) if type_name(x) in {"array", "object", "set", "string"}

_from_path(req) := array.slice(_from_of(req), 0, count(_from_of(req)) - 1) if _has_step(req)

_from_path(req) := _from_of(req) if not _has_step(req)

default _has_step(_) := false

_has_step(req) if _each_step(req)

_each_step(req) := req["ergo/fixed"].each_step[0] if _has_fixed(req)

_each_step(req) := _each_step_of(req) if not _has_fixed(req)

_has_fixed(req) if is_set(req["ergo/fixed"].mark)

_with_fixed(req) := object.union(req, {"ergo/fixed": {
	"mark": set(),
	"each_step": [step | step := _each_step_of(req)],
	"has_parts": _has_parts_of(req),
	"tagging": _tagging_of(req),
	"scoped": _scoped_of(req),
}}) if is_object(req)

_each_step_of(req) := step if {
	f := _from_of(req)
	is_array(f)
	count(f) > 0
	step := f[count(f) - 1]
	is_object(step)
	not _is_ref(step)
}

default _stepped(_) := false

_stepped(req) if {
	f := _from_of(req)
	is_array(f)
	some seg in f
	is_object(seg)
	not _is_ref(seg)
}

default _from_well_formed(_) := false

_from_well_formed(req) if {
	is_object(req)
	is_array(_from_of(req))
	not _stepped(req)
}

_from_well_formed(req) if {
	_each_step(req)
	every seg in _from_path(req) {
		_plain_step(seg)
	}
}

_plain_step(seg) if not is_object(seg)

_plain_step(seg) if _is_ref(seg)

_valid_name(n) if {
	is_string(n)
	n != ""
	not startswith(n, "$")
	not n in {"params", "input"}
}

_listed_keys(step) := v if {
	_is_ref(step.keys)
	v := _ref_read(step.keys.ref)
	is_array(v)
}

_target(doc, req) := object.get(doc, _from_keys(req), null) if is_object(doc)

_target_read(doc, req) := object.get(doc, _from_keys(req), _absent) if is_object(doc)

_target_read(doc, req) := doc if {
	not _is_collection(doc)
	_from_keys(req) == []
}

_target_read(doc, req) := _absent if {
	not is_object(doc)
	count(_from_keys(req)) > 0
}

_target_cause(doc, req) := c if {
	_from_well_formed(req)
	not _from_unreadable(req)
	not _keys_step(req)
	not _every_from(req)
	c := _target_state(doc, req)
	c != "value"
}

_target_cause(doc, req) := c if {
	_from_well_formed(req)
	not _from_unreadable(req)
	_every_from(req)
	c := _every_cause(doc, req)
}

_every_cause(doc, req) := c if {
	not is_object(doc)
	c := _target_state(doc, req)
	c != "value"
} else := _worst_of({f.cause | some f in fails}) if {
	fails := _every_walk(doc, _from_keys(req)).fails
	count(fails) > 0
}

default _every_from(_) := false

_every_from(req) if {
	is_object(req)
	is_string(object.get(req, "subject", null))
	req.subject in object.get(data.ergo_subject_sentences, "every", set())
}

_every_walk(doc, keys) := {"subjects": [{"subject": e.v, "at": _walk_at(w, e)} | some e in w.items; _every_kept(e, last)], "fails": array.concat(array.concat(w.fails, _walk_stop(w)), [object.union(_every_end_fail(e), {"at": _walk_at(w, e)}) | some e in w.items; not _every_kept(e, last)])} if {
	w := _walk({"c": [], "v": doc, "i": null, "iv": null, "r": [], "a": _doc_at}, keys, true)
	last := count(keys) in w.walked
}

_every_kept(_, true)

_every_kept(e, false) if _walk_container(e.v)

_every_end_fail(e) := {"path": e.c, "item": e.c, "cause": _walk_stop_state(e.v), "value": _walk_shown(e.v)}

_keys_step(req) if "keys" in object.keys(_each_step(req))

default _target_state(_, _) := "absent"

_target_state(doc, req) := "null" if _target_read(doc, req) == null

_target_state(doc, _) := "unusable" if is_array(doc)

_target_state(doc, req) := "unusable" if {
	_target_read(doc, req) == _absent
	_blocked(doc, _from_keys(req))
}

_target_state(doc, req) := "unusable" if {
	v := _target_read(doc, req)
	v != _absent
	v != null
	not _is_collection(v)
}

_target_state(doc, req) := "value" if {
	v := _target_read(doc, req)
	v != _absent
	_is_collection(v)
}

_from_keys(req) := ks if {
	p := _from_path(req)
	is_array(p)
	ks := [_step_key(seg) | some seg in p]
	count(ks) == count(p)
}

_from_unreadable(_) if _unreadable_input

_from_unreadable(req) if {
	p := _from_path(req)
	is_array(p)
	some seg in p
	_is_ref(seg)
	not _step_key(seg)
}

_from_unreadable(req) if {
	step := _each_step(req)
	_is_ref(step.keys)
	not _listed_keys(step)
}

_from_cause(req) := _worst_of(unread) if {
	unread := _from_ref_states(req) - {"value"}
	count(unread) > 0
}

_from_cause(req) := "unusable" if _from_ref_states(req) - {"value"} == set()

_from_ref_states(req) := {_ref_state(seg.ref) | some seg in _from_path(req); _is_ref(seg)} | {_ref_state(r) | some r in _keys_refs(_each_step(req))}

_keys_refs(step) := {step.keys.ref} if _is_ref(step.keys)

_listed_subjects(doc, req) := [{"subject": subj, "at": concat("", [base, "/", format_int(i, 10)])} | some i, subj in coll] if {
	coll := _target(doc, req)
	is_array(coll)
	base := _pointer(_doc_at, doc, _from_keys(req))
}

_listed_subjects(doc, req) := [{"subject": coll, "at": _pointer(_doc_at, doc, _from_keys(req))}] if {
	coll := _target(doc, req)
	is_object(coll)
}

_listed_subjects(doc, req) := [] if {
	not is_array(_target(doc, req))
	not is_object(_target(doc, req))
}

_raw_entries(doc, req) := [entry | some entry in _listed_subjects(doc, req)] if {
	not _stepped(req)
	_from_well_formed(req)
	not _every_from(req)
}

_raw_entries(doc, req) := _every_walk(doc, _from_keys(req)).subjects if {
	_from_well_formed(req)
	_every_from(req)
	is_object(doc)
}

_raw_entries(doc, req) := [] if {
	_from_well_formed(req)
	_every_from(req)
	not is_object(doc)
}

_raw_entries(doc, req) := [{"key": k, "subject": object.get(_keyed(doc, req), [k], _absent), "at": _pointer(_doc_at, doc, array.concat(_from_keys(req), [k]))} | some k in sort({k | some k in _listed_keys(_each_step(req))})] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	_listed_keys(_each_step(req))
}

_raw_entries(_, req) := [] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	not _listed_keys(_each_step(req))
}

_keyed(doc, req) := coll if {
	coll := _target(doc, req)
	is_object(coll)
}

_keyed(doc, req) := {} if not is_object(_target(doc, req))

_scope_of(req, subj) := {"ergo/names": object.union(object.union(object.union(names, _parent_names), _subject_name(req, subj)), {"$at": {"names": _name_ats(req), "subject": _subject_at}})} if names := _each_names(req, subj)

_name_ats(req) := object.union({_each_step(req).each_as: _subject_at}, _parent_ats) if {
	_has_step(req)
	_from_well_formed(req)
}

_name_ats(req) := _parent_ats if not _has_step(req)

_subject_name(req, subj) := {"ergo/subject": subj} if _has_parts(req)

_subject_name(req, _) := {} if not _has_parts(req)

_subjects_with_parts := {name | some name, parts in object.get(data.ergo_subject_sentences, "parts", {}); count(parts) > 0}

default _has_parts(_) := false

_has_parts(req) if {
	_has_fixed(req)
	req["ergo/fixed"].has_parts == true
}

_has_parts(req) if {
	not _has_fixed(req)
	_has_parts_of(req)
}

default _has_parts_of(_) := false

_has_parts_of(req) if {
	is_string(object.get(req, "subject", null))
	req.subject in _subjects_with_parts
}

_each_names(req, subj) := {_each_step(req).each_as: subj} if {
	_has_step(req)
	_from_well_formed(req)
}

_each_names(req, _) := {} if not _has_step(req)

default _parent_names := {}

_parent_names := data.ergo_parent if is_object(data.ergo_parent)

_scoped(req) if {
	_has_fixed(req)
	req["ergo/fixed"].scoped == true
}

_scoped(req) if {
	not _has_fixed(req)
	_scoped_of(req)
}

default _scoped_of(_) := false

_scoped_of(req) if _has_step(req)

_scoped_of(_) if _parent_names != {}

_scoped_of(req) if {
	_has_parts(req)
	_reads_whole_subject(req)
}

_reads_whole_subject(req) if _has_old_marker(req)

_has_old_marker(x) if {
	walk(x, [_, s])
	is_string(s)
	startswith(s, "${\"alias\":")
	_part_start([s])
	_part_of([s]).old == true
}

_applies_evals(req, subj, flaws) := {name: _filter_eval(req, check, subj, flaws[name]) | some name, check in _applies_to_of(req)} if not _scoped(req)

else := evals if {
	_scoped(req)
	s := _scope_of(req, subj)
	evals := {name: _filter_eval(req, check, subj, flaws[name]) | some name, check in _applies_to_of(req)} with input as s
}

_filter_eval(req, check, subj, flaw) := {
	"passed": _filter_walk_passed(flaw, w),
	"cause": _filter_walk_cause(flaw, w),
	"assertion_cause": w.cause,
	"inputs": _tagged(_with_key_fields(subj, check, w.inputs), check, req, subj),
	"failed_items": w.failed,
} if {
	_walks(check)
	w := _walk_row(check, subj)
}

_filter_eval(req, check, subj, flaw) := {
	"passed": passed,
	"cause": _filter_cause(check, subj, flaw),
	"assertion_cause": _filter_assertion_cause(passed, check, subj, flaw),
	"inputs": _tagged(_row_inputs(subj, check), check, req, subj),
} if {
	not _walks(check)
	passed := _check_passed(check, subj, flaw)
}

_filter_walk_passed("", w) := w.cause == "satisfied"

_filter_walk_passed(flaw, _) := false if flaw != ""

_filter_walk_cause("", w) := w.cause

_filter_walk_cause(flaw, _) := flaw if flaw != ""

_filter_assertion_cause(true, _, _, _) := "satisfied"

_filter_assertion_cause(false, check, subj, flaw) := _assertion_cause(check, subj, flaw)

_outcome(req, check, flaw, subj) := _tagged_outcome(_check_outcome(check, subj, flaw), check, req, subj) if not _scoped(req)

else := o if {
	_scoped(req)
	s := _scope_of(req, subj)
	raw := _check_outcome(check, subj, flaw) with input as s
	o := _tagged_failures(object.union(raw, {"inputs": _tagged(raw.inputs, check, req, subj)}), check, req, subj) with input as s
}

_tagged_outcome(raw, _, req, _) := raw if not _tagging(req)

_tagged_outcome(raw, check, req, subj) := _tagged_failures(object.union(raw, {"inputs": _tagged(raw.inputs, check, req, subj)}), check, req, subj) if _tagging(req)

_tagged_failures(row, check, req, subj) := object.union(row, {"failed_items": [_tagged_failure(f, check, req, subj) | some f in row.failed_items]}) if "failed_items" in object.keys(row)

else := row

_tagged_failure(f, check, req, subj) := object.union(f, {"failed_assertions": [_tagged_line(l, check, req, subj) | some l in f.failed_assertions]}) if "failed_assertions" in object.keys(f)

else := f

_tagged_line(l, check, req, subj) := object.union(l, object.union(_tagged_line_inputs(l, check, req, subj), _tagged_line_items(l, check, req, subj)))

_tagged_line_inputs(l, check, req, subj) := {"inputs": _tagged(l.inputs, check, req, subj)} if "inputs" in object.keys(l)

else := {}

_tagged_line_items(l, check, req, subj) := {"items": [object.union(x, {"inputs": _tagged(x.inputs, check, req, subj)}) | some x in l.items]} if "items" in object.keys(l)

else := {}

_tagging(req) if {
	_has_fixed(req)
	req["ergo/fixed"].tagging == true
}

_tagging(req) if {
	not _has_fixed(req)
	_tagging_of(req)
}

default _tagging_of(_) := false

_tagging_of(req) if _has_parts(req)

_tagging_of(req) if {
	is_string(object.get(req, "subject", null))
	some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)
	a in _subjects_with_parts
}

_tagged(inputs, _, req, _) := inputs if not _tagging(req)

_tagged(inputs, check, req, subj) := [_tagged_input(i, {{"name": p.name, "id": _part_id(p.ms, p.steps, p.read, subj)} | some p in parts; _mentions(i.name, p.patterns)}) | some i in inputs] if {
	_tagging(req)
	parts := _check_parts(check, req)
}

_tagged_input(i, matches) := object.union(i, {"part": tag}) if {
	count(matches) == 1
	some tag in matches
}

_tagged_input(i, matches) := i if count(matches) != 1

_check_parts(check, req) := [{"patterns": [_mention_pattern(_steps_name([_p_marker(m.alias, m.n, m.of, false)])), _mention_pattern(_steps_name([ms])), _mention_pattern(_steps_name(array.concat([_p_marker(m.alias, -1, m.of, m.old)], steps)))], "name": _tag_name(m), "ms": ms, "steps": steps, "read": read} |
	some ms in {x[0] | walk(check, [_, x]); is_array(x); _part_start(x)}
	m := json.unmarshal(substring(ms, 1, -1))
	read := data.ergo_subject_sentences.parts[_marker_owner(req, m)][m.alias]
	steps := read.from.path
]

_marker_owner(req, m) := req.subject if m.of == null

_marker_owner(_, m) := m.of if m.of != null

_tag_name(m) := m.alias if m.of == null

_tag_name(m) := concat("", [_s_key_text(m.of), ".", m.alias]) if m.of != null

_part_id(ms, steps, read, subj) := _value_at(subj, array.concat(array.concat([ms], steps), path)) if path := _id_path(read)

_part_id(_, _, read, _) := null if not _id_path(read)

_id_path(read) := path if {
	is_object(read.identified_by)
	path := read.identified_by.path
}

_mentions(name, patterns) if {
	some pattern in patterns
	regex.match(pattern, replace(name, "[]", ""))
}

_mention_pattern(token) := concat("", [`(^|[^A-Za-z0-9_."$-])`, _quoted(replace(token, "[]", "")), `($|[^A-Za-z0-9_-])`])

_quoted(text) := strings.replace_n({`\`: `\\`, ".": `\.`, "+": `\+`, "*": `\*`, "?": `\?`, "(": `\(`, ")": `\)`, "|": `\|`, "[": `\[`, "]": `\]`, "{": `\{`, "}": `\}`, "^": `\^`, "$": `\$`}, text)

_check_outcome(check, subj, flaw) := {
	"inputs": _row_inputs(subj, check),
	"passed": _check_passed(check, subj, flaw),
	"cause": _row_cause(check, subj, flaw),
} if {
	not _all_of_run(check)
	not _any_of_run(check)
	not _walk_run(check)
	not _derived_once(check)
}

_check_outcome(check, subj, flaw) := {
	"inputs": _with_key_fields(subj, check, e.inputs),
	"passed": _once_passed(flaw, e),
	"cause": _once_cause(flaw, e),
} if {
	_derived_once(check)
	e := _derived_eval(check, subj)
}

_once_passed("", e) := e.passed

_once_passed(flaw, _) := false if flaw != ""

_once_cause("", e) := e.cause

_once_cause(flaw, _) := flaw if flaw != ""

default _derived_once(_) := false

_derived_once(check) if check["$once"] == true

_derived_once(check) if {
	not _answered_once(check)
	_once_shaped(check)
}

_answered_once(check) if {
	is_object(check)
	object.get(check, "$once", null) != null
}

default _once_shaped(_) := false

_once_shaped(check) if {
	check.op == "compare"
	_derived_sides(check) != []
	every f in ["left", "right"] {
		_side_form(object.get(check, f, null))
	}
}

_ref_cause(check) := check["$ref_cause"] if {
	is_object(check)
	"$ref_cause" in object.keys(check)
} else := _worst_of({_used_ref_state(check, r) | some r in _check_refs(check)}) if {
	_unreadable_ref(check)
} else := ""

_derived_eval(check, subj) := {"passed": passed, "cause": cause, "inputs": array.concat(l.inputs, r.inputs)} if {
	l := _side_eval(subj, check.left)
	r := _side_eval(subj, check.right)
	passed := _eval_compared(check, l.v, r.v)
	states := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(check, lf, rf)}
	cause := _eval_cause(passed, _ref_cause(check), states)
}

_eval_compared(check, [lv], [rv]) if _compared(check, lv, rv)

default _eval_compared(_, _, _) := false

_eval_cause(true, _, _) := "satisfied"

_eval_cause(false, "", states) := _worst_or_value(states)

_eval_cause(false, ref_cause, _) := ref_cause if ref_cause != ""

_basic_eval(subj, side) := {"v": v, "found": [x | x := _simple_found(subj, side)], "states": {_read_state(subj, side)}, "inputs": _basic_inputs(subj, side)} if {
	_basic_form(side) == "path"
	v := [x | x := _value_at(subj, side)]
}

_basic_eval(subj, side) := {"v": [_written(side)], "found": [x | x := _simple_found(subj, side)], "states": set(), "inputs": []} if _basic_form(side) == "literal"

_basic_eval(subj, side) := {"v": v, "found": v, "states": t.states, "inputs": _tally_inputs(subj, side, t)} if {
	_basic_form(side) in {"count_of", "sum_of"}
	t := _tally(subj, side)
	v := [x | x := t.value]
}

_basic_eval(subj, side) := {"v": v, "found": v, "states": _elapsed_states(subj, side), "inputs": _basic_inputs(subj, side)} if {
	_basic_form(side) == "elapsed"
	v := [x | x := _basic_value(subj, side)]
}

_side_eval(subj, side) := _basic_eval(subj, side) if _basic_form(side)

_side_eval(subj, side) := {"v": v, "found": v, "states": union({o.states | some o in ops}), "inputs": array.concat([_number_input(_side_text(side), _first_or_null(v), operands)], operands)} if {
	_side_form(side) == "add"
	ops := [_operand_eval(subj, operand) | some operand in side.add]
	operands := [i | some o in ops; some i in o.inputs]
	v := _added(side, ops)
}

_operand_eval(subj, operand) := object.union(_basic_eval(subj, operand), {"states": _number_states(subj, operand)}) if _basic_form(operand) == "path"

_operand_eval(subj, operand) := _basic_eval(subj, operand) if _basic_form(operand) != "path"

_added(side, ops) := [_add_numbers(side, nums)] if {
	nums := [n | some o in ops; [n] := o.v]
	count(nums) == count(ops)
	every n in nums {
		is_number(n)
	}
} else := []

_first_or_null([x]) := x

_first_or_null([]) := null

_check_outcome(check, subj, _) := {
	"inputs": _with_key_fields(subj, check, r.inputs),
	"passed": r.cause == "satisfied",
	"cause": r.cause,
	"failed_items": r.failed,
} if {
	_walks(check)
	_walk_run(check)
	r := _walk_row(check, subj)
}

_walk_run(check) if {
	check.op in {"every", "some", "for"}
}

_check_outcome(check, subj, _) := {
	"inputs": r.inputs,
	"passed": r.cause == "satisfied",
	"cause": r.cause,
	"failed_items": r.failed,
} if {
	check.op == "for"
	_walk_run(check)
	r := _for_row(check, subj)
}

_all_of_run(check) if {
	check.op == "all_of"
}

_check_outcome(check, subj, flaw) := {
	"inputs": _merged_inputs([i | some o in outs; some i in o.inputs]),
	"passed": count(failed) == 0,
	"cause": _all_of_cause(failed),
	"failed_assertions": failed,
} if {
	_all_of_run(check)
	outs := [_assertion_out(c, subj, flaw) | some c in check.checks]
	failed := [{"assertion": check.assertions[i], "cause": o.cause} | some i, o in outs; o.cause != "satisfied"]
}

_any_of_run(check) if {
	check.op == "sentence_any_of"
}

_check_outcome(check, subj, flaw) := {
	"inputs": _merged_inputs([i | some o in outs; some i in o.inputs]),
	"passed": cause == "satisfied",
	"cause": cause,
} if {
	_any_of_run(check)
	outs := [_assertion_out(c, subj, flaw) | some c in check.checks]
	lines := [_option_line_cause(c, outs[i].cause, subj) | some i, c in check.checks]
	cause := _any_of_lines_cause(check.option_of, lines, flaw)
}

_option_line_cause(c, cause, subj) := "missing" if {
	cause == "value"
	not _walks(c)
	_asks_presence(c, subj)
	_read_state(subj, c.path) in {"absent", "null"}
} else := cause

_any_of_lines_cause(_, _, flaw) := flaw if flaw != ""

_any_of_lines_cause(option_of, lines, "") := "satisfied" if {
	some nm in option_of
	every i, n in option_of {
		_line_passed_or_elsewhere(n, nm, lines[i])
	}
} else := _worst_or_value({_group_cause({lines[i] | some i, n in option_of; n == nm}) | some nm in option_of})

_line_passed_or_elsewhere(n, nm, _) if n != nm

_line_passed_or_elsewhere(_, _, "satisfied")

_assertion_out(c, subj, "") := {"cause": e.cause, "inputs": _with_key_fields(subj, c, e.inputs)} if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := {"cause": _assertion_cause(c, subj, ""), "inputs": _with_key_fields(subj, c, _assertion_inputs(subj, c))}

_assertion_out(c, subj, flaw) := {"cause": _assertion_cause(c, subj, flaw), "inputs": _with_key_fields(subj, c, _assertion_inputs(subj, c))} if flaw != ""

_assertion_cause(c, subj, "") := _row_cause(c, subj, "") if not _walks(c)

_assertion_cause(c, subj, _) := _walk_row(c, subj).cause if _walks(c)

_assertion_cause(c, subj, "unusable") := "unusable" if {
	not _walks(c)
	_unusable_assertion(c)
} else := _row_cause(c, subj, "") if not _walks(c)

_unusable_assertion(_) if _unreadable_input

_unusable_assertion(c) if _node_param_broken(c)

_assertion_inputs(subj, c) := _row_inputs(subj, c) if not _walks(c)

_assertion_inputs(subj, c) := _walk_row(c, subj).inputs if _walks(c)

_all_of_cause([]) := "satisfied"

_all_of_cause(failed) := [c | some c in array.concat(_cause_precedence, ["value"]); c in {f.cause | some f in failed}][0] if failed != []

default _subject_matches(_, _) := false

_subject_matches(evals, req) if {
	count(evals) == count(_applies_to_of(req))
	every _, e in evals {
		e.passed
	}
}

_req_subject_ref(req) := object.union({"type": _subject_type_of(req), "id": null}, _row_in)

default _row_in := {}

_row_in := {"in": data.ergo_in} if data.ergo_in != {}

_entry_ref(entry, req) := object.union(_entry_ref_of(entry, req), _row_in)

_entry_ref_of(entry, req) := {"type": _subject_type_of(req), "id": entry.key} if "key" in object.keys(entry)

_entry_ref_of(entry, req) := _subject_ref(entry.subject, req) if {
	not "key" in object.keys(entry)
	not _scoped(req)
}

_entry_ref_of(entry, req) := r if {
	not "key" in object.keys(entry)
	_scoped(req)
	s := _scope_of(req, entry.subject)
	r := _subject_ref(entry.subject, req) with input as s
}

_subject_ref(subj, req) := {
	"type": _subject_type_of(req),
	"id": _subject_id(subj, req),
}

_subject_id(subj, req) := _value_at(subj, _id_of(req)) if {
	is_object(subj)
	is_array(_id_of(req))
}

_subject_id(subj, _) := subj if not is_object(subj)

_absent := {"ergo/absent": set()}

default _value_at(_, _) := null

_value_at(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, _plain_keys(path), null)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_field(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, _plain_keys(path), _absent)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_resolved(subj, path) := object.get(subj, _plain_keys(path), _absent) if {
	is_object(subj)
	_plain_path(path)
} else := _read_from(_start_of(subj, path), _keys_in(subj, path))

_plain_keys(path) := [_key(seg) | some seg in path]

_plain_path(path) if {
	is_array(path)
	not _named(path)
	every seg in path {
		not is_object(seg)
	}
}

_read_from(start, keys) := _read_at(start, keys, [i | some i, seg in keys; is_object(seg)]) if is_object(start)

_read_from(start, []) := start

_read_from(start, keys) := object.get({"it": start}, array.concat(["it"], keys), _absent) if {
	is_array(start)
	count(keys) > 0
	every seg in keys {
		not is_object(seg)
	}
}

_read_at(start, keys, []) := object.get(start, keys, _absent)

default _named(_) := false

_named(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "$")
}

default _builtin(_) := false

_builtin(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "$$")
}

_start_of(subj, path) := subj if not _named(path)

_start_of(_, path) := data.ergo_document if path[0] == "$$input"

_start_of(_, path) := data.ergo_params if path[0] == "$$params"

_start_of(_, path) := input["ergo/names"][substring(path[0], 1, -1)] if {
	_named(path)
	not _builtin(path)
	not _part_start(path)
}

_start_of(subj, path) := subj if {
	_subject_part(path)
	_part_of(path).old == false
}

_start_of(_, path) := input["ergo/names"]["ergo/subject"] if {
	_subject_part(path)
	_part_of(path).old == true
}

_start_of(_, path) := input["ergo/names"][_part_of(path).of] if {
	_part_start(path)
	not _subject_part(path)
}

default _part_start(_) := false

_part_start(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "${\"alias\":")
	json.is_valid(substring(path[0], 1, -1))
	m := json.unmarshal(substring(path[0], 1, -1))
	is_object(m)
	object.keys(m) == {"alias", "n", "of", "old"}
}

_part_of(path) := json.unmarshal(substring(path[0], 1, -1))

default _subject_part(_) := false

_subject_part(path) if {
	_part_start(path)
	_part_of(path).of == null
}

default _at_ctx := {}

_at_ctx := input["ergo/names"]["$at"] if is_object(input["ergo/names"]["$at"])

default _doc_at := ""

_doc_at := _at_ctx.doc if is_string(_at_ctx.doc)

default _subject_at := "~~"

_subject_at := _at_ctx.subject if is_string(_at_ctx.subject)

default _parent_ats := {}

_parent_ats := _at_ctx.names if is_object(_at_ctx.names)

_name_at(name) := _parent_ats[name]

_row_input(at) := {"ergo/names": {"$at": {"names": _parent_ats, "subject": at}}}

_start_at(path) := _subject_at if not _named(path)

_start_at(path) := "" if path[0] == "$$input"

_start_at(path) := "$params:" if path[0] == "$$params"

_start_at(path) := _name_at(substring(path[0], 1, -1)) if {
	_named(path)
	not _builtin(path)
	not _part_start(path)
}

_start_at(path) := _subject_at if _subject_part(path)

_start_at(path) := _name_at(_part_of(path).of) if {
	_part_start(path)
	not _subject_part(path)
}

_escaped(k) := replace(replace(k, "~", "~0"), "/", "~1") if is_string(k)

_escaped(k) := format_int(k, 10) if is_number(k)

_probe(start, keys) := object.get(start, keys, _absent) if is_object(start)

_probe(start, keys) := object.get({"v": start}, array.concat(["v"], keys), _absent) if not is_object(start)

_reached(start, keys) := max({0} | {i |
	count(keys) > 0
	some i in numbers.range(1, count(keys))
	_probe(start, array.slice(keys, 0, i)) != _absent
})

_pointer(base, start, keys) := _joined(base, keys) if _probe(start, keys) != _absent

else := _joined(base, array.slice(keys, 0, _reached(start, keys)))

_joined(base, []) := base

_joined(base, keys) := concat("", [base, "/", concat("/", [_escaped(k) | some k in keys])]) if count(keys) > 0

_resolved_prefix(subj, steps) := ks if {
	read := {i: k | some i, seg in steps; k := _field_step_key(subj, seg)}
	missing := {i | some i, _ in steps; not i in object.keys(read)}
	n := min(missing | {count(steps)})
	ks := [read[i] | some i in numbers.range(0, n - 1); n > 0]
}

_leading_keys(subj, path) := _resolved_prefix(subj, _path_steps(path))

_first_seen(xs) := [p[1] | some p in sort([[s[1], s[0]] | some j, s in sorted; _starts_group(sorted, j)])] if sorted := sort([[x, i] | some i, x in xs])

_starts_group(_, 0)

_starts_group(sorted, j) if {
	j > 0
	sorted[j][0] != sorted[j - 1][0]
}

_number_input(name, value, inputs) := {"name": name, "value": value, "locations": _first_seen([l | some i in inputs; some l in i.locations])}

_locations_of(subj, path) := [at] if at := _at(subj, path)

else := []

_at(subj, path) := _joined(_subject_at, keys) if {
	is_object(subj)
	_plain_path(path)
	keys := _plain_keys(path)
	object.get(subj, keys, _absent) != _absent
} else := _pointer(_subject_at, subj, _plain_keys(path)) if {
	is_object(subj)
	_plain_path(path)
} else := _pointer(_start_at(path), start, _leading_keys(subj, path)) if {
	start := _start_of(subj, path)
}

_path_input(subj, path) := {"name": _item_path_name(path), "value": _value_at(subj, path), "locations": [at]} if at := _at(subj, path)

else := {"name": _item_path_name(path), "value": _value_at(subj, path), "locations": []}

_merged_inputs(inputs) := [object.union(_with_part({"name": t[0], "value": t[1]}, t[2]), {"locations": t[3]}) | some t in sort({[i.name, i.value, object.get(i, "part", null), i.locations] | some i in inputs})]

_with_part(entry, null) := entry

_with_part(entry, part) := object.union(entry, {"part": part}) if part != null

default _off_subject(_) := false

_off_subject(path) if {
	_named(path)
	not _subject_part(path)
}

_visible(path) := array.concat(_visible_root(_part_of(path)), array.slice(path, 1 + max([_part_of(path).n, 0]), count(path))) if _part_start(path)

_visible(path) := path if not _part_start(path)

_visible_root(m) := [m.alias] if {
	m.of == null
	m.old == false
	m.n >= 0
}

_visible_root(m) := [] if {
	m.of == null
	m.n < 0
}

_visible_root(m) := [concat("", ["$", m.alias])] if {
	m.of == null
	m.old == true
	m.n >= 0
}

_visible_root(m) := [concat("", ["$", m.of]), m.alias] if {
	m.of != null
	m.n >= 0
}

_visible_root(m) := [concat("", ["$", m.of])] if {
	m.of != null
	m.n < 0
}

_keys_of(path) := ks if {
	is_array(path)
	not _named(path)
	ks := [_step_key(seg) | some seg in path]
	count(ks) == count(path)
}

_keys_of(path) := ks if {
	_named(path)
	rest := array.slice(path, 1, count(path))
	ks := [_step_key(seg) | some seg in rest]
	count(ks) == count(rest)
}

_step_key(seg) := _key(seg.literal) if _is_literal(seg)

_step_key(seg) := _key(v) if {
	_is_ref(seg)
	v := _ref_read(seg.ref)
	_is_key(v)
}

_step_key(seg) := _key(seg) if {
	not _is_literal(seg)
	not _is_ref(seg)
	not _name_step(seg)
	not _field_step(seg)
}

_step_key(seg) := v if {
	_name_step(seg)
	v := input["ergo/names"][seg.named_by]
	is_string(v)
}

_name_step(seg) if {
	is_object(seg)
	object.keys(seg) == {"named_by"}
	is_string(seg.named_by)
}

_field_step(seg) if {
	is_object(seg)
	object.keys(seg) == {"named_by_field"}
	is_string(seg.named_by_field)
}

_has_field_step(path) if {
	is_array(path)
	some seg in path
	_field_step(seg)
}

_keys_in(_, path) := _keys_of(path) if not _has_field_step(path)

_keys_in(subj, path) := ks if {
	_has_field_step(path)
	steps := _path_steps(path)
	ks := [k | some seg in steps; k := _field_step_key(subj, seg)]
	count(ks) == count(steps)
}

_path_steps(path) := array.slice(path, 1, count(path)) if _named(path)

_path_steps(path) := path if not _named(path)

_field_step_key(subj, seg) := v if {
	_field_step(seg)
	is_object(subj)
	v := subj[seg.named_by_field]
	is_string(v)
}

_field_step_key(_, seg) := _step_key(seg) if not _field_step(seg)

_is_key(v) if is_string(v)

_is_key(v) if {
	is_number(v)
	not _out_of_range(v)
	v >= 0
	v <= 9007199254740991
	v == floor(v)
}

_key(v) := floor(v) if {
	is_number(v)
	_is_key(v)
} else := v

default _is_ref(_) := false

_is_ref(x) if {
	is_object(x)
	object.keys(x) == {"ref"}
}

default _is_literal(_) := false

_is_literal(x) if {
	is_object(x)
	object.keys(x) == {"literal"}
}

_arg(x) := v if {
	_is_ref(x)
	v := _ref_read(x.ref)
	v != _absent
	v != null
}

_arg(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
}

_ref_read(path) := object.get(start, [_key(seg) | some seg in array.slice(path, 1, count(path))], _absent) if {
	_builtin(path)
	start := _start_of(null, path)
	is_object(start)
}

_ref_name(path) := "<invalid ref>" if not _builtin(path)

_written(x) := x.literal if _is_literal(x)

_written(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
}

_field_path_name(path) := concat(".", [_segment_name(path[i]) | some i in _names(path)])

_path_name([]) := "it"

_path_name(path) := _visible_path_name(_visible(path)) if path != []

_visible_path_name(path) := concat("", ["item ", _literal_text(path[count(path) - 1] + 1), " of ", _steps_name(array.slice(path, 0, count(path) - 1))]) if {
	is_array(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := concat("", ["item ", _literal_text(path[0] + 1), " of it"]) if {
	is_array(path)
	count(path) == 1
	_index_step(path[0])
} else := _steps_name(path)

_ref_name(path) := concat("", ["item ", _literal_text(path[count(path) - 1] + 1), " of ", _plain_steps_name(array.slice(path, 0, count(path) - 1))]) if {
	_builtin(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := _plain_steps_name(path) if _builtin(path)

_index_step(s) if {
	is_number(s)
	_is_key(s)
}

_steps_name(path) := concat("", array.concat(_it_root(visible), [_step_name(i, visible[i]) | some i in _names(visible)])) if visible := _visible(path)

_it_root(visible) := ["it"] if _index_step(visible[0])

_it_root(visible) := [] if not _index_step(visible[0])

_plain_steps_name(path) := concat("", [_plain_step_name(i, path[i]) | some i in _names(path)])

_step_name(i, p) := _plain_step_name(i, p) if _nameable_step(p)

_step_name(i, p) := concat("", [" named by ", _ref_name(p.ref)]) if {
	i > 0
	_named_by(p)
}

_step_name(i, p) := concat("", [" named by ", _s_key_text(p.named_by)]) if {
	i > 0
	_name_step(p)
}

_step_name(i, p) := concat("", [" named by ", _s_key_text(p.named_by_field)]) if {
	i > 0
	_field_step(p)
}

_step_name(i, p) := concat("", [_step_dot(i), _segment_name(p)]) if {
	not _nameable_step(p)
	not _is_ref(p)
	not _name_step_after(i, p)
}

_name_step_after(i, p) if {
	i > 0
	_name_step(p)
}

_name_step_after(i, p) if {
	i > 0
	_field_step(p)
}

_nameable_step(p) if is_string(p)

_nameable_step(p) if _index_step(p)

_nameable_step(p) if {
	_is_literal(p)
	is_string(p.literal)
}

_plain_step_name(0, "$$input") := "$input"

_plain_step_name(0, "$$params") := "$params"

_plain_step_name(0, step) := step if {
	is_string(step)
	startswith(step, "$")
	not step in {"$$input", "$$params", "$input", "$params"}
	not _parent_name(step)
}

_plain_step_name(0, step) := _s_key_text(substring(step, 1, -1)) if _parent_name(step)

_parent_name(step) if {
	is_string(step)
	startswith(step, "$")
	some p, _ in _parent_names
	step == concat("", ["$", p])
}

_plain_step_name(0, step) := concat("", [_s_dot(step, "left"), _s_key_text(step)]) if {
	is_string(step)
	not startswith(step, "$")
}

_plain_step_name(i, step) := concat("", [".", _s_key_text(step)]) if {
	i > 0
	is_string(step)
}

_plain_step_name(0, step) := concat("", [_s_dot(step.literal, "left"), _s_key_text(step.literal)]) if _string_literal(step)

_plain_step_name(i, step) := concat("", [".", _s_key_text(step.literal)]) if {
	i > 0
	_string_literal(step)
}

_plain_step_name(_, step) := concat("", ["[", _literal_text(step), "]"]) if _index_step(step)

_step_dot(i) := "." if i > 0

_string_literal(p) if {
	_is_literal(p)
	is_string(p.literal)
}

_named_by(p) if {
	_is_ref(p)
	_builtin(p.ref)
	count(p.ref) == 2
	is_string(p.ref[1])
}

_item_path_name(path) := _path_name(path)

_segment_name(p) := _key_name(p) if not is_object(p)

_segment_name(p) := _key_name(p.literal) if _is_literal(p)

_segment_name(p) := concat("", ["[", concat(" and ", sort([concat("", [_key_name(k), "==", _value_text(v)]) | some k, v in p.where])), "]"]) if {
	is_object(p)
	not _is_literal(p)
	not _is_ref(p)
}

_first_dollar_key(0, k) if {
	is_string(k)
	startswith(k, "$")
}

_key_name(k) := k if _plain_key(k)

_key_name(k) := _json_text(k) if {
	is_string(k)
	not _plain_key(k)
}

_key_name(k) := _literal_text(k) if {
	is_number(k)
	_is_key(k)
}

_key_name(k) := "<invalid step>" if {
	not is_string(k)
	not _is_key(k)
}

_plain_key(k) if {
	is_string(k)
	regex.match(`^[A-Za-z_$][A-Za-z0-9_$-]*$`, k)
}

_json_text(v) := concat("", [_json_token(t) | some m in regex.find_all_string_submatch_n(`"(?:[^"\\]|\\.)*"|-?[0-9][0-9.eE+-]*|[^"0-9-]+`, _sorted_json(v), -1); t := m[0]])

_plain_numbers(v) := _plain_json(v, json.marshal(v))

_plain_json(v, text) := v if not regex.match(`[:,\[]\s*(?:-?[0-9]+(?:\.[0-9]+)?[eE]|-?[0-9]+\.[0-9]*0\s*[,\]}]|-0\s*[,\]}])`, text)

else := json.unmarshal(concat("", [_plain_part(m) | some m in regex.find_all_string_submatch_n(`(-?[0-9][0-9.eE+-]*)|(?:"(?:[^"\\]|\\.)*"|[^"0-9-])+`, text, -1)]))

_plain_part(m) := m[0] if m[1] == ""

_plain_part(m) := _plain_number(m[1]) if m[1] != ""

_plain_number(t) := t if regex.match(`^(?:0|-?[1-9][0-9]*|-?(?:0|[1-9][0-9]*)\.[0-9]*[1-9])$`, t)

else := t if not _fits_a_float(json.unmarshal(t))

else := _number_text(t)

_sorted_json(v) := concat("", [_node_json(paths, index, i) | some i, _ in paths]) if {
	index := {p: x | walk(v, [p, x])}
	paths := [pair[1] | some pair in sort([[_written_path(index, p), p] | some p, _ in index])]
}

_written_path(index, p) := [_written_step(index, p, i) | some i, _ in p]

_written_step(index, p, i) := _key_text(p[i]) if is_object(index[array.slice(p, 0, i)])

_written_step(index, p, i) := p[i] if not is_object(index[array.slice(p, 0, i)])

_key_text(k) := k if is_string(k)

_node_json(paths, index, i) := concat("", [
	_node_separator(paths, i),
	_node_key(index, paths[i]),
	_node_body(index[paths[i]]),
	_node_closers(paths, index, i),
])

_node_separator(_, 0) := ""

_node_separator(paths, i) := "" if {
	i > 0
	paths[i - 1] == _parent(paths[i])
}

_node_separator(paths, i) := "," if {
	i > 0
	paths[i - 1] != _parent(paths[i])
}

_parent(p) := array.slice(p, 0, count(p) - 1)

_node_key(index, p) := concat("", [_key_json(p[count(p) - 1]), ":"]) if {
	count(p) > 0
	is_object(index[_parent(p)])
}

_node_key(_, p) := "" if count(p) == 0

_node_key(index, p) := "" if {
	count(p) > 0
	not is_object(index[_parent(p)])
}

_key_json(k) := json.marshal(_key_text(k))

_node_body(x) := "{" if {
	_opens(x)
	is_object(x)
}

_node_body(x) := "[" if {
	_opens(x)
	not is_object(x)
}

_node_body(x) := "{}" if {
	is_object(x)
	count(x) == 0
}

_node_body(x) := "[]" if {
	type_name(x) in {"array", "set"}
	count(x) == 0
}

_node_body(x) := json.marshal(x) if not type_name(x) in {"object", "array", "set"}

_opens(x) if {
	type_name(x) in {"object", "array", "set"}
	count(x) > 0
}

_node_closers(paths, index, i) := "" if _opens(index[paths[i]])

_node_closers(paths, index, i) := concat("", [_closer(index[array.slice(paths[i], 0, k)]) | some k in _closed_depths(paths, i)]) if not _opens(index[paths[i]])

_closed_depths(paths, i) := numbers.range(count(paths[i]) - 1, _next_depth(paths, i)) if count(paths[i]) > _next_depth(paths, i)

_closed_depths(paths, i) := [] if count(paths[i]) <= _next_depth(paths, i)

_next_depth(paths, i) := count(paths[i + 1]) if i + 1 < count(paths)

_next_depth(paths, i) := 0 if i + 1 == count(paths)

_closer(x) := "}" if is_object(x)

_closer(x) := "]" if not is_object(x)

_json_token(t) := concat("", [object.get(_standard_escapes, e, e) | some m in regex.find_all_string_submatch_n(`\\u[0-9a-f]{4}|\\.|[^\\]+`, t, -1); e := m[0]]) if startswith(t, `"`)

_json_token(t) := _number_text(t) if regex.match(`^-?[0-9]`, t)

_json_token(t) := strings.replace_n({",": ", ", ":": ": "}, t) if {
	not startswith(t, `"`)
	not regex.match(`^-?[0-9]`, t)
}

_standard_escapes := {`\u003c`: "<", `\u003e`: ">", `\u0026`: "&", `\u2028`: "\u2028", `\u2029`: "\u2029", `\u0008`: `\b`, `\u000c`: `\f`}

_number_text(t) := _signed(m[1], _decimal(concat("", [m[2], m[3]]), count(m[2]) + _exponent(m[4]))) if {
	m := regex.find_all_string_submatch_n(`^(-?)([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$`, t, 1)[0]
}

_exponent("") := 0

_exponent(e) := to_number(trim_prefix(e, "+")) if e != ""

_decimal(digits, point) := _decimal_text(whole, frac) if {
	left := max([0, 1 - point])
	padded := concat("", [_zeros(left), digits, _zeros(point - count(digits))])
	whole := trim_left(substring(padded, 0, point + left), "0")
	frac := trim_right(substring(padded, point + left, -1), "0")
}

_decimal_text("", "") := "0"

_decimal_text(whole, "") := whole if whole != ""

_decimal_text("", frac) := concat("", ["0.", frac]) if frac != ""

_decimal_text(whole, frac) := concat(".", [whole, frac]) if {
	whole != ""
	frac != ""
}

_signed(_, "0") := "0"

_signed(sign, n) := concat("", [sign, n]) if n != "0"

_zeros(n) := concat("", ["0" | some _ in numbers.range(1, n)]) if n > 0

_zeros(n) := "" if n <= 0

_value_text(x) := _ref_name(x.ref) if _is_ref(x)

_value_text(x) := _literal_text(_written(x)) if {
	not _is_ref(x)
}

_literal_text(v) := "<number out of range>" if _out_of_range(v)

_literal_text(v) := _json_text(v) if not _out_of_range(v)

_text(x) := x if is_string(x)

_text(x) := _literal_text(x) if not is_string(x)

_out_of_range(x) if {
	walk(x, [_, n])
	is_number(n)
	not _fits_a_float(n)
}

_fits_a_float(0)

_fits_a_float(n) if {
	abs(n) >= 2.2250738585072014e-308
	abs(n) <= 1.7976931348623157e308
}

default _leaf_passed(_, _) := false

_leaf_passed(check, subj) if _leaf_op_passed(check.op, check, subj)

_leaf_op_passed("range", check, subj) if {
	v := _value_at(subj, check.path)
	is_number(v)
	lo := _arg(check.min)
	hi := _arg(check.max)
	is_number(lo)
	is_number(hi)
	v >= lo
	v <= hi
}

_leaf_op_passed("excludes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	want := _arg(check.value)
	_items_fit(v, [want])
	not want in v
}

_leaf_op_passed("includes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	want := _arg(check.value)
	_items_fit(v, [want])
	want in v
}

_leaf_op_passed("excludes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	every want in wants {
		not want in v
	}
}

_leaf_op_passed("includes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	every want in wants {
		want in v
	}
}

_leaf_op_passed("in", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	_fits_list(v, vals)
	some want in vals
	want == v
}

_leaf_op_passed("has_type", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	type_name(v) == _json_types[check.type]
}

_json_types := {"list": "array", "string": "string", "number": "number", "boolean": "boolean", "object": "object"}

_leaf_op_passed("not_in", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	_fits_list(v, vals)
	every want in vals {
		want != v
	}
}

_leaf_op_passed("equals", check, subj) if {
	_field(subj, check.path) == _arg(check.value)
}

_leaf_op_passed("present", check, subj) if {
	_value_at(subj, check.path) != null
}

_leaf_op_passed("non_empty_string", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	v != ""
}

_leaf_op_passed("missing", check, subj) if {
	_missing_at(subj, check.path)
	not _params_not_given(check.path)
}

_leaf_op_passed("empty_string_or_list", check, subj) if {
	_value_at(subj, check.path) in {[], ""}
}

_leaf_op_passed("not_empty_string_or_list", check, subj) if {
	v := _value_at(subj, check.path)
	_string_or_list(v)
	count(v) > 0
}

_string_or_list(v) if is_string(v)

_string_or_list(v) if is_array(v)

_missing_at(x, path) if {
	_keys_in(x, path)
	_ := _start_of(x, path)
	_read_state(x, path) in {"absent", "null"}
}

_blocked(start, [k]) if not _can_hold(start, k)

_blocked(start, keys) if {
	count(keys) > 1
	_blocked_under(start, keys, _parent_read(start, keys))
}

_parent_read(start, keys) := v if {
	v := _read_from(start, array.slice(keys, 0, count(keys) - 1))
} else := _absent

_blocked_under(_, keys, parent) if {
	parent != _absent
	not _can_hold(parent, keys[count(keys) - 1])
}

_blocked_under(start, keys, parent) if {
	parent == _absent
	some i, k in keys
	v := _read_from(start, array.slice(keys, 0, i))
	not _can_hold(v, k)
}

_can_hold(v, _) if v == _absent

_can_hold(v, _) if v == null

_can_hold(v, k) if {
	is_object(v)
	is_string(k)
}

_can_hold(v, k) if {
	is_array(v)
	is_number(k)
}

_leaf_op_passed("matches_any", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, v)
}

_leaf_op_passed("not_matches_any", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	every pattern in patterns {
		is_string(pattern)
		not regex.match(pattern, v)
	}
}

_leaf_op_passed("compare", check, subj) if {
	l := _simple_value(subj, check.left)
	r := _simple_value(subj, check.right)
	_compared(check, l, r)
}

_compared(check, l, r) if {
	not "within" in object.keys(check)
	not check.cmp in _list_cmps
	_comparable(l, r)
	_orderable(check.cmp, l)
	_cmp(check.cmp, l, r)
	_at_most_max(check, l)
}

default _at_most_max(_, _) := false

_at_most_max(check, _) if not "max" in object.keys(check)

_at_most_max(check, l) if {
	is_number(l)
	is_number(check.max)
	l <= check.max
}

_compared(check, l, r) if {
	not "within" in object.keys(check)
	check.cmp in _list_cmps
	not "max" in object.keys(check)
	_cmp(check.cmp, l, r)
}

_compared(check, l, r) if {
	"within" in object.keys(check)
	is_number(l)
	is_number(r)
	not "max" in object.keys(check)
	abs(l - r) <= check.within
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
	_cmp(check.cmp, time.parse_rfc3339_ns(l), time.parse_rfc3339_ns(r))
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	is_number(l)
	is_number(r)
	_cmp(check.cmp, l, r)
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	_date_shaped(l)
	_date_shaped(r)
	_cmp(check.cmp, l, r)
}

_wants(values) := _arg(values) if not _value_list(values)

_wants(values) := [_arg(x) | some x in values] if {
	_value_list(values)
	every x in values {
		_readable(x)
	}
}

_readable(x) if _ = _arg(x)

_wanted(v) if {
	_value_list(v)
	count(v) > 0
}

_value_list(v) if is_array(v)

_comparable(l, r) if {
	l != null
	type_name(l) == type_name(r)
}

_orderable(c, _) if c in {"eq", "ne"}

_orderable(c, v) if {
	is_number(v)
	not c in _text_cmps
}

_orderable(c, v) if {
	is_string(v)
	c in _text_cmps
}

_unusable_states(leaf, x) := {"unusable" | _unusable(leaf, x)}

_unusable(leaf, x) if {
	leaf.op == "range"
	v := _found(x, leaf.path)
	not is_number(v)
}

_unusable(leaf, x) if {
	leaf.op in {"matches_any", "not_matches_any"}
	v := _found(x, leaf.path)
	not is_string(v)
}

_unusable(leaf, x) if {
	leaf.op in {"includes", "excludes"}
	v := _found(x, leaf.path)
	not is_array(v)
}

_unusable(leaf, x) if {
	leaf.op in {"includes", "excludes"}
	v := _found(x, leaf.path)
	is_array(v)
	not _items_fit(v, _leaf_wants(leaf))
}

_leaf_wants(leaf) := [_arg(leaf.value)] if "value" in object.keys(leaf)

_leaf_wants(leaf) := vals if {
	vals := _wants(leaf.values)
	_value_list(vals)
}

_items_fit(items, wants) if not _mixed_types(array.concat(items, wants))

_unusable(leaf, x) if {
	leaf.op in {"empty_string_or_list", "not_empty_string_or_list"}
	v := _found(x, leaf.path)
	not _string_or_list(v)
}

_unusable(leaf, x) if {
	leaf.op == "compare"
	not "within" in object.keys(leaf)
	not leaf.cmp in _list_cmps
	l := _simple_found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _usable_pair(leaf.cmp, l, r)
}

_unusable(leaf, x) if {
	leaf.op == "equals"
	v := _found(x, leaf.path)
	w := _arg(leaf.value)
	w != null
	type_name(v) != type_name(w)
}

_unusable(leaf, x) if {
	leaf.op in {"in", "not_in"}
	v := _found(x, leaf.path)
	vals := _wants(leaf.values)
	_value_list(vals)
	not _fits_list(v, vals)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"in", "not_in"}
	l := _found(x, leaf.left)
	r := _found(x, leaf.right)
	is_array(r)
	not _fits_list(l, r)
}

_fits_list(v, vals) if {
	every w in vals {
		_fits(v, w)
	}
}

_fits(_, w) if w == null

_fits(v, w) if type_name(v) == type_name(w)

_mixed_types(vals) if count({type_name(w) | some w in vals; w != null}) > 1

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"matches_any", "not_matches_any"}
	v := _found(x, leaf.left)
	not is_string(v)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"includes", "excludes", "includes_all", "excludes_all"}
	v := _found(x, leaf.left)
	not is_array(v)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"includes", "excludes"}
	l := _found(x, leaf.left)
	r := _found(x, leaf.right)
	is_array(l)
	not _items_fit(l, [r])
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"includes_all", "excludes_all"}
	l := _found(x, leaf.left)
	r := _found(x, leaf.right)
	is_array(l)
	is_array(r)
	not _items_fit(l, r)
}

_unusable(leaf, x) if {
	leaf.op == "compare"
	"within" in object.keys(leaf)
	l := _simple_found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _numbers(l, r)
}

_numbers(l, r) if {
	is_number(l)
	is_number(r)
}

_simple_found(x, side) := _found(x, side) if is_array(side)

_simple_found(_, side) := v if {
	_basic_form(side) == "literal"
	v := _written(side)
	v != null
}

_unusable(leaf, x) if {
	leaf.op == "compare_time"
	l := _found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _timestamps(l, r)
}

_usable_pair(cmp, l, r) if {
	_comparable(l, r)
	_orderable(cmp, l)
}

_timestamps(l, r) if {
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
}

_timestamps(l, r) if {
	is_number(l)
	is_number(r)
}

_timestamps(l, r) if {
	_date_shaped(l)
	_date_shaped(r)
}

_found(x, path) := v if {
	v := _field(x, path)
	v != null
}

_rfc3339_shaped(v) if {
	is_string(v)
	m := regex.find_all_string_submatch_n(`^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$`, v, 1)[0]
	_real_date(m)
}

_date_shaped(v) if {
	is_string(v)
	m := regex.find_all_string_submatch_n(`^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$`, v, 1)[0]
	_real_date(m)
}

_real_date(m) if {
	year := to_number(m[1])
	year >= 1678
	year <= 2261
	to_number(trim_left(m[3], "0")) <= _days_in(year, to_number(trim_left(m[2], "0")))
}

_days_in(_, month) := 31 if month in {1, 3, 5, 7, 8, 10, 12}

_days_in(_, month) := 30 if month in {4, 6, 9, 11}

_days_in(year, 2) := 29 if _leap_year(year)

_days_in(year, 2) := 28 if not _leap_year(year)

_leap_year(year) if {
	year % 4 == 0
	year % 100 != 0
}

_leap_year(year) if year % 400 == 0

default _cmp(_, _, _) := false

_cmp("eq", l, r) if l == r

_cmp("ne", l, r) if l != r

_cmp("gt", l, r) if l > r

_cmp("gte", l, r) if l >= r

_cmp("lt", l, r) if l < r

_cmp("lte", l, r) if l <= r

_cmp("starts_with", l, r) if {
	is_string(l)
	is_string(r)
	startswith(l, r)
}

_cmp("ends_with", l, r) if {
	is_string(l)
	is_string(r)
	endswith(l, r)
}

_cmp("alphabetically_before", l, r) if {
	is_string(l)
	is_string(r)
	l < r
}

_cmp("alphabetically_after", l, r) if {
	is_string(l)
	is_string(r)
	l > r
}

_cmp("in", l, r) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	l in r
}

_cmp("not_in", l, r) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	not l in r
}

_cmp("includes", l, r) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	r in l
}

_cmp("excludes", l, r) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	not r in l
}

_cmp("includes_all", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		want in l
	}
}

_cmp("excludes_all", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		not want in l
	}
}

_cmp("matches_any", l, r) if {
	is_string(l)
	_valid_patterns(r)
	some pattern in r
	regex.match(pattern, l)
}

_cmp("not_matches_any", l, r) if {
	is_string(l)
	_valid_patterns(r)
	every pattern in r {
		not regex.match(pattern, l)
	}
}

_list_cmps := {"in", "not_in", "includes", "excludes", "includes_all", "excludes_all", "matches_any", "not_matches_any"}

_list_cmp(leaf) if {
	leaf.op == "compare"
	leaf.cmp in _list_cmps
	is_array(leaf.right)
}

default _list_flaw(_, _) := set()

_list_flaw(leaf, x) := {_read_state(x, leaf.right)} if {
	_list_cmp(leaf)
	_read_state(x, leaf.right) != "value"
}

_list_flaw(leaf, x) := {"unusable"} if {
	_list_cmp(leaf)
	_read_state(x, leaf.right) == "value"
	not _list_right_usable(leaf.cmp, _value_at(x, leaf.right))
}

_list_flawed(leaf, x) if count(_list_flaw(leaf, x)) > 0

_list_right_usable(cmp, r) if {
	cmp in {"in", "not_in"}
	is_array(r)
	not _mixed_types(r)
}

_list_right_usable(cmp, _) if cmp in {"includes", "excludes"}

_list_right_usable(cmp, r) if {
	cmp in {"includes_all", "excludes_all"}
	_wanted(r)
	not _mixed_types(r)
}

_list_right_usable(cmp, r) if {
	cmp in {"matches_any", "not_matches_any"}
	_valid_patterns(r)
}

_leaf_ops := {"range", "excludes", "includes", "in", "equals", "present", "missing", "non_empty_string", "matches_any", "not_matches_any", "compare", "compare_time"}

_required_fields := {
	"range": {"path", "min", "max"},
	"excludes": {"path"},
	"includes": {"path"},
	"in": {"path", "values"},
	"equals": {"path", "value"},
	"present": {"path"},
	"missing": {"path"},
	"non_empty_string": {"path"},
	"empty_string_or_list": {"path"},
	"not_in": {"path", "values"},
	"has_type": {"path", "type"},
	"all_of": {"checks", "assertions"},
	"sentence_any_of": {"checks", "assertions", "option_of", "places"},
	"every": {"path", "check", "whose", "if_any"},
	"for": {"items", "checks", "assertions"},
	"some": {"path", "check", "whose", "if_any"},
	"not_empty_string_or_list": {"path"},
	"matches_any": {"path", "patterns"},
	"not_matches_any": {"path", "patterns"},
	"compare": {"left", "right", "cmp"},
	"compare_time": {"left", "right", "cmp"},
	"all": {"path", "check"},
	"any": {"path", "check"},
	"any_of": {"options"},
}

_flaw(check, names) := "unusable" if {
	_param_broken(check, names)
} else := "unusable" if {
	_unreadable_input
} else := ""

_unreadable_input if data.ergo_unreadable != []

_check_problems(check, names, here) := {[node[1], msg] |
	some node in _static_nodes(check, names)
	some msg in _node_problems(node[0], node[2], node[3], here)
}

_static_nodes(check, names) := _walk_nodes([[check, [], [], names]])

_walk_nodes(l0) := nodes if {
	l1 := _descend(l0)
	l2 := _descend(l1)
	l3 := _descend(l2)
	l4 := _descend(l3)
	l5 := _descend(l4)
	nodes := array.concat(array.concat(array.concat(l0, l1), array.concat(l2, l3)), array.concat(l4, l5))
}

_descend(level) := [[child[0], array.concat(node[1], child[1]), array.concat(node[2], [child[2]]), child[3]] |
	some node in level
	some child in _children(node[0], node[3])
]

_children(node, names) := array.concat(_where_children(node, names), _assertion_children(node, names))

default _assertion_children(_, _) := []

_assertion_children(node, names) := [[c, ["checks", i], "assertion", names] | some i, c in node.checks] if {
	node.op in {"all_of", "sentence_any_of"}
	is_array(node.checks)
}

_assertion_children(node, names) := array.concat([[node.check, ["check"], "assertion", names]], [[c, ["whose", i], "assertion", names] | some i, c in node.whose]) if {
	_walks(node)
	is_object(node.check)
	is_array(node.whose)
}

_assertion_children(node, names) := array.concat([[c, ["checks", i], "assertion", (names | _for_item_names(node.items, count(node.items)))] | some i, c in node.checks], [[c, ["items", i, "whose", j], "assertion", (names | _for_item_names(node.items, i))] | some i, item in node.items; some j, c in item.whose]) if {
	node.op == "for"
	is_array(node.checks)
	is_array(node.items)
}

_for_item_names(items, n) := {item.as | some item in array.slice(items, 0, n); _valid_name(object.get(item, "as", null))}

_walks(check) if check.op in {"every", "some"}

_node_problems(node, _, _, _) := {"invalid check"} if not is_object(node)

_node_problems(node, kinds, names, here) := (_field_problems(node, here) | _name_problems(node, names)) | _derived_placement_problem(node, kinds, here) if {
	is_object(node)
	not _s_unread(node, here)
}

_node_problems(node, _, _, here) := {p | some p in node["$sentence"]} | _wording_problem(node) if _s_unread(node, here)

_field_problems(node, here) := union({_side_problem(node, here), _within_problem(node), _wording_problem(node), _unknown_fields_problem(node, here), _compare_max_problem(node), _missing_fields_problem(node), _range_bounds_problem(node), _range_order_problem(node), _values_problem(node), _value_or_values_problem(node), _patterns_problem(node), _nested_wrapper_problem(node), _cmp_problem(node, here), _out_of_range_problem(node), _refs_problem(node), _json_problem(node)})

_json_problem(node) := _json_problems(object.remove(_own_fields(node), ["meta"]))

_missing_fields_problem(node) := {concat("", ["missing ", f]) |
	is_string(node.op)
	some f in object.get(_required_fields, node.op, set())
	not f in object.keys(node)
}

_value_or_values_problem(node) := {"missing value or values" |
	node.op in {"includes", "excludes"}
	count({"value", "values"} & object.keys(node)) == 0
} | {"both value and values" |
	node.op in {"includes", "excludes"}
	count({"value", "values"} & object.keys(node)) == 2
}

_unknown_fields_problem(node, here) := {concat("", ["unknown field ", _text(f)]) |
	node.op in object.keys(_op_fields)
	some f in object.keys(node)
	not f in _op_fields[node.op]
	not f in {"op", "description", "meta", "expression", "inputs"}
	not _sentence_max(f, node, here)
}

_sentence_max("max", node, here) if {
	node.op == "compare"
	_s_read(node, here)
}

_compare_max_problem(node) := ({"invalid max" |
	node.op == "compare"
	"max" in object.keys(node)
	not is_number(node.max)
} | {"max needs cmp gte" |
	node.op == "compare"
	"max" in object.keys(node)
	object.get(node, "cmp", null) != "gte"
}) | {"max can't go with within" |
	node.op == "compare"
	"max" in object.keys(node)
	"within" in object.keys(node)
}

_wording_problem(node) := ({"invalid description" |
	"description" in object.keys(node)
	not _has_type("description", node.description)
} | {"invalid meta" |
	"meta" in object.keys(node)
	not _has_type("meta", node.meta)
}) | {concat("", ["meta ", p]) |
	"meta" in object.keys(node)
	is_object(node.meta)
	some p in (_meta_problems(node.meta) - {"number out of range"})
}

_op_fields := object.union(_required_fields, {
	"compare": {"left", "right", "cmp", "within"},
	"excludes": {"path", "value", "values"},
	"includes": {"path", "value", "values"},
	"all": {"path", "check", "each", "as"},
	"any": {"path", "check", "each", "as"},
})

_range_bounds_problem(node) := {concat("", ["invalid ", f]) |
	node.op == "range"
	some f in ["min", "max"]
	f in object.keys(node)
	v := _written(node[f])
	not is_number(v)
}

_range_order_problem(node) := {"min above max" |
	node.op == "range"
	lo := _written(node.min)
	hi := _written(node.max)
	is_number(lo)
	is_number(hi)
	lo > hi
}

_values_problem(node) := ({"invalid values" |
	node.op in {"in", "not_in", "includes", "excludes"}
	"values" in object.keys(node)
	not _value_list(_written(node.values))
	not is_set(_written(node.values))
	not _is_ref(node.values)
} | {"values of mixed types" |
	node.op in {"in", "not_in", "includes", "excludes"}
	vals := _written(node.values)
	_value_list(vals)
	_mixed_types([_written(w) | some w in vals; not _is_ref(w)])
}) | {"empty values" |
	node.op in {"includes", "excludes"}
	_value_list(_written(node.values))
	count(_written(node.values)) == 0
}

_patterns_problem(node) := {"invalid patterns" |
	node.op in {"matches_any", "not_matches_any"}
	"patterns" in object.keys(node)
	not _is_ref(node.patterns)
	not is_set(_written(node.patterns))
	not _written_patterns(_written(node.patterns))
}

_written_patterns(v) if {
	_value_list(v)
	every p in v {
		_written_pattern(p)
	}
}

_written_pattern(p) if _valid_pattern(_written(p))

_nested_wrapper_problem(node) := {concat("", [_wrapper(x), " inside ", f]) |
	node.op in _leaf_ops
	some f in ["value", "values", "patterns", "min", "max"]
	f in object.keys(node)
	walk(node[f], [p, x])
	_wrapper(x)
	p != []
	not _under_literal(node[f], p)
} | {concat("", [kind, " inside where"]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some path in _own_paths(node, f)
	some kind in _wrapped_in_where(path)
}

_wrapped_in_where(path) := {_wrapper(x) |
	is_array(path)
	some seg in path
	is_object(seg)
	is_object(object.get(seg, "where", null))
	some w in seg.where
	walk(w, [p, x])
	p != []
	_wrapper(x)
	not _under_literal(w, p)
}

_wrapper(x) := "ref" if _is_ref(x)

_cmp_problem(node, here) := {"invalid cmp" |
	_two_sided(node)
	"cmp" in object.keys(node)
	not node.cmp in {"eq", "ne", "gt", "gte", "lt", "lte"}
	not _sentence_cmp(node, here)
}

_text_cmps := {"starts_with", "ends_with", "alphabetically_before", "alphabetically_after"}

_sentence_cmp(node, here) if {
	node.op == "compare"
	node.cmp in (_text_cmps | _list_cmps)
	_s_read(node, here)
}

_out_of_range_problem(node) := {"number out of range" | _out_of_range(_own_fields(node))}

_refs_problem(node) := {"invalid ref" |
	some r in _check_refs(_own_fields(node))
	not _known_ref(r)
}

_known_ref(r) if {
	is_array(r)
	r[0] in {"$$input", "$$params"}
	every seg in array.slice(r, 1, count(r)) {
		_is_key(seg)
	}
}

_valid_patterns(v) if {
	_value_list(v)
	every p in v {
		_valid_pattern(p)
	}
}

_own_fields(node) := object.remove(node, ["check", "options"])

_own_paths(node, f) := [node[f]] if {
	f != "inputs"
	f in object.keys(node)
	not _side_field(node, f)
	is_array(node[f])
}

_own_paths(node, f) := _side_paths(node[f]) if _side_field(node, f)

_side_field(node, f) if {
	node.op == "compare"
	f in {"left", "right"}
	f in object.keys(node)
}

_own_paths(node, "inputs") := [p | some spec in node.inputs; some p in _input_paths(spec)] if is_array(node.inputs)

default _own_paths(_, _) := []

_input_paths(spec) := [spec] if not is_object(spec)

_name_problems(node, names) := _unknown_name_problem(node, names)

_unknown_name_problem(node, names) := {concat("", ["unknown alias ", p[0]]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some p in _own_paths(node, f)
	_named(p)
	not _name_known(p[0], names)
}

_name_known(start, _) if start in {"$$input", "$$params"}

_name_known(start, names) if {
	_part_start([start])
	_part_of([start]).of == null
	_part_of([start]).alias in names
}

_name_known(start, names) if {
	_part_start([start])
	_part_of([start]).of != null
	_part_of([start]).of in names
}

_name_known(start, names) if {
	not startswith(start, "$$")
	substring(start, 1, -1) in names
}

default _param_broken(_, _) := false

_param_broken(check, names) if {
	some node in _static_nodes(check, names)
	_node_param_broken(node[0])
}

_node_param_broken(node) if {
	node.op in {"in", "not_in"}
	_is_ref(node.values)
	v := _arg(node.values)
	not _value_list(v)
}

_node_param_broken(node) if {
	node.op in {"in", "not_in", "includes", "excludes"}
	vals := _wants(node.values)
	_value_list(vals)
	_mixed_types(vals)
}

_node_param_broken(node) if {
	node.op in {"includes", "excludes"}
	_is_ref(node.values)
	v := _arg(node.values)
	not _wanted(v)
}

_node_param_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	_is_ref(node.patterns)
	v := _arg(node.patterns)
	not _valid_patterns(v)
}

_valid_pattern(p) if {
	is_string(p)
	regex.is_valid(p)
}

default _op_passed(_, _) := false

_op_passed(check, subj) if {
	_leaf_passed(check, subj)
}

_op_passed(check, subj) if {
	_derived_sides(check) != []
	l := _side_value(subj, check.left)
	r := _side_value(subj, check.right)
	_compared(check, l, r)
}

default _check_passed(_, _, _) := false

_check_passed(check, subj, "") if _op_passed(check, subj)

_read_paths(check) := [side | some side in [check.left, check.right]; is_array(side)] if _two_sided(check)

_read_paths(check) := [check.path] if {
	not _two_sided(check)
	check.path
}

_read_state(subj, path) := _plain_read_state(subj, path, object.get(subj, _plain_keys(path), _absent)) if {
	is_object(subj)
	_plain_path(path)
} else := _any_read_state(subj, path)

_plain_read_state(subj, path, v) := "value" if {
	v != _absent
	v != null
}

else := "null" if v == null

else := "unusable" if _blocked(subj, path)

else := "absent"

default _any_read_state(_, _) := "absent"

_any_read_state(subj, path) := "not_an_object" if {
	start := _start_of(subj, path)
	not is_object(start)
	not _reads_itself(path)
	not _position_first(path)
	not _params_not_given(path)
}

_reads_itself(path) if _keys_of(path) == []

_reads_subject(path) if path == []

_reads_subject(path) if _list_subject_path(path)

_list_subject_path(path) if {
	is_array(path)
	count(path) > 0
	_index_step(path[0])
}

_position_first(path) if _index_step(_keys_of(path)[0])

_any_read_state(_, path) := _name_step_state(path) if _name_step_state(path)

_any_read_state(subj, path) := s if {
	not _name_step_state(path)
	s := _field_step_state(subj, path)
}

_field_step_state(subj, path) := "not_an_object" if {
	_has_field_step(path)
	not is_object(subj)
} else := "null" if {
	some seg in path
	_field_step(seg)
	subj[seg.named_by_field] == null
} else := "unusable" if {
	some seg in path
	_field_step(seg)
	v := subj[seg.named_by_field]
	not is_string(v)
}

_name_step_state(path) := "null" if {
	_has_name_step(path)
	some step in path
	_name_step(step)
	input["ergo/names"][step.named_by] == null
} else := "unusable" if {
	_has_name_step(path)
	some step in path
	_name_step(step)
	not is_string(input["ergo/names"][step.named_by])
}

_any_read_state(subj, path) := "null" if _resolved(subj, path) == null

_any_read_state(subj, path) := "unusable" if {
	start := _start_of(subj, path)
	is_object(start)
	_blocked(start, _keys_in(subj, path))
}

_any_read_state(subj, path) := "unusable" if {
	_position_first(path)
	start := _start_of(subj, path)
	start != null
	not is_array(start)
	not is_object(start)
}

_any_read_state(subj, path) := "value" if {
	v := _resolved(subj, path)
	v != _absent
	v != null
}

_is_collection(v) if is_array(v)

_is_collection(v) if is_object(v)

_cause_precedence := ["not_an_object", "ambiguous", "unusable", "absent", "null"]

_worst_read(subj, check) := _worst_or_value(_check_states(check, subj)) if not _unreadable_ref(check)

_worst_or_value(states) := c if {
	c := _worst_of(states)
} else := "value"

_check_states(check, subj) := _answered(check, subj, {_read_state(subj, p) | some p in _read_paths(check)}) | _unusable_states(check, subj) if {
	not _list_flawed(check, subj)
}

_check_states(check, subj) := _list_flaw(check, subj) if {
	_list_flawed(check, subj)
}

_group_cause(causes) := "value" if {
	"missing" in causes
} else := _worst_or_value(causes)

_leaf_cause(leaf, x) := "satisfied" if {
	_leaf_passed(leaf, x)
} else := "missing" if {
	_asks_presence(leaf, x)
	_read_state(x, leaf.path) in {"absent", "null"}
} else := _worst_or_value(_list_flaw(leaf, x)) if {
	_list_flawed(leaf, x)
} else := _worst_or_value({_read_state(x, p) | some p in _leaf_paths(leaf)} | _unusable_states(leaf, x))

_answered(check, x, states) := {_presence_state(s) | some s in states} if _asks_presence(check, x)

_answered(check, x, states) := states if not _asks_presence(check, x)

default _asks_presence(_, _) := false

_asks_presence(check, x) if {
	check.op == "present"
	_keys_in(x, check.path)
	_ := _start_of(x, check.path)
	not _params_not_given(check.path)
}

_params_not_given(path) if {
	path[0] == "$$params"
	not is_object(data.ergo_params)
}

_presence_state(s) := "missing" if s in {"absent", "null"}

_presence_state(s) := s if not s in {"absent", "null"}

_worst_read(_, check) := _worst_of({_used_ref_state(check, r) | some r in _check_refs(check)}) if _unreadable_ref(check)

default _unreadable_ref(_) := false

_unreadable_ref(check) if {
	some r in _check_refs(check)
	_used_ref_state(check, r) != "value"
}

_worst_of(states) := _cause_precedence[i] if {
	i := min([j |
		some j, c in _cause_precedence
		c in states
	])
}

_row_cause(_, _, flaw) := flaw if flaw != ""

_row_cause(check, subj, "") := c if {
	_derived_once(check)
	c := _derived_eval(check, subj).cause
} else := _readable_cause(check, subj)

_readable_cause(check, subj) := "satisfied" if _op_passed(check, subj)

else := _worst_read(subj, check)

_check_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
}

_step_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
	count(p) >= 2
	p[count(p) - 2] in {"path", "left", "right", "each"}
	is_number(p[count(p) - 1])
}

_used_ref_state(check, r) := "unusable" if _wrong_step(check, r)

_used_ref_state(check, r) := _ref_state(r) if not _wrong_step(check, r)

_wrong_step(check, r) if {
	r in _step_refs(check)
	_ref_state(r) == "value"
	not _is_key(_ref_read(r))
}

_under_literal(check, p) if {
	some i, seg in p
	seg == "literal"
	walk(check, [q, w])
	q == array.slice(p, 0, i)
	_is_literal(w)
}

default _ref_state(_) := "absent"

_ref_state(r) := "null" if _ref_read(r) == null

_ref_state(r) := "unusable" if {
	_ref_read(r) == _absent
	_blocked(_start_of(null, r), [seg | some seg in array.slice(r, 1, count(r))])
}

_ref_state(r) := "value" if {
	v := _ref_read(r)
	v != _absent
	v != null
}

default _ref_shown(_) := null

_ref_shown(r) := v if {
	v := _ref_read(r)
	v != _absent
}

_ref_inputs(check) := [{"name": pair[0], "value": pair[1], "locations": pair[2]} | some pair in sort({[_ref_name(r), _ref_shown(r), _ref_locations(r)] | some r in _check_refs(check)})]

_ref_locations(r) := [_ref_at(r)] if _builtin(r)

_ref_locations(r) := [] if not _builtin(r)

_ref_at(r) := _pointer(_start_at(r), start, [_key(seg) | some seg in array.slice(r, 1, count(r))]) if {
	start := _start_of(null, r)
}

_verdict_cause(passed) := "satisfied" if passed

_verdict_cause(passed) := "value" if not passed

_applies_cause(_, true) := "satisfied"

_applies_cause(evals, false) := _scope_cause({e.cause | some e in evals; not e.passed})

_scope_cause(causes) := "value" if {
	"missing" in causes
} else := "value" if {
	causes == {"value"}
} else := _worst_of(causes)

_filter_cause(check, subj, flaw) := "missing" if _answers_presence(check, subj, flaw)

_filter_cause(check, subj, flaw) := _row_cause(check, subj, flaw) if not _answers_presence(check, subj, flaw)

default _answers_presence(_, _, _) := false

_answers_presence(check, subj, "") if {
	check.op == "present"
	_keys_in(subj, check.path)
	_ := _start_of(subj, check.path)
	not _unreadable_ref(check)
	not _params_not_given(check.path)
	_read_state(subj, check.path) in {"absent", "null"}
}

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

default _two_sided(_) := false

_two_sided(check) if check.op in {"compare", "compare_time"}

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
}

_check_inputs(subj, check) := _derived_eval(check, subj).inputs if {
	_derived_once(check)
}

_check_inputs(subj, check) := [_path_input(subj, check.path)] if {
	not check.inputs
	not _two_sided(check)
	is_array(check.path)
}

_leaf_paths(leaf) := [side | some side in [leaf.left, leaf.right]; is_array(side)] if _two_sided(leaf)

_leaf_paths(leaf) := [leaf.path] if {
	not _two_sided(leaf)
	leaf.path
}

_row_inputs(subj, check) := _with_key_fields(subj, check, _check_inputs(subj, check))

_with_key_fields(subj, check, inputs) := _once(array.concat(inputs, [_path_input(subj, [f]) | some f in _key_fields(check)])) if count(_key_fields(check)) > 0

else := inputs

_key_fields(check) := sort({seg.named_by_field |
	is_object(check)
	some p in array.concat([object.get(check, "path", [])], array.concat(_side_paths(object.get(check, "left", null)), _side_paths(object.get(check, "right", null))))
	is_array(p)
	some seg in p
	_field_step(seg)
})

_once(xs) := [x | some i, x in xs; not x in array.slice(xs, 0, i)]

_check_def(check, here) := _with_refs({"description": _reported_description(check), "meta": _reported_meta(check), "expression": check.expression}, check) if _s_read(check, here)

_check_def(check, here) := _with_refs(object.union(object.remove(_described(check), {"description", "meta"}), {"description": _reported_description(check), "meta": _reported_meta(check)}), check) if not _s_read(check, here)

_with_refs(def, checked) := object.union(def, {"$refs_of": checked}) if {
	data.ergo_reading == true
	count(_check_refs(checked)) > 0
} else := object.union(def, {"$refs": _ref_inputs(checked)}) if count(_check_refs(checked)) > 0

_with_refs(def, checked) := def if count(_check_refs(checked)) == 0

_described(check) := {"expression": _expression_of(check)} if not is_object(check)

_chain_part(req) if data.ergo_subject_sentences.from_parts[req.subject]

_chain_part_name(req) := concat("", [_s_key_text(data.ergo_subject_sentences.chains[req.subject]), ".", _s_key_text(alias), _tail_after_part(req, alias)]) if alias := data.ergo_subject_sentences.from_parts[req.subject]

_tail_after_part(req, alias) := concat("", [_step_name(i + 2, rest[i]) | some i in _names(rest)]) if {
	rest := array.slice(_from_of(req), count(data.ergo_subject_sentences.parts[data.ergo_subject_sentences.chains[req.subject]][alias].from.path), count(_from_of(req)))
}

_matching_count_name(req) := concat("", ["count(matching(", _from_text(req), "))"])

_from_text(req) := concat("", [_every_word(req), _from_name(_from_path(req))]) if {
	_from_well_formed(req)
	_from_path(req) != []
	not _chained(req)
	not _chain_part(req)
}

_every_word(req) := "every " if _every_from(req)

else := ""

_from_text(req) := _chain_part_name(req) if {
	_from_well_formed(req)
	_from_path(req) != []
	_chain_part(req)
}

_from_text(req) := _path_name(array.concat([data.ergo_subject_sentences.chains[req.subject]], _from_path(req))) if {
	_from_well_formed(req)
	_chained(req)
	not _chain_part(req)
}

_from_text(req) := "$input" if {
	_from_well_formed(req)
	_from_path(req) == []
}

_from_text(req) := "<invalid from>" if not _from_well_formed(req)

_from_name(p) := _path_name(_from_steps(p))

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

_repeated_ids_name(req) := concat(" ", ["repeated", _text(_subject_type_of(req)), "ids"])

_well_formed_def := {"$well_formed": {
	"description": "The requirement is written correctly",
	"expression": "count(problems) == 0",
}}

default _well_formed_named(_, _) := false

_well_formed_named(req, name) if {
	is_string(name)
	_well_formed(req)
}

_name_problem_inputs(name) := [] if is_string(name)

_name_problem_inputs(name) := [{"name": "requirement name", "value": ["not a string"], "locations": []}] if not is_string(name)

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

_own_check_problems(req) := {_placed_problem(req, f, n, check, p) |
	some f in ["applies_to", "checks"]
	some n, check in _req_checks(req, f)
	here := _s_written_here(req, f, n)
	found := _check_problems(check, _from_names(req, here), here)
	some p in found
}

_ancestors_of(req) := _s_ancestors(req.subject, data.ergo_subject_sentences.chains) if _chained(req)

else := []

_req_checks(req, "applies_to") := _applies_to_of(req)

_req_checks(req, "checks") := _checks_of(req)

_problem_at(req, "applies_to", n, _) := ["subjects", _resolution_of(req).filter_owners[n], "from"]

_problem_at(_, "checks", n, at) := array.concat(["checks", n], at)

_placed_problem(req, f, n, check, p) := [_field_path_name(["checks", n]), concat("", [check.places[p[0][1]], ": ", p[1]])] if {
	f == "checks"
	check.op == "sentence_any_of"
	count(p[0]) > 1
	p[0][0] == "checks"
} else := [_field_path_name(_problem_at(req, f, n, p[0])), p[1]]

_from_names(req, here) := ({n |
	_from_well_formed(req)
	n := _each_step(req).each_as
} | {a | _chained(req); here; some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)}) | {a |
	is_string(object.get(req, "subject", null))
	some a, _ in object.get(object.get(data.ergo_subject_sentences, "parts", {}), req.subject, {})
}

_well_formed_inputs(req) := array.concat(
	array.concat(
		[{"name": "count(checks)", "value": count(_checks_of(req)), "locations": []}],
		_echo(req, "require", _require_of(req)),
	),
	array.concat(array.concat(array.concat(_not_an_object_inputs(req), _field_problem_inputs(req)), _check_problem_inputs(req)), _policy_problems),
)

_echo(req, f, v) := [{"name": _field_name(f), "value": v, "locations": []}] if not _has_problems(req, f)

_echo(req, f, _) := [] if _has_problems(req, f)

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
			not name in _reserved_checks
			def := _check_def(check, _s_written_here(req, "checks", name))
		},
		object.union(_min_subjects_def(req), _unique_ids_def(req)),
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

_anchored_all(xs, at) := [object.union(x, {"locations": [replace(l, "~~", at) | some l in x.locations]}) | some x in xs]

_subject_rows(entry, ref, req, req_name, flaws, prepared) := [row |
	some check_name in _names(prepared)
	row := object.union(
		{
			"requirement": req_name,
			"subject": ref,
			"check": check_name,
		},
		_anchored(_outcome(req, prepared[check_name], flaws[check_name], entry.subject), entry.at),
	)
]

_well_formed_row(req, name, parts) := v if {
	v := parts.well_formed
} else := _well_formed_row_of(req, name)

_well_formed_row_of(req, req_name) := row if {
	passed := _well_formed_named(req, req_name)
	row := {
		"requirement": req_name,
		"subject": _req_subject_ref(req),
		"check": "$well_formed",
		"inputs": array.concat(_name_problem_inputs(req_name), _well_formed_inputs(req)),
		"passed": passed,
		"cause": _verdict_cause(passed),
	}
}

_min_subjects_row(doc, req, req_name, matching, at) := object.union(
	{
		"requirement": req_name,
		"subject": _req_subject_ref(req),
		"check": "$min_subjects",
		"inputs": array.concat([{"name": _subject_count_name(req), "value": matching, "locations": at}], data.ergo_unreadable),
		"passed": _enough_subjects(doc, req, matching),
		"cause": _min_subjects_cause(doc, req, matching),
	},
	_every_failed_items(doc, req),
)

_every_failed_items(doc, req) := {"failed_items": [{"path": _path_name(f.path), "item": _path_name(f.item), "cause": f.cause, "value": f.value, "locations": _fail_locations(f)} |
	fails := _every_walk(doc, _from_keys(req)).fails
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
]} if {
	_every_from(req)
	is_object(doc)
	_from_well_formed(req)
	not _from_unreadable(req)
} else := {"failed_items": []} if _every_from(req)

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
		some l in _id_locations(entry, req)
	]}],
	"passed": count(repeated) == 0,
	"cause": _verdict_cause(count(repeated) == 0),
} if {
	repeated := _repeated_ids(refs)
}

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
		"inputs": _tie_sorted(_anchored_all(_applies_inputs(evals, req), entry.at)),
		"passed": matched,
		"cause": _applies_cause(evals, matched),
	},
	_applies_failures(evals, req, entry.at),
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
	"prepared": {n: _with_ref_answer(check) | some n, check in _checks_of(req)},
}

_evaluation_with(doc, written, name, fixed) := {
	"min_subjects": [_min_subjects_row(doc, req, name, count(matching), [m.at | some m in matching])],
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
	refs := {i: _entry_ref(entry, req) | some i, entry in raw}
	evals := {i: _applies_evals(req, entry.subject, fixed.filter_flaws) | some i, entry in raw}
	matches := {i: _subject_matches(evals[i], req) | some i, _ in raw}
	applies := _applies_rows(raw, refs, evals, req, name)
	matching := [raw[i] | some i, _ in raw; matches[i]]
	groups := _subject_row_groups(matching, req, name, fixed.check_flaws, fixed.prepared)
}

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
	some group in groups
	_all_passed(group)
}

_required("some", groups) if count(groups) == 0

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

_causes(status, _) := [] if status in {"met", "not_applicable"}

_causes("not_met", e) := [{"cause": cause, "rows": n} |
	some cause in array.concat(_cause_precedence, ["value"])
	n := count([row |
		some row in _requirement_rows(e)
		row.passed == false
		not _out_of_scope_row(row)
		row.cause == cause
	])
	n > 0
]

_requirement_rows(e) := array.concat(
	array.concat(array.concat([e.well_formed], array.concat(e.min_subjects, e.unique_ids)), e.applies),
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

_results(policy, evaluations) := array.concat(
	array.concat(
		[evaluations[name].well_formed | some name in _names(policy)],
		array.concat(
			[row | some name in _names(policy); some row in evaluations[name].min_subjects],
			[row | some name in _names(policy); some row in evaluations[name].unique_ids],
		),
	),
	array.concat(
		[_inputs_once(row) | some name in _names(policy); some row in evaluations[name].applies],
		[_inputs_once(row) | some name in _names(policy); some group in evaluations[name].subject_rows; some row in group],
	),
)

_inputs_once(row) := object.union(row, {"inputs": _once(row.inputs)})

_names(x) := sort(object.keys(x)) if is_object(x)

_names(x) := [i | some i, _ in x] if is_array(x)

_names(x) := sort(x) if is_set(x)

report(doc, policy, params) := _run(doc, c.policy, _from_compiled(c), params) if {
	c := _compiled(policy)
} else := _run(doc, c.policy, _stale_read(c), params) if {
	c := _stale_compiled(policy)
} else := _run(doc, policy, _read(policy), params)

compile(policy) := policy if _compiled(policy)

else := policy if _stale_compiled(policy)

else := {"ergo/compiled": object.union({"policy": policy, "engine": _engine}, _to_compiled(rd))} if rd := _read_ahead(policy)

else := policy

_read(policy) := {"subjects": subjects, "subject_sentences": subject_sentences, "reqs": reqs, "sentences": sentences, "resolved": resolved, "ahead": {}} if {
	raw := _section(policy, "requirements")
	written_subjects := _section(policy, "subjects")
	parts := _p_parts(written_subjects)
	reads := _s_from_reads(written_subjects, parts)
	subjects := _s_subjects(_s_new_subjects(written_subjects), reads, parts)
	subject_sentences := _s_subject_sentences(written_subjects, reads, parts)
	reqs := _p_requirements(raw, subject_sentences.chains, parts)
	sentences := _s_sentences(raw, reqs)
	resolved := _resolved_subjects with data.ergo_subjects as subjects with data.ergo_subject_sentences as subject_sentences
}

_s_new_subjects(subjects) := {name: _s_new_subject(def) | some name, def in subjects} if is_object(subjects)

else := subjects

_s_new_subject(def) := object.union(object.remove(def, ["applies_to", "of", "from", "identified_by"]), {f: _s_new_field(def[f]) | some f in ["from", "identified_by"]; f in object.keys(def)}) if is_object(def)

else := def

_s_new_field(v) := v if is_string(v)

else := false

_read_ahead(policy) := object.union(rd, {"ahead": ahead}) if {
	rd := _read(policy)
	ahead := {
		"policy_problems": _policy_problem_inputs(policy),
		"listed": _reported_subjects(_section(policy, "subjects"), rd.reqs),
		"requirements": {name: {"well_formed": _well_formed_row_of(req, name), "defs": _requirement_check_defs(req)} | some name, req in rd.reqs},
	} with data.ergo_policy_problems as _policy_problem_inputs(policy) with data.ergo_document as {} with data.ergo_params as {} with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_reading as true with data.ergo_unreadable as [] with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences with input as {"ergo/names": {}}
}

_to_compiled(rd) := {
	"subjects": rd.subjects,
	"subject_sentences": object.union(object.remove(rd.subject_sentences, ["lines"]), {
		"every": sort(rd.subject_sentences.every),
		"narrowed": sort(rd.subject_sentences.narrowed),
		"filters": sort(rd.subject_sentences.filters),
		"has_problems": {n: sort(ps) | some n, ps in rd.subject_sentences.has_problems},
	}),
	"requirements": rd.reqs,
	"sentences": sort(rd.sentences),
	"resolved": {n: object.union(r, {"members": sort(r.members), "problems": sort(r.problems)}) | some n, r in rd.resolved},
	"ahead": rd.ahead,
}

_from_compiled(c) := {
	"subjects": c.subjects,
	"subject_sentences": object.union(c.subject_sentences, {
		"every": {x | some x in c.subject_sentences.every},
		"narrowed": {x | some x in c.subject_sentences.narrowed},
		"filters": {x | some x in c.subject_sentences.filters},
		"has_problems": {n: {p | some p in ps} | some n, ps in c.subject_sentences.has_problems},
	}),
	"reqs": c.requirements,
	"sentences": {x | some x in c.sentences},
	"resolved": {n: object.union(r, {"members": {m | some m in r.members}, "problems": {p | some p in r.problems}}) | some n, r in c.resolved},
	"ahead": c.ahead,
}

_stale_compiled(x) := c if {
	is_object(x)
	object.keys(x) == {"ergo/compiled"}
	c := x["ergo/compiled"]
	is_object(c)
	"policy" in object.keys(c)
	object.get(c, "engine", null) != _engine
}

_stale_read(c) := object.union(_read(c.policy), {"ahead": {"policy_problems": array.concat([_engine_problem(object.get(c, "engine", null))], _policy_problem_inputs(c.policy))}})

_engine_problem(null) := {"name": "ergo/compiled engine", "value": ["missing"], "locations": []}

_engine_problem(e) := {"name": "ergo/compiled engine", "value": [concat("", ["compiled by another engine, expected ", _engine.name, " ", _engine.version])], "locations": []} if e != null

_compiled(x) := c if {
	is_object(x)
	object.keys(x) == {"ergo/compiled"}
	c := x["ergo/compiled"]
	is_object(c)
	c.engine == _engine
	every f in ["policy", "subjects", "requirements"] {
		f in object.keys(c)
	}
	every f in ["resolved", "subject_sentences", "ahead"] {
		is_object(object.get(c, f, null))
	}
	is_array(object.get(c, "sentences", null))
	every f in ["every", "narrowed", "filters"] {
		is_array(object.get(c.subject_sentences, f, null))
	}
	is_object(object.get(c.subject_sentences, "has_problems", null))
	every f in ["listed", "requirements"] {
		is_object(object.get(c.ahead, f, null))
	}
	is_array(object.get(c.ahead, "policy_problems", null))
}

_ahead_check_defs(req, parts) := {n: _ahead_refs(def) | some n, def in parts.defs} if {
	parts.defs
} else := _requirement_check_defs(req)

_ahead_refs(def) := object.union(object.remove(def, ["$refs_of"]), {"$refs": _ref_inputs(def["$refs_of"])}) if "$refs_of" in object.keys(def)

else := def

_listed_of(policy, rd) := v if {
	v := rd.ahead.listed
} else := _reported_subjects(_section(policy, "subjects"), rd.reqs)

_policy_problems_of(policy, rd) := v if {
	v := rd.ahead.policy_problems
} else := _policy_problem_inputs(policy)

_run(doc, policy, rd, params) := r if {
	raw := _section(policy, "requirements")
	reqs := rd.reqs
	unreadable := _unreadable_inputs(doc, params)
	written := object.union(_report_of(doc, reqs, object.get(rd.ahead, "requirements", {})), {"description": _reported_description(policy), "meta": _reported_meta(policy), "subjects": _listed_of(policy, rd)}) with data.ergo_reading as false with data.ergo_policy_problems as _policy_problems_of(policy, rd) with data.ergo_document as doc with data.ergo_params as params with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_unreadable as unreadable with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences with input as {"ergo/names": {}}
	used := _used_subjects(reqs, rd.subjects, rd.resolved)
	r := object.union(_reported(written, unreadable, [raw, used]), {"ergo": _spec, "engine": _engine})
}

version := "0.2.0-dev"

_engine := {"name": "ergo.rego", "version": version}

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
	chains := object.get(data.ergo_subject_sentences, "chains", {})
	follows := object.get(data.ergo_subject_sentences, "follows", {})
}

_listed_subject_names(reqs) := graph.reachable(_listed_subject_graph, {req.subject |
	some req in reqs
	_reported_subject_name(req) != null
})

_reported_subjects(written, reqs) := {name: _reported_subject(name, written[name]) | some name in _listed_subject_names(reqs)} if is_object(written)

_reported_subjects(written, _) := {} if not is_object(written)

_reported_subject(name, def) := {
	"description": _reported_description(def),
	"from": _subject_from_text(name, def),
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

_subject_from_text(name, null) := _path_name([name])

_subject_from_text(_, def) := "<invalid from>" if {
	def != null
	not is_object(def)
}

_subject_from_text(name, def) := "<invalid from>" if {
	is_object(def)
	_subject_from_unreadable(name, def)
}

_subject_from_text(name, def) := _subject_text(name, def) if {
	is_object(def)
	not _subject_from_unreadable(name, def)
}

default _subject_from_invalid(_) := false

_subject_from_invalid(name) if {
	some p in data.ergo_resolved[name].problems
	some f in ["from", "of"]
	p[0] == ["subjects", name, f]
}

_subject_from_unreadable(name, _) if _subject_from_invalid(name)

_subject_from_unreadable(name, def) if not _subject_readable(name, def)

_subject_readable(name, def) if _subject_text(name, def)

_subject_text(name, def) := _s_from_line_text(data.ergo_subject_sentences.lines[name]) if {
	is_string(object.get(def, "from", null))
	object.keys(def) & {"of", "applies_to"} == set()
}

_subject_text(name, def) := _path_name([name]) if {
	not "from" in object.keys(def)
	object.keys(def) & {"of", "applies_to"} == set()
}

_subject_id_text(name) := _id_text(data.ergo_resolved[name].def.identified_by) if {
	"identified_by" in object.keys(data.ergo_resolved[name].def)
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

_spec := "v0.2"

_is_version(v) if regex.match(`^v[0-9]+\.[0-9]+(-dev)?$`, v)

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
		"causes": _causes(status, evaluations[name]),
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
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
}

_evaluated(doc, req, name, parts) := e if {
	not _chained(req)
	e := _evaluation(doc, req, name, parts)
}

_evaluated(doc, req, name, parts) := _chain_evaluation(req, name, _parent_pick(doc, req), parts) if {
	_chained(req)
	not _grand_chained(req)
}

_evaluated(doc, req, name, parts) := _grand_evaluation(req, name, _parent_pick_of(doc, {"subject": grand, "checks": {}}), parent, grand, _fixed(req), parts) if {
	_grand_chained(req)
	parent := data.ergo_subject_sentences.chains[req.subject]
	grand := data.ergo_subject_sentences.chains[parent]
}

_grand_chained(req) if {
	_chained(req)
	data.ergo_subject_sentences.chains[req.subject] in object.keys(data.ergo_subject_sentences.chains)
}

_grand_evaluation(req, name, gpick, _, _, _, parts) := _no_parent_evaluation(req, name, gpick.cause, parts) if "cause" in object.keys(gpick)

_grand_evaluation(req, name, gpick, parent, grand, fixed, parts) := _grand_branches(req, name, [e | some g in gpick.parents; some e in _grand_branch(req, name, parent, grand, g, fixed)], parts) if "parents" in object.keys(gpick)

_grand_branches(req, name, es, parts) := _parents_evaluation(req, name, es, parts) if count(es) > 0

else := _no_parent_evaluation(req, name, "none", parts)

_grand_branch(req, name, _, grand, g, fixed) := [_parent_evaluation(req, name, grand, g, fixed)] if "cause" in object.keys(g)

_grand_branch(req, name, parent, grand, g, fixed) := _grand_children(req, name, parent, grand, g, pick, fixed) if {
	"subject" in object.keys(g)
	pick := _parent_pick_of(g.subject, {"subject": parent, "checks": {}}) with data.ergo_in as {grand: g.id} with data.ergo_parent as {grand: g.subject} with input as {"ergo/names": {"$at": {"doc": g.at, "names": {grand: g.at}}}}
}

_grand_children(req, name, _, grand, g, pick, fixed) := [_parent_evaluation(req, name, grand, {"id": g.id, "cause": pick.cause}, fixed)] if "cause" in object.keys(pick)

_grand_children(req, name, parent, grand, g, pick, fixed) := [_grandchild_evaluation(req, name, parent, grand, g, p, fixed) | some p in pick.parents] if "parents" in object.keys(pick)

_grandchild_evaluation(req, name, parent, grand, g, p, fixed) := e if {
	"subject" in object.keys(p)
	e := _evaluation_with(p.subject, req, name, fixed) with data.ergo_in as {grand: g.id, parent: p.id} with data.ergo_parent as {grand: g.subject, parent: p.subject} with input as {"ergo/names": {"$at": {"doc": p.at, "names": {grand: g.at, parent: p.at}}}}
}

_grandchild_evaluation(req, name, parent, grand, g, p, _) := {
	"min_subjects": [row],
	"unique_ids": [],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
} if {
	"cause" in object.keys(p)
	row := _parent_min_subjects_row(req, name, p.cause) with data.ergo_in as {grand: g.id, parent: p.id}
}

_chain_evaluation(req, name, pick, parts) := _parents_evaluation(req, name, [_parent_evaluation(req, name, pick.parent, p, fixed) | some p in pick.parents], parts) if {
	fixed := _fixed(req)
	"parents" in object.keys(pick)
	count(pick.parents) > 0
}

_chain_evaluation(req, name, pick, parts) := _no_parent_evaluation(req, name, "none", parts) if {
	"parents" in object.keys(pick)
	count(pick.parents) == 0
}

_chain_evaluation(req, name, pick, parts) := _no_parent_evaluation(req, name, pick.cause, parts) if "cause" in object.keys(pick)

_no_parent_evaluation(req, name, cause, parts) := object.union(_evaluation({}, req, name, parts), {
	"min_subjects": [_parent_min_subjects_row(req, name, cause)],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
})

_parent_evaluation(req, name, parent, p, fixed) := e if {
	"subject" in object.keys(p)
	e := _evaluation_with(p.subject, req, name, fixed) with data.ergo_in as {parent: p.id} with data.ergo_parent as {parent: p.subject} with input as {"ergo/names": {"$at": {"doc": p.at, "names": {parent: p.at}}}}
}

_parent_evaluation(req, name, parent, p, _) := {
	"min_subjects": [row],
	"unique_ids": [],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
} if {
	"cause" in object.keys(p)
	row := _parent_min_subjects_row(req, name, p.cause) with data.ergo_in as {parent: p.id}
}

_parents_evaluation(req, name, es, parts) := {
	"well_formed": _well_formed_row(req, name, parts),
	"min_subjects": [row | some e in es; some row in e.min_subjects],
	"unique_ids": [row | some e in es; some row in e.unique_ids],
	"applies": [row | some e in es; some row in e.applies],
	"subject_rows": [group | some e in es; some group in e.subject_rows],
	"total": sum([e.total | some e in es]),
	"matching": sum([e.matching | some e in es]),
	"scope_readable": every_readable,
	"rows_complete": every_complete,
} if {
	every_readable := count([e | some e in es; not e.scope_readable]) == 0
	every_complete := count([e | some e in es; not e.rows_complete]) == 0
}

_chained(req) if {
	is_object(req)
	is_string(object.get(req, "subject", null))
	req.subject in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
}

_parent_pick(doc, req) := pick if {
	parent := data.ergo_subject_sentences.chains[req.subject]
	preq := {"subject": parent, "checks": {}}
	pick := _parent_pick_of(doc, preq)
}

_parent_pick_of(doc, preq) := {"cause": c} if {
	c := _target_cause(doc, preq)
} else := {"cause": _from_cause(preq)} if {
	_from_well_formed(preq)
	_from_unreadable(preq)
} else := r if {
	raw := _raw_entries(doc, preq)
	flaws := {n: flaw |
		some n, check in _applies_to_of(preq)
		here := _s_written_here(preq, "applies_to", n)
		flaw := _flaw(check, _from_names(preq, here))
	}
	refs := {i: _entry_ref_of(entry, preq) | some i, entry in raw}
	evals := {i: _applies_evals(preq, entry.subject, flaws) | some i, entry in raw}
	applies := {i: {"passed": matched, "cause": _applies_cause(evals[i], matched)} |
		some i, _ in raw
		matched := _subject_matches(evals[i], preq)
	}
	r := _parent_pick_from(raw, refs, applies, preq)
}

_parent_pick_from(raw, refs, applies, preq) := {"parent": preq.subject, "parents": [p |
	some i, entry in raw
	some p in _parent_of(entry, refs[i], applies, i, preq)
]}

_parent_of(entry, ref, _, _, preq) := [{"subject": entry.subject, "id": ref.id, "at": entry.at}] if _size(_applies_to_of(preq)) == 0

_parent_of(entry, ref, applies, i, preq) := [{"subject": entry.subject, "id": ref.id, "at": entry.at}] if {
	_size(_applies_to_of(preq)) > 0
	applies[i].passed
}

_parent_of(_, ref, applies, i, preq) := [{"id": ref.id, "cause": applies[i].cause}] if {
	_size(_applies_to_of(preq)) > 0
	not applies[i].cause in {"satisfied", "value"}
}

_parent_of(_, _, applies, i, preq) := [] if {
	_size(_applies_to_of(preq)) > 0
	applies[i].cause == "value"
}

_parent_min_subjects_row(req, name, "none") := {
	"requirement": name,
	"subject": _req_subject_ref(req),
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": 0, "locations": []}], data.ergo_unreadable),
	"passed": _min_subjects_of(req) == 0,
	"cause": _verdict_cause(_min_subjects_of(req) == 0),
}

_parent_min_subjects_row(req, name, cause) := {
	"requirement": name,
	"subject": _req_subject_ref(req),
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": 0, "locations": []}], data.ergo_unreadable),
	"passed": false,
	"cause": cause,
} if cause != "none"

violations(report) := [object.union(
	{
		"requirement": row.requirement,
		"subject": row.subject,
		"check": row.check,
		"description": _definition_field(report.requirements, row, "description"),
		"expression": _definition_field(report.requirements, row, "expression"),
		"inputs": array.concat(row.inputs, _recorded_refs(report.requirements, row)),
		"cause": row.cause,
	},
	object.union(_failed_items_of(row), _failed_assertions_of(row)),
) |
	some row in report.results
	_is_violation(report.requirements, row)
]

_failed_items_of(row) := {"failed_items": row.failed_items} if "failed_items" in object.keys(row)

_failed_items_of(row) := {} if not "failed_items" in object.keys(row)

_failed_assertions_of(row) := {"failed_assertions": row.failed_assertions} if "failed_assertions" in object.keys(row)

_failed_assertions_of(row) := {} if not "failed_assertions" in object.keys(row)

default _recorded_refs(_, _) := []

_recorded_refs(requirements, row) := refs if {
	refs := requirements[row.requirement].checks[row.check]["$refs"]
	is_array(refs)
}

default _is_violation(_, _) := false

_is_violation(requirements, row) if {
	row.passed == false
	not _out_of_scope_row(row)
	not _reported_as_holding(requirements, row.requirement)
}

_reported_as_holding(requirements, name) if requirements[name].status in {"met", "not_applicable"}

_out_of_scope_row(row) if {
	row.check == "$applies"
	row.cause == "value"
}

_definition_field(requirements, row, key) := object.get(
	requirements,
	[row.requirement, "checks", row.check, key],
	"",
)

_basic_form(side) := "path" if is_array(side)

_basic_form(side) := "literal" if {
	is_object(side)
	object.keys(side) == {"literal"}
}

_basic_form(side) := f if {
	is_object(side)
	some f in ["count_of", "sum_of"]
	object.keys(side) == {f, "whose", "text"}
	is_array(side[f])
	is_array(side.whose)
	is_string(side.text)
}

_basic_form(side) := "elapsed" if {
	is_object(side)
	object.keys(side) == {"unit", "elapsed_from", "elapsed_to", "text"}
	side.unit in object.keys(_elapsed_seconds)
	is_array(side.elapsed_from)
	is_array(side.elapsed_to)
	is_string(side.text)
}

_elapsed_seconds := {"seconds": 1, "minutes": 60, "hours": 3600, "days": 86400, "weeks": 604800}

_side_form(side) := _basic_form(side)

_side_form(side) := "add" if {
	is_object(side)
	object.keys(side) - {"text"} == {"add"}
	is_string(object.get(side, "text", ""))
	is_array(side.add)
	count(side.add) > 0
	every operand in side.add {
		_operand(operand)
	}
}

_operand(x) if _basic_form(x) in {"path", "count_of", "sum_of", "elapsed"}

_operand(x) if {
	_basic_form(x) == "literal"
	is_number(_written(x))
}

default _derived(_) := false

_derived(side) if _side_form(side) in {"add", "count_of", "sum_of", "elapsed"}

default _derived_sides(_) := []

_derived_sides(check) := [check[f] | some f in ["left", "right"]; f in object.keys(check); _derived(check[f])] if check.op == "compare"

_simple_value(subj, side) := _value_at(subj, side) if is_array(side)

_simple_value(_, side) := _written(side) if _basic_form(side) == "literal"

_basic_value(subj, side) := _simple_value(subj, side) if _basic_form(side) in {"path", "literal"}

_basic_value(subj, side) := _elapsed_units(side.unit, _value_at(subj, side.elapsed_from), _value_at(subj, side.elapsed_to)) if _basic_form(side) == "elapsed"

_basic_value(subj, side) := r.value if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
	r.states == set()
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, _time_ns(y) - _time_ns(x)) if {
	_rfc3339_shaped(x)
	_rfc3339_shaped(y)
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, _time_ns(y) - _time_ns(x)) if {
	_date_shaped(x)
	_date_shaped(y)
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, (round(y * 1000000) - round(x * 1000000)) * 1000) if {
	_elapsed_seconds_time(x)
	_elapsed_seconds_time(y)
}

_elapsed_ns(unit, n) := ((n - (n % step)) / step) / 1000000 if {
	n >= 0
	step := _elapsed_seconds[unit] * 1000
}

_elapsed_seconds_time(v) if {
	is_number(v)
	v >= -9000000000
	v <= 9000000000
}

_elapsed_times(x, y) if {
	_rfc3339_shaped(x)
	_rfc3339_shaped(y)
}

_elapsed_times(x, y) if {
	_date_shaped(x)
	_date_shaped(y)
}

_elapsed_times(x, y) if {
	_elapsed_seconds_time(x)
	_elapsed_seconds_time(y)
}

_time_ns(v) := time.parse_rfc3339_ns(v) if _rfc3339_shaped(v)

_time_ns(v) := time.parse_rfc3339_ns(concat("", [v, "T00:00:00Z"])) if _date_shaped(v)

_elapsed_path_states(subj, path) := {s} if {
	s := _read_state(subj, path)
	s != "value"
}

_elapsed_path_states(subj, path) := set() if _read_state(subj, path) == "value"

_elapsed_states(subj, side) := (_elapsed_path_states(subj, side.elapsed_from) | _elapsed_path_states(subj, side.elapsed_to)) | {"unusable" |
	_elapsed_path_states(subj, side.elapsed_from) == set()
	_elapsed_path_states(subj, side.elapsed_to) == set()
	not _elapsed_times(_value_at(subj, side.elapsed_from), _value_at(subj, side.elapsed_to))
}

_side_value(subj, side) := _basic_value(subj, side) if _basic_form(side)

_side_value(subj, side) := _add_numbers(side, nums) if {
	_side_form(side) == "add"
	nums := [n | some operand in side.add; n := _basic_value(subj, operand)]
	count(nums) == count(side.add)
	every n in nums {
		is_number(n)
	}
}

_add_numbers(side, nums) := _decimal_sum(nums) if "text" in object.keys(side)

_number_states(x, path) := {s} if {
	s := _read_state(x, path)
	s != "value"
}

_number_states(x, path) := {"unusable"} if {
	_read_state(x, path) == "value"
	not is_number(_value_at(x, path))
}

_number_states(x, path) := set() if {
	_read_state(x, path) == "value"
	is_number(_value_at(x, path))
}

_usable_sides(check, l, r) if {
	not "within" in object.keys(check)
	_usable_pair(check.cmp, l, r)
}

_usable_sides(check, l, r) if {
	"within" in object.keys(check)
	_numbers(l, r)
}

_basic_inputs(subj, side) := [_path_input(subj, side)] if _basic_form(side) == "path"

_basic_inputs(_, side) := [] if _basic_form(side) == "literal"

_basic_inputs(subj, side) := _tally_inputs(subj, side, r) if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
}

_tally_inputs(subj, side, t) := array.concat(
	[
		{"name": side.text, "value": object.get(t, "value", null), "locations": t.locations},
		_tally_list_input(t),
	],
	_merged_inputs(array.concat(
		_named_inputs(subj, [p | some c in object.get(side, "whose", []); some p in _condition_paths(c)]),
		_field_named_inputs(subj, [p | some c in object.get(side, "whose", []); some p in _condition_paths(c)]),
	)),
)

_tally_list_input(t) := {"name": t.list, "value": t.values, "locations": t.locations}

_basic_inputs(subj, side) := [_number_input(side.text, _first_or_null([x | x := _basic_value(subj, side)]), [from, to]), from, to] if {
	_basic_form(side) == "elapsed"
	from := _path_input(subj, side.elapsed_from)
	to := _path_input(subj, side.elapsed_to)
}

_side_inputs(subj, side) := _basic_inputs(subj, side) if _basic_form(side)

_side_inputs(subj, side) := array.concat([_derived_input(subj, side, _side_text(side), operands)], operands) if {
	_side_form(side) == "add"
	operands := [i | some operand in side.add; some i in _basic_inputs(subj, operand)]
}

_tally(subj, side) := {"states": {"not_an_object"}, "list": _path_name(path), "values": [], "locations": []} if {
	path := side[_basic_form(side)]
	not _off_subject(path)
	not _reads_subject(path)
	not is_object(subj)
} else := {"states": {_read_state(subj, path)}, "list": _path_name(path), "values": [], "locations": []} if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
} else := r if {
	f := _basic_form(side)
	w := _walk(_walk_start({"path": side[f]}, subj), _walk_keys({"path": side[f]}, subj), true)
	flaws := [_cond_flaw(c) | some c in side.whose]
	judged := [_tally_judge(side, e, flaws) | some e in w.items]
	kept := [e.v | some i, e in w.items; judged[i].kept]
	states := ((({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {c | some j in judged; some c in j.states}) | _tally_number_states(f, kept)) | {fl | some fl in flaws; fl != ""}
	r := object.union({"states": states, "list": _walk_name(side[f], w.walked), "values": [_walk_shown(e.v) | some e in w.items], "locations": _walk_locations(w)}, _tally_value(f, kept, states))
}

_tally_judge(side, e, flaws) := {"kept": kept, "states": ({c | some c in causes; not c in {"satisfied", "value", "missing"}} | _tally_mark(kept, e))} if {
	causes := [_tally_cond_cause(c, e.iv, flaws[i]) | some i, c in side.whose]
	kept := count([c | some c in causes; c in {"value", "missing"}]) == 0
}

_tally_cond_cause(c, item, "") := _eval_cause(passed, _ref_cause(c), states) if {
	_derived_once(c)
	l := _cond_side(item, c.left)
	r := _cond_side(item, c.right)
	passed := _eval_compared(c, l.v, r.v)
	states := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(c, lf, rf)}
}

_cond_side(item, side) := {"v": v, "found": v, "states": _elapsed_states(item, side)} if {
	_basic_form(side) == "elapsed"
	v := [x | x := _elapsed_units(side.unit, _value_at(item, side.elapsed_from), _value_at(item, side.elapsed_to))]
}

_cond_side(item, side) := {"v": [x | x := t.value], "found": [x | x := t.value], "states": t.states} if {
	_basic_form(side) == "count_of"
	t := _cond_tally(item, side)
}

_cond_tally(item, side) := {"states": {"not_an_object"}} if {
	not _off_subject(side.count_of)
	not _reads_subject(side.count_of)
	not is_object(item)
} else := {"states": {_read_state(item, side.count_of)}} if {
	not _walk_keys({"path": side.count_of}, item)
} else := r if {
	w := _walk(_walk_start({"path": side.count_of}, item), _walk_keys({"path": side.count_of}, item), true)
	kept := [e.v | some e in w.items]
	states := ({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {c | some e in w.items; some c in _tally_mark(true, e)}
	r := object.union({"states": states}, _tally_value("count_of", kept, states))
}

_cond_side(item, side) := {"v": [x | x := _value_at(item, side)], "found": [x | x := _simple_found(item, side)], "states": {_read_state(item, side)}} if _basic_form(side) == "path"

_cond_side(item, side) := {"v": [_written(side)], "found": [x | x := _simple_found(item, side)], "states": set()} if _basic_form(side) == "literal"

_tally_cond_cause(c, item, "") := _leaf_cause(c, item) if not _derived_once(c)

_tally_cond_cause(_, _, flaw) := flaw if flaw != ""

_cond_flaw(c) := "unusable" if {
	_node_param_broken(c)
} else := _worst_of({_used_ref_state(c, r) | some r in _check_refs(c)}) if {
	_unreadable_ref(c)
} else := ""

_tally_mark(true, e) := {"absent"} if e.v == _absent

_tally_mark(true, e) := {_read_state(e.iv, e.r)} if e.v == _unusable_mark

_tally_mark(_, e) := set() if not _walk_marked(e.v)

_tally_mark(false, e) := set() if _walk_marked(e.v)

_tally_value(_, _, states) := {} if states != set()

_tally_value("count_of", kept, set()) := {"value": count(kept)}

_tally_value("sum_of", kept, set()) := {"value": _decimal_sum(kept)}

_tally_number_states("count_of", _) := set()

_tally_number_states("sum_of", kept) := {_sum_state(n) | some n in kept; not _walk_marked(n); not is_number(n)}

_sum_state(null) := "null"

_sum_state(n) := "unusable" if n != null

_decimal_sum(nums) := sum([round(n * scale) | some n in nums]) / scale if {
	places := max(array.concat([0], [_decimal_places(n) | some n in nums]))
	places <= 15
	scale := product([10 | some i in numbers.range(1, 15); i <= places])
	every n in nums {
		abs(n) * scale < 1e15
	}
} else := sum(nums)

_decimal_places(n) := max([0, count(_fraction_digits(parts[0])) - _written_exponent(parts)]) if parts := split(lower(json.marshal(n)), "e")

_fraction_digits(mantissa) := split(mantissa, ".")[1] if contains(mantissa, ".")

_fraction_digits(mantissa) := "" if not contains(mantissa, ".")

_written_exponent([_]) := 0

_written_exponent([_, e]) := to_number(e)

_derived_input(subj, side, name, operands) := _number_input(name, v, operands) if {
	v := _side_value(subj, side)
} else := _number_input(name, null, operands)

_side_text(side) := side.text if {
	_side_form(side) == "add"
	"text" in object.keys(side)
}

_basic_paths(side) := [side] if _basic_form(side) == "path"

_basic_paths(side) := [] if _basic_form(side) == "literal"

_basic_paths(side) := [side.elapsed_from, side.elapsed_to] if _basic_form(side) == "elapsed"

_basic_paths(side) := [side[f]] if {
	f := _basic_form(side)
	f in {"count_of", "sum_of"}
}

_sentence_side(side) if _basic_form(side) in {"count_of", "sum_of", "elapsed"}

_sentence_side(side) if {
	is_object(side)
	"text" in object.keys(side)
}

_side_paths(side) := _basic_paths(side) if _basic_form(side)

_side_paths(side) := [p | some operand in side.add; some p in _basic_paths(operand)] if _side_form(side) == "add"

_side_paths(side) := [] if not _side_form(side)

_where_children(node, names) := [[c, array.concat(at, ["whose", i]), "where", names] |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	some [at, side] in _tallies(node[f], [f])
	some i, c in side.whose
]

_tallies(side, at) := [[at, side]] if _basic_form(side) in {"count_of", "sum_of"}

_tallies(side, at) := [[array.concat(at, ["add", i]), operand] | some i, operand in side.add; _basic_form(operand) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_tallies(side, _) := [] if not _side_form(side) in {"count_of", "sum_of", "add"}

_side_problem(node, here) := ({concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	not _side_form(node[f])
} | {concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	_sentence_side(node[f])
	not _s_read(node, here)
}) | {concat("", ["invalid ", f]) |
	node.op == "compare_time"
	some f in ["left", "right"]
	f in object.keys(node)
	not is_array(node[f])
	not _sentence_time_value(f, node, here)
}

_sentence_time_value("right", node, here) if {
	_basic_form(node.right) == "literal"
	_s_read(node, here)
}

_within_problem(node) := {"invalid within" |
	node.op == "compare"
	"within" in object.keys(node)
	not _non_negative(node.within)
} | {"within needs cmp eq" |
	node.op == "compare"
	"within" in object.keys(node)
	object.get(node, "cmp", null) != "eq"
}

_non_negative(n) if {
	is_number(n)
	n >= 0
}

_derived_placement_problem(node, kinds, here) := {concat("", [_side_form(side), " can't go here"]) |
	kinds != []
	not _assertion_kinds(kinds)
	some side in _derived_sides(node)
	not _sentence_side_in_whose(side, kinds, node, here)
}

_sentence_side_in_whose(side, kinds, node, here) if {
	_basic_form(side) in {"elapsed", "count_of"}
	kinds[count(kinds) - 1] == "where"
	_s_read(node, here)
}

_assertion_kinds(kinds) if {
	every k in kinds {
		k == "assertion"
	}
}

_s_patterns := {
	"assertions": concat("", [`(`, assertion, `)(?: +and +|$)`]),
	"assertion": concat("", [`^(?:(every|some) +(`, path, `)|(`, left, `))(?: +whose +(`, conds, `))?(, +if +any,)? +(`, phrase, `)$`]),
	"for_items": concat("", [`(`, for_item, `)(?:, +|$)`]),
	"for_item": concat("", [`^(?:(every|some) +)?(`, path, `)(?: +whose +(`, conds, `))?(?: +sorted +by +(`, path, `)( +alphabetically)?)?(, +if +any,)? +as +(`, key, `)$`]),
	"from": concat("", [`^(`, path, `)(?: +named +by +each +of +(`, rpath, `))?(?: +whose +(`, from_conds, `))?$`]),
	"from_conds": concat("", [`(`, from_cond, `)(?: +and +|$)`]),
	"from_cond": concat("", [`^(?:(every|some) +(`, path, `)(, +if +any,)?|(`, left, `)) +(`, phrase, `)$`]),
	"conds": concat("", [`(`, cond, `)(?: +and +|$)`]),
	"cond": concat("", [`^(`, left, `) +(`, phrase, `)$`]),
	"phrases": phrases,
	"kinds": {kind[0]: concat("", [`^(?:`, kind[1], `)$`]) | some kind in kinds},
	"plain": concat("", [`^(`, path, `) +(\S.*)$`]),
	"quantified": concat("", [`^(every|some) +(`, path, `) +(\S.*)$`]),
	"path": concat("", [`^`, path, `$`]),
	"path_parts": concat("", [`^(?:(item +([1-9][0-9]*)( +from +last)?|first|last) +of +)?(`, start, `)((?:`, step, `)*)$`]),
	"steps": concat("", [`\.(`, key, `|`, dq, `)| +named +by +(`, ref, `)|\[(`, ref, `)\]|\[(`, dq, `)\]|\[(0|[1-9][0-9]*)\]`]),
	"terms": concat("", [`(`, term, `)(?: +plus +|$)`]),
	"number": concat("", [`^`, num, `$`]),
	"derived": concat("", [`^(count|sum) +of +(`, path, `)$`]),
	"elapsed": concat("", [`^(seconds|minutes|hours|days|weeks) +elapsed +from +(`, path, `) +to +(`, path, `)$`]),
	"value": concat("", [`^`, value, `$`]),
	"values": concat("", [`^`, values, `$`]),
	"each_value": value,
	"range": concat("", [`^(`, num, `) +and +(`, num, `)$`]),
	"operand_within": concat("", [`^(`, operand, `)(?: +within +(`, num, `))?$`]),
	"quotes": `^(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^"']+)*`,
	"strings": `"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'`,
	"string": concat("", [`^(?:`, dq, `|`, sq, `)$`]),
	"quantified_path": concat("", [`^(?:(?:every|some) +)?`, path, `$`]),
} if {
	key := `[A-Za-z_][A-Za-z0-9_-]*`
	dq := `"(?:[^"\\\x00-\x1f]|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*"`
	sq := `'(?:[^'\\\x00-\x1f]|\\[^\x00-\x1f])*'`
	num := `-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?`
	ref := concat("", [`(?:\$params|\$input)\.(?:`, key, `|`, dq, `)|`, key])
	step := concat("", [`\.(?:`, key, `|`, dq, `)| +named +by +(?:`, ref, `)|\[(?:`, ref, `|`, dq, `|0|[1-9][0-9]*)\]`])
	start := concat("", [`\$params|\$input|\.?(?:`, key, `|`, dq, `)`])
	rstart := concat("", [`\$params|\$input|`, key, `|\.(?:`, key, `|`, dq, `)`])
	pos := `(?:item +[1-9][0-9]*(?: +from +last)?|first|last) +of +`
	plain := concat("", [`(?:`, start, `)(?:`, step, `)*`])
	path := concat("", [`(?:`, pos, `)?`, plain])
	rpath := concat("", [`(?:`, pos, `)?(?:`, rstart, `)(?:`, step, `)*`])
	elapsed := concat("", [`(?:seconds|minutes|hours|days|weeks) +elapsed +from +`, path, ` +to +`, path])
	derived := concat("", [`(?:(?:count|sum) +of +`, path, `|`, elapsed, `)`])
	term := concat("", [`(?:`, derived, `|`, rpath, `|`, num, `)`])
	terms := concat("", [term, `(?: +plus +`, term, `)*`])
	left := concat("", [`(?:`, path, `|`, terms, `)`])
	value := concat("", [`(?:`, dq, `|`, sq, `|`, num, `|true|false|null)`])
	values := concat("", [value, `(?:, *`, value, `)*`])
	operand := concat("", [`(?:`, num, `(?: +plus +`, term, `)+|`, value, `|(?:`, derived, `|`, rpath, `)(?: +plus +`, term, `)*)`])
	list := concat("", [`(?:`, values, `|`, rpath, `)`])
	type := `(?:list|string|number|boolean|object)`
	phrases := [
		["is not one of", `is +not +(?:one +of|in) +`, list, "list"],
		["is one of", `is +(?:one +of|in) +`, list, "list"],
		["is a non-empty string", `is +a +non-empty +string`, ``, "none"],
		["is a", `is +an? +`, type, "type"],
		["is not empty", `is +not +empty`, ``, "none"],
		["is empty", `is +empty`, ``, "none"],
		["does not exist", `does +not +exist`, ``, "none"],
		["exists", `exists`, ``, "none"],
		["contains all of", `contains +all +of +`, list, "list"],
		["contains none of", `contains +none +of +`, list, "list"],
		["does not contain", `does +not +contain +`, operand, "operand"],
		["contains", `contains +`, operand, "operand"],
		["does not match", `does +not +match +`, list, "list"],
		["matches", `matches +`, list, "list"],
		["starts with", `starts +with +`, operand, "operand"],
		["ends with", `ends +with +`, operand, "operand"],
		["is alphabetically before", `is +alphabetically +before +`, operand, "operand"],
		["is alphabetically after", `is +alphabetically +after +`, operand, "operand"],
		["is at least", `is +at +least +`, operand, "operand"],
		["is at most", `is +at +most +`, operand, "operand"],
		["is more than", `is +more +than +`, operand, "operand"],
		["is less than", `is +less +than +`, operand, "operand"],
		["is between", `is +between +`, concat("", [num, ` +and +`, num]), "range"],
		["is on or after", `is +on +or +after +`, operand, "operand"],
		["is on or before", `is +on +or +before +`, operand, "operand"],
		["is before", `is +before +`, operand, "operand"],
		["is after", `is +after +`, operand, "operand"],
		["is not", `(?:is +not|does +not +equal) +`, operand, "operand"],
		["is", `(?:is +equal +to|equals|is) +`, concat("", [operand, `(?: +within +`, num, `)?`]), "operand_within"],
	]
	kinds := [
		["none", ``],
		["type", type],
		["range", concat("", [num, ` +and +`, num])],
		["list", list],
		["operand", operand],
		["operand_within", concat("", [operand, `(?: +within +`, num, `)?`])],
	]
	phrase := concat("|", [concat("", [`(?:`, concat("|", [ph[1] | some ph in phrases; ph[3] == kind[0]]), `)`, kind[1]]) | some kind in kinds])
	cond := concat("", [`(?:`, derived, `|`, path, `) +(?:`, phrase, `)`])
	conds := concat("", [cond, `(?: +and +`, cond, `)*`])
	from_cond := concat("", [`(?:(?:every|some) +`, path, `(?:, +if +any,)?|(?:`, derived, `|`, path, `)) +(?:`, phrase, `)`])
	from_conds := concat("", [from_cond, `(?: +and +`, from_cond, `)*`])
	assertion := concat("", [`(?:(?:every|some) +`, path, `|`, left, `)(?: +whose +`, conds, `)?(?:, +if +any,)? +(?:`, phrase, `)`])
	for_item := concat("", [`(?:(?:every|some) +)?`, path, `(?: +whose +`, conds, `)?(?: +sorted +by +`, path, `(?: +alphabetically)?)?(?:, +if +any,)? +as +`, key])
}

_s_words := {"a", "after", "alphabetically", "an", "and", "as", "at", "before", "between", "count", "days", "each", "empty", "equal", "every", "false", "first", "hours", "in", "it", "item", "last", "less", "minutes", "more", "named", "not", "null", "of", "on", "one", "or", "plus", "seconds", "some", "sorted", "sum", "to", "true", "weeks", "whose", "within"}

_s_pieces(pattern, text) := [m[1] | some m in matches] if {
	matches := regex.find_all_string_submatch_n(pattern, text, -1)
	concat("", [m[0] | some m in matches]) == text
}

_sentence(raw) := {"assertions": [assertion]} if {
	pat := _s_patterns
	m := regex.find_all_string_submatch_n(pat.plain, trim_space(raw), 1)[0]
	assertion := {"path": _s_path_of(m[1], pat), "phrase": _s_phrase_of(m[2], pat)}
	count(_s_sentence_problems({"assertions": [assertion]})) == 0
} else := {"assertions": [assertion]} if {
	pat := _s_patterns
	m := regex.find_all_string_submatch_n(pat.quantified, trim_space(raw), 1)[0]
	assertion := {m[1]: _s_path_of(m[2], pat), "phrase": _s_phrase_of(m[3], pat)}
	count(_s_sentence_problems({"assertions": [assertion]})) == 0
} else := {"assertions": assertions} if {
	pat := _s_patterns
	text := trim_space(raw)
	pieces := _s_pieces(pat.assertions, text)
	assertions := [_s_assertion_of(a, pat) | some a in pieces]
	count(assertions) == count(pieces)
	count(pieces) > 0
	count(_s_sentence_problems({"assertions": assertions})) == 0
} else := {"problems": _s_problems(trim_space(raw), _s_patterns)}

_for_line(raw) := {"items": items} if {
	pat := _s_patterns
	text := trim_space(raw)
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
} else := {"problems": _from_problems(_s_after_every(trim_space(raw)), _s_patterns)}

_from_problems(text, pat) := ["a condition after whose can't have a whose of its own"] if {
	_s_problems(text, pat) == ["doesn't parse"]
	regex.match(` +whose +(?:.* +and +)?(?:(?:every|some) +|(?:count|sum) +of +)\S+ +whose +`, text)
} else := _s_problems(text, pat)

_s_pick_problems(parsed) := ((({`an item starts with "every", "some" or a position, like "last of"` |
	some item in object.get(parsed, "items", [])
	not "position" in object.keys(object.get(item, "pick", {"position": 1}))
} | {`"sorted by" goes after a position, like "last of", not after every or some` |
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

_s_from_plain(text, pat) := object.union({"path": _s_path_of(m[1], pat)}, object.union(_s_each_of(m[2], pat), _s_from_where_of(m[3], pat))) if {
	m := regex.find_all_string_submatch_n(pat.from, text, 1)[0]
}

_s_each_of("", _) := {}

_s_each_of(text, pat) := {"named_by_each_of": _s_path_of(text, pat)} if text != ""

_s_assertion_of(text, pat) := out if {
	m := regex.find_all_string_submatch_n(pat.assertion, text, 1)[0]
	m[1] != ""
	out := object.union(
		{m[1]: _s_path_of(m[2], pat), "phrase": _s_phrase_of(m[6], pat)},
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
		{_s_item_word(m[1]): _s_path_of(m[2], pat), "as": m[7]},
		object.union(object.union(_s_where_of(m[3], pat), _s_if_any(m[6])), _s_sorted_by(m[4], m[5], pat)),
	)
}

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

_s_from_cond_of(text, pat) := object.union({m[1]: _s_path_of(m[2], pat), "phrase": _s_phrase_of(m[5], pat)}, _s_if_any(m[3])) if {
	m := regex.find_all_string_submatch_n(pat.from_cond, text, 1)[0]
	m[1] != ""
}

_s_from_cond_of(text, pat) := object.union(_s_left_of(m[4], pat), {"phrase": _s_phrase_of(m[5], pat)}) if {
	m := regex.find_all_string_submatch_n(pat.from_cond, text, 1)[0]
	m[1] == ""
}

_s_cond_of(text, pat) := object.union(_s_left_of(m[1], pat), {"phrase": _s_phrase_of(m[2], pat)}) if {
	m := regex.find_all_string_submatch_n(pat.cond, text, 1)[0]
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
} else := {m[1]: _s_path_of(m[2], pat)} if {
	m := regex.find_all_string_submatch_n(pat.derived, text, 1)[0]
} else := {"unit": m[1], "elapsed_from": _s_path_of(m[2], pat), "elapsed_to": _s_path_of(m[3], pat)} if {
	m := regex.find_all_string_submatch_n(pat.elapsed, text, 1)[0]
} else := _s_path_of(text, pat)

_s_path_of(text, pat) := _s_lifted(_s_unlifted_path_of(text, pat))

_s_unlifted_path_of(text, pat) := object.union(_s_position_of(m[1], m[2], m[3]), _s_start_of(m[4], _s_steps_of(m[5], pat))) if {
	m := regex.find_all_string_submatch_n(pat.path_parts, text, 1)[0]
}

_s_lifted(path) := object.union(object.union(object.remove(path, ["steps"]), object.remove(last, ["index"])), {"position": last.index + 1, "steps": array.slice(path.steps, 0, count(path.steps) - 1)}) if {
	not "position" in object.keys(path)
	object.get(path, "it", false) != true
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

_s_start_of("it", steps) := {"steps": array.concat(["it"], steps), "it": true}

_s_start_of(key, steps) := {"steps": array.concat([key], steps), "bare_word": key} if {
	key in _s_words
	key != "it"
}

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(key)], steps)} if {
	not key in _s_words
	not startswith(key, "$")
	not startswith(key, ".")
}

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(substring(key, 1, -1))], steps), "dot": true} if startswith(key, ".")

_s_key_of(text) := json.unmarshal(text) if startswith(text, `"`)

_s_key_of(text) := text if not startswith(text, `"`)

_s_steps_of(text, pat) := [_s_step_of(m) | some m in matches] if {
	matches := regex.find_all_string_submatch_n(pat.steps, text, -1)
	concat("", [m[0] | some m in matches]) == text
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

_s_ref_of(text) := {"steps": [text]} if {
	not startswith(text, "$")
	not _s_bad_name(text)
}

_s_ref_of(text) := {"steps": [text], "bad_name": text} if _s_bad_name(text)

_s_phrase_of(text, pat) := object.union({"op": pat.phrases[hit[0]][0]}, _s_args_of(pat.phrases[hit[0]][3], hit[1], pat)) if {
	hits := [[i, m[1]] |
		some i, ph in pat.phrases
		m := regex.find_all_string_submatch_n(concat("", [`^(?:`, ph[1], `)(.*)$`]), text, 1)[0]
		regex.match(pat.kinds[ph[3]], m[1])
	]
	hit := hits[0]
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
} else := {"terms": _s_terms_of(text, pat)}

_s_values_of(text, pat) := [_s_value_of(m[0]) | some m in regex.find_all_string_submatch_n(pat.each_value, text, -1)]

_s_value_of(text) := _s_number(text) if regex.match(`^-?[0-9]`, text)

_s_value_of(text) := json.unmarshal(text) if {
	not startswith(text, "'")
	not regex.match(`^-?[0-9]`, text)
}

_s_value_of(text) := concat("", [_s_sq_char(m[0]) | some m in regex.find_all_string_submatch_n(`\\'|\\\\|\\.|[^\\]`, substring(text, 1, count(text) - 2), -1)]) if startswith(text, "'")

_s_number(text) := 0 if {
	regex.match(`^-?[0.]+[eE]`, text)
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

_s_sentence_problems(parsed) := _s_base_problems(parsed) | _s_it_problems(parsed)

_s_it_problems(parsed) := ({_s_it_step_message(node) |
	some node in _s_nodes(parsed)
	is_object(node)
	node.it == true
	_s_it_followed(node)
} | {"it can't name a key" |
	some node in _s_nodes(parsed)
	is_object(node)
	node.bad_name == "it"
}) | {"it can only start an assertion: write it first, like it is not empty" |
	_s_it_total(parsed) > count(_s_it_allowed(parsed))
}

_s_it_whole(x) if {
	is_object(x)
	x.it == true
	x.steps == ["it"]
}

_s_it_followed(node) if count(node.steps) > 1

_s_it_step_message(node) := concat("", ["it is the whole subject: write ", _s_key_text(node.steps[1]), ", not it.", _s_key_text(node.steps[1])]) if {
	count(node.steps) > 1
	is_string(node.steps[1])
}

else := "it is the whole subject: nothing can follow it"

_s_it_total(parsed) := count([1 |
	walk(parsed, [_, x])
	_s_it_whole(x)
])

_s_it_allowed(parsed) := array.concat(
	array.concat(
		[1 |
			some a in object.get(parsed, "assertions", [])
			_s_it_whole(object.get(a, "path", null))
		],
		[1 |
			some a in object.get(parsed, "assertions", [])
			some q in ["every", "some"]
			_s_it_whole(object.get(a, q, null))
		],
	),
	array.concat(
		[1 |
			some a in _s_own_holders(parsed)
			some t in object.get(a, "terms", [])
			is_object(t)
			some k in ["count", "sum"]
			_s_it_whole(object.get(t, k, null))
		],
		array.concat(
			[1 |
				some c in _s_from_conds(parsed)
				_s_it_whole(object.get(c, "path", null))
			],
			[1 |
				some c in _s_from_conds(parsed)
				some q in ["every", "some"]
				_s_it_whole(object.get(c, q, null))
			],
		),
	),
)

_s_own_holders(parsed) := array.concat(object.get(parsed, "assertions", []), _s_from_conds(parsed))

_s_from_conds(parsed) := object.get(parsed, "where", []) if {
	not "assertions" in object.keys(parsed)
	not "items" in object.keys(parsed)
}

else := []

_s_base_problems(parsed) := ((((((((((((((((({concat("", [node.bare_word, " is a word of the grammar: write .", node.bare_word]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bare_word" in object.keys(node)
} | {concat("", [node.bad_name, " can't be an alias"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bad_name" in object.keys(node)
	node.bad_name != "it"
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
}) | {"a whose goes after every, some, count of or sum of" |
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
	not node.phrase.op in {"is", "is not", "is at least", "is at most", "is more than", "is less than", "is between"}
}) | {"a number can't start a sentence" |
	some node in _s_nodes(parsed)
	is_object(node)
	node.terms == [node.terms[0]]
	is_number(node.terms[0])
}) | {"min above max" |
	some node in _s_nodes(parsed)
	is_object(node)
	node.op == "is between"
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
	node.op in {"starts with", "ends with", "is alphabetically before", "is alphabetically after"}
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
	node.phrase.op in {"contains", "does not contain", "contains all of", "contains none of"}
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

_s_self_ops := {"is", "is not", "is at least", "is at most", "is more than", "is less than", "is before", "is after", "is on or after", "is on or before", "starts with", "ends with", "is alphabetically before", "is alphabetically after"}

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
} | _s_whose_self_problems(assertions)) | {concat("", [_s_unmarked_text(a.phrase.terms[0]), " is compared with itself, because after every or some it's read from the item: to read the subject's ", _s_unmarked_text(a.phrase.terms[0]), ", put the list on the for line and compare under assert"]) |
	some a in assertions
	some q in ["every", "some"]
	walked := object.get(a, q, null)
	is_object(walked)
	t := _s_self_term(a)
	object.keys(object.remove(t, ["dot", "field", "own"])) == {"steps"}
	k := count(t.steps)
	k < count(walked.steps)
	array.slice(walked.steps, count(walked.steps) - k, count(walked.steps)) == t.steps
}

_s_unmarked_text(p) := _s_path_text(object.remove(p, ["dot", "field", "own", "part", "alias"]), "left")

_s_whose_self_problems(holders) := {concat("", [_s_unmarked_text(w.path), " is compared with itself, because in a whose it's read from the item", _s_whose_advice(h, w)]) |
	some h in holders
	some w in object.get(h, "where", [])
	is_object(w)
	_s_self_compared(w)
}

_s_whose_advice(h, w) := ", and a count or a sum can't read the subject's field there yet" if "terms" in object.keys(h)

else := concat("", [": to read the subject's ", _s_unmarked_text(w.path), ", compare under assert"])

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
	object.get(p, "it", false) != true
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

else := ph

_s_marked_cond(c, names) := object.union(c, {"path": _s_marked(c.path, names, true), "phrase": _s_marked_phrase(c.phrase, names)}) if "path" in object.keys(c)

else := object.union(c, {"terms": [_s_own_term(t, names) | some t in c.terms], "phrase": _s_marked_phrase(c.phrase, names)})

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
	problems := _s_sentence_problems(_s_parsed_anyway(text, pat))
	count(problems) > 0
} else := names if {
	names := sort({concat("", ["unknown name ", m[1]]) | some m in regex.find_all_string_submatch_n(concat("", [pat.strings, `|(?:^|[ ,\[])(\$[A-Za-z_][A-Za-z0-9_]*)`]), text, -1); not m[1] in {"", "$params", "$input"}})
	count(names) > 0
} else := ["two quantifiers in one sentence: put them on a for line"] if {
	regex.match(`^(?:every|some) +\S+ +(?:every|some) `, text)
} else := [`"within" needs a number after it`] if {
	regex.match(` within$`, text)
} else := [concat("", ["nothing after the path at column ", _json_text(count(text) + 1), `: expected a phrase, like "is" or "exists"`])] if {
	regex.match(pat.quantified_path, text)
} else := ["doesn't parse"]

_s_parsed_anyway(text, pat) := {"assertions": assertions} if {
	pieces := _s_pieces(pat.assertions, text)
	assertions := [_s_assertion_of(a, pat) | some a in pieces]
	count(assertions) == count(pieces)
	count(pieces) > 0
}

_s_parsed_anyway(text, pat) := {"items": items} if {
	pieces := _s_pieces(pat.for_items, text)
	items := [_s_for_item_of(a, pat) | some a in pieces]
	count(items) == count(pieces)
	count(pieces) in {1, 2}
}

_s_parsed_anyway(text, pat) := _s_from_plain(text, pat)

_s_check_text(parsed) := concat(" and ", [_s_assertion_text(a) | some a in parsed.assertions])

_s_for_line_text(parsed) := concat(", ", [_s_for_item_text(a) | some a in parsed.items])

_s_from_line_text(parsed) := concat("", [_s_every_text(parsed), _s_path_text(parsed.path, "left"), _s_each_text(parsed), _s_where_text(parsed)])

_s_every_text(parsed) := "every " if object.get(parsed, "every", false) == true

else := ""

_s_each_text(parsed) := concat("", [" named by each of ", _s_path_text(parsed.named_by_each_of, "right")]) if "named_by_each_of" in object.keys(parsed)

_s_each_text(parsed) := "" if not "named_by_each_of" in object.keys(parsed)

_s_for_item_text(item) := concat("", [_s_quantified_text(item), " as ", item.as]) if not "pick" in object.keys(item)

_s_for_item_text(item) := concat("", [_s_path_text(item.pick, "left"), _s_where_text(item), _s_sorted_by_text(item), " as ", item.as]) if "pick" in object.keys(item)

_s_sorted_by_text(item) := concat("", [" sorted by ", _s_path_text(item.sorted_by, "left"), _s_alphabetically_text(item)]) if "sorted_by" in object.keys(item)

else := ""

_s_assertion_text(a) := concat(" ", [_s_quantified_text(a), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) != ""

_s_assertion_text(a) := concat(" ", [concat("", [_s_left_text(a), _s_where_text(a)]), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) == ""

_s_quantified_text(a) := concat("", [_s_quantifier_of(a), " ", _s_path_text(a[_s_quantifier_of(a)], "left"), _s_where_text(a), _s_if_any_text(a)])

_s_quantifier_of(a) := "every" if "every" in object.keys(a)

_s_quantifier_of(a) := "some" if "some" in object.keys(a)

_s_quantifier_of(a) := "pick" if "pick" in object.keys(a)

_s_quantifier_of(a) := "" if object.keys(a) & {"every", "some", "pick"} == set()

_s_if_any_text(a) := ", if any," if object.get(a, "if_any", false) == true

_s_if_any_text(a) := "" if not object.get(a, "if_any", false)

_s_where_text(a) := concat("", [" whose ", concat(" and ", [_s_cond_text(c) | some c in a.where])]) if "where" in object.keys(a)

_s_where_text(a) := "" if not "where" in object.keys(a)

_s_cond_text(c) := concat(" ", [_s_left_text(c), _s_phrase_text(c.phrase)])

_s_cond_text(c) := concat(" ", [concat("", [_s_quantifier_of(c), " ", _s_path_text(c[_s_quantifier_of(c)], "left"), _s_if_any_text(c)]), _s_phrase_text(c.phrase)]) if _s_quantifier_of(c) in {"every", "some"}

_s_left_text(c) := _s_path_text(c.path, "left") if "path" in object.keys(c)

_s_left_text(c) := _s_terms_text(c.terms) if "terms" in object.keys(c)

_s_terms_text(terms) := concat(" plus ", [_s_term_text(t) | some t in terms])

_s_term_text(t) := _json_text(t) if is_number(t)

_s_term_text(t) := concat("", ["count of ", _s_path_text(t.count, "left")]) if {
	is_object(t)
	"count" in object.keys(t)
}

_s_term_text(t) := concat("", ["sum of ", _s_path_text(t.sum, "left")]) if {
	is_object(t)
	"sum" in object.keys(t)
}

_s_term_text(t) := concat("", [t.unit, " elapsed from ", _s_path_text(t.elapsed_from, "left"), " to ", _s_path_text(t.elapsed_to, "left")]) if {
	is_object(t)
	"elapsed_from" in object.keys(t)
}

_s_term_text(t) := _s_path_text(t, "right") if {
	is_object(t)
	"steps" in object.keys(t)
}

_s_path_text(p, side) := concat("", [_s_position_text(p), _s_start_text(p, side), concat("", [_s_step_text(s) | some s in array.slice(p.steps, _s_first_step(p), count(p.steps))])])

_s_position_text(p) := concat("", ["item ", _json_text(p.position), _s_from_last_text(p), " of "]) if is_number(object.get(p, "position", null))

_s_position_text(p) := concat("", [p.position, " of "]) if is_string(object.get(p, "position", null))

_s_position_text(p) := "" if not "position" in object.keys(p)

_s_from_last_text(p) := " from last" if object.get(p, "from_last", false) == true

else := ""

_s_first_step(p) := 0 if "start" in object.keys(p)

_s_first_step(p) := 1 if not "start" in object.keys(p)

_s_start_text(p, _) := "$params" if object.get(p, "start", "") == "params"

_s_start_text(p, _) := "$input" if object.get(p, "start", "") == "input"

_s_start_text(p, side) := concat("", [_s_start_dot(p, side), _s_key_text(p.steps[0])]) if not "start" in object.keys(p)

_s_start_dot(p, side) := "." if {
	object.get(p, "field", false) == true
	object.get(p, "own", false) != true
}

else := "" if object.get(p, "it", false) == true

else := _s_dot(p.steps[0], side)

_s_dot(key, side) := "." if {
	_s_needs_dot(key, side)
} else := ""

_s_needs_dot(key, _) if key in _s_words

_s_needs_dot(key, "right") if not _s_bare_key(key)

_s_bare_key(key) if regex.match(`^[A-Za-z_][A-Za-z0-9_-]*$`, key)

_s_key_text(key) := key if _s_bare_key(key)

_s_key_text(key) := _json_text(key) if not _s_bare_key(key)

_s_step_text(s) := concat("", [".", _s_key_text(s)]) if is_string(s)

_s_step_text(s) := concat("", [" named by ", _s_ref_text(s.named_by)]) if {
	is_object(s)
	"named_by" in object.keys(s)
}

_s_step_text(s) := concat("", ["[", _json_text(s.index), "]"]) if {
	is_object(s)
	"index" in object.keys(s)
}

_s_ref_text(r) := concat("", ["$", r.start, ".", _s_key_text(r.steps[0])]) if "start" in object.keys(r)

_s_ref_text(r) := r.steps[0] if not "start" in object.keys(r)

_s_phrase_text(ph) := concat(" ", [_s_phrase_words(ph), _s_args_text(ph)]) if _s_args_text(ph) != ""

_s_phrase_text(ph) := _s_phrase_words(ph) if _s_args_text(ph) == ""

_s_phrase_words(ph) := "equals" if {
	ph.op == "is"
	"terms" in object.keys(ph)
}

_s_phrase_words(ph) := "is" if {
	ph.op == "is"
	"value" in object.keys(ph)
}

_s_phrase_words(ph) := "does not equal" if {
	ph.op == "is not"
	"terms" in object.keys(ph)
}

_s_phrase_words(ph) := "is not" if {
	ph.op == "is not"
	"value" in object.keys(ph)
}

_s_phrase_words(ph) := "is one of" if {
	ph.op == "is one of"
	"values" in object.keys(ph)
}

_s_phrase_words(ph) := "is in" if {
	ph.op == "is one of"
	"path" in object.keys(ph)
}

_s_phrase_words(ph) := "is not one of" if {
	ph.op == "is not one of"
	"values" in object.keys(ph)
}

_s_phrase_words(ph) := "is not in" if {
	ph.op == "is not one of"
	"path" in object.keys(ph)
}

_s_phrase_words(ph) := "is an" if {
	ph.op == "is a"
	ph.type == "object"
}

_s_phrase_words(ph) := "is a" if {
	ph.op == "is a"
	ph.type != "object"
}

_s_phrase_words(ph) := ph.op if not ph.op in {"is", "is not", "is one of", "is not one of", "is a"}

_s_args_text(ph) := ph.type if ph.op == "is a"

_s_args_text(ph) := concat(" and ", [_json_text(ph.min), _json_text(ph.max)]) if ph.op == "is between"

_s_args_text(ph) := concat(" within ", [_s_operand_text(ph), _json_text(ph.within)]) if "within" in object.keys(ph)

_s_args_text(ph) := _s_operand_text(ph) if {
	not ph.op in {"is a", "is between"}
	not "within" in object.keys(ph)
}

_s_operand_text(ph) := _s_value_text(ph.value) if "value" in object.keys(ph)

_s_operand_text(ph) := _s_terms_text(ph.terms) if "terms" in object.keys(ph)

_s_operand_text(ph) := concat(", ", [_s_value_text(v) | some v in ph.values]) if "values" in object.keys(ph)

_s_operand_text(ph) := _s_path_text(ph.path, "right") if "path" in object.keys(ph)

_s_operand_text(ph) := "" if object.keys(ph) & {"value", "terms", "values", "path"} == set()

_s_value_text(v) := concat("", ["'", v, "'"]) if {
	_s_single_quoted(v)
} else := _json_text(v)

_s_single_quoted(v) if {
	is_string(v)
	contains(v, `\`)
	not contains(v, "'")
	not contains(v, `\\`)
	not endswith(v, `\`)
	regex.match(`^[^\x00-\x1f]*$`, v)
}

_s_from_reads(subjects, parts) := {name: object.union(_s_from_part(name, parts.lines, subjects, {"narrow": parts.narrow, "descend": parts.descend, "parts": parts.effective}), _s_id_part(def)) | some name, def in subjects; is_object(def)} if is_object(subjects)

_s_from_part(name, lines, subjects, chains) := _s_from_read(name, lines[name], subjects, chains) if name in object.keys(lines)

_s_from_part(name, lines, _, _) := {} if not name in object.keys(lines)

_s_id_part(def) := {"identified_by": _s_id_read(def.identified_by)} if is_string(object.get(def, "identified_by", null))

_s_id_part(def) := {} if not is_string(object.get(def, "identified_by", null))

_s_id_read(text) := {"path": _s_model_path(fl.path)} if {
	fl := _from_line(text)
	object.keys(fl) == {"path"}
	count(_s_from_paths_unsupported({"path": fl.path})) == 0
} else := {"problems": [`identified_by is a path, like "id" or "build.number"`]}

_s_from_reads(subjects, _) := {} if not is_object(subjects)

_p_alias_ok(alias) if {
	is_string(alias)
	regex.match(`^[A-Za-z_][A-Za-z0-9_-]*$`, alias)
	not _s_bad_name(alias)
}

_p_own_reads(subjects) := {name: {alias: _p_part_read(alias, entry) | some alias, entry in def.has} |
	some name, def in subjects
	is_object(def)
	is_object(object.get(def, "has", null))
} if is_object(subjects)

_p_part_read(alias, entry) := {"from": from, "identified_by": id, "problems": sort(problems)} if {
	from := _p_field_read(entry, "from")
	id := _p_field_read(entry, "identified_by")
	problems := ((_p_alias_problems(alias) | _p_shape_problems(entry)) | _p_prefixed("from", from)) | _p_prefixed("identified_by", id)
}

_p_alias_problems(alias) := {"invalid alias" | not _p_alias_ok(alias)}

_p_shape_problems(entry) := {"not a string or an object"} if {
	not is_string(entry)
	not is_object(entry)
}

_p_shape_problems(entry) := ({concat("", ["unknown field ", _text(f)]) | some f in object.keys(entry); not f in {"from", "identified_by"}} | {"missing from" | not "from" in object.keys(entry)}) | {concat("", ["invalid ", f]) | some f in ["from", "identified_by"]; f in object.keys(entry); not is_string(entry[f])} if is_object(entry)

_p_shape_problems(entry) := set() if is_string(entry)

_p_prefixed(f, read) := {concat("", [f, ": ", p]) |
	is_object(read)
	some p in object.get(read, "problems", [])
}

_p_field_read(entry, "from") := _p_path_read(entry) if is_string(entry)

_p_field_read(entry, f) := _p_path_read(entry[f]) if {
	is_object(entry)
	is_string(object.get(entry, f, null))
}

_p_field_read(entry, f) := {} if {
	is_object(entry)
	f in object.keys(entry)
	not is_string(entry[f])
}

_p_field_read(entry, "identified_by") := null if {
	is_object(entry)
	not "identified_by" in object.keys(entry)
}

_p_field_read(entry, "identified_by") := null if is_string(entry)

_p_field_read(entry, "from") := {} if {
	not is_string(entry)
	not is_object(entry)
}

_p_field_read(entry, "identified_by") := null if {
	not is_string(entry)
	not is_object(entry)
}

_p_field_read(entry, "from") := {} if {
	is_object(entry)
	not "from" in object.keys(entry)
}

_p_path_read(text) := {"path": path, "text": _path_name(path)} if {
	fl := _from_line(text)
	count(_p_path_problems(fl)) == 0
	path := _s_model_path(fl.path)
}

_p_path_read(text) := {"problems": sort(_p_path_problems(_from_line(text)))} if count(_p_path_problems(_from_line(text))) > 0

_p_path_problems(fl) := {p | some p in object.get(fl, "problems", ["doesn't parse"])} if not "path" in object.keys(fl)

_p_path_problems(fl) := ({"a part is a path: whose and named by each of can't go in it" | object.keys(fl) != {"path"}} | {"a part reads inside its subject, so it can't start at $params or $input" | "start" in object.keys(fl.path)}) | _s_from_paths_unsupported({"path": fl.path}) if "path" in object.keys(fl)

_p_valid(read) if {
	read.problems == []
	"path" in object.keys(read.from)
}

_p_lines(subjects) := {name: _from_line(def.from) | some name, def in subjects; is_object(def); is_string(def.from)}

_p_narrow(subjects, lines) := {name: _s_chain_parent(name, lines, subjects) | some name, _ in subjects}

_p_descend(subjects, lines) := {name: lines[name].path.steps[0] | some name, _ in lines; "path" in object.keys(lines[name]); _s_descends(name, lines[name], subjects)}

_p_parts(subjects) := {"own": own, "effective": {name: _p_merged(name, own, narrow) | some name, _ in subjects}, "problems": _p_problems(subjects, own, narrow, descend), "lines": lines, "narrow": narrow, "descend": descend} if {
	is_object(subjects)
	lines := _p_lines(subjects)
	narrow := _p_narrow(subjects, lines)
	descend := _p_descend(subjects, lines)
	own := _p_own_reads(subjects)
}

_p_parts(subjects) := _p_no_parts if not is_object(subjects)

_p_members(name, narrow) := graph.reachable(narrow, [name])

_p_merged(name, own, narrow) := {a: own[_p_owner(a, members, own)][a] | some a in {a | some m in members; some a, _ in object.get(own, m, {})}} if members := sort(_p_members(name, narrow))

_p_owner(a, members, own) := [m | some m in members; a in object.keys(object.get(own, m, {}))][0]

_p_problems(subjects, own, narrow, descend) := {name: probs |
	some name, def in subjects
	is_object(def)
	probs := _p_subject_problems(name, def, own, narrow, descend, subjects)
	count(probs) > 0
}

_p_subject_problems(name, def, own, narrow, descend, subjects) := (({[["has"], "not an object"] | "has" in object.keys(def); not is_object(def.has)} | {[["has", alias], p] | some alias, read in object.get(own, name, {}); some p in read.problems}) | {[["has", alias], concat("", [alias, " can't be an alias: it's a subject's name"])] |
	some alias, _ in object.get(own, name, {})
	alias in object.keys(subjects)
}) | {[["has", alias], concat("", [alias, " can't be an alias: it's a part of ", _p_name_text(declarer)])] |
	some alias, _ in object.get(own, name, {})
	some owner in _p_part_owners(name, narrow, descend)
	some declarer in _p_members(owner, narrow)
	alias in object.keys(object.get(own, declarer, {}))
}

_p_name_text(name) := _s_key_text(name)

_p_part_owners(name, narrow, descend) := ({m | some m in _p_members(name, narrow); m != name} | {a | a := descend[name]}) | {a | a := descend[descend[name]]}

_s_subjects(subjects, reads, parts) := {name: _s_subject(name, def, reads, parts) | some name, def in subjects} if is_object(subjects)

_s_subjects(subjects, _, _) := subjects if not is_object(subjects)

_s_subject(name, null, _, _) := {"from": [name]}

_s_subject(name, def, reads, parts) := object.union(_s_without_narrowed_from(_p_old_filters(def, _p_own_context(name, parts.effective)), reads[name]), object.union(_s_from_fields(name, def, reads), _s_id_field(reads[name]))) if is_object(def)

_s_without_narrowed_from(def, read) := object.remove(def, ["from"]) if {
	"of" in object.keys(object.get(read, "fields", {}))
	_s_from_used(def, read)
} else := def

_s_subject(_, def, _, _) := def if {
	def != null
	not is_object(def)
}

_s_from_fields(name, def, reads) := {"from": [name]} if {
	not "from" in object.keys(def)
	not "of" in object.keys(def)
} else := reads[name].fields if {
	_s_from_used(def, reads[name])
} else := {}

_s_from_used(def, read) if {
	is_string(def.from)
	read.problems == []
	not "applies_to" in object.keys(def)
	not "of" in object.keys(def)
}

_s_from_read(name, fl, subjects, chains) := object.union(object.union({"problems": problems, "fields": fields, "parent": parent, "every": every_list}, _p_from_part(name, fl, subjects, chains.parts)), _s_follows(name, fl, subjects, chains)) if {
	"path" in object.keys(fl)
	names := {a | some a in _s_ancestors(name, chains.descend)}
	keep := names | object.keys(_p_steps_of(object.get(chains.parts, name, {})))
	pc := {"own": _p_steps_of(object.get(chains.parts, name, {})), "ancestors": {a: _p_steps_of(object.get(chains.parts, a, {})) | some a in names}}
	conds := [_p_applied(_s_parent_named(t, _s_check([t], {}, _p_part_walk_problems([t], "", pc), keep), names), pc) | some c in object.get(fl, "where", []); t := _s_cond_text(_s_from_cond(c, names, keep))]
	problems := sort(((((((((_s_chain_unsupported(name, fl, subjects, chains) | _s_loop(name, fl, subjects, chains)) | _s_blank_start(fl, subjects)) | _s_every_unsupported(name, fl, subjects)) | _s_from_start_problems(fl)) | _s_from_paths_unsupported({"path": fl.path})) | _s_elapsed_flaw({"where": object.get(fl, "where", [])})) | {concat("", ["whose: ", p]) | some c in conds; some p in object.get(c, "$sentence", [])}) | {"whose: a condition can't be read" | count(conds) != count(object.get(fl, "where", []))}))
	fields := object.union(_s_source(name, fl, subjects, chains.parts), _s_whose_filters(_s_filter_prefix(name, chains.narrow), conds))
	parent := _s_descend_parent(name, fl, subjects)
	every_list := object.get(fl, "every", false) == true
} else := {"problems": object.get(fl, "problems", ["doesn't parse"]), "fields": {}}

_s_from_cond(c, names, keep) := object.union(c, object.union(
	{q: _s_from_dot(c[q], names, keep) | some q in ["every", "some"]; is_object(object.get(c, q, null))},
	object.union(
		{"path": _s_from_dot(c.path, names, keep) | is_object(object.get(c, "path", null))},
		object.union(
			{"terms": [_s_from_term(t, names, keep) | some t in c.terms] | is_array(object.get(c, "terms", null))},
			{"phrase": _s_from_phrase(c.phrase, keep) | is_object(object.get(c, "phrase", null))},
		),
	),
))

_s_from_phrase(ph, keep) := object.union(ph, object.union(
	{"path": _s_from_dot(ph.path, set(), keep) | is_object(object.get(ph, "path", null))},
	{"terms": [_s_from_term(t, set(), keep) | some t in ph.terms] | is_array(object.get(ph, "terms", null))},
))

_s_from_term(t, names, keep) := object.union(t, {f: _s_from_dot(t[f], names, keep) |
	some f in ["count", "sum", "elapsed_from", "elapsed_to"]
	f in object.keys(t)
}) if {
	is_object(t)
	not "steps" in object.keys(t)
} else := _s_from_dot(t, names, keep)

_s_from_dot(p, names, keep) := object.union(p, {"field": true, "own": false}) if {
	_s_markable(p, keep)
	object.get(p, "dot", false) == true
} else := object.union(p, {"field": true, "own": false}) if {
	_s_markable(p, names)
} else := p

_p_from_part(name, fl, subjects, eff) := {"part": rest[0]} if {
	_s_descends(name, fl, subjects)
	rest := array.slice(_s_model_path(fl.path), 1, count(fl.path.steps))
	count(rest) > 0
	is_string(rest[0])
	rest[0] in object.keys(_p_steps_of(object.get(eff, fl.path.steps[0], {})))
} else := {}

_s_source(name, fl, subjects, eff) := {"of": fl.path.steps[0]} if {
	_s_narrows(name, fl, subjects)
} else := {"from": array.concat(_s_from_steps(_p_descend_steps(array.slice(_s_model_path(fl.path), 1, count(fl.path.steps)), object.get(eff, fl.path.steps[0], {}))), _s_each_step(fl))} if {
	_s_descends(name, fl, subjects)
} else := {"from": array.concat(_s_from_steps(_s_model_path(fl.path)), _s_each_step(fl))}

_s_descend_parent(name, fl, subjects) := fl.path.steps[0] if _s_descends(name, fl, subjects)

else := null

_s_descends(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	count(fl.path.steps) > 1
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
}

_s_narrows(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	fl.path.steps == [fl.path.steps[0]]
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
	not "named_by_each_of" in object.keys(fl)
}

_s_from_steps(path) := [_s_plain_from_step(st) | some st in array.slice(path, 1, count(path))] if {
	count(path) > 0
	path[0] == "$$input"
} else := [_s_plain_from_step(st) | some st in path]

_s_plain_from_step(st) := st.literal if {
	is_object(st)
	object.keys(st) == {"literal"}
} else := st

_s_from_start_problems(fl) := {"a from reads the input, so it can't start at $params" | object.get(fl.path, "start", "") == "params"}

_s_each_step(fl) := [{"each_as": "subject", "keys": {"ref": _s_model_path(fl.named_by_each_of)}}] if "named_by_each_of" in object.keys(fl)

_s_each_step(fl) := [] if not "named_by_each_of" in object.keys(fl)

_s_whose_filters(_, []) := {}

_s_whose_filters(prefix, conds) := {"applies_to": {concat("", [prefix, _s_filter_name(i, count(conds))]): c | some i, c in conds}} if conds != []

_s_filter_prefix(name, chain) := concat("", [_s_pad(count(graph.reachable(chain, [name])) - 1), " ", _text(name), " "])

_s_pad(i) := concat("", [substring("         ", 0, 9 - count(format_int(i, 10))), format_int(i, 10)])

_s_chain_parent(n, lines, subjects) := [lines[n].path.steps[0]] if {
	"path" in object.keys(object.get(lines, n, {}))
	_s_narrows(n, lines[n], subjects)
} else := [subjects[n].of] if {
	is_object(subjects[n])
	is_string(object.get(subjects[n], "of", null))
} else := []

_s_filter_name(i, n) := concat("", ["whose ", strings.replace_n({" ": "0"}, sprintf_pad)]) if {
	width := count(format_int(n - 1, 10))
	digits := format_int(i, 10)
	sprintf_pad := concat("", [substring("                    ", 0, width - count(digits)), digits])
}

_s_every_unsupported(_, fl, _) := set() if object.get(fl, "every", false) != true

_s_every_unsupported(name, fl, subjects) := ({"every can't go with a from line that starts at another subject yet" |
	not "start" in object.keys(fl.path)
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
} | {"every can't go with named by each of: start the from line at a subject to read its names one subject at a time" | "named_by_each_of" in object.keys(fl)}) | {"every over more than ten steps isn't supported yet" | count(_walk_steps(_s_model_path(fl.path))) > 10} if object.get(fl, "every", false) == true

_s_chain_unsupported(name, fl, subjects, chains) := {"a chain of more than three subjects isn't supported yet" |
	_s_descends(name, fl, subjects)
	parent := fl.path.steps[0]
	parent in object.keys(chains.descend)
	chains.descend[parent] in object.keys(chains.descend)
	not _s_in_loop(name, fl, subjects, chains)
}

_s_loop(name, fl, subjects, chains) := {"leads to a loop" | _s_in_loop(name, fl, subjects, chains)}

_s_in_loop(name, fl, subjects, chains) if {
	_s_starts_at_subject(name, fl, subjects)
	links := {n: array.concat(object.get(chains.narrow, n, []), [p | some p in [object.get(chains.descend, n, null)]; p != null]) | some n, _ in subjects}
	some m in graph.reachable(links, [fl.path.steps[0]])
	m in graph.reachable(links, links[m])
}

_s_follows(name, fl, subjects, chains) := {"follows": fl.path.steps[0]} if {
	_s_in_loop(name, fl, subjects, chains)
} else := {"follows": fl.path.steps[0]} if {
	_s_blank_start(fl, subjects) != set()
} else := {}

_s_starts_at_subject(name, fl, subjects) if _s_descends(name, fl, subjects)

_s_starts_at_subject(name, fl, subjects) if _s_narrows(name, fl, subjects)

_s_blank_start(fl, subjects) := {concat("", ["\"", fl.path.steps[0], "\" isn't a subject name"]) |
	not "start" in object.keys(fl.path)
	is_string(fl.path.steps[0])
	fl.path.steps[0] in object.keys(subjects)
	trim_space(fl.path.steps[0]) == ""
}

_s_id_field(read) := {"identified_by": read.identified_by.path} if "path" in object.keys(object.get(read, "identified_by", {}))

else := {}

_s_subject_sentences(subjects, reads, parts) := {"from_parts": {name: r.part | some name, r in reads; _s_from_used(subjects[name], r)}, "lines": parts.lines, "parts": parts.effective, "has_problems": parts.problems, "chains": {name: p | some name, r in reads; _s_from_used(subjects[name], r); p := object.get(r, "parent", null); p != null}, "every": {name | some name, r in reads; _s_from_used(subjects[name], r); object.get(r, "every", false) == true}, "narrowed": {name | some name, r in reads; _s_from_used(subjects[name], r); "of" in object.keys(r.fields)}, "filters": {[name, n] | some name, r in reads; _s_from_used(subjects[name], r); some n, _ in object.get(r.fields, "applies_to", {})}, "problems": {name: probs | some name, def in subjects; probs := _s_subject_problems(name, def, reads); probs != {}}, "follows": {name: r.follows | some name, r in reads; "follows" in object.keys(r)}} if is_object(subjects)

_s_subject_sentences(subjects, _, _) := {"from_parts": {}, "lines": {}, "parts": {}, "has_problems": {}, "chains": {}, "every": set(), "narrowed": set(), "filters": set(), "problems": {}, "follows": {}} if not is_object(subjects)

_s_subject_problems(name, def, reads) := {f: ps | some f in ["applies_to", "from", "identified_by", "of"]; ps := _s_field_problems(name, def, f, reads); ps != []} if is_object(def)

_s_subject_problems(_, def, _) := {} if not is_object(def)

_s_field_problems(name, def, "from", reads) := reads[name].problems if is_string(object.get(def, "from", null))

_s_field_problems(name, def, "identified_by", reads) := object.get(reads[name].identified_by, "problems", []) if is_string(object.get(def, "identified_by", null))

_s_field_problems(_, def, f, _) := ["not a string"] if {
	f in {"from", "identified_by"}
	f in object.keys(def)
	not is_string(def[f])
}

_s_field_problems(_, def, f, _) := [] if {
	f in {"from", "identified_by"}
	not f in object.keys(def)
}

_s_field_problems(_, def, f, _) := ["unknown field"] if {
	f in {"applies_to", "of"}
	f in object.keys(def)
}

_s_field_problems(_, def, f, _) := [] if {
	f in {"applies_to", "of"}
	not f in object.keys(def)
}

_p_no_parts := {"own": {}, "effective": {}, "problems": {}, "lines": {}, "narrow": {}, "descend": {}}

_p_aliases(req, parts) := {alias | some alias, _ in object.get(parts.effective, req.subject, {})} if is_string(object.get(req, "subject", null))

_p_aliases(req, _) := set() if not is_string(object.get(req, "subject", null))

_p_named_by_problems(lines, ftext, aliases) := {concat("", ["named by ", ref.steps[0], " reads a part, which isn't supported yet"]) |
	aliases != set()
	some node in array.concat([n | some line in lines; is_string(line); some n in _s_nodes(_sentence(line))], [n | is_string(ftext); some n in _s_nodes(_for_line(ftext))])
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
	ref.steps[0] in aliases
}

_p_named_by_problems(_, _, aliases) := set() if aliases == set()

_p_for_clash(check, pc) := {concat("", [item.as, " can't be an alias: it's a subject's name"]) |
	some item in _p_for_items(check)
	item.as in pc.subjects
} | {concat("", [item.as, " can't be an alias: it's a part of ", _p_name_text(declarer)]) |
	some item in _p_for_items(check)
	some _, owned in pc.part_owners
	some declarer in object.get(owned, item.as, set())
}

_p_for_clash(check, _) := set() if not is_string(object.get(check, "for", ""))

_p_for_items(check) := object.get(_for_line(check.for), "items", []) if is_string(check.for)

_p_part_walk_problems(_, _, pc) := set() if _p_idle(pc)

_p_part_walk_problems(lines, ftext, pc) := {"every and some over more than ten steps aren't supported yet" |
	some w in _p_part_walks(lines, ftext, pc)
	_p_part_walk_steps(w, pc) > 10
} if not _p_idle(pc)

_p_part_walks(lines, ftext, pc) := {p |
	some line in lines
	is_string(line)
	some a in object.get(_sentence(line), "assertions", [])
	some p in _p_walk_paths(_s_aliased(a, _s_names(set(), _p_unaliased(ftext, object.keys(pc.own)) | object.keys(pc.ancestors))))
} | {p |
	is_string(ftext)
	fl := _for_line(ftext)
	some item in _s_marked_items(fl, object.keys(pc.own) | object.keys(pc.ancestors))
	some p in _p_walk_paths(_s_unpicked(item))
}

_p_unaliased(ftext, names) := names - {item.as |
	is_string(ftext)
	some item in object.get(_for_line(ftext), "items", [])
}

_p_walk_paths(x) := {[x[q], false] | some q in ["every", "some", "pick"]; is_object(object.get(x, q, null))} | ({[t[k], false] | some t in _s_nodes(object.remove(x, _p_item_keys(x))); some k in _p_derived_keys(t)} | {[t[k], true] | _p_walks_items(x); some t in _s_nodes(object.filter(x, _p_item_keys(x))); some k in _p_derived_keys(t)})

_p_walks_items(x) if object.keys(x) & {"every", "some", "pick"} != set()

_p_derived_keys(t) := {k |
	_s_derived_term(t)
	some k in ["count", "sum"]
	is_object(object.get(t, k, null))
}

_p_item_keys(x) := ["where", "phrase"] if object.keys(x) & {"every", "some", "pick"} != set()

else := ["where"]

_p_part_walk_steps([p, false], pc) := (count(_walk_steps(_s_model_path(p))) - 1) + count(pc.own[p.steps[0]]) if {
	object.get(p, "part", false) == true
	p.steps[0] in object.keys(pc.own)
} else := _p_parent_walk_steps(p, pc)

_p_part_walk_steps([p, true], pc) := _p_parent_walk_steps(p, pc)

_p_parent_walk_steps(p, pc) := (count(_walk_steps(_s_model_path(p))) - 2) + count(pc.ancestors[p.steps[0]][p.steps[1]]) if {
	object.get(p, "part", false) == true
	p.steps[1] in object.keys(pc.ancestors[p.steps[0]])
} else := 0

_p_steps_of(parts) := {alias: read.from.path | some alias, read in parts; _p_valid(read)}

_p_own_context(name, eff) := {"own": _p_steps_of(object.get(eff, name, {})), "ancestors": {}}

_p_context(req, chains, parts) := {"own": _p_steps_of(object.get(parts.effective, req.subject, {})), "ancestors": {a: _p_steps_of(object.get(parts.effective, a, {})) | some a in _s_ancestors(req.subject, chains)}, "subjects": object.keys(parts.effective), "part_owners": {s: {a: {m | some m in _p_members(s, parts.narrow); a in object.keys(object.get(parts.own, m, {}))} | some a, _ in object.get(parts.effective, s, {})} | some s in array.concat([req.subject], _s_ancestors(req.subject, chains))}} if {
	is_string(object.get(req, "subject", null))
} else := {"own": {}, "ancestors": {}, "subjects": object.keys(parts.effective), "part_owners": {}}

_s_ancestors(name, chains) := array.concat([chains[name]], [chains[chains[name]] | chains[name] in object.keys(chains)]) if name in object.keys(chains)

else := []

_p_idle(pc) if {
	pc.own == {}
	every _, steps in pc.ancestors {
		steps == {}
	}
}

_p_applied(m, pc) := m if _p_idle(pc)

_p_applied(m, pc) := m if {
	not _p_idle(pc)
	"$sentence" in object.keys(m)
}

_p_applied(m, pc) := _p_smodel(m, pc) if {
	not _p_idle(pc)
	not "$sentence" in object.keys(m)
}

_p_applied_to(_, model, pc) := model if _p_idle(pc)

_p_applied_to(written, model, pc) := model if {
	not _p_idle(pc)
	not _s_written_as_sentence(written)
}

_p_applied_to(written, model, pc) := _p_applied(model, pc) if {
	not _p_idle(pc)
	_s_written_as_sentence(written)
}

_p_old_filters(def, pc) := def if _p_idle(pc)

_p_old_filters(def, pc) := def if {
	not _p_idle(pc)
	not is_object(object.get(def, "applies_to", null))
}

_p_descend_steps(rest, parts) := array.concat(_p_steps_of(parts)[rest[0]], array.slice(rest, 1, count(rest))) if {
	count(rest) > 0
	is_string(rest[0])
	rest[0] in object.keys(_p_steps_of(parts))
} else := rest

_p_marker(alias, n, of, old) := concat("", ["${\"alias\":", json.marshal(alias), ",\"n\":", format_int(n, 10), ",\"of\":", json.marshal(of), ",\"old\":", json.marshal(old), "}"])

_p_item_mode(mode) := "i" if mode != "o"

_p_path(path, pc, "s") := array.concat(array.concat([_p_marker(path[0], count(pc.own[path[0]]), null, false)], pc.own[path[0]]), array.slice(path, 1, count(path))) if {
	is_array(path)
	count(path) > 0
	is_string(path[0])
	not startswith(path[0], "$")
	path[0] in object.keys(pc.own)
} else := _p_parent_path(path, pc)

_p_path(path, pc, "i") := _p_parent_path(path, pc)

_p_path(path, pc, "o") := array.concat(array.concat([_p_marker(alias, count(pc.own[alias]), null, true)], pc.own[alias]), array.slice(path, 1, count(path))) if {
	is_array(path)
	count(path) > 0
	is_string(path[0])
	startswith(path[0], "$")
	not startswith(path[0], "$$")
	alias := substring(path[0], 1, -1)
	alias in object.keys(pc.own)
}

_p_parent_path(path, pc) := array.concat(array.concat([_p_marker(path[1], count(pc.ancestors[a][path[1]]), a, false)], pc.ancestors[a][path[1]]), array.slice(path, 2, count(path))) if {
	is_array(path)
	count(path) > 1
	is_string(path[0])
	a := substring(path[0], 1, -1)
	path[0] == concat("", ["$", a])
	a in object.keys(pc.ancestors)
	is_string(path[1])
	path[1] in object.keys(pc.ancestors[a])
} else := path

_p_smodel(m, pc) := object.union(m, {"checks": [_p_sleaf(c, pc) | some c in m.checks]}) if m.op in {"all_of", "sentence_any_of"}

_p_smodel(m, pc) := object.union(m, {
	"checks": [_p_sleaf(c, pc) | some c in m.checks],
	"items": [object.union(item, {"path": _p_path(item.path, pc, "s"), "whose": [_p_leaf(c, pc, "i") | some c in item.whose]}) | some item in m.items],
}) if m.op == "for"

_p_smodel(m, pc) := _p_sleaf(m, pc) if not m.op in {"all_of", "sentence_any_of", "for"}

_p_sleaf(m, pc) := object.union(m, {
	"path": _p_path(m.path, pc, "s"),
	"whose": [_p_leaf(c, pc, "i") | some c in m.whose],
	"check": _p_leaf(m.check, pc, "i"),
}) if m.op in {"every", "some"}

_p_sleaf(m, pc) := _p_leaf(m, pc, "s") if not m.op in {"every", "some"}

_p_leaf(m, pc, mode) := object.union(object.union(m, {f: _p_item_side(f, m[f], pc, mode) | some f in ["path", "left", "right"]; f in object.keys(m)}), {"inputs": [_p_side(i, pc, mode) | some i in m.inputs] | is_array(object.get(m, "inputs", null))})

_p_item_side(f, side, pc, mode) := _p_path(_p_own_named(side), pc, "o") if {
	_p_own_on_item_right(f, side, pc, mode)
} else := _p_side(side, pc, mode)

_p_own_on_item_right(f, side, pc, mode) if {
	f == "right"
	mode == "i"
	is_array(side)
	count(side) > 0
	is_string(side[0])
	not startswith(side[0], "$")
	side[0] in object.keys(pc.own)
}

_p_own_named(side) := array.concat([concat("", ["$", side[0]])], array.slice(side, 1, count(side)))

_p_side(side, pc, mode) := _p_path(side, pc, mode) if is_array(side)

_p_side(side, pc, mode) := object.union(side, {"add": [_p_side_one(o, pc, mode) | some o in side.add]}) if {
	is_object(side)
	is_array(object.get(side, "add", null))
}

_p_side(side, pc, mode) := _p_side_one(side, pc, mode) if {
	is_object(side)
	not "add" in object.keys(side)
}

_p_side_one(side, pc, mode) := _p_path(side, pc, mode) if is_array(side)

_p_side_one(side, pc, mode) := object.union(_p_tally(side, pc, mode), object.union({"whose": [_p_cond(c, pc, _p_item_mode(mode)) | some c in side.whose] | is_array(object.get(side, "whose", null))}, {"where": _p_cond(side.where, pc, _p_item_mode(mode)) | is_object(object.get(side, "where", null))})) if is_object(side)

_p_tally(side, pc, mode) := object.union(side, {f: _p_path(side[f], pc, mode) | some f in ["count_of", "sum_of", "elapsed_from", "elapsed_to"]; is_array(object.get(side, f, null))})

_p_cond(c, pc, mode) := object.union(c, {f: _p_cond_side(f, c[f], pc, mode) | some f in ["path", "left", "right"]; is_array(object.get(c, f, null))}) if is_object(c)

_p_cond_side(f, side, pc, mode) := _p_path(_p_own_named(side), pc, "o") if {
	_p_own_on_item_right(f, side, pc, mode)
} else := _p_path(side, pc, mode)

_s_requirements(reqs, chains) := _p_requirements(reqs, chains, _p_no_parts)

_p_requirements(reqs, chains, parts) := {name: _p_requirement(req, chains, parts) | some name, req in reqs} if is_object(reqs)

_p_requirements(reqs, _, _) := reqs if not is_object(reqs)

_p_requirement(req, chains, parts) := object.union(object.remove(req, ["checks"]), {"checks": {name: _p_applied_to(check, _s_parent_named(check, _p_written(check, aliases, _s_parents_of(req, chains), pc), _s_parents_of(req, chains)), pc) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
	aliases := _p_aliases(req, parts)
	pc := _p_context(req, chains, parts)
} else := req

_s_parents_of(req, chains) := {a | some a in _s_ancestors(req.subject, chains)} if {
	is_string(object.get(req, "subject", null))
	req.subject in object.keys(chains)
} else := set()

_s_parent_named(_, model, names) := model if names == set()

_s_parent_named(written, model, _) := model if not _s_written_as_sentence(written)

_s_parent_named(written, model, names) := model if {
	names != set()
	_s_written_as_sentence(written)
	"$sentence" in object.keys(model)
}

_s_parent_named(written, model, names) := _s_named_model(model, names) if {
	names != set()
	_s_written_as_sentence(written)
	not "$sentence" in object.keys(model)
}

_s_named_model(m, names) := object.union(m, {"checks": [_s_named_model_leaf(c, names) | some c in m.checks]}) if m.op in {"all_of", "sentence_any_of"}

_s_named_model(m, names) := object.union(m, {
	"checks": [_s_named_model_leaf(c, names) | some c in m.checks],
	"items": [object.union(item, {"path": _s_named_path(item.path, names), "whose": [_s_named(c, names) | some c in item.whose]}) | some item in m.items],
}) if m.op == "for"

_s_named_model(m, names) := _s_named_model_leaf(m, names) if not m.op in {"all_of", "sentence_any_of", "for"}

_s_named_model_leaf(m, names) := object.union(m, {
	"path": _s_named_path(m.path, names),
	"whose": [_s_named(c, names) | some c in m.whose],
	"check": object.union(_s_named(m.check, names), object.filter(m.check, {"path", "left"})),
}) if m.op in {"every", "some"}

_s_named_model_leaf(m, names) := _s_named(m, names) if not m.op in {"every", "some"}

_s_written_check(check) := _p_written(check, set(), set(), _p_context({}, {}, _p_no_parts))

_p_written(check, aliases, parents, pc) := _s_check([check], {}, _p_named_by_problems([check], "", aliases) | _p_part_walk_problems([check], "", pc), aliases | parents) if is_string(check)

_p_written(check, aliases, parents, pc) := _s_check(_s_lines(check.assert), object.filter(check, {"description", "meta"}), ((_s_form_problems(check) | _p_named_by_problems(_s_lines(check.assert), "", aliases)) | _p_part_walk_problems(_s_lines(check.assert), "", pc)), aliases | parents) if {
	_s_assert_form(check)
	"assert" in object.keys(check)
	not "for" in object.keys(check)
}

_p_written(check, aliases, parents, pc) := _s_check_for(_s_lines(check.assert), check.for, object.filter(check, {"description", "meta"}), (((_s_form_problems(check) | _p_for_clash(check, pc)) | _p_named_by_problems(_s_lines(check.assert), object.get(check, "for", ""), aliases)) | _p_part_walk_problems(_s_lines(check.assert), check.for, pc)), aliases | parents) if {
	_s_assert_form(check)
	"assert" in object.keys(check)
	"for" in object.keys(check)
}

_p_written(check, _, _, _) := object.union(object.filter(check, {"description", "meta"}), {"expression": "<missing assert>", "$sentence": sort(_s_form_problems(check))}) if {
	_s_assert_form(check)
	not "assert" in object.keys(check)
}

_p_written(check, aliases, parents, pc) := _s_any_of(check, aliases, aliases | parents, pc) if _s_any_of_form(check)

_s_lines(a) := a if is_array(a)

_s_lines(a) := [a] if not is_array(a)

_p_written(check, _, _, _) := check if not _s_written_as_sentence(check)

_s_written_as_sentence(check) if is_string(check)

_s_written_as_sentence(check) if _s_assert_form(check)

_s_written_as_sentence(check) if _s_any_of_form(check)

_s_any_of_form(check) if {
	is_object(check)
	"any_of" in object.keys(check)
	not "assert" in object.keys(check)
}

_s_any_of(check, aliases, names, pc) := object.union(object.filter(check, {"description", "meta"}), {
	"op": "sentence_any_of",
	"checks": [object.remove(p[0], ["expression"]) | some p in pairs],
	"assertions": [p[1] | some p in pairs],
	"option_of": [p[2] | some p in pairs],
	"places": [place | some nm in _names(options); some place in _s_option_places(nm, _s_lines(check.any_of[nm]))],
	"expression": _one_of([[_text(nm), _option_text(nm, texts, texts)] | some nm in _names(options); texts := [p[1] | some p in pairs; p[2] == nm]]),
}) if {
	count(_s_any_of_problems(check)) == 0
	options := {nm: _s_check(_s_lines(o), {}, _p_named_by_problems(_s_lines(o), "", aliases) | _p_part_walk_problems(_s_lines(o), "", pc), names) | some nm, o in check.any_of}
	every m in options {
		not "$sentence" in object.keys(m)
	}
	pairs := [p | some nm in _names(options); some p in _s_option_lines(options[nm], nm)]
} else := object.union(object.filter(check, {"description", "meta"}), {
	"expression": _s_any_of_written(check.any_of),
	"$sentence": sort(_s_or_unrunnable(_s_any_of_problems(check) | _s_options_problems(check.any_of, aliases, names, pc))),
})

_s_option_lines(m, nm) := [[c, m.assertions[i], nm] | some i, c in m.checks] if m.op == "all_of"

_s_option_lines(m, nm) := [[m, m.expression, nm]] if m.op != "all_of"

_s_option_places(nm, lines) := [_s_option_place(nm, i, count(lines)) | some i, line in lines; some _ in _sentence(line).assertions]

_s_option_place(nm, _, 1) := concat("", ["option ", _text(nm)])

_s_option_place(nm, i, n) := concat("", ["option ", _text(nm), ": line ", _literal_text(i + 1)]) if n > 1

_s_any_of_problems(check) := {concat("", ["unknown field ", _text(f)]) | some f in object.keys(check); not f in {"any_of", "description", "meta"}} | _s_options_shape(check.any_of)

_s_options_shape(options) := {"invalid any_of"} if not is_object(options)

_s_options_shape({}) := {"empty any_of"}

_s_options_shape(options) := {_s_option_shape(nm, o) | some nm, o in options; _s_option_shape(nm, o) != ""} if {
	is_object(options)
	options != {}
}

_s_option_shape(nm, o) := concat("", ["empty option ", _text(nm)]) if o == []

else := concat("", ["invalid option ", _text(nm)]) if not _s_option_written(o)

else := ""

_s_option_written(o) if is_string(o)

_s_option_written(o) if {
	is_array(o)
	every line in o {
		is_string(line)
	}
}

_s_options_problems(options, aliases, names, pc) := {concat("", ["option ", _text(nm), ": ", p]) |
	some nm, o in options
	_s_option_written(o)
	o != []
	m := _s_check(_s_lines(o), {}, _p_named_by_problems(_s_lines(o), "", aliases) | _p_part_walk_problems(_s_lines(o), "", pc), names)
	some p in object.get(m, "$sentence", [])
} if is_object(options)

else := set()

_s_any_of_written(options) := _one_of([[_text(nm), _s_option_written_text(nm, o)] | some nm, o in options]) if is_object(options)

else := "<invalid any_of>"

_s_option_written_text(nm, o) := _option_text(nm, texts, texts) if {
	_s_option_written(o)
	texts := [_s_written_text(line) | some line in _s_lines(o)]
} else := _option_text(nm, null, [])

_s_assert_form(check) if {
	is_object(check)
	not _s_any_of_form(check)
}

_s_sentences(raw, reqs) := {[reqs[name], c] |
	some name, req in raw
	is_object(req)
	checks := object.get(req, "checks", {})
	is_object(checks)
	some c, check in checks
	_s_written_as_sentence(check)
} if is_object(raw)

else := set()

_s_form_problems(check) := ({concat("", ["unknown field ", _text(f)]) | some f in object.keys(check); not f in {"assert", "description", "meta", "for"}} | _s_assert_problems(check)) | _s_for_problem(check)

_s_assert_problems(check) := _s_assert_problem(check.assert) if "assert" in object.keys(check)

_s_assert_problems(check) := {"missing assert"} if not "assert" in object.keys(check)

_s_for_problem(check) := {"invalid for" | "for" in object.keys(check); not is_string(check.for)}

_s_assert_problem(a) := set() if is_string(a)

_s_assert_problem(a) := {"empty assert"} if a == []

_s_assert_problem(a) := {"invalid assert" | some line in a; not is_string(line)} if {
	is_array(a)
	a != []
}

_s_assert_problem(a) := {"invalid assert"} if {
	not is_string(a)
	not is_array(a)
}

_s_check(lines, wording, problems, parts) := object.union(wording, object.union(model, {"expression": _s_check_text({"assertions": marked})})) if {
	count(problems) == 0
	parsed := [_sentence(line) | some line in lines]
	every p in parsed {
		"assertions" in object.keys(p)
	}
	assertions := [a | some p in parsed; some a in p.assertions]
	count({u | some a in assertions; some u in _s_assertion_unsupported(a)}) == 0
	marked := [_s_aliased(a, _s_names(set(), parts)) | some a in assertions]
	count(_s_self_problems(marked)) == 0
	model := _s_model_of(marked)
} else := object.union(wording, {"expression": concat(" and ", [_s_written_text(line) | some line in lines]), "$sentence": sort(_s_or_unrunnable(((problems | _s_lines_problems(lines)) | _s_lines_self(lines, _s_names(set(), parts)))))})

_s_lines_self([line], names) := _s_line_self(line, names)

_s_lines_self(lines, names) := {concat("", ["line ", _literal_text(i + 1), ": ", p]) | some i, line in lines; some p in _s_line_self(line, names)} if count(lines) > 1

_s_lines_self([], _) := set()

_s_line_self(line, names) := _s_self_problems([_s_aliased(a, names) | some a in parsed.assertions]) if {
	is_string(line)
	parsed := _sentence(line)
	"assertions" in object.keys(parsed)
} else := set()

_s_model_of([a]) := _s_model(a)

_s_model_of(assertions) := {"op": "all_of", "checks": models, "assertions": [_s_assertion_text(a) | some a in assertions]} if {
	count(assertions) > 1
	models := [_s_model(a) | some a in assertions]
	count(models) == count(assertions)
}

_s_lines_problems([line]) := _s_unread_problems(line)

_s_lines_problems(lines) := {concat("", ["line ", _literal_text(i + 1), ": ", p]) | some i, line in lines; some p in _s_unread_problems(line)} if count(lines) > 1

_s_lines_problems([]) := set()

_s_or_unrunnable(problems) := problems if count(problems) > 0

_s_or_unrunnable(problems) := {"can't be run"} if count(problems) == 0

_s_written_text(text) := trim_space(text) if is_string(text)

_s_written_text(text) := "<invalid assert>" if not is_string(text)

_s_unread_problems(text) := set() if not is_string(text)

_s_unread_problems(text) := {p | some p in object.get(parsed, "problems", [])} | _s_unsupported(parsed) if {
	is_string(text)
	parsed := _sentence(text)
}

_s_unread(node, here) if {
	_s_read(node, here)
	count(object.get(node, "$sentence", [])) > 0
}

_s_read(node, true) if is_object(node)

_s_written_here(req, "checks", n) if {
	[req, n] in data.ergo_sentences
} else := false

_s_written_here(req, "applies_to", n) if {
	some m in data.ergo_resolved[req.subject].members
	[m, n] in data.ergo_subject_sentences.filters
} else := false

_s_unsupported(parsed) := set() if not "assertions" in object.keys(parsed)

_s_unsupported(parsed) := {u | some a in parsed.assertions; some u in _s_assertion_unsupported(a)} if "assertions" in object.keys(parsed)

_s_assertion_unsupported(a) := ((((_s_paths_unsupported(a) | _s_argument_unsupported(a.phrase)) | {u | some c in object.get(a, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(a)) | _s_derived_too_long(a)) | {"count of, sum of and plus after every or some aren't supported yet" |
	terms := object.get(a.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
} if object.keys(a) & {"every", "some"} != set()

_s_cond_unsupported(c) := _s_derived_unsupported(c) if "terms" in object.keys(c)

_s_cond_unsupported(c) := _s_argument_unsupported(c.phrase) | _s_derived_too_long(c) if not "terms" in object.keys(c)

_s_walk_too_long(a) := {"every and some over more than ten steps aren't supported yet" | count(_walk_steps(_s_model_path(a[_s_quantifier_of(a)]))) > 10}

_s_assertion_unsupported(a) := _s_derived_unsupported(a) if "terms" in object.keys(a)

_s_derived_unsupported(a) := (_s_paths_unsupported(a) | {u | some c in object.get(a, "where", []); some u in _s_tally_cond_unsupported(c)}) | _s_derived_too_long(a)

_s_derived_too_long(a) := {"every and some over more than ten steps aren't supported yet" |
	some t in _s_nodes(a)
	_s_derived_term(t)
	count(_walk_steps(_s_model_path(object.get(t, "count", object.get(t, "sum", null))))) > 10
}

_s_tally_cond_unsupported(c) := ({"a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	"terms" in object.keys(c)
	not _s_one_elapsed(c.terms)
	not _s_one_count(c.terms)
} | {"a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	terms := object.get(c.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
	not _s_one_elapsed(terms)
	not _s_one_count(terms)
}) | _s_argument_unsupported(c.phrase)

_s_one_count(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"count" in object.keys(terms[0])
}

_s_one_elapsed(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"elapsed_from" in object.keys(terms[0])
}

_s_assertion_unsupported(a) := (_s_paths_unsupported(a) | _s_argument_unsupported(a.phrase)) | _s_derived_too_long(a) if object.keys(a) & {"every", "some", "terms"} == set()

_s_model(a) := _s_leaf_model(a) if _s_quantifier_of(a) == ""

_s_model(a) := {
	"op": q,
	"path": _s_model_path(a[q]),
	"check": _s_leaf_model(object.union(object.remove(a, ["every", "some", "where", "if_any"]), {"path": {"steps": ["x"]}})),
	"whose": [_s_leaf_model(c) | some c in object.get(a, "where", [])],
	"if_any": object.get(a, "if_any", false),
} if {
	q := _s_quantifier_of(a)
	q != ""
}

_s_paths_unsupported(a) := {`last of isn't supported yet here: pick the item on a for line, like "for: last of commits as commit"` |
	some node in _s_nodes(a)
	is_object(node)
	_s_from_last(node)
} | _s_elapsed_unsupported(a)

_s_from_last(node) if object.get(node, "position", null) == "last"

_s_from_last(node) if object.get(node, "from_last", false) == true

_s_elapsed_unsupported(a) := _s_elapsed_flaw(_s_whose_stripped(_s_without_terms(a)))

_s_elapsed_flaw(x) := {"an elapsed time isn't supported yet after every or some, or in a from line" |
	some node in _s_nodes(x)
	is_object(node)
	"elapsed_from" in object.keys(node)
}

_s_whose_stripped(a) := object.union(object.remove(a, ["where"]), {"where": [_s_cond_stripped(c) | some c in a.where]}) if "where" in object.keys(a)

_s_whose_stripped(a) := a if not "where" in object.keys(a)

_s_cond_stripped(c) := object.union(object.remove(c, ["terms", "phrase"]), {"phrase": object.remove(c.phrase, ["terms"])})

_s_without_terms(a) := object.union(object.remove(a, ["terms", "phrase"]), {"phrase": object.remove(a.phrase, ["terms"])}) if {
	"phrase" in object.keys(a)
	object.keys(a) & {"every", "some"} == set()
}

_s_without_terms(a) := a if not _s_stripped(a)

_s_stripped(a) if {
	"phrase" in object.keys(a)
	object.keys(a) & {"every", "some"} == set()
}

_s_from_paths_unsupported(a) := _s_paths_unsupported(a) | {concat("", ["unknown alias ", ref.steps[0]]) |
	some node in _s_nodes(a)
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
}

_s_argument_unsupported(ph) := {concat("", [`"`, _s_phrase_words(ph), `" can't take a count of, a sum of or a plus`])} if {
	terms := object.get(ph, "terms", [])
	terms != []
	not _s_one_path(terms)
	not ph.op in object.keys(_s_derived_cmps)
}

default _s_argument_unsupported(_) := set()

_s_one_path(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"steps" in object.keys(terms[0])
}

_s_list_ops := {"is one of", "is not one of", "contains", "does not contain", "contains all of", "contains none of", "matches", "does not match"}

_s_list_path(ph) := ph.path if "path" in object.keys(ph)

_s_list_path(ph) := ph.terms[0] if {
	"terms" in object.keys(ph)
	_s_one_path(ph.terms)
}

_s_takes := object.union({op: "a time or a number" | some op, _ in _s_time_cmps}, {op: "a number" | some op, _ in _s_order_cmps})

_s_takes_value(op, v) if {
	op in object.keys(_s_time_cmps)
	_s_time_value(v)
}

_s_takes_value(op, v) if {
	op in object.keys(_s_order_cmps)
	is_number(v)
}

_s_takes_value(_, v) if {
	is_object(v)
	"out_of_range" in object.keys(v)
}

_s_time_value(v) if is_number(v)

_s_time_value(v) if _rfc3339_shaped(v)

_s_time_value(v) if _date_shaped(v)

_s_time_cmps := {"is before": "lt", "is after": "gt", "is on or after": "gte", "is on or before": "lte"}

_s_order_cmps := {"is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

_s_leaf_model(a) := object.union({"op": "compare", "left": _s_left_side(a.terms, object.get(a, "where", [])), "cmp": _s_derived_cmps[a.phrase.op], "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within", "max"})) if "terms" in object.keys(a)

_s_leaf_model(a) := _s_plain_model(a) if not "terms" in object.keys(a)

_s_cond_model(c) := _s_plain_model(c) if not "terms" in object.keys(c)

_s_cond_model(c) := object.union({"op": "compare", "left": _s_bare_side(c.terms), "cmp": _s_derived_cmps[c.phrase.op], "right": _s_side(c.phrase)}, object.filter(c.phrase, {"within", "max"})) if "terms" in object.keys(c)

_s_derived_cmps := {"is between": "gte", "is": "eq", "is not": "ne", "is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

_s_plain_model(a) := {"op": "equals", "path": _s_model_path(a.path), "value": a.phrase.value} if {
	a.phrase.op == "is"
	"value" in object.keys(a.phrase)
	not "within" in object.keys(a.phrase)
}

_s_plain_model(a) := object.union({"op": "compare", "left": _s_model_path(a.path), "cmp": "eq", "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within"})) if {
	a.phrase.op == "is"
	_s_side_given(a.phrase)
}

_s_plain_model(a) := {"op": "compare", "left": _s_model_path(a.path), "cmp": "ne", "right": _s_side(a.phrase)} if a.phrase.op == "is not"

_s_plain_model(a) := {"op": _s_compare_ops[a.phrase.op][0], "left": _s_model_path(a.path), "cmp": _s_compare_ops[a.phrase.op][1], "right": _s_side(a.phrase)} if a.phrase.op in object.keys(_s_compare_ops)

_s_plain_model(a) := {"op": "in", "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op == "is one of"
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "has_type", "path": _s_model_path(a.path), "type": a.phrase.type} if a.phrase.op == "is a"

_s_plain_model(a) := {"op": "not_in", "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op == "is not one of"
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "present", "path": _s_model_path(a.path)} if a.phrase.op == "exists"

_s_plain_model(a) := {"op": "missing", "path": _s_model_path(a.path)} if a.phrase.op == "does not exist"

_s_plain_model(a) := {"op": "non_empty_string", "path": _s_model_path(a.path)} if a.phrase.op == "is a non-empty string"

_s_plain_model(a) := {"op": "empty_string_or_list", "path": _s_model_path(a.path)} if a.phrase.op == "is empty"

_s_plain_model(a) := {"op": "not_empty_string_or_list", "path": _s_model_path(a.path)} if a.phrase.op == "is not empty"

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "value": _s_one(a.phrase)} if {
	a.phrase.op in {"contains", "does not contain"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op in {"contains all of", "contains none of"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "patterns": _s_list(a.phrase)} if {
	a.phrase.op in {"matches", "does not match"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := object.union({"op": "compare", "left": _s_model_path(a.path), "cmp": _s_list_cmps[a.phrase.op], "right": _s_model_path(_s_list_path(a.phrase))}, _s_shown_inputs(a)) if _s_field_arg(a.phrase)

_s_shown_inputs(a) := {"inputs": [_s_model_path(a.path)]} if _s_named_arg(a.phrase)

_s_shown_inputs(a) := {} if not _s_named_arg(a.phrase)

_s_field_arg(ph) if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	not "start" in object.keys(p)
}

_s_field_arg(ph) if _s_named_arg(ph)

_s_named_arg(ph) if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	"start" in object.keys(p)
	some s in p.steps
	is_object(s)
	"named_by" in object.keys(s)
}

_s_list_cmps := {
	"is one of": "in",
	"is not one of": "not_in",
	"contains": "includes",
	"does not contain": "excludes",
	"contains all of": "includes_all",
	"contains none of": "excludes_all",
	"matches": "matches_any",
	"does not match": "not_matches_any",
}

_s_plain_model(a) := {"op": "range", "path": _s_model_path(a.path), "min": a.phrase.min, "max": a.phrase.max} if a.phrase.op == "is between"

_s_compare_ops := object.union(
	object.union({op: ["compare", cmp] | some op, cmp in _s_order_cmps}, {op: ["compare_time", cmp] | some op, cmp in _s_time_cmps}),
	{"starts with": ["compare", "starts_with"], "ends with": ["compare", "ends_with"], "is alphabetically before": ["compare", "alphabetically_before"], "is alphabetically after": ["compare", "alphabetically_after"]},
)

_s_contains_ops := {
	"contains": "includes",
	"does not contain": "excludes",
	"contains all of": "includes",
	"contains none of": "excludes",
	"matches": "matches_any",
	"does not match": "not_matches_any",
}

_s_side_given(ph) if "terms" in object.keys(ph)

_s_side_given(ph) if "within" in object.keys(ph)

_s_side(ph) := {"literal": ph.value} if "value" in object.keys(ph)

_s_side(ph) := {"literal": ph.min} if ph.op == "is between"

_s_side(ph) := _s_bare_side(ph.terms) if "terms" in object.keys(ph)

_s_bare_side([t]) := _s_term_side(t)

_s_bare_side(terms) := {"add": [_s_term_side(t) | some t in terms], "text": _s_terms_text(terms)} if count(terms) > 1

_s_left_side(terms, []) := _s_bare_side(terms)

_s_left_side(terms, where) := _s_whose_side(terms[0], where) if {
	where != []
	count(terms) == 1
}

_s_left_side(terms, where) := {"add": array.concat([_s_term_side(t) | some t in array.slice(terms, 0, count(terms) - 1)], [_s_whose_side(terms[count(terms) - 1], where)]), "text": concat("", [_s_terms_text(terms), _s_where_text({"where": where})])} if {
	where != []
	count(terms) > 1
}

_s_whose_side(t, where) := object.union(_s_term_side(t), {"whose": [_s_cond_model(c) | some c in where], "text": concat("", [_s_term_text(t), _s_where_text({"where": where})])})

_s_term_side(t) := {"literal": t} if is_number(t)

_s_term_side(t) := {"unit": t.unit, "elapsed_from": _s_model_path(t.elapsed_from), "elapsed_to": _s_model_path(t.elapsed_to), "text": _s_term_text(t)} if {
	is_object(t)
	"elapsed_from" in object.keys(t)
}

_s_term_side(t) := _s_model_path(t) if {
	is_object(t)
	"steps" in object.keys(t)
}

_s_term_side(t) := {concat("", [k, "_of"]): _s_model_path(t[k]), "whose": [], "text": _s_term_text(t)} if {
	is_object(t)
	some k in ["count", "sum"]
	k in object.keys(t)
}

_s_one(ph) := ph.value if "value" in object.keys(ph)

_s_one(ph) := {"ref": _s_model_path(ph.terms[0])} if "terms" in object.keys(ph)

_s_list(ph) := ph.values if "values" in object.keys(ph)

_s_list(ph) := {"ref": _s_model_path(ph.path)} if "path" in object.keys(ph)

_s_model_path(p) := array.concat(array.concat(_s_model_start(p), [_s_model_step(s) | some s in array.slice(p.steps, _s_first_step(p), count(p.steps))]), _s_model_position(p))

_s_model_start(p) := [concat("", ["$$", p.start])] if "start" in object.keys(p)

_s_model_start(p) := [] if {
	not "start" in object.keys(p)
	object.get(p, "it", false) == true
}

_s_model_start(p) := [concat("", ["$", p.steps[0]])] if {
	not "start" in object.keys(p)
	object.get(p, "it", false) != true
	object.get(p, "alias", false) == true
}

_s_model_start(p) := [{"literal": p.steps[0]}] if {
	not "start" in object.keys(p)
	object.get(p, "it", false) != true
	object.get(p, "alias", false) != true
	_s_literal_start(p)
}

_s_model_start(p) := [p.steps[0]] if {
	not "start" in object.keys(p)
	object.get(p, "it", false) != true
	object.get(p, "alias", false) != true
	not _s_literal_start(p)
}

_s_literal_start(p) if startswith(p.steps[0], "$")

_s_literal_start(p) if object.get(p, "field", false) == true

_s_model_step(s) := s if is_string(s)

_s_model_step(s) := s.index if {
	is_object(s)
	is_number(object.get(s, "index", null))
}

_s_model_step(s) := {"ref": [concat("", ["$$", s.named_by.start]), s.named_by.steps[0]]} if {
	is_object(s)
	"named_by" in object.keys(s)
	"start" in object.keys(s.named_by)
}

_s_model_step(s) := {"named_by_field": s.named_by.steps[0]} if {
	is_object(s)
	"named_by" in object.keys(s)
	not "start" in object.keys(s.named_by)
}

_s_model_position(p) := [p.position - 1] if is_number(object.get(p, "position", null))

_s_model_position(p) := [0] if object.get(p, "position", null) == "first"

_s_model_position(p) := [] if not "position" in object.keys(p)

_unusable_mark := {"ergo/unusable": set()}

_walk_row(check, subj) := object.union(_walk_read_row(check, subj), {"cause": "unusable", "failed": []}) if {
	_walk_flawed(check)
} else := {"cause": "not_an_object", "inputs": [], "failed": []} if {
	not _off_subject(check.path)
	not _reads_subject(check.path)
	not is_object(subj)
} else := _walk_read_row(check, subj)

_walk_flawed(check) if _param_broken(check, set())

_walk_flawed(_) if _unreadable_input

_walk_read_row(check, subj) := {"cause": state, "inputs": _merged_inputs(array.concat([{"name": _path_name(check.path), "value": [], "locations": []}], array.concat(_named_inputs(subj, _walk_condition_paths(check)), _field_named_inputs(subj, _walk_condition_paths(check))))), "failed": []} if {
	state := _read_state(subj, check.path)
	not _walk_keys(check, subj)
}

_walk_read_row(check, subj) := {"cause": cause, "inputs": inputs, "failed": failed} if {
	keys := _walk_keys(check, subj)
	w := _walk(_walk_start(check, subj), keys, check.if_any == true)
	judged := [_walk_judge(check, w, e) | some e in w.items]
	fails := array.concat(array.concat(w.fails, [j.failure | some j in judged; j.failure != null]), _walk_stop(w))
	cause := _walk_cause(check, w, judged, fails)
	failed := _walk_failed(cause, fails)
	inputs := _merged_inputs(array.concat(_walk_inputs(check, w), array.concat(_named_inputs(subj, _walk_condition_paths(check)), _field_named_inputs(subj, _walk_condition_paths(check)))))
}

_walk_condition_paths(check) := array.concat([p | some p in _condition_paths(check.check)], [p | some c in check.whose; some p in _condition_paths(c)])

_named_inputs(subj, paths) := [_path_input(subj, shown) |
	some p in paths
	_read_off_item(p)
	not _has_field_step(p)
	shown := _as_subject_part(p)
]

_field_named_inputs(subj, paths) := [_path_input(subj, shown) |
	some p in paths
	_read_off_item(p)
	_has_field_step(p)
	shown := _as_subject_part(_before_field_step(p))
	not _through_list(subj, shown)
]

_before_field_step(p) := array.slice(p, 0, min([j | some j, step in p; j > 0; _field_step(step)]))

_as_subject_part(p) := array.concat([_p_marker(m.alias, m.n, m.of, false)], array.slice(p, 1, count(p))) if {
	_part_start(p)
	m := _part_of(p)
	m.old == true
}

_as_subject_part(p) := p if not _old_part(p)

_old_part(p) if {
	_part_start(p)
	_part_of(p).old == true
}

_read_off_item(p) if _starts_at_name(p)

_read_off_item(p) if {
	_part_start(p)
	_part_of(p).of == null
}

_read_off_item(p) if p[0] == "$$input"

_walk_keys(check, subj) := ks if {
	_ := _start_of(subj, check.path)
	ks := _keys_in(subj, check.path)
}

_walk_start(check, subj) := {"c": _walk_root(check.path), "v": _start_of(subj, check.path), "i": null, "iv": null, "r": [], "a": _walk_base(check.path)}

_walk_base(path) := base if base := _start_at(path)

else := ""

_walk_at(w, e) := _joined(w.trail[0].a, array.slice(e.c, count(w.trail[0].c), count(e.c))) if not _walk_marked(e.v)

else := _pointer(w.trail[0].a, w.trail[0].v, array.slice(e.c, count(w.trail[0].c), count(e.c)))

_walk_locations(w) := [_walk_at(w, e) | some e in w.items]

_item_at(w, e) := _pointer(w.trail[0].a, w.trail[0].v, array.slice(e.i, count(w.trail[0].c), count(e.i)))

_fail_locations(f) := [f.at] if "at" in object.keys(f)

else := []

_item_read_at(w, e, path) := _pointer(_item_at(w, e), e.iv, _resolved_prefix(e.iv, path))

_walk_root(path) := [path[0]] if _named(path)

_walk_root(path) := [] if not _named(path)

_walk(start, keys, if_any) := {"items": items, "fails": fails, "walked": walked, "trail": trail} if {
	r0 := _walk_level([start], keys, 0, if_any)
	r1 := _walk_level(r0.entries, keys, 1, if_any)
	r2 := _walk_level(r1.entries, keys, 2, if_any)
	r3 := _walk_level(r2.entries, keys, 3, if_any)
	r4 := _walk_level(r3.entries, keys, 4, if_any)
	r5 := _walk_level(r4.entries, keys, 5, if_any)
	r6 := _walk_level(r5.entries, keys, 6, if_any)
	r7 := _walk_level(r6.entries, keys, 7, if_any)
	r8 := _walk_level(r7.entries, keys, 8, if_any)
	r9 := _walk_level(r8.entries, keys, 9, if_any)
	r10 := _walk_level(r9.entries, keys, 10, if_any)
	levels := [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10]
	fails := [object.union(f, {"at": _pointer(start.a, start.v, array.slice(f.path, count(start.c), count(f.path)))}) | some r in levels; some f in r.fails]
	walked := {i | some i, r in levels; r.walked}
	items := [e | some e in r10.entries; e.i != null]
	trail := array.concat([start], [r.entries[0] | some i, r in levels; i < count(keys); count(r.entries) == 1])
}

_walk_level(entries, keys, i, _) := {"entries": entries, "fails": [], "walked": false} if i > count(keys)

_walk_level(entries, keys, i, if_any) := {"entries": [_walk_step(e, keys, i) | some e in expanded], "fails": fails, "walked": walked} if {
	i <= count(keys)
	walked := _walks_here(entries, keys, i)
	expanded := [x | some e in entries; some x in _walk_expand(e, walked, i)]
	fails := [f | some e in entries; some f in _walk_expand_fail(e, walked, if_any)]
}

_walks_here(entries, keys, i) if {
	some e in entries
	is_array(e.v)
	i == count(keys)
} else if {
	some e in entries
	is_array(e.v)
	not is_number(keys[i])
} else := false

_walk_expand(e, false, _) := [e]

_walk_expand(e, true, i) := [{"c": array.concat(_walk_unaliased(e.c, i), [j]), "v": x, "i": array.concat(_walk_unaliased(e.c, i), [j]), "iv": x, "r": []} | some j, x in e.v] if is_array(e.v)

_walk_expand(e, true, _) := [] if not is_array(e.v)

_walk_unaliased(c, i) := array.concat([_p_marker(m.alias, -1, m.of, m.old)], array.slice(c, 1, count(c))) if {
	_part_start(c)
	m := _part_of(c)
	m.n > 0
	i > 0
	i < m.n
}

_walk_unaliased(c, i) := c if not _walk_inside_part(c, i)

_walk_inside_part(c, i) if {
	_part_start(c)
	m := _part_of(c)
	m.n > 0
	i > 0
	i < m.n
}

_walk_expand_fail(_, false, _) := []

_walk_expand_fail(e, true, if_any) := [] if {
	is_array(e.v)
	_walk_empty_ok(e.v, if_any)
}

_walk_expand_fail(e, true, if_any) := [{"path": e.c, "item": e.c, "cause": "value", "value": []}] if {
	e.v == []
	not _walk_empty_ok(e.v, if_any)
}

_walk_expand_fail(e, true, _) := [{"path": e.c, "item": e.c, "cause": _walk_state(e.v), "value": _walk_shown(e.v)}] if not is_array(e.v)

_walk_empty_ok(v, _) if count(v) > 0

_walk_empty_ok(_, true)

_walk_step(e, keys, i) := e if i >= count(keys)

_walk_step(e, keys, i) := {"c": array.concat(e.c, [keys[i]]), "v": _walk_read(e.v, keys[i]), "i": e.i, "iv": e.iv, "r": array.concat(e.r, [keys[i]])} if i < count(keys)

_walk_read(v, k) := object.get(v, k, _absent) if {
	is_object(v)
	is_string(k)
	v != _absent
	v != _unusable_mark
} else := v[k] if {
	is_array(v)
	is_number(k)
	k < count(v)
} else := _absent if {
	is_array(v)
	is_number(k)
} else := _absent if {
	_walk_gone(v)
} else := _unusable_mark

_walk_gone(v) if v == _absent

_walk_gone(null)

_walk_state(v) := "absent" if v == _absent

_walk_state(null) := "null"

_walk_state(v) := "unusable" if not _walk_gone(v)

_walk_shown(v) := null if _walk_marked(v)

_walk_shown(v) := v if not _walk_marked(v)

_walk_marked(v) if v == _absent

_walk_marked(v) if v == _unusable_mark

_walk_judge(check, w, e) := {"kept": kept, "passed": passed, "failure": failure} if {
	undecided := [[c, cause] | some c in check.whose; cause := _row_cause(c, e.iv, ""); not cause in {"satisfied", "value"}]
	kept := count([c | some c in check.whose; _row_cause(c, e.iv, "") == "value"]) == 0
	leaf := _walk_target(check.check, e.r)
	passed := _walk_passed(undecided, kept, leaf, e.iv)
	failure := _walk_failure(w, e, undecided, kept, leaf, passed)
}

default _walk_passed(_, _, _, _) := false

_walk_passed([], true, leaf, v) if _op_passed(leaf, v)

_walk_failure(w, e, [], true, leaf, false) := {"path": e.c, "item": e.i, "cause": _row_cause(leaf, e.iv, ""), "value": _walk_shown(e.v), "at": _walk_at(w, e)}

_walk_failure(w, e, undecided, _, _, _) := {"path": array.concat(e.i, _walk_first_path(undecided[0][0])), "item": e.i, "cause": undecided[0][1], "value": _walk_first_value(undecided[0][0], e.iv), "at": _item_read_at(w, e, _walk_first_path(undecided[0][0]))} if undecided != []

_walk_failure(_, _, [], false, _, _) := null

_walk_failure(_, _, [], true, _, true) := null

_walk_first_path(c) := _condition_paths(c)[0]

_walk_first_value(c, v) := _value_at(v, _condition_paths(c)[0])

_condition_paths(c) := array.concat(_leaf_paths(c), [p | some side in _derived_sides(c); some p in _side_paths(side)])

_walk_target(leaf, r) := object.union(leaf, {"left": r}) if _two_sided(leaf)

_walk_target(leaf, r) := object.union(leaf, {"path": r}) if not _two_sided(leaf)

_walk_cause(_, w, _, _) := _walk_stop(w)[0].cause if w.walked == set()

_walk_cause(check, w, judged, fails) := _walk_verdict(check.op, check.if_any == true, judged, fails) if w.walked != set()

_walk_stop(w) := [] if w.walked != set()

_walk_stop(w) := [{"path": e.c, "item": e.c, "cause": _walk_stop_state(e.v), "value": _walk_shown(e.v), "at": _walk_at(w, e)} | e := _walk_stopped_at(w.trail)] if w.walked == set()

_walk_stopped_at(trail) := [e | some e in trail; not _walk_container(e.v)][0] if {
	some e in trail
	not _walk_container(e.v)
} else := trail[count(trail) - 1]

_walk_container(v) if {
	is_object(v)
	not _walk_marked(v)
}

_walk_container(v) if is_array(v)

_walk_stop_state(v) := _walk_state(v) if _walk_gone(v)

_walk_stop_state(v) := "unusable" if not _walk_gone(v)

_walk_verdict("every", if_any, judged, []) := "satisfied" if {
	_walk_some_kept(judged, if_any)
} else := "value"

_walk_verdict("every", _, _, fails) := _walk_worst(fails) if fails != []

_walk_verdict("some", _, judged, fails) := "satisfied" if {
	some j in judged
	j.passed
} else := _walk_worst(fails) if {
	fails != []
} else := "value"

_walk_some_kept(_, true)

_walk_some_kept(judged, false) if {
	some j in judged
	j.kept
}

_walk_worst(fails) := [c | some c in array.concat(_cause_precedence, ["value"]); c in {f.cause | some f in fails}][0]

_walk_failed("satisfied", _) := []

_walk_failed(cause, fails) := [{"path": _path_name(f.path), "item": _path_name(f.item), "cause": f.cause, "value": f.value, "locations": _fail_locations(f)} |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_walk_inputs(check, w) := [{"name": _walk_name(check.path, w.walked), "value": [_walk_shown(e.v) | some e in w.items], "locations": _walk_locations(w)}]

_walk_name(path, walked) := _walk_shown_name(_walk_unaliased(path, _walk_crossed(path, walked)), walked)

_walk_crossed(path, walked) := min({i | some i in walked; i > 0; i < _part_of(path).n}) if _part_start(path)

_walk_crossed(path, walked) := 0 if not _walk_crosses(path, walked)

_walk_crosses(path, walked) if {
	_part_start(path)
	some i in walked
	i > 0
	i < _part_of(path).n
}

_walk_shown_name(path, walked) := concat("", array.concat(array.concat(_walk_root_name(path), [concat("", [_walk_mark(i + _walk_hidden(path), walked), _step_name(i + count(_walk_root_name(path)), step)]) | some i, step in array.slice(_walk_steps(path), _walk_hidden(path), count(_walk_steps(path)))]), [_walk_mark(count(_walk_steps(path)), walked)]))

_walk_hidden(path) := max([_part_of(path).n, 0]) if _part_start(path)

_walk_hidden(path) := 0 if not _part_start(path)

_walk_root_name(path) := [_plain_step_name(0, path[0])] if {
	_named(path)
	not _part_start(path)
}

_walk_root_name(path) := [_plain_step_name(0, root[0])] if {
	_part_start(path)
	root := _visible_root(_part_of(path))
	count(root) == 1
}

_walk_root_name(path) := [_plain_step_name(0, root[0]), _step_name(1, root[1])] if {
	_part_start(path)
	root := _visible_root(_part_of(path))
	count(root) == 2
}

_walk_root_name(path) := [] if {
	_part_start(path)
	count(_visible_root(_part_of(path))) == 0
}

_walk_root_name([]) := ["it"]

_walk_root_name(path) := [] if {
	not _named(path)
	not _reads_subject(path)
}

_walk_root_name(path) := ["it"] if {
	not _named(path)
	path != []
	_reads_subject(path)
}

_walk_steps(path) := array.slice(path, count(_walk_root(path)), count(path))

_walk_mark(i, walked) := "[]" if i in walked

_walk_mark(i, walked) := "" if not i in walked

_s_check_for(lines, ftext, wording, problems, parts) := object.union(wording, {
	"op": "for",
	"items": [_s_for_item_model(item, {earlier.as | some earlier in array.slice(fl.items, 0, i)}) | some i, item in items],
	"checks": [_s_named_model_leaf(_s_model(a), names) | some a in marked],
	"assertions": texts,
	"expression": concat("", ["for ", _s_for_line_text({"items": items}), ": ", concat(" and ", texts)]),
}) if {
	count(problems) == 0
	fl := _for_line(ftext)
	"items" in object.keys(fl)
	names := {item.as | some item in fl.items}
	parsed := [_sentence(line) | some line in lines]
	every p in parsed {
		"assertions" in object.keys(p)
	}
	assertions := [a | some p in parsed; some a in p.assertions]
	count(_s_for_unsupported(fl, assertions)) == 0
	items := _s_marked_items(fl, parts)
	marked := [_s_aliased(a, _s_names(names, parts)) | some a in assertions]
	count(_s_self_problems(marked) | _s_whose_self_problems(items)) == 0
	texts := [_s_assertion_text(a) | some a in marked]
} else := object.union(wording, {"expression": _s_for_written_text(lines, ftext), "$sentence": sort(_s_or_unrunnable(((problems | _s_for_problems(lines, ftext)) | _s_for_self(lines, ftext, parts))))})

_s_marked_items(fl, parts) := [_s_sort_marked(_s_aliased_item(item, _s_names({earlier.as | some earlier in array.slice(fl.items, 0, i)}, parts)), _s_names({i.as | some i in fl.items}, parts)) | some i, item in fl.items]

_s_sort_marked(item, names) := object.union(object.remove(item, ["sorted_by"]), {"sorted_by": _s_marked(item.sorted_by, names, false)}) if "sorted_by" in object.keys(item)

else := item

_s_for_self(lines, ftext, parts) := _s_lines_self(lines, _s_names({item.as | some item in fl.items}, parts)) | {concat("", ["for: ", p]) | some p in _s_whose_self_problems(_s_marked_items(fl, parts))} if {
	is_string(ftext)
	fl := _for_line(ftext)
	"items" in object.keys(fl)
} else := set()

_s_for_written_text(lines, ftext) := concat("", ["for ", trim_space(ftext), ": ", concat(" and ", [_s_written_text(line) | some line in lines])]) if is_string(ftext)

_s_for_written_text(lines, ftext) := concat(" and ", [_s_written_text(line) | some line in lines]) if not is_string(ftext)

_s_for_problems(lines, ftext) := {concat("", ["for: ", p]) | some p in object.get(_for_line(ftext), "problems", [])} | _s_for_line_unsupported(lines, ftext) if is_string(ftext)

_s_for_problems(lines, ftext) := _s_lines_problems(lines) if not is_string(ftext)

_s_for_line_unsupported(lines, ftext) := _s_lines_problems(lines) if not "items" in object.keys(_for_line(ftext))

_s_for_line_unsupported(lines, ftext) := _s_for_unsupported(fl, []) | _s_lines_problems(lines) if {
	fl := _for_line(ftext)
	"items" in object.keys(fl)
}

_s_for_unsupported(fl, assertions) := ({u | some item in fl.items; some u in _s_item_unsupported(item)} | {u | some a in assertions; some u in _s_assertion_unsupported(a)}) | {u | some i, item in fl.items; some u in _s_names_not_given(item, {later.as | some later in array.slice(fl.items, i, count(fl.items))})}

_s_names_not_given(x, later) := {concat("", ["unknown alias ", ref.steps[0]]) |
	some node in _s_nodes(x)
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
	ref.steps[0] in later
}

_s_item_unsupported(item) := (_s_paths_unsupported(_s_unpicked(item)) | {u | some c in object.get(item, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(_s_unpicked(item))

_s_unpicked(item) := object.union(object.remove(item, ["pick"]), {"pick": object.remove(item.pick, ["position", "from_last"])}) if "pick" in object.keys(item)

else := item

_s_for_item_model(item, names) := {
	"q": q,
	"path": _s_named_path(_s_model_path(item[q]), names),
	"whose": [_s_named(_s_leaf_model(c), names) | some c in object.get(item, "where", [])],
	"if_any": object.get(item, "if_any", false),
	"as": item.as,
} if {
	q := _s_quantifier_of(item)
	q != "pick"
}

_s_for_item_model(item, names) := {
	"q": "every",
	"path": _s_named_path(_s_model_path(_s_unpicked(item).pick), names),
	"whose": [_s_named(_s_leaf_model(c), names) | some c in object.get(item, "where", [])],
	"if_any": false,
	"as": item.as,
	"pick": object.union({"at": _s_pick_at(item.pick.position), "from_last": _s_picks_from_last(item.pick)}, object.union({"by": _s_model_path(item.sorted_by) | "sorted_by" in object.keys(item)}, {"alphabetically": true | object.get(item, "alphabetically", false) == true})),
} if "pick" in object.keys(item)

_s_pick_at(n) := n if is_number(n)

_s_pick_at(n) := 1 if n in {"first", "last"}

_s_picks_from_last(p) if p.position == "last"

else := object.get(p, "from_last", false)

_s_named(m, names) := object.union(object.union(m, {f: _s_named_side(m[f], names) | some f in ["path", "left", "right"]; f in object.keys(m)}), {"inputs": [_s_named_side(i, names) | some i in m.inputs] | is_array(object.get(m, "inputs", null))})

_s_named_side(side, names) := _s_named_path(side, names) if is_array(side)

_s_named_side(side, names) := object.union(side, {"add": [_s_named_tally(o, names) | some o in side.add]}) if {
	is_object(side)
	"add" in object.keys(side)
}

_s_named_side(side, names) := _s_named_tally(side, names) if {
	is_object(side)
	not "add" in object.keys(side)
}

_s_named_tally(side, names) := _s_named_path(side, names) if is_array(side)

_s_named_tally(side, names) := object.union(side, {f: _s_named_path(side[f], names), "whose": [_s_named_cond(c, names) | some c in side.whose]}) if {
	is_object(side)
	some f in ["count_of", "sum_of"]
	f in object.keys(side)
}

_s_named_tally(side, names) := object.union(side, {f: _s_named_path(side[f], names) | some f in ["elapsed_from", "elapsed_to"]}) if {
	is_object(side)
	"elapsed_from" in object.keys(side)
}

_s_named_tally(side, _) := side if {
	is_object(side)
	object.keys(side) & {"count_of", "sum_of", "elapsed_from"} == set()
}

_s_named_cond(c, names) := object.union(c, {f: _s_named_path(c[f], names) | some f in ["path", "left", "right"]; is_array(object.get(c, f, null))})

_s_named_path(p, names) := [_s_named_step(i, step, names) | some i, step in p]

_s_named_step(i, step, names) := concat("", ["$", step]) if {
	i == 0
	is_string(step)
	step in names
} else := {"named_by": step.named_by_field} if {
	_field_step(step)
	step.named_by_field in names
} else := step

_for_names := object.get(input, "ergo/names", {})

_bound(names, name, v, at) := object.union(names, {name: v, "$at": object.union(object.get(names, "$at", {}), {"names": object.union(object.get(object.get(names, "$at", {}), "names", {}), {name: at})})})

_for_row(check, subj) := object.union(_for_outer(check, subj, _for_names), {"cause": "unusable", "failed": []}) if {
	_walk_flawed(check)
} else := {"cause": "not_an_object", "inputs": [], "failed": []} if {
	some item in check.items
	not _off_subject(item.path)
	not is_object(subj)
} else := _for_outer(check, subj, _for_names)

_for_outer(check, subj, names) := {"cause": w.unread, "inputs": _for_inputs(check, subj, names, check.items[0], w), "failed": []} if {
	w := _for_walk(check.items[0], subj, names)
	"unread" in object.keys(w)
} else := {"cause": cause, "inputs": _for_inputs(check, subj, names, check.items[0], _for_walk(check.items[0], subj, names)), "failed": _for_failed(check, cause, [object.union(f, {"lines": []}) | some f in pre.fails])} if {
	pre := _for_pre(check, subj, names)
	pre != null
	"pick" in object.keys(check.items[1])
	cause := _for_pick_failure(pre)
} else := {"cause": cause, "inputs": inputs, "failed": failed} if {
	item := check.items[0]
	w := _for_walk(item, subj, names)
	pre := _for_pre(check, subj, names)
	judged := [_for_judge_outer(check, subj, names, item, e, pre, w) | some e in w.items]
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	failed := _for_failed(check, cause, _for_shared(check, fails, pre, names))
	inputs := _for_inputs(check, subj, names, item, w)
}

_for_unwalked(check, w) := [f | some f in array.concat(w.fails, _walk_stop(w))] if not "unread" in object.keys(w)

else := [object.union({"path": check.items[1].path, "item": check.items[1].path, "cause": w.unread, "value": null}, object.get(w, "unread_at", {}))]

_for_shared(_, fails, null, _) := fails

_for_shared(check, fails, pre, names) := array.concat([trimmed[i] | some i, f in fails; not _for_only_shared(f, trimmed[i])], shared) if {
	pre != null
	seen := {h.path | some f in fails; some h in object.get(f, "inner", [])}
	shared := [g | some g in array.concat([object.union(f, {"lines": []}) | some f in _for_unwalked(check, pre)], _for_free_undecided(check, pre, names)); g.path in seen]
	paths := {g.path | some g in shared}
	trimmed := [_for_trim(f, [g | some g in object.get(f, "inner", []); not g.path in paths]) | some f in fails]
}

_for_free_undecided(check, _, _) := [] if _for_whose_reads(check.items[1].whose, check.items[0].as)

_for_free_undecided(check, pre, names) := [{"path": e.i, "item": e.i, "cause": wh.undecided[0], "value": _walk_shown(e.v), "lines": [], "at": _walk_at(pre, e)} |
	some e in pre.items
	wh := _for_whose(check.items[1], e, names)
	wh.undecided != []
] if not _for_whose_reads(check.items[1].whose, check.items[0].as)

_for_whose_reads(whose, name) if {
	some c in whose
	_reads_name(c, name)
}

_for_trim(f, own) := object.union(f, {"inner": own, "cause": _walk_worst([{"cause": c} | some c in ({l.cause | some l in f.lines} | {g.cause | some g in own})])}) if {
	count(own) < count(object.get(f, "inner", []))
	count(f.lines) + count(own) > 0
} else := object.union(f, {"inner": own})

_for_only_shared(f, t) if {
	f.lines == []
	object.get(f, "inner", []) != []
	t.inner == []
}

_for_walk(item, subj, names) := _for_picked(item, w, names) if {
	keys := _walk_keys(item, subj) with input as {"ergo/names": names}
	w := _walk(_walk_start(item, subj), keys, _for_empty_ok(item)) with input as {"ergo/names": names}
} else := object.union({"items": [], "fails": [], "walked": set(), "trail": [], "unread": _read_state(subj, item.path)}, _unread_at(subj, item, names))

_unread_at(subj, item, names) := {"unread_at": {"at": at}} if at := _unread_pointer(subj, item.path) with input as {"ergo/names": names}

else := {}

_unread_pointer(subj, path) := _pointer(_start_at(path), start, _leading_keys(subj, path)) if start := _start_of(subj, path)

_for_empty_ok(item) if "pick" in object.keys(item)

else := item.if_any == true

_for_picked(item, w, _) := w if not "pick" in object.keys(item)

_for_picked(item, w, _) := w if {
	"pick" in object.keys(item)
	w.walked == set()
}

_for_picked(item, w, names) := _for_pick_sorted(item, object.union(w, {"items": kept}), w.items, names) if {
	"pick" in object.keys(item)
	w.walked != set()
	judged := [[e, _for_whose(item, e, names)] | some e in w.items]
	whose_fails := [{"path": j[0].i, "item": j[0].i, "cause": j[1].undecided[0], "value": _walk_shown(j[0].v), "at": _walk_at(w, j[0])} | some j in judged; j[1].undecided != []]
	kept := [j[0] | some j in judged; j[1].undecided == []; j[1].kept]
	_for_no_fails(w, whose_fails)
}

_for_picked(item, w, names) := object.union(w, {"items": [], "fails": array.concat(w.fails, whose_fails), "input": _for_list_input(item, w)}) if {
	"pick" in object.keys(item)
	w.walked != set()
	whose_fails := [{"path": e.i, "item": e.i, "cause": wh.undecided[0], "value": _walk_shown(e.v), "at": _walk_at(w, e)} | some e in w.items; wh := _for_whose(item, e, names); wh.undecided != []]
	not _for_no_fails(w, whose_fails)
}

_for_no_fails(w, whose_fails) if {
	w.fails == []
	whose_fails == []
}

_for_pick_sorted(item, w, read, names) := object.union(w, {"items": [], "fails": bad, "input": _for_list_input(item, object.union(w, {"items": read}))}) if {
	bad := _for_unsortable(item, w, names)
	bad != []
} else := object.union(w, {"items": read, "unread": "absent"}) if {
	not _for_pick_index(item, w.items, names)
} else := object.union(w, {"items": [], "fails": tied, "input": _for_list_input(item, object.union(w, {"items": read}))}) if {
	tied := _for_tied(item, w, names)
	count(tied) > 1
} else := object.union(w, {"items": [e], "input": [_path_name(e.i), _walk_shown(e.v), [_walk_at(w, e)]]}) if {
	e := w.items[_for_pick_index(item, w.items, names)]
}

_for_pick_failure(w) := w.unread if "unread" in object.keys(w)

else := _walk_worst(fails) if {
	fails := array.concat(w.fails, _walk_stop(w))
	fails != []
}

_for_list_input(item, w) := [_walk_name(item.path, w.walked), [_walk_shown(e.v) | some e in w.items], _walk_locations(w)]

_for_sort_key(item, e, names) := _for_sortable(v, object.get(item.pick, "alphabetically", false)) if {
	"by" in object.keys(item.pick)
	is_object(e.iv)
	v := _resolved(e.iv, item.pick.by) with input as {"ergo/names": names}
}

_for_sortable(v, false) := ["number", v] if is_number(v)

_for_sortable(v, false) := ["time", _time_ns(v)] if _rfc3339_shaped(v)

_for_sortable(v, false) := ["date", v] if _date_shaped(v)

_for_sortable(v, true) := ["text", v] if is_string(v)

_for_kept_kind(kinds) := [k | some k in ["number", "time", "date", "text"]; k in kinds][0]

_for_unsortable(item, _, _) := [] if not "by" in object.keys(item.pick)

_for_unsortable(item, w, names) := array.concat(unread, mixed) if {
	"by" in object.keys(item.pick)
	items := w.items
	unread := [{"path": e.i, "item": e.i, "cause": _for_sort_state(item, e, names), "value": _for_sort_shown(item, e, names), "at": _for_sort_at(item, w, e, names)} | some e in items; not _for_sort_key(item, e, names)]
	kinds := {_for_sort_key(item, e, names)[0] | some e in items}
	mixed := [{"path": e.i, "item": e.i, "cause": "unusable", "value": _for_sort_shown(item, e, names), "at": _for_sort_at(item, w, e, names)} |
		count(kinds) > 1
		some e in items
		_for_sort_key(item, e, names)[0] != _for_kept_kind(kinds)
	]
}

_for_sort_state(item, e, names) := s if {
	is_object(e.iv)
	s := _read_state(e.iv, item.pick.by) with input as {"ergo/names": names}
	s != "value"
} else := "unusable" if is_object(e.iv)

else := "not_an_object"

_for_sort_at(item, w, e, names) := _item_read_at(w, e, item.pick.by) if is_object(e.iv) with input as {"ergo/names": names}

else := _item_at(w, e)

_for_sort_shown(item, e, names) := _walk_shown(v) if {
	is_object(e.iv)
	v := _resolved(e.iv, item.pick.by) with input as {"ergo/names": names}
}

else := null

_for_order(item, items, names) := [pair[2] | some pair in sort([[_for_sort_key(item, e, names)[1], i, i] | some i, e in items])] if "by" in object.keys(item.pick)

_for_order(item, items, _) := numbers.range(0, count(items) - 1) if not "by" in object.keys(item.pick)

_for_pick_index(item, items, names) := order[_for_pick_slot(item.pick, count(order))] if {
	order := _for_order(item, items, names)
	count(items) > 0
}

_for_pick_slot(pick, n) := pick.at - 1 if {
	not pick.from_last
	pick.at <= n
}

_for_pick_slot(pick, n) := n - pick.at if {
	pick.from_last
	pick.at <= n
}

_for_tied(item, _, _) := [] if not "by" in object.keys(item.pick)

_for_tied(item, w, names) := [{"path": e.i, "item": e.i, "cause": "ambiguous", "value": _for_sort_shown(item, e, names), "at": _for_sort_at(item, w, e, names)} |
	some e in w.items
	_for_sort_key(item, e, names)[1] == key
] if {
	"by" in object.keys(item.pick)
	key := _for_sort_key(item, w.items[_for_pick_index(item, w.items, names)], names)[1]
}

_for_pre(check, subj, names) := _for_walk(check.items[1], subj, names) if {
	count(check.items) == 2
	not _for_from_first(check)
} else := null

_for_from_first(check) if check.items[1].path[0] == concat("", ["$", check.items[0].as])

_for_from_first(check) if {
	some step in check.items[1].path
	_name_step(step)
	step.named_by == check.items[0].as
}

_for_judge_outer(check, subj, names, item, e, pre, w) := {"passed": res.passed, "kept": wh.kept, "failure": _for_failure(e, wh.undecided, wh.kept, res, _walk_at(w, e)), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_outer_next(check, subj, _bound(names, item.as, e.v, _walk_at(w, e)), wh.undecided, wh.kept, pre)
}

_for_judge_inner(check, subj, names, item, e, w) := {"passed": res.passed, "kept": wh.kept, "failure": _for_failure(e, wh.undecided, wh.kept, res, _walk_at(w, e)), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_inner_next(check, subj, _bound(names, item.as, e.v, _walk_at(w, e)), wh.undecided, wh.kept)
}

_for_whose(item, e, names) := {"undecided": _for_undecided(undecided, kept, e.v), "kept": kept} if {
	causes := [_row_cause(c, e.iv, "") | some c in item.whose] with input as {"ergo/names": names}
	undecided := [c | some c in causes; not c in {"satisfied", "value"}]
	kept := count([c | some c in causes; c == "value"]) == 0
}

_for_undecided(undecided, true, v) := array.concat(undecided, _for_mark_cause(v))

_for_undecided(undecided, false, _) := undecided

_for_mark_cause(v) := ["absent"] if v == _absent

_for_mark_cause(v) := ["unusable"] if v == _unusable_mark

_for_mark_cause(v) := [] if not _walk_marked(v)

_for_outer_next(_, _, _, undecided, _, _) := {"passed": false, "cause": undecided[0], "lines": []} if undecided != []

_for_outer_next(_, _, _, [], false, _) := {"passed": false, "cause": "value", "lines": []}

_for_outer_next(check, subj, bound, [], true, null) := _for_inner(check, subj, bound, _for_walk(check.items[1], subj, bound)) if count(check.items) == 2

_for_outer_next(check, subj, bound, [], true, pre) := _for_inner(check, subj, bound, pre) if pre != null

_for_outer_next(check, subj, bound, [], true, _) := _for_lines(check, subj, bound) if count(check.items) == 1

_for_inner_next(_, _, _, undecided, _) := {"passed": false, "cause": undecided[0], "lines": []} if undecided != []

_for_inner_next(_, _, _, [], false) := {"passed": false, "cause": "value", "lines": []}

_for_inner_next(check, subj, bound, [], true) := _for_lines(check, subj, bound)

_for_failure(_, [], false, _, _) := null

_for_failure(e, undecided, _, res, at) := {"path": e.i, "item": e.i, "cause": res.cause, "value": _walk_shown(e.v), "lines": res.lines, "inner": object.get(res, "unchecked", []), "at": at} if undecided != []

_for_failure(e, [], true, res, at) := {"path": e.i, "item": e.i, "cause": res.cause, "value": _walk_shown(e.v), "lines": res.lines, "inner": object.get(res, "unchecked", []), "at": at} if not res.passed

_for_failure(_, [], true, res, _) := null if res.passed

_for_inner(check, subj, names, w) := {"passed": false, "cause": "not_an_object", "lines": []} if {
	check.items[1].path[0] == concat("", ["$", check.items[0].as])
	count(check.items[1].path) > 1
	not is_object(names[check.items[0].as])
} else := {"passed": false, "cause": w.unread, "lines": [], "unchecked": _for_unwalked(check, w)} if {
	"unread" in object.keys(w)
} else := {"passed": cause == "satisfied", "cause": cause, "lines": lines, "unchecked": [f | some f in fails; f.lines == []]} if {
	item := check.items[1]
	judged := [_for_judge_inner(check, subj, names, item, e, w) | some e in w.items]
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	lines := _for_merge_lines(check, cause, fails)
}

_for_lines(check, subj, names) := {"passed": count(lines) == 0, "cause": _all_of_cause(lines), "lines": lines} if {
	lines := [{"assertion": check.assertions[i], "cause": cause, "inputs": _for_line_inputs(check, read)} |
		some i, c in check.checks
		cause := _for_cause(c, subj) with input as {"ergo/names": names}
		cause != "satisfied"
		read := _for_read(c, subj) with input as {"ergo/names": names}
	]
}

_for_cause(c, subj) := e.cause if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := _assertion_cause(c, subj, "")

_for_read(c, subj) := _with_key_fields(subj, c, e.inputs) if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := _with_key_fields(subj, c, _assertion_inputs(subj, c))

_for_merge_lines(_, "satisfied", _) := []

_for_merge_lines(check, cause, fails) := [object.union({"assertion": a, "cause": _walk_worst([{"cause": c} | some c in causes])}, _for_line_items(check, i, a, fails)) |
	some i, a in check.assertions
	causes := [l.cause | some f in fails; some l in f.lines; l.assertion == a]
	count(causes) > 0
] if cause != "satisfied"

_for_line_inputs(check, inputs) := [object.union(i, {"name": _for_input_name(i.name, {item.as | some item in check.items})}) | some i in inputs]

_for_input_name(name, aliases) := concat("", [m[1], alias, m[2]]) if {
	some alias in aliases
	m := regex.find_all_string_submatch_n(concat("", [`(?s)^((?:item [0-9]+ of )?)\$`, _quoted(alias), `((?:[.\[ ].*)?)$`]), name, 1)[0]
} else := name

_for_line_items(check, i, a, fails) := {"items": [{"item": _for_item_name(check, f.path), "cause": l.cause, "inputs": l.inputs} |
	some p in sort({f.path | some f in fails; some l in f.lines; l.assertion == a})
	some f in fails
	f.path == p
	some l in f.lines
	l.assertion == a
]} if _reads_name(check.checks[i], check.items[1].as)

else := {"inputs": _for_line_first_inputs(a, fails)}

_for_line_first_inputs(a, fails) := inputs[0] if inputs := [l.inputs | some f in fails; some l in f.lines; l.assertion == a]

_reads_name(c, name) if {
	walk(c, [at, x])
	not _under_data(at)
	not _under_literal(c, at)
	_name_read(x, name)
}

_under_data(at) if {
	some k in at
	k in {"value", "values", "patterns", "min", "max"}
}

_name_read(x, name) if {
	is_array(x)
	count(x) > 0
	x[0] == concat("", ["$", name])
}

_name_read(x, name) if {
	is_object(x)
	x.named_by == name
}

_for_item_name(check, p) := _path_name(array.concat([substring(p[0], 1, -1)], array.slice(p, 1, count(p)))) if p[0] in {concat("", ["$", item.as]) | some item in check.items}

else := _path_name(p)

_for_verdict(item, w, judged, fails) := _walk_stop(w)[0].cause if {
	w.walked == set()
	count(_walk_stop(w)) > 0
} else := _walk_verdict(item.q, item.if_any == true, judged, fails)

_for_failed(_, "satisfied", _) := []

_for_failed(check, cause, fails) := [object.union({"path": _path_name(f.path), "item": _path_name(f.item), "cause": f.cause, "value": f.value, "failed_assertions": f.lines, "locations": _fail_locations(f)}, _for_unchecked(check, object.get(f, "inner", []))) |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_for_unchecked(_, []) := {}

_for_unchecked(check, inner) := {"failed_items": [{"path": _for_item_name(check, f.path), "item": _for_item_name(check, f.item), "cause": f.cause, "value": f.value, "locations": _fail_locations(f)} |
	some p in sort({f.path | some f in inner})
	some f in inner
	f.path == p
]} if inner != []

_for_inputs(check, subj, names, item, w) := _merged_inputs([{"name": t[0], "value": t[1], "locations": t[2]} | some t in _for_input_pairs(check, subj, names, item, w)])

_for_input_pairs(check, subj, names, item, w) := ((((((((({object.get(w, "input", _for_list_input(item, w))} | _for_inner_pairs(check, subj, names, item, w)) | {[_path_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	shown := _before_names(p)
}) | {[_path_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	_starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	shown := _before_later_names(p)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	some side in _derived_sides(c)
	not _tally_named(check, side)
	some i in _side_inputs(subj, side)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	some side in _derived_sides(c)
	_tally_named(check, side)
	some part in _tally_parts(side)
	some i in _tally_kept_inputs(check, subj, part)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	not _for_alias_path(check, c.path)
	some i in _walk_read_row(c, subj).inputs
	not i in _named_inputs(subj, [p | some p in _walk_condition_paths(c); _for_alias_path(check, p)])
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	_for_alias_path(check, c.path)
	some i in array.concat(_named_inputs(subj, [p | some p in _walk_condition_paths(c); not _for_alias_path(check, p)]), _field_named_inputs(subj, [p | some p in _walk_condition_paths(c); not _for_alias_path(check, p)]))
}) | {[_path_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	_walks(c)
	shown := _before_alias_name(check, subj, c.path)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	some i in _named_inputs(subj, [shown | some p in _walk_condition_paths(c); shown := _before_alias_name(check, subj, p)])
}) | {[_path_name([f]), _value_at(subj, [f]), _locations_of(subj, [f])] |
	some f in _for_key_fields(check)
}

_for_alias_path(check, p) if p[0] in {concat("", ["$", item.as]) | some item in check.items}

_for_alias_path(_, p) if _has_name_step(p)

_before_alias_name(check, subj, p) := shown if {
	_has_name_step(p)
	_starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	shown := _before_later_names(p)
	not _through_list(subj, shown)
}

_before_alias_name(check, subj, p) := shown if {
	_has_name_step(p)
	not _starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	shown := _before_names(p)
	not _through_list(subj, shown)
}

_through_list(subj, path) if {
	count(path) > 1
	some i in numbers.range(1, count(path) - 1)
	is_array(_value_at(subj, array.slice(path, 0, i)))
}

_for_key_fields(check) := {seg.named_by_field |
	some item in check.items
	some seg in item.path
	_field_step(seg)
} | {f | some c in check.checks; some f in _key_fields(c)}

_for_inner_pairs(check, _, _, _, _) := set() if count(check.items) == 1

_for_inner_pairs(check, subj, names, item, w) := {[_for_list_name(check, check.items[1].path, walked), values, locations]} if {
	count(check.items) == 2
	_for_from_first(check)
	inner := [_for_walk(check.items[1], subj, _bound(names, item.as, e.v, _walk_at(w, e))) | some e in w.items]
	walked := {i | some iw in inner; some i in iw.walked}
	values := [_walk_shown(e2.v) | some iw in inner; some e2 in iw.items]
	locations := [_walk_at(iw, e2) | some iw in inner; some e2 in iw.items]
}

_for_inner_pairs(check, subj, names, _, _) := {object.get(iw, "input", [_for_list_name(check, check.items[1].path, iw.walked), [_walk_shown(e.v) | some e in iw.items], _walk_locations(iw)])} if {
	count(check.items) == 2
	not _for_from_first(check)
	iw := _for_walk(check.items[1], subj, names)
}

_tally_named(check, side) if {
	some p in _side_paths(side)
	_for_alias_path(check, p)
}

_tally_named(check, side) if {
	some t in _tally_parts(side)
	some c in t.whose
	some p in _condition_paths(c)
	_for_alias_path(check, p)
}

_tally_kept_inputs(check, subj, part) := _basic_inputs(subj, part) if not _tally_named(check, part)

_tally_kept_inputs(check, subj, part) := array.concat(
	array.concat(
		[_tally_list_input(_tally(subj, part)) | not _for_alias_path(check, part[_basic_form(part)])],
		[{"name": _path_name(shown), "value": _value_at(subj, shown), "locations": _locations_of(subj, shown)} | shown := _before_alias_name(check, subj, part[_basic_form(part)])],
	),
	_merged_inputs(array.concat(
		_named_inputs(subj, array.concat(
			[p | some c in part.whose; some p in _condition_paths(c); not _for_alias_path(check, p)],
			[shown | some c in part.whose; some p in _condition_paths(c); shown := _before_alias_name(check, subj, p)],
		)),
		_field_named_inputs(subj, [p | some c in part.whose; some p in _condition_paths(c); not _for_alias_path(check, p)]),
	)),
) if _tally_named(check, part)

_tally_parts(side) := [side] if _basic_form(side) in {"count_of", "sum_of"}

_tally_parts(side) := [o | some o in side.add; _basic_form(o) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_for_list_name(check, path, walked) := substring(_walk_name(path, walked), 1, -1) if path[0] in {concat("", ["$", item.as]) | some item in check.items}

_for_list_name(check, path, walked) := _walk_name(path, walked) if not path[0] in {concat("", ["$", item.as]) | some item in check.items}

_starts_at_name(p) if {
	_off_subject(p)
	not _builtin(p)
}

_before_names(p) := p if {
	not _starts_at_name(p)
	not _has_name_step(p)
} else := array.slice(p, 0, i) if {
	not _starts_at_name(p)
	i := min([j | some j, step in p; _name_step(step)])
	i > 0
}

_before_later_names(p) := array.slice(p, 0, min(array.concat([count(p)], [j | some j, step in p; j > 0; _name_step(step)])))

_has_name_step(p) if {
	is_array(p)
	some step in p
	_name_step(step)
}

as_sentences(policy) := object.union(object.remove(policy, ["subjects", "requirements"]), object.union(_c_sections(policy), {"ergo_spec": _spec})) if is_object(policy)

as_sentences(policy) := policy if not is_object(policy)

_c_sections(policy) := {f: _c_section(f, policy[f], {"chains": _c_chains(policy), "aliases": _c_aliases(policy)}) | some f in ["subjects", "requirements"]; f in object.keys(policy)}

_c_aliases(policy) := {name: {a | some a, _ in parts} | some name, parts in _p_parts(policy.subjects).effective} if is_object(object.get(policy, "subjects", null))

_c_aliases(policy) := {} if not is_object(object.get(policy, "subjects", null))

_c_chains(policy) := _s_subject_sentences(policy.subjects, _s_from_reads(policy.subjects, _p_parts(policy.subjects)), _p_no_parts).chains if is_object(object.get(policy, "subjects", null))

_c_chains(policy) := {} if not is_object(object.get(policy, "subjects", null))

_c_section("subjects", section, _) := _c_subjects(section) if is_object(section)

_c_section("requirements", section, ctx) := _c_requirements(section, ctx) if is_object(section)

_c_section(_, section, _) := section if not is_object(section)

_c_requirements(reqs, ctx) := {name: _c_requirement(req, ctx) | some name, req in reqs}

_c_requirement(req, ctx) := object.union(object.remove(req, ["checks"]), {"checks": {name: _c_check_of(check, object.get(ctx.aliases, object.get(req, "subject", null), set())) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
	not object.get(req, "subject", null) in object.keys(ctx.chains)
} else := req

_c_check_of(check, aliases) := check if {
	aliases & {x | walk(check, [_, x]); is_string(x)} != set()
} else := _c_check(check)

_c_check(check) := _c_written(check, text) if {
	text := _c_sentence(_c_bare(check))
} else := check

_c_bare(check) := object.remove(check, ["description", "meta"]) if is_object(check)

_c_written(check, text) := text if object.keys(check) & {"description", "meta"} == set()

_c_written(check, text) := object.union(object.filter(check, {"description", "meta"}), {"assert": text}) if object.keys(check) & {"description", "meta"} != set()

_c_sentence(model) := [t | some t in _c_candidates(model); _c_reads_back(t, model)][0]

_c_reads_back(text, model) if {
	parsed := _sentence(text)
	count(parsed.assertions) == 1
	count(_s_unsupported(parsed)) == 0
	_s_line_self(text, set()) == set()
	_s_model(parsed.assertions[0]) == model
}

_c_path(p) := _path_name(p) if is_array(p)

_c_values(vs) := concat(", ", [_json_text(v) | some v in vs]) if is_array(vs)

_c_values(vs) := _ref_name(vs.ref) if _is_ref(vs)

_c_candidates(m) := [concat("", [_c_path(m.path), " exists"])] if m.op == "present"

_c_candidates(m) := [concat("", [_c_path(m.path), " does not exist"])] if m.op == "missing"

_c_candidates(m) := [concat("", [_c_path(m.path), " is ", _json_text(m.value)])] if m.op == "equals"

_c_candidates(m) := [concat("", [_c_path(m.path), " is a non-empty string"])] if m.op == "non_empty_string"

_c_candidates(m) := [concat("", [_c_path(m.path), " is one of ", _c_values(m.values)]), concat("", [_c_path(m.path), " is in ", _c_values(m.values)])] if m.op == "in"

_c_candidates(m) := [concat("", [_c_path(m.path), " is between ", _json_text(m.min), " and ", _json_text(m.max)])] if m.op == "range"

_c_candidates(m) := [concat("", [_c_path(m.path), " matches ", _c_values(m.patterns)])] if m.op == "matches_any"

_c_candidates(m) := [concat("", [_c_path(m.path), " does not match ", _c_values(m.patterns)])] if m.op == "not_matches_any"

_c_candidates(m) := [concat("", [_c_path(m.path), " contains ", _c_one(m.value)])] if {
	m.op == "includes"
	"value" in object.keys(m)
	not "values" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " contains all of ", _c_values(m.values)])] if {
	m.op == "includes"
	"values" in object.keys(m)
	not "value" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " does not contain ", _c_one(m.value)])] if {
	m.op == "excludes"
	"value" in object.keys(m)
	not "values" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " contains none of ", _c_values(m.values)])] if {
	m.op == "excludes"
	"values" in object.keys(m)
	not "value" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.left), " ", _c_compare_words[m.cmp], " ", _c_side(m.right), _c_within(m)])] if {
	m.op == "compare"
	m.cmp in object.keys(_c_compare_words)
}

_c_candidates(m) := [concat("", [_c_path(m.left), " ", _c_time_words[m.cmp], " ", _c_path(m.right)])] if {
	m.op == "compare_time"
	m.cmp in object.keys(_c_time_words)
}

_c_one(v) := _ref_name(v.ref) if _is_ref(v)

_c_one(v) := _json_text(v) if not _is_ref(v)

_c_side(s) := _c_path(s) if is_array(s)

_c_side(s) := _json_text(s.literal) if _basic_form(s) == "literal"

_c_within(m) := concat("", [" within ", _json_text(m.within)]) if "within" in object.keys(m)

_c_within(m) := "" if not "within" in object.keys(m)

_c_compare_words := {"eq": "equals", "ne": "does not equal", "gt": "is more than", "gte": "is at least", "lt": "is less than", "lte": "is at most"}

_c_time_words := {"gt": "is after", "lt": "is before", "gte": "is on or after", "lte": "is on or before"}

_c_subjects(subjects) := {name: _c_subject(name, def, subjects) | some name, def in subjects}

_c_subject(name, def, subjects) := object.union(object.remove(def, ["from", "applies_to", "of"]), object.union({"from": from}, _c_id(def))) if {
	is_object(def)
	from := _c_from_line(name, def, subjects)
} else := def

_c_id(def) := {"identified_by": text} if {
	is_array(object.get(def, "identified_by", null))
	text := _path_name(def.identified_by)
	object.get(_s_id_read(text), "path", null) == def.identified_by
} else := {}

_c_from_line(name, def, subjects) := concat("", [source, _c_whose(conds)]) if {
	not "of" in object.keys(def)
	is_array(def.from)
	source := _c_source(name, def.from, subjects)
	conds := _c_conditions(def)
}

_c_from_line(name, def, subjects) := concat("", [parent, _c_whose(conds)]) if {
	is_string(object.get(def, "of", null))
	not "from" in object.keys(def)
	not "identified_by" in object.keys(def)
	def.of != name
	def.of in object.keys(subjects)
	not startswith(def.of, "$")
	parent := _path_name([def.of])
	fl := _from_line(parent)
	object.keys(fl) == {"path"}
	_s_narrows(name, fl, subjects)
	fl.path.steps == [def.of]
	conds := _c_conditions(def)
}

_c_whose([]) := ""

_c_whose(conds) := concat("", [" whose ", concat(" and ", conds)]) if conds != []

_c_conditions(def) := [] if not "applies_to" in object.keys(def)

_c_conditions(def) := conds if {
	is_object(def.applies_to)
	conds := [text |
		some n in sort(object.keys(def.applies_to))
		f := def.applies_to[n]
		is_object(f)
		object.keys(f) & {"description", "meta"} == set()
		text := _c_sentence(f)
	]
	count(conds) == count(def.applies_to)
}

_c_source(_, [], _) := "$input"

_c_source(name, from, subjects) := text if {
	count(from) > 0
	not _c_naming(from[count(from) - 1])
	text := _c_from_path(name, from, subjects)
	_c_from_reads_back(text, from)
}

_c_source(name, from, subjects) := text if {
	count(from) > 1
	step := from[count(from) - 1]
	is_object(step)
	object.keys(step) == {"each_as", "keys"}
	step.each_as == "subject"
	_is_ref(step.keys)
	text := concat("", [_c_from_path(name, array.slice(from, 0, count(from) - 1), subjects), " named by each of ", _ref_name(step.keys.ref)])
	_c_from_reads_back(text, from)
}

_c_naming(step) if {
	is_object(step)
	not _is_ref(step)
}

_c_from_path(name, steps, subjects) := concat("", ["$input.", _steps_name(_from_steps(steps))]) if {
	is_string(steps[0])
	steps[0] != name
	steps[0] in object.keys(subjects)
} else := _steps_name(_from_steps(steps))

_c_from_reads_back(text, from) if {
	fl := _from_line(text)
	object.keys(fl) - {"named_by_each_of"} == {"path"}
	array.concat(_s_from_steps(_s_model_path(fl.path)), _c_each_back(fl, from)) == from
}

_c_each_back(fl, from) := [object.union(from[count(from) - 1], {"keys": {"ref": _s_model_path(fl.named_by_each_of)}})] if "named_by_each_of" in object.keys(fl)

_c_each_back(fl, _) := [] if not "named_by_each_of" in object.keys(fl)
