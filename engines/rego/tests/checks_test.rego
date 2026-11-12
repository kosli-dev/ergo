package ergo_test

import data.ergo
import rego.v1

test_nested_from_resolves_through_objects if {
	subject_counts({"a": {"b": {"items": [{"id": "x"}]}}}, "every .a.b.items") == {"total": 1, "matching": 1}
}

test_range_inside if verdict({"temp_c": 5}, in_range) == true

test_range_at_lower_bound if verdict({"temp_c": 0}, in_range) == true

test_range_at_upper_bound if verdict({"temp_c": 10}, in_range) == true

test_range_below_bound if verdict({"temp_c": -1}, in_range) == false

test_range_above_bound if verdict({"temp_c": 11}, in_range) == false

test_excludes_when_value_absent if verdict({"labels": ["ready"]}, no_wip) == true

test_excludes_over_empty_array if verdict({"labels": []}, no_wip) == true

test_excludes_when_value_present if verdict({"labels": ["ready", "wip"]}, no_wip) == false

test_includes_when_value_present if verdict({"labels": ["approved"]}, has_approved) == true

test_includes_when_value_absent if verdict({"labels": ["ready"]}, has_approved) == false

test_includes_over_empty_array if verdict({"labels": []}, has_approved) == false

no_allergens := "allergens contains none of \"nuts\", \"garlic\""

test_excludes_values_passes_when_the_field_holds_none_of_them if {
	verdict({"allergens": ["milk"]}, no_allergens) == true
	verdict({"allergens": []}, no_allergens) == true
}

test_excludes_values_fails_when_the_field_holds_any_one_of_them if {
	every allergens in [["garlic", "milk"], ["nuts"], ["nuts", "garlic"]] {
		[verdict({"allergens": allergens}, no_allergens), cause_of({"allergens": allergens}, no_allergens)] == [false, "value"]
	}
}

all_signed_off := "sign_offs contains all of \"qa\", \"security\""

test_includes_values_passes_when_the_field_holds_all_of_them if {
	verdict({"sign_offs": ["security", "qa"]}, all_signed_off) == true
	verdict({"sign_offs": ["qa", "legal", "security"]}, all_signed_off) == true
}

test_includes_values_fails_when_the_field_misses_any_one_of_them if {
	every sign_offs in [["qa"], ["security"], []] {
		[verdict({"sign_offs": sign_offs}, all_signed_off), cause_of({"sign_offs": sign_offs}, all_signed_off)] == [false, "value"]
	}
}

test_includes_and_excludes_values_fail_closed_on_a_missing_null_or_wrong_typed_field if {
	every pair in [["allergens", no_allergens], ["sign_offs", all_signed_off]] {
		[field, check] := pair
		[verdict({}, check), cause_of({}, check)] == [false, "absent"]
		[verdict({field: null}, check), cause_of({field: null}, check)] == [false, "null"]
		[verdict({field: "nuts"}, check), cause_of({field: "nuts"}, check)] == [false, "unusable"]
	}
}

allowed_licence := "id is one of \"MIT\", \"Apache-2.0\""

test_in_when_field_is_one_of_the_values if verdict({"id": "Apache-2.0"}, allowed_licence) == true

test_in_when_field_is_none_of_the_values if verdict({"id": "GPL-3.0"}, allowed_licence) == false

test_in_is_type_sensitive if verdict({"n": "1"}, "n is one of 1, 2") == false

test_in_matches_numbers if verdict({"n": 2}, "n is one of 1, 2") == true

test_in_fails_closed_on_a_missing_field if {
	verdict({}, allowed_licence) == false
	cause_of({}, allowed_licence) == "absent"
}

test_in_fails_closed_on_a_null_field if {
	verdict({"id": null}, allowed_licence) == false
	cause_of({"id": null}, allowed_licence) == "null"
}

test_in_does_not_match_a_null_field_against_null_in_values if {
	verdict({"id": null}, "id is one of null, \"MIT\"") == false
}

test_in_fails_closed_on_a_wrong_typed_field if verdict({"id": ["MIT"]}, allowed_licence) == false

test_in_shows_the_field_value_in_inputs if {
	inputs_of({"id": "GPL-3.0"}, allowed_licence) == [{"name": "id", "value": "GPL-3.0", "locations": ["/items/0/id"]}]
}

test_equals_on_match if verdict({"state": "MERGED"}, is_merged) == true

test_equals_on_mismatch if verdict({"state": "CLOSED"}, is_merged) == false

test_equals_is_type_sensitive if verdict({"n": "1"}, "n is 1") == false

test_equals_compares_booleans if verdict({"verified": true}, "verified is true") == true

test_equals_null_matches_an_explicit_null if {
	verdict({"x": null}, "x is null") == true
}

test_present_when_set if verdict({"fingerprint": "abc"}, has_fingerprint) == true

test_present_accepts_empty_string if verdict({"fingerprint": ""}, has_fingerprint) == true

test_present_accepts_false if verdict({"fingerprint": false}, has_fingerprint) == true

test_non_empty_string_when_filled if verdict({"fingerprint": "abc"}, filled) == true

no_fingerprint := "fingerprint does not exist"

test_missing_when_the_field_is_not_there if verdict({}, no_fingerprint) == true

test_missing_when_the_field_is_null if verdict({"fingerprint": null}, no_fingerprint) == true

test_missing_fails_as_value_when_the_field_is_set if {
	every v in ["abc", "", false, 0, [], {}] {
		[verdict({"fingerprint": v}, no_fingerprint), cause_of({"fingerprint": v}, no_fingerprint)] == [false, "value"]
	}
}

test_missing_passes_when_a_step_before_the_field_is_not_there_or_is_null if {
	check := "build.fingerprint does not exist"
	verdict({}, check) == true
	verdict({"build": null}, check) == true
	verdict({"build": {}}, check) == true
}

test_missing_reads_past_the_end_of_a_list_as_missing if verdict({"xs": [1]}, "item 4 of xs does not exist") == true

test_missing_fails_as_unusable_when_a_step_before_the_field_cannot_hold_it if {
	every pair in [
		[{"build": "abc"}, "build.fingerprint"],
		[{"build": 5}, "build.fingerprint"],
		[{"build": ["abc"]}, "build.fingerprint"],
		[{"build": {}}, "item 1 of build"],
	] {
		[verdict(pair[0], concat(" ", [pair[1], "does not exist"])), cause_of(pair[0], concat(" ", [pair[1], "does not exist"]))] == [false, "unusable"]
	}
}

