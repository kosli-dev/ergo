package ergo_test

import data.ergo
import rego.v1

solo(subj, check) := ergo.report(
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

subject_counts(doc, from) := ergo.report(doc, id_req(from)).requirements.s.subjects

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
	rows := rows_for(ergo.report(mixed_subjects, mixed_req), "s", "c")
	[[r.subject.id, r.passed, r.cause] | some r in rows] == [
		["x", true, "satisfied"],
		["b", false, "not_an_object"],
		[null, false, "not_an_object"],
		[3, false, "not_an_object"],
	]
}

test_a_subject_that_is_not_an_object_shows_up_as_a_violation if {
	count(ergo.violations(ergo.report(mixed_subjects, mixed_req))) == 3
}

test_a_subject_that_is_not_an_object_keeps_its_applies_row if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"kind": {"op": "equals", "path": ["kind"], "value": "lib"}},
		"checks": {"c": {"op": "present", "path": ["n"]}},
	}}
	rep := ergo.report({"items": ["b"]}, req)
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [["b", false, "not_an_object"]]
	{v.check | some v in ergo.violations(rep)} == {"$applies", "$min_subjects"}
}

test_a_subject_that_is_not_an_object_is_not_mistaken_for_one_missing_its_fields if {
	causes := {r.subject.id: r.cause | some r in rows_for(ergo.report({"items": [{"id": "x"}, "b"]}, mixed_req), "s", "c")}
	causes == {"x": "value", "b": "not_an_object"}
}

test_a_subject_that_is_not_an_object_fails_a_quantified_check_as_not_an_object if {
	req := {"s": {"from": ["items"], "checks": {"c": {"op": "all", "path": ["commits"], "check": {"op": "present", "path": ["sha"]}}}}}
	[r.cause | some r in rows_for(ergo.report({"items": ["b"]}, req), "s", "c")] == ["not_an_object"]
}

test_an_id_path_can_use_a_selector if {
	req := {"s": {
		"from": ["items"],
		"id": ["tags", {"where": {"k": "name"}}, "v"],
		"checks": {"c": {"op": "present", "path": ["tags"]}},
	}}
	[r.subject.id | some r in rows_for(ergo.report({"items": [{"tags": [{"k": "name", "v": "web"}]}]}, req), "s", "c")] == ["web"]
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
	rep := ergo.report({"items": [{"no_id_here": 1}]}, id_req(["items"]))
	some row in rep.results
	row.subject == {"type": "thing", "id": null}
}

test_subject_id_is_read_from_the_declared_path if {
	rep := ergo.report({"items": [{"id": "abc"}]}, id_req(["items"]))
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
	rep := ergo.report(two_states, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_checks_are_conjunctive if {
	both := object.union(merged_only, {"on_main": {"op": "equals", "path": ["base_ref"], "value": "main"}})
	doc := {"items": [
		{"id": "a", "state": "MERGED", "base_ref": "main"},
		{"id": "b", "state": "MERGED", "base_ref": "topic"},
	]}
	rep := ergo.report(doc, scoped_req(both))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_excludes_subjects_whose_filtered_field_is_missing if {
	rep := ergo.report({"items": [{"id": "a"}]}, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
}

test_empty_applies_to_matches_everything if {
	rep := ergo.report(two_states, scoped_req({}))
	rep.requirements.s.subjects == {"total": 2, "matching": 2}
}

test_applies_to_is_evaluated_for_every_raw_subject if {
	rep := ergo.report(two_states, scoped_req(merged_only))
	verdicts := {r.subject.id: r.passed |
		some r in rep.results
		r.check == "$applies"
	}
	verdicts == {"a": true, "b": false}
}

test_applies_row_echoes_the_field_the_filter_read if {
	rep := ergo.report(two_states, scoped_req(merged_only))
	some r in rep.results
	r.check == "$applies"
	r.subject.id == "b"
	r.inputs == [{"name": "state", "value": "CLOSED"}]
}

test_applies_definition_renders_the_filter_expression if {
	rep := ergo.report(two_states, scoped_req(merged_only))
	rep.requirements.s.checks["$applies"].expression == `state == "MERGED"`
}

test_applies_definition_conjoins_multiple_filter_checks if {
	both := object.union(merged_only, {"on_main": {"op": "equals", "path": ["base_ref"], "value": "main"}})
	rep := ergo.report(two_states, scoped_req(both))

	rep.requirements.s.checks["$applies"].expression == `state == "MERGED" and base_ref == "main"`
}

test_no_applies_to_means_no_applies_rows_or_definition if {
	rep := ergo.report(two_states, id_req(["items"]))
	count([r | some r in rep.results; r.check == "$applies"]) == 0
	not "$applies" in object.keys(rep.requirements.s.checks)
}

test_out_of_scope_subject_gets_no_check_rows if {
	rep := ergo.report(two_states, scoped_req(merged_only))
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

test_includes_and_excludes_take_a_set_of_values if {
	verdict({"sign_offs": ["security", "qa"]}, object.union(all_signed_off, {"values": {"qa", "security"}})) == true
	verdict({"allergens": ["garlic"]}, object.union(no_allergens, {"values": {"nuts", "garlic"}})) == false
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
		every values in [[], set()] {
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
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

test_in_fails_closed_on_an_empty_set if verdict({"id": "MIT"}, {"op": "in", "path": ["id"], "values": set()}) == false

test_in_accepts_a_set_of_values if {
	check := {"op": "in", "path": ["id"], "values": {"MIT", "Apache-2.0"}}
	verdict({"id": "MIT"}, check) == true
	verdict({"id": "GPL-3.0"}, check) == false
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
	rep := ergo.report({"items": [{"id": "a", "build": "abc"}]}, scoped_req({"built": {"op": "present", "path": ["build", "fingerprint"]}}))
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "unusable"]]
	rep.compliant == false
}

test_a_present_filter_still_rules_out_a_subject_whose_selector_has_no_list if {
	rep := ergo.report({"items": [{"id": "a"}]}, scoped_req({"f": {"op": "present", "path": ["xs", {"where": {"k": 1}}, "v"]}}))
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
}

test_missing_reads_names_given_by_as if {
	check := {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "missing", "path": ["$x", "b"]}}
	verdict({"xs": [{"a": 1}, {}]}, check) == true
	verdict({"xs": [{"a": 1}, {"b": 2}]}, check) == false
}

test_missing_fails_on_a_subject_that_is_not_an_object if {
	rep := ergo.report({"items": ["abc"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "missing", "path": ["v"]}}}})
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
	rep := ergo.report(doc, scoped_req(prod))
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [["a", true, "satisfied"], ["b", true, "satisfied"], ["c", false, "value"]]
	rep.compliant == true
}

test_a_missing_filter_rules_a_subject_with_the_field_out if {
	rep := ergo.report({"items": [{"id": "a", "draft": true}, {"id": "b"}]}, scoped_req({"final": {"op": "missing", "path": ["draft"]}}))
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

service_accounts := {"svc_.*", `.*\[bot\]`, `noreply@github\.com`}

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
	check := {"op": "not_matches_any", "path": ["author"], "patterns": {"svc_.*", 42}}
	verdict({"author": "Alice <alice@example.com>"}, check) == false
}

test_matches_any_fails_on_a_non_string_pattern_even_when_another_matches if {
	check := {"op": "matches_any", "path": ["author"], "patterns": {"svc_.*", 42}}
	verdict({"author": "svc_bot"}, check) == false
	cause_of({"author": "svc_bot"}, check) == "ill_formed"
}

test_matching_with_no_patterns if {
	verdict({"author": "Alice"}, {"op": "matches_any", "path": ["author"], "patterns": set()}) == false
	verdict({"author": "Alice"}, {"op": "not_matches_any", "path": ["author"], "patterns": set()}) == true
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
	rendered({"pairs": []}, {"op": "all", "path": ["pairs"], "check": {"op": "compare", "cmp": "eq", "left": [], "right": [0]}}) == "every pairs: pairs[] eq 0"
}

test_an_inner_check_without_a_path_names_the_item_after_its_list if {
	check := {"op": "all", "path": ["pairs"], "check": {"op": "compare", "cmp": "eq", "left": ["a"], "right": ["b"]}}
	inputs_of({"pairs": [{"a": 1, "b": 1}]}, check) == [{"name": "pairs[]", "value": [{"a": 1, "b": 1}]}]
}

branch_req(check) := {"s": {"from": ["branches"], "checks": {"c": check}}}

on_main := {"op": "matches_any", "path": [], "patterns": ["^main$"]}

branch_rows(check) := [[r.subject.id, r.passed, r.cause] |
	some r in rows_for(ergo.report({"branches": ["main", "feature", null]}, branch_req(check)), "s", "c")
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
	rep := ergo.report({"branches": ["main"]}, branch_req(on_main))
	rep.requirements.s.checks.c.expression == `branches[] matches one of ["^main$"]`
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "branches[]", "value": "main"}]]
}

test_an_empty_path_on_the_whole_input_is_named_dollar_dollar_input if {
	rep := ergo.report({"state": "ok"}, {"s": {"checks": {"c": {"op": "present", "path": []}}}})
	rep.requirements.s.checks.c.expression == "$$input is present"
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "$$input", "value": {"state": "ok"}}]]
}

test_the_whole_input_is_not_named_like_a_key_called_input if {
	rep := ergo.report({"input": "inner"}, {"s": {"checks": {"c": {"op": "any_of", "options": {
		"a": [{"op": "present", "path": []}],
		"b": [{"op": "present", "path": ["input"]}],
	}}}}})
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[
		{"name": "$$input", "value": {"input": "inner"}},
		{"name": "input", "value": "inner"},
	]]
}

test_an_empty_path_on_a_subject_is_named_after_from_in_every_kind_of_check if {
	rep := ergo.report({"branches": ["main"]}, {"s": {
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
		"backed": [{"name": "branches[]", "value": "main"}, {"name": "branches[]", "value": "main"}],
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
	rep := ergo.report(
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
	rendered({}, {"op": "any_of", "options": {"standard": []}}) == "one of: standard()"
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
	rep := ergo.report(
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
	rep := ergo.report({"items": [{"id": "a", "internal": true}]}, {"s": {
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
	inputs_of({"a": {"b": 1}}, check) == [{"name": "a.b", "value": 1}]
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
	rendered({}, {"op": "present", "path": ["xs", 0]}) == `xs.0 is present`
}

test_an_empty_key_is_quoted if {
	rendered({}, {"op": "present", "path": ["a", "", "b"]}) == `a."".b is present`
}

test_a_key_with_a_quote_is_escaped if {
	rendered({}, {"op": "present", "path": [`say "hi"`]}) == `"say \"hi\"" is present`
}

test_a_plain_key_with_a_dash_or_dollar_is_not_quoted if {
	rendered({}, {"op": "present", "path": ["pull-request", "$schema_x"]}) == `pull-request.$schema_x is present`
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
		{"name": "a.b", "value": "nested"},
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
		{"name": "a", "value": 1},
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

test_expression_for_in_sorts_a_set_of_values if {
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"MIT", "Apache-2.0"}}) == `id in ["Apache-2.0", "MIT"]`
}

test_expression_for_in_does_not_list_values_it_will_not_match if {
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"licence": "MIT"}}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": "MIT"}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": null}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"]}) == "id in <missing values>"
}

test_expression_for_matches_any_does_not_list_patterns_it_will_not_match if {
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"p": "x"}}) == "a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": "x"}) == "a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"literal": "x"}}) == "a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": null}) == "a matches one of <invalid patterns>"
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"]}) == "a matches one of <missing patterns>"
}

test_expression_for_not_matches_any_does_not_list_patterns_it_will_not_match if {
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"], "patterns": "x"}) == "a matches none of <invalid patterns>"
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"], "patterns": null}) == "a matches none of <invalid patterns>"
	rendered({"a": "x"}, {"op": "not_matches_any", "path": ["a"]}) == "a matches none of <missing patterns>"
}

