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

default _links(_) := false

_links(name) if _of_edges(_raw_subject(name), data.ergo_subjects) != []

_filters_of(name) := object.get(_raw_subject(name), "applies_to", {})

_built_on_count(name) := count(graph.reachable(_of_graph, [name]))

_resolved_subjects := {name: _resolution(name) | some name, _ in data.ergo_subjects} if is_object(data.ergo_subjects)

default _resolved_subjects := {}

_resolution(name) := object.union({"members": members, "problems": problems}, resolved) if {
	members := {m | some m in graph.reachable(_of_graph, [name])}
	resolved := _resolved_def(members)
	problems := union({_member_problems(members), _loop_problems(name, members), _read_problems(resolved)})
}

_resolved_def(members) := {"def": def, "from_owner": r, "filter_owners": owners} if {
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

_merged_filters(members, _) := [f | some m in sort(members); f := _filters_of(m); not is_object(f)][0] if {
	some m in members
	not is_object(_filters_of(m))
}

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

_from_owner(req) := _resolution_of(req).from_owner

_filter_owner(req, n) := _resolution_of(req).filter_owners[n]

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

default _bad_applies_to(_) := false

_bad_applies_to(req) if "applies_to" in _wrong_typed(_subject_def(req), _subject_wrong_type_problems)

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
	not f in object.keys(_subject_wrong_type_problems)
])

_unknown_req_fields(req) := [] if not is_object(req)

_not_an_object_inputs(req) := [{"name": "requirement", "value": req}] if not is_object(req)

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
	"from": "not a list or a string",
	"identified_by": "not a list or a string",
	"description": "not a string",
	"of": "empty or not a string",
}

_req_problems(req) := union({_req_meta_problems(req), _type_problems(req), _range_problems(req), _unknown_problems(req), _checks_problems(req), _require_problems(req), _req_json_problems(req), _subject_problems(req)})

_subject_problems(req) := (_subject_ref_problems(req) | _resolution_problems(req)) | _parent_problems(req)

_parent_problems(req) := _resolution_problems({"subject": data.ergo_subject_sentences.chains[req.subject]}) if _chained(req)

_parent_problems(req) := set() if not _chained(req)

_resolution_problems(req) := r.problems if {
	r := _resolution_of(req)
} else := set()