test_present_and_missing_fail_as_unusable_when_a_step_before_the_field_cannot_hold_it if {
	cause_of({"a": "x"}, ".a.b exists") == "unusable"
	cause_of({"a": "x"}, ".a.b does not exist") == "unusable"
}

clean_labels := {"any_of": {"no_labels": "labels does not exist", "clean": "labels does not contain \"do-not-merge\""}}

test_missing_in_any_of_lets_a_missing_field_pass_a_check if {
	[verdict({}, clean_labels), verdict({"labels": ["ok"]}, clean_labels)] == [true, true]
	[verdict({"labels": ["do-not-merge"]}, clean_labels), cause_of({"labels": ["do-not-merge"]}, clean_labels)] == [false, "value"]
	[verdict({"labels": "do-not-merge"}, clean_labels), cause_of({"labels": "do-not-merge"}, clean_labels)] == [false, "unusable"]
}

compare_ab(op) := concat(" ", [".a", {"eq": "equals", "ne": "does not equal", "gt": "is more than", "gte": "is at least", "lt": "is less than", "lte": "is at most"}[op], "b"])

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

test_compare_does_not_order_two_strings if cause_of({"a": "abc", "b": "abd"}, compare_ab("lt")) == "unusable"

test_matches_any_matches_a_prefix_pattern if {
	verdict({"author": "svc_release <svc_release@example.com>"}, matches("matches_any")) == true
}

test_matches_any_matches_a_bracketed_bot if {
	verdict({"author": "dependabot[bot]"}, matches("matches_any")) == true
}

