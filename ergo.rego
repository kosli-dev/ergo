# Copyright 2026 Kosli, Inc
# SPDX-License-Identifier: Apache-2.0

package ergo

import rego.v1

checks_of(req) := object.get(req, "checks", {})

applies_to_of(req) := object.get(req, "applies_to", {})

from_of(req) := object.get(req, "from", [])

subject_type_of(req) := object.get(req, "subject_type", "subject")

min_subjects_of(req) := object.get(req, "min_subjects", 1)

require_of(req) := object.get(req, "require", "every")

from_path(req) := array.slice(from_of(req), 0, count(from_of(req)) - 1) if each_step(req)

from_path(req) := from_of(req) if not each_step(req)

each_step(req) := step if {
	f := from_of(req)
	is_array(f)
	count(f) > 0
	step := f[count(f) - 1]
	is_object(step)
	not is_ref(step)
}

stepped(req) if {
	f := from_of(req)
	is_array(f)
	some seg in f
	is_object(seg)
	not is_ref(seg)
}

default from_well_formed(_) := false

from_well_formed(req) if not stepped(req)

from_well_formed(req) if {
	step := each_step(req)
	every seg in from_path(req) {
		plain_step(seg)
	}
	object.keys(step) - {"each_as", "keys"} == set()
	valid_name(step.each_as)
	keys_well_formed(step)
}

plain_step(seg) if not is_object(seg)

plain_step(seg) if is_ref(seg)

valid_name(n) if {
	is_string(n)
	n != ""
	not startswith(n, "$")
}

keys_well_formed(step) if not "keys" in object.keys(step)

keys_well_formed(step) if {
	is_array(step.keys)
	every k in step.keys {
		not malformed(k)
	}
}

keys_well_formed(step) if is_ref(step.keys)

keys_well_formed(step) if {
	is_literal(step.keys)
	is_array(step.keys.literal)
}

listed_keys(step) := ks if {
	is_array(step.keys)
	ks := [step_key(k) | some k in step.keys]
	count(ks) == count(step.keys)
}

listed_keys(step) := step.keys.literal if {
	is_literal(step.keys)
	is_array(step.keys.literal)
}

listed_keys(step) := v if {
	is_ref(step.keys)
	v := ref_read(step.keys.ref)
	is_array(v)
}

target(doc, req) := object.get(doc, from_keys(req), null)

from_keys(req) := ks if {
	p := from_path(req)
	is_array(p)
	ks := [step_key(seg) | some seg in p]
	count(ks) == count(p)
}

from_keys(req) := from_path(req) if not is_array(from_path(req))

from_unreadable(req) if {
	p := from_path(req)
	is_array(p)
	some seg in p
	is_ref(seg)
	not step_key(seg)
}

from_unreadable(req) if {
	step := each_step(req)
	is_ref(step.keys)
	not listed_keys(step)
}

from_unreadable(req) if {
	step := each_step(req)
	is_array(step.keys)
	not listed_keys(step)
}

from_cause(req) := worst_of(unread) if {
	unread := from_ref_states(req) - {"value"}
	count(unread) > 0
}

from_cause(req) := "absent" if from_ref_states(req) - {"value"} == set()

from_ref_states(req) := {ref_state(seg.ref) | some seg in from_path(req); is_ref(seg)} | {ref_state(r) | some r in keys_refs(each_step(req))}

keys_refs(step) := {step.keys.ref} if is_ref(step.keys)

keys_refs(step) := {k.ref | some k in step.keys; is_ref(k)} if is_array(step.keys)

listed_subjects(doc, req) := coll if {
	coll := target(doc, req)
	is_array(coll)
}

listed_subjects(doc, req) := [coll] if {
	coll := target(doc, req)
	is_object(coll)
}

listed_subjects(doc, req) := [] if {
	not is_array(target(doc, req))
	not is_object(target(doc, req))
}

raw_entries(doc, req) := [{"subject": subj} | some subj in listed_subjects(doc, req)] if not stepped(req)

raw_entries(_, req) := [] if {
	stepped(req)
	not from_well_formed(req)
}

raw_entries(doc, req) := [{"subject": subj} | some subj in coll] if {
	from_well_formed(req)
	not "keys" in object.keys(each_step(req))
	coll := target(doc, req)
	is_array(coll)
}

raw_entries(doc, req) := [{"key": k, "subject": coll[k]} | some k in sort(object.keys(coll))] if {
	from_well_formed(req)
	not "keys" in object.keys(each_step(req))
	coll := target(doc, req)
	is_object(coll)
}

raw_entries(doc, req) := [] if {
	from_well_formed(req)
	not "keys" in object.keys(each_step(req))
	not is_array(target(doc, req))
	not is_object(target(doc, req))
}

raw_entries(doc, req) := [{"key": k, "subject": object.get(keyed(doc, req), [k], absent)} | some k in sort({k | some k in listed_keys(each_step(req))})] if {
	from_well_formed(req)
	"keys" in object.keys(each_step(req))
	listed_keys(each_step(req))
}

raw_entries(_, req) := [] if {
	from_well_formed(req)
	"keys" in object.keys(each_step(req))
	not listed_keys(each_step(req))
}

keyed(doc, req) := coll if {
	coll := target(doc, req)
	is_object(coll)
}

keyed(doc, req) := {} if not is_object(target(doc, req))

raw_subjects(doc, req) := [entry.subject | some entry in raw_entries(doc, req)]

matching_entries(doc, req) := [entry |
	some entry in raw_entries(doc, req)
	subject_matches(entry.subject, req)
]