test_expression_for_matches_any_lists_a_literal_list_of_patterns if {
	rendered({"a": "x"}, {"op": "matches_any", "path": ["a"], "patterns": {"literal": ["y", "x"]}}) == `a matches one of ["x", "y"]`
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

test_a_byte_order_mark_in_subject_type_and_from_is_written_as_is if {
	min_subjects := ergo.report({"i\ufeff": [{"id": 1}]}, {"s": {
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
	rep := ergo.report({"xs": []}, {"s": {"from": ["xs"], "min_subjects": 2.0, "checks": {"c": {"op": "present", "path": ["x"]}}}})
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(xs)) >= 2"
}

test_a_step_that_cannot_be_a_key_is_named_apart_from_a_key_that_looks_like_it if {
	rendered({}, {"op": "present", "path": ["a", true]}) == "a.<invalid step> is present"
	rendered({}, {"op": "present", "path": ["a", "true"]}) == "a.true is present"
}

bad_steps := [true, null, ["a"], 1.5, -1, 1.0, 1e0, {"literal": true}, {"literal": -1}]

test_a_present_filter_with_a_step_that_cannot_be_a_key_cannot_rule_subjects_out if {
	rows := [[rep.requirements.s.satisfied, r.passed, r.cause] |
		some seg in bad_steps
		rep := ergo.report({"xs": [{"id": 1, "a": [1, 2]}]}, {"s": {
			"from": ["xs"],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": {"op": "present", "path": ["a", seg]}},
			"checks": {"c": {"op": "present", "path": ["id"]}},
		}})
		some r in rows_for(rep, "s", "$applies")
	]
	rows == [[false, false, "ill_formed"] | some _ in bad_steps]
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
	rendered({}, {"op": "present", "path": ["a", 1]}) == "a.1 is present"
}

test_a_ref_step_that_reads_something_that_cannot_be_a_key_fails_as_unusable if {
	check := {"op": "present", "path": ["a", {"ref": ["$$params", "i"]}]}
	params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check) == [[true, "satisfied", [{"name": "a.[$$params.i]", "value": 2}]]] with data.params as {"i": 1}
	r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": -1}
	[r[0], r[1]] == [false, "unusable"]
	s := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 1.0}
	[s[0], s[1]] == [false, "unusable"]
}

test_a_from_or_id_with_a_step_that_cannot_be_a_key_is_not_well_formed if {
	rows := [r.passed |
		some m in [{"from": ["xs", true]}, {"from": ["xs", 1.0, {"each_as": "x"}]}, {"id": ["id", null]}]
		rep := ergo.report({"xs": [{"id": 1}]}, {"s": object.union({"from": ["xs"], "checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
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
		rep := ergo.report({"xs": [{"id": 1}]}, {"s": object.union({"from": ["xs"], "checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [["$well_formed", false], ["$well_formed", false], ["$well_formed", false]]
}

test_min_subjects_is_described_like_any_number if {
	rep := ergo.report({"xs": []}, {"s": {"from": ["xs"], "min_subjects": 2.0, "checks": {"c": {"op": "present", "path": ["x"]}}}})
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

test_expression_for_compare if rendered({}, compare_ab("lt")) == "a lt b"

test_expression_for_compare_time if rendered(span, compare_time_span("lt")) == "start lt end"

test_expression_for_all if rendered({"commits": []}, all_verified) == "every commits: verified == true"

test_expression_for_any if rendered({"approvers": []}, any_approved) == `some approvers: state == "APPROVED"`

test_expression_for_nested_paths_is_dotted if {
	check := {"op": "equals", "path": ["a", "b"], "value": 1}
	rendered({}, check) == "a.b == 1"
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
	rep := ergo.report(doc, two_check_req)
	count([r | some r in rep.results; not startswith(r.check, "$")]) == 4

	count(rep.results) == 6
}

test_row_carries_exactly_the_documented_keys if {
	every row in solo({"state": "MERGED"}, is_merged).results {
		object.keys(row) == {"requirement", "subject", "check", "inputs", "passed", "cause"}
	}
}

test_rows_are_produced_even_for_an_empty_subject if {
	rep := ergo.report({"items": [{}]}, two_check_req)
	check_rows := [r | some r in rep.results; not startswith(r.check, "$")]
	count(check_rows) == 2
	every row in check_rows {
		row.passed == false
	}
}

test_unknown_op_produces_a_failing_row_not_a_gap if {
	verdict({"id": "x"}, {"op": "no_such_op", "path": ["id"]}) == false
}

test_subject_type_defaults_to_subject if {
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
		"from": ["items"],
		"checks": {"c": has_fingerprint},
	}})
	rep.results[0].subject.type == "subject"
}

test_rows_from_different_requirements_are_labelled_separately if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	rep := ergo.report(doc, policy)
	count(rows_for(rep, "first", "c")) == 1
	count(rows_for(rep, "second", "c")) == 1
}

test_requirement_name_is_the_policy_key if {
	rep := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
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
		[{"a": 3}, {"op": "equals", "path": ["id"], "value": 0, "inputs": [["a", "b"]]}],
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
	rep := ergo.report({"items": []}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "present", "path": ["x"]}},
	}})
	rows_for(rep, "s", "$well_formed")[0].cause == "satisfied"
	rows_for(rep, "s", "$min_subjects")[0].cause == "value"
}

test_an_applies_row_carries_the_state_of_the_filter_paths if {
	rep := ergo.report({"items": [{"id": "a", "env": "prod"}, {"id": "b"}]}, {"s": {
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
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
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

test_min_subjects_satisfied if {
	rep := ergo.report({"items": [{"id": "a"}]}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.satisfied == true
}

test_min_subjects_violated_fails_the_requirement if {
	rep := ergo.report({"items": []}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == false
	rep.requirements.s.satisfied == false
	rep.compliant == false
}

test_min_subjects_row_has_a_null_subject_id if {
	rep := ergo.report({"items": []}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].subject == {"type": "thing", "id": null}
}

test_min_subjects_definition_is_in_the_check_table if {
	rep := ergo.report({"items": []}, min_subjects_req(2))
	def := rep.requirements.s.checks["$min_subjects"]
	def.description == "The in-scope thing count is at least 2"
	def.expression == "count(matching(items)) >= 2"
}

test_min_subjects_defaults_to_one if {
	rep := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_min_subjects_zero_permits_an_empty_collection if {
	rep := ergo.report({"items": []}, min_subjects_req(0))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.satisfied == true
}

test_min_subjects_counts_subjects_after_the_applies_to_filter if {
	both := {"s": object.union(min_subjects_req(2).s, {"applies_to": merged_only})}
	rep := ergo.report(two_states, both)
	rows_for(rep, "s", "$min_subjects")[0].passed == false
}

test_min_subjects_guards_a_missing_collection if {
	rep := ergo.report({}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == false
	rep.compliant == false
}

test_well_formed_passes_for_an_ordinary_requirement if {
	rep := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_well_formed_fails_when_no_checks_are_declared if {
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.satisfied == false
}

test_well_formed_fails_on_an_unrecognised_require_value if {
	rep := ergo.report(both_ok, require_req("most"))
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.satisfied == false
}

test_well_formed_row_is_about_the_requirement_not_a_subject if {
	rep := ergo.report({"items": [{"id": "a"}, {"id": "b"}]}, id_req(["items"]))
	count(rows_for(rep, "s", "$well_formed")) == 1
	rows_for(rep, "s", "$well_formed")[0].subject == {"type": "thing", "id": null}
}

test_well_formed_does_not_depend_on_the_input if {
	with_items := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
	without := ergo.report({}, id_req(["items"]))
	rows_for(with_items, "s", "$well_formed")[0] == rows_for(without, "s", "$well_formed")[0]
}

test_well_formed_echoes_the_declaration_it_read if {
	rep := ergo.report(both_ok, require_req("most"))
	rows_for(rep, "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2},
		{"name": "require", "value": "most"},
	]
}

test_a_requirement_that_is_not_an_object_stays_in_the_report_and_is_not_well_formed if {
	rows := [[name in object.keys(rep.requirements), rep.requirements[name].satisfied, r.passed, r.inputs[2]] |
		some [name, req] in [["a", 5], ["b", null], ["c", [1]], ["d", "x"]]
		rep := ergo.report({"items": [{"id": 1}]}, {name: req})
		some r in rows_for(rep, name, "$well_formed")
	]
	rows == [
		[true, false, false, {"name": "requirement", "value": 5}],
		[true, false, false, {"name": "requirement", "value": null}],
		[true, false, false, {"name": "requirement", "value": [1]}],
		[true, false, false, {"name": "requirement", "value": "x"}],
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
	["from", "items"],
	["from", {"a": 1}],
	["from", null],
	["id", "id"],
	["id", null],
	["min_subjects", "0"],
	["min_subjects", null],
	["min_subjects", -1],
	["min_subjects", 0.5],
	["min_subjects", 1.5],
	["subject_type", 3],
	["subject_type", {"name": "x"}],
	["subject_type", null],
]

test_a_min_subjects_whose_value_is_a_whole_number_is_well_formed_however_it_is_written if {
	rows := [r.passed |
		some m in [0, 2.0, 1e2]
		rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [true, true, true]
}

test_a_field_of_the_wrong_type_fails_well_formed_and_shows_its_value if {
	rows := [[f, "s" in object.keys(rep.requirements), rep.requirements.s.satisfied, r.passed, r.cause, r.inputs[count(r.inputs) - 1]] |
		some [f, v] in wrong_types
		rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {f: v})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [[f, true, false, false, "value", {"name": f, "value": v}] | some [f, v] in wrong_types]
}

test_a_requirement_that_is_not_an_object_finds_no_subjects_so_it_cannot_claim_the_whole_input if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": 5})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "value"]]
}

test_a_from_that_is_not_a_list_records_no_refs_because_it_is_never_read if {
	rep := ergo.report({}, {"s": object.union(typed_req, {"from": {"ref": ["$$params", "p"]}})})
	not "$refs" in object.keys(rep.requirements.s.checks["$min_subjects"])
}

test_an_applies_to_that_is_not_an_object_fails_every_subject_as_ill_formed_so_none_is_blamed_for_a_check if {
	doc := {"items": [{"id": 1, "env": "dev"}, {"id": 2, "env": "prod"}]}
	reps := [ergo.report(doc, {"s": object.union(typed_req, {"applies_to": a})}) |
		some a in [[{"op": "equals", "path": ["env"], "value": "prod"}], true, null]
	]
	every rep in reps {
		[[r.check, r.subject.id, r.passed, r.cause, r.inputs] | some r in rep.results; not r.check in {"$well_formed", "$min_subjects"}] == [
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
	rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"applies_to": {"a": {"op": "present", "path": ["id"]}}})})
	row := rows_for(rep, "s", "$well_formed")[0]
	[row.passed, count(row.inputs)] == [true, 2]
}

test_checks_that_are_not_an_object_give_no_rows_named_by_list_index if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"checks": [{"op": "present", "path": ["id"]}]})})
	[r.check | some r in rep.results] == ["$well_formed", "$min_subjects"]
	rows_for(rep, "s", "$well_formed")[0].inputs[0] == {"name": "count(checks)", "value": 0}
}

test_a_from_that_is_not_a_list_gives_no_subjects if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": "items", "min_subjects": 1})})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

test_an_id_that_is_not_a_list_gives_a_null_id if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"id": "id"})})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == [null]
}

test_a_min_subjects_that_is_not_a_number_fails_min_subjects_whatever_opa_thinks_of_comparing_it if {
	rows := [[r.passed, r.cause] |
		some m in ["0", null, [], {}]
		rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})})
		some r in rows_for(rep, "s", "$min_subjects")
	]
	rows == [[false, "value"], [false, "value"], [false, "value"], [false, "value"]]
}

test_min_subjects_names_the_whole_input_like_the_checks_do_when_from_reads_it if {
	rows := [[d.expression, r.inputs[0].name] |
		some m in [{}, {"from": []}, {"from": [{"each_as": "x"}]}]
		rep := ergo.report({"id": 1}, {"s": object.union({"checks": {"c": {"op": "present", "path": ["id"]}}}, m)})
		d := rep.requirements.s.checks["$min_subjects"]
		some r in rows_for(rep, "s", "$min_subjects")
	]
	rows == [
		["count(matching($$input)) >= 1", "in-scope subject count"],
		["count(matching($$input)) >= 1", "in-scope subject count"],
		["count(matching($$input)) >= 1", "in-scope subject count"],
	]
}

test_a_from_starting_with_a_dollar_key_is_quoted_because_from_takes_no_names_or_input if {
	rows := [[rep.requirements.s.checks["$min_subjects"].expression, rep.requirements.s.checks.c.expression] |
		some f in [["$$input"], ["$x", "a"], ["$schema", {"each_as": "x"}]]
		rep := ergo.report({}, {"s": {"from": f, "checks": {"c": {"op": "present", "path": []}}}})
	]
	rows == [
		[`count(matching("$$input")) >= 1`, `"$$input"[] is present`],
		[`count(matching("$x".a)) >= 1`, `"$x".a[] is present`],
		[`count(matching("$schema")) >= 1`, "$x is present"],
	]
}

problem_inputs(rep) := [i | some i in rows_for(rep, "s", "$well_formed")[0].inputs; not i.name in {"count(checks)", "require", "from"}]

test_a_badly_written_check_fails_well_formed_and_says_where_and_what if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"applies_to": {"is_prod": {"op": "equals", "path": ["env"]}},
		"checks": {"merged": {"op": "equls", "path": ["state"], "value": "MERGED"}, "fine": {"op": "present", "path": ["id"]}},
	}})
	r := rows_for(rep, "s", "$well_formed")[0]
	[r.passed, r.cause] == [false, "value"]
	problem_inputs(rep) == [
		{"name": "applies_to.is_prod", "value": ["missing value"]},
		{"name": "checks.merged", "value": ["unknown op equls"]},
	]
}

test_a_problem_inside_a_check_is_named_by_where_it_sits if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {
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

test_a_check_with_several_problems_lists_them_in_order if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "range", "path": ["n", 1e400], "min": 9, "max": 1}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["min above max", "number out of range", "step that can't be a key in path"]}]
}

_within(name, base) if name == base

_within(name, base) if startswith(name, concat("", [base, "."]))

test_every_badly_written_check_fails_well_formed if {
	checks := {sprintf("c%d", [i]): c | some i, c in badly_written}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": checks}})
	rows_for(rep, "s", "$well_formed")[0].passed == false
	every i, _ in badly_written {
		some p in problem_inputs(rep)
		_within(p.name, sprintf("checks.c%d", [i]))
	}
}

test_a_ref_that_reads_the_wrong_kind_of_value_leaves_well_formed_alone_because_params_are_input if {
	every check in read_the_wrong_kind {
		rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		rows_for(rep, "s", "$well_formed")[0].passed == true
	}
}

test_a_name_given_by_from_is_known_and_any_other_is_not if {
	good := ergo.report({"prs": [{"n": 1}]}, {"s": {"from": ["prs", {"each_as": "pr"}], "id": ["n"], "checks": {"c": {"op": "present", "path": ["$pr", "n"]}}}})
	bad := ergo.report({"prs": [{"n": 1}]}, {"s": {"from": ["prs", {"each_as": "pr"}], "id": ["n"], "checks": {"c": {"op": "present", "path": ["$p", "n"]}}}})
	rows_for(good, "s", "$well_formed")[0].passed == true
	problem_inputs(bad) == [{"name": "checks.c", "value": ["unknown name $p"]}]
	[r.cause | some r in rows_for(bad, "s", "c")] == ["ill_formed"]
}