test_matches_any_is_unanchored if {
	verdict({"author": "GitHub <noreply@github.com>"}, matches("matches_any")) == true
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

span := {"start": "2024-01-01T00:00:00Z", "end": "2024-06-01T00:00:00Z"}

test_compare_time_lt if verdict(span, compare_time_span("lt")) == true

test_compare_time_gt if verdict(span, compare_time_span("gt")) == false

test_compare_time_normalises_offsets if {
	doc := {"start": "2024-01-01T12:00:00Z", "end": "2024-01-01T13:00:00+01:00"}
	verdict(doc, compare_time_span("gte")) == true
	verdict(doc, compare_time_span("lte")) == true
}

test_compare_time_respects_sub_second_precision if {
	doc := {"start": "2024-01-01T00:00:00.000000001Z", "end": "2024-01-01T00:00:00.000000002Z"}
	verdict(doc, compare_time_span("lt")) == true
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

test_compare_time_orders_two_dates_without_a_time if {
	verdict({"start": "2024-01-01", "end": "2024-06-01"}, compare_time_span("lt")) == true
}

test_compare_time_accepts_epoch_seconds if {
	verdict({"start": 1753600000, "end": 1753603600}, compare_time_span("lt")) == true
}

test_compare_time_orders_epoch_seconds if {
	verdict({"start": 1753603600, "end": 1753600000}, compare_time_span("lt")) == false
	verdict({"start": 1753603600, "end": 1753600000}, compare_time_span("gt")) == true
}

test_compare_time_compares_equal_epochs if {
	verdict({"start": 1753600000, "end": 1753600000}, compare_time_span("gte")) == true
	verdict({"start": 1753600000, "end": 1753600000}, compare_time_span("lte")) == true
}

test_all_when_one_element_fails if {
	verdict({"commits": [{"verified": true}, {"verified": false}]}, all_verified) == false
}

test_all_when_an_element_is_missing_the_field if {
	verdict({"commits": [{"verified": true}, {"sha1": "abc"}]}, all_verified) == false
}

test_any_when_no_element_passes if {
	verdict({"approvers": [{"state": "COMMENTED"}]}, any_approved) == false
}

test_any_over_empty_collection if verdict({"approvers": []}, any_approved) == false

test_any_of_passes_when_one_option_is_wholly_satisfied if {
	verdict({"type": "Story", "state": "CLOSED"}, flavoured) == true
}

test_any_of_passes_on_any_of_the_options_not_just_the_first if {
	verdict({"type": "SAFe Story", "state": "DONE"}, flavoured) == true
}

test_any_of_fails_closed_on_empty_options if stopped(solo({"type": "Story"}, {"any_of": {}}))

test_any_of_with_single_leaf_options_is_a_plain_disjunction if {
	single := {"any_of": {"by_type": "type is \"Story\"", "by_state": "state is \"DONE\""}}
	verdict({"type": "Story", "state": "OPEN"}, single) == true
	verdict({"type": "Chore", "state": "DONE"}, single) == true
	verdict({"type": "Chore", "state": "OPEN"}, single) == false
}

test_any_of_rendering_is_order_independent if {
	reordered := {"any_of": {"safe": ["type matches \"^SAFe Story$\"", "state matches \"^DONE$\""], "standard": ["type matches \"^Story$\"", "state matches \"^CLOSED$\""]}}
	rendered({"type": "Story"}, reordered) == rendered({"type": "Story"}, flavoured)
}

test_any_of_echoes_a_field_only_one_option_reads if {
	check := {"any_of": {"a": "type is \"Story\"", "b": "project is \"PA\""}}
	inputs_of({"type": "Chore", "project": "PA"}, check) == [
		{"name": "project", "value": "PA", "locations": ["/items/0/project"]},
		{"name": "type", "value": "Chore", "locations": ["/items/0/type"]},
	]
}

test_any_of_echoes_both_sides_of_a_two_sided_leaf if {
	check := {"any_of": {"a": "approved_at is more than committed_at"}}
	inputs_of({"approved_at": 200, "committed_at": 100}, check) == [
		{"name": "approved_at", "value": 200, "locations": ["/items/0/approved_at"]},
		{"name": "committed_at", "value": 100, "locations": ["/items/0/committed_at"]},
	]
}

test_any_of_echoes_an_absent_field_as_null if {
	inputs_of({"type": "Story"}, flavoured) == [
		{"name": "state", "value": null, "locations": ["/items/0"]},
		{"name": "type", "value": "Story", "locations": ["/items/0/type"]},
	]
}

test_inputs_echo_the_read_path if {
	inputs_of({"state": "MERGED"}, is_merged) == [{"name": "state", "value": "MERGED", "locations": ["/items/0/state"]}]
}

test_inputs_echo_null_for_a_missing_field if {
	inputs_of({}, is_merged) == [{"name": "state", "value": null, "locations": ["/items/0"]}]
}

test_inputs_name_nested_paths_with_dots if {
	check := ".a.b is 1"
	inputs_of({"a": {"b": 1}}, check) == [{"name": ".a.b", "value": 1, "locations": ["/items/0/a/b"]}]
}

test_an_any_of_reading_a_dotted_key_and_a_nested_path_gives_a_report if {
	check := {"any_of": {"x": "\"a.b\" exists", "y": ".a.b exists"}}
	inputs_of({"id": 1, "a.b": "dotted", "a": {"b": "nested"}}, check) == [
		{"name": `"a.b"`, "value": "dotted", "locations": ["/items/0/a.b"]},
		{"name": ".a.b", "value": "nested", "locations": ["/items/0/a/b"]},
	]
}

test_inputs_echo_both_sides_of_a_comparison if {
	inputs_of({"a": 1, "b": 2}, compare_ab("lt")) == [
		{"name": ".a", "value": 1, "locations": ["/items/0/a"]},
		{"name": "b", "value": 2, "locations": ["/items/0/b"]},
	]
}

test_a_ref_step_that_reads_something_that_cannot_be_a_key_fails_as_unusable if {
	check := ".a named by $params.i exists"
	every i in [1, 0, -1, 1.5, true, {"a": 1}, ["a"]] {
		r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": i}
		[r[0], r[1]] == [false, "unusable"]
	}
	params_rows({"items": [{"id": 1, "a": {"x": 2}}]}, check) == [[true, "satisfied", [{"name": ".a named by $params.i", "value": 2, "locations": ["/items/0/a/x"]}]]] with data.params as {"i": "x"}
}

test_a_ref_step_that_reads_a_number_fails_as_unusable_so_does_not_exist_cannot_pass if {
	check := ".a named by $params.i does not exist"
	every i in [2, 9007199254740991, 9007199254740992, 1e20] {
		r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": i}
		[r[0], r[1]] == [false, "unusable"]
	}
}

test_a_check_with_a_number_too_big_for_a_float_fails_closed if {
	stopped(solo({"id": 1, "n": 1e400}, "n is 1e400"))
}

test_a_check_with_a_number_too_small_for_a_float_fails_closed_so_it_cannot_pass_as_zero if {
	stopped(solo({"id": 1, "n": 0}, "n is 1e-400"))
	stopped(solo({"id": 1, "n": 1e-400}, "n is 1e-400"))
}

test_a_number_a_float_cannot_hold_in_the_input_is_compared_exactly if {
	compare := ".a equals b"
	[verdict({"id": 1, "a": 1e400, "b": 1e400}, compare), verdict({"id": 1, "a": 1e400, "b": 2e400}, compare)] == [true, false]
	[verdict({"id": 1, "a": 1e-400, "b": 0}, compare), cause_of({"id": 1, "a": 1e-400, "b": 0}, compare)] == [false, "value"]
}

test_a_number_at_the_edge_of_a_float_still_works if {
	verdict({"id": 1, "n": 1.79769313486231e308}, "n is 1.79769313486231e308") == true
	verdict({"id": 1, "n": 2.22507385850721e-308}, "n is 2.22507385850721e-308") == true
	verdict({"id": 1, "n": 0}, "n is 0") == true
	stopped(solo({"id": 1, "n": 2.2250738585072e-308}, "n is 2.2250738585072e-308"))
}

test_expression_for_non_empty_string if rendered({}, filled) == "fingerprint is a non-empty string"

test_row_carries_exactly_the_documented_keys if {
	every row in solo({"state": "MERGED"}, is_merged).results {
		object.keys(row) == {"requirement", "subject", "check", "inputs", "passed", "cause"}
	}
}

test_cause_satisfied_when_the_check_holds if {
	cause_of({"state": "MERGED"}, "state is \"MERGED\"") == "satisfied"
}

test_cause_value_when_the_paths_read_cleanly_and_the_assertion_is_false if {
	cause_of({"state": "OPEN"}, "state is \"MERGED\"") == "value"
}

test_cause_absent_when_the_path_is_not_there if {
	cause_of({}, "state is \"MERGED\"") == "absent"
}

test_cause_null_when_the_path_is_there_and_null if {
	cause_of({"state": null}, "state is \"MERGED\"") == "null"
}

test_cause_precedence_prefers_the_more_fundamental_defect if {
	cause_of({"left": null}, "left is less than right") == "absent"
}

test_cause_precedence_reports_null_only_when_nothing_worse_happened if {
	cause_of({"left": null, "right": null}, "left is less than right") == "null"
}

test_synthesised_rows_carry_a_cause if {
	rep := report({"items": []}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
		"checks": {"c": "x exists"},
	}})
	rows_for(rep, "s", "$well_formed")[0].cause == "satisfied"
	rows_for(rep, "s", "$min_subjects")[0].cause == "value"
}

test_a_field_on_a_list_input_is_unusable if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input.commits"})}
	every doc in [[{"commits": [{"id": "a"}]}], []] {
		[[r.passed, r.cause] | some r in rows_for(report(doc, req), "s", "$min_subjects")] == [[false, "unusable"]]
	}
}

test_the_engine_gives_only_its_name_and_version_because_anything_about_the_machine_would_make_the_report_depend_on_more_than_the_policy_and_input if {
	ergo.report(_engine_doc, _engine_policy, {}).engine == {"name": "ergo-rego", "version": ergo.version}
}

test_the_version_on_main_ends_in_dev_because_only_the_release_workflow_drops_it if {
	regex.match(`^[0-9]+\.[0-9]+\.[0-9]+-dev$`, ergo.version)
}

test_a_report_from_an_input_json_cannot_hold_is_left_as_built if {
	rep := report({"items": [{"id": 1.50, "t": {"a"}}]}, {"s": object.union(typed_req, {"checks": {"c": "t exists"}})})
	some row in rep.results
	row.check == "c"
	is_set(row.inputs[0].value)
}

test_the_policys_own_problems_are_sorted_by_name if {
	_spec_rows(two_reqs_policy({"ergo_spec": 1, "description": 5, "meta": "x"}))[1][0] == ["s", false, [
		{"name": "policy description", "value": ["not a string"], "locations": []},
		{"name": "policy ergo_spec", "value": ["not a string"], "locations": []},
		{"name": "policy meta", "value": ["not an object"], "locations": []},
	]]
}