matching_subjects(doc, req) := [entry.subject | some entry in matching_entries(doc, req)]

scope_of(req, subj) := {"ergo/names": {each_step(req).each_as: subj}} if from_well_formed(req)

passes(req, check, subj) := check_passed(check, subj) if not each_step(req)

passes(req, check, subj) := v if {
	each_step(req)
	s := scope_of(req, subj)
	v := check_passed(check, subj) with input as s
}

cause_in(req, check, subj) := row_cause(check, subj) if not each_step(req)

cause_in(req, check, subj) := c if {
	each_step(req)
	s := scope_of(req, subj)
	c := row_cause(check, subj) with input as s
}

inputs_in(req, check, subj) := row_inputs(subj, check, subject_item_name(req)) if not each_step(req)

inputs_in(req, check, subj) := i if {
	each_step(req)
	s := scope_of(req, subj)
	i := row_inputs(subj, check, subject_item_name(req)) with input as s
}

default subject_matches(_, _) := false

subject_matches(subj, req) if {
	every _, check in applies_to_of(req) {
		passes(req, check, subj)
	}
}

entry_ref(entry, req) := {"type": subject_type_of(req), "id": entry.key} if "key" in object.keys(entry)

entry_ref(entry, req) := subject_ref(entry.subject, req) if {
	not "key" in object.keys(entry)
	not each_step(req)
}

entry_ref(entry, req) := r if {
	not "key" in object.keys(entry)
	each_step(req)
	s := scope_of(req, entry.subject)
	r := subject_ref(entry.subject, req) with input as s
}

subject_ref(subj, req) := {
	"type": subject_type_of(req),
	"id": subject_id(subj, req),
}

subject_id(subj, req) := value_at(subj, object.get(req, "id", [])) if is_object(subj)

subject_id(subj, _) := subj if not is_object(subj)

absent := {"ergo/absent": true}

default value_at(_, _) := null

value_at(subj, path) := v if {
	v := resolved(subj, path)
	v != absent
}

field(subj, path) := v if {
	v := resolved(subj, path)
	v != absent
}

resolved(subj, path) := read_from(start_of(subj, path), keys_of(path))

read_from(start, keys) := object.get(start, keys, absent) if not selector_index(keys)

read_from(start, []) := start

read_from(start, keys) := v if {
	i := selector_index(keys)
	base := object.get(start, array.slice(keys, 0, i), absent)
	base != absent
	elem := selected(base, keys[i])
	v := object.get(elem, array.slice(keys, i + 1, count(keys)), absent)
}

named(path) if {
	is_array(path)
	startswith(path[0], "$")
}

builtin(path) if {
	is_array(path)
	startswith(path[0], "$$")
}

start_of(subj, path) := subj if not named(path)

start_of(_, path) := data.ergo_document if path[0] == "$$input"

start_of(_, path) := data.ergo_params if path[0] == "$$params"

start_of(_, path) := input["ergo/names"][substring(path[0], 1, -1)] if {
	named(path)
	not builtin(path)
}

keys_of(path) := ks if {
	is_array(path)
	not named(path)
	ks := [step_key(seg) | some seg in path]
	count(ks) == count(path)
}

keys_of(path) := [path] if is_string(path)

keys_of(path) := [path] if is_number(path)

keys_of(path) := ks if {
	named(path)
	rest := array.slice(path, 1, count(path))
	ks := [step_key(seg) | some seg in rest]
	count(ks) == count(rest)
}

step_key(seg) := seg.literal if is_literal(seg)

step_key(seg) := v if {
	is_ref(seg)
	v := ref_read(seg.ref)
	is_key(v)
}

step_key(seg) := seg if {
	not is_literal(seg)
	not is_ref(seg)
	not malformed(seg)
}

is_key(v) if is_string(v)

is_key(v) if is_number(v)

unliteral(seg) := seg.literal if is_literal(seg)

unliteral(seg) := seg if not is_literal(seg)

is_ref(x) if {
	is_object(x)
	object.keys(x) == {"ref"}
}

is_literal(x) if {
	is_object(x)
	object.keys(x) == {"literal"}
}

arg(x) := x.literal if is_literal(x)

arg(x) := v if {
	is_ref(x)
	v := ref_read(x.ref)
	v != absent
	v != null
}

arg(x) := x if {
	not is_ref(x)
	not is_literal(x)
	not malformed(x)
}

ref_read(path) := object.get(start_of(null, path), [unliteral(seg) | some seg in array.slice(path, 1, count(path))], absent) if builtin(path)

ref_name(path) := concat(".", [sprintf("%v", [unliteral(seg)]) | some seg in path]) if builtin(path)

ref_name(path) := "<invalid ref>" if not builtin(path)

malformed(x) if {
	is_object(x)
	some k in {"ref", "literal"}
	k in object.keys(x)
	count(x) > 1
}

written(x) := x.literal if is_literal(x)

written(x) := x if {
	not is_ref(x)
	not is_literal(x)
	not malformed(x)
}

selector_index(path) := min([i | some i, seg in path; is_object(seg)])

selected(base, sel) := candidates[0] if {
	candidates := [v |
		some v in base
		selector_matches(v, sel)
	]
	count(candidates) == 1
}

selector_matches(v, sel) if {
	is_object(v)
	count(sel.where) > 0
	every k, want in sel.where {
		object.get(v, [k], absent) == arg(want)
	}
}

path_name(path) := concat(".", [segment_name(p) | some p in path])

item_path_name(item, []) := item

item_path_name(_, path) := path_name(path) if path != []

projection_name(path, []) := sprintf("%s[]", [path_name(path)])