test_a_name_given_by_as_is_known_only_inside_its_check if {
	rep := ergo.report({"prs": [{"n": 1}]}, {"s": {"from": ["prs"], "id": ["n"], "checks": {"c": {"op": "any_of", "options": {
		"a": [{"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "present", "path": ["$approver", "id"]}}],
		"b": [{"op": "present", "path": ["$approver", "id"]}],
	}}}}})
	problem_inputs(rep) == [{"name": "checks.c.options.b.0", "value": ["unknown name $approver"]}]
}

test_a_badly_written_filter_fails_well_formed_too if {
	rep := ergo.report(typo_doc, typo_req({"op": "nope", "path": ["n"]}))
	problem_inputs(rep) == [{"name": "applies_to.f", "value": ["unknown op nope"]}]
}

test_a_badly_written_filter_wins_over_one_that_rules_the_subject_out_because_scope_cannot_be_trusted if {
	rep := ergo.report(typo_doc, {"s": {
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
		"a <missing cmp> b",
		"a lt <missing right>",
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
	defs := ergo.report({}, {"s": {"checks": checks}}).requirements.s.checks
	every name, _ in checks {
		is_string(defs[name].expression)
	}
}

test_a_missing_path_or_check_inside_a_nested_list_check_shows_in_the_expression if {
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "any", "check": {"op": "present", "path": []}}}) == "every xs: some <missing path>: <missing path>[] is present"
	rendered({}, {"op": "all", "path": ["xs"], "check": {"op": "any", "path": ["ys"]}}) == "every xs: some ys: <missing check>"
}

test_a_check_reading_a_name_nothing_gives_fails_the_requirement_even_when_no_subject_is_found if {
	rep := ergo.report({"items": []}, {"s": {"from": ["items"], "min_subjects": 0, "checks": {"c": {"op": "present", "path": ["$p", "id"]}}}})
	rep.requirements.s.satisfied == false
	problem_inputs(rep) == [{"name": "checks.c", "value": ["unknown name $p"]}]
}

test_a_field_its_op_does_not_use_fails_well_formed if {
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
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
	common := {"description": "d", "expression": "e", "inputs": [["n"]], "substitute": {"op": "present", "path": ["n"]}}
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {name: object.union(c, common) | some name, c in checks}}})
	problem_inputs(rep) == []
	object.keys(checks) == {op | some op in ergo.operators; not op in {"even", "both_present", "multiple_of"}}
}

test_a_custom_op_keeps_any_fields_it_likes if {
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "multiple_of", "path": ["n"], "by": 1, "owner": "me", "expression": "n is whole", "inputs": [["n"]]}}}})
	problem_inputs(rep) == []
	[r.cause | some r in rows_for(rep, "s", "c")] == ["satisfied"]
}

test_a_list_check_without_from_is_described if {
	rep := ergo.report({"xs": [1]}, {"s": {"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": []}}}}})
	rep.requirements.s.checks.c.expression == "every xs: xs[] is present"
}

kinds_doc := {"items": [{"id": 1, "s": "x", "n": 5, "o": {"a": 1}, "e": [], "l": [1], "t": "2026-01-01T00:00:00Z", "bad_t": "2026-02-30T00:00:00Z"}]}

kind_cause(check) := [r.cause | some r in rows_for(ergo.report(kinds_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0]

kind_filter(check) := [rep.requirements.s.satisfied, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := ergo.report(kinds_doc, {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"f": check}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
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
		kind_filter(check) == [false, ["unusable"]]
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
		kind_filter(check) == [true, ["value"]]
	}
}

approvers_doc(approvers) := {"items": [{"id": 1, "approvers": approvers}]}

not_a_bot := {"op": "any", "path": ["approvers"], "check": {"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]}}

every_human := {"op": "all", "path": ["approvers"], "check": {"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]}}

item_cause(check, approvers) := [r.cause | some r in rows_for(ergo.report(approvers_doc(approvers), {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0]

test_a_list_check_takes_the_worst_cause_of_its_failing_items if {
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {}]) == "absent"
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {"username": 42}]) == "unusable"
	item_cause(not_a_bot, [{"username": "renovate[bot]"}, {"username": "dependabot[bot]"}]) == "value"
	item_cause(every_human, [{"username": "renovate[bot]"}, {}]) == "absent"
	item_cause(every_human, [{"username": "renovate[bot]"}, {"username": "ann"}]) == "value"
	item_cause(every_human, [{"username": "ann"}, {"username": null}]) == "null"
}

test_a_filter_cannot_rule_out_a_subject_whose_items_could_not_be_read if {
	rep := ergo.report(approvers_doc([{"username": "renovate[bot]"}, {}]), {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"f": not_a_bot}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_each_takes_the_cause_of_its_inner_lists if {
	check := {"op": "all", "path": ["prs"], "each": ["commits"], "check": {"op": "present", "path": ["sha"]}}
	causes := [[r.passed, r.cause] |
		some prs in [[{"commits": [{"sha": "a"}]}, {}], [{"commits": "a"}], [{"commits": []}], [{"commits": [{"sha": "a"}]}]]
		some r in rows_for(ergo.report({"items": [{"id": 1, "prs": prs}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == [[false, "absent"], [false, "unusable"], [false, "value"], [true, "satisfied"]]
}

test_a_nested_list_check_takes_the_worst_cause_of_its_inner_items if {
	check := {"op": "all", "path": ["prs"], "check": {"op": "all", "path": ["commits"], "check": {"op": "range", "path": ["n"], "min": 0, "max": 9}}}
	causes := [r.cause |
		some commits in [[{"n": 1}, {"n": 99}], [{"n": 1}, {}], [{"n": 1}, {"n": "x"}]]
		some r in rows_for(ergo.report({"items": [{"id": 1, "prs": [{"commits": commits}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == ["value", "absent", "unusable"]
}

test_an_any_of_inside_a_list_check_takes_the_worst_cause_of_its_options if {
	check := {"op": "any", "path": ["xs"], "check": {"op": "any_of", "options": {"a": [{"op": "equals", "path": ["k"], "value": 1}], "b": [{"op": "range", "path": ["n"], "min": 0, "max": 9}]}}}
	causes := [r.cause |
		some xs in [[{"k": 2, "n": 99}], [{"k": 2}], [{"k": 2, "n": "x"}]]
		some r in rows_for(ergo.report({"items": [{"id": 1, "xs": xs}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")
	]
	causes == ["value", "absent", "unusable"]
}

test_a_list_check_that_passes_in_an_option_adds_nothing_to_the_cause_even_when_an_item_could_not_be_read if {
	check := {"op": "any_of", "options": {"o": [
		{"op": "any", "path": ["xs"], "check": {"op": "equals", "path": ["k"], "value": 1}},
		{"op": "equals", "path": ["n"], "value": 1},
	]}}
	rep := ergo.report({"items": [{"id": 1, "n": 2, "xs": [{"k": 1}, {}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[r.cause | some r in rows_for(rep, "s", "c")] == ["value"]
}

lockfile_req(filters) := {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": filters, "checks": {"c": {"op": "equals", "path": ["hashed"], "value": true}}}}

lockfile_scope(item, filters) := [rep.requirements.s.satisfied, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := ergo.report({"items": [item]}, lockfile_req(filters))
}

test_a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_other_filters_read if {
	filters := {"recorded": {"op": "present", "path": ["status"]}, "attested": {"op": "equals", "path": ["status"], "value": "COMPLETE"}}
	lockfile_scope({"id": 1}, filters) == [true, ["value"]]
	lockfile_scope({"id": 1, "status": null}, filters) == [true, ["value"]]
	lockfile_scope({"id": 1}, object.union(filters, {"other": {"op": "equals", "path": ["owner"], "value": "me"}})) == [true, ["value"]]
	lockfile_scope({"id": 1, "status": "PENDING"}, filters) == [true, ["value"]]
	lockfile_scope({"id": 1, "status": "COMPLETE", "hashed": true}, filters) == [true, ["satisfied"]]
}

test_a_present_filter_does_not_win_over_a_filter_written_wrong if {
	lockfile_scope({"id": 1}, {"recorded": {"op": "present", "path": ["status"]}, "broken": {"op": "nope"}}) == [false, ["ill_formed"]]
}

test_a_present_filter_that_cannot_reach_its_field_does_not_rule_the_subject_out if {
	filters := {"recorded": {"op": "present", "path": ["atts", {"where": {"k": "lock"}}, "status"]}, "env": {"op": "equals", "path": ["env"], "value": "prod"}}
	lockfile_scope({"id": 1, "atts": [], "env": "dev"}, filters) == [false, ["unmatched"]]
}

test_present_on_a_missing_field_is_a_clean_no_wherever_it_is if {
	doc := {"items": [{"id": 1, "approvers": [{"username": "renovate[bot]"}, {}]}]}
	human := {"op": "any", "path": ["approvers"], "check": {"op": "any_of", "options": {"human": [
		{"op": "present", "path": ["username"]},
		{"op": "not_matches_any", "path": ["username"], "patterns": ["\\[bot\\]$"]},
	]}}}
	as_check := ergo.report(doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["owner"]}, "h": human}}})
	[[r.check, r.cause] | some r in as_check.results; r.check in {"c", "h"}] == [["c", "value"], ["h", "value"]]
	as_filter := ergo.report(doc, {"s": {"from": ["items"], "id": ["id"], "min_subjects": 0, "applies_to": {"h": human}, "checks": {"c": {"op": "present", "path": ["id"]}}}})
	[as_filter.requirements.s.satisfied, [r.cause | some r in rows_for(as_filter, "s", "$applies")]] == [true, ["value"]]
}

test_present_that_cannot_reach_its_field_is_not_a_clean_no if {
	causes := [[r.cause | some r in rows_for(ergo.report({"items": [item]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}), "s", "c")][0] |
		some [item, check] in [
			[{"id": 1, "xs": []}, {"op": "present", "path": ["xs", {"where": {"k": 1}}, "v"]}],
		]
	]
	causes == ["unmatched"]
	[r.cause | some r in rows_for(ergo.report({"items": ["x"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "present", "path": ["a"]}}}}), "s", "c")] == ["not_an_object"]
}

test_a_path_starting_with_a_reserved_double_dollar_name_is_ill_formed if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "equals", "path": ["$$foo", "x"], "value": 1}}}})
	problem_inputs(rep) == [{"name": "checks.c", "value": ["unknown name $$foo"]}]
	[r.cause | some r in rows_for(rep, "s", "c")] == ["ill_formed"]
}

test_an_empty_subject_type_fails_well_formed_because_rows_and_descriptions_would_name_nothing if {
	every name in ["", " ", "\t "] {
		rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"subject_type": name})})
		row := rows_for(rep, "s", "$well_formed")[0]
		[row.passed, row.inputs[count(row.inputs) - 1]] == [false, {"name": "subject_type", "value": name}]
	}
	rep := ergo.report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"subject_type": "a b"})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

plain_defs(req) := ergo.report({"items": [{"id": 1}]}, {"s": object.union({"from": ["items"], "id": ["id"], "applies_to": {"f": {"op": "present", "path": ["id"]}}, "checks": {"c": {"op": "present", "path": ["id"]}}}, req)}).requirements.s.checks

test_the_checks_ergo_adds_are_described_in_plain_words if {
	defs := plain_defs({"subject_type": "deployment"})
	defs["$min_subjects"].description == "The in-scope deployment count is at least 1"
	defs["$applies"].description == "The deployment is in scope"
	defs["$well_formed"].description == "The requirement is written correctly"
	plain_defs({"subject_type": "deployment", "min_subjects": 2})["$min_subjects"].description == "The in-scope deployment count is at least 2"
	plain_defs({"subject_type": "deployment", "min_subjects": 0})["$min_subjects"].description == "The in-scope deployment count is at least 0"
	plain_defs({})["$min_subjects"].description == "The in-scope subject count is at least 1"
	plain_defs({})["$applies"].description == "The subject is in scope"
}

test_the_well_formed_description_is_the_same_with_a_naming_step if {
	rep := ergo.report({"items": []}, {"s": {"from": ["items", {"each_as": "it"}], "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rep.requirements.s.checks["$well_formed"].description == "The requirement is written correctly"
}

test_min_subjects_names_its_input_after_what_it_counts if {
	rep := ergo.report({"items": []}, {"s": {"subject_type": "deployment", "from": ["items"], "checks": {"c": {"op": "present", "path": ["id"]}}}})
	[r.inputs | some r in rows_for(rep, "s", "$min_subjects")] == [[{"name": "in-scope deployment count", "value": 0}]]
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_well_formed_definition_is_in_the_check_table if {
	rep := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
	rep.requirements.s.checks["$well_formed"].expression == `fields have the right types and count(checks) >= 1 and require in ["every", "some"] and steps are keys and numbers fit a float and checks are written right`
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

test_every_satisfied_when_all_subjects_pass if {
	doc := {"items": [
		{"id": "a", "signed": true, "reviewed": true},
		{"id": "b", "signed": true, "reviewed": true},
	]}
	ergo.report(doc, require_req("every")).requirements.s.satisfied == true
}

test_every_unsatisfied_when_one_subject_fails if {
	ergo.report(split_across_subjects, require_req("every")).requirements.s.satisfied == false
}

test_some_satisfied_when_one_subject_passes_every_check if {
	ergo.report(both_ok, require_req("some")).requirements.s.satisfied == true
}

test_some_unsatisfied_when_checks_are_split_across_subjects if {
	ergo.report(split_across_subjects, require_req("some")).requirements.s.satisfied == false
}

test_some_unsatisfied_without_subjects if {
	ergo.report({"items": []}, require_req("some")).requirements.s.satisfied == false
}

some_req_zero := {"s": object.union(require_req("some").s, {"min_subjects": 0})}

test_some_with_min_subjects_zero_is_vacuously_satisfied_when_empty if {
	rep := ergo.report({"items": []}, some_req_zero)
	rep.requirements.s.satisfied == true
	rep.compliant == true
}

test_some_without_min_subjects_zero_still_denies_an_empty_collection if {
	ergo.report({"items": []}, require_req("some")).requirements.s.satisfied == false
}

test_some_with_min_subjects_zero_still_denies_when_no_subject_passes if {
	rep := ergo.report(split_across_subjects, some_req_zero)
	rep.requirements.s.satisfied == false
	count(ergo.violations(rep)) > 0
}

test_some_with_min_subjects_zero_is_satisfied_when_the_filter_empties_the_scope if {
	scoped := {"s": object.union(some_req_zero.s, {"applies_to": merged_only})}
	ergo.report({"items": [{"id": "a", "state": "CLOSED"}]}, scoped).requirements.s.satisfied == true
}

test_some_still_records_rows_for_the_failing_subjects if {
	rep := ergo.report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	rep.requirements.s.satisfied == true
	count([r | some r in rep.results; r.passed == false]) == 1
}

test_require_defaults_to_every if {
	rep := ergo.report(split_across_subjects, require_req("every"))
	defaulted := ergo.report(split_across_subjects, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"checks": require_req("every").s.checks,
	}})
	defaulted.requirements.s.require == "every"
	defaulted.requirements.s.satisfied == rep.requirements.s.satisfied
}

test_unknown_require_value_is_unsatisfied if {
	ergo.report(both_ok, require_req("most")).requirements.s.satisfied == false
}

test_compliant_when_every_requirement_is_satisfied if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "min_subjects": 1, "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "min_subjects": 1, "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	ergo.report(doc, policy).compliant == true
}

test_not_compliant_when_any_requirement_is_unsatisfied if {
	doc := {"a": [{"id": "1"}], "b": [{"no_id": true}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	ergo.report(doc, policy).compliant == false
}

test_report_has_one_entry_per_declared_requirement if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
		"second": {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}},
	}
	object.keys(ergo.report(doc, policy).requirements) == {"first", "second"}
}

test_requirement_entry_carries_exactly_the_documented_keys if {
	rep := solo({"state": "MERGED"}, is_merged)
	object.keys(rep.requirements.s) == {"require", "satisfied", "subjects", "checks"}
}

test_report_carries_exactly_the_documented_keys if {
	object.keys(solo({}, is_merged)) == {"compliant", "requirements", "results"}
}

test_report_is_deterministic if {
	doc := {"items": [{"id": "b", "state": "MERGED"}, {"id": "a", "state": "CLOSED"}]}
	rep := ergo.report(doc, two_check_req)
	json.marshal(rep) == json.marshal(ergo.report(doc, two_check_req))
}

test_row_order_is_independent_of_policy_key_order if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	first := {"subject_type": "t", "from": ["a"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}
	second := {"subject_type": "t", "from": ["b"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}

	json.marshal(ergo.report(doc, {"first": first, "second": second})) == json.marshal(ergo.report(doc, {"second": second, "first": first}))
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
		some r in ergo.report(doc, {"zzz": req, "aaa": req}).results
	]
	sequence == [
		["aaa", "$well_formed", null],
		["zzz", "$well_formed", null],
		["aaa", "$min_subjects", null],
		["zzz", "$min_subjects", null],
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
	rep := ergo.report({"items": [{"id": 1}]}, {"t": req, "s": req, "delta": req, "alpha": req, "gamma": req, "beta": req})
	[r.requirement | some r in rep.results; r.check == "c"] == ["alpha", "beta", "delta", "gamma", "s", "t"]
}

test_checks_come_out_in_name_order_whatever_the_runtime if {
	check := {"op": "present", "path": ["id"]}
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check, "b": check, "a": check, "delta": check, "gamma": check}}})
	[r.check | some r in rep.results; not startswith(r.check, "$")] == ["a", "b", "c", "delta", "gamma"]
}

test_a_policy_written_as_a_set_still_gets_its_rows if {
	req := {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}
	[r.check | some r in ergo.report({"items": [{"id": 1}]}, {req}).results] == ["$well_formed", "$min_subjects", "c"]
}

test_inputs_written_as_an_object_come_out_in_key_order if {
	check := {"op": "bespoke", "inputs": {"alpha": ["a"], "beta": ["b"], "gamma": ["c"], "delta": ["d"]}}
	[i.name | some i in inputs_of({"a": 1, "b": 2, "c": 3, "d": 4}, check)] == ["a", "b", "d", "c"]
}

test_an_option_written_as_an_object_is_rendered_in_key_order if {
	check := {"op": "any_of", "options": {"o": {
		"alpha": {"op": "present", "path": ["a"]},
		"beta": {"op": "present", "path": ["b"]},
		"gamma": {"op": "present", "path": ["c"]},
		"delta": {"op": "present", "path": ["d"]},
	}}}
	rendered({}, check) == "one of: o(a is present and b is present and d is present and c is present)"
	rendered({"xs": []}, {"op": "all", "path": ["xs"], "check": check}) == "every xs: one of: o(a is present and b is present and d is present and c is present)"
}

test_an_op_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": {"ref": ["a"]}, "path": ["x"]}) == `<unknown op {"ref": ["a"]}>`
	rendered({}, {"op": null, "path": ["x"]}) == "<unknown op null>"
	rendered({}, {"op": 1.50, "path": ["x"]}) == "<unknown op 1.5>"
}

test_a_cmp_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": {"x": 1}}) == `a {"x": 1} b`
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": null}) == "a null b"
	rendered({}, {"op": "compare", "left": ["a"], "right": ["b"], "cmp": 1.5}) == "a 1.5 b"
}

test_an_option_name_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	rendered({}, {"op": "any_of", "options": {[{"op": "present", "path": ["a"]}]}}) == `one of: [{"op": "present", "path": ["a"]}](a is present)`
}

test_a_subject_type_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	req := {"from": ["xs"], "applies_to": {"f": {"op": "present", "path": ["id"]}}, "checks": {"c": {"op": "present", "path": ["id"]}}}
	checks := ergo.report({"xs": [{"id": 1}]}, {"s": object.union(req, {"subject_type": ["a", "b"]})}).requirements.s.checks
	checks["$min_subjects"].description == `The in-scope ["a", "b"] count is at least 1`
	checks["$applies"].description == `The ["a", "b"] is in scope`
	ergo.report({"xs": [{"id": 1}]}, {"s": object.union(req, {"subject_type": null})}).requirements.s.checks["$min_subjects"].description == "The in-scope null count is at least 1"
	ergo.report({"xs": [{"id": 1}]}, {"s": object.union(req, {"subject_type": -1})}).requirements.s.checks["$min_subjects"].description == "The in-scope -1 count is at least 1"
}

test_a_number_written_with_a_plus_in_its_exponent_is_written_in_full if {
	rendered({}, {"op": "equals", "path": ["x"], "value": 1e+21}) == "x == 1000000000000000000000"
	rendered({}, {"op": "equals", "path": ["x"], "value": 2.5e+30}) == "x == 2500000000000000000000000000000"
}

test_every_row_resolves_to_one_check_definition if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"applies_to": merged_only})}
	rep := ergo.report(two_states, scoped)
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
	rep := ergo.report({"items": [{"id": "a", "signed": true, "reviewed": true}]}, violating_req)
	rep.compliant == true
	ergo.violations(rep) == []
}

test_violation_entry_carries_exactly_the_documented_keys if {
	rep := ergo.report({"items": [{"id": "a"}]}, violating_req)
	count(ergo.violations(rep)) == 2
	every v in ergo.violations(rep) {
		object.keys(v) == {"requirement", "subject", "check", "description", "expression", "inputs", "cause"}
	}
}

test_violations_join_the_definition_onto_the_row if {
	rep := ergo.report({"items": [{"id": "a", "signed": true}]}, violating_req)
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
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
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
	rep := ergo.report({"items": [{"id": "a", "signed": true}]}, violating_req)
	[v.check | some v in ergo.violations(rep)] == ["reviewed"]
}

test_violations_include_min_subjects_failures if {
	rep := ergo.report({"items": []}, min_subjects_req(1))
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
	rep := ergo.report(doc, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
		"applies_to": merged_only,
		"checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}},
	}})
	rep.requirements.s.satisfied == false

	count([r | some r in rep.results; r.check == "$applies"; r.passed == false]) == 1

	[[v.subject.id, v.check] | some v in ergo.violations(rep)] == [["a", "signed"]]
}