test_problems_with_several_fields_are_listed_by_field if {
	req := {"from": 5, "require": "most", "zz": 1, "checks": {}, "min_subjects": -1}
	row := rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0]
	row.inputs == [
		{"name": "count(checks)", "value": 0, "locations": []},
		{"name": "require", "value": ["neither every nor some"], "locations": []},
		{"name": "checks", "value": ["empty"], "locations": []},
		{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []},
		{"name": "zz", "value": ["unknown field"], "locations": []},
		{"name": "subjects.subject.from", "value": ["not a string"], "locations": []},
	]
}

test_checks_that_are_not_an_object_give_no_rows_named_by_list_index if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"checks": ["id exists"]})})
	stopped(rep)
	rows_for(rep, "s", "$well_formed")[0].inputs[0] == {"name": "count(checks)", "value": 0, "locations": []}
}

test_unknown_require_value_is_not_met if {
	report(both_ok, require_req("most")).requirements.s.status == "not_met"
}

test_report_carries_exactly_the_documented_keys if {
	object.keys(solo({}, is_merged)) == {"compliant", "description", "engine", "ergo", "meta", "requirements", "results", "subjects"}
}

test_report_is_deterministic if {
	doc := {"items": [{"id": "b", "state": "MERGED"}, {"id": "a", "state": "CLOSED"}]}
	rep := report(doc, two_check_req)
	json.marshal(rep) == json.marshal(report(doc, two_check_req))
}

test_row_order_is_independent_of_policy_key_order if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	first := {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "id exists"}}
	second := {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "id exists"}}

	json.marshal(report(doc, {"first": first, "second": second})) == json.marshal(report(doc, {"second": second, "first": first}))
}

test_checks_come_out_in_name_order_whatever_the_runtime if {
	check := "id exists"
	rep := report({"items": [{"id": 1}]}, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check, "b": check, "a": check, "delta": check, "gamma": check}}})
	[r.check | some r in rep.results; not startswith(r.check, "$")] == ["a", "b", "c", "delta", "gamma"]
}

test_an_not_met_report_always_explains_itself_under_some if count(unexplained("some")) == 0

test_an_not_met_report_always_explains_itself_under_a_bad_require if count(unexplained("most")) == 0

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

test_equals_null_does_not_pass_on_a_missing_field if {
	verdict({}, "x is null") == false
}

test_all_over_an_empty_collection_is_not_a_pass if {
	verdict({"commits": []}, all_verified) == false
}

test_a_present_check_on_a_missing_field_is_a_clean_no if {
	cause_of({}, "lock exists") == "value"
}

test_an_input_path_reads_from_the_top_of_the_document if {
	r := row_in({"mode": "strict"}, {"id": 1}, "$input.mode is \"strict\"")
	[r.passed, r.cause, r.inputs] == [true, "satisfied", [{"name": "$input.mode", "value": "strict", "locations": ["/mode"]}]]
}

test_an_input_path_fails_closed_when_it_leads_nowhere if {
	check := "$input.mode is \"strict\""
	[row_in({}, {"id": 1}, check).passed, row_in({}, {"id": 1}, check).cause] == [false, "absent"]
	[row_in({"mode": null}, {"id": 1}, check).passed, row_in({"mode": null}, {"id": 1}, check).cause] == [false, "null"]
}

test_input_is_only_a_name_at_the_start_of_a_path if {
	row_in({}, {"id": 1, "a": {"$$input": "x"}}, ".a.\"$$input\" is \"x\"").passed == true
}

test_a_literal_path_step_reads_a_key_that_looks_like_a_name if {
	r := row_in({"$$input": "top"}, {"id": 1, "$$input": "x"}, "\"$$input\" is \"x\"")
	[r.passed, r.inputs] == [true, [{"name": `"$$input"`, "value": "x", "locations": ["/items/0/$$input"]}]]
}

test_a_check_without_refs_has_no_refs_in_its_definition if {
	not "$refs" in object.keys(in_doc({}, {"id": 1}, "id exists").requirements.s.checks.c)
}

test_a_policy_that_is_not_an_object_is_not_compliant if {
	every policy in [null, true, 1, "requirements", [], [params_req("id exists")]] {
		has_only_the_policy_row(ergo.report({"items": [{"id": 1}]}, policy, {}))
	}
}

test_sections_ergo_does_not_know_leave_the_report_unchanged if {
	policy := lifted(params_req("id exists"))
	rep := ergo.report({"items": [{"id": 1}]}, policy, {})
	rep.compliant == true
	ergo.report({"items": [{"id": 1}]}, object.union(policy, {"notes": "reviewed by the platform team"}), {}) == rep
}

trail_rows(check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(trail_doc, trail_req(check)), "s", "c")]