projection_name(path, each) := sprintf("%s[].%s", [path_name(path), path_name(each)]) if each != []

segment_name(p) := sprintf("%v", [p]) if not is_object(p)

segment_name(p) := sprintf("%v", [p.literal]) if is_literal(p)

segment_name(p) := sprintf("[%s]", [concat(" and ", sort([sprintf("%v==%s", [k, value_text(v)]) | some k, v in p.where]))]) if {
	is_object(p)
	not is_literal(p)
	not is_ref(p)
	not malformed(p)
}

segment_name(p) := sprintf("[%s]", [ref_name(p.ref)]) if is_ref(p)

segment_name(p) := "[<invalid ref>]" if malformed(p)

value_text(x) := ref_name(x.ref) if is_ref(x)

value_text(x) := sprintf("%v", [written(x)]) if {
	not is_ref(x)
	not malformed(x)
}

value_text(x) := "<invalid ref>" if malformed(x)

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
	value_list(vals)
	some want in vals
	want == v
}

leaf_passed(check, subj) if {
	check.op == "equals"
	field(subj, check.path) == arg(check.value)
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
	comparable(l, r)
	cmp(check.cmp, l, r)
}

leaf_passed(check, subj) if {
	check.op == "compare_time"
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	rfc3339_shaped(l)
	rfc3339_shaped(r)
	cmp(check.cmp, time.parse_rfc3339_ns(l), time.parse_rfc3339_ns(r))
}

leaf_passed(check, subj) if {
	check.op == "compare_time"
	l := value_at(subj, check.left)
	r := value_at(subj, check.right)
	is_number(l)
	is_number(r)
	cmp(check.cmp, l, r)
}

value_list(v) if is_array(v)

value_list(v) if is_set(v)

comparable(l, r) if {
	l != null
	type_name(l) == type_name(r)
}

rfc3339_shaped(v) if {
	is_string(v)
	regex.match(`^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[Tt]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?([Zz]|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$`, v)
}

default cmp(_, _, _) := false

cmp("eq", l, r) if l == r

cmp("ne", l, r) if l != r

cmp("gt", l, r) if l > r

cmp("gte", l, r) if l >= r

cmp("lt", l, r) if l < r

cmp("lte", l, r) if l <= r

quantified(check) if check.op in {"all", "any"}

combinator(check) if check.op == "any_of"

default op_passed(_, _) := false

op_passed(check, subj) if {
	not quantified(check)
	not combinator(check)
	leaf_passed(check, subj)
}

op_passed(check, subj) if list_passed(check, subj)

default list_passed(_, _) := false

list_passed(check, subj) if {
	check.op == "all"
	names_free(check)
	every elem in elements(subj, check) {
		item_passed(check, elem)
	}
}

list_passed(check, subj) if {
	check.op == "any"
	names_free(check)
	some elem in elements(subj, check)
	item_passed(check, elem)
}

bound_names := n if {
	n := input["ergo/names"]
	is_object(n)
}

names_free(check) if not "as" in object.keys(check)

names_free(check) if {
	valid_name(check.as)
	not check.as in object.keys(bound_names)
}

item_passed(check, elem) := element_passed(check.check, elem) if not "as" in object.keys(check)

item_passed(check, elem) := v if {
	"as" in object.keys(check)
	names := object.union(bound_names, {check.as: elem})
	v := element_passed(check.check, elem) with input as {"ergo/names": names}
}

inner_item_passed(check, elem) := inner_passed(check.check, elem) if not "as" in object.keys(check)

inner_item_passed(check, elem) := v if {
	"as" in object.keys(check)
	names := object.union(bound_names, {check.as: elem})
	v := inner_passed(check.check, elem) with input as {"ergo/names": names}
}

default inner_passed(_, _) := false

inner_passed(check, elem) if {
	not quantified(check)
	not combinator(check)
	leaf_passed(check, elem)
}

inner_passed(check, elem) if any_of_passed(check, elem)

elements(subj, check) := coll if {
	not check.each
	coll := value_at(subj, check.path)
	is_array(coll)
	count(coll) > 0
}

elements(subj, check) := [elem |
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

default element_passed(_, _) := false

element_passed(check, elem) if {
	not combinator(check)
	leaf_passed(check, elem)
}

element_passed(check, elem) if element_any_of_passed(check, elem)

element_passed(check, elem) if element_list_passed(check, elem)

default element_list_passed(_, _) := false

element_list_passed(check, elem) if {
	check.op == "all"
	names_free(check)
	every inner in elements(elem, check) {
		inner_item_passed(check, inner)
	}
}

element_list_passed(check, elem) if {
	check.op == "any"
	names_free(check)
	some inner in elements(elem, check)
	inner_item_passed(check, inner)
}

op_passed(check, subj) if top_any_of_passed(check, subj)

default top_any_of_passed(_, _) := false

top_any_of_passed(check, subj) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		top_option_passed(leaf, subj)
	}
}

top_option_passed(leaf, subj) if leaf_passed(leaf, subj)

top_option_passed(leaf, subj) if list_passed(leaf, subj)

default element_any_of_passed(_, _) := false

element_any_of_passed(check, elem) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		element_option_passed(leaf, elem)
	}
}

element_option_passed(leaf, elem) if leaf_passed(leaf, elem)

element_option_passed(leaf, elem) if element_list_passed(leaf, elem)

default any_of_passed(_, _) := false

any_of_passed(check, subj) if {
	check.op == "any_of"
	some group in check.options
	is_array(group)
	count(group) > 0
	every leaf in group {
		leaf_passed(leaf, subj)
	}
}

default check_passed(_, _) := false

