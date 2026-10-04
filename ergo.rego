# Copyright 2026 Kosli, Inc
# SPDX-License-Identifier: Apache-2.0

package ergo

import rego.v1

_checks_of(req) := object.get(req, "checks", {}) if is_object(req)

_applies_to_of(req) := object.get(req, "applies_to", {}) if is_object(req)

_from_of(req) := object.get(req, "from", []) if is_object(req)

_subject_type_of(req) := object.get(req, "subject_type", "subject") if is_object(req)

_min_subjects_of(req) := object.get(req, "min_subjects", 1) if is_object(req)

_require_of(req) := object.get(req, "require", "every") if is_object(req)

_size(x) := count(x) if type_name(x) in {"array", "object", "set", "string"}

_from_path(req) := array.slice(_from_of(req), 0, count(_from_of(req)) - 1) if _each_step(req)

_from_path(req) := _from_of(req) if not _each_step(req)

_each_step(req) := step if {
	f := _from_of(req)
	is_array(f)
	count(f) > 0
	step := f[count(f) - 1]
	is_object(step)
	not _is_ref(step)
}

_stepped(req) if {
	f := _from_of(req)
	is_array(f)
	some seg in f
	is_object(seg)
	not _is_ref(seg)
}

default _from_well_formed(_) := false

_from_well_formed(req) if not _stepped(req)

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

_from_keys(req) := ks if {
	p := _from_path(req)
	is_array(p)
	ks := [_step_key(seg) | some seg in p]
	count(ks) == count(p)
}

_from_keys(req) := _from_path(req) if not is_array(_from_path(req))

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

_from_cause(req) := "absent" if _from_ref_states(req) - {"value"} == set()

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

_raw_entries(doc, req) := [{"subject": subj} | some subj in _listed_subjects(doc, req)] if not _stepped(req)

_raw_entries(_, req) := [] if {
	_stepped(req)
	not _from_well_formed(req)
}

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

_passes(req, check, subj) := _check_passed(check, subj) if not _each_step(req)

_passes(req, check, subj) := v if {
	_each_step(req)
	s := _scope_of(req, subj)
	v := _check_passed(check, subj) with input as s
}

_cause_in(req, check, subj) := _row_cause(check, subj) if not _each_step(req)

_cause_in(req, check, subj) := c if {
	_each_step(req)
	s := _scope_of(req, subj)
	c := _row_cause(check, subj) with input as s
}

_inputs_in(req, check, subj) := _row_inputs(subj, check, _subject_item_name(req)) if not _each_step(req)

_inputs_in(req, check, subj) := i if {
	_each_step(req)
	s := _scope_of(req, subj)
	i := _row_inputs(subj, check, _subject_item_name(req)) with input as s
}

default _subject_matches(_, _) := false

_subject_matches(subj, req) if {
	every _, check in _applies_to_of(req) {
		_passes(req, check, subj)
	}
}

_entry_ref(entry, req) := {"type": _subject_type_of(req), "id": entry.key} if "key" in object.keys(entry)

_entry_ref(entry, req) := _subject_ref(entry.subject, req) if {
	not "key" in object.keys(entry)
	not _each_step(req)
}

_entry_ref(entry, req) := r if {
	not "key" in object.keys(entry)
	_each_step(req)
	s := _scope_of(req, entry.subject)
	r := _subject_ref(entry.subject, req) with input as s
}

_subject_ref(subj, req) := {
	"type": _subject_type_of(req),
	"id": _subject_id(subj, req),
}

_subject_id(subj, req) := value_at(subj, object.get(req, "id", [])) if is_object(subj)

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

_read_from(start, keys) := object.get(start, keys, _absent) if {
	is_object(start)
	not _selector_index(keys)
}

_read_from(start, []) := start

_read_from(start, keys) := v if {
	is_object(start)
	i := _selector_index(keys)
	base := object.get(start, array.slice(keys, 0, i), _absent)
	base != _absent
	elem := _selected(base, keys[i])
	v := object.get(elem, array.slice(keys, i + 1, count(keys)), _absent)
}

_named(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "$")
}

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

