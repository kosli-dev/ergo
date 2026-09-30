package ergo

import rego.v1

checks_of(req) := object.get(req, "checks", {})

applies_to_of(req) := object.get(req, "applies_to", {})

from_of(req) := object.get(req, "from", [])

subject_type_of(req) := object.get(req, "subject_type", "subject")

min_subjects_of(req) := object.get(req, "min_subjects", 1)

require_of(req) := object.get(req, "require", "every")

raw_subjects(doc, req) := coll if {
	coll := object.get(doc, from_of(req), null)
	is_array(coll)
}

raw_subjects(doc, req) := [coll] if {
	coll := object.get(doc, from_of(req), null)
	is_object(coll)
}

raw_subjects(doc, req) := [] if {
	not is_array(object.get(doc, from_of(req), null))
	not is_object(object.get(doc, from_of(req), null))
}

matching_subjects(doc, req) := [subj |
	some subj in raw_subjects(doc, req)
	subject_matches(subj, req)
]

default subject_matches(_, _) := false

subject_matches(subj, req) if {
	every _, check in applies_to_of(req) {
		check_passed(check, subj)
	}
}

subject_ref(subj, req) := {
	"type": subject_type_of(req),
	"id": object.get(subj, object.get(req, "id", []), null),
}

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

resolved(subj, path) := object.get(subj, path, absent) if not selector_index(path)

resolved(subj, path) := v if {
	i := selector_index(path)
	base := object.get(subj, array.slice(path, 0, i), absent)
	base != absent
	elem := selected(base, path[i])
	v := object.get(elem, array.slice(path, i + 1, count(path)), absent)
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
		object.get(v, [k], absent) == want
	}
}

path_name(path) := concat(".", [segment_name(p) | some p in path])

segment_name(p) := sprintf("%v", [p]) if not is_object(p)

segment_name(p) := sprintf("[%s]", [concat(" and ", sort([sprintf("%v==%v", [k, v]) | some k, v in p.where]))]) if is_object(p)

default leaf_passed(_, _) := false

leaf_passed(check, subj) if {
	check.op == "range"
	v := value_at(subj, check.path)
	is_number(v)
	v >= check.min
	v <= check.max
}

leaf_passed(check, subj) if {
	check.op == "excludes"
	v := value_at(subj, check.path)
	is_array(v)
	not check.value in v
}

leaf_passed(check, subj) if {
	check.op == "includes"
	v := value_at(subj, check.path)
	is_array(v)
	check.value in v
}

leaf_passed(check, subj) if {
	check.op == "equals"
	field(subj, check.path) == check.value
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
	some pattern in check.patterns
	is_string(pattern)
	regex.match(pattern, v)
}