check_passed(check, subj) if op_passed(check, subj)

check_passed(check, subj) if op_passed(substitute_of(check), subj)

substitute_of(check) := object.get(check, "substitute", {})

default read_paths(_) := []

read_paths(check) := [input_spec_path(spec) | some spec in check.inputs] if check.inputs

read_paths(check) := [check.left, check.right] if {
	not check.inputs
	two_sided(check)
}

read_paths(check) := list_reads(check) if {
	not check.inputs
	quantified(check)
}

list_reads(check) := array.concat(array.concat([check.path], named_each(check)), element_name_reads(check))

named_each(check) := [check.each] if named(object.get(check, "each", []))

named_each(check) := [] if not named(object.get(check, "each", []))

read_paths(check) := [p |
	some group in check.options
	some leaf in group
	some p in check_reads(leaf)
] if {
	not check.inputs
	combinator(check)
}

read_paths(check) := [check.path] if {
	not check.inputs
	not two_sided(check)
	not quantified(check)
	not combinator(check)
	check.path
}

input_spec_path(spec) := spec if is_array(spec)

input_spec_path(spec) := object.get(spec, "path", []) if is_object(spec)

default read_state(_, _) := "absent"

read_state(subj, path) := "not_an_object" if {
	start := start_of(subj, path)
	not is_object(start)
	not reads_itself(path)
}

reads_itself(path) if keys_of(path) == []

read_state(subj, path) := "ambiguous" if count(selector_candidates(subj, path)) > 1

read_state(subj, path) := "unmatched" if count(selector_candidates(subj, path)) == 0

read_state(subj, path) := "null" if resolved(subj, path) == null

read_state(subj, path) := "value" if {
	v := resolved(subj, path)
	v != absent
	v != null
}

selector_candidates(subj, path) := candidates if {
	keys := keys_of(path)
	base := base_collection(start_of(subj, path), keys)
	candidates := [v |
		some v in base
		selector_matches(v, keys[selector_index(keys)])
	]
}

base_collection(start, keys) := base if {
	i := selector_index(keys)
	base := object.get(start, array.slice(keys, 0, i), absent)
	base != absent
	is_collection(base)
}

is_collection(v) if is_array(v)

is_collection(v) if is_object(v)

cause_precedence := ["not_an_object", "ambiguous", "unmatched", "absent", "null"]

default worst_read(_, _) := "value"

worst_read(subj, check) := worst_of({read_state(subj, p) | some p in read_paths(check)}) if {
	not unreadable_ref(check)
	not broken_list_check(check)
}

worst_read(_, check) := worst_of({used_ref_state(check, r) | some r in check_refs(check)}) if {
	unreadable_ref(check)
	not broken_list_check(check)
}

worst_read(_, check) := "absent" if broken_list_check(check)

broken_list_check(check) if {
	some chain in list_chains(check)
	count(chain) > 2
}

broken_list_check(check) if {
	some chain in list_chains(check)
	not chain_names_free(chain)
}

lists_at(check) := [check] if quantified(check)

lists_at(check) := [leaf |
	some group in check.options
	is_array(group)
	some leaf in group
	quantified(leaf)
] if combinator(check)

lists_at(check) := [] if {
	not quantified(check)
	not combinator(check)
}

list_chains(check) := array.concat(
	array.concat(
		[[a] | some a in lists_at(check)],
		[[a, b] | some a in lists_at(check); some b in lists_at(object.get(a, "check", {}))],
	),
	[[a, b, c] |
		some a in lists_at(check)
		some b in lists_at(object.get(a, "check", {}))
		some c in lists_at(object.get(b, "check", {}))
	],
)

chain_names_free(chain) if not "as" in object.keys(chain[count(chain) - 1])

chain_names_free(chain) if {
	last := chain[count(chain) - 1]
	valid_name(last.as)
	not last.as in object.keys(bound_names)
	every c in array.slice(chain, 0, count(chain) - 1) {
		object.get(c, "as", null) != last.as
	}
}

unreadable_ref(check) if {
	some r in check_refs(check)
	used_ref_state(check, r) != "value"
}

worst_of(states) := cause_precedence[i] if {
	i := min([j |
		some j, c in cause_precedence
		c in states
	])
}

row_cause(check, subj) := "satisfied" if op_passed(check, subj)

row_cause(check, subj) := "substituted" if {
	not op_passed(check, subj)
	op_passed(substitute_of(check), subj)
}

row_cause(check, subj) := worst_read(subj, check) if not check_passed(check, subj)

check_refs(check) := {x.ref |
	walk(check, [p, x])
	is_ref(x)
	not under_literal(check, p)
} | {"<invalid ref>" |
	walk(check, [p, x])
	malformed(x)
	not under_literal(check, p)
}

step_refs(check) := {x.ref |
	walk(check, [p, x])
	is_ref(x)
	not under_literal(check, p)
	count(p) >= 2
	p[count(p) - 2] in {"path", "left", "right", "each"}
	is_number(p[count(p) - 1])
}

used_ref_state(check, r) := "absent" if wrong_step(check, r)

used_ref_state(check, r) := ref_state(r) if not wrong_step(check, r)

wrong_step(check, r) if {
	r in step_refs(check)
	ref_state(r) == "value"
	not is_key(ref_read(r))
}

under_literal(check, p) if {
	some i, seg in p
	seg == "literal"
	walk(check, [q, w])
	q == array.slice(p, 0, i)
	is_literal(w)
}

default ref_state(_) := "absent"

ref_state(r) := "null" if ref_read(r) == null

ref_state(r) := "value" if {
	v := ref_read(r)
	v != absent
	v != null
}