test_violations_exclude_rows_of_a_satisfied_requirement if {
	rep := ergo.report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	rep.requirements.s.satisfied == true
	count([r | some r in rep.results; r.passed == false]) == 1
	ergo.violations(rep) == []
}

test_is_violation_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := ergo.report(
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
	rep := ergo.report({"items": [{"id": "a", "signed": true}]}, violating_req)
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
	{v.requirement | some v in ergo.violations(ergo.report(doc, policy))} == {"first", "second"}
}

test_violations_follow_results_order if {
	rep := ergo.report({"items": [{"id": "a"}, {"id": "b"}]}, violating_req)
	from_rows := [[r.requirement, r.check, r.subject.id] |
		some r in rep.results
		r.passed == false
		r.check != "$applies"
	]
	[[v.requirement, v.check, v.subject.id] | some v in ergo.violations(rep)] == from_rows
}

test_violations_keep_two_failures_that_look_alike if {
	rep := ergo.report(
		{"items": [{"signed": false}, {"signed": false}]},
		{"s": {"from": ["items"], "id": ["no_such_field"], "checks": {"signed": {"op": "equals", "path": ["signed"], "value": true}}}},
	)
	count(ergo.violations(rep)) == 2
}

test_violations_take_the_definition_from_the_rows_own_requirement if {
	rep := ergo.report({"a": [{"id": 1}], "b": [{"id": 2}]}, {
		"first": {"from": ["a"], "id": ["id"], "checks": {"c": {"description": "First", "op": "present", "path": ["x"]}}},
		"second": {"from": ["b"], "id": ["id"], "checks": {"c": {"description": "Second", "op": "present", "path": ["x"]}}},
	})
	{[v.requirement, v.description] | some v in ergo.violations(rep)} == {["first", "First"], ["second", "Second"]}
}

test_a_requirement_without_checks_yields_a_violation if {
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rep.compliant == false
	[v.check | some v in ergo.violations(rep)] == ["$well_formed"]
}

test_an_unknown_require_value_yields_a_violation if {
	rep := ergo.report(both_ok, require_req("most"))
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

scan_reports(rq) := [ergo.report(d, scan_policy(rq, mn, cs, fl)) |
	some mn in scan_mins
	some cs in scan_checksets
	some fl in scan_filters
	some d in scan_docs
]

unexplained(rq) := [rep | some rep in scan_reports(rq); rep.compliant == false; count(ergo.violations(rep)) == 0]

test_an_unsatisfied_report_always_explains_itself_under_every if count(unexplained("every")) == 0

test_an_unsatisfied_report_always_explains_itself_under_some if count(unexplained("some")) == 0

test_an_unsatisfied_report_always_explains_itself_under_a_bad_require if count(unexplained("most")) == 0

malformed(rq) := [rep | some rep in scan_reports(rq); rows_for(rep, "s", "$well_formed")[0].passed == false]

malformed_ones_fail_and_say_why(rq) if {
	every rep in malformed(rq) {
		rep.requirements.s.satisfied == false
		count([v |
			some v in ergo.violations(rep)
			v.check == "$well_formed"
		]) == 1
	}
}

test_a_malformed_requirement_is_never_satisfied_under_every if malformed_ones_fail_and_say_why("every")

test_a_malformed_requirement_is_never_satisfied_under_some if malformed_ones_fail_and_say_why("some")

test_a_malformed_requirement_is_never_satisfied_under_a_bad_require if {
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

test_every_over_no_subjects_is_not_satisfied if {
	ergo.report({"items": []}, require_req("every")).requirements.s.satisfied == false
}

test_a_typo_in_the_subject_from_path_is_not_compliant if {
	ergo.report({"items": [{"id": "a"}]}, id_req(["itmes"])).compliant == false
}

test_a_policy_with_no_requirements_is_not_compliant if {
	ergo.report({"items": []}, {}).compliant == false
}

test_min_subjects_row_labels_the_count_it_actually_reports if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"applies_to": merged_only})}
	rep := ergo.report(two_states, scoped)
	row := rows_for(rep, "s", "$min_subjects")[0]
	row.inputs[0].value == 1
	row.inputs[0].name != "count(items)"
}

test_out_of_scope_subject_is_recorded_as_evidence if {
	rep := ergo.report(two_states, scoped_req(merged_only))
	some row in rep.results
	row.subject.id == "b"
}