_member_problems(members) := union({
	{[array.concat(["subjects", m], [p[0]]), p[1]] |
		some m in members
		some p in _def_problems(_raw_subject(m))
	},
	{[["subjects", m, _of_field(m)], "can't build on a subject read from another subject yet"] |
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
	{[["subjects", m, f], p] |
		some m in members
		some f, ps in object.get(data.ergo_subject_sentences.problems, m, {})
		some p in ps
	},
	{[["subjects", m, "applies_to", n], "also a filter of a subject it builds on"] |
		some m in members
		some n in object.keys(_object_or_empty(_filters_of(m)))
		some other in graph.reachable(_of_graph, [m])
		other != m
		n in object.keys(_object_or_empty(_filters_of(other)))
	},
})

_of_field(m) := "from" if m in object.get(data.ergo_subject_sentences, "narrowed", set())

else := "of"

_loop_problems(name, members) := {[["subjects", name, _of_field(name)], "leads to a loop"] |
	count(members) > 0
	every m in members {
		_links(m)
	}
}

_read_problems(resolved) := {[array.concat(["subjects", resolved.from_owner], [p[0]]), p[1]] |
	some p in (_naming_step_problems(object.get(resolved.def, "from", [])) | _where_problems(object.get(resolved.def, "identified_by", [])))
}

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
	{[f, "not allowed with of"] | "of" in object.keys(def); some f in ["from", "identified_by"]; f in object.keys(def)},
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

_require_problems(req) := {["require", "neither every nor some"] | is_object(req); not _require_of(req) in {"every", "some"}}

_path_problems(req, f) := {[f, "step that can't be a key"] | is_array(_req_field(req, f, null)); _badly_stepped(req[f])} | {[f, "number out of range"] | is_array(_req_field(req, f, null)); _out_of_range(req[f])}

_naming_step_problems(from) := {["from", m] |
	is_array(from)
	some i, seg in from
	is_object(seg)
	not _is_ref(seg)
	some m in _object_step_problems(seg, i == (count(from) - 1))
}

_object_step_problems(_, false) := {"object step before the last"}

_object_step_problems(step, true) := {"object step without each_as"} if not "each_as" in object.keys(step)

_object_step_problems(step, true) := ({concat("", ["unknown field ", _text(k), " in naming step"]) |
	some k in object.keys(step)
	not k in {"each_as", "keys"}
} | {"invalid name" | not _valid_name(step.each_as)}) | {"invalid keys" | not _keys_well_formed(step)} if "each_as" in object.keys(step)

_where_problems(id) := {["identified_by", concat("", [kind, " inside where"])] | some kind in _wrapped_in_where(id)}

_field_problem_inputs(req) := [{"name": _field_name(f), "value": sort({p[1] | some p in problems; p[0] == f})} | some f in sort({p[0] | some p in problems})] if {
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

_each_step(req) := step if {
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
	step := _each_step(req)
	every seg in _from_path(req) {
		_plain_step(seg)
	}
	object.keys(step) - {"each_as", "keys"} == set()
	_valid_name(step.each_as)
	_keys_well_formed(step)
}

_plain_step(seg) if not is_object(seg)

_plain_step(seg) if _is_ref(seg)

_valid_name(n) if {
	is_string(n)
	n != ""
	not startswith(n, "$")
	not n in {"params", "input"}
}

_keys_well_formed(step) if not "keys" in object.keys(step)

_keys_well_formed(step) if {
	is_array(step.keys)
	every k in step.keys {
		not _malformed(k)
	}
}

_keys_well_formed(step) if _is_ref(step.keys)

_keys_well_formed(step) if {
	_is_literal(step.keys)
	is_array(step.keys.literal)
}

_listed_keys(step) := ks if {
	is_array(step.keys)
	ks := [_step_key(k) | some k in step.keys]
	count(ks) == count(step.keys)
}

_listed_keys(step) := step.keys.literal if {
	_is_literal(step.keys)
	is_array(step.keys.literal)
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
	c := _target_state(doc, req)
	c != "value"
}

_target_cause(_, req) := "value" if not _from_well_formed(req)

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

_from_unreadable(req) if {
	step := _each_step(req)
	is_array(step.keys)
	not _listed_keys(step)
}

_from_cause(req) := _worst_of(unread) if {
	unread := _from_ref_states(req) - {"value"}
	count(unread) > 0
}

_from_cause(req) := "unusable" if _from_ref_states(req) - {"value"} == set()

_from_ref_states(req) := {_ref_state(seg.ref) | some seg in _from_path(req); _is_ref(seg)} | {_ref_state(r) | some r in _keys_refs(_each_step(req))}

_keys_refs(step) := {step.keys.ref} if _is_ref(step.keys)

_keys_refs(step) := {k.ref | some k in step.keys; _is_ref(k)} if is_array(step.keys)

_listed_subjects(doc, req) := coll if {
	coll := _target(doc, req)
	is_array(coll)
}

_listed_subjects(doc, req) := [coll] if {
	coll := _target(doc, req)
	is_object(coll)
}

_listed_subjects(doc, req) := [] if {
	not is_array(_target(doc, req))
	not is_object(_target(doc, req))
}

_raw_entries(doc, req) := [{"subject": subj} | some subj in _listed_subjects(doc, req)] if {
	not _stepped(req)
	_from_well_formed(req)
}

_raw_entries(_, req) := [] if not _from_well_formed(req)

_raw_entries(doc, req) := [entry | some entry in _each_entries(_target(doc, req))] if {
	_from_well_formed(req)
	not "keys" in object.keys(_each_step(req))
}

_each_entries(coll) := [{"subject": subj} | some subj in coll] if is_array(coll)

_each_entries(coll) := [{"key": k, "subject": coll[k]} | some k in sort(object.keys(coll))] if is_object(coll)

_each_entries(coll) := [] if not _is_collection(coll)

_raw_entries(doc, req) := [{"key": k, "subject": object.get(_keyed(doc, req), [k], _absent)} | some k in sort({k | some k in _listed_keys(_each_step(req))})] if {
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

_scope_of(req, subj) := {"ergo/names": object.union(names, _parent_names)} if names := _each_names(req, subj)

_each_names(req, subj) := {_each_step(req).each_as: subj} if {
	_has_step(req)
	_from_well_formed(req)
}

_each_names(req, _) := {} if not _has_step(req)

default _parent_names := {}

_parent_names := data.ergo_parent if is_object(data.ergo_parent)

_scoped(req) if _has_step(req)

_scoped(_) if _parent_names != {}

_passes(req, check, flaw, subj) := _check_passed(check, subj, flaw) if not _scoped(req)

else := v if {
	_scoped(req)
	s := _scope_of(req, subj)
	v := _check_passed(check, subj, flaw) with input as s
}

_inputs_in(req, check, subj, item) := _row_inputs(subj, check, item) if not _scoped(req)

else := i if {
	_scoped(req)
	s := _scope_of(req, subj)
	i := _row_inputs(subj, check, item) with input as s
}

_outcome(req, check, flaw, subj, item) := _check_outcome(check, subj, flaw, item) if not _scoped(req)

else := o if {
	_scoped(req)
	s := _scope_of(req, subj)
	o := _check_outcome(check, subj, flaw, item) with input as s
}

_check_outcome(check, subj, flaw, item) := object.union(
	{
		"inputs": _row_inputs(subj, check, item),
		"passed": _check_passed(check, subj, flaw),
		"cause": _row_cause(check, subj, flaw),
	},
	_failed_items_field(check, subj, flaw, item),
) if {
	not _all_of_run(check, flaw)
	not _walk_run(check, flaw)
	not _derived_once(check)
}

_check_outcome(check, subj, flaw, item) := {
	"inputs": e.inputs,
	"passed": _once_passed(flaw, e),
	"cause": _once_cause(flaw, e),
} if {
	_derived_once(check)
	e := _derived_eval(check, subj, item)
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
	not "substitute" in object.keys(check)
	not "inputs" in object.keys(check)
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

_derived_eval(check, subj, item) := {"passed": passed, "cause": cause, "inputs": array.concat(l.inputs, r.inputs)} if {
	l := _side_eval(subj, check.left, item)
	r := _side_eval(subj, check.right, item)
	passed := _eval_compared(check, l.v, r.v)
	states := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(check, lf, rf)}
	cause := _eval_cause(passed, _ref_cause(check), states)
}

_eval_compared(check, [lv], [rv]) if _compared(check, lv, rv)

default _eval_compared(_, _, _) := false

_eval_cause(true, _, _) := "satisfied"

_eval_cause(false, "", states) := _worst_or_value(states)

_eval_cause(false, ref_cause, _) := ref_cause if ref_cause != ""

_basic_eval(subj, side, item) := {"v": v, "found": [x | x := _simple_found(subj, side)], "states": {_read_state(subj, side)}, "inputs": _basic_inputs(subj, side, item)} if {
	_basic_form(side) == "path"
	v := [x | x := value_at(subj, side)]
}

_basic_eval(subj, side, _) := {"v": [_written(side)], "found": [x | x := _simple_found(subj, side)], "states": set(), "inputs": []} if _basic_form(side) == "literal"

_basic_eval(subj, side, item) := {"v": v, "found": v, "states": _basic_states(subj, side), "inputs": _basic_inputs(subj, side, item)} if {
	_basic_form(side) in {"count", "sum"}
	v := [x | x := _basic_value(subj, side)]
}

_basic_eval(subj, side, _) := {"v": v, "found": v, "states": t.states, "inputs": [{"name": side.text, "value": object.get(t, "value", null)}, {"name": t.list, "value": t.values}]} if {
	_basic_form(side) in {"count_of", "sum_of"}
	t := _tally(subj, side)
	v := [x | x := t.value]
}

_side_eval(subj, side, item) := _basic_eval(subj, side, item) if _basic_form(side)

_side_eval(subj, side, item) := {"v": v, "found": v, "states": union({o.states | some o in ops}), "inputs": array.concat([{"name": _side_text(item, side), "value": _first_or_null(v)}], [i | some o in ops; some i in o.inputs])} if {
	_side_form(side) == "add"
	ops := [_operand_eval(subj, operand, item) | some operand in side.add]
	v := _added(side, ops)
}

_operand_eval(subj, operand, item) := object.union(_basic_eval(subj, operand, item), {"states": _number_states(subj, operand)}) if _basic_form(operand) == "path"

_operand_eval(subj, operand, item) := _basic_eval(subj, operand, item) if _basic_form(operand) != "path"

_added(side, ops) := [_add_numbers(side, nums)] if {
	nums := [n | some o in ops; [n] := o.v]
	count(nums) == count(ops)
	every n in nums {
		is_number(n)
	}
} else := []

_first_or_null([x]) := x

_first_or_null([]) := null

_check_outcome(check, subj, flaw, _) := {
	"inputs": r.inputs,
	"passed": r.cause == "satisfied",
	"cause": r.cause,
	"failed_items": r.failed,
} if {
	_walks(check)
	_walk_run(check, flaw)
	r := _walk_row(check, subj)
}

_walk_run(check, flaw) if {
	check.op in {"every", "some", "for"}
	flaw != "ill_formed"
}

_check_outcome(check, subj, flaw, _) := {
	"inputs": r.inputs,
	"passed": r.cause == "satisfied",
	"cause": r.cause,
	"failed_items": r.failed,
} if {
	check.op == "for"
	_walk_run(check, flaw)
	r := _for_row(check, subj)
}

_all_of_run(check, flaw) if {
	check.op == "all_of"
	flaw != "ill_formed"
}

_check_outcome(check, subj, flaw, item) := {
	"inputs": [{"name": pair[0], "value": pair[1]} | some pair in sort({[i.name, i.value] | some o in outs; some i in o.inputs})],
	"passed": count(failed) == 0,
	"cause": _all_of_cause(failed),
	"failed_assertions": failed,
} if {
	_all_of_run(check, flaw)
	outs := [_assertion_out(c, subj, flaw, item) | some c in check.checks]
	failed := [{"assertion": check.assertions[i], "cause": o.cause} | some i, o in outs; o.cause != "satisfied"]
}

_assertion_out(c, subj, "", item) := {"cause": e.cause, "inputs": e.inputs} if {
	_derived_once(c)
	e := _derived_eval(c, subj, item)
} else := {"cause": _assertion_cause(c, subj, ""), "inputs": _assertion_inputs(subj, c, item)}

_assertion_out(c, subj, flaw, item) := {"cause": _assertion_cause(c, subj, flaw), "inputs": _assertion_inputs(subj, c, item)} if flaw != ""

_assertion_cause(c, subj, "") := _row_cause(c, subj, "") if not _walks(c)

_assertion_cause(c, subj, _) := _walk_row(c, subj).cause if _walks(c)

_assertion_cause(c, subj, "unusable") := "unusable" if {
	not _walks(c)
	_unusable_assertion(c)
} else := _row_cause(c, subj, "") if not _walks(c)

_unusable_assertion(_) if _unreadable_input

_unusable_assertion(c) if _node_param_broken(c)

_assertion_inputs(subj, c, item) := _row_inputs(subj, c, item) if not _walks(c)

_assertion_inputs(subj, c, _) := _walk_row(c, subj).inputs if _walks(c)

_all_of_cause([]) := "satisfied"

_all_of_cause(failed) := [c | some c in array.concat(_cause_precedence, ["value"]); c in {f.cause | some f in failed}][0] if failed != []

_failed_items_field(check, subj, flaw, item) := {"failed_items": _failed_items(subj, check, flaw, item)} if _quantified(check)

_failed_items_field(check, _, _, _) := {} if not _quantified(check)

_failed_items(subj, check, flaw, item) := [{"path": e[0], "item": e[0], "cause": flaw, "value": e[1]} |
	some e in _item_entries(subj, check, item)
] if flaw != ""

_failed_items(subj, check, "", item) := [] if {
	_list_passed(check, subj)
} else := [f |
	some e in _item_entries(subj, check, item)
	some f in _entry_failure(subj, check, e)
]

_entry_failure(subj, check, [p, v]) := [{"path": p, "item": p, "cause": c, "value": v} |
	c := _failed_item_cause(subj, check, v)
	c != "satisfied"
]

_entry_failure(_, _, [p, v, c]) := [{"path": p, "item": p, "cause": c, "value": v}]

_failed_item_cause(subj, check, v) := "satisfied" if {
	_item_passed(check, v)
} else := _worst_read(subj, check) if {
	_unreadable_ref(check)
} else := _shown_cause(_item_cause(check, v))

_shown_cause("missing") := "value"

_shown_cause(c) := c if c != "missing"

default _item_entries(_, _, _) := []

_item_entries(subj, check, item) := [[_entry_name(item, check.path, [i]), v] |
	some i, v in coll
] if {
	not check.each
	coll := _field(subj, check.path)
	is_array(coll)
}

_item_entries(subj, check, item) := [[_entry_name(item, check.path, [i]), v] |
	some i, v in coll
] if {
	check.each
	not is_array(check.each)
	coll := _field(subj, check.path)
	is_array(coll)
}

_item_entries(subj, check, item) := [e |
	some i, outer in coll
	some e in _outer_entries(outer, check, item, array.concat([i], check.each))
] if {
	is_array(check.each)
	check.each
	coll := _field(subj, check.path)
	is_array(coll)
}

_outer_entries(outer, check, item, rest) := [[_entry_name(item, check.path, array.concat(rest, [j])), v] | some j, v in inner] if {
	inner := _field(outer, check.each)
	is_array(inner)
	count(inner) > 0
}

_outer_entries(outer, check, item, rest) := [[_entry_name(item, check.path, rest), [], "value"]] if _field(outer, check.each) == []

_outer_entries(outer, check, item, rest) := [[_entry_name(item, check.path, rest), value_at(outer, check.each), _each_state(outer, check.each)]] if not _is_list_at(outer, check.each)

_entry_name(_, path, rest) := _path_name(array.concat(path, rest)) if path != []

_entry_name(item, [], rest) := concat("", ["item ", _literal_text(rest[count(rest) - 1] + 1), " of ", item, _steps_name(array.slice(rest, 0, count(rest) - 1))]) if {
	_index_step(rest[count(rest) - 1])
} else := concat("", [item, _steps_name(rest)])

_is_list_at(x, path) if is_array(_field(x, path))

default _subject_matches(_, _, _) := false

_subject_matches(subj, req, flaws) if {
	not _bad_applies_to(req)
	every name, check in _applies_to_of(req) {
		_passes(req, check, flaws[name], subj)
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

_subject_id(subj, req) := value_at(subj, _id_of(req)) if {
	is_object(subj)
	is_array(_id_of(req))
}

_subject_id(subj, req) := null if {
	is_object(subj)
	not is_array(_id_of(req))
}

_subject_id(subj, _) := subj if not is_object(subj)

_absent := {"ergo/absent": set()}

default value_at(_, _) := null

value_at(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, path, null)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_field(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, path, _absent)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_resolved(subj, path) := object.get(subj, path, _absent) if {
	is_object(subj)
	_plain_path(path)
} else := _read_from(_start_of(subj, path), _keys_of(path))

_plain_path(path) if {
	is_array(path)
	not _named(path)
	every seg in path {
		not is_object(seg)
	}
}

_read_from(start, keys) := _read_at(start, keys, [i | some i, seg in keys; is_object(seg)]) if is_object(start)

_read_from(start, []) := start

_read_at(start, keys, []) := object.get(start, keys, _absent)

_read_at(start, keys, selectors) := v if {
	i := min(selectors)
	base := object.get(start, array.slice(keys, 0, i), _absent)
	base != _absent
	elem := _selected(base, keys[i])
	v := object.get(elem, array.slice(keys, i + 1, count(keys)), _absent)
}

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

_step_key(seg) := seg.literal if _is_literal(seg)

_step_key(seg) := v if {
	_is_ref(seg)
	v := _ref_read(seg.ref)
	_is_key(v)
}

_step_key(seg) := seg if {
	not _is_literal(seg)
	not _is_ref(seg)
	not _malformed(seg)
	not _name_step(seg)
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

_is_key(v) if is_string(v)

_is_key(v) if {
	is_number(v)
	regex.match(`^[0-9]+$`, json.marshal(v))
}

_badly_stepped(p) if {
	is_array(p)
	some seg in p
	_bad_step(seg)
}

_badly_stepped(p) if {
	not is_array(p)
	_bad_step(p)
}

_bad_step(seg) if {
	not is_object(seg)
	not _is_key(seg)
}

_bad_step(seg) if {
	_is_literal(seg)
	not _is_key(seg.literal)
}

_bad_step(seg) if {
	_name_step(seg)
	not data.ergo_sentence_here == true
}

_unliteral(seg) := seg.literal if _is_literal(seg)

_unliteral(seg) := seg if not _is_literal(seg)

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

arg(x) := x.literal if _is_literal(x)

arg(x) := v if {
	_is_ref(x)
	v := _ref_read(x.ref)
	v != _absent
	v != null
}

arg(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
	not _malformed(x)
}

_ref_read(path) := object.get(start, [_unliteral(seg) | some seg in array.slice(path, 1, count(path))], _absent) if {
	_builtin(path)
	start := _start_of(null, path)
	is_object(start)
}

_ref_name(path) := "<invalid ref>" if not _builtin(path)

default _malformed(_) := false

_malformed(x) if {
	is_object(x)
	some k in {"ref", "literal"}
	k in object.keys(x)
	count(x) > 1
}

_written(x) := x.literal if _is_literal(x)

_written(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
	not _malformed(x)
}

_selector_index(path) := min([i | some i, seg in path; is_object(seg)])

_selected(base, sel) := candidates[0] if {
	candidates := [v |
		some v in base
		_selector_matches(v, sel)
	]
	count(candidates) == 1
}

_selector_matches(v, sel) if {
	is_object(v)
	count(sel.where) > 0
	every k, want in sel.where {
		object.get(v, [k], _absent) == arg(want)
	}
}

_field_path_name(path) := concat(".", [_segment_name(path[i]) | some i in _names(path)])

_path_name(path) := concat("", ["item ", _literal_text(_unliteral(path[count(path) - 1]) + 1), " of ", _steps_name(array.slice(path, 0, count(path) - 1))]) if {
	is_array(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := _steps_name(path)

_ref_name(path) := concat("", ["item ", _literal_text(_unliteral(path[count(path) - 1]) + 1), " of ", _plain_steps_name(array.slice(path, 0, count(path) - 1))]) if {
	_builtin(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := _plain_steps_name(path) if _builtin(path)

_index_step(s) if {
	is_number(s)
	_is_key(s)
}

_index_step(s) if {
	_is_literal(s)
	is_number(s.literal)
	_is_key(s.literal)
}

_steps_name(path) := concat("", [_step_name(i, path[i]) | some i in _names(path)])

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

_step_name(i, p) := concat("", ["[", _ref_name(p.ref), "]"]) if {
	_is_ref(p)
	not _named_by_after(i, p)
}

_named_by_after(i, p) if {
	i > 0
	_named_by(p)
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

_plain_step_name(0, step) := concat("", ["<unknown name ", step, ">"]) if step in {"$input", "$params"}

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

_plain_step_name(_, step) := concat("", ["[", _literal_text(_unliteral(step)), "]"]) if _index_step(step)

_plain_step_name(i, step) := concat("", [_step_dot(i), _key_name(_unliteral(step))]) if not _nameable_step(step)

_step_dot(0) := ""

_step_dot(i) := "." if i > 0

_string_literal(p) if {
	_is_literal(p)
	is_string(p.literal)
}

_named_by(p) if {
	_is_ref(p)
	_builtin(p.ref)
	count(p.ref) == 2
	is_string(_unliteral(p.ref[1]))
}

_item_path_name(item, []) := item

_item_path_name(_, path) := _path_name(path) if path != []

_projection_name(path, each) := concat("", [_steps_name(path), "[]", _tail_name(each)])

_tail_name(steps) := concat("", [_step_name(i + 1, steps[i]) | some i in _names(steps)]) if is_array(steps)

_tail_name(steps) := ".<invalid each>" if not is_array(steps)

_item_list_name(item, []) := item

_item_list_name(_, path) := _steps_name(path) if path != []

_segment_name(p) := _key_name(p) if not is_object(p)

_segment_name(p) := _key_name(p.literal) if _is_literal(p)

_segment_name(p) := concat("", ["[", concat(" and ", sort([concat("", [_key_name(k), "==", _value_text(v)]) | some k, v in p.where])), "]"]) if {
	is_object(p)
	not _is_literal(p)
	not _is_ref(p)
	not _malformed(p)
}

_segment_name(p) := "[<invalid ref>]" if _malformed(p)

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

_key_text(k) := "<invalid key>" if not is_string(k)

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
	not _malformed(x)
}

_value_text(x) := "<invalid ref>" if _malformed(x)

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

default leaf_passed(_, _) := false

leaf_passed(check, subj) if _leaf_op_passed(check.op, check, subj)

_leaf_op_passed("range", check, subj) if {
	v := value_at(subj, check.path)
	is_number(v)
	lo := arg(check.min)
	hi := arg(check.max)
	is_number(lo)
	is_number(hi)
	v >= lo
	v <= hi
}

_leaf_op_passed("excludes", check, subj) if {
	v := value_at(subj, check.path)
	is_array(v)
	want := arg(check.value)
	not want in v
}

_leaf_op_passed("includes", check, subj) if {
	v := value_at(subj, check.path)
	is_array(v)
	want := arg(check.value)
	want in v
}

_leaf_op_passed("excludes", check, subj) if {
	v := value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	every want in wants {
		not want in v
	}
}

_leaf_op_passed("includes", check, subj) if {
	v := value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	every want in wants {
		want in v
	}
}

_leaf_op_passed("in", check, subj) if {
	v := value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	some want in vals
	want == v
}

_leaf_op_passed("has_type", check, subj) if {
	v := value_at(subj, check.path)
	v != null
	type_name(v) == _json_types[check.type]
}

_json_types := {"list": "array", "string": "string", "number": "number", "boolean": "boolean", "object": "object"}

_leaf_op_passed("not_in", check, subj) if {
	v := value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	every want in vals {
		want != v
	}
}

_leaf_op_passed("equals", check, subj) if {
	_field(subj, check.path) == arg(check.value)
}

_leaf_op_passed("present", check, subj) if {
	value_at(subj, check.path) != null
}

_leaf_op_passed("non_empty_string", check, subj) if {
	v := value_at(subj, check.path)
	is_string(v)
	v != ""
}

_leaf_op_passed("missing", check, subj) if {
	_missing_at(subj, check.path)
	not _params_not_given(check.path)
}

_leaf_op_passed("empty", check, subj) if {
	value_at(subj, check.path) == []
}

_leaf_op_passed("empty_string_or_list", check, subj) if {
	value_at(subj, check.path) in {[], ""}
}

_leaf_op_passed("not_empty_string_or_list", check, subj) if {
	v := value_at(subj, check.path)
	_string_or_list(v)
	count(v) > 0
}

_string_or_list(v) if is_string(v)

_string_or_list(v) if is_array(v)

_missing_at(x, path) if {
	_keys_of(path)
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

_can_hold(v, k) if {
	_is_collection(v)
	is_object(k)
}

_leaf_op_passed("matches_any", check, subj) if {
	v := value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, v)
}

_leaf_op_passed("not_matches_any", check, subj) if {
	v := value_at(subj, check.path)
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
}

_compared(check, l, r) if {
	not "within" in object.keys(check)
	check.cmp in _list_cmps
	_cmp(check.cmp, l, r)
}

_compared(check, l, r) if {
	"within" in object.keys(check)
	is_number(l)
	is_number(r)
	abs(l - r) <= check.within
}

_leaf_op_passed("compare_time", check, subj) if {
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
	_cmp(check.cmp, time.parse_rfc3339_ns(l), time.parse_rfc3339_ns(r))
}

_leaf_op_passed("compare_time", check, subj) if {
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	is_number(l)
	is_number(r)
	_cmp(check.cmp, l, r)
}

_wants(values) := arg(values) if not _value_list(values)

_wants(values) := [arg(x) | some x in values] if {
	_value_list(values)
	every x in values {
		_readable(x)
	}
}

_readable(x) if _ = arg(x)

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

_orderable(_, v) if is_string(v)

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
	leaf.op in {"includes", "excludes", "empty"}
	v := _found(x, leaf.path)
	not is_array(v)
}

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
	r := _found(x, leaf.right)
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

_found(x, path) := v if {
	v := _field(x, path)
	v != null
}

_rfc3339_shaped(v) if {
	is_string(v)
	m := regex.find_all_string_submatch_n(`^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$`, v, 1)[0]
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

_cmp("in", l, r) if {
	l != null
	is_array(r)
	l in r
}

_cmp("not_in", l, r) if {
	l != null
	is_array(r)
	not l in r
}

_cmp("includes", l, r) if {
	is_array(l)
	r != null
	r in l
}

_cmp("excludes", l, r) if {
	is_array(l)
	r != null
	not r in l
}

_cmp("includes_all", l, r) if {
	is_array(l)
	_wanted(r)
	every want in r {
		want in l
	}
}

_cmp("excludes_all", l, r) if {
	is_array(l)
	_wanted(r)
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
	not _list_right_usable(leaf.cmp, value_at(x, leaf.right))
}

_list_flawed(leaf, x) if count(_list_flaw(leaf, x)) > 0

_list_right_usable(cmp, r) if {
	cmp in {"in", "not_in"}
	is_array(r)
}

_list_right_usable(cmp, _) if cmp in {"includes", "excludes"}

_list_right_usable(cmp, r) if {
	cmp in {"includes_all", "excludes_all"}
	_wanted(r)
}

_list_right_usable(cmp, r) if {
	cmp in {"matches_any", "not_matches_any"}
	_valid_patterns(r)
}

_leaf_ops := {"range", "excludes", "includes", "in", "equals", "present", "missing", "non_empty_string", "empty", "matches_any", "not_matches_any", "compare", "compare_time"}

operators contains op if some op in (_leaf_ops | {"all", "any", "any_of"})

_required_fields := {
	"range": {"path", "min", "max"},
	"excludes": {"path"},
	"includes": {"path"},
	"in": {"path", "values"},
	"equals": {"path", "value"},
	"present": {"path"},
	"missing": {"path"},
	"non_empty_string": {"path"},
	"empty": {"path"},
	"empty_string_or_list": {"path"},
	"not_in": {"path", "values"},
	"has_type": {"path", "type"},
	"all_of": {"checks", "assertions"},
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

_flaw(check, names) := "ill_formed" if {
	_ill_formed(check, names)
} else := "unusable" if {
	_param_broken(check, names)
} else := "unusable" if {
	_unreadable_input
} else := ""

_unreadable_input if data.ergo_unreadable != []

default _ill_formed(_, _) := false

_ill_formed(check, names) if count(_check_problems(check, names)) > 0

_check_problems(check, names) := {[node[1], msg] |
	some node in _static_nodes(check, names)
	some msg in _node_problems(node[0], node[2], node[3])
}

_static_nodes(check, names) := array.concat(_walk_nodes([[check, [], [], names]]), _substitute_nodes(check, names))

default _substitute_nodes(_, _) := []

_substitute_nodes(check, names) := _walk_nodes([[check.substitute, ["substitute"], [], names]]) if {
	is_object(check)
	"substitute" in object.keys(check)
}

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
	not _too_deep(node[0], node[2])
	some child in _children(node[0], node[3])
]

_too_deep(node, kinds) if {
	_quantified(node)
	not node.op in _allowed_ops(kinds)
}

_children(node, names) := array.concat(array.concat(array.concat(_inner_child(node, names), _option_children(node, names)), _where_children(node, names)), _assertion_children(node, names))

default _assertion_children(_, _) := []

_assertion_children(node, names) := [[c, ["checks", i], "assertion", names] | some i, c in node.checks] if {
	node.op == "all_of"
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

default _inner_child(_, _) := []

_inner_child(node, names) := [[node.check, ["check"], "check", _given_with(node, names)]] if _quantified(node)

default _option_children(_, _) := []

_option_children(node, names) := [[leaf, ["options", nm, i], "option", names] |
	some nm, group in node.options
	is_array(group)
	some i, leaf in group
] if {
	_combinator(node)
	_option_list(node.options)
}

_node_problems(node, _, _) := {"invalid check"} if not is_object(node)

_node_problems(node, kinds, names) := (((_op_problems(node, kinds) | _field_problems(node)) | _step_problems(node)) | _name_problems(node, names)) | _derived_placement_problem(node, kinds) if {
	is_object(node)
	not _s_unread(node)
}

_node_problems(node, _, _) := {p | some p in node["$sentence"]} | _wording_problem(node) if _s_unread(node)

default _op_problems(_, _) := set()

_op_problems(node, _) := {"missing op"} if not "op" in object.keys(node)

_op_problems(node, _) := {concat("", ["unknown op ", _text(node.op)])} if {
	"op" in object.keys(node)
	not node.op in operators
	not _sentence_op(node)
}

_sentence_ops := {"empty_string_or_list", "not_empty_string_or_list", "not_in", "has_type", "all_of", "every", "some", "for"}

_sentence_op(node) if {
	node.op in _sentence_ops
	_s_read(node)
}

_op_problems(node, kinds) := {"nested too deep"} if _too_deep(node, kinds)

_op_problems(node, kinds) := {concat("", [_text(node.op), " can't go here"])} if {
	node.op in operators
	not _quantified(node)
	not node.op in _allowed_ops(kinds)
}

_allowed_ops(kinds) := operators if kinds == []

_allowed_ops(kinds) := object.get(_nested_ops, [kinds[count(kinds) - 1], count([k | some k in kinds; k == "check"])], set()) if kinds != []

_nested_ops := {
	"option": [(_leaf_ops | {"all", "any"}), (_leaf_ops | {"all", "any"}), _leaf_ops],
	"check": [set(), (_leaf_ops | {"all", "any", "any_of"}), (_leaf_ops | {"any_of"})],
	"where": [_leaf_ops],
	"assertion": [_leaf_ops],
}

_field_problems(node) := union({_side_problem(node), _within_problem(node), _wording_problem(node), _unknown_fields_problem(node), _missing_fields_problem(node), _range_bounds_problem(node), _range_order_problem(node), _values_problem(node), _value_or_values_problem(node), _patterns_problem(node), _nested_wrapper_problem(node), _cmp_problem(node), _misplaced_fields_problem(node), _options_problem(node), _empty_options_problem(node), _empty_option_problem(node), _out_of_range_problem(node), _refs_problem(node), _json_problem(node)})

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

_unknown_fields_problem(node) := {concat("", ["unknown field ", _text(f)]) |
	node.op in object.keys(_op_fields)
	some f in object.keys(node)
	not f in _op_fields[node.op]
	not f in {"op", "description", "meta", "expression", "substitute", "inputs", "as", "each"}
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

_values_problem(node) := {"invalid values" |
	node.op in {"in", "not_in", "includes", "excludes"}
	"values" in object.keys(node)
	not _value_list(_written(node.values))
	not is_set(_written(node.values))
	not _is_ref(node.values)
	not _malformed(node.values)
} | {"empty values" |
	node.op in {"includes", "excludes"}
	_value_list(_written(node.values))
	count(_written(node.values)) == 0
}

_patterns_problem(node) := {"invalid patterns" |
	node.op in {"matches_any", "not_matches_any"}
	"patterns" in object.keys(node)
	not _is_ref(node.patterns)
	not _malformed(node.patterns)
	not is_set(_written(node.patterns))
	not _written_patterns(_written(node.patterns))
}

_written_patterns(v) if {
	_value_list(v)
	every p in v {
		_written_pattern(p)
	}
}

_written_pattern(p) if _is_ref(p)

_written_pattern(p) if _valid_pattern(_written(p))

_nested_wrapper_problem(node) := {concat("", [_wrapper(x), " inside ", f]) |
	node.op in _leaf_ops
	some f in ["value", "values", "patterns", "min", "max"]
	f in object.keys(node)
	walk(node[f], [p, x])
	_wrapper(x)
	not _ref_read_at(f, node[f], p)
	not _under_literal(node[f], p)
	not _under_ref(node[f], p)
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
	not _under_ref(w, p)
}

_wrapper(x) := "ref" if _is_ref(x)

_wrapper(x) := "literal" if _is_literal(x)

_under_ref(v, p) if {
	some i, _ in p
	walk(v, [q, w])
	q == array.slice(p, 0, i)
	_is_ref(w)
}

_ref_read_at(_, _, [])

_ref_read_at(f, v, [_]) if {
	f in {"values", "patterns"}
	_value_list(v)
}

_cmp_problem(node) := {"invalid cmp" |
	_two_sided(node)
	"cmp" in object.keys(node)
	not node.cmp in {"eq", "ne", "gt", "gte", "lt", "lte"}
	not _sentence_cmp(node)
}

_text_cmps := {"starts_with", "ends_with"}

_sentence_cmp(node) if {
	node.op == "compare"
	node.cmp in (_text_cmps | _list_cmps)
	_s_read(node)
}

_misplaced_fields_problem(node) := {concat("", [f, " can't go here"]) |
	node.op in (_leaf_ops | {"any_of"})
	some f in ["as", "each"]
	f in object.keys(node)
}

_options_problem(node) := {"invalid options" |
	_combinator(node)
	"options" in object.keys(node)
	not _option_list(node.options)
}

_empty_options_problem(node) := {"empty options" |
	_combinator(node)
	_option_list(node.options)
	count(node.options) == 0
}

_empty_option_problem(node) := {concat("", ["empty option ", _text(nm)]) |
	_combinator(node)
	_option_list(node.options)
	some nm, group in node.options
	group == []
} | {concat("", ["option ", _text(nm), " not a list"]) |
	_combinator(node)
	_option_list(node.options)
	some nm, group in node.options
	not is_array(group)
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
		_is_key(_unliteral(seg))
	}
}

_valid_patterns(v) if {
	_value_list(v)
	every p in v {
		_valid_pattern(p)
	}
}

_own_fields(node) := object.remove(node, ["check", "options", "substitute"])

_step_problems(node) := {concat("", [f, " not a list"]) |
	some f in ["path", "left", "right", "each"]
	f in object.keys(node)
	not _side_field(node, f)
	not _checked_as_side(node, f)
	not is_array(node[f])
} | {concat("", ["step that can't be a key in ", f]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some p in _own_paths(node, f)
	_badly_stepped(p)
}

_checked_as_side(node, f) if {
	node.op == "compare_time"
	f in {"left", "right"}
}

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

_input_paths(spec) := [object.get(spec, f, []) | some f in ["path", "each"]] if is_object(spec)

_name_problems(node, names) := union({_invalid_name_problem(node), _name_given_twice_problem(node, names), _unknown_name_problem(node, names)})

_invalid_name_problem(node) := {"invalid name" |
	_quantified(node)
	"as" in object.keys(node)
	not _valid_name(node.as)
}

_name_given_twice_problem(node, names) := {"name given twice" |
	_quantified(node)
	_valid_name(node.as)
	node.as in names
}

_unknown_name_problem(node, names) := {concat("", ["unknown name ", p[0]]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some p in _own_paths(node, f)
	_named(p)
	not _name_known(p[0], names)
}

_name_known(start, _) if start in {"$$input", "$$params"}

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
	node.op == "range"
	some f in ["min", "max"]
	_is_ref(node[f])
	v := arg(node[f])
	not is_number(v)
}

_node_param_broken(node) if {
	node.op == "range"
	_is_ref(node.min)
	lo := arg(node.min)
	hi := arg(node.max)
	is_number(lo)
	is_number(hi)
	lo > hi
}

_node_param_broken(node) if {
	node.op == "range"
	_is_ref(node.max)
	lo := arg(node.min)
	hi := arg(node.max)
	is_number(lo)
	is_number(hi)
	lo > hi
}

_node_param_broken(node) if {
	node.op in {"in", "not_in"}
	_is_ref(node.values)
	v := arg(node.values)
	not _value_list(v)
}

_node_param_broken(node) if {
	node.op in {"includes", "excludes"}
	_is_ref(node.values)
	v := arg(node.values)
	not _wanted(v)
}

_node_param_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	_is_ref(node.patterns)
	v := arg(node.patterns)
	not _valid_patterns(v)
}

_node_param_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	_value_list(node.patterns)
	some p in node.patterns
	_is_ref(p)
	v := _wants(node.patterns)
	not _valid_patterns(v)
}

_option_list(options) if is_object(options)

_option_list(options) if is_array(options)

_valid_pattern(p) if {
	is_string(p)
	regex.is_valid(p)
}

default _quantified(_) := false

_quantified(check) if check.op in {"all", "any"}

default _combinator(_) := false

_combinator(check) if check.op == "any_of"

default op_passed(_, _) := false

op_passed(check, subj) if {
	not _quantified(check)
	not _combinator(check)
	leaf_passed(check, subj)
}

op_passed(check, subj) if _list_passed(check, subj)

op_passed(check, subj) if {
	_derived_sides(check) != []
	l := _side_value(subj, check.left)
	r := _side_value(subj, check.right)
	_compared(check, l, r)
}

default _list_passed(_, _) := false

_list_passed(check, subj) if {
	check.op == "all"
	_names_free(check)
	every elem in _elements(subj, check) {
		_item_passed(check, elem)
	}
}

_list_passed(check, subj) if {
	check.op == "any"
	_names_free(check)
	some elem in _elements(subj, check)
	_item_passed(check, elem)
}

_bound_names := n if {
	n := input["ergo/names"]
	is_object(n)
}

_names_free(check) if not "as" in object.keys(check)

_names_free(check) if {
	_valid_name(check.as)
	not check.as in object.keys(_bound_names)
}

_item_passed(check, elem) := _element_passed(check.check, elem) if not "as" in object.keys(check)

_item_passed(check, elem) := v if {
	"as" in object.keys(check)
	names := object.union(_bound_names, {check.as: elem})
	v := _element_passed(check.check, elem) with input as {"ergo/names": names}
}

_inner_item_passed(check, elem) := _inner_passed(check.check, elem) if not "as" in object.keys(check)

_inner_item_passed(check, elem) := v if {
	"as" in object.keys(check)
	names := object.union(_bound_names, {check.as: elem})
	v := _inner_passed(check.check, elem) with input as {"ergo/names": names}
}

default _inner_passed(_, _) := false

_inner_passed(check, elem) if {
	not _quantified(check)
	not _combinator(check)
	leaf_passed(check, elem)
}

_inner_passed(check, elem) if _any_of_passed(check, elem)

_elements(subj, check) := coll if {
	not check.each
	coll := value_at(subj, check.path)
	is_array(coll)
	count(coll) > 0
}

_elements(subj, check) := [elem |
	some outer in value_at(subj, check.path)
	some elem in value_at(outer, check.each)
] if {
	check.each
	outer_coll := value_at(subj, check.path)
	is_array(outer_coll)
	count(outer_coll) > 0
	every outer in outer_coll {
		inner := value_at(outer, check.each)
		is_array(inner)
		count(inner) > 0
	}
}

default _element_passed(_, _) := false

_element_passed(check, elem) if {
	not _combinator(check)
	leaf_passed(check, elem)
}

_element_passed(check, elem) if _element_any_of_passed(check, elem)

_element_passed(check, elem) if _element_list_passed(check, elem)

default _element_list_passed(_, _) := false

_element_list_passed(check, elem) if {
	check.op == "all"
	_names_free(check)
	every inner in _elements(elem, check) {
		_inner_item_passed(check, inner)
	}
}

_element_list_passed(check, elem) if {
	check.op == "any"
	_names_free(check)
	some inner in _elements(elem, check)
	_inner_item_passed(check, inner)
}

op_passed(check, subj) if _top_any_of_passed(check, subj)

default _top_any_of_passed(_, _) := false

_top_any_of_passed(check, subj) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		_top_option_passed(leaf, subj)
	}
}

_top_option_passed(leaf, subj) if leaf_passed(leaf, subj)

_top_option_passed(leaf, subj) if _list_passed(leaf, subj)

default _element_any_of_passed(_, _) := false

_element_any_of_passed(check, elem) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		_element_option_passed(leaf, elem)
	}
}

_element_option_passed(leaf, elem) if leaf_passed(leaf, elem)

_element_option_passed(leaf, elem) if _element_list_passed(leaf, elem)

default _any_of_passed(_, _) := false

_any_of_passed(check, subj) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		leaf_passed(leaf, subj)
	}
}

default _check_passed(_, _, _) := false

_check_passed(check, subj, "") if _passed_or_substituted(check, subj)

_passed_or_substituted(check, subj) if op_passed(check, subj)

_passed_or_substituted(check, subj) if op_passed(_substitute_of(check), subj)

_substitute_of(check) := object.get(check, "substitute", {})

default _read_paths(_) := []

_read_paths(check) := [_input_spec_path(spec) | some spec in check.inputs] if _cause_from_inputs(check)

_read_paths(check) := [side | some side in [check.left, check.right]; is_array(side)] if {
	not _cause_from_inputs(check)
	_two_sided(check)
}

_list_reads(check) := array.concat(array.concat([check.path], _named_each(check)), _element_name_reads(check))

_named_each(check) := [check.each] if _named(object.get(check, "each", []))

_named_each(check) := [] if not _named(object.get(check, "each", []))

_read_paths(check) := [check.path] if {
	not _cause_from_inputs(check)
	not _two_sided(check)
	not _quantified(check)
	not _combinator(check)
	check.path
}

_input_spec_path(spec) := spec if is_array(spec)

_input_spec_path(spec) := object.get(spec, "path", []) if is_object(spec)

_read_state(subj, path) := _plain_read_state(subj, path, object.get(subj, path, _absent)) if {
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
	not _params_not_given(path)
}

_reads_itself(path) if _keys_of(path) == []

_any_read_state(_, path) := _name_step_state(path) if _name_step_state(path)

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

_any_read_state(subj, path) := "ambiguous" if count(_selector_candidates(subj, path)) > 1

_any_read_state(subj, path) := "unmatched" if count(_selector_candidates(subj, path)) == 0

_any_read_state(subj, path) := "null" if _resolved(subj, path) == null

_any_read_state(subj, path) := "unusable" if {
	start := _start_of(subj, path)
	is_object(start)
	_blocked(start, _keys_of(path))
}

_any_read_state(subj, path) := "value" if {
	v := _resolved(subj, path)
	v != _absent
	v != null
}

_selector_candidates(subj, path) := candidates if {
	keys := _keys_of(path)
	base := _base_collection(_start_of(subj, path), keys)
	candidates := [v |
		some v in base
		_selector_matches(v, keys[_selector_index(keys)])
	]
}

_base_collection(start, keys) := base if {
	is_object(start)
	i := _selector_index(keys)
	base := object.get(start, array.slice(keys, 0, i), _absent)
	base != _absent
	_is_collection(base)
}

_is_collection(v) if is_array(v)

_is_collection(v) if is_object(v)

_cause_precedence := ["ill_formed", "not_an_object", "ambiguous", "unmatched", "unusable", "absent", "null"]

_worst_read(subj, check) := _worst_or_value(_check_states(check, subj) | _substitute_problems(check, subj)) if not _unreadable_ref(check)

_worst_or_value(states) := c if {
	c := _worst_of(states)
} else := "value"

_substitute_problems(check, subj) := {c |
	sub := _substitute_of(check)
	is_object(sub)
	some c in _check_states(sub, subj)
	not c in {"absent", "null", "missing", "value"}
}

default _has_inputs(_) := false

_has_inputs(check) if check.inputs

default _cause_from_inputs(_) := false

_cause_from_inputs(check) if {
	_has_inputs(check)
	not check.op in (_leaf_ops | {"all", "any", "any_of"})
}

_check_states(check, subj) := {_read_state(subj, p) | some p in _read_paths(check)} if _cause_from_inputs(check)

_check_states(check, subj) := (_answered(check, subj, {_read_state(subj, p) | some p in _read_paths(check)}) | _unusable_states(check, subj)) | _derived_states(check, subj) if {
	not _cause_from_inputs(check)
	not _quantified(check)
	not _combinator(check)
	not _list_flawed(check, subj)
}

_check_states(check, subj) := _list_flaw(check, subj) if {
	not _cause_from_inputs(check)
	not _quantified(check)
	not _combinator(check)
	_list_flawed(check, subj)
}

_check_states(check, subj) := {_list_cause(check, subj)} if {
	not _cause_from_inputs(check)
	_quantified(check)
}

_check_states(check, subj) := {_option_cause(group, subj) | some group in check.options} if {
	not _cause_from_inputs(check)
	_combinator(check)
}

_option_cause(group, subj) := _group_cause({_top_leaf_cause(leaf, subj) | some leaf in group})

_group_cause(causes) := "value" if {
	"missing" in causes
} else := _worst_or_value(causes)

_top_leaf_cause(leaf, subj) := _list_cause(leaf, subj) if _quantified(leaf)

_top_leaf_cause(leaf, subj) := _leaf_cause(leaf, subj) if not _quantified(leaf)

_leaf_cause(leaf, x) := "satisfied" if {
	leaf_passed(leaf, x)
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
	_keys_of(check.path)
	_ := _start_of(x, check.path)
	not _params_not_given(check.path)
}

_params_not_given(path) if {
	path[0] == "$$params"
	not is_object(data.ergo_params)
}

_presence_state(s) := "missing" if s in {"absent", "null"}

_presence_state(s) := s if not s in {"absent", "null"}

_list_cause(check, subj) := "satisfied" if {
	_list_passed(check, subj)
} else := _worst_or_value(_list_states(check, subj) | {_item_cause(check, e) | some e in _items(subj, check)})

_list_states(check, x) := ({_read_state(x, check.path)} | {"unusable" | _not_a_list(x, check.path)}) | {_each_state(outer, check.each) |
	check.each
	coll := _field(x, check.path)
	is_array(coll)
	some outer in coll
}

default _not_a_list(_, _) := false

_not_a_list(x, path) if {
	v := _found(x, path)
	not is_array(v)
}

_each_state(outer, each) := "unusable" if {
	_not_a_list(outer, each)
} else := _read_state(outer, each)

default _items(_, _) := []

_items(x, check) := coll if {
	not check.each
	coll := _field(x, check.path)
	is_array(coll)
}

_items(x, check) := [elem |
	some outer in coll
	inner := _field(outer, check.each)
	is_array(inner)
	some elem in inner
] if {
	check.each
	coll := _field(x, check.path)
	is_array(coll)
}

_item_cause(check, elem) := _element_cause(check.check, elem) if not "as" in object.keys(check)

_item_cause(check, elem) := c if {
	"as" in object.keys(check)
	names := object.union(_bound_names, {check.as: elem})
	c := _element_cause(check.check, elem) with input as {"ergo/names": names}
}

_element_cause(check, elem) := "satisfied" if {
	_element_passed(check, elem)
} else := _element_failure(check, elem)

_element_failure(check, elem) := _leaf_cause(check, elem) if {
	not _combinator(check)
	not _quantified(check)
}

_element_failure(check, elem) := _worst_or_value({_element_option_cause(group, elem) | some group in check.options}) if _combinator(check)

_element_failure(check, elem) := _nested_list_cause(check, elem) if _quantified(check)

_element_option_cause(group, elem) := _group_cause({_element_option_leaf_cause(leaf, elem) | some leaf in group})

_element_option_leaf_cause(leaf, elem) := _nested_list_cause(leaf, elem) if _quantified(leaf)

_element_option_leaf_cause(leaf, elem) := _leaf_cause(leaf, elem) if not _quantified(leaf)

_nested_list_cause(check, elem) := "satisfied" if {
	_element_list_passed(check, elem)
} else := _worst_or_value(_list_states(check, elem) | {_inner_item_cause(check, i) | some i in _items(elem, check)})

_inner_item_cause(check, inner) := _inner_cause(check.check, inner) if not "as" in object.keys(check)

_inner_item_cause(check, inner) := c if {
	"as" in object.keys(check)
	names := object.union(_bound_names, {check.as: inner})
	c := _inner_cause(check.check, inner) with input as {"ergo/names": names}
}

_inner_cause(check, inner) := _leaf_cause(check, inner) if not _combinator(check)

_inner_cause(check, inner) := _inner_any_of_cause(check, inner) if _combinator(check)

_inner_any_of_cause(check, inner) := "satisfied" if {
	_inner_passed(check, inner)
} else := _worst_or_value({_inner_option_cause(group, inner) | some group in check.options})

_inner_option_cause(group, inner) := _group_cause({_leaf_cause(leaf, inner) | some leaf in group})

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
	c := _derived_eval(check, subj, null).cause
} else := _readable_cause(check, subj)

_readable_cause(check, subj) := "satisfied" if op_passed(check, subj)

else := "substituted" if op_passed(_substitute_of(check), subj)

else := _worst_read(subj, check)

_check_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
} | {"<invalid ref>" |
	walk(check, [p, x])
	_malformed(x)
	not _under_literal(check, p)
}

_step_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
	count(p) >= 2
	_step_position(check, p)
	is_number(p[count(p) - 1])
}

_step_position(_, p) if p[count(p) - 2] in {"path", "left", "right", "each"}

_step_position(check, p) if {
	p[count(p) - 2] in {"count", "sum"}
	_in_compare_side(check, array.slice(p, 0, count(p) - 2))
}

_step_position(check, p) if {
	count(p) >= 3
	p[count(p) - 3] == "add"
	is_number(p[count(p) - 2])
	_in_compare_side(check, array.slice(p, 0, count(p) - 3))
}

_step_position(check, p) if {
	count(p) >= 4
	p[count(p) - 2] in {"count", "sum"}
	p[count(p) - 4] == "add"
	_in_compare_side(check, array.slice(p, 0, count(p) - 4))
}

_in_compare_side(check, side_path) if {
	count(side_path) >= 1
	side_path[count(side_path) - 1] in {"left", "right"}
	walk(check, [q, node])
	q == array.slice(side_path, 0, count(side_path) - 1)
	object.get(node, "op", null) == "compare"
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
	_blocked(_start_of(null, r), [_unliteral(seg) | some seg in array.slice(r, 1, count(r))])
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

_ref_inputs(check) := [{"name": pair[0], "value": pair[1]} | some pair in sort({[_ref_name(r), _ref_shown(r)] | some r in _check_refs(check)})]

_verdict_cause(passed) := "satisfied" if passed

_verdict_cause(passed) := "value" if not passed

_applies_cause(_, _, _, true) := "satisfied"

_applies_cause(subj, req, flaws, false) := _scope_cause(_failed_filter_causes(subj, req, flaws))

_scope_cause(causes) := "ill_formed" if {
	"ill_formed" in causes
} else := "value" if {
	"missing" in causes
} else := "value" if {
	causes == {"value"}
} else := _worst_of(causes)

_failed_filter_causes(subj, req, flaws) := _filter_causes(subj, req, flaws) if not _scoped(req)

else := causes if {
	_scoped(req)
	s := _scope_of(req, subj)
	causes := _filter_causes(subj, req, flaws) with input as s
}

_filter_causes(subj, req, flaws) := {_filter_cause(check, subj, flaws[name]) |
	some name, check in _applies_to_of(req)
	not _check_passed(check, subj, flaws[name])
}

_filter_cause(check, subj, flaw) := "missing" if _answers_presence(check, subj, flaw)

_filter_cause(check, subj, flaw) := _row_cause(check, subj, flaw) if not _answers_presence(check, subj, flaw)

default _answers_presence(_, _, _) := false

_answers_presence(check, subj, "") if {
	check.op == "present"
	_keys_of(check.path)
	_ := _start_of(subj, check.path)
	not _unreadable_ref(check)
	not _params_not_given(check.path)
	_substitute_problems(check, subj) == set()
	_read_state(subj, check.path) in {"absent", "null"}
}

_nested_describe(check, item) := _leaf_describe(check, item) if not _misplaced(check)

_nested_describe(check, _) := concat("", ["<", _text(check.op), " can't go here>"]) if _misplaced(check)

_misplaced(check) if {
	check.op in operators
	not check.op in _leaf_ops
	not _quantified(check)
}

default _leaf_describe(_, _) := ""

_leaf_describe(check, _) := concat("", ["<unknown op ", _text(check.op), ">"]) if not check.op in operators

_leaf_describe(check, _) := "<missing op>" if {
	is_object(check)
	not "op" in object.keys(check)
}

_leaf_describe(check, _) := "<invalid check>" if not is_object(check)

_leaf_describe(check, item) := concat("", [n, " >= ", _param_text(check, "min"), " and ", n, " <= ", _param_text(check, "max")]) if {
	check.op == "range"
	n := _path_text(item, check, "path")
}

_path_text(item, check, f) := _item_path_name(item, check[f]) if is_array(object.get(check, f, null))

_path_text(_, check, f) := concat("", ["<invalid ", f, ">"]) if {
	f in object.keys(check)
	not is_array(check[f])
}

_path_text(_, check, f) := concat("", ["<missing ", f, ">"]) if not f in object.keys(check)

_param_text(check, f) := _value_text(check[f]) if f in object.keys(check)

_param_text(check, f) := concat("", ["<missing ", f, ">"]) if not f in object.keys(check)

_leaf_describe(check, item) := concat("", ["not contains(", _path_text(item, check, "path"), ", ", _one_value_text(check), ")"]) if {
	check.op == "excludes"
	not _values_only(check)
}

_leaf_describe(check, item) := concat("", ["contains(", _path_text(item, check, "path"), ", ", _one_value_text(check), ")"]) if {
	check.op == "includes"
	not _values_only(check)
}

_leaf_describe(check, item) := concat("", ["contains_none(", _path_text(item, check, "path"), ", ", _list_text(check.values, "values"), ")"]) if {
	check.op == "excludes"
	_values_only(check)
}

_leaf_describe(check, item) := concat("", ["contains_all(", _path_text(item, check, "path"), ", ", _list_text(check.values, "values"), ")"]) if {
	check.op == "includes"
	_values_only(check)
}

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " in ", _list_text(check.values, "values")]) if {
	check.op == "in"
	"values" in object.keys(check)
}

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " in <missing values>"]) if {
	check.op == "in"
	not "values" in object.keys(check)
}

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " == ", _param_text(check, "value")]) if check.op == "equals"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " is present"]) if check.op == "present"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " is missing"]) if check.op == "missing"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " is a non-empty string"]) if check.op == "non_empty_string"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " is empty"]) if check.op == "empty"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " matches one of ", _pattern_list(check)]) if check.op == "matches_any"