default ref_shown(_) := null

ref_shown(r) := v if {
	v := ref_read(r)
	v != absent
}

ref_inputs(check) := [{"name": pair[0], "value": pair[1]} | some pair in sort({[ref_name(r), ref_shown(r)] | some r in check_refs(check)})]

verdict_cause(passed) := "satisfied" if passed

verdict_cause(passed) := "value" if not passed

applies_cause(subj, req) := "satisfied" if subject_matches(subj, req)

applies_cause(subj, req) := "value" if ruled_out(subj, req)

applies_cause(subj, req) := cause_precedence[i] if {
	scope_unreadable(subj, req)
	i := min([j |
		some j, c in cause_precedence
		c in failed_filter_causes(subj, req)
	])
}

failed_filter_causes(subj, req) := filter_causes(subj, req) if not each_step(req)

failed_filter_causes(subj, req) := causes if {
	each_step(req)
	s := scope_of(req, subj)
	causes := filter_causes(subj, req) with input as s
}

filter_causes(subj, req) := {filter_cause(check, subj) |
	some check in applies_to_of(req)
	not check_passed(check, subj)
}

filter_cause(check, subj) := "value" if answers_presence(check, subj)

filter_cause(check, subj) := row_cause(check, subj) if not answers_presence(check, subj)

answers_presence(check, subj) if {
	check.op == "present"
	keys_of(check.path)
	not unreadable_ref(check)
	row_cause(check, subj) in {"absent", "null"}
}

ruled_out(subj, req) if "value" in failed_filter_causes(subj, req)

scope_unreadable(subj, req) if {
	not subject_matches(subj, req)
	not ruled_out(subj, req)
}

scope_readable(doc, req) if {
	not from_unreadable(req)
	every subj in raw_subjects(doc, req) {
		not scope_unreadable(subj, req)
	}
}

default leaf_describe(_, _) := ""

leaf_describe(check, item) := sprintf("%s >= %s and %s <= %s", [n, value_text(check.min), n, value_text(check.max)]) if {
	check.op == "range"
	n := item_path_name(item, check.path)
}

leaf_describe(check, item) := sprintf("not contains(%s, %s)", [item_path_name(item, check.path), value_text(check.value)]) if check.op == "excludes"

leaf_describe(check, item) := sprintf("contains(%s, %s)", [item_path_name(item, check.path), value_text(check.value)]) if check.op == "includes"

leaf_describe(check, item) := sprintf("%s in [%s]", [item_path_name(item, check.path), concat(", ", sort([sprintf("%v", [v]) | some v in written(check.values)]))]) if {
	check.op == "in"
	value_list(written(check.values))
}

leaf_describe(check, item) := sprintf("%s in %s", [item_path_name(item, check.path), ref_name(check.values.ref)]) if {
	check.op == "in"
	is_ref(check.values)
}

leaf_describe(check, item) := sprintf("%s in <invalid ref>", [item_path_name(item, check.path)]) if {
	check.op == "in"
	malformed(check.values)
}

leaf_describe(check, item) := sprintf("%s in <invalid values>", [item_path_name(item, check.path)]) if {
	check.op == "in"
	not is_ref(object.get(check, "values", null))
	not malformed(object.get(check, "values", null))
	not value_list(written(object.get(check, "values", null)))
}

leaf_describe(check, item) := sprintf("%s == %s", [item_path_name(item, check.path), value_text(check.value)]) if check.op == "equals"

leaf_describe(check, item) := sprintf("%s is present", [item_path_name(item, check.path)]) if check.op == "present"

leaf_describe(check, item) := sprintf("%s is a non-empty string", [item_path_name(item, check.path)]) if check.op == "non_empty_string"

leaf_describe(check, item) := sprintf("%s matches one of %s", [item_path_name(item, check.path), pattern_list(check)]) if check.op == "matches_any"

leaf_describe(check, item) := sprintf("%s matches none of %s", [item_path_name(item, check.path), pattern_list(check)]) if check.op == "not_matches_any"

pattern_list(check) := sprintf("[%s]", [concat(", ", sort([sprintf("%v", [p]) | some p in written(check.patterns)]))]) if {
	not is_ref(check.patterns)
	not malformed(check.patterns)
}

pattern_list(check) := ref_name(check.patterns.ref) if is_ref(check.patterns)

pattern_list(check) := "<invalid ref>" if malformed(check.patterns)

leaf_describe(check, item) := sprintf("%s %s %s", [item_path_name(item, check.left), check.cmp, item_path_name(item, check.right)]) if check.op in {"compare", "compare_time"}

default expression_of(_, _) := ""

expression_of(check, _) := check.expression

expression_of(check, item) := leaf_describe(check, item) if {
	not check.expression
	not quantified(check)
	not combinator(check)
}

expression_of(check, item) := list_describe(check, item_given(item)) if {
	not check.expression
	quantified(check)
}

list_describe(check, given) := sprintf("%s %s%s: %s", [
	quantifier(check),
	collection_name(check),
	as_text(check, given),
	element_describe(check.check, item_name(check), given_with(check, given)),
])

as_text(check, _) := "" if not "as" in object.keys(check)

as_text(check, given) := sprintf(" as $%s", [check.as]) if {
	valid_name(check.as)
	not check.as in given
}

as_text(check, given) := " as <name given twice>" if {
	valid_name(check.as)
	check.as in given
}

as_text(check, _) := " as <invalid name>" if {
	"as" in object.keys(check)
	not valid_name(check.as)
}

item_given(item) := {substring(item, 1, -1)} if {
	startswith(item, "$")
	not startswith(item, "$$")
}