test_requirement_names_are_unique_by_construction if {
	doc := {"a": [{"id": "A", "v": 1}], "b": [{"id": "B", "v": 9}]}
	policy := {
		"thing": {"subject_type": "thing", "from": ["a"], "id": ["id"], "checks": {"chk": {"op": "equals", "path": ["v"], "value": 1}}},
		"other_thing": {"subject_type": "thing", "from": ["b"], "id": ["id"], "checks": {"chk": {"op": "equals", "path": ["v"], "value": 2}}},
	}
	rep := ergo.report(doc, policy)
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
	rep := ergo.report({"items": [{"id": "a"}]}, colliding)

	rep.requirements.s.checks.min_subjects == {
		"description": "user check",
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
	rep := ergo.report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": ["items"],
		"id": ["id"],
	}})
	rep.requirements.s.satisfied == false
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
	rep := ergo.report({"items": [{"id": "a", "n": 2}, {"id": "b", "n": 3}]}, {"s": {
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
	rep := ergo.report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_null_filter_field_fails_the_requirement if {
	rep := ergo.report({"rounds": [{"id": "r1", "degraded": null}]}, degraded_req("every"))
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "null"
}

test_a_filter_selector_that_matches_nothing_fails_the_requirement if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"pr": {
		"op": "equals",
		"path": ["attestations", {"where": {"type": "pr"}}, "degraded"],
		"value": true,
	}}})}
	rep := ergo.report({"rounds": [{"id": "r1", "attestations": [{"type": "jira"}]}]}, req)
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "unmatched"
}

test_an_unreadable_filter_fails_a_some_requirement_that_another_subject_meets if {
	doc := {"rounds": [{"id": "r1", "degraded": true, "signed": true}, {"id": "r2"}]}
	ergo.report(doc, degraded_req("some")).requirements.s.satisfied == false
}

test_an_unreadable_filter_fails_a_some_requirement_with_nothing_in_scope if {
	ergo.report({"rounds": [{"id": "r1"}]}, degraded_req("some")).requirements.s.satisfied == false
}

test_an_unreadable_filter_makes_the_policy_not_compliant if {
	ergo.report({"rounds": [{"id": "r1"}]}, degraded_req("every")).compliant == false
}

test_an_unreadable_filter_is_reported_as_a_violation if {
	rep := ergo.report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	[[v.subject.id, v.check, v.cause] | some v in ergo.violations(rep)] == [["r1", "$applies", "absent"]]
}

test_a_subject_with_an_unreadable_filter_still_gets_no_check_rows if {
	rep := ergo.report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	rows_for(rep, "s", "c") == []
}

test_a_filter_that_reads_a_value_that_does_not_match_leaves_the_subject_out_of_scope if {
	rep := ergo.report({"rounds": [{"id": "r1", "degraded": false}]}, degraded_req("every"))
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_filter_value_of_the_wrong_type_leaves_the_subject_out_of_scope if {
	rep := ergo.report({"rounds": [{"id": "r1", "degraded": "yes"}]}, degraded_req("every"))
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_ruled_out_by_one_filter_still_fails_the_requirement_when_another_filter_cannot_be_read if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := ergo.report({"rounds": [{"id": "r1", "state": "CLOSED"}]}, req)
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "absent"
	[v.check | some v in ergo.violations(rep)] == ["$applies"]
}

test_a_subject_is_out_of_scope_when_every_failing_filter_reads_sound_values if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := ergo.report({"rounds": [{"id": "r1", "state": "CLOSED", "degraded": false}]}, req)
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_whose_filter_fails_on_an_unreadable_field_is_not_ruled_out_by_a_passing_filter if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := ergo.report({"rounds": [{"id": "r1", "state": "MERGED"}]}, req)
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_missing_substitute_does_not_make_an_out_of_scope_subject_unreadable if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"in_scope": object.union(
		degraded_only.degraded,
		{"substitute": {"op": "equals", "path": ["forced"], "value": true}},
	)}})}
	rep := ergo.report({"rounds": [{"id": "r1", "degraded": false}]}, req)
	rep.requirements.s.satisfied == true
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
	rep := ergo.report({"packages": [{"id": "a"}]}, locked_req(["lock"]))
	rep.requirements.s.satisfied == true
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "value"]]
	ergo.violations(rep) == []
}

test_a_present_filter_rules_out_a_subject_whose_field_is_null if {
	rep := ergo.report({"packages": [{"id": "a", "lock": null}]}, locked_req(["lock"]))
	rep.requirements.s.satisfied == true
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_a_present_filter_still_fails_when_its_selector_matches_nothing if {
	rep := ergo.report({"packages": [{"id": "a", "atts": [{"type": "scan"}]}]}, locked_req(["atts", {"where": {"type": "lock"}}]))
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unmatched"]
}

test_a_present_filter_still_fails_when_its_selector_matches_several_items if {
	rep := ergo.report({"packages": [{"id": "a", "atts": [{"type": "lock"}, {"type": "lock"}]}]}, locked_req(["atts", {"where": {"type": "lock"}}]))
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ambiguous"]
}

test_a_present_filter_still_fails_on_a_subject_that_is_not_an_object if {
	rep := ergo.report({"packages": ["a"]}, locked_req(["lock"]))
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["not_an_object"]
}

test_a_present_check_on_a_missing_field_is_a_clean_no if {
	cause_of({}, {"op": "present", "path": ["lock"]}) == "value"
}

test_only_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	req := {"s": object.union(locked_req(["lock"]).s, {"applies_to": {"locked": {"op": "non_empty_string", "path": ["lock"]}}})}
	rep := ergo.report({"packages": [{"id": "a"}]}, req)
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_a_custom_op_filter_without_inputs_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"is_even": {"op": "even", "path": ["n"], "expression": "n is even"}}})}
	ergo.report({"rounds": [{"id": "r1", "n": 3, "degraded": true}]}, req).requirements.s.satisfied == true
}

test_a_failing_custom_op_filter_that_declares_no_reads_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"both": {
		"op": "both_present",
		"paths": [["a"], ["b"]],
		"expression": "a and b are present",
	}}})}
	rep := ergo.report({"rounds": [{"id": "r1", "a": 1, "degraded": true}]}, req)
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