leaf_passed(check, subj) if {
	check.op == "not_matches_any"
	v := value_at(subj, check.path)
	is_string(v)
	every pattern in check.patterns {
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

op_passed(check, subj) if {
	check.op == "all"
	every elem in elements(subj, check) {
		element_passed(check.check, elem)
	}
}

op_passed(check, subj) if {
	check.op == "any"
	some elem in elements(subj, check)
	element_passed(check.check, elem)
}

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

element_passed(check, elem) if any_of_passed(check, elem)

op_passed(check, subj) if any_of_passed(check, subj)

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

read_paths(check) := [check.path] if {
	not check.inputs
	quantified(check)
}

read_paths(check) := [p |
	some group in check.options
	some leaf in group
	some p in leaf_paths(leaf)
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

read_state(subj, path) := "ambiguous" if count(selector_candidates(subj, path)) > 1

read_state(subj, path) := "unmatched" if count(selector_candidates(subj, path)) == 0

read_state(subj, path) := "null" if resolved(subj, path) == null

read_state(subj, path) := "value" if {
	v := resolved(subj, path)
	v != absent
	v != null
}

selector_candidates(subj, path) := candidates if {
	base := base_collection(subj, path)
	candidates := [v |
		some v in base
		selector_matches(v, path[selector_index(path)])
	]
}

base_collection(subj, path) := base if {
	i := selector_index(path)
	base := object.get(subj, array.slice(path, 0, i), absent)
	base != absent
	is_collection(base)
}

is_collection(v) if is_array(v)

is_collection(v) if is_object(v)

cause_precedence := ["ambiguous", "unmatched", "absent", "null"]

default worst_read(_, _) := "value"

worst_read(subj, paths) := cause_precedence[i] if {
	states := {read_state(subj, p) | some p in paths}
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

row_cause(check, subj) := worst_read(subj, read_paths(check)) if not check_passed(check, subj)

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

failed_filter_causes(subj, req) := {row_cause(check, subj) |
	some check in applies_to_of(req)
	not check_passed(check, subj)
}

ruled_out(subj, req) if "value" in failed_filter_causes(subj, req)

scope_unreadable(subj, req) if {
	not subject_matches(subj, req)
	not ruled_out(subj, req)
}

scope_readable(doc, req) if {
	every subj in raw_subjects(doc, req) {
		not scope_unreadable(subj, req)
	}
}

default leaf_describe(_) := ""

leaf_describe(check) := sprintf("%s >= %v and %s <= %v", [n, check.min, n, check.max]) if {
	check.op == "range"
	n := path_name(check.path)
}

leaf_describe(check) := sprintf("not contains(%s, %v)", [path_name(check.path), check.value]) if check.op == "excludes"

leaf_describe(check) := sprintf("contains(%s, %v)", [path_name(check.path), check.value]) if check.op == "includes"

leaf_describe(check) := sprintf("%s == %v", [path_name(check.path), check.value]) if check.op == "equals"

leaf_describe(check) := sprintf("%s is present", [path_name(check.path)]) if check.op == "present"

leaf_describe(check) := sprintf("%s is a non-empty string", [path_name(check.path)]) if check.op == "non_empty_string"

leaf_describe(check) := sprintf("%s matches one of [%s]", [path_name(check.path), pattern_list(check)]) if check.op == "matches_any"

leaf_describe(check) := sprintf("%s matches none of [%s]", [path_name(check.path), pattern_list(check)]) if check.op == "not_matches_any"

pattern_list(check) := concat(", ", sort([sprintf("%v", [p]) | some p in check.patterns]))

leaf_describe(check) := sprintf("%s %s %s", [path_name(check.left), check.cmp, path_name(check.right)]) if check.op in {"compare", "compare_time"}

default expression_of(_) := ""

expression_of(check) := check.expression

expression_of(check) := leaf_describe(check) if {
	not check.expression
	not quantified(check)
	not combinator(check)
}

expression_of(check) := sprintf("every %s: %s", [collection_name(check), element_describe(check.check)]) if {
	not check.expression
	check.op == "all"
}

expression_of(check) := sprintf("some %s: %s", [collection_name(check), element_describe(check.check)]) if {
	not check.expression
	check.op == "any"
}

expression_of(check) := any_of_describe(check) if {
	not check.expression
	check.op == "any_of"
}

collection_name(check) := path_name(check.path) if not check.each

collection_name(check) := sprintf("%s[].%s", [path_name(check.path), path_name(check.each)]) if check.each

element_describe(check) := leaf_describe(check) if not combinator(check)

element_describe(check) := any_of_describe(check) if combinator(check)

any_of_describe(check) := sprintf("one of: %s", [concat(" | ", sort([variant_describe(nm, group) | some nm, group in check.options]))])

variant_describe(nm, group) := sprintf("%v(%s)", [nm, concat(" and ", [leaf_describe(leaf) | some leaf in group])])

two_sided(check) if check.op in {"compare", "compare_time"}

default check_inputs(_, _) := []

check_inputs(subj, check) := [echoed(subj, spec) | some spec in check.inputs] if {
	check.inputs
}

echoed(subj, spec) := {"name": path_name(spec), "value": value_at(subj, spec)} if is_array(spec)

echoed(subj, spec) := {
	"name": sprintf("%s[].%s", [path_name(object.get(spec, "path", [])), path_name(object.get(spec, "each", []))]),
	"value": [value_at(elem, object.get(spec, "each", [])) | some elem in value_at(subj, object.get(spec, "path", []))],
} if is_object(spec)

check_inputs(subj, check) := [
	{"name": path_name(check.left), "value": value_at(subj, check.left)},
	{"name": path_name(check.right), "value": value_at(subj, check.right)},
] if {
	not check.inputs
	two_sided(check)
}

check_inputs(subj, check) := [{"name": nm, "value": vals}] if {
	not check.inputs
	quantified(check)
	not check.each
	vals := [value_at(elem, object.get(check.check, "path", [])) | some elem in value_at(subj, check.path)]
	nm := sprintf("%s[].%s", [path_name(check.path), path_name(object.get(check.check, "path", []))])
}

check_inputs(subj, check) := [{"name": collection_name(check), "value": vals}] if {
	not check.inputs
	quantified(check)
	check.each
	vals := [value_at(elem, check.each) | some elem in value_at(subj, check.path)]
}

check_inputs(subj, check) := [{"name": path_name(check.path), "value": value_at(subj, check.path)}] if {
	not check.inputs
	not two_sided(check)
	not quantified(check)
	check.path
}

check_inputs(subj, check) := [{"name": nm, "value": reads[nm]} | some nm in sort(object.keys(reads))] if {
	not check.inputs
	check.op == "any_of"
	reads := any_of_reads(subj, check)
}

any_of_reads(subj, check) := {path_name(p): value_at(subj, p) |
	some group in check.options
	some leaf in group
	some p in leaf_paths(leaf)
}

leaf_paths(leaf) := [leaf.left, leaf.right] if two_sided(leaf)

leaf_paths(leaf) := [leaf.path] if {
	not two_sided(leaf)
	leaf.path
}

row_inputs(subj, check) := check_inputs(subj, check) if not check.substitute

row_inputs(subj, check) := array.concat(
	check_inputs(subj, check),
	check_inputs(subj, check.substitute),
) if check.substitute

check_def(check) := object.union(check, {"expression": expression_of(check)}) if not check.substitute

check_def(check) := object.union(check, {"expression": sprintf(
	"%s, or substitute: %s",
	[expression_of(check), expression_of(check.substitute)],
)}) if check.substitute

matching_count_name(req) := sprintf("count(matching(%s))", [path_name(from_of(req))])

min_subjects_def(req) := {"$min_subjects": {
	"description": sprintf("at least %d matching %s subject(s) required", [min_subjects_of(req), subject_type_of(req)]),
	"expression": sprintf("%s >= %d", [matching_count_name(req), min_subjects_of(req)]),
}}

well_formed_def(_) := {"$well_formed": {
	"description": "the requirement declares at least one check and a recognised \"require\" value; lacking either, it asserts nothing that could ever be satisfied",
	"expression": "count(checks) >= 1 and require in {every, some}",
}}

default well_formed(_) := false

well_formed(req) if {
	count(checks_of(req)) > 0
	require_of(req) in {"every", "some"}
}

applies_def(req) := {"$applies": {
	"description": sprintf("subject is in scope as a %s under this requirement's applies_to filter; out-of-scope subjects are recorded but not evaluated, and a subject whose filter can't be read fails", [subject_type_of(req)]),
	"expression": concat(" and ", [expression_of(applies_to_of(req)[name]) | some name in applies_to_names(req)]),
}} if count(applies_to_of(req)) > 0

applies_def(req) := {} if count(applies_to_of(req)) == 0

applies_to_names(req) := sort(object.keys(applies_to_of(req)))

requirement_check_defs(req) := object.union(
	object.union(
		{name: check_def(check) | some name, check in checks_of(req)},
		min_subjects_def(req),
	),
	object.union(applies_def(req), well_formed_def(req)),
)

subject_passed(req, subj) if {
	every _, check in checks_of(req) {
		check_passed(check, subj)
	}
}

subject_rows(doc, policy, req_name) := [row |
	some subj in matching_subjects(doc, policy[req_name])
	some check_name, check in checks_of(policy[req_name])
	row := {
		"requirement": req_name,
		"subject": subject_ref(subj, policy[req_name]),
		"check": check_name,
		"inputs": row_inputs(subj, check),
		"passed": check_passed(check, subj),
		"cause": row_cause(check, subj),
	}
]

well_formed_row(policy, req_name) := {
	"requirement": req_name,
	"subject": {"type": subject_type_of(policy[req_name]), "id": null},
	"check": "$well_formed",
	"inputs": [
		{"name": "count(checks)", "value": count(checks_of(policy[req_name]))},
		{"name": "require", "value": require_of(policy[req_name])},
	],
	"passed": well_formed(policy[req_name]),
	"cause": verdict_cause(well_formed(policy[req_name])),
}

min_subjects_row(doc, policy, req_name) := {
	"requirement": req_name,
	"subject": {"type": subject_type_of(policy[req_name]), "id": null},
	"check": "$min_subjects",
	"inputs": [{"name": matching_count_name(policy[req_name]), "value": count(matching_subjects(doc, policy[req_name]))}],
	"passed": count(matching_subjects(doc, policy[req_name])) >= min_subjects_of(policy[req_name]),
	"cause": verdict_cause(count(matching_subjects(doc, policy[req_name])) >= min_subjects_of(policy[req_name])),
}

applies_rows(doc, policy, req_name) := [{
	"requirement": req_name,
	"subject": subject_ref(subj, policy[req_name]),
	"check": "$applies",
	"inputs": applies_inputs(subj, policy[req_name]),
	"passed": subject_matches(subj, policy[req_name]),
	"cause": applies_cause(subj, policy[req_name]),
} |
	some subj in raw_subjects(doc, policy[req_name])
] if {
	count(applies_to_of(policy[req_name])) > 0
}

applies_rows(_, policy, req_name) := [] if count(applies_to_of(policy[req_name])) == 0

applies_inputs(subj, req) := [inp |
	some name in applies_to_names(req)
	some inp in row_inputs(subj, applies_to_of(req)[name])
]

default requirement_satisfied(_, _) := false

requirement_satisfied(doc, req) if {
	count(checks_of(req)) > 0
	require_of(req) == "every"
	scope_readable(doc, req)
	count(matching_subjects(doc, req)) >= min_subjects_of(req)
	every subj in matching_subjects(doc, req) {
		subject_passed(req, subj)
	}
}

requirement_satisfied(doc, req) if {
	count(checks_of(req)) > 0
	require_of(req) == "some"
	scope_readable(doc, req)
	count(matching_subjects(doc, req)) >= min_subjects_of(req)
	some subj in matching_subjects(doc, req)
	subject_passed(req, subj)
}

requirement_satisfied(doc, req) if {
	count(checks_of(req)) > 0
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
		[well_formed_row(policy, name) | some name, _ in policy],
		[min_subjects_row(doc, policy, name) | some name, _ in policy],
	),
	array.concat(
		[row | some name, _ in policy; some row in applies_rows(doc, policy, name)],
		[row | some name, _ in policy; some row in subject_rows(doc, policy, name)],
	),
)

report(doc, policy) := {
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
	"inputs": row.inputs,
	"cause": row.cause,
} |
	some row in report.results
	is_violation(report.requirements, row)
]

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