item_given(item) := set() if not startswith(item, "$")

given_with(check, given) := given | {check.as} if valid_name(object.get(check, "as", null))

given_with(check, given) := given if not valid_name(object.get(check, "as", null))

quantifier(check) := "every" if check.op == "all"

quantifier(check) := "some" if check.op == "any"

expression_of(check, item) := sprintf("one of: %s", [concat(" | ", sort([sprintf("%v(%s)", [nm, concat(" and ", [top_option_describe(leaf, item) | some leaf in group])]) | some nm, group in check.options]))]) if {
	not check.expression
	check.op == "any_of"
}

top_option_describe(leaf, item) := leaf_describe(leaf, item) if not quantified(leaf)

top_option_describe(leaf, item) := list_describe(leaf, item_given(item)) if quantified(leaf)

collection_name(check) := path_name(check.path) if not check.each

collection_name(check) := projection_name(check.path, check.each) if check.each

item_name(check) := sprintf("%s[]", [collection_name(check)]) if not valid_name(object.get(check, "as", null))

item_name(check) := sprintf("$%s", [check.as]) if valid_name(object.get(check, "as", null))

inner_collection_name(check, item) := item_path_name(item, check.path) if not check.each

inner_collection_name(check, item) := sprintf("%s[].%s", [item_path_name(item, check.path), path_name(check.each)]) if check.each

inner_item_name(check, item) := sprintf("%s[]", [inner_collection_name(check, item)]) if not valid_name(object.get(check, "as", null))

inner_item_name(check, _) := sprintf("$%s", [check.as]) if valid_name(object.get(check, "as", null))

element_describe(check, item, _) := leaf_describe(check, item) if {
	not combinator(check)
	not quantified(check)
}

element_describe(check, item, given) := sprintf("one of: %s", [concat(" | ", sort([sprintf("%v(%s)", [nm, concat(" and ", [element_option_describe(leaf, item, given) | some leaf in group])]) | some nm, group in check.options]))]) if combinator(check)

element_describe(check, item, given) := element_list_describe(check, item, given) if quantified(check)

element_option_describe(leaf, item, _) := leaf_describe(leaf, item) if not quantified(leaf)

element_option_describe(leaf, item, given) := element_list_describe(leaf, item, given) if quantified(leaf)

element_list_describe(check, item, given) := sprintf("%s %s%s: %s", [
	quantifier(check),
	inner_collection_name(check, item),
	as_text(check, given),
	inner_describe(check.check, inner_item_name(check, item)),
])

inner_describe(check, item) := leaf_describe(check, item) if {
	not combinator(check)
	not quantified(check)
}

inner_describe(check, item) := any_of_describe(check, item) if combinator(check)

inner_describe(check, _) := "<nested too deep>" if quantified(check)

any_of_describe(check, item) := sprintf("one of: %s", [concat(" | ", sort([variant_describe(nm, group, item) | some nm, group in check.options]))])

variant_describe(nm, group, item) := sprintf("%v(%s)", [nm, concat(" and ", [inner_option_describe(leaf, item) | some leaf in group])])

inner_option_describe(leaf, item) := leaf_describe(leaf, item) if not quantified(leaf)

inner_option_describe(leaf, _) := "<nested too deep>" if quantified(leaf)

two_sided(check) if check.op in {"compare", "compare_time"}

default check_inputs(_, _, _) := []

check_inputs(subj, check, item) := [echoed(subj, spec, item) | some spec in check.inputs] if {
	check.inputs
}

echoed(subj, spec, item) := {"name": item_path_name(item, spec), "value": value_at(subj, spec)} if is_array(spec)

echoed(subj, spec, _) := {
	"name": projection_name(object.get(spec, "path", []), object.get(spec, "each", [])),
	"value": [value_at(elem, object.get(spec, "each", [])) | some elem in value_at(subj, object.get(spec, "path", []))],
} if is_object(spec)

check_inputs(subj, check, item) := [
	{"name": item_path_name(item, check.left), "value": value_at(subj, check.left)},
	{"name": item_path_name(item, check.right), "value": value_at(subj, check.right)},
] if {
	not check.inputs
	two_sided(check)
}

check_inputs(subj, check, _) := array.concat(quantified_inputs(subj, check), name_inputs(subj, check)) if {
	not check.inputs
	quantified(check)
}

name_inputs(subj, check) := [{"name": path_name(p), "value": value_at(subj, p)} | some p in element_name_paths(check)]

element_name_paths(check) := [p | some p in element_name_reads(check); p != object.get(check.check, "path", [])]

element_name_reads(check) := sort({p |
	some read in scoped_reads(check)
	p := read[0]
	named(p)
	not substring(p[0], 1, -1) in read[1]
})

scoped_reads(check) := [read |
	given := names_of(check)
	some leaf in element_leaves(check.check)
	some read in leaf_reads(leaf, given)
]

leaf_reads(leaf, given) := [[p, given] | some p in leaf_paths(leaf)] if not quantified(leaf)

leaf_reads(leaf, given) := array.concat([[p, given] | some p in array.concat([leaf.path], named_each(leaf))], [[p, given | names_of(leaf)] |
	some l in element_leaves(leaf.check)
	some p in leaf_paths(l)
]) if quantified(leaf)

names_of(check) := {check.as} if "as" in object.keys(check)

names_of(check) := set() if not "as" in object.keys(check)

check_reads(leaf) := leaf_paths(leaf) if not quantified(leaf)

check_reads(leaf) := list_reads(leaf) if quantified(leaf)

element_leaves(check) := [check] if not combinator(check)