_leaf_describe(check, item) := concat("", [_path_text(item, check, "path"), " matches none of ", _pattern_list(check)]) if check.op == "not_matches_any"

_pattern_list(check) := _list_text(check.patterns, "patterns") if "patterns" in object.keys(check)

_pattern_list(check) := "<missing patterns>" if not "patterns" in object.keys(check)

_leaf_describe(check, item) := concat("", [_path_text(item, check, "left"), " ", _cmp_text(check), " ", _path_text(item, check, "right")]) if check.op == "compare_time"

_leaf_describe(check, item) := concat("", [_simple_side_text(item, check, "left"), " ", _cmp_text(check), " ", _simple_side_text(item, check, "right"), _within_text(check)]) if check.op == "compare"

_one_value_text(check) := _value_text(check.value) if {
	"value" in object.keys(check)
	not "values" in object.keys(check)
}

_one_value_text(check) := "<both value and values>" if {
	"value" in object.keys(check)
	"values" in object.keys(check)
}

_one_value_text(check) := "<missing value or values>" if count({"value", "values"} & object.keys(check)) == 0

_values_only(check) if {
	"values" in object.keys(check)
	not "value" in object.keys(check)
}

_list_text(v, _) := concat("", ["[", concat(", ", sort([_value_text(x) | some x in v])), "]"]) if _value_list(v)

