# Copyright 2026 Kosli, Inc
# SPDX-License-Identifier: Apache-2.0

package ergo

import rego.v1

_req_field(req, f, d) := object.get(req, f, d) if is_object(req)

_req_field(req, _, d) := d if not is_object(req)

_object_or_empty(x) := x if is_object(x)

_object_or_empty(x) := {} if not is_object(x)

_checks_of(req) := _object_or_empty(_req_field(req, "checks", {}))

_applies_to_of(req) := _object_or_empty(_req_field(req, "applies_to", {}))

_from_of(req) := _req_field(req, "from", [])

_id_of(req) := _req_field(req, "id", [])

_subject_type_of(req) := _req_field(req, "subject_type", "subject")

_min_subjects_of(req) := _req_field(req, "min_subjects", 1)

_require_of(req) := _req_field(req, "require", "every")

_wrong_typed_fields(req) := [f |
	is_object(req)
	some f in sort(object.keys(_wrong_type_problems))
	f in object.keys(req)
	not _has_type(f, req[f])
]

_has_type("applies_to", v) if is_object(v)

_has_type("checks", v) if is_object(v)

_has_type("from", v) if is_array(v)

_has_type("id", v) if is_array(v)

_has_type("min_subjects", v) if {
	is_number(v)
	v >= 0
	v == floor(v)
}