element_leaves(check) := [leaf | some group in check.options; some leaf in group] if combinator(check)

outer_named(check, p) if {
	named(p)
	not substring(p[0], 1, -1) in names_of(check)
}

relative_path(check, p) := array.slice(p, 1, count(p)) if reads_item(check, p)

relative_path(check, p) := p if not reads_item(check, p)

reads_item(check, p) if {
	named(p)
	substring(p[0], 1, -1) == check.as
}

quantified_inputs(subj, check) := [{"name": nm, "value": vals}] if {
	not check.each
	inner := object.get(check.check, "path", [])
	not outer_named(check, inner)
	rel := relative_path(check, inner)
	vals := [value_at(elem, rel) | some elem in value_at(subj, check.path)]
	nm := projection_name(check.path, rel)
}

quantified_inputs(subj, check) := [
	{"name": projection_name(check.path, []), "value": value_at(subj, check.path)},
	{"name": path_name(inner), "value": value_at(subj, inner)},
] if {
	not check.each
	inner := object.get(check.check, "path", [])
	outer_named(check, inner)
}

quantified_inputs(subj, check) := [{"name": collection_name(check), "value": vals}] if {
	check.each
	vals := [value_at(elem, check.each) | some elem in value_at(subj, check.path)]
}

check_inputs(subj, check, item) := [{"name": item_path_name(item, check.path), "value": value_at(subj, check.path)}] if {
	not check.inputs
	not two_sided(check)
	not quantified(check)
	check.path
}

check_inputs(subj, check, item) := [{"name": nm, "value": reads[nm]} | some nm in sort(object.keys(reads))] if {
	not check.inputs
	check.op == "any_of"
	reads := any_of_reads(subj, check, item)
}

any_of_reads(subj, check, item) := {item_path_name(item, p): value_at(subj, p) |
	some group in check.options
	some leaf in group
	some p in check_reads(leaf)
}

leaf_paths(leaf) := [leaf.left, leaf.right] if two_sided(leaf)

leaf_paths(leaf) := [leaf.path] if {
	not two_sided(leaf)
	leaf.path
}

row_inputs(subj, check, item) := check_inputs(subj, check, item) if not check.substitute

row_inputs(subj, check, item) := array.concat(
	check_inputs(subj, check, item),
	check_inputs(subj, check.substitute, item),
) if check.substitute

check_def(check, item) := with_refs(described(check, item), check)

with_refs(def, checked) := object.union(def, {"$refs": ref_inputs(checked)}) if count(check_refs(checked)) > 0

with_refs(def, checked) := def if count(check_refs(checked)) == 0

described(check, item) := object.union(check, {"expression": expression_of(check, item)}) if not check.substitute

described(check, item) := object.union(check, {"expression": sprintf(
	"%s, or substitute: %s",
	[expression_of(check, item), expression_of(check.substitute, item)],
)}) if check.substitute

subject_item_name(req) := sprintf("$%s", [each_step(req).each_as]) if from_well_formed(req)

subject_item_name(req) := sprintf("%s[]", [path_name(from_of(req))]) if {
	not stepped(req)
	from_of(req) != []
}

subject_item_name(req) := "input" if {
	not stepped(req)
	from_of(req) == []
}

subject_item_name(req) := "<invalid from>" if {
	stepped(req)
	not from_well_formed(req)
}

matching_count_name(req) := sprintf("count(matching(%s))", [path_name(from_path(req))]) if from_well_formed(req)

matching_count_name(req) := "count(matching(<invalid from>))" if not from_well_formed(req)

min_subjects_def(req) := {"$min_subjects": with_refs(
	{
		"description": sprintf("at least %d matching %s subject(s) required", [min_subjects_of(req), subject_type_of(req)]),
		"expression": sprintf("%s >= %d", [matching_count_name(req), min_subjects_of(req)]),
	},
	{"from": from_of(req)},
)}

well_formed_def(req) := {"$well_formed": {
	"description": "the requirement declares at least one check and a recognised \"require\" value; lacking either, it asserts nothing that could ever be satisfied",
	"expression": "count(checks) >= 1 and require in {every, some}",
}} if not stepped(req)

well_formed_def(req) := {"$well_formed": {
	"description": "the requirement declares at least one check, a recognised \"require\" value, and a from that ends with its only step, which gives a name that doesn't start with $ and, if it has keys, gives them as a list",
	"expression": "count(checks) >= 1 and require in {every, some} and from is well formed",
}} if stepped(req)

default well_formed(_) := false

well_formed(req) if {
	count(checks_of(req)) > 0
	require_of(req) in {"every", "some"}
	from_well_formed(req)
}

well_formed_inputs(req) := [
	{"name": "count(checks)", "value": count(checks_of(req))},
	{"name": "require", "value": require_of(req)},
] if not stepped(req)

well_formed_inputs(req) := [
	{"name": "count(checks)", "value": count(checks_of(req))},
	{"name": "require", "value": require_of(req)},
	{"name": "from", "value": from_of(req)},
] if stepped(req)

applies_def(req) := {"$applies": with_refs(
	{
		"description": sprintf("subject is in scope as a %s under this requirement's applies_to filter; out-of-scope subjects are recorded but not evaluated, and a subject whose filter can't be read fails", [subject_type_of(req)]),
		"expression": concat(" and ", [expression_of(applies_to_of(req)[name], subject_item_name(req)) | some name in applies_to_names(req)]),
	},
	applies_to_of(req),
)} if count(applies_to_of(req)) > 0

applies_def(req) := {} if count(applies_to_of(req)) == 0

applies_to_names(req) := sort(object.keys(applies_to_of(req)))