_list_text(v, _) := concat("", ["[", concat(", ", sort([_literal_text(x) | some x in v.literal])), "]"]) if {
	_is_literal(v)
	_value_list(v.literal)
}

_list_text(v, _) := _ref_name(v.ref) if _is_ref(v)

_list_text(v, _) := "<invalid ref>" if _malformed(v)

_list_text(v, name) := concat("", ["<invalid ", name, ">"]) if {
	not _is_ref(v)
	not _malformed(v)
	not _value_list(_written(v))
}

_cmp_text(check) := _text(check.cmp) if "cmp" in object.keys(check)

_cmp_text(check) := "<missing cmp>" if not "cmp" in object.keys(check)

_expression_of(check, _) := check.expression if _written_expression(check)

_written_expression(check) if is_string(check.expression)

_expression_of(check, item) := _leaf_describe(check, item) if {
	not _written_expression(check)
	not _quantified(check)
	not _combinator(check)
	_derived_sides(check) == []
}

_expression_of(check, item) := concat("", [_compare_side_text(item, check, "left"), " ", _cmp_text(check), " ", _compare_side_text(item, check, "right"), _within_text(check)]) if {
	not _written_expression(check)
	_derived_sides(check) != []
}

_expression_of(check, item) := _list_describe(check, _item_given(item)) if {
	not _written_expression(check)
	_quantified(check)
}

_list_describe(check, given) := concat("", [
	_quantifier(check),
	" ",
	_collection_name(check),
	_as_text(check, given),
	": ",
	_inner_check_describe(check, _item_name(check), _given_with(check, given)),
])

_inner_check_describe(check, item, given) := _element_describe(check.check, item, given) if "check" in object.keys(check)

_inner_check_describe(check, _, _) := "<missing check>" if not "check" in object.keys(check)

_as_text(check, _) := "" if not "as" in object.keys(check)

_as_text(check, given) := concat("", [" as $", check.as]) if {
	_valid_name(check.as)
	not check.as in given
}

_as_text(check, given) := " as <name given twice>" if {
	_valid_name(check.as)
	check.as in given
}

_as_text(check, _) := " as <invalid name>" if {
	"as" in object.keys(check)
	not _valid_name(check.as)
}

_item_given(item) := {substring(item, 1, -1) |
	startswith(item, "$")
	not startswith(item, "$$")
	item != "$input"
}

_given_with(check, given) := given | {check.as} if _valid_name(object.get(check, "as", null))

_given_with(check, given) := given if not _valid_name(object.get(check, "as", null))

_quantifier(check) := "every" if check.op == "all"

_quantifier(check) := "some" if check.op == "any"

_expression_of(check, _) := "one of: <missing options>" if {
	not _written_expression(check)
	check.op == "any_of"
	not "options" in object.keys(check)
}

_expression_of(check, item) := _one_of([_option_text(nm, group, [_top_option_describe(group[k], item) | some k in _names(group)]) | some nm, group in check.options]) if {
	not _written_expression(check)
	check.op == "any_of"
	"options" in object.keys(check)
}

_top_option_describe(leaf, item) := _nested_describe(leaf, item) if not _quantified(leaf)

_top_option_describe(leaf, item) := _list_describe(leaf, _item_given(item)) if _quantified(leaf)

_collection_name(check) := "<missing path>" if not "path" in object.keys(check)

_collection_name(check) := _path_name(check.path) if not check.each

_collection_name(check) := _projection_name(check.path, check.each) if check.each

_item_name(check) := concat("", [_steps_name(check.path), "[]"]) if {
	not _valid_name(object.get(check, "as", null))
	not check.each
}

_item_name(check) := concat("", [_projection_name(check.path, check.each), "[]"]) if {
	not _valid_name(object.get(check, "as", null))
	check.each
}

_item_name(check) := concat("", ["$", check.as]) if _valid_name(object.get(check, "as", null))

_item_name(check) := "<missing path>[]" if {
	not _valid_name(object.get(check, "as", null))
	not "path" in object.keys(check)
}

_inner_collection_name(check, _) := "<missing path>" if not "path" in object.keys(check)

_inner_collection_name(check, item) := _item_path_name(item, check.path) if not check.each

_inner_collection_name(check, item) := concat("", [_item_list_name(item, check.path), "[]", _tail_name(check.each)]) if check.each

_inner_list_name(check, item) := _item_list_name(item, check.path) if not check.each

_inner_list_name(check, item) := _inner_collection_name(check, item) if check.each

_inner_item_name(check, item) := concat("", [_inner_list_name(check, item), "[]"]) if {
	not _valid_name(object.get(check, "as", null))
	"path" in object.keys(check)
}

_inner_item_name(check, _) := "<missing path>[]" if {
	not _valid_name(object.get(check, "as", null))
	not "path" in object.keys(check)
}

_inner_item_name(check, _) := concat("", ["$", check.as]) if _valid_name(object.get(check, "as", null))

_element_describe(check, item, _) := _nested_describe(check, item) if {
	not _combinator(check)
	not _quantified(check)
}

_element_describe(check, item, given) := _one_of([_option_text(nm, group, [_element_option_describe(group[k], item, given) | some k in _names(group)]) | some nm, group in check.options]) if _combinator(check)

_element_describe(check, item, given) := _element_list_describe(check, item, given) if _quantified(check)

_element_option_describe(leaf, item, _) := _nested_describe(leaf, item) if not _quantified(leaf)

_element_option_describe(leaf, item, given) := _element_list_describe(leaf, item, given) if _quantified(leaf)

_element_list_describe(check, item, given) := concat("", [
	_quantifier(check),
	" ",
	_inner_collection_name(check, item),
	_as_text(check, given),
	": ",
	_deeper_check_describe(check, _inner_item_name(check, item)),
])

_deeper_check_describe(check, item) := _inner_describe(check.check, item) if "check" in object.keys(check)

_deeper_check_describe(check, _) := "<missing check>" if not "check" in object.keys(check)

_inner_describe(check, item) := _nested_describe(check, item) if {
	not _combinator(check)
	not _quantified(check)
}

_inner_describe(check, item) := _any_of_describe(check, item) if _combinator(check)

_inner_describe(check, _) := "<nested too deep>" if _quantified(check)

_any_of_describe(check, item) := _one_of([_option_text(nm, group, [_inner_option_describe(group[k], item) | some k in _names(group)]) | some nm, group in check.options])

_one_of(parts) := "one of: <empty options>" if count(parts) == 0

_one_of(parts) := concat("", ["one of: ", concat(" | ", sort(parts))]) if count(parts) > 0

_option_text(nm, group, texts) := concat("", [_text(nm), "(", _option_body(group, texts), ")"])

_option_body(group, _) := "<invalid option>" if not is_array(group)

_option_body([], _) := "<empty option>"

_option_body(group, texts) := concat(" and ", texts) if {
	is_array(group)
	count(group) > 0
}

_inner_option_describe(leaf, item) := _nested_describe(leaf, item) if not _quantified(leaf)

_inner_option_describe(leaf, _) := "<nested too deep>" if _quantified(leaf)

default _two_sided(_) := false

_two_sided(check) if check.op in {"compare", "compare_time"}

default _check_inputs(_, _, _) := []

_check_inputs(subj, check, item) := [_echoed(subj, check.inputs[k], item) | some k in _names(check.inputs)] if {
	check.inputs
}

_echoed(subj, spec, item) := {"name": _item_path_name(item, spec), "value": value_at(subj, spec)} if is_array(spec)

_echoed(subj, spec, _) := {
	"name": _projection_name(object.get(spec, "path", []), object.get(spec, "each", [])),
	"value": [value_at(elem, object.get(spec, "each", [])) | some elem in _list_at(subj, object.get(spec, "path", []))],
} if is_object(spec)

_check_inputs(subj, check, item) := [
	{"name": _item_path_name(item, check.left), "value": value_at(subj, check.left)},
	{"name": _item_path_name(item, check.right), "value": value_at(subj, check.right)},
] if {
	not check.inputs
	check.op == "compare_time"
	is_array(check.left)
	is_array(check.right)
}

_check_inputs(subj, check, item) := array.concat(_side_inputs(subj, object.get(check, "left", null), item), _side_inputs(subj, object.get(check, "right", null), item)) if {
	not check.inputs
	check.op == "compare"
	every f in ["left", "right"] {
		_side_form(object.get(check, f, null))
	}
	not _derived_once(check)
}

_check_inputs(subj, check, item) := _derived_eval(check, subj, item).inputs if {
	_derived_once(check)
}

_check_inputs(subj, check, _) := array.concat(_quantified_inputs(subj, check), _name_inputs(subj, check)) if {
	not check.inputs
	_quantified(check)
}

_name_inputs(subj, check) := [{"name": _path_name(p), "value": value_at(subj, p)} | some p in _element_name_paths(check)]

_element_name_paths(check) := [p | some p in _element_name_reads(check); p != _inner_path(check)]

_inner_path(check) := object.get(check.check, "path", []) if is_object(check.check)

_element_name_reads(check) := sort({p |
	some read in _scoped_reads(check)
	p := read[0]
	_named(p)
	not substring(p[0], 1, -1) in read[1]
})

_scoped_reads(check) := [read |
	given := _names_of(check)
	some leaf in _element_leaves(check.check)
	some read in _leaf_reads(leaf, given)
]

_leaf_reads(leaf, given) := [[p, given] | some p in _leaf_paths(leaf)] if not _quantified(leaf)