test_a_ref_step_in_a_path_reads_the_key_it_names if {
	trail_rows(attested) == [[true, "satisfied", [{"name": "attestations named by $params.att.status", "value": "COMPLETE", "locations": ["/trail/artifacts/app/attestations/pull-request/status"]}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	trail_rows(attested) == [[false, "value", [{"name": "attestations named by $params.att.status", "value": "FAILED", "locations": ["/trail/artifacts/app/attestations/junit/status"]}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_step_is_never_a_list_position if {
	check := "tags named by $params.i is \"v2\""
	[r[0] | some r in trail_rows(check)] == [false] with data.params as {"artifact": "app", "i": 1}
}

test_a_ref_step_that_cannot_be_read_fails_the_check if {
	trail_rows(attested) == [[false, "absent", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app"}
	trail_rows(attested) == [[false, "null", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app", "att": null}
	every bad in [["pull-request"], {"k": "pull-request"}, true] {
		trail_rows(attested) == [[false, "unusable", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app", "att": bad}
	}
}

test_a_ref_step_at_the_end_of_from_is_not_a_naming_step if {
	rep := report(trail_doc, trail_req("fingerprint exists")) with data.params as {"artifact": "app"}
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_ordering_numbers_still_works if {
	verdict(ordering_doc, "n is less than m") == true
	cause_of(ordering_doc, "m is less than n") == "value"
}

test_ordering_two_strings_fails_as_unusable if {
	cause_of(ordering_doc, "z is more than s") == "unusable"
}

test_ordering_a_number_against_a_string_fails_as_unusable if {
	cause_of(ordering_doc, "n is less than s") == "unusable"
}

test_eq_and_ne_still_compare_objects_lists_and_booleans if {
	cause_of(ordering_doc, ".a equals b") == "value"
	verdict(ordering_doc, "xs does not equal ys") == true
	cause_of(ordering_doc, "f equals t") == "value"
}

test_checks_that_are_not_an_object_are_not_compliant if {
	report(one_item, {"s": {"from": "items", "checks": 5}}).compliant == false
}

test_an_input_that_is_a_string_without_from_is_not_compliant if {
	report("x", {"s": {"checks": {"c": "id exists"}}}).compliant == false
}

test_an_input_that_is_a_list_without_from_is_not_compliant if {
	rep := ergo.report([{"id": 1}], {"ergo_spec": ergo._spec, "subjects": {"s": {}}, "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}}, {})
	rep.compliant == false
	[r.cause | some r in rep.results; r.check == "$min_subjects"] == ["unusable"]
}

test_a_key_that_is_not_a_string_in_the_input_fails_the_check_even_when_a_number_step_reaches_it if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "item 2 of x is \"a\""}}}
	rows_for(report({"items": [{"id": "a", "x": {1: "a"}}]}, req), "s", "c")[0].cause == "unusable"
}

lookalike_rows(doc, req) := [[r.check, r.subject.id, r.passed, r.cause, r.inputs] |
	some r in report(doc, req).results
	not startswith(r.check, "$")
]

test_a_field_holding_an_object_like_ergos_absent_marker_is_there if {
	lookalike_rows({"items": [{"id": 1, "o": absent_lookalike}]}, lookalike_req("items", {
		"m": "o does not exist",
		"p": "o exists",
	})) == [
		["m", 1, false, "value", [{"name": "o", "value": absent_lookalike, "locations": ["/items/0/o"]}]],
		["p", 1, true, "satisfied", [{"name": "o", "value": absent_lookalike, "locations": ["/items/0/o"]}]],
	]
}

test_the_and_of_between_is_not_the_and_between_assertions if {
	_read(`qty is between 1 and 5 and kind is "a"`).assertions[0].phrase == {"op": "is between", "min": 1, "max": 5}
	count(_read(`qty is between 1 and 5 and kind is "a"`).assertions) == 2
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

test_a_comparison_of_a_path_with_itself_is_listed_next_to_an_unknown_name_and_next_to_no_other_problem if {
	_sentence_problems(`x is x and y is $foo`) == ["unknown name $foo", "x is compared with itself"]
	_sentence_problems(`$foo is $foo`) == ["$foo is compared with itself", "unknown name $foo"]
	_sentence_problems(`x is x and x is not null and y is $foo`) == [`"is not null" is written "exists"`, "unknown name $foo"]
}

test_a_path_is_compared_with_itself_only_when_both_sides_read_the_same_thing if {
	not _sentence_problems({"for": "every zs as y", "assert": "every xs.y equals y"})
	not _sentence_problems({"for": "every environments as env, some deployments whose env equals env as deployment", "assert": "deployment.ok is true"})
	not _sentence_problems({"for": "every zs as y", "assert": "every xs.y equals .y"})
	_sentence_problems({"for": "every zs as y", "assert": ["x exists", "y equals y"]}) == ["line 2: y is compared with itself"]
}

test_comparisons_that_can_go_either_way_are_not_read_as_a_path_compared_with_itself if {
	every check in [
		`tags contains tags`, `x is in x`, `x is more than x plus 1`, `first of commits.x equals x`,
		`every xs.y equals $input.y`, `every xs.y equals z`, `every xs equals xs`,
		{"for": "some conditions as condition", "assert": "condition.type equals type"},
	] {
		not _sentence_problems(check)
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

test_is_not_one_of_passes_on_a_value_of_the_listed_type_that_is_not_listed_and_fails_as_unusable_on_another_type if {
	doc := {"things": [{"id": "a", "x": "dev"}, {"id": "b", "x": "prod"}, {"id": "c", "x": 5}, {"id": "d", "x": null}, {"id": "e"}]}
	[[r[0], r[2]] | some r in _sentence_rows({"v": `x is not one of "prod", "staging"`, "p": "x is not in $params.blocked"}, doc, {"blocked": ["prod"]})] == [
		["p", "satisfied"], ["v", "satisfied"],
		["p", "value"], ["v", "value"],
		["p", "unusable"], ["v", "unusable"],
		["p", "null"], ["v", "null"],
		["p", "absent"], ["v", "absent"],
	]
}

test_is_a_type_passes_on_that_json_type_and_fails_any_other_as_value if {
	doc := {"things": [{"id": "a", "x": []}, {"id": "b", "x": ""}, {"id": "c", "x": 0}, {"id": "d", "x": false}, {"id": "e", "x": {}}, {"id": "f", "x": null}, {"id": "g"}]}
	checks := {"b": "x is a boolean", "l": "x is a list", "n": "x is a number", "o": "x is an object", "s": "x is a string"}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {}); r[1]] == [["l", "satisfied"], ["s", "satisfied"], ["n", "satisfied"], ["b", "satisfied"], ["o", "satisfied"]]
	{r[2] | some r in _sentence_rows(checks, doc, {}); not r[1]} == {"value", "null", "absent"}
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

test_an_any_of_sorts_its_options_by_name_and_not_by_the_text_they_print if {
	r := ergo.report(
		{"things": []}, _sentence_policy({
			"c": {"any_of": {"a!": "x is 2", "a": "x is 1"}},
		}),
		{},
	)
	r.requirements.s.checks.c.expression == "one of: a(x is 1) | a!(x is 2)"
}

test_the_negative_phrases_never_pass_on_a_field_that_is_null_or_missing if {
	every sentence in [`x does not start with "a"`, `x does not end with "a"`, `x is alphabetically on or before "a"`, `x is alphabetically on or after "a"`, `x is not between 1 and 2`, `x is not 1 within 1`, `x contains some of 1`, `x does not contain all of 1`, `x is not a string`, `x is not a non-empty string`] {
		every subject in [{"x": null}, {}] {
			rows := _tally_rows(sentence, [object.union(subject, {"id": 1})], {})
			every row in rows {
				row[1] != "satisfied"
			}
		}
	}
}

test_a_number_with_trailing_zeros_is_added_exactly if {
	_tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.500000000000000000, "y": 1}], {})[0][2][0].value == 2.5
	[row[1] | some row in _tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.50, "y": 1}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.500000000000000000, "y": 1}], {})] == ["satisfied"]
}

test_a_between_does_not_make_an_and_a_bare_condition if {
	_read(`every ws that is between 1 and 3 ends with`) == {"problems": ["doesn't parse"]}
	_read(`every ws that is between 1 and 3 and ends with ends with`) == {"problems": ["a condition after and starts with whose or that"]}
	_read(`every ws that is "a and b" ends`) == {"problems": ["doesn't parse"]}
}

test_a_field_called_that_is_read_with_a_dot if {
	rep := _from_report({"xs": [{"that": "x"}, {"that": "y"}]}, {"s": {"from": `every xs whose .that is "x"`}}, {"c": "w is not empty"}, {})
	count([r | some r in rep.results; r.check == "c"]) == 1
}

test_named_by_a_field_that_holds_no_key_fails_with_its_cause if {
	doc := {"things": [
		{"id": 1, "age": 1},
		{"id": 2, "age": 1, "severity": null},
		{"id": 3, "age": 1, "severity": 3},
		{"id": 4, "age": 1, "severity": ["high"]},
		{"id": 5, "age": 1, "severity": "medium"},
		{"id": 6, "age": 1, "severity": "high"},
	]}
	rows := [[r.subject.id, r.cause] | some r in ergo.report(doc, _sentence_policy({"c": "age is at most $params.limits named by severity"}), {"limits": {"high": 5}}).results; r.check == "c"]
	rows == [[1, "absent"], [2, "null"], [3, "unusable"], [4, "unusable"], [5, "absent"], [6, "satisfied"]]
}

test_named_by_a_for_name_before_it_is_given_is_an_unknown_name if {
	_sentence_problems({"for": "every xs named by x as x", "assert": "x is 1"}) == ["for: unknown alias x"]
	_sentence_problems({"for": "every lists named by q as p, every qs as q", "assert": "p is 1"}) == ["for: unknown alias q"]
	_sentence_problems({"for": "every objs whose v named by o is 1 as o", "assert": "o exists"}) == ["for: unknown alias o"]
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

test_the_batched_swap_comparison_names_a_scenario_that_has_no_row_for_a_check if {
	_swap_differs({"results": [{"check": "c", "subject": {"id": "other"}}]}, {}, "s", {"c": "x is 1"})
}

test_a_between_after_a_plus_is_inclusive_and_fails_closed_on_text if {
	doc := {"things": [{"id": "a", "n": 3}, {"id": "b", "n": "3"}, {"id": "c", "n": null}, {"id": "d", "n": 1}, {"id": "e", "n": 6}]}
	rows := _sentence_rows({"c": "n plus 1 is between 2 and 4"}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [true, "satisfied"], [false, "value"]]
}

test_a_list_read_with_named_by_a_reference_that_is_null_or_not_a_key_fails_whatever_the_field_holds if {
	nulls := _sentence_rows({"c": "x is in $params.lists named by $params.nk"}, _named_things, _named_params)
	{r[2] | some r in nulls} == {"null"}
	objects := _sentence_rows({"c": "x is not in $params.lists named by $params.bk"}, _named_things, _named_params)
	{r[2] | some r in objects} == {"unusable"}
	missing := _sentence_rows({"c": "x is not in $params.lists named by $params.nope"}, _named_things, _named_params)
	{r[2] | some r in missing} == {"absent"}
}

test_a_tie_away_from_the_picked_position_doesnt_matter if {
	_picked_author("last of commits sorted by timestamp", [1, 1, 3]) == "linus"
}

test_a_list_can_be_sorted_by_time if {
	_picked_author("last of commits sorted by timestamp", ["2026-10-02T00:00:00Z", "2026-10-02T01:00:00+02:00", "2026-10-01T22:00:00Z"]) == "ada"
	_picked_author("first of commits sorted by timestamp", ["2026-10-02T00:00:00Z", "2026-10-02T01:00:00+02:00", "2026-10-01T22:00:00Z"]) == "linus"
}

test_a_position_past_the_end_or_an_empty_list_fails_as_absent if {
	[_picked(item, [1, 2])[0] | some item in ["item 3 of commits", "item 3 from last of commits sorted by timestamp"]] == ["absent", "absent"]
	[_picked("last of commits", [])[0]] == ["absent"]
}

test_numbers_and_times_in_one_sort_field_fail_as_unusable_on_the_times if {
	rows := _for_rows({"for": "last of xs sorted by t as x", "assert": "x exists"}, [{"id": 1, "xs": [{"t": 1}, {"t": "2026-10-01T00:00:00Z"}]}], {})
	rows[0][1] == "unusable"
	rows[0][2] == [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "unusable", "value": "2026-10-01T00:00:00Z", "failed_assertions": [], "locations": ["/things/0/xs/1/t"]}]
}

test_a_pick_can_come_second_and_start_from_the_first_name if {
	second := {"for": "some approvers as approver, item 5 of commits as c", "assert": "approver exists"}
	[row[1] | some row in _for_rows(second, [{"id": 1, "approvers": [1], "commits": [1]}], {})] == ["absent"]
	named := {"for": "every pull_requests as pr, last of pr.commits sorted by timestamp as c", "assert": `c.author is "grace"`}
	[row[1] | some row in _for_rows(
		named, [
			{"id": 1, "pull_requests": [{"commits": [{"author": "grace", "timestamp": 2}, {"author": "ada", "timestamp": 1}]}]},
			{"id": 2, "pull_requests": [{"commits": [{"author": "grace", "timestamp": 2}]}, {"commits": [{"author": "ada", "timestamp": 1}]}]},
		],
		{},
	)] == ["satisfied", "value"]
}

test_a_failed_line_lists_a_value_it_reads_twice_once if {
	things := [{"id": 1, "commits": [{"ts": 5, "files": ["a"]}]}]
	_line_inputs({"for": "every commits as c", "assert": "c.ts is at least c.ts plus 1"}, things) == [[
		{"name": "c.ts", "value": 5, "locations": ["/things/0/commits/0/ts"]},
		{"name": "c.ts plus 1", "value": 6, "locations": ["/things/0/commits/0/ts"]},
	]]
	_line_inputs({"for": "every commits as c", "assert": "count of c.files is at least count of c.files plus 1"}, things) == [[
		{"name": "count of c.files", "value": 1, "locations": ["/things/0/commits/0/files/0"]},
		{"name": "c.files[]", "value": ["a"], "locations": ["/things/0/commits/0/files/0"]},
		{"name": "count of c.files plus 1", "value": 2, "locations": ["/things/0/commits/0/files/0"]},
	]]
}

test_a_list_beside_the_first_still_passes_when_the_first_list_is_empty_and_may_be if {
	check := {"for": "every xs, if any, as x, every ys as y", "assert": "x.t is more than y.t"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": []}], {})] == ["satisfied"]
}

test_a_check_named_with_a_dollar_sign_later_in_its_name_is_allowed if {
	rep := reserved_check_rows("a$b")
	problem_inputs(rep) == []
	[r.passed | some r in rows_for(rep, "s", "a$b")] == [true]
}

test_a_check_named_like_one_of_ergos_own_rows_that_does_not_parse_is_listed_once if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {"$unique_ids": "id is"}})})
	problem_inputs(rep) == [{"name": "checks.$unique_ids", "value": ["a name can't start with $", "doesn't parse"], "locations": []}]
}

test_a_path_that_cannot_go_on_points_at_the_last_value_it_read if {
	doc := {"things": [{"id": "t1", "x": "text"}, {"id": "t2", "x": {"z": 1}}, {"id": "t3", "x": null}, {"id": "t4"}, {"id": "t5", "x": {"y": {"w": 1}}}]}
	_located_rows({"c": "x.y.k exists"}, doc, {}) == [
		["t1", "c", [{"name": "x.y.k", "locations": ["/things/0/x"]}]],
		["t2", "c", [{"name": "x.y.k", "locations": ["/things/1/x"]}]],
		["t3", "c", [{"name": "x.y.k", "locations": ["/things/2/x"]}]],
		["t4", "c", [{"name": "x.y.k", "locations": ["/things/3"]}]],
		["t5", "c", [{"name": "x.y.k", "locations": ["/things/4/x/y"]}]],
	]
}

test_a_position_in_a_list_is_in_the_location_only_when_the_list_has_it if {
	_located_rows({"c": "item 2 of x exists"}, {"things": [{"id": "t1", "x": ["p", "q"]}, {"id": "t2", "x": ["p"]}, {"id": "t3", "x": {"1": "q"}}, {"id": "t4", "x": "pq"}]}, {}) == [
		["t1", "c", [{"name": "item 2 of x", "locations": ["/things/0/x/1"]}]],
		["t2", "c", [{"name": "item 2 of x", "locations": ["/things/1/x"]}]],
		["t3", "c", [{"name": "item 2 of x", "locations": ["/things/2/x"]}]],
		["t4", "c", [{"name": "item 2 of x", "locations": ["/things/3/x"]}]],
	]
}

test_a_key_with_a_slash_or_a_tilde_is_escaped_in_its_location if {
	_located_rows({"c": `"a/b"."c~d"."~/" exists`}, {"things": [{"id": "t1", "a/b": {"c~d": {"~/": 1}}}]}, {}) == [["t1", "c", [{"name": `"a/b"."c~d"."~/"`, "locations": ["/things/0/a~1b/c~0d/~0~1"]}]]]
}

test_an_input_read_by_two_assertions_is_listed_once_with_its_location if {
	_located_rows({"c": {"assert": ["x exists", "x is 1", "y exists"]}}, {"things": [{"id": "t1", "x": 1, "y": 2}]}, {}) == [["t1", "c", [{"name": "x", "locations": ["/things/0/x"]}, {"name": "y", "locations": ["/things/0/y"]}]]]
}

test_a_number_worked_out_from_two_entries_lists_a_location_once_though_both_read_it if {
	elapsed := _elapsed_rows("days elapsed from t to t is 0", [{"id": 1, "t": 5}], {})
	elapsed[0][3][0].locations == ["/things/0/t"]
	counted := _tally_rows("count of xs plus count of xs is 4", [{"id": 1, "xs": [1, 2]}], {})
	counted[0][2][0].locations == ["/things/0/xs/0", "/things/0/xs/1"]
}

test_reads_with_the_same_name_and_value_merge_only_when_their_locations_match if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids", "identified_by": "id"}}, "requirements": {"s": {"subject": "kid", "checks": {"c": "b.x is 1 and .b.x is 1", "d": "b.x is 1 and b.x is 1"}}}}
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 1}}]}]}, policy, {})
	rows_for(rep, "s", "c")[0].inputs == [
		{"name": ".b.x", "value": 1, "locations": ["/bs/0/kids/0/b/x"]},
		{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]},
	]
	rows_for(rep, "s", "d")[0].inputs == [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}]
}