in_doc(top, subj, check) := ergo.report(object.union(top, {"items": [subj]}), {"s": {
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
	[r.passed, r.cause, r.inputs] == [true, "satisfied", [{"name": "$$input.mode", "value": "strict"}]]
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
	expression_in(top, {"id": 1}, {"op": "excludes", "path": ["xs"], "values": banned_ref}) == "contains_none(xs, $$input.params.banned)"
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
	expression_in(top, {"id": 1}, {"op": "excludes", "path": ["xs"], "values": [nuts_ref, "garlic"]}) == `contains_none(xs, ["garlic", $$input.params.nut])`
	refs_in(top, {"id": 1, "xs": ["nuts"]}, {"op": "excludes", "path": ["xs"], "values": [nuts_ref]}) == [{"name": "$$input.params.nut", "value": "nuts"}]
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
	expression_in(top, {"id": 1}, {"op": "in", "path": ["licence"], "values": [licence_ref, "MIT"]}) == `licence in ["MIT", $$input.params.licence]`
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
	expression_in(top, {"id": 1}, matches) == `author matches one of ["^svc_", $$input.params.bot]`
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {
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
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "excludes", "path": ["xs"], "value": [{"literal": "nuts"}]}}}})
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
	rep := ergo.report(object.union(top, {"items": [subj]}), {"s": {"from": ["items"], "id": ["id"], "checks": {
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
	ergo.report(
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
	refs_in(licence_params, subj, licence_in_allowed) == [{"name": "$$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
}

test_a_violation_shows_the_ref_values_beside_what_the_check_read if {
	violation_in(licence_params, {"id": 1, "licence": "GPL-3.0"}, licence_in_allowed).inputs == [
		{"name": "licence", "value": "GPL-3.0"},
		{"name": "$$input.params.allowed", "value": ["MIT", "Apache-2.0"]},
	]
}

test_a_check_without_refs_has_no_refs_in_its_definition if {
	not "$refs" in object.keys(in_doc({}, {"id": 1}, {"op": "present", "path": ["id"]}).requirements.s.checks.c)
}

test_a_missing_ref_is_recorded_as_null if {
	refs_in({}, {"id": 1, "licence": "MIT"}, licence_in_allowed) == [{"name": "$$input.params.allowed", "value": null}]
	violation_in({}, {"id": 1, "licence": "MIT"}, licence_in_allowed).inputs == [
		{"name": "licence", "value": "MIT"},
		{"name": "$$input.params.allowed", "value": null},
	]
}

test_a_ref_shows_its_path_in_the_expression if {
	expression_in({}, {"id": 1}, licence_in_allowed) == "licence in $$input.params.allowed"
	expression_in({}, {"id": 1}, {"op": "equals", "path": ["v"], "value": missing_ref}) == "v == $$input.params.missing"
	expression_in({}, {"id": 1}, {"op": "includes", "path": ["l"], "value": missing_ref}) == "contains(l, $$input.params.missing)"
	expression_in({}, {"id": 1}, {"op": "excludes", "path": ["l"], "value": missing_ref}) == "not contains(l, $$input.params.missing)"
	expression_in({}, {"id": 1}, {"op": "matches_any", "path": ["a"], "patterns": missing_ref}) == "a matches one of $$input.params.missing"
	expression_in({}, {"id": 1}, {"op": "not_matches_any", "path": ["a"], "patterns": missing_ref}) == "a matches none of $$input.params.missing"
	expression_in({}, {"id": 1}, {"op": "range", "path": ["n"], "min": missing_ref, "max": 3}) == "n >= $$input.params.missing and n <= 3"
	expression_in({}, {"id": 1}, {"op": "present", "path": ["atts", {"where": {"type": missing_ref}}]}) == "atts.[type==$$input.params.missing] is present"
}

any_allowed_licence := {"op": "any", "path": ["licences"], "check": {"op": "in", "path": [], "values": allowed_ref}}

test_a_ref_inside_any_is_read_once_and_shown_once if {
	r := row_in(licence_params, {"id": 1, "licences": ["GPL-3.0"]}, any_allowed_licence)
	[r.passed, r.cause] == [false, "value"]
	r.inputs == [{"name": "licences[]", "value": ["GPL-3.0"]}]
	refs_in(licence_params, {"id": 1}, any_allowed_licence) == [{"name": "$$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
	expression_in(licence_params, {"id": 1}, any_allowed_licence) == "some licences: licences[] in $$input.params.allowed"
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
	refs_in(licence_params, {"id": 1}, check) == [{"name": "$$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
	row_in({}, {"id": 1, "licence": "MIT"}, check).cause == "absent"
}

test_a_ref_in_a_check_and_its_substitute_is_shown_once if {
	check := object.union(licence_in_allowed, {"substitute": {"op": "in", "path": ["fallback"], "values": allowed_ref}})
	r := row_in(licence_params, {"id": 1, "licence": "GPL-3.0", "fallback": "MIT"}, check)
	[r.passed, r.cause] == [true, "substituted"]
	r.inputs == [{"name": "licence", "value": "GPL-3.0"}, {"name": "fallback", "value": "MIT"}]
	refs_in(licence_params, {"id": 1}, check) == [{"name": "$$input.params.allowed", "value": ["MIT", "Apache-2.0"]}]
}

test_ref_inputs_are_sorted_by_name if {
	check := {"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "lo"]}, "max": {"ref": ["$$input", "params", "hi"]}}
	[i.name | some i in refs_in({"params": {"lo": 1, "hi": 3}}, {"id": 1, "n": 2}, check)] == ["$$input.params.hi", "$$input.params.lo"]
}

test_a_ref_in_an_applies_to_filter_is_read_and_shown if {
	req := {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"kind": {"op": "equals", "path": ["kind"], "value": {"ref": ["$$input", "params", "kind"]}}},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}}
	rep := ergo.report({"params": {"kind": "lib"}, "items": [{"id": 1, "kind": "lib"}, {"id": 2, "kind": "app"}]}, req)
	[[r.subject.id, r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "$applies")] == [
		[1, true, "satisfied", [{"name": "kind", "value": "lib"}]],
		[2, false, "value", [{"name": "kind", "value": "app"}]],
	]
	rep.requirements.s.checks["$applies"]["$refs"] == [{"name": "$$input.params.kind", "value": "lib"}]
	unreadable := ergo.report({"items": [{"id": 1, "kind": "lib"}]}, req)
	unreadable.requirements.s.satisfied == false
	[r.cause | some r in rows_for(unreadable, "s", "$applies")] == ["absent"]
	[v.inputs | some v in ergo.violations(unreadable); v.check == "$applies"] == [[{"name": "kind", "value": "lib"}, {"name": "$$input.params.kind", "value": null}]]
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
	expression_in({}, {"id": 1}, {"op": "not_matches_any", "path": ["a"], "patterns": bad}) == "a matches none of <invalid ref>"
	expression_in({}, {"id": 1}, {"op": "in", "path": ["a"], "values": bad}) == "a in <invalid ref>"
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
	row_in({"mode": "strict"}, {"id": 1, "xs": [1, 2]}, check).inputs == [{"name": "xs[]", "value": [1, 2]}, {"name": "$$input.mode", "value": "strict"}]
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
	refs_in({"params": {"m": 2}}, {"id": 1, "n": 4}, check) == [{"name": "$$input.params.m", "value": 2}]
}

test_a_path_written_as_a_string_reads_that_one_key if {
	row_in({}, {"id": 1}, {"op": "present", "path": "state"}).passed == false
	row_in({}, {"id": 1}, {"op": "present", "path": "state"}).cause == "value"
	row_in({}, {"id": 1, "state": "OPEN"}, {"op": "equals", "path": "state", "value": "OPEN"}).passed == true
	row_in({}, {"id": 1}, {"op": "present", "path": 3}).passed == false
}

test_a_path_written_as_an_object_reads_nothing if {
	r := row_in({}, {"id": 1, "a": 1}, {"op": "present", "path": {"a": 1}})
	[r.passed, r.cause] == [false, "absent"]
}

test_a_string_that_starts_with_two_dollars_is_not_a_name_when_it_is_the_whole_path if {
	row_in({"mode": "strict"}, {"id": 1, "$$input": "own"}, {"op": "equals", "path": "$$input", "value": "own"}).passed == true
}

test_a_path_written_as_an_object_on_a_subject_that_is_not_an_object_is_not_an_object if {
	row_in({}, "str", {"op": "present", "path": {"a": 1}}).cause == "not_an_object"
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

suite_rows(doc, step) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(ergo.report(doc, suite_req(step)), "s", "c")]

test_an_each_step_makes_every_entry_of_an_object_a_subject_named_by_its_key if {
	suite_rows(suite_doc, {"each_as": "suite"}) == [
		["integration-test", true, "satisfied"],
		["smoke-test", false, "value"],
		["unit-test", true, "satisfied"],
	]
}

test_an_each_step_identifies_entries_of_an_object_by_key_even_with_an_id if {
	rep := ergo.report(suite_doc, {"s": object.union(suite_req({"each_as": "suite"}).s, {"id": ["result"]})})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == ["integration-test", "smoke-test", "unit-test"]
}

test_an_each_step_over_a_list_makes_every_item_a_subject if {
	rep := ergo.report({"items": [{"id": "b"}, {"id": "a"}]}, {"s": {"from": ["items", {"each_as": "item"}], "id": ["id"], "checks": {"c": {"op": "present", "path": ["$item", "id"]}}}})
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
	rep := ergo.report(suite_doc, suite_req({"each_as": "suite", "keys": ["system-test"]}))
	rep.requirements.s.satisfied == false
	rep.compliant == false
}

test_a_missing_key_reads_as_absent_even_from_the_subject_itself if {
	rep := ergo.report(suite_doc, {"s": {
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
	rep := ergo.report(suite_doc, suite_req({"each_as": "suite", "keys": []}))
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.satisfied == false
}

test_an_each_step_on_something_missing_or_scalar_gives_no_subjects if {
	ergo.report({}, suite_req({"each_as": "suite"})).requirements.s.subjects == {"total": 0, "matching": 0}
	ergo.report({"build": {"test_runs": "x"}}, suite_req({"each_as": "suite"})).requirements.s.subjects == {"total": 0, "matching": 0}
	ergo.report({}, suite_req({"each_as": "suite"})).requirements.s.satisfied == false
}

test_min_subjects_counts_from_the_path_before_the_each_step if {
	rep := ergo.report(suite_doc, suite_req({"each_as": "suite"}))
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(build.test_runs)) >= 1"
}

test_an_empty_path_under_an_each_step_is_named_after_the_name if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "present", "path": []}},
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks.c.expression == "$suite is present"
	rep.requirements.s.checks["$applies"].expression == "$suite is present"
}

test_a_name_at_the_start_of_a_path_reads_the_subject if {
	rep := ergo.report(suite_doc, {"s": {
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
	rep := ergo.report({"names": ["a", ""]}, {"s": {
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
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(ergo.report(pr_doc, peer_req), "s", "c")] == [
		[1, true, "satisfied"],
		[2, false, "value"],
		[3, false, "absent"],
	]
}

test_a_name_read_inside_a_list_check_is_shown_in_the_row if {
	rows := rows_for(ergo.report(pr_doc, peer_req), "s", "c")
	[r.inputs | some r in rows] == [
		[{"name": "approvers[]", "value": [{"username": "ann"}, {"username": "bob"}]}, {"name": "$pr.author", "value": "ann"}],
		[{"name": "approvers[]", "value": [{"username": "bob"}]}, {"name": "$pr.author", "value": "bob"}],
		[{"name": "approvers[]", "value": [{"username": "bob"}]}, {"name": "$pr.author", "value": null}],
	]
	ergo.report(pr_doc, peer_req).requirements.s.checks.c.expression == "some approvers: username ne $pr.author"
}

test_a_name_read_inside_an_any_of_in_a_list_check_is_shown_in_the_row if {
	rep := ergo.report(pr_doc, {"s": {
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
	rep := ergo.report({"items": [{"id": 1, "xs": [{"v": 2}]}], "params": {"max": 3}}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "compare", "left": ["v"], "right": ["$$input", "params", "max"], "cmp": "lt"}}},
	}})
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "xs[]", "value": [{"v": 2}]}, {"name": "$$input.params.max", "value": 3}]]
}

test_each_subject_reads_its_own_name if {
	rep := ergo.report({"a": [{"x": 1, "y": 1}, {"x": 2, "y": 3}]}, {"s": {
		"from": ["a", {"each_as": "it"}],
		"id": ["x"],
		"checks": {"c": {"op": "compare", "left": ["$it", "x"], "right": ["y"], "cmp": "eq"}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, false]]
}

test_a_name_that_is_not_bound_is_ill_formed if {
	rep := ergo.report(pr_doc, {"s": {
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
	rendered({}, {"op": "present", "path": ["a", {"literal": "$schema"}]}) == `a.$schema is present`
}

test_a_key_that_starts_with_a_dollar_is_read_with_literal if {
	row_in({}, {"id": 1, "$schema": "x"}, {"op": "present", "path": ["$schema"]}).passed == false
	row_in({}, {"id": 1, "$schema": "x"}, {"op": "present", "path": [{"literal": "$schema"}]}).passed == true
}

test_a_ref_to_a_name_fails_closed if {
	rep := ergo.report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "equals", "path": ["author"], "value": {"ref": ["$pr", "author"]}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [false, false, false]
	rep.requirements.s.checks.c.expression == "author == <invalid ref>"
	rep.requirements.s.checks.c["$refs"] == [{"name": "<invalid ref>", "value": null}]
}

test_a_filter_can_read_a_name if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "equals", "path": ["$suite", "result"], "value": "passed"}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "$applies")] == [["integration-test", true], ["smoke-test", false], ["unit-test", true]]
	rep.requirements.s.subjects == {"total": 3, "matching": 2}
	rep.requirements.s.satisfied == true
}

test_a_filter_that_reads_a_name_and_fails_shows_its_value if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"applies_to": {"f": {"op": "equals", "path": ["$suite", "result"], "value": "passed"}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	some r in rows_for(rep, "s", "$applies")
	r.subject.id == "smoke-test"
	[r.inputs, r.cause] == [[{"name": "$suite.result", "value": "failed"}], "value"]
}

test_a_present_filter_on_a_name_rules_out_a_missing_key if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "suite", "keys": ["system-test", "unit-test"]}],
		"applies_to": {"f": {"op": "present", "path": ["$suite"]}},
		"checks": {"c": {"op": "present", "path": ["result"]}},
	}})
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	rep.requirements.s.satisfied == true
}

test_require_some_passes_when_one_key_passes if {
	rep := ergo.report(suite_doc, {"s": object.union(suite_req({"each_as": "suite", "keys": ["smoke-test", "unit-test"]}).s, {"require": "some"})})
	rep.requirements.s.satisfied == true
}

test_a_custom_operator_can_read_a_name if {
	rep := ergo.report({"xs": [{"n": 2}, {"n": 3}]}, {"s": {
		"from": ["xs", {"each_as": "x"}],
		"id": ["n"],
		"checks": {"c": {"op": "even", "path": ["$x", "n"]}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[2, true], [3, false]]
}

test_a_name_read_from_the_input_still_works_under_an_each_step if {
	rep := ergo.report(object.union(suite_doc, {"params": {"want": "passed"}}), {"s": {
		"from": ["build", "test_runs", {"each_as": "suite"}],
		"checks": {"c": {"op": "equals", "path": ["$suite", "result"], "value": {"ref": ["$$input", "params", "want"]}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [true, false, true]
}

ill_formed_from(step_from) := ergo.report(suite_doc, {"s": {
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
		rep.requirements.s.satisfied == false
		rep.compliant == false
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
}

test_a_badly_written_from_is_named_as_invalid if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", {"each_as": "x"}, "test_runs"],
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks.c.expression == "<invalid from> is present"
}

test_a_well_formed_row_for_a_from_with_a_step_shows_the_from if {
	rep := ill_formed_from(["build", "test_runs", {"each_as": "suite"}])
	row := rows_for(rep, "s", "$well_formed")[0]
	row.passed == true
	row.inputs[2] == {"name": "from", "value": ["build", "test_runs", {"each_as": "suite"}]}
	rep.requirements.s.checks["$well_formed"].expression == `fields have the right types and count(checks) >= 1 and require in ["every", "some"] and from is well formed and steps are keys and numbers fit a float and checks are written right`
}

test_a_well_formed_row_without_a_step_is_unchanged if {
	rep := ill_formed_from(["build", "test_runs"])
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_an_input_missing_inside_a_list_check_fails_as_absent if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"v": 2}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "compare", "left": ["v"], "right": ["$$input", "params", "max"], "cmp": "lt"}}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_a_name_missing_in_the_path_of_a_list_check_fails_as_absent if {
	rep := ergo.report({"prs": [{"n": 1, "xs": [1, 2]}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "non_empty_string", "path": ["$pr", "author"]}}},
	}})
	[[r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "c")] == [[false, "absent", [{"name": "xs[]", "value": [1, 2]}, {"name": "$pr.author", "value": null}]]]
}

test_an_input_missing_in_the_path_of_a_list_check_fails_as_absent if {
	rep := ergo.report({"items": [{"id": 1, "xs": [1]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "non_empty_string", "path": ["$$input", "nope"]}}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_an_id_can_start_with_a_name if {
	rep := ergo.report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["$pr", "number"],
		"checks": {"c": {"op": "present", "path": ["number"]}},
	}})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == [1, 2, 3]
}

test_the_input_cannot_give_names if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs"],
		"checks": {"c": {"op": "present", "path": ["$suite", "x"]}},
	}}) with input as {"ergo/names": {"suite": {"x": 1}}}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false]
}

test_the_input_cannot_give_other_names_under_a_step if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", "test_runs", {"each_as": "run"}],
		"checks": {"c": {"op": "present", "path": ["$suite", "x"]}},
	}}) with input as {"ergo/names": {"suite": {"x": 1}}}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false, false, false]
}

test_a_badly_written_from_is_named_as_invalid_in_min_subjects if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", {"each_as": "x"}, "test_runs"],
		"checks": {"c": {"op": "present", "path": []}},
	}})
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

test_a_literal_or_selector_in_from_is_not_well_formed_so_it_cannot_pass_by_finding_nothing if {
	every f in [["a", {"literal": "$x"}], ["a", {"where": {"id": 1}}]] {
		rep := ergo.report({"a": {"$x": [{"id": 1}]}}, {"s": {"from": f, "min_subjects": 0, "checks": {"c": {"op": "present", "path": ["id"]}}}})
		rows_for(rep, "s", "$well_formed")[0].passed == false
		rep.requirements.s.satisfied == false
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

review_rows(check) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(ergo.report(review_doc, review_req(check)), "s", "c")]

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
	ergo.report(review_doc, review_req(after_last_commit)).requirements.s.checks.c.expression == "some approvers as $approver: every $pr.commits: $approver.timestamp gt timestamp"
}

test_a_nested_list_check_shows_the_list_and_the_names_it_reads if {
	some r in rows_for(ergo.report(review_doc, review_req(after_last_commit)), "s", "c")
	r.subject.id == 42
	r.inputs == [
		{"name": "approvers[]", "value": [{"username": "bob", "timestamp": "2026-10-01T11:00:00Z"}]},
		{"name": "$pr.commits", "value": [{"sha": "c1", "timestamp": "2026-10-01T10:00:00Z"}, {"sha": "c2", "timestamp": "2026-10-01T12:00:00Z"}]},
	]
}

test_a_name_given_by_as_is_not_read_for_the_row_but_its_item_decides_the_cause if {
	check := {"op": "all", "path": ["approvers"], "as": "a", "check": {"op": "non_empty_string", "path": ["$a", "timestamp"]}}
	review_rows(check)[4] == [45, false, "absent"]
	some r in rows_for(ergo.report(review_doc, review_req(check)), "s", "c")
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
	rep := ergo.report({"items": [{"id": 1, "tags": ["a"]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "all", "path": ["tags"], "as": "tag", "check": {"op": "non_empty_string", "path": []}}}}})
	rep.requirements.s.checks.c.expression == "every tags as $tag: $tag is a non-empty string"
	rows_for(rep, "s", "c")[0].passed == true
}

test_as_works_without_a_naming_step if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"v": 1, "w": [1]}]}]}, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "all", "path": ["w"], "check": {"op": "compare", "left": [], "right": ["$x", "v"], "cmp": "eq"}}}}}})
	rows_for(rep, "s", "c")[0].passed == true
}

test_an_inner_list_check_can_read_a_list_inside_the_outer_item if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": [2, 3]}, {"ys": [4]}]}, {"id": 2, "xs": [{"ys": [1]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "range", "path": [], "min": 2, "max": 9}}}},
	}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, false]]
	rep.requirements.s.checks.c.expression == "every xs: every ys: ys[] >= 2 and ys[] <= 9"
	rows_for(rep, "s", "c")[0].inputs == [{"name": "xs[].ys", "value": [[2, 3], [4]]}]
}