_leaf_reads(leaf, given) := array.concat([[p, given] | some p in array.concat([leaf.path], _named_each(leaf))], [[p, (given | _names_of(leaf))] |
	some l in _element_leaves(leaf.check)
	some p in _leaf_paths(l)
]) if _quantified(leaf)

_names_of(check) := {check.as} if "as" in object.keys(check)

_names_of(check) := set() if not "as" in object.keys(check)

_check_reads(leaf) := _leaf_paths(leaf) if not _quantified(leaf)

_check_reads(leaf) := _list_reads(leaf) if _quantified(leaf)

_element_leaves(check) := [check] if not _combinator(check)

_element_leaves(check) := [leaf | some group in check.options; some leaf in group] if _combinator(check)

_outer_named(check, p) if {
	_named(p)
	not substring(p[0], 1, -1) in _names_of(check)
}

_relative_path(check, p) := array.slice(p, 1, count(p)) if _reads_item(check, p)

_relative_path(check, p) := p if not _reads_item(check, p)

_reads_item(check, p) if {
	_named(p)
	substring(p[0], 1, -1) == check.as
}

_quantified_inputs(subj, check) := [{"name": nm, "value": vals}] if {
	not check.each
	inner := _inner_path(check)
	not _outer_named(check, inner)
	rel := _relative_path(check, inner)
	vals := [value_at(elem, rel) | some elem in _list_at(subj, check.path)]
	nm := _projection_name(check.path, rel)
}

_quantified_inputs(subj, check) := [
	{"name": _projection_name(check.path, []), "value": value_at(subj, check.path)},
	{"name": _path_name(inner), "value": value_at(subj, inner)},
] if {
	not check.each
	inner := _inner_path(check)
	_outer_named(check, inner)
}

_quantified_inputs(subj, check) := [{"name": _collection_name(check), "value": vals}] if {
	check.each
	vals := [value_at(elem, check.each) | some elem in _list_at(subj, check.path)]
}

_list_at(subj, path) := v if {
	v := value_at(subj, path)
	is_array(v)
}

_list_at(subj, path) := [] if not is_array(value_at(subj, path))

_check_inputs(subj, check, item) := [{"name": _item_path_name(item, check.path), "value": value_at(subj, check.path)}] if {
	not check.inputs
	not _two_sided(check)
	not _quantified(check)
	not _combinator(check)
	is_array(check.path)
}

_check_inputs(subj, check, item) := [{"name": r[0], "value": r[1]} | some r in sort(_any_of_reads(subj, check, item))] if {
	not check.inputs
	check.op == "any_of"
}

_any_of_reads(subj, check, item) := {[_item_path_name(item, p), value_at(subj, p)] |
	some group in check.options
	some leaf in group
	some p in _check_reads(leaf)
}

_leaf_paths(leaf) := [side | some side in [leaf.left, leaf.right]; is_array(side)] if _two_sided(leaf)

_leaf_paths(leaf) := [leaf.path] if {
	not _two_sided(leaf)
	leaf.path
}

_row_inputs(subj, check, item) := _check_inputs(subj, check, item) if not check.substitute

_row_inputs(subj, check, item) := _once(array.concat(
	_check_inputs(subj, check, item),
	_check_inputs(subj, check.substitute, item),
)) if check.substitute

_once(xs) := [x | some i, x in xs; not x in array.slice(xs, 0, i)]

_check_def(check, _) := _with_refs({"description": _reported_description(check), "meta": _reported_meta(check), "expression": check.expression}, check) if _s_read(check)

_check_def(check, item) := _with_refs(object.union(object.remove(_described(check, item), {"description", "meta"}), {"description": _reported_description(check), "meta": _reported_meta(check)}), check) if not _s_read(check)

_with_refs(def, checked) := object.union(def, {"$refs": _ref_inputs(checked)}) if count(_check_refs(checked)) > 0

_with_refs(def, checked) := def if count(_check_refs(checked)) == 0

_described(check, item) := object.union(check, {"expression": _expression_of(check, item)}) if {
	is_object(check)
	not check.substitute
}

_described(check, item) := {"expression": _expression_of(check, item)} if not is_object(check)

_described(check, item) := object.union(check, {"expression": concat("", [
	_expression_of(check, item),
	", or substitute: ",
	_expression_of(check.substitute, item),
])}) if check.substitute

_subject_item_name(req) := concat("", ["$", _each_step(req).each_as]) if _from_well_formed(req)

_subject_item_name(req) := concat("", [_steps_name(_from_steps(_from_of(req))), "[]"]) if {
	not _stepped(req)
	_from_well_formed(req)
	_from_of(req) != []
}

_subject_item_name(req) := "$input" if {
	not _stepped(req)
	_from_well_formed(req)
	_from_of(req) == []
}

_subject_item_name(req) := "<invalid from>" if not _from_well_formed(req)

_matching_count_name(req) := concat("", ["count(matching(", _from_text(req), "))"])

_from_text(req) := _from_name(_from_path(req)) if {
	_from_well_formed(req)
	_from_path(req) != []
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

_name_problem_inputs(name) := [{"name": "requirement name", "value": ["not a string"]}] if not is_string(name)

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
	not _badly_stepped(_from_of(req))
	not _badly_stepped(_id_of(req))
	_wrapped_in_where(_id_of(req)) == set()
	_req_json_problems(req) == set()
	_check_problem_inputs(req) == []
	_policy_problems == []
}

_check_problem_inputs(req) := [{"name": name, "value": sort({p[1] | some p in problems; p[0] == name})} | some name in sort({p[0] | some p in problems})] if {
	problems := {[_field_path_name(array.concat(_checks_at(req, f, n), p[0])), p[1]] |
		some f in ["applies_to", "checks"]
		some n, check in _req_checks(req, f)
		found := _check_problems(check, _from_names(req)) with data.ergo_sentence_here as _s_written_here(req, f, n)
		some p in found
	}
}

_req_checks(req, "applies_to") := _applies_to_of(req)

_req_checks(req, "checks") := _checks_of(req)

_checks_at(req, "applies_to", n) := ["subjects", _filter_owner(req, n), "applies_to", n]

_checks_at(_, "checks", n) := ["checks", n]

_from_names(req) := {n |
	_from_well_formed(req)
	n := _each_step(req).each_as
} | {data.ergo_subject_sentences.chains[req.subject] | _chained(req); data.ergo_sentence_here == true}

_well_formed_inputs(req) := array.concat(
	array.concat(
		[{"name": "count(checks)", "value": count(_checks_of(req))}],
		array.concat(_echo(req, "require", _require_of(req)), _from_echo(req)),
	),
	array.concat(array.concat(array.concat(_not_an_object_inputs(req), _field_problem_inputs(req)), _check_problem_inputs(req)), _policy_problems),
)

_echo(req, f, v) := [{"name": _field_name(f), "value": v}] if not _has_problems(req, f)

_echo(req, f, _) := [] if _has_problems(req, f)

_from_echo(req) := _echo(req, ["subjects", _from_owner(req), "from"], _from_of(req)) if _stepped(req)

_from_echo(req) := [] if not _stepped(req)

_applies_description(req) := concat("", ["The ", _text(_subject_type_of(req)), " is in scope"])

_applies_def(req) := {"$applies": _with_refs(
	{
		"description": _applies_description(req),
		"expression": concat(" and ", [_expression_of(_applies_to_of(req)[name], _subject_item_name(req)) | some name in _applies_to_names(req)]),
	},
	_applies_to_of(req),
)} if _size(_applies_to_of(req)) > 0

_applies_def(req) := {"$applies": {
	"description": _applies_description(req),
	"expression": "<invalid applies_to>",
}} if _bad_applies_to(req)

_applies_def(req) := {} if {
	_size(_applies_to_of(req)) == 0
	not _bad_applies_to(req)
}

_applies_to_names(req) := sort(object.keys(_applies_to_of(req))) if is_object(_applies_to_of(req))

_requirement_check_defs(req) := {name: object.union({"meta": {}}, def) | some name, def in _requirement_checks_written_or_added(req)}

_requirement_checks_written_or_added(req) := object.union(
	object.union(
		{name: def |
			some name, check in _checks_of(req)
			def := _check_def(check, _subject_item_name(req)) with data.ergo_sentence_here as _s_written_here(req, "checks", name)
		},
		object.union(_min_subjects_def(req), _unique_ids_def(req)),
	),
	object.union(_applies_def(req), _well_formed_def),
)

_subject_row_groups(matching, req, req_name, flaws, item, prepared) := [[row |
	some check_name in _names(prepared)
	row := object.union(
		{
			"requirement": req_name,
			"subject": ref,
			"check": check_name,
		},
		_outcome(req, prepared[check_name], flaws[check_name], entry.subject, item),
	)
] |
	some entry in matching
	ref := _entry_ref(entry, req)
]

_well_formed_row(req, req_name) := row if {
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

_min_subjects_row(doc, req, req_name, matching) := {
	"requirement": req_name,
	"subject": _req_subject_ref(req),
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": matching}], data.ergo_unreadable),
	"passed": _enough_subjects(doc, req, matching),
	"cause": _min_subjects_cause(doc, req, matching),
}

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

_unique_ids_row(refs, req, req_name) := {
	"requirement": req_name,
	"subject": _req_subject_ref(req),
	"check": "$unique_ids",
	"inputs": [{"name": _repeated_ids_name(req), "value": repeated}],
	"passed": count(repeated) == 0,
	"cause": _verdict_cause(count(repeated) == 0),
} if {
	repeated := _repeated_ids(refs)
}

_repeated_ids(refs) := [pair[1] | some pair in sort({[_literal_text(id), id] | some id in _repeats(sort([ref.id | some ref in refs]))})]

_repeats(sorted) := {x |
	some i, x in sorted
	i > 0
	x == sorted[i - 1]
}

_applies_rows(raw, refs, matches, req, req_name, flaws, item) := [{
	"requirement": req_name,
	"subject": refs[i],
	"check": "$applies",
	"inputs": _applies_inputs(entry.subject, req, item),
	"passed": matches[i],
	"cause": _applies_cause(entry.subject, req, flaws, matches[i]),
} |
	some i, entry in raw
] if {
	_size(_applies_to_of(req)) > 0
}

_applies_rows(raw, refs, _, req, req_name, _, _) := [{
	"requirement": req_name,
	"subject": refs[i],
	"check": "$applies",
	"inputs": [],
	"passed": false,
	"cause": "ill_formed",
} |
	some i, _ in raw
] if _bad_applies_to(req)

_applies_rows(_, _, _, req, _, _, _) := [] if {
	_size(_applies_to_of(req)) == 0
	not _bad_applies_to(req)
}

_applies_inputs(subj, req, item) := [inp |
	read := {inp |
		some name in _applies_to_names(req)
		some inp in _inputs_in(req, _applies_to_of(req)[name], subj, item)
	}
	some name in sort({inp.name | some inp in read})
	some inp in read
	inp.name == name
]

_evaluation(doc, req, name) := {
	"well_formed": _well_formed_row(req, name),
	"min_subjects": _min_subjects_row(doc, req, name, count(matching)),
	"unique_ids": _unique_ids_row(refs, req, name),
	"applies": applies,
	"subject_rows": groups,
	"total": count(raw),
	"matching": count(matching),
	"scope_readable": _scope_readable(raw, applies, req),
	"rows_complete": _rows_complete(groups, matching, req),
} if {
	raw := _raw_entries(doc, req)
	filter_flaws := {n: flaw |
		some n, check in _applies_to_of(req)
		flaw := _flaw(check, _from_names(req)) with data.ergo_sentence_here as _s_written_here(req, "applies_to", n)
	}
	check_flaws := {n: flaw |
		some n, check in _checks_of(req)
		flaw := _flaw(check, _from_names(req)) with data.ergo_sentence_here as _s_written_here(req, "checks", n)
	}
	item := _subject_item_name(req)
	refs := {i: _entry_ref(entry, req) | some i, entry in raw}
	matches := {i: _subject_matches(entry.subject, req, filter_flaws) | some i, entry in raw}
	applies := _applies_rows(raw, refs, matches, req, name, filter_flaws, item)
	matching := [raw[i] | some i, _ in raw; matches[i]]
	prepared := {n: _with_ref_answer(check) | some n, check in _checks_of(req)}
	groups := _subject_row_groups(matching, req, name, check_flaws, item, prepared)
}

_with_ref_answer(check) := _ref_answered_compare(check) if {
	is_object(check)
	check.op == "compare"
} else := object.union(check, {"checks": [_ref_answered_compare(c) | some c in check.checks]}) if {
	is_object(check)
	check.op in {"all_of", "for"}
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
	not _bad_applies_to(req)
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
	e.unique_ids.passed
	e.min_subjects.passed
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
	array.concat([e.well_formed, e.min_subjects, e.unique_ids], e.applies),
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
			[evaluations[name].min_subjects | some name in _names(policy)],
			[evaluations[name].unique_ids | some name in _names(policy)],
		),
	),
	array.concat(
		[row | some name in _names(policy); some row in evaluations[name].applies],
		[row | some name in _names(policy); some group in evaluations[name].subject_rows; some row in group],
	),
)

_names(x) := sort(object.keys(x)) if is_object(x)

_names(x) := [i | some i, _ in x] if is_array(x)

_names(x) := sort(x) if is_set(x)

report(doc, policy, params) := r if {
	raw := _section(policy, "requirements")
	written_subjects := _section(policy, "subjects")
	reads := _s_from_reads(written_subjects)
	subjects := _s_subjects(written_subjects, reads)
	subject_sentences := _s_subject_sentences(written_subjects, reads)
	reqs := _s_requirements(raw, subject_sentences.chains)
	sentences := _s_sentences(raw, reqs)
	unreadable := _unreadable_inputs(doc, params)
	resolved := _resolved_subjects with data.ergo_subjects as subjects with data.ergo_subject_sentences as subject_sentences
	written := object.union(_report_of(doc, reqs), {"description": _reported_description(policy), "meta": _reported_meta(policy)}) with data.ergo_policy_problems as _policy_problem_inputs(policy) with data.ergo_document as doc with data.ergo_params as params with data.ergo_subjects as subjects with data.ergo_resolved as resolved with data.ergo_unreadable as unreadable with data.ergo_sentences as sentences with data.ergo_subject_sentences as subject_sentences with input as {"ergo/names": {}}
	used := _used_subjects(reqs, subjects, resolved)
	r := _reported(written, unreadable, [raw, used])
}

_used_subjects(reqs, subjects, resolved) := {name: subjects[name] |
	some req in reqs
	_names_a_subject(req)
	some name in resolved[req.subject].members
}

_section(policy, name) := object.get(policy, name, {}) if is_object(policy)

_section(policy, _) := null if not is_object(policy)

_policy_problem_inputs(policy) := [{"name": concat(" ", ["policy", f]), "value": sort(_policy_field_problems(f, policy[f]))} |
	is_object(policy)
	some f in ["description", "meta"]
	f in object.keys(policy)
	count(_policy_field_problems(f, policy[f])) > 0
]

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

_unreadable_inputs(doc, params) := [{"name": name, "value": sort(problems)} |
	some [name, problems] in [["$input", _json_problems(doc)], ["$params", (_json_problems(params) | _params_shape_problems(params))]]
	count(problems) > 0
]

_params_shape_problems(params) := set() if is_object(params)

else := set() if params == null

else := {"not an object"}

_report_of(doc, policy) := {
	"compliant": _policy_compliant(policy, evaluations),
	"requirements": {name: {
		"description": _reported_description(req),
		"meta": _reported_meta(req),
		"require": _require_of(req),
		"status": status,
		"causes": _causes(status, evaluations[name]),
		"subjects": {"total": evaluations[name].total, "matching": evaluations[name].matching},
		"checks": _requirement_check_defs(req),
	} |
		some name, req in policy
		status := _status(req, evaluations[name])
	},
	"results": _results(policy, evaluations),
} if {
	evaluations := {name: _evaluated(doc, policy[name], name) | some name in _names(policy)}
}

_evaluated(doc, req, name) := e if {
	not _chained(req)
	e := _evaluation(doc, req, name) with data.ergo_in as {}
}

_evaluated(doc, req, name) := _chain_evaluation(req, name, _parent_pick(doc, req)) if _chained(req)

_chain_evaluation(req, name, pick) := e if {
	"subject" in object.keys(pick)
	e := _evaluation(pick.subject, req, name) with data.ergo_in as {pick.parent: pick.id} with data.ergo_parent as {pick.parent: pick.subject}
}

_chain_evaluation(req, name, pick) := object.union(base, {
	"min_subjects": _parent_min_subjects_row(req, name, pick.cause),
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
}) if {
	"cause" in object.keys(pick)
	base := _evaluation({}, req, name) with data.ergo_in as {}
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
		flaw := _flaw(check, _from_names(preq)) with data.ergo_sentence_here as _s_written_here(preq, "applies_to", n)
	}
	refs := {i: _entry_ref_of(entry, preq) | some i, entry in raw}
	matches := {i: _subject_matches(entry.subject, preq, flaws) | some i, entry in raw}
	applies := _applies_rows(raw, refs, matches, preq, "", flaws, _subject_item_name(preq))
	r := _parent_pick_from(raw, refs, applies, preq)
}

_parent_pick_from(raw, refs, applies, preq) := {"cause": _worst_of({row.cause | some row in applies} - {"satisfied", "value"})} if {
	not _scope_readable(raw, applies, preq)
} else := _single_parent(raw, refs, applies, preq)

