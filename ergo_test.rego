package ergo_test

import data.ergo
import rego.v1

report(doc, reqs) := ergo.report(doc, lifted(reqs), given_params)

subject_fields := ["from", "id", "applies_to"]

lifted(reqs) := {
	"subjects": {subject_name(reqs, name): subject_def(req) | some name, req in reqs; is_object(req)},
	"requirements": {name: lifted_req(reqs, name, req) | some name, req in reqs},
} if is_object(reqs)

lifted(reqs) := {"requirements": reqs} if not is_object(reqs)

lifted_req(reqs, name, req) := object.union(object.remove(req, array.concat(subject_fields, ["subject_type"])), {"subject": subject_name(reqs, name)}) if is_object(req)

lifted_req(_, _, req) := req if not is_object(req)

subject_def(req) := object.union({"from": []}, {f: req[f] | some f in subject_fields; f in object.keys(req)})

subject_type(req) := object.get(req, "subject_type", "subject")

subject_name(reqs, name) := subject_type(reqs[name]) if {
	count({subject_def(req) | some req in reqs; is_object(req); subject_type(req) == subject_type(reqs[name])}) == 1
} else := name

default given_params := {}

given_params := data.params

solo(subj, check) := report(
	{"items": [subj]},
	{"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": check},
	}},
)

verdict(subj, check) := row.passed if {
	some row in solo(subj, check).results
	row.check == "c"
}

inputs_of(subj, check) := row.inputs if {
	some row in solo(subj, check).results
	row.check == "c"
}

cause_of(subj, check) := row.cause if {
	some row in solo(subj, check).results
	row.check == "c"
}

rendered(subj, check) := solo(subj, check).requirements.s.checks.c.expression

rows_for(report, req_name, check_name) := [r |
	some r in report.results
	r.requirement == req_name
	r.check == check_name
]

id_req(from) := {"s": {
	"subject_type": "thing",
	"from": from,
	"id": ["id"],
	"checks": {"c": {"op": "present", "path": ["id"]}},
}}

subject_counts(doc, from) := report(doc, id_req(from)).requirements.s.subjects

test_array_from_yields_one_subject_per_element if {
	subject_counts({"items": [{"id": "a"}, {"id": "b"}]}, ["items"]) == {"total": 2, "matching": 2}
}

test_single_object_from_is_wrapped_as_one_subject if {
	subject_counts({"item": {"id": "a"}}, ["item"]) == {"total": 1, "matching": 1}
}

test_missing_from_yields_no_subjects if {
	subject_counts({"other": [{"id": "a"}]}, ["items"]) == {"total": 0, "matching": 0}
}

mixed_subjects := {"items": [{"id": "x", "n": "a"}, "b", null, 3]}

mixed_req := {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["n"]}}}}

test_a_subject_that_is_not_an_object_keeps_its_rows if {
	rows := rows_for(report(mixed_subjects, mixed_req), "s", "c")
	[[r.subject.id, r.passed, r.cause] | some r in rows] == [
		["x", true, "satisfied"],
		["b", false, "not_an_object"],
		[null, false, "not_an_object"],
		[3, false, "not_an_object"],
	]
}

test_a_subject_that_is_not_an_object_shows_up_as_a_violation if {
	count(ergo.violations(report(mixed_subjects, mixed_req))) == 3
}

test_a_subject_that_is_not_an_object_keeps_its_applies_row if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"kind": {"op": "equals", "path": ["kind"], "value": "lib"}},
		"checks": {"c": {"op": "present", "path": ["n"]}},
	}}
	rep := report({"items": ["b"]}, req)
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [["b", false, "not_an_object"]]
	{v.check | some v in ergo.violations(rep)} == {"$applies", "$min_subjects"}
}

test_a_subject_that_is_not_an_object_is_not_mistaken_for_one_missing_its_fields if {
	causes := {r.subject.id: r.cause | some r in rows_for(report({"items": [{"id": "x"}, "b"]}, mixed_req), "s", "c")}
	causes == {"x": "value", "b": "not_an_object"}
}

test_a_subject_that_is_not_an_object_fails_a_quantified_check_as_not_an_object if {
	req := {"s": {"from": ["items"], "checks": {"c": {"op": "all", "path": ["commits"], "check": {"op": "present", "path": ["sha"]}}}}}
	[r.cause | some r in rows_for(report({"items": ["b"]}, req), "s", "c")] == ["not_an_object"]
}

test_an_id_path_can_use_a_selector if {
	req := {"s": {
		"from": ["items"],
		"id": ["tags", {"where": {"k": "name"}}, "v"],
		"checks": {"c": {"op": "present", "path": ["tags"]}},
	}}
	[r.subject.id | some r in rows_for(report({"items": [{"tags": [{"k": "name", "v": "web"}]}]}, req), "s", "c")] == ["web"]
}

test_scalar_from_yields_no_subjects if {
	subject_counts({"items": "not-a-collection"}, ["items"]) == {"total": 0, "matching": 0}
}

test_empty_from_treats_the_whole_document_as_one_subject if {
	subject_counts({"id": "root"}, []) == {"total": 1, "matching": 1}
}

test_nested_from_resolves_through_objects if {
	subject_counts({"a": {"b": {"items": [{"id": "x"}]}}}, ["a", "b", "items"]) == {"total": 1, "matching": 1}
}

test_missing_id_path_yields_a_null_subject_id if {
	rep := report({"items": [{"no_id_here": 1}]}, id_req(["items"]))
	some row in rep.results
	row.subject == {"type": "thing", "id": null}
}

test_subject_id_is_read_from_the_declared_path if {
	rep := report({"items": [{"id": "abc"}]}, id_req(["items"]))
	some row in rep.results
	row.subject == {"type": "thing", "id": "abc"}
}

scoped_req(applies_to) := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"applies_to": applies_to,
	"checks": {"c": {"op": "present", "path": ["id"]}},
}}

merged_only := {"merged": {"op": "equals", "path": ["state"], "value": "MERGED"}}

two_states := {"items": [
	{"id": "a", "state": "MERGED"},
	{"id": "b", "state": "CLOSED"},
]}

test_applies_to_narrows_matching_but_leaves_total_intact if {
	rep := report(two_states, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_checks_are_conjunctive if {
	both := object.union(merged_only, {"on_main": {"op": "equals", "path": ["base_ref"], "value": "main"}})
	doc := {"items": [
		{"id": "a", "state": "MERGED", "base_ref": "main"},
		{"id": "b", "state": "MERGED", "base_ref": "topic"},
	]}
	rep := report(doc, scoped_req(both))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_excludes_subjects_whose_filtered_field_is_missing if {
	rep := report({"items": [{"id": "a"}]}, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
}

test_empty_applies_to_matches_everything if {
	rep := report(two_states, scoped_req({}))
	rep.requirements.s.subjects == {"total": 2, "matching": 2}
}

test_applies_to_is_evaluated_for_every_raw_subject if {
	rep := report(two_states, scoped_req(merged_only))
	verdicts := {r.subject.id: r.passed |
		some r in rep.results
		r.check == "$applies"
	}
	verdicts == {"a": true, "b": false}
}

test_applies_row_echoes_the_field_the_filter_read if {
	rep := report(two_states, scoped_req(merged_only))
	some r in rep.results
	r.check == "$applies"
	r.subject.id == "b"
	r.inputs == [{"name": "state", "value": "CLOSED"}]
}

test_applies_definition_renders_the_filter_expression if {
	rep := report(two_states, scoped_req(merged_only))
	rep.requirements.s.checks["$applies"].expression == `state == "MERGED"`
}

test_applies_definition_conjoins_multiple_filter_checks if {
	both := object.union(merged_only, {"on_main": {"op": "equals", "path": ["base_ref"], "value": "main"}})
	rep := report(two_states, scoped_req(both))

	rep.requirements.s.checks["$applies"].expression == `state == "MERGED" and base_ref == "main"`
}

test_no_applies_to_means_no_applies_rows_or_definition if {
	rep := report(two_states, id_req(["items"]))
	count([r | some r in rep.results; r.check == "$applies"]) == 0
	not "$applies" in object.keys(rep.requirements.s.checks)
}

test_out_of_scope_subject_gets_no_check_rows if {
	rep := report(two_states, scoped_req(merged_only))
	ids := {r.subject.id | some r in rep.results; r.check == "c"}
	ids == {"a"}
}

in_range := {"op": "range", "path": ["temp_c"], "min": 0, "max": 10}

test_range_inside if verdict({"temp_c": 5}, in_range) == true

test_range_at_lower_bound if verdict({"temp_c": 0}, in_range) == true

test_range_at_upper_bound if verdict({"temp_c": 10}, in_range) == true

test_range_below_bound if verdict({"temp_c": -1}, in_range) == false

test_range_above_bound if verdict({"temp_c": 11}, in_range) == false

test_range_rejects_numeric_string if verdict({"temp_c": "5"}, in_range) == false

test_range_rejects_missing_field if verdict({"other": 5}, in_range) == false

test_range_rejects_null if verdict({"temp_c": null}, in_range) == false

no_wip := {"op": "excludes", "path": ["labels"], "value": "wip"}

test_excludes_when_value_absent if verdict({"labels": ["ready"]}, no_wip) == true

test_excludes_over_empty_array if verdict({"labels": []}, no_wip) == true

test_excludes_when_value_present if verdict({"labels": ["ready", "wip"]}, no_wip) == false

test_excludes_rejects_non_array if verdict({"labels": "wip"}, no_wip) == false

test_excludes_rejects_missing_field if verdict({}, no_wip) == false

has_approved := {"op": "includes", "path": ["labels"], "value": "approved"}

test_includes_when_value_present if verdict({"labels": ["approved"]}, has_approved) == true

test_includes_when_value_absent if verdict({"labels": ["ready"]}, has_approved) == false

test_includes_over_empty_array if verdict({"labels": []}, has_approved) == false

test_includes_rejects_non_array if verdict({"labels": "approved"}, has_approved) == false

test_includes_rejects_missing_field if verdict({}, has_approved) == false

no_allergens := {"op": "excludes", "path": ["allergens"], "values": ["nuts", "garlic"]}

test_excludes_values_passes_when_the_field_holds_none_of_them if {
	verdict({"allergens": ["milk"]}, no_allergens) == true
	verdict({"allergens": []}, no_allergens) == true
}

test_excludes_values_fails_when_the_field_holds_any_one_of_them if {
	every allergens in [["garlic", "milk"], ["nuts"], ["nuts", "garlic"]] {
		[verdict({"allergens": allergens}, no_allergens), cause_of({"allergens": allergens}, no_allergens)] == [false, "value"]
	}
}

all_signed_off := {"op": "includes", "path": ["sign_offs"], "values": ["qa", "security"]}

test_includes_values_passes_when_the_field_holds_all_of_them if {
	verdict({"sign_offs": ["security", "qa"]}, all_signed_off) == true
	verdict({"sign_offs": ["qa", "legal", "security"]}, all_signed_off) == true
}

test_includes_values_fails_when_the_field_misses_any_one_of_them if {
	every sign_offs in [["qa"], ["security"], []] {
		[verdict({"sign_offs": sign_offs}, all_signed_off), cause_of({"sign_offs": sign_offs}, all_signed_off)] == [false, "value"]
	}
}

test_includes_and_excludes_take_a_list_of_values if {
	verdict({"sign_offs": ["security", "qa"]}, object.union(all_signed_off, {"values": ["qa", "security"]})) == true
	verdict({"allergens": ["garlic"]}, object.union(no_allergens, {"values": ["nuts", "garlic"]})) == false
}

test_includes_and_excludes_values_fail_closed_on_a_missing_null_or_wrong_typed_field if {
	every check in [no_allergens, all_signed_off] {
		field := check.path[0]
		[verdict({}, check), cause_of({}, check)] == [false, "absent"]
		[verdict({field: null}, check), cause_of({field: null}, check)] == [false, "null"]
		[verdict({field: "nuts"}, check), cause_of({field: "nuts"}, check)] == [false, "unusable"]
	}
}

test_empty_values_is_ill_formed_because_includes_and_excludes_would_pass_anything if {
	every op in ["includes", "excludes"] {
		every values in [[]] {
			check := {"op": op, "path": ["xs"], "values": values}
			[verdict({"xs": []}, check), cause_of({"xs": []}, check)] == [false, "ill_formed"]
		}
	}
}

test_values_that_is_not_a_list_is_ill_formed_for_includes_and_excludes if {
	every op in ["includes", "excludes"] {
		every values in ["nuts", {"a": "nuts"}, null, 1] {
			check := {"op": op, "path": ["xs"], "values": values}
			[verdict({"xs": ["nuts"]}, check), cause_of({"xs": ["nuts"]}, check)] == [false, "ill_formed"]
		}
	}
}

test_includes_and_excludes_take_value_or_values_but_not_both if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"both": {"op": "excludes", "path": ["xs"], "value": 2, "values": [3]},
		"neither": {"op": "includes", "path": ["xs"]},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.both", "value": ["both value and values"]},
		{"name": "checks.neither", "value": ["missing value or values"]},
	]
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"both", "neither"}] == [["both", false, "ill_formed"], ["neither", false, "ill_formed"]]
}

test_well_formed_says_when_the_values_of_includes_or_excludes_are_empty_or_not_a_list if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"empty": {"op": "excludes", "path": ["xs"], "values": []},
		"text": {"op": "includes", "path": ["xs"], "values": "nuts"},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.empty", "value": ["empty values"]},
		{"name": "checks.text", "value": ["invalid values"]},
	]
}

test_any_with_in_is_how_to_say_includes_any_of if {
	check := {"op": "any", "path": ["allergens"], "check": {"op": "in", "path": [], "values": ["nuts", "garlic"]}}
	verdict({"allergens": ["garlic", "milk"]}, check) == true
	[verdict({"allergens": ["milk"]}, check), cause_of({"allergens": ["milk"]}, check)] == [false, "value"]
	[verdict({"allergens": []}, check), cause_of({"allergens": []}, check)] == [false, "value"]
	rendered({"allergens": []}, check) == `some allergens: allergens[] in ["garlic", "nuts"]`
}

test_a_list_in_value_is_still_one_value_and_not_several if {
	check := {"op": "includes", "path": ["pairs"], "value": ["a", "b"]}
	verdict({"pairs": [["a", "b"]]}, check) == true
	verdict({"pairs": ["a", "b"]}, check) == false
}

allowed_licence := {"op": "in", "path": ["id"], "values": ["MIT", "Apache-2.0"]}

test_in_when_field_is_one_of_the_values if verdict({"id": "Apache-2.0"}, allowed_licence) == true

test_in_when_field_is_none_of_the_values if verdict({"id": "GPL-3.0"}, allowed_licence) == false

test_in_is_type_sensitive if verdict({"n": "1"}, {"op": "in", "path": ["n"], "values": [1, 2]}) == false

test_in_matches_numbers if verdict({"n": 2}, {"op": "in", "path": ["n"], "values": [1, 2]}) == true

test_in_fails_closed_on_a_missing_field if {
	verdict({}, allowed_licence) == false
	cause_of({}, allowed_licence) == "absent"
}

test_in_fails_closed_on_a_null_field if {
	verdict({"id": null}, allowed_licence) == false
	cause_of({"id": null}, allowed_licence) == "null"
}

test_in_does_not_match_a_null_field_against_null_in_values if {
	verdict({"id": null}, {"op": "in", "path": ["id"], "values": [null, "MIT"]}) == false
}

test_in_fails_closed_on_a_wrong_typed_field if verdict({"id": ["MIT"]}, allowed_licence) == false

test_in_fails_closed_without_values if verdict({"id": "MIT"}, {"op": "in", "path": ["id"]}) == false

test_in_fails_closed_on_null_values if verdict({"id": "MIT"}, {"op": "in", "path": ["id"], "values": null}) == false

test_in_fails_closed_when_values_is_not_a_list_or_set if {
	verdict({"id": "MIT"}, {"op": "in", "path": ["id"], "values": "MIT"}) == false
	verdict({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"licence": "MIT"}}) == false
}

test_in_fails_closed_on_empty_values if verdict({"id": "MIT"}, {"op": "in", "path": ["id"], "values": []}) == false

test_in_rejects_a_set_of_values_because_json_has_no_sets if {
	check := {"op": "in", "path": ["id"], "values": {"MIT", "Apache-2.0"}}
	[verdict({"id": "MIT"}, check), cause_of({"id": "MIT"}, check)] == [false, "ill_formed"]
}

licences_allowed := {"op": "all", "path": ["licences"], "check": allowed_licence}

test_in_checks_every_item_of_a_list if {
	verdict({"licences": [{"id": "MIT"}, {"id": "Apache-2.0"}]}, licences_allowed) == true
	verdict({"licences": [{"id": "MIT"}, {"id": "GPL-3.0"}]}, licences_allowed) == false
}

test_in_inside_all_shows_every_item_in_inputs if {
	inputs_of({"licences": [{"id": "MIT"}, {"id": "GPL-3.0"}]}, licences_allowed) == [{"name": "licences[].id", "value": ["MIT", "GPL-3.0"]}]
}

test_expression_for_in_inside_all if {
	rendered({"licences": []}, licences_allowed) == `every licences: id in ["Apache-2.0", "MIT"]`
}

test_in_shows_the_field_value_in_inputs if {
	inputs_of({"id": "GPL-3.0"}, allowed_licence) == [{"name": "id", "value": "GPL-3.0"}]
}

is_merged := {"op": "equals", "path": ["state"], "value": "MERGED"}

test_equals_on_match if verdict({"state": "MERGED"}, is_merged) == true

test_equals_on_mismatch if verdict({"state": "CLOSED"}, is_merged) == false

test_equals_rejects_missing_field if verdict({}, is_merged) == false

test_equals_is_type_sensitive if verdict({"n": "1"}, {"op": "equals", "path": ["n"], "value": 1}) == false

test_equals_compares_booleans if verdict({"verified": true}, {"op": "equals", "path": ["verified"], "value": true}) == true

test_equals_compares_nested_objects if {
	verdict({"a": {"b": [1, 2]}}, {"op": "equals", "path": ["a"], "value": {"b": [1, 2]}}) == true
}

test_equals_null_matches_an_explicit_null if {
	verdict({"x": null}, {"op": "equals", "path": ["x"], "value": null}) == true
}

has_fingerprint := {"op": "present", "path": ["fingerprint"]}

test_present_when_set if verdict({"fingerprint": "abc"}, has_fingerprint) == true

test_present_rejects_missing_field if verdict({}, has_fingerprint) == false

test_present_rejects_explicit_null if verdict({"fingerprint": null}, has_fingerprint) == false

test_present_accepts_empty_string if verdict({"fingerprint": ""}, has_fingerprint) == true

test_present_accepts_false if verdict({"fingerprint": false}, has_fingerprint) == true

filled := {"op": "non_empty_string", "path": ["fingerprint"]}

test_non_empty_string_when_filled if verdict({"fingerprint": "abc"}, filled) == true

test_non_empty_string_rejects_empty_string if verdict({"fingerprint": ""}, filled) == false

test_non_empty_string_rejects_number if verdict({"fingerprint": 42}, filled) == false

test_non_empty_string_rejects_null if verdict({"fingerprint": null}, filled) == false

test_non_empty_string_rejects_missing_field if verdict({}, filled) == false

no_fingerprint := {"op": "missing", "path": ["fingerprint"]}

test_missing_when_the_field_is_not_there if verdict({}, no_fingerprint) == true

test_missing_when_the_field_is_null if verdict({"fingerprint": null}, no_fingerprint) == true

test_missing_fails_as_value_when_the_field_is_set if {
	every v in ["abc", "", false, 0, [], {}] {
		[verdict({"fingerprint": v}, no_fingerprint), cause_of({"fingerprint": v}, no_fingerprint)] == [false, "value"]
	}
}

test_missing_passes_when_a_step_before_the_field_is_not_there_or_is_null if {
	check := {"op": "missing", "path": ["build", "fingerprint"]}
	verdict({}, check) == true
	verdict({"build": null}, check) == true
	verdict({"build": {}}, check) == true
}

test_missing_reads_past_the_end_of_a_list_as_missing if verdict({"xs": [1]}, {"op": "missing", "path": ["xs", 3]}) == true

test_missing_fails_as_unusable_when_a_step_before_the_field_cannot_hold_it if {
	every pair in [
		[{"build": "abc"}, ["build", "fingerprint"]],
		[{"build": 5}, ["build", "fingerprint"]],
		[{"build": ["abc"]}, ["build", "fingerprint"]],
		[{"build": {}}, ["build", 0]],
	] {
		[verdict(pair[0], {"op": "missing", "path": pair[1]}), cause_of(pair[0], {"op": "missing", "path": pair[1]})] == [false, "unusable"]
	}
}

test_missing_needs_a_selector_to_match_one_item_of_a_list_that_is_there if {
	check := {"op": "missing", "path": ["xs", {"where": {"k": 1}}, "v"]}
	verdict({"xs": [{"k": 1}]}, check) == true
	[verdict({"xs": [{"k": 2}]}, check), cause_of({"xs": [{"k": 2}]}, check)] == [false, "unmatched"]
	[verdict({"xs": [{"k": 1}, {"k": 1}]}, check), cause_of({"xs": [{"k": 1}, {"k": 1}]}, check)] == [false, "ambiguous"]
	verdict({}, check) == true
	verdict({"xs": null}, check) == true
}

presence_cases := [
	[{}, ["a"]],
	[{"a": null}, ["a"]],
	[{"a": 1}, ["a"]],
	[{"a": false}, ["a"]],
	[{}, ["a", "b"]],
	[{"a": null}, ["a", "b"]],
	[{"a": "x"}, ["a", "b"]],
	[{"a": [1]}, ["a", "b"]],
	[{"a": {}}, ["a", 0]],
	[{"a": [1]}, ["a", 3]],
	[{"a": [1]}, ["a", 0]],
	[{}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": null}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": "x"}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": []}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": [{"k": 1}, {"k": 1}]}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": [{"k": 1}]}, ["xs", {"where": {"k": 1}}, "v"]],
	[{"xs": [{"k": 1, "v": 2}]}, ["xs", {"where": {"k": 1}}, "v"]],
]

test_missing_is_the_opposite_of_present if {
	every case in presence_cases {
		present := cause_of(case[0], {"op": "present", "path": case[1]})
		missing := cause_of(case[0], {"op": "missing", "path": case[1]})
		opposite(present, missing)
	}
}

opposite("satisfied", "value")

opposite("value", "satisfied")

opposite(c, c) if not c in {"satisfied", "value"}

test_present_and_missing_fail_as_unusable_when_a_step_before_the_field_cannot_hold_it if {
	every case in [[{"a": "x"}, ["a", "b"]], [{"xs": "x"}, ["xs", {"where": {"k": 1}}, "v"]]] {
		cause_of(case[0], {"op": "present", "path": case[1]}) == "unusable"
		cause_of(case[0], {"op": "missing", "path": case[1]}) == "unusable"
	}
}

test_present_and_missing_fail_as_unusable_when_the_subject_cannot_hold_a_one_step_path if {
	every path in [[0], [3]] {
		cause_of({"a": 1}, {"op": "present", "path": path}) == "unusable"
		cause_of({"a": 1}, {"op": "missing", "path": path}) == "unusable"
	}
	cause_of({"a": 1}, {"op": "present", "path": ["b"]}) == "value"
	verdict({"a": 1}, {"op": "missing", "path": ["b"]}) == true
}

test_a_present_filter_cannot_rule_a_subject_out_when_a_step_before_the_field_cannot_hold_it if {
	rep := report({"items": [{"id": "a", "build": "abc"}]}, scoped_req({"built": {"op": "present", "path": ["build", "fingerprint"]}}))
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "unusable"]]
	rep.compliant == false
}

test_a_present_filter_still_rules_out_a_subject_whose_selector_has_no_list if {
	rep := report({"items": [{"id": "a"}]}, scoped_req({"f": {"op": "present", "path": ["xs", {"where": {"k": 1}}, "v"]}}))
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
}

test_missing_reads_names_given_by_as if {
	check := {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "missing", "path": ["$x", "b"]}}
	verdict({"xs": [{"a": 1}, {}]}, check) == true
	verdict({"xs": [{"a": 1}, {"b": 2}]}, check) == false
}

test_missing_fails_on_a_subject_that_is_not_an_object if {
	rep := report({"items": ["abc"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "missing", "path": ["v"]}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "not_an_object"]]
}

test_missing_with_an_empty_path_passes_only_on_a_null_item if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "missing", "path": []}}
	verdict({"xs": [null, null]}, check) == true
	verdict({"xs": [null, "a"]}, check) == false
}

no_commits := {"op": "empty", "path": ["commits"]}

test_empty_when_the_list_is_empty if verdict({"commits": []}, no_commits) == true

test_empty_fails_as_value_when_the_list_has_items if {
	[verdict({"commits": [null]}, no_commits), cause_of({"commits": [null]}, no_commits)] == [false, "value"]
}

test_empty_fails_when_the_list_is_missing_or_null if {
	[verdict({}, no_commits), cause_of({}, no_commits)] == [false, "absent"]
	[verdict({"commits": null}, no_commits), cause_of({"commits": null}, no_commits)] == [false, "null"]
}

test_empty_only_takes_a_list if {
	every v in ["", {}, 0, false] {
		[verdict({"commits": v}, no_commits), cause_of({"commits": v}, no_commits)] == [false, "unusable"]
	}
}

clean_labels := {"op": "any_of", "options": {
	"no_labels": [{"op": "missing", "path": ["labels"]}],
	"clean": [{"op": "excludes", "path": ["labels"], "value": "do-not-merge"}],
}}

test_missing_in_any_of_lets_a_missing_field_pass_a_check if {
	[verdict({}, clean_labels), verdict({"labels": ["ok"]}, clean_labels)] == [true, true]
	[verdict({"labels": ["do-not-merge"]}, clean_labels), cause_of({"labels": ["do-not-merge"]}, clean_labels)] == [false, "value"]
	[verdict({"labels": "do-not-merge"}, clean_labels), cause_of({"labels": "do-not-merge"}, clean_labels)] == [false, "unusable"]
	rendered({}, clean_labels) == `one of: clean(not contains(labels, "do-not-merge")) | no_labels(labels is missing)`
}

test_missing_in_any_of_keeps_a_subject_with_no_field_in_scope if {
	doc := {"items": [
		{"id": "a", "environment": "prod"},
		{"id": "b"},
		{"id": "c", "environment": "staging"},
	]}
	prod := {"prod": {"op": "any_of", "options": {
		"named": [{"op": "equals", "path": ["environment"], "value": "prod"}],
		"unset": [{"op": "missing", "path": ["environment"]}],
	}}}
	rep := report(doc, scoped_req(prod))
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [["a", true, "satisfied"], ["b", true, "satisfied"], ["c", false, "value"]]
	rep.compliant == true
}

test_a_missing_filter_rules_a_subject_with_the_field_out if {
	rep := report({"items": [{"id": "a", "draft": true}, {"id": "b"}]}, scoped_req({"final": {"op": "missing", "path": ["draft"]}}))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	rep.compliant == true
}

humans_with_usernames_only := {"op": "all", "path": ["approvers"], "check": {"op": "any_of", "options": {
	"human": [{"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]}],
	"skip": [{"op": "missing", "path": ["username"]}],
}}}

test_missing_skips_an_item_in_all_by_passing_it if {
	verdict({"approvers": [{"username": "ann"}, {}]}, humans_with_usernames_only) == true
	verdict({"approvers": [{"username": "renovate[bot]"}, {}]}, humans_with_usernames_only) == false
}

some_person := {"op": "any", "path": ["approvers"], "check": {"op": "any_of", "options": {"person": [
	{"op": "present", "path": ["username"]},
	{"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]},
]}}}

test_present_skips_an_item_in_any_by_failing_it_cleanly if {
	subj := {"approvers": [{"username": "renovate[bot]"}, {}]}
	[verdict(subj, some_person), cause_of(subj, some_person)] == [false, "value"]
	verdict({"approvers": [{"username": "ann"}, {}]}, some_person) == true
}

commits_signed_or_none := {"op": "any_of", "options": {
	"none": [{"op": "empty", "path": ["commits"]}],
	"signed": [{"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["signed"], "value": true}}],
}}

test_empty_in_any_of_lets_an_empty_list_pass_all if {
	verdict({"commits": []}, commits_signed_or_none) == true
	verdict({"commits": [{"signed": true}]}, commits_signed_or_none) == true
	[verdict({"commits": [{"signed": false}]}, commits_signed_or_none), cause_of({"commits": [{"signed": false}]}, commits_signed_or_none)] == [false, "value"]
	[verdict({}, commits_signed_or_none), cause_of({}, commits_signed_or_none)] == [false, "absent"]
}

compare_ab(op) := {"op": "compare", "cmp": op, "left": ["a"], "right": ["b"]}

test_compare_eq_when_equal if verdict({"a": 1, "b": 1}, compare_ab("eq")) == true

test_compare_eq_when_different if verdict({"a": 1, "b": 2}, compare_ab("eq")) == false

test_compare_ne_when_different if verdict({"a": 1, "b": 2}, compare_ab("ne")) == true

test_compare_ne_when_equal if verdict({"a": 1, "b": 1}, compare_ab("ne")) == false

test_compare_gt_when_greater if verdict({"a": 2, "b": 1}, compare_ab("gt")) == true

test_compare_gt_when_equal if verdict({"a": 1, "b": 1}, compare_ab("gt")) == false

test_compare_gte_when_equal if verdict({"a": 1, "b": 1}, compare_ab("gte")) == true

test_compare_lt_when_less if verdict({"a": 1, "b": 2}, compare_ab("lt")) == true

test_compare_lt_when_equal if verdict({"a": 1, "b": 1}, compare_ab("lt")) == false

test_compare_lte_when_equal if verdict({"a": 1, "b": 1}, compare_ab("lte")) == true

test_compare_compares_strings if verdict({"a": "abc", "b": "abd"}, compare_ab("lt")) == true

test_compare_rejects_unknown_cmp if verdict({"a": 1, "b": 1}, compare_ab("congruent")) == false

test_compare_rejects_missing_cmp if {
	verdict({"a": 1, "b": 1}, {"op": "compare", "left": ["a"], "right": ["b"]}) == false
}

attestations_array := {"attestations": [
	{"attestation_type": "unit_test", "payload": "wrong"},
	{"attestation_type": "pull_request", "payload": "right"},
]}

attestations_map := {"attestations": {
	"a-unit": {"attestation_type": "unit_test", "payload": "wrong"},
	"a-pr": {"attestation_type": "pull_request", "payload": "right"},
}}

pr_payload := {
	"op": "equals",
	"path": ["attestations", {"where": {"attestation_type": "pull_request"}}, "payload"],
	"value": "right",
}

test_selector_picks_from_an_array if verdict(attestations_array, pr_payload) == true

test_selector_picks_from_a_map if verdict(attestations_map, pr_payload) == true

test_selector_reads_the_selected_element_not_a_sibling if {
	check := object.union(pr_payload, {"value": "wrong"})
	verdict(attestations_array, check) == false
	verdict(attestations_map, check) == false
}

test_selector_fails_closed_when_nothing_matches if {
	doc := {"attestations": [{"attestation_type": "unit_test", "payload": "right"}]}
	verdict(doc, pr_payload) == false
}

test_selector_fails_closed_when_two_elements_match if {
	doc := {"attestations": [
		{"attestation_type": "pull_request", "payload": "right"},
		{"attestation_type": "pull_request", "payload": "right"},
	]}
	verdict(doc, pr_payload) == false
}

test_selector_fails_closed_on_a_missing_collection if verdict({}, pr_payload) == false

test_selector_fails_closed_on_a_scalar_collection if {
	verdict({"attestations": "not-a-collection"}, pr_payload) == false
}

test_selector_fails_closed_on_an_empty_where if {
	check := object.union(pr_payload, {"path": ["attestations", {"where": {}}, "payload"]})
	verdict(attestations_array, check) == false
}

test_selector_matches_on_every_named_field if {
	doc := {"attestations": [
		{"attestation_type": "pull_request", "status": "COMPLETE", "payload": "right"},
		{"attestation_type": "pull_request", "status": "PENDING", "payload": "wrong"},
	]}
	check := {
		"op": "equals",
		"path": ["attestations", {"where": {"attestation_type": "pull_request", "status": "COMPLETE"}}, "payload"],
		"value": "right",
	}
	verdict(doc, check) == true
}

test_selector_can_end_a_path if {
	check := {"op": "present", "path": ["attestations", {"where": {"attestation_type": "pull_request"}}]}
	verdict(attestations_array, check) == true
	verdict(attestations_map, check) == true
}

test_selector_preserves_the_absent_distinction if {
	explicit := {"attestations": [{"attestation_type": "pull_request", "payload": null}]}
	missing := {"attestations": [{"attestation_type": "pull_request"}]}
	null_check := object.union(pr_payload, {"value": null})
	verdict(explicit, null_check) == true
	verdict(missing, null_check) == false
}

test_selector_expression_is_order_independent if {
	one := {
		"op": "equals",
		"path": ["attestations", {"where": {"attestation_type": "pull_request", "status": "COMPLETE"}}, "payload"],
		"value": "right",
	}
	two := {
		"op": "equals",
		"path": ["attestations", {"where": {"status": "COMPLETE", "attestation_type": "pull_request"}}, "payload"],
		"value": "right",
	}
	rendered(attestations_array, one) == rendered(attestations_array, two)
	rendered(attestations_array, one) == `attestations.[attestation_type=="pull_request" and status=="COMPLETE"].payload == "right"`
}

test_selector_value_is_echoed_in_the_row if {
	report := solo(attestations_array, pr_payload)
	some r in report.results
	r.check == "c"
	r.inputs == [{
		"name": `attestations.[attestation_type=="pull_request"].payload`,
		"value": "right",
	}]
}

service_accounts := ["svc_.*", `.*\[bot\]`, `noreply@github\.com`]

matches(op) := {"op": op, "path": ["author"], "patterns": service_accounts}

test_matches_any_matches_a_prefix_pattern if {
	verdict({"author": "svc_release <svc_release@example.com>"}, matches("matches_any")) == true
}

test_matches_any_matches_a_bracketed_bot if {
	verdict({"author": "dependabot[bot]"}, matches("matches_any")) == true
}

test_matches_any_is_unanchored if {
	verdict({"author": "GitHub <noreply@github.com>"}, matches("matches_any")) == true
}

test_matches_any_rejects_a_human if {
	verdict({"author": "Alice <alice@example.com>"}, matches("matches_any")) == false
}

test_not_matches_any_is_the_complement if {
	verdict({"author": "Alice <alice@example.com>"}, matches("not_matches_any")) == true
	verdict({"author": "dependabot[bot]"}, matches("not_matches_any")) == false
}

test_matching_fails_closed_on_a_missing_field if {
	verdict({}, matches("matches_any")) == false
	verdict({}, matches("not_matches_any")) == false
}

test_matching_fails_closed_on_a_non_string_field if {
	verdict({"author": 42}, matches("matches_any")) == false
	verdict({"author": ["Alice"]}, matches("not_matches_any")) == false
}

test_not_matches_any_fails_closed_on_a_non_string_pattern if {
	check := {"op": "not_matches_any", "path": ["author"], "patterns": ["svc_.*", 42]}
	verdict({"author": "Alice <alice@example.com>"}, check) == false
}

test_matches_any_fails_on_a_non_string_pattern_even_when_another_matches if {
	check := {"op": "matches_any", "path": ["author"], "patterns": ["svc_.*", 42]}
	verdict({"author": "svc_bot"}, check) == false
	cause_of({"author": "svc_bot"}, check) == "ill_formed"
}

test_matching_with_no_patterns if {
	verdict({"author": "Alice"}, {"op": "matches_any", "path": ["author"], "patterns": []}) == false
	verdict({"author": "Alice"}, {"op": "not_matches_any", "path": ["author"], "patterns": []}) == true
}

test_expression_for_matching_sorts_patterns if {
	rendered({"author": "Alice"}, matches("not_matches_any")) == sprintf(
		"author matches none of [%s]",
		[`".*\\[bot\\]", "noreply@github\\.com", "svc_.*"`],
	)
}

compare_time_span(op) := {"op": "compare_time", "cmp": op, "left": ["start"], "right": ["end"]}

span := {"start": "2024-01-01T00:00:00Z", "end": "2024-06-01T00:00:00Z"}

test_compare_time_lt if verdict(span, compare_time_span("lt")) == true

test_compare_time_gt if verdict(span, compare_time_span("gt")) == false

test_compare_time_normalises_offsets if {
	doc := {"start": "2024-01-01T12:00:00Z", "end": "2024-01-01T13:00:00+01:00"}
	verdict(doc, compare_time_span("eq")) == true
}

test_compare_time_respects_sub_second_precision if {
	doc := {"start": "2024-01-01T00:00:00.000000001Z", "end": "2024-01-01T00:00:00.000000002Z"}
	verdict(doc, compare_time_span("lt")) == true
}

test_compare_time_rejects_malformed_timestamp if {
	verdict({"start": "yesterday", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_fails_on_a_date_that_does_not_exist_rather_than_rolling_it_over if {
	verdict({"start": "2024-02-30T00:00:00Z", "end": "2024-03-01T00:00:01Z"}, compare_time_span("lt")) == false
	verdict({"start": "2023-02-29T00:00:00Z", "end": "2023-03-01T00:00:01Z"}, compare_time_span("lt")) == false
}

test_compare_time_fails_on_a_lowercase_t_or_z if {
	verdict({"start": "2024-01-01t00:00:00Z", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "2024-01-01T00:00:00z", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_only_reads_years_from_1678_to_2261_so_nanoseconds_since_1970_always_fit if {
	verdict({"start": "1678-01-01T00:00:00Z", "end": "2261-12-31T23:59:59Z"}, compare_time_span("lt")) == true
	verdict({"start": "1677-12-31T23:59:59Z", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "2024-01-01T00:00:00Z", "end": "2262-01-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "0999-01-01T00:00:00Z", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_knows_which_years_have_a_29th_of_february if {
	verdict({"start": "2024-02-29T00:00:00Z", "end": "2024-03-01T00:00:00Z"}, compare_time_span("lt")) == true
	verdict({"start": "2000-02-29T00:00:00Z", "end": "2000-03-01T00:00:00Z"}, compare_time_span("lt")) == true
	verdict({"start": "1900-02-29T00:00:00Z", "end": "1900-03-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "2023-04-31T00:00:00Z", "end": "2023-05-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "2023-12-31T00:00:00Z", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == true
}

test_compare_time_rejects_an_out_of_range_month if {
	verdict({"start": "2024-13-01T00:00:00Z", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_date_without_a_time if {
	verdict({"start": "2024-01-01", "end": "2024-06-01"}, compare_time_span("lt")) == false
}

test_rfc3339_gate_accepts_valid_timestamps if {
	every ts in [
		"2024-01-01T00:00:00Z",
		"2024-06-30T23:59:59.999999999Z",
		"2024-06-30T12:00:00+02:00",
		"2024-06-30T12:00:00-05:30",
	] {
		ergo._rfc3339_shaped(ts)
	}
}

test_rfc3339_gate_rejects_everything_else if {
	every ts in [
		"yesterday",
		"",
		"2024-01-01",
		"2024-01-01T00:00:00z",
		"2024-01-01t00:00:00Z",
		"2024-02-30T00:00:00Z",
		"1677-12-31T23:59:59Z",
		"2262-01-01T00:00:00Z",
		"2024-13-01T00:00:00Z",
		"2024-00-01T00:00:00Z",
		"2024-01-32T00:00:00Z",
		"2024-01-01T24:00:00Z",
		"2024-01-01T00:60:00Z",
		"2024-12-31T23:59:60Z",
		"2024-01-01T00:00:00",
		"2024-01-01T00:00:00+24:00",
		"24-01-01T00:00:00Z",
		1753600000,
		null,
		true,
		["2024-01-01T00:00:00Z"],
	] {
		not ergo._rfc3339_shaped(ts)
	}
}

test_compare_time_accepts_epoch_seconds if {
	verdict({"start": 1753600000, "end": 1753603600}, compare_time_span("lt")) == true
}

test_compare_time_orders_epoch_seconds if {
	verdict({"start": 1753603600, "end": 1753600000}, compare_time_span("lt")) == false
	verdict({"start": 1753603600, "end": 1753600000}, compare_time_span("gt")) == true
}

test_compare_time_compares_equal_epochs if {
	verdict({"start": 1753600000, "end": 1753600000}, compare_time_span("eq")) == true
}

test_compare_time_rejects_mixed_formats if {
	verdict({"start": 1753600000, "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
	verdict({"start": "2024-01-01T00:00:00Z", "end": 1753600000}, compare_time_span("lt")) == false
}

test_compare_time_rejects_non_numeric_scalars if {
	verdict({"start": true, "end": 1753600000}, compare_time_span("lt")) == false
	verdict({"start": 1753600000, "end": null}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_missing_side if {
	verdict({"end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

all_verified := {
	"op": "all",
	"path": ["commits"],
	"check": {"op": "equals", "path": ["verified"], "value": true},
}

any_approved := {
	"op": "any",
	"path": ["approvers"],
	"check": {"op": "equals", "path": ["state"], "value": "APPROVED"},
}

test_all_when_every_element_passes if {
	verdict({"commits": [{"verified": true}, {"verified": true}]}, all_verified) == true
}

test_all_when_one_element_fails if {
	verdict({"commits": [{"verified": true}, {"verified": false}]}, all_verified) == false
}

test_all_when_an_element_is_missing_the_field if {
	verdict({"commits": [{"verified": true}, {"sha1": "abc"}]}, all_verified) == false
}

test_all_rejects_non_array if verdict({"commits": "none"}, all_verified) == false

test_all_rejects_missing_path if verdict({}, all_verified) == false

test_all_rejects_object_collection if {
	verdict({"commits": {"a": {"verified": true}}}, all_verified) == false
}

test_all_without_a_nested_check_fails if {
	verdict({"commits": [{"verified": true}]}, {"op": "all", "path": ["commits"]}) == false
}

test_any_when_one_element_passes if {
	verdict({"approvers": [{"state": "COMMENTED"}, {"state": "APPROVED"}]}, any_approved) == true
}

test_any_when_no_element_passes if {
	verdict({"approvers": [{"state": "COMMENTED"}]}, any_approved) == false
}

test_any_over_empty_collection if verdict({"approvers": []}, any_approved) == false

test_any_rejects_missing_path if verdict({}, any_approved) == false

test_any_without_a_nested_check_fails if {
	verdict({"approvers": [{"state": "APPROVED"}]}, {"op": "any", "path": ["approvers"]}) == false
}

every_commit_signed := {
	"op": "all",
	"path": ["prs"],
	"each": ["commits"],
	"check": {"op": "equals", "path": ["signed"], "value": true},
}

any_commit_signed := {
	"op": "any",
	"path": ["prs"],
	"each": ["commits"],
	"check": {"op": "equals", "path": ["signed"], "value": true},
}

test_each_passes_when_every_element_of_every_inner_collection_passes if {
	verdict(
		{"prs": [{"commits": [{"signed": true}]}, {"commits": [{"signed": true}, {"signed": true}]}]},
		every_commit_signed,
	) == true
}

test_each_fails_when_one_element_of_one_inner_collection_fails if {
	verdict(
		{"prs": [{"commits": [{"signed": true}]}, {"commits": [{"signed": true}, {"signed": false}]}]},
		every_commit_signed,
	) == false
}

test_each_rejects_a_missing_inner_collection if {
	verdict({"prs": [{"commits": [{"signed": true}]}, {"url": "u"}]}, every_commit_signed) == false
}

test_each_rejects_an_empty_inner_collection if {
	verdict({"prs": [{"commits": [{"signed": true}]}, {"commits": []}]}, every_commit_signed) == false
}

test_each_rejects_a_non_array_inner_collection if {
	verdict({"prs": [{"commits": "none"}]}, every_commit_signed) == false
}

test_each_rejects_an_empty_outer_collection if {
	verdict({"prs": []}, every_commit_signed) == false
}

test_each_rejects_a_missing_outer_collection if verdict({}, every_commit_signed) == false

test_each_under_any_passes_when_one_element_anywhere_passes if {
	verdict(
		{"prs": [{"commits": [{"signed": false}]}, {"commits": [{"signed": true}]}]},
		any_commit_signed,
	) == true
}

test_each_under_any_fails_when_no_element_passes if {
	verdict({"prs": [{"commits": [{"signed": false}]}]}, any_commit_signed) == false
}

identified := {
	"op": "all",
	"path": ["prs"],
	"each": ["commits"],
	"check": {"op": "any_of", "options": {
		"linked_account": [{"op": "non_empty_string", "path": ["author_username"]}],
		"web_flow": [{"op": "matches_any", "path": ["author"], "patterns": [`noreply@github\.com`]}],
	}},
}

test_an_any_of_element_check_passes_per_element_on_either_option if {
	verdict(
		{"prs": [{"commits": [
			{"author_username": "alice"},
			{"author": "GitHub <noreply@github.com>"},
		]}]},
		identified,
	) == true
}

test_an_any_of_element_check_fails_when_an_element_satisfies_neither_option if {
	verdict(
		{"prs": [{"commits": [
			{"author_username": "alice"},
			{"author_username": null, "author": "Bob <bob@example.com>"},
		]}]},
		identified,
	) == false
}

test_an_any_of_element_check_is_also_available_without_each if {
	verdict({"commits": [{"author_username": "alice"}]}, {
		"op": "all",
		"path": ["commits"],
		"check": {"op": "any_of", "options": {
			"linked_account": [{"op": "non_empty_string", "path": ["author_username"]}],
		}},
	}) == true
}

test_each_renders_the_projection_in_the_expression if {
	rendered({"prs": []}, every_commit_signed) == "every prs[].commits: signed == true"
}

test_each_renders_an_any_of_element_check if {
	rendered({"prs": []}, identified) == sprintf(
		"every prs[].commits: one of: %s | %s",
		[
			"linked_account(author_username is a non-empty string)",
			`web_flow(author matches one of ["noreply@github\\.com"])`,
		],
	)
}

test_each_echoes_the_inner_collections if {
	inputs_of({"prs": [{"commits": [{"signed": true}]}, {"commits": []}]}, every_commit_signed) == [{
		"name": "prs[].commits",
		"value": [[{"signed": true}], []],
	}]
}

release_branches := {
	"op": "all",
	"path": ["branches"],
	"check": {"op": "matches_any", "path": [], "patterns": ["^main$", "^release/"]},
}

test_an_empty_path_reads_a_string_item_itself if {
	verdict({"branches": ["main", "release/1"]}, release_branches) == true
	verdict({"branches": ["main", "feature"]}, release_branches) == false
}

test_an_empty_path_reads_a_number_item_itself if {
	verdict({"ns": [1, 2]}, {"op": "any", "path": ["ns"], "check": {"op": "equals", "path": [], "value": 2}}) == true
}

test_an_empty_path_reads_a_list_item_itself if {
	check := {"op": "all", "path": ["groups"], "check": {"op": "includes", "path": [], "value": "a"}}
	verdict({"groups": [["a"], ["a", "b"]]}, check) == true
	verdict({"groups": [["a"], ["b"]]}, check) == false
}

test_an_empty_path_still_reads_an_object_item_whole if {
	check := {"op": "all", "path": ["items"], "check": {"op": "equals", "path": [], "value": {"a": 1}}}
	verdict({"items": [{"a": 1}]}, check) == true
}

test_an_empty_path_fails_closed_on_a_null_item if {
	verdict({"branches": ["main", null]}, release_branches) == false
	verdict({"branches": [null]}, {"op": "all", "path": ["branches"], "check": {"op": "present", "path": []}}) == false
}

test_an_empty_path_names_the_item_after_its_list_in_inputs if {
	inputs_of({"branches": ["main", "feature"]}, release_branches) == [{"name": "branches[]", "value": ["main", "feature"]}]
}

test_an_empty_path_names_the_item_after_its_list_in_the_expression if {
	rendered({"branches": []}, release_branches) == `every branches: branches[] matches one of ["^main$", "^release/"]`
}

test_an_empty_path_names_the_item_inside_an_any_of if {
	rendered({"branches": []}, {"op": "all", "path": ["branches"], "check": {"op": "any_of", "options": {
		"main": [{"op": "equals", "path": [], "value": "main"}],
		"release": [{"op": "matches_any", "path": [], "patterns": ["^release/"]}],
	}}}) == `every branches: one of: main(branches[] == "main") | release(branches[] matches one of ["^release/"])`
}

test_an_empty_path_names_the_item_of_a_compare if {
	rendered({"pairs": []}, {"op": "all", "path": ["pairs"], "check": {"op": "compare", "cmp": "eq", "left": [], "right": [0]}}) == "every pairs: pairs[] eq [0]"
}

test_an_inner_check_without_a_path_names_the_item_after_its_list if {
	check := {"op": "all", "path": ["pairs"], "check": {"op": "compare", "cmp": "eq", "left": ["a"], "right": ["b"]}}
	inputs_of({"pairs": [{"a": 1, "b": 1}]}, check) == [{"name": "pairs[]", "value": [{"a": 1, "b": 1}]}]
}

branch_req(check) := {"s": {"from": ["branches"], "checks": {"c": check}}}

on_main := {"op": "matches_any", "path": [], "patterns": ["^main$"]}

branch_rows(check) := [[r.subject.id, r.passed, r.cause] |
	some r in rows_for(report({"branches": ["main", "feature", null]}, branch_req(check)), "s", "c")
]

test_an_empty_path_reads_a_subject_that_is_not_an_object if {
	branch_rows(on_main) == [["main", true, "satisfied"], ["feature", false, "value"], [null, false, "null"]]
}

test_a_field_path_on_a_subject_that_is_not_an_object_is_still_not_an_object if {
	branch_rows({"op": "present", "path": ["name"]}) == [
		["main", false, "not_an_object"],
		["feature", false, "not_an_object"],
		[null, false, "not_an_object"],
	]
}

test_an_empty_path_on_a_subject_is_named_after_from if {
	rep := report({"branches": ["main"]}, branch_req(on_main))
	rep.requirements.s.checks.c.expression == `branches[] matches one of ["^main$"]`
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "branches[]", "value": "main"}]]
}

test_an_empty_path_on_the_whole_input_is_named_dollar_input if {
	rep := report({"state": "ok"}, {"s": {"checks": {"c": {"op": "present", "path": []}}}})
	rep.requirements.s.checks.c.expression == "$input is present"
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "$input", "value": {"state": "ok"}}]]
}

test_the_whole_input_is_not_named_like_a_key_called_input if {
	rep := report({"input": "inner"}, {"s": {"checks": {"c": {"op": "any_of", "options": {
		"a": [{"op": "present", "path": []}],
		"b": [{"op": "present", "path": ["input"]}],
	}}}}})
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[
		{"name": "$input", "value": {"input": "inner"}},
		{"name": "input", "value": "inner"},
	]]
}

test_an_empty_path_on_a_subject_is_named_after_from_in_every_kind_of_check if {
	rep := report({"branches": ["main"]}, {"s": {
		"from": ["branches"],
		"applies_to": {"named": {"op": "non_empty_string", "path": []}},
		"checks": {
			"either": {"op": "any_of", "options": {"main": [{"op": "equals", "path": [], "value": "main"}]}},
			"same": {"op": "compare", "cmp": "eq", "left": [], "right": []},
			"custom": {"op": "bespoke", "inputs": [[]], "expression": "bespoke"},
			"backed": {"op": "equals", "path": [], "value": "x", "substitute": {"op": "present", "path": []}},
		},
	}})
	rep.requirements.s.checks["$applies"].expression == "branches[] is a non-empty string"
	rep.requirements.s.checks.either.expression == `one of: main(branches[] == "main")`
	rep.requirements.s.checks.same.expression == "branches[] eq branches[]"
	rep.requirements.s.checks.backed.expression == `branches[] == "x", or substitute: branches[] is present`
	{r.check: r.inputs | some r in rep.results; r.subject.id == "main"} == {
		"$applies": [{"name": "branches[]", "value": "main"}],
		"either": [{"name": "branches[]", "value": "main"}],
		"same": [{"name": "branches[]", "value": "main"}, {"name": "branches[]", "value": "main"}],
		"custom": [{"name": "branches[]", "value": "main"}],
		"backed": [{"name": "branches[]", "value": "main"}],
	}
}

plain_licences := {"op": "all", "path": ["licences"], "check": {"op": "in", "path": [], "values": ["MIT", "Apache-2.0"]}}

test_in_checks_a_list_of_plain_strings if {
	verdict({"licences": ["MIT", "Apache-2.0"]}, plain_licences) == true
	verdict({"licences": ["MIT", "GPL-3.0"]}, plain_licences) == false
	rendered({"licences": []}, plain_licences) == `every licences: licences[] in ["Apache-2.0", "MIT"]`
}

test_in_checks_subjects_that_are_plain_strings if {
	branch_rows({"op": "in", "path": [], "values": ["main", "develop"]}) == [
		["main", true, "satisfied"],
		["feature", false, "value"],
		[null, false, "null"],
	]
}

nested_branches := {
	"op": "all",
	"path": ["repos"],
	"each": [],
	"check": {"op": "equals", "path": [], "value": "main"},
}

test_an_empty_each_reads_lists_of_lists if {
	verdict({"repos": [["main"], ["main", "main"]]}, nested_branches) == true
	verdict({"repos": [["main"], ["feature"]]}, nested_branches) == false
}

test_an_empty_each_is_named_after_its_list if {
	rendered({"repos": []}, nested_branches) == `every repos[]: repos[][] == "main"`
	inputs_of({"repos": [["main"]]}, nested_branches) == [{"name": "repos[]", "value": [["main"]]}]
}

test_a_custom_input_with_an_empty_each_reads_every_item if {
	check := {"op": "bespoke", "inputs": [{"path": ["tags"], "each": []}]}
	inputs_of({"tags": ["a", "b"]}, check) == [{"name": "tags[]", "value": ["a", "b"]}]
}

flavoured := {
	"op": "any_of",
	"options": {
		"standard": [
			{"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]},
			{"op": "matches_any", "path": ["state"], "patterns": ["^CLOSED$"]},
		],
		"safe": [
			{"op": "matches_any", "path": ["type"], "patterns": ["^SAFe Story$"]},
			{"op": "matches_any", "path": ["state"], "patterns": ["^DONE$"]},
		],
	},
}

test_any_of_passes_when_one_option_is_wholly_satisfied if {
	verdict({"type": "Story", "state": "CLOSED"}, flavoured) == true
}

test_any_of_passes_on_any_of_the_options_not_just_the_first if {
	verdict({"type": "SAFe Story", "state": "DONE"}, flavoured) == true
}

test_any_of_rejects_a_cross_product_of_two_options if {
	verdict({"type": "Story", "state": "DONE"}, flavoured) == false
}

test_any_of_rejects_when_no_option_matches_either_field if {
	verdict({"type": "Chore", "state": "OPEN"}, flavoured) == false
}

test_any_of_rejects_a_subject_missing_one_of_the_fields if {
	verdict({"type": "Story"}, flavoured) == false
}

test_any_of_fails_closed_on_empty_options if {
	verdict({"type": "Story"}, {"op": "any_of", "options": {}}) == false
}

test_any_of_fails_closed_on_an_empty_option_group if {
	verdict({"type": "Story"}, {"op": "any_of", "options": {"empty": []}}) == false
}

test_any_of_fails_closed_on_a_group_that_is_not_an_array if {
	verdict(
		{"type": "Story"},
		{"op": "any_of", "options": {"bad": {"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]}}},
	) == false
}

test_any_of_rejects_an_option_group_written_as_an_object_of_checks if {
	verdict({"type": "Story", "state": "CLOSED"}, {"op": "any_of", "options": {"standard": {
		"by_type": {"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]},
		"by_state": {"op": "matches_any", "path": ["state"], "patterns": ["^CLOSED$"]},
	}}}) == false
}

test_any_of_fails_closed_on_an_unknown_leaf_op_inside_an_option if {
	verdict(
		{"type": "Story"},
		{"op": "any_of", "options": {"standard": [{"op": "no_such_op", "path": ["type"]}]}},
	) == false
}

test_any_of_one_bad_leaf_sinks_its_whole_option if {
	verdict(
		{"type": "Story", "state": "CLOSED"},
		{"op": "any_of", "options": {"standard": [
			{"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]},
			{"op": "no_such_op", "path": ["state"]},
		]}},
	) == false
}

test_any_of_accepts_options_as_an_array if {
	verdict({"type": "Story", "state": "CLOSED"}, {"op": "any_of", "options": [[
		{"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]},
		{"op": "matches_any", "path": ["state"], "patterns": ["^CLOSED$"]},
	]]}) == true
}

test_any_of_with_single_leaf_options_is_a_plain_disjunction if {
	single := {"op": "any_of", "options": {
		"by_type": [{"op": "equals", "path": ["type"], "value": "Story"}],
		"by_state": [{"op": "equals", "path": ["state"], "value": "DONE"}],
	}}
	verdict({"type": "Story", "state": "OPEN"}, single) == true
	verdict({"type": "Chore", "state": "DONE"}, single) == true
	verdict({"type": "Chore", "state": "OPEN"}, single) == false
}

test_any_of_can_scope_a_requirement if {
	rep := report(
		{"items": [
			{"id": "a", "type": "Story", "state": "CLOSED"},
			{"id": "b", "type": "Story", "state": "DONE"},
		]},
		{"s": {
			"subject_type": "thing",
			"from": ["items"],
			"id": ["id"],
			"applies_to": {"in_a_flavour": flavoured},
			"checks": {"c": {"op": "present", "path": ["id"]}},
		}},
	)
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_any_of_renders_each_option_named if {
	rendered({"type": "Story"}, flavoured) == concat("", [
		"one of: ",
		`safe(type matches one of ["^SAFe Story$"] and state matches one of ["^DONE$"])`,
		" | ",
		`standard(type matches one of ["^Story$"] and state matches one of ["^CLOSED$"])`,
	])
}

test_any_of_rendering_is_order_independent if {
	reordered := {"op": "any_of", "options": {
		"safe": [
			{"op": "matches_any", "path": ["type"], "patterns": ["^SAFe Story$"]},
			{"op": "matches_any", "path": ["state"], "patterns": ["^DONE$"]},
		],
		"standard": [
			{"op": "matches_any", "path": ["type"], "patterns": ["^Story$"]},
			{"op": "matches_any", "path": ["state"], "patterns": ["^CLOSED$"]},
		],
	}}
	rendered({"type": "Story"}, reordered) == rendered({"type": "Story"}, flavoured)
}

test_any_of_renders_an_empty_option_group_instead_of_dropping_it if {
	rendered({}, {"op": "any_of", "options": {"standard": []}}) == "one of: standard(<empty option>)"
	rendered({}, {"op": "any_of", "options": {}}) == "one of: <empty options>"
}

test_any_of_echoes_every_field_it_read_once_each if {
	inputs_of({"type": "Story", "state": "DONE"}, flavoured) == [
		{"name": "state", "value": "DONE"},
		{"name": "type", "value": "Story"},
	]
}

test_any_of_echoes_a_field_only_one_option_reads if {
	check := {"op": "any_of", "options": {
		"a": [{"op": "equals", "path": ["type"], "value": "Story"}],
		"b": [{"op": "equals", "path": ["project"], "value": "PA"}],
	}}
	inputs_of({"type": "Chore", "project": "PA"}, check) == [
		{"name": "project", "value": "PA"},
		{"name": "type", "value": "Chore"},
	]
}

test_any_of_echoes_both_sides_of_a_two_sided_leaf if {
	check := {"op": "any_of", "options": {"a": [{
		"op": "compare",
		"cmp": "gt",
		"left": ["approved_at"],
		"right": ["committed_at"],
	}]}}
	inputs_of({"approved_at": 200, "committed_at": 100}, check) == [
		{"name": "approved_at", "value": 200},
		{"name": "committed_at", "value": 100},
	]
}

test_any_of_echoes_an_absent_field_as_null if {
	inputs_of({"type": "Story"}, flavoured) == [
		{"name": "state", "value": null},
		{"name": "type", "value": "Story"},
	]
}

reviewed_or_verified := {
	"description": "Reviewed in a pull request",
	"op": "equals",
	"path": ["reviewed"],
	"value": true,
	"substitute": {
		"description": "Attested by a verified committer",
		"op": "equals",
		"path": ["verified_committer"],
		"value": true,
	},
}

test_a_check_passes_on_its_substitute if {
	verdict({"verified_committer": true}, reviewed_or_verified) == true
}

test_a_substituted_row_says_so if {
	cause_of({"verified_committer": true}, reviewed_or_verified) == "substituted"
}

test_a_check_that_holds_on_its_own_terms_is_not_substituted if {
	cause_of({"reviewed": true, "verified_committer": true}, reviewed_or_verified) == "satisfied"
}

test_a_check_fails_when_neither_it_nor_its_substitute_holds if {
	verdict({"reviewed": false, "verified_committer": false}, reviewed_or_verified) == false
}

test_a_failing_row_reports_the_state_of_its_own_paths if {
	cause_of({"verified_committer": false}, reviewed_or_verified) == "absent"
}

test_a_substitute_is_evaluated_by_the_same_operators if {
	verdict({"approvals": ["alice"]}, {
		"op": "equals",
		"path": ["reviewed"],
		"value": true,
		"substitute": {"op": "includes", "path": ["approvals"], "value": "alice"},
	}) == true
}

test_a_substitute_of_a_substitute_is_ignored if {
	verdict({"third": true}, {
		"op": "equals",
		"path": ["first"],
		"value": true,
		"substitute": {
			"op": "equals",
			"path": ["second"],
			"value": true,
			"substitute": {"op": "equals", "path": ["third"], "value": true},
		},
	}) == false
}

test_a_substituted_check_satisfies_its_requirement if {
	rep := report(
		{"items": [{"id": "a", "reviewed": true}, {"id": "b", "verified_committer": true}]},
		{"s": {
			"subject_type": "thing",
			"from": ["items"],
			"id": ["id"],
			"checks": {"c": reviewed_or_verified},
		}},
	)
	rep.compliant == true
	ergo.violations(rep) == []
}

test_a_substitute_on_an_element_check_is_ignored if {
	check := {"op": "all", "path": ["commits"], "check": {
		"op": "equals", "path": ["signed"], "value": true,
		"substitute": {"op": "equals", "path": ["exempt"], "value": true},
	}}
	verdict({"commits": [{"exempt": true}]}, check) == false
}

test_a_substitute_on_a_leaf_inside_any_of_is_ignored if {
	check := {"op": "any_of", "options": {"only": [{
		"op": "equals", "path": ["signed"], "value": true,
		"substitute": {"op": "equals", "path": ["exempt"], "value": true},
	}]}}
	verdict({"exempt": true}, check) == false
}

test_a_substitute_works_in_an_applies_to_filter if {
	rep := report({"items": [{"id": "a", "internal": true}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"in_scope": {
			"op": "equals",
			"path": ["production"],
			"value": true,
			"substitute": {"op": "equals", "path": ["internal"], "value": true},
		}},
		"checks": {"c": {"op": "equals", "path": ["signed"], "value": true}},
	}})
	rep.requirements.s.subjects.matching == 1
}

with_range_substitute := {
	"op": "equals",
	"path": ["reviewed"],
	"value": true,
	"substitute": {"op": "range", "path": ["score"], "min": 1, "max": 9},
}

test_a_substitute_that_reads_the_wrong_kind_of_value_gives_the_row_its_cause if {
	cause_of({"score": "high"}, with_range_substitute) == "unusable"
}

test_a_substitute_that_is_only_missing_leaves_the_cause_of_the_main_check if {
	cause_of({"reviewed": false}, with_range_substitute) == "value"
	cause_of({"reviewed": null}, with_range_substitute) == "null"
}

test_a_substitute_that_reads_the_wrong_kind_of_value_stops_a_filter_ruling_a_subject_out if {
	rep := report({"items": [{"id": "a", "production": false, "score": "high"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"in_scope": {
			"op": "equals",
			"path": ["production"],
			"value": true,
			"substitute": {"op": "range", "path": ["score"], "min": 1, "max": 9},
		}},
		"checks": {"c": {"op": "equals", "path": ["signed"], "value": true}},
	}})
	rep.requirements.s.status == "not_met"
}

test_a_substitute_that_reads_the_same_path_shows_it_once if {
	inputs_of({"reviewed": true}, {"op": "equals", "path": ["reviewed"], "value": true, "substitute": {"op": "present", "path": ["reviewed"]}}) == [{"name": "reviewed", "value": true}]
}

test_a_substitute_renders_both_sides if {
	rendered({}, reviewed_or_verified) == "reviewed == true, or substitute: verified_committer == true"
}

test_a_substituted_row_echoes_both_sides if {
	inputs_of({"verified_committer": true}, reviewed_or_verified) == [
		{"name": "reviewed", "value": null},
		{"name": "verified_committer", "value": true},
	]
}

test_the_substitute_spec_stays_in_the_definition_table if {
	solo({}, reviewed_or_verified).requirements.s.checks.c.substitute.description == "Attested by a verified committer"
}

test_inputs_echo_the_read_path if {
	inputs_of({"state": "MERGED"}, is_merged) == [{"name": "state", "value": "MERGED"}]
}

test_inputs_echo_null_for_a_missing_field if {
	inputs_of({}, is_merged) == [{"name": "state", "value": null}]
}

test_inputs_name_nested_paths_with_dots if {
	check := {"op": "equals", "path": ["a", "b"], "value": 1}
	inputs_of({"a": {"b": 1}}, check) == [{"name": ".a.b", "value": 1}]
}

test_a_key_with_a_dot_is_quoted_so_it_is_not_named_like_a_nested_path if {
	check := {"op": "present", "path": ["a.b"]}
	inputs_of({"a.b": 1}, check) == [{"name": `"a.b"`, "value": 1}]
	rendered({}, check) == `"a.b" is present`
}

test_a_kubernetes_label_is_quoted_as_one_key if {
	check := {"op": "present", "path": ["metadata", "labels", "app.kubernetes.io/name"]}
	rendered({}, check) == `metadata.labels."app.kubernetes.io/name" is present`
}

test_a_key_made_of_digits_is_quoted_so_it_is_not_named_like_a_list_index if {
	rendered({}, {"op": "present", "path": ["xs", "0"]}) == `xs."0" is present`
	rendered({}, {"op": "present", "path": ["xs", 0]}) == `item 1 of xs is present`
}

test_an_empty_key_is_quoted if {
	rendered({}, {"op": "present", "path": ["a", "", "b"]}) == `.a."".b is present`
}

test_a_key_with_a_quote_is_escaped if {
	rendered({}, {"op": "present", "path": [`say "hi"`]}) == `"say \"hi\"" is present`
}

test_a_plain_key_with_a_dash_is_not_quoted_but_one_with_a_dollar_is if {
	rendered({}, {"op": "present", "path": ["pull-request", "$schema_x"]}) == `pull-request."$schema_x" is present`
}

test_a_selector_key_with_a_dot_is_quoted if {
	rendered({}, {"op": "present", "path": ["tags", {"where": {"a.b": "x"}}, "v"]}) == `tags.["a.b"=="x"].v is present`
}

test_an_any_of_reading_a_dotted_key_and_a_nested_path_gives_a_report if {
	check := {"op": "any_of", "options": {
		"x": [{"op": "present", "path": ["a.b"]}],
		"y": [{"op": "present", "path": ["a", "b"]}],
	}}
	inputs_of({"id": 1, "a.b": "dotted", "a": {"b": "nested"}}, check) == [
		{"name": `"a.b"`, "value": "dotted"},
		{"name": ".a.b", "value": "nested"},
	]
}

test_an_any_of_names_selectors_on_a_number_and_a_string_apart if {
	check := {"op": "any_of", "options": {
		"x": [{"op": "equals", "path": ["xs", {"where": {"k": 1}}, "v"], "value": "a"}],
		"y": [{"op": "equals", "path": ["xs", {"where": {"k": "1"}}, "v"], "value": "a"}],
	}}
	subj := {"id": 1, "xs": [{"k": 1, "v": "a"}, {"k": "1", "v": "b"}]}
	verdict(subj, check) == true
	inputs_of(subj, check) == [
		{"name": `xs.[k=="1"].v`, "value": "b"},
		{"name": "xs.[k==1].v", "value": "a"},
	]
}

test_inputs_echo_both_sides_of_a_comparison if {
	inputs_of({"a": 1, "b": 2}, compare_ab("lt")) == [
		{"name": ".a", "value": 1},
		{"name": "b", "value": 2},
	]
}

test_inputs_project_leaf_values_across_a_collection if {
	inputs_of({"commits": [{"verified": true}, {"verified": false}]}, all_verified) == [{
		"name": "commits[].verified",
		"value": [true, false],
	}]
}

test_explicit_inputs_win if {
	check := {"op": "present", "path": ["id"], "inputs": [["author"], ["approvers"]]}
	inputs_of({"id": "x", "author": "alice", "approvers": []}, check) == [
		{"name": "author", "value": "alice"},
		{"name": "approvers", "value": []},
	]
}

test_inputs_empty_when_a_check_declares_neither_path_nor_inputs if {
	inputs_of({"id": "x"}, {"op": "bespoke"}) == []
}

test_inputs_can_project_across_a_collection if {
	check := {"op": "bespoke", "inputs": [{"path": ["commits"], "each": ["timestamp"]}]}
	inputs_of({"commits": [{"timestamp": 1}, {"timestamp": 2}]}, check) == [{
		"name": "commits[].timestamp",
		"value": [1, 2],
	}]
}

test_inputs_projection_over_a_missing_collection if {
	check := {"op": "bespoke", "inputs": [{"path": ["commits"], "each": ["timestamp"]}]}
	inputs_of({}, check) == [{"name": "commits[].timestamp", "value": []}]
}

test_inputs_projection_over_an_object_lists_nothing_so_its_order_cannot_vary if {
	check := {"op": "bespoke", "inputs": [{"path": ["commits"], "each": ["timestamp"]}]}
	inputs_of({"commits": {"b": {"timestamp": 2}, "a": {"timestamp": 1}}}, check) == [{"name": "commits[].timestamp", "value": []}]
}

test_a_list_check_over_an_object_lists_nothing_so_its_order_cannot_vary if {
	subj := {"m": {"alpha": {"v": 1}, "beta": {"v": 2}, "gamma": {"v": 3}, "delta": {"v": 4}}}
	inputs_of(subj, {"op": "all", "path": ["m"], "check": {"op": "present", "path": ["v"]}}) == [{"name": "m[].v", "value": []}]
	inputs_of(subj, {"op": "any", "path": ["m"], "each": ["v"], "check": {"op": "present", "path": []}}) == [{"name": "m[].v", "value": []}]
}

test_inputs_mix_paths_and_projections if {
	check := {"op": "bespoke", "inputs": [["author"], {"path": ["commits"], "each": ["sha1"]}]}
	inputs_of({"author": "alice", "commits": [{"sha1": "aaaa"}]}, check) == [
		{"name": "author", "value": "alice"},
		{"name": "commits[].sha1", "value": ["aaaa"]},
	]
}

test_definition_carries_the_raw_spec_and_description if {
	check := object.union(is_merged, {"description": "Merged"})
	def := solo({"state": "MERGED"}, check).requirements.s.checks.c
	def.op == "equals"
	def.path == ["state"]
	def.value == "MERGED"
	def.description == "Merged"
}

test_expression_for_range if rendered({"temp_c": 5}, in_range) == "temp_c >= 0 and temp_c <= 10"

test_expression_for_excludes if rendered({"labels": []}, no_wip) == `not contains(labels, "wip")`

test_expression_for_includes if rendered({"labels": []}, has_approved) == `contains(labels, "approved")`

test_expression_for_includes_and_excludes_values_sorts_them if {
	rendered({"allergens": []}, no_allergens) == `contains_none(allergens, ["garlic", "nuts"])`
	rendered({"sign_offs": []}, all_signed_off) == `contains_all(sign_offs, ["qa", "security"])`
}

test_expression_for_includes_and_excludes_does_not_list_values_it_will_not_use if {
	rendered({"xs": []}, {"op": "excludes", "path": ["xs"], "values": "nuts"}) == "contains_none(xs, <invalid values>)"
	rendered({"xs": []}, {"op": "includes", "path": ["xs"], "values": {"ref": ["$$input"], "x": 1}}) == "contains_all(xs, <invalid ref>)"
	rendered({"xs": []}, {"op": "includes", "path": ["xs"]}) == "contains(xs, <missing value or values>)"
	rendered({"xs": []}, {"op": "excludes", "path": ["xs"], "value": 2, "values": [3]}) == "not contains(xs, <both value and values>)"
}

test_expression_for_in_sorts_the_values if rendered({"id": "MIT"}, allowed_licence) == `id in ["Apache-2.0", "MIT"]`

test_expression_for_in_does_not_list_values_it_will_not_match if {
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"licence": "MIT"}}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": "MIT"}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": null}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"]}) == "id in <missing values>"
}

test_expression_for_matches_any_does_not_list_patterns_it_will_not_match if {
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"p": "x"}}) == ".a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": "x"}) == ".a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"literal": "x"}}) == ".a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": null}) == ".a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"]}) == ".a matches one of <missing patterns>"
}

test_expression_for_not_matches_any_does_not_list_patterns_it_will_not_match if {
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"], "patterns": "x"}) == ".a matches none of <invalid patterns>"
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"], "patterns": null}) == ".a matches none of <invalid patterns>"
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"]}) == ".a matches none of <missing patterns>"
}

test_expression_for_matches_any_lists_a_literal_list_of_patterns if {
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"literal": ["y", "x"]}}) == `.a matches one of ["x", "y"]`
}

test_expression_for_equals if rendered({}, is_merged) == `state == "MERGED"`

test_a_string_value_is_quoted_so_it_is_not_read_as_a_number if {
	rendered({}, {"op": "equals", "path": ["n"], "value": "1"}) == `n == "1"`
	rendered({}, {"op": "equals", "path": ["n"], "value": 1}) == `n == 1`
}

test_a_string_value_is_quoted_so_it_is_not_read_as_true_false_or_null if {
	rendered({}, {"op": "equals", "path": ["x"], "value": "true"}) == `x == "true"`
	rendered({}, {"op": "equals", "path": ["x"], "value": true}) == `x == true`
	rendered({}, {"op": "equals", "path": ["x"], "value": "null"}) == `x == "null"`
	rendered({}, {"op": "equals", "path": ["x"], "value": null}) == `x == null`
}

test_an_empty_string_value_is_shown if {
	rendered({}, {"op": "equals", "path": ["x"], "value": ""}) == `x == ""`
}

test_a_string_value_that_looks_like_a_ref_is_quoted if {
	rendered({}, {"op": "equals", "path": ["x"], "value": "$$params.x"}) == `x == "$$params.x"`
}

test_a_string_value_is_escaped_as_in_standard_json if {
	rendered({}, {"op": "equals", "path": ["x"], "value": "a \"b\" \\ <c> & d\n\t\u0001"}) == `x == "a \"b\" \\ <c> & d\n\t\u0001"`
}

test_a_number_value_is_written_the_same_however_the_policy_wrote_it if {
	[rendered({}, {"op": "equals", "path": ["n"], "value": v}) | some v in [1, 1.0, 1.50, 1e2, 2.5e-3, -0.0, 1.23e-7]] == [
		"n == 1", "n == 1", "n == 1.5", "n == 100", "n == 0.0025", "n == 0", "n == 0.000000123",
	]
}

test_a_large_number_value_is_written_in_full if {
	rendered({}, {"op": "equals", "path": ["n"], "value": 1e21}) == "n == 1000000000000000000000"
	rendered({}, {"op": "equals", "path": ["n"], "value": 123456789012345678901234567890}) == "n == 123456789012345678901234567890"
}

test_keys_of_different_types_are_sorted_by_how_they_are_written if {
	rendered({}, {"op": "equals", "path": ["x"], "value": {"o": {false: 1, 1: 2, "a": {null: 3, 10: 4, 9: 5}}}}) == `x == {"o": {"1": 2, "a": {"10": 4, "9": 5, "null": 3}, "false": 1}}`
}

test_a_set_value_is_written_as_a_sorted_list if {
	rendered({}, {"op": "equals", "path": ["x"], "value": {"o": {3, {"b": 1, "a": {2, 1}}, set()}}}) == `x == {"o": [3, {"a": [1, 2], "b": 1}, []]}`
}

test_an_empty_list_value_is_written_as_json if rendered({}, {"op": "equals", "path": ["x"], "value": [[], {}]}) == "x == [[], {}]"

test_a_key_that_is_not_a_string_is_written_as_a_json_string if rendered({}, {"op": "equals", "path": ["x"], "value": {1: "a"}}) == `x == {"1": "a"}`

test_a_list_or_object_value_is_written_as_json_with_sorted_keys if {
	rendered({}, {"op": "equals", "path": ["x"], "value": ["a", 1.50, {"b": [true, null], "a": "x,y:z"}]}) == `x == ["a", 1.5, {"a": "x,y:z", "b": [true, null]}]`
	rendered({}, {"op": "equals", "path": ["x"], "value": {}}) == "x == {}"
}

test_a_string_inside_a_list_value_is_escaped_as_in_standard_json if {
	rendered({}, {"op": "equals", "path": ["x"], "value": ["a<b&c", "\u0001\b"]}) == `x == ["a<b&c", "\u0001\b"]`
}

test_a_byte_order_mark_in_a_value_is_written_as_is if {
	rendered({}, {"op": "equals", "path": ["x"], "value": "\ufeff"}) == "x == \"\ufeff\""
	rendered({}, {"op": "in", "path": ["x"], "values": ["\ufeff"]}) == "x in [\"\ufeff\"]"
}

test_a_byte_order_mark_in_a_path_key_is_written_as_is if {
	rendered({}, {"op": "present", "path": ["\ufeffa"]}) == "\"\ufeffa\" is present"
}

test_a_byte_order_mark_in_an_op_is_written_as_is if {
	rendered({}, {"op": "\ufeff", "path": ["x"]}) == "<unknown op \ufeff>"
}

test_a_byte_order_mark_in_a_subject_name_and_from_is_written_as_is if {
	min_subjects := report({"i\ufeff": [{"id": 1}]}, {"s": {
		"subject_type": "t\ufeff",
		"from": ["i\ufeff"],
		"id": ["id"],
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}}).requirements.s.checks["$min_subjects"]
	min_subjects.description == "The in-scope t\ufeff count is at least 1"
	min_subjects.expression == "count(matching(\"i\ufeff\")) >= 1"
}

test_text_that_looks_like_an_escape_is_kept_as_written if {
	rendered({}, {"op": "equals", "path": ["x"], "value": `\u003c`}) == `x == "\\u003c"`
}

test_a_range_writes_its_bounds_as_numbers if {
	rendered({}, {"op": "range", "path": ["t"], "min": 175.0, "max": 2e2}) == "t >= 175 and t <= 200"
}

test_min_subjects_is_written_like_any_number if {
	rep := report({"xs": []}, {"s": {"from": ["xs"], "min_subjects": 2.0, "checks": {"c": {"op": "present", "path": ["x"]}}}})
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(xs)) >= 2"
}

test_a_step_that_cannot_be_a_key_is_named_apart_from_a_key_that_looks_like_it if {
	rendered({}, {"op": "present", "path": ["a", true]}) == ".a.<invalid step> is present"
	rendered({}, {"op": "present", "path": ["a", "true"]}) == ".a.true is present"
}

bad_steps := [true, null, ["a"], 1.5, -1, 1.0, 1e0, {"literal": true}, {"literal": -1}]

test_a_present_filter_with_a_step_that_cannot_be_a_key_cannot_rule_subjects_out if {
	rows := [[rep.requirements.s.status, r.passed, r.cause] |
		some seg in bad_steps
		rep := report({"xs": [{"id": 1, "a": [1, 2]}]}, {"s": {
			"from": ["xs"],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": {"op": "present", "path": ["a", seg]}},
			"checks": {"c": {"op": "present", "path": ["id"]}},
		}})
		some r in rows_for(rep, "s", "$applies")
	]
	rows == [["not_met", false, "ill_formed"] | some _ in bad_steps]
}

test_a_check_with_a_step_that_cannot_be_a_key_is_ill_formed if {
	subj := {"id": 1, "a": [1, 2], "b": 1}
	checks := [c |
		some seg in bad_steps
		some c in [
			{"op": "present", "path": ["a", seg]},
			{"op": "compare", "left": ["a", seg], "right": ["b"], "cmp": "eq"},
			{"op": "all", "path": ["a"], "each": [seg], "check": {"op": "present", "path": []}},
		]
	]
	single := [{"op": "present", "path": seg} | some seg in bad_steps; not is_array(seg)]
	[[verdict(subj, c), cause_of(subj, c)] | some c in array.concat(checks, single)] == [[false, "ill_formed"] | some _ in array.concat(checks, single)]
}

test_a_string_never_picks_a_list_item_and_a_number_never_picks_an_object_key if {
	[cause_of({"id": 1, "a": [10, 20]}, {"op": "present", "path": ["a", "0"]}), cause_of({"id": 1, "o": {"0": "zero"}}, {"op": "present", "path": ["o", 0]})] == ["unusable", "unusable"]
}

test_a_check_whose_inputs_have_a_step_that_cannot_be_a_key_is_ill_formed if {
	subj := {"id": 1, "n": 2, "xs": [{"v": 1}]}
	[[verdict(subj, c), cause_of(subj, c)] | some c in [
		{"op": "even", "path": ["n"], "expression": "n is even", "inputs": [["n", true]]},
		{"op": "even", "path": ["n"], "expression": "n is even", "inputs": [{"path": ["xs"], "each": ["v", -1]}]},
		{"op": "even", "path": ["n"], "expression": "n is even", "inputs": [{"path": ["xs", 1.0], "each": ["v"]}]},
		{"op": "equals", "path": ["n"], "value": 2, "inputs": [["n", null]]},
	]] == [[false, "ill_formed"], [false, "ill_formed"], [false, "ill_formed"], [false, "ill_formed"]]
	verdict(subj, {"op": "even", "path": ["n"], "expression": "n is even", "inputs": [["n"], {"path": ["xs"], "each": ["v"]}]}) == true
}

test_a_list_index_written_as_a_whole_number_reads_the_item if {
	verdict({"id": 1, "a": [1, 2]}, {"op": "equals", "path": ["a", 1], "value": 2}) == true
	verdict({"id": 1, "a": [1, 2]}, {"op": "equals", "path": ["a", 0], "value": 1}) == true
	rendered({}, {"op": "present", "path": ["a", 1]}) == "item 2 of .a is present"
}

test_a_ref_step_that_reads_something_that_cannot_be_a_key_fails_as_unusable if {
	check := {"op": "present", "path": ["a", {"ref": ["$$params", "i"]}]}
	params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check) == [[true, "satisfied", [{"name": ".a named by $params.i", "value": 2}]]] with data.params as {"i": 1}
	r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": -1}
	[r[0], r[1]] == [false, "unusable"]
	s := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 1.0}
	[s[0], s[1]] == [false, "unusable"]
}

test_a_from_or_id_with_a_step_that_cannot_be_a_key_is_not_well_formed if {
	rows := [r.passed |
		some m in [{"from": ["xs", true]}, {"from": ["xs", 1.0, {"each_as": "x"}]}, {"id": ["id", null]}]
		rep := report({"xs": [{"id": 1}]}, {"s": object.union({"from": ["xs"], "checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [false, false, false]
}

test_a_check_with_a_number_too_big_for_a_float_fails_closed if {
	check := {"op": "equals", "path": ["n"], "value": 1e400}
	[verdict({"id": 1, "n": 1e400}, check), cause_of({"id": 1, "n": 1e400}, check)] == [false, "ill_formed"]
	rendered({}, check) == "n == <number out of range>"
}

test_a_check_with_a_number_too_small_for_a_float_fails_closed_so_it_cannot_pass_as_zero if {
	check := {"op": "equals", "path": ["n"], "value": 1e-400}
	[verdict({"id": 1, "n": 0}, check), verdict({"id": 1, "n": 1e-400}, check)] == [false, false]
}

test_a_number_out_of_range_anywhere_in_a_check_fails_it if {
	verdict({"id": 1, "n": 5}, {"op": "range", "path": ["n"], "min": 0, "max": 1e400}) == false
	verdict({"id": 1, "n": "a"}, {"op": "in", "path": ["n"], "values": ["a", 1e400]}) == false
	verdict({"id": 1, "n": "a"}, {"op": "in", "path": ["n"], "values": {"literal": ["a", 1e400]}}) == false
	verdict({"id": 1, "xs": [{"k": 1, "v": 1}]}, {"op": "present", "path": ["xs", {"where": {"k": 1e400}}, "v"]}) == false
	verdict({"id": 1, "xs": [1]}, {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1e400}}) == false
	rendered({}, {"op": "in", "path": ["n"], "values": ["a", 1e400]}) == `n in ["a", <number out of range>]`
}

test_a_number_at_the_edge_of_a_float_still_works if {
	verdict({"id": 1, "n": 1.7976931348623157e308}, {"op": "equals", "path": ["n"], "value": 1.7976931348623157e308}) == true
	verdict({"id": 1, "n": 2.2250738585072014e-308}, {"op": "equals", "path": ["n"], "value": 2.2250738585072014e-308}) == true
	verdict({"id": 1, "n": 0}, {"op": "equals", "path": ["n"], "value": 0}) == true
	verdict({"id": 1, "n": 2.2250738585072e-308}, {"op": "equals", "path": ["n"], "value": 2.2250738585072e-308}) == false
}

test_a_requirement_with_a_number_out_of_range_is_not_well_formed if {
	rows := [[r.check, r.passed] |
		some m in [{"min_subjects": 1e-400}, {"id": ["xs", 1e400]}, {"from": ["xs", 1e400]}]
		rep := report({"xs": [{"id": 1}]}, {"s": object.union({"from": ["xs"], "checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [["$well_formed", false], ["$well_formed", false], ["$well_formed", false]]
}

test_min_subjects_is_described_like_any_number if {
	rep := report({"xs": []}, {"s": {"from": ["xs"], "min_subjects": 2.0, "checks": {"c": {"op": "present", "path": ["x"]}}}})
	rep.requirements.s.checks["$min_subjects"].description == "The in-scope subject count is at least 2"
}

test_a_key_is_escaped_as_in_standard_json if {
	rendered({}, {"op": "present", "path": ["a<b"]}) == `"a<b" is present`
}

test_an_in_list_tells_a_number_from_a_string if {
	rendered({}, {"op": "in", "path": ["n"], "values": [1, "1"]}) == `n in ["1", 1]`
}

test_a_selector_tells_a_number_from_a_string if {
	rendered({}, {"op": "present", "path": ["xs", {"where": {"k": 1}}, "v"]}) == `xs.[k==1].v is present`
	rendered({}, {"op": "present", "path": ["xs", {"where": {"k": "1"}}, "v"]}) == `xs.[k=="1"].v is present`
}

test_expression_for_present if rendered({}, has_fingerprint) == "fingerprint is present"

test_expression_for_non_empty_string if rendered({}, filled) == "fingerprint is a non-empty string"

test_expression_for_missing if rendered({}, no_fingerprint) == "fingerprint is missing"

test_expression_for_empty if rendered({}, no_commits) == "commits is empty"

test_expression_for_compare if rendered({}, compare_ab("lt")) == ".a lt b"

test_expression_for_compare_time if rendered(span, compare_time_span("lt")) == "start lt end"

test_expression_for_all if rendered({"commits": []}, all_verified) == "every commits: verified == true"

test_expression_for_any if rendered({"approvers": []}, any_approved) == `some approvers: state == "APPROVED"`

test_expression_for_nested_paths_is_dotted if {
	check := {"op": "equals", "path": ["a", "b"], "value": 1}
	rendered({}, check) == ".a.b == 1"
}

test_declared_expression_wins_over_the_rendered_one if {
	check := object.union(is_merged, {"expression": "state is MERGED"})
	rendered({}, check) == "state is MERGED"
}

test_an_expression_that_is_not_a_string_is_ignored if {
	every e in [false, true, 5, null, ["x"], {"a": 1}] {
		rendered({}, object.union(is_merged, {"expression": e})) == `state == "MERGED"`
	}
}

test_an_expression_that_is_false_still_gives_a_report if {
	solo({"state": "MERGED"}, object.union(is_merged, {"expression": false})).compliant == true
}

test_a_substitute_whose_expression_is_false_is_rendered_as_usual if {
	check := {"op": "present", "path": ["fingerprint"], "substitute": object.union(is_merged, {"expression": false})}
	rendered({}, check) == `fingerprint is present, or substitute: state == "MERGED"`
}

test_a_declared_custom_op_without_an_expression_renders_as_empty if rendered({}, {"op": "even", "path": ["n"]}) == ""

two_check_req := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"checks": {
		"a": {"op": "present", "path": ["id"]},
		"b": {"op": "equals", "path": ["state"], "value": "MERGED"},
	},
}}

test_one_row_per_subject_and_check if {
	doc := {"items": [{"id": "a"}, {"id": "b"}]}
	rep := report(doc, two_check_req)
	count([r | some r in rep.results; not startswith(r.check, "$")]) == 4

	count(rep.results) == 7
}

test_row_carries_exactly_the_documented_keys if {
	every row in solo({"state": "MERGED"}, is_merged).results {
		object.keys(row) == {"requirement", "subject", "check", "inputs", "passed", "cause"}
	}
}

test_rows_are_produced_even_for_an_empty_subject if {
	rep := report({"items": [{}]}, two_check_req)
	check_rows := [r | some r in rep.results; not startswith(r.check, "$")]
	count(check_rows) == 2
	every row in check_rows {
		row.passed == false
	}
}

test_unknown_op_produces_a_failing_row_not_a_gap if {
	verdict({"id": "x"}, {"op": "no_such_op", "path": ["id"]}) == false
}

test_rows_from_different_requirements_are_labelled_separately if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	rep := report(doc, policy)
	count(rows_for(rep, "first", "c")) == 1
	count(rows_for(rep, "second", "c")) == 1
}

test_requirement_name_is_the_policy_key if {
	rep := report({"items": [{"id": "a"}]}, id_req(["items"]))
	object.keys(rep.requirements) == {"s"}
	{r.requirement | some r in rep.results} == {"s"}
}

selected_state := {"op": "equals", "path": ["atts", {"where": {"type": "pr"}}, "state"], "value": "MERGED"}

test_cause_satisfied_when_the_check_holds if {
	cause_of({"state": "MERGED"}, {"op": "equals", "path": ["state"], "value": "MERGED"}) == "satisfied"
}

test_cause_value_when_the_paths_read_cleanly_and_the_assertion_is_false if {
	cause_of({"state": "OPEN"}, {"op": "equals", "path": ["state"], "value": "MERGED"}) == "value"
}

test_cause_absent_when_the_path_is_not_there if {
	cause_of({}, {"op": "equals", "path": ["state"], "value": "MERGED"}) == "absent"
}

test_cause_null_when_the_path_is_there_and_null if {
	cause_of({"state": null}, {"op": "equals", "path": ["state"], "value": "MERGED"}) == "null"
}

test_cause_unusable_when_the_path_walks_through_a_scalar if {
	cause_of({"pr": "none"}, {"op": "equals", "path": ["pr", "state"], "value": "MERGED"}) == "unusable"
}

test_every_read_fails_as_unusable_when_a_step_before_the_field_cannot_hold_it if {
	every pair in [
		[{"a": "x"}, {"op": "all", "path": ["a", "b"], "check": {"op": "present", "path": []}}],
		[{"xs": [{"b": 1}]}, {"op": "all", "path": ["xs"], "each": ["b", "c"], "check": {"op": "present", "path": []}}],
		[{"xs": [{"v": "s"}]}, {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": ["v", "w"], "value": 1}}],
		[{"a": 3}, {"op": "even", "path": ["id"], "inputs": [["a", "b"]]}],
		[{"a": "x", "b": 1}, {"op": "compare", "left": ["a", "z"], "right": ["b"], "cmp": "eq"}],
		[{"a": [1]}, {"op": "equals", "path": ["a", "b"], "value": 1}],
	] {
		cause_of(pair[0], pair[1]) == "unusable"
	}
}

test_a_ref_fails_as_unusable_when_a_step_before_its_value_cannot_hold_it if {
	value := {"op": "equals", "path": ["n"], "value": {"ref": ["$$input", "params", "cfg", "n"]}}
	step := {"op": "present", "path": [{"ref": ["$$input", "params", "cfg", "k"]}]}
	[[r.passed, r.cause] | some r in [row_in({"params": {"cfg": "flat"}}, {"id": 1, "n": 1}, value), row_in({"params": {"cfg": "flat"}}, {"id": 1, "n": 1}, step)]] == [[false, "unusable"], [false, "unusable"]]
	row_in({"params": {}}, {"id": 1, "n": 1}, value).cause == "absent"
}

test_cause_ambiguous_when_a_selector_matches_more_than_one_element if {
	cause_of(
		{"atts": [{"type": "pr", "state": "MERGED"}, {"type": "pr", "state": "OPEN"}]},
		selected_state,
	) == "ambiguous"
}

test_cause_unmatched_when_a_selector_matches_nothing if {
	cause_of({"atts": [{"type": "scan"}]}, selected_state) == "unmatched"
}

test_cause_unmatched_over_an_empty_collection if {
	cause_of({"atts": []}, selected_state) == "unmatched"
}

test_cause_absent_when_the_collection_a_selector_reads_is_not_there if {
	cause_of({}, selected_state) == "absent"
}

test_cause_ambiguous_over_a_map_keyed_collection if {
	cause_of(
		{"atts": {"first": {"type": "pr", "state": "MERGED"}, "second": {"type": "pr", "state": "OPEN"}}},
		selected_state,
	) == "ambiguous"
}

test_cause_satisfied_when_a_selector_matches_exactly_one if {
	cause_of({"atts": [{"type": "pr", "state": "MERGED"}, {"type": "scan"}]}, selected_state) == "satisfied"
}

test_cause_precedence_prefers_the_more_fundamental_defect if {
	cause_of({"left": null}, {
		"op": "compare",
		"left": ["left"],
		"right": ["right"],
		"cmp": "lt",
	}) == "absent"
}

test_cause_precedence_reports_null_only_when_nothing_worse_happened if {
	cause_of({"left": null, "right": null}, {
		"op": "compare",
		"left": ["left"],
		"right": ["right"],
		"cmp": "lt",
	}) == "null"
}

test_cause_of_a_quantified_check_describes_the_collection if {
	cause_of({"commits": [{"verified": false}]}, all_verified) == "value"
	cause_of({}, all_verified) == "absent"
}

test_cause_follows_an_explicit_inputs_list if {
	cause_of({}, {
		"op": "equals",
		"path": ["state"],
		"value": "MERGED",
		"inputs": [["atts", {"where": {"type": "pr"}}, "state"]],
		"expression": "custom",
	}) == "absent"
}

test_synthesised_rows_carry_a_cause if {
	rep := report({"items": []}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "present", "path": ["x"]}},
	}})
	rows_for(rep, "s", "$well_formed")[0].cause == "satisfied"
	rows_for(rep, "s", "$min_subjects")[0].cause == "value"
}

test_an_applies_row_carries_the_state_of_the_filter_paths if {
	rep := report({"items": [{"id": "a", "env": "prod"}, {"id": "b"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"prod_only": {"op": "equals", "path": ["env"], "value": "prod"}},
		"checks": {"c": {"op": "present", "path": ["x"]}},
	}})
	applies := rows_for(rep, "s", "$applies")
	[r.cause | some r in applies] == ["satisfied", "absent"]
}

test_violations_carry_the_cause if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "equals", "path": ["state"], "value": "MERGED"}},
	}})
	[v.cause | some v in ergo.violations(rep)] == ["absent"]
}

min_subjects_req(n) := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"min_subjects": n,
	"checks": {"c": {"op": "present", "path": ["id"]}},
}}

test_min_subjects_met if {
	rep := report({"items": [{"id": "a"}]}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.status == "met"
}

test_min_subjects_violated_fails_the_requirement if {
	rep := report({"items": []}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == false
	rep.requirements.s.status == "not_met"
	rep.compliant == false
}

test_min_subjects_row_has_a_null_subject_id if {
	rep := report({"items": []}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].subject == {"type": "thing", "id": null}
}

test_min_subjects_definition_is_in_the_check_table if {
	rep := report({"items": []}, min_subjects_req(2))
	def := rep.requirements.s.checks["$min_subjects"]
	def.description == "The in-scope thing count is at least 2"
	def.expression == "count(matching(items)) >= 2"
}

test_min_subjects_defaults_to_one if {
	rep := report({"items": [{"id": "a"}]}, id_req(["items"]))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_min_subjects_zero_permits_an_empty_collection if {
	rep := report({"items": []}, min_subjects_req(0))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.status == "not_applicable"
}

test_min_subjects_counts_subjects_after_the_applies_to_filter if {
	both := {"s": object.union(min_subjects_req(2).s, {"applies_to": merged_only})}
	rep := report(two_states, both)
	rows_for(rep, "s", "$min_subjects")[0].passed == false
}

test_min_subjects_guards_a_missing_collection if {
	rep := report({}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == false
	rep.compliant == false
}

test_min_subjects_fails_with_the_cause_of_a_from_it_cannot_read_even_at_zero if {
	every doc, cause in {
		"{}": "absent",
		`{"items": null}`: "null",
		`{"items": "none"}`: "unusable",
		`{"items": 3}`: "unusable",
		`{"items": true}`: "unusable",
	} {
		every n in [0, 1] {
			rep := report(json.unmarshal(doc), min_subjects_req(n))
			[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
			rep.requirements.s.status == "not_met"
			rep.compliant == false
		}
	}
}

test_a_from_that_reads_nothing_fails_a_some_requirement_at_zero_which_an_empty_list_leaves_not_applicable if {
	req := {"s": object.union(min_subjects_req(0).s, {"require": "some"})}
	missing := report({}, req)
	[missing.requirements.s.status, missing.compliant] == ["not_met", false]
	empty := report({"items": []}, req)
	[empty.requirements.s.status, empty.compliant] == ["not_applicable", true]
}

test_min_subjects_fails_as_value_on_an_empty_list_so_a_missing_one_stays_apart if {
	rep := report({"items": []}, min_subjects_req(1))
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "value"]]
}

test_min_subjects_reads_the_from_path_like_a_check_reads_a_path if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": ["build", "items"]})}
	every doc, cause in {
		"{}": "absent",
		`{"build": null}`: "absent",
		`{"build": "b1"}`: "unusable",
		`{"build": ["b1"]}`: "unusable",
		`{"build": {"items": null}}`: "null",
	} {
		rep := report(json.unmarshal(doc), req)
		rows_for(rep, "s", "$min_subjects")[0].cause == cause
	}
}

test_min_subjects_reads_a_list_index_in_from if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": ["builds", 1, "items"]})}
	ok := report({"builds": [{}, {"items": []}]}, req)
	[[r.passed, r.cause] | some r in rows_for(ok, "s", "$min_subjects")] == [[true, "satisfied"]]
	short := report({"builds": [{}]}, req)
	rows_for(short, "s", "$min_subjects")[0].cause == "absent"
}

test_min_subjects_accepts_a_single_object_from_as_one_subject if {
	rep := report({"items": {"id": "a"}}, min_subjects_req(1))
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied"]]
}

test_min_subjects_with_an_empty_from_fails_when_the_document_is_not_an_object if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": []})}
	every doc, cause in {"null": "null", `"x"`: "unusable", "3": "unusable", `[{"id": "a"}]`: "unusable"} {
		rep := report(json.unmarshal(doc), req)
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
}

test_min_subjects_fails_when_from_has_steps_and_the_document_is_not_an_object if {
	every doc, cause in {"null": "absent", `"x"`: "unusable", `[{"items": []}]`: "unusable"} {
		rep := report(json.unmarshal(doc), min_subjects_req(0))
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
}

test_min_subjects_fails_as_unusable_on_a_list_input_even_when_from_starts_with_an_index if {
	every f in [[0], [0, "items"]] {
		req := {"s": object.union(min_subjects_req(0).s, {"from": f})}
		rep := report([{"items": []}], req)
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "unusable"]]
	}
}

test_min_subjects_fails_with_the_cause_of_an_each_from_it_cannot_read if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": ["items", {"each_as": "item"}]})}
	every doc, cause in {"{}": "absent", `{"items": null}`: "null", `{"items": "none"}`: "unusable"} {
		rep := report(json.unmarshal(doc), req)
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
	empty := report({"items": {}}, req)
	[[r.passed, r.cause] | some r in rows_for(empty, "s", "$min_subjects")] == [[true, "satisfied"]]
	empty.requirements.s.status == "not_applicable"
}

test_min_subjects_leaves_a_keys_from_alone_because_each_key_is_a_subject_even_when_from_reads_nothing if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": ["items", {"each_as": "item", "keys": ["a"]}]})}
	rep := report({}, req)
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied"]]
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "value"]]
}

test_min_subjects_at_zero_says_it_only_checks_that_from_can_be_read if {
	def := report({"items": []}, min_subjects_req(0)).requirements.s.checks["$min_subjects"]
	def.description == "The thing list can be read"
	def.expression == "items can be read"
}

test_min_subjects_at_zero_names_the_input_when_there_is_no_from if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": []})}
	report({}, req).requirements.s.checks["$min_subjects"].expression == "$input can be read"
}

test_min_subjects_at_zero_keeps_the_count_with_a_keys_step_because_from_is_not_read if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": ["items", {"each_as": "item", "keys": ["a"]}]})}
	def := report({}, req).requirements.s.checks["$min_subjects"]
	def.description == "The in-scope thing count is at least 0"
	def.expression == "count(matching(items)) >= 0"
}

test_min_subjects_above_zero_keeps_the_count if {
	def := report({"items": []}, min_subjects_req(1)).requirements.s.checks["$min_subjects"]
	def.description == "The in-scope thing count is at least 1"
	def.expression == "count(matching(items)) >= 1"
}

test_a_violation_for_a_from_that_reads_nothing_says_what_failed if {
	rep := report({}, min_subjects_req(0))
	[[v.description, v.expression, v.cause] | some v in ergo.violations(rep)] == [["The thing list can be read", "items can be read", "absent"]]
}

test_min_subjects_fails_like_well_formed_when_from_is_written_wrong_even_at_zero if {
	every f in [5, [{"each_as": "it"}, "items"], ["items", {"each_as": "it", "bad": 1}], ["items", {"ref": ["$$params", "nope"]}, {"bad": 1}]] {
		every n in [0, 1] {
			req := {"s": object.union(min_subjects_req(n).s, {"from": f})}
			rep := report({"items": [{"id": "a"}]}, req)
			[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "value"]]
		}
	}
}

test_a_from_that_reads_nothing_lists_its_min_subjects_row_as_a_violation if {
	rep := report({}, min_subjects_req(0))
	[[v.check, v.cause] | some v in ergo.violations(rep)] == [["$min_subjects", "absent"]]
}

owner_req := {"s": {
	"subject_type": "repo",
	"from": ["repos"],
	"id": ["name"],
	"checks": {"owned": {"op": "non_empty_string", "path": ["owner"]}},
}}

unique_ids_row(doc, policy) := [r.inputs, r.passed, r.cause] if {
	some r in rows_for(report(doc, policy), "s", "$unique_ids")
}

test_unique_ids_passes_when_every_subject_has_its_own_id if {
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "b", "owner": "carol"}]}, owner_req)
	[[r.inputs, r.passed, r.cause] | some r in rows_for(rep, "s", "$unique_ids")] == [[[{"name": "repeated repo ids", "value": []}], true, "satisfied"]]
	rep.requirements.s.status == "met"
}

test_unique_ids_fails_the_requirement_when_two_subjects_share_an_id if {
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "a", "owner": "carol"}]}, owner_req)
	[[r.subject, r.inputs, r.passed, r.cause] | some r in rows_for(rep, "s", "$unique_ids")] == [[
		{"type": "repo", "id": null},
		[{"name": "repeated repo ids", "value": ["a"]}],
		false,
		"value",
	]]
	rep.requirements.s.status == "not_met"
	rep.compliant == false
	[v.check | some v in ergo.violations(rep)] == ["$unique_ids"]
}

test_unique_ids_fails_a_some_requirement_too if {
	policy := {"s": object.union(owner_req.s, {"require": "some"})}
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "a", "owner": ""}]}, policy)
	rep.requirements.s.status == "not_met"
}

test_unique_ids_tells_apart_subjects_whose_rows_would_look_the_same if {
	unique_ids_row({"repos": [{"name": "a", "owner": ""}, {"name": "a", "owner": ""}]}, owner_req) == [[{"name": "repeated repo ids", "value": ["a"]}], false, "value"]
}

test_unique_ids_counts_two_subjects_without_an_id_as_sharing_the_id_null if {
	unique_ids_row({"repos": [{"owner": "bob"}, {"owner": "carol"}]}, owner_req) == [[{"name": "repeated repo ids", "value": [null]}], false, "value"]
}

test_unique_ids_reads_a_subject_that_is_not_an_object_as_its_own_id if {
	unique_ids_row({"repos": ["api", "api", "web"]}, owner_req) == [[{"name": "repeated repo ids", "value": ["api"]}], false, "value"]
}

test_unique_ids_counts_two_identical_subjects_as_a_clash_without_an_id_path if {
	policy := {"s": object.remove(owner_req.s, ["id"])}
	unique_ids_row({"repos": [{"owner": "bob"}, {"owner": "bob"}, {"owner": "carol"}]}, policy) == [[{"name": "repeated repo ids", "value": [{"owner": "bob"}]}], false, "value"]
}

test_unique_ids_counts_subjects_that_are_out_of_scope if {
	policy := {"s": object.union(owner_req.s, {"applies_to": {"live": {"op": "equals", "path": ["live"], "value": true}}})}
	doc := {"repos": [{"name": "a", "owner": "bob", "live": true}, {"name": "a", "owner": "bob", "live": false}]}
	rep := report(doc, policy)
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	[[r.inputs, r.passed] | some r in rows_for(rep, "s", "$unique_ids")] == [[[{"name": "repeated repo ids", "value": ["a"]}], false]]
	rep.requirements.s.status == "not_met"
}

test_unique_ids_lists_each_repeated_id_once_in_the_order_it_is_written_whatever_the_input_order if {
	rows := {row |
		some ids in [[3, "b", 10, "a", 3, "b", 10, 10], [10, 10, "b", 3, "a", 10, "b", 3]]
		row := unique_ids_row({"repos": [{"name": n} | some n in ids]}, owner_req)
	}
	rows == {[[{"name": "repeated repo ids", "value": ["b", 10, 3]}], false, "value"]}
}

test_unique_ids_reads_ids_through_a_name if {
	policy := {"s": object.union(owner_req.s, {"from": ["repos", {"each_as": "repo"}], "id": ["$repo", "name"]})}
	unique_ids_row({"repos": [{"name": "a"}, {"name": "a"}]}, policy) == [[{"name": "repeated repo ids", "value": ["a"]}], false, "value"]
}

test_unique_ids_never_fails_for_subjects_named_by_their_keys if {
	policy := {"s": object.union(owner_req.s, {"from": ["repos", {"each_as": "repo"}]})}
	unique_ids_row({"repos": {"x": {"name": "a"}, "y": {"name": "a"}}}, policy) == [[{"name": "repeated repo ids", "value": []}], true, "satisfied"]
}

test_unique_ids_passes_with_no_subjects_because_min_subjects_already_fails_the_requirement if {
	rep := report({}, owner_req)
	[[r.check, r.passed] | some r in rep.results; r.check in {"$min_subjects", "$unique_ids"}] == [["$min_subjects", false], ["$unique_ids", true]]
	rep.requirements.s.status == "not_met"
}

test_unique_ids_definition_is_in_the_check_table if {
	rows := [[d.description, d.expression] |
		some from in [["repos"], [], 5]
		d := report({}, {"s": object.union(owner_req.s, {"from": from})}).requirements.s.checks["$unique_ids"]
	]
	rows == [
		["Every repo id is unique", "count(repeated(ids(repos))) == 0"],
		["Every repo id is unique", "count(repeated(ids($input))) == 0"],
		["Every repo id is unique", "count(repeated(ids(<invalid from>))) == 0"],
	]
}

test_unique_ids_records_the_refs_in_from_and_id if {
	policy := {"s": object.union(owner_req.s, {
		"from": [{"ref": ["$$params", "list"]}],
		"id": [{"ref": ["$$params", "key"]}],
	})}
	rep := ergo.report({"repos": [{"name": "a"}, {"name": "a"}]}, lifted(policy), {"list": "repos", "key": "name"})
	rep.requirements.s.checks["$unique_ids"]["$refs"] == [{"name": "$params.key", "value": "name"}, {"name": "$params.list", "value": "repos"}]
	[v.inputs | some v in ergo.violations(rep); v.check == "$unique_ids"] == [[
		{"name": "repeated repo ids", "value": ["a"]},
		{"name": "$params.key", "value": "name"},
		{"name": "$params.list", "value": "repos"},
	]]
}

test_well_formed_passes_for_an_ordinary_requirement if {
	rep := report({"items": [{"id": "a"}]}, id_req(["items"]))
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_well_formed_fails_when_no_checks_are_declared if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.status == "not_met"
}

test_well_formed_fails_on_an_unrecognised_require_value if {
	rep := report(both_ok, require_req("most"))
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.status == "not_met"
}

test_well_formed_row_is_about_the_requirement_not_a_subject if {
	rep := report({"items": [{"id": "a"}, {"id": "b"}]}, id_req(["items"]))
	count(rows_for(rep, "s", "$well_formed")) == 1
	rows_for(rep, "s", "$well_formed")[0].subject == {"type": "thing", "id": null}
}

test_well_formed_does_not_depend_on_the_input if {
	with_items := report({"items": [{"id": "a"}]}, id_req(["items"]))
	without := report({}, id_req(["items"]))
	rows_for(with_items, "s", "$well_formed")[0] == rows_for(without, "s", "$well_formed")[0]
}

test_well_formed_echoes_a_valid_require_and_says_what_is_wrong_with_any_other if {
	rows_for(report(both_ok, require_req("some")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2},
		{"name": "require", "value": "some"},
	]
	rows_for(report(both_ok, require_req("most")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2},
		{"name": "require", "value": ["neither every nor some"]},
	]
}

test_a_requirement_that_is_not_an_object_stays_in_the_report_and_is_not_well_formed if {
	rows := [[name in object.keys(rep.requirements), rep.requirements[name].status, r.passed, r.inputs[2]] |
		some [name, req] in [["a", 5], ["b", null], ["c", [1]], ["d", "x"]]
		rep := report({"items": [{"id": 1}]}, {name: req})
		some r in rows_for(rep, name, "$well_formed")
	]
	rows == [
		[true, "not_met", false, {"name": "requirement", "value": 5}],
		[true, "not_met", false, {"name": "requirement", "value": null}],
		[true, "not_met", false, {"name": "requirement", "value": [1]}],
		[true, "not_met", false, {"name": "requirement", "value": "x"}],
	]
}

test_a_requirement_field_ergo_does_not_know_fails_well_formed if {
	rep := report({"releases": [{"id": "r-1", "signed": false}]}, {"s": {
		"from": ["releases"],
		"id": ["id"],
		"subjects": "release",
		"checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}},
	}})
	rep.requirements.s.status == "not_met"
	row := rows_for(rep, "s", "$well_formed")[0]
	row.passed == false
	row.inputs[2] == {"name": "subjects", "value": ["unknown field"]}
}

test_from_id_applies_to_and_subject_type_belong_to_the_subject_not_the_requirement if {
	rep := ergo.report(
		{"releases": [{"id": "r-1", "signed": true}]}, {
			"subjects": {"release": {"from": ["releases"], "id": ["id"]}},
			"requirements": {"s": {
				"subject": "release",
				"subject_type": "release",
				"from": ["releases"],
				"id": ["id"],
				"applies_to": {},
				"checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}},
			}},
		},
		{},
	)
	rep.requirements.s.status == "not_met"
	[r.inputs | some r in rows_for(rep, "s", "$well_formed")] == [[
		{"name": "count(checks)", "value": 1},
		{"name": "require", "value": "every"},
		{"name": "applies_to", "value": ["unknown field"]},
		{"name": "from", "value": ["unknown field"]},
		{"name": "id", "value": ["unknown field"]},
		{"name": "subject_type", "value": ["unknown field"]},
	]]
}

test_a_requirement_with_an_unknown_field_still_has_its_subject_rows if {
	rep := report({"items": [{"id": 1}, {"id": 2}]}, {"s": object.union(typed_req, {"subject": "item"})})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, true]]
}

test_unknown_requirement_fields_are_listed_in_order_and_say_what_is_wrong if {
	req := object.union(typed_req, {"requires": "some", "notes": "x", "title": "t"})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [
		{"name": "notes", "value": ["unknown field"]},
		{"name": "requires", "value": ["unknown field"]},
		{"name": "title", "value": ["unknown field"]},
	]
}

test_an_unknown_requirement_field_is_named_as_a_path if {
	req := object.union(typed_req, {"a b": 1})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [{"name": `"a b"`, "value": ["unknown field"]}]
}

test_unknown_requirement_keys_that_are_not_strings_are_listed_in_the_same_order_everywhere if {
	req := object.union(typed_req, {"zz": 2, 1: "x", true: 3})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [
		{"name": "<invalid key true>", "value": ["unknown field"]},
		{"name": "<invalid key 1>", "value": ["unknown field"]},
		{"name": "zz", "value": ["unknown field"]},
	]
}

test_every_requirement_field_ergo_knows_is_well_formed if {
	req := object.union(typed_req, {"subject_type": "item", "require": "some", "applies_to": {"a": {"op": "present", "path": ["id"]}}, "description": "d", "meta": {"m": "x"}})
	rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0].passed == true
}

test_a_requirement_description_and_meta_are_carried_into_the_report if {
	meta := {"control": "SDLC-CTRL-0007", "frameworks": ["SOC 2", "ISO 27001"], "none": []}
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"description": "Every item has an id", "meta": meta})})
	rep.requirements.s.description == "Every item has an id"
	rep.requirements.s.meta == meta
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_a_requirement_without_a_description_or_meta_reports_empty_ones_so_tools_can_read_them_without_checking if {
	rep := report({"items": [{"id": 1}]}, {"s": typed_req})
	rep.requirements.s.description == ""
	rep.requirements.s.meta == {}
}

test_meta_can_hold_anything_json_can if {
	meta := {"owner": {"name": "alice", "team": null}, "reviewed": true, "version": 2026, "ratio": 0.5, "tags": ["a", 1, false, [], {}], "note": "a<b>&c \"q\" \\ é\n\t\u0001\u2028\ufeff 😀", "a.b \"k\"": "", "": "empty key"}
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"meta": meta, "checks": {"c": {"op": "present", "path": ["id"], "meta": meta}}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.requirements.s.meta == meta
	rep.requirements.s.checks.c.meta == meta
}

test_numbers_in_meta_are_written_the_same_way_however_the_policy_wrote_them if {
	written := {"s": object.union(typed_req, {"meta": {"n": [1.50, 1e2, -0, 1.0, 2.5e-3]}, "checks": {"c": {"op": "present", "path": ["id"], "meta": {"n": 1E+2}}}})}
	plain := {"s": object.union(typed_req, {"meta": {"n": [1.5, 100, 0, 1, 0.0025]}, "checks": {"c": {"op": "present", "path": ["id"], "meta": {"n": 100}}}})}
	json.marshal(report({"items": [{"id": 1}]}, written)) == json.marshal(report({"items": [{"id": 1}]}, plain))
	json.marshal(report({"items": [{"id": 1}]}, written).requirements.s.meta) == `{"n":[1.5,100,0,1,0.0025]}`
}

numbers_req(value, bound, inner) := {"s": {"from": ["items"], "id": ["id"], "checks": {
	"eq": {"op": "equals", "path": ["n"], "value": value},
	"rg": {"op": "range", "path": ["n"], "min": -0.0, "max": bound},
	"ref": {"op": "equals", "path": ["n"], "value": {"ref": ["$$params", "p"]}},
	"all": {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": inner}},
}}}

test_numbers_in_the_report_are_written_in_their_plain_form_however_the_policy_input_and_params_wrote_them if {
	rep := ergo.report(
		{"items": [{"id": 1.0, "n": 1.50, "xs": [2.0, 3e0, 2.5e-3]}, {"id": 1e0, "n": -0.0, "xs": []}]},
		lifted(numbers_req(1.50, 1e1, 9.0)),
		{"p": 2.50},
	)
	checks := rep.requirements.s.checks
	json.marshal([checks.eq.value, checks.rg.min, checks.rg.max, named_values(checks.ref["$refs"]), checks.all.check.value]) == `[1.5,0,10,[["$params.p",2.5]],9]`
	json.marshal([[r.check, r.subject.id, named_values(r.inputs), [[f.path, f.value] | some f in object.get(r, "failed_items", [])]] | some r in rep.results; not startswith(r.check, "$")]) == `[["all",1,[["xs[]",[2,3,0.0025]]],[["item 1 of xs",2],["item 2 of xs",3],["item 3 of xs",0.0025]]],["eq",1,[["n",1.5]],[]],["ref",1,[["n",1.5]],[]],["rg",1,[["n",1.5]],[]],["all",1,[["xs[]",[]]],[]],["eq",1,[["n",0]],[]],["ref",1,[["n",0]],[]],["rg",1,[["n",0]],[]]]`
	json.marshal([[v.check, v.subject.id, named_values(v.inputs)] | some v in ergo.violations(rep)]) == `[["$unique_ids",null,[["repeated subject ids",[1]]]],["all",1,[["xs[]",[2,3,0.0025]]]],["ref",1,[["n",1.5],["$params.p",2.5]]],["all",1,[["xs[]",[]]]],["eq",1,[["n",0]]],["ref",1,[["n",0],["$params.p",2.5]]]]`
}

named_values(inputs) := [[i.name, i.value] | some i in inputs]

test_a_repeated_subject_id_is_written_the_same_way_whichever_spelling_comes_first if {
	ids := [json.marshal(rows_for(report({"items": items}, {"s": typed_req}), "s", "$unique_ids")[0].inputs[0].value) |
		some items in [[{"id": 1.0, "k": "a"}, {"id": 1e0, "k": "b"}], [{"id": 1e0, "k": "a"}, {"id": 1.0, "k": "b"}]]
	]
	ids == ["[1]", "[1]"]
}

test_a_number_a_float_cannot_hold_is_copied_into_the_report_as_written if {
	rep := report({"items": [{"id": 1, "n": 1e400}]}, {"s": object.union(typed_req, {"checks": {"c": {"op": "equals", "path": ["n"], "value": 1.50}}})})
	json.marshal([named_values(row.inputs) | some row in rep.results; row.check == "c"]) == `[[["n",1e400]]]`
}

test_a_number_is_written_in_its_plain_form_even_when_it_is_the_only_one_spelled_another_way if {
	written := [json.marshal([row.inputs[0].value | some row in report({"items": [{"id": "a", "n": n}]}, {"s": object.union(typed_req, {"checks": {"c": {"op": "present", "path": ["n"]}}})}).results; row.check == "c"]) |
		some n in [1.50, -0, 1e2, 2.5E-3, 10.0, [7, -0.0]]
	]
	written == ["[1.5]", "[0]", "[100]", "[0.0025]", "[10]", "[[7,0]]"]
}

test_a_report_from_a_policy_json_cannot_hold_is_left_as_built_so_rows_still_name_their_requirement if {
	every policy in [{1: typed_req}, [typed_req]] {
		rep := report({"items": [{"id": 1.50}]}, policy)
		every row in rep.results {
			rep.requirements[row.requirement].status == "not_met"
		}
	}
}

test_a_report_from_an_input_json_cannot_hold_is_left_as_built if {
	rep := report({"items": [{"id": 1.50, "t": {"a"}}]}, {"s": object.union(typed_req, {"checks": {"c": {"op": "present", "path": ["t"]}}})})
	some row in rep.results
	row.check == "c"
	is_set(row.inputs[0].value)
}

test_a_requirement_meta_that_json_cannot_hold_fails_well_formed_and_is_reported_empty if {
	rows := [[r.requirements.s.status, r.requirements.s.meta, problem_inputs(r)] |
		some m in [{1: "x"}, {"a": {"b": {2: "y"}}}, {"tags": {"a"}}, {"n": [1e400]}]
		r := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"meta": m})})
	]
	rows == [
		["not_met", {}, [{"name": "meta", "value": ["holds a key that isn't a string"]}]],
		["not_met", {}, [{"name": "meta", "value": ["holds a key that isn't a string"]}]],
		["not_met", {}, [{"name": "meta", "value": ["holds a set"]}]],
		["not_met", {}, [{"name": "meta", "value": ["number out of range"]}]],
	]
}

test_a_check_meta_that_json_cannot_hold_is_written_wrong_and_is_reported_empty if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"k": {"op": "present", "path": ["n"], "meta": {"a": {1: "x"}}},
		"s": {"op": "present", "path": ["n"], "meta": {"tags": {"a"}}},
		"r": {"op": "present", "path": ["n"], "meta": {"n": 1e400}},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.k", "value": ["meta holds a key that isn't a string"]},
		{"name": "checks.r", "value": ["number out of range"]},
		{"name": "checks.s", "value": ["meta holds a set"]},
	]
	[rep.requirements.s.checks[c].meta | some c in ["k", "r", "s"]] == [{}, {}, {}]
}

test_a_null_description_or_meta_counts_as_none_since_an_empty_yaml_field_reads_as_null if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"description": null, "meta": null, "checks": {"c": {"op": "present", "path": ["id"], "description": null, "meta": null}}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	[rep.requirements.s.description, rep.requirements.s.meta] == ["", {}]
	[rep.requirements.s.checks.c.description, rep.requirements.s.checks.c.meta] == ["", {}]
}

test_an_empty_requirement_meta_is_well_formed_and_reported if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"meta": {}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.requirements.s.meta == {}
}

test_a_requirement_description_or_meta_of_the_wrong_type_never_reaches_the_report if {
	reps := [report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"description": d, "meta": m})}) |
		some [d, m] in [[5, "x"], [false, 0], [["a"], ["m"]]]
	]
	[[r.requirements.s.status, r.requirements.s.description, r.requirements.s.meta] | some r in reps] == [
		["not_met", "", {}],
		["not_met", "", {}],
		["not_met", "", {}],
	]
}

test_a_requirement_that_is_not_an_object_reports_an_empty_description_and_meta if {
	rep := report({"items": [{"id": 1}]}, {"s": 5})
	rep.requirements.s.description == ""
	rep.requirements.s.meta == {}
}

two_reqs_policy(extra) := object.union(lifted({"s": typed_req, "t": typed_req}), extra)

test_a_policy_description_and_meta_are_copied_to_the_top_of_the_report if {
	meta := {"control": "DEV-0401", "title": "Security testing and code review"}
	rep := ergo.report({"items": [{"id": 1}]}, two_reqs_policy({"description": "Vulnerabilities are fixed in time", "meta": meta}), {})
	[rep.description, rep.meta, rep.compliant] == ["Vulnerabilities are fixed in time", meta, true]
	[r.passed | some r in rep.results; r.check == "$well_formed"] == [true, true]
}

test_a_policy_without_a_description_or_meta_reports_empty_ones_so_tools_can_read_them_without_checking if {
	every extra in [{}, {"description": null, "meta": null}] {
		rep := ergo.report({"items": [{"id": 1}]}, two_reqs_policy(extra), {})
		[rep.description, rep.meta, rep.compliant] == ["", {}, true]
	}
	every policy in [5, [], null] {
		rep := ergo.report({"items": [{"id": 1}]}, policy, {})
		[rep.description, rep.meta] == ["", {}]
	}
}

test_a_policy_description_or_meta_written_wrong_fails_every_requirement_since_it_belongs_to_none_of_them if {
	rows := [[r.description, r.meta, r.compliant, [[w.requirement, w.passed, problem_inputs_of(w)] | some w in r.results; w.check == "$well_formed"]] |
		some extra in [{"description": 5, "meta": "x"}, {"meta": {"a": {1: "x"}}}, {"meta": {"n": 1e400}}]
		r := ergo.report({"items": [{"id": 1}]}, two_reqs_policy(extra), {})
	]
	rows == [
		["", {}, false, [
			["s", false, [{"name": "$policy.description", "value": ["not a string"]}, {"name": "$policy.meta", "value": ["not an object"]}]],
			["t", false, [{"name": "$policy.description", "value": ["not a string"]}, {"name": "$policy.meta", "value": ["not an object"]}]],
		]],
		["", {}, false, [
			["s", false, [{"name": "$policy.meta", "value": ["holds a key that isn't a string"]}]],
			["t", false, [{"name": "$policy.meta", "value": ["holds a key that isn't a string"]}]],
		]],
		["", {}, false, [
			["s", false, [{"name": "$policy.meta", "value": ["number out of range"]}]],
			["t", false, [{"name": "$policy.meta", "value": ["number out of range"]}]],
		]],
	]
}

test_a_policy_description_and_meta_are_kept_when_it_is_rewritten_as_sentences if {
	policy := two_reqs_policy({"description": "d", "meta": {"control": "DEV-0401"}})
	converted := ergo.as_sentences(policy)
	[converted.description, converted.meta] == ["d", {"control": "DEV-0401"}]
}

problem_inputs_of(row) := [i |
	some i in row.inputs
	not i.name in {"count(checks)", "require"}
	not is_from(i.name)
]

badly_written_requirements := {
	"require_most": [{"require": "most"}, [{"name": "require", "value": ["neither every nor some"]}]],
	"require_number": [{"require": 5}, [{"name": "require", "value": ["neither every nor some"]}]],
	"checks_empty": [{"checks": {}}, [{"name": "require", "value": "every"}, {"name": "checks", "value": ["empty"]}]],
	"name_with_dollar": [{"from": ["items", {"each_as": "$x"}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["invalid name"]}]],
	"step_not_last": [{"from": [{"each_as": "x"}, "items"]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["object step before the last"]}]],
	"selector_in_from": [{"from": ["items", {"where": {"id": 1}}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["object step without each_as"]}]],
	"keys_without_name": [{"from": ["items", {"keys": ["a"]}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["object step without each_as"]}]],
	"naming_step_field": [{"from": ["items", {"each_as": "x", "foo": 1}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["unknown field foo in naming step"]}]],
	"naming_step_keys": [{"from": ["items", {"each_as": "x", "keys": 5}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["invalid keys"]}]],
	"from_step_not_key": [{"from": ["items", true]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["step that can't be a key"]}]],
	"from_out_of_range": [{"from": ["items", 1e400]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.from", "value": ["number out of range", "step that can't be a key"]}]],
	"id_step_not_key": [{"id": [1.5]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.id", "value": ["step that can't be a key"]}]],
	"id_ref_in_where": [{"id": [{"where": {"k": {"v": {"ref": ["$$params", "x"]}}}}]}, [{"name": "require", "value": "every"}, {"name": "subjects.subject.id", "value": ["ref inside where"]}]],
	"min_out_of_range": [{"min_subjects": 1e400}, [{"name": "require", "value": "every"}, {"name": "min_subjects", "value": ["number out of range"]}]],
}

test_every_way_a_requirement_is_written_wrong_says_what_is_wrong if {
	got := {name: [row.passed, array.slice(row.inputs, 1, count(row.inputs))] |
		some name, [fields, _] in badly_written_requirements
		base := {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}
		req := object.union(object.remove(base, object.keys(fields)), fields)
		row := rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0]
	}
	got == {name: [false, want] | some name, [_, want] in badly_written_requirements}
}

test_keys_that_are_not_strings_get_a_name_each if {
	req := object.union(typed_req, {true: 1, false: 2, null: 3, 1.5: 4, 2.5: 5})
	names := [i.name | some i in problem_inputs(report({"items": [{"id": 1}]}, {"s": req}))]
	names == ["<invalid key null>", "<invalid key false>", "<invalid key true>", "<invalid key 1.5>", "<invalid key 2.5>"]
}

test_a_min_subjects_that_is_not_a_number_says_so_even_holding_a_number_out_of_range if {
	every v in [[1e400], {"a": 1e400}] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == [{"name": "min_subjects", "value": ["not a whole number of 0 or more"]}]
	}
}

well_formed_or_not := array.concat(
	[object.union(object.remove(typed_req, object.keys(fields)), fields) | some [fields, _] in badly_written_requirements],
	array.concat(
		[object.union(typed_req, {f: v}) | some [f, v] in wrong_types],
		[
			typed_req,
			object.union(typed_req, {"require": "some", "subject_type": "item", "applies_to": {"a": {"op": "present", "path": ["id"]}}}),
			object.union(typed_req, {"from": ["items", {"each_as": "x", "keys": ["a"]}]}),
			object.union(typed_req, {"zz": 1}),
			object.union(typed_req, {"checks": {"c": {"op": "nope"}}}),
			{"from": ["items"]},
			{"from": ["items"], "checks": {}},
			5,
		],
	),
)

test_a_requirement_fails_well_formed_exactly_when_its_row_says_what_is_wrong if {
	lifted_reqs := [lifted({"s": req}) | some req in well_formed_or_not]
	well_formed := {i |
		some i, l in lifted_reqs
		resolved := ergo._resolved_subjects with data.ergo_subjects as l.subjects
		ergo._well_formed(l.requirements.s) with data.ergo_subjects as l.subjects with data.ergo_resolved as resolved
	}
	nothing_listed := {i |
		some i, l in lifted_reqs
		req := l.requirements.s
		resolved := ergo._resolved_subjects with data.ergo_subjects as l.subjects
		problems := (count(ergo._req_problems(req)) + count(ergo._check_problem_inputs(req))) + count(ergo._not_an_object_inputs(req)) with data.ergo_subjects as l.subjects with data.ergo_resolved as resolved
		problems == 0
	}
	well_formed == nothing_listed
	count(well_formed) > 2
	count(well_formed_or_not) - count(well_formed) > 30
}

test_a_requirement_without_checks_says_they_are_missing if {
	row := rows_for(report({"items": [{"id": 1}]}, {"s": {"from": ["items"]}}), "s", "$well_formed")[0]
	row.inputs == [{"name": "count(checks)", "value": 0}, {"name": "require", "value": "every"}, {"name": "checks", "value": ["missing"]}]
}

test_problems_with_several_fields_are_listed_by_field if {
	req := {"from": 5, "require": "most", "zz": 1, "checks": {}, "min_subjects": -1}
	row := rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0]
	row.inputs == [
		{"name": "count(checks)", "value": 0},
		{"name": "checks", "value": ["empty"]},
		{"name": "min_subjects", "value": ["not a whole number of 0 or more"]},
		{"name": "require", "value": ["neither every nor some"]},
		{"name": "zz", "value": ["unknown field"]},
		{"name": "subjects.subject.from", "value": ["not a list or a string"]},
	]
}

typed_req := {"from": ["items"], "id": ["id"], "min_subjects": 0, "checks": {"c": {"op": "present", "path": ["id"]}}}

wrong_types := [
	["applies_to", true],
	["applies_to", [{"op": "present", "path": ["id"]}]],
	["applies_to", null],
	["checks", 5],
	["checks", [{"op": "present", "path": ["id"]}]],
	["checks", null],
	["from", 5],
	["from", {"a": 1}],
	["from", null],
	["id", 5],
	["id", null],
	["min_subjects", "0"],
	["min_subjects", null],
	["min_subjects", -1],
	["min_subjects", 0.5],
	["min_subjects", 1.5],
	["subject_type", 3],
	["subject_type", {"name": "x"}],
	["subject_type", null],
	["description", 5],
	["description", false],
	["description", ["d"]],
	["meta", "x"],
	["meta", 0],
	["meta", ["x"]],
]

test_a_min_subjects_whose_value_is_a_whole_number_is_well_formed_however_it_is_written if {
	rows := [r.passed |
		some m in [0, 2.0, 1e2]
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [true, true, true]
}

wrong_type_problems := {
	"applies_to": "not an object",
	"checks": "not an object",
	"from": "not a list or a string",
	"id": "not a list or a string",
	"min_subjects": "not a whole number of 0 or more",
	"subject_type": "empty or not a string",
	"description": "not a string",
	"meta": "not an object",
}

test_a_field_of_the_wrong_type_fails_well_formed_and_says_what_it_should_be if {
	rows := [[f, "s" in object.keys(rep.requirements), rep.requirements.s.status, r.passed, r.cause, r.inputs[count(r.inputs) - 1]] |
		some [f, v] in wrong_types
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {f: v})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [[f, true, "not_met", false, "value", {"name": lifted_field_name(f), "value": [wrong_type_problems[f]]}] | some [f, _] in wrong_types]
}

lifted_field_name(f) := concat(".", ["subjects", "subject", f]) if f in subject_fields

lifted_field_name("subject_type") := "subject"

lifted_field_name(f) := f if not f in array.concat(subject_fields, ["subject_type"])

test_a_requirement_that_is_not_an_object_finds_no_subjects_so_it_cannot_claim_the_whole_input if {
	rep := report({"items": [{"id": 1}]}, {"s": 5})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "value"]]
}

test_a_from_that_is_not_a_list_records_no_refs_because_it_is_never_read if {
	rep := report({}, {"s": object.union(typed_req, {"from": {"ref": ["$$params", "p"]}})})
	not "$refs" in object.keys(rep.requirements.s.checks["$min_subjects"])
}

test_an_applies_to_that_is_not_an_object_fails_every_subject_as_ill_formed_so_none_is_blamed_for_a_check if {
	doc := {"items": [{"id": 1, "env": "dev"}, {"id": 2, "env": "prod"}]}
	reps := [report(doc, {"s": object.union(typed_req, {"applies_to": a})}) |
		some a in [[{"op": "equals", "path": ["env"], "value": "prod"}], true, null]
	]
	every rep in reps {
		[[r.check, r.subject.id, r.passed, r.cause, r.inputs] | some r in rep.results; not r.check in {"$well_formed", "$min_subjects", "$unique_ids"}] == [
			["$applies", 1, false, "ill_formed", []],
			["$applies", 2, false, "ill_formed", []],
		]
		rep.requirements.s.subjects == {"total": 2, "matching": 0}
		rep.requirements.s.checks["$applies"].expression == "<invalid applies_to>"
		[[v.check, v.subject.id] | some v in ergo.violations(rep)] == [["$well_formed", null], ["$applies", 1], ["$applies", 2]]
	}
	count(reps) == 3
}

test_a_field_of_the_right_type_adds_no_input_to_well_formed if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"applies_to": {"a": {"op": "present", "path": ["id"]}}})})
	row := rows_for(rep, "s", "$well_formed")[0]
	[row.passed, count(row.inputs)] == [true, 2]
}

test_checks_that_are_not_an_object_give_no_rows_named_by_list_index if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"checks": [{"op": "present", "path": ["id"]}]})})
	[r.check | some r in rep.results] == ["$well_formed", "$min_subjects", "$unique_ids"]
	rows_for(rep, "s", "$well_formed")[0].inputs[0] == {"name": "count(checks)", "value": 0}
}

test_a_from_that_is_not_a_list_gives_no_subjects if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": 5, "min_subjects": 1})})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

test_an_id_that_is_not_a_list_gives_a_null_id if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"id": 5})})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == [null]
}

test_a_min_subjects_that_is_not_a_number_fails_min_subjects_whatever_opa_thinks_of_comparing_it if {
	rows := [[r.passed, r.cause] |
		some m in ["0", null, [], {}]
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})})
		some r in rows_for(rep, "s", "$min_subjects")
	]
	rows == [[false, "value"], [false, "value"], [false, "value"], [false, "value"]]
}

test_min_subjects_names_the_whole_input_like_the_checks_do_when_from_reads_it if {
	rows := [[d.expression, r.inputs[0].name] |
		some m in [{}, {"from": []}, {"from": [{"each_as": "x"}]}]
		rep := report({"id": 1}, {"s": object.union({"checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
		d := rep.requirements.s.checks["$min_subjects"]
		some r in rows_for(rep, "s", "$min_subjects")
	]
	rows == [
		["count(matching($input)) >= 1", "in-scope subject count"],
		["count(matching($input)) >= 1", "in-scope subject count"],
		["count(matching($input)) >= 1", "in-scope subject count"],
	]
}

test_a_from_starting_with_a_dollar_key_is_quoted_because_from_takes_no_names_or_input if {
	rows := [[rep.requirements.s.checks["$min_subjects"].expression, rep.requirements.s.checks.c.expression] |
		some f in [["$$input"], ["$x", "a"], ["$schema", {"each_as": "x"}]]
		rep := report({}, {"s": {"from": f, "checks": {"c": {"op": "present", "path": []}}}})
	]
	rows == [
		[`count(matching("$$input")) >= 1`, `"$$input"[] is present`],
		[`count(matching("$x".a)) >= 1`, `"$x".a[] is present`],
		[`count(matching("$schema")) >= 1`, "$x is present"],
	]
}

problem_inputs(rep) := [i |
	some i in rows_for(rep, "s", "$well_formed")[0].inputs
	not i.name in {"count(checks)", "require"}
	not is_from(i.name)
]

is_from(name) if regex.match(`^subjects\.[^.]+\.from$`, name)

test_a_badly_written_check_fails_well_formed_and_says_where_and_what if {
	rep := report({"items": [{"id": 1}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"is_prod": {"op": "equals", "path": ["env"]}},
		"checks": {"merged": {"op": "equls", "path": ["state"], "value": "MERGED"}, "fine": {"op": "present", "path": ["id"]}},
	}})
	r := rows_for(rep, "s", "$well_formed")[0]
	[r.passed, r.cause] == [false, "value"]
	problem_inputs(rep) == [
		{"name": "checks.merged", "value": ["unknown op equls"]},
		{"name": "subjects.subject.applies_to.is_prod", "value": ["missing value"]},
	]
}

test_a_problem_inside_a_check_is_named_by_where_it_sits if {
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"signed": {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": ["v"]}},
		"reviewed": {"op": "present", "path": ["id"], "substitute": {"op": "nope"}},
		"permitted": {"op": "any_of", "options": {"standard": [{"op": "present", "path": ["id"]}, {"op": "in", "path": ["x"], "values": 3}]}},
		"a.b": {"op": "present", "path": ["id"], "as": "x"},
	}}})
	problem_inputs(rep) == [
		{"name": `checks."a.b"`, "value": ["as can't go here"]},
		{"name": "checks.permitted.options.standard.1", "value": ["invalid values"]},
		{"name": "checks.reviewed.substitute", "value": ["unknown op nope"]},
		{"name": "checks.signed.check", "value": ["missing value"]},
	]
}

test_a_path_that_is_not_a_list_is_written_wrong_even_when_it_names_one_key if {
	every path in ["state", "$$input", 3, {"a": 1}] {
		row_in({}, {"id": 1, "state": "OPEN", "$$input": "OPEN"}, {"op": "equals", "path": path, "value": "OPEN"}).cause == "ill_formed"
	}
}

test_a_path_that_is_not_a_list_is_ill_formed_even_on_a_subject_that_is_not_an_object if {
	row_in({}, "str", {"op": "present", "path": {"a": 1}}).cause == "ill_formed"
}

test_the_expression_of_a_check_whose_path_is_not_a_list_says_the_path_is_invalid if {
	every path in ["state", 3, {"a": 1}] {
		expression_in({}, {"id": 1, "state": "OPEN"}, {"op": "present", "path": path}) == "<invalid path> is present"
		expression_in({}, {"id": 1, "state": "OPEN"}, {"op": "in", "path": path, "values": ["a"]}) == "<invalid path> in [\"a\"]"
	}
}

test_a_compare_time_whose_sides_are_not_lists_reads_nothing if {
	row_in({}, {"id": 1, "a": "2026-01-01T00:00:00Z"}, {"op": "compare_time", "left": "a", "right": ["a"], "cmp": "eq"}).inputs == []
	row_in({}, {"id": 1, "a": "2026-01-01T00:00:00Z"}, {"op": "compare_time", "left": ["a"], "right": "a", "cmp": "eq"}).inputs == []
}

test_the_expression_of_a_compare_with_an_invalid_side_says_which_side if {
	subj := {"id": 1, "a": 1, "b": 2, "l": [1, 2]}
	every bad in ["a", 3, {"a": 1}, {"literal": 1, "x": 2}] {
		expression_in({}, subj, {"op": "compare", "left": bad, "right": ["b"], "cmp": "lt"}) == "<invalid left> lt b"
		expression_in({}, subj, {"op": "compare", "left": ["a"], "right": bad, "cmp": "lt"}) == ".a lt <invalid right>"
		expression_in({}, subj, {"op": "compare", "left": bad, "right": ["b"], "cmp": "lt", "within": 1}) == "<invalid left> lt b, within 1"
	}
}

test_the_expression_of_a_compare_with_an_invalid_side_next_to_a_derived_value_says_which_side if {
	subj := {"id": 1, "a": 1, "b": 2, "l": [1, 2]}
	expression_in({}, subj, {"op": "compare", "left": {"count": ["l"]}, "right": "b", "cmp": "lt"}) == "count(l) lt <invalid right>"
	expression_in({}, subj, {"op": "compare", "left": "b", "right": {"count": ["l"]}, "cmp": "lt", "within": 1}) == "<invalid left> lt count(l), within 1"
	expression_in({}, subj, {"op": "compare", "left": {"add": [["a"], ["b"]]}, "right": 5, "cmp": "lt"}) == ".a + b lt <invalid right>"
	expression_in({}, subj, {"op": "compare", "left": "a", "right": {"sum": ["l"], "each": []}, "cmp": "lt"}) == "<invalid left> lt sum(l[])"
}

test_a_compare_with_an_invalid_side_reads_nothing if {
	subj := {"id": 1, "a": 1, "b": 2, "l": [1, 2]}
	row_in({}, subj, {"op": "compare", "left": "a", "right": ["b"], "cmp": "lt"}).inputs == []
	row_in({}, subj, {"op": "compare", "left": ["a"], "right": "b", "cmp": "lt"}).inputs == []
	row_in({}, subj, {"op": "compare", "left": {"count": ["l"]}, "right": "b", "cmp": "lt"}).inputs == []
	row_in({}, subj, {"op": "compare", "left": "b", "right": {"add": [["a"], ["b"]]}, "cmp": "lt"}).inputs == []
	row_in({}, subj, {"op": "compare", "left": ["a"], "cmp": "lt"}).inputs == []
}

test_the_expression_of_a_compare_time_with_an_invalid_side_says_which_side if {
	subj := {"id": 1, "a": "2026-01-01T00:00:00Z", "b": "2026-01-02T00:00:00Z"}
	every bad in ["a", 3, {"a": 1}] {
		expression_in({}, subj, {"op": "compare_time", "left": bad, "right": ["b"], "cmp": "lt"}) == "<invalid left> lt b"
		expression_in({}, subj, {"op": "compare_time", "left": ["a"], "right": bad, "cmp": "lt"}) == ".a lt <invalid right>"
	}
}

test_a_check_whose_path_is_not_a_list_reads_nothing if {
	row_in({}, {"id": 1, "state": "OPEN"}, {"op": "present", "path": "state"}).inputs == []
}

test_a_custom_input_that_is_not_a_list_is_a_step_that_cannot_be_a_key if {
	rep := report({"items": [{"id": 1, "n": 2}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "even", "path": ["n"], "expression": "n is even", "inputs": [true]}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["step that can't be a key in inputs"]}]
}

test_well_formed_says_which_path_is_not_a_list if {
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"c": {"op": "even", "left": "a", "right": ["b"]},
		"d": {"op": "even", "left": ["a"], "right": 1},
		"e": {"op": "all", "path": ["xs"], "each": "a", "check": {"op": "equals", "path": [], "value": 1}},
		"f": {"op": "present", "path": "a"},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.c", "value": ["left not a list"]},
		{"name": "checks.d", "value": ["right not a list"]},
		{"name": "checks.e", "value": ["each not a list"]},
		{"name": "checks.f", "value": ["path not a list"]},
	]
}

test_well_formed_says_which_option_is_not_a_list if {
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "any_of", "options": {"standard": {"a": {"op": "present", "path": ["a"]}}, "other": []}}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["empty option other", "option standard not a list"]}]
}

test_a_check_with_several_problems_lists_them_in_order if {
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "range", "path": ["n", 1e400], "min": 9, "max": 1}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["min above max", "number out of range", "step that can't be a key in path"]}]
}

_within(name, base) if name == base

_within(name, base) if startswith(name, concat("", [base, "."]))

test_every_badly_written_check_fails_well_formed if {
	checks := {sprintf("c%d", [i]): c | some i, c in badly_written}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": checks}})
	rows_for(rep, "s", "$well_formed")[0].passed == false
	every i, _ in badly_written {
		some p in problem_inputs(rep)
		_within(p.name, sprintf("checks.c%d", [i]))
	}
}

test_a_ref_that_reads_the_wrong_kind_of_value_leaves_well_formed_alone_because_params_are_input if {
	every check in read_the_wrong_kind {
		rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		rows_for(rep, "s", "$well_formed")[0].passed == true
	}
}

test_a_name_given_by_from_is_known_and_any_other_is_not if {
	good := report({"prs": [{"n": 1}]}, {"s": {"from": ["prs", {"each_as": "pr"}], "id": ["n"], "checks": {"c": {"op": "present", "path": ["$pr", "n"]}}}})
	bad := report({"prs": [{"n": 1}]}, {"s": {"from": ["prs", {"each_as": "pr"}], "id": ["n"], "checks": {"c": {"op": "present", "path": ["$p", "n"]}}}})
	rows_for(good, "s", "$well_formed")[0].passed == true
	problem_inputs(bad) == [{"name": "checks.c", "value": ["unknown name $p"]}]
	[r.cause | some r in rows_for(bad, "s", "c")] == ["ill_formed"]
}

test_a_name_given_by_as_is_known_only_inside_its_check if {
	rep := report({"prs": [{"n": 1}]}, {"s": {"from": ["prs"], "id": ["n"], "checks": {"c": {"op": "any_of", "options": {
		"a": [{"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "present", "path": ["$approver", "id"]}}],
		"b": [{"op": "present", "path": ["$approver", "id"]}],
	}}}}})
	problem_inputs(rep) == [{"name": "checks.c.options.b.0", "value": ["unknown name $approver"]}]
}

test_a_badly_written_filter_fails_well_formed_too if {
	rep := report(typo_doc, typo_req({"op": "nope", "path": ["n"]}))
	problem_inputs(rep) == [{"name": "subjects.subject.applies_to.f", "value": ["unknown op nope"]}]
}

test_a_badly_written_filter_wins_over_one_that_rules_the_subject_out_because_scope_cannot_be_trusted if {
	rep := report(typo_doc, {"s": {
		"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {
			"out": {"op": "equals", "path": ["n"], "value": 2},
			"broken": {"op": "nope", "path": ["n"]},
		},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "ill_formed"]]
	[v.check | some v in ergo.violations(rep)] == ["$well_formed", "$applies"]
}

test_a_missing_parameter_shows_in_the_expression_instead_of_leaving_it_empty if {
	rows := [rendered({}, c) | some c in [
		{"op": "equals", "path": ["state"]},
		{"op": "equals", "value": 1},
		{"op": "includes", "path": ["xs"]},
		{"op": "excludes", "path": ["xs"]},
		{"op": "present"},
		{"op": "non_empty_string"},
		{"op": "missing"},
		{"op": "empty"},
		{"op": "range", "path": ["n"], "min": 0},
		{"op": "range", "path": ["n"]},
		{"op": "compare", "left": ["a"], "right": ["b"]},
		{"op": "compare_time", "left": ["a"], "cmp": "lt"},
		{"op": "all", "path": ["xs"]},
		{"op": "any", "check": {"op": "present", "path": ["v"]}},
		{"op": "any_of"},
	]]
	rows == [
		"state == <missing value>",
		"<missing path> == 1",
		"contains(xs, <missing value or values>)",
		"not contains(xs, <missing value or values>)",
		"<missing path> is present",
		"<missing path> is a non-empty string",
		"<missing path> is missing",
		"<missing path> is empty",
		"n >= 0 and n <= <missing max>",
		"n >= <missing min> and n <= <missing max>",
		".a <missing cmp> b",
		".a lt <missing right>",
		"every xs: <missing check>",
		"some <missing path>: v is present",
		"one of: <missing options>",
	]
}

odd_checks := [
	{"op": "any_of", "options": 5},
	{"op": "any_of", "options": {"a": 5}},
	{"op": "all", "path": 5, "check": {"op": "present", "path": []}},
	{"op": "range", "path": ["n"], "min": {"ref": 5}, "max": 1},
	{"op": "compare", "left": 5, "right": ["a"], "cmp": "eq"},
	{"op": "present", "path": "x"},
	{"op": "present", "path": {"a": 1}},
	{"op": "all", "path": ["xs"], "each": 5, "check": {"op": "present", "path": []}},
	{"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": [], "check": {}}}},
	{"op": {"x": 1}},
	{"op": null},
	{"op": "all"},
	{"op": "any_of", "options": []},
	{"op": "all", "path": ["xs"], "check": {"op": "any", "check": {"op": "present", "path": []}}},
	{"op": "all", "path": ["xs"], "check": {"op": "any", "path": ["ys"]}},
]

test_every_check_however_badly_written_keeps_an_expression_in_its_definition if {
	checks := {sprintf("c%d", [i]): c | some i, c in array.concat(badly_written, odd_checks)}
	defs := report({}, {"s": {"checks": checks}}).requirements.s.checks
	every name, _ in checks {
		is_string(defs[name].expression)
	}
}

test_a_missing_path_or_check_inside_a_nested_list_check_shows_in_the_expression if {
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "any", "check": {"op": "present", "path": []}}}) == "every xs: some <missing path>: <missing path>[] is present"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "any", "path": ["ys"]}}) == "every xs: some ys: <missing check>"
}

test_a_check_reading_a_name_nothing_gives_fails_the_requirement_even_when_no_subject_is_found if {
	rep := report({"items": []}, {"s": {"from": ["items"], "min_subjects": 0, "checks": {"c": {"op": "present", "path": ["$p", "id"]}}}})
	rep.requirements.s.status == "not_met"
	problem_inputs(rep) == [{"name": "checks.c", "value": ["unknown name $p"]}]
}

test_a_field_its_op_does_not_use_fails_well_formed if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"typo": {"op": "equals", "path": ["n"], "valeu": 1},
		"note": {"op": "equals", "path": ["n"], "value": 1, "descripton": "n is one"},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.note", "value": ["unknown field descripton"]},
		{"name": "checks.typo", "value": ["missing value", "unknown field valeu"]},
	]
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"note", "typo"}] == [["note", false, "ill_formed"], ["typo", false, "ill_formed"]]
}

test_an_unknown_field_inside_a_check_is_found_where_it_sits if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"inner": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [], "owner": "me"}},
		"sub": {"op": "present", "path": ["n"], "substitute": {"op": "present", "path": ["s"], "x": 1}},
		"opt": {"op": "any_of", "options": {"o": [{"op": "present", "path": ["n"], "y": 2}]}, "z": 3},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.inner.check", "value": ["unknown field owner"]},
		{"name": "checks.opt", "value": ["unknown field z"]},
		{"name": "checks.opt.options.o.0", "value": ["unknown field y"]},
		{"name": "checks.sub.substitute", "value": ["unknown field x"]},
	]
}

test_every_built_in_op_takes_its_own_fields_and_the_ones_every_check_can_have if {
	common := {"description": "d", "meta": {"m": "x"}, "expression": "e", "inputs": [["n"]], "substitute": {"op": "present", "path": ["n"]}}
	checks := {
		"range": {"op": "range", "path": ["n"], "min": 0, "max": 9},
		"excludes": {"op": "excludes", "path": ["xs"], "value": 5},
		"includes": {"op": "includes", "path": ["xs"], "value": 1},
		"in": {"op": "in", "path": ["n"], "values": [1]},
		"equals": {"op": "equals", "path": ["n"], "value": 1},
		"present": {"op": "present", "path": ["n"]},
		"non_empty_string": {"op": "non_empty_string", "path": ["s"]},
		"missing": {"op": "missing", "path": ["gone"]},
		"empty": {"op": "empty", "path": ["xs"]},
		"matches_any": {"op": "matches_any", "path": ["s"], "patterns": ["a"]},
		"not_matches_any": {"op": "not_matches_any", "path": ["s"], "patterns": ["b"]},
		"compare": {"op": "compare", "left": ["n"], "right": ["n"], "cmp": "eq"},
		"compare_time": {"op": "compare_time", "left": ["t"], "right": ["t"], "cmp": "eq"},
		"all": {"op": "all", "path": ["xs"], "each": [], "as": "x", "check": {"op": "present", "path": []}},
		"any": {"op": "any", "path": ["xs"], "each": [], "as": "x", "check": {"op": "present", "path": []}},
		"any_of": {"op": "any_of", "options": {"o": [{"op": "present", "path": ["n"]}]}},
	}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {name: object.union(c, common) | some name, c in checks}}})
	problem_inputs(rep) == []
	object.keys(checks) == {op | some op in ergo.operators; not op in {"even", "both_present", "multiple_of", "sees_only_its_fields"}}
}

test_a_check_meta_is_carried_into_the_report if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["n"], "meta": {"severity": "high", "refs": ["RB-1"]}}}}})
	problem_inputs(rep) == []
	rep.requirements.s.checks.c.meta == {"severity": "high", "refs": ["RB-1"]}
}

test_a_check_without_a_description_or_meta_reports_empty_ones_so_tools_can_read_them_without_checking if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["n"]}}}})
	rep.requirements.s.checks.c.description == ""
	rep.requirements.s.checks.c.meta == {}
}

test_a_check_description_or_meta_of_the_wrong_type_is_written_wrong_and_never_reaches_the_report if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"d": {"op": "present", "path": ["n"], "description": 5},
		"m": {"op": "present", "path": ["n"], "meta": "high"},
		"n": {"op": "present", "path": ["n"], "meta": []},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.d", "value": ["invalid description"]},
		{"name": "checks.m", "value": ["invalid meta"]},
		{"name": "checks.n", "value": ["invalid meta"]},
	]
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"d", "m", "n"}] == [["d", false, "ill_formed"], ["m", false, "ill_formed"], ["n", false, "ill_formed"]]
	rep.requirements.s.checks.d.description == ""
	rep.requirements.s.checks.m.meta == {}
	rep.requirements.s.checks.n.meta == {}
	[v.description | some v in ergo.violations(rep); v.check == "d"] == [""]
}

test_a_filter_description_and_meta_are_checked_but_the_shared_applies_entry_keeps_ergos_own if {
	rep := report({"items": [{"id": 1, "env": "prod"}]}, {"s": {"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "equals", "path": ["env"], "value": "prod", "description": "Production only", "meta": {"why": "scope"}}}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.requirements.s.checks["$applies"] == {"description": "The subject is in scope", "expression": `env == "prod"`, "meta": {}}
}

test_meta_can_sit_wherever_a_description_can if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "present", "path": ["n"], "meta": {"m": "x"}}}, "checks": {
		"inner": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [], "meta": {"m": "x"}}},
		"sub": {"op": "present", "path": ["n"], "substitute": {"op": "present", "path": ["s"], "meta": {"m": "x"}}},
		"opt": {"op": "any_of", "options": {"o": [{"op": "present", "path": ["n"], "meta": {"m": "x"}}]}},
	}}})
	problem_inputs(rep) == []
}

test_a_bad_meta_or_description_inside_a_check_is_found_where_it_sits if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "present", "path": ["n"], "description": 1}}, "checks": {
		"inner": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [], "meta": 5}},
		"sub": {"op": "present", "path": ["n"], "substitute": {"op": "present", "path": ["s"], "description": true}},
		"opt": {"op": "any_of", "options": {"o": [{"op": "present", "path": ["n"], "meta": ["x"]}]}},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.inner.check", "value": ["invalid meta"]},
		{"name": "checks.opt.options.o.0", "value": ["invalid meta"]},
		{"name": "checks.sub.substitute", "value": ["invalid description"]},
		{"name": "subjects.subject.applies_to.f", "value": ["invalid description"]},
	]
}

test_a_custom_op_keeps_its_own_fields_but_not_a_description_or_meta_of_the_wrong_type if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "multiple_of", "path": ["n"], "by": 1, "description": 5, "meta": "x"}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["invalid description", "invalid meta"]}]
}

test_every_check_in_the_report_has_a_description_and_meta_even_the_ones_ergo_adds if {
	rep := report({"items": [{"id": 1, "env": "prod"}]}, {"s": {"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "equals", "path": ["env"], "value": "prod"}}, "checks": {"c": {"op": "equals", "path": ["id"], "value": {"ref": ["$$params", "p"]}}}}})
	{name: [is_string(def.description), def.meta] | some name, def in rep.requirements.s.checks} == {
		"$applies": [true, {}],
		"$min_subjects": [true, {}],
		"$unique_ids": [true, {}],
		"$well_formed": [true, {}],
		"c": [true, {}],
	}
}

test_a_custom_op_keeps_any_fields_it_likes if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "multiple_of", "path": ["n"], "by": 1, "owner": "me", "expression": "n is whole", "inputs": [["n"]]}}}})
	problem_inputs(rep) == []
	[r.cause | some r in rows_for(rep, "s", "c")] == ["satisfied"]
}

test_a_list_check_without_from_is_described if {
	rep := report({"xs": [1]}, {"s": {"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": []}}}}})
	rep.requirements.s.checks.c.expression == "every xs: xs[] is present"
}

kinds_doc := {"items": [{"id": 1, "s": "x", "n": 5, "o": {"a": 1}, "e": [], "l": [1], "t": "2026-01-01T00:00:00Z", "bad_t": "2026-02-30T00:00:00Z"}]}

kind_cause(check) := [r.cause | some r in rows_for(report(kinds_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0]

kind_filter(check) := [rep.requirements.s.status, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := report(kinds_doc, {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"f": check}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
}

test_a_value_the_op_cannot_use_fails_as_unusable_and_a_filter_cannot_rule_the_subject_out_with_it if {
	every check in [
		{"op": "range", "path": ["s"], "min": 0, "max": 9},
		{"op": "matches_any", "path": ["n"], "patterns": ["x"]},
		{"op": "not_matches_any", "path": ["n"], "patterns": ["x"]},
		{"op": "includes", "path": ["s"], "value": "x"},
		{"op": "excludes", "path": ["s"], "value": "y"},
		{"op": "all", "path": ["o"], "check": {"op": "present", "path": []}},
		{"op": "any", "path": ["s"], "check": {"op": "present", "path": []}},
		{"op": "compare", "left": ["n"], "right": ["s"], "cmp": "eq"},
		{"op": "compare", "left": ["o"], "right": ["o"], "cmp": "lt"},
		{"op": "compare_time", "left": ["n"], "right": ["t"], "cmp": "lt"},
		{"op": "compare_time", "left": ["bad_t"], "right": ["t"], "cmp": "lt"},
		{"op": "compare_time", "left": ["o"], "right": ["o"], "cmp": "eq"},
		{"op": "empty", "path": ["s"]},
		{"op": "empty", "path": ["o"]},
		{"op": "missing", "path": ["s", "x"]},
		{"op": "missing", "path": ["l", "x"]},
		{"op": "missing", "path": ["o", 0]},
	] {
		kind_cause(check) == "unusable"
		kind_filter(check) == ["not_met", ["unusable"]]
	}
}

test_a_value_ergo_could_use_that_does_not_pass_stays_value if {
	every check in [
		{"op": "equals", "path": ["n"], "value": "5"},
		{"op": "in", "path": ["n"], "values": ["5"]},
		{"op": "non_empty_string", "path": ["n"]},
		{"op": "all", "path": ["e"], "check": {"op": "present", "path": []}},
		{"op": "any", "path": ["e"], "check": {"op": "present", "path": []}},
		{"op": "excludes", "path": ["l"], "value": 1},
		{"op": "empty", "path": ["l"]},
		{"op": "missing", "path": ["n"]},
		{"op": "missing", "path": ["e"]},
	] {
		kind_cause(check) == "value"
		kind_filter(check) == ["not_applicable", ["value"]]
	}
}

approvers_doc(approvers) := {"items": [{"id": 1, "approvers": approvers}]}

not_a_bot := {"op": "any", "path": ["approvers"], "check": {"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]}}

every_human := {"op": "all", "path": ["approvers"], "check": {"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]}}

item_cause(check, approvers) := [r.cause | some r in rows_for(report(approvers_doc(approvers), {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0]

test_a_list_check_takes_the_worst_cause_of_its_failing_items if {
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {}]) == "absent"
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {"username": 42}]) == "unusable"
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {"username": "dependabot[bot]"}]) == "value"
	item_cause(every_human, [{"username": "renovate[bot]"}, {}]) == "absent"
	item_cause(every_human, [{"username": "renovate[bot]"}, {"username": "ann"}]) == "value"
	item_cause(every_human, [{"username": "ann"}, {"username": null}]) == "null"
}

test_a_filter_cannot_rule_out_a_subject_whose_items_could_not_be_read if {
	rep := report(approvers_doc([{"username": "renovate[bot]"}, {}]), {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"f": not_a_bot}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_each_takes_the_cause_of_its_inner_lists if {
	check := {"op": "all", "path": ["prs"], "each": ["commits"], "check": {"op": "present", "path": ["sha"]}}
	causes := [[r.passed, r.cause] |
		some prs in [[{"commits": [{"sha": "a"}]}, {}], [{"commits": "a"}], [{"commits": []}], [{"commits": [{"sha": "a"}]}]]
		some r in rows_for(report({"items": [{"id": 1, "prs": prs}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == [[false, "absent"], [false, "unusable"], [false, "value"], [true, "satisfied"]]
}

test_a_nested_list_check_takes_the_worst_cause_of_its_inner_items if {
	check := {"op": "all", "path": ["prs"], "check": {"op": "all", "path": ["commits"], "check": {"op": "range", "path": ["n"], "min": 0, "max": 9}}}
	causes := [r.cause |
		some commits in [[{"n": 1}, {"n": 99}], [{"n": 1}, {}], [{"n": 1}, {"n": "x"}]]
		some r in rows_for(report({"items": [{"id": 1, "prs": [{"commits": commits}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == ["value", "absent", "unusable"]
}

test_an_any_of_inside_a_list_check_takes_the_worst_cause_of_its_options if {
	check := {"op": "any", "path": ["xs"], "check": {"op": "any_of", "options": {"a": [{"op": "equals", "path": ["k"], "value": 1}], "b": [{"op": "range", "path": ["n"], "min": 0, "max": 9}]}}}
	causes := [r.cause |
		some xs in [[{"k": 2, "n": 99}], [{"k": 2}], [{"k": 2, "n": "x"}]]
		some r in rows_for(report({"items": [{"id": 1, "xs": xs}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == ["value", "absent", "unusable"]
}

test_a_list_check_that_passes_in_an_option_adds_nothing_to_the_cause_even_when_an_item_could_not_be_read if {
	check := {"op": "any_of", "options": {"o": [
		{"op": "any", "path": ["xs"], "check": {"op": "equals", "path": ["k"], "value": 1}},
		{"op": "equals", "path": ["n"], "value": 1},
	]}}
	rep := report({"items": [{"id": 1, "n": 2, "xs": [{"k": 1}, {}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[r.cause | some r in rows_for(rep, "s", "c")] == ["value"]
}

lockfile_req(filters) := {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": filters, "checks": {"c": {"op": "equals", "path": ["hashed"], "value": true}}}}

lockfile_scope(item, filters) := [rep.requirements.s.status, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := report({"items": [item]}, lockfile_req(filters))
}

test_a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_other_filters_read if {
	filters := {"recorded": {"op": "present", "path": ["status"]}, "attested": {"op": "equals", "path": ["status"], "value": "COMPLETE"}}
	lockfile_scope({"id": 1}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": null}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1}, object.union(filters, {"other": {"op": "equals", "path": ["owner"], "value": "me"}})) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "PENDING"}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "COMPLETE", "hashed": true}, filters) == ["met", ["satisfied"]]
}

test_a_present_filter_does_not_win_over_a_filter_written_wrong if {
	lockfile_scope({"id": 1}, {"recorded": {"op": "present", "path": ["status"]}, "broken": {"op": "nope"}}) == ["not_met", ["ill_formed"]]
}

test_a_present_filter_that_cannot_reach_its_field_does_not_rule_the_subject_out if {
	filters := {"recorded": {"op": "present", "path": ["atts", {"where": {"k": "lock"}}, "status"]}, "env": {"op": "equals", "path": ["env"], "value": "prod"}}
	lockfile_scope({"id": 1, "atts": [], "env": "dev"}, filters) == ["not_met", ["unmatched"]]
}

test_present_on_a_missing_field_is_a_clean_no_wherever_it_is if {
	doc := {"items": [{"id": 1, "approvers": [{"username": "renovate[bot]"}, {}]}]}
	human := {"op": "any", "path": ["approvers"], "check": {"op": "any_of", "options": {"human": [
		{"op": "present", "path": ["username"]},
		{"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]},
	]}}}
	as_check := report(doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["owner"]}, "h": human}}})
	[[r.check, r.cause] | some r in as_check.results; r.check in {"c", "h"}] == [["c", "value"], ["h", "value"]]
	as_filter := report(doc, {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"h": human}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
	[as_filter.requirements.s.status, [r.cause | some r in rows_for(as_filter, "s", "$applies")]] == ["not_applicable", ["value"]]
}

test_present_that_cannot_reach_its_field_is_not_a_clean_no if {
	causes := [[r.cause | some r in rows_for(report({"items": [item]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0] |
		some [item, check] in [
			[{"id": 1, "xs": []}, {"op": "present", "path": ["xs", {"where": {"k": 1}}, "v"]}],
		]
	]
	causes == ["unmatched"]
	[r.cause | some r in rows_for(report({"items": ["x"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "present", "path": ["a"]}}}}), "s", "c")] == ["not_an_object"]
}

test_a_path_starting_with_a_reserved_double_dollar_name_is_ill_formed if {
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["$$foo", "x"], "value": 1}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["unknown name $$foo"]}]
	[r.cause | some r in rows_for(rep, "s", "c")] == ["ill_formed"]
}

test_an_empty_subject_name_fails_well_formed_because_rows_and_descriptions_would_name_nothing if {
	every name in ["", " ", "\t "] {
		rep := ergo.report({"items": [{"id": 1}]}, named_subject_policy(name), {})
		row := rows_for(rep, "s", "$well_formed")[0]
		[row.passed, row.inputs[count(row.inputs) - 1]] == [false, {"name": "subject", "value": ["empty or not a string"]}]
	}
	rep := ergo.report({"items": [{"id": 1}]}, named_subject_policy("a b"), {})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.results[0].subject.type == "a b"
}

named_subject_policy(name) := {
	"subjects": {name: {"from": ["items"], "id": ["id"]}},
	"requirements": {"s": {"subject": name, "checks": {"c": {"op": "present", "path": ["id"]}}}},
}

plain_defs(req) := report({"items": [{"id": 1}]}, {"s": object.union({"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "present", "path": ["id"]}}, "checks": {"c": {"op": "present", "path": ["id"]}}}, req)}).requirements.s.checks

test_the_checks_ergo_adds_are_described_in_plain_words if {
	defs := plain_defs({"subject_type": "deployment"})
	defs["$min_subjects"].description == "The in-scope deployment count is at least 1"
	defs["$applies"].description == "The deployment is in scope"
	defs["$well_formed"].description == "The requirement is written correctly"
	plain_defs({"subject_type": "deployment", "min_subjects": 2})["$min_subjects"].description == "The in-scope deployment count is at least 2"
	plain_defs({"subject_type": "deployment", "min_subjects": 0})["$min_subjects"].description == "The deployment list can be read"
	plain_defs({})["$min_subjects"].description == "The in-scope subject count is at least 1"
	plain_defs({})["$applies"].description == "The subject is in scope"
}

test_the_well_formed_description_is_the_same_with_a_naming_step if {
	rep := report({"items": []}, {"s": {"from": ["items", {"each_as": "it"}], "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rep.requirements.s.checks["$well_formed"].description == "The requirement is written correctly"
}

test_min_subjects_names_its_input_after_what_it_counts if {
	rep := report({"items": []}, {"s": {"subject_type": "deployment", "from": ["items"], "checks": {"c": {"op": "present", "path": ["id"]}}}})
	[r.inputs | some r in rows_for(rep, "s", "$min_subjects")] == [[{"name": "in-scope deployment count", "value": 0}]]
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_well_formed_definition_is_in_the_check_table if {
	rep := report({"items": [{"id": "a"}]}, id_req(["items"]))
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

require_req(q) := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"require": q,
	"checks": {
		"signed": {"op": "equals", "path": ["signed"], "value": true},
		"reviewed": {"op": "equals", "path": ["reviewed"], "value": true},
	},
}}

both_ok := {"items": [{"id": "a", "signed": true, "reviewed": true}]}

split_across_subjects := {"items": [
	{"id": "a", "signed": true, "reviewed": false},
	{"id": "b", "signed": false, "reviewed": true},
]}

test_every_met_when_all_subjects_pass if {
	doc := {"items": [
		{"id": "a", "signed": true, "reviewed": true},
		{"id": "b", "signed": true, "reviewed": true},
	]}
	report(doc, require_req("every")).requirements.s.status == "met"
}

test_every_not_met_when_one_subject_fails if {
	report(split_across_subjects, require_req("every")).requirements.s.status == "not_met"
}

test_some_met_when_one_subject_passes_every_check if {
	report(both_ok, require_req("some")).requirements.s.status == "met"
}

test_some_not_met_when_checks_are_split_across_subjects if {
	report(split_across_subjects, require_req("some")).requirements.s.status == "not_met"
}

test_some_not_met_without_subjects if {
	report({"items": []}, require_req("some")).requirements.s.status == "not_met"
}

some_req_zero := {"s": object.union(require_req("some").s, {"min_subjects": 0})}

test_some_with_min_subjects_zero_is_not_applicable_when_empty if {
	rep := report({"items": []}, some_req_zero)
	rep.requirements.s.status == "not_applicable"
	rep.compliant == true
}

test_some_without_min_subjects_zero_still_denies_an_empty_collection if {
	report({"items": []}, require_req("some")).requirements.s.status == "not_met"
}

test_some_with_min_subjects_zero_still_denies_when_no_subject_passes if {
	rep := report(split_across_subjects, some_req_zero)
	rep.requirements.s.status == "not_met"
	count(ergo.violations(rep)) > 0
}

test_some_with_min_subjects_zero_is_not_applicable_when_the_filter_empties_the_scope if {
	scoped := {"s": object.union(some_req_zero.s, {"applies_to": merged_only})}
	report({"items": [{"id": "a", "state": "CLOSED"}]}, scoped).requirements.s.status == "not_applicable"
}

test_some_still_records_rows_for_the_failing_subjects if {
	rep := report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	rep.requirements.s.status == "met"
	count([r | some r in rep.results; r.passed == false]) == 1
}

test_require_defaults_to_every if {
	rep := report(split_across_subjects, require_req("every"))
	defaulted := report(split_across_subjects, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": require_req("every").s.checks,
	}})
	defaulted.requirements.s.require == "every"
	defaulted.requirements.s.status == rep.requirements.s.status
}

test_unknown_require_value_is_not_met if {
	report(both_ok, require_req("most")).requirements.s.status == "not_met"
}

test_compliant_when_every_requirement_is_met if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "min_subjects": 1, "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "min_subjects": 1, "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	report(doc, policy).compliant == true
}

test_not_compliant_when_any_requirement_is_not_met if {
	doc := {"a": [{"id": "1"}], "b": [{"no_id": true}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	report(doc, policy).compliant == false
}

prod_only := {"s": {
	"subject_type": "deployment",
	"from": ["deployments"],
	"id": ["id"],
	"min_subjects": 0,
	"applies_to": {"prod": {"op": "equals", "path": ["env"], "value": "prod"}},
	"checks": {"approved": {"op": "present", "path": ["approved_by"]}},
}}

test_a_requirement_is_met_not_met_or_not_applicable if {
	statuses := [report({"deployments": ds}, prod_only).requirements.s.status | some ds in [
		[{"id": 1, "env": "prod", "approved_by": "ann"}],
		[{"id": 1, "env": "prod"}],
		[{"id": 1, "env": "dev"}],
		[],
	]]
	statuses == ["met", "not_met", "not_applicable", "not_applicable"]
}

test_a_requirement_is_only_not_applicable_when_it_would_otherwise_be_met if {
	statuses := [report({"deployments": [{"id": 1, "env": "dev"}]}, {"s": object.union(prod_only.s, change)}).requirements.s.status | some change in [
		{"min_subjects": 1},
		{"require": "most"},
		{"checks": {"approved": {"op": "nope"}}},
		{"applies_to": {"prod": {"op": "equals", "path": ["region"], "value": "eu"}}},
	]]
	statuses == ["not_met", "not_met", "not_met", "not_met"]
}

test_a_requirement_with_repeated_ids_and_nothing_in_scope_is_not_met if {
	doc := {"deployments": [{"id": 1, "env": "dev"}, {"id": 1, "env": "dev"}]}
	report(doc, prod_only).requirements.s.status == "not_met"
}

test_compliant_when_every_requirement_is_not_applicable if {
	rep := report({"deployments": [{"id": 1, "env": "dev"}]}, prod_only)
	rep.requirements.s.status == "not_applicable"
	rep.compliant == true
}

test_compliant_when_requirements_are_met_or_not_applicable if {
	policy := {"a": prod_only.s, "b": object.remove(prod_only.s, ["applies_to"])}
	rep := report({"deployments": [{"id": 1, "env": "dev", "approved_by": "ann"}]}, policy)
	[rep.requirements.a.status, rep.requirements.b.status] == ["not_applicable", "met"]
	rep.compliant == true
}

test_not_compliant_when_one_requirement_is_not_applicable_and_another_is_not_met if {
	policy := {"a": prod_only.s, "b": object.remove(prod_only.s, ["applies_to"])}
	rep := report({"deployments": [{"id": 1, "env": "dev"}]}, policy)
	[rep.requirements.a.status, rep.requirements.b.status] == ["not_applicable", "not_met"]
	rep.compliant == false
}

test_a_condition_on_the_input_can_make_a_requirement_not_applicable_while_unknown_values_still_count if {
	req := {"s": {
		"subject_type": "deployment",
		"from": [],
		"min_subjects": 0,
		"applies_to": {"needs_tests": {
			"op": "excludes",
			"path": ["$$params", "untested_change_types"],
			"value": {"ref": ["$$input", "deployment", "change_type"]},
		}},
		"checks": {
			"tested": {"op": "any", "path": ["test_runs"], "check": {"op": "present", "path": ["status"]}},
			"passed": {"op": "all", "path": ["test_runs"], "check": {"op": "equals", "path": ["status"], "value": "passed"}},
		},
	}}
	statuses := [report(doc, req).requirements.s.status |
		some doc in [
			{"deployment": {"change_type": "new_development"}, "test_runs": []},
			{"deployment": {"change_type": "new_development"}, "test_runs": [{"status": "passed"}]},
			{"deployment": {"change_type": "bug_fix"}, "test_runs": []},
			{"deployment": {"change_type": "hotfix"}, "test_runs": []},
			{"deployment": {}, "test_runs": []},
		]
	] with data.params as {"untested_change_types": ["bug_fix", "refactor"]}
	statuses == ["not_met", "met", "not_applicable", "not_met", "not_met"]
}

failing_row := {"requirement": "s", "subject": {"id": 1, "type": "t"}, "check": "c", "passed": false, "inputs": [], "cause": "value"}

test_violations_keep_the_failing_rows_of_a_requirement_whose_status_is_not_met_missing_or_unknown if {
	kept := [count(ergo.violations({"requirements": {"s": entry}, "results": [failing_row]})) |
		some entry in [{"status": "not_met"}, {}, {"status": "maybe"}, {"status": true}, {"satisfied": true}]
	]
	kept == [1, 1, 1, 1, 1]
}

test_violations_drop_the_failing_rows_of_a_requirement_that_is_met_or_not_applicable if {
	kept := [count(ergo.violations({"requirements": {"s": {"status": s}}, "results": [failing_row]})) |
		some s in ["met", "not_applicable"]
	]
	kept == [0, 0]
}

test_report_has_one_entry_per_declared_requirement if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	object.keys(report(doc, policy).requirements) == {"first", "second"}
}

test_requirement_entry_carries_exactly_the_documented_keys if {
	rep := solo({"state": "MERGED"}, is_merged)
	object.keys(rep.requirements.s) == {"description", "meta", "require", "status", "causes", "subjects", "checks"}
}

test_report_carries_exactly_the_documented_keys if {
	object.keys(solo({}, is_merged)) == {"compliant", "description", "meta", "requirements", "results"}
}

test_report_is_deterministic if {
	doc := {"items": [{"id": "b", "state": "MERGED"}, {"id": "a", "state": "CLOSED"}]}
	rep := report(doc, two_check_req)
	json.marshal(rep) == json.marshal(report(doc, two_check_req))
}

test_row_order_is_independent_of_policy_key_order if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	first := {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}
	second := {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}

	json.marshal(report(doc, {"first": first, "second": second})) == json.marshal(report(doc, {"second": second, "first": first}))
}

test_row_order_groups_by_check_kind_then_requirement if {
	req := {
		"subject_type": "t",
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"live": {"op": "equals", "path": ["live"], "value": true}},
		"checks": {
			"zeta": {"op": "present", "path": ["id"]},
			"alpha": {"op": "present", "path": ["id"]},
		},
	}
	doc := {"items": [{"id": "s2", "live": true}, {"id": "s1", "live": false}]}

	sequence := [[r.requirement, r.check, r.subject.id] |
		some r in report(doc, {"zzz": req, "aaa": req}).results
	]
	sequence == [
		["aaa", "$well_formed", null],
		["zzz", "$well_formed", null],
		["aaa", "$min_subjects", null],
		["zzz", "$min_subjects", null],
		["aaa", "$unique_ids", null],
		["zzz", "$unique_ids", null],
		["aaa", "$applies", "s2"],
		["aaa", "$applies", "s1"],
		["zzz", "$applies", "s2"],
		["zzz", "$applies", "s1"],
		["aaa", "alpha", "s2"],
		["aaa", "zeta", "s2"],
		["zzz", "alpha", "s2"],
		["zzz", "zeta", "s2"],
	]
}

test_requirements_come_out_in_name_order_whatever_the_runtime if {
	req := {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}
	rep := report({"items": [{"id": 1}]}, {"t": req, "s": req, "delta": req, "alpha": req, "gamma": req, "beta": req})
	[r.requirement | some r in rep.results; r.check == "c"] == ["alpha", "beta", "delta", "gamma", "s", "t"]
}

test_checks_come_out_in_name_order_whatever_the_runtime if {
	check := {"op": "present", "path": ["id"]}
	rep := report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check, "b": check, "a": check, "delta": check, "gamma": check}}})
	[r.check | some r in rep.results; not startswith(r.check, "$")] == ["a", "b", "c", "delta", "gamma"]
}

test_a_policy_written_as_a_set_still_gets_its_rows if {
	policy := {"subjects": {"item": {"from": ["items"], "id": ["id"]}}, "requirements": {{"subject": "item", "checks": {"c": {"op": "present", "path": ["id"]}}}}}
	[r.check | some r in ergo.report({"items": [{"id": 1}]}, policy, {}).results] == ["$well_formed", "$min_subjects", "$unique_ids", "c"]
}

test_inputs_written_as_an_object_come_out_in_key_order if {
	check := {"op": "bespoke", "inputs": {"alpha": ["a"], "beta": ["b"], "gamma": ["c"], "delta": ["d"]}}
	[i.name | some i in inputs_of({"a": 1, "b": 2, "c": 3, "d": 4}, check)] == [".a", "b", "d", "c"]
}

test_an_option_written_as_an_object_is_shown_as_invalid if {
	check := {"op": "any_of", "options": {"o": {
		"alpha": {"op": "present", "path": ["a"]},
		"beta": {"op": "present", "path": ["b"]},
	}}}
	rendered({}, check) == "one of: o(<invalid option>)"
	rendered({"xs": []}, {"op": "all", "path": ["xs"], "check": check}) == "every xs: one of: o(<invalid option>)"
}

test_an_op_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": {"ref": ["a"]}, "path": ["x"]}) == `<unknown op {"ref": ["a"]}>`
	rendered({}, {"op": null, "path": ["x"]}) == "<unknown op null>"
	rendered({}, {"op": 1.50, "path": ["x"]}) == "<unknown op 1.5>"
}

test_a_cmp_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": {"x": 1}}) == `.a {"x": 1} b`
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": null}) == ".a null b"
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": 1.5}) == ".a 1.5 b"
}

test_an_option_name_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": "any_of", "options": {[{"op": "present", "path": ["a"]}]}}) == `one of: [{"op": "present", "path": ["a"]}](.a is present)`
}

checks_for(subject) := ergo.report({"xs": [{"id": 1}]}, {"requirements": {"s": {"subject": subject, "checks": {"c": {"op": "present", "path": ["id"]}}}}}, {}).requirements.s.checks

test_a_subject_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	checks_for(["a", "b"])["$min_subjects"].description == `The in-scope ["a", "b"] count is at least 1`
	checks_for(null)["$unique_ids"].description == "Every null id is unique"
	checks_for(-1)["$unique_ids"].description == "Every -1 id is unique"
}

test_a_number_written_with_a_plus_in_its_exponent_is_written_in_full if {
	rendered({}, {"op": "equals", "path": ["x"], "value": 1e+21}) == "x == 1000000000000000000000"
	rendered({}, {"op": "equals", "path": ["x"], "value": 2.5e+30}) == "x == 2500000000000000000000000000000"
}

test_every_row_resolves_to_one_check_definition if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"applies_to": merged_only})}
	rep := report(two_states, scoped)
	every row in rep.results {
		count([def |
			some name, req in rep.requirements
			name == row.requirement
			some check_name, def in req.checks
			check_name == row.check
		]) == 1
	}
}

violating_req := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"checks": {
		"signed": {"description": "Signed", "op": "equals", "path": ["signed"], "value": true},
		"reviewed": {"description": "Reviewed", "op": "equals", "path": ["reviewed"], "value": true},
	},
}}

test_violations_are_empty_for_a_compliant_report if {
	rep := report({"items": [{"id": "a", "signed": true, "reviewed": true}]}, violating_req)
	rep.compliant == true
	ergo.violations(rep) == []
}

test_violation_entry_carries_exactly_the_documented_keys if {
	rep := report({"items": [{"id": "a"}]}, violating_req)
	count(ergo.violations(rep)) == 2
	every v in ergo.violations(rep) {
		object.keys(v) == {"requirement", "subject", "check", "description", "expression", "inputs", "cause"}
	}
}

test_violations_join_the_definition_onto_the_row if {
	rep := report({"items": [{"id": "a", "signed": true}]}, violating_req)
	ergo.violations(rep) == [{
		"requirement": "s",
		"subject": {"type": "thing", "id": "a"},
		"check": "reviewed",
		"description": "Reviewed",
		"expression": "reviewed == true",
		"inputs": [{"name": "reviewed", "value": null}],
		"cause": "absent",
	}]
}

test_violations_default_a_missing_description_to_an_empty_string if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": {"undescribed": {"op": "equals", "path": ["x"], "value": 1}},
	}})
	v := ergo.violations(rep)
	count(v) == 1
	v[0].description == ""
	v[0].expression == "x == 1"
}

test_violations_exclude_passing_rows if {
	rep := report({"items": [{"id": "a", "signed": true}]}, violating_req)
	[v.check | some v in ergo.violations(rep)] == ["reviewed"]
}

test_violations_include_min_subjects_failures if {
	rep := report({"items": []}, min_subjects_req(1))
	v := ergo.violations(rep)
	count(v) == 1
	v[0].check == "$min_subjects"
	v[0].subject == {"type": "thing", "id": null}
	v[0].description == "The in-scope thing count is at least 1"
}

test_violations_exclude_subjects_that_are_out_of_scope if {
	doc := {"items": [
		{"id": "a", "state": "MERGED"},
		{"id": "b", "state": "CLOSED"},
	]}
	rep := report(doc, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"applies_to": merged_only,
		"checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}},
	}})
	rep.requirements.s.status == "not_met"

	count([r | some r in rep.results; r.check == "$applies"; r.passed == false]) == 1

	[[v.subject.id, v.check] | some v in ergo.violations(rep)] == [["a", "signed"]]
}

test_violations_exclude_rows_of_a_met_requirement if {
	rep := report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	rep.requirements.s.status == "met"
	count([r | some r in rep.results; r.passed == false]) == 1
	ergo.violations(rep) == []
}

test_is_violation_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	some row in rep.results
	row.passed == false
	not ergo._is_violation(rep.requirements, row)
}

test_definition_field_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := report({"items": [{"id": "a", "signed": true}]}, violating_req)
	some row in rep.results
	row.check == "reviewed"
	ergo._definition_field(rep.requirements, row, "description") == "Reviewed"
}

test_violations_span_multiple_requirements if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["v"], "value": 1}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["v"], "value": 1}}},
	}
	{v.requirement | some v in ergo.violations(report(doc, policy))} == {"first", "second"}
}

test_violations_follow_results_order if {
	rep := report({"items": [{"id": "a"}, {"id": "b"}]}, violating_req)
	from_rows := [[r.requirement, r.check, r.subject.id] |
		some r in rep.results
		r.passed == false
		r.check != "$applies"
	]
	[[v.requirement, v.check, v.subject.id] | some v in ergo.violations(rep)] == from_rows
}

test_violations_keep_two_failures_that_look_alike if {
	rep := report(
		{"items": [{"signed": false}, {"signed": false}]},
		{"s": {"from": ["items"], "id": ["no_such_field"], "checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}}}},
	)
	[[v.check, v.subject.id] | some v in ergo.violations(rep)] == [["$unique_ids", null], ["signed", null], ["signed", null]]
}

test_violations_take_the_definition_from_the_rows_own_requirement if {
	rep := report({"a": [{"id": 1}], "b": [{"id": 2}]}, {
		"first": {"from": ["a"], "id": ["id"], "checks": {"c": {"description": "First", "op": "present", "path": ["x"]}}},
		"second": {"from": ["b"], "id": ["id"], "checks": {"c": {"description": "Second", "op": "present", "path": ["x"]}}},
	})
	{[v.requirement, v.description] | some v in ergo.violations(rep)} == {["first", "First"], ["second", "Second"]}
}

test_a_requirement_without_checks_yields_a_violation if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rep.compliant == false
	[v.check | some v in ergo.violations(rep)] == ["$well_formed"]
}

test_an_unknown_require_value_yields_a_violation if {
	rep := report(both_ok, require_req("most"))
	rep.compliant == false
	[v.check | some v in ergo.violations(rep)] == ["$well_formed"]
}

scan_mins := [0, 1, 2]

scan_checksets := [{}, {"c": {"op": "present", "path": ["id"]}}]

scan_filters := [{}, {"m": {"op": "equals", "path": ["state"], "value": "MERGED"}}]

scan_docs := [
	{"items": []},
	{"items": [{"id": "a", "state": "MERGED"}]},
	{"items": [{"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "MERGED"}, {"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "CLOSED"}]},
]

scan_policy(rq, mn, cs, fl) := {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"require": rq,
	"min_subjects": mn,
	"applies_to": fl,
	"checks": cs,
}}

scan_reports(rq) := [report(d, scan_policy(rq, mn, cs, fl)) |
	some mn in scan_mins
	some cs in scan_checksets
	some fl in scan_filters
	some d in scan_docs
]

unexplained(rq) := [rep | some rep in scan_reports(rq); rep.compliant == false; count(ergo.violations(rep)) == 0]

test_an_not_met_report_always_explains_itself_under_every if count(unexplained("every")) == 0

test_an_not_met_report_always_explains_itself_under_some if count(unexplained("some")) == 0

test_an_not_met_report_always_explains_itself_under_a_bad_require if count(unexplained("most")) == 0

malformed(rq) := [rep | some rep in scan_reports(rq); rows_for(rep, "s", "$well_formed")[0].passed == false]

malformed_ones_fail_and_say_why(rq) if {
	every rep in malformed(rq) {
		rep.requirements.s.status == "not_met"
		count([v |
			some v in ergo.violations(rep)
			v.check == "$well_formed"
		]) == 1
	}
}

test_a_malformed_requirement_is_never_met_under_every if malformed_ones_fail_and_say_why("every")

test_a_malformed_requirement_is_never_met_under_some if malformed_ones_fail_and_say_why("some")

test_a_malformed_requirement_is_never_met_under_a_bad_require if {
	count(malformed("most")) > 0
	malformed_ones_fail_and_say_why("most")
}

test_compare_lt_fails_when_the_left_side_is_missing if {
	verdict({"b": 5}, compare_ab("lt")) == false
}

test_compare_lte_fails_when_the_left_side_is_missing if {
	verdict({"b": 5}, compare_ab("lte")) == false
}

test_compare_gt_fails_when_the_right_side_is_missing if {
	verdict({"a": 5}, compare_ab("gt")) == false
}

test_compare_ne_fails_when_a_side_is_missing if {
	verdict({"b": 5}, compare_ab("ne")) == false
}

test_compare_eq_fails_when_both_sides_are_missing if {
	verdict({}, compare_ab("eq")) == false
}

test_compare_fails_across_mismatched_types if {
	verdict({"a": "10", "b": 5}, compare_ab("gt")) == false
}

test_every_over_no_subjects_is_not_met if {
	report({"items": []}, require_req("every")).requirements.s.status == "not_met"
}

test_a_typo_in_the_subject_from_path_is_not_compliant if {
	report({"items": [{"id": "a"}]}, id_req(["itmes"])).compliant == false
}

test_a_policy_with_no_requirements_is_not_compliant if {
	report({"items": []}, {}).compliant == false
}

test_min_subjects_row_labels_the_count_it_actually_reports if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"applies_to": merged_only})}
	rep := report(two_states, scoped)
	row := rows_for(rep, "s", "$min_subjects")[0]
	row.inputs[0].value == 1
	row.inputs[0].name != "count(items)"
}

test_out_of_scope_subject_is_recorded_as_evidence if {
	rep := report(two_states, scoped_req(merged_only))
	some row in rep.results
	row.subject.id == "b"
}

test_requirement_names_are_unique_by_construction if {
	doc := {"a": [{"id": "A", "v": 1}], "b": [{"id": "B", "v": 9}]}
	policy := {
		"thing": {"subject_type": "thing", "from": ["a"], "id": ["id"], "checks": {"chk": {"op": "equals", "path": ["v"], "value": 1}}},
		"other_thing": {"subject_type": "thing", "from": ["b"], "id": ["id"], "checks": {"chk": {"op": "equals", "path": ["v"], "value": 2}}},
	}
	rep := report(doc, policy)
	every row in rep.results {
		count([def |
			some name, req in rep.requirements
			name == row.requirement
			some check_name, def in req.checks
			check_name == row.check
		]) == 1
	}
}

test_a_user_check_named_min_subjects_is_not_clobbered if {
	colliding := {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 1,
		"checks": {"min_subjects": {"description": "user check", "op": "equals", "path": ["id"], "value": "zzz"}},
	}}
	rep := report({"items": [{"id": "a"}]}, colliding)

	rep.requirements.s.checks.min_subjects == {
		"description": "user check",
		"meta": {},
		"op": "equals",
		"path": ["id"],
		"value": "zzz",
		"expression": `id == "zzz"`,
	}
	rep.requirements.s.checks["$min_subjects"].description == "The in-scope thing count is at least 1"

	count(rows_for(rep, "s", "min_subjects")) == 1
	rows_for(rep, "s", "min_subjects")[0].passed == false
	count(rows_for(rep, "s", "$min_subjects")) == 1
	rows_for(rep, "s", "$min_subjects")[0].passed == true
}

test_a_requirement_without_checks_explains_itself if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rep.requirements.s.status == "not_met"
	count(rep.results) > 0
}

test_equals_null_does_not_pass_on_a_missing_field if {
	verdict({}, {"op": "equals", "path": ["x"], "value": null}) == false
}

test_any_rejects_an_object_collection if {
	verdict({"approvers": {"a": {"state": "APPROVED"}}}, any_approved) == false
}

test_all_over_an_empty_collection_is_not_a_pass if {
	verdict({"commits": []}, all_verified) == false
}

even := {"op": "even", "path": ["n"], "expression": "n is even", "inputs": [["n"]]}

test_a_custom_op_passes if verdict({"n": 2}, even) == true

test_a_custom_op_fails if verdict({"n": 3}, even) == false

test_a_custom_op_fails_closed_on_a_missing_field if {
	verdict({}, even) == false
	cause_of({}, even) == "absent"
}

test_a_custom_op_fails_closed_on_a_wrong_type if {
	verdict({"n": "2"}, even) == false
	cause_of({"n": "2"}, even) == "value"
}

test_a_custom_op_uses_its_declared_expression if rendered({}, even) == "n is even"

test_a_custom_op_echoes_its_declared_inputs if {
	inputs_of({"n": 3, "other": 1}, even) == [{"name": "n", "value": 3}]
}

test_a_custom_op_without_inputs_takes_its_cause_from_its_path if {
	cause_of({"n": null}, {"op": "even", "path": ["n"]}) == "null"
}

test_a_custom_op_takes_its_cause_from_a_projected_input if {
	check := {"op": "even", "path": ["n"], "inputs": [{"path": ["ns"], "each": []}]}
	cause_of({"n": 3, "ns": [1]}, check) == "value"
	cause_of({"n": 3}, check) == "absent"
}

test_a_custom_op_can_call_the_built_in_operators if {
	check := {"op": "both_present", "paths": [["a"], ["b"]]}
	verdict({"a": 1, "b": 2}, check) == true
	verdict({"a": 1}, check) == false
}

test_a_custom_op_can_scope_a_requirement if {
	rep := report({"items": [{"id": "a", "n": 2}, {"id": "b", "n": 3}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"is_even": even},
		"checks": {"c": {"op": "present", "path": ["n"]}},
	}})
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_a_custom_op_can_be_a_substitute if {
	check := {"op": "equals", "path": ["reviewed"], "value": true, "substitute": even}
	cause_of({"n": 2}, check) == "substituted"
}

test_a_custom_op_can_have_a_substitute if {
	check := object.union(even, {"substitute": {"op": "equals", "path": ["exempt"], "value": true}})
	cause_of({"n": 3, "exempt": true}, check) == "substituted"
}

test_a_custom_op_inside_all_fails_closed if {
	verdict({"items": [{"n": 2}]}, {"op": "all", "path": ["items"], "check": even}) == false
}

test_a_custom_op_inside_any_of_fails_closed if {
	verdict({"n": 2}, {"op": "any_of", "options": {"only": [even]}}) == false
}

degraded_only := {"degraded": {"op": "equals", "path": ["degraded"], "value": true}}

degraded_req(req_kind) := {"s": {
	"subject_type": "round",
	"from": ["rounds"],
	"id": ["id"],
	"require": req_kind,
	"min_subjects": 0,
	"applies_to": degraded_only,
	"checks": {"c": {"op": "equals", "path": ["signed"], "value": true}},
}}

test_a_missing_filter_field_fails_the_requirement_even_with_min_subjects_zero if {
	rep := report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_null_filter_field_fails_the_requirement if {
	rep := report({"rounds": [{"id": "r1", "degraded": null}]}, degraded_req("every"))
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "null"
}

test_a_filter_selector_that_matches_nothing_fails_the_requirement if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"pr": {
		"op": "equals",
		"path": ["attestations", {"where": {"type": "pr"}}, "degraded"],
		"value": true,
	}}})}
	rep := report({"rounds": [{"id": "r1", "attestations": [{"type": "jira"}]}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "unmatched"
}

test_an_unreadable_filter_fails_a_some_requirement_that_another_subject_meets if {
	doc := {"rounds": [{"id": "r1", "degraded": true, "signed": true}, {"id": "r2"}]}
	report(doc, degraded_req("some")).requirements.s.status == "not_met"
}

test_an_unreadable_filter_fails_a_some_requirement_with_nothing_in_scope if {
	report({"rounds": [{"id": "r1"}]}, degraded_req("some")).requirements.s.status == "not_met"
}

test_an_unreadable_filter_makes_the_policy_not_compliant if {
	report({"rounds": [{"id": "r1"}]}, degraded_req("every")).compliant == false
}

test_an_unreadable_filter_is_reported_as_a_violation if {
	rep := report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	[[v.subject.id, v.check, v.cause] | some v in ergo.violations(rep)] == [["r1", "$applies", "absent"]]
}

test_a_subject_with_an_unreadable_filter_still_gets_no_check_rows if {
	rep := report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	rows_for(rep, "s", "c") == []
}

test_a_filter_that_reads_a_value_that_does_not_match_leaves_the_subject_out_of_scope if {
	rep := report({"rounds": [{"id": "r1", "degraded": false}]}, degraded_req("every"))
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_filter_value_of_the_wrong_type_leaves_the_subject_out_of_scope if {
	rep := report({"rounds": [{"id": "r1", "degraded": "yes"}]}, degraded_req("every"))
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_ruled_out_by_one_filter_still_fails_the_requirement_when_another_filter_cannot_be_read if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
	[v.check | some v in ergo.violations(rep)] == ["$applies"]
}

test_a_subject_is_out_of_scope_when_every_failing_filter_reads_sound_values if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED", "degraded": false}]}, req)
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_whose_filter_fails_on_an_unreadable_field_is_not_ruled_out_by_a_passing_filter if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := report({"rounds": [{"id": "r1", "state": "MERGED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_missing_substitute_does_not_make_an_out_of_scope_subject_unreadable if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"in_scope": object.union(
		degraded_only.degraded,
		{"substitute": {"op": "equals", "path": ["forced"], "value": true}},
	)}})}
	rep := report({"rounds": [{"id": "r1", "degraded": false}]}, req)
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

locked_req(filter_path) := {"s": {
	"from": ["packages"],
	"id": ["id"],
	"min_subjects": 0,
	"applies_to": {"locked": {"op": "present", "path": filter_path}},
	"checks": {"c": {"op": "equals", "path": ["signed"], "value": true}},
}}

test_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	rep := report({"packages": [{"id": "a"}]}, locked_req(["lock"]))
	rep.requirements.s.status == "not_applicable"
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "value"]]
	ergo.violations(rep) == []
}

test_a_present_filter_rules_out_a_subject_whose_field_is_null if {
	rep := report({"packages": [{"id": "a", "lock": null}]}, locked_req(["lock"]))
	rep.requirements.s.status == "not_applicable"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_a_present_filter_still_fails_when_its_selector_matches_nothing if {
	rep := report({"packages": [{"id": "a", "atts": [{"type": "scan"}]}]}, locked_req(["atts", {"where": {"type": "lock"}}]))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unmatched"]
}

test_a_present_filter_still_fails_when_its_selector_matches_several_items if {
	rep := report({"packages": [{"id": "a", "atts": [{"type": "lock"}, {"type": "lock"}]}]}, locked_req(["atts", {"where": {"type": "lock"}}]))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ambiguous"]
}

test_a_present_filter_still_fails_on_a_subject_that_is_not_an_object if {
	rep := report({"packages": ["a"]}, locked_req(["lock"]))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["not_an_object"]
}

test_a_present_check_on_a_missing_field_is_a_clean_no if {
	cause_of({}, {"op": "present", "path": ["lock"]}) == "value"
}

test_only_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	req := {"s": object.union(locked_req(["lock"]).s, {"applies_to": {"locked": {"op": "non_empty_string", "path": ["lock"]}}})}
	rep := report({"packages": [{"id": "a"}]}, req)
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_a_custom_op_filter_without_inputs_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"is_even": {"op": "even", "path": ["n"], "expression": "n is even"}}})}
	report({"rounds": [{"id": "r1", "n": 3, "degraded": true}]}, req).requirements.s.status == "not_applicable"
}

test_a_failing_custom_op_filter_that_declares_no_reads_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"both": {
		"op": "both_present",
		"paths": [["a"], ["b"]],
		"expression": "a and b are present",
	}}})}
	rep := report({"rounds": [{"id": "r1", "a": 1, "degraded": true}]}, req)
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

in_doc(top, subj, check) := report(object.union(top, {"items": [subj]}), {"s": {
	"subject_type": "thing",
	"from": ["items"],
	"id": ["id"],
	"checks": {"c": check},
}})

row_in(top, subj, check) := r if {
	some r in in_doc(top, subj, check).results
	r.check == "c"
}

expression_in(top, subj, check) := in_doc(top, subj, check).requirements.s.checks.c.expression

refs_in(top, subj, check) := object.get(in_doc(top, subj, check).requirements.s.checks.c, "$refs", [])

violation_in(top, subj, check) := v if {
	some v in ergo.violations(in_doc(top, subj, check))
	v.check == "c"
}

test_an_input_path_reads_from_the_top_of_the_document if {
	r := row_in({"mode": "strict"}, {"id": 1}, {"op": "equals", "path": ["$$input", "mode"], "value": "strict"})
	[r.passed, r.cause, r.inputs] == [true, "satisfied", [{"name": "$input.mode", "value": "strict"}]]
}

test_an_input_path_fails_closed_when_it_leads_nowhere if {
	check := {"op": "equals", "path": ["$$input", "mode"], "value": "strict"}
	[row_in({}, {"id": 1}, check).passed, row_in({}, {"id": 1}, check).cause] == [false, "absent"]
	[row_in({"mode": null}, {"id": 1}, check).passed, row_in({"mode": null}, {"id": 1}, check).cause] == [false, "null"]
}

test_an_input_path_can_use_a_selector if {
	check := {"op": "equals", "path": ["$$input", "teams", {"where": {"name": "core"}}, "lead"], "value": "ann"}
	row_in({"teams": [{"name": "core", "lead": "ann"}]}, {"id": 1}, check).passed == true
	row_in({"teams": [{"name": "web", "lead": "bo"}]}, {"id": 1}, check).cause == "unmatched"
}

test_an_input_path_reads_from_the_top_inside_all if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": ["$$input", "mode"], "value": "strict"}}
	row_in({"mode": "strict"}, {"id": 1, "xs": [1, 2]}, check).passed == true
	row_in({"mode": "loose"}, {"id": 1, "xs": [1, 2]}, check).passed == false
}

test_an_input_path_reads_from_the_top_for_a_subject_that_is_not_an_object if {
	r := row_in({"mode": "strict"}, "a", {"op": "equals", "path": ["$$input", "mode"], "value": "strict"})
	[r.passed, r.cause] == [true, "satisfied"]
}

test_an_unknown_built_in_name_fails_closed if {
	r := row_in({"mode": "strict"}, {"id": 1}, {"op": "equals", "path": ["$$inptu", "mode"], "value": "strict"})
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_input_is_only_a_name_at_the_start_of_a_path if {
	row_in({}, {"id": 1, "a": {"$$input": "x"}}, {"op": "equals", "path": ["a", "$$input"], "value": "x"}).passed == true
}

test_a_literal_path_step_reads_a_key_that_looks_like_a_name if {
	r := row_in({"$$input": "top"}, {"id": 1, "$$input": "x"}, {"op": "equals", "path": [{"literal": "$$input"}], "value": "x"})
	[r.passed, r.inputs] == [true, [{"name": `"$$input"`, "value": "x"}]]
}

licence_params := {"params": {"allowed": ["MIT", "Apache-2.0"]}}

allowed_ref := {"ref": ["$$input", "params", "allowed"]}

licence_in_allowed := {"op": "in", "path": ["licence"], "values": allowed_ref}

test_a_ref_reads_the_values_of_in if {
	row_in(licence_params, {"id": 1, "licence": "MIT"}, licence_in_allowed).passed == true
	r := row_in(licence_params, {"id": 1, "licence": "GPL-3.0"}, licence_in_allowed)
	[r.passed, r.cause] == [false, "value"]
}

test_a_ref_reads_the_value_of_equals if {
	check := {"op": "equals", "path": ["branch"], "value": {"ref": ["$$input", "params", "branch"]}}
	row_in({"params": {"branch": "main"}}, {"id": 1, "branch": "main"}, check).passed == true
	row_in({"params": {"branch": "main"}}, {"id": 1, "branch": "dev"}, check).passed == false
}

test_a_ref_reads_the_value_of_includes_and_excludes if {
	top := {"params": {"label": "approved"}}
	label := {"ref": ["$$input", "params", "label"]}
	row_in(top, {"id": 1, "labels": ["approved"]}, {"op": "includes", "path": ["labels"], "value": label}).passed == true
	row_in(top, {"id": 1, "labels": ["approved"]}, {"op": "excludes", "path": ["labels"], "value": label}).passed == false
}

banned_ref := {"ref": ["$$input", "params", "banned"]}

test_a_ref_reads_the_values_of_includes_and_excludes if {
	top := {"params": {"banned": ["nuts", "garlic"]}}
	row_in(top, {"id": 1, "xs": ["milk"]}, {"op": "excludes", "path": ["xs"], "values": banned_ref}).passed == true
	row_in(top, {"id": 1, "xs": ["garlic"]}, {"op": "excludes", "path": ["xs"], "values": banned_ref}).passed == false
	row_in(top, {"id": 1, "xs": ["garlic", "nuts"]}, {"op": "includes", "path": ["xs"], "values": banned_ref}).passed == true
	row_in(top, {"id": 1, "xs": ["garlic"]}, {"op": "includes", "path": ["xs"], "values": banned_ref}).passed == false
	expression_in(top, {"id": 1}, {"op": "excludes", "path": ["xs"], "values": banned_ref}) == "contains_none(xs, $input.params.banned)"
}

nuts_ref := {"ref": ["$$input", "params", "nut"]}

test_a_ref_or_literal_in_the_values_of_includes_or_excludes_is_read_like_value if {
	top := {"params": {"nut": "nuts"}}
	every item in [nuts_ref, {"literal": "nuts"}] {
		excl := {"op": "excludes", "path": ["xs"], "values": [item, "garlic"]}
		[row_in(top, {"id": 1, "xs": ["nuts"]}, excl).passed, row_in(top, {"id": 1, "xs": ["nuts"]}, excl).cause] == [false, "value"]
		row_in(top, {"id": 1, "xs": ["milk"]}, excl).passed == true
		incl := {"op": "includes", "path": ["xs"], "values": [item, "garlic"]}
		row_in(top, {"id": 1, "xs": ["garlic", "nuts"]}, incl).passed == true
		[row_in(top, {"id": 1, "xs": ["garlic"]}, incl).passed, row_in(top, {"id": 1, "xs": ["garlic"]}, incl).cause] == [false, "value"]
	}
	expression_in(top, {"id": 1}, {"op": "excludes", "path": ["xs"], "values": [nuts_ref, "garlic"]}) == `contains_none(xs, ["garlic", $input.params.nut])`
	refs_in(top, {"id": 1, "xs": ["nuts"]}, {"op": "excludes", "path": ["xs"], "values": [nuts_ref]}) == [{"name": "$input.params.nut", "value": "nuts"}]
}

test_a_missing_or_null_ref_in_the_values_of_includes_or_excludes_fails_instead_of_being_skipped if {
	every op in ["includes", "excludes"] {
		check := {"op": op, "path": ["xs"], "values": [nuts_ref, "garlic"]}
		missing := row_in({}, {"id": 1, "xs": ["milk"]}, check)
		[missing.passed, missing.cause] == [false, "absent"]
		null_ref := row_in({"params": {"nut": null}}, {"id": 1, "xs": ["milk"]}, check)
		[null_ref.passed, null_ref.cause] == [false, "null"]
	}
}

test_a_malformed_ref_in_the_values_of_includes_or_excludes_is_ill_formed if {
	check := {"op": "excludes", "path": ["xs"], "values": [{"ref": ["$$input", "params", "nut"], "x": 1}]}
	r := row_in({"params": {"nut": "nuts"}}, {"id": 1, "xs": ["milk"]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
	expression_in({}, {"id": 1}, check) == "contains_none(xs, [<invalid ref>])"
}

test_ref_shaped_items_under_a_literal_or_read_from_params_are_data_not_refs if {
	shaped := {"ref": ["$$input", "params", "nut"]}
	top := {"params": {"nut": "nuts", "list": [shaped]}}
	every values in [{"literal": [shaped]}, {"ref": ["$$input", "params", "list"]}] {
		check := {"op": "excludes", "path": ["xs"], "values": values}
		row_in(top, {"id": 1, "xs": ["nuts"]}, check).passed == true
		[row_in(top, {"id": 1, "xs": [shaped]}, check).passed, row_in(top, {"id": 1, "xs": [shaped]}, check).cause] == [false, "value"]
	}
}

licence_ref := {"ref": ["$$input", "params", "licence"]}

test_a_ref_or_literal_in_the_values_of_in_is_read_like_value if {
	top := {"params": {"licence": "BSD-3-Clause"}}
	every item in [licence_ref, {"literal": "BSD-3-Clause"}] {
		check := {"op": "in", "path": ["licence"], "values": [item, "MIT"]}
		row_in(top, {"id": 1, "licence": "BSD-3-Clause"}, check).passed == true
		row_in(top, {"id": 1, "licence": "MIT"}, check).passed == true
		r := row_in(top, {"id": 1, "licence": "GPL-3.0"}, check)
		[r.passed, r.cause] == [false, "value"]
	}
	expression_in(top, {"id": 1}, {"op": "in", "path": ["licence"], "values": [licence_ref, "MIT"]}) == `licence in ["MIT", $input.params.licence]`
	expression_in(top, {"id": 1}, {"op": "in", "path": ["licence"], "values": [{"literal": "BSD-3-Clause"}, "MIT"]}) == `licence in ["BSD-3-Clause", "MIT"]`
}

test_a_missing_or_null_ref_in_the_values_of_in_fails_instead_of_being_skipped if {
	check := {"op": "in", "path": ["licence"], "values": [licence_ref, "MIT"]}
	missing := row_in({}, {"id": 1, "licence": "MIT"}, check)
	[missing.passed, missing.cause] == [false, "absent"]
	null_ref := row_in({"params": {"licence": null}}, {"id": 1, "licence": "MIT"}, check)
	[null_ref.passed, null_ref.cause] == [false, "null"]
}

bot_ref := {"ref": ["$$input", "params", "bot"]}

test_a_ref_in_the_patterns_is_read_like_a_pattern if {
	top := {"params": {"bot": "\\[bot\\]$"}}
	matches := {"op": "matches_any", "path": ["author"], "patterns": [bot_ref, "^svc_"]}
	row_in(top, {"id": 1, "author": "renovate[bot]"}, matches).passed == true
	row_in(top, {"id": 1, "author": "svc_deploy"}, matches).passed == true
	[row_in(top, {"id": 1, "author": "ann"}, matches).passed, row_in(top, {"id": 1, "author": "ann"}, matches).cause] == [false, "value"]
	not_matches := {"op": "not_matches_any", "path": ["author"], "patterns": [bot_ref, "^svc_"]}
	row_in(top, {"id": 1, "author": "ann"}, not_matches).passed == true
	[row_in(top, {"id": 1, "author": "renovate[bot]"}, not_matches).passed, row_in(top, {"id": 1, "author": "renovate[bot]"}, not_matches).cause] == [false, "value"]
	expression_in(top, {"id": 1}, matches) == `author matches one of ["^svc_", $input.params.bot]`
}

test_a_ref_in_the_patterns_that_reads_no_valid_pattern_fails_as_unusable if {
	every op in ["matches_any", "not_matches_any"] {
		every bot in ["(", 3, ["x"]] {
			r := row_in({"params": {"bot": bot}}, {"id": 1, "author": "ann"}, {"op": op, "path": ["author"], "patterns": [bot_ref, "^svc_"]})
			[r.passed, r.cause] == [false, "unusable"]
		}
	}
}

test_a_missing_or_null_ref_in_the_patterns_fails_instead_of_being_skipped if {
	every op in ["matches_any", "not_matches_any"] {
		check := {"op": op, "path": ["author"], "patterns": [bot_ref, "^svc_"]}
		missing := row_in({}, {"id": 1, "author": "ann"}, check)
		[missing.passed, missing.cause] == [false, "absent"]
		null_ref := row_in({"params": {"bot": null}}, {"id": 1, "author": "ann"}, check)
		[null_ref.passed, null_ref.cause] == [false, "null"]
	}
}

test_a_ref_deeper_inside_a_value_is_written_wrong_so_it_cannot_be_compared_as_data if {
	top := {"params": {"nut": "nuts"}}
	every check in [
		{"op": "excludes", "path": ["xs"], "value": [nuts_ref]},
		{"op": "includes", "path": ["xs"], "value": {"a": nuts_ref}},
		{"op": "equals", "path": ["xs"], "value": [nuts_ref]},
		{"op": "excludes", "path": ["xs"], "values": [[nuts_ref]]},
		{"op": "in", "path": ["xs"], "values": [{"a": nuts_ref}]},
		{"op": "includes", "path": ["xs"], "values": [{"a": nuts_ref}]},
	] {
		r := row_in(top, {"id": 1, "xs": [["nuts"]]}, check)
		[r.passed, r.cause] == [false, "ill_formed"]
	}
}

test_well_formed_says_where_a_ref_sits_inside_a_value if {
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
		"in_value": {"op": "excludes", "path": ["xs"], "value": [nuts_ref]},
		"in_values": {"op": "in", "path": ["n"], "values": [[nuts_ref]]},
		"in_patterns": {"op": "matches_any", "path": ["s"], "patterns": [{"p": nuts_ref}]},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.in_patterns", "value": ["invalid patterns", "ref inside patterns"]},
		{"name": "checks.in_value", "value": ["ref inside value"]},
		{"name": "checks.in_values", "value": ["ref inside values"]},
	]
}

test_a_literal_deeper_inside_a_value_is_written_wrong_so_it_cannot_be_compared_as_data if {
	every check in [
		{"op": "excludes", "path": ["xs"], "value": [{"literal": "nuts"}]},
		{"op": "equals", "path": ["xs"], "value": {"a": {"literal": 1}}},
		{"op": "excludes", "path": ["xs"], "values": [[{"literal": "nuts"}]]},
		{"op": "in", "path": ["xs"], "values": [[{"literal": "nuts"}]]},
	] {
		r := row_in({}, {"id": 1, "xs": [["nuts"]]}, check)
		[r.passed, r.cause] == [false, "ill_formed"]
	}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "excludes", "path": ["xs"], "value": [{"literal": "nuts"}]}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["literal inside value"]}]
}

test_a_literal_under_a_literal_is_data if {
	check := {"op": "excludes", "path": ["xs"], "value": {"literal": [{"literal": "nuts"}]}}
	row_in({}, {"id": 1, "xs": [["nuts"]]}, check).passed == true
	r := row_in({}, {"id": 1, "xs": [[{"literal": "nuts"}]]}, check)
	[r.passed, r.cause] == [false, "value"]
}

test_a_literal_step_inside_a_ref_is_part_of_the_ref_and_not_a_literal_inside_a_value if {
	check := {"op": "excludes", "path": ["xs"], "value": {"ref": ["$$input", "params", {"literal": "nut"}]}}
	r := row_in({"params": {"nut": "nuts"}}, {"id": 1, "xs": ["nuts"]}, check)
	[r.passed, r.cause] == [false, "value"]
	row_in({"params": {"nut": "nuts"}}, {"id": 1, "xs": ["milk"]}, check).passed == true
}

test_a_ref_or_literal_deeper_inside_a_where_value_is_written_wrong if {
	top := {"params": {"k": "a"}}
	subj := {"id": 1, "items": [{"k": ["a"], "tags": ["bad"]}]}
	rep := report(object.union(top, {"items": [subj]}), {"s": {"from": ["items"], "id": ["id"], "checks": {
		"ref": {"op": "excludes", "path": ["items", {"where": {"k": [{"ref": ["$$input", "params", "k"]}]}}, "tags"], "value": "bad"},
		"literal": {"op": "present", "path": ["items", {"where": {"k": {"a": {"literal": 1}}}}, "tags"]},
		"right": {"op": "compare", "left": ["id"], "right": ["items", {"where": {"k": [{"literal": "a"}]}}, "n"], "cmp": "eq"},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.literal", "value": ["literal inside where"]},
		{"name": "checks.ref", "value": ["ref inside where"]},
		{"name": "checks.right", "value": ["literal inside where"]},
	]
	[[r.check, r.cause] | some r in rep.results; r.check in {"ref", "literal", "right"}] == [["literal", "ill_formed"], ["ref", "ill_formed"], ["right", "ill_formed"]]
}

id_where_well_formed(where) := rows_for(
	report(
		{"params": {"k": "a"}, "items": [{"ids": [{"k": "a", "v": 1}], "x": 1}]},
		{"s": {"from": ["items"], "id": ["ids", {"where": {"k": where}}, "v"], "checks": {"c": {"op": "present", "path": ["x"]}}}},
	),
	"s", "$well_formed",
)[0].passed

test_a_ref_or_literal_deeper_inside_a_where_value_in_id_is_not_well_formed if {
	id_where_well_formed([{"ref": ["$$input", "params", "k"]}]) == false
	id_where_well_formed({"a": {"literal": "a"}}) == false
	id_where_well_formed({"ref": ["$$input", "params", "k"]}) == true
	id_where_well_formed({"literal": [{"ref": ["x"]}]}) == true
}

test_a_where_value_under_a_literal_is_data if {
	shaped := {"ref": ["$$input", "params", "k"]}
	check := {"op": "present", "path": ["items", {"where": {"k": {"literal": [shaped]}}}, "tags"]}
	row_in({"params": {"k": "a"}}, {"id": 1, "items": [{"k": [shaped], "tags": []}]}, check).passed == true
}

test_a_ref_shaped_object_under_a_literal_is_still_data if {
	shaped := {"ref": ["$$input", "params", "nut"]}
	check := {"op": "excludes", "path": ["xs"], "value": {"literal": [shaped]}}
	row_in({"params": {"nut": "nuts"}}, {"id": 1, "xs": [["nuts"]]}, check).passed == true
	r := row_in({"params": {"nut": "nuts"}}, {"id": 1, "xs": [[shaped]]}, check)
	[r.passed, r.cause] == [false, "value"]
}

test_a_ref_that_gives_includes_or_excludes_an_empty_list_or_no_list_fails_as_unusable if {
	every op in ["includes", "excludes"] {
		every banned in [[], "nuts", {"a": "nuts"}] {
			r := row_in({"params": {"banned": banned}}, {"id": 1, "xs": ["milk"]}, {"op": op, "path": ["xs"], "values": banned_ref})
			[r.passed, r.cause] == [false, "unusable"]
		}
	}
}

test_a_missing_ref_for_the_values_of_includes_or_excludes_fails_as_absent if {
	every op in ["includes", "excludes"] {
		r := row_in({}, {"id": 1, "xs": ["milk"]}, {"op": op, "path": ["xs"], "values": banned_ref})
		[r.passed, r.cause] == [false, "absent"]
	}
}

test_a_ref_reads_the_patterns if {
	top := {"params": {"bots": ["\\[bot\\]$"]}}
	bots := {"ref": ["$$input", "params", "bots"]}
	row_in(top, {"id": 1, "author": "dependabot[bot]"}, {"op": "matches_any", "path": ["author"], "patterns": bots}).passed == true
	row_in(top, {"id": 1, "author": "dependabot[bot]"}, {"op": "not_matches_any", "path": ["author"], "patterns": bots}).passed == false
}

test_a_ref_reads_min_and_max if {
	top := {"params": {"lo": 1, "hi": 3}}
	check := {"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "lo"]}, "max": {"ref": ["$$input", "params", "hi"]}}
	row_in(top, {"id": 1, "n": 2}, check).passed == true
	row_in(top, {"id": 1, "n": 4}, check).passed == false
}

test_a_ref_reads_a_selector_value if {
	check := {"op": "equals", "path": ["atts", {"where": {"type": {"ref": ["$$input", "params", "kind"]}}}, "state"], "value": "done"}
	row_in({"params": {"kind": "scan"}}, {"id": 1, "atts": [{"type": "pr", "state": "open"}, {"type": "scan", "state": "done"}]}, check).passed == true
}

missing_ref := {"ref": ["$$input", "params", "missing"]}

test_a_missing_ref_fails_every_op_closed if {
	subj := {"id": 1, "v": "x", "n": 2, "labels": ["x"]}
	checks := [
		{"op": "equals", "path": ["v"], "value": missing_ref},
		{"op": "in", "path": ["v"], "values": missing_ref},
		{"op": "includes", "path": ["labels"], "value": missing_ref},
		{"op": "excludes", "path": ["labels"], "value": missing_ref},
		{"op": "matches_any", "path": ["v"], "patterns": missing_ref},
		{"op": "not_matches_any", "path": ["v"], "patterns": missing_ref},
		{"op": "range", "path": ["n"], "min": missing_ref, "max": 3},
		{"op": "range", "path": ["n"], "min": 1, "max": missing_ref},
		{"op": "equals", "path": ["labels", {"where": {"k": missing_ref}}], "value": "x"},
	]
	[[r.passed, r.cause] | some check in checks; r := row_in({}, subj, check)] == [[false, "absent"] | some _ in checks]
}

test_a_ref_cannot_use_a_selector if {
	check := {"op": "equals", "path": ["v"], "value": {"ref": ["$$input", "params", {"where": {"k": "a"}}, "v"]}}
	r := row_in({"params": [{"k": "a", "v": "x"}]}, {"id": 1, "v": "x"}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_null_ref_fails_closed_with_cause_null if {
	check := {"op": "equals", "path": ["v"], "value": {"ref": ["$$input", "params", "v"]}}
	r := row_in({"params": {"v": null}}, {"id": 1, "v": null}, check)
	[r.passed, r.cause] == [false, "null"]
}

test_a_ref_must_start_with_input if {
	r := row_in({}, {"id": 1, "licence": "MIT"}, {"op": "equals", "path": ["licence"], "value": {"ref": ["licence"]}})
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_ref_value_is_recorded_once_in_the_check_definition if {
	subj := {"id": 1, "licence": "GPL-3.0"}
	row_in(licence_params, subj, licence_in_allowed).inputs == [{"name": "licence", "value": "GPL-3.0"}]
	refs_in(licence_params, subj, licence_in_allowed) == [{"name": "$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
}

test_a_violation_shows_the_ref_values_beside_what_the_check_read if {
	violation_in(licence_params, {"id": 1, "licence": "GPL-3.0"}, licence_in_allowed).inputs == [
		{"name": "licence", "value": "GPL-3.0"},
		{"name": "$input.params.allowed", "value": ["MIT", "Apache-2.0"]},
	]
}

test_a_check_without_refs_has_no_refs_in_its_definition if {
	not "$refs" in object.keys(in_doc({}, {"id": 1}, {"op": "present", "path": ["id"]}).requirements.s.checks.c)
}

test_a_missing_ref_is_recorded_as_null if {
	refs_in({}, {"id": 1, "licence": "MIT"}, licence_in_allowed) == [{"name": "$input.params.allowed", "value": null}]
	violation_in({}, {"id": 1, "licence": "MIT"}, licence_in_allowed).inputs == [
		{"name": "licence", "value": "MIT"},
		{"name": "$input.params.allowed", "value": null},
	]
}

test_a_ref_shows_its_path_in_the_expression if {
	expression_in({}, {"id": 1}, licence_in_allowed) == "licence in $input.params.allowed"
	expression_in({}, {"id": 1}, {"op": "equals", "path": ["v"], "value": missing_ref}) == "v == $input.params.missing"
	expression_in({}, {"id": 1}, {"op": "includes", "path": ["l"], "value": missing_ref}) == "contains(l, $input.params.missing)"
	expression_in({}, {"id": 1}, {"op": "excludes", "path": ["l"], "value": missing_ref}) == "not contains(l, $input.params.missing)"
	expression_in({}, {"id": 1}, {"op": "matches_any", "path": ["a"], "patterns": missing_ref}) == ".a matches one of $input.params.missing"
	expression_in({}, {"id": 1}, {"op": "not_matches_any", "path": ["a"], "patterns": missing_ref}) == ".a matches none of $input.params.missing"
	expression_in({}, {"id": 1}, {"op": "range", "path": ["n"], "min": missing_ref, "max": 3}) == "n >= $input.params.missing and n <= 3"
	expression_in({}, {"id": 1}, {"op": "present", "path": ["atts", {"where": {"type": missing_ref}}]}) == "atts.[type==$input.params.missing] is present"
}

any_allowed_licence := {"op": "any", "path": ["licences"], "check": {"op": "in", "path": [], "values": allowed_ref}}

test_a_ref_inside_any_is_read_once_and_shown_once if {
	r := row_in(licence_params, {"id": 1, "licences": ["GPL-3.0"]}, any_allowed_licence)
	[r.passed, r.cause] == [false, "value"]
	r.inputs == [{"name": "licences[]", "value": ["GPL-3.0"]}]
	refs_in(licence_params, {"id": 1}, any_allowed_licence) == [{"name": "$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
	expression_in(licence_params, {"id": 1}, any_allowed_licence) == "some licences: licences[] in $input.params.allowed"
	row_in(licence_params, {"id": 1, "licences": ["GPL-3.0", "MIT"]}, any_allowed_licence).passed == true
}

test_a_missing_ref_inside_any_fails_with_its_own_cause if {
	r := row_in({}, {"id": 1, "licences": ["MIT"]}, any_allowed_licence)
	[r.passed, r.cause] == [false, "absent"]
}

test_a_ref_inside_any_of_is_read if {
	check := {"op": "any_of", "options": {"allowed": [licence_in_allowed]}}
	r := row_in(licence_params, {"id": 1, "licence": "MIT"}, check)
	[r.passed, r.inputs] == [true, [{"name": "licence", "value": "MIT"}]]
	refs_in(licence_params, {"id": 1}, check) == [{"name": "$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
	row_in({}, {"id": 1, "licence": "MIT"}, check).cause == "absent"
}

test_a_ref_in_a_check_and_its_substitute_is_shown_once if {
	check := object.union(licence_in_allowed, {"substitute": {"op": "in", "path": ["fallback"], "values": allowed_ref}})
	r := row_in(licence_params, {"id": 1, "licence": "GPL-3.0", "fallback": "MIT"}, check)
	[r.passed, r.cause] == [true, "substituted"]
	r.inputs == [{"name": "licence", "value": "GPL-3.0"}, {"name": "fallback", "value": "MIT"}]
	refs_in(licence_params, {"id": 1}, check) == [{"name": "$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
}

test_ref_inputs_are_sorted_by_name if {
	check := {"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "lo"]}, "max": {"ref": ["$$input", "params", "hi"]}}
	[i.name | some i in refs_in({"params": {"lo": 1, "hi": 3}}, {"id": 1, "n": 2}, check)] == ["$input.params.hi", "$input.params.lo"]
}

test_a_ref_in_an_applies_to_filter_is_read_and_shown if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"kind": {"op": "equals", "path": ["kind"], "value": {"ref": ["$$input", "params", "kind"]}}},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}}
	rep := report({"params": {"kind": "lib"}, "items": [{"id": 1, "kind": "lib"}, {"id": 2, "kind": "app"}]}, req)
	[[r.subject.id, r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "$applies")] == [
		[1, true, "satisfied", [{"name": "kind", "value": "lib"}]],
		[2, false, "value", [{"name": "kind", "value": "app"}]],
	]
	rep.requirements.s.checks["$applies"]["$refs"] == [{"name": "$input.params.kind", "value": "lib"}]
	unreadable := report({"items": [{"id": 1, "kind": "lib"}]}, req)
	unreadable.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(unreadable, "s", "$applies")] == ["absent"]
	[v.inputs | some v in ergo.violations(unreadable); v.check == "$applies"] == [[{"name": "kind", "value": "lib"}, {"name": "$input.params.kind", "value": null}]]
}

test_a_literal_value_is_taken_as_written if {
	check := {"op": "equals", "path": ["config"], "value": {"literal": {"ref": ["main"]}}}
	r := row_in({}, {"id": 1, "config": {"ref": ["main"]}}, check)
	[r.passed, r.inputs] == [true, [{"name": "config", "value": {"ref": ["main"]}}]]
}

test_a_literal_can_hold_a_literal if {
	check := {"op": "equals", "path": ["config"], "value": {"literal": {"literal": {"ref": ["main"]}}}}
	row_in({}, {"id": 1, "config": {"literal": {"ref": ["main"]}}}, check).passed == true
}

test_a_literal_works_wherever_a_value_goes if {
	row_in({}, {"id": 1, "licence": "MIT"}, {"op": "in", "path": ["licence"], "values": {"literal": ["MIT"]}}).passed == true
	expression_in({}, {"id": 1}, {"op": "in", "path": ["licence"], "values": {"literal": ["MIT"]}}) == `licence in ["MIT"]`
	expression_in({}, {"id": 1}, {"op": "equals", "path": ["c"], "value": {"literal": "x"}}) == `c == "x"`
}

test_a_readable_ref_leaves_the_cause_to_the_subject if {
	row_in(licence_params, {"id": 1, "licence": null}, licence_in_allowed).cause == "null"
}

test_range_fails_closed_on_bounds_that_are_not_numbers if {
	row_in({}, {"id": 1, "n": 5}, {"op": "range", "path": ["n"], "min": 1, "max": "3"}).passed == false
	row_in({}, {"id": 1, "n": 5}, {"op": "range", "path": ["n"], "min": "1", "max": 10}).passed == false
	row_in({"params": {"hi": "3"}}, {"id": 1, "n": 5}, {"op": "range", "path": ["n"], "min": 1, "max": {"ref": ["$$input", "params", "hi"]}}).passed == false
}

test_an_object_with_ref_and_another_key_fails_closed if {
	check := {"op": "excludes", "path": ["labels"], "value": {"ref": ["$$input", "params", "label"], "note": "x"}}
	r := row_in({"params": {"label": "wip"}}, {"id": 1, "labels": ["ready"]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
	r.inputs == [{"name": "labels", "value": ["ready"]}]
	refs_in({}, {"id": 1}, check) == [{"name": "<invalid ref>", "value": null}]
	expression_in({}, {"id": 1}, check) == "not contains(labels, <invalid ref>)"
}

test_an_object_with_literal_and_another_key_fails_closed if {
	check := {"op": "excludes", "path": ["labels"], "value": {"literal": "wip", "note": "x"}}
	r := row_in({}, {"id": 1, "labels": ["ready"]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_malformed_ref_in_patterns_or_values_reads_as_invalid if {
	bad := {"ref": ["$$input", "p"], "x": 1}
	expression_in({}, {"id": 1}, {"op": "not_matches_any", "path": ["a"], "patterns": bad}) == ".a matches none of <invalid ref>"
	expression_in({}, {"id": 1}, {"op": "in", "path": ["a"], "values": bad}) == ".a in <invalid ref>"
	row_in({}, {"id": 1, "a": "x"}, {"op": "not_matches_any", "path": ["a"], "patterns": bad}).passed == false
}

test_a_ref_that_is_not_a_path_from_input_reads_as_invalid if {
	string_ref := {"op": "equals", "path": ["b"], "value": {"ref": "params"}}
	expression_in({}, {"id": 1}, string_ref) == "b == <invalid ref>"
	refs_in({}, {"id": 1, "b": "x"}, string_ref) == [{"name": "<invalid ref>", "value": null}]
	expression_in({}, {"id": 1}, {"op": "equals", "path": ["b"], "value": {"ref": ["licence"]}}) == "b == <invalid ref>"
}

test_an_input_path_inside_all_is_shown_once_under_its_own_name if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": ["$$input", "mode"], "value": "strict"}}
	row_in({"mode": "strict"}, {"id": 1, "xs": [1, 2]}, check).inputs == [{"name": "xs[]", "value": [1, 2]}, {"name": "$input.mode", "value": "strict"}]
}

test_a_check_field_called_refs_is_the_users_own if {
	check := {"op": "even", "path": ["n"], "refs": "my-param", "expression": "n is even"}
	in_doc({}, {"id": 1, "n": 3}, check).requirements.s.checks.c.refs == "my-param"
	violation_in({}, {"id": 1, "n": 3}, check).inputs == [{"name": "n", "value": 3}]
}

test_a_check_field_called_dollar_refs_cannot_drop_a_violation if {
	check := {"op": "even", "path": ["n"], "$refs": "my-param", "expression": "n is even"}
	violation_in({}, {"id": 1, "n": 3}, check).inputs == [{"name": "n", "value": 3}]
}

test_a_custom_op_reads_a_ref_with_arg if {
	check := {"op": "multiple_of", "path": ["n"], "by": {"ref": ["$$input", "params", "m"]}, "expression": "n is a multiple"}
	row_in({"params": {"m": 2}}, {"id": 1, "n": 4}, check).passed == true
	row_in({"params": {"m": 3}}, {"id": 1, "n": 4}, check).passed == false
	r := row_in({}, {"id": 1, "n": 4}, check)
	[r.passed, r.cause] == [false, "absent"]
	refs_in({"params": {"m": 2}}, {"id": 1, "n": 4}, check) == [{"name": "$input.params.m", "value": 2}]
}

suite_doc := {"build": {"test_runs": {
	"unit-test": {"result": "passed"},
	"smoke-test": {"result": "failed"},
	"integration-test": {"result": "passed"},
}}}

suite_req(step) := {"s": {
	"subject_type": "test run",
	"from": ["build", "test_runs", step],
	"checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}},
}}

suite_rows(doc, step) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(report(doc, suite_req(step)), "s", "c")]

test_an_each_step_makes_every_entry_of_an_object_a_subject_named_by_its_key if {
	suite_rows(suite_doc, {"each_as": "suite"}) == [
		["integration-test", true, "satisfied"],
		["smoke-test", false, "value"],
		["unit-test", true, "satisfied"],
	]
}

test_an_each_step_identifies_entries_of_an_object_by_key_even_with_an_id if {
	rep := report(suite_doc, {"s": object.union(suite_req({"each_as": "suite"}).s, {"id": ["result"]})})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == ["integration-test", "smoke-test", "unit-test"]
}

test_an_each_step_over_a_list_makes_every_item_a_subject if {
	rep := report({"items": [{"id": "b"}, {"id": "a"}]}, {"s": {"from": ["items", {"each_as": "item"}], "id": ["id"], "checks": {"c": {"op": "present", "path": ["$item", "id"]}}}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["b", true], ["a", true]]
}

test_keys_pick_which_entries_are_subjects if {
	suite_rows(suite_doc, {"each_as": "suite", "keys": ["unit-test", "smoke-test"]}) == [
		["smoke-test", false, "value"],
		["unit-test", true, "satisfied"],
	]
}

test_a_key_the_object_does_not_have_is_a_failing_subject if {
	suite_rows(suite_doc, {"each_as": "suite", "keys": ["unit-test", "system-test"]}) == [
		["system-test", false, "absent"],
		["unit-test", true, "satisfied"],
	]
}

test_a_key_the_object_does_not_have_fails_the_requirement if {
	rep := report(suite_doc, suite_req({"each_as": "suite", "keys": ["system-test"]}))
	rep.requirements.s.status == "not_met"
	rep.compliant == false
}

test_a_missing_key_reads_as_absent_even_from_the_subject_itself if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite", "keys": ["system-test"]}],
		"checks": {"c": {"op": "non_empty_string", "path": []}},
	}})
	[[r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "c")] == [[false, "absent", [{"name": "$suite", "value": null}]]]
}

test_keys_are_sorted_and_duplicates_dropped if {
	suite_rows(suite_doc, {"each_as": "suite", "keys": ["unit-test", "smoke-test", "unit-test"]}) == suite_rows(suite_doc, {"each_as": "suite", "keys": ["smoke-test", "unit-test"]})
	count(suite_rows(suite_doc, {"each_as": "suite", "keys": ["unit-test", "unit-test"]})) == 1
}

test_keys_on_something_that_is_not_an_object_all_fail if {
	suite_rows({"build": {"test_runs": [{"result": "passed"}]}}, {"each_as": "suite", "keys": ["0", "unit-test"]}) == [
		["0", false, "absent"],
		["unit-test", false, "absent"],
	]
}

test_an_empty_keys_list_gives_no_subjects if {
	rep := report(suite_doc, suite_req({"each_as": "suite", "keys": []}))
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.status == "not_met"
}

test_an_each_step_on_something_missing_or_scalar_gives_no_subjects if {
	report({}, suite_req({"each_as": "suite"})).requirements.s.subjects == {"total": 0, "matching": 0}
	report({"build": {"test_runs": "x"}}, suite_req({"each_as": "suite"})).requirements.s.subjects == {"total": 0, "matching": 0}
	report({}, suite_req({"each_as": "suite"})).requirements.s.status == "not_met"
}

test_min_subjects_counts_from_the_path_before_the_each_step if {
	rep := report(suite_doc, suite_req({"each_as": "suite"}))
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(build.test_runs)) >= 1"
}

test_an_empty_path_under_an_each_step_is_named_after_the_name if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "present", "path": []}},
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks.c.expression == "$suite is present"
	rep.requirements.s.checks["$applies"].expression == "$suite is present"
}

test_a_name_at_the_start_of_a_path_reads_the_subject if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"checks": {"c": {"op": "equals", "path": ["$suite", "result"], "value": "passed"}},
	}})
	[[r.subject.id, r.passed, r.inputs] | some r in rows_for(rep, "s", "c")] == [
		["integration-test", true, [{"name": "$suite.result", "value": "passed"}]],
		["smoke-test", false, [{"name": "$suite.result", "value": "failed"}]],
		["unit-test", true, [{"name": "$suite.result", "value": "passed"}]],
	]
	rep.requirements.s.checks.c.expression == `$suite.result == "passed"`
}

test_a_name_alone_reads_the_whole_subject if {
	rep := report({"names": ["a", ""]}, {"s": {
		"from": ["names", {"each_as": "n"}],
		"checks": {"c": {"op": "non_empty_string", "path": ["$n"]}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["a", true], ["", false]]
}

pr_doc := {"pull_requests": [
	{"number": 1, "author": "ann", "approvers": [{"username": "ann"}, {"username": "bob"}]},
	{"number": 2, "author": "bob", "approvers": [{"username": "bob"}]},
	{"number": 3, "approvers": [{"username": "bob"}]},
]}

peer_req := {"s": {
	"subject_type": "pull request",
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
	"checks": {"c": {"op": "any", "path": ["approvers"], "check": {"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "ne"}}},
}}

test_a_check_on_a_list_item_can_read_its_subject_by_name if {
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(report(pr_doc, peer_req), "s", "c")] == [
		[1, true, "satisfied"],
		[2, false, "value"],
		[3, false, "absent"],
	]
}

test_a_name_read_inside_a_list_check_is_shown_in_the_row if {
	rows := rows_for(report(pr_doc, peer_req), "s", "c")
	[r.inputs | some r in rows] == [
		[{"name": "approvers[]", "value": [{"username": "ann"}, {"username": "bob"}]}, {"name": "$pr.author", "value": "ann"}],
		[{"name": "approvers[]", "value": [{"username": "bob"}]}, {"name": "$pr.author", "value": "bob"}],
		[{"name": "approvers[]", "value": [{"username": "bob"}]}, {"name": "$pr.author", "value": null}],
	]
	report(pr_doc, peer_req).requirements.s.checks.c.expression == "some approvers: username ne $pr.author"
}

test_a_name_read_inside_an_any_of_in_a_list_check_is_shown_in_the_row if {
	rep := report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "all", "path": ["approvers"], "check": {"op": "any_of", "options": {"x": [{"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "eq"}]}}}},
	}})
	some r in rows_for(rep, "s", "c")
	r.subject.id == 2
	r.passed == true
	r.inputs[1] == {"name": "$pr.author", "value": "bob"}
}

test_an_input_read_inside_a_list_check_is_shown_in_the_row if {
	rep := report({"items": [{"id": 1, "xs": [{"v": 2}]}], "params": {"max": 3}}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "compare", "left": ["v"], "right": ["$$input", "params", "max"], "cmp": "lt"}}},
	}})
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "xs[]", "value": [{"v": 2}]}, {"name": "$input.params.max", "value": 3}]]
}

test_each_subject_reads_its_own_name if {
	rep := report({"a": [{"x": 1, "y": 1}, {"x": 2, "y": 3}]}, {"s": {
		"from": ["a", {"each_as": "it"}],
		"id": ["x"],
		"checks": {"c": {"op": "compare", "left": ["$it", "x"], "right": ["y"], "cmp": "eq"}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, false]]
}

test_a_name_that_is_not_bound_is_ill_formed if {
	rep := report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "present", "path": ["$p", "author"]}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"], [false, "ill_formed"], [false, "ill_formed"]]
}

test_a_name_is_not_bound_without_an_each_step if {
	r := row_in({}, {"id": 1, "a": 1}, {"op": "present", "path": ["$items", "a"]})
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_literal_first_key_that_starts_with_a_dollar_is_quoted_so_it_is_not_named_like_a_name if {
	rendered({}, {"op": "present", "path": [{"literal": "$schema"}, "v"]}) == `"$schema".v is present`
	rendered({}, {"op": "present", "path": ["a", {"literal": "$schema"}]}) == `.a."$schema" is present`
}

test_a_key_that_starts_with_a_dollar_is_read_with_literal if {
	row_in({}, {"id": 1, "$schema": "x"}, {"op": "present", "path": ["$schema"]}).passed == false
	row_in({}, {"id": 1, "$schema": "x"}, {"op": "present", "path": [{"literal": "$schema"}]}).passed == true
}

test_a_ref_to_a_name_fails_closed if {
	rep := report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "equals", "path": ["author"], "value": {"ref": ["$pr", "author"]}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [false, false, false]
	rep.requirements.s.checks.c.expression == "author == <invalid ref>"
	rep.requirements.s.checks.c["$refs"] == [{"name": "<invalid ref>", "value": null}]
}

test_a_filter_can_read_a_name if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "equals", "path": ["$suite", "result"], "value": "passed"}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "$applies")] == [["integration-test", true], ["smoke-test", false], ["unit-test", true]]
	rep.requirements.s.subjects == {"total": 3, "matching": 2}
	rep.requirements.s.status == "met"
}

test_a_filter_that_reads_a_name_and_fails_shows_its_value if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "equals", "path": ["$suite", "result"], "value": "passed"}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	some r in rows_for(rep, "s", "$applies")
	r.subject.id == "smoke-test"
	[r.inputs, r.cause] == [[{"name": "$suite.result", "value": "failed"}], "value"]
}

test_a_present_filter_on_a_name_rules_out_a_missing_key if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite", "keys": ["system-test", "unit-test"]}],
		"applies_to": {"f": {"op": "present", "path": ["$suite"]}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	rep.requirements.s.status == "met"
}

test_require_some_passes_when_one_key_passes if {
	rep := report(suite_doc, {"s": object.union(suite_req({"each_as": "suite", "keys": ["smoke-test", "unit-test"]}).s, {"require": "some"})})
	rep.requirements.s.status == "met"
}

test_a_custom_operator_can_read_a_name if {
	rep := report({"xs": [{"n": 2}, {"n": 3}]}, {"s": {
		"from": ["xs", {"each_as": "x"}],
		"id": ["n"],
		"checks": {"c": {"op": "even", "path": ["$x", "n"]}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[2, true], [3, false]]
}

test_a_name_read_from_the_input_still_works_under_an_each_step if {
	rep := report(object.union(suite_doc, {"params": {"want": "passed"}}), {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"checks": {"c": {"op": "equals", "path": ["$suite", "result"], "value": {"ref": ["$$input", "params", "want"]}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [true, false, true]
}

ill_formed_from(step_from) := report(suite_doc, {"s": {
	"from": step_from,
	"min_subjects": 0,
	"checks": {"c": {"op": "present", "path": ["result"]}},
}})

test_a_from_with_a_badly_written_step_is_not_well_formed if {
	every f in [
		["build", {"each_as": "x"}, "test_runs"],
		["build", {"each_as": "x"}, "test_runs", {"each_as": "y"}],
		["build", "test_runs", {"each_as": 1}],
		["build", "test_runs", {"each_as": ""}],
		["build", "test_runs", {"each_as": "$x"}],
		["build", "test_runs", {"each_as": "$$input"}],
		["build", "test_runs", {"name": "x"}],
		["build", "test_runs", {"each": "x"}],
		["build", "test_runs", {"each_as": "x", "each": "x"}],
		["build", "test_runs", {"each_as": "x", "kesy": ["a"]}],
		["build", "test_runs", {"each_as": "x", "keys": "unit-test"}],
		["build", "test_runs", {"each_as": "x", "keys": {"ref": ["$$params", "keys"], "note": "x"}}],
		["build", "test_runs", {"each_as": "x", "keys": {"literal": "unit-test"}}],
	] {
		rep := ill_formed_from(f)
		rows_for(rep, "s", "$well_formed")[0].passed == false
		rep.requirements.s.status == "not_met"
		rep.compliant == false
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
}

test_a_badly_written_from_is_named_as_invalid if {
	rep := report(suite_doc, {"s": {
		"from": ["build", {"each_as": "x"}, "test_runs"],
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks.c.expression == "<invalid from> is present"
}

test_a_well_formed_row_for_a_from_with_a_step_shows_the_from if {
	rep := ill_formed_from(["build", "test_runs", {"each_as": "suite"}])
	row := rows_for(rep, "s", "$well_formed")[0]
	row.passed == true
	row.inputs[2] == {"name": "subjects.subject.from", "value": ["build", "test_runs", {"each_as": "suite"}]}
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

test_a_well_formed_row_without_a_step_is_unchanged if {
	rep := ill_formed_from(["build", "test_runs"])
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_an_input_missing_inside_a_list_check_fails_as_absent if {
	rep := report({"items": [{"id": 1, "xs": [{"v": 2}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "compare", "left": ["v"], "right": ["$$input", "params", "max"], "cmp": "lt"}}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_a_name_missing_in_the_path_of_a_list_check_fails_as_absent if {
	rep := report({"prs": [{"n": 1, "xs": [1, 2]}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "non_empty_string", "path": ["$pr", "author"]}}},
	}})
	[[r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "c")] == [[false, "absent", [{"name": "xs[]", "value": [1, 2]}, {"name": "$pr.author", "value": null}]]]
}

test_an_input_missing_in_the_path_of_a_list_check_fails_as_absent if {
	rep := report({"items": [{"id": 1, "xs": [1]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "non_empty_string", "path": ["$$input", "nope"]}}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_an_id_can_start_with_a_name if {
	rep := report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["$pr", "number"],
		"checks": {"c": {"op": "present", "path": ["number"]}},
	}})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == [1, 2, 3]
}

test_the_input_cannot_give_names if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs"],
		"checks": {"c": {"op": "present", "path": ["$suite", "x"]}},
	}}) with input as {"ergo/names": {"suite": {"x": 1}}}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false]
}

test_the_input_cannot_give_other_names_under_a_step if {
	rep := report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "run"}],
		"checks": {"c": {"op": "present", "path": ["$suite", "x"]}},
	}}) with input as {"ergo/names": {"suite": {"x": 1}}}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false, false, false]
}

test_a_badly_written_from_is_named_as_invalid_in_min_subjects if {
	rep := report(suite_doc, {"s": {
		"from": ["build", {"each_as": "x"}, "test_runs"],
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

test_a_literal_or_selector_in_from_is_not_well_formed_so_it_cannot_pass_by_finding_nothing if {
	every f in [["a", {"literal": "$x"}], ["a", {"where": {"id": 1}}]] {
		rep := report({"a": {"$x": [{"id": 1}]}}, {"s": {"from": f, "min_subjects": 0, "checks": {"c": {"op": "present", "path": ["id"]}}}})
		rows_for(rep, "s", "$well_formed")[0].passed == false
		rep.requirements.s.status == "not_met"
	}
}

review_doc := {"pull_requests": [
	{"number": 41, "author": "ann", "commits": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}, {"sha": "c2", "timestamp": "2026-10-01T12:00:00Z"}], "approvers": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}, {"username": "cat", "timestamp": "2026-10-01T13:00:00Z"}]},
	{"number": 42, "author": "ann", "commits": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}, {"sha": "c2", "timestamp": "2026-10-01T12:00:00Z"}], "approvers": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 43, "author": "ann", "commits": [{"sha": "c1"}], "approvers": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 44, "author": "ann", "commits": [], "approvers": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 45, "author": "ann", "commits": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}], "approvers": [{"username": "bob"}]},
]}

after_last_commit := {"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "all", "path": ["$pr", "commits"], "check": {"op": "compare_time", "left": ["$approver", "timestamp"], "right": ["timestamp"], "cmp": "gt"}}}

review_req(check) := {"s": {
	"subject_type": "pull request",
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
	"checks": {"c": check},
}}

review_rows(check) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(report(review_doc, review_req(check)), "s", "c")]

test_a_check_inside_a_list_check_can_read_the_item_by_its_name if {
	review_rows(after_last_commit) == [
		[41, true, "satisfied"],
		[42, false, "value"],
		[43, false, "absent"],
		[44, false, "value"],
		[45, false, "absent"],
	]
}

test_a_nested_list_check_renders_both_levels if {
	report(review_doc, review_req(after_last_commit)).requirements.s.checks.c.expression == "some approvers as $approver: every $pr.commits: $approver.timestamp gt timestamp"
}

test_a_nested_list_check_shows_the_list_and_the_names_it_reads if {
	some r in rows_for(report(review_doc, review_req(after_last_commit)), "s", "c")
	r.subject.id == 42
	r.inputs == [
		{"name": "approvers[]", "value": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}]},
		{"name": "$pr.commits", "value": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}, {"sha": "c2", "timestamp": "2026-10-01T12:00:00Z"}]},
	]
}

test_a_name_given_by_as_is_not_read_for_the_row_but_its_item_decides_the_cause if {
	check := {"op": "all", "path": ["approvers"], "as": "a", "check": {"op": "non_empty_string", "path": ["$a", "timestamp"]}}
	review_rows(check)[4] == [45, false, "absent"]
	some r in rows_for(report(review_doc, review_req(check)), "s", "c")
	r.subject.id == 45
	r.inputs == [{"name": "approvers[].timestamp", "value": [null]}]
}

test_a_name_given_by_as_reads_the_same_as_a_path_inside_the_item if {
	with_name := {"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "equals", "path": ["$a", "username"], "value": "cat"}}
	without := {"op": "any", "path": ["approvers"], "check": {"op": "equals", "path": ["username"], "value": "cat"}}
	review_rows(with_name) == review_rows(without)
	review_rows(with_name)[0] == [41, true, "satisfied"]
}

test_an_empty_path_under_as_is_named_after_the_name if {
	rep := report({"items": [{"id": 1, "tags": ["a"]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "all", "path": ["tags"], "as": "tag", "check": {"op": "non_empty_string", "path": []}}}}})
	rep.requirements.s.checks.c.expression == "every tags as $tag: $tag is a non-empty string"
	rows_for(rep, "s", "c")[0].passed == true
}

test_as_works_without_a_naming_step if {
	rep := report({"items": [{"id": 1, "xs": [{"v": 1, "w": [1]}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "all", "path": ["w"], "check": {"op": "compare", "left": [], "right": ["$x", "v"], "cmp": "eq"}}}}}})
	rows_for(rep, "s", "c")[0].passed == true
}

test_an_inner_list_check_can_read_a_list_inside_the_outer_item if {
	rep := report({"items": [{"id": 1, "xs": [{"ys": [2, 3]}, {"ys": [4]}]}, {"id": 2, "xs": [{"ys": [1]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "range", "path": [], "min": 2, "max": 9}}}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, false]]
	rep.requirements.s.checks.c.expression == "every xs: every ys: ys[] >= 2 and ys[] <= 9"
	rows_for(rep, "s", "c")[0].inputs == [{"name": "xs[].ys", "value": [[2, 3], [4]]}]
}

test_an_inner_list_check_fails_on_an_empty_or_missing_inner_list if {
	rep := report({"items": [{"id": 1, "xs": [{"ys": [2]}, {"ys": []}]}, {"id": 2, "xs": [{"ys": [2]}, {}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "present", "path": []}}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [false, false]
}

test_any_inside_all_needs_one_item_of_every_inner_list if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "any", "path": ["ys"], "check": {"op": "equals", "path": [], "value": 1}}}
	row_in({}, {"id": 1, "xs": [{"ys": [0, 1]}, {"ys": [1]}]}, check).passed == true
	row_in({}, {"id": 1, "xs": [{"ys": [0, 1]}, {"ys": [0]}]}, check).passed == false
}

test_an_inner_list_check_can_use_each_and_as if {
	check := {"op": "any", "path": ["teams"], "as": "team", "check": {"op": "all", "path": ["repos"], "each": ["owners"], "as": "owner", "check": {"op": "equals", "path": ["$owner"], "value": {"ref": ["$$input", "lead"]}}}}
	row_in({"lead": "ann"}, {"id": 1, "teams": [{"repos": [{"owners": ["bob"]}]}, {"repos": [{"owners": ["ann"]}, {"owners": ["ann"]}]}]}, check).passed == true
	row_in({"lead": "ann"}, {"id": 1, "teams": [{"repos": [{"owners": ["ann", "bob"]}]}]}, check).passed == false
	expression_in({}, {"id": 1}, check) == "some teams as $team: every repos[].owners as $owner: $owner == $input.lead"
}

test_an_inner_list_check_can_hold_an_any_of_that_reads_both_names if {
	check := {"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "all", "path": ["$pr", "commits"], "as": "commit", "check": {"op": "any_of", "options": {
		"later": [{"op": "compare_time", "left": ["$approver", "timestamp"], "right": ["$commit", "timestamp"], "cmp": "gt"}],
		"self": [{"op": "compare", "left": ["$approver", "username"], "right": ["$pr", "author"], "cmp": "eq"}],
	}}}}
	array.slice(review_rows(check), 0, 3) == [[41, true, "satisfied"], [42, false, "value"], [43, false, "absent"]]
}

test_a_list_check_nested_two_levels_deep_fails_closed if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, check)
	r.passed == false
	expression_in({}, {"id": 1}, check) == "every xs: every ys: <nested too deep>"
}

test_a_badly_written_as_fails_the_check if {
	every name in [1, "", "$a", "$$input", null] {
		check := {"op": "any", "path": ["approvers"], "as": name, "check": {"op": "present", "path": ["username"]}}
		[r[1] | some r in review_rows(check)] == [false, false, false, false, false]
		report(review_doc, review_req(check)).requirements.s.checks.c.expression == "some approvers as <invalid name>: username is present"
	}
}

test_a_badly_written_inner_as_fails_the_check if {
	check := {"op": "any", "path": ["approvers"], "check": {"op": "all", "path": ["$pr", "commits"], "as": "", "check": {"op": "present", "path": ["sha"]}}}
	[r[1] | some r in review_rows(check)] == [false, false, false, false, false]
}

test_a_name_given_twice_fails_the_check if {
	shadow_step := {"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}}
	[r[1] | some r in review_rows(shadow_step)] == [false, false, false, false, false]
	shadow_outer := {"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "a", "check": {"op": "present", "path": ["sha"]}}}
	[r[1] | some r in review_rows(shadow_outer)] == [false, false, false, false, false]
}

test_the_same_name_can_be_given_in_two_separate_checks if {
	rep := report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {
			"a": {"op": "any", "path": ["approvers"], "as": "x", "check": {"op": "present", "path": ["$x", "username"]}},
			"b": {"op": "all", "path": ["commits"], "as": "x", "check": {"op": "present", "path": ["$x", "sha"]}},
		},
	}})
	[r.passed | some r in rows_for(rep, "s", "a")] == [true, true, true, true, true]
	[r.passed | some r in rows_for(rep, "s", "b")] == [true, true, true, false, true]
}

test_a_filter_can_use_as if {
	rep := report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"applies_to": {"f": {"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "equals", "path": ["$a", "username"], "value": "cat"}}},
		"checks": {"c": {"op": "present", "path": ["author"]}},
	}})
	rep.requirements.s.subjects == {"total": 5, "matching": 1}
}

test_a_path_through_as_inside_a_list_check_is_shown_as_a_path_inside_the_item if {
	check := {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "present", "path": ["$x", "v"]}}
	r := row_in({}, {"id": 1, "xs": [{"v": 1}, {"w": 2}]}, check)
	[r.passed, r.cause, r.inputs] == [false, "value", [{"name": "xs[].v", "value": [1, null]}]]
}

test_a_name_given_twice_fails_every_kind_of_list_check if {
	outer_all := {"op": "all", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}}
	[r[1] | some r in review_rows(outer_all)] == [false, false, false, false, false]
	inner_any := {"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "any", "path": ["$pr", "commits"], "as": "a", "check": {"op": "present", "path": ["sha"]}}}
	[r[1] | some r in review_rows(inner_any)] == [false, false, false, false, false]
	inner_any_ok := {"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "any", "path": ["$pr", "commits"], "as": "b", "check": {"op": "present", "path": ["sha"]}}}
	[r[1] | some r in review_rows(inner_any_ok)] == [true, true, true, false, true]
}

test_a_filter_with_a_name_given_twice_cannot_rule_subjects_out if {
	rep := report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"ill_formed"}
}

test_a_filter_with_a_badly_written_as_cannot_rule_subjects_out if {
	rep := report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["approvers"], "as": "a", "check": {"op": "any", "path": ["$pr", "commits"], "as": "$c", "check": {"op": "present", "path": ["sha"]}}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"ill_formed"}
}

test_a_filter_nested_too_deep_cannot_rule_subjects_out if {
	rep := report({"items": [{"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
}

test_a_badly_written_list_check_is_ill_formed if {
	every check in [
		{"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}},
		{"op": "any", "path": ["approvers"], "as": "", "check": {"op": "present", "path": ["username"]}},
		{"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "a", "check": {"op": "present", "path": ["sha"]}}},
		{"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "pr", "check": {"op": "present", "path": ["sha"]}}},
		{"op": "any", "path": ["approvers"], "check": {"op": "all", "path": ["$pr", "commits"], "as": 3, "check": {"op": "present", "path": ["sha"]}}},
	] {
		{r[2] | some r in review_rows(check)} == {"ill_formed"}
	}
}

review_expression(check) := report(review_doc, review_req(check)).requirements.s.checks.c.expression

test_a_name_given_twice_shows_in_the_expression if {
	review_expression({"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}}) == "some approvers as <name given twice>: username is present"
	review_expression({"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "a", "check": {"op": "present", "path": ["sha"]}}}) == "some approvers as $a: every $pr.commits as <name given twice>: sha is present"
	review_expression({"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "pr", "check": {"op": "present", "path": ["sha"]}}}) == "some approvers as $a: every $pr.commits as <name given twice>: sha is present"
	expression_in({}, {"id": 1}, {"op": "any", "path": ["xs"], "as": "items", "check": {"op": "present", "path": []}}) == "some xs as $items: $items is present"
}

peer_doc := {"pull_requests": [
	{"number": 1, "author": "ann", "commits": [{"timestamp": "2026-10-01T10:00:00Z"}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 2, "author": "ann", "commits": [{"timestamp": "2026-10-01T12:00:00Z"}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 3, "author": "ann", "commits": [{"timestamp": "2026-10-01T10:00:00Z"}], "approvers": [{"username": "ann", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}, {"username": "bob", "state": "COMMENTED", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 4, "commits": [{"timestamp": "2026-10-01T10:00:00Z"}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}]},
	{"number": 5, "author": "ann", "commits": [{}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}]},
]}

peer_check := {"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "any_of", "options": {"peer": [
	{"op": "equals", "path": ["state"], "value": "APPROVED"},
	{"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "ne"},
	{"op": "all", "path": ["$pr", "commits"], "check": {"op": "compare", "left": ["$approver", "timestamp"], "right": ["timestamp"], "cmp": "gt"}},
]}}}

peer_rows(check) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(report(peer_doc, review_req(check)), "s", "c")]

test_an_any_of_inside_a_list_check_can_hold_a_list_check if {
	peer_rows(peer_check) == [
		[1, true, "satisfied"],
		[2, false, "value"],
		[3, false, "value"],
		[4, false, "absent"],
		[5, false, "absent"],
	]
}

test_a_list_check_inside_an_any_of_renders_in_its_option if {
	report(peer_doc, review_req(peer_check)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(state == \"APPROVED\" and username ne $pr.author and every $pr.commits: $approver.timestamp gt timestamp)"
}

test_a_list_check_inside_an_any_of_shows_the_names_it_reads if {
	some r in rows_for(report(peer_doc, review_req(peer_check)), "s", "c")
	r.subject.id == 4
	r.inputs == [
		{"name": "approvers[]", "value": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T11:00:00Z"}]},
		{"name": "$pr.author", "value": null},
		{"name": "$pr.commits", "value": [{"timestamp": "2026-10-01T10:00:00Z"}]},
	]
}

test_an_any_of_at_the_top_can_hold_a_list_check if {
	check := {"op": "any_of", "options": {
		"signed": [{"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["verified"], "value": true}}],
		"exempt": [{"op": "equals", "path": ["exempt"], "value": true}],
	}}
	row_in({}, {"id": 1, "commits": [{"verified": true}]}, check).passed == true
	row_in({}, {"id": 1, "commits": [{"verified": false}], "exempt": true}, check).passed == true
	row_in({}, {"id": 1, "commits": [{"verified": false}], "exempt": false}, check).passed == false
	r := row_in({}, {"id": 1, "exempt": false}, check)
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": "commits", "value": null}, {"name": "exempt", "value": false}]
	expression_in({}, {"id": 1}, check) == "one of: exempt(exempt == true) | signed(every commits: verified == true)"
}

test_a_list_check_in_an_any_of_at_the_top_can_nest_and_name_its_items if {
	check := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "as": "x", "check": {"op": "all", "path": ["ys"], "check": {"op": "compare", "left": [], "right": ["$x", "v"], "cmp": "lt"}}}]}}
	row_in({}, {"id": 1, "xs": [{"v": 5, "ys": [1, 2]}]}, check).passed == true
	row_in({}, {"id": 1, "xs": [{"v": 2, "ys": [1, 2]}]}, check).passed == false
	expression_in({}, {"id": 1}, check) == "one of: o(every xs as $x: every ys: ys[] lt $x.v)"
}

test_a_list_check_in_an_any_of_inside_a_nested_list_check_is_too_deep if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}]}}}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
	expression_in({}, {"id": 1}, check) == "every xs: every ys: one of: o(<nested too deep>)"
}

test_a_list_check_two_levels_under_an_any_of_at_the_top_is_too_deep if {
	check := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}}}]}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_name_given_twice_in_a_list_check_inside_an_any_of_is_ill_formed if {
	inner := {"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "any_of", "options": {"peer": [{"op": "all", "path": ["$pr", "commits"], "as": "approver", "check": {"op": "present", "path": ["timestamp"]}}]}}}
	{r[2] | some r in peer_rows(inner)} == {"ill_formed"}
	report(peer_doc, review_req(inner)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(every $pr.commits as <name given twice>: timestamp is present)"
	top := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["commits"], "as": "pr", "check": {"op": "present", "path": ["timestamp"]}}]}}
	{r[2] | some r in peer_rows(top)} == {"ill_formed"}
	report(peer_doc, review_req(top)).requirements.s.checks.c.expression == "one of: o(every commits as <name given twice>: timestamp is present)"
}

test_a_broken_list_check_in_an_any_of_filter_cannot_rule_subjects_out if {
	rep := report(peer_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "any_of", "options": {"o": [{"op": "all", "path": ["commits"], "as": "pr", "check": {"op": "present", "path": ["timestamp"]}}]}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
}

test_a_list_check_inside_an_any_of_at_the_top_reads_names_for_its_row if {
	check := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "compare", "left": [], "right": ["$$input", "lim"], "cmp": "lt"}}]}}
	row_in({"lim": 3}, {"id": 1, "xs": [1, 2]}, check).passed == true
	r := row_in({}, {"id": 1, "xs": [1, 2]}, check)
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": "$input.lim", "value": null}, {"name": "xs", "value": [1, 2]}]
}

test_a_list_check_inside_an_any_of_inside_a_list_check_reads_names_for_its_row if {
	check := {"op": "all", "path": ["as"], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "compare", "left": [], "right": ["$$input", "lim"], "cmp": "lt"}}]}}}
	row_in({"lim": 3}, {"id": 1, "as": [{"xs": [1, 2]}]}, check).passed == true
	r := row_in({}, {"id": 1, "as": [{"xs": [1, 2]}]}, check)
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": ".as[]", "value": [{"xs": [1, 2]}]}, {"name": "$input.lim", "value": null}]
}

test_a_name_read_outside_the_list_check_that_gives_it_is_ill_formed if {
	inside := {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {
		"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
		"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
	}}}
	r := row_in({}, {"id": 1, "xs": [{"ys": []}]}, inside)
	[r.passed, r.cause] == [false, "ill_formed"]
	top := {"op": "any_of", "options": {
		"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
		"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
	}}
	t := row_in({}, {"id": 1, "ys": []}, top)
	[t.passed, t.cause] == [false, "ill_formed"]
	beside := {"op": "all", "path": ["xs"], "as": "o", "check": {"op": "any_of", "options": {"a": [
		{"op": "all", "path": ["ys"], "as": "y", "check": {"op": "present", "path": []}},
		{"op": "equals", "path": ["$y"], "value": 1},
	]}}}
	b := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, beside)
	[b.passed, b.cause] == [false, "ill_formed"]
}

test_a_filter_reading_a_name_outside_the_list_check_that_gives_it_cannot_rule_subjects_out if {
	rep := report({"items": [{"id": 1, "xs": [{"ys": []}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {
			"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
			"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
		}}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
}

test_a_name_nothing_gives_in_an_each_path_is_ill_formed if {
	top := {"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, top)
	[r.passed, r.cause] == [false, "ill_formed"]
	inner := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "each": ["$q", "zs"], "check": {"op": "present", "path": []}}}
	i := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, inner)
	[i.passed, i.cause] == [false, "ill_formed"]
	in_option := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}]}}
	o := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, in_option)
	[o.passed, o.cause] == [false, "ill_formed"]
}

test_a_name_in_an_each_path_reads_the_subject if {
	rep := report({"items": [{"id": 1, "xs": [1, 2], "ys": [3]}]}, {"s": {
		"from": ["items", {"each_as": "it"}],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "each": ["$it", "ys"], "check": {"op": "equals", "path": [], "value": 3}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [true]
}

test_a_filter_with_a_misspelt_name_in_an_each_path_cannot_rule_subjects_out if {
	rep := report({"items": [{"id": 1, "xs": [{"ys": [1]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
}

params_req(check) := {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}

params_rows(doc, check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(doc, params_req(check)), "s", "c")]

test_a_ref_to_params_reads_the_params_given_to_the_report if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	params_rows({"items": [{"id": 1, "name": "app"}]}, check) == [[true, "satisfied", [{"name": "name", "value": "app"}]]] with data.params as {"artifact_name": "app"}
	params_rows({"items": [{"id": 1, "name": "app"}]}, check) == [[false, "value", [{"name": "name", "value": "app"}]]] with data.params as {"artifact_name": "web"}
	rep := report({"items": [{"id": 1, "name": "app"}]}, params_req(check)) with data.params as {"artifact_name": "web"}
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.artifact_name", "value": "web"}]
	rep.requirements.s.checks.c.expression == "name == $params.artifact_name"
	ergo.violations(rep)[0].inputs == [{"name": "name", "value": "app"}, {"name": "$params.artifact_name", "value": "web"}]
}

test_a_path_can_start_at_params if {
	check := {"op": "in", "path": ["$$params", "level"], "values": ["strict", "lax"]}
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.level", "value": "strict"}]]] with data.params as {"level": "strict"}
}

test_params_that_are_missing_fail_closed if {
	check := {"op": "excludes", "path": ["licences"], "value": {"ref": ["$$params", "banned"]}}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]]
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]] with data.params as "not an object"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "null", [{"name": "licences", "value": ["MIT"]}]]] with data.params as {"banned": null}
}

test_a_present_check_on_a_param_fails_as_absent_when_the_params_are_not_an_object if {
	check := {"op": "present", "path": ["$$params", "x"]}
	every params in ["not an object", 1, null, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[false, "value", [{"name": "$params.x", "value": null}]]] with data.params as {}
}

test_a_missing_check_on_a_param_fails_as_absent_when_the_params_are_not_an_object if {
	check := {"op": "missing", "path": ["$$params", "x"]}
	every params in ["not an object", 1, null, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.x", "value": null}]]] with data.params as {}
}

test_a_present_filter_on_a_param_fails_the_requirement_when_the_params_are_not_an_object if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"f": {"op": "present", "path": ["$$params", "x"]}},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}}
	rep := report({"items": [{"id": 1}]}, req) with data.params as "not an object"
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_the_applies_row_lists_each_field_its_filters_read_once_in_name_order if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {
			"a": {"op": "present", "path": ["status"]},
			"b": {"op": "equals", "path": ["status"], "value": "open"},
			"c": {"op": "present", "path": ["kind"]},
		},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}}
	rep := report({"items": [{"id": 1, "status": "open", "kind": "x"}]}, req)
	[i.name | some i in rows_for(rep, "s", "$applies")[0].inputs] == ["kind", "status"]
}

test_the_report_never_reads_data_params if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	rep := ergo.report({"items": [{"id": 1, "name": "app"}]}, lifted(params_req(check)), {"artifact_name": "app"}) with data.params as {"artifact_name": "web"}
	[r.passed | some r in rows_for(rep, "s", "c")] == [true]
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.artifact_name", "value": "app"}]
	unset := ergo.report({"items": [{"id": 1, "name": "app"}]}, lifted(params_req(check)), {}) with data.params as {"artifact_name": "app"}
	[r.cause | some r in rows_for(unset, "s", "c")] == ["absent"]
}

empty_report := {"compliant": false, "description": "", "meta": {}, "requirements": {}, "results": []}

test_a_policy_without_requirements_is_not_compliant if {
	ergo.report({"items": [{"id": 1}]}, {}, {}) == empty_report
	ergo.report({"items": [{"id": 1}]}, {"requirements": {}}, {}) == empty_report
	ergo.report({"items": [{"id": 1}]}, {"requirments": params_req({"op": "present", "path": ["id"]})}, {}) == empty_report
}

test_a_policy_that_is_not_an_object_is_not_compliant if {
	every policy in [null, true, 1, "requirements", [], [params_req({"op": "present", "path": ["id"]})]] {
		ergo.report({"items": [{"id": 1}]}, policy, {}) == empty_report
	}
}

test_requirements_that_are_not_an_object_are_not_compliant if {
	every reqs in [null, true, 1, "", "s", []] {
		ergo.report({"items": [{"id": 1}]}, {"requirements": reqs}, {}) == empty_report
	}
	ergo.report({"items": [{"id": 1}]}, {"requirements": [params_req({"op": "present", "path": ["id"]}).s]}, {}).compliant == false
}

test_sections_ergo_does_not_know_leave_the_report_unchanged if {
	policy := lifted(params_req({"op": "present", "path": ["id"]}))
	rep := ergo.report({"items": [{"id": 1}]}, policy, {})
	rep.compliant == true
	ergo.report({"items": [{"id": 1}]}, object.union(policy, {"notes": "reviewed by the platform team"}), {}) == rep
}

test_params_are_not_read_from_the_input if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	params_rows({"items": [{"id": 1, "name": "app"}], "params": {"artifact_name": "app"}}, check) == [[false, "absent", [{"name": "name", "value": "app"}]]]
}

test_params_can_be_read_inside_named_and_nested_list_checks if {
	check := {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "any", "path": ["$x", "ys"], "check": {"op": "compare", "left": [], "right": ["$$params", "max"], "cmp": "lt"}}}
	rep := report({"items": [{"id": 1, "xs": [{"ys": [1, 9]}, {"ys": [2]}]}]}, {"s": {"from": ["items", {"each_as": "it"}], "id": ["id"], "checks": {"c": check}}}) with data.params as {"max": 3}
	[[r.passed, r.inputs] | some r in rows_for(rep, "s", "c")] == [[true, [{"name": "xs[].ys", "value": [[1, 9], [2]]}, {"name": "$params.max", "value": 3}]]]
}

test_a_key_called_dollar_dollar_params_is_read_with_literal if {
	check := {"op": "equals", "path": [{"literal": "$$params"}], "value": "own"}
	params_rows({"items": [{"id": 1, "$$params": "own"}]}, check) == [[true, "satisfied", [{"name": `"$$params"`, "value": "own"}]]] with data.params as {"$$params": "other"}
}

trail_doc := {"trail": {"artifacts": {"app": {
	"fingerprint": "abc",
	"attestations": {"pull-request": {"status": "COMPLETE"}, "junit": {"status": "FAILED"}},
	"tags": ["v1", "v2"],
}}}}

trail_req(check) := {"s": {
	"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"]}],
	"id": ["fingerprint"],
	"checks": {"c": check},
}}

trail_rows(check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(trail_doc, trail_req(check)), "s", "c")]

attested := {"op": "equals", "path": ["attestations", {"ref": ["$$params", "att"]}, "status"], "value": "COMPLETE"}

test_a_ref_step_in_a_path_reads_the_key_it_names if {
	trail_rows(attested) == [[true, "satisfied", [{"name": "attestations named by $params.att.status", "value": "COMPLETE"}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	trail_rows(attested) == [[false, "value", [{"name": "attestations named by $params.att.status", "value": "FAILED"}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_step_renders_and_is_recorded_like_any_ref if {
	rep := report(trail_doc, trail_req(attested)) with data.params as {"artifact": "app", "att": "junit"}
	rep.requirements.s.checks.c.expression == `attestations named by $params.att.status == "COMPLETE"`
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.att", "value": "junit"}]
	ergo.violations(rep)[0].inputs == [{"name": "attestations named by $params.att.status", "value": "FAILED"}, {"name": "$params.att", "value": "junit"}]
}

test_a_ref_step_can_be_first_or_last if {
	last := {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}
	trail_rows(last) == [[true, "satisfied", [{"name": "attestations named by $params.att", "value": {"status": "COMPLETE"}}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	first := {"op": "non_empty_string", "path": [{"ref": ["$$params", "field"]}]}
	trail_rows(first) == [[true, "satisfied", [{"name": "[$params.field]", "value": "abc"}]]] with data.params as {"artifact": "app", "field": "fingerprint"}
}

test_a_ref_step_can_be_a_list_index if {
	check := {"op": "equals", "path": ["tags", {"ref": ["$$params", "i"]}], "value": "v2"}
	[r[0] | some r in trail_rows(check)] == [true] with data.params as {"artifact": "app", "i": 1}
}

test_a_ref_step_that_cannot_be_read_fails_the_check if {
	trail_rows(attested) == [[false, "absent", [{"name": "attestations named by $params.att.status", "value": null}]]] with data.params as {"artifact": "app"}
	trail_rows(attested) == [[false, "null", [{"name": "attestations named by $params.att.status", "value": null}]]] with data.params as {"artifact": "app", "att": null}
	every bad in [["pull-request"], {"k": "pull-request"}, true] {
		trail_rows(attested) == [[false, "unusable", [{"name": "attestations named by $params.att.status", "value": null}]]] with data.params as {"artifact": "app", "att": bad}
	}
}

test_a_ref_step_with_another_key_fails_the_check if {
	check := {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"], "note": "x"}]}
	trail_rows(check) == [[false, "ill_formed", [{"name": "attestations.[<invalid ref>]", "value": null}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_inside_a_ref_path_is_not_followed if {
	check := {"op": "equals", "path": ["fingerprint"], "value": {"ref": ["$$params", {"ref": ["$$params", "which"]}]}}
	[array.slice(r, 0, 2) | some r in trail_rows(check)] == [[false, "ill_formed"]] with data.params as {"artifact": "app", "which": "fp", "fp": "abc"}
}

test_a_ref_step_works_in_left_right_each_and_id if {
	rep := report({"items": [{"key": "k1", "a": 1, "b": 2, "xs": [{"ys": [1]}]}]}, {"s": {
		"from": ["items"],
		"id": [{"ref": ["$$params", "id"]}],
		"checks": {
			"two_sided": {"op": "compare", "left": [{"ref": ["$$params", "l"]}], "right": [{"ref": ["$$params", "r"]}], "cmp": "lt"},
			"each": {"op": "all", "path": ["xs"], "each": [{"ref": ["$$params", "inner"]}], "check": {"op": "equals", "path": [], "value": 1}},
		},
	}}) with data.params as {"id": "key", "l": "a", "r": "b", "inner": "ys"}
	[[r.check, r.subject.id, r.passed] | some r in rep.results; not startswith(r.check, "$")] == [["each", "k1", true], ["two_sided", "k1", true]]
}

test_a_ref_step_can_follow_a_name_and_come_before_a_selector if {
	rep := report({"prs": [{"n": 1, "atts": {"list": [{"type": "a", "ok": true}]}}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "equals", "path": ["$pr", {"ref": ["$$params", "k"]}, {"where": {"type": "a"}}, "ok"], "value": true}},
	}}) with data.params as {"k": "atts"}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false]
	rep2 := report({"prs": [{"n": 1, "atts": [{"type": "a", "ok": true}]}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "equals", "path": ["$pr", {"ref": ["$$params", "k"]}, {"where": {"type": "a"}}, "ok"], "value": true}},
	}}) with data.params as {"k": "atts"}
	[r.passed | some r in rows_for(rep2, "s", "c")] == [true]
}

test_a_ref_step_in_from_finds_the_subjects if {
	rep := report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]})) with data.params as {"artifact": "app"}
	rep.requirements.s.subjects == {"total": 1, "matching": 1}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(trail.artifacts named by $params.artifact)) >= 1"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.artifact", "value": "app"}]
	rep.requirements.s.status == "met"
}

test_a_ref_step_in_from_that_cannot_be_read_fails_the_requirement_even_with_min_subjects_zero if {
	req := {"s": object.union(trail_req({"op": "present", "path": ["fingerprint"]}).s, {"min_subjects": 0})}
	every params in [{}, {"artifact": null}, {"artifact": ["app"]}] {
		rep := report(trail_doc, req) with data.params as params
		rep.requirements.s.status == "not_met"
		rows_for(rep, "s", "$min_subjects")[0].passed == false
	}
	rows_for(report(trail_doc, req), "s", "$min_subjects")[0].cause == "absent" with data.params as {}
	rows_for(report(trail_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"artifact": null}
	rows_for(report(trail_doc, req), "s", "$min_subjects")[0].cause == "unusable" with data.params as {"artifact": ["app"]}
}

test_a_ref_step_in_from_that_cannot_be_read_shows_up_in_violations if {
	vs := ergo.violations(report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]}))) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope subject count", "value": 0}, {"name": "$params.artifact", "value": null}]]]
}

test_a_ref_step_at_the_end_of_from_is_not_a_naming_step if {
	rep := report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]})) with data.params as {"artifact": "app"}
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_a_ref_step_in_from_works_with_a_naming_step if {
	rep := report(trail_doc, {"s": {
		"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"]}, "attestations", {"each_as": "att", "keys": ["junit", "pull-request", "system-test"]}],
		"checks": {"c": {"op": "equals", "path": ["$att", "status"], "value": "COMPLETE"}},
	}}) with data.params as {"artifact": "app"}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [["junit", false, "value"], ["pull-request", true, "satisfied"], ["system-test", false, "absent"]]
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_a_ref_step_in_from_that_cannot_be_read_fails_the_requirement_with_a_naming_step if {
	every last in [{"each_as": "att"}, {"each_as": "att", "keys": ["junit"]}] {
		req := {"s": {
			"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"]}, "attestations", last],
			"checks": {"c": {"op": "equals", "path": ["$att", "status"], "value": "COMPLETE"}},
		}}
		every params, cause in {"{}": "absent", `{"artifact": null}`: "null", `{"artifact": ["app"]}`: "unusable"} {
			rep := report(trail_doc, req) with data.params as json.unmarshal(params)
			rep.requirements.s.status == "not_met"
			[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
		}
	}
}

test_a_badly_written_ref_step_in_from_is_not_well_formed if {
	rep := report(trail_doc, {"s": {
		"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"], "note": "x"}],
		"min_subjects": 0,
		"checks": {"c": {"op": "present", "path": ["fingerprint"]}},
	}}) with data.params as {"artifact": "app"}
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.status == "not_met"
}

test_a_present_filter_with_a_ref_step_that_cannot_be_read_cannot_rule_subjects_out if {
	rep := report(trail_doc, {"s": {
		"from": ["trail", "artifacts", "app"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}},
		"checks": {"c": {"op": "equals", "path": ["fingerprint"], "value": "nope"}},
	}})
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_present_filter_with_a_ref_step_still_rules_out_a_missing_field if {
	rep := report(trail_doc, {"s": {
		"from": ["trail", "artifacts", "app"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}},
		"checks": {"c": {"op": "equals", "path": ["fingerprint"], "value": "nope"}},
	}}) with data.params as {"att": "sbom"}
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_dotted_key_in_a_ref_is_quoted if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "a.b"]}}
	rep := report({"items": [{"id": 1, "name": "x"}]}, params_req(check)) with data.params as {"a.b": "x"}
	rep.requirements.s.checks.c.expression == `name == $params."a.b"`
	rep.requirements.s.checks.c["$refs"] == [{"name": `$params."a.b"`, "value": "x"}]
}

test_a_literal_in_a_ref_path_is_read_as_written if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", {"literal": "$$odd"}]}}
	params_rows({"items": [{"id": 1, "name": "x"}]}, check) == [[true, "satisfied", [{"name": "name", "value": "x"}]]] with data.params as {"$$odd": "x"}
}

test_a_present_filter_with_a_path_written_as_an_object_cannot_rule_subjects_out if {
	rep := report({"items": [{"id": 1}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": {"a": 1}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.status == "not_met"
}

test_a_ref_step_after_a_name_that_cannot_be_read_is_not_skipped if {
	rep := report({"prs": [{"n": 1, "x": "here"}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "present", "path": ["$pr", {"ref": ["$$params", "k"]}, "x"]}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_a_step_with_a_ref_and_a_where_is_a_mistake_not_a_selector if {
	check := {"op": "present", "path": ["atts", {"where": {"type": "a"}, "ref": ["$$params", "k"]}, "ok"]}
	r := row_in({}, {"id": 1, "atts": [{"type": "a", "ok": true}]}, check)
	[r.passed, r.cause] == [false, "ill_formed"]
}

test_a_ref_step_of_the_wrong_type_inside_a_list_check_fails_as_unusable if {
	inner := {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [{"ref": ["$$params", "k"]}]}}
	option := {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "equals", "path": [{"ref": ["$$params", "k"]}], "value": 1}]}}}
	each := {"op": "all", "path": ["xs"], "each": [{"ref": ["$$params", "k"]}], "check": {"op": "present", "path": []}}
	two_sided := {"op": "any", "path": ["xs"], "check": {"op": "compare", "left": [{"ref": ["$$params", "k"]}], "right": ["$$params", "lim"], "cmp": "lt"}}
	every check in [inner, option, each, two_sided] {
		every k in [["v"], {"a": 1}, true] {
			r := row_in({}, {"id": 1, "xs": [{"v": 1}]}, check) with data.params as {"k": k, "lim": 5}
			[r.passed, r.cause] == [false, "unusable"]
		}
	}
}

test_a_ref_step_of_the_wrong_type_shows_its_value_in_refs if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [{"ref": ["$$params", "k"]}]}}
	refs_in({}, {"id": 1, "xs": [{"v": 1}]}, check) == [{"name": "$params.k", "value": ["v"]}] with data.params as {"k": ["v"]}
}

test_a_filter_with_a_ref_step_of_the_wrong_type_inside_a_list_check_cannot_rule_subjects_out if {
	rep := report({"items": [{"id": 1, "xs": [{"v": 1}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [{"ref": ["$$params", "k"]}]}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}}) with data.params as {"k": ["v"]}
	rep.requirements.s.status == "not_met"
}

test_a_ref_used_as_a_value_may_be_any_type if {
	check := {"op": "equals", "path": ["tags"], "value": {"ref": ["$$params", "k"]}}
	r := row_in({}, {"id": 1, "tags": ["v"]}, check) with data.params as {"k": ["v"]}
	[r.passed, r.cause] == [true, "satisfied"]
	f := row_in({}, {"id": 1, "tags": ["w"]}, check) with data.params as {"k": ["v"]}
	[f.passed, f.cause] == [false, "value"]
}

suites_from_params := {"s": {
	"subject_type": "test run",
	"from": ["build", "test_runs", {"each_as": "run", "keys": {"ref": ["$$params", "suites"]}}],
	"checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}},
}}

test_keys_can_come_from_a_ref if {
	rep := report(suite_doc, suites_from_params) with data.params as {"suites": ["unit-test", "system-test"]}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [
		["system-test", false, "absent"],
		["unit-test", true, "satisfied"],
	]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.suites", "value": ["unit-test", "system-test"]}]
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_keys_from_a_ref_behave_like_keys_written_out if {
	written := report(suite_doc, suite_req({"each_as": "run", "keys": ["unit-test", "smoke-test", "unit-test"]}))
	read := report(suite_doc, suites_from_params) with data.params as {"suites": ["unit-test", "smoke-test", "unit-test"]}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(written, "s", "c")] == [[r.subject.id, r.passed, r.cause] | some r in rows_for(read, "s", "c")]
}

test_keys_from_a_ref_that_cannot_be_read_fail_the_requirement_even_with_min_subjects_zero if {
	req := {"s": object.union(suites_from_params.s, {"min_subjects": 0})}
	rows_for(report(suite_doc, req), "s", "$min_subjects")[0].cause == "absent" with data.params as {}
	rows_for(report(suite_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"suites": null}
	every bad in ["unit-test", {"a": 1}, true, 3] {
		rep := report(suite_doc, req) with data.params as {"suites": bad}
		rep.requirements.s.status == "not_met"
		rows_for(rep, "s", "$min_subjects")[0].cause == "unusable"
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
	report(suite_doc, req).requirements.s.status == "not_met" with data.params as {}
}

test_keys_from_a_ref_that_cannot_be_read_show_up_in_violations if {
	vs := ergo.violations(report(suite_doc, suites_from_params)) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope test run count", "value": 0}, {"name": "$params.suites", "value": null}]]]
}

test_an_empty_list_of_keys_from_a_ref_is_like_an_empty_list_written_out if {
	rep := report(suite_doc, suites_from_params) with data.params as {"suites": []}
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rows_for(rep, "s", "$min_subjects")[0].cause == "value"
	zero := report(suite_doc, {"s": object.union(suites_from_params.s, {"min_subjects": 0})}) with data.params as {"suites": []}
	zero.requirements.s.status == "not_applicable"
}

test_keys_can_be_written_as_a_literal if {
	rep := report(suite_doc, suite_req({"each_as": "run", "keys": {"literal": ["unit-test"]}}))
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["unit-test", true]]
}

test_keys_and_a_ref_step_can_both_come_from_params if {
	rep := report(suite_doc, {"s": {
		"from": ["build", {"ref": ["$$params", "where"]}, {"each_as": "run", "keys": {"ref": ["$$params", "suites"]}}],
		"checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}},
	}}) with data.params as {"where": "test_runs", "suites": ["unit-test"]}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["unit-test", true]]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.suites", "value": ["unit-test"]}, {"name": "$params.where", "value": "test_runs"}]
}

test_badly_written_keys_fail_well_formed_not_the_search_for_subjects if {
	every keys in ["unit-test", {"literal": "unit-test"}, {"ref": ["$$params", "s"], "note": "x"}] {
		rep := report(suite_doc, suite_req({"each_as": "run", "keys": keys}))
		[[r.check, r.passed, r.cause] | some r in rep.results] == [["$well_formed", false, "value"], ["$min_subjects", false, "value"], ["$unique_ids", true, "satisfied"]]
	}
}

test_keys_from_a_ref_to_a_name_fail_as_an_invalid_ref if {
	rep := report(suite_doc, suite_req({"each_as": "run", "keys": {"ref": ["$pr", "suites"]}}))
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rows_for(rep, "s", "$min_subjects")[0].cause == "absent"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "<invalid ref>", "value": null}]
}

test_a_ref_inside_a_list_of_keys_is_read if {
	rep := report(suite_doc, suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "extra"]}, "unit-test"]})) with data.params as {"extra": "smoke-test"}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["smoke-test", false], ["unit-test", true]]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.extra", "value": "smoke-test"}]
}

test_a_ref_inside_a_list_of_keys_that_cannot_be_read_fails_the_requirement_rather_than_dropping_the_key if {
	req := {"s": object.union(suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "extra"]}, "unit-test"]}).s, {"min_subjects": 0})}
	every params in [{}, {"extra": null}, {"extra": ["smoke-test"]}] {
		rep := report(suite_doc, req) with data.params as params
		rep.requirements.s.status == "not_met"
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
	rows_for(report(suite_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"extra": null}
}

test_a_literal_inside_a_list_of_keys_is_read_as_written if {
	rep := report({"o": {"$x": {"result": "passed"}}}, {"s": {"from": ["o", {"each_as": "k", "keys": [{"literal": "$x"}]}], "checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}}}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["$x", true]]
}

test_refs_inside_a_literal_list_of_keys_are_not_read if {
	rep := report({"o": {"a": {}}}, {"s": {"from": ["o", {"each_as": "k", "keys": {"literal": [{"ref": ["$$params", "s"]}]}}], "checks": {"c": {"op": "present", "path": []}}}}) with data.params as {"s": "a"}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[{"ref": ["$$params", "s"]}, false]]
	not rep.requirements.s.checks["$min_subjects"]["$refs"]
}

test_a_badly_written_ref_inside_a_list_of_keys_is_not_well_formed if {
	rep := report(suite_doc, {"s": object.union(suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "s"], "note": "x"}, "unit-test"]}).s, {"min_subjects": 0})}) with data.params as {"s": "smoke-test"}
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.status == "not_met"
}

test_ref_shaped_values_in_params_are_data_not_refs if {
	rep := report({"o": {"a": {}}}, {"s": {"from": ["o", {"each_as": "k", "keys": {"ref": ["$$params", "list"]}}], "checks": {"c": {"op": "present", "path": []}}}}) with data.params as {"list": [{"ref": ["$$params", "s"]}], "s": "a"}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[{"ref": ["$$params", "s"]}, false]]
}

typo_doc := {"params": {"word": "x", "none": null, "nine": 9}, "items": [{"id": 1, "n": 1, "s": "a", "xs": [1], "t": "2026-01-01T00:00:00Z"}]}

typo_req(filter) := {"s": {
	"from": ["items"],
	"id": ["id"],
	"min_subjects": 0,
	"applies_to": {"f": filter},
	"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
}}

badly_written := [
	{"op": "nope", "path": ["n"]},
	{"op": "undeclared", "path": ["n"]},
	{"path": ["n"]},
	{"op": 3, "path": ["n"]},
	{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "bad"},
	{"op": "compare", "left": ["n"], "right": ["n"]},
	{"op": "compare_time", "left": ["t"], "right": ["t"], "cmp": "before"},
	{"op": "compare", "left": ["n"], "cmp": "eq"},
	{"op": "in", "path": ["n"], "values": "notalist"},
	{"op": "in", "path": ["n"], "values": {"literal": "notalist"}},
	{"op": "in", "path": ["n"]},
	{"op": "range", "path": ["n"], "min": "a", "max": 5},
	{"op": "range", "path": ["n"], "min": 0},
	{"op": "range", "path": ["n"], "min": 9, "max": 0},
	{"op": "equals", "path": ["n"], "value": 1, "as": "x"},
	{"op": "present", "path": ["n"], "each": ["a"]},
	{"op": "missing", "path": ["n"], "value": null},
	{"op": "empty", "path": ["xs"], "check": {"op": "present", "path": []}},
	{"op": "any_of", "as": "x", "options": {"o": [{"op": "equals", "path": ["n"], "value": 1}]}},
	{"op": "any_of", "options": {"o": [{"op": "equals", "path": ["n"], "value": 1, "each": []}]}},
	{"op": "equals", "path": ["n"]},
	{"op": "includes", "path": ["xs"]},
	{"op": "excludes", "path": ["xs"]},
	{"op": "present"},
	{"op": "non_empty_string"},
	{"op": "missing"},
	{"op": "empty"},
	{"op": "matches_any", "path": ["s"], "patterns": "a"},
	{"op": "matches_any", "path": ["s"], "patterns": [3]},
	{"op": "matches_any", "path": ["s"], "patterns": ["("]},
	{"op": "not_matches_any", "path": ["s"], "patterns": ["b", "("]},
	{"op": "not_matches_any", "path": ["s"]},
	{"op": "all", "path": ["xs"]},
	{"op": "all", "path": ["xs"], "each": {"x": 1}, "check": {"op": "present", "path": []}},
	{"op": "any", "path": ["xs"], "each": true, "check": {"op": "present", "path": []}},
	{"op": "all", "path": ["xs"], "each": false, "check": {"op": "present", "path": []}},
	{"op": "all", "path": ["xs"], "each": null, "check": {"op": "present", "path": []}},
	{"op": "all", "path": ["xs"], "each": 0, "check": {"op": "present", "path": []}},
	{"op": "any", "path": ["xs"], "check": "present"},
	{"op": "any", "check": {"op": "present", "path": []}},
	{"op": "all", "path": ["xs"], "check": {"op": "nope", "path": []}},
	{"op": "all", "path": ["xs"], "check": {"op": "even", "path": []}},
	{"op": "all", "path": ["xs"], "check": {"op": "equals", "path": []}},
	{"op": "any_of", "options": {"o": [{"op": "any_of", "options": {"p": [{"op": "present", "path": ["id"]}]}}]}},
	{"op": "any_of", "options": {"o": [{"op": "even", "path": ["n"]}]}},
	{"op": "any_of", "options": {"o": [{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "bad"}]}},
	{"op": "any_of", "options": {"o": ["present"]}},
	{"op": "any_of", "options": {"o": []}},
	{"op": "any_of", "options": {"o": {"op": "present", "path": ["n"]}}},
	{"op": "any_of", "options": {}},
	{"op": "any_of", "options": [[{"op": "present", "path": ["n"]}], []]},
	{"op": "any_of", "options": "o"},
	{"op": "any_of"},
	{"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "any_of", "options": {"p": [{"op": "present", "path": []}]}}]}}},
	{"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": [], "check": {"op": "range", "path": [], "min": "a", "max": 1}}]}}},
	{"op": "all", "path": ["xs"], "check": {"op": "all", "path": [], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": [], "check": {"op": "present", "path": []}}]}}}},
	{"op": "all", "path": ["xs"], "check": {"op": "all", "path": [], "check": {"op": "any_of", "options": {"o": [{"op": "in", "path": [], "values": 1}]}}}},
	{"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": [], "check": {"op": "any_of", "options": {"p": [{"op": "in", "path": [], "values": 1}]}}}]}}},
	{"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"p": [{"op": "all", "path": [], "check": {"op": "any_of", "options": {"q": [{"op": "compare", "left": [], "right": [], "cmp": "bad"}]}}}]}}}]}},
]

read_the_wrong_kind := [
	{"op": "range", "path": ["n"], "min": 10, "max": {"ref": ["$$input", "params", "nine"]}},
	{"op": "matches_any", "path": ["s"], "patterns": {"ref": ["$$input", "params", "word"]}},
	{"op": "in", "path": ["n"], "values": {"ref": ["$$input", "params", "word"]}},
	{"op": "range", "path": ["n"], "min": 0, "max": {"ref": ["$$input", "params", "word"]}},
	{"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "nine"]}, "max": 5},
]

test_a_filter_whose_ref_reads_the_wrong_kind_of_value_cannot_rule_subjects_out if {
	every filter in read_the_wrong_kind {
		rep := report(typo_doc, typo_req(filter))
		rep.requirements.s.status == "not_met"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unusable"]
	}
}

test_a_check_whose_ref_reads_the_wrong_kind_of_value_fails_and_is_not_ill_formed if {
	every check in read_the_wrong_kind {
		rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "unusable"]]
	}
}

test_a_badly_written_filter_cannot_rule_subjects_out if {
	every filter in badly_written {
		rep := report(typo_doc, typo_req(filter))
		rep.requirements.s.status == "not_met"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
	}
}

test_a_badly_written_check_is_ill_formed if {
	every check in badly_written {
		rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
	}
}

test_an_operator_that_is_not_declared_fails_even_when_a_rule_passes_it if {
	ergo.op_passed({"op": "undeclared", "path": ["n"]}, {"n": 1})
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "undeclared", "path": ["n"]}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_badly_written_option_fails_an_any_of_even_when_another_option_passes if {
	check := {"op": "any_of", "options": {"good": [{"op": "present", "path": ["n"]}], "bad": [{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "bad"}]}}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_badly_written_substitute_fails_the_check_even_when_the_check_passes if {
	check := {"op": "present", "path": ["n"], "substitute": {"op": "nope", "path": ["n"]}}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_bound_that_reads_null_keeps_the_cause_of_its_ref if {
	check := {"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "none"]}, "max": 5}
	rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "null"]]
}

test_a_well_written_filter_that_fails_still_rules_subjects_out if {
	every filter in [
		{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "ne"},
		{"op": "in", "path": ["n"], "values": [2, 3]},
		{"op": "range", "path": ["n"], "min": 5, "max": 9},
		{"op": "matches_any", "path": ["s"], "patterns": ["^b"]},
		{"op": "any_of", "options": {"o": [{"op": "equals", "path": ["n"], "value": 2}]}},
		{"op": "even", "path": ["n"]},
	] {
		rep := report(typo_doc, typo_req(filter))
		rep.requirements.s.status == "not_applicable"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
	}
}

test_a_present_filter_on_a_name_nothing_gives_cannot_rule_subjects_out if {
	every path in [["$p", "n"], ["$$nope", "n"]] {
		rep := report({"items": [{"id": 1, "n": 1}]}, {"s": {
			"from": ["items", {"each_as": "item"}],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": {"op": "present", "path": path}},
			"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
		}})
		rep.requirements.s.status == "not_met"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
	}
}

test_a_present_filter_on_a_given_name_still_rules_subjects_out if {
	rep := report({"items": [{"id": 1}]}, {"s": {
		"from": ["items", {"each_as": "item"}],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["$item", "n"]}},
		"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
	}})
	rep.requirements.s.status == "not_applicable"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_a_check_fails_when_its_substitute_passes_but_one_side_is_badly_written if {
	every check in [
		{"op": "equals", "path": ["n"], "value": 999, "substitute": {"op": "undeclared", "path": ["n"]}},
		{"op": "nope", "path": ["n"], "substitute": {"op": "present", "path": ["n"]}},
	] {
		rep := report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
	}
}

test_a_present_filter_with_a_badly_written_substitute_cannot_rule_subjects_out if {
	rep := report(typo_doc, typo_req({"op": "present", "path": ["missing"], "substitute": {"op": "nope", "path": ["n"]}}))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
}

test_an_unknown_op_shows_in_the_expression if {
	rendered({}, {"op": "nope", "path": ["n"]}) == "<unknown op nope>"
	rendered({}, {"op": 3, "path": ["n"]}) == "<unknown op 3>"
	rendered({}, {"path": ["n"]}) == "<missing op>"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "nope", "path": []}}) == "every xs: <unknown op nope>"
	rendered({}, {"op": "any_of", "options": {"o": [{"op": "nope", "path": ["n"]}]}}) == "one of: o(<unknown op nope>)"
}

test_a_written_expression_wins_over_the_unknown_op_text if {
	rendered({}, {"op": "nope", "path": ["n"], "expression": "n is fine"}) == "n is fine"
}

test_an_empty_list_in_a_filter_rules_subjects_out_because_nobody_can_be_meant if {
	every filter in [
		{"op": "in", "path": ["n"], "values": []},
		{"op": "in", "path": ["n"], "values": {"ref": ["$$input", "params", "nobody"]}},
		{"op": "matches_any", "path": ["s"], "patterns": []},
	] {
		rep := report(object.union(typo_doc, {"params": {"nobody": []}}), typo_req(filter))
		rep.requirements.s.status == "not_applicable"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
	}
}

test_a_range_with_equal_bounds_is_well_written if {
	verdict({"n": 1}, {"op": "range", "path": ["n"], "min": 1, "max": 1}) == true
}

test_a_check_that_is_not_an_object_shows_in_the_expression if {
	rendered({}, 1) == "<invalid check>"
	[[r.passed, r.cause] | some r in solo({}, 1).results; r.check == "c"] == [[false, "ill_formed"]]
	rendered({}, {"op": "any_of", "options": {"o": ["present"]}}) == "one of: o(<invalid check>)"
	rendered({}, {"op": "all", "path": ["xs"], "check": "present"}) == "every xs: <invalid check>"
}

test_a_check_where_it_cannot_go_shows_in_the_expression if {
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "even", "path": []}}) == "every xs: <even can't go here>"
	rendered({}, {"op": "any_of", "options": {"o": [{"op": "even", "path": ["n"]}]}}) == "one of: o(<even can't go here>)"
	rendered({}, {"op": "any_of", "options": {"o": [{"op": "any_of", "options": {"p": [{"op": "present", "path": ["n"]}]}}]}}) == "one of: o(<any_of can't go here>)"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "even", "path": []}]}}}) == "every xs: one of: o(<even can't go here>)"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "even", "path": []}}}) == "every xs: every ys: <even can't go here>"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "any_of", "options": {"o": [{"op": "even", "path": []}]}}}}) == "every xs: every ys: one of: o(<even can't go here>)"
}

ordering_doc := {"id": 1, "a": {"name": "ann"}, "b": {"owner": "bob"}, "xs": [2], "ys": [1, 9], "f": false, "t": true, "n": 1, "m": 2, "s": "a", "z": "b"}

test_ordering_objects_lists_or_booleans_fails_as_unusable if {
	every check in [
		{"op": "compare", "left": ["a"], "right": ["b"], "cmp": "lt"},
		{"op": "compare", "left": ["b"], "right": ["a"], "cmp": "gte"},
		{"op": "compare", "left": ["xs"], "right": ["ys"], "cmp": "gt"},
		{"op": "compare", "left": ["f"], "right": ["t"], "cmp": "lte"},
		{"op": "compare", "left": [], "right": [], "cmp": "lte"},
	] {
		verdict(ordering_doc, check) == false
		cause_of(ordering_doc, check) == "unusable"
	}
}

test_ordering_numbers_and_strings_still_works if {
	verdict(ordering_doc, {"op": "compare", "left": ["n"], "right": ["m"], "cmp": "lt"}) == true
	verdict(ordering_doc, {"op": "compare", "left": ["z"], "right": ["s"], "cmp": "gt"}) == true
	cause_of(ordering_doc, {"op": "compare", "left": ["m"], "right": ["n"], "cmp": "lt"}) == "value"
}

test_ordering_a_number_against_a_string_fails_as_unusable if {
	cause_of(ordering_doc, {"op": "compare", "left": ["n"], "right": ["s"], "cmp": "lt"}) == "unusable"
}

test_eq_and_ne_still_compare_objects_lists_and_booleans if {
	verdict(ordering_doc, {"op": "compare", "left": ["a"], "right": ["a"], "cmp": "eq"}) == true
	verdict(ordering_doc, {"op": "compare", "left": ["xs"], "right": ["ys"], "cmp": "ne"}) == true
	cause_of(ordering_doc, {"op": "compare", "left": ["f"], "right": ["t"], "cmp": "eq"}) == "value"
}

test_a_filter_ordering_objects_cannot_rule_subjects_out if {
	every filter in [
		{"op": "compare", "left": ["a"], "right": ["b"], "cmp": "lt"},
		{"op": "any_of", "options": {"o": [{"op": "compare", "left": ["xs"], "right": ["ys"], "cmp": "lt"}]}},
		{"op": "equals", "path": ["n"], "value": 5, "substitute": {"op": "compare", "left": ["a"], "right": ["b"], "cmp": "lt"}},
		{"op": "present", "path": ["missing"], "substitute": {"op": "compare", "left": ["a"], "right": ["b"], "cmp": "lt"}},
	] {
		rep := report({"items": [ordering_doc]}, {"s": {
			"from": ["items"],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": filter},
			"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
		}})
		rep.requirements.s.status == "not_met"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unusable"]
	}
}

test_a_present_filter_with_a_substitute_ordering_numbers_still_rules_subjects_out if {
	rep := report({"items": [ordering_doc]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["missing"], "substitute": {"op": "compare", "left": ["n"], "right": ["m"], "cmp": "gt"}}},
		"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
	}})
	rep.requirements.s.status == "not_applicable"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

one_item := {"items": [{"id": 1}]}

test_requirements_written_as_a_number_are_not_compliant if {
	report(one_item, 5).compliant == false
}

test_a_requirement_that_is_not_an_object_is_not_compliant if {
	report(one_item, {"s": 5}).compliant == false
}

test_checks_that_are_not_an_object_are_not_compliant if {
	report(one_item, {"s": {"from": ["items"], "checks": 5}}).compliant == false
}

test_an_applies_to_that_is_a_number_is_not_compliant if {
	report(one_item, {"s": {"from": ["items"], "applies_to": 5, "checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_an_applies_to_that_is_a_string_is_not_compliant if {
	report(one_item, {"s": {"from": ["items"], "applies_to": "x", "checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_a_filter_whose_custom_expression_is_not_a_string_still_filters if {
	rep := report(one_item, {"s": {
		"from": ["items"],
		"applies_to": {"f": {"op": "present", "path": ["id"], "expression": ["id"]}},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}})
	rep.compliant == true
}

test_an_input_that_is_a_string_without_from_is_not_compliant if {
	report("x", {"s": {"checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_an_input_that_is_a_list_without_from_is_not_compliant if {
	report([{"id": 1}], {"s": {"checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_a_selector_on_a_subject_that_is_not_an_object_fails_as_not_an_object if {
	rep := report({"items": ["b"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "equals", "path": [{"where": {"id": 1}}, "n"], "value": 1}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "not_an_object"]]
}

test_a_ref_that_starts_with_a_number_fails_closed if {
	cause_of({"id": 1}, {"op": "equals", "path": ["id"], "value": {"ref": [5, "x"]}}) == "ill_formed"
}

failed_of(subj, check) := row.failed_items if {
	some row in solo(subj, check).results
	row.check == "c"
}

no_self_deploy := {"segregation": {
	"subject_type": "deployment",
	"from": ["deployments", {"each_as": "deploy"}],
	"id": ["id"],
	"checks": {"not_self_deployed": {
		"op": "all",
		"path": ["pull_requests"],
		"each": ["commits"],
		"check": {"op": "compare", "left": ["author"], "right": ["$deploy", "deployed_by"], "cmp": "ne"},
	}},
}}

self_deployed(prs) := rows_for(report({"deployments": [{"id": "d", "deployed_by": "bob", "pull_requests": prs}]}, no_self_deploy), "segregation", "not_self_deployed")[0]

test_failed_items_name_only_the_items_of_an_all_that_failed if {
	row := self_deployed([
		{"number": 7, "commits": [{"sha": "a1", "author": "ann"}]},
		{"number": 8, "commits": [{"sha": "b1", "author": "ann"}, {"sha": "b2", "author": "bob"}]},
	])
	row.passed == false
	row.failed_items == [{"path": "item 2 of pull_requests[1].commits", "item": "item 2 of pull_requests[1].commits", "cause": "value", "value": {"sha": "b2", "author": "bob"}}]
}

test_failed_items_is_empty_when_every_item_passes if {
	row := self_deployed([{"number": 9, "commits": [{"sha": "c1", "author": "ann"}, {"sha": "c2", "author": "carol"}]}])
	row.passed == true
	row.failed_items == []
}

test_failed_items_name_an_inner_list_that_fails_the_check_because_it_is_empty_missing_or_not_a_list if {
	row := self_deployed([
		{"number": 11, "commits": []},
		{"number": 12},
		{"number": 13, "commits": "x"},
		{"number": 14, "commits": [{"sha": "e1", "author": "ann"}]},
	])
	row.passed == false
	row.failed_items == [
		{"path": "pull_requests[0].commits", "item": "pull_requests[0].commits", "cause": "value", "value": []},
		{"path": "pull_requests[1].commits", "item": "pull_requests[1].commits", "cause": "absent", "value": null},
		{"path": "pull_requests[2].commits", "item": "pull_requests[2].commits", "cause": "unusable", "value": "x"},
	]
}

test_failed_items_give_items_that_are_not_objects_or_are_null_their_own_cause if {
	row := self_deployed(["x", {"number": 1, "commits": [null, "y", {"author": null}]}])
	[[f.path, f.cause] | some f in row.failed_items] == [
		["pull_requests[0].commits", "not_an_object"],
		["item 1 of pull_requests[1].commits", "not_an_object"],
		["item 2 of pull_requests[1].commits", "not_an_object"],
		["item 3 of pull_requests[1].commits", "null"],
	]
}

test_failed_items_of_a_failing_any_list_every_item_with_its_own_cause if {
	check := {"op": "any", "path": ["approvers"], "check": {"op": "compare", "left": ["username"], "right": ["$$input", "items", 0, "author"], "cmp": "ne"}}
	subj := {"id": 42, "author": "ann", "approvers": [{"username": "ann"}, {"name": "Bob"}]}
	verdict(subj, check) == false
	failed_of(subj, check) == [
		{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "value", "value": {"username": "ann"}},
		{"path": "item 2 of approvers", "item": "item 2 of approvers", "cause": "absent", "value": {"name": "Bob"}},
	]
}

test_failed_items_of_a_passing_any_is_empty_because_no_item_made_it_fail if {
	subj := {"id": 1, "approvers": [{"username": "ann"}, {"username": "bob"}]}
	check := {"op": "any", "path": ["approvers"], "check": {"op": "equals", "path": ["username"], "value": "bob"}}
	verdict(subj, check) == true
	failed_of(subj, check) == []
}

test_failed_items_is_empty_when_the_list_itself_cannot_be_read_because_the_row_cause_says_why if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1}}
	rows := [[cause_of(subj, check), failed_of(subj, check)] | some subj in [{"id": 1}, {"id": 1, "xs": null}, {"id": 1, "xs": "a"}, {"id": 1, "xs": []}]]
	rows == [["absent", []], ["null", []], ["unusable", []], ["value", []]]
}

test_failed_items_of_a_check_written_wrong_name_every_item_as_ill_formed if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1}, "typo": true}
	subj := {"id": 1, "xs": [1, 2]}
	cause_of(subj, check) == "ill_formed"
	failed_of(subj, check) == [
		{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "ill_formed", "value": 1},
		{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "ill_formed", "value": 2},
	]
}

test_failed_items_of_a_check_written_wrong_name_bad_inner_lists_as_ill_formed_too if {
	check := {"op": "all", "path": ["prs"], "each": ["commits"], "check": {"op": "nope"}}
	failed_of({"id": 1, "prs": [{"commits": [1]}, {}]}, check) == [
		{"path": "item 1 of prs[0].commits", "item": "item 1 of prs[0].commits", "cause": "ill_formed", "value": 1},
		{"path": "prs[1].commits", "item": "prs[1].commits", "cause": "ill_formed", "value": null},
	]
}

test_failed_items_take_the_cause_of_a_ref_that_cannot_be_read if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "in", "path": [], "values": {"ref": ["$$params", "allowed"]}}}
	subj := {"id": 1, "xs": ["a", "b"]}
	failed_of(subj, check) == [
		{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": "a"},
		{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "absent", "value": "b"},
	]
}

test_failed_items_read_names_given_with_as if {
	check := {"op": "all", "path": ["commits"], "as": "c", "check": {"op": "compare", "left": ["$c", "author"], "right": ["$$input", "items", 0, "owner"], "cmp": "ne"}}
	subj := {"id": 1, "owner": "bob", "commits": [{"author": "bob"}, {"author": "ann"}]}
	failed_of(subj, check) == [{"path": "item 1 of commits", "item": "item 1 of commits", "cause": "value", "value": {"author": "bob"}}]
}

test_failed_items_write_paths_the_way_inputs_do if {
	check := {"op": "all", "path": ["pull requests"], "each": ["the commits"], "check": {"op": "present", "path": ["sha"]}}
	subj := {"id": 1, "pull requests": [{"the commits": [{}]}]}
	inputs_of(subj, check)[0].name == "\"pull requests\"[].\"the commits\""
	failed_of(subj, check)[0].path == "item 1 of \"pull requests\"[0].\"the commits\""
}

test_failed_items_of_a_named_path_start_with_the_name if {
	rep := report({"prs": [{"number": 1, "commits": [{"sha": "a"}, {}]}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "all", "path": ["$pr", "commits"], "check": {"op": "present", "path": ["sha"]}}},
	}})
	rows_for(rep, "s", "c")[0].failed_items == [{"path": "item 2 of $pr.commits", "item": "item 2 of $pr.commits", "cause": "value", "value": {}}]
}

test_failed_items_of_a_substituted_check_are_those_of_the_main_check if {
	check := {
		"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1},
		"substitute": {"op": "present", "path": ["waiver"]},
	}
	subj := {"id": 1, "xs": [1, 2], "waiver": "ok"}
	cause_of(subj, check) == "substituted"
	failed_of(subj, check) == [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "value", "value": 2}]
}

test_only_rows_of_all_and_any_checks_have_failed_items if {
	rep := report({"items": [{"id": 1, "xs": [1], "env": "prod"}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1}}},
		"checks": {
			"leaf": {"op": "equals", "path": ["env"], "value": "prod"},
			"either": {"op": "any_of", "options": {"a": [{"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 2}}]}},
			"every": {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 2}},
		},
	}})
	{r.check | some r in rep.results; "failed_items" in object.keys(r)} == {"every"}
}

test_violations_carry_failed_items_and_other_checks_have_none if {
	rep := report({"items": [{"id": 1, "xs": [1, 2], "env": "dev"}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {
			"leaf": {"op": "equals", "path": ["env"], "value": "prod"},
			"every": {"op": "all", "path": ["xs"], "check": {"op": "equals", "path": [], "value": 1}},
		},
	}})
	[[v.check, object.get(v, "failed_items", "none")] | some v in ergo.violations(rep)] == [
		["every", [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "value", "value": 2}]],
		["leaf", "none"],
	]
}

test_failed_items_of_a_nested_check_name_the_outer_item_only if {
	rep := report(
		{"prs": [{
			"number": 42,
			"commits": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}, {"sha": "c2", "timestamp": "2026-10-01T12:00:00Z"}],
			"approvers": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}],
		}]},
		{"s": {
			"from": ["prs", {"each_as": "pr"}],
			"id": ["number"],
			"checks": {"c": {
				"op": "any",
				"path": ["approvers"],
				"as": "approver",
				"check": {"op": "all", "path": ["$pr", "commits"], "check": {"op": "compare_time", "left": ["$approver", "timestamp"], "right": ["timestamp"], "cmp": "gt"}},
			}},
		}},
	)
	rows_for(rep, "s", "c")[0].failed_items == [{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "value", "value": {"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}}]
}

test_failed_items_leave_out_an_item_that_passes_another_option_when_a_ref_cannot_be_read if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {
		"listed": [{"op": "in", "path": [], "values": {"ref": ["$$params", "missing"]}}],
		"one": [{"op": "equals", "path": [], "value": 1}],
	}}}
	subj := {"id": 1, "xs": [1, 2]}
	cause_of(subj, check) == "absent"
	failed_of(subj, check) == [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "absent", "value": 2}]
}

test_failed_items_of_an_empty_each_add_only_the_position if {
	check := {"op": "all", "path": ["xs"], "each": [], "check": {"op": "equals", "path": [], "value": 1}}
	failed_of({"id": 1, "xs": [[1, 2], {"v": 1}]}, check) == [
		{"path": "item 2 of xs[0]", "item": "item 2 of xs[0]", "cause": "value", "value": 2},
		{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "unusable", "value": {"v": 1}},
	]
}

json_only_req := {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["x"], "value": 1}}}}

row_verdicts(rep) := [[r.check, r.passed, r.cause] | some r in rep.results]

test_a_set_anywhere_in_the_input_fails_every_check_as_unusable_so_a_port_can_check_the_input_once if {
	rep := report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, json_only_req)
	row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", false, "unusable"], ["$unique_ids", true, "satisfied"], ["c", false, "unusable"]]
	rep.requirements.s.status == "not_met"
}

test_a_key_that_is_not_a_string_in_the_input_fails_the_check_even_when_a_number_step_reaches_it if {
	req := {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["x", 1], "value": "a"}}}}
	rows_for(report({"items": [{"id": "a", "x": {1: "a"}}]}, req), "s", "c")[0].cause == "unusable"
}

test_a_set_in_the_input_fails_checks_that_pass_on_nothing if {
	every check in [{"op": "missing", "path": ["y"]}, {"op": "excludes", "path": ["y"], "value": "x"}, {"op": "empty", "path": ["y"]}] {
		req := {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": check}}}
		r := rows_for(report({"items": [{"id": "a"}], "tags": {"prod"}}, req), "s", "c")[0]
		[r.passed, r.cause] == [false, "unusable"]
	}
}

test_a_set_in_the_input_takes_every_subject_out_of_scope_as_unusable if {
	req := {"s": object.union(json_only_req.s, {"applies_to": {"f": {"op": "present", "path": ["id"]}}})}
	rows_for(report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, req), "s", "$applies")[0].cause == "unusable"
}

test_a_set_in_the_input_fails_a_requirement_that_has_no_subjects if {
	req := {"s": object.union(json_only_req.s, {"min_subjects": 0})}
	report({"items": [], "tags": {"prod"}}, req).requirements.s.status == "not_met"
}

test_a_set_in_the_params_fails_every_check_as_unusable if {
	req := {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": {"op": "in", "path": ["x"], "values": {"ref": ["$$params", "allowed"]}}}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": {"MIT"}}), "s", "c")[0].cause == "unusable"
}

test_a_list_in_the_params_is_read_as_usual if {
	req := {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": {"op": "in", "path": ["x"], "values": {"ref": ["$$params", "allowed"]}}}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": ["MIT"]}), "s", "c")[0].passed == true
}

test_a_check_holding_a_set_or_a_key_that_is_not_a_string_is_written_wrong if {
	rep := report({"items": [{"id": "a", "x": 1}]}, {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {
		"k": {"op": "equals", "path": ["x"], "value": {1: "a"}},
		"s": {"op": "in", "path": ["x"], "values": {1, 2}},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.k", "value": ["holds a key that isn't a string"]},
		{"name": "checks.s", "value": ["holds a set"]},
	]
	[r.cause | some r in rep.results; r.check in {"k", "s"}] == ["ill_formed", "ill_formed"]
}

test_a_set_in_a_selector_of_from_or_id_is_written_wrong if {
	every f in ["from", "id"] {
		req := {"s": object.union(json_only_req.s, {f: [{"where": {"x": {1}}}]})}
		some i in rows_for(report({"items": [{"id": "a", "x": 1}]}, req), "s", "$well_formed")[0].inputs
		i.name == concat(".", ["subjects", "thing", f])
		"holds a set" in i.value
	}
}

test_a_set_in_the_input_fails_every_check_on_subjects_named_with_each_as if {
	req := {"s": object.union(json_only_req.s, {"from": ["items", {"each_as": "it"}], "checks": {"c": {"op": "equals", "path": ["$it", "x"], "value": 1}}})}
	rep := report({"items": [{"id": "a", "x": 1}, {"id": "b", "x": 1}], "tags": {"prod"}}, req)
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "unusable"], [false, "unusable"]]
}

test_min_subjects_says_what_the_input_and_params_hold_that_json_cannot if {
	rep := ergo.report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}, "k": {1: "a"}}, lifted(json_only_req), {"allowed": {"MIT"}})
	rows_for(rep, "s", "$min_subjects")[0].inputs == [
		{"name": "in-scope thing count", "value": 1},
		{"name": "$input", "value": ["holds a key that isn't a string", "holds a set"]},
		{"name": "$params", "value": ["holds a set"]},
	]
}

test_min_subjects_lists_only_the_count_when_the_input_and_params_are_json if {
	rows_for(ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), {"allowed": ["MIT"]}), "s", "$min_subjects")[0].inputs == [{"name": "in-scope thing count", "value": 1}]
}

test_a_check_or_filter_name_that_is_not_a_string_is_written_wrong if {
	every f in ["checks", "applies_to"] {
		named := {1: {"op": "present", "path": ["x"]}}
		req := {"s": object.union(json_only_req.s, {f: object.union(object.get(json_only_req.s, f, {}), named)})}
		rep := report({"items": [{"id": "a", "x": 1}]}, req)
		rows_for(rep, "s", "$well_formed")[0].passed == false
		name := {"checks": "checks", "applies_to": "subjects.thing.applies_to"}[f]
		{"name": name, "value": ["holds a key that isn't a string"]} in rows_for(rep, "s", "$well_formed")[0].inputs
		rep.requirements.s.status == "not_met"
	}
}

test_a_requirement_name_that_is_not_a_string_fails_the_requirement_and_the_policy if {
	every policy in [{1: json_only_req.s}, [json_only_req.s]] {
		rep := report({"items": [{"id": "a", "x": 1}]}, policy)
		rep.compliant == false
		some name, r in rep.requirements
		r.status == "not_met"
		some row in rep.results
		[row.requirement, row.check, row.passed] == [name, "$well_formed", false]
		row.inputs[0] == {"name": "requirement name", "value": ["not a string"]}
	}
}

test_a_policy_written_as_a_set_is_not_compliant if {
	report({"items": [{"id": "a", "x": 1}]}, {json_only_req.s}).compliant == false
}

test_patterns_written_as_a_set_are_only_reported_as_a_set if {
	rep := report({"items": [{"id": "a", "x": "b"}]}, {"s": object.union(json_only_req.s, {"checks": {"m": {"op": "matches_any", "path": ["x"], "patterns": {"b"}}}})})
	problem_inputs(rep) == [{"name": "checks.m", "value": ["holds a set"]}]
}

test_an_any_of_with_a_stray_path_is_written_wrong_instead_of_stopping_the_report if {
	check := {"op": "any_of", "path": ["y"], "options": {"o": [{"op": "equals", "path": ["x"], "value": 1}]}}
	rep := report({"items": [{"id": "a", "x": 1}]}, {"s": {"subject_type": "thing", "from": ["items"], "id": ["id"], "checks": {"c": check}}})
	r := rows_for(rep, "s", "c")[0]
	[r.passed, r.cause, r.inputs] == [false, "ill_formed", [{"name": "x", "value": 1}]]
	rep.compliant == false
}

test_an_item_whose_field_present_finds_missing_is_listed_as_value_like_its_row_because_missing_is_not_a_cause if {
	every op in ["all", "any"] {
		check := {"op": op, "path": ["commits"], "check": {"op": "present", "path": ["sha"]}}
		subj := {"id": 1, "commits": [{}, {"sha": null}]}
		cause_of(subj, check) == "value"
		failed_of(subj, check) == [
			{"path": "item 1 of commits", "item": "item 1 of commits", "cause": "value", "value": {}},
			{"path": "item 2 of commits", "item": "item 2 of commits", "cause": "value", "value": {"sha": null}},
		]
	}
}

test_an_inner_list_item_whose_field_present_finds_missing_is_listed_as_value_too if {
	check := {"op": "all", "path": ["prs"], "each": ["commits"], "check": {"op": "present", "path": ["sha"]}}
	failed_of({"id": 1, "prs": [{"commits": [{"sha": "a"}, {}]}]}, check) == [{"path": "item 2 of prs[0].commits", "item": "item 2 of prs[0].commits", "cause": "value", "value": {}}]
}

absent_lookalike := {"ergo/absent": true}

lookalike_rows(doc, req) := [[r.check, r.subject.id, r.passed, r.cause, r.inputs] |
	some r in report(doc, req).results
	not startswith(r.check, "$")
]

lookalike_req(from, checks) := {"s": {"from": from, "id": ["id"], "checks": checks}}

test_a_field_holding_an_object_like_ergos_absent_marker_is_there if {
	lookalike_rows({"items": [{"id": 1, "o": absent_lookalike}]}, lookalike_req(["items"], {
		"m": {"op": "missing", "path": ["o"]},
		"p": {"op": "present", "path": ["o"]},
	})) == [
		["m", 1, false, "value", [{"name": "o", "value": absent_lookalike}]],
		["p", 1, true, "satisfied", [{"name": "o", "value": absent_lookalike}]],
	]
}

test_a_named_field_holding_an_object_like_ergos_absent_marker_is_there if {
	lookalike_rows({"items": [{"id": 1, "o": absent_lookalike}]}, lookalike_req(["items", {"each_as": "it"}], {"m": {"op": "missing", "path": ["$it", "o"]}})) == [["m", 1, false, "value", [{"name": "$it.o", "value": absent_lookalike}]]]
}

test_a_selected_field_holding_an_object_like_ergos_absent_marker_is_there if {
	lookalike_rows({"items": [{"id": 1, "xs": [{"k": 1, "v": absent_lookalike}]}]}, lookalike_req(["items"], {"m": {"op": "missing", "path": ["xs", {"where": {"k": 1}}, "v"]}})) == [["m", 1, false, "value", [{"name": "xs.[k==1].v", "value": absent_lookalike}]]]
}

test_a_selector_looking_for_an_object_like_ergos_absent_marker_does_not_match_a_missing_key if {
	lookalike_rows({"items": [{"id": 1, "xs": [{"v": 1}]}]}, lookalike_req(["items"], {"p": {"op": "present", "path": ["xs", {"where": {"k": {"literal": absent_lookalike}}}, "v"]}})) == [["p", 1, false, "unmatched", [{"name": "xs.[k=={\"ergo/absent\": true}].v", "value": null}]]]
}

test_a_ref_to_an_object_like_ergos_absent_marker_reads_it if {
	rows := lookalike_rows({"items": [{"id": 1, "a": absent_lookalike}]}, lookalike_req(["items"], {"e": {"op": "equals", "path": ["a"], "value": {"ref": ["$$params", "x"]}}})) with data.params as {"x": absent_lookalike}
	rows == [["e", 1, true, "satisfied", [{"name": ".a", "value": absent_lookalike}]]]
}

test_a_from_leading_to_an_object_like_ergos_absent_marker_finds_it if {
	rep := report({"items": absent_lookalike}, {"s": {"from": ["items"], "checks": {"p": {"op": "present", "path": []}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied"]]
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "p")] == [[absent_lookalike, true, "satisfied"]]
}

test_a_key_holding_an_object_like_ergos_absent_marker_is_a_subject_that_is_there if {
	rep := report({"t": {"a": absent_lookalike}}, {"s": {"from": ["t", {"each_as": "e", "keys": ["a"]}], "checks": {"p": {"op": "present", "path": []}}}})
	[[r.subject.id, r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "p")] == [["a", true, "satisfied", [{"name": "$e", "value": absent_lookalike}]]]
}

test_ergos_absent_marker_is_something_only_an_input_that_fails_closed_can_hold if {
	req := lookalike_req(["items"], {"m": {"op": "missing", "path": ["o"]}})
	rep := report({"items": [{"id": 1, "o": ergo._absent}]}, req)
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"$min_subjects", "m"}] == [["$min_subjects", false, "unusable"], ["m", false, "unusable"]]
	from_params := report({"items": [{"id": 1}]}, req) with data.params as {"x": ergo._absent}
	[[r.check, r.passed, r.cause] | some r in from_params.results; r.check in {"$min_subjects", "m"}] == [["$min_subjects", false, "unusable"], ["m", false, "unusable"]]
}

deployments_doc := {"deployments": [
	{"id": "d-1", "environment": "prod", "approved_by": "alice", "tested": true},
	{"id": "d-2", "environment": "prod", "tested": false},
	{"id": "d-3", "environment": "staging"},
]}

prod_deployment := {"from": ["deployments"], "id": ["id"], "applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}}}

subject_policy(subjects, reqs) := {"subjects": subjects, "requirements": reqs}

approved_req(subject) := {"subject": subject, "checks": {"approved": {"op": "non_empty_string", "path": ["approved_by"]}}}

tested_req(subject) := {"subject": subject, "checks": {"tested": {"op": "equals", "path": ["tested"], "value": true}}}

subject_rows(rep) := [[r.requirement, r.subject.type, r.subject.id, r.check, r.passed, r.cause] | some r in rep.results]

test_requirements_that_name_the_same_subject_each_check_its_subjects if {
	rep := ergo.report(deployments_doc, subject_policy({"deployment": prod_deployment}, {"approved": approved_req("deployment"), "tested": tested_req("deployment")}), {})
	rep.compliant == false
	subject_rows(rep) == [
		["approved", "deployment", null, "$well_formed", true, "satisfied"],
		["tested", "deployment", null, "$well_formed", true, "satisfied"],
		["approved", "deployment", null, "$min_subjects", true, "satisfied"],
		["tested", "deployment", null, "$min_subjects", true, "satisfied"],
		["approved", "deployment", null, "$unique_ids", true, "satisfied"],
		["tested", "deployment", null, "$unique_ids", true, "satisfied"],
		["approved", "deployment", "d-1", "$applies", true, "satisfied"],
		["approved", "deployment", "d-2", "$applies", true, "satisfied"],
		["approved", "deployment", "d-3", "$applies", false, "value"],
		["tested", "deployment", "d-1", "$applies", true, "satisfied"],
		["tested", "deployment", "d-2", "$applies", true, "satisfied"],
		["tested", "deployment", "d-3", "$applies", false, "value"],
		["approved", "deployment", "d-1", "approved", true, "satisfied"],
		["approved", "deployment", "d-2", "approved", false, "absent"],
		["tested", "deployment", "d-1", "tested", true, "satisfied"],
		["tested", "deployment", "d-2", "tested", false, "value"],
	]
	rep.requirements.approved.checks["$applies"].expression == `environment == "prod"`
	rep.requirements.tested.subjects == {"total": 3, "matching": 2}
}

well_formed_problems(rep, name) := [i | some i in rows_for(rep, name, "$well_formed")[0].inputs; not i.name in {"count(checks)", "require"}]

test_a_requirement_without_a_subject_fails_well_formed_and_checks_nothing if {
	rep := ergo.report(deployments_doc, subject_policy({"deployment": prod_deployment}, {"s": object.remove(approved_req("deployment"), ["subject"])}), {})
	rep.requirements.s.status == "not_met"
	well_formed_problems(rep, "s") == [{"name": "subject", "value": ["missing"]}]
	[[r.check, r.passed] | some r in rep.results; r.check != "$well_formed"] == [["$min_subjects", false], ["$unique_ids", true]]
}

test_a_subject_that_is_not_in_subjects_fails_well_formed_and_checks_nothing if {
	every policy in [
		subject_policy({"deployment": prod_deployment}, {"s": approved_req("deploymnt")}),
		subject_policy({}, {"s": approved_req("deployment")}),
		{"requirements": {"s": approved_req("deployment")}},
	] {
		rep := ergo.report(deployments_doc, policy, {})
		rep.requirements.s.status == "not_met"
		well_formed_problems(rep, "s") == [{"name": "subject", "value": ["not in subjects"]}]
		[[r.check, r.passed] | some r in rep.results; r.check != "$well_formed"] == [["$min_subjects", false], ["$unique_ids", true]]
	}
}

test_subjects_that_are_not_an_object_fail_every_requirement_that_names_one if {
	every subjects in [null, "deployment", ["deployment"], 1] {
		rep := ergo.report(deployments_doc, subject_policy(subjects, {"s": approved_req("deployment")}), {})
		rep.requirements.s.status == "not_met"
		well_formed_problems(rep, "s") == [{"name": "subjects", "value": ["not an object"]}]
	}
}

test_a_subject_that_is_not_an_object_fails_every_requirement_that_names_it if {
	every def in ["deployments", [], 1] {
		rep := ergo.report(deployments_doc, subject_policy({"deployment": def}, {"a": approved_req("deployment"), "t": tested_req("deployment")}), {})
		[rep.requirements.a.status, rep.requirements.t.status] == ["not_met", "not_met"]
		well_formed_problems(rep, "a") == [{"name": "subjects.deployment", "value": ["not an object"]}]
		well_formed_problems(rep, "t") == [{"name": "subjects.deployment", "value": ["not an object"]}]
	}
}

test_a_badly_written_subject_fails_every_requirement_that_names_it if {
	broken := object.union(prod_deployment, {"from": 5, "id": [true], "applies_to": {"is_prod": {"op": "equls", "path": ["environment"]}}, "zz": 1, "description": 5})
	rep := ergo.report(deployments_doc, subject_policy({"deployment": broken}, {"a": approved_req("deployment"), "t": tested_req("deployment")}), {})
	rep.compliant == false
	every name in ["a", "t"] {
		rep.requirements[name].status == "not_met"
		well_formed_problems(rep, name) == [
			{"name": "subjects.deployment.description", "value": ["not a string"]},
			{"name": "subjects.deployment.from", "value": ["not a list or a string"]},
			{"name": "subjects.deployment.id", "value": ["step that can't be a key"]},
			{"name": "subjects.deployment.zz", "value": ["unknown field"]},
			{"name": "subjects.deployment.applies_to.is_prod", "value": ["unknown op equls"]},
		]
	}
}

test_a_subject_no_requirement_names_leaves_the_report_unchanged if {
	policy := subject_policy({"deployment": prod_deployment}, {"a": approved_req("deployment")})
	rep := ergo.report(deployments_doc, policy, {})
	with_unused := object.union(policy, {"subjects": {"deployment": prod_deployment, "release": {"from": "releases", "zz": 1}}})
	ergo.report(deployments_doc, with_unused, {}) == rep
}

test_a_subject_can_have_a_description if {
	described := object.union(prod_deployment, {"description": "A deployment to production"})
	rep := ergo.report(deployments_doc, subject_policy({"deployment": described}, {"a": approved_req("deployment")}), {})
	rows_for(rep, "a", "$well_formed")[0].passed == true
	rep == ergo.report(deployments_doc, subject_policy({"deployment": prod_deployment}, {"a": approved_req("deployment")}), {})
}

test_a_subject_can_read_params if {
	from_params := {"from": [{"ref": ["$$params", "list"]}], "id": ["id"], "applies_to": {"env": {"op": "equals", "path": ["environment"], "value": {"ref": ["$$params", "env"]}}}}
	rep := ergo.report(deployments_doc, subject_policy({"deployment": from_params}, {"a": approved_req("deployment")}), {"list": "deployments", "env": "staging"})
	[[r.subject.id, r.check, r.passed] | some r in rep.results; r.check == "$applies"] == [["d-1", "$applies", false], ["d-2", "$applies", false], ["d-3", "$applies", true]]
	rep.requirements.a.checks["$applies"]["$refs"] == [{"name": "$params.env", "value": "staging"}]
}

sbom_doc := {"components": [
	{"name": "a", "lock_release": "1.0", "sbom_release": "1.0", "exempt": false},
	{"name": "b", "lock_release": "2.0", "sbom_release": "2.1", "exempt": true},
	{"name": "c", "sbom_release": "3.0", "exempt": false},
]}

sbom_subjects := {
	"SBOM package": {"from": ["components"], "id": ["name"]},
	"locked SBOM package": {"of": "SBOM package", "applies_to": {"locked": {"op": "present", "path": ["lock_release"]}}},
	"non-exempt SBOM package": {"of": "SBOM package", "applies_to": {"not_exempt": {"op": "equals", "path": ["exempt"], "value": false}}},
}

sbom_reqs := {
	"versions": {"subject": "locked SBOM package", "checks": {"matches_lock": {"op": "compare", "left": ["sbom_release"], "right": ["lock_release"], "cmp": "eq"}}},
	"named": {"subject": "non-exempt SBOM package", "checks": {"named": {"op": "non_empty_string", "path": ["name"]}}},
}

test_a_subject_built_on_another_reads_its_from_and_id_and_adds_its_own_filters if {
	rep := ergo.report(sbom_doc, subject_policy(sbom_subjects, sbom_reqs), {})
	[[r.requirement, r.subject.type, r.subject.id, r.check, r.passed] | some r in rep.results; not r.check in {"$well_formed", "$min_subjects", "$unique_ids"}] == [
		["named", "non-exempt SBOM package", "a", "$applies", true],
		["named", "non-exempt SBOM package", "b", "$applies", false],
		["named", "non-exempt SBOM package", "c", "$applies", true],
		["versions", "locked SBOM package", "a", "$applies", true],
		["versions", "locked SBOM package", "b", "$applies", true],
		["versions", "locked SBOM package", "c", "$applies", false],
		["named", "non-exempt SBOM package", "a", "named", true],
		["named", "non-exempt SBOM package", "c", "named", true],
		["versions", "locked SBOM package", "a", "matches_lock", true],
		["versions", "locked SBOM package", "b", "matches_lock", false],
	]
	[r.passed | some r in rep.results; r.check == "$well_formed"] == [true, true]
}

test_a_subject_built_on_another_reports_what_the_same_subject_written_out_reports if {
	built := {
		"base": {"from": ["components"], "id": ["name"], "applies_to": {"has_sbom": {"op": "present", "path": ["sbom_release"]}}},
		"locked": {"of": "base", "description": "A package the lockfile pins", "applies_to": {"locked": {"op": "present", "path": ["lock_release"]}}},
	}
	written_out := {"locked": {"from": ["components"], "id": ["name"], "applies_to": {
		"has_sbom": {"op": "present", "path": ["sbom_release"]},
		"locked": {"op": "present", "path": ["lock_release"]},
	}}}
	versions := object.union(sbom_reqs.versions, {"subject": "locked"})
	rep := ergo.report(sbom_doc, subject_policy(built, {"versions": versions}), {})
	rep == ergo.report(sbom_doc, subject_policy(written_out, {"versions": versions}), {})
	rep.requirements.versions.checks["$applies"].expression == "sbom_release is present and lock_release is present"
}

test_a_requirement_can_name_the_subject_others_build_on if {
	rep := ergo.report(sbom_doc, subject_policy(sbom_subjects, {"all": {"subject": "SBOM package", "checks": {"named": {"op": "non_empty_string", "path": ["name"]}}}}), {})
	rep.compliant == true
	rep.requirements.all.subjects == {"total": 3, "matching": 3}
}

built_problems(subjects) := well_formed_problems(ergo.report(sbom_doc, subject_policy(subjects, {"v": sbom_reqs.versions}), {}), "v")

test_a_subject_built_on_one_that_is_not_there_fails_and_checks_nothing if {
	subjects := {"locked SBOM package": sbom_subjects["locked SBOM package"]}
	built_problems(subjects) == [{"name": "subjects.\"locked SBOM package\".of", "value": ["not in subjects"]}]
	rep := ergo.report(sbom_doc, subject_policy(subjects, {"v": sbom_reqs.versions}), {})
	[[r.check, r.passed] | some r in rep.results; r.check != "$well_formed"] == [["$min_subjects", false], ["$unique_ids", true]]
}

test_a_subject_built_on_one_that_is_not_an_object_fails if {
	every base in ["components", []] {
		built_problems(object.union(sbom_subjects, {"SBOM package": base})) == [{"name": "subjects.\"SBOM package\"", "value": ["not an object"]}]
	}
}

deep_subjects := {
	"component": {"from": ["components"], "id": ["name"]},
	"SBOM package": {"of": "component", "applies_to": {"has_sbom": {"op": "present", "path": ["sbom_release"]}}},
	"pinned SBOM package": {"of": "SBOM package", "applies_to": {"pinned": {"op": "present", "path": ["lock_release"]}}},
	"locked SBOM package": {"of": "pinned SBOM package", "applies_to": {"not_exempt": {"op": "equals", "path": ["exempt"], "value": false}}},
}

test_a_subject_can_build_on_a_chain_of_subjects if {
	rep := ergo.report(sbom_doc, subject_policy(deep_subjects, {"v": sbom_reqs.versions}), {})
	written_out := {"locked SBOM package": {"from": ["components"], "id": ["name"], "applies_to": {
		"has_sbom": {"op": "present", "path": ["sbom_release"]},
		"pinned": {"op": "present", "path": ["lock_release"]},
		"not_exempt": {"op": "equals", "path": ["exempt"], "value": false},
	}}}
	rep == ergo.report(sbom_doc, subject_policy(written_out, {"v": sbom_reqs.versions}), {})
	[[r.subject.id, r.passed] | some r in rep.results; r.check == "$applies"] == [["a", true], ["b", false], ["c", false]]
	rows_for(rep, "v", "$well_formed")[0].passed == true
}

test_a_subject_whose_chain_loops_fails_and_checks_nothing if {
	every loop in [
		{"locked SBOM package": {"of": "locked SBOM package"}},
		{"locked SBOM package": {"of": "SBOM package"}, "SBOM package": {"of": "locked SBOM package"}},
		{"locked SBOM package": {"of": "SBOM package"}, "SBOM package": {"of": "component"}, "component": {"of": "SBOM package"}},
	] {
		rep := ergo.report(sbom_doc, subject_policy(loop, {"v": sbom_reqs.versions}), {})
		well_formed_problems(rep, "v") == [{"name": "subjects.\"locked SBOM package\".of", "value": ["leads to a loop"]}]
		[[r.check, r.passed] | some r in rep.results; r.check != "$well_formed"] == [["$min_subjects", false], ["$unique_ids", true]]
	}
}

test_a_broken_link_anywhere_in_the_chain_fails_the_subject if {
	missing := object.remove(deep_subjects, ["component"])
	built_problems(missing) == [{"name": "subjects.\"SBOM package\".of", "value": ["not in subjects"]}]
	not_object := object.union(object.remove(deep_subjects, ["component"]), {"component": "components"})
	built_problems(not_object) == [{"name": "subjects.component", "value": ["not an object"]}]
	with_from := object.union(deep_subjects, {"pinned SBOM package": {"from": ["other"]}})
	built_problems(with_from) == [{"name": "subjects.\"pinned SBOM package\".from", "value": ["not allowed with of"]}]
	rep := ergo.report(sbom_doc, subject_policy(missing, {"v": sbom_reqs.versions}), {})
	[[r.check, r.passed] | some r in rep.results; r.check != "$well_formed"] == [["$min_subjects", false], ["$unique_ids", true]]
}

test_a_filter_name_used_anywhere_along_the_chain_fails if {
	clash := object.union(deep_subjects, {"locked SBOM package": {"applies_to": {"has_sbom": {"op": "present", "path": ["x"]}}}})
	built_problems(clash) == [{"name": "subjects.\"locked SBOM package\".applies_to.has_sbom", "value": ["also a filter of a subject it builds on"]}]
}

test_a_problem_in_a_filter_deep_in_the_chain_is_named_after_its_subject if {
	bad := object.union(deep_subjects, {"SBOM package": {"applies_to": {"has_sbom": {"op": "nope"}}}})
	built_problems(bad) == [{"name": "subjects.\"SBOM package\".applies_to.has_sbom", "value": ["unknown op nope"]}]
}

test_a_subject_built_on_another_takes_its_from_and_id_from_it if {
	own := object.union(sbom_subjects, {"locked SBOM package": object.union(sbom_subjects["locked SBOM package"], {"from": ["other"], "id": ["x"]})})
	built_problems(own) == [
		{"name": "subjects.\"locked SBOM package\".from", "value": ["not allowed with of"]},
		{"name": "subjects.\"locked SBOM package\".id", "value": ["not allowed with of"]},
	]
}

test_a_filter_name_used_by_both_subjects_fails_instead_of_one_replacing_the_other if {
	base := object.union(sbom_subjects["SBOM package"], {"applies_to": {"locked": {"op": "present", "path": ["sbom_release"]}}})
	built_problems(object.union(sbom_subjects, {"SBOM package": base})) == [{"name": "subjects.\"locked SBOM package\".applies_to.locked", "value": ["also a filter of a subject it builds on"]}]
}

test_an_of_that_is_not_a_name_fails if {
	every of in ["", " ", 1, null, ["SBOM package"]] {
		built := object.union(sbom_subjects, {"locked SBOM package": object.union(sbom_subjects["locked SBOM package"], {"of": of})})
		built_problems(built) == [{"name": "subjects.\"locked SBOM package\".of", "value": ["empty or not a string"]}]
	}
}

test_problems_with_the_subject_built_on_are_named_after_it if {
	base := {"from": 5, "applies_to": {"bad": {"op": "nope", "path": ["x"]}}}
	built_problems(object.union(sbom_subjects, {"SBOM package": base})) == [
		{"name": "subjects.\"SBOM package\".from", "value": ["not a list or a string"]},
		{"name": "subjects.\"SBOM package\".applies_to.bad", "value": ["unknown op nope"]},
	]
	stepped := object.union(sbom_subjects, {"SBOM package": {"from": ["components", {"each_as": "$p"}]}})
	built_problems(stepped) == [{"name": "subjects.\"SBOM package\".from", "value": ["invalid name"]}]
}

test_a_well_formed_row_names_the_from_after_the_subject_it_comes_from if {
	stepped := object.union(sbom_subjects, {"SBOM package": {"from": ["components", {"each_as": "p"}], "id": ["name"]}})
	row := rows_for(ergo.report(sbom_doc, subject_policy(stepped, {"v": sbom_reqs.versions}), {}), "v", "$well_formed")[0]
	row.passed == true
	row.inputs[2] == {"name": "subjects.\"SBOM package\".from", "value": ["components", {"each_as": "p"}]}
}

test_filters_that_are_not_an_object_on_either_subject_rule_no_one_out if {
	every pair in [[[], {"locked": {"op": "present", "path": ["lock_release"]}}], [{}, null]] {
		[base_filters, own_filters] := pair
		subjects := {
			"SBOM package": {"from": ["components"], "id": ["name"], "applies_to": base_filters},
			"locked SBOM package": {"of": "SBOM package", "applies_to": own_filters},
		}
		rep := ergo.report(sbom_doc, subject_policy(subjects, {"v": sbom_reqs.versions}), {})
		rep.requirements.v.status == "not_met"
		rep.requirements.v.checks["$applies"].expression == "<invalid applies_to>"
		{[r.check, r.cause] | some r in rep.results; r.subject.id != null} == {["$applies", "ill_formed"]}
	}
}

test_a_subject_no_requirement_names_does_not_change_how_numbers_are_written if {
	policy := subject_policy({"i": {"from": ["items"], "id": ["id"]}}, {"r": {"subject": "i", "checks": {"c": {"op": "equals", "path": ["n"], "value": 1.50}}}})
	with_unused := object.union(policy, {"subjects": {"unused": {"from": [{"where": {"k": {1}}}]}}})
	json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, with_unused, {})) == json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, policy, {}))
}

test_subject_keys_that_are_not_strings_get_a_name_each if {
	subjects := {"i": {"from": ["items"], "id": ["id"], true: 1, false: 2, 2: 3}}
	rep := ergo.report({"items": [{"id": 1}]}, subject_policy(subjects, {"r": {"subject": "i", "checks": {"c": {"op": "present", "path": ["id"]}}}}), {})
	well_formed_problems(rep, "r") == [
		{"name": "subjects.i.<invalid key false>", "value": ["unknown field"]},
		{"name": "subjects.i.<invalid key true>", "value": ["unknown field"]},
		{"name": "subjects.i.<invalid key 2>", "value": ["unknown field"]},
	]
}

two_checks_req := {"subject": "s", "require": "some", "checks": {
	"a": {"op": "present", "path": ["a"]},
	"b": {"op": "present", "path": ["b"]},
}}

passing_row := {"passed": true, "cause": "satisfied"}

evaluation_with(rows, matching, scope_readable) := {
	"well_formed": passing_row,
	"unique_ids": passing_row,
	"min_subjects": passing_row,
	"scope_readable": scope_readable,
	"rows_complete": ergo._rows_complete(rows, matching, two_checks_req),
	"subject_rows": rows,
	"matching": count(matching),
}

test_a_subject_missing_a_check_row_does_not_count_as_passing if {
	ergo._holds(two_checks_req, evaluation_with([[passing_row, passing_row]], [{"subject": {}}], true))
	not ergo._holds(two_checks_req, evaluation_with([[passing_row]], [{"subject": {}}], true))
}

test_a_subject_in_scope_without_rows_does_not_let_some_pass_on_nothing if {
	ergo._holds(two_checks_req, evaluation_with([], [], true))
	not ergo._holds(two_checks_req, evaluation_with([], [{"subject": {}}], true))
}

test_a_subject_without_an_applies_row_leaves_the_scope_unknown if {
	subjects := {"s": {"from": ["items"], "applies_to": {"f": {"op": "present", "path": ["a"]}}}}
	resolved := ergo._resolved_subjects with data.ergo_subjects as subjects
	ergo._scope_readable([{"subject": {}}, {"subject": {}}], [passing_row, passing_row], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
	not ergo._scope_readable([{"subject": {}}, {"subject": {}}], [passing_row], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
	not ergo._scope_readable([{"subject": {}}], [{"passed": false, "cause": "absent"}], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
}

causes_doc := {"deployments": [
	{"id": "d-1", "environment": "prod", "approved_by": "alice"},
	{"id": "d-2", "environment": "prod"},
	{"id": "d-3", "environment": "staging"},
	{"id": "d-4", "environment": "prod", "approved_by": ""},
	{"id": "d-5"},
]}

causes_policy(check) := {"subjects": {"deployment": {"from": ["deployments"], "id": ["id"], "applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}}}}, "requirements": {"r": {"subject": "deployment", "checks": {"approved": check}}}}

causes_of(deployments, check) := ergo.report({"deployments": deployments}, causes_policy(check), {}).requirements.r.causes

approved_check := {"op": "non_empty_string", "path": ["approved_by"]}

test_a_requirement_that_holds_has_no_causes if {
	met := ergo.report({"deployments": [causes_doc.deployments[0], causes_doc.deployments[2]]}, causes_policy(approved_check), {}).requirements.r
	[met.status, met.causes] == ["met", []]
	policy := causes_policy(approved_check)
	optional := object.union(policy, {"requirements": {"r": object.union(policy.requirements.r, {"min_subjects": 0})}})
	not_applicable := ergo.report({"deployments": [causes_doc.deployments[2]]}, optional, {}).requirements.r
	[not_applicable.status, not_applicable.causes] == ["not_applicable", []]
}

test_a_requirement_lists_the_causes_of_its_failing_rows_worst_first_with_how_many_rows_each if {
	causes_of(causes_doc.deployments, approved_check) == [
		{"cause": "absent", "rows": 2},
		{"cause": "value", "rows": 1},
	]
}

test_subjects_that_are_only_out_of_scope_are_not_causes if {
	causes_of([causes_doc.deployments[1], causes_doc.deployments[2]], approved_check) == [{"cause": "absent", "rows": 1}]
}

test_a_badly_written_check_puts_ill_formed_first if {
	causes_of(causes_doc.deployments, {"op": "non_empty_strng", "path": ["approved_by"]}) == [
		{"cause": "ill_formed", "rows": 3},
		{"cause": "absent", "rows": 1},
		{"cause": "value", "rows": 1},
	]
}

test_causes_count_the_rows_violations_returns if {
	rep := ergo.report(causes_doc, causes_policy(approved_check), {})
	vs := ergo.violations(rep)
	rep.requirements.r.causes == [{"cause": c, "rows": n} |
		some c in ["ill_formed", "not_an_object", "ambiguous", "unmatched", "unusable", "absent", "null", "value"]
		n := count([v | some v in vs; v.cause == c])
		n > 0
	]
	sum([e.rows | some e in rep.requirements.r.causes]) == count(vs)
}

derived_row(subj, check) := [r.passed, r.cause, r.inputs] if {
	r := rows_for(ergo.report({"items": [object.union({"id": 1}, subj)]}, lifted({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), {}), "s", "c")[0]
}

derived_verdict(subj, check) := array.slice(derived_row(subj, check), 0, 2)

derived_expression(check) := ergo.report({"items": []}, lifted({"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "checks": {"c": check}}}), {}).requirements.s.checks.c.expression

derived_problems(check) := [i | some i in rows_for(ergo.report({"items": [{"id": 1}]}, lifted({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), {}), "s", "$well_formed")[0].inputs; startswith(i.name, "checks.")]

at_least_one := {"op": "compare", "left": {"count": ["personas"]}, "right": {"literal": 1}, "cmp": "gte"}

test_count_compares_the_length_of_a_list_with_a_fixed_number if {
	derived_expression(at_least_one) == "count(personas) gte 1"
	derived_row({"personas": ["security"]}, at_least_one) == [true, "satisfied", [{"name": "count(personas)", "value": 1}, {"name": "personas", "value": ["security"]}]]
	derived_row({"personas": []}, at_least_one) == [false, "value", [{"name": "count(personas)", "value": 0}, {"name": "personas", "value": []}]]
}

test_count_fails_closed_on_a_list_it_cannot_read if {
	derived_row({}, at_least_one) == [false, "absent", [{"name": "count(personas)", "value": null}, {"name": "personas", "value": null}]]
	derived_row({"personas": null}, at_least_one) == [false, "null", [{"name": "count(personas)", "value": null}, {"name": "personas", "value": null}]]
	derived_verdict({"personas": "security"}, at_least_one) == [false, "unusable"]
	derived_verdict({"personas": {"a": 1}}, at_least_one) == [false, "unusable"]
}

test_count_compares_with_another_field if {
	check := {"op": "compare", "left": {"count": ["resolutions"]}, "right": ["found"], "cmp": "gte"}
	derived_expression(check) == "count(resolutions) gte found"
	derived_verdict({"resolutions": ["a", "b"], "found": 2}, check) == [true, "satisfied"]
	derived_verdict({"resolutions": ["a"], "found": 2}, check) == [false, "value"]
	derived_verdict({"resolutions": ["a"]}, check) == [false, "absent"]
}

claude_findings := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "equals", "path": ["source"], "value": "claude"}}, "right": {"add": [["a"], ["b"]]}, "cmp": "eq"}

test_count_where_only_counts_the_items_that_pass_the_condition if {
	derived_expression(claude_findings) == `count(raw where source == "claude") eq .a + b`
	subj := {"raw": [{"source": "claude"}, {"source": "gpt"}, {"source": "claude"}], "a": 1, "b": 1}
	derived_row(subj, claude_findings) == [true, "satisfied", [
		{"name": `count(raw where source == "claude")`, "value": 2},
		{"name": "raw", "value": subj.raw},
		{"name": ".a + b", "value": 2},
		{"name": ".a", "value": 1},
		{"name": "b", "value": 1},
	]]
}

test_count_where_fails_with_the_cause_of_an_item_it_cannot_decide if {
	r := derived_row({"raw": [{"source": "claude"}, {"origin": "x"}], "a": 1, "b": 0}, claude_findings)
	array.slice(r, 0, 2) == [false, "absent"]
	r[2][0] == {"name": `count(raw where source == "claude")`, "value": null}
}

stage_costs := {"op": "compare", "left": {"sum": ["stages"], "each": ["usd"], "where": {"op": "equals", "path": ["kind"], "value": "model"}}, "right": ["total"], "cmp": "eq", "within": 0.01}

test_sum_totals_a_field_across_the_items_that_pass_the_condition_within_a_tolerance if {
	derived_expression(stage_costs) == `sum(stages[].usd where kind == "model") eq total, within 0.01`
	stages := [{"kind": "model", "usd": 0.5}, {"kind": "model", "usd": 0.255}, {"kind": "tool", "usd": "n/a"}]
	derived_row({"stages": stages, "total": 0.75}, stage_costs) == [true, "satisfied", [
		{"name": `sum(stages[].usd where kind == "model")`, "value": 0.755},
		{"name": "stages[].usd", "value": [0.5, 0.255, "n/a"]},
		{"name": "total", "value": 0.75},
	]]
	derived_verdict({"stages": stages, "total": 0.7}, stage_costs) == [false, "value"]
}

test_sum_fails_closed_on_an_item_it_cannot_add if {
	derived_verdict({"stages": [{"kind": "model", "usd": "1"}], "total": 1}, stage_costs) == [false, "unusable"]
	derived_verdict({"stages": [{"kind": "model"}], "total": 1}, stage_costs) == [false, "absent"]
	derived_verdict({"stages": [{"kind": "model", "usd": null}], "total": 1}, stage_costs) == [false, "null"]
	derived_verdict({"stages": [{"usd": 1}], "total": 1}, stage_costs) == [false, "absent"]
}

test_within_needs_two_numbers if {
	check := {"op": "compare", "left": ["a"], "right": ["b"], "cmp": "eq", "within": 1}
	derived_verdict({"a": 1, "b": 1.5}, check) == [true, "satisfied"]
	derived_verdict({"a": 1, "b": 2.5}, check) == [false, "value"]
	derived_verdict({"a": "1", "b": "1"}, check) == [false, "unusable"]
}

test_add_needs_numbers if {
	check := {"op": "compare", "left": {"add": [{"count": ["records"]}, ["skipped"]]}, "right": ["found"], "cmp": "eq"}
	derived_expression(check) == "count(records) + skipped eq found"
	derived_verdict({"records": [1, 2], "skipped": 1, "found": 3}, check) == [true, "satisfied"]
	derived_verdict({"records": [1, 2], "skipped": "1", "found": 3}, check) == [false, "unusable"]
	derived_verdict({"records": [1, 2], "found": 3}, check) == [false, "absent"]
}

test_a_literal_side_works_inside_a_list_check_too if {
	check := {"op": "all", "path": ["xs"], "check": {"op": "compare", "left": ["n"], "right": {"literal": 2}, "cmp": "lte"}}
	derived_expression(check) == "every xs: n lte 2"
	derived_verdict({"xs": [{"n": 1}, {"n": 2}]}, check) == [true, "satisfied"]
	derived_verdict({"xs": [{"n": 3}]}, check) == [false, "value"]
}

test_a_side_written_wrong_is_ill_formed if {
	every case in [
		["personas", "invalid left"],
		[{"a": 1}, "invalid left"],
		[{"count": "personas"}, "invalid left"],
		[{"count": ["personas"], "zz": 1}, "invalid left"],
		[{"sum": ["stages"]}, "invalid left"],
		[{"add": []}, "invalid left"],
		[{"add": [{"literal": "1"}]}, "invalid left"],
		[{"add": [{"add": [["a"]]}]}, "invalid left"],
		[{"literal": 1, "zz": 2}, "invalid left"],
	] {
		[side, problem] := case
		check := {"op": "compare", "left": side, "right": ["n"], "cmp": "gte"}
		derived_verdict({"personas": [], "n": 1}, check) == [false, "ill_formed"]
		problem in derived_problems(check)[0].value
	}
}

test_within_is_written_wrong_unless_it_is_a_number_of_zero_or_more_on_eq if {
	every case in [["1", "eq", "invalid within"], [-1, "eq", "invalid within"], [1, "lt", "within needs cmp eq"]] {
		[within, cmp, problem] := case
		check := {"op": "compare", "left": ["a"], "right": ["b"], "cmp": cmp, "within": within}
		problem in derived_problems(check)[0].value
	}
	derived_problems({"op": "compare_time", "left": ["a"], "right": ["b"], "cmp": "eq", "within": 1})[0].value == ["unknown field within"]
}

test_a_derived_value_only_goes_in_a_check_of_its_own if {
	inner := {"op": "compare", "left": {"count": ["ys"]}, "right": {"literal": 1}, "cmp": "gte"}
	derived_problems({"op": "all", "path": ["xs"], "check": inner}) == [{"name": "checks.c.check", "value": ["count can't go here"]}]
	derived_problems({"op": "compare_time", "left": {"count": ["ys"]}, "right": ["t"], "cmp": "lt"}) == [{"name": "checks.c", "value": ["invalid left"]}]
}

test_a_where_condition_is_one_basic_check if {
	nested := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "any", "path": ["tags"], "check": {"op": "present", "path": []}}}, "right": {"literal": 1}, "cmp": "gte"}
	derived_problems(nested) == [{"name": "checks.c.left.where", "value": ["nested too deep"]}]
	typo := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "equls", "path": ["source"], "value": "x"}}, "right": {"literal": 1}, "cmp": "gte"}
	derived_problems(typo) == [{"name": "checks.c.left.where", "value": ["unknown op equls"]}]
}

test_add_takes_fixed_numbers if {
	check := {"op": "compare", "left": {"add": [{"count": ["records"]}, {"literal": 1}]}, "right": ["found"], "cmp": "eq"}
	derived_expression(check) == "count(records) + 1 eq found"
	derived_verdict({"records": [1, 2], "found": 3}, check) == [true, "satisfied"]
	derived_verdict({"records": [1, 2], "found": 9}, check) == [false, "value"]
}

test_a_where_condition_can_say_what_it_means if {
	check := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "equals", "path": ["source"], "value": "claude", "expression": "from Claude"}}, "right": {"literal": 1}, "cmp": "gte"}
	derived_expression(check) == "count(raw where from Claude) gte 1"
}

test_a_derived_check_with_a_bad_other_side_is_ill_formed_and_says_which if {
	invalid := {"op": "compare", "left": {"count": ["xs"]}, "right": "n", "cmp": "eq"}
	derived_expression(invalid) == "count(xs) eq <invalid right>"
	derived_verdict({"xs": [1], "n": 1}, invalid) == [false, "ill_formed"]
	missing := {"op": "compare", "left": {"count": ["xs"]}, "cmp": "eq"}
	derived_expression(missing) == "count(xs) eq <missing right>"
	derived_verdict({"xs": [1]}, missing) == [false, "ill_formed"]
}

test_a_derived_value_reads_the_input_and_the_params_like_any_path if {
	check := {"op": "compare", "left": {"count": ["$$params", "suites"]}, "right": {"count": ["$$input", "runs"]}, "cmp": "eq"}
	policy := lifted({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	r := rows_for(ergo.report({"runs": ["unit", "e2e"], "items": [{"id": 1}]}, policy, {"suites": ["unit", "e2e"]}), "s", "c")[0]
	[r.passed, r.cause] == [true, "satisfied"]
	ergo.report({"runs": ["unit", "e2e"], "items": [{"id": 1}]}, policy, {}).requirements.s.causes == [{"cause": "absent", "rows": 1}]
}

test_a_derived_check_can_have_a_substitute if {
	check := {"op": "compare", "left": {"count": ["approvals"]}, "right": {"literal": 2}, "cmp": "gte", "substitute": {"op": "equals", "path": ["emergency"], "value": true}}
	derived_verdict({"approvals": ["ann"], "emergency": true}, check) == [true, "substituted"]
	derived_verdict({"approvals": ["ann"]}, check) == [false, "value"]
}

test_a_derived_check_works_as_a_filter if {
	subjects := {"pr": {"from": ["prs"], "id": ["n"], "applies_to": {"big": {"op": "compare", "left": {"count": ["files"]}, "right": {"literal": 10}, "cmp": "gt"}}}}
	reqs := {"r": {"subject": "pr", "checks": {"reviewed": {"op": "present", "path": ["reviewer"]}}}}
	rep := ergo.report({"prs": [{"n": 1, "files": array.concat(numbers.range(1, 11), []), "reviewer": "ann"}, {"n": 2, "files": [1]}, {"n": 3}]}, subject_policy(subjects, reqs), {})
	[[r.subject.id, r.passed, r.cause] | some r in rep.results; r.check == "$applies"] == [[1, true, "satisfied"], [2, false, "value"], [3, false, "absent"]]
	rep.requirements.r.status == "not_met"
}

test_a_substitute_can_be_a_derived_check if {
	check := {"op": "compare", "left": {"count": ["approvals"]}, "right": {"literal": 2}, "cmp": "gte", "substitute": {"op": "compare", "left": {"count": ["backups"]}, "right": {"literal": 2}, "cmp": "gte"}}
	derived_verdict({"approvals": ["a"], "backups": ["x", "y"]}, check) == [true, "substituted"]
	derived_verdict({"approvals": ["a"], "backups": ["x"]}, check) == [false, "value"]
}

test_a_where_condition_has_no_substitute_because_it_would_change_what_is_counted if {
	check := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "present", "path": ["s"], "substitute": {"op": "present", "path": ["t"]}}}, "right": {"literal": 1}, "cmp": "gte"}
	derived_problems(check) == [{"name": "checks.c.left.where", "value": ["substitute can't go here"]}]
}

test_a_present_condition_leaves_out_items_whose_field_is_missing if {
	check := {"op": "compare", "left": {"count": ["raw"], "where": {"op": "present", "path": ["s"]}}, "right": {"literal": 1}, "cmp": "eq"}
	derived_row({"raw": [{"s": 1}, {}, {"s": null}]}, check) == [true, "satisfied", [{"name": "count(raw where s is present)", "value": 1}, {"name": "raw", "value": [{"s": 1}, {}, {"s": null}]}]]
}

test_a_derived_value_reads_a_name_given_by_from if {
	check := {"op": "compare", "left": {"count": ["$it", "xs"]}, "right": {"literal": 2}, "cmp": "eq"}
	policy := {"subjects": {"i": {"from": ["items", {"each_as": "it"}], "id": ["id"]}}, "requirements": {"r": {"subject": "i", "checks": {"c": check}}}}
	rep := ergo.report({"items": [{"id": 1, "xs": [1, 2]}]}, policy, {})
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check == "c"] == [["c", true, "satisfied"]]
	rep.requirements.r.checks.c.expression == "count($it.xs) eq 2"
	unknown := object.union(check, {"left": {"count": ["$other", "xs"]}})
	[[r.check, r.cause] | some r in ergo.report({"items": [{"id": 1, "xs": [1, 2]}]}, object.union(policy, {"requirements": {"r": {"subject": "i", "checks": {"c": unknown}}}}), {}).results; r.check == "c"] == [["c", "ill_formed"]]
}

one_check_policy(check) := lifted({"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})

test_a_ref_step_in_a_derived_value_reads_its_param_like_in_any_path if {
	counted := {"op": "compare", "left": {"count": ["groups", {"ref": ["$$params", "g"]}]}, "right": {"literal": 2}, "cmp": "eq"}
	added := {"op": "compare", "left": {"add": [["sizes", {"ref": ["$$params", "g"]}]]}, "right": {"literal": 2}, "cmp": "eq"}
	counted_in_add := {"op": "compare", "left": {"add": [{"count": ["groups", {"ref": ["$$params", "g"]}]}]}, "right": {"literal": 2}, "cmp": "eq"}
	doc := {"items": [{"id": 1, "groups": {"a": [1, 2]}, "sizes": {"a": 2}}]}
	every check in [counted, added, counted_in_add] {
		ok := ergo.report(doc, one_check_policy(check), {"g": "a"})
		[[r.passed, r.cause] | some r in rows_for(ok, "s", "c")] == [[true, "satisfied"]]
		ok.requirements.s.checks.c["$refs"] == [{"name": "$params.g", "value": "a"}]
		[r.cause | some r in rows_for(ergo.report(doc, one_check_policy(check), {}), "s", "c")] == ["absent"]
		[r.cause | some r in rows_for(ergo.report(doc, one_check_policy(check), {"g": ["a"]}), "s", "c")] == ["unusable"]
	}
}

test_a_custom_operators_own_count_field_is_not_read_as_a_derived_path if {
	check := {"op": "even", "path": ["n"], "count": ["xs", {"ref": ["$$params", "k"]}]}
	[r.cause | some r in rows_for(ergo.report({"items": [{"id": 1, "n": 3}]}, one_check_policy(check), {"k": ["a"]}), "s", "c")] == ["value"]
	[r.cause | some r in rows_for(ergo.report({"items": [{"id": 1, "n": 3}]}, one_check_policy(object.union(check, {"count": [{"literal": 1}]})), {"k": ["a"]}), "s", "c")] == ["value"]
}

test_a_built_in_check_takes_its_cause_from_what_it_reads_whatever_inputs_it_shows if {
	every check in [
		{"op": "equals", "path": ["a"], "value": 1, "inputs": [["b"]]},
		{"op": "compare", "left": {"count": ["a"]}, "right": {"literal": 1}, "cmp": "gte", "inputs": [["b"]]},
		{"op": "all", "path": ["a"], "check": {"op": "present", "path": ["x"]}, "inputs": [["b"]]},
	] {
		derived_row({"b": 1}, check) == [false, "absent", [{"name": "b", "value": 1}]]
	}
}

_read(text) := ergo._sentence(text)

_printed(text) := ergo._s_check_text(ergo._sentence(text))

test_a_sentence_reads_into_one_assertion_per_and if {
	_read(`environment is "prod" and every commits.verified is true`) == {"assertions": [
		{"path": {"steps": ["environment"]}, "phrase": {"op": "is", "value": "prod"}},
		{"every": {"steps": ["commits", "verified"]}, "phrase": {"op": "is", "value": true}},
	]}
}

test_every_corpus_line_parses_and_prints_back_unchanged if {
	every text in data.spec.sentence_corpus {
		_prints_back(text)
	}
	count(data.spec.sentence_corpus) == 307
}

_prints_back(text) if _printed(text) == text

_prints_back(text) if ergo._s_for_line_text(ergo._for_line(text)) == text

_prints_back(text) if ergo._s_from_line_text(ergo._from_line(text)) == text

test_a_whose_belongs_to_the_quantifier_and_an_and_after_the_phrase_starts_a_new_assertion if {
	_read(`every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"`) == {"assertions": [
		{
			"every": {"steps": ["items", "price"]},
			"where": [
				{"path": {"steps": ["kind"]}, "phrase": {"op": "is", "value": "a"}},
				{"path": {"steps": ["qty"]}, "phrase": {"op": "is", "value": 1}},
			],
			"phrase": {"op": "is at least", "value": 2},
		},
		{"path": {"steps": ["owner"]}, "phrase": {"op": "is", "value": "x"}},
	]}
}

test_the_and_of_between_is_not_the_and_between_assertions if {
	_read(`qty is between 1 and 5 and kind is "a"`).assertions[0].phrase == {"op": "is between", "min": 1, "max": 5}
	count(_read(`qty is between 1 and 5 and kind is "a"`).assertions) == 2
}

test_a_count_with_a_whose_keeps_the_whose_on_the_assertion_and_plus_inside_the_condition if {
	_read(`count of x whose n is m plus k is t`) == {"assertions": [{
		"terms": [{"count": {"steps": ["x"]}}],
		"where": [{"path": {"steps": ["n"]}, "phrase": {"op": "is", "terms": [{"steps": ["m"]}, {"steps": ["k"]}]}}],
		"phrase": {"op": "is", "terms": [{"steps": ["t"]}]},
	}]}
	_read(`k plus count of x whose n is m is t`).assertions[0].terms == [{"steps": ["k"]}, {"count": {"steps": ["x"]}}]
	_read(`sum of stages.usd equals total_usd within 0.01`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["total_usd"]}], "within": 0.01}
	_read(`x is 1 plus 2`).assertions[0].phrase == {"op": "is", "terms": [1, 2]}
}

test_a_path_reads_params_input_lookups_positions_and_quoted_keys if {
	_read(`$params.k."b c"[2].d is 1`).assertions[0].path == {"start": "params", "steps": ["k", "b c", {"index": 2}, "d"]}
	_read(`$params.k."b c"[2] is 1`).assertions[0].path == {"start": "params", "position": 3, "steps": ["k", "b c"]}
	_read(`item 3 of k."b c" is 1`).assertions[0].path == {"position": 3, "steps": ["k", "b c"]}
	_read(`item 3 of k[0] is 1`).assertions[0].path == {"position": 3, "steps": ["k", {"index": 0}]}
	_read(`$input.x named by persona.y is 1`).assertions[0].path == {"start": "input", "steps": ["x", {"named_by": {"steps": ["persona"]}}, "y"]}
	_read(`b[$params.k] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"start": "params", "steps": ["k"]}}]}
	_read(`b[$input."k"] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"start": "input", "steps": ["k"]}}]}
	_read(`b[persona] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"steps": ["persona"]}}]}
	_read(`b["k"] is 1`).assertions[0].path == {"steps": ["b", "k"]}
	_read(`item 3 of b.c is 1`).assertions[0].path == {"position": 3, "steps": ["b", "c"]}
	_read(`first of b is 1`).assertions[0].path == {"position": "first", "steps": ["b"]}
	_read(`last of b is 1`).assertions[0].path == {"position": "last", "steps": ["b"]}
	_read(`"$schema" is 1`).assertions[0].path == {"steps": ["$schema"]}
	_read(`.count is 1`).assertions[0].path == {"steps": ["count"]}
	_read(`"empty" is 1`).assertions[0].path == {"steps": ["empty"]}
	_read(`x is ."$schema"`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["$schema"]}]}
	_read(`.x is 1`) == _read(`x is 1`)
	_read(`x equals .total`) == _read(`x equals total`)
}

test_a_value_reads_as_json_and_a_single_quoted_string_keeps_its_backslashes if {
	_read(`x is "a\"b"`).assertions[0].phrase.value == `a"b`
	_read(`x is 'a\'b\\c\sd'`).assertions[0].phrase.value == `a'b\c\sd`
	_read(`x is 1e2`).assertions[0].phrase.value == 100
	_read(`x is null`).assertions[0].phrase == {"op": "is", "value": null}
	_read(`x is one of "a", 1, false`).assertions[0].phrase == {"op": "is one of", "values": ["a", 1, false]}
	_read(`x is false-positive`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["false-positive"]}]}
	_read(`x is true-ish and y is null-x`).assertions[1].phrase == {"op": "is", "terms": [{"steps": ["null-x"]}]}
	_read(`x is empty-thing`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["empty-thing"]}]}
	_read(`x is not empty-ish`).assertions[0].phrase == {"op": "is not", "terms": [{"steps": ["empty-ish"]}]}
	_read(`x is a listing`) == {"problems": ["doesn't parse"]}
	_read(`x is -0.5`).assertions[0].phrase == {"op": "is", "value": -0.5}
}

test_each_phrase_reads_into_its_op if {
	_read(`x is not one of "a", "b"`).assertions[0].phrase == {"op": "is not one of", "values": ["a", "b"]}
	_read(`x is not in $params.k`).assertions[0].phrase == {"op": "is not one of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x is in $params.k`).assertions[0].phrase == {"op": "is one of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x is a non-empty string`).assertions[0].phrase == {"op": "is a non-empty string"}
	_read(`x is an object`).assertions[0].phrase == {"op": "is a", "type": "object"}
	_read(`x is a list`).assertions[0].phrase == {"op": "is a", "type": "list"}
	_read(`x is empty`).assertions[0].phrase == {"op": "is empty"}
	_read(`x is not empty`).assertions[0].phrase == {"op": "is not empty"}
	_read(`x exists`).assertions[0].phrase == {"op": "exists"}
	_read(`x does not exist`).assertions[0].phrase == {"op": "does not exist"}
	_read(`x contains all of "a", "b"`).assertions[0].phrase == {"op": "contains all of", "values": ["a", "b"]}
	_read(`x contains none of $params.k`).assertions[0].phrase == {"op": "contains none of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x contains "a"`).assertions[0].phrase == {"op": "contains", "value": "a"}
	_read(`x does not contain y`).assertions[0].phrase == {"op": "does not contain", "terms": [{"steps": ["y"]}]}
	_read(`x matches "^a"`).assertions[0].phrase == {"op": "matches", "values": ["^a"]}
	_read(`x does not match $params.p`).assertions[0].phrase == {"op": "does not match", "path": {"start": "params", "steps": ["p"]}}
	_read(`x starts with "a"`).assertions[0].phrase == {"op": "starts with", "value": "a"}
	_read(`x ends with "a"`).assertions[0].phrase == {"op": "ends with", "value": "a"}
	_read(`x is at least 1`).assertions[0].phrase == {"op": "is at least", "value": 1}
	_read(`x is at most 1`).assertions[0].phrase == {"op": "is at most", "value": 1}
	_read(`x is more than 1`).assertions[0].phrase == {"op": "is more than", "value": 1}
	_read(`x is less than 1`).assertions[0].phrase == {"op": "is less than", "value": 1}
	_read(`x is on or after y`).assertions[0].phrase == {"op": "is on or after", "terms": [{"steps": ["y"]}]}
	_read(`x is on or before y`).assertions[0].phrase == {"op": "is on or before", "terms": [{"steps": ["y"]}]}
	_read(`x is before y`).assertions[0].phrase == {"op": "is before", "terms": [{"steps": ["y"]}]}
	_read(`x is after y`).assertions[0].phrase == {"op": "is after", "terms": [{"steps": ["y"]}]}
	_read(`x is 1 within 0.5`).assertions[0].phrase == {"op": "is", "value": 1, "within": 0.5}
	_read(`x is not 1`).assertions[0].phrase == {"op": "is not", "value": 1}
	_read(`x does not equal y`).assertions[0].phrase == {"op": "is not", "terms": [{"steps": ["y"]}]}
	_read(`x is equal to y`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["y"]}]}
	_read(`x equals y`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["y"]}]}
}

test_the_report_prints_one_spelling_for_each_phrase if {
	_printed(`x is equal to y`) == "x equals y"
	_printed(`x is y`) == "x equals y"
	_printed(`x equals "y"`) == `x is "y"`
	_printed(`x is not y`) == "x does not equal y"
	_printed(`x does not equal "y"`) == `x is not "y"`
	_printed(`x is one of $params.k`) == "x is in $params.k"
	_printed(`x is in "a", "b"`) == `x is one of "a", "b"`
	_printed(`x is not one of $params.k`) == "x is not in $params.k"
	_printed(`x is not in "a"`) == `x is not one of "a"`
	_printed(`x is a object`) == "x is an object"
	_printed(`x is an list`) == "x is a list"
	_printed(`x is 1e2 within 1.50`) == "x is 100 within 1.5"
	_printed(`x equals y within 1`) == "x equals y within 1"
	_printed(`  x  is one of  "a",   "b" `) == `x is one of "a", "b"`
	_printed(`x is '^\s'`) == `x is '^\s'`
	_printed(`x is "^\\s"`) == `x is '^\s'`
	_printed(`x is "a\\\\b"`) == `x is "a\\\\b"`
	_printed(`x is "a\\"`) == `x is "a\\"`
	_printed(`x is "a\\\tb"`) == `x is "a\\\tb"`
	_printed(`x is '^\s'`) == _printed(_printed(`x is '^\s'`))
	_printed(`x is 'it\'s'`) == `x is "it's"`
	_printed(`x is "<"`) == `x is "<"`
	_printed(`b[$params.k] is 1`) == "b named by $params.k is 1"
	_printed(`b[persona][2].c is 1`) == "b named by persona[2].c is 1"
	_printed(`b[persona][2] is 1`) == "item 3 of b named by persona is 1"
	_printed(`commits[0] is "x"`) == `item 1 of commits is "x"`
	_printed(`.x is 1`) == "x is 1"
	_printed(`b["k"] is 1`) == "b.k is 1"
	_printed(`b."c d" is 1`) == `b."c d" is 1`
	_printed(`"$schema" is 1`) == `"$schema" is 1`
	_printed(`x is ."$schema"`) == `x equals ."$schema"`
	_printed(`.count is .sum`) == ".count equals .sum"
	_printed(`"count" is 1`) == ".count is 1"
	_printed(`item 3 of b is 1 and first of c is 2 and last of d is 3`) == "item 3 of b is 1 and first of c is 2 and last of d is 3"
	_printed(`every x whose n is 1, if any, is 2`) == "every x whose n is 1, if any, is 2"
	_printed(`some x whose count of y is 1 is 2`) == "some x whose count of y is 1 is 2"
	_printed(`count of x whose n is 1 is 2`) == "count of x whose n is 1 is 2"
	_printed(`sum of x.n plus 1 plus count of y is 2`) == "sum of x.n plus 1 plus count of y is 2"
	_printed(`count of x[0] is 1 and y equals sum of z[1].n`) == "count of item 1 of x is 1 and y equals sum of z[1].n"
	_read(_printed(`count of x[0] is 1`)) == _read(`count of x[0] is 1`)
}

test_a_for_line_reads_its_items if {
	ergo._for_line(`every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver`) == {"items": [
		{"every": {"steps": ["pull_requests"]}, "as": "pr"},
		{"some": {"steps": ["pr", "approvers"]}, "where": [{"path": {"steps": ["state"]}, "phrase": {"op": "is", "value": "APPROVED"}}], "as": "approver"},
	]}
	ergo._for_line(`every commits, if any, as commit`) == {"items": [{"every": {"steps": ["commits"]}, "if_any": true, "as": "commit"}]}
	ergo._s_for_line_text(ergo._for_line(`every commits, if any, as commit`)) == "every commits, if any, as commit"
}

test_a_from_line_reads_its_path_keys_and_whose if {
	ergo._from_line(`artifact.attestations named by each of $params.names whose status is "COMPLETE"`) == {
		"path": {"steps": ["artifact", "attestations"]},
		"named_by_each_of": {"start": "params", "steps": ["names"]},
		"where": [{"path": {"steps": ["status"]}, "phrase": {"op": "is", "value": "COMPLETE"}}],
	}
	ergo._from_line(`trail`) == {"path": {"steps": ["trail"]}}
	ergo._s_from_line_text(ergo._from_line(`artifact.attestations named by each of $params.names whose status is "COMPLETE"`)) == `artifact.attestations named by each of $params.names whose status is "COMPLETE"`
}

test_a_number_out_of_range_is_written_wrong_without_opa_comparing_it if {
	_read(`x is between -6 and -80e-08923553`) == {"problems": ["number out of range: -80e-08923553"]}
	_read(`x is between 1 and 1e400`) == {"problems": ["number out of range: 1e400"]}
	_read(`x is between 1e400 and 1`) == {"problems": ["number out of range: 1e400"]}
	_read(`x matches 1e400`) == {"problems": ["number out of range: 1e400"]}
	_read(`x is at least 1e400`) == {"problems": ["number out of range: 1e400"]}
	_read(`x is 2.2e-308`) == {"problems": ["number out of range: 2.2e-308"]}
	_read(`x is one of 1, 2e400`) == {"problems": ["number out of range: 2e400"]}
	_read(`x is 1 within 1e999`) == {"problems": ["number out of range: 1e999"]}
	_read(`count of y plus 1e-9999999 is 3`) == {"problems": ["number out of range: 1e-9999999"]}
	_read(`x is 1.7976931348623157e308`).assertions[0].phrase.value == 1.7976931348623157e308
	_read(`x is 2.2250738585072014e-308`).assertions[0].phrase.value == 2.2250738585072014e-308
	_read(`x is 0.0e-9999999`).assertions[0].phrase.value == 0
}

test_a_sentence_written_wrong_says_what_is_wrong if {
	_read(`x is "a`) == {"problems": ["unclosed quote at column 6"]}
	_read(`x is 'a' and y is 'b`) == {"problems": ["unclosed quote at column 19"]}
	_read(`x is "\q"`) == {"problems": ["invalid string at column 6"]}
	_read(`x is "a	b"`) == {"problems": ["invalid string at column 6"]}
	_read(`x is 'a	b'`) == {"problems": ["invalid string at column 6"]}
	_read(`"\q" is 1`) == {"problems": ["invalid string at column 1"]}
	_read(`x is "\q" and y is "\q"`) == {"problems": ["invalid string at column 6", "invalid string at column 20"]}
	_read(`x is 'a"\q"b' and y is "\q"`) == {"problems": ["invalid string at column 24"]}
	_read(`x is "cost $usd" and`) == {"problems": ["doesn't parse"]}
	_read(`$foo is $bar and $foo exists`) == {"problems": ["unknown name $bar", "unknown name $foo"]}
	_read(`some x, if any, is 1`) == {"problems": ["if any can't go with some"]}
	_read(`every x some y is 1`) == {"problems": ["two quantifiers in one sentence: put them on a for line"]}
	_read(`count is 1`) == {"problems": ["count is a word of the grammar: write .count"]}
	_read(`x is empty_`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "terms": [{"steps": ["empty_"]}]}}]}
	_read(`a plus b whose c is 1 is 2`) == {"problems": ["a is a word of the grammar: write .a", "a whose goes after every, some, count of or sum of"]}
	_read(`x whose k is 1 is 2`) == {"problems": ["a whose goes after every, some, count of or sum of"]}
	_read(`count of approvers is empty`) == {"problems": ["is empty can't follow a count of, a sum of or a plus"]}
	_read(`x plus y matches "a"`) == {"problems": ["matches can't follow a count of, a sum of or a plus"]}
	_read(`5 is 5`) == {"problems": ["a number can't start a sentence"]}
	_read(`1 plus x is 5`).assertions[0].terms == [1, {"steps": ["x"]}]
	_read(`x named by every is 1`) == {"problems": ["every can't be a name"]}
	_read(`x[params] is 1`) == {"problems": ["params can't be a name"]}
	_read(`commits[01] is "x"`) == {"problems": ["doesn't parse"]}
	_read(`$foo is 1`) == {"problems": ["unknown name $foo"]}
	_read(`x is $params`).assertions[0].phrase.terms == [{"start": "params", "steps": []}]
	_read(`every commits.signed`) == {"problems": [`nothing after the path at column 21: expected a phrase, like "is" or "exists"`]}
	_read(`sum of stages.usd equals total within`) == {"problems": [`"within" needs a number after it`]}
	_read(`every  pull_requests  some approvers.state is "APPROVED"`) == {"problems": ["two quantifiers in one sentence: put them on a for line"]}
	_read(`x is equal to 1 within 2`).assertions[0].phrase == {"op": "is", "value": 1, "within": 2}
	_read(`x is 1 within -1`) == {"problems": [`"within" needs a number of 0 or more`]}
	_read(`x equals y within -0.5`) == {"problems": [`"within" needs a number of 0 or more`]}
	_read(`x is 1 within -0`).assertions[0].phrase.within == 0
	_read(`x is one of "a",	"b"`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`every xs as x, every ys as x`) == {"problems": ["x is given twice"]}
	ergo._from_line(`xs[01]`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`xs whose k is 1`) == {"path": {"steps": ["xs"]}, "where": [{"path": {"steps": ["k"]}, "phrase": {"op": "is", "value": 1}}]}
	_read(`x is between 5 and 1`) == {"problems": ["min above max"]}
	_read(`x matches "("`) == {"problems": [`invalid pattern "("`]}
	_read(`x is`) == {"problems": ["doesn't parse"]}
	_read(``) == {"problems": ["doesn't parse"]}
	_read(`x is 1 and`) == {"problems": ["doesn't parse"]}
	_read(`every x whose a is 1`) == {"problems": ["doesn't parse"]}
	_read(`x is count of y whose a is 1`) == {"problems": ["doesn't parse"]}
	_read(`item 0 of x is 1`) == {"problems": ["doesn't parse"]}
	_read(`foo$bar is 1`) == {"problems": ["doesn't parse"]}
	_read(`x is "$schema"`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "value": "$schema"}}]}
	ergo._for_line(`every x as every`) == {"problems": ["every can't be a name"]}
	ergo._for_line(`every x as params`) == {"problems": ["params can't be a name"]}
	ergo._for_line(`every x as a, every y as b, every z as c`) == {"problems": ["a for line holds two items at most"]}
	ergo._for_line(`some x, if any, as y`) == {"problems": ["if any can't go with some"]}
	ergo._from_line(`count whose x is 1`) == {"problems": ["count is a word of the grammar: write .count"]}
	ergo._from_line(`x is 1`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`$input named by each of "T"`) == {"problems": ["doesn't parse"]}
}

_sentence_policy(checks) := {
	"subjects": {"thing": {"from": ["things"], "id": ["id"]}},
	"requirements": {"s": {"subject": "thing", "checks": checks}},
}

_sentence_rows(checks, doc, params) := [[r.check, r.passed, r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

_sentence_problems(check) := [i.value | some i in ergo.report({"things": []}, _sentence_policy({"c": check}), {}).results[0].inputs; i.name == "checks.c"][0]

test_a_sentence_gives_the_rows_of_the_check_it_reads_into if {
	doc := {"things": [
		{"id": "t1", "x": "a", "n": 3, "m": 3, "l": ["a", "b"], "t": "2024-01-01T00:00:00Z", "u": "2024-02-01T00:00:00Z", "k": {"a": 1}, "q": null},
		{"id": "t2", "x": 5, "n": "3", "l": "a", "t": 1, "k": {"b": 2}},
		{"id": "t3"},
	]}
	params := {"allowed": ["a"], "key": "a", "pats": ["^a"], "groups": [["a"], {"names": [5]}]}
	every pair in [
		[`x is "a"`, {"op": "equals", "path": ["x"], "value": "a"}],
		[`q is null`, {"op": "equals", "path": ["q"], "value": null}],
		[`n equals m`, {"op": "compare", "left": ["n"], "cmp": "eq", "right": ["m"]}],
		[`n is 3.05 within 0.1`, {"op": "compare", "left": ["n"], "cmp": "eq", "right": {"literal": 3.05}, "within": 0.1}],
		[`n equals m within 0`, {"op": "compare", "left": ["n"], "cmp": "eq", "right": ["m"], "within": 0}],
		[`x is not "a"`, {"op": "compare", "left": ["x"], "cmp": "ne", "right": {"literal": "a"}}],
		[`n does not equal m`, {"op": "compare", "left": ["n"], "cmp": "ne", "right": ["m"]}],
		[`x is one of "a", 5`, {"op": "in", "path": ["x"], "values": ["a", 5]}],
		[`x is in $params.allowed`, {"op": "in", "path": ["x"], "values": {"ref": ["$$params", "allowed"]}}],
		[`x is in $params.groups[0].names`, {"op": "in", "path": ["x"], "values": {"ref": ["$$params", "groups", 0, "names"]}}],
		[`x is in first of $params.groups`, {"op": "in", "path": ["x"], "values": {"ref": ["$$params", "groups", 0]}}],
		[`x exists`, {"op": "present", "path": ["x"]}],
		[`x does not exist`, {"op": "missing", "path": ["x"]}],
		[`x is a non-empty string`, {"op": "non_empty_string", "path": ["x"]}],
		[`l contains "a"`, {"op": "includes", "path": ["l"], "value": "a"}],
		[`l contains $params.key`, {"op": "includes", "path": ["l"], "value": {"ref": ["$$params", "key"]}}],
		[`l does not contain "b"`, {"op": "excludes", "path": ["l"], "value": "b"}],
		[`l contains all of "a", "b"`, {"op": "includes", "path": ["l"], "values": ["a", "b"]}],
		[`l contains none of $params.allowed`, {"op": "excludes", "path": ["l"], "values": {"ref": ["$$params", "allowed"]}}],
		[`x matches '^\w$'`, {"op": "matches_any", "path": ["x"], "patterns": ["^\\w$"]}],
		[`x does not match $params.pats`, {"op": "not_matches_any", "path": ["x"], "patterns": {"ref": ["$$params", "pats"]}}],
		[`n is at least 3`, {"op": "compare", "left": ["n"], "cmp": "gte", "right": {"literal": 3}}],
		[`n is at most m`, {"op": "compare", "left": ["n"], "cmp": "lte", "right": ["m"]}],
		[`n is more than 2`, {"op": "compare", "left": ["n"], "cmp": "gt", "right": {"literal": 2}}],
		[`n is less than 2`, {"op": "compare", "left": ["n"], "cmp": "lt", "right": {"literal": 2}}],
		[`n is between 1 and 3`, {"op": "range", "path": ["n"], "min": 1, "max": 3}],
		[`t is before u`, {"op": "compare_time", "left": ["t"], "cmp": "lt", "right": ["u"]}],
		[`t is after u`, {"op": "compare_time", "left": ["t"], "cmp": "gt", "right": ["u"]}],
		[`t is on or after u`, {"op": "compare_time", "left": ["t"], "cmp": "gte", "right": ["u"]}],
		[`t is on or before u`, {"op": "compare_time", "left": ["t"], "cmp": "lte", "right": ["u"]}],
		[`k named by $params.key is 1`, {"op": "equals", "path": ["k", {"ref": ["$$params", "key"]}], "value": 1}],
		[`k[$params.key] is 1`, {"op": "equals", "path": ["k", {"ref": ["$$params", "key"]}], "value": 1}],
		[`item 2 of l is "b"`, {"op": "equals", "path": ["l", 1], "value": "b"}],
		[`first of l is "a"`, {"op": "equals", "path": ["l", 0], "value": "a"}],
		[`l[1] is "b"`, {"op": "equals", "path": ["l", 1], "value": "b"}],
		[`$params.key is "a"`, {"op": "equals", "path": ["$$params", "key"], "value": "a"}],
		[`$input.things[0].id is "t1"`, {"op": "equals", "path": ["$$input", "things", 0, "id"], "value": "t1"}],
		[`"$schema" exists`, {"op": "present", "path": [{"literal": "$schema"}]}],
		[`k."a" is 1`, {"op": "equals", "path": ["k", "a"], "value": 1}],
	] {
		_sentence_rows({"c": pair[0]}, doc, params) == _sentence_rows({"c": pair[1]}, doc, params)
	}
}

test_a_sentence_check_reports_its_description_meta_and_printed_sentence_only if {
	r := ergo.report(
		{"things": [{"id": "t1", "x": "a"}]}, _sentence_policy({
			"a": `x  is equal to 'a'`,
			"b": {"description": "In the list", "meta": {"id": "B-1"}, "assert": "x is in $params.allowed"},
		}),
		{"allowed": ["a"]},
	)
	r.requirements.s.checks.a == {"description": "", "meta": {}, "expression": `x is "a"`}
	r.requirements.s.checks.b == {"description": "In the list", "meta": {"id": "B-1"}, "expression": "x is in $params.allowed", "$refs": [{"name": "$params.allowed", "value": ["a"]}]}
	r.compliant
}

test_a_sentence_written_wrong_fails_its_rows_and_lists_its_problems if {
	r := ergo.report({"things": [{"id": "t1", "x": "a"}]}, _sentence_policy({"c": `x is "a`}), {})
	[[row.check, row.passed, row.cause, row.inputs] | some row in r.results; row.check in {"$well_formed", "c"}] == [
		["$well_formed", false, "value", [{"name": "count(checks)", "value": 1}, {"name": "require", "value": "every"}, {"name": "checks.c", "value": ["unclosed quote at column 6"]}]],
		["c", false, "ill_formed", []],
	]
	r.requirements.s.checks.c.expression == `x is "a`
}

test_an_assert_object_takes_only_description_and_meta if {
	_sentence_problems({"assert": 1}) == ["invalid assert"]
	_sentence_problems({"assert": 1, "description": 2}) == ["invalid assert", "invalid description"]
	_sentence_problems({"assert": "x exists", "meta": []}) == ["invalid meta"]
	ergo.report({"things": []}, _sentence_policy({"c": {"assert": 1}}), {}).requirements.s.checks.c.expression == "<invalid assert>"
}

test_forms_ergo_does_not_run_yet_are_written_wrong_as_not_supported_yet if {
	every pair in [
		[`count of xs is between 1 and 3`, `"is between" after a count of, a sum of or a plus isn't supported yet`],
		[`every xs is y plus 1`, "count of, sum of and plus after every or some aren't supported yet"],
		[`t is before y plus 1`, `"is before" can't take a count of, a sum of or a plus`],
		[`count of xs whose count of ys is 1 is 2`, "a count of, a sum of or a plus in the whose of a count of or a sum of isn't supported yet"],
		[`t is before "2024-01-01T00:00:00Z"`, `"is before" with a value isn't supported yet: compare with a field`],
		[`x is in allowed`, `"is in" with a field of the subject isn't supported yet`],
		[`l contains y`, `"contains" with a field of the subject isn't supported yet`],
		[`x matches $params.a named by $params.b`, `"matches" with named by in its path isn't supported yet`],
		[`last of xs is 1`, "last of isn't supported yet"],
		[`x named by persona is 1`, "unknown name persona"],
	] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
	_sentence_problems({"assert": []}) == ["empty assert"]
	_sentence_problems({"assert": ["x exists", 1]}) == ["invalid assert"]
	_sentence_problems({"assert": ["x exists", "y is \"a"]}) == ["line 2: unclosed quote at column 6"]
	_sentence_problems({"assert": ["x exists", "count of ys is between 1 and 2"]}) == [concat("", ["line 2: ", `"is between" after a count of, a sum of or a plus isn't supported yet`])]
}

test_a_check_written_as_a_string_is_read_as_a_sentence if {
	rendered({}, "present") == "present"
	[[r.passed, r.cause] | some r in solo({}, "present").results; r.check == "c"] == [[false, "ill_formed"]]
	_sentence_problems("present") == [`nothing after the path at column 8: expected a phrase, like "is" or "exists"`]
}

test_is_not_null_is_written_wrong_because_it_could_only_fail if {
	_sentence_problems(`x is not null`) == [`"is not null" is written "exists"`]
	_sentence_problems(`x does not equal null`) == [`"is not null" is written "exists"`]
}

test_requirements_and_checks_that_are_not_objects_are_left_to_the_other_rules if {
	ergo._s_requirements(null, {}) == null
	ergo._s_requirements({"r": 1}, {}) == {"r": 1}
	ergo._s_requirements({"r": {"checks": []}}, {}) == {"r": {"checks": []}}
	ergo._s_requirements({"r": {"checks": {"c": {"op": "present", "path": ["x"]}, "d": 1}}}, {}) == {"r": {"checks": {"c": {"op": "present", "path": ["x"]}, "d": 1}}}
}

test_a_number_just_past_the_largest_float_is_written_wrong_before_opa_reads_it if {
	every text in [`x is 1e309`, `x is 1.8e308`, `x is -1.7976931348623158e308`, `x is 0.00018e312`, `x is at least 1e350`, `x is between 1 and 2e308`, `x is 1 within 1e350`, `x is one of 1, 1e350`, `x contains 1e350`] {
		count(_sentence_problems(text)) == 1
		startswith(_sentence_problems(text)[0], "number out of range: ")
	}
	every text in [`x is 1.7976931348623157e308`, `x is 17976931348623157e292`, `x is 179769313486231570000e288`, `x is 1e308`] {
		ergo.report({"things": [{"id": "t1", "x": 1}]}, _sentence_policy({"c": text}), {}).results[0].passed
	}
}

test_a_sentence_marker_written_by_hand_is_an_unknown_field_like_any_other if {
	every check in [
		{"op": "present", "path": ["x"], "$sentence": [], "valeu": 1},
		{"op": "present", "path": ["x"], "$sentence": "bad", "valeu": 1},
		{"op": "present", "path": ["x"], "$sentence": null, "valeu": 1},
	] {
		_sentence_problems(check) == ["unknown field $sentence", "unknown field valeu"]
		[[r.passed, r.cause] | some r in ergo.report({"things": [{"id": "t1", "x": 1}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [[false, "ill_formed"]]
	}
	ergo.report({"things": []}, _sentence_policy({"c": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [], "$sentence": []}}}), {}).results[0].inputs[2] == {"name": "checks.c.check", "value": ["unknown field $sentence"]}
	ergo.report({"things": []}, _sentence_policy({"c": {"op": "present", "path": ["x"], "substitute": {"op": "present", "path": ["y"], "$sentence": []}}}), {}).results[0].inputs[2] == {"name": "checks.c.substitute", "value": ["unknown field $sentence"]}
	ergo.report({"things": []}, _sentence_policy({"c": {"op": "present", "path": ["x"], "$sentence": []}}), {}).requirements.s.checks.c == {"description": "", "meta": {}, "op": "present", "path": ["x"], "$sentence": [], "expression": "x is present"}
}

test_a_check_is_read_as_a_sentence_only_where_the_policy_wrote_one if {
	not ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"})
	ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"}) with data.ergo_sentence_here as true
	ergo._s_sentences({"r": {"checks": ["x exists"]}, "q": 1}, {"r": {"checks": ["x exists"]}, "q": 1}) == set()
	ergo._s_sentences(null, null) == set()
	ergo._s_written_here({}, "applies_to", "f") == false
}

test_a_sentence_that_reads_into_no_check_is_written_wrong_rather_than_run if {
	ergo._s_or_unrunnable(set()) == {"can't be run"}
	ergo._s_or_unrunnable({"x"}) == {"x"}
}

test_an_object_with_assert_and_op_is_a_check_in_the_old_syntax_so_a_custom_operator_can_take_assert if {
	ergo._s_written_check({"op": "my_op", "assert": "x"}) == {"op": "my_op", "assert": "x"}
	_sentence_problems({"op": "present", "path": ["x"], "assert": "x"}) == ["unknown field assert"]
}

test_within_only_compares_numbers_so_another_value_before_it_is_written_wrong if {
	every text in [`x is null within 1`, `x is "a" within 1`, `x is true within 0`] {
		_sentence_problems(text) == [`"within" only compares numbers`]
	}
}

test_the_smallest_number_is_checked_by_its_digits_so_opa_rounding_it_up_doesnt_let_it_in if {
	every text in [`x is 2.2250738585072013999999999e-308`, `x is 22250738585072013e-324`, `x is 1e-308`, `x is -1e-400`] {
		startswith(_sentence_problems(text)[0], "number out of range: ")
	}
	every text in [`x is 2.2250738585072014e-308`, `x is 0.0`, `x is 0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000`] {
		count(ergo._sentence(text).assertions) == 1
	}
}

test_a_name_from_the_report_reads_back_in_a_sentence_as_the_path_it_names if {
	every path in [
		["x", "$b"],
		["empty", "x"],
		["a"],
		["xs", 1, "k"],
		["xs", 1],
		["$$params", "allowed"],
		["$$input", "repo", "name"],
		["k", {"ref": ["$$params", "n"]}, "ok"],
		[{"literal": "$schema"}, "x"],
		["metadata", "labels", "app.kubernetes.io/name"],
		["count", "first", "is"],
	] {
		parsed := ergo._sentence(concat(" ", [ergo._path_name(path), "exists"]))
		ergo._s_model_path(parsed.assertions[0].path) == path
	}
}

test_a_failed_item_of_a_list_check_with_no_path_counts_from_one_like_every_other_list if {
	policy := {"subjects": {"l": {"from": ["xss"]}}, "requirements": {"r": {"subject": "l", "checks": {"c": {"op": "all", "path": [], "check": {"op": "equals", "path": [], "value": 1}}}}}}
	[r.failed_items | some r in ergo.report({"xss": [[1, 2]]}, policy, {}).results; r.check == "c"] == [[{"cause": "value", "path": "item 2 of xss[]", "item": "item 2 of xss[]", "value": 2}]]
	with_each := {"subjects": {"m": {"from": ["o"]}}, "requirements": {"q": {"subject": "m", "checks": {"c": {"op": "all", "path": [], "each": ["a"], "check": {"op": "equals", "path": [], "value": 1}}}}}}
	[r.failed_items | some r in ergo.report({"o": [[{"a": [1]}, {"b": 2}]]}, with_each, {}).results; r.check == "c"] == [[{"cause": "absent", "path": "o[][1].a", "item": "o[][1].a", "value": null}]]
}

test_a_list_after_each_is_named_further_along_the_path_so_a_grammar_word_gets_no_dot if {
	doc := {"items": [{"id": "i", "o": [{"a": [1, 2]}, {"a": [3]}]}]}
	policy := {"subjects": {"t": {"from": ["items"], "id": ["id"]}}, "requirements": {"s": {"subject": "t", "checks": {"c": {"op": "all", "path": ["o"], "each": ["a"], "check": {"op": "equals", "path": [], "value": 9}}}}}}
	r := ergo.report(doc, policy, {})
	r.requirements.s.checks.c.expression == "every o[].a: o[].a[] == 9"
	[row.inputs[0].name | some row in r.results; row.check == "c"] == ["o[].a"]
}

test_a_list_whose_path_ends_in_an_index_keeps_the_index_in_brackets_before_its_items if {
	doc := {"items": [{"id": "i", "ys": [[1, 2], [3]]}]}
	checks := {
		"c": {"op": "all", "path": ["ys", 0], "check": {"op": "equals", "path": [], "value": 9}},
		"d": {"op": "all", "path": ["ys"], "each": [0], "check": {"op": "equals", "path": [], "value": 9}},
	}
	r := ergo.report(doc, {"subjects": {"t": {"from": ["items"], "id": ["id"]}}, "requirements": {"s": {"subject": "t", "checks": checks}}}, {})
	r.requirements.s.checks.c.expression == "every item 1 of ys: ys[0][] == 9"
	r.requirements.s.checks.d.expression == "every ys[][0]: ys[][0][] == 9"
}

test_params_and_input_cant_be_names_so_a_name_is_never_read_as_the_params_or_the_input if {
	every name in ["params", "input"] {
		policy := {"subjects": {"t": {"from": ["items", {"each_as": name}], "id": ["id"]}}, "requirements": {"s": {"subject": "t", "checks": {"c": {"op": "present", "path": ["id"]}}}}}
		r := ergo.report({"items": [{"id": "a"}]}, policy, {})
		not r.compliant
		[row.cause | some row in r.results; row.check == "$well_formed"] == ["value"]
	}
	rendered({}, {"op": "all", "path": ["xs"], "as": "input", "check": {"op": "present", "path": ["v"]}}) == "every xs as <invalid name>: v is present"
}

test_an_each_that_isnt_a_list_shows_as_invalid_in_the_expression if {
	rendered({"xs": [1]}, {"op": "all", "path": ["xs"], "each": {"x": 1}, "check": {"op": "present", "path": []}}) == "every xs[].<invalid each>: xs[].<invalid each>[] is present"
	rendered({"xs": [1]}, {"op": "all", "path": ["xs"], "each": true, "check": {"op": "present", "path": []}}) == "every xs[].<invalid each>: xs[].<invalid each>[] is present"
}

test_a_name_nothing_gave_never_prints_like_the_params_or_the_input if {
	policy := {"subjects": {"t": {"from": ["items"], "id": ["id"]}}, "requirements": {"s": {"subject": "t", "checks": {
		"a": {"op": "equals", "path": ["$params", "x"], "value": 1},
		"b": {"op": "equals", "path": ["$$params", "x"], "value": 1},
		"c": {"op": "present", "path": ["$input", "x"]},
	}}}}
	checks := ergo.report({"items": [{"id": "i"}]}, policy, {"x": 1}).requirements.s.checks
	[checks.a.expression, checks.b.expression, checks.c.expression] == ["<unknown name $params>.x == 1", "$params.x == 1", "<unknown name $input>.x is present"]
}

test_an_each_that_isnt_a_list_still_lists_every_item_as_ill_formed if {
	policy := {"subjects": {"t": {"from": ["items"], "id": ["id"]}}, "requirements": {"s": {"subject": "t", "checks": {"c": {"op": "all", "path": ["ys"], "each": "x", "check": {"op": "equals", "path": [], "value": 9}}}}}}
	[r.failed_items | some r in ergo.report({"items": [{"id": "i", "ys": [[1], [2]]}]}, policy, {}).results; r.check == "c"] == [[
		{"cause": "ill_formed", "path": "item 1 of ys", "item": "item 1 of ys", "value": [1]},
		{"cause": "ill_formed", "path": "item 2 of ys", "item": "item 2 of ys", "value": [2]},
	]]
}

test_a_number_written_as_a_literal_is_named_like_the_index_it_reads if {
	rendered({}, {"op": "present", "path": ["zs", {"literal": 1}]}) == "item 2 of zs is present"
	rendered({}, {"op": "present", "path": ["zs", {"literal": 1}, "k"]}) == "zs[1].k is present"
}

test_the_operators_only_sentences_read_into_are_unknown_ops_anywhere_in_todays_syntax if {
	every op in ["empty_string_or_list", "not_empty_string_or_list"] {
		_sentence_problems({"op": op, "path": ["x"]}) == [concat("", ["unknown op ", op])]
		ergo.report({"things": []}, _sentence_policy({"c": {"op": "all", "path": ["xs"], "check": {"op": op, "path": []}}}), {}).results[0].inputs[2] == {"name": "checks.c.check", "value": [concat("", ["unknown op ", op])]}
	}
}

test_is_empty_and_is_not_empty_take_a_string_or_a_list if {
	doc := {"things": [{"id": "a", "x": []}, {"id": "b", "x": ""}, {"id": "c", "x": "z"}, {"id": "d", "x": [1]}, {"id": "e", "x": {}}, {"id": "f", "x": null}, {"id": "g"}]}
	[[r[0], r[1], r[2]] | some r in _sentence_rows({"e": "x is empty", "n": "x is not empty"}, doc, {})] == [
		["e", true, "satisfied"], ["n", false, "value"],
		["e", true, "satisfied"], ["n", false, "value"],
		["e", false, "value"], ["n", true, "satisfied"],
		["e", false, "value"], ["n", true, "satisfied"],
		["e", false, "unusable"], ["n", false, "unusable"],
		["e", false, "null"], ["n", false, "null"],
		["e", false, "absent"], ["n", false, "absent"],
	]
}

test_a_check_that_copies_a_sentences_translation_still_cant_use_its_operator if {
	copy := {"op": "empty_string_or_list", "path": ["x"], "expression": "x is empty"}
	every check in [
		copy,
		{"op": "all", "path": ["items"], "check": copy},
		{"op": "any_of", "options": [[copy]]},
		{"op": "present", "path": ["x"], "substitute": copy},
	] {
		r := ergo.report({"things": [{"id": "t1", "x": "", "items": [{"x": ""}]}]}, _sentence_policy({"a": "x is empty", "b": check}), {})
		not r.compliant
		[row.cause | some row in r.results; row.check == "b"] == ["ill_formed"]
	}
	filtered := {
		"subjects": {"thing": {"from": ["things"], "id": ["id"], "applies_to": {"f": copy}}},
		"requirements": {"s": {"subject": "thing", "checks": {"a": "x is empty"}}},
	}
	[row.cause | some row in ergo.report({"things": [{"id": "t1", "x": ""}]}, filtered, {}).results; row.check == "$applies"] == ["ill_formed"]
}

test_is_empty_reads_through_params_named_by_and_a_parent_that_cant_hold_the_field if {
	doc := {"things": [{"id": "a", "art": {"z": ""}, "s": "text"}]}
	rows := _sentence_rows({"p": "$params.p is not empty", "n": "art named by $params.k is empty", "u": "s.y is empty"}, doc, {"p": [1], "k": "z"})
	[[r[0], r[1], r[2]] | some r in rows] == [["n", true, "satisfied"], ["p", true, "satisfied"], ["u", false, "unusable"]]
}

test_a_phrase_lists_its_longer_wording_first_because_finding_a_phrase_never_goes_back_to_try_another_wording if {
	_read(`x is equal to 1`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "value": 1}}]}
	_read(`x is an object`).assertions[0].phrase == {"op": "is a", "type": "object"}
	_read(`x is not in $params.a`).assertions[0].phrase.op == "is not one of"
	_read(`x does not equal y`).assertions[0].phrase.op == "is not"
	every ph in ergo._s_patterns.phrases {
		ph[1] != `(?:is|is +equal +to|equals) +`
	}
}

test_is_not_one_of_passes_on_any_value_that_is_there_and_not_listed_a_value_of_another_type_included if {
	doc := {"things": [{"id": "a", "x": "dev"}, {"id": "b", "x": "prod"}, {"id": "c", "x": 5}, {"id": "d", "x": null}, {"id": "e"}]}
	[[r[0], r[2]] | some r in _sentence_rows({"v": `x is not one of "prod", "staging"`, "p": "x is not in $params.blocked"}, doc, {"blocked": ["prod"]})] == [
		["p", "satisfied"], ["v", "satisfied"],
		["p", "value"], ["v", "value"],
		["p", "satisfied"], ["v", "satisfied"],
		["p", "null"], ["v", "null"],
		["p", "absent"], ["v", "absent"],
	]
}

test_is_not_in_a_list_read_from_the_params_fails_when_the_params_dont_hold_a_list if {
	doc := {"things": [{"id": "a", "x": "dev"}]}
	checks := {"e": "x is not in $params.empty", "m": "x is not in $params.none", "t": "x is not in $params.text"}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {"empty": [], "text": "prod"})] == [["e", "satisfied"], ["m", "absent"], ["t", "unusable"]]
}

test_not_in_is_an_unknown_op_in_todays_syntax if {
	_sentence_problems({"op": "not_in", "path": ["x"], "values": ["a"]}) == ["unknown op not_in"]
}

test_is_a_type_passes_on_that_json_type_and_fails_any_other_as_value if {
	doc := {"things": [{"id": "a", "x": []}, {"id": "b", "x": ""}, {"id": "c", "x": 0}, {"id": "d", "x": false}, {"id": "e", "x": {}}, {"id": "f", "x": null}, {"id": "g"}]}
	checks := {"b": "x is a boolean", "l": "x is a list", "n": "x is a number", "o": "x is an object", "s": "x is a string"}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {}); r[1]] == [["l", "satisfied"], ["s", "satisfied"], ["n", "satisfied"], ["b", "satisfied"], ["o", "satisfied"]]
	{r[2] | some r in _sentence_rows(checks, doc, {}); not r[1]} == {"value", "null", "absent"}
}

test_has_type_is_an_unknown_op_in_todays_syntax if {
	_sentence_problems({"op": "has_type", "path": ["x"], "type": "list"}) == ["unknown op has_type"]
}

test_starts_with_and_ends_with_take_two_strings if {
	doc := {"things": [{"id": "a", "x": "release/1.2", "p": "release/"}, {"id": "b", "x": "main", "p": "release/"}, {"id": "c", "x": 15, "p": 1}, {"id": "d", "x": null, "p": "r"}, {"id": "e", "p": "r"}]}
	checks := {"e": `x ends with ".2"`, "f": "x starts with p", "v": `x starts with "release/"`}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {})] == [
		["e", "satisfied"], ["f", "satisfied"], ["v", "satisfied"],
		["e", "value"], ["f", "value"], ["v", "value"],
		["e", "unusable"], ["f", "unusable"], ["v", "unusable"],
		["e", "null"], ["f", "null"], ["v", "null"],
		["e", "absent"], ["f", "absent"], ["v", "absent"],
	]
}

test_starts_with_is_an_invalid_cmp_in_todays_syntax_even_when_it_copies_a_sentence if {
	copy := {"op": "compare", "left": ["x"], "cmp": "starts_with", "right": {"literal": "a"}, "expression": `x starts with "a"`}
	_sentence_problems(copy) == ["invalid cmp"]
	r := ergo.report({"things": [{"id": "t1", "x": "ab", "xs": ["ab"]}]}, _sentence_policy({"a": `x starts with "a"`, "b": {"op": "all", "path": ["xs"], "check": object.union(copy, {"left": []})}}), {})
	[row.cause | some row in r.results; row.check in {"a", "b"}] == ["satisfied", "ill_formed"]
}

test_starts_with_only_ever_compares_two_strings_even_through_leaf_passed if {
	not ergo.leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "starts_with", "right": ["m"]}, {"n": 15, "m": 1})
	not ergo.leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "ends_with", "right": ["m"]}, {"n": 15, "m": 1})
}

test_a_written_value_after_starts_with_that_isnt_text_is_written_wrong_because_it_could_only_fail if {
	every pair in [[`x starts with null`, `"starts with" takes text`], [`x ends with 1`, `"ends with" takes text`], [`x starts with true`, `"starts with" takes text`]] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
}

test_an_op_that_is_a_list_is_only_an_unknown_op_because_a_list_would_be_read_as_a_path_into_the_table_of_operators if {
	every pair in [[[], "unknown op []"], [["range"], `unknown op ["range"]`], [{"a": 1}, `unknown op {"a": 1}`]] {
		r := ergo.report({"things": [{"id": "t1", "x": 1}]}, _sentence_policy({"c": {"op": pair[0], "path": ["x"]}}), {})
		r.results[0].inputs[2] == {"name": "checks.c", "value": [pair[1]]}
		[row.cause | some row in r.results; row.check == "c"] == ["ill_formed"]
	}
}

test_assertions_joined_with_and_or_listed_under_assert_give_one_row_that_names_the_ones_that_failed if {
	doc := {"prs": [{"id": "late", "username": "bob", "author": "ann", "ts": 1, "last_commit": 2}, {"id": "gone", "username": "ann", "author": "ann", "last_commit": 2}]}
	policy := {"subjects": {"pr": {"from": ["prs"], "id": ["id"]}}, "requirements": {"s": {"subject": "pr", "checks": {
		"line": "username does not equal author and ts is after last_commit",
		"list": {"assert": ["username does not equal author", "ts is after last_commit"]},
	}}}}
	r := ergo.report(doc, policy, {})
	r.requirements.s.checks.list.expression == "username does not equal author and ts is after last_commit"
	rows := [[row.subject.id, row.check, row.cause, row.failed_assertions] | some row in r.results; row.check in {"line", "list"}]
	rows == [
		["late", "line", "value", [{"assertion": "ts is after last_commit", "cause": "value"}]],
		["late", "list", "value", [{"assertion": "ts is after last_commit", "cause": "value"}]],
		["gone", "line", "absent", [{"assertion": "username does not equal author", "cause": "value"}, {"assertion": "ts is after last_commit", "cause": "absent"}]],
		["gone", "list", "absent", [{"assertion": "username does not equal author", "cause": "value"}, {"assertion": "ts is after last_commit", "cause": "absent"}]],
	]
	[v.failed_assertions | some v in ergo.violations(r); v.check == "list"][0] == [{"assertion": "ts is after last_commit", "cause": "value"}]
}

test_a_check_with_several_assertions_that_passes_has_no_failed_assertions_and_reads_every_input_once if {
	r := ergo.report({"things": [{"id": "a", "x": 1, "y": 2}]}, _sentence_policy({"c": "x is 1 and y is 2 and x is at least 1"}), {})
	[[row.cause, row.failed_assertions, row.inputs] | some row in r.results; row.check == "c"] == [["satisfied", [], [{"name": "x", "value": 1}, {"name": "y", "value": 2}]]]
}

test_all_of_is_an_unknown_op_in_todays_syntax if {
	_sentence_problems({"op": "all_of", "checks": [{"op": "present", "path": ["x"]}], "assertions": ["x exists"]}) == ["unknown op all_of"]
}

test_an_assertion_whose_param_cant_be_read_is_the_only_one_listed_as_unusable if {
	r := ergo.report({"things": [{"id": "a", "x": "p", "y": 1}]}, _sentence_policy({"c": "x is in $params.l and y exists and y is 2"}), {"l": "text"})
	[[row.cause, row.failed_assertions] | some row in r.results; row.check == "c"] == [["unusable", [{"assertion": "x is in $params.l", "cause": "unusable"}, {"assertion": "y is 2", "cause": "value"}]]]
}

test_an_all_of_written_by_hand_fails_as_ill_formed_like_any_unknown_op_whatever_shape_it_has if {
	every check in [
		{"op": "all_of", "checks": [], "assertions": []},
		{"op": "all_of"},
		{"op": "all_of", "checks": "x", "assertions": "y"},
		{"op": "all_of", "checks": [{"op": "present", "path": ["zz"]}], "assertions": []},
		{"op": "all_of", "checks": [{"op": "present", "path": ["zz"]}], "assertions": [{"evil": 1}]},
	] {
		r := ergo.report({"things": [{"id": "a", "x": 1}]}, _sentence_policy({"c": check}), {})
		[row | some row in r.results; row.check == "c"] == [{"requirement": "s", "subject": {"type": "thing", "id": "a"}, "check": "c", "passed": false, "cause": "ill_formed", "inputs": []}]
		[v.check | some v in ergo.violations(r)] == ["$well_formed", "c"]
	}
}

test_every_assertion_is_unusable_when_the_input_holds_something_json_cant if {
	r := ergo.report({"things": [{"id": "a", "x": 1, "s": {1}}]}, _sentence_policy({"c": "x is 1 and x exists"}), {})
	[[row.cause, row.failed_assertions] | some row in r.results; row.check == "c"] == [["unusable", [{"assertion": "x is 1", "cause": "unusable"}, {"assertion": "x exists", "cause": "unusable"}]]]
}

_walk_rows(checks, doc, params) := [[r.subject.id, r.check, r.cause, object.get(r, "failed_items", object.get(r, "failed_assertions", []))] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

test_every_and_some_read_into_a_walk_with_its_conditions if {
	c := ergo._s_written_check(`every approvers.username whose state is "APPROVED", if any, is in $params.staff`)
	c.op == "every"
	c.path == ["approvers", "username"]
	c.whose == [{"op": "equals", "path": ["state"], "value": "APPROVED"}]
	c.check.op == "in"
	c.if_any == true
}

test_a_walk_that_reads_no_list_fails_with_what_its_path_ends_at if {
	doc := {"things": [{"id": "a", "x": {"y": 1}}, {"id": "b"}, {"id": "c", "x": {"y": null}}]}
	_walk_rows({"e": "every x.y is 1"}, doc, {}) == [
		["a", "e", "unusable", [{"path": "x.y", "item": "x.y", "cause": "unusable", "value": 1}]],
		["b", "e", "absent", [{"path": "x", "item": "x", "cause": "absent", "value": null}]],
		["c", "e", "null", [{"path": "x.y", "item": "x.y", "cause": "null", "value": null}]],
	]
}

test_a_walk_starts_where_its_path_starts_and_steps_past_a_position_without_walking_it if {
	doc := {"things": [{"id": "a", "m": [[1, 2], [3]]}]}
	rows := _walk_rows({"i": "every $input.things[0].m[0] is at least 1", "p": "every first of m is 1"}, doc, {})
	rows == [["a", "i", "satisfied", []], ["a", "p", "value", [{"path": "item 2 of m[0]", "item": "item 2 of m[0]", "cause": "value", "value": 2}]]]
}

test_a_walk_whose_key_comes_from_a_param_that_cant_be_read_fails_with_its_cause if {
	doc := {"things": [{"id": "a", "o": {"k": [1]}}]}
	_walk_rows({"w": "every o named by $params.key is 1"}, doc, {}) == [["a", "w", "absent", []]]
	_walk_rows({"w": "every o named by $params.key is 1"}, doc, {"key": "k"}) == [["a", "w", "satisfied", []]]
}

test_every_and_some_joined_with_and_give_one_row_with_the_failed_sentences if {
	doc := {"things": [{"id": "a", "n": 1, "xs": [{"v": 1}, {"v": 2}]}]}
	r := ergo.report(doc, _sentence_policy({"c": "n is 1 and every xs.v is 1 and some xs.v is 2"}), {})
	[[row.cause, row.failed_assertions, row.inputs] | some row in r.results; row.check == "c"] == [[
		"value",
		[{"assertion": "every xs.v is 1", "cause": "value"}],
		[{"name": "n", "value": 1}, {"name": "xs[].v", "value": [1, 2]}],
	]]
}

test_forms_a_walk_cant_take_yet_are_written_wrong if {
	_sentence_problems(`every xs whose count of ys is between 1 and 2 is not empty`) == [`"is between" after a count of, a sum of or a plus isn't supported yet`]
	_sentence_problems(`every xs whose y is in z is 1`) == [`"is in" with a field of the subject isn't supported yet`]
	_sentence_problems(`every k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11.k12 is 1`) == ["every and some over more than ten steps aren't supported yet"]
}

test_every_and_some_are_unknown_ops_in_todays_syntax if {
	every op in ["every", "some"] {
		_sentence_problems({"op": op, "path": ["xs"], "check": {"op": "present", "path": []}, "whose": [], "if_any": false}) == [concat("", ["unknown op ", op])]
	}
	_sentence_problems({"op": "for", "items": [{"q": "every", "path": ["xs"], "whose": [], "if_any": false, "as": "x"}], "checks": [{"op": "present", "path": ["$x"]}], "assertions": ["x exists"]}) == ["unknown op for"]
}

test_a_walk_that_reads_no_list_stops_at_the_end_when_every_value_along_the_path_is_an_object if {
	doc := {"things": [{"id": "a", "x": {"y": {"z": 1}}}, {"id": "b", "xs": [1, 2]}]}
	_walk_rows({"e": "every x.y is 1"}, doc, {})[0] == ["a", "e", "unusable", [{"path": "x.y", "item": "x.y", "cause": "unusable", "value": {"z": 1}}]]
	_walk_rows({"e": "every xs[5].y is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "item 6 of xs", "item": "item 6 of xs", "cause": "absent", "value": null}]]
	_walk_rows({"e": "every x.y.z.w is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "x", "item": "x", "cause": "absent", "value": null}]]
}

test_an_item_a_whose_condition_cant_decide_is_undecided_even_when_another_condition_leaves_it_out if {
	doc := {"things": [{"id": "a", "xs": [{"kind": "b"}]}]}
	_walk_rows({"e": `every xs whose kind is "a" and state is "open" is not empty`}, doc, {}) == [["a", "e", "absent", [{"path": "xs[0].state", "item": "item 1 of xs", "cause": "absent", "value": null}]]]
}

test_a_walk_whose_param_cant_be_used_fails_as_unusable_even_with_if_any if {
	doc := {"things": [{"id": "a", "xs": [{"v": 2, "kind": "a"}]}]}
	checks := {
		"a": "every xs.v whose kind is not one of $params.l, if any, is 1",
		"b": "every xs is not one of $params.l",
		"c": "every xs.v is 2 and every xs.kind is in $params.l",
	}
	r := ergo.report(doc, _sentence_policy(checks), {"l": "text"})
	[[row.check, row.cause, object.get(row, "failed_items", object.get(row, "failed_assertions", null))] | some row in r.results; row.check in {"a", "b", "c"}] == [
		["a", "unusable", []],
		["b", "unusable", []],
		["c", "unusable", [{"assertion": "every xs.kind is in $params.l", "cause": "unusable"}]],
	]
	not r.compliant
}

test_a_walk_fails_as_unusable_when_the_input_holds_something_json_cant if {
	r := ergo.report({"things": [{"id": "a", "xs": [1], "bad": {1}}]}, _sentence_policy({"c": "every xs is 1"}), {})
	[row.cause | some row in r.results; row.check == "c"] == ["unusable"]
}

test_a_walk_on_a_subject_that_isnt_an_object_fails_like_any_path_does if {
	r := ergo.report({"things": ["text", null]}, {"subjects": {"t": {"from": ["things"]}}, "requirements": {"s": {"subject": "t", "checks": {"c": "every xs is 1"}}}}, {})
	[row.cause | some row in r.results; row.check == "c"] == ["not_an_object", "not_an_object"]
}

test_a_walk_of_exactly_ten_steps_walks_its_last_list_and_eleven_is_written_wrong if {
	doc := {"things": [{"id": "a", "p0": [{"p1": {"p2": {"p3": {"p4": {"p5": {"p6": {"p7": {"p8": {"p9": [""]}}}}}}}}}]}]}
	_walk_rows({"c": "every p0.p1.p2.p3.p4.p5.p6.p7.p8.p9 is not empty"}, doc, {})[0][2] == "value"
	_sentence_problems("every p0.p1.p2.p3.p4.p5.p6.p7.p8.p9.p10 is not empty") == ["every and some over more than ten steps aren't supported yet"]
}

test_a_walk_whose_named_by_cant_be_read_shows_an_empty_list_in_its_inputs if {
	r := ergo.report({"things": [{"id": "a", "xs": {"k": [1]}}]}, _sentence_policy({"c": "every xs named by $params.k is 1"}), {})
	[[row.cause, row.inputs, row.failed_items] | some row in r.results; row.check == "c"] == [["absent", [{"name": "xs named by $params.k", "value": []}], []]]
}

test_a_list_phrase_after_every_or_some_is_written_wrong_because_the_last_list_is_walked_too if {
	_sentence_problems(`every pull_requests.labels does not contain "hotfix"`) == [`"does not contain" after every or some would check each item of the last list, not the list: put the walk on a for line`]
	_sentence_problems(`some xs contains all of 1, 2`) == [`"contains all of" after every or some would check each item of the last list, not the list: put the walk on a for line`]
}

_for_rows(check, things, params) := [[r.subject.id, r.cause, r.failed_items, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_peer_approval := {
	"for": `some approvers whose state is "APPROVED" as approver, every commits as commit`,
	"assert": ["approver.username does not equal author", "approver.timestamp is after commit.timestamp"],
}

_peer_things := [
	{"id": "peer", "author": "ann", "commits": [{"timestamp": "2026-10-01T09:00:00Z"}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z"}]},
	{"id": "fails", "author": "ann", "commits": [{"timestamp": "2026-10-01T09:00:00Z"}, {"timestamp": "2026-10-01T11:00:00Z"}], "approvers": [
		{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T10:00:00Z"},
		{"username": "ann", "state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z"},
		{"username": "cat", "state": "COMMENTED", "timestamp": "2026-10-01T12:00:00Z"},
	]},
	{"id": "nostate", "author": "ann", "commits": [], "approvers": [{"username": "carl", "timestamp": "2026-10-01T12:00:00Z"}]},
]

test_a_for_line_lists_each_first_item_that_failed_with_the_lines_it_failed if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	[[row[0], row[1]] | some row in rows] == [["peer", "satisfied"], ["fails", "value"], ["nostate", "absent"]]
	rows[1][2] == [
		{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "value", "value": null, "failed_assertions": [{"assertion": "approver.timestamp is after commit.timestamp", "cause": "value"}]},
		{"path": "item 2 of approvers", "item": "item 2 of approvers", "cause": "value", "value": null, "failed_assertions": [{"assertion": "approver.username does not equal author", "cause": "value"}]},
	]
	rows[2][2] == [{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "absent", "value": null, "failed_assertions": []}]
	rows[0][2] == []
}

test_a_for_line_shows_each_list_it_walked_once_and_the_subject_fields_it_read if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	rows[1][3] == [
		{"name": "approvers[]", "value": _peer_things[1].approvers},
		{"name": "author", "value": "ann"},
		{"name": "commits[]", "value": _peer_things[1].commits},
	]
}

test_a_for_line_prints_as_its_for_line_and_its_assertions if {
	r := ergo.report({"things": []}, _sentence_policy({"c": _peer_approval}), {})
	r.requirements.s.checks.c.expression == `for some approvers whose state is "APPROVED" as approver, every commits as commit: approver.username does not equal author and approver.timestamp is after commit.timestamp`
}

test_a_second_item_can_walk_a_list_inside_the_first if {
	check := {"for": `every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver`, "assert": "approver.username does not equal pr.author"}
	things := [
		{"id": 1, "pull_requests": [{"author": "ann", "approvers": [{"username": "bob", "state": "APPROVED"}]}]},
		{"id": 2, "pull_requests": [{"author": "ann", "approvers": [{"username": "bob", "state": "APPROVED"}]}, {"author": "cat", "approvers": [{"username": "cat", "state": "APPROVED"}, {"username": "dan", "state": "COMMENTED"}]}]},
	]
	rows := _for_rows(check, things, {})
	[[row[0], row[1]] | some row in rows] == [[1, "satisfied"], [2, "value"]]
	rows[1][2] == [{"path": "item 2 of pull_requests", "item": "item 2 of pull_requests", "cause": "value", "value": null, "failed_assertions": [{"assertion": "approver.username does not equal pr.author", "cause": "value"}]}]
	rows[1][3] == [
		{"name": "pr.approvers[]", "value": array.concat(things[1].pull_requests[0].approvers, things[1].pull_requests[1].approvers)},
		{"name": "pull_requests[]", "value": things[1].pull_requests},
	]
}

test_an_item_that_no_approver_passes_fails_without_lines_when_whose_left_every_one_out if {
	check := {"for": `every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver`, "assert": "approver.username does not equal pr.author"}
	rows := _for_rows(check, [{"id": 1, "pull_requests": [{"author": "ann", "approvers": [{"username": "bob", "state": "COMMENTED"}]}]}], {})
	rows[0][1] == "value"
	rows[0][2] == [{"path": "item 1 of pull_requests", "item": "item 1 of pull_requests", "cause": "value", "value": null, "failed_assertions": []}]
}

test_a_for_list_fails_closed_as_a_walk_does if {
	check := {"for": "every xs as x", "assert": "x is 1"}
	rows := _for_rows(check, [{"id": 1, "xs": []}, {"id": 2}, {"id": 3, "xs": null}, {"id": 4, "xs": {"a": 1}}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "value", [{"path": "xs", "item": "xs", "cause": "value", "value": [], "failed_assertions": []}]],
		[2, "absent", [{"path": "xs", "item": "xs", "cause": "absent", "value": null, "failed_assertions": []}]],
		[3, "null", [{"path": "xs", "item": "xs", "cause": "null", "value": null, "failed_assertions": []}]],
		[4, "unusable", [{"path": "xs", "item": "xs", "cause": "unusable", "value": {"a": 1}, "failed_assertions": []}]],
	]
	[row[1] | some row in _for_rows({"for": "every xs, if any, as x", "assert": "x is 1"}, [{"id": 1, "xs": []}, {"id": 2}], {})] == ["satisfied", "absent"]
}

test_an_item_a_whose_cant_decide_fails_with_its_cause_before_any_line_is_read if {
	check := {"for": "every xs whose s is at least 1 as x", "assert": `x.k is "a"`}
	rows := _for_rows(check, [{"id": 1, "xs": [{"k": "a", "s": 1}, {"k": "a"}]}, {"id": 2, "xs": [{"k": "a", "s": "1"}]}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "absent", "value": null, "failed_assertions": []}]],
		[2, "unusable", [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "unusable", "value": null, "failed_assertions": []}]],
	]
}

test_a_whose_on_an_item_reads_its_own_field_even_when_it_has_the_items_name if {
	check := {"for": "every xs whose x is 1 as x", "assert": "x.v is 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"x": 1, "v": 2}, {"x": 2, "v": 3}]}], {})] == ["satisfied"]
}

test_a_whose_on_the_second_item_can_read_the_first_items_name if {
	check := {"for": "every prs as pr, some pr.rev whose u does not equal pr.author as r", "assert": `r.u is "b"`}
	[row[1] | some row in _for_rows(check, [{"id": 1, "prs": [{"author": "a", "rev": [{"u": "a"}, {"u": "b"}]}]}, {"id": 2, "prs": [{"author": "b", "rev": [{"u": "a"}, {"u": "b"}]}]}], {})] == ["satisfied", "value"]
}

test_a_name_hides_the_subject_field_with_the_same_name if {
	check := {"for": "every xs as x", "assert": `x is "a"`}
	[row[1] | some row in _for_rows(check, [{"id": 1, "x": "b", "xs": ["a"]}], {})] == ["satisfied"]
}

test_a_for_line_can_walk_a_param if {
	check := {"for": "some $params.allowed as ok", "assert": "k equals ok"}
	rows := _for_rows(check, [{"id": 1, "k": "a"}, {"id": 2, "k": "z"}], {"allowed": ["a", "b"]})
	[row[1] | some row in rows] == ["satisfied", "value"]
	rows[1][3] == [{"name": "$params.allowed[]", "value": ["a", "b"]}, {"name": "k", "value": "z"}]
	[row[1] | some row in _for_rows(check, [{"id": 1, "k": "a"}], {})] == ["absent"]
}

test_an_every_in_the_assertion_walks_inside_the_named_item if {
	check := {"for": "some xs as x", "assert": "every x.ys is at most 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"ys": [1, 3]}, {"ys": [1, 2]}]}, {"id": 2, "xs": [{"ys": [3]}]}], {})] == ["satisfied", "value"]
}

test_each_item_lists_every_line_it_failed_with_the_first_cause_of_each if {
	check := {"for": "every xs as x", "assert": ["x.a is 2", "x.b is 2", "x.c is 1"]}
	rows := _for_rows(check, [{"id": 1, "xs": [{"a": 1, "b": 2}, {"a": 2, "b": 2, "c": 1}]}], {})
	rows[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": null, "failed_assertions": [{"assertion": "x.a is 2", "cause": "value"}, {"assertion": "x.c is 1", "cause": "absent"}]}]
}

test_a_for_line_on_a_subject_that_isnt_an_object_fails_like_any_path_does if {
	[[row[1], row[2], row[3]] | some row in _for_rows({"for": "every xs as x", "assert": "x is 1"}, ["s"], {})] == [["not_an_object", [], []]]
}

test_a_for_line_written_wrong_says_why if {
	_sentence_problems({"assert": "x exists", "for": 1}) == ["invalid for"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as y, every zs as z"}) == ["for: a for line holds two items at most"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as"}) == [`for: an item ends with "as" and a name, like "every pull_requests as pr"`]
	_sentence_problems({"assert": "x.a exists", "for": "xs as x"}) == [`for: an item starts with "every" or "some"`]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as x"}) == ["for: x is given twice"]
	_sentence_problems({"assert": "x.a is 1", "for": "every xs as params"}) == ["for: params can't be a name"]
	_sentence_problems({"assert": "x.a is 1", "for": "some xs, if any, as x"}) == ["for: if any can't go with some"]
	_sentence_problems({"assert": "x is $foo", "for": "every xs as x"}) == ["unknown name $foo"]
}

test_forms_ergo_does_not_run_yet_are_written_wrong_on_a_for_line_too if {
	every pair in [
		["every xs named by k as x", "unknown name k"],
		["every xs whose v named by k is 1 as x", "unknown name k"],
		["every xs whose count of ys is between 1 and 2 as x", `"is between" after a count of, a sum of or a plus isn't supported yet`],
		["every b.c.d.e.f.g.h.i.j.k.l.m as x", "every and some over more than ten steps aren't supported yet"],
	] {
		_sentence_problems({"assert": "x is 1", "for": pair[0]}) == [pair[1]]
	}
}

test_a_for_list_whose_named_by_cant_be_read_fails_with_its_cause_as_a_walk_does if {
	check := {"for": "every m named by $params.k as x", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {}) == [[1, "absent", [], [{"name": "m named by $params.k", "value": []}]]]
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {"k": "a"}) == [[1, "satisfied", [], [{"name": "m named by $params.k[]", "value": [1]}]]]
	inner := {"for": "every xs as x, every m named by $params.k as y", "assert": "y is 1"}
	_for_rows(inner, [{"id": 1, "xs": [1], "m": {"a": [1]}}], {}) == [[
		1, "absent",
		[{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": null, "failed_assertions": []}],
		[{"name": "m named by $params.k", "value": []}, {"name": "xs[]", "value": [1]}],
	]]
}

test_a_second_item_a_whose_cant_decide_fails_the_first_item_with_its_cause if {
	check := {"for": "every xs as x, every ys whose s is 1 as y", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "xs": [1], "ys": [{"s": 1}, {"t": 1}]}], {})[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": null, "failed_assertions": []}]
}

test_a_for_line_whose_param_cant_be_used_fails_as_unusable_and_keeps_its_inputs if {
	rows := _for_rows({"for": "every xs as x", "assert": "x is one of $params.l"}, [{"id": 1, "xs": [1]}, "s"], {"l": "text"})
	rows == [[1, "unusable", [], [{"name": "xs[]", "value": [1]}]], ["s", "unusable", [], [{"name": "xs", "value": []}]]]
	[row[1] | some row in _for_rows({"for": "every xs whose x is one of $params.l as x", "assert": "x is 1"}, [{"id": 1, "xs": [1]}], {"l": "text"})] == ["unusable"]
}

test_a_name_whose_path_ends_missing_or_unreadable_fails_its_item_before_its_lines if {
	rows := _for_rows({"for": "every prs.title as t", "assert": "t does not exist"}, [{"id": 1, "prs": [{}]}, {"id": 2, "prs": [{"title": null}]}, {"id": 3, "prs": [{"meta": "s"}]}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": []}]],
		[2, "satisfied", []],
		[3, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": []}]],
	]
	[row[1] | some row in _for_rows({"for": "every prs.meta.title as t", "assert": "t is null"}, [{"id": 1, "prs": [{"meta": "s"}]}], {})] == ["unusable"]
	[row[1] | some row in _for_rows({"for": `every prs.title whose n is 1 as t`, "assert": `t is "x"`}, [{"id": 1, "prs": [{"n": 2}, {"n": 1, "title": "x"}]}], {})] == ["satisfied"]
}

test_an_every_under_a_for_line_shows_its_list_as_a_one_line_every_does if {
	rows := _for_rows({"for": "every prs as pr", "assert": "every cs.s is true"}, [{"id": 1, "prs": [{"n": 1}], "cs": [{"s": true}, {"s": false}]}], {})
	rows[0][3] == [{"name": "cs[].s", "value": [true, false]}, {"name": "prs[]", "value": [{"n": 1}]}]
}

test_a_for_line_on_a_subject_that_isnt_an_object_fails_when_either_path_starts_at_the_subject if {
	[[row[1], row[3]] | some row in _for_rows({"for": "every $params.l as l, some xs as x", "assert": "x is l"}, ["s"], {"l": [1]})] == [["not_an_object", []]]
}

test_a_second_item_that_reads_into_a_first_item_that_isnt_an_object_fails_it_as_not_an_object if {
	rows := _for_rows({"for": "every prs as pr, some pr.approvers as ap", "assert": "ap is 1"}, [{"id": 1, "prs": [1, null, {"approvers": [1]}]}], {})
	[[f.item, f.cause] | some f in rows[0][2]] == [["item 1 of prs", "not_an_object"], ["item 2 of prs", "not_an_object"]]
	[row[1] | some row in _for_rows({"for": "every m as row, every row as cell", "assert": "cell is 1"}, [{"id": 1, "m": [[1], [1, 1]]}], {})] == ["satisfied"]
}

_tally_rows(check, things, params) := [[r.subject.id, r.cause, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_review := {
	"id": "pr-7",
	"personas_ran": ["security"],
	"findings": [{"source": "claude"}, {"source": "gpt"}, {"source": "claude"}],
	"claude_found": 2,
	"stages": [{"kind": "model", "usd": 0.5}, {"kind": "model", "usd": 0.25}, {"kind": "tool", "usd": 0}],
	"total_usd": 0.76,
}

test_count_of_counts_the_items_left_in_and_shows_them_beside_the_count if {
	_tally_rows(`count of findings whose source is "claude" equals claude_found`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `count of findings whose source is "claude"`, "value": 2},
		{"name": "findings[]", "value": _review.findings},
		{"name": "claude_found", "value": 2},
	]]]
}

test_sum_of_adds_up_the_field_across_the_items_left_in if {
	_tally_rows(`sum of stages.usd whose kind is "model" equals total_usd within 0.01`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `sum of stages.usd whose kind is "model"`, "value": 0.75},
		{"name": "stages[].usd", "value": [0.5, 0.25, 0]},
		{"name": "total_usd", "value": 0.76},
	]]]
	[row[1] | some row in _tally_rows("sum of xs.n is 0.3", [{"id": 1, "xs": [{"n": 0.1}, {"n": 0.2}]}], {})] == ["satisfied"]
}

test_plus_adds_paths_numbers_counts_and_sums if {
	_tally_rows("claude_found is count of personas_ran plus 1", [_review], {}) == [["pr-7", "satisfied", [
		{"name": "claude_found", "value": 2},
		{"name": "count of personas_ran plus 1", "value": 2},
		{"name": "count of personas_ran", "value": 1},
		{"name": "personas_ran[]", "value": ["security"]},
	]]]
	[row[1] | some row in _tally_rows("claude_found plus count of findings is 5", [_review], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of personas_ran plus claude_found is 3", [object.union(_review, {"claude_found": "2"})], {})] == ["unusable"]
}

test_count_of_walks_every_list_along_its_path_and_an_empty_list_adds_nothing if {
	things := [{"id": "empty", "prs": []}, {"id": "nested", "prs": [{"cs": [1, 2]}, {"cs": []}, {"cs": [3]}]}]
	[[row[0], row[1], row[2][0].value] | some row in _tally_rows("count of prs.cs is 3", things, {})] == [["empty", "value", 0], ["nested", "satisfied", 3]]
	[[row[0], row[1], row[2][0].value] | some row in _tally_rows("sum of prs.cs is 6", things, {})] == [["empty", "value", 0], ["nested", "satisfied", 6]]
}

test_count_of_and_sum_of_fail_closed_on_a_list_they_cant_read if {
	things := [{"id": "miss", "prs": [{"cs": [1]}, {}]}, {"id": "null", "prs": null}, {"id": "str", "prs": "x"}, {"id": "gone"}]
	[[row[0], row[1], row[2][0].value] | some row in _tally_rows("count of prs.cs is 1", things, {})] == [["miss", "absent", null], ["null", "null", null], ["str", "unusable", null], ["gone", "absent", null]]
	[[row[0], row[1]] | some row in _tally_rows("count of n is 1", [{"id": 1, "n": 5}, {"id": 2, "n": {"a": 1}}], {})] == [[1, "unusable"], [2, "unusable"]]
}

test_sum_of_fails_on_a_value_that_isnt_a_number if {
	things := [{"id": "nul", "xs": [{"n": null}]}, {"id": "txt", "xs": [{"n": "1"}]}, {"id": "gone", "xs": [{}]}]
	[[row[0], row[1]] | some row in _tally_rows("sum of xs.n is 1", things, {})] == [["nul", "null"], ["txt", "unusable"], ["gone", "absent"]]
}

test_an_item_a_whose_cant_decide_fails_the_count_rather_than_going_uncounted if {
	[[row[1], row[2][0].value] | some row in _tally_rows(`count of xs whose k is "a" is 1`, [{"id": 1, "xs": [{"k": "a"}, {"j": 1}]}], {})] == [["absent", null]]
	[row[1] | some row in _tally_rows(`count of xs whose k exists is 1`, [{"id": 1, "xs": [{"k": "a"}, {"j": 1}]}], {})] == ["satisfied"]
}

test_count_of_reads_params_and_named_by if {
	[row[1] | some row in _tally_rows("count of $params.l is 2", [{"id": 1}], {"l": [1, 2]})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of $params.l is 2", [{"id": 1}], {})] == ["absent"]
	[row[1] | some row in _tally_rows("count of m named by $params.k is 2", [{"id": 1, "m": {"a": [1, 2]}}], {"k": "a"})] == ["satisfied"]
}

test_a_count_can_go_in_a_whose_of_every_and_an_item_it_cant_decide_fails_the_walk if {
	things := [{"id": 1, "findings": [{"a": 1}]}, {"id": 2, "findings": [{"a": 1, "ys": [1]}]}]
	[[row[0], row[1]] | some row in _tally_rows("every findings whose count of ys is 1 exists", things, {})] == [[1, "absent"], [2, "satisfied"]]
}

test_counts_work_in_and_lists_and_under_a_for_line_with_its_names if {
	[row[1] | some row in _tally_rows({"assert": ["count of findings is 3", "sum of stages.usd is 0.75"]}, [_review], {})] == ["satisfied"]
	things := [{"id": 1, "ps": ["a"], "prs": [{"r": [1, 2]}, {"r": [1]}]}, {"id": 2, "ps": ["a"], "prs": [{"r": [1, 2]}]}]
	rows := _tally_rows({"for": "every prs as pr", "assert": ["count of ps is 1", "count of pr.r is at least 2"]}, things, {})
	[[row[0], row[1]] | some row in rows] == [[1, "value"], [2, "satisfied"]]
	rows[1][2] == [{"name": "count of ps", "value": 1}, {"name": "prs[]", "value": [{"r": [1, 2]}]}, {"name": "ps[]", "value": ["a"]}]
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "count of pr.r whose u does not equal pr.a is 2"}, [{"id": 1, "prs": [{"a": "x", "r": [{"u": "x"}, {"u": "y"}, {"u": "z"}]}]}], {})] == ["satisfied"]
}

test_counts_and_sums_are_invalid_sides_in_todays_syntax if {
	_sentence_problems({"op": "compare", "left": {"count_of": ["xs"], "whose": [], "text": "t"}, "cmp": "eq", "right": {"literal": 1}}) == ["invalid left"]
	_sentence_problems({"op": "compare", "left": ["n"], "cmp": "eq", "right": {"sum_of": ["xs"], "whose": [], "text": "t"}}) == ["invalid right"]
	_sentence_problems({"op": "compare", "left": {"add": [["n"], {"literal": 1}], "text": "t"}, "cmp": "eq", "right": {"literal": 1}}) == ["invalid left"]
}

test_a_count_whose_named_by_cant_be_read_fails_with_its_cause if {
	_tally_rows("count of m named by $params.k is 2", [{"id": 1, "m": {"a": [1, 2]}}], {}) == [[1, "absent", [{"name": "count of m named by $params.k", "value": null}, {"name": "m named by $params.k", "value": []}]]]
}

test_a_count_fails_on_a_value_it_cant_read_unless_whose_left_its_item_out if {
	[row[1] | some row in _tally_rows("count of xs.t is 1", [{"id": 1, "xs": ["s"]}], {})] == ["not_an_object"]
	[row[1] | some row in _tally_rows("count of xs.t whose k is 1 is 1", [{"id": 1, "xs": [{"k": 1, "t": 0}, {"k": 2}]}], {})] == ["satisfied"]
}

test_plus_with_a_whose_on_its_last_count if {
	_tally_rows(`claude_found plus count of findings whose source is "gpt" is at least 3`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `claude_found plus count of findings whose source is "gpt"`, "value": 3},
		{"name": "claude_found", "value": 2},
		{"name": `count of findings whose source is "gpt"`, "value": 1},
		{"name": "findings[]", "value": _review.findings},
	]]]
}

test_plus_under_a_for_line_reads_the_names if {
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "pr.a plus count of pr.r is 3"}, [{"id": 1, "prs": [{"a": 1, "r": [1, 2]}]}, {"id": 2, "prs": [{"a": 2, "r": [1, 2]}]}], {})] == ["satisfied", "value"]
}

test_an_add_of_a_count_is_an_invalid_side_in_todays_syntax if {
	_sentence_problems({"op": "compare", "left": {"add": [{"count_of": ["xs"], "whose": [], "text": "t"}]}, "cmp": "eq", "right": {"literal": 1}}) == ["invalid left"]
}

test_sum_of_and_plus_add_numbers_as_decimals if {
	_tally_rows("sum of xs.n is 1.6", [{"id": 1, "xs": [{"n": 0.7}, {"n": 0.9}]}], {})[0][2][0] == {"name": "sum of xs.n", "value": 1.6}
	[row[1] | some row in _tally_rows("x is p plus q plus 0.1", [{"id": 1, "p": 0.7, "q": 0.9, "x": 1.7}], {})] == ["satisfied"]
	ergo._decimal_sum([1e-7, 2e-7]) == 3e-7
	ergo._decimal_sum([1.5e3, 0.25]) == 1500.25
	ergo._decimal_sum([-0.7, 0.9]) == 0.2
	ergo._decimal_sum([]) == 0
	ergo._decimal_sum([1e-20, 1]) == sum([1e-20, 1])
}

test_a_sum_with_several_values_it_cant_add_fails_with_the_worst_cause if {
	[row[1] | some row in _tally_rows("sum of items.usd is 30", [{"id": 1, "items": [{"usd": null}, {}, {"usd": "x"}]}, {"id": 2, "items": [{"usd": null}, {}]}], {})] == ["unusable", "absent"]
}

test_large_numbers_are_added_as_the_runtime_adds_them_so_the_sum_stays_right if {
	[row[1] | some row in _tally_rows("sum of xs is at least big", [{"id": 1, "xs": [0.1, 1e30], "big": 1e30}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("big plus 0.1 is at least big", [{"id": 1, "big": 1e30}], {})] == ["satisfied"]
}

test_a_count_on_a_subject_or_item_that_isnt_an_object_fails_as_not_an_object if {
	[[row[0], row[1]] | some row in _tally_rows("count of xs is 1", [5, null, [1, 2]], {})] == [[5, "not_an_object"], [null, "not_an_object"], [[1, 2], "not_an_object"]]
	[row[1] | some row in _tally_rows("count of xs.n is 1", [{"id": 1, "xs": [5]}], {})] == ["not_an_object"]
	[row[2][0].value | some row in _tally_rows("count of xs.n is 2", [{"id": 1, "xs": [{"n": 1}, {"n": null}]}], {})] == [2]
}

test_a_count_whose_whose_reads_a_for_name_isnt_shown_in_the_inputs if {
	rows := _tally_rows({"for": "every prs as pr", "assert": "count of xs whose n is pr.need is at least 1"}, [{"id": 1, "prs": [{"need": 1}, {"need": 2}], "xs": [{"n": 1}, {"n": 2}]}], {})
	rows == [[1, "satisfied", [{"name": "prs[]", "value": [{"need": 1}, {"need": 2}]}]]]
	added := _tally_rows({"for": "every prs as pr", "assert": "1 plus count of xs whose n is pr.need is at least 2"}, [{"id": 1, "prs": [{"need": 1}], "xs": [{"n": 1}]}], {})
	added == [[1, "satisfied", [{"name": "prs[]", "value": [{"need": 1}]}]]]
}

test_a_count_whose_whose_reads_a_param_it_cant_use_shows_null if {
	_tally_rows("count of xs whose s is one of $params.v is 1", [{"id": 1, "xs": [{"s": "a"}]}], {"v": 5}) == [[1, "unusable", [{"name": "count of xs whose s is in $params.v", "value": null}, {"name": "xs[]", "value": [{"s": "a"}]}]]]
}

test_a_derived_check_with_a_substitute_is_read_the_slow_way_and_gives_the_same_report if {
	check := {
		"op": "compare",
		"left": {"add": [["n"], {"count": ["xs"]}, {"literal": 1}]},
		"cmp": "eq",
		"right": {"literal": 4},
		"substitute": {"op": "present", "path": ["waived"]},
	}
	rows := [[r.subject.id, r.cause, r.inputs] | some r in ergo.report({"things": [{"id": 1, "n": 1, "xs": [1, 2]}, {"id": 2, "n": "1", "xs": [], "waived": true}, {"id": 3, "n": 1, "xs": []}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [
		[1, "satisfied", [{"name": "n + count(xs) + 1", "value": 4}, {"name": "n", "value": 1}, {"name": "count(xs)", "value": 2}, {"name": "xs", "value": [1, 2]}, {"name": "waived", "value": null}]],
		[2, "substituted", [{"name": "n + count(xs) + 1", "value": null}, {"name": "n", "value": "1"}, {"name": "count(xs)", "value": 0}, {"name": "xs", "value": []}, {"name": "waived", "value": true}]],
		[3, "value", [{"name": "n + count(xs) + 1", "value": 2}, {"name": "n", "value": 1}, {"name": "count(xs)", "value": 0}, {"name": "xs", "value": []}, {"name": "waived", "value": null}]],
	]
}

test_a_count_whose_ref_cant_be_read_is_read_the_slow_way_and_fails_with_the_refs_cause if {
	_tally_rows(`count of xs whose s is one of $params.missing is 1`, [{"id": 1, "xs": [{"s": "a"}]}], {}) == [[1, "absent", [{"name": "count of xs whose s is in $params.missing", "value": null}, {"name": "xs[]", "value": [{"s": "a"}]}]]]
}

test_a_custom_operator_sees_only_the_fields_written_on_its_check if {
	[r.cause | some r in ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": {"op": "sees_only_its_fields", "path": ["x"]}}), {}).results; r.check == "c"] == ["satisfied"]
}

test_a_count_whose_whose_reads_a_missing_param_fails_even_when_it_would_count_zero if {
	things := [{"id": 1, "xs": []}, {"id": 2, "xs": [{"k": "a"}]}]
	_tally_rows("count of xs whose k is one of $params.missing is 0", things, {}) == [
		[1, "absent", [{"name": "count of xs whose k is in $params.missing", "value": null}, {"name": "xs[]", "value": []}]],
		[2, "absent", [{"name": "count of xs whose k is in $params.missing", "value": null}, {"name": "xs[]", "value": [{"k": "a"}]}]],
	]
	[row[1] | some row in _tally_rows("count of xs whose k is one of $params.v is 0", things, {"v": null})] == ["null", "null"]
}

test_an_and_list_of_counts_shows_each_count_once if {
	rows := _tally_rows({"assert": ["count of findings is 3", "claude_found plus 1 is 3"]}, [_review], {})
	rows == [["pr-7", "satisfied", [
		{"name": "claude_found", "value": 2},
		{"name": "claude_found plus 1", "value": 3},
		{"name": "count of findings", "value": 3},
		{"name": "findings[]", "value": _review.findings},
	]]]
}

test_a_hand_written_count_of_inside_an_add_is_written_wrong_and_still_shows_its_count if {
	check := {"op": "compare", "left": {"add": [{"count_of": ["xs"], "whose": [], "text": "t"}]}, "cmp": "eq", "right": {"literal": 2}, "substitute": {"op": "present", "path": ["z"]}}
	[[r.cause, r.inputs] | some r in ergo.report({"things": [{"id": 1, "xs": [1, 2]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [["ill_formed", [{"name": "t", "value": 2}, {"name": "xs[]", "value": [1, 2]}, {"name": "z", "value": null}]]]
}

test_the_answers_ergo_works_out_once_per_check_cant_be_written_on_a_check if {
	every f in ["$once", "$ref_cause"] {
		_sentence_problems(object.union({"op": "compare", "left": {"count": ["xs"]}, "cmp": "eq", "right": {"literal": 1}}, {f: true})) == [concat("", ["unknown field ", f])]
	}
}

_from_report(doc, subjects, checks, params) := ergo.report(doc, {"subjects": subjects, "requirements": {"r": {"subject": object.keys(subjects)[_], "checks": checks}}}, params) if count(subjects) == 1

_from_rows(rep) := [[r.subject.id, r.check, r.cause, r.inputs] | some r in rep.results; not r.check in {"$min_subjects", "$unique_ids", "$well_formed"}]

_from_problems(rep) := [i | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

_deployments := {"deployments": [
	{"id": 1, "environment": "prod", "change_type": "emergency"},
	{"id": 2, "environment": "dev"},
	{"id": 3, "environment": "prod", "change_type": "standard"},
]}

test_a_from_written_as_a_sentence_reads_its_path_and_keeps_the_subjects_whose_conditions_hold if {
	rep := _from_report(_deployments, {"emergency change": {"from": `deployments whose environment is "prod" and change_type is "emergency"`, "id": "id"}}, {"c": "id exists"}, {})
	_from_rows(rep) == [
		[1, "$applies", "satisfied", [{"name": "change_type", "value": "emergency"}, {"name": "environment", "value": "prod"}]],
		[2, "$applies", "absent", [{"name": "change_type", "value": null}, {"name": "environment", "value": "dev"}]],
		[3, "$applies", "value", [{"name": "change_type", "value": "standard"}, {"name": "environment", "value": "prod"}]],
		[1, "c", "satisfied", [{"name": "id", "value": 1}]],
	]
	rep.requirements.r.checks["$applies"].expression == `environment is "prod" and change_type is "emergency"`
}

test_the_conditions_of_a_from_keep_the_order_they_were_written_in_past_ten if {
	conds := concat(" and ", [concat("", ["k", format_int(i, 10), " exists"]) | some i in numbers.range(1, 11)])
	rep := _from_report({"xs": [{"id": 1}]}, {"x": {"from": concat("", ["xs whose ", conds])}}, {"c": "id exists"}, {})
	rep.requirements.r.checks["$applies"].expression == conds
}

test_a_subject_with_no_from_reads_the_input_field_named_like_it if {
	doc := {"artifact": {"fingerprint": "sha256:abc", "signed": true}}
	every def in [null, {}, {"id": "fingerprint"}, {"id": ["fingerprint"]}] {
		[[r[1], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": def}, {"c": "signed is true"}, {}))] == [["c", "satisfied"]]
	}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": {"from": [], "id": "artifact.fingerprint"}}, {"c": "artifact.signed is true"}, {}))] == [["sha256:abc", "satisfied"]]
}

test_a_from_named_by_a_param_or_by_each_of_a_param_list if {
	doc := {"build": {"runs": {"unit": {"result": "passed"}, "integration": {"result": "failed"}, "smoke": {"result": "passed"}}}}
	each := _from_report(doc, {"run": {"from": "build.runs named by each of $params.kinds"}}, {"c": `result is "passed"`}, {"kinds": ["unit", "integration", "system"]})
	[[r[0], r[2]] | some r in _from_rows(each)] == [["integration", "value"], ["system", "absent"], ["unit", "satisfied"]]
	one := _from_report(doc, {"run": {"from": "build.runs named by $params.kind"}}, {"c": `result is "passed"`}, {"kind": "unit"})
	[r[2] | some r in _from_rows(one)] == ["satisfied"]
}

test_conditions_of_a_from_can_use_phrases_only_sentences_have if {
	doc := {"xs": [{"id": 1, "tags": [], "cs": [1]}, {"id": 2, "tags": ["a"], "cs": [1]}]}
	rep := _from_report(doc, {"x": {"from": "xs whose tags is empty and count of cs is at least 1", "id": "id"}}, {"c": "id exists"}, {})
	[[r[0], r[1], r[2]] | some r in _from_rows(rep)] == [[1, "$applies", "satisfied"], [2, "$applies", "value"], [1, "c", "satisfied"]]
}

test_a_from_or_id_written_wrong_says_why_in_well_formed if {
	every pair in [
		[{"from": "xs whose"}, {"name": "subjects.x.from", "value": ["doesn't parse"]}],
		[{"from": "xs whose last of ys is 1"}, {"name": "subjects.x.from", "value": ["whose: last of isn't supported yet"]}],
		[{"from": "xs whose a is 1"}, {"name": "subjects.x.from", "value": ["a is a word of the grammar: write .a"]}],
		[{"from": "xs", "id": "id is 1"}, {"name": "subjects.x.id", "value": [`an id is a path, like "id" or "build.number"`]}],
		[{"from": "xs whose id exists", "applies_to": {"a": {"op": "present", "path": ["id"]}}}, {"name": "subjects.x.from", "value": [`applies_to can't go with a from written as a sentence: put the conditions after "whose"`]}],
	] {
		_from_problems(_from_report({"xs": [{"id": 1}]}, {"x": pair[0]}, {"c": "id exists"}, {})) == [pair[1]]
	}
}

test_a_subjects_own_name_in_its_own_from_is_the_input_field if {
	own := ergo.report({"lockfile": {"status": "COMPLETE"}}, {"subjects": {"lockfile": {"from": `lockfile whose status is "COMPLETE"`}}, "requirements": {"r": {"subject": "lockfile", "checks": {"c": "status exists"}}}}, {})
	_from_problems(own) == []
	[r.cause | some r in own.results; r.check == "c"] == ["satisfied"]
}

_chain_doc := {"trail": {"artifacts": {
	"web": {"fingerprint": "sha-1", "name": "web", "pull_requests": [{"url": "pr/7", "approved": true}, {"url": "pr/8", "approved": false}]},
	"api": {"fingerprint": "sha-2", "name": "api", "pull_requests": []},
}}}

_chain_subjects := {
	"artifact": {"from": "trail.artifacts named by $params.name", "id": "fingerprint"},
	"pull request": {"from": "artifact.pull_requests", "id": "url"},
}

_chain_report(doc, subjects, checks, params) := ergo.report(doc, {"subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, params)

test_a_chain_reads_its_path_from_the_parents_one_subject_and_every_row_says_which if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	[[r.subject, r.check, r.cause] | some r in rep.results] == [
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$well_formed", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$min_subjects", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$unique_ids", "satisfied"],
		[{"type": "pull request", "id": "pr/7", "in": {"artifact": "sha-1"}}, "c", "satisfied"],
		[{"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "c", "value"],
	]
}

test_a_check_of_a_chain_reads_the_parent_by_its_name if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": `artifact.name is "web" and url exists`}, {"name": "web"})
	[[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "c"] == [
		["pr/7", "satisfied", [{"name": "artifact.name", "value": "web"}, {"name": "url", "value": "pr/7"}]],
		["pr/8", "satisfied", [{"name": "artifact.name", "value": "web"}, {"name": "url", "value": "pr/8"}]],
	]
}

_chain_min_cause(rep) := [[r.cause, object.keys(r.subject)] | some r in rep.results; r.check == "$min_subjects"]

test_a_chain_with_no_parent_or_several_or_an_unreadable_one_finds_no_subjects if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "api"})) == [["value", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "nope"})) == [["absent", {"type", "id"}]]
	many := {"artifact": {"from": "trail.artifacts", "id": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "id": "url"}}
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a"}, {"fingerprint": "b"}]}}, many, {"c": "url exists"}, {})) == [["unusable", {"type", "id"}]]
	kept := {"artifact": {"from": `trail.artifacts whose env is "prod"`, "id": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "id": "url"}}
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, kept, {"c": "url exists"}, {})) == [["value", {"type", "id"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a"}]}}, kept, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
	zero := _chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, kept, {"c": "url exists"}, {})
	zero.requirements.r.status == "not_met"
}

test_a_chain_whose_parent_is_written_wrong_is_written_wrong_too if {
	broken := {"artifact": {"from": "trail.artifacts whose", "id": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "id": "url"}}
	_from_problems(_chain_report(_chain_doc, broken, {"c": "url exists"}, {})) == [{"name": "subjects.artifact.from", "value": ["doesn't parse"]}]
	three := object.union(_chain_subjects, {"x": {"from": "artifact.pull_requests"}, "pull request": {"from": "x.reviews"}})
	_from_problems(_chain_report(_chain_doc, three, {"c": "url exists"}, {"name": "web"})) == [{"name": `subjects."pull request".from`, "value": ["a chain of more than two subjects isn't supported yet"]}]
}

test_a_from_line_that_starts_at_input_reads_the_input_and_one_at_params_is_written_wrong if {
	doc := {"ds": [{"id": 5}]}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "$input.ds whose id is 5", "id": "id"}}, {"c": "id exists"}, {}))] == [[5, "satisfied"], [5, "satisfied"]]
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "$input", "id": "ds"}}, {"c": "ds exists"}, {}))] == [[[{"id": 5}], "satisfied"]]
	_from_problems(_from_report(doc, {"d": {"from": "$params.ds"}}, {"c": "id exists"}, {"ds": [{"id": 1}]})) == [{"name": "subjects.d.from", "value": ["a from reads the input, so it can't start at $params"]}]
	both := ergo.report({"artifact": {"x": [{"id": 1}]}}, {"subjects": {"artifact": null, "d": {"from": "$input.artifact.x", "id": "id"}}, "requirements": {"r": {"subject": "d", "checks": {"c": "id exists"}}}}, {})
	[r.cause | some r in both.results; r.check == "c"] == ["satisfied"]
}

test_a_from_line_keeps_every_condition_past_a_hundred if {
	conds := concat(" and ", array.concat([`id is 1` | some _ in numbers.range(1, 100)], [`env is "prod"`]))
	rep := _from_report({"ds": [{"id": 1, "env": "dev"}]}, {"d": {"from": concat("", ["ds whose ", conds]), "id": "id"}}, {"c": "id exists"}, {})
	rep.requirements.r.status == "not_met"
	[r.cause | some r in rep.results; r.check == "$applies"] == ["value"]
	endswith(rep.requirements.r.checks["$applies"].expression, `and env is "prod"`)
}

test_a_from_line_can_start_with_a_quoted_key_that_starts_with_a_dollar if {
	[r[2] | some r in _from_rows(_from_report({"$schema": [{"id": 2}]}, {"d": {"from": `"$schema" whose id is 2`, "id": "id"}}, {"c": "id exists"}, {}))] == ["satisfied", "satisfied"]
}

test_a_from_line_next_to_of_adds_no_filters_of_its_own if {
	policy := {"subjects": {"d": {"from": "ds"}, "e": {"of": "d", "from": `ds whose t is "e"`}}, "requirements": {"r": {"subject": "e", "checks": {"c": "id exists"}}}}
	_from_problems(ergo.report({"ds": [{"id": 1}]}, policy, {})) == [{"name": "subjects.e.from", "value": ["not allowed with of"]}]
}

_defects := {"defects": [
	{"id": 1, "severity": "critical", "status": "open", "team": "a"},
	{"id": 2, "severity": "low", "status": "open", "team": "a"},
	{"id": 3, "severity": "critical", "status": "closed", "team": "b"},
	{"id": 4, "severity": "critical", "status": "open", "team": "b"},
]}

_narrow_report(subjects, name) := ergo.report(_defects, {"subjects": subjects, "requirements": {"r": {"subject": name, "checks": {"c": "id exists"}}}}, {})

_kept(rep) := [r.subject.id | some r in rep.results; r.check == "c"]

test_a_from_line_that_names_another_subject_narrows_it if {
	subjects := {"defect": {"from": "defects", "id": "id"}, "critical defect": {"from": `defect whose severity is "critical" and status is one of "open", "in_progress"`}}
	rep := _narrow_report(subjects, "critical defect")
	_kept(rep) == [1, 4]
	rep.requirements.r.checks["$applies"].expression == `severity is "critical" and status is one of "open", "in_progress"`
	_from_problems(rep) == []
	_kept(_narrow_report({"defect": {"from": "defects", "id": "id"}, "all": {"from": "defect"}}, "all")) == [1, 2, 3, 4]
}

test_a_chain_of_narrowing_subjects_prints_the_outer_conditions_first if {
	subjects := {
		"defect": {"from": "defects whose status exists", "id": "id"},
		"critical defect": {"from": `defect whose severity is "critical"`},
		"team b defect": {"from": `"critical defect" whose team is "b"`},
	}
	rep := _narrow_report(subjects, "team b defect")
	_kept(rep) == [3, 4]
	rep.requirements.r.checks["$applies"].expression == `status exists and severity is "critical" and team is "b"`
}

test_a_from_line_can_narrow_a_subject_written_with_op if {
	subjects := {"defect": {"from": ["defects"], "id": ["id"], "applies_to": {"open": {"op": "equals", "path": ["status"], "value": "open"}}}, "critical defect": {"from": `defect whose severity is "critical"`}}
	_kept(_narrow_report(subjects, "critical defect")) == [1, 4]
}

test_a_narrowing_subject_takes_its_id_from_the_one_it_narrows if {
	subjects := {"defect": {"from": "defects", "id": "id"}, "critical defect": {"from": `defect whose severity is "critical"`, "id": "team"}}
	_from_problems(_narrow_report(subjects, "critical defect")) == [{"name": `subjects."critical defect".id`, "value": ["not allowed with of"]}]
}

test_subjects_that_narrow_each_other_lead_to_a_loop if {
	rep := _narrow_report({"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}}, "x")
	_from_problems(rep) == [{"name": "subjects.x.from", "value": ["leads to a loop"]}]
}

test_a_narrowing_chain_through_of_prints_its_from_line_conditions_outer_first_and_its_applies_to_after if {
	subjects := {
		"defect": {"from": `defects whose status is "open"`, "id": "id"},
		"mid": {"of": "defect", "applies_to": {"0 mid": {"op": "equals", "path": ["severity"], "value": "critical"}}},
		"child": {"from": `mid whose team is "b"`},
	}
	rep := _narrow_report(subjects, "child")
	_kept(rep) == [4]
	rep.requirements.r.checks["$applies"].expression == `status is "open" and team is "b" and severity == "critical"`
}

test_a_narrowing_chain_deeper_than_ten_prints_in_order if {
	subjects := object.union({"s0": {"from": "defects whose id exists", "id": "id"}}, {concat("", ["s", format_int(n, 10)]): {"from": concat("", ["s", format_int(n - 1, 10), " whose id is not ", format_int(100 + n, 10)])} | some n in numbers.range(1, 11)})
	rep := _narrow_report(subjects, "s11")
	rep.requirements.r.checks["$applies"].expression == concat(" and ", array.concat(["id exists"], [concat("", ["id is not ", format_int(100 + n, 10)]) | some n in numbers.range(1, 11)]))
}

test_a_subject_name_that_isnt_a_string_gives_the_same_report_with_strict_builtins if {
	rep := ergo.report({"defects": [{"id": 1}]}, {"subjects": {1: {"from": "defects whose id exists"}}, "requirements": {"r": {"subject": "c", "checks": {"c": "id exists"}}}}, {})
	rep.requirements.r.status == "not_met"
}

test_a_chain_whose_parent_reads_a_param_it_cant_use_fails_with_that_cause if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": 5})) == [["unusable", {"type", "id"}]]
	gone := {"artifact": {"from": "trail.nope", "id": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "id": "url"}}
	_chain_min_cause(_chain_report(_chain_doc, gone, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
}

test_a_chain_keeps_the_problems_of_a_check_written_wrong if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": `url is "x`}, {"name": "web"})
	[i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [["unclosed quote at column 8"]]
}

test_every_and_some_in_a_check_of_a_chain_can_walk_the_parent if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "some artifact.pull_requests.approved is true"}, {"name": "web"})
	[r.cause | some r in rep.results; r.check == "c"] == ["satisfied", "satisfied"]
}

_review_doc := {"trail": {"artifacts": {"web": {
	"fingerprint": "sha-1",
	"owner": "ann",
	"pull_requests": [{"url": "pr/7", "approved": true, "reviews": [{"by": "ann", "ok": true}]}],
}}}}

test_the_parents_name_is_the_parent_everywhere_in_a_sentence if {
	every check in [
		{"for": "every artifact.pull_requests as p", "assert": "p.url exists"},
		{"for": "every reviews whose by is artifact.owner as r", "assert": "r.ok is true"},
		"every reviews whose by is artifact.owner exists",
		"every reviews.by is artifact.owner",
		"count of reviews whose by is artifact.owner is 1",
	] {
		[r.cause | some r in _chain_report(_review_doc, _chain_subjects, {"c": check}, {"name": "web"}).results; r.check == "c"] == ["satisfied"]
	}
}

test_a_subject_cant_build_on_a_subject_read_from_another_yet if {
	doc := {"artifacts": [{"fingerprint": "a1", "prs": [{"url": "p1", "ok": true}]}], "prs": [{"url": "elsewhere", "ok": true}]}
	base := {"artifact": {"from": "artifacts", "id": "fingerprint"}, "pr": {"from": "artifact.prs", "id": "url"}}
	every pair in [[{"from": "pr whose ok is true"}, "from"], [{"of": "pr"}, "of"]] {
		rep := ergo.report(doc, {"subjects": object.union(base, {"okpr": pair[0]}), "requirements": {"r": {"subject": "okpr", "checks": {"c": "url exists"}}}}, {})
		_from_problems(rep) == [{"name": concat("", ["subjects.okpr.", pair[1]]), "value": ["can't build on a subject read from another subject yet"]}]
		[r.check | some r in rep.results] == ["$well_formed", "$min_subjects", "$unique_ids"]
	}
}

test_the_parent_is_named_only_in_sentences_and_only_in_its_own_requirement if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": {"op": "present", "path": ["$artifact", "name"]}}, {"name": "web"})
	[i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [["unknown name $artifact"]]
	other := ergo.report({"things": [{"k": 1}], "trail": {"artifacts": {}}}, {"subjects": object.union(_chain_subjects, {"thing": {"from": ["things", {"each_as": "artifact"}]}}), "requirements": {"t": {"subject": "thing", "checks": {"c": {"op": "present", "path": ["$artifact", "k"]}}}}}, {"name": "web"})
	other.requirements.t.checks.c.expression == "$artifact.k is present"
	[r.inputs | some r in other.results; r.check == "c"] == [[{"name": "$artifact.k", "value": 1}]]
}

_persona_doc := {"things": [
	{"id": 1, "dispatched": ["security", "style"], "shas": {"security": "3f2a000000000000000000000000000000000000", "style": "9c1b000000000000000000000000000000000000"}},
	{"id": 2, "dispatched": ["security", "perf", 5], "shas": {"security": "x"}},
]}

test_named_by_a_name_from_the_for_line_reads_the_key_each_item_names if {
	check := {"for": "every dispatched as persona", "assert": `shas named by persona matches "^[0-9a-f]{40}$"`}
	rows := [[r.subject.id, r.cause, [[f.item, f.cause, f.failed_assertions] | some f in r.failed_items], r.inputs] | some r in ergo.report(_persona_doc, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [
		[1, "satisfied", [], [{"name": "dispatched[]", "value": ["security", "style"]}, {"name": "shas", "value": _persona_doc.things[0].shas}]],
		[
			2, "unusable", [
				["item 1 of dispatched", "value", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "value"}]],
				["item 2 of dispatched", "absent", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "absent"}]],
				["item 3 of dispatched", "unusable", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "unusable"}]],
			],
			[{"name": "dispatched[]", "value": ["security", "perf", 5]}, {"name": "shas", "value": {"security": "x"}}],
		],
	]
}

test_named_by_a_bare_word_that_isnt_a_for_name_is_an_unknown_name if {
	_sentence_problems("shas named by persona exists") == ["unknown name persona"]
	_sentence_problems({"for": "every dispatched as other", "assert": "shas named by persona exists"}) == ["unknown name persona"]
}

test_a_named_by_step_is_only_for_sentences if {
	_sentence_problems({"op": "present", "path": ["shas", {"named_by": "x"}]}) == ["step that can't be a key in path"]
	ergo.report({"things": []}, _sentence_policy({"c": {"op": "present", "path": ["shas", {"named_by": "x"}]}}), {}).requirements.s.checks.c.expression == "shas named by x is present"
}

test_named_by_a_for_name_in_the_second_items_path_reads_the_first_items_key if {
	check := {"for": "every ys as y, every xs named by y as x", "assert": "x is 1"}
	rows := [[r.subject.id, r.cause] | some r in ergo.report({"things": [{"id": 1, "xs": {"a": [1], "b": [2]}, "ys": ["a"]}, {"id": 2, "xs": {"a": [1], "b": [2]}, "ys": ["a", "b"]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [[1, "satisfied"], [2, "value"]]
}

test_named_by_a_for_name_before_it_is_given_is_an_unknown_name if {
	_sentence_problems({"for": "every xs named by x as x", "assert": "x is 1"}) == ["unknown name x"]
	_sentence_problems({"for": "every lists named by q as p, every qs as q", "assert": "p is 1"}) == ["unknown name q"]
	_sentence_problems({"for": "every objs whose v named by o is 1 as o", "assert": "o exists"}) == ["unknown name o"]
}

test_named_by_a_for_name_that_holds_no_text_fails_with_its_cause if {
	check := {"for": "every dispatched as p", "assert": "shas named by p exists"}
	rows := [[r.subject.id, r.cause] |
		some r in ergo.report(
			{"things": [
				{"id": 1, "dispatched": [null], "shas": {"a": "x"}},
				{"id": 2, "dispatched": [{"k": 1}], "shas": {"a": "x"}},
				{"id": 3, "dispatched": [0], "shas": ["only"]},
			]},
			_sentence_policy({"c": check}), {},
		).results
		r.check == "c"
	]
	rows == [[1, "null"], [2, "unusable"], [3, "unusable"]]
}

test_a_from_line_named_by_a_bare_word_is_an_unknown_name if {
	_from_problems(_from_report({"m": {}}, {"x": {"from": "m named by k"}}, {"c": "id exists"}, {})) == [{"name": "subjects.x.from", "value": ["unknown name k"]}]
}

test_every_and_count_through_a_for_name_arent_listed_as_inputs_since_they_change_with_each_item if {
	doc := {"things": [{"id": 1, "ps": ["a"], "xs": [{"k": {"a": 1}}], "ys": [{"m": {"a": 1}}]}]}
	every check in [
		{"for": "every ps as p", "assert": "every xs.k named by p is 1"},
		{"for": "every ps as p", "assert": "count of ys whose m named by p is 1 is 1"},
	] {
		[[r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [["satisfied", [{"name": "ps[]", "value": ["a"]}]]]
	}
}

_old_policy := {
	"subjects": {"deployment": {
		"from": ["deployments"],
		"id": ["id"],
		"applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
	}},
	"requirements": {"approved": {"subject": "deployment", "checks": {
		"approved": {"op": "non_empty_string", "path": ["approved_by"], "description": "Someone approved it"},
		"region": {"op": "in", "path": ["region"], "values": ["eu", "us"]},
		"later": {"op": "compare_time", "left": ["deployed_at"], "right": ["approved_at"], "cmp": "gt"},
		"signed": {"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["signed"], "value": true}},
	}}},
}

test_as_sentences_writes_null_as_is_null_because_it_reads_back_the_same if {
	ergo.as_sentences({"requirements": {"r": {"checks": {"c": {"op": "equals", "path": ["x"], "value": null}}}}}).requirements.r.checks.c == "x is null"
}

test_as_sentences_rewrites_each_check_and_subject_it_can_as_a_sentence if {
	ergo.as_sentences(_old_policy) == {
		"subjects": {"deployment": {"from": `deployments whose environment is "prod"`, "id": "id"}},
		"requirements": {"approved": {"subject": "deployment", "checks": {
			"approved": {"description": "Someone approved it", "assert": "approved_by is a non-empty string"},
			"region": `region is one of "eu", "us"`,
			"later": "deployed_at is after approved_at",
			"signed": _old_policy.requirements.approved.checks.signed,
		}}},
	}
}

test_as_sentences_leaves_what_doesnt_read_back_the_same_as_written if {
	every check in [
		{"op": "all", "path": ["xs"], "check": {"op": "present", "path": ["k"]}},
		{"op": "empty", "path": ["x"]},
		{"op": "present", "path": ["x"], "substitute": {"op": "present", "path": ["y"]}},
		{"op": "even", "path": ["x"]},
		{"op": "compare", "left": {"count": ["xs"]}, "cmp": "eq", "right": {"literal": 1}},
		{"op": "present", "path": ["x"], "expression": "x is there"},
		"x exists",
		5,
	] {
		ergo.as_sentences({"requirements": {"r": {"checks": {"c": check}}}}).requirements.r.checks.c == check
	}
}

test_as_sentences_writes_input_before_a_from_that_starts_like_another_subject if {
	policy := {"subjects": {"artifact": {"from": ["artifact"]}, "pr": {"from": ["artifact", "prs"], "id": ["url"]}}}
	ergo.as_sentences(policy).subjects == {"artifact": {"from": "artifact"}, "pr": {"from": "$input.artifact.prs", "id": "url"}}
}

test_as_sentences_writes_naming_and_whole_input_and_narrowing_as_from_lines if {
	policy := {"subjects": {
		"all": {"from": []},
		"run": {"from": ["build", "runs", {"each_as": "subject", "keys": {"ref": ["$$params", "kinds"]}}]},
		"one": {"from": ["build", "runs", {"ref": ["$$params", "kind"]}]},
		"named": {"from": ["build", "runs", {"each_as": "r"}]},
		"$x": {"from": ["$x"]},
		"narrow": {"of": "run", "applies_to": {"b": {"op": "present", "path": ["b"]}, "a": {"op": "present", "path": ["a"]}}},
		"filtered": {"from": ["xs"], "applies_to": {"f": {"op": "present", "path": ["a"], "description": "kept"}}},
	}}
	ergo.as_sentences(policy).subjects == {
		"all": {"from": "$input"},
		"run": {"from": "build.runs named by each of $params.kinds"},
		"one": {"from": "build.runs named by $params.kind"},
		"named": policy.subjects.named,
		"$x": {"from": `"$x"`},
		"narrow": {"from": "run whose .a exists and b exists"},
		"filtered": policy.subjects.filtered,
	}
}

test_as_sentences_keeps_sections_that_arent_objects_and_other_fields if {
	ergo.as_sentences({"requirements": ["x"], "subjects": 5, "other": 1}) == {"requirements": ["x"], "subjects": 5, "other": 1}
	ergo.as_sentences("x") == "x"
	ergo.as_sentences({"requirements": {"r": 1, "s": {"checks": []}}}) == {"requirements": {"r": 1, "s": {"checks": []}}}
}

test_a_policy_as_sentences_gives_the_same_verdicts_on_every_spec_case if {
	every topic in ["compare", "compare_time", "contains", "empty", "equals", "in", "missing", "non_empty_string", "patterns", "present", "range", "requirements", "substitutes"] {
		every group in data.spec.cases[topic] {
			every c in group.cases {
				_verdicts(ergo.report(c.input, group.policy, object.get(group, "params", {}))) == _verdicts(ergo.report(c.input, ergo.as_sentences(group.policy), object.get(group, "params", {})))
			}
		}
	}
}

_verdicts(rep) := {"rows": {[r.requirement, r.subject, r.check, r.passed, r.cause] | some r in rep.results}, "status": {[n, req.status] | some n, req in rep.requirements}}

test_as_sentences_writes_compares_with_a_value_and_within if {
	checks := {
		"a": {"op": "compare", "left": ["x"], "cmp": "eq", "right": {"literal": 1}, "within": 0.5},
		"b": {"op": "compare", "left": ["x"], "cmp": "gte", "right": {"literal": 2}},
		"c": {"op": "compare", "left": ["x"], "cmp": "eq", "right": ["y"], "within": 0.5},
	}
	ergo.as_sentences({"requirements": {"r": {"checks": checks}}}).requirements.r.checks == {"a": "x equals 1 within 0.5", "b": "x is at least 2", "c": "x equals y within 0.5"}
}

test_as_sentences_keeps_a_naming_step_a_from_line_cant_write_the_same if {
	every step in [
		{"each_as": "pr", "keys": {"ref": ["$$params", "names"]}},
		{"each_as": "subject", "keys": {"ref": ["$$params", "names"]}, "zz": 1},
		{"keys": {"ref": ["$$params", "names"]}},
	] {
		subjects := {"pr": {"from": ["prs", step]}}
		ergo.as_sentences({"subjects": subjects}).subjects == subjects
	}
}

test_as_sentences_narrows_only_with_an_of_that_names_another_subject if {
	subjects := {
		"$x": {"from": ["deployments"]},
		"a": {"of": "$x", "applies_to": {"f": {"op": "present", "path": ["id"]}}},
		"b": {"of": "deployments", "applies_to": {"f": {"op": "present", "path": ["id"]}}},
		"c": {"of": ""},
	}
	converted := ergo.as_sentences({"subjects": subjects}).subjects
	[converted.a, converted.b, converted.c] == [subjects.a, subjects.b, subjects.c]
}

test_as_sentences_leaves_the_checks_of_a_subject_read_from_another if {
	policy := {
		"subjects": {"d": {"from": "deployments"}, "c": {"from": "d.commits"}},
		"requirements": {"r": {"subject": "c", "checks": {"k": {"op": "present", "path": ["d", "v"]}}}},
	}
	ergo.as_sentences(policy).requirements == policy.requirements
}