test_an_inner_list_check_fails_on_an_empty_or_missing_inner_list if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": [2]}, {"ys": []}]}, {"id": 2, "xs": [{"ys": [2]}, {}]}]}, {"s": {
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
	expression_in({}, {"id": 1}, check) == "some teams as $team: every repos[].owners as $owner: $owner == $$input.lead"
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
		ergo.report(review_doc, review_req(check)).requirements.s.checks.c.expression == "some approvers as <invalid name>: username is present"
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
	rep := ergo.report(review_doc, {"s": {
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
	rep := ergo.report(review_doc, {"s": {
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
	rep := ergo.report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"ill_formed"}
}

test_a_filter_with_a_badly_written_as_cannot_rule_subjects_out if {
	rep := ergo.report(review_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["approvers"], "as": "a", "check": {"op": "any", "path": ["$pr", "commits"], "as": "$c", "check": {"op": "present", "path": ["sha"]}}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"ill_formed"}
}

test_a_filter_nested_too_deep_cannot_rule_subjects_out if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
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

review_expression(check) := ergo.report(review_doc, review_req(check)).requirements.s.checks.c.expression

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

peer_rows(check) := [[r.subject.id, r.passed, r.cause] | some r in rows_for(ergo.report(peer_doc, review_req(check)), "s", "c")]

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
	ergo.report(peer_doc, review_req(peer_check)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(state == \"APPROVED\" and username ne $pr.author and every $pr.commits: $approver.timestamp gt timestamp)"
}

test_a_list_check_inside_an_any_of_shows_the_names_it_reads if {
	some r in rows_for(ergo.report(peer_doc, review_req(peer_check)), "s", "c")
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
	ergo.report(peer_doc, review_req(inner)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(every $pr.commits as <name given twice>: timestamp is present)"
	top := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["commits"], "as": "pr", "check": {"op": "present", "path": ["timestamp"]}}]}}
	{r[2] | some r in peer_rows(top)} == {"ill_formed"}
	ergo.report(peer_doc, review_req(top)).requirements.s.checks.c.expression == "one of: o(every commits as <name given twice>: timestamp is present)"
}

test_a_broken_list_check_in_an_any_of_filter_cannot_rule_subjects_out if {
	rep := ergo.report(peer_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "any_of", "options": {"o": [{"op": "all", "path": ["commits"], "as": "pr", "check": {"op": "present", "path": ["timestamp"]}}]}}},
		"checks": {"c": {"op": "equals", "path": ["number"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
}

test_a_list_check_inside_an_any_of_at_the_top_reads_names_for_its_row if {
	check := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "compare", "left": [], "right": ["$$input", "lim"], "cmp": "lt"}}]}}
	row_in({"lim": 3}, {"id": 1, "xs": [1, 2]}, check).passed == true
	r := row_in({}, {"id": 1, "xs": [1, 2]}, check)
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": "$$input.lim", "value": null}, {"name": "xs", "value": [1, 2]}]
}

test_a_list_check_inside_an_any_of_inside_a_list_check_reads_names_for_its_row if {
	check := {"op": "all", "path": ["as"], "check": {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "compare", "left": [], "right": ["$$input", "lim"], "cmp": "lt"}}]}}}
	row_in({"lim": 3}, {"id": 1, "as": [{"xs": [1, 2]}]}, check).passed == true
	r := row_in({}, {"id": 1, "as": [{"xs": [1, 2]}]}, check)
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": "as[]", "value": [{"xs": [1, 2]}]}, {"name": "$$input.lim", "value": null}]
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
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": []}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {
			"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
			"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
		}}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
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
	rep := ergo.report({"items": [{"id": 1, "xs": [1, 2], "ys": [3]}]}, {"s": {
		"from": ["items", {"each_as": "it"}],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "each": ["$it", "ys"], "check": {"op": "equals", "path": [], "value": 3}}},
	}})
	[r.passed | some r in rows_for(rep, "s", "c")] == [true]
}

test_a_filter_with_a_misspelt_name_in_an_each_path_cannot_rule_subjects_out if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": [1]}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
}

params_req(check) := {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}}

params_rows(doc, check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(ergo.report(doc, params_req(check)), "s", "c")]

test_a_ref_to_params_reads_data_params if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	params_rows({"items": [{"id": 1, "name": "app"}]}, check) == [[true, "satisfied", [{"name": "name", "value": "app"}]]] with data.params as {"artifact_name": "app"}
	params_rows({"items": [{"id": 1, "name": "app"}]}, check) == [[false, "value", [{"name": "name", "value": "app"}]]] with data.params as {"artifact_name": "web"}
	rep := ergo.report({"items": [{"id": 1, "name": "app"}]}, params_req(check)) with data.params as {"artifact_name": "web"}
	rep.requirements.s.checks.c["$refs"] == [{"name": "$$params.artifact_name", "value": "web"}]
	rep.requirements.s.checks.c.expression == "name == $$params.artifact_name"
	ergo.violations(rep)[0].inputs == [{"name": "name", "value": "app"}, {"name": "$$params.artifact_name", "value": "web"}]
}

test_a_path_can_start_at_params if {
	check := {"op": "in", "path": ["$$params", "level"], "values": ["strict", "lax"]}
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$$params.level", "value": "strict"}]]] with data.params as {"level": "strict"}
}

test_params_that_are_missing_fail_closed if {
	check := {"op": "excludes", "path": ["licences"], "value": {"ref": ["$$params", "banned"]}}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]]
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"]}]]] with data.params as "not an object"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "null", [{"name": "licences", "value": ["MIT"]}]]] with data.params as {"banned": null}
}

test_params_given_to_the_report_replace_data_params if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	rep := ergo.report_with_params({"items": [{"id": 1, "name": "app"}]}, {"artifact_name": "app"}, params_req(check)) with data.params as {"artifact_name": "web"}
	[r.passed | some r in rows_for(rep, "s", "c")] == [true]
	rep.requirements.s.checks.c["$refs"] == [{"name": "$$params.artifact_name", "value": "app"}]
}

test_params_are_not_read_from_the_input if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "artifact_name"]}}
	params_rows({"items": [{"id": 1, "name": "app"}], "params": {"artifact_name": "app"}}, check) == [[false, "absent", [{"name": "name", "value": "app"}]]]
}

test_params_can_be_read_inside_named_and_nested_list_checks if {
	check := {"op": "all", "path": ["xs"], "as": "x", "check": {"op": "any", "path": ["$x", "ys"], "check": {"op": "compare", "left": [], "right": ["$$params", "max"], "cmp": "lt"}}}
	rep := ergo.report({"items": [{"id": 1, "xs": [{"ys": [1, 9]}, {"ys": [2]}]}]}, {"s": {"from": ["items", {"each_as": "it"}], "id": ["id"], "checks": {"c": check}}}) with data.params as {"max": 3}
	[[r.passed, r.inputs] | some r in rows_for(rep, "s", "c")] == [[true, [{"name": "xs[].ys", "value": [[1, 9], [2]]}, {"name": "$$params.max", "value": 3}]]]
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

trail_rows(check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(ergo.report(trail_doc, trail_req(check)), "s", "c")]

attested := {"op": "equals", "path": ["attestations", {"ref": ["$$params", "att"]}, "status"], "value": "COMPLETE"}

test_a_ref_step_in_a_path_reads_the_key_it_names if {
	trail_rows(attested) == [[true, "satisfied", [{"name": "attestations.[$$params.att].status", "value": "COMPLETE"}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	trail_rows(attested) == [[false, "value", [{"name": "attestations.[$$params.att].status", "value": "FAILED"}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_step_renders_and_is_recorded_like_any_ref if {
	rep := ergo.report(trail_doc, trail_req(attested)) with data.params as {"artifact": "app", "att": "junit"}
	rep.requirements.s.checks.c.expression == `attestations.[$$params.att].status == "COMPLETE"`
	rep.requirements.s.checks.c["$refs"] == [{"name": "$$params.att", "value": "junit"}]
	ergo.violations(rep)[0].inputs == [{"name": "attestations.[$$params.att].status", "value": "FAILED"}, {"name": "$$params.att", "value": "junit"}]
}

test_a_ref_step_can_be_first_or_last if {
	last := {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}
	trail_rows(last) == [[true, "satisfied", [{"name": "attestations.[$$params.att]", "value": {"status": "COMPLETE"}}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	first := {"op": "non_empty_string", "path": [{"ref": ["$$params", "field"]}]}
	trail_rows(first) == [[true, "satisfied", [{"name": "[$$params.field]", "value": "abc"}]]] with data.params as {"artifact": "app", "field": "fingerprint"}
}

test_a_ref_step_can_be_a_list_index if {
	check := {"op": "equals", "path": ["tags", {"ref": ["$$params", "i"]}], "value": "v2"}
	[r[0] | some r in trail_rows(check)] == [true] with data.params as {"artifact": "app", "i": 1}
}

test_a_ref_step_that_cannot_be_read_fails_the_check if {
	trail_rows(attested) == [[false, "absent", [{"name": "attestations.[$$params.att].status", "value": null}]]] with data.params as {"artifact": "app"}
	trail_rows(attested) == [[false, "null", [{"name": "attestations.[$$params.att].status", "value": null}]]] with data.params as {"artifact": "app", "att": null}
	every bad in [["pull-request"], {"k": "pull-request"}, true] {
		trail_rows(attested) == [[false, "unusable", [{"name": "attestations.[$$params.att].status", "value": null}]]] with data.params as {"artifact": "app", "att": bad}
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
	rep := ergo.report({"items": [{"key": "k1", "a": 1, "b": 2, "xs": [{"ys": [1]}]}]}, {"s": {
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
	rep := ergo.report({"prs": [{"n": 1, "atts": {"list": [{"type": "a", "ok": true}]}}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "equals", "path": ["$pr", {"ref": ["$$params", "k"]}, {"where": {"type": "a"}}, "ok"], "value": true}},
	}}) with data.params as {"k": "atts"}
	[r.passed | some r in rows_for(rep, "s", "c")] == [false]
	rep2 := ergo.report({"prs": [{"n": 1, "atts": [{"type": "a", "ok": true}]}]}, {"s": {
		"from": ["prs", {"each_as": "pr"}],
		"id": ["n"],
		"checks": {"c": {"op": "equals", "path": ["$pr", {"ref": ["$$params", "k"]}, {"where": {"type": "a"}}, "ok"], "value": true}},
	}}) with data.params as {"k": "atts"}
	[r.passed | some r in rows_for(rep2, "s", "c")] == [true]
}

test_a_ref_step_in_from_finds_the_subjects if {
	rep := ergo.report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]})) with data.params as {"artifact": "app"}
	rep.requirements.s.subjects == {"total": 1, "matching": 1}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(trail.artifacts.[$$params.artifact])) >= 1"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$$params.artifact", "value": "app"}]
	rep.requirements.s.satisfied == true
}

test_a_ref_step_in_from_that_cannot_be_read_fails_the_requirement_even_with_min_subjects_zero if {
	req := {"s": object.union(trail_req({"op": "present", "path": ["fingerprint"]}).s, {"min_subjects": 0})}
	every params in [{}, {"artifact": null}, {"artifact": ["app"]}] {
		rep := ergo.report(trail_doc, req) with data.params as params
		rep.requirements.s.satisfied == false
		rows_for(rep, "s", "$min_subjects")[0].passed == false
	}
	rows_for(ergo.report(trail_doc, req), "s", "$min_subjects")[0].cause == "absent" with data.params as {}
	rows_for(ergo.report(trail_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"artifact": null}
	rows_for(ergo.report(trail_doc, req), "s", "$min_subjects")[0].cause == "unusable" with data.params as {"artifact": ["app"]}
}

test_a_ref_step_in_from_that_cannot_be_read_shows_up_in_violations if {
	vs := ergo.violations(ergo.report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]}))) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope subject count", "value": 0}, {"name": "$$params.artifact", "value": null}]]]
}

test_a_ref_step_at_the_end_of_from_is_not_a_naming_step if {
	rep := ergo.report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]})) with data.params as {"artifact": "app"}
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_a_ref_step_in_from_works_with_a_naming_step if {
	rep := ergo.report(trail_doc, {"s": {
		"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"]}, "attestations", {"each_as": "att", "keys": ["junit", "pull-request", "system-test"]}],
		"checks": {"c": {"op": "equals", "path": ["$att", "status"], "value": "COMPLETE"}},
	}}) with data.params as {"artifact": "app"}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [["junit", false, "value"], ["pull-request", true, "satisfied"], ["system-test", false, "absent"]]
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_a_badly_written_ref_step_in_from_is_not_well_formed if {
	rep := ergo.report(trail_doc, {"s": {
		"from": ["trail", "artifacts", {"ref": ["$$params", "artifact"], "note": "x"}],
		"min_subjects": 0,
		"checks": {"c": {"op": "present", "path": ["fingerprint"]}},
	}}) with data.params as {"artifact": "app"}
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.satisfied == false
}

test_a_present_filter_with_a_ref_step_that_cannot_be_read_cannot_rule_subjects_out if {
	rep := ergo.report(trail_doc, {"s": {
		"from": ["trail", "artifacts", "app"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}},
		"checks": {"c": {"op": "equals", "path": ["fingerprint"], "value": "nope"}},
	}})
	rep.requirements.s.satisfied == false
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_present_filter_with_a_ref_step_still_rules_out_a_missing_field if {
	rep := ergo.report(trail_doc, {"s": {
		"from": ["trail", "artifacts", "app"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"]}]}},
		"checks": {"c": {"op": "equals", "path": ["fingerprint"], "value": "nope"}},
	}}) with data.params as {"att": "sbom"}
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_dotted_key_in_a_ref_is_quoted if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", "a.b"]}}
	rep := ergo.report({"items": [{"id": 1, "name": "x"}]}, params_req(check)) with data.params as {"a.b": "x"}
	rep.requirements.s.checks.c.expression == `name == $$params."a.b"`
	rep.requirements.s.checks.c["$refs"] == [{"name": `$$params."a.b"`, "value": "x"}]
}

test_a_literal_in_a_ref_path_is_read_as_written if {
	check := {"op": "equals", "path": ["name"], "value": {"ref": ["$$params", {"literal": "$$odd"}]}}
	params_rows({"items": [{"id": 1, "name": "x"}]}, check) == [[true, "satisfied", [{"name": "name", "value": "x"}]]] with data.params as {"$$odd": "x"}
}

test_a_present_filter_with_a_path_written_as_an_object_cannot_rule_subjects_out if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": {"a": 1}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}})
	rep.requirements.s.satisfied == false
}