_single_parent(raw, refs, applies, preq) := {"subject": raw[i].subject, "id": refs[i].id, "parent": preq.subject} if {
	kept := _kept_parents(raw, applies, preq)
	count(kept) == 1
	i := kept[0]
} else := {"cause": "none"} if {
	count(_kept_parents(raw, applies, preq)) == 0
} else := {"cause": "unusable"}

_kept_parents(raw, _, preq) := [i | some i, _ in raw] if _size(_applies_to_of(preq)) == 0

_kept_parents(_, applies, preq) := [i | some i, row in applies; row.passed] if _size(_applies_to_of(preq)) > 0

_parent_min_subjects_row(req, name, "none") := {
	"requirement": name,
	"subject": _req_subject_ref(req),
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": 0}], data.ergo_unreadable),
	"passed": _min_subjects_of(req) == 0,
	"cause": _verdict_cause(_min_subjects_of(req) == 0),
}

_parent_min_subjects_row(req, name, cause) := {
	"requirement": name,
	"subject": _req_subject_ref(req),
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": 0}], data.ergo_unreadable),
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

_basic_form(side) := "count" if {
	is_object(side)
	"count" in object.keys(side)
	object.keys(side) - {"count", "where"} == set()
	is_array(side.count)
	_where_shaped(side)
}

_basic_form(side) := "sum" if {
	is_object(side)
	"sum" in object.keys(side)
	object.keys(side) - {"sum", "each", "where"} == set()
	is_array(side.sum)
	is_array(object.get(side, "each", null))
	_where_shaped(side)
}

_basic_form(side) := f if {
	is_object(side)
	some f in ["count_of", "sum_of"]
	object.keys(side) == {f, "whose", "text"}
	is_array(side[f])
	is_array(side.whose)
	is_string(side.text)
}

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

_where_shaped(side) if not "where" in object.keys(side)

_where_shaped(side) if is_object(side.where)

_operand(x) if _basic_form(x) in {"path", "count", "sum", "count_of", "sum_of"}

_operand(x) if {
	_basic_form(x) == "literal"
	is_number(_written(x))
}

default _derived(_) := false

_derived(side) if _side_form(side) in {"count", "sum", "add", "count_of", "sum_of"}

default _derived_sides(_) := []

_derived_sides(check) := [check[f] | some f in ["left", "right"]; f in object.keys(check); _derived(check[f])] if check.op == "compare"

_simple_value(subj, side) := value_at(subj, side) if is_array(side)

_simple_value(_, side) := _written(side) if _basic_form(side) == "literal"

_basic_value(subj, side) := _simple_value(subj, side) if _basic_form(side) in {"path", "literal"}

_basic_value(subj, side) := count([c | some c in causes; c == "satisfied"]) if {
	_basic_form(side) == "count"
	causes := _item_causes(subj, side, side.count)
	_all_decided(causes)
}

_basic_value(subj, side) := sum(nums) if {
	_basic_form(side) == "sum"
	causes := _item_causes(subj, side, side.sum)
	_all_decided(causes)
	nums := [value_at(item, side.each) | some i, item in value_at(subj, side.sum); causes[i] == "satisfied"]
	every n in nums {
		is_number(n)
	}
}

_basic_value(subj, side) := r.value if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
	r.states == set()
}

_item_causes(subj, side, path) := [_where_cause(side, item) | some item in value_at(subj, path)] if is_array(value_at(subj, path))

_all_decided(causes) if {
	every c in causes {
		c in {"satisfied", "value", "missing"}
	}
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

_add_numbers(side, nums) := sum(nums) if not "text" in object.keys(side)

_where_cause(side, _) := "satisfied" if not "where" in object.keys(side)

_where_cause(side, item) := _leaf_cause(side.where, item) if "where" in object.keys(side)

_basic_states(_, side) := set() if _basic_form(side) == "literal"

_basic_states(subj, side) := _counted_states(subj, side, side.count) if _basic_form(side) == "count"

_basic_states(subj, side) := _counted_states(subj, side, side.sum) | {s |
	causes := _item_causes(subj, side, side.sum)
	some i, item in value_at(subj, side.sum)
	causes[i] == "satisfied"
	some s in _number_states(item, side.each)
} if _basic_form(side) == "sum"

_side_states(subj, side) := _basic_states(subj, side) if _basic_form(side)

_side_states(subj, side) := union({_operand_states(subj, operand) | some operand in side.add}) if _side_form(side) == "add"

_operand_states(subj, operand) := _number_states(subj, operand) if _basic_form(operand) == "path"

_operand_states(subj, operand) := _basic_states(subj, operand) if _basic_form(operand) != "path"

_number_states(x, path) := {s} if {
	s := _read_state(x, path)
	s != "value"
}

_number_states(x, path) := {"unusable"} if {
	_read_state(x, path) == "value"
	not is_number(value_at(x, path))
}

_number_states(x, path) := set() if {
	_read_state(x, path) == "value"
	is_number(value_at(x, path))
}

_counted_states(subj, _, path) := {s} if {
	s := _read_state(subj, path)
	s != "value"
}

_counted_states(subj, _, path) := {"unusable"} if {
	_read_state(subj, path) == "value"
	not is_array(value_at(subj, path))
}

_counted_states(subj, side, path) := {c |
	some c in _item_causes(subj, side, path)
	not c in {"satisfied", "value", "missing"}
} if {
	_read_state(subj, path) == "value"
	is_array(value_at(subj, path))
}

_derived_states(check, subj) := union({_side_states(subj, side) | some side in _derived_sides(check)}) | {"unusable" |
	_derived_sides(check) != []
	l := _side_found(subj, check.left)
	r := _side_found(subj, check.right)
	not _usable_sides(check, l, r)
}

_side_found(subj, side) := _simple_found(subj, side) if _basic_form(side) in {"path", "literal"}

_side_found(subj, side) := _side_value(subj, side) if _derived(side)

_usable_sides(check, l, r) if {
	not "within" in object.keys(check)
	_usable_pair(check.cmp, l, r)
}

_usable_sides(check, l, r) if {
	"within" in object.keys(check)
	_numbers(l, r)
}

_basic_inputs(subj, side, item) := [{"name": _item_path_name(item, side), "value": value_at(subj, side)}] if _basic_form(side) == "path"

_basic_inputs(_, side, _) := [] if _basic_form(side) == "literal"

_basic_inputs(subj, side, item) := [_derived_input(subj, side, _basic_text(item, side)), {"name": _item_path_name(item, side.count), "value": value_at(subj, side.count)}] if _basic_form(side) == "count"

_basic_inputs(subj, side, item) := [_derived_input(subj, side, _basic_text(item, side)), {"name": _projection_name(side.sum, side.each), "value": [value_at(x, side.each) | some x in _list_at(subj, side.sum)]}] if _basic_form(side) == "sum"

_basic_inputs(subj, side, _) := [{"name": side.text, "value": object.get(r, "value", null)}, {"name": r.list, "value": r.values}] if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
}

_side_inputs(subj, side, item) := _basic_inputs(subj, side, item) if _basic_form(side)

_side_inputs(subj, side, item) := array.concat([_derived_input(subj, side, _side_text(item, side))], [i | some operand in side.add; some i in _basic_inputs(subj, operand, item)]) if _side_form(side) == "add"

_tally(subj, side) := {"states": {"not_an_object"}, "list": _path_name(path), "values": []} if {
	path := side[_basic_form(side)]
	not _named(path)
	not is_object(subj)
} else := {"states": {_read_state(subj, path)}, "list": _path_name(path), "values": []} if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
} else := r if {
	f := _basic_form(side)
	w := _walk(_walk_start({"path": side[f]}, subj), _walk_keys({"path": side[f]}, subj), true)
	flaws := [_cond_flaw(c) | some c in side.whose]
	judged := [_tally_judge(side, e, flaws) | some e in w.items]
	kept := [e.v | some i, e in w.items; judged[i].kept]
	states := ((({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {c | some j in judged; some c in j.states}) | _tally_number_states(f, kept)) | {fl | some fl in flaws; fl != ""}
	r := object.union({"states": states, "list": _walk_name(side[f], w.walked), "values": [_walk_shown(e.v) | some e in w.items]}, _tally_value(f, kept, states))
}

_tally_judge(side, e, flaws) := {"kept": kept, "states": ({c | some c in causes; not c in {"satisfied", "value", "missing"}} | _tally_mark(kept, e))} if {
	causes := [_tally_cond_cause(c, e.iv, flaws[i]) | some i, c in side.whose]
	kept := count([c | some c in causes; c in {"value", "missing"}]) == 0
}

_tally_cond_cause(c, item, "") := _leaf_cause(c, item)

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

_derived_input(subj, side, name) := {"name": name, "value": v} if {
	v := _side_value(subj, side)
} else := {"name": name, "value": null}

_basic_text(item, side) := _item_path_name(item, side) if _basic_form(side) == "path"

_basic_text(_, side) := _value_text(side) if _basic_form(side) == "literal"

_basic_text(item, side) := concat("", ["count(", _item_path_name(item, side.count), _where_text(side, side.count), ")"]) if _basic_form(side) == "count"

_basic_text(_, side) := concat("", ["sum(", _projection_name(side.sum, side.each), _where_text(side, side.sum), ")"]) if _basic_form(side) == "sum"

_basic_text(_, side) := side.text if _basic_form(side) in {"count_of", "sum_of"}

_side_text(item, side) := _basic_text(item, side) if _basic_form(side)

_side_text(item, side) := concat(" + ", [_basic_text(item, operand) | some operand in side.add]) if {
	_side_form(side) == "add"
	not "text" in object.keys(side)
}

_side_text(_, side) := side.text if {
	_side_form(side) == "add"
	"text" in object.keys(side)
}

_where_text(side, _) := "" if not "where" in object.keys(side)

_where_text(side, path) := concat("", [" where ", _where_describe(side.where, concat("", [_steps_name(path), "[]"]))]) if "where" in object.keys(side)

_where_describe(check, _) := check.expression if _written_expression(check)

_where_describe(check, item) := _leaf_describe(check, item) if not _written_expression(check)

_compare_side_text(item, check, f) := _side_text(item, check[f]) if {
	f in object.keys(check)
	_side_form(check[f])
}

_compare_side_text(_, check, f) := concat("", ["<invalid ", f, ">"]) if {
	f in object.keys(check)
	not _side_form(check[f])
}

_compare_side_text(_, check, f) := concat("", ["<missing ", f, ">"]) if not f in object.keys(check)

_simple_side(side) if _basic_form(side) in {"path", "literal"}

_simple_side_text(item, check, f) := _item_path_name(item, check[f]) if {
	f in object.keys(check)
	is_array(check[f])
}

_simple_side_text(_, check, f) := _value_text(check[f]) if {
	f in object.keys(check)
	_basic_form(check[f]) == "literal"
}

_simple_side_text(_, check, f) := concat("", ["<invalid ", f, ">"]) if {
	f in object.keys(check)
	not _simple_side(check[f])
}

_simple_side_text(_, check, f) := concat("", ["<missing ", f, ">"]) if not f in object.keys(check)

_within_text(check) := concat("", [", within ", _value_text(check.within)]) if "within" in object.keys(check)

_within_text(check) := "" if not "within" in object.keys(check)

_basic_paths(side) := [side] if _basic_form(side) == "path"

_basic_paths(side) := [side.count] if _basic_form(side) == "count"

_basic_paths(side) := [side.sum, side.each] if _basic_form(side) == "sum"

_basic_paths(side) := [] if _basic_form(side) == "literal"

_basic_paths(side) := [side[f]] if {
	f := _basic_form(side)
	f in {"count_of", "sum_of"}
}

_sentence_side(side) if _basic_form(side) in {"count_of", "sum_of"}

_sentence_side(side) if {
	is_object(side)
	"text" in object.keys(side)
}

_sentence_side(side) if {
	_side_form(side) == "add"
	some operand in side.add
	_basic_form(operand) in {"count_of", "sum_of"}
}

_side_paths(side) := _basic_paths(side) if _basic_form(side)

_side_paths(side) := [p | some operand in side.add; some p in _basic_paths(operand)] if _side_form(side) == "add"

_side_paths(side) := [] if not _side_form(side)

_where_children(node, names) := array.concat(
	[[node[f].where, [f, "where"], "where", names] |
		node.op == "compare"
		some f in ["left", "right"]
		f in object.keys(node)
		_basic_form(node[f]) in {"count", "sum"}
		"where" in object.keys(node[f])
	],
	[[c, array.concat(at, ["whose", i]), "where", names] |
		node.op == "compare"
		some f in ["left", "right"]
		f in object.keys(node)
		some [at, side] in _tallies(node[f], [f])
		some i, c in side.whose
	],
)

_tallies(side, at) := [[at, side]] if _basic_form(side) in {"count_of", "sum_of"}

_tallies(side, at) := [[array.concat(at, ["add", i]), operand] | some i, operand in side.add; _basic_form(operand) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_tallies(side, _) := [] if not _side_form(side) in {"count_of", "sum_of", "add"}

_side_problem(node) := ({concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	not _side_form(node[f])
} | {concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	_sentence_side(node[f])
	not _s_read(node)
}) | {concat("", ["invalid ", f]) |
	node.op == "compare_time"
	some f in ["left", "right"]
	f in object.keys(node)
	not is_array(node[f])
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

_derived_placement_problem(node, kinds) := {concat("", [_side_form(side), " can't go here"]) |
	kinds != []
	not _assertion_kinds(kinds)
	some side in _derived_sides(node)
} | {"substitute can't go here" |
	kinds != []
	kinds[count(kinds) - 1] == "where"
	"substitute" in object.keys(node)
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
	"for_item": concat("", [`^(every|some) +(`, path, `)(?: +whose +(`, conds, `))?(, +if +any,)? +as +(`, key, `)$`]),
	"from": concat("", [`^(`, path, `)(?: +named +by +each +of +(`, rpath, `))?(?: +whose +(`, conds, `))?$`]),
	"conds": concat("", [`(`, cond, `)(?: +and +|$)`]),
	"cond": concat("", [`^(`, left, `) +(`, phrase, `)$`]),
	"phrases": phrases,
	"kinds": {kind[0]: concat("", [`^(?:`, kind[1], `)$`]) | some kind in kinds},
	"plain": concat("", [`^(`, path, `) +(\S.*)$`]),
	"quantified": concat("", [`^(every|some) +(`, path, `) +(\S.*)$`]),
	"path": concat("", [`^`, path, `$`]),
	"path_parts": concat("", [`^(?:(item +([1-9][0-9]*)|first|last) +of +)?(`, start, `)((?:`, step, `)*)$`]),
	"steps": concat("", [`\.(`, key, `|`, dq, `)| +named +by +(`, ref, `)|\[(`, ref, `)\]|\[(`, dq, `)\]|\[(0|[1-9][0-9]*)\]`]),
	"terms": concat("", [`(`, term, `)(?: +plus +|$)`]),
	"number": concat("", [`^`, num, `$`]),
	"derived": concat("", [`^(count|sum) +of +(`, path, `)$`]),
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
	pos := `(?:item +[1-9][0-9]*|first|last) +of +`
	plain := concat("", [`(?:`, start, `)(?:`, step, `)*`])
	path := concat("", [`(?:`, pos, `)?`, plain])
	rpath := concat("", [`(?:`, pos, `)?(?:`, rstart, `)(?:`, step, `)*`])
	derived := concat("", [`(?:count|sum) +of +`, path])
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
	assertion := concat("", [`(?:(?:every|some) +`, path, `|`, left, `)(?: +whose +`, conds, `)?(?:, +if +any,)? +(?:`, phrase, `)`])
	for_item := concat("", [`(?:every|some) +`, path, `(?: +whose +`, conds, `)?(?:, +if +any,)? +as +`, key])
}

_s_words := {"a", "after", "an", "and", "as", "at", "before", "between", "count", "each", "empty", "equal", "every", "false", "first", "in", "item", "last", "less", "more", "named", "not", "null", "of", "on", "one", "or", "plus", "some", "sum", "true", "whose", "within"}

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
} else := [`an item starts with "every" or "some"`] if {
	not regex.match(`^(?:every|some) `, text)
} else := [`an item ends with "as" and a name, like "every pull_requests as pr"`] if {
	not regex.match(` as +[^ ,]+$`, text)
} else := _s_problems(text, pat)

_from_line(raw) := line if {
	pat := _s_patterns
	line := _s_from_of(trim_space(raw), pat)
	count(_s_sentence_problems(line)) == 0
} else := {"problems": _s_problems(trim_space(raw), _s_patterns)}

_s_from_of(text, pat) := object.union({"path": _s_path_of(m[1], pat)}, object.union(_s_each_of(m[2], pat), _s_where_of(m[3], pat))) if {
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
		{m[1]: _s_path_of(m[2], pat), "as": m[5]},
		object.union(_s_where_of(m[3], pat), _s_if_any(m[4])),
	)
}

_s_if_any("") := {}

_s_if_any(text) := {"if_any": true} if text != ""

_s_where_of("", _) := {}

_s_where_of(text, pat) := {"where": conds} if {
	text != ""
	pieces := _s_pieces(pat.conds, text)
	conds := [_s_cond_of(c, pat) | some c in pieces]
	count(conds) == count(pieces)
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
} else := _s_path_of(text, pat)

_s_path_of(text, pat) := _s_lifted(object.union(_s_position_of(m[1], m[2]), _s_start_of(m[3], _s_steps_of(m[4], pat)))) if {
	m := regex.find_all_string_submatch_n(pat.path_parts, text, 1)[0]
}

_s_lifted(path) := object.union(object.remove(path, ["steps"]), {"position": last.index + 1, "steps": array.slice(path.steps, 0, count(path.steps) - 1)}) if {
	not "position" in object.keys(path)
	last := path.steps[count(path.steps) - 1]
	is_object(last)
	"index" in object.keys(last)
} else := path

_s_position_of("", _) := {}

_s_position_of(word, "") := {"position": word} if word != ""

_s_position_of(_, digits) := {"position": to_number(digits)} if digits != ""

_s_start_of("$params", steps) := {"start": "params", "steps": steps}

_s_start_of("$input", steps) := {"start": "input", "steps": steps}

_s_start_of(key, steps) := {"steps": array.concat([key], steps), "bare_word": key} if key in _s_words

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(key)], steps)} if {
	not key in _s_words
	not startswith(key, "$")
	not startswith(key, ".")
}