_is_ref(x) if {
	is_object(x)
	object.keys(x) == {"ref"}
}

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

_projection_name(path, []) := sprintf("%s[]", [_path_name(path)])

_projection_name(path, each) := sprintf("%s[].%s", [_path_name(path), _path_name(each)]) if each != []

_segment_name(_, p) := _key_name(p) if not is_object(p)

_segment_name(i, p) := _json_text(p.literal) if {
	_is_literal(p)
	_first_dollar_key(i, p.literal)
}

_segment_name(i, p) := _key_name(p.literal) if {
	_is_literal(p)
	not _first_dollar_key(i, p.literal)
}

_segment_name(_, p) := sprintf("[%s]", [concat(" and ", sort([sprintf("%s==%s", [_key_name(k), _value_text(v)]) | some k, v in p.where]))]) if {
	is_object(p)
	not _is_literal(p)
	not _is_ref(p)
	not _malformed(p)
}

_segment_name(_, p) := sprintf("[%s]", [_ref_name(p.ref)]) if _is_ref(p)

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
	check.op == "in"
	v := value_at(subj, check.path)
	v != null
	vals := arg(check.values)
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
	check.op == "matches_any"
	v := value_at(subj, check.path)
	is_string(v)
	patterns := arg(check.patterns)
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, v)
}

leaf_passed(check, subj) if {
	check.op == "not_matches_any"
	v := value_at(subj, check.path)
	is_string(v)
	patterns := arg(check.patterns)
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

_value_list(v) if is_array(v)

_value_list(v) if is_set(v)

_comparable(l, r) if {
	l != null
	type_name(l) == type_name(r)
}

_orderable(c, _) if c in {"eq", "ne"}

_orderable(_, v) if is_number(v)

_orderable(_, v) if is_string(v)

_unordered(subj, leaf) if {
	leaf.op == "compare"
	l := value_at(subj, leaf.left)
	r := value_at(subj, leaf.right)
	_comparable(l, r)
	not _orderable(leaf.cmp, l)
}

_unordered_reads(subj, check) := {"absent" |
	some c in [check, object.get(check, "substitute", {})]
	some leaf in _element_leaves(c)
	_unordered(subj, leaf)
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

_leaf_ops := {"range", "excludes", "includes", "in", "equals", "present", "non_empty_string", "matches_any", "not_matches_any", "compare", "compare_time"}

operators contains op if some op in (_leaf_ops | {"all", "any", "any_of"})

_required_fields := {
	"range": {"path", "min", "max"},
	"excludes": {"path", "value"},
	"includes": {"path", "value"},
	"in": {"path", "values"},
	"equals": {"path", "value"},
	"present": {"path"},
	"non_empty_string": {"path"},
	"matches_any": {"path", "patterns"},
	"not_matches_any": {"path", "patterns"},
	"compare": {"left", "right", "cmp"},
	"compare_time": {"left", "right", "cmp"},
	"all": {"path", "check"},
	"any": {"path", "check"},
	"any_of": {"options"},
}

_broken_row(check) if _broken_check(check)

_broken_row(check) if {
	is_object(check)
	"substitute" in object.keys(check)
	_broken_check(check.substitute)
}

_broken_check(check) if _broken_list_check(check)

_broken_check(check) if {
	some node in _check_nodes(check)
	_node_broken(node[0], node[1])
}

_check_nodes(check) := nodes if {
	l0 := [[check, []]]
	l1 := _descend(l0)
	l2 := _descend(l1)
	l3 := _descend(l2)
	l4 := _descend(l3)
	l5 := _descend(l4)
	nodes := array.concat(array.concat(array.concat(l0, l1), array.concat(l2, l3)), array.concat(l4, l5))
}

_descend(level) := [[child[0], array.concat(node[1], [child[1]])] |
	some node in level
	some child in _children(node[0])
]

_children(node) := array.concat(_inner_child(node), _option_children(node))

default _inner_child(_) := []

_inner_child(node) := [[node.check, "check"]] if _quantified(node)

default _option_children(_) := []

_option_children(node) := [[leaf, "option"] | some group in node.options; is_array(group); some leaf in group] if {
	_combinator(node)
	_option_list(node.options)
}

_node_broken(node, _) if not is_object(node)

_node_broken(node, kinds) if {
	is_object(node)
	not object.get(node, "op", null) in _allowed_ops(kinds)
}

_node_broken(node, _) if _fields_broken(node)

_allowed_ops(kinds) := operators if kinds == []

_allowed_ops(kinds) := object.get(_nested_ops, [kinds[count(kinds) - 1], count([k | some k in kinds; k == "check"])], set()) if kinds != []

_nested_ops := {
	"option": [_leaf_ops | {"all", "any"}, _leaf_ops | {"all", "any"}, _leaf_ops],
	"check": [set(), _leaf_ops | {"all", "any", "any_of"}, _leaf_ops | {"any_of"}],
}

_fields_broken(node) if {
	some f in object.get(_required_fields, node.op, set())
	not f in object.keys(node)
}

_fields_broken(node) if _out_of_range(node)

_fields_broken(node) if {
	some f in {"path", "left", "right", "each"}
	f in object.keys(node)
	_badly_stepped(node[f])
}

_fields_broken(node) if {
	is_array(node.inputs)
	some spec in node.inputs
	_badly_stepped(_input_paths(spec)[_])
}

_input_paths(spec) := [spec] if not is_object(spec)

_input_paths(spec) := [object.get(spec, f, []) | some f in ["path", "each"]] if is_object(spec)

_fields_broken(node) if {
	node.op == "range"
	some f in ["min", "max"]
	v := arg(node[f])
	not is_number(v)
}

_fields_broken(node) if {
	node.op == "range"
	lo := arg(node.min)
	hi := arg(node.max)
	is_number(lo)
	is_number(hi)
	lo > hi
}

_fields_broken(node) if {
	node.op in (_leaf_ops | {"any_of"})
	some f in {"as", "each"}
	f in object.keys(node)
}

_fields_broken(node) if {
	node.op == "in"
	v := arg(node.values)
	not _value_list(v)
}

_fields_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	v := arg(node.patterns)
	not _value_list(v)
}

_fields_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	v := arg(node.patterns)
	_value_list(v)
	some p in v
	not _valid_pattern(p)
}