test_a_row_shows_an_input_once_when_the_check_reads_it_twice if {
	rep := ergo.report({"deployments": [{"id": "d1", "approvals": ["a", "b"]}]}, {"ergo_spec": ergo._spec, "subjects": {"deployment": {"from": "deployments", "identified_by": "id"}}, "requirements": {"r": {"subject": "deployment", "checks": {"c": "count of approvals plus count of approvals is 4"}}}}, {})
	[[[i.name, i.value, i.locations] | some i in r.inputs] | some r in rep.results; r.check == "c"] == [[
		["count of approvals plus count of approvals", 4, ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
		["count of approvals", 2, ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
		["approvals[]", ["a", "b"], ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
	]]
}

test_does_not_exist_fails_when_the_key_from_a_field_cant_be_read_whatever_the_path_before_it_holds if {
	every thing in [{}, {"zz": null}, {"zz": 3}, {"zz": ["k"]}, {"x": null}, {"x": null, "zz": 3}, {"x": 3, "zz": 3}, {"x": [[]], "zz": null}, {"x": {"k": 1}}] {
		every assertion in ["x named by zz does not exist", "x[0] named by zz does not exist", "x.a named by zz does not exist"] {
			row := _row_of(assertion, thing, {})
			row.passed == false
		}
	}
	every thing in [{}, {"zz": null}, {"zz": 3}, {"zz": ["k"]}] {
		every params in [{}, {"p": null}, {"p": [[]]}, {"p": 3}] {
			row := _row_of("$params.p named by zz does not exist", thing, params)
			row.passed == false
		}
	}
}

test_does_not_exist_with_a_key_from_a_field_that_can_be_read_passes_when_the_path_is_missing if {
	_row_of("x[0] named by zz does not exist", {"x": null, "zz": "k"}, {}).passed
	_row_of("x.a named by zz does not exist", {"x": {"k": 1}, "zz": "k"}, {}).passed
	_row_of("$params.p[0] named by zz does not exist", {"zz": "k"}, {"p": []}).passed
}

test_a_named_by_key_read_from_an_object_input_reads_one_key if {
	policy := _list_key_policy({"from": "every $input.things", "identified_by": "id"}, "m named by $input.k exists")
	rows := [[r.passed, r.cause] | some r in ergo.report({"k": "x", "things": [{"id": "a", "m": {"x": 1}}]}, policy, {}).results; r.check == "c"]
	rows == [[true, "satisfied"]]
}

test_contains_finds_a_list_its_right_side_ends_at_as_one_value if {
	doc := {"pair": ["c", "d"], "things": [{"id": "t1", "pairs": [["a", "b"], ["c", "d"]], "pair": ["a", "b"]}]}
	every check, want in {
		"pairs contains pair": [true, "satisfied", ""],
		"pairs contains $input.pair": [true, "satisfied", ""],
		"pairs contains $params.pair": [true, "satisfied", ""],
		"pairs does not contain pair": [false, "value", "pairs is [[\"a\", \"b\"], [\"c\", \"d\"]], and pair is [\"a\", \"b\"]"],
	} {
		_walk_right_rows(check, doc, {"pair": ["a", "b"]}) == [want]
	}
}

test_contains_with_a_ref_from_an_input_that_is_a_list_fails_as_not_an_object if {
	doc := [{"id": "a", "k": "x", "tags": ["x"]}]
	every check in ["tags contains $input.k", "tags does not contain $input.k"] {
		rows := [[r.passed, r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"]
		rows == [[false, "not_an_object", "$input is [{\"id\": \"a\", \"k\": \"x\", \"tags\": [\"x\"]}], which isn't an object"]]
	}
}

test_contains_reads_a_position_or_the_whole_input_of_an_input_that_is_a_list if {
	doc := [{"id": "t", "k": "z", "tags": ["a"]}]
	every check, want in {
		"tags contains $input[0].k": ["value", "tags is [\"a\"], and $input[0].k is \"z\""],
		"tags contains $input[0]": ["unusable", "tags is [\"a\"], which isn't a list of objects"],
		"tags contains $input": ["unusable", "tags is [\"a\"], which isn't a list of lists"],
	} {
		[[r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"] == [want]
	}
	[r.passed | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, "tags does not contain $input[0].k"), {}).results; r.check == "c"] == [true]
}

test_contains_with_a_named_by_path_from_an_input_that_is_a_list_names_the_input if {
	doc := [{"id": "t", "key": "x", "m": {"x": "a"}, "tags": ["a"]}]
	m := "$input is [{\"id\": \"t\", \"key\": \"x\", \"m\": {\"x\": \"a\"}, \"tags\": [\"a\"]}], which isn't an object"
	every check in ["tags contains $input.m named by key", "tags does not contain $input.m named by key"] {
		[[r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"] == [["not_an_object", m]]
	}
}

test_a_ref_that_reads_into_null_fails_as_null_and_names_the_null if {
	rows := _walk_right_rows("x is in $input.sbom.components.name", {"sbom": {"components": null}, "things": [{"id": "t1", "x": "a"}]}, {})
	rows == [[false, "null", "$input.sbom.components is null"]]
}

test_a_leading_dot_on_a_right_side_is_named_without_the_dot_when_nothing_has_its_name if {
	_dot_plain_rows("x is in .lock.pkgs.name", {"repos": [{"id": "r", "x": "a"}]}) == [{"cause": "absent", "message": "lock.pkgs.name is missing", "names": ["x", "lock.pkgs.name"]}]
	_dot_plain_rows("x is one of .tags", {"repos": [{"id": "r", "x": "z", "tags": ["a"]}]}) == [{"cause": "value", "message": "x is \"z\", and tags is [\"a\"]", "names": ["x", "tags"]}]
}

test_a_leading_dot_on_a_right_side_that_reads_the_left_field_lists_it_once if {
	_dot_plain_rows("x contains all of .x", {"repos": [{"id": "r", "x": "a.py"}]}) == [{"cause": "unusable", "message": "x is \"a.py\", which isn't a list", "names": ["x"]}]
}

test_an_object_with_values_of_different_kinds_on_the_right_fails_as_not_a_list_and_does_not_crash if {
	every c in ["x is in thing", "x is not in thing", "x is one of thing", "x is in $input.o"] {
		policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": c}}}}
		rep := ergo.report({"things": [{"x": 0, "thing": [0]}], "o": {"a": 0, "b": [0]}}, policy, {})
		[[r.passed, r.cause] | some r in rep.results; r.check == "c"] == [[false, "unusable"]]
	}
}

test_a_root_that_is_a_list_after_is_in_still_passes_on_an_empty_list if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "checks": {"c": "count of xs whose v is in pr.z is 0"}}}}
	rep := ergo.report({"prs": [{"id": "p", "z": [], "xs": []}]}, policy, {})
	some r in rep.results
	r.check == "c"
	r.cause == "satisfied"
}

test_two_roots_that_fail_in_one_relative_clause_are_both_named if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "checks": {"c": "count of xs whose aa equals $params.q and whose b equals pr.z is 1"}}}}
	rep := ergo.report({"prs": [{"id": "p", "xs": []}]}, policy, {})
	some r in rep.results
	r.check == "c"
	r.message == "$params.q is missing; pr.z is missing"
}

test_a_root_read_through_null_inside_a_relative_clause_names_the_null_step_once if {
	rows := _root_rows({"c": "count of xs whose v is in $params.c.z is 0"}, {"id": "p", "xs": []}, {"c": null})
	rows.c == ["null", "$params.c is null"]
}

test_both_sides_of_a_comparison_are_named_when_one_is_missing_and_the_other_null if {
	rows := _root_rows({"c": "c.z is d.z"}, {"id": "p", "c": {}, "d": null}, {})
	rows.c == ["absent", "c.z is missing, and d is null"]
}