_s_start_of(key, steps) := {"steps": array.concat([_s_key_of(substring(key, 1, -1))], steps)} if startswith(key, ".")

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

_s_step_of(m) := {"index": to_number(m[5])} if m[5] != ""

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

_s_sentence_problems(parsed) := (((((((((((((({concat("", [node.bare_word, " is a word of the grammar: write .", node.bare_word]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bare_word" in object.keys(node)
} | {concat("", [node.bad_name, " can't be a name"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	"bad_name" in object.keys(node)
}) | {concat("", [node.as, " can't be a name"]) |
	some node in _s_nodes(parsed)
	is_object(node)
	_s_bad_name(object.get(node, "as", ""))
}) | {concat("", [name, " is given twice"]) |
	some i, item in object.get(parsed, "items", [])
	name := item.as
	parsed.items[j].as == name
	j < i
}) | {"if any can't go with some" |
	some node in _s_nodes(parsed)
	is_object(node)
	"some" in object.keys(node)
	object.get(node, "if_any", false) == true
}) | {"a whose goes after every, some, count of or sum of" |
	some node in _s_nodes(parsed)
	node != parsed
	is_object(node)
	"where" in object.keys(node)
	object.keys(node) & {"every", "some"} == set()
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
	node.op in {"starts with", "ends with"}
	"value" in object.keys(node)
	not is_string(node.value)
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

_s_parsed_anyway(text, pat) := _s_from_of(text, pat)

_s_check_text(parsed) := concat(" and ", [_s_assertion_text(a) | some a in parsed.assertions])

_s_for_line_text(parsed) := concat(", ", [_s_for_item_text(a) | some a in parsed.items])

_s_from_line_text(parsed) := concat("", [_s_path_text(parsed.path, "left"), _s_each_text(parsed), _s_where_text(parsed)])

_s_each_text(parsed) := concat("", [" named by each of ", _s_path_text(parsed.named_by_each_of, "right")]) if "named_by_each_of" in object.keys(parsed)

_s_each_text(parsed) := "" if not "named_by_each_of" in object.keys(parsed)

_s_for_item_text(item) := concat("", [_s_quantified_text(item), " as ", item.as])

_s_assertion_text(a) := concat(" ", [_s_quantified_text(a), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) != ""

_s_assertion_text(a) := concat(" ", [concat("", [_s_left_text(a), _s_where_text(a)]), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) == ""

_s_quantified_text(a) := concat("", [_s_quantifier_of(a), " ", _s_path_text(a[_s_quantifier_of(a)], "left"), _s_where_text(a), _s_if_any_text(a)])

_s_quantifier_of(a) := "every" if "every" in object.keys(a)

_s_quantifier_of(a) := "some" if "some" in object.keys(a)

_s_quantifier_of(a) := "" if object.keys(a) & {"every", "some"} == set()

_s_if_any_text(a) := ", if any," if object.get(a, "if_any", false) == true

_s_if_any_text(a) := "" if not object.get(a, "if_any", false)

_s_where_text(a) := concat("", [" whose ", concat(" and ", [_s_cond_text(c) | some c in a.where])]) if "where" in object.keys(a)

_s_where_text(a) := "" if not "where" in object.keys(a)

_s_cond_text(c) := concat(" ", [_s_left_text(c), _s_phrase_text(c.phrase)])

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

_s_term_text(t) := _s_path_text(t, "right") if {
	is_object(t)
	"steps" in object.keys(t)
}

_s_path_text(p, side) := concat("", [_s_position_text(p), _s_start_text(p, side), concat("", [_s_step_text(s) | some s in array.slice(p.steps, _s_first_step(p), count(p.steps))])])

_s_position_text(p) := concat("", ["item ", _json_text(p.position), " of "]) if is_number(object.get(p, "position", null))

_s_position_text(p) := concat("", [p.position, " of "]) if is_string(object.get(p, "position", null))

_s_position_text(p) := "" if not "position" in object.keys(p)

_s_first_step(p) := 0 if "start" in object.keys(p)

_s_first_step(p) := 1 if not "start" in object.keys(p)

_s_start_text(p, _) := "$params" if object.get(p, "start", "") == "params"

_s_start_text(p, _) := "$input" if object.get(p, "start", "") == "input"

_s_start_text(p, side) := concat("", [_s_dot(p.steps[0], side), _s_key_text(p.steps[0])]) if not "start" in object.keys(p)

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

_s_from_reads(subjects) := {name: object.union(_s_from_part(name, lines, subjects, {"narrow": narrow, "descend": descend}), _s_id_part(def)) | some name, def in subjects; is_object(def)} if {
	is_object(subjects)
	lines := {name: _from_line(def.from) | some name, def in subjects; is_object(def); is_string(def.from)}
	narrow := {name: _s_chain_parent(name, lines, subjects) | some name, _ in subjects}
	descend := {name: lines[name].path.steps[0] | some name, _ in lines; "path" in object.keys(lines[name]); _s_descends(name, lines[name], subjects)}
}

_s_from_part(name, lines, subjects, chains) := _s_from_read(name, lines[name], subjects, chains) if name in object.keys(lines)

_s_from_part(name, lines, _, _) := {} if not name in object.keys(lines)

_s_id_part(def) := {"identified_by": _s_id_read(def.identified_by)} if is_string(object.get(def, "identified_by", null))

_s_id_part(def) := {} if not is_string(object.get(def, "identified_by", null))

_s_id_read(text) := {"path": _s_model_path(fl.path)} if {
	fl := _from_line(text)
	object.keys(fl) == {"path"}
	count(_s_paths_unsupported({"path": fl.path})) == 0
} else := {"problems": [`identified_by is a path, like "id" or "build.number"`]}

_s_from_reads(subjects) := {} if not is_object(subjects)

_s_subjects(subjects, reads) := {name: _s_subject(name, def, reads) | some name, def in subjects} if is_object(subjects)

_s_subjects(subjects, _) := subjects if not is_object(subjects)

_s_subject(name, null, _) := {"from": [name]}

_s_subject(name, def, reads) := object.union(_s_without_narrowed_from(def, reads[name]), object.union(_s_from_fields(name, def, reads), _s_id_field(reads[name]))) if is_object(def)

_s_without_narrowed_from(def, read) := object.remove(def, ["from"]) if {
	"of" in object.keys(object.get(read, "fields", {}))
	_s_from_used(def, read)
} else := def

_s_subject(_, def, _) := def if {
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

_s_from_read(name, fl, subjects, chains) := {"problems": problems, "fields": fields, "parent": parent} if {
	"path" in object.keys(fl)
	conds := [_s_check([_s_cond_text(c)], {}, set()) | some c in object.get(fl, "where", [])]
	problems := sort((((_s_chain_unsupported(name, fl, subjects, chains.descend) | _s_from_start_problems(fl)) | _s_paths_unsupported({"path": fl.path})) | {concat("", ["whose: ", p]) | some c in conds; some p in object.get(c, "$sentence", [])}))
	fields := object.union(_s_source(name, fl, subjects), _s_whose_filters(_s_filter_prefix(name, chains.narrow), conds))
	parent := _s_descend_parent(name, fl, subjects)
} else := {"problems": object.get(fl, "problems", ["doesn't parse"]), "fields": {}}

_s_source(name, fl, subjects) := {"of": fl.path.steps[0]} if {
	_s_narrows(name, fl, subjects)
} else := {"from": array.concat(_s_from_steps(array.slice(_s_model_path(fl.path), 1, count(fl.path.steps))), _s_each_step(fl))} if {
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

_s_chain_unsupported(name, fl, subjects, descend) := {"a chain of more than two subjects isn't supported yet" |
	_s_descends(name, fl, subjects)
	fl.path.steps[0] in object.keys(descend)
}

_s_id_field(read) := {"identified_by": read.identified_by.path} if "path" in object.keys(object.get(read, "identified_by", {}))

else := {}

_s_subject_sentences(subjects, reads) := {"chains": {name: p | some name, r in reads; _s_from_used(subjects[name], r); p := object.get(r, "parent", null); p != null}, "narrowed": {name | some name, r in reads; _s_from_used(subjects[name], r); "of" in object.keys(r.fields)}, "filters": {[name, n] | some name, r in reads; _s_from_used(subjects[name], r); some n, _ in object.get(r.fields, "applies_to", {})}, "problems": {name: probs | some name, def in subjects; probs := _s_subject_problems(name, def, reads); probs != {}}} if is_object(subjects)

_s_subject_sentences(subjects, _) := {"chains": {}, "narrowed": set(), "filters": set(), "problems": {}} if not is_object(subjects)

_s_subject_problems(name, def, reads) := {f: ps | some f in ["from", "identified_by"]; ps := _s_field_problems(name, def, f, reads); ps != []} if is_object(def)

_s_subject_problems(_, def, _) := {} if not is_object(def)

_s_field_problems(name, def, "from", reads) := array.concat(reads[name].problems, [`applies_to can't go with a from written as a sentence: put the conditions after "whose"` | "applies_to" in object.keys(def)]) if is_string(object.get(def, "from", null))

_s_field_problems(name, def, "identified_by", reads) := object.get(reads[name].identified_by, "problems", []) if is_string(object.get(def, "identified_by", null))

_s_field_problems(_, def, f, _) := [] if not is_string(object.get(def, f, null))

_s_requirements(reqs, chains) := {name: _s_requirement(req, chains) | some name, req in reqs} if is_object(reqs)

_s_requirements(reqs, _) := reqs if not is_object(reqs)

_s_requirement(req, chains) := object.union(object.remove(req, ["checks"]), {"checks": {name: _s_parent_named(check, _s_written_check(check), _s_parents_of(req, chains)) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
} else := req

_s_parents_of(req, chains) := {chains[req.subject]} if {
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

_s_named_model(m, names) := object.union(m, {"checks": [_s_named_model_leaf(c, names) | some c in m.checks]}) if m.op == "all_of"

_s_named_model(m, names) := object.union(m, {
	"checks": [_s_named_model_leaf(c, names) | some c in m.checks],
	"items": [object.union(item, {"path": _s_named_path(item.path, names), "whose": [_s_named(c, names) | some c in item.whose]}) | some item in m.items],
}) if m.op == "for"

_s_named_model(m, names) := _s_named_model_leaf(m, names) if not m.op in {"all_of", "for"}

_s_named_model_leaf(m, names) := object.union(m, {
	"path": _s_named_path(m.path, names),
	"whose": [_s_named(c, names) | some c in m.whose],
	"check": object.union(_s_named(m.check, names), object.filter(m.check, {"path", "left"})),
}) if m.op in {"every", "some"}

_s_named_model_leaf(m, names) := _s_named(m, names) if not m.op in {"every", "some"}

_s_written_check(check) := _s_check([check], {}, set()) if is_string(check)

_s_written_check(check) := _s_check(_s_lines(check.assert), object.filter(check, {"description", "meta"}), _s_form_problems(check)) if {
	_s_assert_form(check)
	not "for" in object.keys(check)
}

_s_written_check(check) := _s_check_for(_s_lines(check.assert), check.for, object.filter(check, {"description", "meta"}), _s_form_problems(check)) if {
	_s_assert_form(check)
	"for" in object.keys(check)
}

_s_lines(a) := a if is_array(a)

_s_lines(a) := [a] if not is_array(a)

_s_written_check(check) := check if not _s_written_as_sentence(check)

_s_written_as_sentence(check) if is_string(check)

_s_written_as_sentence(check) if _s_assert_form(check)

_s_assert_form(check) if {
	is_object(check)
	"assert" in object.keys(check)
	not "op" in object.keys(check)
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

_s_form_problems(check) := ({concat("", ["unknown field ", _text(f)]) | some f in object.keys(check); not f in {"assert", "description", "meta", "for"}} | _s_assert_problem(check.assert)) | _s_for_problem(check)

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

_s_check(lines, wording, problems) := object.union(wording, object.union(model, {"expression": _s_check_text({"assertions": assertions})})) if {
	count(problems) == 0
	parsed := [_sentence(line) | some line in lines]
	every p in parsed {
		"assertions" in object.keys(p)
	}
	assertions := [a | some p in parsed; some a in p.assertions]
	count({u | some a in assertions; some u in _s_assertion_unsupported(a)}) == 0
	model := _s_model_of(assertions)
} else := object.union(wording, {"expression": concat(" and ", [_s_written_text(line) | some line in lines]), "$sentence": sort(_s_or_unrunnable(problems | _s_lines_problems(lines)))})

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

_s_unread(node) if {
	_s_read(node)
	count(object.get(node, "$sentence", [])) > 0
}

_s_read(node) if {
	is_object(node)
	data.ergo_sentence_here == true
}

_s_written_here(req, "checks", n) if {
	[req, n] in data.ergo_sentences
} else := false

_s_written_here(req, "applies_to", n) if {
	some m in data.ergo_resolved[req.subject].members
	[m, n] in data.ergo_subject_sentences.filters
} else := false

_s_unsupported(parsed) := set() if not "assertions" in object.keys(parsed)

_s_unsupported(parsed) := {u | some a in parsed.assertions; some u in _s_assertion_unsupported(a)} if "assertions" in object.keys(parsed)

_s_assertion_unsupported(a) := (((_s_paths_unsupported(a) | _s_argument_unsupported(a.phrase)) | {u | some c in object.get(a, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(a)) | {"count of, sum of and plus after every or some aren't supported yet" |
	terms := object.get(a.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
} if object.keys(a) & {"every", "some"} != set()

_s_cond_unsupported(c) := _s_derived_unsupported(c) if "terms" in object.keys(c)

_s_cond_unsupported(c) := _s_argument_unsupported(c.phrase) if not "terms" in object.keys(c)

_s_walk_too_long(a) := {"every and some over more than ten steps aren't supported yet" | count(_walk_steps(_s_model_path(a[_s_quantifier_of(a)]))) > 10}

_s_assertion_unsupported(a) := _s_derived_unsupported(a) if "terms" in object.keys(a)

_s_derived_unsupported(a) := ((_s_paths_unsupported(a) | {`"is between" after a count of, a sum of or a plus isn't supported yet` | a.phrase.op == "is between"}) | {u | some c in object.get(a, "where", []); some u in _s_tally_cond_unsupported(c)}) | {"every and some over more than ten steps aren't supported yet" |
	some t in array.concat(a.terms, object.get(a.phrase, "terms", []))
	_s_derived_term(t)
	count(_walk_steps(_s_model_path(object.get(t, "count", object.get(t, "sum", null))))) > 10
}

_s_tally_cond_unsupported(c) := ({"a count of, a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	"terms" in object.keys(c)
} | {"a count of, a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	terms := object.get(c.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
}) | _s_argument_unsupported(c.phrase)

_s_assertion_unsupported(a) := _s_paths_unsupported(a) | _s_argument_unsupported(a.phrase) if object.keys(a) & {"every", "some", "terms"} == set()

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

_s_paths_unsupported(a) := {"last of isn't supported yet" |
	some node in _s_nodes(a)
	is_object(node)
	object.get(node, "position", null) == "last"
} | {concat("", ["unknown name ", ref.steps[0]]) |
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

_s_argument_unsupported(ph) := {concat("", [`"`, ph.op, `" with a value isn't supported yet: compare with a field`])} if {
	ph.op in object.keys(_s_time_cmps)
	"value" in object.keys(ph)
}

_s_argument_unsupported(ph) := {concat("", [`"`, _s_phrase_words(ph), `" with named by in its path isn't supported yet`])} if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	"start" in object.keys(p)
	not _s_ref_steps(p)
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

_s_ref_steps(p) if {
	every s in p.steps {
		_s_plain_step(s)
	}
}

_s_plain_step(s) if is_string(s)

_s_plain_step(s) if {
	is_object(s)
	is_number(object.get(s, "index", null))
}

_s_time_cmps := {"is before": "lt", "is after": "gt", "is on or after": "gte", "is on or before": "lte"}

_s_order_cmps := {"is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

_s_leaf_model(a) := object.union({"op": "compare", "left": _s_left_side(a.terms, object.get(a, "where", [])), "cmp": _s_derived_cmps[a.phrase.op], "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within"})) if "terms" in object.keys(a)

_s_leaf_model(a) := _s_plain_model(a) if not "terms" in object.keys(a)

_s_derived_cmps := {"is": "eq", "is not": "ne", "is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

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

_s_plain_model(a) := {"op": "compare", "left": _s_model_path(a.path), "cmp": _s_list_cmps[a.phrase.op], "right": _s_model_path(_s_list_path(a.phrase))} if _s_field_arg(a.phrase)

_s_field_arg(ph) if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	not "start" in object.keys(p)
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
	{"starts with": ["compare", "starts_with"], "ends with": ["compare", "ends_with"]},
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

_s_whose_side(t, where) := object.union(_s_term_side(t), {"whose": [_s_plain_model(c) | some c in where], "text": concat("", [_s_term_text(t), _s_where_text({"where": where})])})

_s_term_side(t) := {"literal": t} if is_number(t)

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

_s_model_start(p) := [{"literal": p.steps[0]}] if {
	not "start" in object.keys(p)
	startswith(p.steps[0], "$")
}

_s_model_start(p) := [p.steps[0]] if {
	not "start" in object.keys(p)
	not startswith(p.steps[0], "$")
}

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

_s_model_step(s) := {"named_by": s.named_by.steps[0]} if {
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
	not _named(check.path)
	not is_object(subj)
} else := _walk_read_row(check, subj)

_walk_flawed(check) if _param_broken(check, set())

_walk_flawed(_) if _unreadable_input

_walk_read_row(check, subj) := {"cause": state, "inputs": [{"name": _path_name(check.path), "value": []}], "failed": []} if {
	state := _read_state(subj, check.path)
	not _walk_keys(check, subj)
}

_walk_read_row(check, subj) := {"cause": cause, "inputs": inputs, "failed": failed} if {
	keys := _walk_keys(check, subj)
	w := _walk(_walk_start(check, subj), keys, check.if_any == true)
	judged := [_walk_judge(check, e) | some e in w.items]
	fails := array.concat(array.concat(w.fails, [j.failure | some j in judged; j.failure != null]), _walk_stop(w))
	cause := _walk_cause(check, w, judged, fails)
	failed := _walk_failed(cause, fails)
	inputs := _walk_inputs(check, w)
}

_walk_keys(check, subj) := ks if {
	_ := _start_of(subj, check.path)
	ks := _keys_of(check.path)
}

_walk_start(check, subj) := {"c": _walk_root(check.path), "v": _start_of(subj, check.path), "i": null, "iv": null, "r": []}

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
	fails := [f | some r in levels; some f in r.fails]
	walked := {i | some i, r in levels; r.walked}
	items := [e | some e in r10.entries; e.i != null]
	trail := array.concat([start], [r.entries[0] | some i, r in levels; i < count(keys); count(r.entries) == 1])
}

_walk_level(entries, keys, i, _) := {"entries": entries, "fails": [], "walked": false} if i > count(keys)

_walk_level(entries, keys, i, if_any) := {"entries": [_walk_step(e, keys, i) | some e in expanded], "fails": fails, "walked": walked} if {
	i <= count(keys)
	walked := _walks_here(entries, keys, i)
	expanded := [x | some e in entries; some x in _walk_expand(e, walked)]
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

_walk_expand(e, false) := [e]

_walk_expand(e, true) := [{"c": array.concat(e.c, [j]), "v": x, "i": array.concat(e.c, [j]), "iv": x, "r": []} | some j, x in e.v] if is_array(e.v)

_walk_expand(e, true) := [] if not is_array(e.v)

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

_walk_judge(check, e) := {"kept": kept, "passed": passed, "failure": failure} if {
	undecided := [[c, cause] | some c in check.whose; cause := _row_cause(c, e.iv, ""); not cause in {"satisfied", "value"}]
	kept := count([c | some c in check.whose; _row_cause(c, e.iv, "") == "value"]) == 0
	leaf := _walk_target(check.check, e.r)
	passed := _walk_passed(undecided, kept, leaf, e.iv)
	failure := _walk_failure(e, undecided, kept, leaf, passed)
}

default _walk_passed(_, _, _, _) := false

_walk_passed([], true, leaf, v) if op_passed(leaf, v)

_walk_failure(e, [], true, leaf, false) := {"path": e.c, "item": e.i, "cause": _row_cause(leaf, e.iv, ""), "value": _walk_shown(e.v)}

_walk_failure(e, undecided, _, _, _) := {"path": array.concat(e.i, _walk_first_path(undecided[0][0])), "item": e.i, "cause": undecided[0][1], "value": _walk_first_value(undecided[0][0], e.iv)} if undecided != []

_walk_failure(_, [], false, _, _) := null

_walk_failure(_, [], true, _, true) := null

_walk_first_path(c) := _condition_paths(c)[0]

_walk_first_value(c, v) := value_at(v, _condition_paths(c)[0])

_condition_paths(c) := array.concat(_leaf_paths(c), [p | some side in _derived_sides(c); some p in _side_paths(side)])

_walk_target(leaf, r) := object.union(leaf, {"left": r}) if _two_sided(leaf)

_walk_target(leaf, r) := object.union(leaf, {"path": r}) if not _two_sided(leaf)

_walk_cause(_, w, _, _) := _walk_stop(w)[0].cause if w.walked == set()

_walk_cause(check, w, judged, fails) := _walk_verdict(check.op, check.if_any == true, judged, fails) if w.walked != set()

_walk_stop(w) := [] if w.walked != set()

_walk_stop(w) := [{"path": e.c, "item": e.c, "cause": _walk_stop_state(e.v), "value": _walk_shown(e.v)} | e := _walk_stopped_at(w.trail)] if w.walked == set()

_walk_stopped_at(trail) := [e | some i, e in trail; i > 0; not _walk_container(e.v)][0] if {
	some i, e in trail
	i > 0
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

_walk_failed(cause, fails) := [{"path": _path_name(f.path), "item": _path_name(f.item), "cause": f.cause, "value": f.value} |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_walk_inputs(check, w) := [{"name": _walk_name(check.path, w.walked), "value": [_walk_shown(e.v) | some e in w.items]}]

_walk_name(path, walked) := concat("", array.concat(array.concat(_walk_root_name(path), [concat("", [_walk_mark(i, walked), _step_name(i + count(_walk_root(path)), step)]) | some i, step in _walk_steps(path)]), [_walk_mark(count(_walk_steps(path)), walked)]))

_walk_root_name(path) := [_plain_step_name(0, path[0])] if _named(path)

_walk_root_name(path) := [] if not _named(path)

_walk_steps(path) := array.slice(path, count(_walk_root(path)), count(path))

_walk_mark(i, walked) := "[]" if i in walked

_walk_mark(i, walked) := "" if not i in walked

_s_check_for(lines, ftext, wording, problems) := object.union(wording, {
	"op": "for",
	"items": [_s_for_item_model(item, {earlier.as | some earlier in array.slice(fl.items, 0, i)}) | some i, item in fl.items],
	"checks": [_s_named(_s_model(a), names) | some a in assertions],
	"assertions": texts,
	"expression": concat("", ["for ", _s_for_line_text(fl), ": ", concat(" and ", texts)]),
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
	count(_s_for_unsupported(fl, assertions, names)) == 0
	texts := [_s_assertion_text(a) | some a in assertions]
} else := object.union(wording, {"expression": _s_for_written_text(lines, ftext), "$sentence": sort(_s_or_unrunnable(problems | _s_for_problems(lines, ftext)))})

_s_for_written_text(lines, ftext) := concat("", ["for ", trim_space(ftext), ": ", concat(" and ", [_s_written_text(line) | some line in lines])]) if is_string(ftext)

_s_for_written_text(lines, ftext) := concat(" and ", [_s_written_text(line) | some line in lines]) if not is_string(ftext)

_s_for_problems(lines, ftext) := {concat("", ["for: ", p]) | some p in object.get(_for_line(ftext), "problems", [])} | _s_for_line_unsupported(lines, ftext) if is_string(ftext)

_s_for_problems(lines, ftext) := _s_lines_problems(lines) if not is_string(ftext)

_s_for_line_unsupported(lines, ftext) := _s_lines_problems(lines) if not "items" in object.keys(_for_line(ftext))

_s_for_line_unsupported(lines, ftext) := _s_for_unsupported(fl, [], {item.as | some item in fl.items}) | {p | some p in _s_lines_problems(lines); _s_kept_problem(p, {item.as | some item in fl.items})} if {
	fl := _for_line(ftext)
	"items" in object.keys(fl)
}

_s_for_unsupported(fl, assertions, names) := {u | some i, item in fl.items; some u in _s_item_unsupported(item); _s_kept_problem(u, {earlier.as | some earlier in array.slice(fl.items, 0, i)})} | {u | some a in assertions; some u in _s_assertion_unsupported(a); _s_kept_problem(u, names)}

_s_item_unsupported(item) := (_s_paths_unsupported(item) | {u | some c in object.get(item, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(item)

_s_kept_problem(u, names) if not _s_names_a_for_name(u, names)

_s_names_a_for_name(u, names) if {
	parts := split(u, "unknown name ")
	count(parts) == 2
	parts[1] in names
}

_s_for_item_model(item, names) := {
	"q": q,
	"path": _s_named_path(_s_model_path(item[q]), names),
	"whose": [_s_named(_s_leaf_model(c), names) | some c in object.get(item, "where", [])],
	"if_any": object.get(item, "if_any", false),
	"as": item.as,
} if q := _s_quantifier_of(item)

_s_named(m, names) := object.union(m, {f: _s_named_side(m[f], names) | some f in ["path", "left", "right"]; f in object.keys(m)})

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

_s_named_tally(side, _) := side if {
	is_object(side)
	object.keys(side) & {"count_of", "sum_of"} == set()
}

_s_named_cond(c, names) := object.union(c, {f: _s_named_path(c[f], names) | some f in ["path", "left", "right"]; is_array(object.get(c, f, null))})

_s_named_path(p, names) := array.concat([concat("", ["$", p[0]])], array.slice(p, 1, count(p))) if {
	count(p) > 0
	is_string(p[0])
	p[0] in names
} else := p

_for_names := object.get(input, "ergo/names", {})

_for_row(check, subj) := object.union(_for_outer(check, subj, _for_names), {"cause": "unusable", "failed": []}) if {
	_walk_flawed(check)
} else := {"cause": "not_an_object", "inputs": [], "failed": []} if {
	some item in check.items
	not _named(item.path)
	not is_object(subj)
} else := _for_outer(check, subj, _for_names)

_for_outer(check, subj, names) := {"cause": w.unread, "inputs": _for_inputs(check, subj, names, check.items[0], w), "failed": []} if {
	w := _for_walk(check.items[0], subj, names)
	"unread" in object.keys(w)
} else := {"cause": cause, "inputs": inputs, "failed": failed} if {
	item := check.items[0]
	w := _for_walk(item, subj, names)
	pre := _for_pre(check, subj, names)
	judged := [_for_judge_outer(check, subj, names, item, e, pre) | some e in w.items]
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	failed := _for_failed(cause, fails)
	inputs := _for_inputs(check, subj, names, item, w)
}

_for_walk(item, subj, names) := w if {
	keys := _walk_keys(item, subj) with input as {"ergo/names": names}
	w := _walk(_walk_start(item, subj), keys, item.if_any == true) with input as {"ergo/names": names}
} else := {"items": [], "fails": [], "walked": set(), "trail": [], "unread": _read_state(subj, item.path)}

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

_for_judge_outer(check, subj, names, item, e, pre) := {"passed": res.passed, "kept": wh.kept, "failure": _for_failure(e, wh.undecided, wh.kept, res), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_outer_next(check, subj, object.union(names, {item.as: e.v}), wh.undecided, wh.kept, pre)
}

_for_judge_inner(check, subj, names, item, e) := {"passed": res.passed, "kept": wh.kept, "failure": _for_failure(e, wh.undecided, wh.kept, res), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_inner_next(check, subj, object.union(names, {item.as: e.v}), wh.undecided, wh.kept)
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

_for_failure(_, [], false, _) := null

_for_failure(e, undecided, _, res) := {"path": e.i, "item": e.i, "cause": res.cause, "value": null, "lines": res.lines} if undecided != []

_for_failure(e, [], true, res) := {"path": e.i, "item": e.i, "cause": res.cause, "value": null, "lines": res.lines} if not res.passed

_for_failure(_, [], true, res) := null if res.passed

_for_inner(check, subj, names, w) := {"passed": false, "cause": "not_an_object", "lines": []} if {
	check.items[1].path[0] == concat("", ["$", check.items[0].as])
	count(check.items[1].path) > 1
	not is_object(names[check.items[0].as])
} else := {"passed": false, "cause": w.unread, "lines": []} if {
	"unread" in object.keys(w)
} else := {"passed": cause == "satisfied", "cause": cause, "lines": lines} if {
	item := check.items[1]
	judged := [_for_judge_inner(check, subj, names, item, e) | some e in w.items]
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	lines := _for_merge_lines(check, cause, fails)
}

_for_lines(check, subj, names) := {"passed": count(lines) == 0, "cause": _all_of_cause(lines), "lines": lines} if {
	lines := [{"assertion": check.assertions[i], "cause": cause} |
		some i, c in check.checks
		cause := _assertion_cause(c, subj, "") with input as {"ergo/names": names}
		cause != "satisfied"
	]
}

_for_merge_lines(_, "satisfied", _) := []

_for_merge_lines(check, cause, fails) := [{"assertion": a, "cause": causes[0]} |
	some a in check.assertions
	causes := [l.cause | some f in fails; some l in f.lines; l.assertion == a]
	count(causes) > 0
] if cause != "satisfied"

_for_verdict(item, w, judged, fails) := _walk_stop(w)[0].cause if {
	w.walked == set()
	count(_walk_stop(w)) > 0
} else := _walk_verdict(item.q, item.if_any == true, judged, fails)

_for_failed("satisfied", _) := []

_for_failed(cause, fails) := [{"path": _path_name(f.path), "item": _path_name(f.item), "cause": f.cause, "value": f.value, "failed_assertions": f.lines} |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_for_inputs(check, subj, names, item, w) := [{"name": pair[0], "value": pair[1]} | some pair in sort(_for_input_pairs(check, subj, names, item, w))]

_for_input_pairs(check, subj, names, item, w) := ((({[_walk_name(item.path, w.walked), [_walk_shown(e.v) | some e in w.items]]} | _for_inner_pairs(check, subj, names, item, w)) | {[_path_name(shown), value_at(subj, shown)] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	shown := _before_names(p)
}) | {[i.name, i.value] |
	some c in check.checks
	some side in _derived_sides(c)
	not _tally_named(side)
	some i in _side_inputs(subj, side, null)
}) | {[i.name, i.value] |
	some c in check.checks
	_walks(c)
	not _for_named(c.path)
	some i in _walk_read_row(c, subj).inputs
}

_for_inner_pairs(check, _, _, _, _) := set() if count(check.items) == 1

_for_inner_pairs(check, subj, names, item, w) := {[_for_list_name(check.items[1].path, walked), values]} if {
	count(check.items) == 2
	_for_from_first(check)
	inner := [_for_walk(check.items[1], subj, object.union(names, {item.as: e.v})) | some e in w.items]
	walked := {i | some iw in inner; some i in iw.walked}
	values := [_walk_shown(e2.v) | some iw in inner; some e2 in iw.items]
}

_for_inner_pairs(check, subj, names, _, _) := {[_for_list_name(check.items[1].path, iw.walked), [_walk_shown(e.v) | some e in iw.items]]} if {
	count(check.items) == 2
	not _for_from_first(check)
	iw := _for_walk(check.items[1], subj, names)
}

_tally_named(side) if {
	some p in _side_paths(side)
	_for_named(p)
}

_tally_named(side) if {
	some t in _tally_parts(side)
	some c in t.whose
	some p in _condition_paths(c)
	_for_named(p)
}

_tally_parts(side) := [side] if _basic_form(side) in {"count_of", "sum_of"}

_tally_parts(side) := [o | some o in side.add; _basic_form(o) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_for_list_name(path, walked) := substring(_walk_name(path, walked), 1, -1) if _starts_at_name(path)

_for_list_name(path, walked) := _walk_name(path, walked) if not _starts_at_name(path)

_starts_at_name(p) if {
	_named(p)
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

_has_name_step(p) if {
	is_array(p)
	some step in p
	_name_step(step)
}

_for_named(p) if {
	_named(p)
	not _builtin(p)
}

_for_named(p) if {
	is_array(p)
	some step in p
	_name_step(step)
}

as_sentences(policy) := object.union(object.remove(policy, ["subjects", "requirements"]), _c_sections(policy)) if is_object(policy)

as_sentences(policy) := policy if not is_object(policy)

_c_sections(policy) := {f: _c_section(f, policy[f], _c_chains(policy)) | some f in ["subjects", "requirements"]; f in object.keys(policy)}

_c_chains(policy) := _s_subject_sentences(policy.subjects, _s_from_reads(policy.subjects)).chains if is_object(object.get(policy, "subjects", null))

_c_chains(policy) := {} if not is_object(object.get(policy, "subjects", null))

_c_section("subjects", section, _) := _c_subjects(section) if is_object(section)

_c_section("requirements", section, chains) := _c_requirements(section, chains) if is_object(section)

_c_section(_, section, _) := section if not is_object(section)

_c_requirements(reqs, chains) := {name: _c_requirement(req, chains) | some name, req in reqs}

_c_requirement(req, chains) := object.union(object.remove(req, ["checks"]), {"checks": {name: _c_check(check) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
	not object.get(req, "subject", null) in object.keys(chains)
} else := req

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