requirement_check_defs(req) := object.union(
	object.union(
		{name: check_def(check, subject_item_name(req)) | some name, check in checks_of(req)},
		min_subjects_def(req),
	),
	object.union(applies_def(req), well_formed_def(req)),
)

subject_passed(req, subj) if {
	every _, check in checks_of(req) {
		passes(req, check, subj)
	}
}

subject_rows(doc, req, req_name) := [row |
	some entry in matching_entries(doc, req)
	some check_name, check in checks_of(req)
	row := {
		"requirement": req_name,
		"subject": entry_ref(entry, req),
		"check": check_name,
		"inputs": inputs_in(req, check, entry.subject),
		"passed": passes(req, check, entry.subject),
		"cause": cause_in(req, check, entry.subject),
	}
]

well_formed_row(req, req_name) := {
	"requirement": req_name,
	"subject": {"type": subject_type_of(req), "id": null},
	"check": "$well_formed",
	"inputs": well_formed_inputs(req),
	"passed": well_formed(req),
	"cause": verdict_cause(well_formed(req)),
}

min_subjects_row(doc, req, req_name) := {
	"requirement": req_name,
	"subject": {"type": subject_type_of(req), "id": null},
	"check": "$min_subjects",
	"inputs": [{"name": matching_count_name(req), "value": count(matching_subjects(doc, req))}],
	"passed": enough_subjects(doc, req),
	"cause": min_subjects_cause(doc, req),
}

default enough_subjects(_, _) := false

enough_subjects(doc, req) if {
	not from_unreadable(req)
	count(matching_subjects(doc, req)) >= min_subjects_of(req)
}

min_subjects_cause(doc, req) := verdict_cause(enough_subjects(doc, req)) if not from_unreadable(req)

min_subjects_cause(_, req) := from_cause(req) if from_unreadable(req)

applies_rows(doc, req, req_name) := [{
	"requirement": req_name,
	"subject": entry_ref(entry, req),
	"check": "$applies",
	"inputs": applies_inputs(entry.subject, req),
	"passed": subject_matches(entry.subject, req),
	"cause": applies_cause(entry.subject, req),
} |
	some entry in raw_entries(doc, req)
] if {
	count(applies_to_of(req)) > 0
}

applies_rows(_, req, _) := [] if count(applies_to_of(req)) == 0

applies_inputs(subj, req) := [inp |
	some name in applies_to_names(req)
	some inp in inputs_in(req, applies_to_of(req)[name], subj)
]

default requirement_satisfied(_, _) := false

requirement_satisfied(doc, req) if {
	well_formed(req)
	require_of(req) == "every"
	scope_readable(doc, req)
	count(matching_subjects(doc, req)) >= min_subjects_of(req)
	every subj in matching_subjects(doc, req) {
		subject_passed(req, subj)
	}
}

requirement_satisfied(doc, req) if {
	well_formed(req)
	require_of(req) == "some"
	scope_readable(doc, req)
	count(matching_subjects(doc, req)) >= min_subjects_of(req)
	some subj in matching_subjects(doc, req)
	subject_passed(req, subj)
}

requirement_satisfied(doc, req) if {
	well_formed(req)
	require_of(req) == "some"
	scope_readable(doc, req)
	min_subjects_of(req) == 0
	count(matching_subjects(doc, req)) == 0
}

default all_satisfied(_, _) := false

all_satisfied(doc, policy) if {
	count(policy) > 0
	count([name |
		some name, req in policy
		not requirement_satisfied(doc, req)
	]) == 0
}

results(doc, policy) := array.concat(
	array.concat(
		[well_formed_row(req, name) | some name, req in policy],
		[min_subjects_row(doc, req, name) | some name, req in policy],
	),
	array.concat(
		[row | some name, req in policy; some row in applies_rows(doc, req, name)],
		[row | some name, req in policy; some row in subject_rows(doc, req, name)],
	),
)

report(doc, policy) := report_with_params(doc, configured_params, policy)

configured_params := data.params

default configured_params := {}

report_with_params(doc, params, policy) := r if {
	r := report_of(doc, policy) with data.ergo_document as doc with data.ergo_params as params with input as {"ergo/names": {}}
}

report_of(doc, policy) := {
	"compliant": all_satisfied(doc, policy),
	"requirements": {name: {
		"require": require_of(req),
		"satisfied": requirement_satisfied(doc, req),
		"subjects": {"total": count(raw_subjects(doc, req)), "matching": count(matching_subjects(doc, req))},
		"checks": requirement_check_defs(req),
	} |
		some name, req in policy
	},
	"results": results(doc, policy),
}

violations(report) := [{
	"requirement": row.requirement,
	"subject": row.subject,
	"check": row.check,
	"description": definition_field(report.requirements, row, "description"),
	"expression": definition_field(report.requirements, row, "expression"),
	"inputs": array.concat(row.inputs, recorded_refs(report.requirements, row)),
	"cause": row.cause,
} |
	some row in report.results
	is_violation(report.requirements, row)
]

default recorded_refs(_, _) := []

recorded_refs(requirements, row) := refs if {
	refs := requirements[row.requirement].checks[row.check]["$refs"]
	is_array(refs)
}

default is_violation(_, _) := false

is_violation(requirements, row) if {
	row.passed == false
	not out_of_scope_row(row)
	not requirements[row.requirement].satisfied
}

out_of_scope_row(row) if {
	row.check == "$applies"
	row.cause == "value"
}

definition_field(requirements, row, key) := object.get(
	requirements,
	[row.requirement, "checks", row.check, key],
	"",
)