_fields_broken(node) if {
	_two_sided(node)
	not node.cmp in {"eq", "ne", "gt", "gte", "lt", "lte"}
}

_fields_broken(node) if {
	_combinator(node)
	not _option_list(node.options)
}

_fields_broken(node) if {
	_combinator(node)
	count(node.options) == 0
}

_fields_broken(node) if {
	_combinator(node)
	_option_list(node.options)
	some group in node.options
	not _filled_list(group)
}

_fields_broken(node) if {
	_quantified(node)
	"each" in object.keys(node)
	not _path_shaped(node.each)
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

_quantified(check) if check.op in {"all", "any"}

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

default _check_passed(_, _) := false

_check_passed(check, subj) if {
	not _broken_row(check)
	op_passed(check, subj)
}

_check_passed(check, subj) if {
	not _broken_row(check)
	op_passed(_substitute_of(check), subj)
}

_substitute_of(check) := object.get(check, "substitute", {})

default _read_paths(_) := []

_read_paths(check) := [_input_spec_path(spec) | some spec in check.inputs] if check.inputs

_read_paths(check) := [check.left, check.right] if {
	not check.inputs
	_two_sided(check)
}

_read_paths(check) := _list_reads(check) if {
	not check.inputs
	_quantified(check)
}

_list_reads(check) := array.concat(array.concat([check.path], _named_each(check)), _element_name_reads(check))

_named_each(check) := [check.each] if _named(object.get(check, "each", []))

_named_each(check) := [] if not _named(object.get(check, "each", []))

_read_paths(check) := [p |
	some group in check.options
	some leaf in group
	some p in _check_reads(leaf)
] if {
	not check.inputs
	_combinator(check)
}

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

_cause_precedence := ["not_an_object", "ambiguous", "unmatched", "absent", "null"]

default _worst_read(_, _) := "value"

_worst_read(subj, check) := _worst_of({_read_state(subj, p) | some p in _read_paths(check)} | _unordered_reads(subj, check)) if {
	not _unreadable_ref(check)
	not _broken_row(check)
}

_worst_read(_, check) := _worst_of({_used_ref_state(check, r) | some r in _check_refs(check)}) if {
	_unreadable_ref(check)
	not _broken_row(check)
}

_worst_read(_, check) := "absent" if _broken_row(check)

_broken_list_check(check) if {
	some chain in _list_chains(check)
	count(chain) > 2
}

_broken_list_check(check) if {
	some chain in _list_chains(check)
	not _chain_names_free(chain)
}

_lists_at(check) := [check] if _quantified(check)

_lists_at(check) := [leaf |
	some group in check.options
	is_array(group)
	some leaf in group
	_quantified(leaf)
] if _combinator(check)

_lists_at(check) := [] if {
	not _quantified(check)
	not _combinator(check)
}

_list_chains(check) := array.concat(
	array.concat(
		[[a] | some a in _lists_at(check)],
		[[a, b] | some a in _lists_at(check); some b in _lists_at(object.get(a, "check", {}))],
	),
	[[a, b, c] |
		some a in _lists_at(check)
		some b in _lists_at(object.get(a, "check", {}))
		some c in _lists_at(object.get(b, "check", {}))
	],
)

_chain_names_free(chain) if not "as" in object.keys(chain[count(chain) - 1])

_chain_names_free(chain) if {
	last := chain[count(chain) - 1]
	_valid_name(last.as)
	not last.as in object.keys(_bound_names)
	every c in array.slice(chain, 0, count(chain) - 1) {
		object.get(c, "as", null) != last.as
	}
}

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

_row_cause(check, subj) := "satisfied" if {
	not _broken_row(check)
	op_passed(check, subj)
}

_row_cause(check, subj) := "substituted" if {
	not _broken_row(check)
	not op_passed(check, subj)
	op_passed(_substitute_of(check), subj)
}

_row_cause(check, subj) := _worst_read(subj, check) if not _check_passed(check, subj)

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

_used_ref_state(check, r) := "absent" if _wrong_step(check, r)

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

_applies_cause(subj, req) := "satisfied" if _subject_matches(subj, req)

_applies_cause(subj, req) := "value" if _ruled_out(subj, req)

_applies_cause(subj, req) := _cause_precedence[i] if {
	_scope_unreadable(subj, req)
	i := min([j |
		some j, c in _cause_precedence
		c in _failed_filter_causes(subj, req)
	])
}

_failed_filter_causes(subj, req) := _filter_causes(subj, req) if not _each_step(req)

_failed_filter_causes(subj, req) := causes if {
	_each_step(req)
	s := _scope_of(req, subj)
	causes := _filter_causes(subj, req) with input as s
}

_filter_causes(subj, req) := {_filter_cause(check, subj) |
	some check in _applies_to_of(req)
	not _check_passed(check, subj)
}

_filter_cause(check, subj) := "value" if _answers_presence(check, subj)

_filter_cause(check, subj) := _row_cause(check, subj) if not _answers_presence(check, subj)

_answers_presence(check, subj) if {
	check.op == "present"
	_keys_of(check.path)
	_ := _start_of(subj, check.path)
	not _unreadable_ref(check)
	not _broken_row(check)
	_unordered_reads(subj, check) == set()
	_row_cause(check, subj) in {"absent", "null"}
}

_ruled_out(subj, req) if "value" in _failed_filter_causes(subj, req)

_scope_unreadable(subj, req) if {
	not _subject_matches(subj, req)
	not _ruled_out(subj, req)
}

_scope_readable(doc, req) if {
	not _from_unreadable(req)
	every subj in _raw_subjects(doc, req) {
		not _scope_unreadable(subj, req)
	}
}

_nested_describe(check, item) := _leaf_describe(check, item) if not _misplaced(check)

_nested_describe(check, _) := sprintf("<%s can't go here>", [_text(check.op)]) if _misplaced(check)

_misplaced(check) if {
	check.op in operators
	not check.op in _leaf_ops
	not _quantified(check)
}

default _leaf_describe(_, _) := ""

_leaf_describe(check, _) := sprintf("<unknown op %s>", [_text(check.op)]) if not check.op in operators

_leaf_describe(check, _) := "<missing op>" if {
	is_object(check)
	not "op" in object.keys(check)
}

_leaf_describe(check, _) := "<invalid check>" if not is_object(check)

_leaf_describe(check, item) := sprintf("%s >= %s and %s <= %s", [n, _value_text(check.min), n, _value_text(check.max)]) if {
	check.op == "range"
	n := _item_path_name(item, check.path)
}

_leaf_describe(check, item) := sprintf("not contains(%s, %s)", [_item_path_name(item, check.path), _value_text(check.value)]) if check.op == "excludes"

_leaf_describe(check, item) := sprintf("contains(%s, %s)", [_item_path_name(item, check.path), _value_text(check.value)]) if check.op == "includes"

_leaf_describe(check, item) := sprintf("%s in [%s]", [_item_path_name(item, check.path), concat(", ", sort([_literal_text(v) | some v in _written(check.values)]))]) if {
	check.op == "in"
	_value_list(_written(check.values))
}

_leaf_describe(check, item) := sprintf("%s in %s", [_item_path_name(item, check.path), _ref_name(check.values.ref)]) if {
	check.op == "in"
	_is_ref(check.values)
}

_leaf_describe(check, item) := sprintf("%s in <invalid ref>", [_item_path_name(item, check.path)]) if {
	check.op == "in"
	_malformed(check.values)
}

_leaf_describe(check, item) := sprintf("%s in <invalid values>", [_item_path_name(item, check.path)]) if {
	check.op == "in"
	not _is_ref(object.get(check, "values", null))
	not _malformed(object.get(check, "values", null))
	not _value_list(_written(object.get(check, "values", null)))
}

_leaf_describe(check, item) := sprintf("%s == %s", [_item_path_name(item, check.path), _value_text(check.value)]) if check.op == "equals"

_leaf_describe(check, item) := sprintf("%s is present", [_item_path_name(item, check.path)]) if check.op == "present"

_leaf_describe(check, item) := sprintf("%s is a non-empty string", [_item_path_name(item, check.path)]) if check.op == "non_empty_string"

_leaf_describe(check, item) := sprintf("%s matches one of %s", [_item_path_name(item, check.path), _pattern_list(check)]) if check.op == "matches_any"

_leaf_describe(check, item) := sprintf("%s matches none of %s", [_item_path_name(item, check.path), _pattern_list(check)]) if check.op == "not_matches_any"

_pattern_list(check) := sprintf("[%s]", [concat(", ", sort([_literal_text(p) | some p in _written(check.patterns)]))]) if _value_list(_written(check.patterns))

_pattern_list(check) := _ref_name(check.patterns.ref) if _is_ref(check.patterns)

_pattern_list(check) := "<invalid ref>" if _malformed(check.patterns)

_pattern_list(check) := "<invalid patterns>" if {
	not _is_ref(object.get(check, "patterns", null))
	not _malformed(object.get(check, "patterns", null))
	not _value_list(_written(object.get(check, "patterns", null)))
}

_leaf_describe(check, item) := sprintf("%s %s %s", [_item_path_name(item, check.left), _text(check.cmp), _item_path_name(item, check.right)]) if check.op in {"compare", "compare_time"}

default _expression_of(_, _) := ""

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

_list_describe(check, given) := sprintf("%s %s%s: %s", [
	_quantifier(check),
	_collection_name(check),
	_as_text(check, given),
	_element_describe(check.check, _item_name(check), _given_with(check, given)),
])

_as_text(check, _) := "" if not "as" in object.keys(check)

_as_text(check, given) := sprintf(" as $%s", [check.as]) if {
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

_item_given(item) := {substring(item, 1, -1)} if {
	startswith(item, "$")
	not startswith(item, "$$")
}

_item_given(item) := set() if not startswith(item, "$")

_given_with(check, given) := given | {check.as} if _valid_name(object.get(check, "as", null))

_given_with(check, given) := given if not _valid_name(object.get(check, "as", null))

_quantifier(check) := "every" if check.op == "all"

_quantifier(check) := "some" if check.op == "any"

_expression_of(check, item) := sprintf("one of: %s", [concat(" | ", sort([sprintf("%s(%s)", [_text(nm), concat(" and ", [_top_option_describe(group[k], item) | some k in _names(group)])]) | some nm, group in check.options]))]) if {
	not _written_expression(check)
	check.op == "any_of"
}

_top_option_describe(leaf, item) := _nested_describe(leaf, item) if not _quantified(leaf)

_top_option_describe(leaf, item) := _list_describe(leaf, _item_given(item)) if _quantified(leaf)

_collection_name(check) := _path_name(check.path) if not check.each

_collection_name(check) := _projection_name(check.path, check.each) if check.each

_item_name(check) := sprintf("%s[]", [_collection_name(check)]) if not _valid_name(object.get(check, "as", null))

_item_name(check) := sprintf("$%s", [check.as]) if _valid_name(object.get(check, "as", null))

_inner_collection_name(check, item) := _item_path_name(item, check.path) if not check.each

_inner_collection_name(check, item) := sprintf("%s[].%s", [_item_path_name(item, check.path), _path_name(check.each)]) if check.each

_inner_item_name(check, item) := sprintf("%s[]", [_inner_collection_name(check, item)]) if not _valid_name(object.get(check, "as", null))

_inner_item_name(check, _) := sprintf("$%s", [check.as]) if _valid_name(object.get(check, "as", null))

_element_describe(check, item, _) := _nested_describe(check, item) if {
	not _combinator(check)
	not _quantified(check)
}

_element_describe(check, item, given) := sprintf("one of: %s", [concat(" | ", sort([sprintf("%s(%s)", [_text(nm), concat(" and ", [_element_option_describe(group[k], item, given) | some k in _names(group)])]) | some nm, group in check.options]))]) if _combinator(check)

_element_describe(check, item, given) := _element_list_describe(check, item, given) if _quantified(check)

_element_option_describe(leaf, item, _) := _nested_describe(leaf, item) if not _quantified(leaf)

_element_option_describe(leaf, item, given) := _element_list_describe(leaf, item, given) if _quantified(leaf)

_element_list_describe(check, item, given) := sprintf("%s %s%s: %s", [
	_quantifier(check),
	_inner_collection_name(check, item),
	_as_text(check, given),
	_inner_describe(check.check, _inner_item_name(check, item)),
])

_inner_describe(check, item) := _nested_describe(check, item) if {
	not _combinator(check)
	not _quantified(check)
}

_inner_describe(check, item) := _any_of_describe(check, item) if _combinator(check)

_inner_describe(check, _) := "<nested too deep>" if _quantified(check)

_any_of_describe(check, item) := sprintf("one of: %s", [concat(" | ", sort([_variant_describe(nm, group, item) | some nm, group in check.options]))])

_variant_describe(nm, group, item) := sprintf("%s(%s)", [_text(nm), concat(" and ", [_inner_option_describe(group[k], item) | some k in _names(group)])])

_inner_option_describe(leaf, item) := _nested_describe(leaf, item) if not _quantified(leaf)

_inner_option_describe(leaf, _) := "<nested too deep>" if _quantified(leaf)

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

_check_def(check, item) := _with_refs(_described(check, item), check)

_with_refs(def, checked) := object.union(def, {"$refs": _ref_inputs(checked)}) if count(_check_refs(checked)) > 0

_with_refs(def, checked) := def if count(_check_refs(checked)) == 0

_described(check, item) := object.union(check, {"expression": _expression_of(check, item)}) if {
	is_object(check)
	not check.substitute
}

_described(check, item) := {"expression": _expression_of(check, item)} if not is_object(check)

_described(check, item) := object.union(check, {"expression": sprintf(
	"%s, or substitute: %s",
	[_expression_of(check, item), _expression_of(check.substitute, item)],
)}) if check.substitute

_subject_item_name(req) := sprintf("$%s", [_each_step(req).each_as]) if _from_well_formed(req)

_subject_item_name(req) := sprintf("%s[]", [_path_name(_from_of(req))]) if {
	not _stepped(req)
	_from_of(req) != []
}

_subject_item_name(req) := "$$input" if {
	not _stepped(req)
	_from_of(req) == []
}

_subject_item_name(req) := "<invalid from>" if {
	_stepped(req)
	not _from_well_formed(req)
}

_matching_count_name(req) := sprintf("count(matching(%s))", [_path_name(_from_path(req))]) if _from_well_formed(req)

_matching_count_name(req) := "count(matching(<invalid from>))" if not _from_well_formed(req)

_min_subjects_def(req) := {"$min_subjects": _with_refs(
	{
		"description": sprintf("at least %s matching %s subject(s) required", [_literal_text(_min_subjects_of(req)), _text(_subject_type_of(req))]),
		"expression": sprintf("%s >= %s", [_matching_count_name(req), _literal_text(_min_subjects_of(req))]),
	},
	{"from": _from_of(req)},
)}

_well_formed_def(req) := {"$well_formed": {
	"description": "the requirement declares at least one check and a recognised \"require\" value, its from and id only hold steps that can be keys, and its from, id and min_subjects only hold numbers a 64-bit float can hold; lacking any of these, it asserts nothing that could ever be satisfied, or not the same way everywhere",
	"expression": `count(checks) >= 1 and require in ["every", "some"] and steps are keys and numbers fit a float`,
}} if not _stepped(req)

_well_formed_def(req) := {"$well_formed": {
	"description": "the requirement declares at least one check, a recognised \"require\" value, and a from that ends with its only step, which gives a name that doesn't start with $ and, if it has keys, gives them as a list, its from and id only hold steps that can be keys, and its from, id and min_subjects only hold numbers a 64-bit float can hold",
	"expression": `count(checks) >= 1 and require in ["every", "some"] and from is well formed and steps are keys and numbers fit a float`,
}} if _stepped(req)

default _well_formed(_) := false

_well_formed(req) if {
	_size(_checks_of(req)) > 0
	_require_of(req) in {"every", "some"}
	_from_well_formed(req)
	not _out_of_range([object.get(req, f, null) | some f in ["from", "id", "min_subjects"]])
	not _badly_stepped(_from_of(req))
	not _badly_stepped(object.get(req, "id", []))
}

_well_formed_inputs(req) := [
	{"name": "count(checks)", "value": _size(_checks_of(req))},
	{"name": "require", "value": _require_of(req)},
] if not _stepped(req)

_well_formed_inputs(req) := [
	{"name": "count(checks)", "value": _size(_checks_of(req))},
	{"name": "require", "value": _require_of(req)},
	{"name": "from", "value": _from_of(req)},
] if _stepped(req)

_applies_def(req) := {"$applies": _with_refs(
	{
		"description": sprintf("subject is in scope as a %s under this requirement's applies_to filter; out-of-scope subjects are recorded but not evaluated, and a subject whose filter can't be read fails", [_text(_subject_type_of(req))]),
		"expression": concat(" and ", [_expression_of(_applies_to_of(req)[name], _subject_item_name(req)) | some name in _applies_to_names(req)]),
	},
	_applies_to_of(req),
)} if _size(_applies_to_of(req)) > 0

_applies_def(req) := {} if _size(_applies_to_of(req)) == 0

_applies_to_names(req) := sort(object.keys(_applies_to_of(req))) if is_object(_applies_to_of(req))

_requirement_check_defs(req) := object.union(
	object.union(
		{name: _check_def(check, _subject_item_name(req)) | some name, check in _checks_of(req)},
		_min_subjects_def(req),
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
	row := {
		"requirement": req_name,
		"subject": _entry_ref(entry, req),
		"check": check_name,
		"inputs": _inputs_in(req, check, entry.subject),
		"passed": _passes(req, check, entry.subject),
		"cause": _cause_in(req, check, entry.subject),
	}
]

_well_formed_row(req, req_name) := {
	"requirement": req_name,
	"subject": {"type": _subject_type_of(req), "id": null},
	"check": "$well_formed",
	"inputs": _well_formed_inputs(req),
	"passed": _well_formed(req),
	"cause": _verdict_cause(_well_formed(req)),
}

_min_subjects_row(doc, req, req_name) := {
	"requirement": req_name,
	"subject": {"type": _subject_type_of(req), "id": null},
	"check": "$min_subjects",
	"inputs": [{"name": _matching_count_name(req), "value": count(_matching_subjects(doc, req))}],
	"passed": _enough_subjects(doc, req),
	"cause": _min_subjects_cause(doc, req),
}

default _enough_subjects(_, _) := false

_enough_subjects(doc, req) if {
	not _from_unreadable(req)
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
}

_min_subjects_cause(doc, req) := _verdict_cause(_enough_subjects(doc, req)) if not _from_unreadable(req)

_min_subjects_cause(_, req) := _from_cause(req) if _from_unreadable(req)

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

_applies_rows(_, req, _) := [] if _size(_applies_to_of(req)) == 0

_applies_inputs(subj, req) := [inp |
	some name in _applies_to_names(req)
	some inp in _inputs_in(req, _applies_to_of(req)[name], subj)
]

default _requirement_satisfied(_, _) := false

_requirement_satisfied(doc, req) if {
	_well_formed(req)
	_require_of(req) == "every"
	_scope_readable(doc, req)
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
	every subj in _matching_subjects(doc, req) {
		_subject_passed(req, subj)
	}
}

_requirement_satisfied(doc, req) if {
	_well_formed(req)
	_require_of(req) == "some"
	_scope_readable(doc, req)
	count(_matching_subjects(doc, req)) >= _min_subjects_of(req)
	some subj in _matching_subjects(doc, req)
	_subject_passed(req, subj)
}

_requirement_satisfied(doc, req) if {
	_well_formed(req)
	_require_of(req) == "some"
	_scope_readable(doc, req)
	_min_subjects_of(req) == 0
	count(_matching_subjects(doc, req)) == 0
}

default _all_satisfied(_, _) := false

_all_satisfied(doc, policy) if {
	_size(policy) > 0
	count([name |
		some name, req in policy
		not _requirement_satisfied(doc, req)
	]) == 0
}

_results(doc, policy) := array.concat(
	array.concat(
		[_well_formed_row(policy[name], name) | some name in _names(policy)],
		[_min_subjects_row(doc, policy[name], name) | some name in _names(policy)],
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
	r := _report_of(doc, policy) with data.ergo_document as doc with data.ergo_params as params with input as {"ergo/names": {}}
}

_report_of(doc, policy) := {
	"compliant": _all_satisfied(doc, policy),
	"requirements": {name: {
		"require": _require_of(req),
		"satisfied": _requirement_satisfied(doc, req),
		"subjects": {"total": count(_raw_subjects(doc, req)), "matching": count(_matching_subjects(doc, req))},
		"checks": _requirement_check_defs(req),
	} |
		some name, req in policy
	},
	"results": _results(doc, policy),
}

violations(report) := [{
	"requirement": row.requirement,
	"subject": row.subject,
	"check": row.check,
	"description": _definition_field(report.requirements, row, "description"),
	"expression": _definition_field(report.requirements, row, "expression"),
	"inputs": array.concat(row.inputs, _recorded_refs(report.requirements, row)),
	"cause": row.cause,
} |
	some row in report.results
	_is_violation(report.requirements, row)
]

default _recorded_refs(_, _) := []

_recorded_refs(requirements, row) := refs if {
	refs := requirements[row.requirement].checks[row.check]["$refs"]
	is_array(refs)
}

default _is_violation(_, _) := false

_is_violation(requirements, row) if {
	row.passed == false
	not _out_of_scope_row(row)
	not requirements[row.requirement].satisfied
}

_out_of_scope_row(row) if {
	row.check == "$applies"
	row.cause == "value"
}

_definition_field(requirements, row, key) := object.get(
	requirements,
	[row.requirement, "checks", row.check, key],
	"",
)