_has_type("subject_type", v) if {
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

_bad_applies_to(req) if {
	is_object(req)
	"applies_to" in _wrong_typed_fields(req)
}

_typed(req) if {
	is_object(req)
	_wrong_typed_fields(req) == []
}

_unknown_req_fields(req) := sort([f |
	some f in object.keys(req)
	not f in (object.keys(_wrong_type_problems) | {"require"})
]) if is_object(req)

_unknown_req_fields(req) := [] if not is_object(req)

_not_an_object_inputs(req) := [{"name": "requirement", "value": req}] if not is_object(req)

_not_an_object_inputs(req) := [] if is_object(req)

_wrong_type_problems := {
	"applies_to": "not an object",
	"checks": "not an object",
	"from": "not a list",
	"id": "not a list",
	"min_subjects": "not a whole number of 0 or more",
	"subject_type": "empty or not a string",
	"description": "not a string",
	"meta": "not an object",
}

_req_problems(req) := union({_req_meta_problems(req), _type_problems(req), _range_problems(req), _unknown_problems(req), _checks_problems(req), _require_problems(req), _path_problems(req, "from"), _path_problems(req, "id"), _naming_step_problems(req), _where_problems(req), _req_json_problems(req)})

_req_json_problems(req) := {[f, p] |
	some f in ["from", "id"]
	v := _req_field(req, f, null)
	is_array(v)
	some p in _json_problems(v)
} | {[f, "holds a key that isn't a string"] |
	some f in ["checks", "applies_to"]
	v := _req_field(req, f, null)
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

_naming_step_problems(req) := {["from", m] |
	is_array(_from_of(req))
	some i, seg in _from_of(req)
	is_object(seg)
	not _is_ref(seg)
	some m in _object_step_problems(seg, i == (count(_from_of(req)) - 1))
}

_object_step_problems(_, false) := {"object step before the last"}

_object_step_problems(step, true) := {"object step without each_as"} if not "each_as" in object.keys(step)

_object_step_problems(step, true) := ({concat("", ["unknown field ", _text(k), " in naming step"]) |
	some k in object.keys(step)
	not k in {"each_as", "keys"}
} | {"invalid name" | not _valid_name(step.each_as)}) | {"invalid keys" | not _keys_well_formed(step)} if "each_as" in object.keys(step)

_where_problems(req) := {["id", concat("", [kind, " inside where"])] | some kind in _wrapped_in_where(_id_of(req))}

_field_problem_inputs(req) := [{"name": _field_name(f), "value": sort({p[1] | some p in problems; p[0] == f})} | some f in sort({p[0] | some p in problems})] if {
	problems := _req_problems(req)
}

_field_name(f) := _path_name([f]) if is_string(f)

_field_name(f) := concat("", ["<invalid key ", _literal_text(f), ">"]) if not is_string(f)

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

_raw_entries(doc, req) := [{"subject": subj} | some subj in coll] if {
	_from_well_formed(req)
	not "keys" in object.keys(_each_step(req))
	coll := _target(doc, req)
	is_array(coll)
}

_raw_entries(doc, req) := [{"key": k, "subject": coll[k]} | some k in sort(object.keys(coll))] if {
	_from_well_formed(req)
	not "keys" in object.keys(_each_step(req))
	coll := _target(doc, req)
	is_object(coll)
}

_raw_entries(doc, req) := [] if {
	_from_well_formed(req)
	not "keys" in object.keys(_each_step(req))
	not is_array(_target(doc, req))
	not is_object(_target(doc, req))
}

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

_raw_subjects(doc, req) := [entry.subject | some entry in _raw_entries(doc, req)]

_matching_entries(doc, req) := [entry |
	some entry in _raw_entries(doc, req)
	_subject_matches(entry.subject, req)
]

_matching_subjects(doc, req) := [entry.subject | some entry in _matching_entries(doc, req)]

_scope_of(req, subj) := {"ergo/names": {_each_step(req).each_as: subj}} if _from_well_formed(req)

_passes(req, check, subj) := _check_passed(check, subj, _flaw(check, _from_names(req))) if not _has_step(req)

_passes(req, check, subj) := v if {
	_has_step(req)
	flaw := _flaw(check, _from_names(req))
	s := _scope_of(req, subj)
	v := _check_passed(check, subj, flaw) with input as s
}

_cause_in(req, check, subj) := _row_cause(check, subj, _flaw(check, _from_names(req))) if not _has_step(req)

_cause_in(req, check, subj) := c if {
	_has_step(req)
	flaw := _flaw(check, _from_names(req))
	s := _scope_of(req, subj)
	c := _row_cause(check, subj, flaw) with input as s
}

_inputs_in(req, check, subj) := _row_inputs(subj, check, _subject_item_name(req)) if not _has_step(req)

_inputs_in(req, check, subj) := i if {
	_has_step(req)
	s := _scope_of(req, subj)
	i := _row_inputs(subj, check, _subject_item_name(req)) with input as s
}

_failed_items_field(req, check, subj) := {"failed_items": _failed_items_in(req, check, subj)} if _quantified(check)

_failed_items_field(_, check, _) := {} if not _quantified(check)

_failed_items_in(req, check, subj) := _failed_items(subj, check, _flaw(check, _from_names(req)), _subject_item_name(req)) if not _has_step(req)

_failed_items_in(req, check, subj) := f if {
	_has_step(req)
	s := _scope_of(req, subj)
	f := _failed_items(subj, check, _flaw(check, _from_names(req)), _subject_item_name(req)) with input as s
}

_failed_items(subj, check, flaw, item) := [{"path": e[0], "cause": flaw, "value": e[1]} |
	some e in _item_entries(subj, check, item)
] if flaw != ""

_failed_items(subj, check, "", item) := [] if {
	_list_passed(check, subj)
} else := [f |
	some e in _item_entries(subj, check, item)
	some f in _entry_failure(subj, check, e)
]

_entry_failure(subj, check, [p, v]) := [{"path": p, "cause": c, "value": v} |
	c := _failed_item_cause(subj, check, v)
	c != "satisfied"
]

_entry_failure(_, _, [p, v, c]) := [{"path": p, "cause": c, "value": v}]

_failed_item_cause(subj, check, v) := "satisfied" if {
	_item_passed(check, v)
} else := _worst_read(subj, check) if {
	_unreadable_ref(check)
} else := _item_cause(check, v)

default _item_entries(_, _, _) := []

_item_entries(subj, check, item) := [[concat("", [_item_path_name(item, check.path), "[", _text(i), "]"]), v] |
	some i, v in coll
] if {
	not check.each
	coll := _field(subj, check.path)
	is_array(coll)
}

_item_entries(subj, check, item) := [e |
	some i, outer in coll
	some e in _outer_entries(outer, check, concat("", [_item_path_name(item, check.path), "[", _text(i), "]", _each_suffix(check.each)]))
] if {
	check.each
	coll := _field(subj, check.path)
	is_array(coll)
}

_outer_entries(outer, check, name) := [[concat("", [name, "[", _text(j), "]"]), v] | some j, v in inner] if {
	inner := _field(outer, check.each)
	is_array(inner)
	count(inner) > 0
}

_outer_entries(outer, check, name) := [[name, [], "value"]] if _field(outer, check.each) == []

_outer_entries(outer, check, name) := [[name, value_at(outer, check.each), _each_state(outer, check.each)]] if not _is_list_at(outer, check.each)

_each_suffix([]) := ""

_each_suffix(each) := concat("", [".", _path_name(each)]) if each != []

_is_list_at(x, path) if is_array(_field(x, path))

default _subject_matches(_, _) := false

_subject_matches(subj, req) if {
	not _bad_applies_to(req)
	every _, check in _applies_to_of(req) {
		_passes(req, check, subj)
	}
}

_entry_ref(entry, req) := {"type": _subject_type_of(req), "id": entry.key} if "key" in object.keys(entry)

_entry_ref(entry, req) := _subject_ref(entry.subject, req) if {
	not "key" in object.keys(entry)
	not _has_step(req)
}

_entry_ref(entry, req) := r if {
	not "key" in object.keys(entry)
	_has_step(req)
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

_absent := {"ergo/absent": true}

default value_at(_, _) := null

value_at(subj, path) := v if {
	v := _resolved(subj, path)
	v != _absent
}

_field(subj, path) := v if {
	v := _resolved(subj, path)
	v != _absent
}

_resolved(subj, path) := _read_from(_start_of(subj, path), _keys_of(path))

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

_keys_of(path) := [path] if is_string(path)

_keys_of(path) := [path] if is_number(path)

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

_ref_name(path) := concat(".", [_ref_segment_name(i, seg) | some i, seg in path]) if _builtin(path)

_ref_segment_name(0, seg) := seg

_ref_segment_name(i, seg) := _key_name(_unliteral(seg)) if i > 0

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

_path_name(path) := concat(".", [_segment_name(i, path[i]) | some i in _names(path)])

_item_path_name(item, []) := item

_item_path_name(_, path) := _path_name(path) if path != []

_projection_name(path, []) := concat("", [_path_name(path), "[]"])

_projection_name(path, each) := concat("", [_path_name(path), "[].", _path_name(each)]) if each != []

_segment_name(_, p) := _key_name(p) if not is_object(p)

_segment_name(i, p) := _json_text(p.literal) if {
	_is_literal(p)
	_first_dollar_key(i, p.literal)
}

_segment_name(i, p) := _key_name(p.literal) if {
	_is_literal(p)
	not _first_dollar_key(i, p.literal)
}

_segment_name(_, p) := concat("", ["[", concat(" and ", sort([concat("", [_key_name(k), "==", _value_text(v)]) | some k, v in p.where])), "]"]) if {
	is_object(p)
	not _is_literal(p)
	not _is_ref(p)
	not _malformed(p)
}

_segment_name(_, p) := concat("", ["[", _ref_name(p.ref), "]"]) if _is_ref(p)

_segment_name(_, p) := "[<invalid ref>]" if _malformed(p)

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

_sorted_json(v) := concat("", [_node_json(paths, index, i) | some i, _ in paths]) if {
	index := {p: x | walk(v, [p, x])}
	paths := [pair[1] | some pair in sort([[_written_path(index, p), p] | some p, _ in index])]
}

_written_path(index, p) := [_written_step(index, p, i) | some i, _ in p]

_written_step(index, p, i) := _key_text(p[i]) if is_object(index[array.slice(p, 0, i)])

_written_step(index, p, i) := p[i] if not is_object(index[array.slice(p, 0, i)])

_key_text(k) := k if is_string(k)

_key_text(k) := json.marshal(k) if not is_string(k)

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

leaf_passed(check, subj) if {
	check.op == "range"
	v := value_at(subj, check.path)
	is_number(v)
	lo := arg(check.min)
	hi := arg(check.max)
	is_number(lo)
	is_number(hi)
	v >= lo
	v <= hi
}

leaf_passed(check, subj) if {
	check.op == "excludes"
	v := value_at(subj, check.path)
	is_array(v)
	want := arg(check.value)
	not want in v
}

leaf_passed(check, subj) if {
	check.op == "includes"
	v := value_at(subj, check.path)
	is_array(v)
	want := arg(check.value)
	want in v
}

leaf_passed(check, subj) if {
	check.op == "excludes"
	v := value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	every want in wants {
		not want in v
	}
}

leaf_passed(check, subj) if {
	check.op == "includes"
	v := value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	every want in wants {
		want in v
	}
}

leaf_passed(check, subj) if {
	check.op == "in"
	v := value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	some want in vals
	want == v
}

leaf_passed(check, subj) if {
	check.op == "equals"
	_field(subj, check.path) == arg(check.value)
}

leaf_passed(check, subj) if {
	check.op == "present"
	value_at(subj, check.path) != null
}

leaf_passed(check, subj) if {
	check.op == "non_empty_string"
	v := value_at(subj, check.path)
	is_string(v)
	v != ""
}

leaf_passed(check, subj) if {
	check.op == "missing"
	_missing_at(subj, check.path)
}

leaf_passed(check, subj) if {
	check.op == "empty"
	value_at(subj, check.path) == []
}

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

leaf_passed(check, subj) if {
	check.op == "matches_any"
	v := value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, v)
}

leaf_passed(check, subj) if {
	check.op == "not_matches_any"
	v := value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	every pattern in patterns {
		is_string(pattern)
		not regex.match(pattern, v)
	}
}

leaf_passed(check, subj) if {
	check.op == "compare"
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	_comparable(l, r)
	_orderable(check.cmp, l)
	_cmp(check.cmp, l, r)
}

leaf_passed(check, subj) if {
	check.op == "compare_time"
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
	_cmp(check.cmp, time.parse_rfc3339_ns(l), time.parse_rfc3339_ns(r))
}

leaf_passed(check, subj) if {
	check.op == "compare_time"
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

_orderable(_, v) if is_number(v)

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
	leaf.op == "compare"
	l := _found(x, leaf.left)
	r := _found(x, leaf.right)
	not _usable_pair(leaf.cmp, l, r)
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

_children(node, names) := array.concat(_inner_child(node, names), _option_children(node, names))

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

_node_problems(node, kinds, names) := ((_op_problems(node, kinds) | _field_problems(node)) | _step_problems(node)) | _name_problems(node, names) if is_object(node)

default _op_problems(_, _) := set()

_op_problems(node, _) := {"missing op"} if not "op" in object.keys(node)

_op_problems(node, _) := {concat("", ["unknown op ", _text(node.op)])} if {
	"op" in object.keys(node)
	not node.op in operators
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
}

_field_problems(node) := union({_wording_problem(node), _unknown_fields_problem(node), _missing_fields_problem(node), _range_bounds_problem(node), _range_order_problem(node), _values_problem(node), _value_or_values_problem(node), _patterns_problem(node), _nested_wrapper_problem(node), _cmp_problem(node), _misplaced_fields_problem(node), _each_problem(node), _options_problem(node), _empty_options_problem(node), _empty_option_problem(node), _out_of_range_problem(node), _refs_problem(node), _json_problem(node)})

_json_problem(node) := _json_problems(object.remove(_own_fields(node), ["meta"]))

_missing_fields_problem(node) := {concat("", ["missing ", f]) |
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
	node.op in {"in", "includes", "excludes"}
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
}

_misplaced_fields_problem(node) := {concat("", [f, " can't go here"]) |
	node.op in (_leaf_ops | {"any_of"})
	some f in ["as", "each"]
	f in object.keys(node)
}

_each_problem(node) := {"invalid each" |
	_quantified(node)
	"each" in object.keys(node)
	not _path_shaped(node.each)
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
	not _filled_list(group)
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

_step_problems(node) := {concat("", ["step that can't be a key in ", f]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some p in _own_paths(node, f)
	_badly_stepped(p)
}

_own_paths(node, f) := [node[f]] if {
	f != "inputs"
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
	node.op == "in"
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

_path_shaped(p) if is_array(p)

_path_shaped(p) if is_string(p)

_option_list(options) if is_object(options)

_option_list(options) if is_array(options)

_filled_list(group) if {
	is_array(group)
	count(group) > 0
}

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

_read_paths(check) := [_input_spec_path(spec) | some spec in check.inputs] if check.inputs

_read_paths(check) := [check.left, check.right] if {
	not check.inputs
	_two_sided(check)
}

_list_reads(check) := array.concat(array.concat([check.path], _named_each(check)), _element_name_reads(check))

_named_each(check) := [check.each] if _named(object.get(check, "each", []))

_named_each(check) := [] if not _named(object.get(check, "each", []))

_read_paths(check) := [check.path] if {
	not check.inputs
	not _two_sided(check)
	not _quantified(check)
	not _combinator(check)
	check.path
}

_input_spec_path(spec) := spec if is_array(spec)

_input_spec_path(spec) := object.get(spec, "path", []) if is_object(spec)

default _read_state(_, _) := "absent"

_read_state(subj, path) := "not_an_object" if {
	start := _start_of(subj, path)
	not is_object(start)
	not _reads_itself(path)
}

_reads_itself(path) if _keys_of(path) == []

_read_state(subj, path) := "ambiguous" if count(_selector_candidates(subj, path)) > 1

_read_state(subj, path) := "unmatched" if count(_selector_candidates(subj, path)) == 0

_read_state(subj, path) := "null" if _resolved(subj, path) == null

_read_state(subj, path) := "unusable" if {
	start := _start_of(subj, path)
	is_object(start)
	_blocked(start, _keys_of(path))
}

_read_state(subj, path) := "value" if {
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

_worst_read(subj, check) := _worst_or_value(_check_states(check, subj) | _substitute_unusable(check, subj)) if not _unreadable_ref(check)

_worst_or_value(states) := c if {
	c := _worst_of(states)
} else := "value"

_substitute_unusable(check, subj) := {"unusable" |
	some leaf in _element_leaves(_substitute_of(check))
	_unusable(leaf, subj)
}

default _has_inputs(_) := false

_has_inputs(check) if check.inputs

_check_states(check, subj) := {_read_state(subj, p) | some p in _read_paths(check)} if _has_inputs(check)

_check_states(check, subj) := _answered(check, subj, {_read_state(subj, p) | some p in _read_paths(check)}) | _unusable_states(check, subj) if {
	not _has_inputs(check)
	not _quantified(check)
	not _combinator(check)
}

_check_states(check, subj) := {_list_cause(check, subj)} if {
	not _has_inputs(check)
	_quantified(check)
}

_check_states(check, subj) := {_option_cause(group, subj) | some group in check.options} if {
	not _has_inputs(check)
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
} else := _worst_or_value({_read_state(x, p) | some p in _leaf_paths(leaf)} | _unusable_states(leaf, x))

_answered(check, x, states) := {_presence_state(s) | some s in states} if _asks_presence(check, x)

_answered(check, x, states) := states if not _asks_presence(check, x)

default _asks_presence(_, _) := false

_asks_presence(check, x) if {
	check.op == "present"
	_keys_of(check.path)
	_ := _start_of(x, check.path)
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

_row_cause(check, subj, "") := _readable_cause(check, subj)

_readable_cause(check, subj) := "satisfied" if op_passed(check, subj)

_readable_cause(check, subj) := "substituted" if {
	not op_passed(check, subj)
	op_passed(_substitute_of(check), subj)
}

_readable_cause(check, subj) := _worst_read(subj, check) if not _passed_or_substituted(check, subj)

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

_applies_cause(subj, req) := "satisfied" if {
	_subject_matches(subj, req)
} else := _scope_cause(_failed_filter_causes(subj, req))

_scope_cause(causes) := "ill_formed" if {
	"ill_formed" in causes
} else := "value" if {
	"missing" in causes
} else := "value" if {
	causes == {"value"}
} else := _worst_of(causes)

_failed_filter_causes(subj, req) := _filter_causes(subj, req, _filter_flaws(req)) if not _has_step(req)

_failed_filter_causes(subj, req) := causes if {
	_has_step(req)
	flaws := _filter_flaws(req)
	s := _scope_of(req, subj)
	causes := _filter_causes(subj, req, flaws) with input as s
}

_filter_flaws(req) := {name: _flaw(check, _from_names(req)) | some name, check in _applies_to_of(req)}

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
	_substitute_unusable(check, subj) == set()
	_read_state(subj, check.path) in {"absent", "null"}
}

_ruled_out(subj, req) if _scope_cause(_failed_filter_causes(subj, req)) == "value"

_scope_unreadable(subj, req) if {
	not _subject_matches(subj, req)
	not _ruled_out(subj, req)
}

_scope_readable(doc, req) if {
	not _from_unreadable(req)
	not _target_cause(doc, req)
	every subj in _raw_subjects(doc, req) {
		not _scope_unreadable(subj, req)
	}
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

_path_text(item, check, f) := _item_path_name(item, check[f]) if f in object.keys(check)

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

_leaf_describe(check, item) := concat("", [_path_text(item, check, "left"), " ", _cmp_text(check), " ", _path_text(item, check, "right")]) if check.op in {"compare", "compare_time"}

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

_expression_of(check, item) := concat("", ["one of: ", concat(" | ", sort([concat("", [_text(nm), "(", concat(" and ", [_top_option_describe(group[k], item) | some k in _names(group)]), ")"]) | some nm, group in check.options]))]) if {
	not _written_expression(check)
	check.op == "any_of"
	"options" in object.keys(check)
}

_top_option_describe(leaf, item) := _nested_describe(leaf, item) if not _quantified(leaf)

_top_option_describe(leaf, item) := _list_describe(leaf, _item_given(item)) if _quantified(leaf)

_collection_name(check) := "<missing path>" if not "path" in object.keys(check)

_collection_name(check) := _path_name(check.path) if not check.each

_collection_name(check) := _projection_name(check.path, check.each) if check.each

_item_name(check) := concat("", [_collection_name(check), "[]"]) if not _valid_name(object.get(check, "as", null))

_item_name(check) := concat("", ["$", check.as]) if _valid_name(object.get(check, "as", null))

_inner_collection_name(check, _) := "<missing path>" if not "path" in object.keys(check)

_inner_collection_name(check, item) := _item_path_name(item, check.path) if not check.each

_inner_collection_name(check, item) := concat("", [_item_path_name(item, check.path), "[].", _path_name(check.each)]) if check.each

_inner_item_name(check, item) := concat("", [_inner_collection_name(check, item), "[]"]) if not _valid_name(object.get(check, "as", null))

_inner_item_name(check, _) := concat("", ["$", check.as]) if _valid_name(object.get(check, "as", null))

_element_describe(check, item, _) := _nested_describe(check, item) if {
	not _combinator(check)
	not _quantified(check)
}

_element_describe(check, item, given) := concat("", ["one of: ", concat(" | ", sort([concat("", [_text(nm), "(", concat(" and ", [_element_option_describe(group[k], item, given) | some k in _names(group)]), ")"]) | some nm, group in check.options]))]) if _combinator(check)

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

_any_of_describe(check, item) := concat("", ["one of: ", concat(" | ", sort([_variant_describe(nm, group, item) | some nm, group in check.options]))])

_variant_describe(nm, group, item) := concat("", [_text(nm), "(", concat(" and ", [_inner_option_describe(group[k], item) | some k in _names(group)]), ")"])

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
	_two_sided(check)
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
	check.path
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

_leaf_paths(leaf) := [leaf.left, leaf.right] if _two_sided(leaf)

_leaf_paths(leaf) := [leaf.path] if {
	not _two_sided(leaf)
	leaf.path
}

_row_inputs(subj, check, item) := _check_inputs(subj, check, item) if not check.substitute

_row_inputs(subj, check, item) := array.concat(
	_check_inputs(subj, check, item),
	_check_inputs(subj, check.substitute, item),
) if check.substitute

_check_def(check, item) := _with_refs(object.union(object.remove(_described(check, item), {"description", "meta"}), {"description": _reported_description(check), "meta": _reported_meta(check)}), check)

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

_subject_item_name(req) := concat("", [_from_name(_from_of(req)), "[]"]) if {
	not _stepped(req)
	_from_well_formed(req)
	_from_of(req) != []
}

_subject_item_name(req) := "$$input" if {
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

_from_text(req) := "$$input" if {
	_from_well_formed(req)
	_from_path(req) == []
}

_from_text(req) := "<invalid from>" if not _from_well_formed(req)

_from_name(p) := _path_name(array.concat([{"literal": p[0]}], array.slice(p, 1, count(p)))) if _starts_with_dollar_key(p)

_from_name(p) := _path_name(p) if not _starts_with_dollar_key(p)

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

_well_formed_def(req) := {"$well_formed": {
	"description": "The requirement is written correctly",
	"expression": `fields are known and have the right types and count(checks) >= 1 and require in ["every", "some"] and steps are keys and numbers fit a float and checks are written right`,
}} if not _stepped(req)

_well_formed_def(req) := {"$well_formed": {
	"description": "The requirement is written correctly",
	"expression": `fields are known and have the right types and count(checks) >= 1 and require in ["every", "some"] and from is well formed and steps are keys and numbers fit a float and checks are written right`,
}} if _stepped(req)

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
}

_check_problem_inputs(req) := [{"name": name, "value": sort({p[1] | some p in problems; p[0] == name})} | some name in sort({p[0] | some p in problems})] if {
	problems := {[_path_name(array.concat([f, n], p[0])), p[1]] |
		some f in ["applies_to", "checks"]
		some n, check in _req_checks(req, f)
		some p in _check_problems(check, _from_names(req))
	}
}

_req_checks(req, "applies_to") := _applies_to_of(req)

_req_checks(req, "checks") := _checks_of(req)

_from_names(req) := {n |
	_from_well_formed(req)
	n := _each_step(req).each_as
}

_well_formed_inputs(req) := array.concat(
	array.concat(
		[{"name": "count(checks)", "value": count(_checks_of(req))}],
		array.concat(_echo(req, "require", _require_of(req)), _from_echo(req)),
	),
	array.concat(array.concat(_not_an_object_inputs(req), _field_problem_inputs(req)), _check_problem_inputs(req)),
)

_echo(req, f, v) := [{"name": f, "value": v}] if not _has_problems(req, f)

_echo(req, f, _) := [] if _has_problems(req, f)

_from_echo(req) := _echo(req, "from", _from_of(req)) if _stepped(req)

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
		{name: _check_def(check, _subject_item_name(req)) | some name, check in _checks_of(req)},
		object.union(_min_subjects_def(req), _unique_ids_def(req)),
	),
	object.union(_applies_def(req), _well_formed_def(req)),
)

_subject_passed(req, subj) if {
	every _, check in _checks_of(req) {
		_passes(req, check, subj)
	}
}

_subject_rows(doc, req, req_name) := [row |
	some entry in _matching_entries(doc, req)
	some check_name in _names(_checks_of(req))
	check := _checks_of(req)[check_name]
	base := {
		"requirement": req_name,
		"subject": _entry_ref(entry, req),
		"check": check_name,
		"inputs": _inputs_in(req, check, entry.subject),
		"passed": _passes(req, check, entry.subject),
		"cause": _cause_in(req, check, entry.subject),
	}
	row := object.union(base, _failed_items_field(req, check, entry.subject))
]

_well_formed_row(req, req_name) := row if {
	passed := _well_formed_named(req, req_name)
	row := {
		"requirement": req_name,
		"subject": {"type": _subject_type_of(req), "id": null},
		"check": "$well_formed",
		"inputs": array.concat(_name_problem_inputs(req_name), _well_formed_inputs(req)),
		"passed": passed,
		"cause": _verdict_cause(passed),
	}
}

_min_subjects_row(doc, req, req_name) := {
	"requirement": req_name,
	"subject": {"type": _subject_type_of(req), "id": null},
	"check": "$min_subjects",
	"inputs": array.concat([{"name": _subject_count_name(req), "value": count(_matching_subjects(doc, req))}], data.ergo_unreadable),
	"passed": _enough_subjects(doc, req),
	"cause": _min_subjects_cause(doc, req),
}

default _enough_subjects(_, _) := false

_enough_subjects(doc, req) if {
	not _from_unreadable(req)
	not _target_cause(doc, req)
	is_number(_min_subjects_of(req))
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
}

_min_subjects_cause(doc, req) := _verdict_cause(_enough_subjects(doc, req)) if {
	not _from_unreadable(req)
	not _target_cause(doc, req)
}

_min_subjects_cause(doc, req) := _target_cause(doc, req)

_min_subjects_cause(_, req) := _from_cause(req) if {
	_from_well_formed(req)
	_from_unreadable(req)
}

_unique_ids_row(doc, req, req_name) := {
	"requirement": req_name,
	"subject": {"type": _subject_type_of(req), "id": null},
	"check": "$unique_ids",
	"inputs": [{"name": _repeated_ids_name(req), "value": _repeated_ids(doc, req)}],
	"passed": _ids_unique(doc, req),
	"cause": _verdict_cause(_ids_unique(doc, req)),
}

_repeated_ids(doc, req) := [pair[1] | some pair in sort({[_literal_text(id), id] | some id in _repeats(sort(_subject_ids(doc, req)))})]

_subject_ids(doc, req) := [_entry_ref(entry, req).id | some entry in _raw_entries(doc, req)]

_repeats(sorted) := {x |
	some i, x in sorted
	i > 0
	x == sorted[i - 1]
}

default _ids_unique(_, _) := false

_ids_unique(doc, req) if count(_repeated_ids(doc, req)) == 0

_applies_rows(doc, req, req_name) := [{
	"requirement": req_name,
	"subject": _entry_ref(entry, req),
	"check": "$applies",
	"inputs": _applies_inputs(entry.subject, req),
	"passed": _subject_matches(entry.subject, req),
	"cause": _applies_cause(entry.subject, req),
} |
	some entry in _raw_entries(doc, req)
] if {
	_size(_applies_to_of(req)) > 0
}

_applies_rows(doc, req, req_name) := [{
	"requirement": req_name,
	"subject": _entry_ref(entry, req),
	"check": "$applies",
	"inputs": [],
	"passed": false,
	"cause": "ill_formed",
} |
	some entry in _raw_entries(doc, req)
] if _bad_applies_to(req)

_applies_rows(_, req, _) := [] if {
	_size(_applies_to_of(req)) == 0
	not _bad_applies_to(req)
}

_applies_inputs(subj, req) := [inp |
	some name in _applies_to_names(req)
	some inp in _inputs_in(req, _applies_to_of(req)[name], subj)
]

_named_requirement_holds(doc, req, name) if {
	is_string(name)
	_requirement_holds(doc, req)
}

default _requirement_holds(_, _) := false

_requirement_holds(doc, req) if {
	_well_formed(req)
	_ids_unique(doc, req)
	_well_formed_requirement_holds(doc, req)
}

_well_formed_requirement_holds(doc, req) if {
	_require_of(req) == "every"
	_scope_readable(doc, req)
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
	every subj in _matching_subjects(doc, req) {
		_subject_passed(req, subj)
	}
}

_well_formed_requirement_holds(doc, req) if {
	_require_of(req) == "some"
	_scope_readable(doc, req)
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
	some subj in _matching_subjects(doc, req)
	_subject_passed(req, subj)
}

_well_formed_requirement_holds(doc, req) if {
	_require_of(req) == "some"
	_scope_readable(doc, req)
	_min_subjects_of(req) == 0
	count(_matching_subjects(doc, req)) == 0
}

_named_requirement_status(doc, req, name) := _requirement_status(doc, req) if is_string(name)

_named_requirement_status(_, _, name) := "not_met" if not is_string(name)

default _requirement_status(_, _) := "not_met"

_requirement_status(doc, req) := "met" if {
	_requirement_holds(doc, req)
	count(_matching_subjects(doc, req)) > 0
}

_requirement_status(doc, req) := "not_applicable" if {
	_requirement_holds(doc, req)
	count(_matching_subjects(doc, req)) == 0
}

default _policy_compliant(_, _) := false

_policy_compliant(doc, policy) if {
	_size(policy) > 0
	count([name |
		some name, req in policy
		not _named_requirement_holds(doc, req, name)
	]) == 0
}

_results(doc, policy) := array.concat(
	array.concat(
		[_well_formed_row(policy[name], name) | some name in _names(policy)],
		array.concat(
			[_min_subjects_row(doc, policy[name], name) | some name in _names(policy)],
			[_unique_ids_row(doc, policy[name], name) | some name in _names(policy)],
		),
	),
	array.concat(
		[row | some name in _names(policy); some row in _applies_rows(doc, policy[name], name)],
		[row | some name in _names(policy); some row in _subject_rows(doc, policy[name], name)],
	),
)

_names(x) := sort(object.keys(x)) if is_object(x)

_names(x) := [i | some i, _ in x] if is_array(x)

_names(x) := sort(x) if is_set(x)

report(doc, policy) := report_with_params(doc, _configured_params, policy)

_configured_params := data.params

default _configured_params := {}

report_with_params(doc, params, policy) := r if {
	unreadable := _unreadable_inputs(doc, params)
	r := _report_of(doc, policy) with data.ergo_document as doc with data.ergo_params as params with data.ergo_unreadable as unreadable with input as {"ergo/names": {}}
}

_unreadable_inputs(doc, params) := [{"name": name, "value": sort(_json_problems(v))} |
	some [name, v] in [["$$input", doc], ["$$params", params]]
	count(_json_problems(v)) > 0
]

_report_of(doc, policy) := {
	"compliant": _policy_compliant(doc, policy),
	"requirements": {name: {
		"description": _reported_description(req),
		"meta": _reported_meta(req),
		"require": _require_of(req),
		"status": _named_requirement_status(doc, req, name),
		"subjects": {"total": count(_raw_subjects(doc, req)), "matching": count(_matching_subjects(doc, req))},
		"checks": _requirement_check_defs(req),
	} |
		some name, req in policy
	},
	"results": _results(doc, policy),
}

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
	_failed_items_of(row),
) |
	some row in report.results
	_is_violation(report.requirements, row)
]

_failed_items_of(row) := {"failed_items": row.failed_items} if "failed_items" in object.keys(row)

_failed_items_of(row) := {} if not "failed_items" in object.keys(row)

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