test_a_ref_step_after_a_name_that_cannot_be_read_is_not_skipped if {
	rep := ergo.report({"prs": [{"n": 1, "x": "here"}]}, {"s": {
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
	refs_in({}, {"id": 1, "xs": [{"v": 1}]}, check) == [{"name": "$$params.k", "value": ["v"]}] with data.params as {"k": ["v"]}
}

test_a_filter_with_a_ref_step_of_the_wrong_type_inside_a_list_check_cannot_rule_subjects_out if {
	rep := ergo.report({"items": [{"id": 1, "xs": [{"v": 1}]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [{"ref": ["$$params", "k"]}]}}},
		"checks": {"c": {"op": "equals", "path": ["id"], "value": 0}},
	}}) with data.params as {"k": ["v"]}
	rep.requirements.s.satisfied == false
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
	rep := ergo.report(suite_doc, suites_from_params) with data.params as {"suites": ["unit-test", "system-test"]}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [
		["system-test", false, "absent"],
		["unit-test", true, "satisfied"],
	]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$$params.suites", "value": ["unit-test", "system-test"]}]
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_keys_from_a_ref_behave_like_keys_written_out if {
	written := ergo.report(suite_doc, suite_req({"each_as": "run", "keys": ["unit-test", "smoke-test", "unit-test"]}))
	read := ergo.report(suite_doc, suites_from_params) with data.params as {"suites": ["unit-test", "smoke-test", "unit-test"]}
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(written, "s", "c")] == [[r.subject.id, r.passed, r.cause] | some r in rows_for(read, "s", "c")]
}

test_keys_from_a_ref_that_cannot_be_read_fail_the_requirement_even_with_min_subjects_zero if {
	req := {"s": object.union(suites_from_params.s, {"min_subjects": 0})}
	rows_for(ergo.report(suite_doc, req), "s", "$min_subjects")[0].cause == "absent" with data.params as {}
	rows_for(ergo.report(suite_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"suites": null}
	every bad in ["unit-test", {"a": 1}, true, 3] {
		rep := ergo.report(suite_doc, req) with data.params as {"suites": bad}
		rep.requirements.s.satisfied == false
		rows_for(rep, "s", "$min_subjects")[0].cause == "unusable"
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
	ergo.report(suite_doc, req).requirements.s.satisfied == false with data.params as {}
}

test_keys_from_a_ref_that_cannot_be_read_show_up_in_violations if {
	vs := ergo.violations(ergo.report(suite_doc, suites_from_params)) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope test run count", "value": 0}, {"name": "$$params.suites", "value": null}]]]
}

test_an_empty_list_of_keys_from_a_ref_is_like_an_empty_list_written_out if {
	rep := ergo.report(suite_doc, suites_from_params) with data.params as {"suites": []}
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rows_for(rep, "s", "$min_subjects")[0].cause == "value"
	zero := ergo.report(suite_doc, {"s": object.union(suites_from_params.s, {"min_subjects": 0})}) with data.params as {"suites": []}
	zero.requirements.s.satisfied == true
}

test_keys_can_be_written_as_a_literal if {
	rep := ergo.report(suite_doc, suite_req({"each_as": "run", "keys": {"literal": ["unit-test"]}}))
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["unit-test", true]]
}

test_keys_and_a_ref_step_can_both_come_from_params if {
	rep := ergo.report(suite_doc, {"s": {
		"from": ["build", {"ref": ["$$params", "where"]}, {"each_as": "run", "keys": {"ref": ["$$params", "suites"]}}],
		"checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}},
	}}) with data.params as {"where": "test_runs", "suites": ["unit-test"]}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["unit-test", true]]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$$params.suites", "value": ["unit-test"]}, {"name": "$$params.where", "value": "test_runs"}]
}

test_badly_written_keys_fail_well_formed_not_the_search_for_subjects if {
	every keys in ["unit-test", {"literal": "unit-test"}, {"ref": ["$$params", "s"], "note": "x"}] {
		rep := ergo.report(suite_doc, suite_req({"each_as": "run", "keys": keys}))
		[[r.check, r.passed, r.cause] | some r in rep.results] == [["$well_formed", false, "value"], ["$min_subjects", false, "value"]]
	}
}

test_keys_from_a_ref_to_a_name_fail_as_an_invalid_ref if {
	rep := ergo.report(suite_doc, suite_req({"each_as": "run", "keys": {"ref": ["$pr", "suites"]}}))
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rows_for(rep, "s", "$min_subjects")[0].cause == "absent"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "<invalid ref>", "value": null}]
}

test_a_ref_inside_a_list_of_keys_is_read if {
	rep := ergo.report(suite_doc, suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "extra"]}, "unit-test"]})) with data.params as {"extra": "smoke-test"}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["smoke-test", false], ["unit-test", true]]
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$$params.extra", "value": "smoke-test"}]
}

test_a_ref_inside_a_list_of_keys_that_cannot_be_read_fails_the_requirement_rather_than_dropping_the_key if {
	req := {"s": object.union(suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "extra"]}, "unit-test"]}).s, {"min_subjects": 0})}
	every params in [{}, {"extra": null}, {"extra": ["smoke-test"]}] {
		rep := ergo.report(suite_doc, req) with data.params as params
		rep.requirements.s.satisfied == false
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
	rows_for(ergo.report(suite_doc, req), "s", "$min_subjects")[0].cause == "null" with data.params as {"extra": null}
}

test_a_literal_inside_a_list_of_keys_is_read_as_written if {
	rep := ergo.report({"o": {"$x": {"result": "passed"}}}, {"s": {"from": ["o", {"each_as": "k", "keys": [{"literal": "$x"}]}], "checks": {"c": {"op": "equals", "path": ["result"], "value": "passed"}}}})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["$x", true]]
}

test_refs_inside_a_literal_list_of_keys_are_not_read if {
	rep := ergo.report({"o": {"a": {}}}, {"s": {"from": ["o", {"each_as": "k", "keys": {"literal": [{"ref": ["$$params", "s"]}]}}], "checks": {"c": {"op": "present", "path": []}}}}) with data.params as {"s": "a"}
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[{"ref": ["$$params", "s"]}, false]]
	not rep.requirements.s.checks["$min_subjects"]["$refs"]
}

test_a_badly_written_ref_inside_a_list_of_keys_is_not_well_formed if {
	rep := ergo.report(suite_doc, {"s": object.union(suite_req({"each_as": "run", "keys": [{"ref": ["$$params", "s"], "note": "x"}, "unit-test"]}).s, {"min_subjects": 0})}) with data.params as {"s": "smoke-test"}
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.requirements.s.satisfied == false
}

test_ref_shaped_values_in_params_are_data_not_refs if {
	rep := ergo.report({"o": {"a": {}}}, {"s": {"from": ["o", {"each_as": "k", "keys": {"ref": ["$$params", "list"]}}], "checks": {"c": {"op": "present", "path": []}}}}) with data.params as {"list": [{"ref": ["$$params", "s"]}], "s": "a"}
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
		rep := ergo.report(typo_doc, typo_req(filter))
		rep.requirements.s.satisfied == false
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unusable"]
	}
}

test_a_check_whose_ref_reads_the_wrong_kind_of_value_fails_and_is_not_ill_formed if {
	every check in read_the_wrong_kind {
		rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "unusable"]]
	}
}

test_a_badly_written_filter_cannot_rule_subjects_out if {
	every filter in badly_written {
		rep := ergo.report(typo_doc, typo_req(filter))
		rep.requirements.s.satisfied == false
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
	}
}

test_a_badly_written_check_is_ill_formed if {
	every check in badly_written {
		rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
	}
}

test_an_operator_that_is_not_declared_fails_even_when_a_rule_passes_it if {
	ergo.op_passed({"op": "undeclared", "path": ["n"]}, {"n": 1})
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "undeclared", "path": ["n"]}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_badly_written_option_fails_an_any_of_even_when_another_option_passes if {
	check := {"op": "any_of", "options": {"good": [{"op": "present", "path": ["n"]}], "bad": [{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "bad"}]}}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_badly_written_substitute_fails_the_check_even_when_the_check_passes if {
	check := {"op": "present", "path": ["n"], "substitute": {"op": "nope", "path": ["n"]}}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
}

test_a_bound_that_reads_null_keeps_the_cause_of_its_ref if {
	check := {"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "none"]}, "max": 5}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
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
		rep := ergo.report(typo_doc, typo_req(filter))
		rep.requirements.s.satisfied == true
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
	}
}

test_a_present_filter_on_a_name_nothing_gives_cannot_rule_subjects_out if {
	every path in [["$p", "n"], ["$$nope", "n"]] {
		rep := ergo.report({"items": [{"id": 1, "n": 1}]}, {"s": {
			"from": ["items", {"each_as": "item"}],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": {"op": "present", "path": path}},
			"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
		}})
		rep.requirements.s.satisfied == false
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["ill_formed"]
	}
}

test_a_present_filter_on_a_given_name_still_rules_subjects_out if {
	rep := ergo.report({"items": [{"id": 1}]}, {"s": {
		"from": ["items", {"each_as": "item"}],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["$item", "n"]}},
		"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
	}})
	rep.requirements.s.satisfied == true
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_a_check_fails_when_its_substitute_passes_but_one_side_is_badly_written if {
	every check in [
		{"op": "equals", "path": ["n"], "value": 999, "substitute": {"op": "undeclared", "path": ["n"]}},
		{"op": "nope", "path": ["n"], "substitute": {"op": "present", "path": ["n"]}},
	] {
		rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "ill_formed"]]
	}
}

test_a_present_filter_with_a_badly_written_substitute_cannot_rule_subjects_out if {
	rep := ergo.report(typo_doc, typo_req({"op": "present", "path": ["missing"], "substitute": {"op": "nope", "path": ["n"]}}))
	rep.requirements.s.satisfied == false
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
		rep := ergo.report(object.union(typo_doc, {"params": {"nobody": []}}), typo_req(filter))
		rep.requirements.s.satisfied == true
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
	}
}

test_an_each_written_as_one_key_still_reads_the_inner_lists if {
	verdict({"xs": [{"a": [1]}]}, {"op": "all", "path": ["xs"], "each": "a", "check": {"op": "equals", "path": [], "value": 1}}) == true
}

test_a_range_with_equal_bounds_is_well_written if {
	verdict({"n": 1}, {"op": "range", "path": ["n"], "min": 1, "max": 1}) == true
}

test_a_check_that_is_not_an_object_shows_in_the_expression if {
	rendered({}, "present") == "<invalid check>"
	[[r.passed, r.cause] | some r in solo({}, "present").results; r.check == "c"] == [[false, "ill_formed"]]
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
		rep := ergo.report({"items": [ordering_doc]}, {"s": {
			"from": ["items"],
			"id": ["id"],
			"min_subjects": 0,
			"applies_to": {"f": filter},
			"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
		}})
		rep.requirements.s.satisfied == false
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unusable"]
	}
}

test_a_present_filter_with_a_substitute_ordering_numbers_still_rules_subjects_out if {
	rep := ergo.report({"items": [ordering_doc]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"min_subjects": 0,
		"applies_to": {"f": {"op": "present", "path": ["missing"], "substitute": {"op": "compare", "left": ["n"], "right": ["m"], "cmp": "gt"}}},
		"checks": {"c": {"op": "equals", "path": ["n"], "value": 999}},
	}})
	rep.requirements.s.satisfied == true
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

one_item := {"items": [{"id": 1}]}

test_a_policy_that_is_not_an_object_is_not_compliant if {
	ergo.report(one_item, 5).compliant == false
}

test_a_requirement_that_is_not_an_object_is_not_compliant if {
	ergo.report(one_item, {"s": 5}).compliant == false
}

test_checks_that_are_not_an_object_are_not_compliant if {
	ergo.report(one_item, {"s": {"from": ["items"], "checks": 5}}).compliant == false
}

test_an_applies_to_that_is_a_number_is_not_compliant if {
	ergo.report(one_item, {"s": {"from": ["items"], "applies_to": 5, "checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_an_applies_to_that_is_a_string_is_not_compliant if {
	ergo.report(one_item, {"s": {"from": ["items"], "applies_to": "x", "checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_a_filter_whose_custom_expression_is_not_a_string_still_filters if {
	rep := ergo.report(one_item, {"s": {
		"from": ["items"],
		"applies_to": {"f": {"op": "present", "path": ["id"], "expression": ["id"]}},
		"checks": {"c": {"op": "present", "path": ["id"]}},
	}})
	rep.compliant == true
}

test_an_input_that_is_a_string_without_from_is_not_compliant if {
	ergo.report("x", {"s": {"checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_an_input_that_is_a_list_without_from_is_not_compliant if {
	ergo.report([{"id": 1}], {"s": {"checks": {"c": {"op": "present", "path": ["id"]}}}}).compliant == false
}

test_a_selector_on_a_subject_that_is_not_an_object_fails_as_not_an_object if {
	rep := ergo.report({"items": ["b"]}, {"s": {"from": ["items"], "checks": {"c": {"op": "equals", "path": [{"where": {"id": 1}}, "n"], "value": 1}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "not_an_object"]]
}

test_a_ref_that_starts_with_a_number_fails_closed if {
	cause_of({"id": 1}, {"op": "equals", "path": ["id"], "value": {"ref": [5, "x"]}}) == "ill_formed"
}
