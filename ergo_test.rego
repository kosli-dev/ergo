package ergo_test

import data.ergo
import rego.v1

report(doc, reqs) := ergo.report(doc, lifted(reqs), given_params)

subject_fields := ["from", "identified_by", "applies_to"]

lifted(reqs) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {subject_name(reqs, name): subject_def(req) | some name, req in reqs; is_object(req)},
	"requirements": {name: lifted_req(reqs, name, req) | some name, req in reqs},
} if is_object(reqs)

lifted(reqs) := {"ergo_spec": "v0.3-dev", "requirements": reqs} if not is_object(reqs)

lifted_req(reqs, name, req) := object.union(object.remove(req, array.concat(subject_fields, ["subject_type"])), {"subject": subject_name(reqs, name)}) if is_object(req)

lifted_req(_, _, req) := req if not is_object(req)

subject_def(req) := object.union({"from": "$input"}, {f: req[f] | some f in subject_fields; f in object.keys(req)})

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
		"from": "items",
		"identified_by": "id",
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

stopped(rep) if [[r.check, r.passed, r.cause] | some r in rep.results] == [["$well_formed", false, "value"]]

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
	"identified_by": "id",
	"checks": {"c": "id exists"},
}}

subject_counts(doc, from) := report(doc, id_req(from)).requirements.s.subjects

test_array_from_yields_one_subject_per_element if {
	subject_counts({"items": [{"id": "a"}, {"id": "b"}]}, "items") == {"total": 2, "matching": 2}
}

test_single_object_from_is_wrapped_as_one_subject if {
	subject_counts({"item": {"id": "a"}}, ".item") == {"total": 1, "matching": 1}
}

test_missing_from_yields_no_subjects if {
	subject_counts({"other": [{"id": "a"}]}, "items") == {"total": 0, "matching": 0}
}

mixed_subjects := {"items": [{"id": "x", "n": "a"}, "b", null, 3]}

mixed_req := {"s": {"from": "items", "identified_by": "id", "checks": {"c": "n exists"}}}

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
		"from": "items whose kind is \"lib\"",
		"identified_by": "id",
		"checks": {"c": "n exists"},
	}}
	rep := report({"items": ["b"]}, req)
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [["b", false, "not_an_object"]]
	{v.check | some v in ergo.violations(rep)} == {"$applies", "$min_subjects"}
}

test_a_subject_that_is_not_an_object_is_not_mistaken_for_one_missing_its_fields if {
	causes := {r.subject.id: r.cause | some r in rows_for(report({"items": [{"id": "x"}, "b"]}, mixed_req), "s", "c")}
	causes == {"x": "value", "b": "not_an_object"}
}

test_scalar_from_yields_no_subjects if {
	subject_counts({"items": "not-a-collection"}, "items") == {"total": 0, "matching": 0}
}

test_empty_from_treats_the_whole_document_as_one_subject if {
	subject_counts({"id": "root"}, "$input") == {"total": 1, "matching": 1}
}

test_nested_from_resolves_through_objects if {
	subject_counts({"a": {"b": {"items": [{"id": "x"}]}}}, ".a.b.items") == {"total": 1, "matching": 1}
}

test_missing_id_path_yields_a_null_subject_id if {
	rep := report({"items": [{"no_id_here": 1}]}, id_req("items"))
	some row in rep.results
	row.subject == {"type": "thing", "id": null}
}

test_subject_id_is_read_from_the_declared_path if {
	rep := report({"items": [{"id": "abc"}]}, id_req("items"))
	some row in rep.results
	row.subject == {"type": "thing", "id": "abc"}
}

scoped_req(conditions) := {"s": {
	"subject_type": "thing",
	"from": whose_line("items", conditions),
	"identified_by": "id",
	"checks": {"c": "id exists"},
}}

whose_line(path, "") := path

whose_line(path, conditions) := concat(" whose ", [path, conditions]) if conditions != ""

merged_only := "state is \"MERGED\""

two_states := {"items": [
	{"id": "a", "state": "MERGED"},
	{"id": "b", "state": "CLOSED"},
]}

test_applies_to_narrows_matching_but_leaves_total_intact if {
	rep := report(two_states, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_checks_are_conjunctive if {
	both := concat(" and ", [merged_only, "base_ref is \"main\""])
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
	rep := report(two_states, scoped_req(""))
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
	r.inputs == [{"name": "state", "value": "CLOSED", "locations": ["/items/1/state"]}]
}

test_applies_definition_renders_the_filter_expression if {
	rep := report(two_states, scoped_req(merged_only))
	rep.requirements.s.checks["$applies"].expression == `state is "MERGED"`
}

test_applies_definition_conjoins_multiple_filter_checks if {
	both := concat(" and ", [merged_only, "base_ref is \"main\""])
	rep := report(two_states, scoped_req(both))

	rep.requirements.s.checks["$applies"].expression == `state is "MERGED" and base_ref is "main"`
}

test_no_applies_to_means_no_applies_rows_or_definition if {
	rep := report(two_states, id_req("items"))
	count([r | some r in rep.results; r.check == "$applies"]) == 0
	not "$applies" in object.keys(rep.requirements.s.checks)
}

test_out_of_scope_subject_gets_no_check_rows if {
	rep := report(two_states, scoped_req(merged_only))
	ids := {r.subject.id | some r in rep.results; r.check == "c"}
	ids == {"a"}
}

in_range := "temp_c is between 0 and 10"

test_range_inside if verdict({"temp_c": 5}, in_range) == true

test_range_at_lower_bound if verdict({"temp_c": 0}, in_range) == true

test_range_at_upper_bound if verdict({"temp_c": 10}, in_range) == true

test_range_below_bound if verdict({"temp_c": -1}, in_range) == false

test_range_above_bound if verdict({"temp_c": 11}, in_range) == false

test_range_rejects_numeric_string if verdict({"temp_c": "5"}, in_range) == false

test_range_rejects_missing_field if verdict({"other": 5}, in_range) == false

test_range_rejects_null if verdict({"temp_c": null}, in_range) == false

no_wip := "labels does not contain \"wip\""

test_excludes_when_value_absent if verdict({"labels": ["ready"]}, no_wip) == true

test_excludes_over_empty_array if verdict({"labels": []}, no_wip) == true

test_excludes_when_value_present if verdict({"labels": ["ready", "wip"]}, no_wip) == false

test_excludes_rejects_non_array if verdict({"labels": "wip"}, no_wip) == false

test_excludes_rejects_missing_field if verdict({}, no_wip) == false

has_approved := "labels contains \"approved\""

test_includes_when_value_present if verdict({"labels": ["approved"]}, has_approved) == true

test_includes_when_value_absent if verdict({"labels": ["ready"]}, has_approved) == false

test_includes_over_empty_array if verdict({"labels": []}, has_approved) == false

test_includes_rejects_non_array if verdict({"labels": "approved"}, has_approved) == false

test_includes_rejects_missing_field if verdict({}, has_approved) == false

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

is_merged := "state is \"MERGED\""

test_equals_on_match if verdict({"state": "MERGED"}, is_merged) == true

test_equals_on_mismatch if verdict({"state": "CLOSED"}, is_merged) == false

test_equals_rejects_missing_field if verdict({}, is_merged) == false

test_equals_is_type_sensitive if verdict({"n": "1"}, "n is 1") == false

test_equals_compares_booleans if verdict({"verified": true}, "verified is true") == true

test_equals_null_matches_an_explicit_null if {
	verdict({"x": null}, "x is null") == true
}

has_fingerprint := "fingerprint exists"

test_present_when_set if verdict({"fingerprint": "abc"}, has_fingerprint) == true

test_present_rejects_missing_field if verdict({}, has_fingerprint) == false

test_present_rejects_explicit_null if verdict({"fingerprint": null}, has_fingerprint) == false

test_present_accepts_empty_string if verdict({"fingerprint": ""}, has_fingerprint) == true

test_present_accepts_false if verdict({"fingerprint": false}, has_fingerprint) == true

filled := "fingerprint is a non-empty string"

test_non_empty_string_when_filled if verdict({"fingerprint": "abc"}, filled) == true

test_non_empty_string_rejects_empty_string if verdict({"fingerprint": ""}, filled) == false

test_non_empty_string_rejects_number if verdict({"fingerprint": 42}, filled) == false

test_non_empty_string_rejects_null if verdict({"fingerprint": null}, filled) == false

test_non_empty_string_rejects_missing_field if verdict({}, filled) == false

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

test_present_and_missing_fail_as_unusable_when_the_subject_cannot_hold_a_one_step_path if {
	cause_of({"a": 1}, "b exists") == "value"
	verdict({"a": 1}, "b does not exist") == true
}

test_a_present_filter_cannot_rule_a_subject_out_when_a_step_before_the_field_cannot_hold_it if {
	rep := report({"items": [{"id": "a", "build": "abc"}]}, scoped_req("build.fingerprint exists"))
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "unusable"]]
	rep.compliant == false
}

test_missing_fails_on_a_subject_that_is_not_an_object if {
	rep := report({"items": ["abc"]}, {"s": {"from": "items", "checks": {"c": "v does not exist"}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "not_an_object"]]
}

clean_labels := {"any_of": {"no_labels": "labels does not exist", "clean": "labels does not contain \"do-not-merge\""}}

test_missing_in_any_of_lets_a_missing_field_pass_a_check if {
	[verdict({}, clean_labels), verdict({"labels": ["ok"]}, clean_labels)] == [true, true]
	[verdict({"labels": ["do-not-merge"]}, clean_labels), cause_of({"labels": ["do-not-merge"]}, clean_labels)] == [false, "value"]
	[verdict({"labels": "do-not-merge"}, clean_labels), cause_of({"labels": "do-not-merge"}, clean_labels)] == [false, "unusable"]
}

test_a_missing_filter_rules_a_subject_with_the_field_out if {
	rep := report({"items": [{"id": "a", "draft": true}, {"id": "b"}]}, scoped_req("draft does not exist"))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	rep.compliant == true
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

service_accounts := ["svc_.*", `.*\[bot\]`, `noreply@github\.com`]

matches(op) := concat(" ", ["author", {"matches_any": "matches", "not_matches_any": "does not match"}[op], concat(", ", [json.marshal(p) | some p in service_accounts])])

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

compare_time_span(op) := concat(" ", ["start", {"gt": "is after", "gte": "is on or after", "lt": "is before", "lte": "is on or before"}[op], "end"])

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

test_compare_time_orders_two_dates_without_a_time if {
	verdict({"start": "2024-01-01", "end": "2024-06-01"}, compare_time_span("lt")) == true
}

test_compare_time_rejects_a_date_against_a_time_even_at_midnight if {
	verdict({"start": "2024-01-01", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_date_that_doesnt_exist if {
	verdict({"start": "2023-02-29", "end": "2024-06-01"}, compare_time_span("lt")) == false
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
	verdict({"start": 1753600000, "end": 1753600000}, compare_time_span("gte")) == true
	verdict({"start": 1753600000, "end": 1753600000}, compare_time_span("lte")) == true
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

all_verified := "every commits.verified is true"

any_approved := `some approvers.state is "APPROVED"`

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

test_any_when_no_element_passes if {
	verdict({"approvers": [{"state": "COMMENTED"}]}, any_approved) == false
}

test_any_over_empty_collection if verdict({"approvers": []}, any_approved) == false

test_any_rejects_missing_path if verdict({}, any_approved) == false

every_commit_signed := "every prs.commits.signed is true"

any_commit_signed := "some prs.commits.signed is true"

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

test_each_under_any_fails_when_no_element_passes if {
	verdict({"prs": [{"commits": [{"signed": false}]}]}, any_commit_signed) == false
}

branch_req(check) := {"s": {"from": "branches", "checks": {"c": check}}}

branch_rows(check) := [[r.subject.id, r.passed, r.cause] |
	some r in rows_for(report({"branches": ["main", "feature", null]}, branch_req(check)), "s", "c")
]

test_a_field_path_on_a_subject_that_is_not_an_object_is_still_not_an_object if {
	branch_rows("name exists") == [
		["main", false, "not_an_object"],
		["feature", false, "not_an_object"],
		[null, false, "not_an_object"],
	]
}

flavoured := {"any_of": {"standard": ["type matches \"^Story$\"", "state matches \"^CLOSED$\""], "safe": ["type matches \"^SAFe Story$\"", "state matches \"^DONE$\""]}}

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

test_any_of_echoes_every_field_it_read_once_each if {
	inputs_of({"type": "Story", "state": "DONE"}, flavoured) == [
		{"name": "state", "value": "DONE", "locations": ["/items/0/state"]},
		{"name": "type", "value": "Story", "locations": ["/items/0/type"]},
	]
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

test_a_byte_order_mark_in_a_subject_name_and_from_is_written_as_is if {
	min_subjects := report({"i\ufeff": [{"id": 1}]}, {"s": {
		"subject_type": "t\ufeff",
		"from": "\"i\ufeff\"",
		"identified_by": "id",
		"checks": {"c": "id exists"},
	}}).requirements.s.checks["$min_subjects"]
	min_subjects.description == "The in-scope t\ufeff count is at least 1"
	min_subjects.expression == "count(matching(\"i\ufeff\")) >= 1"
}

test_min_subjects_is_written_like_any_number if {
	rep := report({"xs": []}, {"s": {"from": "xs", "min_subjects": 2.0, "checks": {"c": "x exists"}}})
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(xs)) >= 2"
}

test_a_string_never_picks_a_list_item_and_a_number_never_picks_an_object_key if {
	[cause_of({"id": 1, "a": [10, 20]}, ".a.\"0\" exists"), cause_of({"id": 1, "o": {"0": "zero"}}, "item 1 of o exists")] == ["unusable", "unusable"]
}

test_a_list_index_written_as_a_whole_number_reads_the_item if {
	verdict({"id": 1, "a": [1, 2]}, "item 2 of .a is 2") == true
	verdict({"id": 1, "a": [1, 2]}, "item 1 of .a is 1") == true
}

test_a_ref_step_that_reads_a_list_index_written_with_an_exponent_reads_the_item if {
	check := ".a named by $params.i exists"
	params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check) == [[true, "satisfied", [{"name": ".a named by $params.i", "value": 2, "locations": ["/items/0/a/1"]}]]] with data.params as {"i": 1e0}
}

test_a_list_index_reads_the_same_item_however_other_checks_write_it if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"item": {"from": "items", "identified_by": "id"}},
		"requirements": {"r": {"subject": "item", "checks": {
			"c1": "item 2 of .a exists",
			"c2": "item 2 of .a exists",
		}}},
	}
	rep := ergo.report({"items": [{"id": 1, "a": [1, 2]}]}, policy, {})
	[[r.check, r.passed, r.cause] | some r in rep.results] == [[c, true, "satisfied"] | some c in ["$well_formed", "$min_subjects", "$unique_ids", "c1", "c2"]]
}

test_a_ref_step_that_reads_something_that_cannot_be_a_key_fails_as_unusable if {
	check := ".a named by $params.i exists"
	params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check) == [[true, "satisfied", [{"name": ".a named by $params.i", "value": 2, "locations": ["/items/0/a/1"]}]]] with data.params as {"i": 1}
	r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": -1}
	[r[0], r[1]] == [false, "unusable"]
	s := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 1.5}
	[s[0], s[1]] == [false, "unusable"]
}

test_a_ref_step_that_reads_a_number_too_big_to_be_a_list_position_fails_as_unusable_so_does_not_exist_cannot_pass if {
	check := ".a named by $params.i does not exist"
	params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check) == [[true, "satisfied", [{"name": ".a named by $params.i", "value": null, "locations": ["/items/0/a"]}]]] with data.params as {"i": 9007199254740991}
	r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 9007199254740992}
	[r[0], r[1]] == [false, "unusable"]
	s := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 1e20}
	[s[0], s[1]] == [false, "unusable"]
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

test_a_number_a_float_cannot_hold_read_from_the_params_is_compared_exactly if {
	check := "n is $params.n"
	big := row_in({}, {"id": 1, "n": 1e400}, check) with data.params as {"n": 1e400}
	small := row_in({}, {"id": 1, "n": 0}, check) with data.params as {"n": 1e-400}
	[[big.passed, big.cause], [small.passed, small.cause]] == [[true, "satisfied"], [false, "value"]]
	json.marshal(big.inputs) == `[{"locations":["/items/0/n"],"name":"n","value":1e400},{"locations":["$params:/n"],"name":"$params.n","value":1e400}]`
}

test_a_number_at_the_edge_of_a_float_still_works if {
	verdict({"id": 1, "n": 1.7976931348623157e308}, "n is 1.7976931348623157e308") == true
	verdict({"id": 1, "n": 2.2250738585072014e-308}, "n is 2.2250738585072014e-308") == true
	verdict({"id": 1, "n": 0}, "n is 0") == true
	stopped(solo({"id": 1, "n": 2.2250738585072e-308}, "n is 2.2250738585072e-308"))
}

test_a_requirement_with_a_number_out_of_range_is_not_well_formed if {
	rows := [[r.check, r.passed] |
		some m in [{"min_subjects": 1e-400}, {"from": "xs.\"a\".1e400"}]
		rep := report({"xs": [{"id": 1}]}, {"s": object.union({"from": "xs", "checks": {"c": "id exists"}}, m)})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [["$well_formed", false], ["$well_formed", false]]
}

test_min_subjects_is_described_like_any_number if {
	rep := report({"xs": []}, {"s": {"from": "xs", "min_subjects": 2.0, "checks": {"c": "x exists"}}})
	rep.requirements.s.checks["$min_subjects"].description == "The in-scope subject count is at least 2"
}

test_expression_for_non_empty_string if rendered({}, filled) == "fingerprint is a non-empty string"

two_check_req := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"checks": {
		"a": "id exists",
		"b": "state is \"MERGED\"",
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

test_rows_from_different_requirements_are_labelled_separately if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "id exists"}},
	}
	rep := report(doc, policy)
	count(rows_for(rep, "first", "c")) == 1
	count(rows_for(rep, "second", "c")) == 1
}

test_requirement_name_is_the_policy_key if {
	rep := report({"items": [{"id": "a"}]}, id_req("items"))
	object.keys(rep.requirements) == {"s"}
	{r.requirement | some r in rep.results} == {"s"}
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

test_cause_unusable_when_the_path_walks_through_a_scalar if {
	cause_of({"pr": "none"}, "pr.state is \"MERGED\"") == "unusable"
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

test_an_applies_row_carries_the_state_of_the_filter_paths if {
	rep := report({"items": [{"id": "a", "env": "prod"}, {"id": "b"}]}, {"s": {
		"subject_type": "thing",
		"from": "items whose env is \"prod\"",
		"identified_by": "id",
		"checks": {"c": "x exists"},
	}})
	applies := rows_for(rep, "s", "$applies")
	[r.cause | some r in applies] == ["satisfied", "absent"]
}

test_violations_carry_the_cause if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
		"checks": {"c": "state is \"MERGED\""},
	}})
	[v.cause | some v in ergo.violations(rep)] == ["absent"]
}

min_subjects_req(n) := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"min_subjects": n,
	"checks": {"c": "id exists"},
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
	rep := report({"items": [{"id": "a"}]}, id_req("items"))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_min_subjects_zero_permits_an_empty_collection if {
	rep := report({"items": []}, min_subjects_req(0))
	rows_for(rep, "s", "$min_subjects")[0].passed == true
	rep.requirements.s.status == "not_applicable"
}

test_min_subjects_counts_subjects_after_the_applies_to_filter if {
	both := {"s": object.union(min_subjects_req(2).s, {"from": whose_line("items", merged_only)})}
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
	req := {"s": object.union(min_subjects_req(0).s, {"from": "build.items"})}
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
	req := {"s": object.union(min_subjects_req(0).s, {"from": "builds[1].items"})}
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
	req := {"s": object.union(min_subjects_req(0).s, {"from": "$input"})}
	every doc, cause in {"null": "null", `"x"`: "unusable", "3": "unusable", "true": "unusable"} {
		rep := report(json.unmarshal(doc), req)
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
}

test_from_input_on_a_list_makes_each_item_a_subject_and_an_empty_list_fails_as_value if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input"})}
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([{"id": "a"}, 1], req), "s", "$min_subjects")] == [[true, "satisfied", 2, ["/0", "/1"]]]
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "value", 0, []]]
}

test_from_every_input_on_a_list_makes_each_item_a_subject_and_prints_every if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input"})}
	rep := report([{"id": "a"}, 1], req)
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations, r.failed_items] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied", 2, ["/0", "/1"], []]]
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(every $input)) >= 1"
	[[r.passed, r.cause, r.inputs[0].value, r.failed_items] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "value", 0, []]]
}

test_from_every_input_on_an_input_that_is_not_a_list_fails_and_names_the_input_from_input if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input"})}
	every doc, cause in {"null": "null", `"x"`: "unusable", "3": "unusable", "true": "unusable"} {
		[[r.passed, r.cause, r.failed_items] | some r in rows_for(report(json.unmarshal(doc), req), "s", "$min_subjects")] == [[false, cause, [{"path": "$input", "item": "$input", "cause": cause, "value": json.unmarshal(doc), "locations": [""]}]]]
	}
	[[r.passed, r.cause, r.failed_items[0].path, r.failed_items[0].item] | some r in rows_for(report({"id": "a"}, req), "s", "$min_subjects")] == [[false, "unusable", "$input", "$input"]]
}

test_every_walks_that_start_at_a_list_input_read_the_lists_inside_its_items if {
	doc := [{"commits": [{"id": "a"}]}, {"commits": []}]
	every from in ["every $input.commits", "every commits"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report(doc, req), "s", "$min_subjects")] == [[true, "satisfied", 1, ["/0/commits/0"]]]
	}
}

test_every_walk_that_starts_at_a_list_input_fails_an_item_that_is_not_an_object_or_has_no_list if {
	every doc, cause in {`[1]`: "unusable", `[{}]`: "absent", `[{"commits": null}]`: "null", `[{"commits": 1}]`: "unusable"} {
		req := {"s": object.union(min_subjects_req(1).s, {"from": "every commits"})}
		[[r.passed, r.cause] | some r in rows_for(report(json.unmarshal(doc), req), "s", "$min_subjects")] == [[false, cause]]
	}
}

test_every_walk_that_starts_at_a_list_input_names_where_it_broke_from_input if {
	every from in ["every $input.commits", "every commits"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[f.path, f.item, f.locations] | some r in rows_for(report([{"commits": [{"id": "a"}]}, {"commits": 5}, 7], req), "s", "$min_subjects"); some f in r.failed_items] == [["$input[1].commits", "$input[1].commits", ["/1/commits"]], ["$input[2].commits", "$input[2].commits", ["/2"]]]
	}
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input[1].commits"})}
	[[f.path, f.item] | some r in rows_for(report([{"commits": []}, 5], req), "s", "$min_subjects"); some f in r.failed_items] == [["item 2 of $input", "item 2 of $input"]]
}

test_a_from_line_with_a_position_on_a_list_input_names_it_from_input_in_expressions if {
	every from, want in {
		"every $input[1].commits": ["count(matching(every $input[1].commits)) >= 1", "count(repeated(ids(every $input[1].commits))) == 0"],
		"$input[1]": ["count(matching(item 2 of $input)) >= 1", "count(repeated(ids(item 2 of $input))) == 0"],
		"first of $input": ["count(matching(item 1 of $input)) >= 1", "count(repeated(ids(item 1 of $input))) == 0"],
		"every $input.commits": ["count(matching(every commits)) >= 1", "count(repeated(ids(every commits))) == 0"],
	} {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		rep := report([{"commits": [{"id": "a"}]}, {"commits": [{"id": "b"}]}], req)
		[rep.requirements.s.checks[c].expression | some c in ["$min_subjects", "$unique_ids"]] == want
	}
}

test_a_child_subject_reads_the_items_of_a_list_input_as_its_parents if {
	reqs := {"s": {"subject_type": "kid", "from": "parent.kids", "checks": {"c": "id exists"}}, "p": {"subject_type": "parent", "from": "$input", "checks": {"c": "kids exists"}}}
	rep := report([{"kids": [{"id": "a"}]}, {"kids": []}], reqs)
	[[r.passed, r.cause, r.inputs[0].locations] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied", ["/0/kids/0"]], [false, "value", []]]
}

test_a_position_on_a_list_input_reads_the_item_and_ends_absent_past_the_end if {
	every from in ["$input[0]", "first of $input"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([{"id": "a"}, 1], req), "s", "$min_subjects")] == [[true, "satisfied", 1, ["/0"]]]
		[[r.passed, r.cause, r.inputs[0].value] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "absent", 0]]
	}
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input[5]"})}
	[[r.passed, r.cause] | some r in rows_for(report([{"id": "a"}], req), "s", "$min_subjects")] == [[false, "absent"]]
}

test_a_position_on_a_list_input_that_leads_to_a_list_reads_its_items if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input[0].commits"})}
	[[r.passed, r.cause, r.inputs[0].locations] | some r in rows_for(report([{"commits": [{"id": "a"}]}], req), "s", "$min_subjects")] == [[true, "satisfied", ["/0/commits/0"]]]
}

test_a_field_on_a_list_input_is_unusable if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input.commits"})}
	every doc in [[{"commits": [{"id": "a"}]}], []] {
		[[r.passed, r.cause] | some r in rows_for(report(doc, req), "s", "$min_subjects")] == [[false, "unusable"]]
	}
}

test_min_subjects_fails_when_from_has_steps_and_the_document_is_not_an_object if {
	every doc, cause in {"null": "absent", `"x"`: "unusable", `[{"items": []}]`: "unusable"} {
		rep := report(json.unmarshal(doc), min_subjects_req(0))
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
}

test_min_subjects_at_zero_says_it_only_checks_that_from_can_be_read if {
	def := report({"items": []}, min_subjects_req(0)).requirements.s.checks["$min_subjects"]
	def.description == "The thing list can be read"
	def.expression == "items can be read"
}

test_min_subjects_at_zero_names_the_input_when_there_is_no_from if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": "$input"})}
	report({}, req).requirements.s.checks["$min_subjects"].expression == "$input can be read"
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

test_a_from_written_wrong_stops_at_well_formed_even_with_min_subjects_zero if {
	every f in [5, ["items"], "items whose"] {
		every n in [0, 1] {
			req := {"s": object.union(min_subjects_req(n).s, {"from": f})}
			stopped(report({"items": [{"id": "a"}]}, req))
		}
	}
}

test_a_from_that_reads_nothing_lists_its_min_subjects_row_as_a_violation if {
	rep := report({}, min_subjects_req(0))
	[[v.check, v.cause] | some v in ergo.violations(rep)] == [["$min_subjects", "absent"]]
}

owner_req := {"s": {
	"subject_type": "repo",
	"from": "repos",
	"identified_by": "name",
	"checks": {"owned": "owner is a non-empty string"},
}}

unique_ids_row(doc, policy) := [r.inputs, r.passed, r.cause] if {
	some r in rows_for(report(doc, policy), "s", "$unique_ids")
}

test_unique_ids_passes_when_every_subject_has_its_own_id if {
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "b", "owner": "carol"}]}, owner_req)
	[[r.inputs, r.passed, r.cause] | some r in rows_for(rep, "s", "$unique_ids")] == [[[{"name": "repeated repo ids", "value": [], "locations": []}], true, "satisfied"]]
	rep.requirements.s.status == "met"
}

test_unique_ids_fails_the_requirement_when_two_subjects_share_an_id if {
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "a", "owner": "carol"}]}, owner_req)
	[[r.subject, r.inputs, r.passed, r.cause] | some r in rows_for(rep, "s", "$unique_ids")] == [[
		{"type": "repo", "id": null},
		[{"name": "repeated repo ids", "value": ["a"], "locations": ["/repos/0/name", "/repos/1/name"]}],
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
	unique_ids_row({"repos": [{"name": "a", "owner": ""}, {"name": "a", "owner": ""}]}, owner_req) == [[{"name": "repeated repo ids", "value": ["a"], "locations": ["/repos/0/name", "/repos/1/name"]}], false, "value"]
}

test_unique_ids_counts_two_subjects_without_an_id_as_sharing_the_id_null if {
	unique_ids_row({"repos": [{"owner": "bob"}, {"owner": "carol"}]}, owner_req) == [[{"name": "repeated repo ids", "value": [null], "locations": ["/repos/0", "/repos/1"]}], false, "value"]
}

test_unique_ids_reads_a_subject_that_is_not_an_object_as_its_own_id if {
	unique_ids_row({"repos": ["api", "api", "web"]}, owner_req) == [[{"name": "repeated repo ids", "value": ["api"], "locations": ["/repos/0", "/repos/1"]}], false, "value"]
}

test_unique_ids_counts_two_identical_subjects_as_a_clash_without_an_id_path if {
	policy := {"s": object.remove(owner_req.s, ["identified_by"])}
	unique_ids_row({"repos": [{"owner": "bob"}, {"owner": "bob"}, {"owner": "carol"}]}, policy) == [[{"name": "repeated repo ids", "value": [{"owner": "bob"}], "locations": ["/repos/0", "/repos/1"]}], false, "value"]
}

test_unique_ids_counts_subjects_that_are_out_of_scope if {
	policy := {"s": object.union(owner_req.s, {"from": "repos whose live is true"})}
	doc := {"repos": [{"name": "a", "owner": "bob", "live": true}, {"name": "a", "owner": "bob", "live": false}]}
	rep := report(doc, policy)
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	[[r.inputs, r.passed] | some r in rows_for(rep, "s", "$unique_ids")] == [[[{"name": "repeated repo ids", "value": ["a"], "locations": ["/repos/0/name", "/repos/1/name"]}], false]]
	rep.requirements.s.status == "not_met"
}

test_unique_ids_lists_each_repeated_id_once_in_the_order_it_is_written_whatever_the_input_order if {
	rows := {row |
		some ids in [[3, "b", 10, "a", 3, "b", 10, 10], [10, 10, "b", 3, "a", 10, "b", 3]]
		full := unique_ids_row({"repos": [{"name": n} | some n in ids]}, owner_req)
		row := [[{"name": i.name, "value": i.value} | some i in full[0]], full[1], full[2]]
	}
	rows == {[[{"name": "repeated repo ids", "value": ["b", 10, 3]}], false, "value"]}
}

test_unique_ids_lists_the_locations_of_the_repeated_ids_in_the_order_the_ids_are_listed_then_the_subjects if {
	first := unique_ids_row({"repos": [{"name": n} | some n in [3, "b", 10, "a", 3, "b", 10, 10]]}, owner_req)
	first[0][0].locations == ["/repos/1/name", "/repos/5/name", "/repos/2/name", "/repos/6/name", "/repos/7/name", "/repos/0/name", "/repos/4/name"]
	second := unique_ids_row({"repos": [{"name": n} | some n in [10, 10, "b", 3, "a", 10, "b", 3]]}, owner_req)
	second[0][0].locations == ["/repos/2/name", "/repos/6/name", "/repos/0/name", "/repos/1/name", "/repos/5/name", "/repos/3/name", "/repos/7/name"]
}

test_unique_ids_passes_with_no_subjects_because_min_subjects_already_fails_the_requirement if {
	rep := report({}, owner_req)
	[[r.check, r.passed] | some r in rep.results; r.check in {"$min_subjects", "$unique_ids"}] == [["$min_subjects", false], ["$unique_ids", true]]
	rep.requirements.s.status == "not_met"
}

test_unique_ids_definition_is_in_the_check_table if {
	rows := [[d.description, d.expression] |
		some from in ["repos", "$input", 5]
		d := report({}, {"s": object.union(owner_req.s, {"from": from})}).requirements.s.checks["$unique_ids"]
	]
	rows == [
		["Every repo id is unique", "count(repeated(ids(repos))) == 0"],
		["Every repo id is unique", "count(repeated(ids($input))) == 0"],
		["Every repo id is unique", "count(repeated(ids(<invalid from>))) == 0"],
	]
}

test_well_formed_passes_for_an_ordinary_requirement if {
	rep := report({"items": [{"id": "a"}]}, id_req("items"))
	rows_for(rep, "s", "$well_formed")[0].passed == true
}

test_well_formed_fails_when_no_checks_are_declared if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
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
	rep := report({"items": [{"id": "a"}, {"id": "b"}]}, id_req("items"))
	count(rows_for(rep, "s", "$well_formed")) == 1
	rows_for(rep, "s", "$well_formed")[0].subject == {"type": "thing", "id": null}
}

test_well_formed_does_not_depend_on_the_input if {
	with_items := report({"items": [{"id": "a"}]}, id_req("items"))
	without := report({}, id_req("items"))
	rows_for(with_items, "s", "$well_formed")[0] == rows_for(without, "s", "$well_formed")[0]
}

test_well_formed_echoes_a_valid_require_and_says_what_is_wrong_with_any_other if {
	rows_for(report(both_ok, require_req("some")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2, "locations": []},
		{"name": "require", "value": "some", "locations": []},
	]
	rows_for(report(both_ok, require_req("most")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2, "locations": []},
		{"name": "require", "value": ["neither every nor some"], "locations": []},
	]
}

test_a_requirement_that_is_not_an_object_stays_in_the_report_and_is_not_well_formed if {
	rows := [[name in object.keys(rep.requirements), rep.requirements[name].status, r.passed, r.inputs[2]] |
		some [name, req] in [["a", 5], ["b", null], ["c", [1]], ["d", "x"]]
		rep := report({"items": [{"id": 1}]}, {name: req})
		some r in rows_for(rep, name, "$well_formed")
	]
	rows == [
		[true, "not_met", false, {"name": "requirement", "value": 5, "locations": []}],
		[true, "not_met", false, {"name": "requirement", "value": null, "locations": []}],
		[true, "not_met", false, {"name": "requirement", "value": [1], "locations": []}],
		[true, "not_met", false, {"name": "requirement", "value": "x", "locations": []}],
	]
}

test_a_requirement_field_ergo_does_not_know_fails_well_formed if {
	rep := report({"releases": [{"id": "r-1", "signed": false}]}, {"s": {
		"from": "releases",
		"identified_by": "id",
		"subjects": "release",
		"checks": {"signed": "signed is true"},
	}})
	rep.requirements.s.status == "not_met"
	row := rows_for(rep, "s", "$well_formed")[0]
	row.passed == false
	row.inputs[2] == {"name": "subjects", "value": ["unknown field"], "locations": []}
}

test_from_id_applies_to_and_subject_type_belong_to_the_subject_not_the_requirement if {
	rep := ergo.report(
		{"releases": [{"id": "r-1", "signed": true}]}, {
			"ergo_spec": "v0.3-dev",
			"subjects": {"release": {"from": "releases", "identified_by": "id"}},
			"requirements": {"s": {
				"subject": "release",
				"subject_type": "release",
				"from": "releases",
				"identified_by": "id",
				"checks": {"signed": "signed is true"},
			}},
		},
		{},
	)
	rep.requirements.s.status == "not_met"
	[r.inputs | some r in rows_for(rep, "s", "$well_formed")] == [[
		{"name": "count(checks)", "value": 1, "locations": []},
		{"name": "require", "value": "every", "locations": []},
		{"name": "from", "value": ["unknown field"], "locations": []},
		{"name": "identified_by", "value": ["unknown field"], "locations": []},
		{"name": "subject_type", "value": ["unknown field"], "locations": []},
	]]
}

test_a_subject_with_id_instead_of_identified_by_is_written_wrong if {
	rep := ergo.report(
		{"releases": [{"id": "r-1", "signed": true}]},
		{
			"ergo_spec": "v0.3-dev",
			"subjects": {"release": {"from": "releases", "id": ["id"]}},
			"requirements": {"s": {"subject": "release", "checks": {"signed": "signed is true"}}},
		},
		{},
	)
	rep.requirements.s.status == "not_met"
	[[r.passed, r.inputs] | some r in rows_for(rep, "s", "$well_formed")] == [[false, [
		{"name": "count(checks)", "value": 1, "locations": []},
		{"name": "require", "value": "every", "locations": []},
		{"name": "subjects.release.id", "value": ["unknown field"], "locations": []},
	]]]
}

test_a_requirement_with_an_unknown_field_still_has_its_subject_rows if {
	rep := report({"items": [{"id": 1}, {"id": 2}]}, {"s": object.union(typed_req, {"subject": "item"})})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [[1, true], [2, true]]
}

test_unknown_requirement_fields_are_listed_in_order_and_say_what_is_wrong if {
	req := object.union(typed_req, {"requires": "some", "notes": "x", "title": "t"})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [
		{"name": "notes", "value": ["unknown field"], "locations": []},
		{"name": "requires", "value": ["unknown field"], "locations": []},
		{"name": "title", "value": ["unknown field"], "locations": []},
	]
}

test_an_unknown_requirement_field_is_named_as_a_path if {
	req := object.union(typed_req, {"a b": 1})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [{"name": `"a b"`, "value": ["unknown field"], "locations": []}]
}

test_unknown_requirement_keys_that_are_not_strings_are_listed_in_the_same_order_everywhere if {
	req := object.union(typed_req, {"zz": 2, 1: "x", true: 3})
	problem_inputs(report({"items": [{"id": 1}]}, {"s": req})) == [
		{"name": "<invalid key true>", "value": ["unknown field"], "locations": []},
		{"name": "<invalid key 1>", "value": ["unknown field"], "locations": []},
		{"name": "zz", "value": ["unknown field"], "locations": []},
	]
}

test_every_requirement_field_ergo_knows_is_well_formed if {
	req := object.union(typed_req, {"subject_type": "item", "require": "some", "from": "items whose id exists", "description": "d", "meta": {"m": "x"}})
	rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0].passed == true
}

_engine_policy := {"ergo_spec": "v0.3-dev", "subjects": {"x": {"from": "xs", "identified_by": "id"}}, "requirements": {"r": {"subject": "x", "checks": {"c": "id is 1"}}}}

_engine_doc := {"xs": [{"id": 1}, {"id": 2}]}

test_the_report_says_which_version_of_the_spec_it_follows if {
	ergo.report(_engine_doc, _engine_policy, {}).ergo == "v0.3-dev"
}

test_the_report_says_which_version_of_the_spec_it_follows_whatever_version_the_policy_names if {
	every v in ["v9.9", 0.1, null] {
		rep := ergo.report(_engine_doc, object.union(_engine_policy, {"ergo_spec": v}), {})
		[rep.ergo, rep.compliant] == ["v0.3-dev", false]
	}
}

test_the_engine_gives_only_its_name_and_version_because_anything_about_the_machine_would_make_the_report_depend_on_more_than_the_policy_and_input if {
	ergo.report(_engine_doc, _engine_policy, {}).engine == {"name": "ergo.rego", "version": ergo.version}
}

test_a_compiled_policy_gives_the_same_ergo_and_engine if {
	rep := ergo.report(_engine_doc, ergo.compile(_engine_policy), {})
	rep.ergo == "v0.3-dev"
	rep.engine == {"name": "ergo.rego", "version": ergo.version}
}

test_the_version_on_main_ends_in_dev_because_only_the_release_workflow_drops_it if {
	regex.match(`^[0-9]+\.[0-9]+\.[0-9]+-dev$`, ergo.version)
}

test_a_report_that_cant_read_its_input_still_says_its_version_and_engine if {
	rep := ergo.report("not an object", _engine_policy, "not params")
	rep.ergo == "v0.3-dev"
	rep.engine.name == "ergo.rego"
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
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"meta": meta, "checks": {"c": {"assert": "id exists", "meta": meta}}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.requirements.s.meta == meta
	rep.requirements.s.checks.c.meta == meta
}

test_numbers_in_meta_are_written_the_same_way_however_the_policy_wrote_them if {
	written := {"s": object.union(typed_req, {"meta": {"n": [1.50, 1e2, -0, 1.0, 2.5e-3]}, "checks": {"c": {"assert": "id exists", "meta": {"n": 1E+2}}}})}
	plain := {"s": object.union(typed_req, {"meta": {"n": [1.5, 100, 0, 1, 0.0025]}, "checks": {"c": {"assert": "id exists", "meta": {"n": 100}}}})}
	json.marshal(report({"items": [{"id": 1}]}, written)) == json.marshal(report({"items": [{"id": 1}]}, plain))
	json.marshal(report({"items": [{"id": 1}]}, written).requirements.s.meta) == `{"n":[1.5,100,0,1,0.0025]}`
}

named_values(inputs) := [[i.name, i.value] | some i in inputs]

test_a_repeated_subject_id_is_written_the_same_way_whichever_spelling_comes_first if {
	ids := [json.marshal(rows_for(report({"items": items}, {"s": typed_req}), "s", "$unique_ids")[0].inputs[0].value) |
		some items in [[{"id": 1.0, "k": "a"}, {"id": 1e0, "k": "b"}], [{"id": 1e0, "k": "a"}, {"id": 1.0, "k": "b"}]]
	]
	ids == ["[1]", "[1]"]
}

test_a_number_a_float_cannot_hold_is_copied_into_the_report_as_written if {
	rep := report({"items": [{"id": 1, "n": 1e400}]}, {"s": object.union(typed_req, {"checks": {"c": "n is 1.50"}})})
	json.marshal([named_values(row.inputs) | some row in rep.results; row.check == "c"]) == `[[["n",1e400]]]`
}

test_a_number_is_written_in_its_plain_form_even_when_it_is_the_only_one_spelled_another_way if {
	written := [json.marshal([row.inputs[0].value | some row in report({"items": [{"id": "a", "n": n}]}, {"s": object.union(typed_req, {"checks": {"c": "n exists"}})}).results; row.check == "c"]) |
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
	rep := report({"items": [{"id": 1.50, "t": {"a"}}]}, {"s": object.union(typed_req, {"checks": {"c": "t exists"}})})
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
		["not_met", {}, [{"name": "meta", "value": ["holds a key that isn't a string"], "locations": []}]],
		["not_met", {}, [{"name": "meta", "value": ["holds a key that isn't a string"], "locations": []}]],
		["not_met", {}, [{"name": "meta", "value": ["holds a set"], "locations": []}]],
		["not_met", {}, [{"name": "meta", "value": ["number out of range"], "locations": []}]],
	]
}

test_a_check_meta_that_json_cannot_hold_is_written_wrong_and_is_reported_empty if {
	rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {
		"k": {"assert": "n exists", "meta": {"a": {1: "x"}}},
		"s": {"assert": "n exists", "meta": {"tags": {"a"}}},
		"r": {"assert": "n exists", "meta": {"n": 1e400}},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.k", "value": ["meta holds a key that isn't a string"], "locations": []},
		{"name": "checks.r", "value": ["number out of range"], "locations": []},
		{"name": "checks.s", "value": ["meta holds a set"], "locations": []},
	]
	[rep.requirements.s.checks[c].meta | some c in ["k", "r", "s"]] == [{}, {}, {}]
}

test_a_null_description_or_meta_counts_as_none_since_an_empty_yaml_field_reads_as_null if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"description": null, "meta": null, "checks": {"c": {"assert": "id exists", "description": null, "meta": null}}})})
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

test_a_policy_description_or_meta_written_wrong_fails_every_requirement_and_is_named_in_words_since_a_dollar_name_is_one_a_check_can_read if {
	rows := [[r.description, r.meta, r.compliant, [[w.requirement, w.passed, problem_inputs_of(w)] | some w in r.results; w.check == "$well_formed"]] |
		some extra in [{"description": 5, "meta": "x"}, {"meta": {"a": {1: "x"}}}, {"meta": {"n": 1e400}}]
		r := ergo.report({"items": [{"id": 1}]}, two_reqs_policy(extra), {})
	]
	rows == [
		["", {}, false, [
			["s", false, [{"name": "policy description", "value": ["not a string"], "locations": []}, {"name": "policy meta", "value": ["not an object"], "locations": []}]],
			["t", false, [{"name": "policy description", "value": ["not a string"], "locations": []}, {"name": "policy meta", "value": ["not an object"], "locations": []}]],
		]],
		["", {}, false, [
			["s", false, [{"name": "policy meta", "value": ["holds a key that isn't a string"], "locations": []}]],
			["t", false, [{"name": "policy meta", "value": ["holds a key that isn't a string"], "locations": []}]],
		]],
		["", {}, false, [
			["s", false, [{"name": "policy meta", "value": ["number out of range"], "locations": []}]],
			["t", false, [{"name": "policy meta", "value": ["number out of range"], "locations": []}]],
		]],
	]
}

_spec_rows(policy) := [r.compliant, [[w.requirement, w.passed, problem_inputs_of(w)] | some w in r.results; w.check == "$well_formed"]] if {
	r := ergo.report({"items": [{"id": 1}]}, policy, {})
}

test_a_policy_without_ergo_spec_is_written_wrong_so_every_requirement_fails if {
	every policy in [object.remove(two_reqs_policy({}), ["ergo_spec"]), two_reqs_policy({"ergo_spec": null})] {
		_spec_rows(policy) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": ["missing"], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": ["missing"], "locations": []}]],
		]]
	}
}

test_an_ergo_spec_that_is_not_a_string_is_written_wrong_because_yaml_reads_0_1_as_a_number if {
	every v in [0.1, 1, true, ["v0.3-dev"], {"v": "v0.3-dev"}] {
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": ["not a string"], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": ["not a string"], "locations": []}]],
		]]
	}
}

test_an_engine_reads_only_the_version_it_follows_so_any_other_ergo_spec_is_written_wrong if {
	every v in ["v0.1", "v0.2-dev", "v1.0", "v10.25", "v0.2"] {
		expected := concat("", ["unsupported version ", v, ", expected v0.3-dev"])
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
		]]
	}
}

test_an_ergo_spec_that_is_not_shaped_like_a_version_is_written_wrong_and_the_row_shows_it if {
	every v in ["0.1", "V0.1", "v0.1.0", " v0.2-dev", "v0.2-dev ", "v.1", "v1", "", "v0.2-beta", "v0.2-", "v0.2-dev-dev", "v0.2-DEV", "v0.2-dev2", "v0.3-devdev", "v-dev"] {
		expected := concat("", ["not a version ", v])
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
		]]
	}
}

test_the_expected_version_in_the_row_is_the_one_the_report_says_it_follows if {
	rep := ergo.report({"items": [{"id": 1}]}, two_reqs_policy({"ergo_spec": "v0.1"}), {})
	row := [i.value[0] | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "policy ergo_spec"][0]
	endswith(row, concat("", [", expected ", rep.ergo]))
}

test_the_policys_own_problems_are_sorted_by_name if {
	_spec_rows(two_reqs_policy({"ergo_spec": 1, "description": 5, "meta": "x"}))[1][0] == ["s", false, [
		{"name": "policy description", "value": ["not a string"], "locations": []},
		{"name": "policy ergo_spec", "value": ["not a string"], "locations": []},
		{"name": "policy meta", "value": ["not an object"], "locations": []},
	]]
}

test_a_compiled_policy_without_ergo_spec_fails_like_the_policy_it_came_from if {
	policy := object.remove(two_reqs_policy({}), ["ergo_spec"])
	ergo.report({"items": [{"id": 1}]}, ergo.compile(policy), {}) == ergo.report({"items": [{"id": 1}]}, policy, {})
	ergo.report({"items": [{"id": 1}]}, ergo.compile(policy), {}).compliant == false
}

test_a_policy_with_ergo_spec_and_no_requirements_is_still_not_compliant if {
	ergo.report({"items": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "requirements": {}}, {}).compliant == false
}

test_a_policy_ergo_spec_description_and_meta_are_kept_when_it_is_rewritten_as_sentences if {
	policy := two_reqs_policy({"description": "d", "meta": {"control": "DEV-0401"}})
	converted := ergo.as_sentences(policy)
	[converted.ergo_spec, converted.description, converted.meta] == ["v0.3-dev", "d", {"control": "DEV-0401"}]
}

problem_inputs_of(row) := [i |
	some i in row.inputs
	not i.name in {"count(checks)", "require"}
]

badly_written_requirements := {
	"require_most": [{"require": "most"}, [{"name": "require", "value": ["neither every nor some"], "locations": []}]],
	"require_number": [{"require": 5}, [{"name": "require", "value": ["neither every nor some"], "locations": []}]],
	"checks_empty": [{"checks": {}}, [{"name": "require", "value": "every", "locations": []}, {"name": "checks", "value": ["empty"], "locations": []}]],
	"min_out_of_range": [{"min_subjects": 1e400}, [{"name": "require", "value": "every", "locations": []}, {"name": "min_subjects", "value": ["number out of range"], "locations": []}]],
}

test_every_way_a_requirement_is_written_wrong_says_what_is_wrong if {
	got := {name: [row.passed, array.slice(row.inputs, 1, count(row.inputs))] |
		some name, [fields, _] in badly_written_requirements
		base := {"from": "items", "identified_by": "id", "checks": {"c": "id exists"}}
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

test_a_min_subjects_over_a_million_says_so_whatever_its_size if {
	every v in [1000001, 1000000.5, 1e308, 9007199254740993, -1, 1.5, "2", null, true] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == [{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []}]
	}
}

test_a_min_subjects_of_a_million_is_well_formed_however_it_is_written if {
	every v in [1000000, 1e6, 1.0e6, 1000000.0, 0] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == []
	}
}

test_a_min_subjects_past_a_float_is_out_of_range_not_over_a_million if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": 1e400})})
	problem_inputs(rep) == [{"name": "min_subjects", "value": ["number out of range"], "locations": []}]
}

test_a_min_subjects_that_is_not_a_number_says_so_even_holding_a_number_out_of_range if {
	every v in [[1e400], {"a": 1e400}] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == [{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []}]
	}
}

well_formed_or_not := array.concat(
	[object.union(object.remove(typed_req, object.keys(fields)), fields) | some [fields, _] in badly_written_requirements],
	array.concat(
		[object.union(typed_req, {f: v}) | some [f, v] in wrong_types],
		[
			typed_req,
			object.union(typed_req, {"require": "some", "subject_type": "item", "from": "items whose id exists"}),
			object.union(typed_req, {"from": "every groups.items"}),
			object.union(typed_req, {"zz": 1}),
			object.union(typed_req, {"checks": {"c": {"op": "nope"}}}),
			{"from": "items"},
			{"from": "items", "checks": {}},
			5,
		],
	),
)

test_a_requirement_fails_well_formed_exactly_when_its_row_says_what_is_wrong if {
	lifted_reqs := [lifted({"s": req}) | some req in well_formed_or_not]
	well_formed := {i |
		some i, l in lifted_reqs
		rd := ergo._read(l)
		ergo._well_formed(rd.reqs.s) with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences
	}
	nothing_listed := {i |
		some i, l in lifted_reqs
		rd := ergo._read(l)
		req := rd.reqs.s
		problems := (count(ergo._req_problems(req)) + count(ergo._check_problem_inputs(req))) + count(ergo._not_an_object_inputs(req)) with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences
		problems == 0
	}
	well_formed == nothing_listed
	count(well_formed) > 2
	count(well_formed_or_not) - count(well_formed) > 30
}

test_a_requirement_without_checks_says_they_are_missing if {
	row := rows_for(report({"items": [{"id": 1}]}, {"s": {"from": "items"}}), "s", "$well_formed")[0]
	row.inputs == [{"name": "count(checks)", "value": 0, "locations": []}, {"name": "require", "value": "every", "locations": []}, {"name": "checks", "value": ["missing"], "locations": []}]
}

test_problems_with_several_fields_are_listed_by_field if {
	req := {"from": 5, "require": "most", "zz": 1, "checks": {}, "min_subjects": -1}
	row := rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0]
	row.inputs == [
		{"name": "count(checks)", "value": 0, "locations": []},
		{"name": "checks", "value": ["empty"], "locations": []},
		{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []},
		{"name": "require", "value": ["neither every nor some"], "locations": []},
		{"name": "zz", "value": ["unknown field"], "locations": []},
		{"name": "subjects.subject.from", "value": ["not a string"], "locations": []},
	]
}

typed_req := {"from": "items", "identified_by": "id", "min_subjects": 0, "checks": {"c": "id exists"}}

wrong_types := [
	["checks", 5],
	["checks", ["id exists"]],
	["checks", null],
	["from", 5],
	["from", {"a": 1}],
	["from", null],
	["identified_by", 5],
	["identified_by", null],
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
	"checks": "not an object",
	"from": "not a string",
	"identified_by": "not a string",
	"min_subjects": "not a whole number from 0 to 1000000",
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
	rows == [[f, true, "not_met", false, "value", {"name": lifted_field_name(f), "value": [wrong_type_problems[f]], "locations": []}] | some [f, _] in wrong_types]
}

lifted_field_name(f) := concat(".", ["subjects", "subject", f]) if f in subject_fields

lifted_field_name("subject_type") := "subject"

lifted_field_name(f) := f if not f in array.concat(subject_fields, ["subject_type"])

test_a_requirement_that_is_not_an_object_finds_no_subjects_so_it_cannot_claim_the_whole_input if {
	rep := report({"items": [{"id": 1}]}, {"s": 5})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
	stopped(rep)
}

test_a_from_that_is_not_a_list_records_no_refs_because_it_is_never_read if {
	rep := report({}, {"s": object.union(typed_req, {"from": {"ref": ["$$params", "p"]}})})
	not "$refs" in object.keys(rep.requirements.s.checks["$min_subjects"])
}

test_a_field_of_the_right_type_adds_no_input_to_well_formed if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": "items whose id exists"})})
	row := rows_for(rep, "s", "$well_formed")[0]
	[row.passed, count(row.inputs)] == [true, 2]
}

test_checks_that_are_not_an_object_give_no_rows_named_by_list_index if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"checks": ["id exists"]})})
	stopped(rep)
	rows_for(rep, "s", "$well_formed")[0].inputs[0] == {"name": "count(checks)", "value": 0, "locations": []}
}

test_a_from_that_is_not_a_list_gives_no_subjects if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": 5, "min_subjects": 1})})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

test_an_id_that_is_not_a_string_stops_at_well_formed if {
	stopped(report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"identified_by": 5})}))
}

test_a_min_subjects_that_is_not_a_number_stops_at_well_formed_whatever_opa_thinks_of_comparing_it if {
	every m in ["0", null, [], {}] {
		stopped(report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})}))
	}
}

test_min_subjects_names_the_whole_input_like_the_checks_do_when_from_reads_it if {
	rows := [[d.expression, r.inputs[0].name] |
		some m in [{}, {"from": "$input"}]
		rep := report({"id": 1}, {"s": object.union({"checks": {"c": "id exists"}}, m)})
		d := rep.requirements.s.checks["$min_subjects"]
		some r in rows_for(rep, "s", "$min_subjects")
	]
	rows == [
		["count(matching($input)) >= 1", "in-scope subject count"],
		["count(matching($input)) >= 1", "in-scope subject count"],
	]
}

problem_inputs(rep) := [i |
	some i in rows_for(rep, "s", "$well_formed")[0].inputs
	not i.name in {"count(checks)", "require"}
]

test_every_badly_written_check_fails_well_formed_and_says_what_is_wrong if {
	every case in badly_written {
		[check, at, want] := case
		rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}})
		problem_inputs(rep) == [{"name": concat("", ["checks.c", at]), "value": want, "locations": []}]
	}
}

test_a_bare_word_after_named_by_that_no_for_line_gives_is_an_unknown_alias if {
	_sentence_problems({"for": "every xs named by x as x", "assert": "x is 1"}) == ["for: unknown alias x"]
}

test_a_dollar_word_in_a_sentence_is_not_an_alias_so_it_stays_an_unknown_name if {
	_sentence_problems({"for": "every xs as x", "assert": "x is $foo"}) == ["unknown name $foo"]
	_sentence_problems({"assert": "$foo.a exists"}) == ["unknown name $foo"]
}

odd_checks := [
	true,
	[],
	{},
	{"assert": {"x": 1}},
	{"any_of": 5},
	{"any_of": {"a": 5}},
	{"for": 5, "assert": "x"},
	{"for": "every xs as x", "assert": "x exists", "any_of": {"o": 5}},
]

test_every_check_however_badly_written_keeps_an_expression_in_its_definition if {
	checks := {sprintf("c%d", [i]): c | some i, c in array.concat([c | some [c, _, _] in badly_written], odd_checks)}
	defs := report({}, {"s": {"checks": checks}}).requirements.s.checks
	every name, _ in checks {
		is_string(defs[name].expression)
	}
}

test_a_check_meta_is_carried_into_the_report if {
	rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": {"assert": "n exists", "meta": {"refs": ["RB-1"], "severity": "high"}}}}})
	problem_inputs(rep) == []
	rep.requirements.s.checks.c.meta == {"severity": "high", "refs": ["RB-1"]}
}

test_a_check_without_a_description_or_meta_reports_empty_ones_so_tools_can_read_them_without_checking if {
	rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": "n exists"}}})
	rep.requirements.s.checks.c.description == ""
	rep.requirements.s.checks.c.meta == {}
}

test_a_check_description_or_meta_of_the_wrong_type_is_written_wrong_and_never_reaches_the_report if {
	rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {
		"d": {"assert": "n exists", "description": 5},
		"m": {"assert": "n exists", "meta": "high"},
		"n": {"assert": "n exists", "meta": []},
	}}})
	problem_inputs(rep) == [
		{"name": "checks.d", "value": ["invalid description"], "locations": []},
		{"name": "checks.m", "value": ["invalid meta"], "locations": []},
		{"name": "checks.n", "value": ["invalid meta"], "locations": []},
	]
	stopped(rep)
	rep.requirements.s.checks.d.description == ""
	rep.requirements.s.checks.m.meta == {}
	rep.requirements.s.checks.n.meta == {}
}

test_every_check_in_the_report_has_a_description_and_meta_even_the_ones_ergo_adds if {
	rep := report({"items": [{"id": 1, "env": "prod"}]}, {"s": {"from": "items whose env is \"prod\"", "identified_by": "id", "checks": {"c": "id is $params.p"}}})
	{name: [is_string(def.description), def.meta] | some name, def in rep.requirements.s.checks} == {
		"$applies": [true, {}],
		"$min_subjects": [true, {}],
		"$unique_ids": [true, {}],
		"$well_formed": [true, {}],
		"c": [true, {}],
	}
}

lockfile_req(conditions) := {"s": {"from": whose_line("items", conditions), "identified_by": "id", "min_subjects": 0, "checks": {"c": "hashed is true"}}}

lockfile_scope(item, conditions) := [rep.requirements.s.status, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := report({"items": [item]}, lockfile_req(conditions))
}

test_a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_other_filters_read if {
	filters := "status exists and status is \"COMPLETE\""
	lockfile_scope({"id": 1}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": null}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1}, concat(" and ", [filters, "owner is \"me\""])) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "PENDING"}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "COMPLETE", "hashed": true}, filters) == ["met", ["satisfied"]]
}

test_an_empty_subject_name_fails_well_formed_because_rows_and_descriptions_would_name_nothing if {
	every name in ["", " ", "\t "] {
		rep := ergo.report({"items": [{"id": 1}]}, named_subject_policy(name), {})
		row := rows_for(rep, "s", "$well_formed")[0]
		[row.passed, row.inputs[count(row.inputs) - 1]] == [false, {"name": "subject", "value": ["empty or not a string"], "locations": []}]
	}
	rep := ergo.report({"items": [{"id": 1}]}, named_subject_policy("a b"), {})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.results[0].subject.type == "a b"
}

named_subject_policy(name) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {name: {"from": "items", "identified_by": "id"}},
	"requirements": {"s": {"subject": name, "checks": {"c": "id exists"}}},
}

plain_defs(req) := report({"items": [{"id": 1}]}, {"s": object.union({"from": "items whose id exists", "identified_by": "id", "checks": {"c": "id exists"}}, req)}).requirements.s.checks

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

test_min_subjects_names_its_input_after_what_it_counts if {
	rep := report({"items": []}, {"s": {"subject_type": "deployment", "from": "items", "checks": {"c": "id exists"}}})
	[r.inputs | some r in rows_for(rep, "s", "$min_subjects")] == [[{"name": "in-scope deployment count", "value": 0, "locations": []}]]
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(items)) >= 1"
}

test_well_formed_definition_is_in_the_check_table if {
	rep := report({"items": [{"id": "a"}]}, id_req("items"))
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

require_req(q) := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"require": q,
	"checks": {
		"signed": "signed is true",
		"reviewed": "reviewed is true",
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
	scoped := {"s": object.union(some_req_zero.s, {"from": whose_line("items", merged_only)})}
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
		"from": "items",
		"identified_by": "id",
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
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "min_subjects": 1, "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "min_subjects": 1, "checks": {"c": "id exists"}},
	}
	report(doc, policy).compliant == true
}

test_not_compliant_when_any_requirement_is_not_met if {
	doc := {"a": [{"id": "1"}], "b": [{"no_id": true}]}
	policy := {
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "id exists"}},
	}
	report(doc, policy).compliant == false
}

prod_only := {"s": {
	"subject_type": "deployment",
	"from": "deployments whose env is \"prod\"",
	"identified_by": "id",
	"min_subjects": 0,
	"checks": {"approved": "approved_by exists"},
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
		{"checks": {"approved": "approved_by is"}},
		{"from": "deployments whose region is \"eu\""},
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
	policy := {"a": prod_only.s, "b": object.union(prod_only.s, {"from": "deployments"})}
	rep := report({"deployments": [{"id": 1, "env": "dev", "approved_by": "ann"}]}, policy)
	[rep.requirements.a.status, rep.requirements.b.status] == ["not_applicable", "met"]
	rep.compliant == true
}

test_not_compliant_when_one_requirement_is_not_applicable_and_another_is_not_met if {
	policy := {"a": prod_only.s, "b": object.union(prod_only.s, {"from": "deployments"})}
	rep := report({"deployments": [{"id": 1, "env": "dev"}]}, policy)
	[rep.requirements.a.status, rep.requirements.b.status] == ["not_applicable", "not_met"]
	rep.compliant == false
}

test_a_condition_on_the_input_can_make_a_requirement_not_applicable_while_unknown_values_still_count if {
	req := {"s": {
		"subject_type": "deployment",
		"from": "$input whose $params.untested_change_types does not contain $input.deployment.change_type",
		"min_subjects": 0,
		"checks": {
			"tested": "some test_runs.status exists",
			"passed": "every test_runs.status is \"passed\"",
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
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "id exists"}},
	}
	object.keys(report(doc, policy).requirements) == {"first", "second"}
}

test_requirement_entry_carries_exactly_the_documented_keys if {
	rep := solo({"state": "MERGED"}, is_merged)
	object.keys(rep.requirements.s) == {"description", "meta", "require", "subject", "status", "causes", "subjects", "checks"}
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

test_row_order_groups_by_check_kind_then_requirement if {
	req := {
		"subject_type": "t",
		"from": "items whose live is true",
		"identified_by": "id",
		"checks": {
			"zeta": "id exists",
			"alpha": "id exists",
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
	req := {"from": "items", "identified_by": "id", "checks": {"c": "id exists"}}
	rep := report({"items": [{"id": 1}]}, {"t": req, "s": req, "delta": req, "alpha": req, "gamma": req, "beta": req})
	[r.requirement | some r in rep.results; r.check == "c"] == ["alpha", "beta", "delta", "gamma", "s", "t"]
}

test_checks_come_out_in_name_order_whatever_the_runtime if {
	check := "id exists"
	rep := report({"items": [{"id": 1}]}, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check, "b": check, "a": check, "delta": check, "gamma": check}}})
	[r.check | some r in rep.results; not startswith(r.check, "$")] == ["a", "b", "c", "delta", "gamma"]
}

test_a_policy_written_as_a_set_still_gets_a_row if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"item": {"from": "items", "identified_by": "id"}}, "requirements": {{"subject": "item", "checks": {"c": "id exists"}}}}
	stopped(ergo.report({"items": [{"id": 1}]}, policy, {}))
}

checks_for(subject) := ergo.report({"xs": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "requirements": {"s": {"subject": subject, "checks": {"c": "id exists"}}}}, {}).requirements.s.checks

test_a_subject_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	checks_for(["a", "b"])["$min_subjects"].description == `The in-scope ["a", "b"] count is at least 1`
	checks_for(null)["$unique_ids"].description == "Every null id is unique"
	checks_for(-1)["$unique_ids"].description == "Every -1 id is unique"
}

test_every_row_resolves_to_one_check_definition if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"from": whose_line("items", merged_only)})}
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
	"from": "items",
	"identified_by": "id",
	"checks": {
		"signed": {"assert": "signed is true", "description": "Signed"},
		"reviewed": {"assert": "reviewed is true", "description": "Reviewed"},
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
		"expression": "reviewed is true",
		"inputs": [{"name": "reviewed", "value": null, "locations": ["/items/0"]}],
		"cause": "absent",
	}]
}

test_violations_default_a_missing_description_to_an_empty_string if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
		"checks": {"undescribed": "x is 1"},
	}})
	v := ergo.violations(rep)
	count(v) == 1
	v[0].description == ""
	v[0].expression == "x is 1"
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
		"from": whose_line("items", merged_only),
		"identified_by": "id",
		"checks": {"signed": "signed is true"},
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
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "v is 1"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "v is 1"}},
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
		{"s": {"from": "items", "identified_by": "no_such_field", "checks": {"signed": "signed is true"}}},
	)
	[[v.check, v.subject.id] | some v in ergo.violations(rep)] == [["$unique_ids", null], ["signed", null], ["signed", null]]
}

test_violations_take_the_definition_from_the_rows_own_requirement if {
	rep := report({"a": [{"id": 1}], "b": [{"id": 2}]}, {
		"first": {"from": ".a", "identified_by": "id", "checks": {"c": {"assert": "x exists", "description": "First"}}},
		"second": {"from": "b", "identified_by": "id", "checks": {"c": {"assert": "x exists", "description": "Second"}}},
	})
	{[v.requirement, v.description] | some v in ergo.violations(rep)} == {["first", "First"], ["second", "Second"]}
}

test_a_requirement_without_checks_yields_a_violation if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
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

scan_checksets := [{}, {"c": "id exists"}]

scan_filters := ["", "state is \"MERGED\""]

scan_docs := [
	{"items": []},
	{"items": [{"id": "a", "state": "MERGED"}]},
	{"items": [{"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "MERGED"}, {"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "CLOSED"}]},
]

scan_policy(rq, mn, cs, fl) := {"s": {
	"subject_type": "thing",
	"from": whose_line("items", fl),
	"identified_by": "id",
	"require": rq,
	"min_subjects": mn,
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
	report({"items": [{"id": "a"}]}, id_req("itmes")).compliant == false
}

test_a_policy_with_no_requirements_is_not_compliant if {
	report({"items": []}, {}).compliant == false
}

test_min_subjects_row_labels_the_count_it_actually_reports if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"from": whose_line("items", merged_only)})}
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
		"thing": {"subject_type": "thing", "from": ".a", "identified_by": "id", "checks": {"chk": "v is 1"}},
		"other_thing": {"subject_type": "thing", "from": "b", "identified_by": "id", "checks": {"chk": "v is 2"}},
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
		"from": "items",
		"identified_by": "id",
		"min_subjects": 1,
		"checks": {"min_subjects": {"assert": "id is \"zzz\"", "description": "user check"}},
	}}
	rep := report({"items": [{"id": "a"}]}, colliding)

	rep.requirements.s.checks.min_subjects == {
		"description": "user check",
		"meta": {},
		"expression": `id is "zzz"`,
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
		"from": "items",
		"identified_by": "id",
	}})
	rep.requirements.s.status == "not_met"
	count(rep.results) > 0
}

test_equals_null_does_not_pass_on_a_missing_field if {
	verdict({}, "x is null") == false
}

test_any_rejects_an_object_collection if {
	verdict({"approvers": {"a": {"state": "APPROVED"}}}, any_approved) == false
}

test_all_over_an_empty_collection_is_not_a_pass if {
	verdict({"commits": []}, all_verified) == false
}

degraded_only := "degraded is true"

degraded_req(req_kind) := degraded_req_whose(req_kind, degraded_only)

degraded_req_whose(req_kind, conditions) := {"s": {
	"subject_type": "round",
	"from": whose_line("rounds", conditions),
	"identified_by": "id",
	"require": req_kind,
	"min_subjects": 0,
	"checks": {"c": "signed is true"},
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

test_a_filter_value_of_the_wrong_type_fails_the_requirement_instead_of_leaving_the_subject_out if {
	rep := report({"rounds": [{"id": "r1", "degraded": "yes"}]}, degraded_req("every"))
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "unusable"
}

test_a_subject_ruled_out_by_one_filter_still_fails_the_requirement_when_another_filter_cannot_be_read if {
	req := degraded_req_whose("every", concat(" and ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
	[v.check | some v in ergo.violations(rep)] == ["$applies"]
}

test_a_subject_is_out_of_scope_when_every_failing_filter_reads_sound_values if {
	req := degraded_req_whose("every", concat(" and ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED", "degraded": false}]}, req)
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_whose_filter_fails_on_an_unreadable_field_is_not_ruled_out_by_a_passing_filter if {
	req := degraded_req_whose("every", concat(" and ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "MERGED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

locked_req(filter_path) := {"s": {
	"from": concat("", ["packages whose ", filter_path, " exists"]),
	"identified_by": "id",
	"min_subjects": 0,
	"checks": {"c": "signed is true"},
}}

test_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	rep := report({"packages": [{"id": "a"}]}, locked_req("lock"))
	rep.requirements.s.status == "not_applicable"
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "value"]]
	ergo.violations(rep) == []
}

test_a_present_filter_rules_out_a_subject_whose_field_is_null if {
	rep := report({"packages": [{"id": "a", "lock": null}]}, locked_req("lock"))
	rep.requirements.s.status == "not_applicable"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_a_present_filter_still_fails_on_a_subject_that_is_not_an_object if {
	rep := report({"packages": ["a"]}, locked_req("lock"))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["not_an_object"]
}

test_a_present_check_on_a_missing_field_is_a_clean_no if {
	cause_of({}, "lock exists") == "value"
}

test_only_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	req := {"s": object.union(locked_req("lock").s, {"from": "packages whose lock is a non-empty string"})}
	rep := report({"packages": [{"id": "a"}]}, req)
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

in_doc(top, subj, check) := report(object.union(top, {"items": [subj]}), {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"checks": {"c": check},
}})

row_in(top, subj, check) := r if {
	some r in in_doc(top, subj, check).results
	r.check == "c"
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

test_an_input_path_reads_from_the_top_for_a_subject_that_is_not_an_object if {
	r := row_in({"mode": "strict"}, "a", "$input.mode is \"strict\"")
	[r.passed, r.cause] == [true, "satisfied"]
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

params_req(check) := {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}}

params_rows(doc, check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(doc, params_req(check)), "s", "c")]

test_a_path_can_start_at_params if {
	check := "$params.level is one of \"strict\", \"lax\""
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.level", "value": "strict", "locations": ["$params:/level"]}]]] with data.params as {"level": "strict"}
}

test_params_that_are_missing_fail_closed if {
	check := "licences does not contain $params.banned"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}]]]
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}]]] with data.params as null
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "unusable", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}]]] with data.params as "not an object"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "null", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}]]] with data.params as {"banned": null}
}

test_a_present_check_on_a_param_fails_as_absent_with_no_params_and_as_unusable_with_params_that_are_not_an_object if {
	check := "$params.x exists"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as null
	every params in ["not an object", 1, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[false, "value", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as {}
}

test_a_missing_check_on_a_param_fails_as_absent_with_no_params_and_as_unusable_with_params_that_are_not_an_object if {
	check := "$params.x does not exist"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as null
	every params in ["not an object", 1, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as {}
}

test_a_present_filter_on_a_param_fails_the_requirement_with_no_params_or_params_that_are_not_an_object if {
	req := {"s": {
		"from": "items whose $params.x exists",
		"identified_by": "id",
		"checks": {"c": "id exists"},
	}}
	every params, cause in {"null": "absent", `"not an object"`: "unusable"} {
		rep := report({"items": [{"id": 1}]}, req) with data.params as json.unmarshal(params)
		rep.requirements.s.status == "not_met"
		rows_for(rep, "s", "$applies")[0].cause == cause
	}
}

test_the_applies_row_lists_each_field_its_filters_read_once_in_name_order if {
	req := {"s": {
		"from": "items whose status exists and status is \"open\" and kind exists",
		"identified_by": "id",
		"checks": {"c": "id exists"},
	}}
	rep := report({"items": [{"id": 1, "status": "open", "kind": "x"}]}, req)
	[i.name | some i in rows_for(rep, "s", "$applies")[0].inputs] == ["kind", "status"]
}

test_the_report_never_reads_data_params if {
	policy := lifted(params_req("name is $params.artifact_name"))
	rep := ergo.report({"items": [{"id": 1, "name": "app"}]}, policy, {"artifact_name": "app"}) with data.params as {"artifact_name": "web"}
	[[r.passed, r.inputs] | some r in rows_for(rep, "s", "c")] == [[true, [{"name": "name", "value": "app", "locations": ["/items/0/name"]}, {"name": "$params.artifact_name", "value": "app", "locations": ["$params:/artifact_name"]}]]]
	unset := ergo.report({"items": [{"id": 1, "name": "app"}]}, policy, {}) with data.params as {"artifact_name": "app"}
	[r.cause | some r in rows_for(unset, "s", "c")] == ["absent"]
}

empty_report := {"compliant": false, "description": "", "engine": {"name": "ergo.rego", "version": ergo.version}, "ergo": "v0.3-dev", "meta": {}, "requirements": {}, "results": [], "subjects": {}}

test_a_policy_without_requirements_is_not_compliant if {
	ergo.report({"items": [{"id": 1}]}, {}, {}) == empty_report
	ergo.report({"items": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "requirements": {}}, {}) == empty_report
	ergo.report({"items": [{"id": 1}]}, {"requirments": params_req("id exists")}, {}) == empty_report
}

test_a_policy_that_is_not_an_object_is_not_compliant if {
	every policy in [null, true, 1, "requirements", [], [params_req("id exists")]] {
		ergo.report({"items": [{"id": 1}]}, policy, {}) == empty_report
	}
}

test_requirements_that_are_not_an_object_are_not_compliant if {
	every reqs in [null, true, 1, "", "s", []] {
		ergo.report({"items": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "requirements": reqs}, {}) == empty_report
	}
	ergo.report({"items": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "requirements": [params_req("id exists").s]}, {}).compliant == false
}

test_sections_ergo_does_not_know_leave_the_report_unchanged if {
	policy := lifted(params_req("id exists"))
	rep := ergo.report({"items": [{"id": 1}]}, policy, {})
	rep.compliant == true
	ergo.report({"items": [{"id": 1}]}, object.union(policy, {"notes": "reviewed by the platform team"}), {}) == rep
}

test_params_are_not_read_from_the_input if {
	check := "name is $params.artifact_name"
	params_rows({"items": [{"id": 1, "name": "app"}], "params": {"artifact_name": "app"}}, check) == [[false, "absent", [{"name": "name", "value": "app", "locations": ["/items/0/name"]}, {"name": "$params.artifact_name", "value": null, "locations": ["$params:"]}]]]
}

test_a_key_called_dollar_dollar_params_is_read_with_literal if {
	check := "\"$$params\" is \"own\""
	params_rows({"items": [{"id": 1, "$$params": "own"}]}, check) == [[true, "satisfied", [{"name": `"$$params"`, "value": "own", "locations": ["/items/0/$$params"]}]]] with data.params as {"$$params": "other"}
}

trail_doc := {"trail": {"artifacts": {"app": {
	"fingerprint": "abc",
	"attestations": {"pull-request": {"status": "COMPLETE"}, "junit": {"status": "FAILED"}},
	"tags": ["v1", "v2"],
}}}}

trail_req(check) := {"s": {
	"from": "trail.artifacts named by $params.artifact",
	"identified_by": "fingerprint",
	"checks": {"c": check},
}}

trail_rows(check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(trail_doc, trail_req(check)), "s", "c")]

attested := "attestations named by $params.att.status is \"COMPLETE\""

test_a_ref_step_in_a_path_reads_the_key_it_names if {
	trail_rows(attested) == [[true, "satisfied", [{"name": "attestations named by $params.att.status", "value": "COMPLETE", "locations": ["/trail/artifacts/app/attestations/pull-request/status"]}]]] with data.params as {"artifact": "app", "att": "pull-request"}
	trail_rows(attested) == [[false, "value", [{"name": "attestations named by $params.att.status", "value": "FAILED", "locations": ["/trail/artifacts/app/attestations/junit/status"]}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_step_renders_and_is_recorded_like_any_ref if {
	rep := report(trail_doc, trail_req(attested)) with data.params as {"artifact": "app", "att": "junit"}
	rep.requirements.s.checks.c.expression == `attestations named by $params.att.status is "COMPLETE"`
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.att", "value": "junit", "locations": ["$params:/att"]}]
	ergo.violations(rep)[0].inputs == [{"name": "attestations named by $params.att.status", "value": "FAILED", "locations": ["/trail/artifacts/app/attestations/junit/status"]}, {"name": "$params.att", "value": "junit", "locations": ["$params:/att"]}]
}

test_a_ref_step_can_be_a_list_index if {
	check := "tags named by $params.i is \"v2\""
	[r[0] | some r in trail_rows(check)] == [true] with data.params as {"artifact": "app", "i": 1}
}

test_a_ref_step_that_cannot_be_read_fails_the_check if {
	trail_rows(attested) == [[false, "absent", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app"}
	trail_rows(attested) == [[false, "null", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app", "att": null}
	every bad in [["pull-request"], {"k": "pull-request"}, true] {
		trail_rows(attested) == [[false, "unusable", [{"name": "attestations named by $params.att.status", "value": null, "locations": ["/trail/artifacts/app/attestations"]}]]] with data.params as {"artifact": "app", "att": bad}
	}
}

test_a_ref_step_in_from_finds_the_subjects if {
	rep := report(trail_doc, trail_req("fingerprint exists")) with data.params as {"artifact": "app"}
	rep.requirements.s.subjects == {"total": 1, "matching": 1}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(trail.artifacts named by $params.artifact)) >= 1"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.artifact", "value": "app", "locations": ["$params:/artifact"]}]
	rep.requirements.s.status == "met"
}

test_a_ref_step_in_from_that_cannot_be_read_fails_the_requirement_even_with_min_subjects_zero if {
	req := {"s": object.union(trail_req("fingerprint exists").s, {"min_subjects": 0})}
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
	vs := ergo.violations(report(trail_doc, trail_req("fingerprint exists"))) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope subject count", "value": 0, "locations": []}, {"name": "$params.artifact", "value": null, "locations": ["$params:"]}]]]
}

test_a_ref_step_at_the_end_of_from_is_not_a_naming_step if {
	rep := report(trail_doc, trail_req("fingerprint exists")) with data.params as {"artifact": "app"}
	count(rows_for(rep, "s", "$well_formed")[0].inputs) == 2
}

test_a_present_filter_with_a_ref_step_that_cannot_be_read_cannot_rule_subjects_out if {
	rep := report(trail_doc, {"s": {
		"from": "trail.artifacts.app whose attestations named by $params.att exists",
		"min_subjects": 0,
		"checks": {"c": "fingerprint is \"nope\""},
	}})
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_present_filter_with_a_ref_step_still_rules_out_a_missing_field if {
	rep := report(trail_doc, {"s": {
		"from": "trail.artifacts.app whose attestations named by $params.att exists",
		"min_subjects": 0,
		"checks": {"c": "fingerprint is \"nope\""},
	}}) with data.params as {"att": "sbom"}
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

typo_doc := {"params": {"word": "x", "none": null, "nine": 9}, "items": [{"id": 1, "n": 1, "s": "a", "xs": [1], "t": "2026-01-01T00:00:00Z"}]}

badly_written := [
	[`n is one of 1, "a"`, "", ["values of mixed types"]],
	["n is between 9 and 0", "", ["min above max"]],
	[`s matches "("`, "", [`invalid pattern "("`]],
	[`s does not match "b" or "("`, "", ["doesn't parse"]],
	["xs[9007199254740992] exists", "", ["9007199254740992 can't be a list position"]],
	["item 9007199254740992 of xs exists", "", ["9007199254740992 can't be a list position"]],
	["n is $foo", "", ["unknown name $foo"]],
	["n is", "", ["doesn't parse"]],
	["n is at least 1e400", "", ["number out of range: 1e400"]],
	["n is at least n", "", ["n is compared with itself"]],
	["empty is 1", "", ["empty is a word of the grammar: write .empty"]],
	["some xs, if any, exists", "", ["if any can't go with some"]],
	[`t is before "yesterday"`, "", [`"is before" takes a time or a number`]],
	[`every xs.v is one of 1, "a"`, "", ["values of mixed types"]],
	[`count of xs whose v is one of 1, "a" is 0`, "", ["values of mixed types"]],
	["count of xs whose v is between 9 and 0 is 0", "", ["min above max"]],
	[`count of xs whose v matches "(" is 0`, "", [`invalid pattern "("`]],
	["count of xs whose $foo exists is 0", "", ["unknown name $foo"]],
	["count of xs whose v[9007199254740992] exists is 0", "", ["9007199254740992 can't be a list position"]],
	[`every xs whose v is one of 1, "a" is 1`, "", ["values of mixed types"]],
	["n exists whose v is 1", "", ["doesn't parse"]],
	["every xs some ys is 1", "", ["two quantifiers in one sentence: put them on a for line"]],
	[{"assert": "n exists", "description": 5}, "", ["invalid description"]],
	[{"assert": "n exists", "meta": "high"}, "", ["invalid meta"]],
	[{"assert": "n exists", "meta": []}, "", ["invalid meta"]],
	[{"assert": "n exists", "zz": 1}, "", ["unknown field zz"]],
	[{"assert": 5}, "", ["invalid assert"]],
	[{"assert": []}, "", ["empty assert"]],
	[{"assert": ["n exists", "n is"]}, "", ["line 2: doesn't parse"]],
	[{"for": "every xs as x"}, "", ["missing assert"]],
	[{"assert": "x exists", "for": "every xs"}, "", [`for: an item ends with "as" and a name, like "every pull_requests as pr"`]],
	[{"assert": "x exists", "for": "every xs as x, every x.ys as x"}, "", ["for: x is given twice"]],
	[{"assert": "x exists", "for": `every xs whose v is one of 1, "a" as x`}, "", ["for: values of mixed types"]],
	[{"assert": `x is one of 1, "a"`, "for": "every xs as x"}, "", ["values of mixed types"]],
	[{"assert": ["n exists", "n is one of 1, \"a\""]}, "", ["line 2: values of mixed types"]],
	[{"assert": ["n is one of 1, \"a\"", "n is"]}, "", ["line 1: values of mixed types", "line 2: doesn't parse"]],
	[{"assert": "n exists", "for": 5}, "", ["invalid for"]],
	[{"any_of": {"o": "n is"}}, "", ["option o: doesn't parse"]],
	[{"any_of": {"o": ["n exists", "n is one of 1, \"a\""]}}, "", ["option o: line 2: values of mixed types"]],
	[{"any_of": {"a": ["n exists and n exists", "n exists"], "b": ["n exists and n exists", "n is one of 1, \"a\""]}}, "", ["option b: line 2: values of mixed types"]],
	[{"any_of": {"a": "n exists", "b": "n is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": "n exists and n exists", "b": "n is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": "n exists", "b": "n exists and every xs is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": ["n exists", "every xs is one of 1, \"a\""], "b": "n is one of 1, \"a\""}}, "", ["option a: line 2: values of mixed types", "option b: values of mixed types"]],
	[{"any_of": {}}, "", ["empty any_of"]],
	[{"any_of": {"o": []}}, "", ["empty option o"]],
	[{"any_of": "o"}, "", ["invalid any_of"]],
	[{"any_of": {"o": "n exists"}, "assert": "n exists"}, "", ["unknown field any_of"]],
	[5, "", ["invalid check"]],
	[null, "", ["invalid check"]],
]

test_a_check_whose_ref_reads_the_wrong_kind_of_value_fails_as_unusable_and_is_not_written_wrong if {
	every check in ["s matches $input.params.word", "n is one of $input.params.word"] {
		rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "unusable"]]
		rows_for(rep, "s", "$well_formed")[0].passed == true
	}
}

test_a_badly_written_check_stops_its_requirement_at_well_formed if {
	every case in badly_written {
		stopped(report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": case[0]}}}))
	}
}

filter_policy(subjects) := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": "b", "min_subjects": 0, "checks": {"c": "x exists"}}}}

test_a_badly_written_filter_fails_well_formed_too if {
	rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": `things whose x is one of 1, "a"`}}), {})
	problem_inputs(rep) == [{"name": "subjects.b.from", "value": ["values of mixed types"], "locations": []}]
	stopped(rep)
}

badly_written_filters := [
	[`x is one of 1, "a"`, "values of mixed types"],
	["x is between 9 and 0", "min above max"],
	[`x matches "("`, `invalid pattern "("`],
	["x is $foo", "unknown name $foo"],
	["xs[9007199254740992] exists", "9007199254740992 can't be a list position"],
	["x is at least x", "whose: x is compared with itself"],
	["x is at least 1e400", "number out of range: 1e400"],
	[`x is before "yesterday"`, `"is before" takes a time or a number`],
	["x is", "doesn't parse"],
]

test_every_badly_written_filter_fails_well_formed_and_says_what_is_wrong if {
	every case in badly_written_filters {
		[whose, want] := case
		rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": concat(" whose ", ["things", whose])}}), {})
		problem_inputs(rep) == [{"name": "subjects.b.from", "value": [want], "locations": []}]
		rep.compliant == false
	}
}

test_a_badly_written_filter_is_named_after_the_subject_whose_from_line_holds_it if {
	subjects := {"thing": {"from": `things whose x is one of 1, "a"`}, "b": {"from": "thing whose y exists"}}
	rep := ergo.report({"things": [{"x": 1, "y": 1}]}, filter_policy(subjects), {})
	problem_inputs(rep) == [{"name": "subjects.thing.from", "value": ["values of mixed types"], "locations": []}]
}

test_a_badly_written_filter_on_a_parent_or_a_grandparent_stops_the_child_at_well_formed if {
	subjects := {
		"artifact": {"from": `artifacts whose x is one of 1, "a"`, "identified_by": "id"},
		"pr": {"from": "artifact.prs", "identified_by": "url"},
		"commit": {"from": "pr.commits", "identified_by": "sha"},
	}
	doc := {"artifacts": [{"id": "a", "x": 1, "prs": [{"url": "p", "commits": [{"sha": "s"}]}]}]}
	every name in ["pr", "commit"] {
		rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": name, "checks": {"c": "x exists"}}}}, {})
		stopped(rep)
		problem_inputs(rep) == [{"name": "subjects.artifact.from", "value": ["values of mixed types"], "locations": []}]
	}
}

test_a_badly_written_filter_stops_the_requirement_even_when_another_condition_rules_the_subject_out if {
	rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": `things whose x is one of 1, "a" and y exists`}}), {})
	stopped(rep)
	rep.requirements.s.status == "not_met"
	[v.check | some v in ergo.violations(rep)] == ["$well_formed"]
}

test_an_index_that_cannot_be_a_key_is_written_wrong_wherever_it_sits if {
	big := "99999999999999999999"
	checks := [
		concat("", ["items[", big, "] does not exist"]),
		concat("", ["item ", big, " of items does not exist"]),
		concat("", ["count of items whose v[", big, "] exists is 0"]),
		{"for": "every items as i", "assert": concat("", ["i.v[", big, "] does not exist"])},
		{"for": concat("", ["every items whose v[", big, "] does not exist as i"]), "assert": "i exists"},
	]
	subjects := [
		{"from": concat("", ["things[", big, "].items"])},
		{"from": concat("", ["things whose items[", big, "] does not exist"])},
	]
	policies := array.concat(
		[{"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {"c": c}}}} | some c in checks],
		[filter_policy({"b": def}) | some def in subjects],
	)
	got := [[rep.compliant, [p | some i in problem_inputs(rep); some p in i.value]] |
		some policy in policies
		rep := ergo.report({"things": [{"items": [1]}]}, policy, {})
	]
	got == [[false, [concat("", [prefix, big, " can't be a list position"])]] | some prefix in ["", "", "", "", "for: ", "", ""]]
}

named_by_then_each_of_policy(from) := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": from}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x is 1"}}}}

test_a_from_line_can_read_a_key_named_by_a_param_before_naming_each_subject if {
	every from in [
		"top named by $params.g named by each of $params.keys",
		"top named by $input.g named by each of $params.keys",
		"top[$params.g] named by each of $params.keys whose x exists",
	] {
		rep := ergo.report({"g": "m", "top": {"m": {"k1": {"x": 1}, "k2": {"x": 2}}}}, named_by_then_each_of_policy(from), {"g": "m", "keys": ["k1", "k2"]})
		rows_for(rep, "s", "$well_formed")[0].passed == true
		[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [["k1", true, "satisfied"], ["k2", false, "value"]]
	}
}

position_child_policy(from) := {"ergo_spec": "v0.3-dev", "subjects": {"p": {"from": "ps"}, "k": {"from": from}}, "requirements": {"r": {"subject": "k", "checks": {"c": "x exists"}}}}

test_a_position_after_a_parents_name_is_read_and_never_drops_to_narrowing_the_parent if {
	every from in ["p[0]", "p[1]", "first of p", "item 2 of p"] {
		rep := ergo.report({"ps": [{"x": 1}]}, position_child_policy(from), {})
		rep.compliant == false
		rep.requirements.r.status == "not_met"
		[[r.passed, r.cause] | some r in rows_for(rep, "r", "$min_subjects")] == [[false, "unusable"]]
		count(rows_for(rep, "r", "c")) == 0
		count(ergo.violations(rep)) == 1
	}
}

test_a_position_after_a_parents_name_picks_the_item_of_each_parent_that_is_a_list if {
	rep := ergo.report({"ps": [[{"x": 1}, {"x": 2}], [{"x": 3}]]}, position_child_policy("p[1]"), {})
	[r.cause | some r in rows_for(rep, "r", "$min_subjects")] == ["satisfied", "absent"]
	rep2 := ergo.report({"ps": [[{"x": 1}, {"x": 2}]]}, position_child_policy("item 2 of p"), {})
	rep2.compliant == true
	[[r.passed, r.cause] | some r in rows_for(rep2, "r", "c")] == [[true, "satisfied"]]
}

test_a_position_of_a_list_input_in_a_from_line_is_read_and_every_over_it_reads_its_items if {
	every from in ["$input[0]", "first of $input", "item 1 of $input", "every $input[0]"] {
		rep := ergo.report([[{"x": 1}], [{"x": 2}]], position_child_policy(from), {})
		[[r.passed, r.cause] | some r in rows_for(rep, "r", "$min_subjects")] == [[true, "satisfied"]]
	}
}

test_last_of_after_a_parents_name_in_a_from_line_is_written_wrong_and_still_lists_the_parent if {
	rep := ergo.report({"ps": [[{"x": 1}]]}, position_child_policy("last of p"), {})
	rep.requirements.r.status == "not_met"
	object.keys(rep.subjects) == {"k", "p"}
	some row in rows_for(rep, "r", "$well_formed")
	some entry in row.inputs
	entry.name == "subjects.k.from"
	entry.value == [`last of isn't supported yet here: pick the item on a for line, like "for: last of commits as commit"`]
}

test_a_from_line_with_every_that_reads_a_missing_param_keeps_its_requirement_and_fails_min_subjects if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "every x named by $params.k", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}
	every case in [[{}, "absent"], [{"k": null}, "null"], [{"k": ["x"]}, "unusable"]] {
		rep := ergo.report({"x": [{"id": 1}]}, policy, case[0])
		rep.requirements.s.status == "not_met"
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, case[1]]]
		count(ergo.violations(rep)) == 1
	}
}

test_a_from_line_with_every_on_a_null_input_fails_min_subjects_as_null_like_the_place_its_walk_breaks if {
	every from in ["every commits", "every $input[0]", "every $input[0].y", "every x.y", "every x[0]", "every commits named by $params.k"] {
		policy := {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": from}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}
		rep := ergo.report(null, policy, {"k": "a"})
		rep.requirements.s.status == "not_met"
		[[r.passed, r.cause, [f.cause | some f in r.failed_items]] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "null", ["null"]]]
	}
}

test_named_by_each_of_on_an_object_that_cant_be_read_fails_min_subjects_so_a_check_for_a_missing_field_cant_meet_the_requirement if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
	every run in [
		[{}, "absent"],
		[{"m": null}, "null"],
		[{"m": [{"x": 1}]}, "unusable"],
		[{"m": "k1"}, "unusable"],
	] {
		rep := ergo.report(run[0], policy, {"keys": ["k1"]})
		rep.compliant == false
		rep.requirements.s.status == "not_met"
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, run[1]]]
		[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["k1", true]]
	}
}

test_named_by_each_of_a_key_that_isnt_a_string_makes_no_subject_and_fails_min_subjects_as_unusable if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
	every keys in [["k1", 1], [null]] {
		rep := ergo.report({"m": {"k1": {}}}, policy, {"keys": keys})
		rep.compliant == false
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "unusable"]]
		rows_for(rep, "s", "c") == []
	}
}

test_named_by_each_of_still_makes_a_subject_of_a_key_the_object_lacks if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
	rep := ergo.report({"m": {"k1": {"x": 1}}}, policy, {"keys": ["k1", "k2"]})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["k1", false], ["k2", true]]
}

test_the_largest_position_a_float_holds_exactly_is_well_written if {
	rep := ergo.report(
		{"things": [{"items": [1]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {
			"c": "items[9007199254740991] does not exist",
			"d": "item 9007199254740991 of items does not exist",
		}}}},
		{},
	)
	rep.compliant == true
}

test_an_identified_by_with_an_index_that_cannot_be_a_key_is_written_wrong if {
	rep := ergo.report({"things": [{"items": [1]}]}, filter_policy({"b": {"from": "things", "identified_by": "items[99999999999999999999]"}}), {})
	rows_for(rep, "s", "$well_formed")[0].passed == false
	rep.compliant == false
}

test_a_problem_inside_a_sentence_is_named_by_its_check_and_the_check_prints_as_written if {
	rep := ergo.report(
		{"things": [{"items": [1]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {
			"k": `count of items whose x is one of 1, "a" and y is one of true, 2 is 0`,
			"e": {"for": `every items whose x is one of 1, "a" as i`, "assert": "i.y exists"},
		}}}},
		{},
	)
	problem_inputs(rep) == [
		{"name": "checks.e", "value": ["for: values of mixed types"], "locations": []},
		{"name": "checks.k", "value": ["values of mixed types"], "locations": []},
	]
	rep.requirements.s.checks.k.expression == "count of items whose x is one of 1, \"a\" and y is one of true, 2 is 0"
	rep.requirements.s.checks.e.expression == "for every items whose x is one of 1, \"a\" as i: i.y exists"
}

test_a_range_with_equal_bounds_is_well_written if {
	verdict({"n": 1}, "n is between 1 and 1") == true
}

ordering_doc := {"id": 1, "a": {"name": "ann"}, "b": {"owner": "bob"}, "xs": [2], "ys": [1, 9], "f": false, "t": true, "n": 1, "m": 2, "s": "a", "z": "b"}

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

test_a_filter_ordering_objects_or_strings_cannot_rule_subjects_out if {
	every condition in [".a is less than b", "z is more than s"] {
		rep := report({"items": [ordering_doc]}, {"s": {
			"from": concat(" whose ", ["items", condition]),
			"identified_by": "id",
			"min_subjects": 0,
			"checks": {"c": "n is 999"},
		}})
		rep.requirements.s.status == "not_met"
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["unusable"]
	}
}

one_item := {"items": [{"id": 1}]}

test_requirements_written_as_a_number_are_not_compliant if {
	report(one_item, 5).compliant == false
}

test_a_requirement_that_is_not_an_object_is_not_compliant if {
	report(one_item, {"s": 5}).compliant == false
}

test_checks_that_are_not_an_object_are_not_compliant if {
	report(one_item, {"s": {"from": "items", "checks": 5}}).compliant == false
}

test_an_input_that_is_a_string_without_from_is_not_compliant if {
	report("x", {"s": {"checks": {"c": "id exists"}}}).compliant == false
}

test_an_input_that_is_a_list_without_from_is_not_compliant if {
	rep := ergo.report([{"id": 1}], {"ergo_spec": "v0.3-dev", "subjects": {"s": {}}, "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}}, {})
	rep.compliant == false
	[r.cause | some r in rep.results; r.check == "$min_subjects"] == ["unusable"]
}

json_only_req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is 1"}}}

row_verdicts(rep) := [[r.check, r.passed, r.cause] | some r in rep.results]

test_a_set_anywhere_in_the_input_fails_every_check_as_unusable_so_a_port_can_check_the_input_once if {
	rep := report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, json_only_req)
	row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", false, "unusable"], ["$unique_ids", true, "satisfied"], ["c", false, "unusable"]]
	rep.requirements.s.status == "not_met"
}

test_a_key_that_is_not_a_string_in_the_input_fails_the_check_even_when_a_number_step_reaches_it if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "item 2 of x is \"a\""}}}
	rows_for(report({"items": [{"id": "a", "x": {1: "a"}}]}, req), "s", "c")[0].cause == "unusable"
}

test_a_set_in_the_input_takes_every_subject_out_of_scope_as_unusable if {
	req := {"s": object.union(json_only_req.s, {"from": "items whose id exists"})}
	rows_for(report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, req), "s", "$applies")[0].cause == "unusable"
}

test_a_set_in_the_input_fails_a_requirement_that_has_no_subjects if {
	req := {"s": object.union(json_only_req.s, {"min_subjects": 0})}
	report({"items": [], "tags": {"prod"}}, req).requirements.s.status == "not_met"
}

test_a_set_in_the_params_fails_every_check_as_unusable if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is one of $params.allowed"}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": {"MIT"}}), "s", "c")[0].cause == "unusable"
}

test_a_list_in_the_params_is_read_as_usual if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is one of $params.allowed"}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": ["MIT"]}), "s", "c")[0].passed == true
}

test_min_subjects_says_what_the_input_and_params_hold_that_json_cannot if {
	rep := ergo.report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}, "k": {1: "a"}}, lifted(json_only_req), {"allowed": {"MIT"}})
	rows_for(rep, "s", "$min_subjects")[0].inputs == [
		{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]},
		{"name": "$input", "value": ["holds a key that isn't a string", "holds a set"], "locations": []},
		{"name": "$params", "value": ["holds a set"], "locations": []},
	]
}

test_params_that_are_not_an_object_fail_every_requirement_even_one_that_reads_no_params_since_they_can_only_be_a_mistake if {
	every params in ["x", 1, true, [], ["a"]] {
		rep := ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), params)
		row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", false, "unusable"], ["$unique_ids", true, "satisfied"], ["c", false, "unusable"]]
		rows_for(rep, "s", "$min_subjects")[0].inputs == [{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]}, {"name": "$params", "value": ["not an object"], "locations": []}]
		rep.compliant == false
	}
}

test_null_params_are_no_params_and_fail_nothing_a_policy_does_not_read if {
	every params in [null, {}] {
		rep := ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), params)
		row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", true, "satisfied"], ["$unique_ids", true, "satisfied"], ["c", true, "satisfied"]]
	}
}

test_a_whole_params_read_with_null_params_fails_as_null_and_with_an_object_reads_it if {
	check := "$params exists"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "null", [{"name": "$params", "value": null, "locations": ["$params:"]}]]] with data.params as null
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params", "value": {}, "locations": ["$params:"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params", "value": "x", "locations": ["$params:"]}]]] with data.params as "x"
}

test_min_subjects_lists_only_the_count_when_the_input_and_params_are_json if {
	rows_for(ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), {"allowed": ["MIT"]}), "s", "$min_subjects")[0].inputs == [{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]}]
}

test_a_requirement_name_that_is_not_a_string_fails_the_requirement_and_the_policy if {
	every policy in [{1: json_only_req.s}, [json_only_req.s]] {
		rep := report({"items": [{"id": "a", "x": 1}]}, policy)
		rep.compliant == false
		some name, r in rep.requirements
		r.status == "not_met"
		some row in rep.results
		[row.requirement, row.check, row.passed] == [name, "$well_formed", false]
		row.inputs[0] == {"name": "requirement name", "value": ["not a string"], "locations": []}
	}
}

test_a_policy_written_as_a_set_is_not_compliant if {
	report({"items": [{"id": "a", "x": 1}]}, {json_only_req.s}).compliant == false
}

absent_lookalike := {"ergo/absent": true}

lookalike_rows(doc, req) := [[r.check, r.subject.id, r.passed, r.cause, r.inputs] |
	some r in report(doc, req).results
	not startswith(r.check, "$")
]

lookalike_req(from, checks) := {"s": {"from": from, "identified_by": "id", "checks": checks}}

test_a_field_holding_an_object_like_ergos_absent_marker_is_there if {
	lookalike_rows({"items": [{"id": 1, "o": absent_lookalike}]}, lookalike_req("items", {
		"m": "o does not exist",
		"p": "o exists",
	})) == [
		["m", 1, false, "value", [{"name": "o", "value": absent_lookalike, "locations": ["/items/0/o"]}]],
		["p", 1, true, "satisfied", [{"name": "o", "value": absent_lookalike, "locations": ["/items/0/o"]}]],
	]
}

test_a_from_leading_to_an_object_like_ergos_absent_marker_finds_it if {
	rep := report({"items": absent_lookalike}, {"s": {"from": "items", "checks": {"p": "\"ergo/absent\" exists"}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied"]]
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "p")] == [[absent_lookalike, true, "satisfied"]]
}

test_ergos_absent_marker_is_something_only_an_input_that_fails_closed_can_hold if {
	req := lookalike_req("items", {"m": "o does not exist"})
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

prod_deployment := {"from": "deployments whose environment is \"prod\"", "identified_by": "id"}

subject_policy(subjects, reqs) := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": reqs}

approved_req(subject) := {"subject": subject, "checks": {"approved": "approved_by is a non-empty string"}}

tested_req(subject) := {"subject": subject, "checks": {"tested": "tested is true"}}

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
	rep.requirements.approved.checks["$applies"].expression == `environment is "prod"`
	rep.requirements.tested.subjects == {"total": 3, "matching": 2}
}

well_formed_problems(rep, name) := [i | some i in rows_for(rep, name, "$well_formed")[0].inputs; not i.name in {"count(checks)", "require"}]

test_a_requirement_without_a_subject_fails_well_formed_and_checks_nothing if {
	rep := ergo.report(deployments_doc, subject_policy({"deployment": prod_deployment}, {"s": object.remove(approved_req("deployment"), ["subject"])}), {})
	rep.requirements.s.status == "not_met"
	well_formed_problems(rep, "s") == [{"name": "subject", "value": ["missing"], "locations": []}]
	stopped(rep)
}

test_a_subject_that_is_not_in_subjects_fails_well_formed_and_checks_nothing if {
	every policy in [
		subject_policy({"deployment": prod_deployment}, {"s": approved_req("deploymnt")}),
		subject_policy({}, {"s": approved_req("deployment")}),
		{"ergo_spec": "v0.3-dev", "requirements": {"s": approved_req("deployment")}},
	] {
		rep := ergo.report(deployments_doc, policy, {})
		rep.requirements.s.status == "not_met"
		well_formed_problems(rep, "s") == [{"name": "subject", "value": ["not in subjects"], "locations": []}]
		stopped(rep)
	}
}

test_subjects_that_are_not_an_object_fail_every_requirement_that_names_one if {
	every subjects in [null, "deployment", ["deployment"], 1] {
		rep := ergo.report(deployments_doc, subject_policy(subjects, {"s": approved_req("deployment")}), {})
		rep.requirements.s.status == "not_met"
		well_formed_problems(rep, "s") == [{"name": "subjects", "value": ["not an object"], "locations": []}]
	}
}

test_a_subject_that_is_not_an_object_fails_every_requirement_that_names_it if {
	every def in ["deployments", [], 1] {
		rep := ergo.report(deployments_doc, subject_policy({"deployment": def}, {"a": approved_req("deployment"), "t": tested_req("deployment")}), {})
		[rep.requirements.a.status, rep.requirements.t.status] == ["not_met", "not_met"]
		well_formed_problems(rep, "a") == [{"name": "subjects.deployment", "value": ["not an object"], "locations": []}]
		well_formed_problems(rep, "t") == [{"name": "subjects.deployment", "value": ["not an object"], "locations": []}]
	}
}

test_a_badly_written_subject_fails_every_requirement_that_names_it if {
	broken := object.union(prod_deployment, {"from": 5, "identified_by": [true], "applies_to": {"is_prod": {"op": "equls", "path": ["environment"]}}, "zz": 1, "description": 5})
	rep := ergo.report(deployments_doc, subject_policy({"deployment": broken}, {"a": approved_req("deployment"), "t": tested_req("deployment")}), {})
	rep.compliant == false
	every name in ["a", "t"] {
		rep.requirements[name].status == "not_met"
		well_formed_problems(rep, name) == [
			{"name": "subjects.deployment.applies_to", "value": ["unknown field"], "locations": []},
			{"name": "subjects.deployment.description", "value": ["not a string"], "locations": []},
			{"name": "subjects.deployment.from", "value": ["not a string"], "locations": []},
			{"name": "subjects.deployment.identified_by", "value": ["not a string"], "locations": []},
			{"name": "subjects.deployment.zz", "value": ["unknown field"], "locations": []},
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
	without_subjects(rep) == without_subjects(ergo.report(deployments_doc, subject_policy({"deployment": prod_deployment}, {"a": approved_req("deployment")}), {}))
}

without_subjects(rep) := object.remove(rep, ["subjects"])

sbom_doc := {"components": [
	{"name": "a", "lock_release": "1.0", "sbom_release": "1.0", "exempt": false},
	{"name": "b", "lock_release": "2.0", "sbom_release": "2.1", "exempt": true},
	{"name": "c", "sbom_release": "3.0", "exempt": false},
]}

sbom_subjects := {
	"SBOM package": {"from": "components", "identified_by": "name"},
	"locked SBOM package": {"from": "\"SBOM package\" whose lock_release exists"},
	"non-exempt SBOM package": {"from": "\"SBOM package\" whose exempt is false"},
}

sbom_reqs := {
	"versions": {"subject": "locked SBOM package", "checks": {"matches_lock": "sbom_release equals lock_release"}},
	"named": {"subject": "non-exempt SBOM package", "checks": {"named": "name is a non-empty string"}},
}

test_a_requirement_can_name_the_subject_others_build_on if {
	rep := ergo.report(sbom_doc, subject_policy(sbom_subjects, {"all": {"subject": "SBOM package", "checks": {"named": "name is a non-empty string"}}}), {})
	rep.compliant == true
	rep.requirements.all.subjects == {"total": 3, "matching": 3}
}

built_problems(subjects) := well_formed_problems(ergo.report(sbom_doc, subject_policy(subjects, {"v": sbom_reqs.versions}), {}), "v")

test_problems_with_the_subject_built_on_are_named_after_it if {
	base := {"from": 5}
	built_problems(object.union(sbom_subjects, {"SBOM package": base})) == [{"name": "subjects.\"SBOM package\".from", "value": ["not a string"], "locations": []}]
}

test_a_subject_no_requirement_names_does_not_change_how_numbers_are_written if {
	policy := subject_policy({"i": {"from": "items", "identified_by": "id"}}, {"r": {"subject": "i", "checks": {"c": "n is 1.50"}}})
	with_unused := object.union(policy, {"subjects": {"unused": {"from": [{"where": {"k": {1}}}]}}})
	json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, with_unused, {})) == json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, policy, {}))
}

two_checks_req := {"subject": "s", "require": "some", "checks": {
	"a": ".a exists",
	"b": "b exists",
}}

passing_row := {"passed": true, "cause": "satisfied"}

evaluation_with(rows, matching, scope_readable) := {
	"well_formed": passing_row,
	"unique_ids": [passing_row],
	"min_subjects": [passing_row],
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

causes_policy(check) := {"ergo_spec": "v0.3-dev", "subjects": {"deployment": {"from": "deployments whose environment is \"prod\"", "identified_by": "id"}}, "requirements": {"r": {"subject": "deployment", "checks": {"approved": check}}}}

causes_of(deployments, check) := ergo.report({"deployments": deployments}, causes_policy(check), {}).requirements.r.causes

approved_check := "approved_by is a non-empty string"

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

test_causes_count_the_rows_violations_returns if {
	rep := ergo.report(causes_doc, causes_policy(approved_check), {})
	vs := ergo.violations(rep)
	rep.requirements.r.causes == [{"cause": c, "rows": n} |
		some c in ["not_an_object", "ambiguous", "unusable", "absent", "null", "value"]
		n := count([v | some v in vs; v.cause == c])
		n > 0
	]
	sum([e.rows | some e in rep.requirements.r.causes]) == count(vs)
}

derived_row(subj, check) := [r.passed, r.cause, r.inputs] if {
	r := rows_for(ergo.report({"items": [object.union({"id": 1}, subj)]}, lifted({"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}}), {}), "s", "c")[0]
}

derived_verdict(subj, check) := array.slice(derived_row(subj, check), 0, 2)

test_within_needs_two_numbers if {
	check := ".a equals b within 1"
	derived_verdict({"a": 1, "b": 1.5}, check) == [true, "satisfied"]
	derived_verdict({"a": 1, "b": 2.5}, check) == [false, "value"]
	derived_verdict({"a": "1", "b": "1"}, check) == [false, "unusable"]
}

test_a_derived_check_works_as_a_filter if {
	subjects := {"pr": {"from": "prs whose count of files is more than 10", "identified_by": "n"}}
	reqs := {"r": {"subject": "pr", "checks": {"reviewed": "reviewer exists"}}}
	rep := ergo.report({"prs": [{"n": 1, "files": array.concat(numbers.range(1, 11), []), "reviewer": "ann"}, {"n": 2, "files": [1]}, {"n": 3}]}, subject_policy(subjects, reqs), {})
	[[r.subject.id, r.passed, r.cause] | some r in rep.results; r.check == "$applies"] == [[1, true, "satisfied"], [2, false, "value"], [3, false, "absent"]]
	rep.requirements.r.status == "not_met"
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
	count(data.spec.sentence_corpus) == 315
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
	_read(`.count is 1`).assertions[0].path == {"steps": ["count"], "dot": true}
	_read(`"empty" is 1`).assertions[0].path == {"steps": ["empty"]}
	_read(`x is ."$schema"`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["$schema"], "dot": true}]}
	_read(`.x is 1`).assertions[0].path == {"steps": ["x"], "dot": true}
	_read(`x equals .total`).assertions[0].phrase.terms == [{"steps": ["total"], "dot": true}]
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
	_read(`x named by every is 1`) == {"problems": ["every can't be an alias"]}
	_read(`x[params] is 1`) == {"problems": ["params can't be an alias"]}
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
	ergo._for_line(`every x as every`) == {"problems": ["every can't be an alias"]}
	ergo._for_line(`every x as params`) == {"problems": ["params can't be an alias"]}
	ergo._for_line(`every x as a, every y as b, every z as c`) == {"problems": ["a for line holds two items at most"]}
	ergo._for_line(`some x, if any, as y`) == {"problems": ["if any can't go with some"]}
	ergo._from_line(`count whose x is 1`) == {"problems": ["count is a word of the grammar: write .count"]}
	ergo._from_line(`x is 1`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`$input named by each of "T"`) == {"problems": ["doesn't parse"]}
}

_sentence_policy(checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"thing": {"from": "things", "identified_by": "id"}},
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
		[`x is "a"`, "x is \"a\""],
		[`q is null`, "q is null"],
		[`n equals m`, "n equals m"],
		[`n is 3.05 within 0.1`, "n equals 3.05 within 0.1"],
		[`n equals m within 0`, "n equals m within 0"],
		[`x is not "a"`, "x does not equal \"a\""],
		[`n does not equal m`, "n does not equal m"],
		[`x is one of "a", 5`, "x is one of \"a\", 5"],
		[`x is in $params.allowed`, "x is one of $params.allowed"],
		[`x is in $params.groups[0].names`, "x is one of $params.groups[0].names"],
		[`x is in first of $params.groups`, "x is one of item 1 of $params.groups"],
		[`x exists`, "x exists"],
		[`x does not exist`, "x does not exist"],
		[`x is a non-empty string`, "x is a non-empty string"],
		[`l contains "a"`, "l contains \"a\""],
		[`l contains $params.key`, "l contains $params.key"],
		[`l does not contain "b"`, "l does not contain \"b\""],
		[`l contains all of "a", "b"`, "l contains all of \"a\", \"b\""],
		[`l contains none of $params.allowed`, "l contains none of $params.allowed"],
		[`x matches '^\w$'`, "x matches \"^\\\\w$\""],
		[`x does not match $params.pats`, "x does not match $params.pats"],
		[`n is at least 3`, "n is at least 3"],
		[`n is at most m`, "n is at most m"],
		[`n is more than 2`, "n is more than 2"],
		[`n is less than 2`, "n is less than 2"],
		[`n is between 1 and 3`, "n is between 1 and 3"],
		[`t is before u`, "t is before u"],
		[`t is after u`, "t is after u"],
		[`t is on or after u`, "t is on or after u"],
		[`t is on or before u`, "t is on or before u"],
		[`k named by $params.key is 1`, "k named by $params.key is 1"],
		[`k[$params.key] is 1`, "k named by $params.key is 1"],
		[`item 2 of l is "b"`, "item 2 of l is \"b\""],
		[`first of l is "a"`, "item 1 of l is \"a\""],
		[`l[1] is "b"`, "item 2 of l is \"b\""],
		[`$params.key is "a"`, "$params.key is \"a\""],
		[`$input.things[0].id is "t1"`, "$input.things[0].id is \"t1\""],
		[`"$schema" exists`, "\"$schema\" exists"],
		[`k."a" is 1`, "k.a is 1"],
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
	r.requirements.s.checks.b == {"description": "In the list", "meta": {"id": "B-1"}, "expression": "x is in $params.allowed", "$refs": [{"name": "$params.allowed", "value": ["a"], "locations": ["$params:/allowed"]}]}
	r.compliant
}

test_a_sentence_written_wrong_stops_at_well_formed_and_lists_its_problems if {
	r := ergo.report({"things": [{"id": "t1", "x": "a"}]}, _sentence_policy({"c": `x is "a`}), {})
	[[row.check, row.passed, row.cause, row.inputs] | some row in r.results] == [["$well_formed", false, "value", [{"name": "count(checks)", "value": 1, "locations": []}, {"name": "require", "value": "every", "locations": []}, {"name": "checks.c", "value": ["unclosed quote at column 6"], "locations": []}]]]
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
		[`every xs is y plus 1`, "count of, sum of and plus after every or some aren't supported yet"],
		[`t is before y plus 1`, `"is before" can't take a count of, a sum of or a plus`],
		[`count of xs whose sum of ys is 1 is 2`, "a sum of or a plus in the whose of a count of or a sum of isn't supported yet"],
		[`count of xs whose n is count of ys plus 1 is 2`, "a sum of or a plus in the whose of a count of or a sum of isn't supported yet"],
		[`last of xs is 1`, "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""],
	] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
	_sentence_problems({"assert": []}) == ["empty assert"]
	_sentence_problems({"assert": ["x exists", 1]}) == ["invalid assert"]
	_sentence_problems({"assert": ["x exists", "y is \"a"]}) == ["line 2: unclosed quote at column 6"]
	_sentence_problems({"assert": ["x exists", "last of ys is 1"]}) == ["line 2: last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""]
}

test_a_check_written_as_a_string_is_read_as_a_sentence if {
	rendered({}, "present") == "present"
	stopped(solo({}, "present"))
	_sentence_problems("present") == [`nothing after the path at column 8: expected a phrase, like "is" or "exists"`]
}

test_is_not_null_is_written_wrong_because_it_could_only_fail if {
	_sentence_problems(`x is not null`) == [`"is not null" is written "exists"`]
	_sentence_problems(`x does not equal null`) == [`"is not null" is written "exists"`]
}

test_a_bare_params_or_input_after_named_by_or_in_brackets_does_not_parse_even_with_an_unknown_name if {
	every text in [`x named by $params is 1`, `x named by $input is 1`, `x[$params] is 1`, `x[$input] is 1`, `x named by $params is $foo`] {
		_sentence_problems(text) == ["doesn't parse"]
	}
}

test_a_bare_params_after_named_by_does_not_hide_a_within_with_no_number_or_two_quantifiers if {
	_sentence_problems(`x named by $params is 1 within`) == [`"within" needs a number after it`]
	_sentence_problems(`every a every b named by $params exists`) == ["two quantifiers in one sentence: put them on a for line"]
}

test_a_comparison_of_a_path_with_itself_is_listed_next_to_an_unknown_name_and_next_to_no_other_problem if {
	_sentence_problems(`x is x and y is $foo`) == ["unknown name $foo", "x is compared with itself"]
	_sentence_problems(`$foo is $foo`) == ["$foo is compared with itself", "unknown name $foo"]
	_sentence_problems(`x is x and x is not null and y is $foo`) == [`"is not null" is written "exists"`, "unknown name $foo"]
}

test_a_path_compared_with_itself_is_written_wrong_because_it_could_only_pass_or_only_fail if {
	every text in [
		`x equals x`, `x does not equal x`, `x is x within 1`, `x is at least x`, `x is less than x`,
		`x is after x`, `x is on or before x`, `x starts with x`, `x ends with x`,
	] {
		_sentence_problems(text) == ["x is compared with itself"]
	}
	_sentence_problems(`$input.x.y equals $input.x.y`) == ["$input.x.y is compared with itself"]
	_sentence_problems({"for": "every xs as entry", "assert": "entry.y equals entry.y"}) == ["entry.y is compared with itself"]
}

test_a_whose_that_compares_a_field_with_itself_says_the_bare_name_is_the_items if {
	message := "type is compared with itself, because in a whose it's read from the item: to read the subject's type, compare under assert"
	_sentence_problems(`some conditions.status whose type equals type is "OK"`) == [message]
	_sentence_problems({"for": "some conditions whose type equals type as condition", "assert": `condition.status is "OK"`}) == [concat("", ["for: ", message])]
}

test_every_or_some_ending_where_it_compares_says_the_bare_name_is_the_items if {
	_sentence_problems(`every conditions.type equals type`) == ["type is compared with itself, because after every or some it's read from the item: to read the subject's type, put the list on the for line and compare under assert"]
	_sentence_problems(`some pull_requests.commits[0].author is after author`) == ["author is compared with itself, because after every or some it's read from the item: to read the subject's author, put the list on the for line and compare under assert"]
	_sentence_problems(`every xs.ys.zs equals ys.zs`) == ["ys.zs is compared with itself, because after every or some it's read from the item: to read the subject's ys.zs, put the list on the for line and compare under assert"]
	_sentence_problems(`every $input.xs.y equals y`) == ["y is compared with itself, because after every or some it's read from the item: to read the subject's y, put the list on the for line and compare under assert"]
}

_alias_things := [{
	"id": "t1", "approver": "grace",
	"approvals": [{"approver": "grace", "timestamp": "2026-10-20T12:00:00Z"}],
	"commits": [{"author": "grace", "approver": "ada", "timestamp": "2026-10-20T10:00:00Z"}],
	"environments": [{"name": "prod"}],
	"deployments": [{"environment": "prod", "env": "prod", "ok": true}],
}]

_alias_causes(checks) := {r.check: r.cause | some r in ergo.report({"things": _alias_things}, _sentence_policy(checks), {}).results; not startswith(r.check, "$")}

test_an_alias_on_the_right_after_every_reads_the_alias_not_the_items_field if {
	_alias_causes({
		"alias": {"for": "some approvals.approver as approver", "assert": "every commits.author does not equal approver"},
		"path": {"for": "some approvals as approval", "assert": "every commits.timestamp is before approval.timestamp"},
	}) == {"alias": "value", "path": "satisfied"}
}

test_a_dot_reads_the_field_where_an_alias_has_the_same_name if {
	_alias_causes({
		"item": {"for": "some approvals.approver as approver", "assert": "every commits.author does not equal .approver"},
		"subject": {"for": "some approvals.approver as approver", "assert": ".approver equals approver"},
	}) == {"item": "satisfied", "subject": "satisfied"}
}

test_the_left_of_a_whose_is_the_items_field_and_its_right_can_read_an_alias if {
	checks := {
		"left": {"for": `every environments as env, some deployments whose env is "prod" as deployment`, "assert": "deployment.ok is true"},
		"right": {"for": "every environments as env, some deployments whose environment equals env.name as deployment", "assert": "deployment.ok is true"},
	}
	_alias_causes(checks) == {"left": "satisfied", "right": "satisfied"}
	r := ergo.report({"things": _alias_things}, _sentence_policy(checks), {})
	r.requirements.s.checks.left.expression == `for every environments as env, some deployments whose env is "prod" as deployment: deployment.ok is true`
}

test_a_path_is_compared_with_itself_only_when_both_sides_read_the_same_thing if {
	not _sentence_problems({"for": "every zs as y", "assert": "every xs.y equals y"})
	not _sentence_problems({"for": "every environments as env, some deployments whose env equals env as deployment", "assert": "deployment.ok is true"})
	_sentence_problems({"for": "every zs as y", "assert": "every xs.y equals .y"}) == ["y is compared with itself, because after every or some it's read from the item: to read the subject's y, put the list on the for line and compare under assert"]
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

test_requirements_and_checks_that_are_not_objects_are_left_to_the_other_rules if {
	ergo._s_requirements(null, {}) == null
	ergo._s_requirements({"r": 1}, {}) == {"r": 1}
	ergo._s_requirements({"r": {"checks": []}}, {}) == {"r": {"checks": []}}
	ergo._s_requirements({"r": {"checks": {"d": 1}}}, {}) == {"r": {"checks": {"d": 1}}}
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

test_no_data_document_can_make_a_check_read_as_a_sentence if {
	json_policy := lifted({"s": {"from": ["items", {"each_as": "it"}], "id": ["id"], "checks": {
		"c": {"op": "all_of", "checks": [{"op": "present", "path": ["id"]}], "assertions": ["id exists"]},
		"d": {"op": "present", "path": ["id"], "$sentence": []},
	}}})
	plain := ergo.report({"items": [{"id": 1}]}, json_policy, {})
	set_by_data := ergo.report({"items": [{"id": 1}]}, json_policy, {}) with data.ergo_sentence_here as true
	set_by_data == plain
	[r.passed | some r in plain.results; r.check == "$well_formed"] == [false]
}

test_a_check_is_read_as_a_sentence_only_where_the_policy_wrote_one if {
	not ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"}, false)
	ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"}, true)
	ergo._s_sentences({"r": {"checks": ["x exists"]}, "q": 1}, {"r": {"checks": ["x exists"]}, "q": 1}) == set()
	ergo._s_sentences(null, null) == set()
	ergo._s_written_here({}, "applies_to", "f") == false
}

test_a_sentence_that_reads_into_no_check_is_written_wrong_rather_than_run if {
	ergo._s_or_unrunnable(set()) == {"can't be run"}
	ergo._s_or_unrunnable({"x"}) == {"x"}
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

test_is_not_in_a_list_read_from_the_params_fails_when_the_params_dont_hold_a_list if {
	doc := {"things": [{"id": "a", "x": "dev"}]}
	checks := {"e": "x is not in $params.empty", "m": "x is not in $params.none", "t": "x is not in $params.text"}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {"empty": [], "text": "prod"})] == [["e", "satisfied"], ["m", "absent"], ["t", "unusable"]]
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

test_starts_with_only_ever_compares_two_strings_even_through_leaf_passed if {
	not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "starts_with", "right": ["m"]}, {"n": 15, "m": 1})
	not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "ends_with", "right": ["m"]}, {"n": 15, "m": 1})
}

test_a_written_value_after_starts_with_that_isnt_text_is_written_wrong_because_it_could_only_fail if {
	every pair in [[`x starts with null`, `"starts with" takes text`], [`x ends with 1`, `"ends with" takes text`], [`x starts with true`, `"starts with" takes text`]] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
}

test_assertions_joined_with_and_or_listed_under_assert_give_one_row_that_names_the_ones_that_failed if {
	doc := {"prs": [{"id": "late", "username": "bob", "author": "ann", "ts": 1, "last_commit": 2}, {"id": "gone", "username": "ann", "author": "ann", "last_commit": 2}]}
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"s": {"subject": "pr", "checks": {
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
	[[row.cause, row.failed_assertions, row.inputs] | some row in r.results; row.check == "c"] == [["satisfied", [], [{"name": "x", "value": 1, "locations": ["/things/0/x"]}, {"name": "y", "value": 2, "locations": ["/things/0/y"]}]]]
}

test_an_assertion_whose_param_cant_be_read_is_the_only_one_listed_as_unusable if {
	r := ergo.report({"things": [{"id": "a", "x": "p", "y": 1}]}, _sentence_policy({"c": "x is in $params.l and y exists and y is 2"}), {"l": "text"})
	[[row.cause, row.failed_assertions] | some row in r.results; row.check == "c"] == [["unusable", [{"assertion": "x is in $params.l", "cause": "unusable"}, {"assertion": "y is 2", "cause": "value"}]]]
}

test_every_assertion_is_unusable_when_the_input_holds_something_json_cant if {
	r := ergo.report({"things": [{"id": "a", "x": 1, "s": {1}}]}, _sentence_policy({"c": "x is 1 and x exists"}), {})
	[[row.cause, row.failed_assertions] | some row in r.results; row.check == "c"] == [["unusable", [{"assertion": "x is 1", "cause": "unusable"}, {"assertion": "x exists", "cause": "unusable"}]]]
}

test_an_any_of_of_sentences_passes_when_every_line_of_one_option_passes if {
	doc := {"components": [
		{"name": "click", "licenses": [{"license": {"id": "BSD-3-Clause"}}]},
		{"name": "prometheus-client"},
		{"name": "leftpad", "licenses": [{"license": {"id": "WTFPL"}}]},
	]}
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"component": {"from": "components", "identified_by": "name"}}, "requirements": {"s": {"subject": "component", "checks": {"c": {"description": "The licence is allowed", "meta": {"k": 1}, "any_of": {
		"declared": "some licenses.license.id is in $params.allowed",
		"known": ["licenses does not exist", "$params.known named by name is in $params.allowed"],
	}}}}}}
	r := ergo.report(doc, policy, {"allowed": ["BSD-3-Clause", "Apache-2.0"], "known": {"prometheus-client": "Apache-2.0"}})
	object.filter(r.requirements.s.checks.c, {"description", "meta", "expression"}) == {"description": "The licence is allowed", "meta": {"k": 1}, "expression": "one of: declared(some licenses.license.id is in $params.allowed) | known(licenses does not exist and $params.known named by name is in $params.allowed)"}
	[[row.subject.id, row.passed, row.cause] | some row in r.results; row.check == "c"] == [["click", true, "satisfied"], ["prometheus-client", true, "satisfied"], ["leftpad", false, "absent"]]
}

test_an_any_of_of_sentences_gives_the_same_causes_as_the_any_of_it_reads_into if {
	sentences := {"any_of": {"b": "z is 1", "a": ["x exists", "x.y is 1"]}}
	old := {"any_of": {"b": "z is 1", "a": ["x exists", "x.y is 1"]}}
	doc := {"things": [{"id": "1", "z": 1}, {"id": "2", "x": {"y": 1}}, {"id": "3", "z": 2}, {"id": "4", "x": {}, "z": 2}, {"id": "5", "x": 3, "z": 2}, {"id": "6", "x": {"y": 2}}, {"id": "7", "x": null, "z": null}]}
	r := ergo.report(doc, _sentence_policy({"new": sentences, "old": old}), {})
	causes := {c: [[row.subject.id, row.cause, row.inputs] | some row in r.results; row.check == c] | some c in ["new", "old"]}
	causes.new == causes.old
	[x[1] | some x in causes.new] == ["satisfied", "satisfied", "value", "absent", "unusable", "absent", "null"]
}

test_an_option_of_an_any_of_can_hold_every_some_and_counts if {
	check := {"any_of": {"none": "count of xs is 0", "all_ok": "every xs.ok is true", "one": "some xs.n is 3"}}
	r := ergo.report({"things": [{"id": "a", "xs": []}, {"id": "b", "xs": [{"ok": true}]}, {"id": "c", "xs": [{"ok": false, "n": 3}]}, {"id": "d", "xs": [{"ok": false, "n": 2}]}, {"id": "e"}]}, _sentence_policy({"c": check}), {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "satisfied"], ["d", "value"], ["e", "absent"]]
	r.requirements.s.checks.c.expression == "one of: all_ok(every xs.ok is true) | none(count of xs is 0) | one(some xs.n is 3)"
}

test_an_any_of_row_reads_every_input_once_and_lists_no_failed_lines if {
	r := ergo.report({"things": [{"id": "a", "x": 2, "y": 1}]}, _sentence_policy({"c": {"any_of": {"a": "x is 1 and y is 1", "b": ["x is 3", "y exists"]}}}), {})
	[row | some row in r.results; row.check == "c"] == [{"requirement": "s", "subject": {"type": "thing", "id": "a"}, "check": "c", "passed": false, "cause": "value", "inputs": [{"name": "x", "value": 2, "locations": ["/things/0/x"]}, {"name": "y", "value": 1, "locations": ["/things/0/y"]}]}]
}

test_an_any_of_fails_as_unusable_when_a_param_is_the_wrong_type_even_if_another_option_passes if {
	r := ergo.report({"things": [{"id": "a", "x": 1}]}, _sentence_policy({"c": {"any_of": {"a": "x is 1", "b": "x is in $params.l"}}}), {"l": "text"})
	[[row.passed, row.cause] | some row in r.results; row.check == "c"] == [[false, "unusable"]]
}

test_an_any_of_of_sentences_fails_as_unusable_when_the_input_holds_something_json_cant if {
	r := ergo.report({"things": [{"id": "a", "x": 1, "s": {1}}]}, _sentence_policy({"c": {"any_of": {"a": "x is 1"}}}), {})
	[[row.passed, row.cause] | some row in r.results; row.check == "c"] == [[false, "unusable"]]
}

test_an_any_of_of_sentences_is_written_wrong_when_its_shape_or_a_line_is if {
	every pair in [
		[{"any_of": "x is 1"}, ["invalid any_of"], "<invalid any_of>"],
		[{"any_of": {}}, ["empty any_of"], "one of: <empty options>"],
		[{"any_of": {"a": []}}, ["empty option a"], "one of: a(<empty option>)"],
		[{"any_of": {"a": 1, "b": "x is 1"}}, ["invalid option a"], "one of: a(<invalid option>) | b(x is 1)"],
		[{"any_of": {"a": ["x is 1", 2]}}, ["invalid option a"], "one of: a(<invalid option>)"],
		[{"any_of": {"a": "x is 1"}, "for": "every xs as x"}, ["unknown field for"], "one of: a(x is 1)"],
		[{"any_of": {"a": "x is", "b": ["x is 1", "x is"]}}, ["option a: doesn't parse", "option b: line 2: doesn't parse"], "one of: a(x is) | b(x is 1 and x is)"],
		[{"any_of": {"a": "x is 1"}, "assert": "x is 1"}, ["unknown field any_of"], "x is 1"],
	] {
		r := ergo.report({"things": [{"id": "t1", "x": 1}]}, _sentence_policy({"c": pair[0]}), {})
		_sentence_problems(pair[0]) == pair[1]
		r.requirements.s.checks.c.expression == pair[2]
		stopped(r)
	}
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

test_a_missing_param_only_fails_the_options_of_an_any_of_that_read_it if {
	rows := _sentence_rows({"c": {"any_of": {"a": "x is 1", "b": "x is in $params.l"}}}, {"things": [{"id": "t", "x": 1}, {"id": "u", "x": 2}]}, {})
	[[row[1], row[2]] | some row in rows] == [[true, "satisfied"], [false, "absent"]]
}

test_an_option_of_an_any_of_reads_a_part_by_its_alias if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"cov": "attestations.cov"}}}, "requirements": {"s": {"subject": "thing", "checks": {"c": {"any_of": {"high": "cov.pct is at least 80", "waived": "waived is true"}}}}}}
	r := ergo.report({"things": [{"id": "a", "attestations": {"cov": {"pct": 90}}}, {"id": "b", "waived": true, "attestations": {"cov": {"pct": 10}}}, {"id": "c", "waived": false, "attestations": {"cov": {"pct": 10}}}]}, policy, {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "value"]]
}

test_an_option_of_an_any_of_reads_a_parent_subject_by_its_name if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"pr": {"from": "prs", "identified_by": "id"}, "commit": {"from": "pr.commits", "identified_by": "sha"}}, "requirements": {"s": {"subject": "commit", "checks": {"c": {"any_of": {"signed": "signed is true", "bot": "pr.author is \"bot\""}}}}}}
	r := ergo.report({"prs": [{"id": "1", "author": "bot", "commits": [{"sha": "a", "signed": false}]}, {"id": "2", "author": "ann", "commits": [{"sha": "b", "signed": true}, {"sha": "c", "signed": false}]}]}, policy, {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "value"]]
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
		["a", "e", "unusable", [{"path": "x.y", "item": "x.y", "cause": "unusable", "value": 1, "locations": ["/things/0/x/y"]}]],
		["b", "e", "absent", [{"path": "x", "item": "x", "cause": "absent", "value": null, "locations": ["/things/1"]}]],
		["c", "e", "null", [{"path": "x.y", "item": "x.y", "cause": "null", "value": null, "locations": ["/things/2/x/y"]}]],
	]
}

test_a_walk_starts_where_its_path_starts_and_steps_past_a_position_without_walking_it if {
	doc := {"things": [{"id": "a", "m": [[1, 2], [3]]}]}
	rows := _walk_rows({"i": "every $input.things[0].m[0] is at least 1", "p": "every first of m is 1"}, doc, {})
	rows == [["a", "i", "satisfied", []], ["a", "p", "value", [{"path": "item 2 of m[0]", "item": "item 2 of m[0]", "cause": "value", "value": 2, "locations": ["/things/0/m/0/1"]}]]]
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
		[{"name": "n", "value": 1, "locations": ["/things/0/n"]}, {"name": "xs[].v", "value": [1, 2], "locations": ["/things/0/xs/0/v", "/things/0/xs/1/v"]}],
	]]
}

test_forms_a_walk_cant_take_yet_are_written_wrong if {
	_sentence_problems(`every xs whose last of ys is 1 is not empty`) == ["last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""]
	_sentence_problems(`every k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11.k12 is 1`) == ["every and some over more than ten steps aren't supported yet"]
}

test_a_walk_that_reads_no_list_stops_at_the_end_when_every_value_along_the_path_is_an_object if {
	doc := {"things": [{"id": "a", "x": {"y": {"z": 1}}}, {"id": "b", "xs": [1, 2]}]}
	_walk_rows({"e": "every x.y is 1"}, doc, {})[0] == ["a", "e", "unusable", [{"path": "x.y", "item": "x.y", "cause": "unusable", "value": {"z": 1}, "locations": ["/things/0/x/y"]}]]
	_walk_rows({"e": "every xs[5].y is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "item 6 of xs", "item": "item 6 of xs", "cause": "absent", "value": null, "locations": ["/things/1/xs"]}]]
	_walk_rows({"e": "every x.y.z.w is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "x", "item": "x", "cause": "absent", "value": null, "locations": ["/things/1"]}]]
}

test_an_item_a_whose_condition_cant_decide_is_undecided_even_when_another_condition_leaves_it_out if {
	doc := {"things": [{"id": "a", "xs": [{"kind": "b"}]}]}
	_walk_rows({"e": `every xs whose kind is "a" and state is "open" is not empty`}, doc, {}) == [["a", "e", "absent", [{"path": "xs[0].state", "item": "item 1 of xs", "cause": "absent", "value": null, "locations": ["/things/0/xs/0"]}]]]
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
	r := ergo.report({"things": ["text", null]}, {"ergo_spec": "v0.3-dev", "subjects": {"t": {"from": "things"}}, "requirements": {"s": {"subject": "t", "checks": {"c": "every xs is 1"}}}}, {})
	[row.cause | some row in r.results; row.check == "c"] == ["not_an_object", "not_an_object"]
}

test_a_walk_of_exactly_ten_steps_walks_its_last_list_and_eleven_is_written_wrong if {
	doc := {"things": [{"id": "a", "p0": [{"p1": {"p2": {"p3": {"p4": {"p5": {"p6": {"p7": {"p8": {"p9": [""]}}}}}}}}}]}]}
	_walk_rows({"c": "every p0.p1.p2.p3.p4.p5.p6.p7.p8.p9 is not empty"}, doc, {})[0][2] == "value"
	_sentence_problems("every p0.p1.p2.p3.p4.p5.p6.p7.p8.p9.p10 is not empty") == ["every and some over more than ten steps aren't supported yet"]
}

test_a_position_is_a_step_of_a_walk_so_ten_steps_with_one_read_and_eleven_are_written_wrong if {
	doc := {"things": [{"id": "a", "k1": [{"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": [true, false]}}}}}}}}]}, {"id": "b", "k1": [{"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": [false, true]}}}}}}}}]}]}
	[[r[0], r[2]] | some r in _walk_rows({"c": "every first of k1.k2.k3.k4.k5.k6.k7.k8.k9 is true"}, doc, {})] == [["a", "satisfied"], ["b", "value"]]
	[[r[0], r[2]] | some r in _walk_rows({"c": "every k1.k2.k3.k4.k5.k6.k7.k8.k9 is true"}, doc, {})] == [["a", "value"], ["b", "value"]]
	_sentence_problems("every first of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10 is true") == ["every and some over more than ten steps aren't supported yet"]
}

_ten := "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10"

_eleven := "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11"

_too_long := ["every and some over more than ten steps aren't supported yet"]

_for_too_long := "for: every and some over more than ten steps aren't supported yet"

test_a_count_of_or_sum_of_on_the_right_of_a_phrase_over_ten_steps_reads_and_gives_the_right_verdicts if {
	doc := {"things": [
		{"id": "a", "n": 2, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": [1, 1]}}}}}}}}}},
		{"id": "b", "n": 1, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": [1, 1]}}}}}}}}}},
	]}
	rows := _walk_rows({"c": concat("", ["n is count of ", _ten]), "d": concat("", ["n is at least sum of ", _ten])}, doc, {})
	[[r[0], r[1], r[2]] | some r in rows] == [["a", "c", "satisfied"], ["a", "d", "satisfied"], ["b", "c", "value"], ["b", "d", "value"]]
}

test_a_count_of_or_sum_of_over_more_than_ten_steps_is_written_wrong_on_the_right_of_a_phrase if {
	_sentence_problems(concat("", ["n is count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["n is at least sum of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["n is count of k1 plus count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["count of k1 is at least count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["count of k1 plus count of ", _eleven, " is 1"])) == _too_long
}

test_a_count_of_over_more_than_ten_steps_is_written_wrong_inside_a_whose_a_for_line_and_an_any_of if {
	_sentence_problems(concat("", ["every xs whose n is count of ", _eleven, " is not empty"])) == _too_long
	_sentence_problems(concat("", ["some xs whose n is count of ", _eleven, " is not empty"])) == _too_long
	_sentence_problems(concat("", ["count of xs whose n is count of ", _eleven, " is 1"])) == _too_long
	_sentence_problems({"for": "every xs as x", "assert": concat("", ["n is count of ", _eleven])}) == _too_long
	_sentence_problems({"for": "every xs as x", "assert": [concat("", ["x.n is at least sum of ", _eleven])]}) == _too_long
	_sentence_problems({"any_of": {"a": concat("", ["n is count of ", _eleven]), "b": "n is 1"}}) == ["option a: every and some over more than ten steps aren't supported yet"]
}

_reads(check) if {
	some row in ergo.report({"things": []}, _sentence_policy({"c": check}), {}).results
	row.check == "$well_formed"
	row.passed
}

test_a_for_alias_is_a_step_of_a_count_of_on_the_right_so_a_check_that_read_before_is_written_wrong if {
	doc := {"things": [{"id": "a", "xs": [{"n": 1, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": [1]}}}}}}}}}]}]}
	[[r[0], r[2]] | some r in _walk_rows({"c": {"for": "every xs as x", "assert": "x.n is count of x.k1.k2.k3.k4.k5.k6.k7.k8.k9"}}, doc, {})] == [["a", "satisfied"]]
	_sentence_problems({"for": "every xs as x", "assert": concat("", ["x.n is count of x.", _ten])}) == _too_long
}

test_a_position_and_a_sum_after_plus_on_the_right_and_a_count_in_a_picked_items_whose_are_held_to_ten_steps if {
	_reads("n is count of first of k1.k2.k3.k4.k5.k6.k7.k8.k9")
	_sentence_problems(concat("", ["n is count of first of ", _ten])) == _too_long
	_reads("n is count of xs plus sum of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10")
	_sentence_problems(concat("", ["n is count of xs plus sum of ", _eleven])) == _too_long
	_reads({"for": "first of xs whose n is count of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10 as x", "assert": "x.n is 1"})
	_sentence_problems({"for": concat("", ["first of xs whose n is count of ", _eleven, " as x"]), "assert": "x.n is 1"}) == [concat("", ["for: ", p]) | some p in _too_long]
}

test_params_is_not_a_step_of_a_walk if {
	_reads("every $params.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10 is 1")
	_sentence_problems(concat("", ["every $params.", _eleven, " is 1"])) == _too_long
}

_nine := "k1.k2.k3.k4.k5.k6.k7.k8.k9"

_k9(v) := {"k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": v}}}}}}}}}

_k10(v) := {"k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": v}}}}}}}}}}

_part_walk_policy(has, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"thing": {"from": "things", "identified_by": "id", "has": has}},
	"requirements": {"s": {"subject": "thing", "checks": checks}},
}

_part_walk_rows(has, checks, doc) := [[r.subject.id, r.check, r.cause] | some r in ergo.report(doc, _part_walk_policy(has, checks), {}).results; not startswith(r.check, "$")]

_part_walk_problems(has, check) := [i.value | some i in ergo.report({"things": []}, _part_walk_policy(has, {"c": check}), {}).results[0].inputs; i.name == "checks.c"][0]

_part_walk_reads(has, check) if {
	some row in ergo.report({"things": []}, _part_walk_policy(has, {"c": check}), {}).results
	row.check == "$well_formed"
	row.passed
}

test_a_walk_through_a_part_counts_the_parts_own_path_so_ten_steps_in_all_read_and_eleven_are_written_wrong if {
	doc := {"things": [object.union({"id": "a"}, _k9({"z": [1]})), object.union({"id": "b"}, _k9({"z": [2]}))]}
	_part_walk_rows({"x": _nine}, {"e": "every x.z is 1", "s": "some x.z is 1"}, doc) == [["a", "e", "satisfied"], ["a", "s", "satisfied"], ["b", "e", "value"], ["b", "s", "value"]]
	_part_walk_problems({"x": _ten}, "every x.z is 1") == _too_long
	_part_walk_problems({"x": _ten}, "some x.z is 1") == _too_long
}

test_every_straight_on_a_part_of_ten_steps_reads_and_a_part_of_eleven_is_written_wrong if {
	doc := {"things": [object.union({"id": "a"}, _k10([1])), object.union({"id": "b"}, _k10([2]))]}
	_part_walk_rows({"x": _ten}, {"e": "every x is 1"}, doc) == [["a", "e", "satisfied"], ["b", "e", "value"]]
	_part_walk_problems({"x": _eleven}, "every x is 1") == _too_long
	_part_walk_problems({"x": _eleven}, "some x is 1") == _too_long
}

test_a_count_of_or_sum_of_through_a_part_counts_the_parts_path_on_either_side if {
	doc := {"things": [object.union({"id": "a", "n": 2}, _k9({"z": [1, 1]})), object.union({"id": "b", "n": 1}, _k9({"z": [1, 1]}))]}
	checks := {"l": "count of x.z is at least 2", "r": "n is count of x.z", "m": "n is at most sum of x.z", "p": "count of x.z plus count of x.z is 4"}
	[[r[0], r[1], r[2]] | some r in _part_walk_rows({"x": _nine}, checks, doc)] == [
		["a", "l", "satisfied"], ["a", "m", "satisfied"], ["a", "p", "satisfied"], ["a", "r", "satisfied"],
		["b", "l", "satisfied"], ["b", "m", "satisfied"], ["b", "p", "satisfied"], ["b", "r", "value"],
	]
	has := {"x": _ten}
	_part_walk_problems(has, "count of x.z is 1") == _too_long
	_part_walk_problems(has, "sum of x.z is 1") == _too_long
	_part_walk_problems(has, "n is count of x.z") == _too_long
	_part_walk_problems(has, "n is at least sum of x.z") == _too_long
	_part_walk_problems(has, "n is count of k1 plus count of x.z") == _too_long
	_part_walk_problems(has, "count of x.z plus 1 is 2") == _too_long
}

test_a_part_on_a_for_line_item_counts_the_parts_path if {
	doc := {"things": [object.union({"id": "a"}, _k9({"z": [1]})), object.union({"id": "b"}, _k9({"z": [2]}))]}
	_part_walk_rows({"x": _nine}, {"c": {"for": "every x.z as y", "assert": "y is 1"}}, doc) == [["a", "c", "satisfied"], ["b", "c", "value"]]
	_part_walk_problems({"x": _ten}, {"for": "every x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "some x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "first of x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "every xs as y", "assert": "y.n is count of x.z"}) == _too_long
}

test_a_count_or_sum_that_starts_at_a_part_name_on_the_right_of_a_whose_reads_the_part_so_its_path_is_counted if {
	doc := {"things": [object.union({"id": "a", "xs": [{"n": 1, "v": 1, "x": {"z": [1, 1, 1]}}, {"n": 3, "v": 2, "x": {"z": [1, 1, 1]}}]}, _k9({"z": [1]}))]}
	_part_walk_rows({"x": _nine}, {"c": "every xs.v whose n is count of x.z is 1"}, doc) == [["a", "c", "satisfied"]]
	_part_walk_rows({"x": _nine}, {"c": "every xs.v whose n is count of .x.z is 1"}, doc) == [["a", "c", "value"]]
	_part_walk_rows({"x": _nine}, {"c": "count of xs whose count of x.z is 3 is 2"}, doc) == [["a", "c", "satisfied"]]
	has := {"x": _ten}
	_part_walk_problems(has, "every xs.v whose n is count of x.z is 1") == _too_long
	_part_walk_problems(has, "some xs whose n is at most sum of x.z is not empty") == _too_long
	_part_walk_problems(has, "count of xs whose n is count of x.z is 1") == _too_long
	_part_walk_problems(has, "sum of xs.v whose n is count of x.z is 1") == _too_long
	_part_walk_reads({"x": _nine}, "every xs.v whose n is count of x.z is 1")
	_part_walk_reads({"x": _nine}, "some xs whose n is at most sum of x.z is not empty")
	_part_walk_reads({"x": _nine}, "count of xs whose n is count of x.z is 1")
	_part_walk_reads({"x": _nine}, "sum of xs.v whose n is count of x.z is 1")
	_part_walk_reads(has, "every xs.v whose n is count of .x.z is 1")
	_part_walk_reads(has, "every xs.v whose count of x.z is 1 is 1")
	_part_walk_reads(has, "count of xs whose count of x.z is 1 is 1")
	_part_walk_reads({"x": _ten}, "n is 1 and x.z is 1")
}

test_a_plus_or_an_elapsed_time_on_the_right_of_a_whose_reads_the_part_too if {
	item := {"n": 1, "v": 1, "x": {"z": [1, 1, 1], "zz": 5, "a": "2026-01-01", "b": "2026-01-03"}}
	doc := {"things": [{"id": "a", "p": {"z": [1], "zz": 0, "a": "2026-01-01", "b": "2026-01-02"}, "xs": [item]}]}
	checks := {
		"plus_number": "every xs.v whose n is count of x.z plus 0 is 1",
		"plus_path": "every xs.v whose n is x.zz plus count of x.z is 1",
		"elapsed": "every xs.v whose n is days elapsed from x.a to x.b is 1",
		"dot_plus_path": "every xs.v whose n is .x.zz plus count of .x.z is 1",
	}
	_part_walk_rows({"x": "p"}, checks, doc) == [["a", "dot_plus_path", "value"], ["a", "elapsed", "satisfied"], ["a", "plus_number", "satisfied"], ["a", "plus_path", "satisfied"]]
}

test_a_plus_reads_the_part_on_the_subject_and_on_the_right_of_a_whose if {
	doc := {"things": [{"id": "a", "p": {"z": [1], "zz": 0}, "xs": [{"n": 1, "v": 1}]}]}
	checks := {"on_subject": "x.zz plus count of x.z is 1", "in_whose": "every xs.v whose n is x.zz plus count of x.z is 1"}
	_part_walk_rows({"x": "p"}, checks, doc) == [["a", "in_whose", "satisfied"], ["a", "on_subject", "satisfied"]]
}

_tag_of(report, check, name) := [object.get(i, "part", null) | some r in report.results; r.check == check; some i in r.inputs; i.name == name][0]

test_a_count_or_sum_carries_a_part_tag_only_when_its_list_is_read_from_the_part if {
	policy := _part_walk_policy({"pa": "pa"}, {
		"on_items": "count of items whose w is pa.w is 1",
		"on_part": "count of pa.items whose w is pa.w is 1",
		"sum_on_items": "sum of items.n whose w is pa.w is 3",
		"sum_on_part": "sum of pa.items.n whose w is 2 is 5",
	})
	doc := {"things": [{"id": "a", "items": [{"w": 1, "n": 2}, {"w": 2, "n": 3}], "pa": {"w": 2, "items": [{"w": 2, "n": 5}]}}]}
	report := ergo.report(doc, policy, {})
	_tag_of(report, "on_items", "count of items whose w equals pa.w") == null
	_tag_of(report, "on_items", "pa.w") == {"id": null, "name": "pa"}
	_tag_of(report, "on_part", "count of pa.items whose w equals pa.w") == {"id": null, "name": "pa"}
	_tag_of(report, "sum_on_items", "sum of items.n whose w equals pa.w") == null
	_tag_of(report, "sum_on_part", "sum of pa.items.n whose w is 2") == {"id": null, "name": "pa"}
}

test_a_part_in_an_option_of_an_any_of_counts_the_parts_path if {
	has := {"x": _ten}
	_part_walk_problems(has, {"any_of": {"a": "every x.z is 1", "b": "n is 1"}}) == ["option a: every and some over more than ten steps aren't supported yet"]
	_part_walk_reads({"x": _nine}, {"any_of": {"a": "every x.z is 1", "b": "n is 1"}})
}

test_a_part_in_the_whose_of_a_from_line_counts_the_parts_path if {
	doc := {"things": [object.union({"id": "a", "n": 1}, _k9({"z": [1]})), object.union({"id": "b", "n": 2}, _k9({"z": [1]}))]}
	reads := _from_report(doc, {"s": {"from": "things whose n is count of x.z", "identified_by": "id", "has": {"x": _nine}}}, {"c": "id exists"}, {})
	_from_problems(reads) == []
	[[r.subject.id, r.cause] | some r in reads.results; r.check == "$applies"] == [["a", "satisfied"], ["b", "value"]]
	wrong := _from_report(doc, {"s": {"from": "things whose n is count of x.z", "identified_by": "id", "has": {"x": _ten}}}, {"c": "id exists"}, {})
	_from_problems(wrong) == [{"name": "subjects.s.from", "value": ["whose: every and some over more than ten steps aren't supported yet"], "locations": []}]
}

test_a_part_used_in_a_path_that_is_not_a_walk_is_never_held_to_ten_steps if {
	doc := {"things": [object.union({"id": "a"}, _k10({"z": 1}))]}
	_part_walk_rows({"x": _ten}, {"c": "x.z is 1", "d": "x exists", "e": "x.z is at least 1"}, doc) == [["a", "c", "satisfied"], ["a", "d", "satisfied"], ["a", "e", "satisfied"]]
	_part_walk_reads({"x": _eleven}, "x.z is 1")
}

_parent_part_policy(has, check) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"b": {"from": "bs", "identified_by": "id", "has": has}, "kid": {"from": "b.kids", "identified_by": "id"}},
	"requirements": {"r": {"subject": "kid", "checks": {"c": check}}},
}

test_a_walk_through_a_part_of_the_parent_counts_the_parts_path if {
	doc := {"bs": [{"id": "b1", "kids": [{"id": "k1"}], "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"z": [1]}}}}}}}}}}]}
	[r.cause | some r in ergo.report(doc, _parent_part_policy({"x": _nine}, "every b.x.z is 1"), {}).results; r.check == "c"] == ["satisfied"]
	wrong := ergo.report(doc, _parent_part_policy({"x": _ten}, "every b.x.z is 1"), {})
	[i.value | some r in wrong.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [_too_long]
}

_parent_part_problems(has, check) := [i.value | some r in ergo.report({"bs": []}, _parent_part_policy(has, check), {}).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

_parent_part_cause(has, check, doc) := [r.cause | some r in ergo.report(doc, _parent_part_policy(has, check), {}).results; r.check == "c"]

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_reads_the_parents_part_and_counts_its_path if {
	doc := {"bs": [object.union({"id": "b1", "kids": [{"id": "c1", "n": 1, "xs": [{"v": 1, "n": 1, "b": {"x": {"z": [1, 1]}}}]}]}, _k9({"z": [1]}))]}
	has := {"x": _nine}
	_parent_part_cause(has, "count of xs whose n is count of b.x.z is 1", doc) == ["satisfied"]
	_parent_part_cause(has, "count of xs whose n is count of b.x.z is 0", doc) == ["value"]
	_parent_part_cause(has, "count of xs whose n is at least count of b.x.z is 1", doc) == ["satisfied"]
	_parent_part_cause(has, "sum of xs.v whose n is count of b.x.z is 1", doc) == ["satisfied"]
	_parent_part_cause(has, "count of xs whose n is count of .b.x.z is 1", doc) == ["value"]
	_parent_part_cause(has, "count of xs whose count of b.x.z is 2 is 1", doc) == ["satisfied"]
}

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_counts_the_parents_part_at_ten_names if {
	_parent_part_problems({"x": _ten}, "count of xs whose n is count of b.x.z is 1") == [_too_long]
	_parent_part_problems({"x": _ten}, "sum of xs.v whose n is count of b.x.z is 1") == [_too_long]
	_parent_part_problems({"x": _nine}, "count of xs whose n is count of b.x.z is 1") == []
	_parent_part_problems({"x": _ten}, "count of xs whose count of b.x.z is 1 is 1") == []
}

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_reads_the_parent_and_fails_closed_when_it_cant if {
	kid := {"id": "c1", "xs": [{"v": 1, "n": 2, "b": {"z": [1]}}]}
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["satisfied"]
	_parent_part_cause({}, "sum of xs.v whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["satisfied"]
	_parent_part_cause({}, "count of xs whose n is count of .b.z is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["value"]
	_parent_part_cause({}, "count of xs whose count of b.z is 1 is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["satisfied"]
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "kids": [kid]}]}) == ["absent"]
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": null, "kids": [kid]}]}) == ["null"]
	_parent_part_cause({}, "sum of xs.v whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": "ab", "kids": [kid]}]}) == ["unusable"]
}

test_a_parent_part_in_the_whose_of_every_some_or_a_for_item_is_still_counted_at_ten_names if {
	has := {"x": _ten}
	_parent_part_problems(has, "every xs.v whose n is count of b.x.z is 1") == [_too_long]
	_parent_part_problems(has, "some xs whose n is count of b.x.z is not empty") == [_too_long]
	_parent_part_problems({"x": _nine}, "every xs.v whose n is count of b.x.z is 1") == []
}

test_a_walk_that_is_already_written_wrong_for_another_reason_gets_no_ten_step_message_too if {
	has := {"x": _ten}
	_part_walk_problems(has, {"for": "every xs as x", "assert": "every x.z is 1"}) == ["x can't be an alias: it's a part of thing"]
	_part_walk_problems(has, {"for": "every xs as x", "assert": "count of x.z is 1"}) == ["x can't be an alias: it's a part of thing"]
	_parent_part_problems(has, "count of xs whose sum of b.x.z is 1 is 0") == [["a sum of or a plus in the whose of a count of or a sum of isn't supported yet"]]
}

test_a_walk_over_ten_steps_in_a_for_items_whose_is_listed_under_for if {
	_parent_part_problems({"x": _ten}, {"for": "every xs whose n is count of b.x.z as y", "assert": "y.v is 1"}) == [[_for_too_long]]
	_part_walk_problems({"x": _ten}, {"for": "every xs whose n is count of x.z as r", "assert": "r.v is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "every xs as r", "assert": "every r.v whose n is count of x.z is 1"}) == _too_long
}

test_a_parent_part_on_the_right_of_a_count_whose_gets_the_ten_step_message_beside_another_problem if {
	_parent_part_problems({"x": _ten}, "count of xs whose n is sum of b.x.z is 0") == [["a sum of or a plus in the whose of a count of or a sum of isn't supported yet", "every and some over more than ten steps aren't supported yet"]]
}

test_a_for_alias_named_like_a_parent_subject_still_counts_the_parents_part_beside_the_clash if {
	_parent_part_problems({"x": _ten}, {"for": "every xs as b", "assert": "every b.x.z is 1"}) == [["b can't be an alias: it's a subject's name", "every and some over more than ten steps aren't supported yet"]]
}

test_a_walk_whose_named_by_cant_be_read_shows_an_empty_list_in_its_inputs if {
	r := ergo.report({"things": [{"id": "a", "xs": {"k": [1]}}]}, _sentence_policy({"c": "every xs named by $params.k is 1"}), {})
	[[row.cause, row.inputs, row.failed_items] | some row in r.results; row.check == "c"] == [["absent", [{"name": "xs named by $params.k", "value": [], "locations": []}], []]]
}

test_a_list_phrase_after_every_or_some_is_written_wrong_because_the_last_list_is_walked_too if {
	_sentence_problems(`every pull_requests.labels does not contain "hotfix"`) == [`"does not contain" after every or some would check each item of the last list, not the list: put the walk on a for line`]
	_sentence_problems(`some xs contains all of 1, 2`) == [`"contains all of" after every or some would check each item of the last list, not the list: put the walk on a for line`]
}

_for_rows(check, things, params) := [[r.subject.id, r.cause, _bare_failed(r.failed_items), r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_for_rows_full(check, things, params) := [[r.subject.id, r.cause, r.failed_items, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_bare_failed(failed) := [_bare_item(f) | some f in failed]

_bare_item(f) := object.union(f, {"failed_assertions": [_bare_line(l) | some l in f.failed_assertions]})

_bare_line(l) := object.union(object.remove(l, ["inputs", "items"]), {"items": [object.remove(i, ["inputs"]) | some i in l.items]}) if "items" in object.keys(l)

_bare_line(l) := object.remove(l, ["inputs"]) if not "items" in object.keys(l)

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
		{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "value", "value": _peer_things[1].approvers[0], "failed_assertions": [{"assertion": "approver.timestamp is after commit.timestamp", "cause": "value", "items": [{"item": "item 2 of commits", "cause": "value"}]}], "locations": ["/things/1/approvers/0"]},
		{"path": "item 2 of approvers", "item": "item 2 of approvers", "cause": "value", "value": _peer_things[1].approvers[1], "failed_assertions": [{"assertion": "approver.username does not equal author", "cause": "value"}], "locations": ["/things/1/approvers/1"]},
	]
	rows[2][2] == [{"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "absent", "value": _peer_things[2].approvers[0], "failed_assertions": [], "locations": ["/things/2/approvers/0"]}]
	rows[0][2] == []
}

test_a_for_line_shows_each_list_it_walked_once_and_the_subject_fields_it_read if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	rows[1][3] == [
		{"name": "approvers[]", "value": _peer_things[1].approvers, "locations": ["/things/1/approvers/0", "/things/1/approvers/1", "/things/1/approvers/2"]},
		{"name": "author", "value": "ann", "locations": ["/things/1/author"]},
		{"name": "commits[]", "value": _peer_things[1].commits, "locations": ["/things/1/commits/0", "/things/1/commits/1"]},
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
	rows[1][2] == [{"path": "item 2 of pull_requests", "item": "item 2 of pull_requests", "cause": "value", "value": things[1].pull_requests[1], "failed_assertions": [{"assertion": "approver.username does not equal pr.author", "cause": "value", "items": [{"item": "item 1 of pr.approvers", "cause": "value"}]}], "locations": ["/things/1/pull_requests/1"]}]
	rows[1][3] == [
		{"name": "pr.approvers[]", "value": array.concat(things[1].pull_requests[0].approvers, things[1].pull_requests[1].approvers), "locations": ["/things/1/pull_requests/0/approvers/0", "/things/1/pull_requests/1/approvers/0", "/things/1/pull_requests/1/approvers/1"]},
		{"name": "pull_requests[]", "value": things[1].pull_requests, "locations": ["/things/1/pull_requests/0", "/things/1/pull_requests/1"]},
	]
}

test_an_item_that_no_approver_passes_fails_without_lines_when_whose_left_every_one_out if {
	check := {"for": `every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver`, "assert": "approver.username does not equal pr.author"}
	rows := _for_rows(check, [{"id": 1, "pull_requests": [{"author": "ann", "approvers": [{"username": "bob", "state": "COMMENTED"}]}]}], {})
	rows[0][1] == "value"
	rows[0][2] == [{"path": "item 1 of pull_requests", "item": "item 1 of pull_requests", "cause": "value", "value": {"author": "ann", "approvers": [{"username": "bob", "state": "COMMENTED"}]}, "failed_assertions": [], "locations": ["/things/0/pull_requests/0"]}]
}

test_a_for_list_fails_closed_as_a_walk_does if {
	check := {"for": "every xs as x", "assert": "x is 1"}
	rows := _for_rows(check, [{"id": 1, "xs": []}, {"id": 2}, {"id": 3, "xs": null}, {"id": 4, "xs": {"a": 1}}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "value", [{"path": "xs", "item": "xs", "cause": "value", "value": [], "failed_assertions": [], "locations": ["/things/0/xs"]}]],
		[2, "absent", [{"path": "xs", "item": "xs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/1"]}]],
		[3, "null", [{"path": "xs", "item": "xs", "cause": "null", "value": null, "failed_assertions": [], "locations": ["/things/2/xs"]}]],
		[4, "unusable", [{"path": "xs", "item": "xs", "cause": "unusable", "value": {"a": 1}, "failed_assertions": [], "locations": ["/things/3/xs"]}]],
	]
	[row[1] | some row in _for_rows({"for": "every xs, if any, as x", "assert": "x is 1"}, [{"id": 1, "xs": []}, {"id": 2}], {})] == ["satisfied", "absent"]
}

test_an_item_a_whose_cant_decide_fails_with_its_cause_before_any_line_is_read if {
	check := {"for": "every xs whose s is at least 1 as x", "assert": `x.k is "a"`}
	rows := _for_rows(check, [{"id": 1, "xs": [{"k": "a", "s": 1}, {"k": "a"}]}, {"id": 2, "xs": [{"k": "a", "s": "1"}]}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "absent", "value": {"k": "a"}, "failed_assertions": [], "locations": ["/things/0/xs/1"]}]],
		[2, "unusable", [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "unusable", "value": {"k": "a", "s": "1"}, "failed_assertions": [], "locations": ["/things/1/xs/0"]}]],
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
	rows[1][3] == [{"name": "$params.allowed[]", "value": ["a", "b"], "locations": ["$params:/allowed/0", "$params:/allowed/1"]}, {"name": "k", "value": "z", "locations": ["/things/1/k"]}]
	[row[1] | some row in _for_rows(check, [{"id": 1, "k": "a"}], {})] == ["absent"]
}

test_an_every_in_the_assertion_walks_inside_the_named_item if {
	check := {"for": "some xs as x", "assert": "every x.ys is at most 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"ys": [1, 3]}, {"ys": [1, 2]}]}, {"id": 2, "xs": [{"ys": [3]}]}], {})] == ["satisfied", "value"]
}

test_each_item_lists_every_line_it_failed_with_the_first_cause_of_each if {
	check := {"for": "every xs as x", "assert": ["x.a is 2", "x.b is 2", "x.c is 1"]}
	rows := _for_rows(check, [{"id": 1, "xs": [{"a": 1, "b": 2}, {"a": 2, "b": 2, "c": 1}]}], {})
	rows[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": {"a": 1, "b": 2}, "failed_assertions": [{"assertion": "x.a is 2", "cause": "value"}, {"assertion": "x.c is 1", "cause": "absent"}], "locations": ["/things/0/xs/0"]}]
}

test_a_for_line_on_a_subject_that_isnt_an_object_fails_like_any_path_does if {
	[[row[1], row[2], row[3]] | some row in _for_rows({"for": "every xs as x", "assert": "x is 1"}, ["s"], {})] == [["not_an_object", [], []]]
}

test_a_for_line_written_wrong_says_why if {
	_sentence_problems({"assert": "x exists", "for": 1}) == ["invalid for"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as y, every zs as z"}) == ["for: a for line holds two items at most"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as"}) == [`for: an item ends with "as" and a name, like "every pull_requests as pr"`]
	_sentence_problems({"assert": "x.a exists", "for": "xs as x"}) == [`for: an item starts with "every", "some" or a position, like "last of"`]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as x"}) == ["for: x is given twice"]
	_sentence_problems({"assert": "x.a is 1", "for": "every xs as params"}) == ["for: params can't be an alias"]
	_sentence_problems({"assert": "x.a is 1", "for": "some xs, if any, as x"}) == ["for: if any can't go with some"]
	_sentence_problems({"assert": "x is $foo", "for": "every xs as x"}) == ["unknown name $foo"]
}

test_forms_ergo_does_not_run_yet_are_written_wrong_on_a_for_line_too if {
	every pair in [
		["every xs whose last of ys is 1 as x", "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""],
		["every b.c.d.e.f.g.h.i.j.k.l.m as x", "every and some over more than ten steps aren't supported yet"],
	] {
		_sentence_problems({"assert": "x is 1", "for": pair[0]}) == [concat("", ["for: ", pair[1]])]
	}
}

test_a_for_list_whose_named_by_cant_be_read_fails_with_its_cause_as_a_walk_does if {
	check := {"for": "every m named by $params.k as x", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {}) == [[1, "absent", [], [{"name": "m named by $params.k", "value": [], "locations": []}]]]
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {"k": "a"}) == [[1, "satisfied", [], [{"name": "m named by $params.k[]", "value": [1], "locations": ["/things/0/m/a/0"]}]]]
	inner := {"for": "every xs as x, every m named by $params.k as y", "assert": "y is 1"}
	_for_rows(inner, [{"id": 1, "xs": [1], "m": {"a": [1]}}], {}) == [[
		1, "absent",
		[{"path": "m named by $params.k", "item": "m named by $params.k", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0/m"]}],
		[{"name": "m named by $params.k", "value": [], "locations": []}, {"name": "xs[]", "value": [1], "locations": ["/things/0/xs/0"]}],
	]]
}

test_a_second_item_a_whose_cant_decide_fails_the_first_item_with_its_cause if {
	check := {"for": "every xs as x, every ys whose s is 1 as y", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "xs": [1], "ys": [{"s": 1}, {"t": 1}]}], {})[0] == [1, "absent", [{"path": "item 2 of ys", "item": "item 2 of ys", "cause": "absent", "value": {"t": 1}, "failed_assertions": [], "locations": ["/things/0/ys/1"]}], [{"name": "xs[]", "value": [1], "locations": ["/things/0/xs/0"]}, {"name": "ys[]", "value": [{"s": 1}, {"t": 1}], "locations": ["/things/0/ys/0", "/things/0/ys/1"]}]]
}

test_a_for_line_whose_param_cant_be_used_fails_as_unusable_and_keeps_its_inputs if {
	rows := _for_rows({"for": "every xs as x", "assert": "x is one of $params.l"}, [{"id": 1, "xs": [1]}, "s"], {"l": "text"})
	rows == [[1, "unusable", [], [{"name": "xs[]", "value": [1], "locations": ["/things/0/xs/0"]}]], ["s", "unusable", [], [{"name": "xs", "value": [], "locations": []}]]]
	[row[1] | some row in _for_rows({"for": "every xs whose x is one of $params.l as x", "assert": "x is 1"}, [{"id": 1, "xs": [1]}], {"l": "text"})] == ["unusable"]
}

test_a_name_whose_path_ends_missing_or_unreadable_fails_its_item_before_its_lines if {
	rows := _for_rows({"for": "every prs.title as t", "assert": "t does not exist"}, [{"id": 1, "prs": [{}]}, {"id": 2, "prs": [{"title": null}]}, {"id": 3, "prs": [{"meta": "s"}]}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0/prs/0"]}]],
		[2, "satisfied", []],
		[3, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/2/prs/0"]}]],
	]
	[row[1] | some row in _for_rows({"for": "every prs.meta.title as t", "assert": "t is null"}, [{"id": 1, "prs": [{"meta": "s"}]}], {})] == ["unusable"]
	[row[1] | some row in _for_rows({"for": `every prs.title whose n is 1 as t`, "assert": `t is "x"`}, [{"id": 1, "prs": [{"n": 2}, {"n": 1, "title": "x"}]}], {})] == ["satisfied"]
}

test_an_every_under_a_for_line_shows_its_list_as_a_one_line_every_does if {
	rows := _for_rows({"for": "every prs as pr", "assert": "every cs.s is true"}, [{"id": 1, "prs": [{"n": 1}], "cs": [{"s": true}, {"s": false}]}], {})
	rows[0][3] == [{"name": "cs[].s", "value": [true, false], "locations": ["/things/0/cs/0/s", "/things/0/cs/1/s"]}, {"name": "prs[]", "value": [{"n": 1}], "locations": ["/things/0/prs/0"]}]
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
		{"name": `count of findings whose source is "claude"`, "value": 2, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "findings[]", "value": _review.findings, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
	]]]
}

test_sum_of_adds_up_the_field_across_the_items_left_in if {
	_tally_rows(`sum of stages.usd whose kind is "model" equals total_usd within 0.01`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `sum of stages.usd whose kind is "model"`, "value": 0.75, "locations": ["/things/0/stages/0/usd", "/things/0/stages/1/usd", "/things/0/stages/2/usd"]},
		{"name": "stages[].usd", "value": [0.5, 0.25, 0], "locations": ["/things/0/stages/0/usd", "/things/0/stages/1/usd", "/things/0/stages/2/usd"]},
		{"name": "total_usd", "value": 0.76, "locations": ["/things/0/total_usd"]},
	]]]
	[row[1] | some row in _tally_rows("sum of xs.n is 0.3", [{"id": 1, "xs": [{"n": 0.1}, {"n": 0.2}]}], {})] == ["satisfied"]
}

test_within_works_out_the_gap_exactly_in_a_whose if {
	[row[1] | some row in _tally_rows("count of xs whose x equals y within 0.2 is 1", [{"id": 1, "xs": [{"x": 0.3, "y": 0.1}]}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of xs whose x equals y within 0.19999 is 0", [{"id": 1, "xs": [{"x": 0.3, "y": 0.1}]}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of xs whose x equals y within 0.2 is 1", [{"id": 1, "xs": [{"x": 1e15, "y": 1e15}]}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of xs whose x equals y within 1 is 1", [{"id": 1, "xs": [{"x": 1e5000, "y": 1}]}], {})] == ["unusable"]
}

_within_cause(x, y, w) := cause if {
	rows := [row[1] | some row in _tally_rows(concat("", ["x equals y within ", w]), [{"id": 1, "x": x, "y": y}], {})]
	cause := rows[0]
}

test_within_reads_numbers_opa_counts_as_equal_by_their_digits if {
	_within_cause(1234567890.1209567990, 0, "1234567890.1209567890") == "value"
	_within_cause(123964818.71664440535747000531389400, 123964818.7166444053574700053138940000000000000002244422625687264764923070, "0.0000000000000000000000000000000000000002244422625687264764923069") == "value"
	_within_cause(123964818.71664440535747000531389400, 123964818.7166444053574700053138940000000000000002244422625687264764923070, "0.0000000000000000000000000000000000000002244422625687264764923070") == "satisfied"
}

test_within_compares_more_than_fifteen_digits_exactly_on_both_sides_of_the_boundary if {
	_within_cause(12345678901234567890.5, 12345678901234567890.4, "0.1") == "satisfied"
	_within_cause(12345678901234567890.5, 12345678901234567890.4, "0.09") == "value"
	_within_cause(12345678901234567890.4, 12345678901234567890.5, "0.1") == "satisfied"
	_within_cause(12345678901234567890.4, 12345678901234567890.5, "0.09") == "value"
	_within_cause(0.30000000000000004, 0.3, "0.01") == "satisfied"
	_within_cause(0.30000000000000004, 0.3, "0.000000000000000001") == "value"
}

test_within_passes_the_float_noise_of_a_cost_and_its_total if {
	_within_cause(0.30000000000000004, 0.3, "0.01") == "satisfied"
	_within_cause(12.340000000000002, 12.34, "0.01") == "satisfied"
	_within_cause(1761700000.123456, 1761700000.12, "0.01") == "satisfied"
}

test_within_carries_across_chunk_boundaries if {
	_within_cause(99999999999999999999, -1, "100000000000000000000") == "satisfied"
	_within_cause(99999999999999999999, -1, "99999999999999999999") == "value"
	_within_cause(-1, 99999999999999999999, "100000000000000000000") == "satisfied"
	_within_cause(9999999999999999999999999999, 1, "9999999999999999999999999998") == "satisfied"
	_within_cause(9999999999999999999999999999, 1, "9999999999999999999999999997") == "value"
	_within_cause(10000000000000000000000000000, 1, "9999999999999999999999999999") == "satisfied"
	_within_cause(10000000000000000000000000000, 1, "9999999999999999999999999998") == "value"
}

test_within_adds_the_sizes_when_the_signs_differ_and_takes_the_difference_when_they_match if {
	_within_cause(-5000000000000000000000, 5000000000000000000000, "10000000000000000000000") == "satisfied"
	_within_cause(-5000000000000000000000, 5000000000000000000001, "10000000000000000000000") == "value"
	_within_cause(-5000000000000000000001, 5000000000000000000000, "10000000000000000000000") == "value"
	_within_cause(-5000000000000000000000, -5000000000000000000003, "3") == "satisfied"
	_within_cause(-5000000000000000000000, -5000000000000000000003, "2") == "value"
}

test_within_treats_zero_and_negative_zero_as_having_no_sign if {
	_within_cause(0, -0, "0") == "satisfied"
	_within_cause(-0, -1e20, "100000000000000000000") == "satisfied"
	_within_cause(0, -1e20, "99999999999999999999") == "value"
	_within_cause(1e20, 0, "100000000000000000000") == "satisfied"
	_within_cause(-1e-30, 0, "0.000000000000000000000000000001") == "satisfied"
}

test_within_compares_tiny_exponents_exactly if {
	_within_cause(3e-30, 1e-30, "0.000000000000000000000000000002") == "satisfied"
	_within_cause(3e-30, 1e-30, "0.000000000000000000000000000001") == "value"
	_within_cause(1e-30, -1e-30, "0.000000000000000000000000000002") == "satisfied"
}

test_within_compares_big_numbers_that_need_no_decimals_exactly if {
	_within_cause(1e9, 1e9, "0.000001") == "satisfied"
	_within_cause(1000000000.000001, 1e9, "0.000001") == "satisfied"
	_within_cause(1000000000.000002, 1e9, "0.000001") == "value"
}

test_within_gives_up_as_unusable_when_the_exponents_are_more_than_4096_apart if {
	_within_cause(1e5000, 1, "1") == "unusable"
	_within_cause(1, 1e5000, "1") == "unusable"
	_within_cause(1e4097, 1, "1") == "unusable"
	_within_cause(1e4000, 1e4000, "1e-300") == "unusable"
}

test_within_compares_when_the_exponents_are_exactly_4096_apart if {
	_within_cause(1e4096, 1, "1") == "value"
	_within_cause(1e4096, 1e4096, "1") == "satisfied"
	_within_cause(-1e4096, 1e4096, "1") == "value"
	_within_cause(-1e4096, -1e4096, "0") == "satisfied"
}

test_plus_adds_paths_numbers_counts_and_sums if {
	_tally_rows("claude_found is count of personas_ran plus 1", [_review], {}) == [["pr-7", "satisfied", [
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
		{"name": "count of personas_ran plus 1", "value": 2, "locations": ["/things/0/personas_ran/0"]},
		{"name": "count of personas_ran", "value": 1, "locations": ["/things/0/personas_ran/0"]},
		{"name": "personas_ran[]", "value": ["security"], "locations": ["/things/0/personas_ran/0"]},
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
	rows[1][2] == [{"name": "count of ps", "value": 1, "locations": ["/things/1/ps/0"]}, {"name": "prs[]", "value": [{"r": [1, 2]}], "locations": ["/things/1/prs/0"]}, {"name": "ps[]", "value": ["a"], "locations": ["/things/1/ps/0"]}]
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "count of pr.r whose u does not equal pr.a is 2"}, [{"id": 1, "prs": [{"a": "x", "r": [{"u": "x"}, {"u": "y"}, {"u": "z"}]}]}], {})] == ["satisfied"]
}

test_a_count_whose_named_by_cant_be_read_fails_with_its_cause if {
	_tally_rows("count of m named by $params.k is 2", [{"id": 1, "m": {"a": [1, 2]}}], {}) == [[1, "absent", [{"name": "count of m named by $params.k", "value": null, "locations": []}, {"name": "m named by $params.k", "value": [], "locations": []}]]]
}

_sum_whose_cause(check, items) := [row[1] | some row in _tally_rows(check, [{"id": "t", "items": items}], {})]

test_a_sum_fails_with_the_cause_of_an_item_whose_cant_decide_and_does_not_read_its_field if {
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": "ab", "k": null}]) == ["null"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": "ab"}]) == ["absent"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": "ab", "k": 5}]) == ["unusable"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": 1, "k": null}]) == ["null"]
	_sum_whose_cause(`sum of items.x.y whose k is "a" is 1`, [{"x": "ab", "k": null}]) == ["null"]
	_sum_whose_cause(`sum of items.x.y whose k is "a" is 1`, [{"x": {"y": "ab"}, "k": null}]) == ["null"]
}

test_a_sum_whose_worst_cause_wins_between_an_undecided_item_and_the_bad_field_of_a_kept_item if {
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": "ab"}, {"x": null, "k": "a"}]) == ["absent"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": "ab", "k": null}, {"x": "ab", "k": "a"}]) == ["unusable"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 1`, [{"x": 1, "k": null}, {"x": null, "k": "a"}]) == ["null"]
}

test_a_sum_whose_kept_items_are_all_fine_is_still_added if {
	_sum_whose_cause(`sum of items.x whose k is "a" is 3`, [{"x": 1, "k": "a"}, {"x": "ab", "k": "b"}, {"x": 2, "k": "a"}]) == ["satisfied"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 4`, [{"x": 1, "k": "a"}, {"x": "ab", "k": "b"}, {"x": 2, "k": "a"}]) == ["value"]
	_sum_whose_cause(`sum of items.x whose k is "a" is 3`, [{"x": 3, "k": "a"}, {"x": "ab", "k": "b"}]) == ["satisfied"]
}

test_a_count_whose_undecided_item_fails_with_its_cause if {
	_sum_whose_cause(`count of items whose k is "a" is 1`, [{"x": "ab", "k": null}]) == ["null"]
	_sum_whose_cause(`count of items.x whose k is "a" is 1`, [{"x": "ab"}]) == ["absent"]
	_sum_whose_cause(`count of items.x whose k is "a" is 1`, [{"x": null, "k": null}, {"x": 1, "k": "a"}]) == ["null"]
}

test_a_count_fails_on_a_value_it_cant_read_unless_whose_left_its_item_out if {
	[row[1] | some row in _tally_rows("count of xs.t is 1", [{"id": 1, "xs": ["s"]}], {})] == ["not_an_object"]
	[row[1] | some row in _tally_rows("count of xs.t whose k is 1 is 1", [{"id": 1, "xs": [{"k": 1, "t": 0}, {"k": 2}]}], {})] == ["satisfied"]
}

test_plus_with_a_whose_on_its_last_count if {
	_tally_rows(`claude_found plus count of findings whose source is "gpt" is at least 3`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `claude_found plus count of findings whose source is "gpt"`, "value": 3, "locations": ["/things/0/claude_found", "/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
		{"name": `count of findings whose source is "gpt"`, "value": 1, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "findings[]", "value": _review.findings, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
	]]]
}

test_plus_under_a_for_line_reads_the_names if {
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "pr.a plus count of pr.r is 3"}, [{"id": 1, "prs": [{"a": 1, "r": [1, 2]}]}, {"id": 2, "prs": [{"a": 2, "r": [1, 2]}]}], {})] == ["satisfied", "value"]
}

test_sum_of_and_plus_add_numbers_as_decimals if {
	_tally_rows("sum of xs.n is 1.6", [{"id": 1, "xs": [{"n": 0.7}, {"n": 0.9}]}], {})[0][2][0] == {"name": "sum of xs.n", "value": 1.6, "locations": ["/things/0/xs/0/n", "/things/0/xs/1/n"]}
	[row[1] | some row in _tally_rows("x is p plus q plus 0.1", [{"id": 1, "p": 0.7, "q": 0.9, "x": 1.7}], {})] == ["satisfied"]
	ergo._decimal_sum([1e-7, 2e-7]) == 3e-7
	ergo._decimal_sum([1.5e3, 0.25]) == 1500.25
	ergo._decimal_sum([-0.7, 0.9]) == 0.2
	ergo._decimal_sum([]) == 0
	not ergo._decimal_sum([1e-20, 1])
	not ergo._decimal_sum([1e15])
	ergo._decimal_sum([0.123456789012345]) == 0.123456789012345
	ergo._decimal_sum([0.1, 0.2, 100]) == 100.3
}

test_a_sum_with_several_values_it_cant_add_fails_with_the_worst_cause if {
	[row[1] | some row in _tally_rows("sum of items.usd is 30", [{"id": 1, "items": [{"usd": null}, {}, {"usd": "x"}]}, {"id": 2, "items": [{"usd": null}, {}]}], {})] == ["unusable", "absent"]
}

test_a_sum_that_needs_more_than_fifteen_digits_at_a_common_scale_fails_as_unusable if {
	[[row[1], row[2][0].value] | some row in _tally_rows("sum of xs is at least big", [{"id": 1, "xs": [0.1, 1e30], "big": 1e30}], {})] == [["unusable", null]]
	[[row[1], row[2][0].value] | some row in _tally_rows("big plus 0.1 is at least big", [{"id": 1, "big": 1e30}], {})] == [["unusable", null]]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 0.123456789012345, "y": 100}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 1e20, "y": 1e20}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 999999999999999, "y": 1}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 0.1000000000000000001, "y": 0.2}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 1e-16, "y": 0}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("sum of xs is at least 0", [{"id": 1, "xs": [1e15]}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("sum of xs is at least 0", [{"id": 1, "xs": [0.123456789012345, 100]}], {})] == ["unusable"]
	[row[1] | some row in _tally_rows("x plus y is at least 0", [{"id": 1, "x": 0.1, "y": 0.2}], {})] == ["satisfied"]
}

test_a_number_with_trailing_zeros_is_added_exactly if {
	_tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.500000000000000000, "y": 1}], {})[0][2][0].value == 2.5
	[row[1] | some row in _tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.50, "y": 1}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("x plus y is 2.5", [{"id": 1, "x": 1.500000000000000000, "y": 1}], {})] == ["satisfied"]
}

test_a_count_on_a_subject_or_item_that_isnt_an_object_fails_as_not_an_object if {
	[[row[0], row[1]] | some row in _tally_rows("count of xs is 1", [5, null, [1, 2]], {})] == [[5, "not_an_object"], [null, "not_an_object"], [[1, 2], "not_an_object"]]
	[row[1] | some row in _tally_rows("count of xs.n is 1", [{"id": 1, "xs": [5]}], {})] == ["not_an_object"]
	[row[2][0].value | some row in _tally_rows("count of xs.n is 2", [{"id": 1, "xs": [{"n": 1}, {"n": null}]}], {})] == [2]
}

test_a_count_whose_whose_reads_a_for_name_shows_its_list_and_not_its_number if {
	rows := _tally_rows({"for": "every prs as pr", "assert": "count of xs whose n is pr.need is at least 1"}, [{"id": 1, "prs": [{"need": 1}, {"need": 2}], "xs": [{"n": 1}, {"n": 2}]}], {})
	rows == [[1, "satisfied", [
		{"name": "prs[]", "value": [{"need": 1}, {"need": 2}], "locations": ["/things/0/prs/0", "/things/0/prs/1"]},
		{"name": "xs[]", "value": [{"n": 1}, {"n": 2}], "locations": ["/things/0/xs/0", "/things/0/xs/1"]},
	]]]
	added := _tally_rows({"for": "every prs as pr", "assert": "1 plus count of xs whose n is pr.need is at least 2"}, [{"id": 1, "prs": [{"need": 1}], "xs": [{"n": 1}]}], {})
	added == [[1, "satisfied", [
		{"name": "prs[]", "value": [{"need": 1}], "locations": ["/things/0/prs/0"]},
		{"name": "xs[]", "value": [{"n": 1}], "locations": ["/things/0/xs/0"]},
	]]]
}

test_a_count_whose_whose_reads_a_param_it_cant_use_shows_null if {
	_tally_rows("count of xs whose s is one of $params.v is 1", [{"id": 1, "xs": [{"s": "a"}]}], {"v": 5}) == [[1, "unusable", [{"name": "count of xs whose s is in $params.v", "value": null, "locations": ["/things/0/xs/0"]}, {"name": "xs[]", "value": [{"s": "a"}], "locations": ["/things/0/xs/0"]}]]]
}

test_a_count_whose_ref_cant_be_read_is_read_the_slow_way_and_fails_with_the_refs_cause if {
	_tally_rows(`count of xs whose s is one of $params.missing is 1`, [{"id": 1, "xs": [{"s": "a"}]}], {}) == [[1, "absent", [{"name": "count of xs whose s is in $params.missing", "value": null, "locations": ["/things/0/xs/0"]}, {"name": "xs[]", "value": [{"s": "a"}], "locations": ["/things/0/xs/0"]}]]]
}

test_a_count_whose_whose_reads_a_missing_param_fails_even_when_it_would_count_zero if {
	things := [{"id": 1, "xs": []}, {"id": 2, "xs": [{"k": "a"}]}]
	_tally_rows("count of xs whose k is one of $params.missing is 0", things, {}) == [
		[1, "absent", [{"name": "count of xs whose k is in $params.missing", "value": null, "locations": []}, {"name": "xs[]", "value": [], "locations": []}]],
		[2, "absent", [{"name": "count of xs whose k is in $params.missing", "value": null, "locations": ["/things/1/xs/0"]}, {"name": "xs[]", "value": [{"k": "a"}], "locations": ["/things/1/xs/0"]}]],
	]
	[row[1] | some row in _tally_rows("count of xs whose k is one of $params.v is 0", things, {"v": null})] == ["null", "null"]
}

test_an_and_list_of_counts_shows_each_count_once if {
	rows := _tally_rows({"assert": ["count of findings is 3", "claude_found plus 1 is 3"]}, [_review], {})
	rows == [["pr-7", "satisfied", [
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
		{"name": "claude_found plus 1", "value": 3, "locations": ["/things/0/claude_found"]},
		{"name": "count of findings", "value": 3, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "findings[]", "value": _review.findings, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
	]]]
}

_from_report(doc, subjects, checks, params) := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": object.keys(subjects)[_], "checks": checks}}}, params) if count(subjects) == 1

_from_rows(rep) := [[r.subject.id, r.check, r.cause, r.inputs] | some r in rep.results; not r.check in {"$min_subjects", "$unique_ids", "$well_formed"}]

_from_problems(rep) := [i | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

_deployments := {"deployments": [
	{"id": 1, "environment": "prod", "change_type": "emergency"},
	{"id": 2, "environment": "dev"},
	{"id": 3, "environment": "prod", "change_type": "standard"},
]}

test_a_from_written_as_a_sentence_reads_its_path_and_keeps_the_subjects_whose_conditions_hold if {
	rep := _from_report(_deployments, {"emergency change": {"from": `deployments whose environment is "prod" and change_type is "emergency"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	_from_rows(rep) == [
		[1, "$applies", "satisfied", [{"name": "change_type", "value": "emergency", "locations": ["/deployments/0/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/0/environment"]}]],
		[2, "$applies", "absent", [{"name": "change_type", "value": null, "locations": ["/deployments/1"]}, {"name": "environment", "value": "dev", "locations": ["/deployments/1/environment"]}]],
		[3, "$applies", "value", [{"name": "change_type", "value": "standard", "locations": ["/deployments/2/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/2/environment"]}]],
		[1, "c", "satisfied", [{"name": "id", "value": 1, "locations": ["/deployments/0/id"]}]],
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
	every def in [null, {}, {"identified_by": "fingerprint"}] {
		[[r[1], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": def}, {"c": "signed is true"}, {}))] == [["c", "satisfied"]]
	}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": {"from": "$input", "identified_by": "artifact.fingerprint"}}, {"c": "artifact.signed is true"}, {}))] == [["sha256:abc", "satisfied"]]
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
	rep := _from_report(doc, {"x": {"from": "xs whose tags is empty and count of cs is at least 1", "identified_by": "id"}}, {"c": "id exists"}, {})
	[[r[0], r[1], r[2]] | some r in _from_rows(rep)] == [[1, "$applies", "satisfied"], [2, "$applies", "value"], [1, "c", "satisfied"]]
}

_releases := {"releases": [
	{"id": "mixed", "files": [{"path": "docs/upgrade.md"}, {"path": "src/api.go"}], "ticket": "ok"},
	{"id": "docs", "files": [{"path": "docs/upgrade.md"}], "ticket": "ok"},
	{"id": "none", "files": [], "ticket": "ok"},
	{"id": "unset", "ticket": "ok"},
	{"id": "null", "files": null, "ticket": "ok"},
	{"id": "text", "files": "docs/upgrade.md", "ticket": "ok"},
	{"id": "gap", "files": [{"path": "docs/upgrade.md"}, {"name": "x"}], "ticket": "ok"},
	{"id": "number", "files": [{"path": "docs/upgrade.md"}, {"path": 5}], "ticket": "ok"},
]}

_release_outcomes(line) := {r[0]: r[2] | some r in _from_rows(_from_report(_releases, {"release": {"from": line, "identified_by": "id"}}, {"c": "ticket exists"}, {})); r[1] == "$applies"}

test_a_from_condition_can_ask_whether_some_item_of_a_list_passes if {
	_release_outcomes(`releases whose some files.path does not match "^docs/"`) == {
		"mixed": "satisfied",
		"docs": "value",
		"none": "value",
		"unset": "absent",
		"null": "null",
		"text": "unusable",
		"gap": "absent",
		"number": "unusable",
	}
}

test_a_from_condition_can_ask_whether_every_item_of_a_list_passes if {
	_release_outcomes(`releases whose every files.path matches "^docs/"`) == {
		"mixed": "value",
		"docs": "satisfied",
		"none": "value",
		"unset": "absent",
		"null": "null",
		"text": "unusable",
		"gap": "absent",
		"number": "unusable",
	}
}

test_a_from_condition_with_every_and_if_any_keeps_a_release_with_no_files_in_scope if {
	_release_outcomes(`releases whose every files.path, if any, matches "^docs/"`) == {
		"mixed": "value",
		"docs": "satisfied",
		"none": "satisfied",
		"unset": "absent",
		"null": "null",
		"text": "unusable",
		"gap": "absent",
		"number": "unusable",
	}
}

test_a_release_the_condition_cannot_decide_fails_its_requirement_and_does_not_drop_out_of_scope if {
	rep := _from_report(_releases, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	rep.requirements.r.status == "not_met"
	{c.cause | some c in rep.requirements.r.causes; c.cause != "value"} == {"absent", "null", "unusable"}
}

test_the_applies_row_of_a_some_condition_reads_the_same_inputs_and_causes_as_the_same_sentence_as_a_check if {
	sentence := `some files.path does not match "^docs/"`
	as_condition := _from_report(_releases, {"release": {"from": concat(" whose ", ["releases", sentence]), "identified_by": "id"}}, {"c": "ticket exists"}, {})
	as_check := _from_report(_releases, {"release": {"from": "releases", "identified_by": "id"}}, {"c": sentence}, {})
	condition_rows := {r.subject.id: [r.cause, r.inputs] | some r in as_condition.results; r.check == "$applies"}
	check_rows := {r.subject.id: [r.cause, r.inputs] | some r in as_check.results; r.check == "c"}
	condition_rows == check_rows
	as_condition.requirements.r.checks["$applies"].expression == sentence
}

_applies_failures_of(rep) := {r.subject.id: object.filter(r, ["failed_items", "failed_assertions"]) | some r in rep.results; r.check == "$applies"}

_check_failures_of(rep) := {r.subject.id: object.filter(r, ["failed_items", "failed_assertions"]) | some r in rep.results; r.check == "c"}

_as_condition_and_as_check(sentences) := [
	_from_report(_releases, {"release": {"from": concat(" whose ", ["releases", concat(" and ", sentences)]), "identified_by": "id"}}, {"c": "ticket exists"}, {}),
	_from_report(_releases, {"release": {"from": "releases", "identified_by": "id"}}, {"c": {"assert": sentences}}, {}),
]

test_the_applies_row_of_a_some_or_every_condition_lists_the_failed_items_its_check_row_lists if {
	every sentence in [`some files.path does not match "^docs/"`, `every files.path matches "^docs/"`, `every files.path, if any, matches "^docs/"`] {
		both := _as_condition_and_as_check([sentence])
		_applies_failures_of(both[0]) == _check_failures_of(both[1])
	}
	rows := _applies_failures_of(_from_report(_releases, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {}))
	rows.mixed == {"failed_items": []}
	rows.docs.failed_items != []
	not "failed_assertions" in object.keys(rows.docs)
}

test_the_applies_row_of_several_conditions_lists_the_failed_assertions_its_check_row_lists_and_no_failed_items if {
	every sentences in [
		[`ticket is "ok"`, `some files.path does not match "^docs/"`],
		[`some files.path does not match "^docs/"`, `ticket is "ok"`],
		[`ticket is "open"`, `every files.path matches "^docs/"`],
		[`ticket is "ok"`, `ticket is "open"`, `ticket exists`],
	] {
		both := _as_condition_and_as_check(sentences)
		_applies_failures_of(both[0]) == _check_failures_of(both[1])
		every _, row in _applies_failures_of(both[0]) {
			object.keys(row) == {"failed_assertions"}
		}
	}
	rows := _applies_failures_of(_from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and every files.path matches "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {}))
	rows.docs == {"failed_assertions": []}
	rows.mixed.failed_assertions == [{"assertion": `every files.path matches "^docs/"`, "cause": "value"}]
	rows.unset.failed_assertions == [{"assertion": `every files.path matches "^docs/"`, "cause": "absent"}]
}

test_the_applies_row_of_a_plain_condition_has_no_more_fields_than_the_check_row_of_the_same_sentence if {
	every sentence in [`ticket is "ok"`, `ticket is "open"`, `ticket exists`, `count of files is at least 2`, `sum of files.size is at least 2`] {
		both := _as_condition_and_as_check([sentence])
		every _, row in _applies_failures_of(both[0]) {
			row == {}
		}
		_applies_failures_of(both[0]) == _check_failures_of(both[1])
	}
}

test_the_applies_row_of_a_some_condition_whose_param_cant_be_used_fails_as_unusable_with_no_failed_items_like_its_check_row if {
	sentence := `some files.path matches $params.pattern`
	as_condition := _from_report(_releases, {"release": {"from": concat(" whose ", ["releases", sentence]), "identified_by": "id"}}, {"c": "ticket exists"}, {"pattern": 5})
	as_check := _from_report(_releases, {"release": {"from": "releases", "identified_by": "id"}}, {"c": sentence}, {"pattern": 5})
	_applies_failures_of(as_condition) == _check_failures_of(as_check)
	every _, row in _applies_failures_of(as_condition) {
		row == {"failed_items": []}
	}
	{[r.passed, r.cause] | some r in as_condition.results; r.check == "$applies"} == {[false, "unusable"]}
}

test_an_applies_row_that_fails_with_a_cause_other_than_value_is_a_violation_with_the_failed_items_or_assertions if {
	some_rep := _from_report(_releases, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	some_violations := {v.subject.id: object.filter(v, ["failed_items", "failed_assertions"]) | some v in ergo.violations(some_rep); v.check == "$applies"}
	some_violations.unset == {"failed_items": [{"path": "files", "item": "files", "cause": "absent", "value": null, "locations": ["/releases/3"]}]}
	some_violations.null.failed_items[0].cause == "null"
	not "mixed" in object.keys(some_violations)
	not "docs" in object.keys(some_violations)
	many_rep := _from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and every files.path matches "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	many_violations := {v.subject.id: object.filter(v, ["failed_items", "failed_assertions"]) | some v in ergo.violations(many_rep); v.check == "$applies"}
	many_violations.unset == {"failed_assertions": [{"assertion": `every files.path matches "^docs/"`, "cause": "absent"}]}
	not "mixed" in object.keys(many_violations)
}

test_a_failed_item_of_an_applies_row_says_where_its_value_was_read_in_the_input_of_its_own_subject if {
	doc := {"releases": [
		{"id": "a", "files": [{"path": "docs/x.md"}, {"path": "src/y.go"}]},
		{"id": "b", "files": [{"path": "docs/x.md"}, {"name": "z"}]},
	]}
	some_rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in some_rep.results; r.check == "$applies"} == {
		"a": [],
		"b": [
			{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/x.md", "locations": ["/releases/1/files/0/path"]},
			{"path": "files[1].path", "item": "item 2 of files", "cause": "absent", "value": null, "locations": ["/releases/1/files/1"]},
		],
	}
	every_rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": {"release": {"from": `releases whose every files.path matches "^docs/"`, "identified_by": "id"}}, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in every_rep.results; r.check == "$applies"} == {
		"a": [{"path": "files[1].path", "item": "item 2 of files", "cause": "value", "value": "src/y.go", "locations": ["/releases/0/files/1/path"]}],
		"b": [{"path": "files[1].path", "item": "item 2 of files", "cause": "absent", "value": null, "locations": ["/releases/1/files/1"]}],
	}
	{r.subject.id: r.inputs | some r in every_rep.results; r.check == "$applies"} == {
		"a": [{"name": "files[].path", "value": ["docs/x.md", "src/y.go"], "locations": ["/releases/0/files/0/path", "/releases/0/files/1/path"]}],
		"b": [{"name": "files[].path", "value": ["docs/x.md", null], "locations": ["/releases/1/files/0/path", "/releases/1/files/1"]}],
	}
	not contains(json.marshal(every_rep), "~~")
}

test_an_applies_row_of_a_child_subject_and_of_a_subject_that_reads_its_parent_has_the_same_fields if {
	doc := {"artifact": {"id": "sha", "owner": "ann", "releases": [{"id": 1, "files": [{"owner": "ann"}]}, {"id": 2, "files": [{"owner": "bob"}]}]}}
	subjects := {"artifact": {"identified_by": "id"}, "release": {"from": "artifact.releases whose some files.owner is artifact.owner and id exists", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_assertions | some r in rep.results; r.check == "$applies"} == {1: [], 2: [{"assertion": "some files.owner equals artifact.owner", "cause": "value"}]}
	single := {"artifact": {"identified_by": "id"}, "release": {"from": "artifact.releases whose some files.owner is artifact.owner", "identified_by": "id"}}
	one := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": single, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in one.results; r.check == "$applies"} == {1: [], 2: [{"path": "files[0].owner", "item": "item 1 of files", "cause": "value", "value": "bob", "locations": ["/artifact/releases/1/files/0/owner"]}]}
	chain := {"releases": {"from": "releases", "identified_by": "id"}, "source": {"from": `releases whose some files.path does not match "^docs/"`}}
	cdoc := {"releases": [{"id": 3, "files": [{"path": "a.go"}]}, {"id": 4, "files": [{"path": "docs/a"}]}]}
	crep := ergo.report(cdoc, {"ergo_spec": "v0.3-dev", "subjects": chain, "requirements": {"r": {"subject": "source", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: count(r.failed_items) | some r in crep.results; r.check == "$applies"} == {3: 0, 4: 1}
}

test_a_from_condition_written_with_some_prints_in_the_spelling_of_the_report_and_joins_with_and if {
	rep := _from_report(_releases, {"release": {"from": `releases whose some  files.path   matches "x" and ticket   is "ok" and every files.path, if any, does not match "y"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	rep.requirements.r.checks["$applies"].expression == `some files.path matches "x" and ticket is "ok" and every files.path, if any, does not match "y"`
}

test_a_from_condition_with_some_reads_a_bare_name_on_its_right_side_from_the_item if {
	doc := {"releases": [
		{"id": 1, "steward": "bob", "files": [{"owner": "ann", "steward": "ann"}]},
		{"id": 2, "steward": "ann", "files": [{"owner": "ann", "steward": "bob"}]},
		{"id": 3, "steward": "ann", "files": [{"owner": "ann"}]},
	]}
	rep := _from_report(doc, {"release": {"from": "releases whose some files.owner is steward", "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.cause | some r in rep.results; r.check == "$applies"} == {1: "satisfied", 2: "value", 3: "absent"}
}

test_a_from_condition_with_some_reads_a_parent_subject_by_its_name if {
	doc := {"artifact": {"id": "sha", "owner": "ann", "releases": [{"id": 1, "files": [{"owner": "ann"}]}, {"id": 2, "files": [{"owner": "bob"}]}]}}
	subjects := {"artifact": {"identified_by": "id"}, "release": {"from": "artifact.releases whose some files.owner is artifact.owner", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.subject["in"], r.cause] | some r in rep.results; r.check == "$applies"] == [[1, {"artifact": "sha"}, "satisfied"], [2, {"artifact": "sha"}, "value"]]
}

test_a_from_condition_with_some_works_on_every_from_lines_and_narrowing_chains if {
	doc := {"artifacts": [{"releases": [{"id": 1, "files": [{"path": "a.go"}]}, {"id": 2, "files": [{"path": "docs/a"}]}]}], "releases": [{"id": 3, "files": [{"path": "a.go"}]}, {"id": 4, "files": [{"path": "docs/a"}]}]}
	every_rep := _from_report(doc, {"release": {"from": `every artifacts.releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.cause | some r in every_rep.results; r.check == "$applies"} == {1: "satisfied", 2: "value"}
	subjects := {"releases": {"from": "releases", "identified_by": "id"}, "source": {"from": `releases whose some files.path does not match "^docs/"`}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "source", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.cause | some r in rep.results; r.check == "$applies"} == {3: "satisfied", 4: "value"}
}

test_a_from_condition_with_some_walks_every_list_along_its_path if {
	deep := {"x": {"id": 1, "p": [{"q": [{"r": [{"u": 2}, {"u": 1}]}]}]}}
	hit := _from_report(deep, {"x": {"from": "x whose some p.q.r.u is 1"}}, {"c": "id exists"}, {})
	miss := _from_report(deep, {"x": {"from": "x whose some p.q.r.u is 3"}}, {"c": "id exists"}, {})
	[r.cause | some r in hit.results; r.check == "$applies"] == ["satisfied"]
	[r.cause | some r in miss.results; r.check == "$applies"] == ["value"]
}

test_a_from_condition_with_if_any_after_some_or_a_whose_of_its_own_is_written_wrong if {
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files.path, if any, matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["if any can't go with some"], "locations": []}]
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files whose kind is "src" matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and every files whose kind is "src" matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	every line in [`releases whose count of files whose path is "x" is at least 1`, `releases whose sum of files.size whose path is "x" is at least 1`, `releases whose ticket is "ok" and count of files whose path is "x" is at least 1`] {
		_from_problems(_from_report(_releases, {"release": {"from": line}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	}
	_read(`count of files whose path is "x" is at least 1`).assertions[0].where != []
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files.path`}}, {"c": "ticket exists"}, {})) != []
}

test_a_whose_in_a_check_or_a_for_line_still_takes_no_some_or_every_condition if {
	_read(`some a whose some b.c is 1 is 2`) == {"problems": ["doesn't parse"]}
	_read(`every a whose every b.c is 1 is 2`) == {"problems": ["doesn't parse"]}
	_read(`some a whose some b.c is 1`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`every a whose some b.c is 1 as x`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`last of a whose every b.c is 1 as x`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`releases whose some files.path matches "x"`) != {"problems": ["doesn't parse"]}
}

test_a_from_condition_that_cannot_be_turned_back_into_text_is_written_wrong_and_never_dropped if {
	read := ergo._s_from_read("x", {"path": {"steps": ["xs"]}, "where": [{"nonsense": true, "phrase": {"op": "is", "value": 1}}]}, {"x": {"from": "xs"}}, {"parts": {}, "descend": {}, "narrow": {}})
	"whose: a condition can't be read" in read.problems
}

test_a_from_or_id_written_wrong_says_why_in_well_formed if {
	every pair in [
		[{"from": "xs whose"}, {"name": "subjects.x.from", "value": ["doesn't parse"], "locations": []}],
		[{"from": "xs whose last of ys is 1"}, {"name": "subjects.x.from", "value": ["whose: last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""], "locations": []}],
		[{"from": "xs whose a is 1"}, {"name": "subjects.x.from", "value": ["a is a word of the grammar: write .a"], "locations": []}],
		[{"from": "xs", "identified_by": "id is 1"}, {"name": "subjects.x.identified_by", "value": [`identified_by is a path, like "id" or "build.number"`], "locations": []}],
		[{"from": "xs whose id exists", "applies_to": {"a": {"op": "present", "path": ["id"]}}}, {"name": "subjects.x.applies_to", "value": ["unknown field"], "locations": []}],
	] {
		_from_problems(_from_report({"xs": [{"id": 1}]}, {"x": pair[0]}, {"c": "id exists"}, {})) == [pair[1]]
	}
}

test_a_subjects_own_name_in_its_own_from_is_the_input_field if {
	own := ergo.report({"lockfile": {"status": "COMPLETE"}}, {"ergo_spec": "v0.3-dev", "subjects": {"lockfile": {"from": `lockfile whose status is "COMPLETE"`}}, "requirements": {"r": {"subject": "lockfile", "checks": {"c": "status exists"}}}}, {})
	_from_problems(own) == []
	[r.cause | some r in own.results; r.check == "c"] == ["satisfied"]
}

_chain_doc := {"trail": {"artifacts": {
	"web": {"fingerprint": "sha-1", "name": "web", "pull_requests": [{"url": "pr/7", "approved": true}, {"url": "pr/8", "approved": false}]},
	"api": {"fingerprint": "sha-2", "name": "api", "pull_requests": []},
}}}

_chain_subjects := {
	"artifact": {"from": "trail.artifacts named by $params.name", "identified_by": "fingerprint"},
	"pull request": {"from": "artifact.pull_requests", "identified_by": "url"},
}

_chain_report(doc, subjects, checks, params) := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, params)

test_a_chain_names_its_parent_in_the_expressions_of_the_checks_ergo_adds_as_its_from_line_does if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	[rep.requirements.r.checks["$min_subjects"].expression, rep.requirements.r.checks["$unique_ids"].expression] == [
		"count(matching(artifact.pull_requests)) >= 1",
		"count(repeated(ids(artifact.pull_requests))) == 0",
	]
	quoted := {"locked thing": {"from": "trail.artifacts named by $params.name"}, "pull request": {"from": `"locked thing".pull_requests`, "identified_by": "url"}}
	_chain_report(_chain_doc, quoted, {"c": "approved is true"}, {"name": "web"}).requirements.r.checks["$min_subjects"].expression == `count(matching("locked thing".pull_requests)) >= 1`
}

test_a_chain_reads_its_path_from_the_parents_one_subject_and_every_row_but_well_formed_says_which if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	[[r.subject, r.check, r.cause] | some r in rep.results] == [
		[{"type": "pull request", "id": null}, "$well_formed", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$min_subjects", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$unique_ids", "satisfied"],
		[{"type": "pull request", "id": "pr/7", "in": {"artifact": "sha-1"}}, "c", "satisfied"],
		[{"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "c", "value"],
	]
}

test_a_check_of_a_chain_reads_the_parent_by_its_name if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": `artifact.name is "web" and url exists`}, {"name": "web"})
	[[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "c"] == [
		["pr/7", "satisfied", [{"name": "artifact.name", "value": "web", "locations": ["/trail/artifacts/web/name"]}, {"name": "url", "value": "pr/7", "locations": ["/trail/artifacts/web/pull_requests/0/url"]}]],
		["pr/8", "satisfied", [{"name": "artifact.name", "value": "web", "locations": ["/trail/artifacts/web/name"]}, {"name": "url", "value": "pr/8", "locations": ["/trail/artifacts/web/pull_requests/1/url"]}]],
	]
}

_owner_doc := {"artifact": {"name": "a1", "owner": "ann", "pull_requests": [{"id": 1, "commits": [{"author": "bob", "n": 1}, {"author": "ann", "n": 2}]}]}}

_owner_subjects := {"artifact": {"identified_by": "name"}, "pr": {"from": "artifact.pull_requests", "identified_by": "id"}}

_owner_input := {"name": "artifact.owner", "value": "ann", "locations": ["/artifact/owner"]}

_owner_authors := {"name": "commits[].author", "value": ["bob", "ann"], "locations": ["/artifact/pull_requests/0/commits/0/author", "/artifact/pull_requests/0/commits/1/author"]}

_owner_rows(checks) := {r.check: r.inputs |
	some r in ergo.report(_owner_doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	r.check in object.keys(checks)
}

test_a_one_line_some_or_every_lists_the_parent_it_reads_on_the_right_side if {
	_owner_rows({"some": "some commits.author is artifact.owner", "every": "every commits.author, if any, is artifact.owner"}) == {
		"some": [_owner_input, _owner_authors],
		"every": [_owner_input, _owner_authors],
	}
}

test_a_one_line_some_lists_the_parent_its_whose_reads if {
	_owner_rows({"c": "some commits.n whose author is artifact.owner is 2"}) == {"c": [
		_owner_input,
		{"name": "commits[].n", "value": [1, 2], "locations": ["/artifact/pull_requests/0/commits/0/n", "/artifact/pull_requests/0/commits/1/n"]},
	]}
}

test_a_count_or_a_sum_lists_the_parent_its_whose_reads if {
	commits := [{"author": "bob", "n": 1}, {"author": "ann", "n": 2}]
	at := ["/artifact/pull_requests/0/commits/0", "/artifact/pull_requests/0/commits/1"]
	ns := ["/artifact/pull_requests/0/commits/0/n", "/artifact/pull_requests/0/commits/1/n"]
	_owner_rows({"count": "count of commits whose author is artifact.owner is 1", "sum": "sum of commits.n whose author is artifact.owner is 2"}) == {
		"count": [
			{"name": "count of commits whose author equals artifact.owner", "value": 1, "locations": at},
			{"name": "commits[]", "value": commits, "locations": at},
			_owner_input,
		],
		"sum": [
			{"name": "sum of commits.n whose author equals artifact.owner", "value": 2, "locations": ns},
			{"name": "commits[].n", "value": [1, 2], "locations": ns},
			_owner_input,
		],
	}
}

test_a_one_line_some_after_a_for_line_lists_the_parent_it_reads if {
	commits := {"name": "commits[]", "value": [{"author": "bob", "n": 1}, {"author": "ann", "n": 2}], "locations": ["/artifact/pull_requests/0/commits/0", "/artifact/pull_requests/0/commits/1"]}
	doc := object.union(_owner_doc, {"artifact": {"tags": ["x", "ann"]}})
	checks := {
		"right": {"for": "every commits as c", "assert": "some artifact.tags is c.author"},
		"left": {"for": "every commits as c", "assert": "c.author is artifact.owner and some artifact.tags is \"x\""},
	}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	tags := {"name": "artifact.tags[]", "value": ["x", "ann"], "locations": ["/artifact/tags/0", "/artifact/tags/1"]}
	{r.check: r.inputs | some r in rep.results; r.check in {"right", "left"}} == {
		"right": [tags, commits],
		"left": [_owner_input, tags, commits],
	}
}

test_a_walk_from_a_for_alias_lists_the_parent_it_compares_with if {
	doc := object.union(_owner_doc, {"artifact": {"pull_requests": [{"id": 1, "commits": [{"author": "bob", "n": 1, "reviewers": ["ann"]}, {"author": "ann", "n": 2, "reviewers": ["cid"]}]}]}})
	checks := {"c": {"for": "every commits as c", "assert": "some c.reviewers is artifact.owner"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[r.cause, [i.name | some i in r.inputs]] | some r in rep.results; r.check == "c"] == [["value", ["artifact.owner", "commits[]"]]]
}

test_a_one_line_some_lists_an_input_value_it_compares_with_but_not_a_param if {
	_owner_rows({"input": "some commits.author is $input.artifact.owner", "param": "some commits.author is $params.owner"}) == {
		"input": [{"name": "$input.artifact.owner", "value": "ann", "locations": ["/artifact/owner"]}, _owner_authors],
		"param": [_owner_authors],
	}
}

test_a_one_line_some_lists_a_missing_or_null_parent_value_as_a_plain_assertion_does if {
	doc := object.union(_owner_doc, {"artifact": {"nul": null}})
	checks := {"missing": "some commits.author is artifact.nope", "null": "some commits.author is artifact.nul"}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	{r.check: [r.cause, r.inputs] | some r in rep.results; r.check in {"missing", "null"}} == {
		"missing": ["absent", [{"name": "artifact.nope", "value": null, "locations": ["/artifact"]}, _owner_authors]],
		"null": ["null", [{"name": "artifact.nul", "value": null, "locations": ["/artifact/nul"]}, _owner_authors]],
	}
}

test_a_parent_read_by_a_walk_and_by_a_plain_assertion_is_listed_once if {
	_owner_rows({"c": `some commits.author is artifact.owner and artifact.owner is "ann"`}) == {"c": [_owner_input, _owner_authors]}
}

test_the_applies_row_of_a_from_condition_with_some_lists_the_parent_it_reads if {
	subjects := object.union(_owner_subjects, {"pr": {"from": "artifact.pull_requests whose some commits.author is artifact.owner", "identified_by": "id"}})
	rep := ergo.report(_owner_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id exists"}}}}, {})
	_applies_of(rep) == [[1, "satisfied", [_owner_input, _owner_authors]]]
}

test_a_walk_named_by_a_parent_path_lists_the_same_entry_as_the_plain_form if {
	doc := object.union(_owner_doc, {"artifact": {"key": "k1", "map": {"k1": "ann"}}})
	checks := {"walk": "some commits.author is artifact.map named by artifact.key", "plain": "author is artifact.map named by artifact.key"}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	rows := {r.check: r.inputs | some r in rep.results; r.check in object.keys(checks)}
	entry := [i | some i in rows.plain; i.name == "artifact.map named by artifact.key"]
	entry == [i | some i in rows.walk; i.name == "artifact.map named by artifact.key"]
	count(entry) == 1
	not "artifact.map" in {i.name | some i in rows.walk}
}

test_a_count_under_a_for_line_whose_whose_reads_a_parent_lists_it_when_the_path_starts_at_the_alias if {
	doc := object.union(_owner_doc, {"artifact": {"pull_requests": [{"id": 1, "commits": [{"author": "bob", "revs": [{"n": "ann"}]}, {"author": "ann", "revs": [{"n": "x"}]}]}]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of c.revs whose n is artifact.owner is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.owner", "commits[]"]]
}

test_a_count_under_a_for_line_lists_its_list_when_its_whose_reads_the_alias if {
	doc := object.union(_owner_doc, {"artifact": {"people": [{"r": "ann"}, {"r": "bob"}]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of artifact.people whose r is c.author is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.people[]", "commits[]"]]
}

test_a_count_under_a_for_line_lists_its_list_and_its_number_when_they_dont_change_per_item if {
	doc := object.union(_owner_doc, {"artifact": {"tags": ["t"]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of artifact.tags is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

_add_rows(assert) := [[i.name | some i in r.inputs] |
	some r in ergo.report(
		{"artifacts": [{"name": "a1", "tags": [{"x": "bob"}], "pull_requests": [{"id": 1, "commits": [{"author": "bob", "revs": [1]}]}]}]},
		{"ergo_spec": "v0.3-dev", "subjects": {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.pull_requests", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": "every commits as c", "assert": assert}}}}},
		{},
	).results
	r.check == "c"
]

test_an_add_under_a_for_line_lists_the_number_of_the_operand_that_doesnt_read_the_alias if {
	_add_rows("count of artifact.tags plus count of artifact.tags whose x is c.author is at least 1") == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

test_an_add_under_a_for_line_lists_the_number_of_the_second_operand_when_the_first_reads_the_alias_in_its_path if {
	_add_rows("count of c.revs plus count of artifact.tags is at least 1") == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

_part_subjects := object.union(_owner_subjects, {"pr": {"from": "artifact.pull_requests", "identified_by": "id", "has": {"w": "info.who"}}})

_part_doc := {"artifact": {"name": "a1", "pull_requests": [{"id": 1, "info": {"who": "ann"}, "commits": [{"author": "bob", "revs": [{"n": "ann"}]}, {"author": "ann", "revs": [{"n": "x"}]}]}]}}

_part_rows(checks) := {r.check: [[i.name, object.get(i, "part", null)] | some i in r.inputs] |
	some r in ergo.report(_part_doc, {"ergo_spec": "v0.3-dev", "subjects": _part_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	r.check in object.keys(checks)
}

test_a_walk_lists_the_subjects_own_part_it_compares_with_as_a_plain_assertion_does if {
	rows := _part_rows({
		"walk": "some commits.author is w",
		"count": "count of commits whose author is w is 1",
		"for": {"for": "every commits as c", "assert": "some c.revs.n is w"},
		"forcount": {"for": "every commits as c", "assert": "count of c.revs whose n is w is at least 0"},
	})
	own := ["w", {"id": null, "name": "w"}]
	own in rows.walk
	own in rows.count
	own in rows.for
	own in rows.forcount
}

test_a_dotted_name_on_the_right_of_a_walk_is_the_items_field_and_isnt_the_subjects_part if {
	doc := {"artifact": {"name": "a1", "pull_requests": [{"id": 1, "info": {"who": "ann"}, "commits": [{"author": "bob", "w": "ann"}]}]}}
	checks := {"dot": "some commits.author is .w", "part": "some commits.author is w"}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _part_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	rows := {r.check: [i.name | some i in r.inputs] | some r in rep.results; r.check in object.keys(checks)}
	rows == {"dot": ["commits[].author"], "part": ["commits[].author", "w"]}
}

test_the_applies_row_of_a_from_condition_lists_the_subjects_own_part_it_compares_with if {
	subjects := object.union(_part_subjects, {"pr": {"from": "artifact.pull_requests whose some commits.author is w", "identified_by": "id", "has": {"w": "info.who"}}})
	rep := ergo.report(_part_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id is 1"}}}}, {})
	["w", {"id": null, "name": "w"}] in [[i.name, object.get(i, "part", null)] | some r in rep.results; r.check == "$applies"; some i in r.inputs]
}

_atts_doc := {"artifacts": [{"name": "a1", "owner": "ann", "team": {"lead": "ann"}, "atts": {"x": {"owner": "ann"}, "y": {"owner": "zed"}}, "pull_requests": [{"id": 1, "commits": [{"author": "bob", "k": "x"}, {"author": "zed", "k": "y"}], "files": [{"k": "x"}, {"k": "y"}]}]}]}

_atts_subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.pull_requests", "identified_by": "id"}}

_atts_rows(checks, params) := {r.check: [i.name | some i in r.inputs] |
	some r in ergo.report(_atts_doc, {"ergo_spec": "v0.3-dev", "subjects": _atts_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, params).results
	r.check in object.keys(checks)
}

test_a_walk_whose_named_by_reads_the_item_lists_the_part_before_the_name_and_not_the_path_it_names if {
	_atts_rows({"item": "some commits.author is artifact.atts named by k.owner", "param": "some commits.author is artifact.atts named by $params.n.owner"}, {"n": "x"}) == {
		"item": ["artifact.atts", "commits[].author"],
		"param": ["artifact.atts named by $params.n.owner", "commits[].author"],
	}
}

test_a_count_whose_named_by_reads_the_item_lists_the_part_before_the_name_and_not_the_path_it_names if {
	_atts_rows({"c": "count of commits whose author is artifact.atts named by k.owner is 1"}, {}) == {"c": [
		"count of commits whose author equals artifact.atts named by k.owner",
		"commits[]",
		"artifact.atts",
	]}
}

test_a_for_line_walk_named_by_the_item_or_the_alias_lists_the_part_before_the_name_and_not_the_path_it_names if {
	checks := {
		"item": {"for": "every files as f", "assert": "some commits.author is artifact.atts named by k.owner"},
		"alias": {"for": "every files as f", "assert": "some commits.author is artifact.atts named by f.k.owner"},
	}
	_atts_rows(checks, {}) == {"item": ["artifact.atts", "commits[].author", "files[]"], "alias": ["artifact.atts", "commits[].author", "files[]"]}
}

test_the_applies_row_of_a_from_condition_named_by_the_item_lists_the_part_before_the_name_and_not_the_path_it_names if {
	subjects := object.union(_atts_subjects, {"pr": {"from": "artifact.pull_requests whose some commits.author is artifact.atts named by k.owner", "identified_by": "id"}})
	rep := ergo.report(_atts_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id exists"}}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "$applies"] == [["artifact.atts", "commits[].author"]]
}

test_a_count_under_a_for_line_still_lists_the_parent_it_reads if {
	checks := {
		"parent": {"for": "every files as f", "assert": "count of commits whose author is artifact.owner is 1"},
		"plain": {"for": "every files as f", "assert": "count of commits whose author is \"zed\" is 1"},
	}
	_atts_rows(checks, {}) == {
		"parent": ["artifact.owner", "commits[]", "count of commits whose author equals artifact.owner", "files[]"],
		"plain": ["commits[]", "count of commits whose author is \"zed\"", "files[]"],
	}
}

test_a_count_whose_parents_are_written_in_either_order_lists_them_in_the_same_order if {
	rows := _atts_rows(
		{
			"a": "count of commits whose author is artifact.team.lead and author is artifact.owner is 1",
			"b": "count of commits whose author is artifact.owner and author is artifact.team.lead is 1",
		},
		{},
	)
	array.slice(rows.a, 1, 4) == ["commits[]", "artifact.owner", "artifact.team.lead"]
	array.slice(rows.b, 1, 4) == ["commits[]", "artifact.owner", "artifact.team.lead"]
}

_kids_doc := {"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "v": 1}, {"id": "k2", "v": 2}]}]}

_kids_report(from) := ergo.report(_kids_doc, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": from, "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})

_applies_of(rep) := [[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"]

test_a_whose_in_a_childs_from_line_reads_the_parent_by_its_name if {
	_applies_of(_kids_report("b.kids whose v equals b.x")) == [
		["k1", "satisfied", [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "value", [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_the_parents_name_on_the_left_of_a_whose_in_a_childs_from_line_is_the_childs_own_field if {
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 2}, "v": 2}, {"id": "k2", "v": 1}]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids whose b.x equals v", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": "b.x", "value": 2, "locations": ["/bs/0/kids/0/b/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "absent", [{"name": "b.x", "value": null, "locations": ["/bs/0/kids/1"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/1/v"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == ".b.x equals v"
}

test_a_dot_before_the_parents_name_in_a_childs_from_line_reads_the_childs_own_field if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "b": 1}, {"id": "k2", "b": 5}]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids whose .b equals 1", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "b exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": "b", "value": 1, "locations": ["/bs/0/kids/0/b"]}]],
		["k2", "value", [{"name": "b", "value": 5, "locations": ["/bs/0/kids/1/b"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == ".b is 1"
}

test_a_whose_in_a_childs_from_line_reads_a_part_of_the_parent_by_its_name if {
	doc := {"bs": [{"id": "b1", "meta": {"tag": {"id": "t1", "x": 1}}, "kids": [{"id": "k1", "v": 1}, {"id": "k2", "v": 2}]}]}
	subjects := {"b": {"from": "bs", "identified_by": "id", "has": {"tag": {"from": "meta.tag", "identified_by": "id"}}}, "kid": {"from": "b.kids whose v equals b.tag.x", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": "b.tag.x", "value": 1, "part": {"name": "b.tag", "id": "t1"}, "locations": ["/bs/0/meta/tag/x"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "value", [{"name": "b.tag.x", "value": 1, "part": {"name": "b.tag", "id": "t1"}, "locations": ["/bs/0/meta/tag/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_a_count_on_the_left_of_a_whose_in_a_check_reads_the_items_own_field_not_the_parent if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "items": [{"b": {"kids": [1, 2, 3]}, "v": 3}, {"b": {"kids": []}, "v": 1}]}]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "every items.v whose count of b.kids is at least v is 3"}}}}, {})
	[r.cause | some r in rep.results; r.check == "c"] == ["satisfied"]
}

test_a_count_on_the_left_of_a_whose_in_a_childs_from_line_reads_the_childs_own_field_not_the_parent if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "b": {"kids": [1, 2]}, "v": 2}, {"id": "k2", "v": 1}]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids whose count of b.kids is at least v", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "$applies"] == [["k1", "satisfied"], ["k2", "absent"]]
	rep.requirements.r.checks["$applies"].expression == "count of .b.kids is at least v"
}

test_a_dot_before_a_part_on_the_left_of_a_whose_in_a_from_line_reads_the_field_not_the_part if {
	doc := {"kids": [{"id": "k1", "att": {"id": 1}, "atts": {"pr": {"id": 2}}}, {"id": "k2", "atts": {"pr": {"id": 1}}}]}
	subjects := {"kid": {"from": "kids whose .att.id is 1", "identified_by": "id", "has": {"att": {"from": "atts.pr", "identified_by": "id"}}}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "$applies"] == [["k1", "satisfied"], ["k2", "absent"]]
	plain := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": object.union(subjects, {"kid": object.union(subjects.kid, {"from": "kids whose att.id is 1"})}), "requirements": {"r": {"subject": "kid", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in plain.results; r.check == "$applies"] == [["k1", "value"], ["k2", "satisfied"]]
}

test_a_whose_in_a_childs_from_line_that_reads_a_missing_field_of_the_parent_fails_as_absent if {
	_applies_of(_kids_report("b.kids whose v equals b.nope")) == [
		["k1", "absent", [{"name": "b.nope", "value": null, "locations": ["/bs/0"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "absent", [{"name": "b.nope", "value": null, "locations": ["/bs/0"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_a_whose_in_the_from_lines_of_a_chain_of_three_subjects_reads_every_ancestor_by_its_name if {
	doc := {"tops": [{"id": "t1", "y": 2, "bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "v": 1, "w": 2}, {"id": "k2", "v": 2, "w": 2}]}, {"id": "b2", "x": 3, "kids": [{"id": "k3", "v": 3, "w": 2}]}]}]}
	subjects := {
		"top": {"from": "tops", "identified_by": "id"},
		"b": {"from": "top.bs whose x is less than top.y", "identified_by": "id"},
		"kid": {"from": "b.kids whose w equals top.y and v equals b.x", "identified_by": "id"},
	}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	[[r.subject.id, r.subject.in, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"] == [
		["k1", {"top": "t1", "b": "b1"}, "satisfied", [{"name": "b.x", "value": 1, "locations": ["/tops/0/bs/0/x"]}, {"name": "top.y", "value": 2, "locations": ["/tops/0/y"]}, {"name": "v", "value": 1, "locations": ["/tops/0/bs/0/kids/0/v"]}, {"name": "w", "value": 2, "locations": ["/tops/0/bs/0/kids/0/w"]}]],
		["k2", {"top": "t1", "b": "b1"}, "value", [{"name": "b.x", "value": 1, "locations": ["/tops/0/bs/0/x"]}, {"name": "top.y", "value": 2, "locations": ["/tops/0/y"]}, {"name": "v", "value": 2, "locations": ["/tops/0/bs/0/kids/1/v"]}, {"name": "w", "value": 2, "locations": ["/tops/0/bs/0/kids/1/w"]}]],
	]
}

_chain_min_cause(rep) := [[r.cause, object.keys(r.subject)] | some r in rep.results; r.check == "$min_subjects"]

test_a_chain_with_no_parent_or_an_unreadable_one_finds_no_subjects if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "api"})) == [["value", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "nope"})) == [["absent", {"type", "id"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, _kept_subjects, {"c": "url exists"}, {})) == [["value", {"type", "id"}]]
	zero := _chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, _kept_subjects, {"c": "url exists"}, {})
	zero.requirements.r.status == "not_met"
}

test_a_child_under_a_parent_that_is_not_an_object_fails_min_subjects_as_not_an_object if {
	every parent in ["x", 5, [1], true, null] {
		_chain_min_cause(_chain_report({"trail": {"artifacts": [parent]}}, _plain_chain, {"c": "url exists"}, {})) == [["not_an_object", {"type", "id", "in"}]]
	}
}

test_a_child_under_an_object_parent_without_the_field_still_fails_min_subjects_as_absent if {
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a"}]}}, _plain_chain, {"c": "url exists"}, {})) == [["absent", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "pull_requests": null}]}}, _plain_chain, {"c": "url exists"}, {})) == [["null", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "pull_requests": "x"}]}}, _plain_chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id", "in"}]]
}

test_a_child_from_that_starts_with_a_position_reads_its_parent_as_a_list if {
	chain := object.union(_plain_chain, {"pull request": {"from": "artifact[0].pull_requests", "identified_by": "url"}})
	_chain_min_cause(_chain_report({"trail": {"artifacts": ["x"]}}, chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [null]}}, chain, {"c": "url exists"}, {})) == [["absent", {"type", "id", "in"}]]
}

test_a_top_level_subject_read_from_an_input_that_is_not_an_object_keeps_its_cause if {
	_chain_min_cause(_chain_report("x", _plain_chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id"}]]
	_chain_min_cause(_chain_report(null, _plain_chain, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
}

_plain_chain := {"artifact": {"from": "trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}

_kept_subjects := {"artifact": {"from": `trail.artifacts whose env is "prod"`, "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}

_many_doc := {"trail": {"artifacts": [
	{"fingerprint": "a", "env": "prod", "pull_requests": [{"url": "pr/7", "ok": true}, {"url": "pr/8", "ok": false}]},
	{"fingerprint": "b", "env": "prod", "pull_requests": [{"url": "pr/7", "ok": true}]},
]}}

_rows_of(rep) := [[r.check, r.subject, r.cause] | some r in rep.results]

test_a_chain_from_several_parents_checks_the_subjects_of_each_and_every_row_but_well_formed_says_which if {
	rep := _chain_report(_many_doc, _kept_subjects, {"c": "ok is true"}, {})
	_rows_of(rep) == [
		["$well_formed", {"type": "pull request", "id": null}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "b"}}, "satisfied"],
		["$unique_ids", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["$unique_ids", {"type": "pull request", "id": null, "in": {"artifact": "b"}}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "a"}}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/8", "in": {"artifact": "a"}}, "value"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "b"}}, "satisfied"],
	]
	rep.requirements.r.subjects == {"total": 3, "matching": 3}
	rep.requirements.r.status == "not_met"
}

test_a_chain_from_several_parents_reads_each_parent_by_its_name if {
	rep := _chain_report(_many_doc, _kept_subjects, {"c": "artifact.fingerprint exists"}, {})
	[[r.subject.in.artifact, r.inputs] | some r in rep.results; r.check == "c"] == [
		["a", [{"name": "artifact.fingerprint", "value": "a", "locations": ["/trail/artifacts/0/fingerprint"]}]],
		["a", [{"name": "artifact.fingerprint", "value": "a", "locations": ["/trail/artifacts/0/fingerprint"]}]],
		["b", [{"name": "artifact.fingerprint", "value": "b", "locations": ["/trail/artifacts/1/fingerprint"]}]],
	]
	rep.requirements.r.status == "met"
}

test_a_parent_without_subjects_fails_min_subjects_on_its_own_row_unless_min_subjects_is_zero if {
	doc := {"trail": {"artifacts": [{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}]}, {"fingerprint": "b", "pull_requests": []}]}}
	subjects := {"artifact": {"from": "trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
	rep := _chain_report(doc, subjects, {"c": "url exists"}, {})
	[[r.subject.in, r.passed, r.cause, r.inputs] | some r in rep.results; r.check == "$min_subjects"] == [
		[{"artifact": "a"}, true, "satisfied", [{"name": "in-scope pull request count", "value": 1, "locations": ["/trail/artifacts/0/pull_requests/0"]}]],
		[{"artifact": "b"}, false, "value", [{"name": "in-scope pull request count", "value": 0, "locations": []}]],
	]
	rep.requirements.r.status == "not_met"
	zero := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	[r.passed | some r in zero.results; r.check == "$min_subjects"] == [true, true]
	zero.requirements.r.status == "met"
}

test_ids_of_a_chain_from_several_parents_are_unique_within_each_parent if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}, {"url": "pr/7"}]},
		{"fingerprint": "b", "pull_requests": [{"url": "pr/7"}]},
	]}}
	subjects := {"artifact": {"from": "trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
	rep := _chain_report(doc, subjects, {"c": "url exists"}, {})
	[[r.subject.in, r.cause, r.inputs] | some r in rep.results; r.check == "$unique_ids"] == [
		[{"artifact": "a"}, "value", [{"name": "repeated pull request ids", "value": ["pr/7"], "locations": ["/trail/artifacts/0/pull_requests/0/url", "/trail/artifacts/0/pull_requests/1/url"]}]],
		[{"artifact": "b"}, "satisfied", [{"name": "repeated pull request ids", "value": [], "locations": []}]],
	]
	rep.requirements.r.status == "not_met"
}

test_a_parent_its_own_conditions_leave_out_gives_no_rows_even_with_repeated_ids if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "env": "prod", "pull_requests": [{"url": "pr/7"}]},
		{"fingerprint": "b", "env": "dev", "pull_requests": [{"url": "pr/9"}, {"url": "pr/9"}]},
		{"fingerprint": "c", "env": "dev", "pull_requests": []},
	]}}
	rep := _chain_report(doc, _kept_subjects, {"c": "url exists"}, {})
	{r.subject.in.artifact | some r in rep.results; "in" in object.keys(r.subject)} == {"a"}
	rep.requirements.r.status == "met"
}

test_a_parent_whose_conditions_cant_be_decided_fails_min_subjects_on_its_row_and_its_subjects_are_not_checked if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "env": "prod", "pull_requests": [{"url": "pr/7"}]},
		{"fingerprint": "b", "pull_requests": [{"url": "pr/8"}, {"url": "pr/8"}]},
	]}}
	rep := _chain_report(doc, _kept_subjects, {"c": "url exists"}, {})
	_rows_of(rep) == [
		["$well_formed", {"type": "pull request", "id": null}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "b"}}, "absent"],
		["$unique_ids", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "a"}}, "satisfied"],
	]
	rep.requirements.r.status == "not_met"
	rep.requirements.r.causes == [{"cause": "absent", "rows": 1}]
	zero := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _kept_subjects, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	zero.requirements.r.status == "not_met"
}

test_a_chain_from_several_parents_reads_each_parents_part_with_its_own_id if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "atts": {"pr": {"id": "att-1", "pull_requests": [{"url": "pr/7", "by": "ann"}]}}},
		{"fingerprint": "b", "atts": {"pr": {"id": "att-2", "pull_requests": [{"url": "pr/8", "by": "bo"}]}}},
	]}}
	subjects := {
		"artifact": {"from": "trail.artifacts", "identified_by": "fingerprint", "has": {"pr_att": {"from": "atts.pr", "identified_by": "id"}}},
		"pull request": {"from": "artifact.pr_att.pull_requests", "identified_by": "url"},
	}
	rep := _chain_report(doc, subjects, {"c": "artifact.pr_att.id exists and by exists"}, {})
	[[r.subject.id, r.subject.in, r.inputs[0]] | some r in rep.results; r.check == "c"] == [
		["pr/7", {"artifact": "a"}, {"name": "artifact.pr_att.id", "value": "att-1", "part": {"name": "artifact.pr_att", "id": "att-1"}, "locations": ["/trail/artifacts/0/atts/pr/id"]}],
		["pr/8", {"artifact": "b"}, {"name": "artifact.pr_att.id", "value": "att-2", "part": {"name": "artifact.pr_att", "id": "att-2"}, "locations": ["/trail/artifacts/1/atts/pr/id"]}],
	]
}

test_a_chain_whose_parent_is_written_wrong_is_written_wrong_too if {
	broken := {"artifact": {"from": "trail.artifacts whose", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
	_from_problems(_chain_report(_chain_doc, broken, {"c": "url exists"}, {})) == [{"name": "subjects.artifact.from", "value": ["doesn't parse"], "locations": []}]
	four := object.union(_chain_subjects, {"x": {"from": "artifact.pull_requests"}, "y": {"from": "x.reviews"}, "pull request": {"from": "y.comments"}})
	_from_problems(_chain_report(_chain_doc, four, {"c": "url exists"}, {"name": "web"})) == [{"name": `subjects."pull request".from`, "value": ["a chain of more than three subjects isn't supported yet"], "locations": []}]
	three := object.union(_chain_subjects, {"x": {"from": "artifact.pull_requests"}, "pull request": {"from": "x.reviews"}})
	_from_problems(_chain_report(_chain_doc, three, {"c": "url exists"}, {"name": "web"})) == []
	grand_broken := {"artifact": {"from": "trail.artifacts whose", "identified_by": "fingerprint"}, "x": {"from": "artifact.pull_requests"}, "pull request": {"from": "x.reviews", "identified_by": "url"}}
	_from_problems(_chain_report(_chain_doc, grand_broken, {"c": "url exists"}, {})) == [{"name": "subjects.artifact.from", "value": ["doesn't parse"], "locations": []}]
}

test_a_from_line_that_starts_at_input_reads_the_input_and_one_at_params_is_written_wrong if {
	doc := {"ds": [{"id": 5}]}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "$input.ds whose id is 5", "identified_by": "id"}}, {"c": "id exists"}, {}))] == [[5, "satisfied"], [5, "satisfied"]]
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "$input", "identified_by": "ds"}}, {"c": "ds exists"}, {}))] == [[[{"id": 5}], "satisfied"]]
	_from_problems(_from_report(doc, {"d": {"from": "$params.ds"}}, {"c": "id exists"}, {"ds": [{"id": 1}]})) == [{"name": "subjects.d.from", "value": ["a from reads the input, so it can't start at $params"], "locations": []}]
	both := ergo.report({"artifact": {"x": [{"id": 1}]}}, {"ergo_spec": "v0.3-dev", "subjects": {"artifact": null, "d": {"from": "$input.artifact.x", "identified_by": "id"}}, "requirements": {"r": {"subject": "d", "checks": {"c": "id exists"}}}}, {})
	[r.cause | some r in both.results; r.check == "c"] == ["satisfied"]
}

test_a_from_line_keeps_every_condition_past_a_hundred if {
	conds := concat(" and ", array.concat([`id is 1` | some _ in numbers.range(1, 100)], [`env is "prod"`]))
	rep := _from_report({"ds": [{"id": 1, "env": "dev"}]}, {"d": {"from": concat("", ["ds whose ", conds]), "identified_by": "id"}}, {"c": "id exists"}, {})
	rep.requirements.r.status == "not_met"
	[r.cause | some r in rep.results; r.check == "$applies"] == ["value"]
	endswith(rep.requirements.r.checks["$applies"].expression, `and env is "prod"`)
}

test_a_from_line_can_start_with_a_quoted_key_that_starts_with_a_dollar if {
	[r[2] | some r in _from_rows(_from_report({"$schema": [{"id": 2}]}, {"d": {"from": `"$schema" whose id is 2`, "identified_by": "id"}}, {"c": "id exists"}, {}))] == ["satisfied", "satisfied"]
}

_defects := {"defects": [
	{"id": 1, "severity": "critical", "status": "open", "team": "a"},
	{"id": 2, "severity": "low", "status": "open", "team": "a"},
	{"id": 3, "severity": "critical", "status": "closed", "team": "b"},
	{"id": 4, "severity": "critical", "status": "open", "team": "b"},
]}

_narrow_report(subjects, name) := ergo.report(_defects, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": name, "checks": {"c": "id exists"}}}}, {})

_kept(rep) := [r.subject.id | some r in rep.results; r.check == "c"]

test_a_from_line_that_names_another_subject_narrows_it if {
	subjects := {"defect": {"from": "defects", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical" and status is one of "open", "in_progress"`}}
	rep := _narrow_report(subjects, "critical defect")
	_kept(rep) == [1, 4]
	rep.requirements.r.checks["$applies"].expression == `severity is "critical" and status is one of "open", "in_progress"`
	_from_problems(rep) == []
	_kept(_narrow_report({"defect": {"from": "defects", "identified_by": "id"}, "all": {"from": "defect"}}, "all")) == [1, 2, 3, 4]
}

test_a_chain_of_narrowing_subjects_prints_the_outer_conditions_first if {
	subjects := {
		"defect": {"from": "defects whose status exists", "identified_by": "id"},
		"critical defect": {"from": `defect whose severity is "critical"`},
		"team b defect": {"from": `"critical defect" whose team is "b"`},
	}
	rep := _narrow_report(subjects, "team b defect")
	_kept(rep) == [3, 4]
	rep.requirements.r.checks["$applies"].expression == `status exists and severity is "critical" and team is "b"`
}

test_a_from_line_can_narrow_a_subject_written_with_op if {
	subjects := {"defect": {"from": "defects whose status is \"open\"", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical"`}}
	_kept(_narrow_report(subjects, "critical defect")) == [1, 4]
}

test_a_narrowing_subject_takes_its_id_from_the_one_it_narrows if {
	subjects := {"defect": {"from": "defects", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical"`, "identified_by": "team"}}
	_from_problems(_narrow_report(subjects, "critical defect")) == [{"name": `subjects."critical defect".identified_by`, "value": ["not allowed on a subject that narrows another"], "locations": []}]
}

test_subjects_that_narrow_each_other_lead_to_a_loop if {
	rep := _narrow_report({"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}}, "x")
	_from_problems(rep) == [{"name": "subjects.x.from", "value": ["leads to a loop"], "locations": []}]
}

test_a_narrowing_chain_deeper_than_ten_prints_in_order if {
	subjects := object.union({"s0": {"from": "defects whose id exists", "identified_by": "id"}}, {concat("", ["s", format_int(n, 10)]): {"from": concat("", ["s", format_int(n - 1, 10), " whose id is not ", format_int(100 + n, 10)])} | some n in numbers.range(1, 11)})
	rep := _narrow_report(subjects, "s11")
	rep.requirements.r.checks["$applies"].expression == concat(" and ", array.concat(["id exists"], [concat("", ["id is not ", format_int(100 + n, 10)]) | some n in numbers.range(1, 11)]))
}

test_a_subject_name_that_isnt_a_string_gives_the_same_report_with_strict_builtins if {
	rep := ergo.report({"defects": [{"id": 1}]}, {"ergo_spec": "v0.3-dev", "subjects": {1: {"from": "defects whose id exists"}}, "requirements": {"r": {"subject": "c", "checks": {"c": "id exists"}}}}, {})
	rep.requirements.r.status == "not_met"
}

test_a_chain_whose_parent_reads_a_param_it_cant_use_fails_with_that_cause if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": 5})) == [["unusable", {"type", "id"}]]
	gone := {"artifact": {"from": "trail.nope", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
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
	base := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "pr": {"from": "artifact.prs", "identified_by": "url"}}
	every pair in [[{"from": "pr whose ok is true"}, "from"]] {
		rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": object.union(base, {"okpr": pair[0]}), "requirements": {"r": {"subject": "okpr", "checks": {"c": "url exists"}}}}, {})
		_from_problems(rep) == [{"name": concat("", ["subjects.okpr.", pair[1]]), "value": ["can't build on a subject read from another subject yet"], "locations": []}]
		stopped(rep)
	}
}

_persona_doc := {"things": [
	{"id": 1, "dispatched": ["security", "style"], "shas": {"security": "3f2a000000000000000000000000000000000000", "style": "9c1b000000000000000000000000000000000000"}},
	{"id": 2, "dispatched": ["security", "perf", 5], "shas": {"security": "x"}},
]}

test_named_by_a_name_from_the_for_line_reads_the_key_each_item_names if {
	check := {"for": "every dispatched as persona", "assert": `shas named by persona matches "^[0-9a-f]{40}$"`}
	rows := [[r.subject.id, r.cause, [[f.item, f.cause, [_bare_line(l) | some l in f.failed_assertions]] | some f in r.failed_items], r.inputs] | some r in ergo.report(_persona_doc, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [
		[1, "satisfied", [], [{"name": "dispatched[]", "value": ["security", "style"], "locations": ["/things/0/dispatched/0", "/things/0/dispatched/1"]}, {"name": "shas", "value": _persona_doc.things[0].shas, "locations": ["/things/0/shas"]}]],
		[
			2, "unusable", [
				["item 1 of dispatched", "value", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "value"}]],
				["item 2 of dispatched", "absent", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "absent"}]],
				["item 3 of dispatched", "unusable", [{"assertion": `shas named by persona matches "^[0-9a-f]{40}$"`, "cause": "unusable"}]],
			],
			[{"name": "dispatched[]", "value": ["security", "perf", 5], "locations": ["/things/1/dispatched/0", "/things/1/dispatched/1", "/things/1/dispatched/2"]}, {"name": "shas", "value": {"security": "x"}, "locations": ["/things/1/shas"]}],
		],
	]
}

test_named_by_a_bare_word_in_a_from_line_or_an_id_is_an_unknown_name_since_there_is_no_subject_to_read_it_from if {
	from := ergo.report({"things": [{"id": 1, "k": "a"}]}, {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things named by k", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}, {})
	[i.value | some r in from.results; r.check == "$well_formed"; some i in r.inputs; i.name == "subjects.thing.from"] == [["unknown alias k"]]
	id := ergo.report({"things": [{"id": {"a": 1}, "k": "a"}]}, {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things", "identified_by": "id named by k"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "k exists"}}}}, {})
	[i.value | some r in id.results; r.check == "$well_formed"; some i in r.inputs; i.name == "subjects.thing.identified_by"] == [[`identified_by is a path, like "id" or "build.number"`]]
}

test_named_by_a_field_reads_the_key_the_subjects_field_holds if {
	doc := {"things": [
		{"id": "v1", "severity": "high", "age": 3},
		{"id": "v2", "severity": "low", "age": 40},
	]}
	_sentence_rows({"c": "age is at most $params.limits named by severity"}, doc, {"limits": {"high": 5, "low": 30}}) == [
		["c", true, "satisfied", [{"name": "age", "value": 3, "locations": ["/things/0/age"]}, {"name": "$params.limits named by severity", "value": 5, "locations": ["$params:/limits/high"]}, {"name": "severity", "value": "high", "locations": ["/things/0/severity"]}]],
		["c", false, "value", [{"name": "age", "value": 40, "locations": ["/things/1/age"]}, {"name": "$params.limits named by severity", "value": 30, "locations": ["$params:/limits/low"]}, {"name": "severity", "value": "low", "locations": ["/things/1/severity"]}]],
	]
	_sentence_rows({"c": "age is at most $params.limits[severity]"}, doc, {"limits": {"high": 5, "low": 30}}) == _sentence_rows({"c": "age is at most $params.limits named by severity"}, doc, {"limits": {"high": 5, "low": 30}})
	ergo.report(doc, _sentence_policy({"c": "age is at most $params.limits[severity]"}), {}).requirements.s.checks.c.expression == "age is at most $params.limits named by severity"
	rep := ergo.report(doc, _sentence_policy({"c": "age is at most $params.limits named by severity"}), {})
	rep.requirements.s.checks.c.expression == "age is at most $params.limits named by severity"
	not "$refs" in object.keys(rep.requirements.s.checks.c)
}

test_named_by_a_field_reads_a_key_of_the_subject_too if {
	doc := {"things": [{"id": 1, "k": "a", "m": {"a": 1, "b": 2}}, {"id": 2, "k": "b", "m": {"a": 1, "b": 2}}]}
	_sentence_rows({"c": "m named by k is 1"}, doc, {}) == [
		["c", true, "satisfied", [{"name": "m named by k", "value": 1, "locations": ["/things/0/m/a"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]],
		["c", false, "value", [{"name": "m named by k", "value": 2, "locations": ["/things/1/m/b"]}, {"name": "k", "value": "b", "locations": ["/things/1/k"]}]],
	]
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

test_named_by_a_field_on_a_subject_that_isnt_an_object_fails_as_not_an_object if {
	rows := [[r.subject.id, r.cause] | some r in ergo.report({"things": ["x"]}, {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "$params.limits named by severity is 1"}}}}, {"limits": {"x": 1}}).results; r.check == "c"]
	rows == [["x", "not_an_object"]]
}

test_named_by_a_field_works_with_exists_every_count_and_plus if {
	doc := {"things": [{"id": 1, "k": "a", "xs": {"a": [1], "b": [2, 3]}}]}
	_sentence_rows({"c": "xs named by k exists"}, doc, {}) == [["c", true, "satisfied", [{"name": "xs named by k", "value": [1], "locations": ["/things/0/xs/a"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "every xs named by k is 1"}, doc, {}) == [["c", true, "satisfied", [{"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "count of xs named by k is 1"}, doc, {}) == [["c", true, "satisfied", [{"name": "count of xs named by k", "value": 1, "locations": ["/things/0/xs/a/0"]}, {"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "count of xs.b plus $params.extra named by k is 3"}, doc, {"extra": {"a": 1}}) == [["c", true, "satisfied", [{"name": "count of xs.b plus $params.extra named by k", "value": 3, "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1", "$params:/extra/a"]}, {"name": "count of xs.b", "value": 2, "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1"]}, {"name": "xs.b[]", "value": [2, 3], "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1"]}, {"name": "$params.extra named by k", "value": 1, "locations": ["$params:/extra/a"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": {"assert": ["xs named by k exists", "every xs named by k is 1"]}}, doc, {}) == [["c", true, "satisfied", [{"name": "k", "value": "a", "locations": ["/things/0/k"]}, {"name": "xs named by k", "value": [1], "locations": ["/things/0/xs/a"]}, {"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}]]]
}

test_named_by_a_field_in_a_whose_or_the_phrase_of_a_one_line_every_reads_the_items_field if {
	doc := {"things": [{"id": 1, "items": [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}]}]}
	params := {"min": {"a": 2, "b": 2}}
	_walk_rows({"c": "every items.n is at least $params.min named by kind"}, doc, params) == [[1, "c", "value", [{"cause": "value", "item": "item 2 of items", "path": "items[1].n", "value": 1, "locations": ["/things/0/items/1/n"]}]]]
	_sentence_rows({"c": "count of items whose n is at least $params.min named by kind is 1"}, doc, params)[0][2] == "satisfied"
}

test_named_by_a_field_on_a_for_line_reads_the_subject_and_a_for_name_hides_a_field_with_the_same_name if {
	things := [{"id": 1, "k": "a", "xs": {"a": [1], "b": [2]}, "items": [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}]}]
	_for_rows({"for": "every xs named by k as x", "assert": "x is 1"}, things, {}) == [[1, "satisfied", [], [{"name": "k", "value": "a", "locations": ["/things/0/k"]}, {"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}]]]
	_for_rows({"for": "every items as i", "assert": "i.n is at least $params.min named by k"}, things, {"min": {"a": 2, "b": 2}})[0][3] == [
		{"name": "$params.min named by k", "value": 2, "locations": ["$params:/min/a"]},
		{"name": "items[]", "value": [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}], "locations": ["/things/0/items/0", "/things/0/items/1"]},
		{"name": "k", "value": "a", "locations": ["/things/0/k"]},
	]
	_for_rows({"for": "every items as k", "assert": "$params.min named by k exists"}, [{"id": 1, "k": "b", "items": ["a"]}], {"min": {"a": 1}})[0][1] == "satisfied"
	_for_rows({"for": "every xs whose v named by k is 1 as x", "assert": "x exists"}, [{"id": 1, "xs": [{"k": "a", "v": {"a": 1}}]}], {})[0][1] == "satisfied"
}

test_a_field_after_named_by_is_part_of_its_path_so_another_sides_cause_can_come_first_as_with_a_for_name_and_unlike_a_param if {
	doc := {"things": [{"id": 1, "s": null, "m": {}}]}
	_sentence_rows({"c": "xs equals m named by s"}, doc, {})[0][2] == "absent"
	_for_rows({"for": "every ks as s", "assert": "xs equals m named by s"}, [{"id": 1, "ks": [null], "m": {}}], {})[0][1] == "absent"
	_sentence_rows({"c": "xs equals m named by $params.s"}, {"things": [{"id": 1, "m": {}}]}, {"s": null})[0][2] == "null"
}

test_named_by_a_for_name_in_the_second_items_path_reads_the_first_items_key if {
	check := {"for": "every ys as y, every xs named by y as x", "assert": "x is 1"}
	rows := [[r.subject.id, r.cause] | some r in ergo.report({"things": [{"id": 1, "xs": {"a": [1], "b": [2]}, "ys": ["a"]}, {"id": 2, "xs": {"a": [1], "b": [2]}, "ys": ["a", "b"]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [[1, "satisfied"], [2, "value"]]
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

test_a_from_line_named_by_a_bare_word_is_an_unknown_name if {
	_from_problems(_from_report({"m": {}}, {"x": {"from": "m named by k"}}, {"c": "id exists"}, {})) == [{"name": "subjects.x.from", "value": ["unknown alias k"], "locations": []}]
}

test_every_through_a_for_name_isnt_listed_as_an_input_since_it_changes_with_each_item if {
	doc := {"things": [{"id": 1, "ps": ["a"], "xs": [{"k": {"a": 1}}]}]}
	[[r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy({"c": {"for": "every ps as p", "assert": "every xs.k named by p is 1"}}), {}).results; r.check == "c"] == [["satisfied", [{"name": "ps[]", "value": ["a"], "locations": ["/things/0/ps/0"]}]]]
}

test_a_count_through_a_for_name_lists_its_list_and_not_its_number_since_that_changes_with_each_item if {
	doc := {"things": [{"id": 1, "ps": ["a"], "ys": [{"m": {"a": 1}}]}]}
	[[r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy({"c": {"for": "every ps as p", "assert": "count of ys whose m named by p is 1 is 1"}}), {}).results; r.check == "c"] == [["satisfied", [
		{"name": "ps[]", "value": ["a"], "locations": ["/things/0/ps/0"]},
		{"name": "ys[]", "value": [{"m": {"a": 1}}], "locations": ["/things/0/ys/0"]},
	]]]
}

test_a_walk_through_a_for_name_lists_the_part_before_the_name_once_as_a_plain_check_does if {
	things := [{"id": 1, "ks": ["a", "b"], "m": {"a": [1], "b": [2]}}]
	want := [
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/things/0/ks/0", "/things/0/ks/1"]},
		{"name": "m", "value": {"a": [1], "b": [2]}, "locations": ["/things/0/m"]},
	]
	_for_rows({"for": "every ks as k", "assert": "some m named by k is at least 1"}, things, {})[0][3] == want
	_for_rows({"for": "every ks as k", "assert": ["some m named by k is at least 1", "every m named by k is at least 1"]}, things, {})[0][3] == want
}

test_a_count_through_a_for_name_lists_the_part_before_the_name_and_not_its_number_or_its_items if {
	things := [{"id": 1, "ks": ["a", "b"], "m": {"a": [1], "b": [2]}}]
	_for_rows({"for": "every ks as k", "assert": "count of m named by k is at least 1"}, things, {})[0][3] == [
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/things/0/ks/0", "/things/0/ks/1"]},
		{"name": "m", "value": {"a": [1], "b": [2]}, "locations": ["/things/0/m"]},
	]
}

test_a_whose_that_reads_a_parent_through_a_for_name_lists_the_part_before_the_name if {
	doc := {"artifacts": [{"id": "a", "nums": {"a": 1, "b": 2}, "prs": [{"id": 1, "ks": ["a", "b"], "rows": [{"n": 1}, {"n": 2}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	checks := {"c": {"for": "every ks as k", "assert": "count of rows whose n is artifact.nums named by k is at least 1"}}
	rows := [r | some r in ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results; r.check == "c"]
	[[r.cause, r.inputs] | some r in rows] == [["satisfied", [
		{"name": "artifact.nums", "value": {"a": 1, "b": 2}, "locations": ["/artifacts/0/nums"]},
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/artifacts/0/prs/0/ks/0", "/artifacts/0/prs/0/ks/1"]},
		{"name": "rows[]", "value": [{"n": 1}, {"n": 2}], "locations": ["/artifacts/0/prs/0/rows/0", "/artifacts/0/prs/0/rows/1"]},
	]]]
}

_old_policy := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"deployment": {
		"from": ["deployments"],
		"identified_by": ["id"],
		"applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
	}},
	"requirements": {"approved": {"subject": "deployment", "checks": {
		"approved": {"assert": "approved_by is a non-empty string", "description": "Someone approved it"},
		"region": "region is one of \"eu\", \"us\"",
		"later": "deployed_at is after approved_at",
		"signed": {"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["signed"], "value": true}},
	}}},
}

test_as_sentences_writes_null_as_is_null_because_it_reads_back_the_same if {
	ergo.as_sentences({"requirements": {"r": {"checks": {"c": "x is null"}}}}).requirements.r.checks.c == "x is null"
}

test_as_sentences_rewrites_each_check_and_subject_it_can_as_a_sentence if {
	ergo.as_sentences(_old_policy) == {
		"ergo_spec": "v0.3-dev",
		"subjects": {"deployment": {"from": `deployments whose environment is "prod"`, "identified_by": "id"}},
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
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"artifact": {"from": ["artifact"]}, "pr": {"from": ["artifact", "prs"], "identified_by": ["url"]}}}
	ergo.as_sentences(policy).subjects == {"artifact": {"from": "artifact"}, "pr": {"from": "$input.artifact.prs", "identified_by": "url"}}
}

test_as_sentences_writes_naming_and_whole_input_and_narrowing_as_from_lines if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {
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
	ergo.as_sentences({"requirements": ["x"], "subjects": 5, "other": 1}) == {"ergo_spec": "v0.3-dev", "requirements": ["x"], "subjects": 5, "other": 1}
	ergo.as_sentences("x") == "x"
	ergo.as_sentences({"requirements": {"r": 1, "s": {"checks": []}}}) == {"ergo_spec": "v0.3-dev", "requirements": {"r": 1, "s": {"checks": []}}}
}

test_as_sentences_writes_compares_with_a_value_and_within if {
	checks := {
		"a": "x equals 1 within 0.5",
		"b": "x is at least 2",
		"c": "x equals y within 0.5",
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
		"ergo_spec": "v0.3-dev",
		"subjects": {"d": {"from": "deployments"}, "c": {"from": "d.commits"}},
		"requirements": {"r": {"subject": "c", "checks": {"k": "d.v exists"}}},
	}
	ergo.as_sentences(policy).requirements == policy.requirements
}

_list_phrases := {
	"is one of": "is in",
	"is not one of": "is not in",
	"contains": "contains",
	"does not contain": "does not contain",
	"contains all of": "contains all of",
	"contains none of": "contains none of",
	"matches": "matches",
	"does not match": "does not match",
}

_list_lefts := [
	{"id": "l00"},
	{"id": "l01", "x": null},
	{"id": "l02", "x": "a"},
	{"id": "l03", "x": "b"},
	{"id": "l04", "x": 3},
	{"id": "l05", "x": true},
	{"id": "l06", "x": []},
	{"id": "l07", "x": ["a"]},
	{"id": "l08", "x": ["a", "b"]},
	{"id": "l09", "x": ["b"]},
	{"id": "l10", "x": {"k": "a"}},
	{"id": "l11", "x": ""},
	{"id": "l12", "x": [1]},
	{"id": "l13", "x": [null]},
	{"id": "l14", "x": ["a", 1]},
	{"id": "l15", "x": [["a"]]},
]

_list_rights := [
	{},
	{"v": null},
	{"v": []},
	{"v": ["a"]},
	{"v": ["a", "b"]},
	{"v": "a"},
	{"v": "text"},
	{"v": 3},
	{"v": true},
	{"v": {"k": "a"}},
	{"v": [1, "a"]},
	{"v": ["a", null]},
	{"v": [["a"]]},
	{"v": ["^a", "("]},
	{"v": ["^a"]},
	{"v": ["^a", 1]},
	{"v": [null]},
	{"v": ["a", "a"]},
	{"v": [1]},
	{"v": [{"k": "a"}]},
	{"v": "("},
	{"v": ["["]},
	{"v": [true]},
	{"v": [false]},
]

_list_verdicts(check, things, params) := [[r.subject.id, r.passed, r.cause] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_list_with_field(things, right) := [object.union(t, {"y": right.v}) | some t in things] if "v" in object.keys(right)

_list_with_field(things, right) := things if not "v" in object.keys(right)

_list_params(right) := {"k": right.v} if "v" in object.keys(right)

_list_params(right) := {} if not "v" in object.keys(right)

_list_same_as_params(words, suffix, right) if {
	_list_verdicts(concat("", ["x ", words, " y", suffix]), _list_with_field(_list_lefts, right), {}) == _list_verdicts(concat("", ["x ", words, " $params.k", suffix]), _list_lefts, _list_params(right))
}

_list_same_as_params_for_every_right(words) if {
	every right in _list_rights {
		_list_same_as_params(words, "", right)
	}
}

test_the_list_phrases_compared_with_params_are_every_list_phrase if {
	{w | some _, w in _list_phrases} == {"is in", "is not in", "contains", "does not contain", "contains all of", "contains none of", "matches", "does not match"}
}

test_a_field_after_is_in_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("is in")

test_a_field_after_is_not_in_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("is not in")

test_a_field_after_contains_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains")

test_a_field_after_does_not_contain_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("does not contain")

test_a_field_after_contains_all_of_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains all of")

test_a_field_after_contains_none_of_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains none of")

test_a_field_after_matches_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("matches")

test_a_field_after_does_not_match_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("does not match")

test_a_path_that_cant_be_read_after_a_list_phrase_gives_the_cause_of_the_same_path_in_params if {
	every _, words in _list_phrases {
		every right in [{}, {"v": null}, {"v": "s"}, {"v": 3}, {"v": []}, {"v": {}}, {"v": {"z": null}}, {"v": {"z": ["a"]}}, {"v": {"z": "a"}}, {"v": {"z": ["^a"]}}] {
			_list_same_as_params(words, ".z", right)
		}
	}
}

test_each_list_phrase_with_a_field_fails_closed_on_a_missing_null_or_wrong_typed_side if {
	every pair in [
		["x is in y", "a", ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x is not in y", "a", ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains y", ["a"], "a", 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x does not contain y", ["a"], "a", 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains all of y", ["a"], ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains none of y", ["a"], ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x matches y", "a", ["^a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x does not match y", "a", ["^a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
	] {
		things := [
			{"id": 1, "y": pair[2]},
			{"id": 2, "x": null, "y": pair[2]},
			{"id": 3, "x": pair[3], "y": pair[2]},
			{"id": 4, "x": pair[1]},
			{"id": 5, "x": pair[1], "y": null},
			{"id": 6, "x": pair[1], "y": pair[3]},
		]
		[r[2] | some r in _list_verdicts(pair[0], things, {})] == pair[4]
	}
}

test_a_field_after_a_list_phrase_passes_and_fails_by_what_the_list_holds if {
	things := [
		{"id": 1, "x": "a", "l": ["a", "b"], "p": ["^a"], "w": "a"},
		{"id": 2, "x": "c", "l": ["a", "b"], "p": ["^a"], "w": "c"},
		{"id": 3, "x": ["a", "b"], "l": ["a"], "p": ["^a"], "w": "z"},
		{"id": 4, "x": ["a", "b"], "l": ["c"], "p": [], "w": "b"},
	]
	every pair in [
		["x is in l", [true, false, false, false]],
		["x is not in l", [false, true, false, false]],
		["x contains w", [false, false, false, true]],
		["x does not contain w", [false, false, true, false]],
		["x contains all of l", [false, false, true, false]],
		["x contains none of l", [false, false, false, true]],
		["x matches p", [true, false, false, false]],
		["x does not match p", [false, true, false, false]],
	] {
		[r[1] | some r in _list_verdicts(pair[0], things, {})] == pair[1]
	}
}

test_a_field_after_a_list_phrase_lists_both_fields_in_the_row_inputs_and_keeps_the_sentence_as_written if {
	doc := {"things": [{"id": "t1", "files": ["a", "b"], "gaps": ["a"]}]}
	r := ergo.report(doc, _sentence_policy({"c": "files contains all of gaps"}), {})
	[row.inputs | some row in r.results; row.check == "c"] == [[{"name": "files", "value": ["a", "b"], "locations": ["/things/0/files"]}, {"name": "gaps", "value": ["a"], "locations": ["/things/0/gaps"]}]]
	r.requirements.s.checks.c == {"description": "", "meta": {}, "expression": "files contains all of gaps"}
	r2 := ergo.report(doc, _sentence_policy({"c": "files contains all of $params.k"}), {"k": ["a"]})
	[row.inputs | some row in r2.results; row.check == "c"] == [[{"name": "files", "value": ["a", "b"], "locations": ["/things/0/files"]}]]
}

test_a_field_of_the_input_before_a_list_phrase_reads_a_field_of_the_subject_after_it if {
	doc := {"artifact": {"developers": ["ann", "bob"]}, "things": [{"id": "t1", "tested_by": "cy"}, {"id": "t2", "tested_by": "ann"}]}
	r := ergo.report(doc, _sentence_policy({"c": "$input.artifact.developers does not contain tested_by"}), {})
	[[row.subject.id, row.cause, row.inputs] | some row in r.results; row.check == "c"] == [
		["t1", "satisfied", [{"name": "$input.artifact.developers", "value": ["ann", "bob"], "locations": ["/artifact/developers"]}, {"name": "tested_by", "value": "cy", "locations": ["/things/0/tested_by"]}]],
		["t2", "value", [{"name": "$input.artifact.developers", "value": ["ann", "bob"], "locations": ["/artifact/developers"]}, {"name": "tested_by", "value": "ann", "locations": ["/things/1/tested_by"]}]],
	]
}

test_a_list_phrase_with_a_field_runs_after_a_for_line_a_whose_and_a_one_line_every_or_some if {
	doc := {"things": [
		{"id": 1, "excluded": ["q"], "allowed": ["s1"], "approvers": [{"username": "x"}, {"username": "y"}], "commits": [{"sha": "s1", "author": "x", "ok": ["s1"]}, {"sha": "s2", "author": "z", "ok": ["s1"]}]},
		{"id": 2, "excluded": ["x"], "allowed": ["s9"], "approvers": [{"username": "x"}, {"username": "y"}], "commits": [{"sha": "s1", "author": "x", "ok": ["s9"]}]},
	]}
	checks := {
		"f": {"for": "every approvers as ap", "assert": "ap.username is not one of excluded"},
		"w": "every commits.sha whose author is \"x\" is in ok",
		"s": "some commits.sha whose author is \"x\" is in ok",
		"c": {"for": "every commits as cm", "assert": "cm.sha is in allowed"},
	}
	[[r.check, r.subject.id, r.passed, r.cause] | some r in ergo.report(doc, _sentence_policy(checks), {}).results; r.check in {"f", "w", "s", "c"}] == [
		["c", 1, false, "value"], ["f", 1, true, "satisfied"], ["s", 1, true, "satisfied"], ["w", 1, true, "satisfied"],
		["c", 2, false, "value"], ["f", 2, false, "value"], ["s", 2, false, "value"], ["w", 2, false, "value"],
	]
}

test_a_list_phrase_with_a_field_runs_in_a_from_lines_whose if {
	doc := {"deployments": [
		{"id": 1, "environment": "prod", "allowed_envs": ["prod"]},
		{"id": 2, "environment": "dev", "allowed_envs": ["prod"]},
		{"id": 3, "environment": "prod", "allowed_envs": ["dev"]},
	]}
	rep := _from_report(doc, {"d": {"from": "deployments whose environment is in allowed_envs", "identified_by": "id"}}, {"c": "id exists"}, {})
	[r[0] | some r in _from_rows(rep); r[1] == "c"] == [1]
}

test_a_list_comparison_only_ever_passes_on_values_of_the_type_it_reads_even_through_leaf_passed if {
	every cmp in ["in", "not_in", "includes", "excludes", "includes_all", "excludes_all", "matches_any", "not_matches_any"] {
		not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": cmp, "right": ["m"]}, {"n": 15, "m": 1})
	}
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "matches_any", "right": ["y"]}, {"x": "a", "y": ["("]})
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "not_matches_any", "right": ["y"]}, {"x": "a", "y": ["(", "^b"]})
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "includes_all", "right": ["y"]}, {"x": ["a"], "y": []})
}

test_a_whose_of_a_count_with_a_field_after_a_list_phrase_decides_each_item_as_the_same_whose_with_params_does if {
	every _, words in _list_phrases {
		every right in [{}, {"v": null}, {"v": 3}, {"v": []}, {"v": ["a"]}, {"v": ["^a"]}, {"v": ["^a", "("]}] {
			items := [{"s": "a", "l": ["a"]}, {"s": "b", "l": ["a"]}, {"s": null, "l": "a"}]
			by_field := _tally_rows(concat("", ["count of xs whose s ", words, " k is at least 1"]), [{"id": 1, "xs": [object.union(i, object.filter(_list_item_right(right), ["k"])) | some i in items]}], {})
			by_params := _tally_rows(concat("", ["count of xs whose s ", words, " $params.k is at least 1"]), [{"id": 1, "xs": items}], _list_params(right))
			[r[1] | some r in by_field] == [r[1] | some r in by_params]
		}
	}
}

_list_item_right(right) := {"k": right.v} if "v" in object.keys(right)

_list_item_right(right) := {} if not "v" in object.keys(right)

_snyk := {"id": "v1", "first_seen_ts": "2026-10-01T00:00:00Z", "now_ts": "2026-10-04T12:00:00Z", "severity": "high"}

_elapsed_rows(check, things, params) := [[r.subject.id, r.passed, r.cause, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_elapsed_first(check, things, params) := [_elapsed_rows(check, things, params)[0][1], _elapsed_rows(check, things, params)[0][2]]

_elapsed_cause(check, thing, params) := _elapsed_rows(check, [thing], params)[0][2]

test_days_elapsed_is_the_difference_of_two_times_in_days_and_shows_its_inputs if {
	_elapsed_rows("days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity", [_snyk], {"max_days": {"high": 4}}) == [["v1", true, "satisfied", [
		{"name": "days elapsed from first_seen_ts to now_ts", "value": 3.5, "locations": ["/things/0/first_seen_ts", "/things/0/now_ts"]},
		{"name": "first_seen_ts", "value": "2026-10-01T00:00:00Z", "locations": ["/things/0/first_seen_ts"]},
		{"name": "now_ts", "value": "2026-10-04T12:00:00Z", "locations": ["/things/0/now_ts"]},
		{"name": "$params.max_days named by severity", "value": 4, "locations": ["$params:/max_days/high"]},
		{"name": "severity", "value": "high", "locations": ["/things/0/severity"]},
	]]]
	_elapsed_first("days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity", [_snyk], {"max_days": {"high": 3}}) == [false, "value"]
}

test_every_unit_divides_the_seconds_between_two_times_by_its_length if {
	every pair in [["seconds", "302400"], ["minutes", "5040"], ["hours", "84"], ["days", "3.5"], ["weeks", "0.5"]] {
		_elapsed_first(concat("", [pair[0], " elapsed from first_seen_ts to now_ts is ", pair[1]]), [_snyk], {}) == [true, "satisfied"]
	}
}

test_elapsed_counts_seconds_for_two_numbers_and_gives_fractions_and_zero if {
	_elapsed_first("days elapsed from p to q is 1.5", [{"id": 1, "p": 100, "q": 129700}], {}) == [true, "satisfied"]
	_elapsed_first("hours elapsed from p to q is 0", [{"id": 1, "p": 100, "q": 100}], {}) == [true, "satisfied"]
	_elapsed_first("days elapsed from p to q is 0", [{"id": 1, "p": "2026-01-01T00:00:00Z", "q": "2026-01-01T01:00:00+01:00"}], {}) == [true, "satisfied"]
	_elapsed_first("seconds elapsed from p to q is 0.5", [{"id": 1, "p": "2026-01-01T00:00:00Z", "q": "2026-01-01T00:00:00.5Z"}], {}) == [true, "satisfied"]
}

test_elapsed_is_rounded_down_to_six_decimal_places_so_every_runtime_prints_the_same_number if {
	[r[3][0].value | some r in _elapsed_rows(
		"days elapsed from p to q is less than 5", [
			{"id": 1, "p": 0, "q": 1},
			{"id": 2, "p": 0, "q": 431999},
			{"id": 3, "p": "2025-05-30T00:00:00.000000001Z", "q": "2025-06-04T23:59:59.999999999Z"},
		],
		{},
	)] == [0.000011, 4.999988, 5.999999]
}

test_elapsed_reads_a_number_to_the_nearest_microsecond if {
	_elapsed_first("seconds elapsed from p to q is 0.876543", [{"id": 1, "p": 1748736000.1234567, "q": 1748736001}], {}) == [true, "satisfied"]
}

test_elapsed_fails_a_number_outside_the_years_rfc_3339_times_cover_so_milliseconds_arent_read_as_seconds if {
	_elapsed_cause("days elapsed from p to q is 1", {"id": 1, "p": 1748736000000, "q": 1748822400000}, {}) == "unusable"
	_elapsed_cause("days elapsed from p to q is 1", {"id": 1, "p": -9000000001, "q": 0}, {}) == "unusable"
	_elapsed_first("seconds elapsed from p to q is 18000000000", [{"id": 1, "p": -9000000000, "q": 9000000000}], {}) == [true, "satisfied"]
}

test_elapsed_fails_as_value_when_the_end_is_before_the_start if {
	_elapsed_rows("days elapsed from p to q is at most 5", [{"id": 1, "p": "2026-01-02T00:00:00Z", "q": "2026-01-01T00:00:00Z"}, {"id": 2, "p": 5, "q": 4}], {}) == [
		[1, false, "value", [{"name": "days elapsed from p to q", "value": null, "locations": ["/things/0/p", "/things/0/q"]}, {"name": "p", "value": "2026-01-02T00:00:00Z", "locations": ["/things/0/p"]}, {"name": "q", "value": "2026-01-01T00:00:00Z", "locations": ["/things/0/q"]}]],
		[2, false, "value", [{"name": "days elapsed from p to q", "value": null, "locations": ["/things/1/p", "/things/1/q"]}, {"name": "p", "value": 5, "locations": ["/things/1/p"]}, {"name": "q", "value": 4, "locations": ["/things/1/q"]}]],
	]
}

test_elapsed_fails_closed_on_a_side_it_cant_read if {
	t := "2026-01-01T00:00:00Z"
	every case in [
		[{"id": 1, "q": t}, "absent"],
		[{"id": 1, "p": t}, "absent"],
		[{"id": 1, "p": null, "q": t}, "null"],
		[{"id": 1, "p": t, "q": null}, "null"],
		[{"id": 1, "p": null, "q": null}, "null"],
		[{"id": 1, "p": null}, "absent"],
		[{"id": 1, "p": true, "q": t}, "unusable"],
		[{"id": 1, "p": t, "q": [1]}, "unusable"],
		[{"id": 1, "p": {"x": 1}, "q": t}, "unusable"],
		[{"id": 1, "p": "yesterday", "q": t}, "unusable"],
		[{"id": 1, "p": true}, "absent"],
		[{"id": 1, "p": true, "q": null}, "null"],
		[{"id": 1, "p": t, "q": 5}, "unusable"],
		[{"id": 1, "p": 5, "q": t}, "unusable"],
		[{"id": 1, "p": "2026-01-01t00:00:00Z", "q": t}, "unusable"],
		[{"id": 1, "p": t, "q": "2026-01-01T00:00:00z"}, "unusable"],
		[{"id": 1, "p": "2026-02-30T00:00:00Z", "q": t}, "unusable"],
		[{"id": 1, "p": "1677-12-31T00:00:00Z", "q": t}, "unusable"],
		[{"id": 1, "p": t, "q": "2262-01-01T00:00:00Z"}, "unusable"],
	] {
		_elapsed_cause("days elapsed from p to q is at least 0", case[0], {}) == case[1]
	}
}

test_elapsed_reads_paths_like_any_other_path if {
	t := {"id": 1, "x": {"p": "2026-01-01T00:00:00Z"}, "ends": {"k": 1100}, "k": "k"}
	_elapsed_cause("days elapsed from x.a to $input.now is 1", t, {}) == "absent"
	_elapsed_first("seconds elapsed from $params.start to ends named by k is 1000", [t], {"start": 100}) == [true, "satisfied"]
	_elapsed_cause("seconds elapsed from $params.start to $params.end is 1", {"id": 1}, {"start": 100}) == "absent"
	_elapsed_first("seconds elapsed from $params.start to $params.end is 1", [{"id": 1}], {"start": 100, "end": 101}) == [true, "satisfied"]
}

test_elapsed_takes_the_phrases_a_count_takes if {
	every pair in [
		["days elapsed from p to q equals 1", true],
		["days elapsed from p to q is not 2", true],
		["days elapsed from p to q does not equal 2", true],
		["days elapsed from p to q is at least 1", true],
		["days elapsed from p to q is at most 1", true],
		["days elapsed from p to q is more than 0.5", true],
		["days elapsed from p to q is less than 2", true],
		["days elapsed from p to q is 1.01 within 0.1", true],
		["days elapsed from p to q is more than 1", false],
		["days elapsed from p to q is c", true],
		["days elapsed from p to q is more than c plus 1", false],
	] {
		_elapsed_rows(pair[0], [{"id": 1, "p": 0, "q": 86400, "c": 1}], {})[0][1] == pair[1]
	}
}

test_elapsed_prints_its_sentence_in_the_reports_spelling if {
	r := ergo.report({"things": []}, _sentence_policy({"c": "hours   elapsed  from  .days to  x named by  $params.k is less than 5"}), {})
	r.requirements.s.checks.c.expression == "hours elapsed from .days to x named by $params.k is less than 5"
	r2 := ergo.report({"things": []}, _sentence_policy({"c": {"assert": ["days elapsed from p to q is 1", "weeks elapsed from \"a b\" to q is at most 1"]}}), {})
	r2.requirements.s.checks.c.expression == `days elapsed from p to q is 1 and weeks elapsed from "a b" to q is at most 1`
}

test_elapsed_words_start_a_sentence_so_a_field_with_that_name_needs_a_dot if {
	every w in ["seconds", "minutes", "hours", "days", "weeks", "to"] {
		_sentence_problems(concat("", [w, " is 1"])) == [concat("", [w, " is a word of the grammar: write .", w])]
		_elapsed_rows(concat("", [".", w, " is 1"]), [{"id": 1, w: 1}], {})[0][1] == true
	}
	_elapsed_first("days elapsed from .to to .days is 1", [{"id": 1, "to": 0, "days": 86400}], {}) == [true, "satisfied"]
}

test_months_and_years_are_not_elapsed_phrases if {
	_sentence_problems("months elapsed from p to q is 1") == ["doesn't parse"]
	_sentence_problems("years elapsed from p to q is 1") == ["doesn't parse"]
}

test_elapsed_works_in_each_line_of_a_list_and_under_a_for_line if {
	_elapsed_first({"assert": ["days elapsed from p to q is 1", "hours elapsed from p to q is 24"]}, [{"id": 1, "p": 0, "q": 86400}], {}) == [true, "satisfied"]
	fors := _elapsed_rows({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is less than $params.max"}, [{"id": 1, "ps": [{"p": 0, "q": 86400}, {"p": 0, "q": 86400}]}, {"id": 2, "ps": [{"p": 0, "q": 864000}]}], {"max": 2})
	[[r[0], r[1]] | some r in fors] == [[1, true], [2, false]]
	_elapsed_cause({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is 1"}, {"id": 1, "ps": [{"p": 0}]}, {}) == "absent"
	_elapsed_cause({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is 1"}, {"id": 1, "ps": [{"p": 1, "q": 0}]}, {}) == "value"
}

test_elapsed_is_written_wrong_after_every_or_some_and_in_a_from_line if {
	msg := "an elapsed time isn't supported yet after every or some, or in a from line"
	every check in [
		"every xs is days elapsed from p to q",
		"some xs is days elapsed from p to q",
		"every xs is days elapsed from p to q plus 1",
	] {
		msg in _sentence_problems(check)
	}
	_from_problems(_from_report({"xs": [{"id": 1}]}, {"x": {"from": "xs whose days elapsed from p to q is 1"}}, {"c": "id exists"}, {})) == [{"name": "subjects.x.from", "value": [msg], "locations": []}]
}

test_an_elapsed_time_in_a_whose_decides_each_item_of_a_count_a_sum_and_an_every if {
	doc := [{"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, {"n": 2, "p": 0, "q": 86400}, {"n": 4, "p": 0, "q": 172800}]}]
	_elapsed_rows("count of xs whose days elapsed from p to q is 1 is 2", doc, {})[0][1] == true
	_elapsed_rows("sum of xs.n whose days elapsed from p to q is 1 is 3", doc, {})[0][1] == true
	_elapsed_rows("sum of xs.n whose days elapsed from p to q is 1 is 4", doc, {})[0][1] == false
	_elapsed_rows("count of xs whose n is days elapsed from p to q is 1", doc, {})[0][1] == true
	_elapsed_rows("every xs.n whose days elapsed from p to q is 1 is less than 3", doc, {})[0][1] == true
	_elapsed_rows("every xs.n whose days elapsed from p to q is 1 is less than 2", doc, {})[0][1] == false
}

test_an_elapsed_time_in_a_whose_fails_closed_when_an_item_has_no_usable_time if {
	items := {
		"absent": {"n": 1, "p": 0},
		"null": {"n": 1, "p": 0, "q": null},
		"mixed": {"n": 1, "p": 0, "q": "2026-10-01T00:00:00Z"},
		"text": {"n": 1, "p": 0, "q": "x"},
	}
	every state, item in items {
		_elapsed_cause("count of xs whose days elapsed from p to q is 1 is 1", {"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, item]}, {}) == state_cause[state]
		_elapsed_cause("every xs.n whose days elapsed from p to q is 1 is 1", {"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, item]}, {}) == state_cause[state]
	}
}

state_cause := {"absent": "absent", "null": "null", "mixed": "unusable", "text": "unusable"}

test_an_elapsed_time_in_a_whose_goes_on_a_for_line_too if {
	doc := [{"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, {"n": 2, "p": 0, "q": 172800}]}]
	_elapsed_first({"for": "every xs whose days elapsed from p to q is 1 as x", "assert": "x.n is 1"}, doc, {}) == [true, "satisfied"]
	_elapsed_first({"for": "every xs whose days elapsed from p to q is 2 as x", "assert": "x.n is 1"}, doc, {}) == [false, "value"]
}

test_an_elapsed_time_goes_in_a_plus_on_either_side_of_a_phrase if {
	doc := [{"id": 1, "n": 3, "p": 0, "q": 86400}, {"id": 2, "n": 3, "p": 0, "q": "1970-01-02T00:00:00Z"}, {"id": 3, "n": 3, "p": null, "q": 86400}, {"id": 4, "n": "3", "p": 0, "q": 86400}, {"id": 5, "n": 3, "p": 86400, "q": 0}]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("days elapsed from p to q plus n is 4", doc, {})] == [[1, true, "satisfied"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("n is days elapsed from p to q", doc, {})] == [[1, false, "value"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
	with_x := [object.union(d, {"x": [1, 2]}) | some d in doc]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("n is less than 1 plus days elapsed from p to q plus count of x", with_x, {})] == [[1, true, "satisfied"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
}

test_an_elapsed_time_on_the_right_of_is_prints_as_is_not_equals if {
	ergo.report({"things": []}, _sentence_policy({"c": "n is days elapsed from p to q and m is not days elapsed from p to q and k is count of xs"}), {}).requirements.s.checks.c.expression == "n equals days elapsed from p to q and m does not equal days elapsed from p to q and k equals count of xs"
}

test_elapsed_cant_take_a_phrase_that_takes_no_number if {
	_sentence_problems("days elapsed from p to q is empty") == ["is empty can't follow a count of, a sum of or a plus"]
	_sentence_problems("days elapsed from p to q is before c") == ["is before can't follow a count of, a sum of or a plus"]
}

_listed_reqs(name) := {"r": {"subject": name, "checks": {"c": "id exists"}}}

_listed(subjects, name) := ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": _listed_reqs(name)}, {}).subjects

test_the_report_lists_a_subject_from_the_line_read_with_the_policy_not_by_reading_it_again if {
	read := {"lines": {"d": ergo._from_line("xs")}}
	ergo._subject_text("d", {"from": "ys"}) == "xs" with data.ergo_subject_sentences as read
}

test_the_report_lists_a_subject_with_its_description_from_and_id if {
	subjects := {"deployment": {"from": `deployments whose environment is "prod"`, "identified_by": "id", "description": "A deployment to production"}}
	_listed(subjects, "deployment") == {"deployment": {"description": "A deployment to production", "from": `deployments whose environment is "prod"`, "identified_by": "id", "parts": {}}}
}

test_a_listed_subject_carries_exactly_the_documented_keys if {
	rep := ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}}, "requirements": _listed_reqs("d")}, {})
	object.keys(rep.subjects.d) == {"description", "from", "identified_by", "parts"}
}

test_a_from_line_is_printed_the_canonical_way if {
	subjects := {"d": {"from": `  deployments   whose environment is   "prod"  and approved_by exists `}}
	_listed(subjects, "d").d.from == `deployments whose environment is "prod" and approved_by exists`
}

test_a_from_line_that_names_each_key_is_printed_with_it if {
	subjects := {"d": {"from": "trail.artifacts named by each of $params.names"}}
	_listed(subjects, "d").d.from == "trail.artifacts named by each of $params.names"
}

test_a_subject_that_narrows_another_is_listed_with_the_one_it_narrows if {
	subjects := {
		"round": {"from": "rounds", "identified_by": "id", "description": "A round"},
		"done": {"from": `round whose state is "done"`},
		"other": {"from": "others"},
	}
	_listed(subjects, "done") == {
		"done": {"description": "", "from": `round whose state is "done"`, "identified_by": "id", "parts": {}},
		"round": {"description": "A round", "from": "rounds", "identified_by": "id", "parts": {}},
	}
}

test_a_chain_of_narrowing_subjects_lists_every_subject_it_builds_on if {
	subjects := {
		"defect": {"from": "defects", "identified_by": "id"},
		"critical": {"from": `defect whose severity is "critical"`},
		"open critical": {"from": `critical whose state is "open"`},
	}
	object.keys(_listed(subjects, "open critical")) == {"defect", "critical", "open critical"}
	_listed(subjects, "open critical")["open critical"].identified_by == "id"
}

test_a_subject_read_from_another_is_listed_with_its_parent if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	rep.subjects == {
		"artifact": {"description": "", "from": "trail.artifacts named by $params.name", "identified_by": "fingerprint", "parts": {}},
		"pull request": {"description": "", "from": "artifact.pull_requests", "identified_by": "url", "parts": {}},
	}
}

test_a_parent_that_is_not_named_by_a_requirement_is_still_listed if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {})
	object.keys(rep.subjects) == {"artifact", "pull request"}
}

test_an_old_subject_without_filters_prints_just_its_path if {
	_listed({"d": {"from": "deployments"}}, "d").d.from == "deployments"
	_listed({"d": {"from": "$input", "identified_by": "id"}}, "d").d.from == "$input"
}

test_an_old_subject_that_names_each_key_prints_it if {
	subjects := {"d": {"from": "trail.artifacts named by each of $params.names"}}
	_listed(subjects, "d").d.from == "trail.artifacts named by each of $params.names"
}

test_a_subject_without_from_reads_the_input_field_named_like_it if {
	_listed({"deployments": {}}, "deployments").deployments.from == "deployments"
	_listed({"deployments": null}, "deployments").deployments.from == "deployments"
	_listed({"my deployments": {"identified_by": "id"}}, "my deployments")["my deployments"].from == `"my deployments"`
}

test_a_subject_without_identified_by_has_none if {
	every subjects in [{"d": {"from": "ds"}}, {"d": null}] {
		_listed(subjects, "d").d.identified_by == null
	}
}

test_an_id_written_in_the_old_syntax_is_printed_as_a_sentence_path if {
	_listed({"d": {"from": "ds", "identified_by": "build.number"}}, "d").d.identified_by == "build.number"
	_listed({"d": {"from": "ds", "identified_by": "build.number"}}, "d").d.identified_by == "build.number"
}

test_a_from_written_wrong_still_gets_an_entry_marked_invalid if {
	every from in ["???", "ds whose", "", 1, true, null, [true], [["a"]], [1.5]] {
		subjects := {"d": {"from": from, "identified_by": "id"}}
		_listed(subjects, "d").d.from == "<invalid from>"
	}
}

test_a_from_line_with_applies_to_or_of_is_marked_invalid if {
	_listed({"d": {"from": "ds", "applies_to": {"a": {"op": "present", "path": ["x"]}}}}, "d").d.from == "<invalid from>"
	_listed({"b": {"from": "bs"}, "d": {"from": "ds", "of": "b"}}, "d").d.from == "<invalid from>"
}

test_an_id_written_wrong_is_marked_invalid if {
	every id in ["???", 1, true] {
		_listed({"d": {"from": "ds", "identified_by": id}}, "d").d.identified_by == "<invalid identified_by>"
	}
}

test_a_subject_that_is_not_an_object_still_gets_an_entry if {
	every def in ["ds", 1, true, ["ds"]] {
		_listed({"d": def}, "d").d == {"description": "", "from": "<invalid from>", "identified_by": null, "parts": {}}
	}
}

test_a_subject_description_that_is_null_or_the_wrong_type_is_empty if {
	every description in [null, 1, true, [], {}] {
		_listed({"d": {"from": "ds", "description": description}}, "d").d.description == ""
	}
	_listed({"d": {"from": "ds"}}, "d").d.description == ""
}

test_a_subject_no_requirement_uses_is_not_listed if {
	subjects := {"used": {"from": "us"}, "unused": {"from": "others"}, "broken": {"from": "???"}}
	object.keys(_listed(subjects, "used")) == {"used"}
}

test_a_subject_nothing_builds_on_or_reads_from_is_not_listed_even_when_it_looks_related if {
	subjects := {"round": {"from": "rounds"}, "done": {"from": "round whose state is \"done\""}}
	object.keys(_listed(subjects, "round")) == {"round"}
}

test_no_subject_is_listed_when_no_requirement_names_one if {
	ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}}, "requirements": {"r": {"checks": {"c": "id exists"}}}}, {}).subjects == {}
	ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}}}, {}).subjects == {}
	ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}}, "requirements": {"r": {"subject": "nope", "checks": {"c": "id exists"}}}}, {}).subjects == {}
}

test_a_subjects_section_that_is_not_an_object_lists_nothing if {
	every subjects in [null, true, 1, "d", []] {
		ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": _listed_reqs("d")}, {}).subjects == {}
	}
}

test_a_requirement_reports_the_name_of_its_subject if {
	rep := ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}, "e": {"from": "es"}}, "requirements": {"a": {"subject": "d", "checks": {"c": "id exists"}}, "b": {"subject": "e", "checks": {"c": "id exists"}}}}, {})
	{name: entry.subject | some name, entry in rep.requirements} == {"a": "d", "b": "e"}
}

test_a_requirement_reports_no_subject_when_it_names_none_or_one_that_is_not_there if {
	every req in [{"checks": {"c": "id exists"}}, {"subject": "nope", "checks": {"c": "id exists"}}, {"subject": 1, "checks": {"c": "id exists"}}, {"subject": null, "checks": {"c": "id exists"}}, {"subject": ["d"], "checks": {"c": "id exists"}}] {
		ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": {"from": "ds"}}, "requirements": {"r": req}}, {}).requirements.r.subject == null
	}
	ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": [], "requirements": _listed_reqs("d")}, {}).requirements.r.subject == null
}

test_a_requirement_that_names_a_subject_written_wrong_still_reports_its_name if {
	ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": {"d": 1}, "requirements": _listed_reqs("d")}, {}).requirements.r.subject == "d"
}

test_the_subjects_section_is_independent_of_the_order_the_policy_is_written_in if {
	first := {"round": {"from": "rounds", "identified_by": "id"}, "done": {"from": `round whose state is "done"`}, "old": {"from": "ds whose .a exists and b exists"}}
	reqs := {"x": {"subject": "done", "checks": {"c": "id exists"}}, "y": {"subject": "old", "checks": {"c": "id exists"}}}
	one := ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": first, "requirements": reqs}, {})
	two := ergo.report({}, {"ergo_spec": "v0.3-dev", "requirements": {"y": reqs.y, "x": reqs.x}, "subjects": {"old": {"from": "ds whose .a exists and b exists"}, "done": first.done, "round": first.round}}, {})
	json.marshal(one) == json.marshal(two)
	one.subjects.old.from == "ds whose .a exists and b exists"
}

test_a_from_that_cannot_be_printed_is_invalid_even_when_nothing_flagged_it if {
	every def in [{"from": "ds", "applies_to": {}}, {"from": "ds", "of": "b"}, {"from": 1}, {"of": 1}] {
		ergo._subject_from_text("d", def, set()) == "<invalid from>" with data.ergo_resolved as {"d": {"problems": set()}} with data.ergo_subjects as {"d": def, "b": {}}
	}
}

_parts_policy(has, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"round": {"from": "trail", "identified_by": "name", "has": has}},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_parts_doc(d) := {"trail": {"name": "t1", "dd": d}}

_parts_report(has, checks, d) := ergo.report(_parts_doc(d), _parts_policy(has, checks), {})

_parts_rows(rep, check) := [r | some r in rep.results; r.check == check]

_parts_row(rep, check) := _parts_rows(rep, check)[0]

_parts_problems(rep) := {i.name: i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs}

test_a_part_alias_stands_for_its_path_inside_the_subject if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1"}, {"b": {"x": 1}})
	row := _parts_row(rep, "c")
	row.passed
	row.cause == "satisfied"
	_untagged(row.inputs) == [{"name": "cov.x", "value": 1, "locations": ["/trail/dd/b/x"]}]
	rep.requirements.r.checks.c.expression == "cov.x is 1"
}

test_a_part_can_be_a_path_to_one_value_and_a_check_can_read_the_alias_alone if {
	rep := _parts_report({"ratio": "dd.b.ratio"}, {"c": "ratio is at least 2"}, {"b": {"ratio": 3}})
	row := _parts_row(rep, "c")
	row.passed
	_untagged(row.inputs) == [{"name": "ratio", "value": 3, "locations": ["/trail/dd/b/ratio"]}]
}

test_a_part_in_the_long_form_works_like_one_written_as_a_line if {
	line := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1"}, {"b": {"x": 2}})
	long := _parts_report({"cov": {"from": "dd.b", "identified_by": "id"}}, {"c": "cov.x is 1"}, {"b": {"x": 2}})
	_parts_row(line, "c") == _parts_row(long, "c")
	_parts_row(line, "c").cause == "value"
}

test_a_missing_part_fails_as_absent_like_its_full_path if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "f": "dd.b.x is 1"}, {})
	_parts_row(rep, "c").cause == "absent"
	_parts_row(rep, "f").cause == "absent"
	rep2 := _parts_report({"cov": "dd.b"}, {"c": "cov exists", "f": "dd.b exists"}, {})
	_parts_row(rep2, "c").cause == "value"
	_parts_row(rep2, "f").cause == "value"
}

test_a_null_part_fails_as_null_when_the_alias_stands_alone_and_absent_when_a_step_follows if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "a": "cov is null", "f": "dd.b.x is 1"}, {"b": null})
	_parts_row(rep, "c").cause == "absent"
	_parts_row(rep, "f").cause == "absent"
	_parts_row(rep, "a").passed
}

test_a_wrong_typed_part_fails_as_unusable_like_its_full_path if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "f": "dd.b.x is 1"}, {"b": "text"})
	_parts_row(rep, "c").cause == "unusable"
	_parts_row(rep, "f").cause == "unusable"
	rep2 := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "f": "dd.b.x is 1"}, "text")
	_parts_row(rep2, "c").cause == "unusable"
	_parts_row(rep2, "f").cause == "unusable"
}

test_a_part_of_a_subject_that_is_not_an_object_fails_as_not_an_object_like_its_full_path if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"s": {"from": "items", "has": {"cov": "dd.b"}}},
		"requirements": {"r": {"subject": "s", "checks": {"c": "cov.x is 1", "f": "dd.b.x is 1"}}},
	}
	rep := ergo.report({"items": ["text", null, 5]}, policy, {})
	causes := [r.cause | some r in rep.results; r.check == "c"]
	causes == ["not_an_object", "not_an_object", "not_an_object"]
	[r.cause | some r in rep.results; r.check == "f"] == causes
}

test_a_part_keeps_its_ref_step_so_an_unreadable_param_fails_it_like_its_full_path if {
	has := {"by": "dd.m named by $params.k"}
	alias := ergo.report(_parts_doc({"m": {"q": {"x": 1}}}), _parts_policy(has, {"c": "by.x is 1"}), {"k": 1})
	full := ergo.report(_parts_doc({"m": {"q": {"x": 1}}}), _parts_policy({}, {"c": "dd.m named by $params.k.x is 1"}), {"k": 1})
	_parts_row(alias, "c").cause == _parts_row(full, "c").cause
	_parts_row(alias, "c").cause == "unusable"
	alias.requirements.r.checks.c["$refs"] == full.requirements.r.checks.c["$refs"]
	good := ergo.report(_parts_doc({"m": {"q": {"x": 1}}}), _parts_policy(has, {"c": "by.x is 1"}), {"k": "q"})
	_parts_row(good, "c").passed
}

test_the_names_in_a_row_keep_the_alias_and_the_values_are_the_full_paths if {
	has := {"lst": "dd.items", "pos": "dd.items[1]", "cov": "dd.b"}
	checks := {
		"every": "every lst.x is 1",
		"count": "count of lst is 2",
		"pos": "pos.x is 1",
		"alone": "pos exists",
		"two": "cov.x is at least cov.n",
	}
	d := {"items": [{"x": 1}, {"x": 2}], "b": {"x": 1, "n": 2}}
	rep := _parts_report(has, checks, d)
	_untagged(_parts_row(rep, "every").inputs) == [{"name": "lst[].x", "value": [1, 2], "locations": ["/trail/dd/items/0/x", "/trail/dd/items/1/x"]}]
	_parts_row(rep, "every").failed_items == [{"cause": "value", "item": "item 2 of lst", "path": "lst[1].x", "value": 2, "locations": ["/trail/dd/items/1/x"]}]
	_untagged(_parts_row(rep, "count").inputs) == [{"name": "count of lst", "value": 2, "locations": ["/trail/dd/items/0", "/trail/dd/items/1"]}, {"name": "lst[]", "value": [{"x": 1}, {"x": 2}], "locations": ["/trail/dd/items/0", "/trail/dd/items/1"]}]
	_untagged(_parts_row(rep, "pos").inputs) == [{"name": "pos.x", "value": 2, "locations": ["/trail/dd/items/1/x"]}]
	_untagged(_parts_row(rep, "alone").inputs) == [{"name": "pos", "value": {"x": 2}, "locations": ["/trail/dd/items/1"]}]
	_untagged(_parts_row(rep, "two").inputs) == [{"name": "cov.x", "value": 1, "locations": ["/trail/dd/b/x"]}, {"name": "cov.n", "value": 2, "locations": ["/trail/dd/b/n"]}]
	rep.requirements.r.checks.every.expression == "every lst.x is 1"
	rep.requirements.r.checks.pos.expression == "pos.x is 1"
}

test_an_alias_shadows_a_field_of_the_subject_with_the_same_name if {
	policy := _parts_policy({"cov": "dd.b"}, {"c": "cov.x is 1"})
	rep := ergo.report({"trail": {"name": "t1", "cov": {"x": 2}, "dd": {"b": {"x": 1}}}}, policy, {})
	_parts_row(rep, "c").passed
}

test_the_dot_in_front_of_a_field_reads_the_field_a_part_hides if {
	policy := _parts_policy({"cov": "dd.b"}, {"c": "cov.x is 1", "d": ".cov.x is 2", "e": "dd.b.x is 1 and .cov.x is 2"})
	rep := ergo.report({"trail": {"name": "t1", "cov": {"x": 2}, "dd": {"b": {"x": 1}}}}, policy, {})
	_parts_row(rep, "c").passed
	_parts_row(rep, "d").passed
	_parts_row(rep, "d").inputs == [{"name": "cov.x", "value": 2, "locations": ["/trail/cov/x"]}]
	_parts_row(rep, "e").passed
}

test_a_field_of_the_subject_with_no_alias_in_the_way_is_read_as_before if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "name is \"t1\""}, {})
	_parts_row(rep, "c").passed
}

test_a_child_reads_its_parents_part_on_the_right_inside_an_items_scope if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {
			"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
			"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url"},
		},
		"requirements": {"r": {"subject": "pull request", "checks": {
			"every": "every reviews.by equals artifact.pra.boss",
			"whose": `some reviews.by whose by equals artifact.pra.boss is "bob"`,
			"for": {"for": "some reviews whose by equals artifact.pra.boss as rv", "assert": `rv.by is "bob"`},
		}}},
	}
	doc := {"artifacts": [{"fingerprint": "f1", "attestations": {"pr": {"boss": "bob", "pull_requests": [{"url": "u1", "reviews": [{"by": "bob"}]}]}}}]}
	{r.check: r.cause | some r in ergo.report(doc, policy, {}).results; not startswith(r.check, "$")} == {"every": "satisfied", "whose": "satisfied", "for": "satisfied"}
}

_parent_name_policy(checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {
		"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url"},
	},
	"requirements": {"r": {"subject": "pull request", "checks": checks}},
}

_parent_name_doc := {"artifacts": [{"fingerprint": "f1", "attestations": {"pr": {"pull_requests": [{"url": "u1", "artifact": "bob", "reviews": [{"by": "bob", "artifact": "f1"}]}]}}}]}

test_a_parents_name_reads_like_any_other_name if {
	rep := ergo.report(
		_parent_name_doc, _parent_name_policy({
			"right": "every reviews.artifact equals artifact.fingerprint",
			"whose_left": `some reviews.by whose artifact is "f1" is "bob"`,
			"dot": `.artifact is "bob"`,
		}),
		{},
	)
	{r.check: r.cause | some r in rep.results; not startswith(r.check, "$")} == {"right": "satisfied", "whose_left": "satisfied", "dot": "satisfied"}
}

test_a_dot_in_a_later_for_item_reads_the_subjects_field if {
	checks := {"c": {"for": "some approvals as ap, every .ap.r as r", "assert": "r is 1"}}
	doc := {"things": [{"id": "t1", "ap": {"r": [1]}, "approvals": [{"r": [2]}]}]}
	[r.cause | some r in ergo.report(doc, _sentence_policy(checks), {}).results; r.check == "c"] == ["satisfied"]
}

test_a_part_on_the_right_of_a_whose_in_a_count_or_a_sum_is_the_part if {
	rep := _parts_report(
		{"cov": "dd.b"}, {
			"count": "count of dd.items whose x equals cov.x is 1",
			"sum": "sum of dd.items.x whose x equals cov.x is 5",
		},
		{"b": {"x": 5}, "items": [{"x": 5}, {"x": 6}]},
	)
	_parts_row(rep, "count").passed
	_parts_row(rep, "sum").passed
}

test_a_whose_in_a_count_compared_with_itself_says_the_subject_cant_be_read_there if {
	message := "x is compared with itself, because in a whose it's read from the item, and a count or a sum can't read the subject's field there yet"
	_sentence_problems("count of xs whose x equals x is 2") == [message]
	_sentence_problems("sum of xs.y whose x equals .x is 2") == [message]
}

test_a_part_on_the_right_after_every_is_not_the_item_compared_with_itself if {
	rep := _parts_report(
		{"cov": "dd.b"}, {
			"walk": "every dd.items.cov equals cov.x",
			"whose": "every dd.items.x whose cov equals cov.x is at least 5",
		},
		{"b": {"x": 5}, "items": [{"cov": 5, "x": 5}]},
	)
	_parts_row(rep, "walk").passed
	_parts_row(rep, "whose").passed
	stopped(_parts_report({"cov": "dd.b"}, {"plain": "cov.x equals cov.x"}, {"b": {"x": 5}}))
}

test_a_part_is_the_items_field_on_the_left_of_a_whose_and_the_part_on_the_right if {
	has := {"cov": "dd.b"}
	d := {"b": {"x": 5}, "items": [{"cov": 5, "x": 5}, {"cov": 7, "x": 6}]}
	rep := _parts_report(
		has, {
			"w": "every dd.items.x whose cov is at least 5 is at least 5",
			"a": "every dd.items.x is at least cov.x",
			"r": "every dd.items.x whose x is at least cov.x is at least 5",
			"d": "every dd.items.x equals .cov",
		},
		d,
	)
	_parts_row(rep, "w").passed
	_parts_row(rep, "a").passed
	_parts_row(rep, "r").passed
	_parts_row(rep, "d").cause == "value"
	_parts_row(rep, "d").failed_items == [{"cause": "value", "item": "item 2 of dd.items", "path": "dd.items[1].x", "value": 6, "locations": ["/trail/dd/items/1/x"]}]
}

test_an_alias_works_on_the_subject_in_a_for_line_and_not_on_its_items if {
	has := {"cov": "dd.b", "lst": "dd.items"}
	checks := {
		"c": {"for": "every lst as entry", "assert": ["entry.x is cov.x", "cov.s exists"]},
		"d": {"for": "some lst whose y is 2 as entry", "assert": "entry.x is 1"},
		"e": {"for": "every lst as entry, every entry.sub as s", "assert": "s is cov.x"},
	}
	d := {"b": {"x": 1, "s": "a"}, "items": [{"x": 1, "y": 2, "sub": [1]}, {"x": 1, "y": 3, "sub": [1, 1]}]}
	rep := _parts_report(has, checks, d)
	every c in ["c", "d", "e"] {
		_parts_row(rep, c).passed
	}
	rep.requirements.r.checks.c.expression == "for every lst as entry: entry.x equals cov.x and cov.s exists"
	_untagged(_parts_row(rep, "c").inputs) == [{"name": "cov.s", "value": "a", "locations": ["/trail/dd/b/s"]}, {"name": "cov.x", "value": 1, "locations": ["/trail/dd/b/x"]}, {"name": "lst[]", "value": [{"sub": [1], "x": 1, "y": 2}, {"sub": [1, 1], "x": 1, "y": 3}], "locations": ["/trail/dd/items/0", "/trail/dd/items/1"]}]
}

test_a_for_line_alias_that_is_also_a_part_alias_is_written_wrong if {
	has := {"cov": "dd.b"}
	rep := _parts_report(has, {"c": {"for": "every dd.items as cov", "assert": "cov.x is 1"}}, {"items": [{"x": 1}]})
	_parts_problems(rep)["checks.c"] == ["cov can't be an alias: it's a part of round"]
	stopped(rep)
}

test_a_whose_of_two_conditions_in_the_from_line_keeps_the_part_of_each_input if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"round": {"from": "rounds whose cov.x is 1 and cov.n is 2", "identified_by": "id", "has": {"cov": "dd.b"}}},
		"requirements": {"r": {"subject": "round", "checks": {"c": "cov.n is 2"}}},
	}
	rep := ergo.report({"rounds": [{"id": "a", "dd": {"b": {"x": 1, "n": 2}}}]}, policy, {})
	[r.inputs | some r in rep.results; r.check == "$applies"] == [[
		{"name": "cov.n", "part": {"id": null, "name": "cov"}, "value": 2, "locations": ["/rounds/0/dd/b/n"]},
		{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": 1, "locations": ["/rounds/0/dd/b/x"]},
	]]
}

test_a_whose_in_the_from_line_reads_the_subjects_parts if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"round": {"from": "rounds whose cov.x is 1", "identified_by": "id", "has": {"cov": "dd.b"}}},
		"requirements": {"r": {"subject": "round", "checks": {"c": "cov.n is 2"}}},
	}
	rep := ergo.report({"rounds": [{"id": "a", "dd": {"b": {"x": 1, "n": 2}}}, {"id": "b", "dd": {"b": {"x": 2, "n": 2}}}, {"id": "c", "dd": {}}]}, policy, {})
	[[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"] == [
		["a", "satisfied", [{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": 1, "locations": ["/rounds/0/dd/b/x"]}]],
		["b", "value", [{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": 2, "locations": ["/rounds/1/dd/b/x"]}]],
		["c", "absent", [{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": null, "locations": ["/rounds/2/dd"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == "cov.x is 1"
	[r.subject.id | some r in rep.results; r.check == "c"] == ["a"]
}

_parts_narrow := {
	"ergo_spec": "v0.3-dev",
	"subjects": {
		"round": {"from": "rounds", "identified_by": "id", "has": {"cov": "dd.b"}},
		"good round": {"from": "round whose cov.x is 1", "has": {"extra": "dd.e"}},
	},
	"requirements": {
		"r": {"subject": "good round", "checks": {"c": "cov.n is 2 and extra is 5"}},
	},
}

_parts_rounds := {"rounds": [{"id": "a", "dd": {"b": {"x": 1, "n": 2}, "e": 5}}, {"id": "b", "dd": {"b": {"x": 2, "n": 2}, "e": 5}}]}

test_re_adding_a_kept_alias_is_written_wrong_and_names_the_subject_it_comes_from if {
	subjects := object.union(_parts_narrow.subjects, {"good round": {"from": "round whose cov.x is 1", "has": {"cov": "dd.q"}}})
	rep := ergo.report(_parts_rounds, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "good round", "checks": {"c": "cov.n is 2"}}}}, {})
	_parts_problems(rep)["subjects.\"good round\".has.cov"] == ["cov can't be an alias: it's a part of round"]
}

test_two_subjects_that_do_not_narrow_each_other_can_use_the_same_alias if {
	subjects := {
		"a": {"from": "xs", "has": {"cov": "p"}},
		"b": {"from": "ys", "has": {"cov": "q"}},
	}
	policy := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"ra": {"subject": "a", "checks": {"c": "cov is 1"}}, "rb": {"subject": "b", "checks": {"c": "cov is 2"}}}}
	rep := ergo.report({"xs": [{"p": 1, "q": 2}], "ys": [{"p": 1, "q": 2}]}, policy, {})
	[r.passed | some r in rep.results; r.check == "c"] == [true, true]
}

_parts_chain := {
	"ergo_spec": "v0.3-dev",
	"subjects": {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url", "has": {"rev": "reviews"}},
	},
	"requirements": {"r": {"subject": "pull request", "checks": {
		"parent": "artifact.pra.name is \"w\"",
		"own": "rev.count is 2",
		"field": "pra is 1",
		"every": "every artifact.pra.pull_requests.url is not empty",
	}}},
}

_parts_chain_doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "pra": 1, "attestations": {"pr": {"name": "w", "pull_requests": [
	{"url": "pr/7", "reviews": {"count": 2}},
	{"url": "pr/8", "reviews": {"count": 1}},
]}}}}}}

test_a_chained_subject_reads_its_parents_parts_and_starts_from_one if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	[[r.subject.id, r.check, r.passed, r.cause] | some r in rep.results; r.check in {"parent", "own", "field", "every"}] == [
		["pr/7", "every", true, "satisfied"], ["pr/7", "field", false, "absent"], ["pr/7", "own", true, "satisfied"], ["pr/7", "parent", true, "satisfied"],
		["pr/8", "every", true, "satisfied"], ["pr/8", "field", false, "absent"], ["pr/8", "own", false, "value"], ["pr/8", "parent", true, "satisfied"],
	]
	_untagged(_parts_row(rep, "parent").inputs) == [{"name": "artifact.pra.name", "value": "w", "locations": ["/trail/artifacts/web/attestations/pr/name"]}]
	_untagged(_parts_row(rep, "every").inputs) == [{"name": "artifact.pra.pull_requests[].url", "value": ["pr/7", "pr/8"], "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/url", "/trail/artifacts/web/attestations/pr/pull_requests/1/url"]}]
	rep.subjects["pull request"].from == "artifact.pra.pull_requests"
}

test_a_part_is_only_reached_through_its_subject_so_a_bare_alias_in_a_chained_child_is_a_field if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	_parts_row(rep, "field").inputs == [{"name": "pra", "value": null, "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0"]}]
	_parts_row(rep, "field").cause == "absent"
}

test_a_chained_subject_cannot_use_its_parents_name_as_a_part_alias_because_it_is_a_subjects_name if {
	subjects := object.union(_parts_chain.subjects, {"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url", "has": {"artifact": "reviews"}}})
	rep := ergo.report(_parts_chain_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": _parts_chain.requirements}, {"art": "web"})
	_parts_problems(rep)["subjects.\"pull request\".has.artifact"] == ["artifact can't be an alias: it's a subject's name"]
}

test_a_problem_in_a_parent_subjects_has_fails_the_requirements_of_its_chained_child if {
	subjects := object.union(_parts_chain.subjects, {"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": 5}}})
	rep := ergo.report(_parts_chain_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": _parts_chain.requirements}, {"art": "web"})
	_parts_problems(rep)["subjects.artifact.has.pra"] == ["not a string or an object"]
}

test_a_chained_child_cannot_read_a_part_the_parent_does_not_have if {
	policy := object.union(_parts_chain, {"requirements": {"r": {"subject": "pull request", "checks": {"c": "artifact.nope.name is \"w\""}}}})
	rep := ergo.report(_parts_chain_doc, policy, {"art": "web"})
	_parts_row(rep, "c").cause == "absent"
}

test_a_path_shaped_like_an_internal_part_marker_does_not_read_the_subject if {
	forged := "${\"alias\":\"cov\",\"n\":0,\"of\":null,\"old\":false}"
	honest := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1"}, {"b": {"x": 1}})
	rep := _parts_report({"cov": "dd.b"}, {"c": concat("", [json.marshal(forged), ".x is 1"])}, {"b": {"x": 1}})
	[_parts_row(honest, "c").passed, _parts_row(rep, "c").passed, _parts_row(rep, "c").cause] == [true, false, "absent"]
	[object.keys(i) | some i in _parts_row(rep, "c").inputs] == [{"locations", "name", "value"}]
}

test_a_subject_with_no_has_is_listed_with_no_parts if {
	rep := ergo.report({"trail": {"name": "t1"}}, _parts_policy({}, {"c": "name is \"t1\""}), {})
	rep.subjects.round.parts == {}
	_parts_row(rep, "c").passed
}

test_the_report_lists_every_part_with_its_path_as_written_canonically_and_its_id if {
	has := {
		"a": "  dd.b  ",
		"b": {"from": "dd.\"x y\".z", "identified_by": "attestation_id"},
		"c": {"from": "dd.m named by $params.k"},
		"d": "dd.items[1].y",
		"e": "item 3 of dd.items",
		"f": "dd.m[$params.k]",
	}
	rep := _parts_report(has, {"c": "name is \"t1\""}, {})
	rep.subjects.round.parts == {
		"a": {"from": "dd.b", "identified_by": null},
		"b": {"from": "dd.\"x y\".z", "identified_by": "attestation_id"},
		"c": {"from": "dd.m named by $params.k", "identified_by": null},
		"d": {"from": "dd.items[1].y", "identified_by": null},
		"e": {"from": "item 3 of dd.items", "identified_by": null},
		"f": {"from": "dd.m named by $params.k", "identified_by": null},
	}
}

test_the_report_shows_a_part_written_wrong_as_best_it_can if {
	has := {
		"bad_from": {"from": "dd.b whose x is 1", "identified_by": "id"},
		"bad_id": {"from": "dd.b", "identified_by": 5},
		"no_from": {"identified_by": "id"},
		"number": 5,
		"bad alias": "dd.b",
	}
	rep := _parts_report(has, {"c": "name is \"t1\""}, {})
	rep.subjects.round.parts == {
		"bad alias": {"from": "dd.b", "identified_by": null},
		"bad_from": {"from": "<invalid from>", "identified_by": "id"},
		"bad_id": {"from": "dd.b", "identified_by": "<invalid identified_by>"},
		"no_from": {"from": "<invalid from>", "identified_by": "id"},
		"number": {"from": "<invalid from>", "identified_by": null},
	}
}

test_a_has_that_is_not_an_object_is_written_wrong_and_lists_no_parts if {
	rep := _parts_report("cov", {"c": "name is \"t1\""}, {})
	_parts_problems(rep)["subjects.round.has"] == ["not an object"]
	rep.subjects.round.parts == {}
}

test_every_way_a_part_can_be_written_wrong_is_named_with_its_alias if {
	has := {
		"num": 5,
		"nofrom": {"identified_by": "id"},
		"extra": {"from": "x", "other": 1},
		"fromnum": {"from": 1},
		"idnum": {"from": "x", "identified_by": 1},
		"who": "x whose y is 1",
		"eacha": "x named by each of $params.k",
		"cnt": "count of x",
		"prm": "$params.x",
		"inp": "$input.x",
		"nobare": "x named by foo",
		"emp": "",
		"idbad": {"from": "x", "identified_by": "y whose z is 1"},
		"$dollar": "x",
		"with space": "x",
		"plain": "x",
		"item": "x",
	}
	problems := _parts_problems(_parts_report(has, {"c": "name is \"t1\""}, {}))
	problems["subjects.round.has.num"] == ["not a string or an object"]
	problems["subjects.round.has.nofrom"] == ["missing from"]
	problems["subjects.round.has.extra"] == ["unknown field other"]
	problems["subjects.round.has.fromnum"] == ["invalid from"]
	problems["subjects.round.has.idnum"] == ["invalid identified_by"]
	problems["subjects.round.has.who"] == ["from: a part is a path: whose and named by each of can't go in it"]
	problems["subjects.round.has.eacha"] == ["from: a part is a path: whose and named by each of can't go in it"]
	problems["subjects.round.has.cnt"] == ["from: doesn't parse"]
	problems["subjects.round.has.prm"] == ["from: a part reads inside its subject, so it can't start at $params or $input"]
	problems["subjects.round.has.inp"] == ["from: a part reads inside its subject, so it can't start at $params or $input"]
	problems["subjects.round.has.nobare"] == ["from: unknown alias foo"]
	problems["subjects.round.has.emp"] == ["from: doesn't parse"]
	problems["subjects.round.has.idbad"] == ["identified_by: a part is a path: whose and named by each of can't go in it"]
	problems["subjects.round.has.$dollar"] == ["invalid alias"]
	problems["subjects.round.has.\"with space\""] == ["invalid alias"]
	problems["subjects.round.has.item"] == ["invalid alias"]
	not "subjects.round.has.plain" in object.keys(problems)
}

test_a_part_alias_must_be_a_bare_word_that_is_not_a_word_of_the_grammar_or_params_or_input if {
	bad := ["empty", "every", "params", "input", "true", "a", "x y", "$x", "", "1x", "x.y", "é"]
	every alias in bad {
		problems := _parts_problems(_parts_report({alias: "x"}, {"c": "name is \"t1\""}, {}))
		some key, value in problems
		contains(key, "subjects.round.has")
		value == ["invalid alias"]
	}
	good := ["x", "_x", "x-y", "x_1", "Cov", "coverage-verification"]
	every alias in good {
		problems := _parts_problems(_parts_report({alias: "x"}, {"c": "name is \"t1\""}, {}))
		count([k | some k, _ in problems; contains(k, "subjects.round.has")]) == 0
	}
}

test_a_named_by_that_names_a_part_alias_is_written_wrong_because_it_would_read_the_subjects_field if {
	has := {"cov": "dd.k"}
	checks := {
		"a": "$params.m named by cov is 1",
		"b": "every dd.items.z whose $params.m named by cov is 1 is 2",
		"c": {"for": "every dd.items as entry", "assert": "$params.m named by entry is 1"},
	}
	problems := _parts_problems(_parts_report(has, checks, {"k": "q"}))
	problems["checks.a"] == ["named by cov reads a part, which isn't supported yet"]
	problems["checks.b"] == ["named by cov reads a part, which isn't supported yet"]
	not "checks.c" in object.keys(problems)
}

test_as_sentences_leaves_an_old_check_that_names_an_alias_as_written_because_a_sentence_would_read_the_part if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"s": {"from": ["items"], "has": {"cov": "dd.b"}}},
		"requirements": {"r": {"subject": "s", "checks": {
			"a": "cov.x is 1",
			"b": "other.x is 1",
			"c": {"op": "equals", "path": ["$cov", "x"], "value": 1},
		}}},
	}
	converted := ergo.as_sentences(policy)
	converted.requirements.r.checks.a == "cov.x is 1"
	converted.requirements.r.checks.b == "other.x is 1"
	converted.requirements.r.checks.c == {"op": "equals", "path": ["$cov", "x"], "value": 1}
	converted.subjects.s.has == {"cov": "dd.b"}
}

test_a_problem_in_has_names_the_subject_that_holds_it_for_every_requirement_that_builds_on_it if {
	subjects := {
		"round": {"from": "rounds", "has": {"cov": 5}},
		"good": {"from": "round whose x is 1"},
	}
	rep := ergo.report({"rounds": [{"x": 1}]}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "good", "checks": {"c": "x is 1"}}}}, {})
	_parts_problems(rep)["subjects.round.has.cov"] == ["not a string or an object"]
}

test_a_part_with_no_alias_clash_works_when_another_subject_of_the_policy_is_written_wrong if {
	subjects := {
		"round": {"from": "rounds", "has": {"cov": "dd.b"}},
		"bad": {"from": "rounds", "has": 5},
	}
	policy := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "round", "checks": {"c": "cov.x is 1"}}}}
	rep := ergo.report({"rounds": [{"dd": {"b": {"x": 1}}}]}, policy, {})
	_parts_row(rep, "c").passed
	not "subjects.bad.has" in object.keys(_parts_problems(rep))
}

_swap_has := {
	"cov": "dd.b",
	"lst": "dd.items",
	"uno": "dd.b.x",
	"by": "dd.m named by $params.k",
	"pos": "dd.items[1]",
}

_swap_full := {
	"@cov": "dd.b",
	"@lst": "dd.items",
	"@uno": "dd.b.x",
	"@by": "dd.m named by $params.k",
	"@pos": "dd.items[1]",
}

_swap_alias := {
	"@cov": "cov",
	"@lst": "lst",
	"@uno": "uno",
	"@by": "by",
	"@pos": "pos",
}

_swap_lines := [
	"@cov.x is 1",
	"@cov.x is not 1",
	"@cov.x exists",
	"@cov.x does not exist",
	"@cov.s is a non-empty string",
	"@cov.x is one of 1, 2",
	"@cov.x is not one of 1, 2",
	"@cov.s matches \"^a\"",
	"@cov.s does not match \"^b\"",
	"@cov.s starts with \"a\"",
	"@cov.x is at least 2",
	"@cov.x is between 1 and 3",
	"@cov.x equals @cov.n",
	"@cov.x does not equal @cov.n",
	"@cov.t is before @cov.t2",
	"@cov.items is empty",
	"@cov.items is not empty",
	"@cov exists",
	"@cov.x is a number",
	"@cov.x is 1 and @cov.n is 2",
	"@uno is 1",
	"@uno exists",
	"@by.x is 1",
	"@by exists",
	"@pos.x is 1",
	"@pos exists",
]

_swap_walks := [
	"every @lst.x is 1",
	"some @lst.x is 1",
	"every @lst.x whose y is 2 is 1",
	"every @lst.x is at least 1",
	"every @lst, if any, is not empty",
	"some @lst.x whose y is 2 is 1",
	"every @lst.sub is not empty",
	"count of @lst is 2",
	"count of @lst whose y is 2 is 1",
	"sum of @lst.n is 5",
	"sum of @lst.n whose y is 2 is 2",
	"@cov.x plus @cov.n is 3",
	"count of @lst plus @cov.x is 3",
	"days elapsed from @cov.t to @cov.t2 is 1",
	"count of @lst is @cov.x",
	"sum of @lst.n equals @cov.n within 0.5",
]

_swap_fors := [
	{"for": "every @lst as entry", "assert": "entry.x is 1"},
	{"for": "every @lst as entry", "assert": ["entry.x is @cov.x", "@cov.s exists"]},
	{"for": "some @lst whose y is 2 as entry", "assert": ["entry.x is 1", "@cov.s exists"]},
	{"for": "every @lst as entry, every entry.sub as s", "assert": "s is @cov.x"},
	{"for": "every @lst as entry", "assert": "count of entry.sub is @cov.x"},
	{"for": "every @lst as entry", "assert": "entry.x is @uno"},
	{"for": "every @cov.items as entry", "assert": "entry.x is @uno"},
]

_swap_old_alias := {"cov": ["$cov"], "lst": ["$lst"], "uno": ["$uno"]}

_swap_checks(replacements, lines, walks, fors) := object.union(
	{sprintf("l%02d", [i]): strings.replace_n(replacements, line) | some i, line in lines},
	object.union(
		{sprintf("w%02d", [i]): strings.replace_n(replacements, line) | some i, line in walks},
		{sprintf("f%02d", [i]): _swap_for(replacements, item) | some i, item in fors},
	),
)

_swap_for(replacements, item) := {"for": strings.replace_n(replacements, item.for), "assert": _swap_assert(replacements, item.assert)}

_swap_assert(replacements, a) := strings.replace_n(replacements, a) if is_string(a)

_swap_assert(replacements, a) := [strings.replace_n(replacements, line) | some line in a] if is_array(a)

_swap_policy(has, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"round": _swap_subject(has)},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_subject(has) := {"from": "trail", "identified_by": "name", "has": has} if count(has) > 0

_swap_subject(has) := {"from": "trail", "identified_by": "name"} if count(has) == 0

_swap_view(rep) := {
	"rows": [{
		"check": r.check,
		"subject": r.subject,
		"passed": r.passed,
		"cause": r.cause,
		"values": {i.value | some i in r.inputs},
		"failed": {[f.cause, f.value, [a.cause | some a in object.get(f, "failed_assertions", [])]] | some f in object.get(r, "failed_items", [])},
		"lines": [a.cause | some a in object.get(r, "failed_assertions", [])],
	} |
		some r in rep.results
	],
	"requirement": {c: {x.value | some x in object.get(d, "$refs", [])} | some c, d in rep.requirements.r.checks},
	"status": rep.requirements.r.status,
	"causes": rep.requirements.r.causes,
}

_swap_item(x, y, n, sub) := {"x": x, "y": y, "n": n, "sub": sub}

_swap_good := {
	"b": {"x": 1, "s": "abc", "n": 2, "t": "2026-01-01T00:00:00Z", "t2": "2026-01-02T00:00:00Z", "items": [1, 2]},
	"items": [_swap_item(1, 2, 2, [1]), _swap_item(1, 3, 3, [1, 1])],
	"m": {"m1": {"x": 1}},
}

_swap_group_checks("lines_a", replacements) := _swap_checks(replacements, array.slice(_swap_lines, 0, 13), [], [])

_swap_group_checks("lines_b", replacements) := _swap_checks(replacements, array.slice(_swap_lines, 13, count(_swap_lines)), [], [])

_swap_group_checks("walks", replacements) := _swap_checks(replacements, [], _swap_walks, [])

_swap_group_checks("fors", replacements) := _swap_checks(replacements, [], [], _swap_fors)

_swap_good_with(f, v) := {"trail": {"name": "t1", "dd": object.union(_swap_good, {f: v})}}

_swap_good_without(f) := {"trail": {"name": "t1", "dd": object.remove(_swap_good, [f])}}

_swap_scenarios := {
	"everything_is_there": {"doc": _parts_doc(_swap_good), "params": {"k": "m1"}},
	"everything_is_there_and_no_params": {"doc": _parts_doc(_swap_good), "params": {}},
	"the_named_by_param_is_a_number": {"doc": _parts_doc(_swap_good), "params": {"k": 1}},
	"the_named_by_param_is_null": {"doc": _parts_doc(_swap_good), "params": {"k": null}},
	"the_named_by_key_is_not_in_its_object": {"doc": _swap_good_with("m", {}), "params": {"k": "m1"}},
	"an_object_part_is_missing": {"doc": _swap_good_without("b"), "params": {"k": "m1"}},
	"an_object_part_is_null": {"doc": _swap_good_with("b", null), "params": {"k": "m1"}},
	"an_object_part_is_text": {"doc": _swap_good_with("b", "text"), "params": {"k": "m1"}},
	"an_object_part_is_a_list": {"doc": _swap_good_with("b", [1]), "params": {"k": "m1"}},
	"a_field_inside_a_part_is_null": {"doc": _swap_good_with("b", object.union(_swap_good.b, {"x": null})), "params": {"k": "m1"}},
	"the_fields_inside_a_part_have_the_wrong_types": {"doc": _swap_good_with("b", {"x": "1", "s": 5, "n": "2", "t": "nope", "t2": 3, "items": "s"}), "params": {"k": "m1"}},
	"the_list_is_missing": {"doc": _swap_good_without("items"), "params": {"k": "m1"}},
	"the_list_is_null": {"doc": _swap_good_with("items", null), "params": {"k": "m1"}},
	"the_list_is_empty": {"doc": _swap_good_with("items", []), "params": {"k": "m1"}},
	"the_list_is_a_string": {"doc": _swap_good_with("items", "str"), "params": {"k": "m1"}},
	"the_list_holds_a_number_and_a_null": {"doc": _swap_good_with("items", [_swap_item(1, 2, 2, [1]), 5, null]), "params": {"k": "m1"}},
	"the_list_holds_items_with_missing_and_wrong_fields": {"doc": _swap_good_with("items", [_swap_item(null, 2, "q", []), {"y": 2}]), "params": {"k": "m1"}},
	"the_named_by_part_is_null": {"doc": _swap_good_with("m", null), "params": {"k": "m1"}},
	"the_named_by_part_is_text": {"doc": _swap_good_with("m", "s"), "params": {"k": "m1"}},
	"the_named_by_part_is_missing": {"doc": _swap_good_without("m"), "params": {"k": "m1"}},
	"the_subject_has_no_part_field": {"doc": {"trail": {"name": "t1"}}, "params": {"k": "m1"}},
	"the_part_field_is_null": {"doc": {"trail": {"name": "t1", "dd": null}}, "params": {"k": "m1"}},
	"the_part_field_is_text": {"doc": {"trail": {"name": "t1", "dd": "s"}}, "params": {"k": "m1"}},
	"the_part_field_is_a_list": {"doc": {"trail": {"name": "t1", "dd": [1]}}, "params": {"k": "m1"}},
}

_swap_batch_policy(has, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"round": object.union(_swap_subject(has), {"from": "trails"})},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_scenario_rows(rep, n) := [r | some r in rep.results; r.subject.id in {n, null}]

_swap_scenario_view(rep, n) := _swap_view({"results": _swap_scenario_rows(rep, n), "requirements": rep.requirements})

_swap_differences(group) := {n |
	some params in {s.params | some s in _swap_scenarios}
	names := {m | some m, s in _swap_scenarios; s.params == params}
	doc := {"trails": [object.union(_swap_scenarios[m].doc.trail, {"name": m}) | some m in names]}
	checks := _swap_group_checks(group, _swap_alias)
	alias := ergo.report(doc, _swap_batch_policy(_swap_has, checks), params)
	full := ergo.report(doc, _swap_batch_policy({}, _swap_group_checks(group, _swap_full)), params)
	some n in names
	_swap_differs(alias, full, n, checks)
}

_swap_differs(alias, full, n, _) if _swap_scenario_view(alias, n) != _swap_scenario_view(full, n)

_swap_differs(alias, _, n, checks) if object.keys(checks) - {r.check | some r in _swap_scenario_rows(alias, n)} != set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_first_one_line_checks if _swap_differences("lines_a") == set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_other_one_line_checks if _swap_differences("lines_b") == set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_checks_that_walk_lists if _swap_differences("walks") == set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_for_line_checks if _swap_differences("fors") == set()

test_the_batched_swap_comparison_names_each_scenario_where_a_part_reads_the_wrong_path if {
	scenarios := {n: _swap_scenarios[n] | some n in {"everything_is_there", "the_named_by_param_is_a_number", "the_subject_has_no_part_field"}}
	differences := _swap_differences("lines_b") with data.ergo_test._swap_has as object.union(_swap_has, {"by": "dd.m named by $params.j"})
		with data.ergo_test._swap_scenarios as scenarios
	differences == {"everything_is_there", "the_named_by_param_is_a_number", "the_subject_has_no_part_field"}
}

test_the_batched_swap_comparison_names_a_scenario_that_has_no_row_for_a_check if {
	_swap_differs({"results": [{"check": "c", "subject": {"id": "other"}}]}, {}, "s", {"c": "x is 1"})
}

test_the_swap_comparison_would_notice_a_part_that_reads_the_wrong_path if {
	alias := ergo.report(_parts_doc(_swap_good), _swap_policy({"cov": "dd.items"}, {"c": "cov.x is 1"}), {})
	full := ergo.report(_parts_doc(_swap_good), _swap_policy({}, {"c": "dd.b.x is 1"}), {})
	_swap_view(alias) != _swap_view(full)
}

test_the_swap_comparison_sees_rows_of_every_kind_of_outcome if {
	text := _swap_scenarios.an_object_part_is_text
	one := ergo.report(text.doc, _swap_policy(_swap_has, _swap_group_checks("lines_a", _swap_alias)), text.params)
	{"unusable"} - {r.cause | some r in one.results; startswith(r.check, "l")} == set()
	walks := ergo.report(_swap_scenarios.the_list_holds_a_number_and_a_null.doc, _swap_policy(_swap_has, _swap_group_checks("walks", _swap_alias)), {"k": "m1"})
	{"value", "satisfied"} - {r.cause | some r in walks.results; startswith(r.check, "w")} == set()
}

test_the_swap_comparison_sees_a_subject_that_is_not_an_object if {
	nothing := _swap_scenarios.the_part_field_is_text
	rep := ergo.report(nothing.doc, _swap_policy(_swap_has, _swap_group_checks("fors", _swap_alias)), nothing.params)
	{"unusable"} - {r.cause | some r in rep.results; startswith(r.check, "f")} == set()
}

_deep_all(p, check) := {"op": "all", "path": p.lst, "check": check}

_deep_at(level, _, options) := {"op": "any_of", "options": options} if level == "a"

_deep_at(level, p, options) := _deep_all(p, {"op": "any_of", "options": options}) if level == "b"

_deep_at(level, p, options) := _deep_all(p, {"op": "all", "path": ["sub"], "check": {"op": "any_of", "options": options}}) if level == "c"

_deep_at(level, p, options) := {"op": "any_of", "options": [[_deep_all(p, {"op": "all", "path": ["sub"], "check": {"op": "any_of", "options": options}})]]} if level == "d"

test_a_group_of_options_that_is_not_a_list_or_holds_a_non_object_is_written_wrong_at_every_depth if {
	every level in ["a", "b", "c", "d"] {
		every options in [{"g": "nope"}, ["nope"], {"g": [5]}, [[5]]] {
			check := _deep_at(level, _swap_old_alias, options)
			stopped(ergo.report(_parts_doc(_swap_good), _swap_policy(_swap_has, {"c": check}), {}))
		}
	}
}

_deep_nest(n, leaf) := {"op": "all", "path": ["xs"], "check": leaf} if n == 1

_deep_nest(n, leaf) := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": leaf}} if n == 2

_deep_nest(n, leaf) := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": leaf}}} if n == 3

_deep_nest(n, leaf) := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["xs"], "check": leaf}}}} if n == 4

test_a_nested_check_that_is_not_an_object_is_written_wrong_at_every_depth_and_does_not_hide_the_row if {
	every n in [1, 2, 3, 4] {
		stopped(ergo.report(_parts_doc(_swap_good), _swap_policy(_swap_has, {"c": _deep_nest(n, 5)}), {}))
	}
}

test_a_check_or_a_filter_that_is_not_an_object_is_written_wrong_when_a_subject_has_parts if {
	stopped(ergo.report(_parts_doc(_swap_good), _swap_policy(_swap_has, {"c": 5}), {}))
}

test_a_requirement_that_reads_parts_only_by_name_runs_without_a_scope_because_a_scope_makes_opa_work_out_every_row_again if {
	parts := {"parts": {"s": {"cov": {}}}}
	not ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, false), "b", "x"]}}}) with data.ergo_subject_sentences as parts
	ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, true), "b", "x"]}}}) with data.ergo_subject_sentences as parts
}

test_an_old_syntax_side_that_is_not_a_path_or_a_known_shape_is_left_as_written if {
	checks := {
		"a": {"op": "compare", "left": 5, "right": ["$cov", "x"], "cmp": "lt"},
		"b": {"op": "compare", "left": {"add": [5, ["$cov", "x"]]}, "right": {"literal": 1}, "cmp": "lt"},
		"c": {"op": "compare", "left": {"count_of": ["$lst"], "whose": [5], "text": "t"}, "right": {"literal": 1}, "cmp": "lt"},
	}
	stopped(_parts_report(_swap_has, checks, _swap_good))
}

test_a_part_with_a_key_that_is_not_a_string_is_written_wrong_and_is_not_listed if {
	policy := _parts_policy({1: "dd.b", true: "dd.c", "ok": "dd.d"}, {"c": "ok exists"})
	rep := ergo.report(_parts_doc({"d": 1}), policy, {})
	problems := _parts_problems(rep)
	problems["subjects.round.has.<invalid key 1>"] == ["invalid alias"]
	problems["subjects.round.has.<invalid key true>"] == ["invalid alias"]
	rep.subjects.round.parts == {"ok": {"from": "dd.d", "identified_by": null}}
	stopped(rep)
}

_hidden_doc := {"pull_requests": [
	{"reviews": [{"state": "ok"}]},
	{"reviews": [{"state": "ok"}, {"state": "ok"}]},
	{"reviews": [{"state": "bad"}, {"state": "ok"}]},
]}

test_a_position_in_a_list_inside_a_part_is_never_hidden_so_the_failed_item_names_the_full_path if {
	checks := {
		"every": "every reviews.state is \"ok\"",
		"count": "count of reviews is 4",
		"for": {"for": "every reviews as r", "assert": "r.state is \"ok\""},
	}
	full := {
		"every": "every pull_requests.reviews.state is \"ok\"",
		"count": "count of pull_requests.reviews is 4",
		"for": {"for": "every pull_requests.reviews as r", "assert": "r.state is \"ok\""},
	}
	alias := ergo.report(_hidden_doc, _swap_policy2({"reviews": "pull_requests.reviews"}, checks), {})
	plain := ergo.report(_hidden_doc, _swap_policy2({}, full), {})
	row := _parts_row(alias, "every")
	row.failed_items == [{"cause": "value", "item": "item 1 of pull_requests[2].reviews", "path": "pull_requests[2].reviews[0].state", "value": "bad", "locations": ["/pull_requests/2/reviews/0/state"]}]
	_untagged(row.inputs) == [{"name": "pull_requests[].reviews[].state", "value": ["ok", "ok", "ok", "bad", "ok"], "locations": ["/pull_requests/0/reviews/0/state", "/pull_requests/1/reviews/0/state", "/pull_requests/1/reviews/1/state", "/pull_requests/2/reviews/0/state", "/pull_requests/2/reviews/1/state"]}]
	_parts_row(alias, "count").inputs[1].name == "pull_requests[].reviews[]"
	_parts_row(alias, "for").failed_items[0].item == "item 1 of pull_requests[2].reviews"
	_parts_row(alias, "for").inputs[0].name == "pull_requests[].reviews[]"
	[[r.check, r.passed, r.cause] | some r in alias.results; r.check in {"every", "count", "for"}] == [[r.check, r.passed, r.cause] | some r in plain.results; r.check in {"every", "count", "for"}]
	alias.requirements.r.checks.every.expression == "every reviews.state is \"ok\""
}

_swap_policy2(has, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"round": _swap_subject2(has)},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_subject2(has) := {"from": "$input", "has": has} if count(has) > 0

_swap_subject2(has) := {"from": "$input"} if count(has) == 0

test_a_position_in_a_list_inside_a_parents_part_is_never_hidden_either if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"rv": "pull_requests.reviews"}},
		"pull request": {"from": "artifact.items", "identified_by": "state"},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "items": [{"state": "s"}], "pull_requests": [{"reviews": [{"state": "ok"}]}, {"reviews": [{"state": "bad"}]}]}}}}
	checks := {"c": "every artifact.rv.state is \"ok\"", "n": "count of artifact.rv is 2"}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, {"art": "web"})
	row := _parts_row(rep, "c")
	row.failed_items == [{"cause": "value", "item": "item 1 of artifact.pull_requests[1].reviews", "path": "artifact.pull_requests[1].reviews[0].state", "value": "bad", "locations": ["/trail/artifacts/web/pull_requests/1/reviews/0/state"]}]
	_untagged(row.inputs) == [{"name": "artifact.pull_requests[].reviews[].state", "value": ["ok", "bad"], "locations": ["/trail/artifacts/web/pull_requests/0/reviews/0/state", "/trail/artifacts/web/pull_requests/1/reviews/0/state"]}]
}

test_a_chained_subject_that_starts_at_its_parents_part_shows_its_from_as_written_in_its_expressions if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	checks := rep.requirements.r.checks
	checks["$min_subjects"].expression == "count(matching(artifact.pra.pull_requests)) >= 1"
	checks["$unique_ids"].expression == "count(repeated(ids(artifact.pra.pull_requests))) == 0"
	deeper := object.union(_parts_chain.subjects, {"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url"}})
	policy := {"ergo_spec": "v0.3-dev", "subjects": deeper, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}
	ergo.report(_parts_chain_doc, policy, {"art": "web"}).requirements.r.checks["$min_subjects"].expression == "count(matching(artifact.pra.pull_requests)) >= 1"
}

test_a_chained_subject_that_starts_deeper_in_its_parents_part_keeps_the_rest_of_the_path_in_its_expressions if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "artifact.pra.pull_requests[0].list", "identified_by": "url"},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "attestations": {"pr": {"pull_requests": [{"list": [{"url": "a"}]}]}}}}}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {"art": "web"})
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(artifact.pra.pull_requests[0].list)) >= 1"
}

_untagged(inputs) := [object.remove(i, ["part"]) | some i in inputs]

_tag_has := {
	"coverage": {"from": "dd.cov", "identified_by": "attestation_id"},
	"lst": "dd.items",
	"nowhere": {"from": "dd.cov", "identified_by": "nope"},
	"nulled": {"from": "dd.cov", "identified_by": "nothing"},
	"obj": {"from": "dd.cov", "identified_by": "meta"},
}

_tag_doc := {"cov": {"attestation_id": "att-7", "hunks_total": 25, "hunks_acknowledged": 25, "nothing": null, "meta": {"k": [1, 2]}}, "items": [{"x": 1}, {"x": 2}]}

test_an_input_read_through_a_part_is_tagged_with_the_alias_and_the_id_inside_the_part if {
	checks := {
		"eq": "coverage.hunks_acknowledged equals coverage.hunks_total",
		"own": "name is \"t1\"",
	}
	rep := _parts_report(_tag_has, checks, _tag_doc)
	_parts_row(rep, "eq").inputs == [
		{"name": "coverage.hunks_acknowledged", "part": {"id": "att-7", "name": "coverage"}, "value": 25, "locations": ["/trail/dd/cov/hunks_acknowledged"]},
		{"name": "coverage.hunks_total", "part": {"id": "att-7", "name": "coverage"}, "value": 25, "locations": ["/trail/dd/cov/hunks_total"]},
	]
	_parts_row(rep, "own").inputs == [{"name": "name", "value": "t1", "locations": ["/trail/name"]}]
}

test_a_part_without_an_id_or_with_an_id_that_leads_nowhere_or_to_null_is_tagged_with_a_null_id if {
	checks := {"a": "lst[0].x is 1", "b": "nowhere.hunks_total is 25", "c": "nulled.hunks_total is 25"}
	rep := _parts_report(_tag_has, checks, _tag_doc)
	every c in ["a", "b", "c"] {
		_parts_row(rep, c).inputs[0].part.id == null
	}
	_parts_row(rep, "a").inputs[0].part.name == "lst"
}

test_a_part_id_is_the_value_as_read_even_when_it_is_an_object if {
	rep := _parts_report(_tag_has, {"c": "obj.hunks_total is 25"}, _tag_doc)
	_parts_row(rep, "c").inputs[0].part == {"id": {"k": [1, 2]}, "name": "obj"}
}

test_a_part_id_is_read_for_each_subject_of_the_row if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"s": {"from": "xs", "identified_by": "n", "has": {"p": {"from": "d", "identified_by": "i"}}}},
		"requirements": {"r": {"subject": "s", "checks": {"c": "p.v is 1"}}},
	}
	rep := ergo.report({"xs": [{"n": "a", "d": {"i": 1, "v": 1}}, {"n": "b", "d": {"i": "two", "v": 2}}, {"n": "c"}]}, policy, {})
	[r.inputs[0].part.id | some r in rep.results; r.check == "c"] == [1, "two", null]
}

test_a_walk_and_a_count_and_a_for_line_tag_the_lists_they_read_through_a_part if {
	checks := {
		"every": "every lst.x is at least 1",
		"count": "count of lst is 2",
		"for": {"for": "every lst as entry", "assert": "entry.x is at least 1"},
	}
	rep := _parts_report(_tag_has, checks, _tag_doc)
	every c in ["every", "count", "for"] {
		every i in _parts_row(rep, c).inputs {
			i.part == {"id": null, "name": "lst"}
		}
	}
}

test_an_input_that_reads_through_two_parts_in_one_value_is_not_tagged_because_it_has_no_one_part if {
	rep := _parts_report(_tag_has, {"c": "count of lst plus coverage.hunks_total is 27"}, _tag_doc)
	inputs := _parts_row(rep, "c").inputs
	some i in inputs
	contains(i.name, "plus")
	not "part" in object.keys(i)
	some j in inputs
	j.name == "coverage.hunks_total"
	j.part.name == "coverage"
}

test_a_field_of_an_item_named_like_a_part_is_not_tagged_because_it_is_not_read_through_the_part if {
	has := {"x": "dd.cov"}
	rep := _parts_report(has, {"c": "every dd.items.x whose x is at least 1 is at least 1"}, _tag_doc)
	every i in _parts_row(rep, "c").inputs {
		not "part" in object.keys(i)
	}
}

test_a_walk_through_a_list_inside_a_part_that_names_the_full_path_is_still_tagged if {
	has := {"reviews": {"from": "pull_requests.reviews", "identified_by": "id"}}
	rep := ergo.report(_hidden_doc, _swap_policy2(has, {"c": "every reviews.state is \"ok\""}), {})
	_parts_row(rep, "c").inputs == [{"name": "pull_requests[].reviews[].state", "part": {"id": null, "name": "reviews"}, "value": ["ok", "ok", "ok", "bad", "ok"], "locations": ["/pull_requests/0/reviews/0/state", "/pull_requests/1/reviews/0/state", "/pull_requests/1/reviews/1/state", "/pull_requests/2/reviews/0/state", "/pull_requests/2/reviews/1/state"]}]
}

test_an_input_read_through_a_parents_part_is_tagged_with_the_parent_and_the_id_from_the_parents_part if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": {"from": "attestations.pr", "identified_by": "att"}}},
		"pull request": {"from": "artifact.pra.pull_requests", "identified_by": "url", "has": {"rev": "reviews"}},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "attestations": {"pr": {"att": "att-3", "name": "w", "pull_requests": [{"url": "pr/7", "reviews": {"count": 2}}]}}}}}}
	checks := {"parent": "artifact.pra.name is \"w\"", "own": "rev.count is 2", "field": "url exists"}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, {"art": "web"})
	_parts_row(rep, "parent").inputs == [{"name": "artifact.pra.name", "part": {"id": "att-3", "name": "artifact.pra"}, "value": "w", "locations": ["/trail/artifacts/web/attestations/pr/name"]}]
	_parts_row(rep, "own").inputs == [{"name": "rev.count", "part": {"id": null, "name": "rev"}, "value": 2, "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/reviews/count"]}]
	_parts_row(rep, "field").inputs == [{"name": "url", "value": "pr/7", "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/url"]}]
}

test_a_violation_carries_the_tags_of_the_row_it_copies if {
	rep := _parts_report(_tag_has, {"c": "coverage.hunks_total is 99"}, _tag_doc)
	violation := [v | some v in ergo.violations(rep); v.check == "c"][0]
	violation.inputs[0] == {"name": "coverage.hunks_total", "part": {"id": "att-7", "name": "coverage"}, "value": 25, "locations": ["/trail/dd/cov/hunks_total"]}
}

test_a_failed_item_and_a_ref_are_not_tagged_because_only_inputs_are if {
	rep := _parts_report(_tag_has, {"c": "every lst.x is 1"}, _tag_doc)
	every f in _parts_row(rep, "c").failed_items {
		not "part" in object.keys(f)
	}
}

test_a_policy_without_parts_gives_inputs_with_no_part_key if {
	rep := ergo.report({"trail": {"name": "t1", "dd": {"b": {"x": 1}}}}, _parts_policy({}, {"c": "dd.b.x is 1", "d": "name is \"t1\""}), {})
	every r in rep.results {
		every i in r.inputs {
			not "part" in object.keys(i)
		}
	}
}

test_an_applies_row_tags_the_inputs_its_conditions_read_through_a_part if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"s": {"from": "xs whose p.v is 1", "identified_by": "n", "has": {"p": {"from": "d", "identified_by": "i"}}}},
		"requirements": {"r": {"subject": "s", "checks": {"c": "n exists"}}},
	}
	rep := ergo.report({"xs": [{"n": "a", "d": {"i": 9, "v": 1}}]}, policy, {})
	[r.inputs | some r in rep.results; r.check == "$applies"] == [[{"name": "p.v", "part": {"id": 9, "name": "p"}, "value": 1, "locations": ["/xs/0/d/v"]}]]
}

_flows_doc := {"artifacts": [
	{"fingerprint": "sha-1", "pull_requests": [{"url": "pr/7", "approvals": 2}, {"url": "pr/8", "approvals": 0}]},
	{"fingerprint": "sha-2", "pull_requests": []},
	{"fingerprint": "sha-3", "pull_requests": [{"url": "pr/9", "approvals": 1}]},
]}

_every_prs := {"pull request": {"from": "every artifacts.pull_requests", "identified_by": "url"}}

test_a_from_line_with_every_reads_one_flat_list_from_every_list_along_its_path if {
	rep := _from_report(_flows_doc, _every_prs, {"c": "approvals is at least 1"}, {})
	[[r.check, r.subject, r.cause] | some r in rep.results] == [
		["$well_formed", {"type": "pull request", "id": null}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null}, "satisfied"],
		["$unique_ids", {"type": "pull request", "id": null}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/7"}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/8"}, "value"],
		["c", {"type": "pull request", "id": "pr/9"}, "satisfied"],
	]
	[r.inputs | some r in rep.results; r.check == "$min_subjects"] == [[{"name": "in-scope pull request count", "value": 3, "locations": ["/artifacts/0/pull_requests/0", "/artifacts/0/pull_requests/1", "/artifacts/2/pull_requests/0"]}]]
	rep.subjects["pull request"].from == "every artifacts.pull_requests"
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(every artifacts.pull_requests)) >= 1"
	rep.requirements.r.checks["$unique_ids"].expression == "count(repeated(ids(every artifacts.pull_requests))) == 0"
}

test_a_from_line_with_every_lists_no_failed_items_when_every_branch_is_read if {
	rep := _from_report(_flows_doc, _every_prs, {"c": "url exists"}, {})
	[r.failed_items | some r in rep.results; r.check == "$min_subjects"] == [[]]
	[r | some r in rep.results; r.check != "$min_subjects"; "failed_items" in object.keys(r)] == []
}

test_a_from_line_with_every_walks_lists_inside_lists_and_the_last_one if {
	doc := {"flows": [{"trails": [{"tags": ["a", "b"]}, {"tags": ["c"]}]}, {"trails": [{"tags": ["d"]}]}]}
	rep := _from_report(doc, {"tag": {"from": "every flows.trails.tags"}}, {"c": "x exists"}, {})
	[r.subject.id | some r in rep.results; r.check == "c"] == ["a", "b", "c", "d"]
}

test_ids_of_subjects_read_with_every_are_unique_across_all_of_them if {
	doc := {"artifacts": [{"pull_requests": [{"url": "pr/7"}]}, {"pull_requests": [{"url": "pr/7"}]}]}
	rep := _from_report(doc, _every_prs, {"c": "url exists"}, {})
	[[r.cause, r.inputs] | some r in rep.results; r.check == "$unique_ids"] == [["value", [{"name": "repeated pull request ids", "value": ["pr/7"], "locations": ["/artifacts/0/pull_requests/0/url", "/artifacts/1/pull_requests/0/url"]}]]]
}

test_a_from_line_with_every_keeps_the_subjects_its_whose_holds_for if {
	subjects := {"pull request": {"from": "every artifacts.pull_requests whose approvals is at least 1", "identified_by": "url"}}
	rep := _from_report(_flows_doc, subjects, {"c": "url exists"}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check in {"$applies", "c"}] == [["pr/7", "satisfied"], ["pr/8", "value"], ["pr/9", "satisfied"], ["pr/7", "satisfied"], ["pr/9", "satisfied"]]
	rep.subjects["pull request"].from == "every artifacts.pull_requests whose approvals is at least 1"
}

test_an_empty_list_along_a_from_line_with_every_adds_no_subject_and_fails_nothing if {
	rep := _from_report(_flows_doc, _every_prs, {"c": "url exists"}, {})
	rep.requirements.r.status == "met"
	none := _from_report({"artifacts": [{"pull_requests": []}]}, _every_prs, {"c": "url exists"}, {})
	[[r.cause, r.failed_items] | some r in none.results; r.check == "$min_subjects"] == [["value", []]]
}

test_a_broken_branch_along_a_from_line_with_every_fails_min_subjects_with_the_worst_cause_and_lists_where if {
	doc := {"artifacts": [
		{"pull_requests": [{"url": "pr/7", "approvals": 2}]},
		{"fingerprint": "sha-4"},
		{"pull_requests": null},
		{"pull_requests": "none"},
	]}
	rep := _from_report(doc, _every_prs, {"c": "approvals is at least 1"}, {})
	[[r.passed, r.cause, r.failed_items] | some r in rep.results; r.check == "$min_subjects"] == [[false, "unusable", [
		{"path": "artifacts[1].pull_requests", "item": "artifacts[1].pull_requests", "cause": "absent", "value": null, "locations": ["/artifacts/1"]},
		{"path": "artifacts[2].pull_requests", "item": "artifacts[2].pull_requests", "cause": "null", "value": null, "locations": ["/artifacts/2/pull_requests"]},
		{"path": "artifacts[3].pull_requests", "item": "artifacts[3].pull_requests", "cause": "unusable", "value": "none", "locations": ["/artifacts/3/pull_requests"]},
	]]]
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "c"] == [["pr/7", "satisfied"]]
	rep.requirements.r.status == "not_met"
	[[v.check, v.failed_items[0].path] | some v in ergo.violations(rep)] == [["$min_subjects", "artifacts[1].pull_requests"]]
	missing := _from_report({"artifacts": [{"pull_requests": [{"url": "pr/7"}]}, {}]}, _every_prs, {"c": "url exists"}, {})
	[r.cause | some r in missing.results; r.check == "$min_subjects"] == ["absent"]
	zero := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _every_prs, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	[r.cause | some r in zero.results; r.check == "$min_subjects"] == ["unusable"]
	zero.requirements.r.status == "not_met"
}

test_a_from_line_with_every_fails_where_its_path_stops_as_every_does_in_a_check if {
	rep := _from_report({"artifact": {"pull_requests": [{"url": "pr/7"}]}}, {"a": {"from": "every artifact"}}, {"c": "x exists"}, {})
	[[r.cause, r.failed_items] | some r in rep.results; r.check == "$min_subjects"] == [["unusable", [{"path": "artifact", "item": "artifact", "cause": "unusable", "value": {"pull_requests": [{"url": "pr/7"}]}, "locations": ["/artifact"]}]]]
	gone := _from_report({}, _every_prs, {"c": "x exists"}, {})
	[[r.cause, r.failed_items[0].path] | some r in gone.results; r.check == "$min_subjects"] == [["absent", "artifacts"]]
	ends := _from_report({"flows": [{"a": {"n": 1}}, {"a": "x"}]}, {"a": {"from": "every flows.a"}}, {"c": "n exists"}, {})
	[[r.cause, [f.path | some f in r.failed_items]] | some r in ends.results; r.check == "$min_subjects"] == [["unusable", ["flows[1].a"]]]
	[r.cause | some r in ends.results; r.check == "c"] == ["satisfied"]
}

test_a_from_line_with_every_on_an_input_that_is_not_an_object_fails_as_one_without_every if {
	[r.cause | some r in _from_report("x", _every_prs, {"c": "x exists"}, {}).results; r.check == "$min_subjects"] == ["unusable"]
	[r.failed_items | some r in _from_report("x", _every_prs, {"c": "x exists"}, {}).results; r.check == "$min_subjects"] == [[{"path": "$input", "item": "$input", "cause": "unusable", "value": "x", "locations": [""]}]]
}

test_a_from_line_through_a_list_without_every_still_fails if {
	rep := _from_report(_flows_doc, {"pull request": {"from": "artifacts.pull_requests", "identified_by": "url"}}, {"c": "url exists"}, {})
	[r.cause | some r in rep.results; r.check == "$min_subjects"] == ["unusable"]
	[r | some r in rep.results; r.check == "$min_subjects"; "failed_items" in object.keys(r)] == []
}

test_every_in_a_from_line_cant_start_at_another_subject_or_go_with_named_by_each_of_or_walk_more_than_ten_steps if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	_from_problems(ergo.report(_flows_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})) == [{"name": `subjects."pull request".from`, "value": ["every can't go with a from line that starts at another subject yet"], "locations": []}]
	narrow := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "kept": {"from": "every artifact"}}
	_from_problems(ergo.report(_flows_doc, {"ergo_spec": "v0.3-dev", "subjects": narrow, "requirements": {"r": {"subject": "kept", "checks": {"c": "url exists"}}}}, {})) == [{"name": "subjects.kept.from", "value": ["every can't go with a from line that starts at another subject yet"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every artifacts named by each of $params.names"}}, {"c": "x exists"}, {"names": ["a"]})) == [{"name": "subjects.s.from", "value": ["every can't go with named by each of: start the from line at a subject to read its names one subject at a time"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every x.b.c.d.e.f.g.h.i.j.k"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every over more than ten steps isn't supported yet"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every x.b.c.d.e.f.g.h.i.j"}}, {"c": "x exists"}, {})) == []
}

test_every_in_a_from_line_with_a_leading_dot_reads_the_top_level_field_even_when_a_subject_has_the_name if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "p": {"from": "every .artifact.p"}, "q": {"from": "every .artifact"}}
	input_doc := {"artifacts": [], "artifact": [{"p": [{"x": 1}]}]}
	rep := ergo.report(input_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "p", "checks": {"c": "x exists"}}, "s": {"subject": "q", "checks": {"c": "p exists"}}}}, {})
	_from_problems(rep) == []
	rep.subjects.p.from == "every .artifact.p"
	rep.subjects.q.from == "every .artifact"
	[r.cause | some r in rep.results; r.requirement == "r"; r.check == "c"] == ["satisfied"]
	[r.cause | some r in rep.results; r.requirement == "s"; r.check == "c"] == ["satisfied"]
	plain := ergo.report({"artifacts": [{"id": "a"}], "artifact": [{"x": 1}]}, {"ergo_spec": "v0.3-dev", "subjects": {"artifact": {"from": "artifacts", "identified_by": "id"}, "q": {"from": ".artifact"}}, "requirements": {"r": {"subject": "q", "checks": {"c": "x exists"}}}}, {})
	plain.subjects.q.identified_by == null
	[r.subject.id | some r in plain.results; r.check == "c"] == [{"x": 1}]
}

test_a_from_line_with_every_does_not_count_input_as_a_step if {
	doc := {"k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": [{"id": "a"}, {"id": "b"}]}}}}}}}}}}
	rep := _from_report(doc, {"s": {"from": "every $input.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10", "identified_by": "id"}}, {"c": "id exists"}, {})
	_from_problems(rep) == []
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "c"] == [["a", "satisfied"], ["b", "satisfied"]]
	_from_problems(_from_report(doc, {"s": {"from": "every $input.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every over more than ten steps isn't supported yet"], "locations": []}]
}

test_a_count_of_over_more_than_ten_steps_on_the_right_of_a_from_lines_whose_is_written_wrong if {
	_from_problems(_from_report({"things": []}, {"s": {"from": concat("", ["things whose n is count of ", _eleven])}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["whose: every and some over more than ten steps aren't supported yet"], "locations": []}]
	_from_problems(_from_report({"things": []}, {"s": {"from": concat("", ["things whose n is count of ", _ten])}}, {"c": "x exists"}, {})) == []
}

test_a_field_called_every_in_a_from_line_is_written_with_a_dot if {
	rep := _from_report({"every": {"x": [{"id": 1}]}}, {"s": {"from": ".every.x", "identified_by": "id"}}, {"c": "id exists"}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "c"] == [[1, "satisfied"]]
	_from_problems(_from_report({"every": [1]}, {"s": {"from": "every"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every is a word of the grammar: write .every"], "locations": []}]
	_from_problems(_from_report({}, {"s": {"from": "every count.x"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["count is a word of the grammar: write .count"], "locations": []}]
	ergo._sentence(`every x whose k is 1`) == {"problems": ["doesn't parse"]}
}

test_a_parent_read_with_every_gives_its_child_subjects_per_parent if {
	doc := {"flows": [{"artifacts": [{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}]}]}, {"artifacts": [{"fingerprint": "b", "pull_requests": [{"url": "pr/7"}]}]}]}
	subjects := {"artifact": {"from": "every flows.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
	rep := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})
	[[r.check, r.subject.id, object.get(r.subject, "in", null)] | some r in rep.results; r.check != "$well_formed"] == [
		["$min_subjects", null, {"artifact": "a"}],
		["$min_subjects", null, {"artifact": "b"}],
		["$unique_ids", null, {"artifact": "a"}],
		["$unique_ids", null, {"artifact": "b"}],
		["c", "pr/7", {"artifact": "a"}],
		["c", "pr/7", {"artifact": "b"}],
	]
	rep.requirements.r.status == "met"
	broken := ergo.report({"flows": [{"artifacts": [{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}]}]}, {}]}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})
	[[r.check, r.cause, object.get(r.subject, "in", null)] | some r in broken.results; r.check != "$well_formed"] == [["$min_subjects", "absent", null], ["$unique_ids", "satisfied", null]]
}

_three_doc := {"artifacts": [
	{"fingerprint": "sha-1", "env": "prod", "atts": {"pr": {"id": "att-1", "pull_requests": [
		{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": true}, {"sha": "c2", "verified": false}]},
		{"url": "pr/8", "state": "MERGED", "commits": []},
		{"url": "pr/9", "state": "OPEN", "commits": [{"sha": "c9", "verified": false}, {"sha": "c9"}]},
	]}}},
	{"fingerprint": "sha-2", "env": "dev", "atts": {"pr": {"id": "att-2", "pull_requests": [{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": false}]}]}}},
	{"fingerprint": "sha-4", "env": "prod", "atts": {"pr": {"id": "att-4", "pull_requests": [{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": true}, {"sha": "c1", "verified": true}]}]}}},
]}

_three_subjects := {
	"artifact": {"from": `artifacts whose env is "prod"`, "identified_by": "fingerprint", "has": {"pr_att": {"from": "atts.pr", "identified_by": "id"}}},
	"pull request": {"from": `artifact.pr_att.pull_requests whose state is "MERGED"`, "identified_by": "url"},
	"commit": {"from": `"pull request".commits`, "identified_by": "sha"},
}

_three_report(doc, checks) := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _three_subjects, "requirements": {"r": {"subject": "commit", "checks": checks}}}, {})

test_a_chain_of_three_subjects_checks_each_grandchild_and_its_rows_list_every_ancestor if {
	rep := _three_report(_three_doc, {"c": "verified is true"})
	[[r.check, r.subject, r.cause] | some r in rep.results] == [
		["$well_formed", {"type": "commit", "id": null}, "satisfied"],
		["$min_subjects", {"type": "commit", "id": null, "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "satisfied"],
		["$min_subjects", {"type": "commit", "id": null, "in": {"artifact": "sha-1", "pull request": "pr/8"}}, "value"],
		["$min_subjects", {"type": "commit", "id": null, "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "satisfied"],
		["$unique_ids", {"type": "commit", "id": null, "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "satisfied"],
		["$unique_ids", {"type": "commit", "id": null, "in": {"artifact": "sha-1", "pull request": "pr/8"}}, "satisfied"],
		["$unique_ids", {"type": "commit", "id": null, "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "value"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "satisfied"],
		["c", {"type": "commit", "id": "c2", "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "value"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "satisfied"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "satisfied"],
	]
	rep.requirements.r.subjects == {"total": 4, "matching": 4}
	rep.requirements.r.checks["$min_subjects"].expression == `count(matching("pull request".commits)) >= 1`
}

test_a_check_of_a_chain_of_three_subjects_reads_every_ancestor_and_its_parts_by_name if {
	rep := _three_report(_three_doc, {"c": `artifact.fingerprint exists and "pull request".url exists and artifact.pr_att.id exists and sha exists`})
	[[r.subject.id, r.subject.in, r.inputs] | some r in rep.results; r.check == "c"; r.subject.in.artifact == "sha-1"] == [
		["c1", {"artifact": "sha-1", "pull request": "pr/7"}, [
			{"name": `"pull request".url`, "value": "pr/7", "locations": ["/artifacts/0/atts/pr/pull_requests/0/url"]},
			{"name": "artifact.fingerprint", "value": "sha-1", "locations": ["/artifacts/0/fingerprint"]},
			{"name": "artifact.pr_att.id", "value": "att-1", "part": {"name": "artifact.pr_att", "id": "att-1"}, "locations": ["/artifacts/0/atts/pr/id"]},
			{"name": "sha", "value": "c1", "locations": ["/artifacts/0/atts/pr/pull_requests/0/commits/0/sha"]},
		]],
		["c2", {"artifact": "sha-1", "pull request": "pr/7"}, [
			{"name": `"pull request".url`, "value": "pr/7", "locations": ["/artifacts/0/atts/pr/pull_requests/0/url"]},
			{"name": "artifact.fingerprint", "value": "sha-1", "locations": ["/artifacts/0/fingerprint"]},
			{"name": "artifact.pr_att.id", "value": "att-1", "part": {"name": "artifact.pr_att", "id": "att-1"}, "locations": ["/artifacts/0/atts/pr/id"]},
			{"name": "sha", "value": "c2", "locations": ["/artifacts/0/atts/pr/pull_requests/0/commits/1/sha"]},
		]],
	]
	[r.inputs[2].part.id | some r in rep.results; r.check == "c"; r.subject.in.artifact == "sha-4"] == ["att-4", "att-4"]
	[r.cause | some r in rep.results; r.check == "c"] == ["satisfied", "satisfied", "satisfied", "satisfied"]
}

test_scope_applies_at_every_level_of_a_chain_of_three_subjects if {
	rep := _three_report(_three_doc, {"c": "verified is true"})
	{r.subject.in.artifact | some r in rep.results; "in" in object.keys(r.subject)} == {"sha-1", "sha-4"}
	{r.subject.in["pull request"] | some r in rep.results; "in" in object.keys(r.subject)} == {"pr/7", "pr/8"}
}

test_an_ancestor_of_a_chain_of_three_subjects_that_cant_be_decided_fails_min_subjects_on_its_row if {
	doc := {"artifacts": [
		{"fingerprint": "sha-1", "atts": {"pr": {"pull_requests": [{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": true}]}]}}},
		{"fingerprint": "sha-2", "env": "prod", "atts": {"pr": {"pull_requests": [{"url": "pr/8", "commits": [{"sha": "c2", "verified": true}]}]}}},
	]}
	rep := _three_report(doc, {"c": "verified is true"})
	[[r.check, r.subject, r.cause] | some r in rep.results; r.check != "$well_formed"] == [
		["$min_subjects", {"type": "commit", "id": null, "in": {"artifact": "sha-1"}}, "absent"],
		["$min_subjects", {"type": "commit", "id": null, "in": {"artifact": "sha-2", "pull request": "pr/8"}}, "absent"],
	]
	rep.requirements.r.status == "not_met"
}

test_a_chain_of_three_subjects_with_no_grandparent_or_no_parent_in_scope_fails_min_subjects_on_one_row if {
	none := _three_report({"artifacts": [{"fingerprint": "sha-2", "env": "dev"}]}, {"c": "verified is true"})
	[[r.cause, object.keys(r.subject)] | some r in none.results; r.check == "$min_subjects"] == [["value", {"type", "id"}]]
	empty := _three_report({"artifacts": [{"fingerprint": "sha-1", "env": "prod", "atts": {"pr": {"pull_requests": []}}}]}, {"c": "verified is true"})
	[[r.cause, object.keys(r.subject)] | some r in empty.results; r.check == "$min_subjects"] == [["value", {"type", "id"}]]
	gone := _three_report({"artifacts": [{"fingerprint": "sha-1", "env": "prod"}]}, {"c": "verified is true"})
	[[r.cause, r.subject.in] | some r in gone.results; r.check == "$min_subjects"] == [["absent", {"artifact": "sha-1"}]]
	unread := _three_report({}, {"c": "verified is true"})
	[[r.cause, object.keys(r.subject)] | some r in unread.results; r.check == "$min_subjects"] == [["absent", {"type", "id"}]]
}

test_a_part_named_like_a_grandparent_is_written_wrong_as_a_subjects_name if {
	subjects := object.union(_three_subjects, {"commit": {"from": `"pull request".commits`, "identified_by": "sha", "has": {"artifact": "x"}}})
	rep := ergo.report(_three_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "commit", "checks": {"c": "sha exists"}}}}, {})
	[i | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")] == [{"name": "subjects.commit.has.artifact", "value": ["artifact can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_requirement_field_named_like_the_facts_ergo_works_out_once_is_unknown_and_stops_the_requirement if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pr_att": "atts.pr"}}, "pull request": {"from": "artifact.pull_requests", "identified_by": "url"}}
	doc := {"artifacts": [{"fingerprint": "a", "atts": {"pr": {"id": "x"}}, "pull_requests": [{"url": "pr/7"}]}, {"fingerprint": "b", "pull_requests": [{"url": "pr/8"}]}]}
	plain := {"subject": "pull request", "checks": {"c": "url exists and artifact.pr_att.id exists"}}
	odd := object.union(plain, {"ergo/fixed": {"each_step": [{"each_as": "x"}], "has_parts": true, "tagging": false, "scoped": false}})
	clean := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": plain}}, {})
	marked := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": odd}}, {})
	stopped(marked)
	[r.subject.id | some r in clean.results; r.check == "c"] == ["pr/7", "pr/8"]
	[i | some r in marked.results; r.check == "$well_formed"; some i in r.inputs; i.name == `"ergo/fixed"`] == [{"name": `"ergo/fixed"`, "value": ["unknown field"], "locations": []}]
}

_saved(form) := json.unmarshal(json.marshal(form))

_compile_policies := [
	_sentence_policy({"c": "x is in $params.l and y exists and y is 2", "d": "y is $params.y"}),
	{"ergo_spec": "v0.3-dev", "subjects": _three_subjects, "requirements": {"r": {"subject": "commit", "checks": {"c": "verified is true"}}, "p": {"subject": "pull request", "checks": {"c": "url exists"}}}},
	{"ergo_spec": "v0.3-dev", "subjects": {"deployment": {"from": "$input named by $params.list whose environment is $params.env", "identified_by": "id"}}, "requirements": {"a": approved_req("deployment")}},
	_sentence_policy({"c": "x is", "d": "y is 2"}),
	{"description": 1, "requirements": {"s": {"subject": "nowhere", "checks": {"c": "x exists"}}}},
	{},
	null,
	"policy",
]

_compile_runs := [
	[0, {"things": [{"id": "a", "x": "p", "y": 1}, {"id": "b", "x": "q", "y": 2}]}, {"l": ["p"], "y": 2}],
	[0, {"things": [{"id": "a", "x": "p", "y": 1}]}, {"l": "text"}],
	[0, {"things": [{"id": "a", "x": {"p"}, "y": 2}]}, {}],
	[1, _three_doc, {}],
	[1, null, {}],
	[2, deployments_doc, {"list": "deployments", "env": "staging"}],
	[2, deployments_doc, "params"],
	[3, {"things": [{"id": "a", "y": 2}]}, {}],
	[4, {"things": []}, {}],
	[5, {}, {}],
	[6, {}, {}],
	[7, {}, {}],
]

test_a_report_from_a_saved_compiled_policy_is_the_report_from_its_policy if {
	every run in _compile_runs {
		ergo.report(run[1], _saved(ergo.compile(_compile_policies[run[0]])), run[2]) == ergo.report(run[1], _compile_policies[run[0]], run[2])
	}
}

test_a_compiled_policy_holds_no_set_so_json_can_hold_it if {
	every policy in _compile_policies {
		ergo.compile(policy) == _saved(ergo.compile(policy))
	}
}

test_any_policy_compiles if {
	every policy in _compile_policies {
		object.keys(ergo.compile(policy)) == {"ergo/compiled"}
	}
}

test_compiling_a_compiled_policy_gives_it_back if {
	every policy in _compile_policies {
		ergo.compile(ergo.compile(policy)) == ergo.compile(policy)
	}
}

test_a_compiled_policy_reads_the_params_and_input_of_each_run_not_the_ones_it_was_compiled_with if {
	form := _saved(ergo.compile(_sentence_policy({"c": "x is in $params.l"})))
	doc := {"things": [{"id": "a", "x": "p"}]}
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": ["p"]}).results; r.check == "c"] == [[true, "satisfied"]]
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": ["q"]}).results; r.check == "c"] == [[false, "value"]]
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": "text"}).results; r.check == "c"] == [[false, "unusable"]]
	[[r.passed, r.cause] | some r in ergo.report({"things": [{"id": "a", "x": {"p"}}]}, form, {"l": ["p"]}).results; r.check == "c"] == [[false, "unusable"]]
	ergo.report(doc, form, {"l": ["p"]}).requirements.s.checks.c["$refs"] == [{"name": "$params.l", "value": ["p"], "locations": ["$params:/l"]}]
	ergo.report(doc, form, {"l": ["q"]}).requirements.s.checks.c["$refs"] == [{"name": "$params.l", "value": ["q"], "locations": ["$params:/l"]}]
}

test_a_compiled_policy_with_a_field_missing_or_of_a_type_ergo_cant_use_fails_like_a_policy_ergo_cant_read if {
	form := ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"]
	doc := {"things": [{"id": "a", "x": 1}]}
	ergo.report(doc, {"ergo/compiled": form}, {}).compliant
	every broken in array.concat(
		[{"ergo/compiled": null}, {"ergo/compiled": {}}, {"ergo/compiled": form, "x": 1}],
		array.concat(
			array.concat(
				[{"ergo/compiled": object.remove(form, [f])} | some f, _ in form; f != "engine"],
				[{"ergo/compiled": object.union(form, {f: "x"})} | some f in ["resolved", "subject_sentences", "ahead", "sentences"]],
			),
			array.concat(
				[{"ergo/compiled": object.union(object.remove(form, ["ahead"]), {"ahead": object.remove(form.ahead, [f])})} | some f, _ in form.ahead],
				[{"ergo/compiled": object.union(form, {"ahead": object.union(form.ahead, {f: "x"})})} | some f, _ in form.ahead],
			),
		),
	) {
		ergo.report(doc, broken, {}) == ergo.report(doc, {"x": 1}, {})
	}
}

test_a_compiled_policy_says_which_engine_compiled_it if {
	ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"].engine == {"name": "ergo.rego", "version": ergo.version}
}

_stale_rows(form) := [[r.requirement, r.check, r.passed, problem_inputs_of(r)] | some r in ergo.report({"things": [{"id": "a", "x": 1}]}, {"ergo/compiled": form}, {}).results]

test_a_compiled_policy_without_an_engine_fails_its_well_formed_rows if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])
	_stale_rows(form) == [["s", "$well_formed", false, [{"name": "ergo/compiled engine", "value": ["missing"], "locations": []}]]]
}

test_a_compiled_policy_from_another_engine_fails_its_well_formed_rows if {
	want := [["s", "$well_formed", false, [{"name": "ergo/compiled engine", "value": [concat("", ["compiled by another engine, expected ergo.rego ", ergo.version])], "locations": []}]]]
	form := ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"]
	every engine in [{"name": "ergo.rego", "version": "0.0.9"}, {"name": "other", "version": ergo.version}, {"name": "ergo.rego"}, "ergo.rego", 1, {}] {
		_stale_rows(object.union(object.remove(form, ["engine"]), {"engine": engine})) == want
	}
}

test_a_compiled_policy_from_another_engine_is_read_from_its_policy_because_its_other_fields_may_mean_something_else_now if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])
	stale := object.union(form, {"requirements": {}, "sentences": [], "resolved": {}, "ahead": {}})
	_stale_rows(stale) == _stale_rows(form)
	_stale_rows(object.union(form, {"policy": _sentence_policy({"c": {"op": "empty", "path": ["xs"]}})})) == [["s", "$well_formed", false, [
		{"name": "checks.c", "value": ["missing assert", "unknown field op", "unknown field path"], "locations": []},
		{"name": "ergo/compiled engine", "value": ["missing"], "locations": []},
	]]]
}

test_a_compiled_policy_from_another_engine_lists_its_engine_before_the_policys_own_problems if {
	form := object.remove(ergo.compile(object.remove(_sentence_policy({"c": "x is 1"}), ["ergo_spec"]))["ergo/compiled"], ["engine"])
	_stale_rows(form) == [["s", "$well_formed", false, [
		{"name": "ergo/compiled engine", "value": ["missing"], "locations": []},
		{"name": "policy ergo_spec", "value": ["missing"], "locations": []},
	]]]
}

test_compiling_a_policy_compiled_by_another_engine_gives_it_back_so_the_report_still_says_so if {
	stale := {"ergo/compiled": object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])}
	ergo.compile(stale) == stale
}

test_a_compiled_policy_from_another_engine_without_its_policy_fails_like_a_policy_ergo_cant_read if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine", "policy"])
	ergo.report({"things": [{"id": "a", "x": 1}]}, {"ergo/compiled": form}, {}) == ergo.report({"things": [{"id": "a", "x": 1}]}, {"x": 1}, {})
}

test_data_named_like_ergos_compile_flag_changes_no_report if {
	policy := _sentence_policy({"c": "x is 1"})
	doc := {"things": [{"id": "a", "x": 2}]}
	want := ergo.report(doc, policy, {})
	every form in [policy, ergo.compile(policy)] {
		ergo.report(doc, form, {}) == want with data.ergo_reading as true
	}
}

test_a_between_after_a_count_reads_the_items_its_whose_keeps if {
	doc := {"things": [{"id": "a", "xs": [{"k": 1}, {"k": 1}, {"k": 2}]}, {"id": "b", "xs": [{"k": 1}, {"k": 1}, {"k": 1}, {"k": 1}]}]}
	rows := _sentence_rows({"c": "count of xs whose k is 1 is between 1 and 3"}, doc, {})
	[[r[0], r[1], r[2]] | some r in rows] == [["c", true, "satisfied"], ["c", false, "value"]]
}

test_a_between_after_a_plus_is_inclusive_and_fails_closed_on_text if {
	doc := {"things": [{"id": "a", "n": 3}, {"id": "b", "n": "3"}, {"id": "c", "n": null}, {"id": "d", "n": 1}, {"id": "e", "n": 6}]}
	rows := _sentence_rows({"c": "n plus 1 is between 2 and 4"}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [true, "satisfied"], [false, "value"]]
}

test_a_between_after_a_count_goes_with_and_in_a_list_of_assertions if {
	doc := {"things": [{"id": "a", "xs": [1, 2], "n": 1}, {"id": "b", "xs": [1, 2], "n": 2}]}
	rows := ergo.report(doc, _sentence_policy({"c": {"assert": ["count of xs is between 1 and 2", "n is 1"]}}), {}).results
	[[r.subject.id, r.passed, r.cause] | some r in rows; r.check == "c"] == [["a", true, "satisfied"], ["b", false, "value"]]
}

test_a_count_in_the_whose_of_a_count_or_a_sum_leaves_out_the_items_it_fails if {
	doc := [{"id": 1, "xs": [{"n": 2, "ys": [1, 2]}, {"n": 3, "ys": [1]}, {"n": 4, "ys": [1, 2, 3]}]}]
	_elapsed_rows("count of xs whose count of ys is at least 2 is 2", doc, {})[0][1] == true
	_elapsed_rows("sum of xs.n whose count of ys is at least 2 is 6", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose n is count of ys is 1", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose count of ys is at least 2 is 3", doc, {})[0][1] == false
}

test_a_count_in_the_whose_of_a_count_fails_closed_when_an_item_list_cant_be_counted if {
	every list, cause in {"missing": "absent", "null": "null", "text": "unusable"} {
		item := object.union({"n": 1}, {k: v | list != "missing"; k := "ys"; v := {"null": null, "text": "abc"}[list]})
		_elapsed_cause("count of xs whose count of ys is at least 2 is 1", {"id": 1, "xs": [{"n": 1, "ys": [1, 2]}, item]}, {}) == cause
		_elapsed_cause("sum of xs.n whose count of ys is at least 2 is 1", {"id": 1, "xs": [{"n": 1, "ys": [1, 2]}, item]}, {}) == cause
	}
	_elapsed_cause("count of xs whose count of ys.z is at least 1 is 1", {"id": 1, "xs": [{"ys": [{"z": [1]}]}, "a"]}, {}) == "not_an_object"
}

test_a_count_in_the_whose_of_a_count_counts_through_a_list_it_walks if {
	doc := [{"id": 1, "xs": [{"ys": [{"z": [1, 2]}, {"z": [1]}]}, {"ys": [{"z": [1]}]}]}]
	_elapsed_rows("count of xs whose count of ys.z is 3 is 1", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose count of ys.z is 3 is 2", doc, {})[0][1] == false
}

test_a_time_phrase_with_a_written_value_fails_closed_on_every_kind_of_field if {
	doc := {"things": [{"id": "a", "t": "2024-01-01T00:00:00Z"}, {"id": "b", "t": 5}, {"id": "c", "t": null}, {"id": "d"}, {"id": "e", "t": [1]}, {"id": "f", "t": "2025-01-01T00:00:00Z"}]}
	rows := _sentence_rows({"c": "t is before \"2024-06-01T00:00:00Z\""}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [false, "absent"], [false, "unusable"], [false, "value"]]
}

test_a_written_value_after_a_time_phrase_that_isnt_a_time_is_written_wrong_because_it_could_only_fail if {
	every pair in [[`t is before null`, `"is before" takes a time or a number`], [`t is after true`, `"is after" takes a time or a number`], [`t is on or after "yesterday"`, `"is on or after" takes a time or a number`], [`t is on or before "2024-02-30"`, `"is on or before" takes a time or a number`], [`t is before "2024-02-30T00:00:00Z"`, `"is before" takes a time or a number`]] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
}

test_a_written_number_after_a_time_phrase_is_a_time_so_a_text_field_is_unusable if {
	doc := {"things": [{"id": "a", "t": "2024-01-01T00:00:00Z"}, {"id": "b", "t": 5}]}
	[r[2] | some r in _sentence_rows({"c": "t is before 6"}, doc, {})] == ["unusable", "satisfied"]
}

test_a_written_value_that_isnt_a_time_is_written_wrong_in_a_whose_too if {
	_sentence_problems(`every xs.v whose t is before "soon" is true`) == [`"is before" takes a time or a number`]
}

test_a_time_phrase_with_a_written_value_shows_only_the_field_it_reads if {
	_sentence_rows({"c": "t is on or after 5"}, {"things": [{"id": "a", "t": 5}]}, {}) == [["c", true, "satisfied", [{"name": "t", "value": 5, "locations": ["/things/0/t"]}]]]
}

test_a_time_phrase_with_a_written_value_goes_in_a_whose if {
	doc := {"things": [{"id": "a", "xs": [{"t": "2024-01-01T00:00:00Z", "v": "x"}, {"t": "2026-01-01T00:00:00Z", "v": ""}]}, {"id": "b", "xs": [{"t": "2024-01-01T00:00:00Z", "v": ""}]}, {"id": "c", "xs": [{"t": 5, "v": ""}]}]}
	rows := _sentence_rows({"c": "every xs.v whose t is before \"2025-01-01T00:00:00Z\" is not empty"}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "value"], [false, "unusable"]]
	count_rows := _sentence_rows({"c": "count of xs whose t is before \"2025-01-01T00:00:00Z\" is 1"}, doc, {})
	[[r[1], r[2]] | some r in count_rows] == [[true, "satisfied"], [true, "satisfied"], [false, "unusable"]]
}

_named_params := {"lists": {"a": ["p", "q"], "b": "text", "c": null}, "pats": {"a": ["^a"], "bad": ["("]}, "k": "a", "kbad": "bad", "nk": null, "bk": {"x": 1}}

_named_things := {"things": [{"id": "t1", "x": "p", "kind": "a"}, {"id": "t2", "x": "z", "kind": "b"}, {"id": "t3", "x": "p", "kind": "c"}, {"id": "t4", "x": "p", "kind": "zz"}, {"id": "t5", "x": "p"}, {"id": "t6", "x": 3, "kind": "a"}]}

test_a_list_read_with_named_by_a_params_key_shows_only_the_field if {
	rows := _sentence_rows({"c": "x is in $params.lists named by $params.k"}, _named_things, _named_params)
	[[r[1], r[2], r[3]] | some r in rows] == [
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/0/x"]}]],
		[false, "value", [{"name": "x", "value": "z", "locations": ["/things/1/x"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/2/x"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/3/x"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/4/x"]}]],
		[false, "unusable", [{"name": "x", "value": 3, "locations": ["/things/5/x"]}]],
	]
}

test_a_list_read_with_named_by_a_subject_field_fails_closed_when_the_key_is_unusable if {
	rows := _sentence_rows({"c": "x is in $params.lists named by kind"}, _named_things, _named_params)
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [false, "absent"], [false, "absent"], [false, "unusable"]]
}

test_a_list_read_with_named_by_a_reference_that_is_null_or_not_a_key_fails_whatever_the_field_holds if {
	nulls := _sentence_rows({"c": "x is in $params.lists named by $params.nk"}, _named_things, _named_params)
	{r[2] | some r in nulls} == {"null"}
	objects := _sentence_rows({"c": "x is not in $params.lists named by $params.bk"}, _named_things, _named_params)
	{r[2] | some r in objects} == {"unusable"}
	missing := _sentence_rows({"c": "x is not in $params.lists named by $params.nope"}, _named_things, _named_params)
	{r[2] | some r in missing} == {"absent"}
}

test_named_by_works_after_each_phrase_that_takes_a_list if {
	causes := {sentence: [r[2] | some r in _sentence_rows({"c": sentence}, _named_things, _named_params)] |
		some sentence in [
			"x is not in $params.lists named by $params.k",
			"x matches $params.pats named by $params.k",
			"x does not match $params.pats named by $params.k",
			"x matches $params.pats named by $params.kbad",
			"kind contains $params.lists named by $params.k",
			"kind contains none of $params.lists named by $params.k",
		]
	}
	causes["x is not in $params.lists named by $params.k"] == ["value", "satisfied", "value", "value", "value", "unusable"]
	causes["x matches $params.pats named by $params.k"] == ["value", "value", "value", "value", "value", "unusable"]
	causes["x does not match $params.pats named by $params.k"] == ["satisfied", "satisfied", "satisfied", "satisfied", "satisfied", "unusable"]
	causes["x matches $params.pats named by $params.kbad"] == ["unusable", "unusable", "unusable", "unusable", "unusable", "unusable"]
	causes["kind contains $params.lists named by $params.k"] == ["unusable", "unusable", "unusable", "unusable", "absent", "unusable"]
	causes["kind contains none of $params.lists named by $params.k"] == ["unusable", "unusable", "unusable", "unusable", "absent", "unusable"]
}

_named_count_in_whose(xs) := [[r.passed, r.cause] | some r in ergo.report({"things": [{"id": "t", "xs": xs}]}, _sentence_policy({"c": "count of xs whose count of $params.lists named by kind is 1 is 1"}), {"lists": {"a": [1]}}).results; r.check == "c"]

test_a_count_named_by_a_missing_or_wrong_key_in_a_whose_fails_closed if {
	_named_count_in_whose([{"kind": "a"}]) == [[true, "satisfied"]]
	_named_count_in_whose([{}]) == [[false, "absent"]]
	_named_count_in_whose([{"kind": 5}]) == [[false, "unusable"]]
	_named_count_in_whose([{"kind": "b"}]) == [[false, "absent"]]
}

_commits(ts) := [{"author": a, "timestamp": t} | some i, t in ts; a := ["ada", "grace", "linus", "ken"][i]]

_picked(item, ts) := [row[1], row[2], row[3]] if {
	some row in _for_rows({"for": concat("", [item, " as c"]), "assert": `c.author is "x"`}, [{"id": 1, "commits": _commits(ts)}], {})
}

_picked_author(item, ts) := a if {
	[row[1] | some row in _for_rows({"for": concat("", [item, " as c"]), "assert": `c.author is "ada"`}, [{"id": 1, "commits": _commits(ts)}], {})] == ["satisfied"]
	a := "ada"
} else := a if {
	some a in ["grace", "linus", "ken"]
	[row[1] | some row in _for_rows({"for": concat("", [item, " as c"]), "assert": concat("", [`c.author is "`, a, `"`])}, [{"id": 1, "commits": _commits(ts)}], {})] == ["satisfied"]
}

test_a_for_item_that_picks_with_brackets_is_written_wrong if {
	msg := [`for: an item starts with "every", "some" or a position, like "last of"`]
	_sentence_problems({"assert": "i exists", "for": "t[0] as i"}) == msg
	_sentence_problems({"assert": "i exists", "for": "t[0].u as i"}) == msg
	_sentence_problems({"assert": "i exists", "for": "t.u[1] as i"}) == msg
	_sentence_problems({"assert": "i exists", "for": "every t as x, t[0] as i"}) == msg
	_sentence_problems({"assert": "i exists", "for": "every t as x, t[0].u as i"}) == msg
	_sentence_problems({"assert": "i exists", "for": "every t as x, t.u[1] as i"}) == msg
}

test_a_for_item_that_picks_with_brackets_still_lists_the_line_s_other_problems if {
	_sentence_problems({"assert": "x exists", "for": "every t as x, t as x"}) == [
		`for: an item starts with "every", "some" or a position, like "last of"`,
		"for: x is given twice",
	]
	_sentence_problems({"assert": "x exists", "for": "every t as x, t[0] as x"}) == [
		`for: an item starts with "every", "some" or a position, like "last of"`,
		"for: x is given twice",
	]
}

test_brackets_in_a_for_item_that_starts_with_every_some_or_a_position_are_read if {
	"items" in object.keys(ergo._for_line("first of t as i"))
	"items" in object.keys(ergo._for_line("some t[0] as i"))
	"items" in object.keys(ergo._for_line("every t[0].u as i"))
	"items" in object.keys(ergo._for_line("every t as x, some t[0] as i"))
	"items" in object.keys(ergo._for_line("every t as x, every t[0].u as i"))
	"items" in object.keys(ergo._for_line("every t as x, first of x.u as i"))
}

test_a_for_line_picks_an_item_by_its_position_as_written if {
	_picked_author("first of commits", [3, 1, 2]) == "ada"
	_picked_author("item 2 of commits", [3, 1, 2]) == "grace"
	_picked_author("last of commits", [3, 1, 2]) == "linus"
	_picked_author("item 2 from last of commits", [3, 1, 2]) == "grace"
}

test_a_for_line_picks_an_item_by_its_position_sorted_by_a_field if {
	_picked_author("first of commits sorted by timestamp", [3, 1, 2]) == "grace"
	_picked_author("item 2 of commits sorted by timestamp", [3, 1, 2]) == "linus"
	_picked_author("last of commits sorted by timestamp", [3, 1, 2]) == "ada"
	_picked_author("item 2 from last of commits sorted by timestamp", [3, 1, 2]) == "linus"
}

test_a_picked_item_that_fails_is_named_by_where_it_is_in_the_input if {
	_picked("last of commits sorted by timestamp", [3, 1, 2]) == [
		"value",
		[{"path": "item 1 of commits", "item": "item 1 of commits", "cause": "value", "value": {"author": "ada", "timestamp": 3}, "failed_assertions": [{"assertion": `c.author is "x"`, "cause": "value"}], "locations": ["/things/0/commits/0"]}],
		[{"name": "item 1 of commits", "value": {"author": "ada", "timestamp": 3}, "locations": ["/things/0/commits/0"]}],
	]
}

test_a_tie_at_the_picked_position_fails_as_ambiguous_and_names_the_tied_items if {
	_picked("last of commits sorted by timestamp", [1, 3, 3]) == [
		"ambiguous",
		[
			{"path": "item 2 of commits", "item": "item 2 of commits", "cause": "ambiguous", "value": 3, "failed_assertions": [], "locations": ["/things/0/commits/1/timestamp"]},
			{"path": "item 3 of commits", "item": "item 3 of commits", "cause": "ambiguous", "value": 3, "failed_assertions": [], "locations": ["/things/0/commits/2/timestamp"]},
		],
		[{"name": "commits[]", "value": [{"author": "ada", "timestamp": 1}, {"author": "grace", "timestamp": 3}, {"author": "linus", "timestamp": 3}], "locations": ["/things/0/commits/0", "/things/0/commits/1", "/things/0/commits/2"]}],
	]
}

test_a_tie_away_from_the_picked_position_doesnt_matter if {
	_picked_author("last of commits sorted by timestamp", [1, 1, 3]) == "linus"
}

test_a_sort_field_missing_null_or_of_the_wrong_type_on_any_item_fails_without_picking if {
	[_picked("last of commits sorted by timestamp", ts)[0] | some ts in [
		[1, null, 3],
		[1, "x", 3],
		[1, "2026-10-01T00:00:00Z", 3],
		[1, true, 3],
		[1, [2], 3],
	]] == ["null", "unusable", "unusable", "unusable", "unusable"]
	rows := _for_rows({"for": "last of commits sorted by timestamp as c", "assert": "c.author exists"}, [{"id": 1, "commits": [{"author": "ada", "timestamp": 1}, {"author": "grace"}]}], {})
	rows[0][1] == "absent"
	rows[0][2] == [{"path": "item 2 of commits", "item": "item 2 of commits", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0/commits/1"]}]
}

test_a_list_can_be_sorted_by_time if {
	_picked_author("last of commits sorted by timestamp", ["2026-10-02T00:00:00Z", "2026-10-02T01:00:00+02:00", "2026-10-01T22:00:00Z"]) == "ada"
	_picked_author("first of commits sorted by timestamp", ["2026-10-02T00:00:00Z", "2026-10-02T01:00:00+02:00", "2026-10-01T22:00:00Z"]) == "linus"
}

test_a_position_past_the_end_or_an_empty_list_fails_as_absent if {
	[_picked(item, [1, 2])[0] | some item in ["item 3 of commits", "item 3 from last of commits sorted by timestamp"]] == ["absent", "absent"]
	[_picked("last of commits", [])[0]] == ["absent"]
}

test_a_list_that_isnt_there_or_isnt_a_list_fails_as_a_walk_does if {
	[row[1] | some row in _for_rows({"for": "last of commits as c", "assert": "c exists"}, [{"id": 1}, {"id": 2, "commits": 1}, {"id": 3, "commits": null}], {})] == ["absent", "unusable", "null"]
}

test_a_whose_filters_the_list_before_it_is_sorted if {
	check := {"for": `last of approvers whose state is "APPROVED" sorted by timestamp as approval`, "assert": `approval.username is "ada"`}
	approvers := [{"username": "ada", "state": "APPROVED", "timestamp": 3}, {"username": "grace", "state": "CHANGES_REQUESTED", "timestamp": 5}, {"username": "linus", "state": "APPROVED"}]
	[row[1] | some row in _for_rows(check, [{"id": 1, "approvers": array.slice(approvers, 0, 2)}], {})] == ["satisfied"]
	[row[1] | some row in _for_rows(check, [{"id": 1, "approvers": approvers}], {})] == ["absent"]
	[row[1] | some row in _for_rows(check, [{"id": 1, "approvers": [approvers[1]]}], {})] == ["absent"]
	[row[1] | some row in _for_rows(check, [{"id": 1, "approvers": [{"username": "ken", "timestamp": 1}, approvers[0]]}], {})] == ["absent"]
}

test_a_picked_item_and_a_walk_share_a_for_line if {
	check := {
		"for": "some approvers as approver, last of commits sorted by timestamp as last_commit",
		"assert": "approver.username does not equal last_commit.author_username",
	}
	commits := [{"author_username": "ada", "timestamp": 2}, {"author_username": "grace", "timestamp": 1}]
	[row[1] | some row in _for_rows(
		check, [
			{"id": 1, "approvers": [{"username": "grace"}], "commits": commits},
			{"id": 2, "approvers": [{"username": "ada"}], "commits": commits},
		],
		{},
	)] == ["satisfied", "value"]
	reverse := {
		"for": "last of commits sorted by timestamp as last_commit, some approvers as approver",
		"assert": "approver.username does not equal last_commit.author_username",
	}
	[row[1] | some row in _for_rows(
		reverse, [
			{"id": 1, "approvers": [{"username": "grace"}], "commits": commits},
			{"id": 2, "approvers": [{"username": "ada"}], "commits": commits},
		],
		{},
	)] == ["satisfied", "value"]
}

test_a_pick_prints_as_written if {
	check := {"for": `item 2 from last of approvers whose state is "APPROVED" sorted by timestamp as approval`, "assert": "approval exists"}
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": check}), {}).requirements.s.checks.c.expression == `for item 2 from last of approvers whose state is "APPROVED" sorted by timestamp as approval: approval exists`
}

test_a_pick_written_wrong_says_why if {
	_sentence_problems({"assert": "x exists", "for": "xs as x"}) == [`for: an item starts with "every", "some" or a position, like "last of"`]
	_sentence_problems({"assert": "x exists", "for": "every xs sorted by t as x"}) == [`for: "sorted by" goes after a position, like "last of", not after every or some`]
	_sentence_problems({"assert": "x exists", "for": "last of xs, if any, as x"}) == ["for: if any can't go with a position"]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by $params.t as x"}) == [`for: "sorted by" reads a field of each item`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by last of t as x"}) == [`for: "sorted by" reads a field of each item`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by y.t as x, every ys as y"}) == [`for: "sorted by" reads a field of the item, not y: write .y`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by x as x"}) == [`for: "sorted by" reads a field of the item, not x: write .x`]
}

test_last_of_in_a_sentence_points_to_the_for_line if {
	every text in ["last of xs is 1", "item 2 from last of xs is 1"] {
		_sentence_problems({"assert": text}) == [`last of isn't supported yet here: pick the item on a for line, like "for: last of commits as commit"`]
	}
}

test_a_pick_reads_items_that_arent_objects_as_not_an_object_when_sorted if {
	rows := _for_rows({"for": "last of xs sorted by t as x", "assert": "x exists"}, [{"id": 1, "xs": [1, {"t": 2}]}], {})
	rows[0][1] == "not_an_object"
	rows[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "not_an_object", "value": null, "failed_assertions": [], "locations": ["/things/0/xs/0"]}]
	[row[1] | some row in _for_rows({"for": "last of xs as x", "assert": "x is 1"}, [{"id": 1, "xs": [{"t": 2}, 1]}], {})] == ["satisfied"]
}

test_numbers_and_times_in_one_sort_field_fail_as_unusable_on_the_times if {
	rows := _for_rows({"for": "last of xs sorted by t as x", "assert": "x exists"}, [{"id": 1, "xs": [{"t": 1}, {"t": "2026-10-01T00:00:00Z"}]}], {})
	rows[0][1] == "unusable"
	rows[0][2] == [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "unusable", "value": "2026-10-01T00:00:00Z", "failed_assertions": [], "locations": ["/things/0/xs/1/t"]}]
}

test_a_pick_sorts_every_item_a_longer_path_walks_to if {
	check := {"for": "last of pull_requests.commits sorted by timestamp as c", "assert": `c.author is "grace"`}
	prs := [{"commits": [{"author": "ada", "timestamp": 1}]}, {"commits": []}, {"commits": [{"author": "grace", "timestamp": 2}]}]
	[row[1] | some row in _for_rows(check, [{"id": 1, "pull_requests": prs}], {})] == ["satisfied"]
	rows := _for_rows(check, [{"id": 1, "pull_requests": array.concat(prs, [{"commits": 1}])}], {})
	rows[0][1] == "unusable"
	rows[0][2] == [{"path": "pull_requests[3].commits", "item": "pull_requests[3].commits", "cause": "unusable", "value": 1, "failed_assertions": [], "locations": ["/things/0/pull_requests/3/commits"]}]
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

test_a_pick_sorted_by_a_field_named_by_a_param_reads_the_param if {
	check := {"for": "last of xs sorted by t named by $params.k as x", "assert": "x.n is 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"n": 1, "t": {"a": 1, "b": 9}}, {"n": 2, "t": {"a": 2, "b": 0}}]}], {"k": "a"})] == ["satisfied"]
}

test_a_pick_that_doesnt_start_from_the_first_name_fails_the_check_as_it_would_written_first if {
	commits := [{"author": "ada", "timestamp": 2}, {"author": "grace", "timestamp": 2}]
	first := _for_rows({"for": "last of commits sorted by timestamp as c, some approvers as approver", "assert": "approver.username does not equal c.author"}, [{"id": 1, "approvers": [{"username": "linus"}], "commits": commits}], {})
	second := _for_rows({"for": "some approvers as approver, last of commits sorted by timestamp as c", "assert": "approver.username does not equal c.author"}, [{"id": 1, "approvers": [{"username": "linus"}], "commits": commits}], {})
	[first[0][1], first[0][2]] == [second[0][1], second[0][2]]
	second[0][1] == "ambiguous"
	[f.path | some f in second[0][2]] == ["item 1 of commits", "item 2 of commits"]
	[row[1] | some row in _for_rows({"for": "some approvers as approver, item 3 of commits as c", "assert": "approver exists"}, [{"id": 1, "approvers": [1], "commits": commits}], {})] == ["absent"]
}

test_sorted_by_reads_a_field_of_the_item_with_a_dot_or_an_index_after_it if {
	check := {"for": "last of xs sorted by .x as x", "assert": "x.n is 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"n": 1, "x": 9}, {"n": 2, "x": 1}]}], {})] == ["value"]
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"n": 1, "x": 1}, {"n": 2, "x": 9}]}], {})] == ["satisfied"]
	indexed := {"for": "last of xs sorted by ts[0] as x", "assert": "x.n is 2"}
	[row[1] | some row in _for_rows(indexed, [{"id": 1, "xs": [{"n": 1, "ts": [1, 9]}, {"n": 2, "ts": [2, 0]}]}], {})] == ["satisfied"]
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": indexed}), {}).requirements.s.checks.c.expression == "for last of xs sorted by ts[0] as x: x.n is 2"
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": check}), {}).requirements.s.checks.c.expression == "for last of xs sorted by .x as x: x.n is 2"
	earlier := {"for": "some ys as y, last of xs sorted by .y as x", "assert": "x.n is 2"}
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": earlier}), {}).requirements.s.checks.c.expression == "for some ys as y, last of xs sorted by .y as x: x.n is 2"
	plain := {"for": "last of xs sorted by .t as x", "assert": "x.n is 2"}
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": plain}), {}).requirements.s.checks.c.expression == "for last of xs sorted by t as x: x.n is 2"
}

test_a_number_out_of_range_after_a_time_or_order_phrase_is_reported_once if {
	_sentence_problems({"assert": "x is before 1e400"}) == ["number out of range: 1e400"]
	_sentence_problems({"assert": "x is at least 1e400"}) == ["number out of range: 1e400"]
}

test_a_written_value_after_an_order_phrase_has_to_be_a_number if {
	_sentence_problems({"assert": "x is at most \"3\""}) == [`"is at most" takes a number`]
	_sentence_problems({"assert": "x is less than true"}) == [`"is less than" takes a number`]
}

test_a_written_date_after_a_time_phrase_is_a_time if {
	[r.cause | some r in ergo.report({"things": [{"id": 1, "x": "2026-09-30"}, {"id": 2, "x": "2026-10-01"}]}, _sentence_policy({"c": "x is before \"2026-10-01\""}), {}).results; r.check == "c"] == ["satisfied", "value"]
}

test_a_failed_line_lists_the_values_it_compared_for_each_pair_of_items if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows_full(check, [{"id": 1, "approvers": [{"t": 5}, {"t": 2}], "commits": [{"t": 1}, {"t": 9}]}], {})
	rows[0][2][0].failed_assertions == [{"assertion": "approver.t is more than commit.t", "cause": "value", "items": [{"item": "item 2 of commits", "cause": "value", "inputs": [
		{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
		{"name": "commit.t", "value": 9, "locations": ["/things/0/commits/1/t"]},
	]}]}]
	rows[0][2][1].failed_assertions[0].items == [{"item": "item 2 of commits", "cause": "value", "inputs": [
		{"name": "approver.t", "value": 2, "locations": ["/things/0/approvers/1/t"]},
		{"name": "commit.t", "value": 9, "locations": ["/things/0/commits/1/t"]},
	]}]
}

test_a_failed_line_that_doesnt_read_the_second_items_name_lists_what_it_read_on_the_line_itself if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": ["approver.username does not equal author", "approver.t is more than commit.t"]}
	rows := _for_rows_full(check, [{"id": 1, "author": "ann", "approvers": [{"username": "ann", "t": 5}], "commits": [{"t": 1}, {"t": 9}]}], {})
	rows[0][2][0].failed_assertions[0] == {"assertion": "approver.username does not equal author", "cause": "value", "inputs": [
		{"name": "approver.username", "value": "ann", "locations": ["/things/0/approvers/0/username"]},
		{"name": "author", "value": "ann", "locations": ["/things/0/author"]},
	]}
}

test_a_failed_line_on_one_item_lists_what_it_read if {
	rows := _for_rows_full({"for": "every xs as x", "assert": ["x.k is 1", "x.k is more than limit"]}, [{"id": 1, "limit": 7, "xs": [{"k": 1}, {"k": 2}]}], {})
	rows[0][2][0].failed_assertions == [
		{"assertion": "x.k is more than limit", "cause": "value", "inputs": [
			{"name": "x.k", "value": 1, "locations": ["/things/0/xs/0/k"]},
			{"name": "limit", "value": 7, "locations": ["/things/0/limit"]},
		]},
	]
	rows[0][2][1].failed_assertions[0].inputs == [{"name": "x.k", "value": 2, "locations": ["/things/0/xs/1/k"]}]
}

test_a_failed_line_that_counts_through_an_alias_lists_the_number_then_the_list if {
	rows := _for_rows_full({"for": "every commits as commit", "assert": "count of commit.files is at least 2"}, [{"id": 1, "commits": [{"files": ["a", "b"]}, {"files": ["c"]}]}], {})
	rows[0][2][0].failed_assertions[0].inputs == [
		{"name": "count of commit.files", "value": 1, "locations": ["/things/0/commits/1/files/0"]},
		{"name": "commit.files[]", "value": ["c"], "locations": ["/things/0/commits/1/files/0"]},
	]
}

test_a_failed_line_lists_where_a_read_stopped_for_a_missing_null_or_wrong_typed_second_item if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows_full(check, [{"id": 1, "approvers": [{"t": 5}], "commits": [{}, {"t": null}, "x", {"t": 9}]}], {})
	rows[0][1] == "not_an_object"
	rows[0][2][0].failed_assertions[0].items == [
		{"item": "item 1 of commits", "cause": "absent", "inputs": [
			{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
			{"name": "commit.t", "value": null, "locations": ["/things/0/commits/0"]},
		]},
		{"item": "item 2 of commits", "cause": "null", "inputs": [
			{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
			{"name": "commit.t", "value": null, "locations": ["/things/0/commits/1/t"]},
		]},
		{"item": "item 3 of commits", "cause": "not_an_object", "inputs": [
			{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
			{"name": "commit.t", "value": null, "locations": ["/things/0/commits/2"]},
		]},
		{"item": "item 4 of commits", "cause": "value", "inputs": [
			{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
			{"name": "commit.t", "value": 9, "locations": ["/things/0/commits/3/t"]},
		]},
	]
}

test_a_failed_line_after_a_picked_item_lists_where_the_picked_item_is_in_the_input if {
	check := {"for": "last of commits sorted by t as last_commit, some approvers as approver", "assert": "approver.u does not equal last_commit.u"}
	rows := _for_rows_full(check, [{"id": 1, "approvers": [{"u": "ada"}], "commits": [{"u": "ada", "t": 2}, {"u": "bob", "t": 1}]}], {})
	rows[0][2][0].failed_assertions[0].items[0].inputs == [
		{"name": "approver.u", "value": "ada", "locations": ["/things/0/approvers/0/u"]},
		{"name": "last_commit.u", "value": "ada", "locations": ["/things/0/commits/0/u"]},
	]
}

test_a_failed_line_that_names_a_key_with_an_alias_lists_the_value_read_and_not_the_alias if {
	check := {"for": "every dispatched as persona", "assert": `shas named by persona matches "^[0-9a-f]{40}$"`}
	rows := _for_rows_full(check, _persona_doc.things, {})
	rows[1][2][0].failed_assertions[0].inputs == [{"name": "shas named by persona", "value": "x", "locations": ["/things/1/shas/security"]}]
	rows[1][2][1].failed_assertions[0].inputs == [{"name": "shas named by persona", "value": null, "locations": ["/things/1/shas"]}]
}

test_a_failed_line_that_reads_a_part_tags_the_input_with_it if {
	has := {"cov": "dd.b", "lst": "dd.items"}
	rep := _parts_report(has, {"c": {"for": "every lst as entry", "assert": "entry.x is cov.x"}}, {"b": {"x": 2}, "items": [{"x": 1}]})
	_parts_row(rep, "c").failed_items[0].failed_assertions[0].inputs == [
		{"name": "entry.x", "value": 1, "locations": ["/trail/dd/items/0/x"]},
		{"name": "cov.x", "value": 2, "locations": ["/trail/dd/b/x"], "part": {"name": "cov", "id": null}},
	]
}

test_a_failed_line_lists_its_values_in_the_violations_too if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	r := ergo.report({"things": [{"id": 1, "approvers": [{"t": 5}], "commits": [{"t": 9}]}]}, _sentence_policy({"c": check}), {})
	[v.failed_items[0].failed_assertions[0].items[0].inputs | some v in ergo.violations(r); v.check == "c"] == [[
		{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
		{"name": "commit.t", "value": 9, "locations": ["/things/0/commits/0/t"]},
	]]
}

_line_inputs(check, things) := [l.inputs | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), {}).results; r.check == "c"; some f in r.failed_items; some l in f.failed_assertions]

test_a_failed_line_names_an_alias_that_holds_a_list_as_the_sentence_writes_it if {
	things := [{"id": 1, "batches": [["x", "y"], []]}]
	_line_inputs({"for": "every batches as b", "assert": `first of b is "x"`}, things) == [[{"name": "item 1 of b", "value": null, "locations": ["/things/0/batches/1"]}]]
	_line_inputs({"for": "every batches as b", "assert": "count of b is at least 3"}, things) == [
		[{"name": "count of b", "value": 2, "locations": ["/things/0/batches/0/0", "/things/0/batches/0/1"]}, {"name": "b[]", "value": ["x", "y"], "locations": ["/things/0/batches/0/0", "/things/0/batches/0/1"]}],
		[{"name": "count of b", "value": 0, "locations": []}, {"name": "b[]", "value": [], "locations": []}],
	]
	_line_inputs({"for": "every m as x", "assert": "item 3 of x.q is 1"}, [{"id": 1, "m": [{"q": [1]}]}]) == [[{"name": "item 3 of x.q", "value": null, "locations": ["/things/0/m/0/q"]}]]
}

test_a_failed_line_names_an_alias_read_by_a_key_as_the_sentence_writes_it if {
	things := [{"id": 1, "key": "k1", "n": [{"k1": [1, 2]}]}]
	_line_inputs({"for": "every n as c", "assert": "c named by key is 9"}, things) == [[
		{"name": "c named by key", "value": [1, 2], "locations": ["/things/0/n/0/k1"]},
		{"name": "key", "value": "k1", "locations": ["/things/0/key"]},
	]]
	_line_inputs({"for": "every n as c", "assert": "first of c named by key is 9"}, things) == [[
		{"name": "item 1 of c named by key", "value": 1, "locations": ["/things/0/n/0/k1/0"]},
		{"name": "key", "value": "k1", "locations": ["/things/0/key"]},
	]]
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

test_a_failed_line_lists_a_value_it_reads_twice_once_for_each_pair_of_items if {
	things := [{"id": 1, "commits": [{"ts": 5}], "ap": [{"ts": 9}, {"ts": 1}]}]
	check := {"for": "every commits as c, every ap as ap", "assert": "c.ts is at least c.ts plus ap.ts"}
	rows := _for_rows_full(check, things, {})
	[x.inputs | some x in rows[0][2][0].failed_assertions[0].items] == [
		[{"name": "c.ts", "value": 5, "locations": ["/things/0/commits/0/ts"]}, {"name": "c.ts plus ap.ts", "value": 14, "locations": ["/things/0/commits/0/ts", "/things/0/ap/0/ts"]}, {"name": "ap.ts", "value": 9, "locations": ["/things/0/ap/0/ts"]}],
		[{"name": "c.ts", "value": 5, "locations": ["/things/0/commits/0/ts"]}, {"name": "c.ts plus ap.ts", "value": 6, "locations": ["/things/0/commits/0/ts", "/things/0/ap/1/ts"]}, {"name": "ap.ts", "value": 1, "locations": ["/things/0/ap/1/ts"]}],
	]
}

test_a_failed_line_orders_two_reads_of_one_name_by_where_they_were_read_as_a_row_does if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": {"for": "every cs as c", "assert": "c.ts is at least b.x plus .b.x"}}}}}
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 1}, "cs": [{"ts": 1}]}]}]}, policy, {})
	[i.locations | some r in rep.results; r.check == "c"; some i in r.failed_items[0].failed_assertions[0].inputs; i.name == "b.x"] == [["/bs/0/kids/0/b/x"], ["/bs/0/x"]]
}

test_a_failed_line_names_the_items_of_the_second_list_it_failed_on if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	[[f.item, f.failed_assertions] | some f in rows[1][2]] == [
		["item 1 of approvers", [{"assertion": "approver.timestamp is after commit.timestamp", "cause": "value", "items": [{"item": "item 2 of commits", "cause": "value"}]}]],
		["item 2 of approvers", [{"assertion": "approver.username does not equal author", "cause": "value"}]],
	]
}

test_the_items_of_the_second_list_are_in_list_order_not_alphabetical if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	commits := [{"t": t} | some t in [1, 9, 1, 1, 1, 1, 1, 1, 1, 9]]
	rows := _for_rows(check, [{"id": 1, "approvers": [{"t": 5}], "commits": commits}], {})
	rows[0][2][0].failed_assertions[0].items == [{"item": "item 2 of commits", "cause": "value"}, {"item": "item 10 of commits", "cause": "value"}]
}

test_a_second_item_that_cant_be_read_is_named_with_the_line_it_failed if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"t": 5}], "commits": [{"t": 1}, {}]}], {})
	rows[0][1] == "absent"
	rows[0][2][0].failed_assertions == [{"assertion": "approver.t is more than commit.t", "cause": "absent", "items": [{"item": "item 2 of commits", "cause": "absent"}]}]
}

test_a_failed_line_names_the_items_of_a_second_list_walked_inside_the_first if {
	check := {"for": "every pull_requests as pr, some pr.approvers as approver", "assert": "approver.username does not equal pr.author"}
	rows := _for_rows(check, [{"id": 1, "pull_requests": [{"author": "ann", "approvers": [{"username": "bob"}]}, {"author": "cat", "approvers": [{"username": "cat"}]}]}], {})
	rows[0][2][0].failed_assertions == [{"assertion": "approver.username does not equal pr.author", "cause": "value", "items": [{"item": "item 1 of pr.approvers", "cause": "value"}]}]
}

test_a_failed_line_after_a_picked_item_names_the_items_of_the_second_list if {
	check := {"for": "last of commits sorted by t as last_commit, some approvers as approver", "assert": "approver.u does not equal last_commit.u"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"u": "ada"}, {"u": "ada"}], "commits": [{"u": "ada", "t": 2}, {"u": "bob", "t": 1}]}], {})
	rows[0][2] == [{"path": "item 1 of commits", "item": "item 1 of commits", "cause": "value", "value": {"u": "ada", "t": 2}, "failed_assertions": [{"assertion": "approver.u does not equal last_commit.u", "cause": "value", "items": [{"item": "item 1 of approvers", "cause": "value"}, {"item": "item 2 of approvers", "cause": "value"}]}], "locations": ["/things/0/commits/0"]}]
}

test_a_for_item_that_failed_shows_the_item_as_its_value if {
	rows := _for_rows({"for": "every xs as x", "assert": "x.k is 1"}, [{"id": 1, "xs": [{"k": 1}, {"k": 2}]}], {})
	rows[0][2] == [{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "value", "value": {"k": 2}, "failed_assertions": [{"assertion": "x.k is 1", "cause": "value"}], "locations": ["/things/0/xs/1"]}]
}

test_a_failed_line_that_doesnt_read_the_second_items_name_names_no_items if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": ["approver.username does not equal author", "approver.t is more than commit.t"]}
	rows := _for_rows(check, [{"id": 1, "author": "ann", "approvers": [{"username": "ann", "t": 5}], "commits": [{"t": 1}, {"t": 9}]}], {})
	rows[0][2][0].failed_assertions == [
		{"assertion": "approver.username does not equal author", "cause": "value"},
		{"assertion": "approver.t is more than commit.t", "cause": "value", "items": [{"item": "item 2 of commits", "cause": "value"}]},
	]
}

test_a_failed_line_reads_the_second_items_name_in_a_whose_or_a_named_by_but_not_in_a_quoted_value if {
	check := {"for": "every xs as x, every ys as y", "assert": [`x.k is "$y"`, "count of x.zs whose k equals y.k is 1", "m named by y is 1"]}
	rows := _for_rows(check, [{"id": 1, "m": {"a": 2}, "xs": [{"k": "b", "zs": []}], "ys": ["a"]}], {})
	rows[0][2][0].failed_assertions == [
		{"assertion": `x.k is "$y"`, "cause": "value"},
		{"assertion": "count of x.zs whose k equals y.k is 1", "cause": "value", "items": [{"item": "item 1 of ys", "cause": "value"}]},
		{"assertion": "m named by y is 1", "cause": "value", "items": [{"item": "item 1 of ys", "cause": "value"}]},
	]
}

test_a_second_list_item_whose_whose_reads_the_first_name_and_cant_decide_is_listed_under_its_first_item if {
	check := {"for": "some approvers as approver, every commits whose author does not equal approver.u as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"u": "bob", "t": 5}], "commits": [{"t": 1, "author": "ann"}, {"t": 2}]}], {})
	rows[0][1] == "absent"
	rows[0][2] == [{
		"path": "item 1 of approvers", "item": "item 1 of approvers", "cause": "absent", "value": {"u": "bob", "t": 5}, "failed_assertions": [],
		"failed_items": [{"path": "item 2 of commits", "item": "item 2 of commits", "cause": "absent", "value": {"t": 2}, "locations": ["/things/0/commits/1"]}], "locations": ["/things/0/approvers/0"],
	}]
}

test_a_list_beside_the_first_whose_whose_cant_decide_without_the_first_name_is_listed_once if {
	check := {"for": `some approvers as approver, every commits whose kind is "code" as commit`, "assert": "approver.t is more than commit.t"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"t": 5}, {"t": 6}], "commits": [{"t": 1, "kind": "code"}, {"t": 2}]}], {})
	rows[0][1] == "absent"
	rows[0][2] == [{"path": "item 2 of commits", "item": "item 2 of commits", "cause": "absent", "value": {"t": 2}, "failed_assertions": [], "locations": ["/things/0/commits/1"]}]
}

test_a_second_list_beside_the_first_that_cant_be_walked_is_listed_as_a_walk_lists_it if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"t": 5}]}, {"id": 2, "approvers": [{"t": 5}], "commits": []}, {"id": 3, "approvers": [{"t": 5}], "commits": null}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "commits", "item": "commits", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0"]}]],
		[2, "value", [{"path": "commits", "item": "commits", "cause": "value", "value": [], "failed_assertions": [], "locations": ["/things/1/commits"]}]],
		[3, "null", [{"path": "commits", "item": "commits", "cause": "null", "value": null, "failed_assertions": [], "locations": ["/things/2/commits"]}]],
	]
}

test_a_second_list_inside_the_first_that_cant_be_walked_is_listed_under_each_first_item if {
	check := {"for": "every prs as pr, some pr.approvers as approver", "assert": "approver.t is 1"}
	rows := _for_rows(check, [{"id": 1, "prs": [{}, {"approvers": null}]}], {})
	[f.failed_items | some f in rows[0][2]] == [
		[{"path": "pr.approvers", "item": "pr.approvers", "cause": "absent", "value": null, "locations": ["/things/0/prs/0"]}],
		[{"path": "pr.approvers", "item": "pr.approvers", "cause": "null", "value": null, "locations": ["/things/0/prs/1/approvers"]}],
	]
}

test_a_second_list_inside_the_first_that_failed_before_any_line_is_named_with_the_alias if {
	check := {"for": "every pull_requests as pr, some pr.approvers as approver", "assert": "approver.username does not equal pr.author"}
	rows := _for_rows(check, [{"id": 1, "pull_requests": [{"author": "ann", "approvers": []}]}], {})
	rows[0][2][0].failed_items == [{"path": "pr.approvers", "item": "pr.approvers", "cause": "value", "value": [], "locations": ["/things/0/pull_requests/0/approvers"]}]
}

test_a_second_list_item_that_failed_on_a_line_is_not_listed_again_under_its_first_item if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	rows := _for_rows(check, [{"id": 1, "approvers": [{"t": 5}], "commits": [{"t": 9}]}], {})
	not "failed_items" in object.keys(rows[0][2][0])
}

test_a_for_item_whose_path_ends_at_a_field_shows_what_its_alias_stands_for_as_its_value if {
	check := {"for": "every prs.author as who", "assert": `who is "ann"`}
	rows := _for_rows(check, [{"id": 1, "prs": [{"author": "ann"}, {"author": "bob"}]}], {})
	rows[0][2] == [{"path": "item 2 of prs", "item": "item 2 of prs", "cause": "value", "value": "bob", "failed_assertions": [{"assertion": `who is "ann"`, "cause": "value"}], "locations": ["/things/0/prs/1/author"]}]
}

test_each_second_list_item_a_line_failed_for_has_its_own_cause_and_the_line_has_the_worst if {
	check := {"for": "some xs as x, every ys as y", "assert": "x.t is more than y.t"}
	rows := _for_rows(check, [{"id": 1, "xs": [{"t": 5}], "ys": [{"t": 1}, {"t": 9}, {}]}], {})
	rows[0][2][0].failed_assertions == [{"assertion": "x.t is more than y.t", "cause": "absent", "items": [{"item": "item 2 of ys", "cause": "value"}, {"item": "item 3 of ys", "cause": "absent"}]}]
}

test_a_second_list_beside_the_first_that_cant_be_walked_is_listed_once_in_place_of_each_first_item if {
	check := {"for": "some xs as x, every ys as y", "assert": "x.t is more than y.t"}
	rows := _for_rows(check, [{"id": 1, "xs": [{"t": 5}, {"t": 6}, {"t": 7}]}], {})
	rows[0][1] == "absent"
	rows[0][2] == [{"path": "ys", "item": "ys", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0"]}]
}

test_a_broken_list_beside_the_first_is_listed_once_next_to_the_first_items_that_failed_a_line if {
	check := {"for": "every xs as x, every ys.zs as y", "assert": "x.t is more than y.t"}
	rows := _for_rows(check, [{"id": 1, "xs": [{"t": 5}, {"t": 0}], "ys": [{"zs": [{"t": 1}]}, {}]}], {})
	rows[0][2] == [
		{"path": "item 2 of xs", "item": "item 2 of xs", "cause": "value", "value": {"t": 0}, "failed_assertions": [{"assertion": "x.t is more than y.t", "cause": "value", "items": [{"item": "item 1 of ys[0].zs", "cause": "value"}]}], "locations": ["/things/0/xs/1"]},
		{"path": "ys[1].zs", "item": "ys[1].zs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0/ys/1"]},
	]
}

test_a_list_beside_the_first_still_passes_when_the_first_list_is_empty_and_may_be if {
	check := {"for": "every xs, if any, as x, every ys as y", "assert": "x.t is more than y.t"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": []}], {})] == ["satisfied"]
}

test_a_second_list_inside_the_first_whose_ref_cant_be_read_is_named_under_each_first_item if {
	check := {"for": "every prs as pr, every pr.m named by $params.k as y", "assert": "y is 1"}
	rows := _for_rows(check, [{"id": 1, "prs": [{"m": {"a": [1]}}]}], {})
	rows[0][2] == [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": {"m": {"a": [1]}}, "failed_assertions": [], "failed_items": [{"path": "pr.m named by $params.k", "item": "pr.m named by $params.k", "cause": "absent", "value": null, "locations": ["/things/0/prs/0/m"]}], "locations": ["/things/0/prs/0"]}]
}

test_a_plus_under_a_for_line_whose_term_is_missing_still_shows_the_sum_and_the_term_as_null if {
	check := {"for": "every xs as x", "assert": ["x.a is 1", "n plus 2 is 3"]}
	[[r.cause, r.inputs] | some r in ergo.report({"things": [{"id": 1, "xs": [{"a": 1}]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [["absent", [
		{"name": "n", "value": null, "locations": ["/things/0"]},
		{"name": "n plus 2", "value": null, "locations": ["/things/0"]},
		{"name": "xs[]", "value": [{"a": 1}], "locations": ["/things/0/xs/0"]},
	]]]
}

test_a_plus_under_a_for_line_shows_the_sum_and_each_term if {
	check := {"for": "every xs as x", "assert": ["x.a is 1", "n plus 2 is 3"]}
	[[r.cause, r.inputs] | some r in ergo.report({"things": [{"id": 1, "n": 1, "xs": [{"a": 1}]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [["satisfied", [
		{"name": "n", "value": 1, "locations": ["/things/0/n"]},
		{"name": "n plus 2", "value": 3, "locations": ["/things/0/n"]},
		{"name": "xs[]", "value": [{"a": 1}], "locations": ["/things/0/xs/0"]},
	]]]
}

kinds_doc := {"items": [{"id": 1, "s": "x", "n": 5, "o": {"a": 1}, "e": [], "l": [1], "t": "2026-01-01T00:00:00Z", "bad_t": "2026-02-30T00:00:00Z"}]}

kind_cause(check) := [r.cause | some r in rows_for(report(kinds_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}}), "s", "c")][0]

test_a_value_the_phrase_cannot_use_fails_as_unusable if {
	every check in [
		"s is between 0 and 9",
		"n is \"5\"",
		"n is one of \"5\"",
		"n is one of \"5\", null",
		"l contains \"1\"",
		"l contains none of \"1\"",
		"n matches \"x\"",
		"n does not match \"x\"",
		"s contains \"x\"",
		"s does not contain \"y\"",
		"n equals s",
		"n is before t",
		"bad_t is before t",
		"s.x does not exist",
		"l.x does not exist",
		"item 1 of o does not exist",
	] {
		kind_cause(check) == "unusable"
	}
}

as_sentences_checks(checks) := ergo.as_sentences({"subjects": {"s": {"from": "items"}}, "requirements": {"r": {"subject": "s", "checks": checks}}}).requirements.r.checks

test_as_sentences_writes_each_old_check_as_the_sentence_that_reads_back_the_same if {
	as_sentences_checks({
		"present": {"op": "present", "path": ["a"]},
		"missing": {"op": "missing", "path": ["a"]},
		"nes": {"op": "non_empty_string", "path": ["a"]},
		"in": {"op": "in", "path": ["a"], "values": ["x", 1]},
		"in_ref": {"op": "in", "path": ["a"], "values": {"ref": ["$$params", "allowed"]}},
		"range": {"op": "range", "path": ["n"], "min": 1, "max": 5},
		"matches": {"op": "matches_any", "path": ["a"], "patterns": ["^x"]},
		"not_matches": {"op": "not_matches_any", "path": ["a"], "patterns": ["^x", "y$"]},
		"contains": {"op": "includes", "path": ["xs"], "value": "x"},
		"contains_ref": {"op": "includes", "path": ["xs"], "value": {"ref": ["$$params", "label"]}},
		"contains_all": {"op": "includes", "path": ["xs"], "values": ["x", "y"]},
		"not_contains": {"op": "excludes", "path": ["xs"], "value": "x"},
		"contains_none": {"op": "excludes", "path": ["xs"], "values": ["x", "y"]},
		"compare": {"op": "compare", "left": ["n"], "right": ["m"], "cmp": "lte"},
		"compare_literal": {"op": "compare", "left": ["n"], "right": {"literal": 3}, "cmp": "gt"},
		"within": {"op": "compare", "left": ["n"], "right": ["m"], "cmp": "eq", "within": 0.5},
		"before": {"op": "compare_time", "left": ["t"], "right": ["u"], "cmp": "lt"},
		"described": {"op": "present", "path": ["a"], "description": "A is there", "meta": {"k": 1}},
		"literal_step": {"op": "present", "path": ["o", {"literal": "$x"}]},
		"ref_step": {"op": "present", "path": ["o", {"ref": ["$$params", "k"]}, "v"]},
		"selector": {"op": "present", "path": ["xs", {"where": {"k": "v", "n": {"ref": ["$$params", "n"]}}}, "v"]},
		"bad_step": {"op": "present", "path": ["o", true]},
		"bad_ref": {"op": "in", "path": ["a"], "values": {"ref": ["x"]}},
		"malformed_ref": {"op": "equals", "path": ["a"], "value": {"ref": ["$$params", "k"], "x": 1}},
		"self": {"op": "compare", "left": ["a"], "right": ["a"], "cmp": "eq"},
	}) == {
		"present": ".a exists",
		"missing": ".a does not exist",
		"nes": ".a is a non-empty string",
		"in": ".a is one of \"x\", 1",
		"in_ref": ".a is one of $params.allowed",
		"range": "n is between 1 and 5",
		"matches": ".a matches \"^x\"",
		"not_matches": ".a does not match \"^x\", \"y$\"",
		"contains": "xs contains \"x\"",
		"contains_ref": "xs contains $params.label",
		"contains_all": "xs contains all of \"x\", \"y\"",
		"not_contains": "xs does not contain \"x\"",
		"contains_none": "xs contains none of \"x\", \"y\"",
		"compare": "n is at most m",
		"compare_literal": "n is more than 3",
		"within": "n equals m within 0.5",
		"before": "t is before u",
		"described": {"assert": ".a exists", "description": "A is there", "meta": {"k": 1}},
		"literal_step": {"op": "present", "path": ["o", {"literal": "$x"}]},
		"ref_step": "o named by $params.k.v exists",
		"selector": {"op": "present", "path": ["xs", {"where": {"k": "v", "n": {"ref": ["$$params", "n"]}}}, "v"]},
		"bad_step": {"op": "present", "path": ["o", true]},
		"bad_ref": {"op": "in", "path": ["a"], "values": {"ref": ["x"]}},
		"malformed_ref": {"op": "equals", "path": ["a"], "value": {"ref": ["$$params", "k"], "x": 1}},
		"self": {"cmp": "eq", "left": ["a"], "op": "compare", "right": ["a"]},
	}
}

test_as_sentences_says_the_policy_is_for_this_version_of_the_spec if {
	every policy in [{}, {"ergo_spec": "v0"}, {"ergo_spec": "v0.3-dev", "subjects": {"s": {"from": ["items"]}}}] {
		ergo.as_sentences(policy).ergo_spec == "v0.3-dev"
	}
}

test_as_sentences_leaves_a_field_compared_with_itself_as_written_because_that_sentence_is_written_wrong if {
	as_sentences_checks({"c": {"op": "compare", "left": ["a"], "right": ["a"], "cmp": "eq"}}) == {"c": {"op": "compare", "left": ["a"], "right": ["a"], "cmp": "eq"}}
}

test_as_sentences_leaves_a_subject_path_with_a_literal_step_or_a_key_list_as_written_because_a_from_line_cant_say_it if {
	every subjects in [
		{"s": {"from": ["o", {"literal": "$x"}, "items"]}},
		{"s": {"from": ["o", {"literal": 1}]}},
		{"s": {"from": ["o", {"literal": true}]}},
		{"s": {"from": ["items", {"each_as": "it", "keys": [1, "a"]}]}},
	] {
		ergo.as_sentences({"subjects": subjects}) == {"ergo_spec": "v0.3-dev", "subjects": subjects}
	}
}

test_as_sentences_leaves_an_old_check_with_a_literal_step_or_a_literal_object_as_written if {
	checks := {
		"index": {"op": "present", "path": ["o", {"literal": 1}]},
		"flag": {"op": "present", "path": ["o", {"literal": true}]},
		"spaced": {"op": "present", "path": ["o", {"literal": "a b"}]},
		"object": {"op": "equals", "path": ["a"], "value": {"literal": {"k": 1}}},
	}
	as_sentences_checks(checks) == checks
}

test_as_sentences_leaves_an_old_check_whose_path_starts_at_a_part_alias_as_written if {
	policy := {"subjects": {"s": {"from": ["items"], "has": {"cov": "d.b"}}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"op": "present", "path": ["cov", "x"]}}}}}
	ergo.as_sentences(policy).requirements.r.checks.c == {"op": "present", "path": ["cov", "x"]}
}

test_each_key_named_by_a_list_is_a_subject_even_when_the_object_holding_them_is_missing_or_not_an_object if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"suite": {"from": "atts named by each of $params.names"}}, "requirements": {"r": {"subject": "suite", "checks": {"c": "status is \"COMPLETE\""}}}}
	every doc in [{}, {"atts": "x"}, {"atts": null}] {
		[[r.subject.id, r.cause] | some r in ergo.report(doc, policy, {"names": ["junit", "lint"]}).results; r.check == "c"] == [["junit", "absent"], ["lint", "absent"]]
	}
}

test_as_sentences_keeps_a_sentence_policy_with_parts_as_it_is if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"round": {"from": "rounds", "identified_by": "id", "has": {"a": "  d.b  ", "b": {"from": "d.\"x y\".z", "identified_by": "attestation_id"}, "c": "d.m named by $params.k", "e": "item 3 of d.items", "f": "d.items[1].y"}}}, "requirements": {"r": {"subject": "round", "checks": {"c": "id exists"}}}}
	ergo.as_sentences(policy) == policy
}

test_as_sentences_leaves_an_old_any_of_and_an_object_value_as_written if {
	checks := {
		"either": {"op": "any_of", "options": {"safe": [{"op": "equals", "path": ["type"], "value": "Chore"}], "standard": [{"op": "equals", "path": ["type"], "value": "Story"}, {"op": "equals", "path": ["state"], "value": "Done"}]}},
		"object": {"op": "equals", "path": ["x"], "value": {"a": "x", "b": [1, 2]}},
	}
	as_sentences_checks(checks) == checks
}

reserved_check_rows(name) := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {name: "id exists"}})})

test_a_check_named_like_one_of_ergos_own_rows_is_written_wrong if {
	every name in ["$applies", "$min_subjects", "$unique_ids", "$well_formed"] {
		rep := reserved_check_rows(name)
		problem_inputs(rep) == [{"name": concat(".", ["checks", name]), "value": ["name reserved"], "locations": []}]
		[r.passed | some r in rep.results] == [false]
	}
}

test_a_check_named_like_an_ergo_row_ergo_never_adds_is_allowed if {
	rep := reserved_check_rows("$other")
	problem_inputs(rep) == []
	[r.passed | some r in rows_for(rep, "s", "$other")] == [true]
}

test_a_check_named_like_one_of_ergos_own_rows_leaves_only_ergos_check_in_the_requirement if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {"$well_formed": "id is 2", "$applies": "id is 2"}})})
	object.keys(rep.requirements.s.checks) == {"$min_subjects", "$unique_ids", "$well_formed"}
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

subject_problems(subjects, subject, inp) := [i |
	some r in ergo.report(inp, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": "v exists"}}}}, {}).results
	r.check == "$well_formed"
	some i in r.inputs
	not i.name in {"count(checks)", "require"}
]

test_a_from_line_that_starts_at_a_blank_subject_name_is_written_wrong_under_from if {
	every case in [[" ", `" " whose id is "a"`], [" ", `" ".kids`], ["", `"" whose id is "a"`], ["", `"".kids`]] {
		[name, from] := case
		subjects := {name: {"from": "things", "identified_by": "id"}, "b": {"from": from}}
		subject_problems(subjects, "b", {"things": [{"id": "a", "kids": [{"v": 1}]}]}) == [{"name": "subjects.b.from", "value": [concat("", [`"`, name, `" isn't a subject name`])], "locations": []}]
	}
}

test_child_subjects_that_read_each_other_lead_to_a_loop_not_a_chain_too_deep if {
	subjects := {"b": {"from": "kid.x"}, "kid": {"from": "b.kids"}}
	every name in ["b", "kid"] {
		subject_problems(subjects, name, {}) == [{"name": concat("", ["subjects.", name, ".from"]), "value": ["leads to a loop"], "locations": []}]
	}
}

test_every_subject_in_a_loop_through_child_subjects_is_named_after_its_own_from if {
	every subjects in [
		{"p": {"from": "q.x"}, "q": {"from": "r.x"}, "r": {"from": "p.x"}},
		{"p": {"from": "q"}, "q": {"from": "r.x"}, "r": {"from": "p"}},
		{"p": {"from": "q.x"}, "q": {"from": "r"}, "r": {"from": "p"}},
	] {
		every name in ["p", "q", "r"] {
			subject_problems(subjects, name, {}) == [{"name": concat("", ["subjects.", name, ".from"]), "value": ["leads to a loop"], "locations": []}]
		}
	}
}

test_a_chain_through_a_subject_that_narrows_without_a_loop_is_not_a_loop if {
	subject_problems({"p": {"from": "q.x"}, "q": {"from": "r"}, "r": {"from": "bs"}}, "p", {"bs": []}) == []
}

test_a_chain_four_subjects_deep_without_a_loop_is_still_too_deep if {
	subjects := {"a": {"from": "b.x"}, "b": {"from": "c.x"}, "c": {"from": "d.x"}, "d": {"from": "e.x"}, "e": {"from": "es"}}
	subject_problems(subjects, "a", {}) == [{"name": "subjects.a.from", "value": ["a chain of more than three subjects isn't supported yet"], "locations": []}]
}

test_a_chain_that_reaches_a_loop_further_up_leads_to_a_loop if {
	subjects := {"a": {"from": "b.x"}, "b": {"from": "c.x"}, "c": {"from": "d.x"}, "d": {"from": "e.x"}, "e": {"from": "d.y"}}
	subject_problems(subjects, "a", {}) == [{"name": "subjects.a.from", "value": ["leads to a loop"], "locations": []}]
}

named_by_rows(subjects, subject, check, inp) := [[r.passed, r.inputs] |
	some r in ergo.report(inp, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": check}}}}, {"allowed": {"a": [1]}}).results
	r.check == "c"
]

test_a_part_read_with_named_by_on_the_right_side_shows_the_parts_value if {
	subjects := {"t": {"from": "things", "identified_by": "id", "has": {"cov": "d.b"}}}
	named_by_rows(subjects, "t", "cov.x is one of $params.allowed named by id", {"things": [{"id": "a", "d": {"b": {"x": 1}}}]}) == [[true, [{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": 1, "locations": ["/things/0/d/b/x"]}, {"name": "id", "value": "a", "locations": ["/things/0/id"]}]]]
}

test_a_parent_read_with_named_by_on_the_right_side_shows_the_parents_value if {
	subjects := {"t": {"from": "ts", "identified_by": "id"}, "kid": {"from": "t.kids"}}
	named_by_rows(subjects, "kid", "t.x is one of $params.allowed named by n", {"ts": [{"id": "a", "x": 1, "kids": [{"n": "a"}]}]}) == [[true, [{"name": "t.x", "value": 1, "locations": ["/ts/0/x"]}, {"name": "n", "value": "a", "locations": ["/ts/0/kids/0/n"]}]]]
}

test_a_check_named_like_one_of_ergos_own_rows_that_does_not_parse_is_listed_once if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {"$unique_ids": "id is"}})})
	problem_inputs(rep) == [{"name": "checks.$unique_ids", "value": ["doesn't parse", "name reserved"], "locations": []}]
}

test_a_subject_that_leads_into_a_loop_is_named_after_its_own_from if {
	every subjects in [
		{"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}},
		{"pa": {"from": "pb.x"}, "pb": {"from": "pa.x"}, "pc": {"from": "pa.kids"}},
		{"pa": {"from": "pb.x"}, "pb": {"from": "pa.x"}, "pc": {"from": "pa"}},
	] {
		subject_problems(subjects, "pc", {}) == [{"name": "subjects.pc.from", "value": ["leads to a loop"], "locations": []}]
	}
}

listed_subjects(subjects, subject) := object.keys(ergo.report({}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": "v exists"}}}}, {}).subjects)

test_the_report_lists_every_subject_a_from_line_written_wrong_starts_at if {
	listed_subjects({"x": {"from": "y"}, "y": {"from": "z"}, "z": {"from": "x"}}, "x") == {"x", "y", "z"}
	listed_subjects({"p": {"from": "q.x"}, "q": {"from": "r.x"}, "r": {"from": "p.x"}}, "p") == {"p", "q", "r"}
	listed_subjects({"b": {"from": "kid"}, "kid": {"from": "b.kids"}}, "kid") == {"b", "kid"}
	listed_subjects({"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}, "t": {"from": "things"}}, "pc") == {"pa", "pb", "pc"}
	listed_subjects({" ": {"from": "things"}, "b": {"from": `" ".kids`}}, "b") == {" ", "b"}
}

test_a_for_row_shows_the_parent_fields_its_assertions_read if {
	subjects := {"t": {"from": "ts", "identified_by": "id", "has": {"cov": "d.c"}}, "kid": {"from": "t.kids", "identified_by": "id"}}
	inp := {"ts": [{"id": "t1", "x": 1, "d": {"c": {"q": 3}}, "kids": [{"id": "k1", "rs": [{"v": 1}, {"v": 2}]}]}]}
	rs := {"name": "rs[]", "value": [{"v": 1}, {"v": 2}], "locations": ["/ts/0/kids/0/rs/0", "/ts/0/kids/0/rs/1"]}
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at least t.x"}, inp) == [[true, [rs, {"name": "t.x", "value": 1, "locations": ["/ts/0/x"]}]]]
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at least t.y"}, inp) == [[false, [rs, {"name": "t.y", "value": null, "locations": ["/ts/0"]}]]]
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at most t.cov.q"}, inp) == [[true, [rs, {"name": "t.cov.q", "part": {"id": null, "name": "t.cov"}, "value": 3, "locations": ["/ts/0/d/c/q"]}]]]
}

test_a_whose_with_plus_on_its_left_is_written_wrong if {
	inp := {"ts": [{"id": "t1", "p": 1, "q": 1, "xs": [{"p": 1, "q": 1, "v": 1}], "kids": [{"p": 1, "q": 1}]}]}
	every case in [
		[{"t": {"from": "ts whose p plus q is 2"}}, "t", "v exists", "subjects.t.from", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}, "kid": {"from": "u.kids whose u.p plus q is 2"}}, "kid", "v exists", "subjects.kid.from", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", "every xs.v whose p plus q is 2 is 1", "checks.c", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", {"for": "every xs whose p plus q is 2 as x", "assert": "x.v is 1"}, "checks.c", "for: doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", "count of xs whose p plus q is 2 is 1", "checks.c", "doesn't parse"],
	] {
		[subjects, subject, check, at, problem] := case
		rows := [r | some r in ergo.report(inp, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": check}}}}, {}).results]
		[r.check | some r in rows] == ["$well_formed"]
		{"name": at, "value": [problem], "locations": []} in rows[0].inputs
	}
}

_located_rows(checks, doc, params) := [[r.subject.id, r.check, [{"name": i.name, "locations": object.get(i, "locations", null)} | some i in r.inputs]] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

test_each_input_of_a_subject_in_a_list_says_where_in_the_input_it_was_read if {
	_located_rows({"c": "x exists"}, {"things": [{"id": "t1", "x": 1}, {"id": "t2"}, {"id": "t3", "x": null}]}, {}) == [
		["t1", "c", [{"name": "x", "locations": ["/things/0/x"]}]],
		["t2", "c", [{"name": "x", "locations": ["/things/1"]}]],
		["t3", "c", [{"name": "x", "locations": ["/things/2/x"]}]],
	]
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

test_a_subject_that_is_not_an_object_has_its_own_location_for_every_input if {
	_located_rows({"c": "x.y exists"}, {"things": ["text", 3, null, [1]]}, {}) == [
		["text", "c", [{"name": "x.y", "locations": ["/things/0"]}]],
		[3, "c", [{"name": "x.y", "locations": ["/things/1"]}]],
		[null, "c", [{"name": "x.y", "locations": ["/things/2"]}]],
		[[1], "c", [{"name": "x.y", "locations": ["/things/3"]}]],
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

test_a_path_into_params_gives_its_location_after_the_params_prefix if {
	check := {"c": "n is at most $params.max_days.high"}
	doc := {"things": [{"id": "t1", "n": 3}]}
	_located_rows(check, doc, {"max_days": {"high": 4}}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:/max_days/high"]}]]]
	_located_rows(check, doc, {"max_days": {}}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:/max_days"]}]]]
	every params in [{}, null, "text", [1]] {
		_located_rows(check, doc, params) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:"]}]]]
	}
}

test_a_path_from_the_input_starts_at_the_root_of_the_input_whatever_the_subject if {
	_located_rows({"c": "n is at most $input.limits.high"}, {"limits": {"high": 9}, "things": [{"id": "t1", "n": 3}]}, {}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$input.limits.high", "locations": ["/limits/high"]}]]]
	_located_rows({"c": "n is at most $input.limits.high"}, {"limits": [1], "things": [{"id": "t1", "n": 3}]}, {}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$input.limits.high", "locations": ["/limits"]}]]]
}

test_a_ref_step_adds_the_key_it_read_and_stops_before_it_when_it_cannot_be_read if {
	check := {"c": ".a named by $params.i exists"}
	doc := {"things": [{"id": "t1", "a": [1, 2]}]}
	_located_rows(check, doc, {"i": 1}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a/1"]}]]]
	_located_rows(check, doc, {"i": 2}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a"]}]]]
	every i in [-1, 1.5, "1", null, [1]] {
		_located_rows(check, doc, {"i": i}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a"]}]]]
	}
	_located_rows(check, doc, {}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a"]}]]]
}

test_a_field_step_adds_the_key_the_field_holds_and_the_field_is_shown_with_its_own_location if {
	check := {"c": "values named by key exists"}
	doc := {"things": [{"id": "t1", "key": "k/1", "values": {"k/1": 5}}, {"id": "t2", "key": "zz", "values": {"k/1": 5}}, {"id": "t3", "values": {"k/1": 5}}, {"id": "t4", "key": 7, "values": {"7": 5}}]}
	_located_rows(check, doc, {}) == [
		["t1", "c", [{"name": "values named by key", "locations": ["/things/0/values/k~11"]}, {"name": "key", "locations": ["/things/0/key"]}]],
		["t2", "c", [{"name": "values named by key", "locations": ["/things/1/values"]}, {"name": "key", "locations": ["/things/1/key"]}]],
		["t3", "c", [{"name": "values named by key", "locations": ["/things/2/values"]}, {"name": "key", "locations": ["/things/2"]}]],
		["t4", "c", [{"name": "values named by key", "locations": ["/things/3/values"]}, {"name": "key", "locations": ["/things/3/key"]}]],
	]
}

test_a_subject_read_from_the_values_of_an_object_starts_at_its_escaped_key if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"scan": {"from": "scans named by each of $params.required"}}, "requirements": {"s": {"subject": "scan", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"scans": {"sast": {"x": 1}, "sca/x": {"x": 2}, "a~b": {}}}, policy, {"required": ["sast", "sca/x", "a~b", "secrets"]})
	[[r.subject.id, r.inputs[0].locations] | some r in rep.results; r.check == "c"] == [
		["a~b", ["/scans/a~0b"]],
		["sast", ["/scans/sast/x"]],
		["sca/x", ["/scans/sca~1x/x"]],
		["secrets", ["/scans"]],
	]
}

test_a_subject_read_with_every_starts_where_the_walk_found_it if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"item": {"from": "every groups.xs", "identified_by": "id"}}, "requirements": {"s": {"subject": "item", "checks": {"c": "id exists"}}}}
	rep := ergo.report({"groups": [{"xs": [{"id": "a"}]}, {"xs": [{"id": "b"}, {"id": "c"}]}]}, policy, {})
	[[r.subject.id, r.inputs[0].locations] | some r in rep.results; r.check == "c"] == [
		["a", ["/groups/0/xs/0/id"]],
		["b", ["/groups/1/xs/0/id"]],
		["c", ["/groups/1/xs/1/id"]],
	]
}

test_a_child_subject_starts_at_its_parent_and_a_grandchild_at_its_own_parent if {
	rep := _three_report(_three_doc, {"c": "artifact.fingerprint exists and \"pull request\".url exists and sha exists"})
	[[r.subject.id, r.subject.in, [{"name": i.name, "locations": i.locations} | some i in r.inputs]] | some r in rep.results; r.check == "c"; r.subject.in.artifact == "sha-4"] == [
		["c1", {"artifact": "sha-4", "pull request": "pr/7"}, [
			{"name": "\"pull request\".url", "locations": ["/artifacts/2/atts/pr/pull_requests/0/url"]},
			{"name": "artifact.fingerprint", "locations": ["/artifacts/2/fingerprint"]},
			{"name": "sha", "locations": ["/artifacts/2/atts/pr/pull_requests/0/commits/0/sha"]},
		]],
		["c1", {"artifact": "sha-4", "pull request": "pr/7"}, [
			{"name": "\"pull request\".url", "locations": ["/artifacts/2/atts/pr/pull_requests/0/url"]},
			{"name": "artifact.fingerprint", "locations": ["/artifacts/2/fingerprint"]},
			{"name": "sha", "locations": ["/artifacts/2/atts/pr/pull_requests/0/commits/1/sha"]},
		]],
	]
}

test_a_ref_in_refs_has_its_location_and_a_violation_copies_it if {
	rep := ergo.report({"things": [{"id": "t1", "x": "z"}]}, _sentence_policy({"c": "x is in $params.allowed"}), {"allowed": ["p", "q"]})
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.allowed", "value": ["p", "q"], "locations": ["$params:/allowed"]}]
	[v.inputs | some v in ergo.violations(rep)] == [[
		{"name": "x", "value": "z", "locations": ["/things/0/x"]},
		{"name": "$params.allowed", "value": ["p", "q"], "locations": ["$params:/allowed"]},
	]]
}

test_a_ref_that_is_not_a_path_in_the_input_or_the_params_has_no_location if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": {"assert": "x exists", "meta": {"ref": ["x"]}}}}}}
	rep := ergo.report({"things": [{"id": "t1", "x": "a"}]}, policy, {})
	rep.requirements.s.checks.c["$refs"] == [{"name": "<invalid ref>", "value": null, "locations": []}]
}

test_an_input_read_by_two_assertions_is_listed_once_with_its_location if {
	_located_rows({"c": {"assert": ["x exists", "x is 1", "y exists"]}}, {"things": [{"id": "t1", "x": 1, "y": 2}]}, {}) == [["t1", "c", [{"name": "x", "locations": ["/things/0/x"]}, {"name": "y", "locations": ["/things/0/y"]}]]]
}

test_an_applies_row_lists_an_input_read_by_two_conditions_once_with_its_location if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"thing": {"from": "things whose state is \"live\" and state is not \"old\"", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"things": [{"id": "t1", "state": "live", "x": 1}, {"id": "t2", "state": "old"}]}, policy, {})
	[[r.subject.id, r.inputs] | some r in rep.results; r.check == "$applies"] == [
		["t1", [{"name": "state", "value": "live", "locations": ["/things/0/state"]}]],
		["t2", [{"name": "state", "value": "old", "locations": ["/things/1/state"]}]],
	]
}

test_a_for_line_row_gives_the_location_of_each_item_and_of_the_item_that_failed if {
	rows := [r | some r in ergo.report({"things": [{"id": "t1", "prs": [{"a": 1}, {"a": 2}]}]}, _sentence_policy({"c": {"for": "every prs as pr", "assert": "pr.a is 1"}}), {}).results; r.check == "c"]
	count(rows) == 1
	rows[0].inputs == [{"name": "prs[]", "value": [{"a": 1}, {"a": 2}], "locations": ["/things/0/prs/0", "/things/0/prs/1"]}]
	rows[0].failed_items == [{
		"path": "item 2 of prs",
		"item": "item 2 of prs",
		"cause": "value",
		"value": {"a": 2},
		"locations": ["/things/0/prs/1"],
		"failed_assertions": [{"assertion": "pr.a is 1", "cause": "value", "inputs": [{"name": "pr.a", "value": 2, "locations": ["/things/0/prs/1/a"]}]}],
	}]
}

test_first_seen_keeps_the_first_of_each_location_in_the_order_they_came if {
	ergo._first_seen(["b", "a", "b", "c", "a"]) == ["b", "a", "c"]
	ergo._first_seen([]) == []
}

test_a_pointer_reads_into_a_list_a_name_holds_and_stops_where_the_read_stopped if {
	ergo._pointer("/x", [10, 20], [1]) == "/x/1"
	ergo._pointer("/x", [10], [3]) == "/x"
	ergo._pointer("/x", 5, ["a"]) == "/x"
	ergo._pointer("/x", 5, []) == "/x"
	ergo._pointer("", {"a": [{"b": 1}]}, ["a", 0, "c"]) == "/a/0"
}

test_a_read_that_starts_at_a_name_nothing_holds_has_no_location_and_never_leaves_the_report if {
	ergo._path_input({}, ["$nope", "a"]) == {"name": "$nope.a", "value": null, "locations": []}
	ergo._locations_of({}, ["$nope", "a"]) == []
	ergo._unread_at({}, {"path": ["$nope", "a"]}, {}) == {}
	ergo._fail_locations({"path": ["$nope", "a"]}) == []
}

test_a_walk_that_starts_at_a_name_with_no_location_still_walks_its_items if {
	start := ergo._walk_start({"path": ["$x", "a"]}, {}) with input as {"ergo/names": {"x": {"a": [1]}}}
	start.v == {"a": [1]}
	start.a == ""
}

test_a_number_worked_out_from_two_entries_lists_a_location_once_though_both_read_it if {
	elapsed := _elapsed_rows("days elapsed from t to t is 0", [{"id": 1, "t": 5}], {})
	elapsed[0][3][0].locations == ["/things/0/t"]
	counted := _tally_rows("count of xs plus count of xs is 4", [{"id": 1, "xs": [1, 2]}], {})
	counted[0][2][0].locations == ["/things/0/xs/0", "/things/0/xs/1"]
}

test_a_walk_has_a_location_for_each_item_whatever_it_starts_at if {
	doc := {"things": [{"id": 1, "a/b": [{"ok": true}, {"ok": true}]}], "xs": [{"ok": true}, {"ok": false}]}
	rows := _sentence_rows({"input": "every $input.xs.ok is true", "escaped": "every \"a/b\".ok is true", "params": "every $params.list.ok is true"}, doc, {"list": [{"ok": true}]})
	{r[0]: r[3][0].locations | some r in rows} == {
		"input": ["/xs/0/ok", "/xs/1/ok"],
		"escaped": ["/things/0/a~1b/0/ok", "/things/0/a~1b/1/ok"],
		"params": ["$params:/list/0/ok"],
	}
	failed := _walk_rows({"input": "every $input.xs.ok is true"}, doc, {})
	failed[0][3][0].locations == ["/xs/1/ok"]
}

test_a_walk_over_a_list_inside_a_list_a_for_name_holds_has_a_location_for_each_item if {
	rows := _for_rows({"for": "every xs as row, every row as cell", "assert": "cell is 1"}, [{"id": 1, "xs": [[1, 1], [1]]}], {})
	rows[0][3] == [{"name": "row[]", "value": [1, 1, 1], "locations": ["/things/0/xs/0/0", "/things/0/xs/0/1", "/things/0/xs/1/0"]}, {"name": "xs[]", "value": [[1, 1], [1]], "locations": ["/things/0/xs/0", "/things/0/xs/1"]}]
}

test_a_failed_item_of_a_nested_for_line_points_at_the_value_it_read if {
	check := {"for": "every prs.meta as m, every m.commits as c", "assert": "c.signed is true"}
	rows := _for_rows(check, [{"id": 1, "prs": [{"meta": {"commits": "zz"}, "commits": [{"signed": true}]}]}], {})
	rows[0][2][0].locations == ["/things/0/prs/0/meta"]
	rows[0][2][0].failed_items[0].locations == ["/things/0/prs/0/meta/commits"]
	absent := _for_rows(check, [{"id": 1, "prs": [{"meta": {"n": 1}, "commits": [{"signed": true}]}, {"meta": {"commits": []}}]}], {})
	absent[0][2][0].locations == ["/things/0/prs/0/meta"]
	absent[0][2][0].failed_items[0].locations == ["/things/0/prs/0/meta"]
}

test_a_failed_item_points_at_where_its_value_was_read_not_at_the_item if {
	rows := _for_rows({"for": "first of owners sorted by name as o", "assert": "o.ok is true"}, [{"id": 1, "owners": [{"name": "Zoe", "ok": true}, {"name": "Zoe", "ok": false}]}], {})
	[[f.value, f.locations] | some f in rows[0][2]] == [["Zoe", ["/things/0/owners/0/name"]], ["Zoe", ["/things/0/owners/1/name"]]]
	titles := _walk_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "prs": [{"title": "x"}, {"title": "y"}]}]}, {})
	titles[0][3] == [{"path": "prs[1].title", "item": "item 2 of prs", "cause": "value", "value": "y", "locations": ["/things/0/prs/1/title"]}]
	whole := _walk_rows({"c": "every prs is 1"}, {"things": [{"id": 1, "prs": [1, 2]}]}, {})
	whole[0][3][0].locations == ["/things/0/prs/1"]
}

test_a_walk_on_a_missing_list_has_no_values_and_its_failed_item_says_where_it_stopped if {
	rows := _walk_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "x": {}}]}, {})
	rows[0][3] == [{"path": "prs", "item": "prs", "cause": "absent", "value": null, "locations": ["/things/0"]}]
	inputs := _sentence_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "x": {}}]}, {})
	inputs[0][3] == [{"name": "prs.title", "value": [], "locations": []}]
}

test_reads_with_the_same_name_and_value_merge_only_when_their_locations_match if {
	policy := {"ergo_spec": "v0.3-dev", "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids", "identified_by": "id"}}, "requirements": {"s": {"subject": "kid", "checks": {"c": "b.x is 1 and .b.x is 1", "d": "b.x is 1 and b.x is 1"}}}}
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 1}}]}]}, policy, {})
	rows_for(rep, "s", "c")[0].inputs == [
		{"name": "b.x", "value": 1, "locations": ["/bs/0/kids/0/b/x"]},
		{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]},
	]
	rows_for(rep, "s", "d")[0].inputs == [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}]
}

test_unique_ids_locates_the_ids_of_a_child_subject_where_they_are_in_the_input if {
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "pull_requests": [{"url": "pr/7"}, {"url": "pr/8"}, {"url": "pr/7"}]}}}}
	rep := _chain_report(doc, _chain_subjects, {"c": "url exists"}, {"name": "web"})
	rows_for(rep, "r", "$unique_ids")[0].inputs == [{"name": "repeated pull request ids", "value": ["pr/7"], "locations": ["/trail/artifacts/web/pull_requests/0/url", "/trail/artifacts/web/pull_requests/2/url"]}]
}

test_the_applies_row_of_a_some_or_every_condition_gives_one_location_per_item_and_stops_where_the_read_stopped if {
	doc := {"releases": [
		{"id": 1, "files": [{"path": "docs/a"}, {"path": "src/b"}]},
		{"id": 2, "files": [{"path": "docs/a"}, {"name": "x"}]},
		{"id": 3},
		{"id": 4, "files": []},
	]}
	every_rep := _from_report(doc, {"release": {"from": `releases whose every files.path, if any, matches "^docs/"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.inputs | some r in every_rep.results; r.check == "$applies"} == {
		1: [{"name": "files[].path", "value": ["docs/a", "src/b"], "locations": ["/releases/0/files/0/path", "/releases/0/files/1/path"]}],
		2: [{"name": "files[].path", "value": ["docs/a", null], "locations": ["/releases/1/files/0/path", "/releases/1/files/1"]}],
		3: [{"name": "files.path", "value": [], "locations": []}],
		4: [{"name": "files[].path", "value": [], "locations": []}],
	}
	some_rep := _from_report(doc, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.inputs | some r in some_rep.results; r.check == "$applies"} == {
		1: [{"name": "files[].path", "value": ["docs/a", "src/b"], "locations": ["/releases/0/files/0/path", "/releases/0/files/1/path"]}],
		2: [{"name": "files[].path", "value": ["docs/a", null], "locations": ["/releases/1/files/0/path", "/releases/1/files/1"]}],
		3: [{"name": "files.path", "value": [], "locations": []}],
		4: [{"name": "files[].path", "value": [], "locations": []}],
	}
}

_it_policy(from, checks) := {
	"ergo_spec": "v0.3-dev",
	"subjects": {"s": {"from": from}},
	"requirements": {"r": {"subject": "s", "checks": checks}},
}

_it_report(doc, from, checks, params) := ergo.report(doc, _it_policy(from, checks), params)

_it_rows(doc, from, check, params) := [[r.subject.id, r.passed, r.cause, r.inputs] | some r in _it_report(doc, from, {"c": check}, params).results; r.check == "c"]

_it_problems(from, checks) := [i.value | some i in _it_report({"xs": []}, from, checks, {}).results[0].inputs; i.name == _it_problem_name(from)][0]

_it_problem_name(from) := "subjects.s.from" if from != "every xs"

_it_problem_name("every xs") := "checks.c"

test_it_is_the_subject_itself_when_the_subject_is_a_string if {
	_it_rows(
		{"deployment": {"id": "d-17", "regions": ["eu-west-1", "us-east-1"]}},
		"every deployment.regions",
		"it is one of $params.allowed_regions",
		{"allowed_regions": ["eu-west-1"]},
	) == [
		["eu-west-1", true, "satisfied", [{"name": "it", "value": "eu-west-1", "locations": ["/deployment/regions/0"]}]],
		["us-east-1", false, "value", [{"name": "it", "value": "us-east-1", "locations": ["/deployment/regions/1"]}]],
	]
	rep := _it_report({"deployment": {"regions": ["eu-west-1"]}}, "every deployment.regions", {"c": "it is one of $params.allowed_regions"}, {"allowed_regions": ["eu-west-1"]})
	rep.requirements.r.checks.c.expression == "it is in $params.allowed_regions"
}

_it_phrases := [
	"is an object", "is a string", "is a list", "is a number", "exists", "does not exist", "is empty", "is not empty",
	"is a non-empty string", "is at least 2", "is not 1", "is one of 1, 2", "is one of $params.l", "equals $params.n",
	"contains 'a'", "contains all of 1, 2", "matches 'a'", "starts with 'a'", "is before '2020-01-01T00:00:00Z'",
	"is between 1 and 3", "is alphabetically before 'b'",
]

_it_values := [null, "a", 1, "", [], {}, [1, 2], {"k": 1}, true, "2019-01-01T00:00:00Z"]

_it_by_value(rows) := {json.marshal(r[3][0].value): [r[1], r[2]] | some r in rows}

test_it_fails_like_a_field_that_holds_the_same_value if {
	every phrase in _it_phrases {
		params := {"l": [1], "n": 1}
		got := _it_by_value(_it_rows({"xs": _it_values}, "every xs", concat(" ", ["it", phrase]), params))
		want := _it_by_value(_it_rows({"xs": [{"id": i, "x": v} | some i, v in _it_values]}, "every xs", concat(" ", ["x", phrase]), params))
		count(got) == count(_it_values)
		got == want
	}
}

test_it_is_an_object_passes_for_an_object_and_fails_for_anything_else if {
	_it_by_value(_it_rows({"xs": [{"a": 1}, "s", null, 3, [1]]}, "every xs", "it is an object", {})) == {
		`{"a":1}`: [true, "satisfied"],
		`"s"`: [false, "value"],
		"null": [false, "null"],
		"3": [false, "value"],
		"[1]": [false, "value"],
	}
}

test_it_on_a_null_subject_fails_as_null_and_on_the_wrong_type_as_value_or_unusable if {
	rows := _it_by_value(_it_rows({"xs": [null, "a", 3]}, "every xs", "it is at least 2", {}))
	rows == {"null": [false, "null"], `"a"`: [false, "unusable"], "3": [true, "satisfied"]}
	_it_by_value(_it_rows({"xs": [null, "a", 3]}, "every xs", "it is a string", {})) == {"null": [false, "null"], `"a"`: [true, "satisfied"], "3": [false, "value"]}
}

test_it_walks_and_counts_a_subject_that_is_a_list if {
	doc := {"xs": [["a", "b"], [1, 2], [1, "a"], [], null, "s"]}
	rows := _it_rows(doc, "every xs", "every it is a string", {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "value"], [false, "value"], [false, "value"], [false, "null"], [false, "unusable"]]
	rows[1][3] == [{"name": "it[]", "value": [1, 2], "locations": ["/xs/1/0", "/xs/1/1"]}]
	_it_report(doc, "every xs", {"c": "every it is a string"}, {}).results[4].failed_items == [
		{"cause": "value", "item": "item 1 of it", "path": "item 1 of it", "value": 1, "locations": ["/xs/1/0"]},
		{"cause": "value", "item": "item 2 of it", "path": "item 2 of it", "value": 2, "locations": ["/xs/1/1"]},
	]
	[[r[1], r[2]] | some r in _it_rows(doc, "every xs", "some it is a string", {})] == [[true, "satisfied"], [false, "value"], [true, "satisfied"], [false, "value"], [false, "null"], [false, "unusable"]]
	counts := _it_rows(doc, "every xs", "count of it is 2", {})
	[[r[1], r[2]] | some r in counts] == [[true, "satisfied"], [true, "satisfied"], [true, "satisfied"], [false, "value"], [false, "null"], [false, "unusable"]]
	counts[1][3] == [{"name": "count of it", "value": 2, "locations": ["/xs/1/0", "/xs/1/1"]}, {"name": "it[]", "value": [1, 2], "locations": ["/xs/1/0", "/xs/1/1"]}]
	sums := _it_rows(doc, "every xs", "sum of it is 3", {})
	[[r[1], r[2]] | some r in sums] == [[false, "unusable"], [true, "satisfied"], [false, "unusable"], [false, "value"], [false, "null"], [false, "unusable"]]
}

test_it_in_an_every_names_an_empty_list_and_a_missing_one_it if {
	rows := _it_rows({"xs": [[], null]}, "every xs", "every it is a string", {})
	rows[1][3] == [{"name": "it", "value": [], "locations": []}]
	rep := _it_report({"xs": [[]]}, "every xs", {"c": "every it is a string"}, {})
	[r.failed_items | some r in rep.results; r.check == "c"] == [[{"cause": "value", "item": "it", "path": "it", "value": [], "locations": ["/xs/0"]}]]
}

test_a_field_called_it_is_written_with_a_dot_and_printed_with_one if {
	doc := {"xs": [{"id": "a", "it": 1}, {"id": "b", "it": 2}]}
	_it_rows(doc, "every xs", ".it is 1", {}) == [
		[{"id": "a", "it": 1}, true, "satisfied", [{"name": ".it", "value": 1, "locations": ["/xs/0/it"]}]],
		[{"id": "b", "it": 2}, false, "value", [{"name": ".it", "value": 2, "locations": ["/xs/1/it"]}]],
	]
	_it_report(doc, "every xs", {"c": "\"it\" is 1"}, {}).requirements.r.checks.c.expression == ".it is 1"
	[r[1] | some r in _it_rows(doc, "every xs", "it is an object", {})] == [true, true]
	_it_rows({"xs": [{"id": "a", "x": {"it": 1}}]}, "every xs", "x.it is 1", {}) == [[{"id": "a", "x": {"it": 1}}, true, "satisfied", [{"name": "x.it", "value": 1, "locations": ["/xs/0/x/it"]}]]]
	rep := _it_report(doc, "every xs", {"c": ".it is 1 and it is an object"}, {})
	rep.requirements.r.checks.c.expression == ".it is 1 and it is an object"
}

test_it_is_a_word_of_the_grammar_so_a_bare_it_never_reads_a_field if {
	"it" in ergo._s_words
	_it_rows({"xs": [{"id": "a", "it": 1}]}, "every xs", "it is 1", {}) == [[{"id": "a", "it": 1}, false, "unusable", [{"name": "it", "value": {"id": "a", "it": 1}, "locations": ["/xs/0"]}]]]
}

test_it_works_after_and_and_in_an_any_of_option_and_names_the_subject if {
	rows := _it_rows({"xs": [1, 2]}, "every xs", "it is 1 and it is a number", {})
	[[r[0], r[1], r[2]] | some r in rows] == [[1, true, "satisfied"], [2, false, "value"]]
	_it_report({"xs": [1, 2]}, "every xs", {"c": "it is 1 and it is a number"}, {}).results[4].failed_assertions == [{"assertion": "it is 1", "cause": "value"}]
	options := _it_rows({"xs": [1, "a", null]}, "every xs", {"any_of": {"num": "it is a number", "str": ["it is a string", "it is 'a'"]}}, {})
	[[r[0], r[1], r[2]] | some r in options] == [[1, true, "satisfied"], ["a", true, "satisfied"], [null, false, "null"]]
	_it_report({"xs": [1]}, "every xs", {"c": {"any_of": {"num": "it is a number", "str": "it is a string"}}}, {}).requirements.r.checks.c.expression == "one of: num(it is a number) | str(it is a string)"
}

test_it_after_a_for_line_is_still_the_subject_and_not_the_item if {
	doc := {"xs": [{"id": "a", "l": [1, 2]}]}
	rows := _it_rows(doc, "every xs", {"for": "every l as e", "assert": ["it is an object", "e is 1"]}, {})
	rows[0][1] == false
	rows[0][3][0] == {"name": "it", "value": {"id": "a", "l": [1, 2]}, "locations": ["/xs/0"]}
	_it_report(doc, "every xs", {"c": {"for": "every l as e", "assert": ["it is an object", "e is 1"]}}, {}).requirements.r.checks.c.expression == "for every l as e: it is an object and e is 1"
}

test_it_in_a_from_line_whose_reads_each_item_and_names_it_in_the_applies_row if {
	rep := _it_report({"ws": ["a", "bb", null, 3, "cc"]}, "every ws whose it is a string and it starts with 'b'", {"c": "it is a string"}, {})
	applies := [[r.subject.id, r.passed, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"]
	applies == [
		["a", false, "value", [{"name": "it", "value": "a", "locations": ["/ws/0"]}]],
		["bb", true, "satisfied", [{"name": "it", "value": "bb", "locations": ["/ws/1"]}]],
		[null, false, "null", [{"name": "it", "value": null, "locations": ["/ws/2"]}]],
		[3, false, "unusable", [{"name": "it", "value": 3, "locations": ["/ws/3"]}]],
		["cc", false, "value", [{"name": "it", "value": "cc", "locations": ["/ws/4"]}]],
	]
	[r.subject.id | some r in rep.results; r.check == "c"] == ["bb"]
	counted := _it_report({"xs": [[1], [1, 2], []]}, "every xs whose count of it is at least 2", {"c": "it is a list"}, {})
	[r.subject.id | some r in counted.results; r.check == "c"] == [[1, 2]]
}

test_two_equal_plain_values_fail_unique_ids_and_are_still_checked_with_it if {
	rep := _it_report({"xs": ["a", "a", "b"]}, "every xs", {"c": "it is a string"}, {})
	uniq := [r | some r in rep.results; r.check == "$unique_ids"]
	uniq[0].passed == false
	uniq[0].inputs == [{"name": "repeated s ids", "value": ["a"], "locations": ["/xs/0", "/xs/1"]}]
	[[r.subject.id, r.passed] | some r in rep.results; r.check == "c"] == [["a", true], ["a", true], ["b", true]]
	rep.compliant == false
}

test_it_followed_by_a_step_is_written_wrong_and_says_to_write_the_field_alone if {
	_it_problems("every xs", {"c": "it.name is 1"}) == ["it is the whole subject: write name, not it.name"]
	_it_problems("every xs", {"c": `it."x y" is 1`}) == [`it is the whole subject: write "x y", not it."x y"`]
	_it_problems("every xs", {"c": "every it.name is 1"}) == ["it is the whole subject: write name, not it.name"]
	every text in ["it[0] is 1", "it[0].k is 1", "it named by $params.k is 1", "first of it[0] is 1", "count of it[1] is 1"] {
		_it_problems("every xs", {"c": text}) == ["it is the whole subject: nothing can follow it"]
	}
}

test_it_on_the_right_side_or_anywhere_but_the_start_of_an_assertion_is_written_wrong if {
	every text in [
		"$params.p equals it", "x is it", "x is one of it", "x contains it", "it is it", "x is 1 plus it", "count of x is count of it",
		"it plus 1 is 2", "it is 1 and x is it", "every xs whose it is 1 is 2", "every xs whose x is it is 2", "count of xs whose it is 1 is 2",
		"every it whose it is 1 is 2", "sum of x is sum of it",
	] {
		_it_problems("every xs", {"c": text}) == ["it can only start an assertion: write it first, like it is not empty"]
	}
	every line in [
		{"for": "every it as e", "assert": "e is 1"},
		{"for": "every xs whose it is 1 as e", "assert": "e is 1"},
		{"for": "every xs whose x is it as e", "assert": "e is 1"},
		{"for": "last of xs sorted by it as e", "assert": "e is 1"},
		{"for": "every xs as e, every it as f", "assert": "e is f"},
	] {
		_it_problems("every xs", {"c": line}) == ["for: it can only start an assertion: write it first, like it is not empty"]
	}
	_it_problems("every it", {"c": "x exists"}) == ["it can only start an assertion: write it first, like it is not empty"]
	_it_problems("every it whose x is 1", {"c": "x exists"}) == ["it can only start an assertion: write it first, like it is not empty"]
	_it_problems("xs whose x is it", {"c": "x exists"}) == ["it can only start an assertion: write it first, like it is not empty"]
}

test_it_cannot_name_a_key_or_be_an_alias if {
	_it_problems("every xs", {"c": "$params.m named by it is 1"}) == ["it can't name a key"]
	_it_problems("every xs", {"c": "x named by it is 1"}) == ["it can't name a key"]
	_it_problems("every xs", {"c": {"for": "every xs as it", "assert": "it is 1"}}) == ["for: it can't be an alias"]
}

test_a_written_wrong_it_stops_the_requirement_with_only_its_well_formed_row if {
	rep := _it_report({"xs": [1]}, "every xs", {"c": "it.name is 1"}, {})
	stopped(rep)
}

test_it_cannot_be_a_part_path_or_an_identified_by if {
	rep := ergo.report({"xs": [1]}, {"ergo_spec": "v0.3-dev", "subjects": {"s": {"from": "every xs", "has": {"p": "it"}}}, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}, {})
	stopped(rep)
	rep2 := ergo.report({"xs": [1]}, {"ergo_spec": "v0.3-dev", "subjects": {"s": {"from": "every xs", "identified_by": "it"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}, {})
	stopped(rep2)
}

_it_named(subjects, subject) := [i | some r in ergo.report({"xs": [1]}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": subject, "checks": {"c": "x exists"}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

test_a_subject_called_it_is_written_wrong_for_the_requirement_that_uses_it if {
	_it_named({"it": {"from": "xs"}}, "it") == [{"name": "subjects.it", "value": ["it is a word of the grammar, so a subject can't be called it"], "locations": []}]
	_it_named({"it": {"from": "xs"}, "b": {"from": "it"}}, "b") != []
}

test_only_the_exact_name_it_is_refused_as_a_subject_name if {
	every name in ["It", "items", "it x", "it_"] {
		_it_named({name: {"from": "xs"}}, name) == []
	}
	_it_named({"it": {"from": "xs"}, "b": {"from": "xs"}}, "b") == []
}

_it_position_sentences := [
	"first of X is 1", "item 2 of X is 'x'", "first of X exists",
	"first of X does not exist", "first of X is not empty", "first of X is a string", "first of X is one of 1, 2",
	"every first of X is 1", "some item 2 of X is 1", "count of first of X is 1", "sum of item 2 of X is 3",
	"every X is a string", "some X is a string", "count of X is 2", "sum of X is 3", "X is a list",
]

_it_position_values := [[1, "x"], [], "s", null, [["a"], "b"], {"k": 1}, {}, 3, true]

_it_shape(rows) := json.marshal([[r.passed, r.cause, _unlocated(r.inputs), _unlocated(object.get(r, "failed_items", null))] | some r in rows])

_unlocated(entries) := [{k: v | some k, v in e; k != "locations"} | some e in entries] if entries != null

_unlocated(null) := null

_it_field_shape(rows) := replace(replace(replace(replace(_it_shape(rows), `"v[`, `"it[`), `"v"`, `"it"`), ` of v"`, ` of it"`), ` of v[`, ` of it[`)

_it_rows_of(doc, from, text) := [r | some r in _it_report(doc, from, {"c": text}, {}).results; r.check == "c"]

test_a_position_on_it_reads_and_names_like_the_same_position_on_a_field if {
	every text in _it_position_sentences {
		on_it := _it_rows_of({"xs": _it_position_values}, "every xs", replace(text, "X", "it"))
		on_field := _it_rows_of({"xs": [{"id": i, "v": v} | some i, v in _it_position_values]}, "every xs", replace(text, "X", "v"))
		count(on_it) == count(_it_position_values)
		_it_shape(on_it) == _it_field_shape(on_field)
	}
}

test_a_position_on_it_names_the_item_the_way_a_field_does if {
	rows := _it_rows({"xs": [["a", "b"]]}, "every xs", "first of it is 'a'", {})
	rows == [[["a", "b"], true, "satisfied", [{"name": "item 1 of it", "value": "a", "locations": ["/xs/0/0"]}]]]
	_it_rows({"xs": [[]]}, "every xs", "first of it is 'a'", {})[0][2] == "absent"
	_it_rows({"xs": ["s"]}, "every xs", "first of it is 'a'", {})[0][2] == "unusable"
	_it_report({"xs": [["a"]]}, "every xs", {"c": "item 2 of it is 'a'"}, {}).requirements.r.checks.c.expression == "item 2 of it is \"a\""
	_it_problems("every xs", {"c": "first of it.k is 1"}) == ["it is the whole subject: write k, not it.k"]
}

test_a_position_on_it_is_written_wrong_where_it_cannot_start_an_assertion if {
	_it_problems("every xs", {"c": "x is first of it"}) == ["it can only start an assertion: write it first, like it is not empty"]
	_it_problems("every xs", {"c": {"for": "last of it as e", "assert": "e is 1"}}) == ["for: it can only start an assertion: write it first, like it is not empty"]
}

test_a_walk_from_a_for_alias_that_is_null_fails_as_null_like_a_field_that_is_null if {
	_it_rows({"xs": [null]}, "every xs", "every first of it is 1", {})[0][2] == "null"
	rep := _it_report({"xs": [{"id": 1, "names": [null], "n": null}]}, "every xs", {"c": {"for": "every names as n", "assert": "every n.ys is 1"}, "d": "every .n.ys is 1"}, {})
	[r.cause | some r in rep.results; r.check in {"c", "d"}] == ["null", "null"]
}

test_a_position_on_a_for_alias_holding_a_list_reads_it_as_it_does_on_a_field if {
	rep := _it_report({"xs": [{"id": 1, "bs": [["x", "y"], [], "s"]}]}, "every xs", {"c": {"for": "every bs as b", "assert": "first of b is \"x\""}}, {})
	[[f.item, f.cause] | some r in rep.results; r.check == "c"; some f in r.failed_items] == [["item 2 of bs", "absent"], ["item 3 of bs", "unusable"]]
}

test_as_sentences_writes_an_empty_path_as_it_and_a_field_called_it_with_a_dot if {
	ergo.as_sentences({"requirements": {"r": {"checks": {"c": {"op": "equals", "path": [], "value": "x"}}}}}).requirements.r.checks.c == `it is "x"`
	ergo.as_sentences({"requirements": {"r": {"checks": {"c": {"op": "in", "path": [], "values": ["a"]}}}}}).requirements.r.checks.c == `it is one of "a"`
	ergo.as_sentences({"requirements": {"r": {"checks": {"c": {"op": "equals", "path": ["it"], "value": 1}}}}}).requirements.r.checks.c == ".it is 1"
}

test_it_in_a_plus_term_is_allowed_on_the_left_side_and_written_wrong_on_the_right if {
	_it_rows({"xs": [[1, 2]]}, "every xs", "count of it plus 1 is 3", {})[0][1] == true
	_it_rows({"xs": [[1, 2]]}, "every xs", "count of it plus count of $params.ys is 3", {"ys": [0]})[0][1] == true
	_it_problems("every xs", {"c": "count of xs is 1 plus count of it"}) == ["it can only start an assertion: write it first, like it is not empty"]
}

test_it_after_some_or_every_in_a_from_line_whose_reads_the_subject_as_the_same_check_does if {
	rows := [[r.subject.id, r.cause] | some r in _it_report({"xs": [[1, 2], [1], [], "s"]}, "every xs whose some it is 1", {"c": "it is not empty"}, {}).results; r.check == "$applies"]
	rows == [[[1, 2], "satisfied"], [[1], "satisfied"], [[], "value"], ["s", "unusable"]]
	[[r.subject.id, r.cause] | some r in _it_report({"xs": [[1, 2], [1]]}, "every xs whose every it is 1", {"c": "it is not empty"}, {}).results; r.check == "$applies"] == [[[1, 2], "value"], [[1], "satisfied"]]
	_it_problems("every xs whose some it is it", {"c": "it is not empty"}) == ["it can only start an assertion: write it first, like it is not empty"]
}

test_it_reads_the_location_of_the_subject_itself_and_of_each_item_of_a_list_subject if {
	doc := {"values": [1], "lists": [[1, 2]], "sets": [[3]]}
	plain := _it_report(doc, "every values", {"c": "it is 1"}, {})
	[r.inputs | some r in plain.results; r.check == "c"] == [[{"name": "it", "value": 1, "locations": ["/values/0"]}]]
	list := _it_report(doc, "every lists", {"c": "every it is 1 and count of it is 2"}, {})
	[r.inputs | some r in list.results; r.check == "c"] == [[
		{"name": "count of it", "value": 2, "locations": ["/lists/0/0", "/lists/0/1"]},
		{"name": "it[]", "value": [1, 2], "locations": ["/lists/0/0", "/lists/0/1"]},
	]]
	kept := _it_report(doc, "every sets whose some it is 1", {"c": "it is not empty"}, {})
	[[r.inputs, r.failed_items] | some r in kept.results; r.check == "$applies"] == [[
		[{"name": "it[]", "value": [3], "locations": ["/sets/0/0"]}],
		[{"cause": "value", "item": "item 1 of it", "path": "item 1 of it", "value": 3, "locations": ["/sets/0/0"]}],
	]]
}

test_an_applies_row_with_some_it_names_its_failed_items_as_the_check_row_does if {
	applies := [[r.subject.id, r.cause, r.failed_items] | some r in _it_report({"xs": [[1, 2], [3], [], "s"]}, "every xs whose some it is 1", {"c": "it is not empty"}, {}).results; r.check == "$applies"]
	check := [[r.subject.id, r.cause, r.failed_items] | some r in _it_report({"xs": [[1, 2], [3], [], "s"]}, "every xs", {"c": "some it is 1"}, {}).results; r.check == "c"]
	applies == check
	applies[1] == [[3], "value", [{"cause": "value", "item": "item 1 of it", "path": "item 1 of it", "value": 3, "locations": ["/xs/1/0"]}]]
	applies[2] == [[], "value", [{"cause": "value", "item": "it", "path": "it", "value": [], "locations": ["/xs/2"]}]]
	applies[3] == ["s", "unusable", [{"cause": "unusable", "item": "it", "path": "it", "value": "s", "locations": ["/xs/3"]}]]
}

test_a_row_shows_an_input_once_when_the_check_reads_it_twice if {
	rep := ergo.report({"deployments": [{"id": "d1", "approvals": ["a", "b"]}]}, {"ergo_spec": "v0.3-dev", "subjects": {"deployment": {"from": "deployments", "identified_by": "id"}}, "requirements": {"r": {"subject": "deployment", "checks": {"c": "count of approvals plus count of approvals is 4"}}}}, {})
	[[[i.name, i.value, i.locations] | some i in r.inputs] | some r in rep.results; r.check == "c"] == [[
		["count of approvals plus count of approvals", 4, ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
		["count of approvals", 2, ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
		["approvals[]", ["a", "b"], ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]],
	]]
}

test_a_second_item_that_starts_at_a_parent_is_named_with_the_whole_parent_name if {
	doc := {"artifacts": [{"name": "x", "map": {"k1": [1], "k2": []}, "prs": [{"id": 1, "keys": ["k1", "k2"], "approvers": [{"n": 1}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	checks := {
		"c": {"for": "every keys as k, every artifact.map named by k as x", "assert": "x is not empty"},
		"e": {"for": "every artifact.prs as p, every p.approvers as person", "assert": "person.n is at least 1"},
	}
	rows := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[i.name | some r in rows; r.check == "c"; some i in r.inputs] == ["artifact.map named by k[]", "keys[]"]
	[i.name | some r in rows; r.check == "e"; some i in r.inputs] == ["artifact.prs[]", "p.approvers[]"]
}

_named_read_cause(nums, keys, assertion) := [r.cause | some r in ergo.report(doc, policy, {}).results; r.check == "c"][0] if {
	prs := [{"id": 1, "keys": keys, "rows": [{"n": 1, "p": 7}, {"n": 2, "p": 8}]}]
	doc := {"artifacts": [object.union({"name": "x", "prs": prs}, {"nums": nums})]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	policy := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": "every keys as k", "assert": assertion}}}}}
}

_named_read_walks := [
	"some rows.n is at least artifact.nums named by k",
	"some rows.p whose n is artifact.nums named by k is 7",
	"count of rows whose n is artifact.nums named by k is at least 1",
]

test_a_walk_reads_a_parent_through_a_for_alias_on_its_right_side if {
	every assertion in _named_read_walks {
		_named_read_cause({"k1": 1}, ["k1"], assertion) == "satisfied"
		_named_read_cause({"k1": 5}, ["k1"], assertion) == "value"
	}
	_named_read_cause({"k1": 1, "k2": 5}, ["k1"], _named_read_walks[1]) == "satisfied"
}

test_a_walk_through_a_for_alias_fails_like_a_count_when_the_key_is_missing_or_the_parent_is_not_an_object if {
	every assertion in _named_read_walks {
		_named_read_cause({"k2": 1}, ["k1"], assertion) == "absent"
		_named_read_cause(null, ["k1"], assertion) == "absent"
		_named_read_cause("abc", ["k1"], assertion) == "unusable"
		_named_read_cause(5, ["k1"], assertion) == "unusable"
	}
}

test_a_walk_through_a_for_alias_fails_like_a_count_when_the_alias_is_null_or_a_number_or_the_value_has_the_wrong_type if {
	every assertion in _named_read_walks {
		_named_read_cause({"k1": 1}, [null], assertion) == "null"
		_named_read_cause({"k1": 1}, [3], assertion) == "unusable"
		_named_read_cause({"k1": "a"}, ["k1"], assertion) == "unusable"
		_named_read_cause({"k1": null}, ["k1"], assertion) == "null"
	}
}

test_a_walk_keyed_by_an_item_field_lists_the_part_before_the_name_and_never_the_keyed_value if {
	nums := {"a": 1, "b": 2}
	rows := [{"key": "a", "n": 1}, {"key": "b", "n": 2}]
	doc := {"artifacts": [{"name": "x", "nums": nums, "prs": [{"id": 1, "keys": ["k1"], "rows": rows, "groups": [{"items": rows}]}]}]}
	artifact_nums := {"name": "artifact.nums", "value": nums, "locations": ["/artifacts/0/nums"]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	policy := {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {
		"plain": "some rows.n is at least artifact.nums named by key",
		"whose": "some rows.n whose n is artifact.nums named by key is at least 1",
		"for": {"for": "every keys as k", "assert": "some rows.n is at least artifact.nums named by key"},
		"alias": {"for": "every groups as g", "assert": "some g.items.n is at least artifact.nums named by key"},
	}}}}
	results := ergo.report(doc, policy, {}).results
	every check in {"plain", "whose", "for", "alias"} {
		inputs := [i | some r in results; r.check == check; some i in r.inputs]
		artifact_nums in inputs
		count([i | some i in inputs; contains(i.name, "named by")]) == 0
	}
	subjects_applies := object.union(subjects, {"pr": {"from": "artifact.prs whose some rows.n is at least artifact.nums named by key", "identified_by": "id"}})
	applies := ergo.report(doc, object.union(policy, {"subjects": subjects_applies}), {}).results
	applies_inputs := [i | some r in applies; r.check == "$applies"; some i in r.inputs]
	artifact_nums in applies_inputs
	count([i | some i in applies_inputs; contains(i.name, "named by")]) == 0
}

test_a_walk_through_a_for_name_whose_part_before_the_name_walks_a_list_lists_nothing_of_it if {
	doc := {"artifacts": [{"name": "x", "ls": [{"m": {"a": 1}}, {"m": {"a": 2}}], "prs": [{"id": 1, "keys": ["a"]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	checks := {"c": {"for": "every keys as k", "assert": "every artifact.ls.m named by k is at least 1"}}
	rows := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[[i.name | some i in r.inputs] | some r in rows; r.check == "c"] == [["keys[]"]]
}

test_a_sum_through_a_for_name_lists_the_part_before_the_name_and_not_the_sum_or_a_list_per_item if {
	things := [{"id": 1, "ks": ["a", "b"], "m": {"a": [1], "b": [2]}}]
	_for_rows({"for": "every ks as k", "assert": "sum of m named by k is at least 1"}, things, {})[0][3] == [
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/things/0/ks/0", "/things/0/ks/1"]},
		{"name": "m", "value": {"a": [1], "b": [2]}, "locations": ["/things/0/m"]},
	]
}

test_a_second_item_that_starts_at_input_or_params_keeps_its_dollar_in_the_list_and_failed_item_names if {
	doc := {"artifacts": [{"name": "a1", "pull_requests": [{"id": 1, "keys": ["k1"]}]}], "top": [11]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.pull_requests", "identified_by": "id"}}
	checks := {
		"i": {"for": "every keys as k, every $input.top as x", "assert": "x is at least 100"},
		"p": {"for": "every keys as k, some $params.l as x", "assert": "x is at least 100"},
	}
	rows := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {"l": [12]}).results
	[i.name | some r in rows; r.check == "i"; some i in r.inputs] == ["$input.top[]", "keys[]"]
	[i.name | some r in rows; r.check == "p"; some i in r.inputs] == ["$params.l[]", "keys[]"]
	[f.item | some r in rows; r.check == "i"; some o in r.failed_items; some a in o.failed_assertions; some f in a.items] == ["item 1 of $input.top"]
}

_keyed_tally_rows(nums, rows, checks) := {r.check: [r.cause, [i.name | some i in r.inputs]] |
	doc := {"artifacts": [{"name": "x", "nums": nums, "prs": [{"id": 1, "keys": ["k1"], "rows": rows}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	some r in ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	r.check in object.keys(checks)
}

_keyed_tallies := {
	"count": "count of rows whose n is at least artifact.nums named by key is at least 1",
	"sum": "sum of rows.n whose n is at least artifact.nums named by key is at least 1",
	"for_count": {"for": "every keys as k", "assert": "count of rows whose n is at least artifact.nums named by key is at least 1"},
	"for_sum": {"for": "every keys as k", "assert": "sum of rows.n whose n is at least artifact.nums named by key is at least 1"},
}

test_a_count_or_sum_keyed_by_an_item_field_lists_the_part_before_the_name_and_never_the_keyed_value if {
	got := _keyed_tally_rows({"a": 1, "b": 2}, [{"key": "a", "n": 1}, {"key": "b", "n": 2}], _keyed_tallies)
	every _, r in got {
		r[0] == "satisfied"
		"artifact.nums" in r[1]
		not "artifact.nums named by key" in r[1]
	}
}

test_a_count_or_sum_keyed_by_an_item_field_fails_as_before_when_the_key_is_missing_null_or_wrong_typed if {
	rows := [{"key": "a", "n": 1}]
	missing := _keyed_tally_rows({"z": 1}, rows, _keyed_tallies)
	nulled := _keyed_tally_rows({"a": null}, rows, _keyed_tallies)
	wrong := _keyed_tally_rows({"a": "s"}, rows, _keyed_tallies)
	every _, r in missing {
		r[0] == "absent"
		"artifact.nums" in r[1]
	}
	every _, r in nulled {
		r[0] == "null"
		"artifact.nums" in r[1]
	}
	every _, r in wrong {
		r[0] == "unusable"
		"artifact.nums" in r[1]
	}
}

test_a_walk_keyed_by_an_item_field_whose_part_before_the_name_walks_a_list_lists_nothing_of_it if {
	doc := {"artifacts": [{"name": "x", "ls": [{"m": {"a": 1}}], "prs": [{"id": 1, "rows": [{"key": "a", "n": 1}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "artifact.prs", "identified_by": "id"}}
	checks := {"c": "some rows.n is at least artifact.ls.m named by key"}
	rows := ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[[i.name | some i in r.inputs] | some r in rows; r.check == "c"] == [["rows[].n"]]
}

_part_for_subjects(has) := {
	"artifact": {"from": "$input.artifact", "identified_by": "n", "has": has},
	"child": {"from": "artifact.kids", "identified_by": "id"},
}

_part_for_row(doc, has, check, params) := [r | some r in ergo.report(doc, {"ergo_spec": "v0.3-dev", "subjects": _part_for_subjects(has), "requirements": {"r": {"subject": "child", "checks": {"c": check}}}}, params).results; r.check == "c"][0]

test_a_second_for_item_that_starts_at_a_parents_part_names_its_unchecked_items_like_its_inputs if {
	doc := {"artifact": {"n": "a", "ps": {"w": [{"t": "k1"}, {}]}, "kids": [{"id": 1, "keys": ["k1"]}]}}
	row := _part_for_row(doc, {"ap": "ps"}, {"for": "every keys as k, every artifact.ap.w whose t is k as x", "assert": "x.t is 1"}, {})
	[f.item | some f in row.failed_items[0].failed_items] == ["item 2 of artifact.ap.w"]
	[f.path | some f in row.failed_items[0].failed_items] == ["item 2 of artifact.ap.w"]
	[i.name | some i in row.inputs] == ["artifact.ap.w[]", "keys[]"]
}

test_a_second_for_item_that_starts_at_a_parents_part_named_by_an_item_keeps_the_key_it_read_and_hides_the_part_marker if {
	doc := {"artifact": {"n": "a", "ps": {"k1": [{"t": 1}, {}]}, "kids": [{"id": 1, "keys": ["k1"]}]}}
	row := _part_for_row(doc, {"ap": "ps"}, {"for": "every keys as k, every artifact.ap named by k.t as x", "assert": "x is 1"}, {})
	[f.item | some f in row.failed_items[0].failed_items] == ["item 2 of artifact.ap.k1"]
	[i.name | some i in row.inputs] == ["artifact.ap named by k[].t", "keys[]"]
}

test_a_failed_sentence_of_a_second_for_item_that_starts_at_a_parents_part_names_its_items_without_the_part_marker if {
	doc := {"artifact": {"n": "a", "ps": {"w": ["k1", "z"]}, "kids": [{"id": 1, "keys": ["k1"]}]}}
	row := _part_for_row(doc, {"ap": "ps"}, {"for": "every keys as k, every artifact.ap.w as x", "assert": "x is k"}, {})
	[[i.item | some i in a.items] | some a in row.failed_items[0].failed_assertions] == [["item 2 of artifact.ap.w"]]
}

test_a_second_for_item_that_starts_at_a_plain_parent_input_or_params_keeps_its_name_in_unchecked_items if {
	doc := {"artifact": {"n": "a", "w": [{"t": "k1"}, {}], "kids": [{"id": 1, "keys": ["k1"]}]}, "top": [{"t": "k1"}, {}]}
	plain := _part_for_row(doc, {}, {"for": "every keys as k, every artifact.w whose t is k as x", "assert": "x.t is 1"}, {})
	[f.item | some f in plain.failed_items[0].failed_items] == ["item 2 of artifact.w"]
	from_input := _part_for_row(doc, {}, {"for": "every keys as k, every $input.top whose t is k as x", "assert": "x.t is 1"}, {})
	[f.item | some f in from_input.failed_items[0].failed_items] == ["item 2 of $input.top"]
	from_params := _part_for_row(doc, {}, {"for": "every keys as k, every $params.l whose t is k as x", "assert": "x.t is 1"}, {"l": [{"t": "k1"}, {}]})
	[f.item | some f in from_params.failed_items[0].failed_items] == ["item 2 of $params.l"]
}

test_a_first_for_item_through_a_parents_part_or_named_by_names_its_failed_items_like_a_walk if {
	doc := {"artifact": {"n": "a", "ps": {"w": [1, 0], "k1": [1, 0]}, "kids": [{"id": 1, "k": "k1"}]}}
	part := _part_for_row(doc, {"ap": "ps"}, {"for": "every artifact.ap.w as x", "assert": "x is 1"}, {})
	[f.item | some f in part.failed_items] == ["item 2 of artifact.ap.w"]
	named := _part_for_row(doc, {"ap": "ps"}, {"for": "every artifact.ap named by k as x", "assert": "x is 1"}, {})
	[f.item | some f in named.failed_items] == ["item 2 of artifact.ap.k1"]
	[i.name | some i in named.inputs] == ["artifact.ap named by k[]", "k"]
}

_clash_doc := {"bs": [{"id": "b1", "k1": {"k2": {"k3": {"z": 2}}}, "kids": [{"id": "k1", "xs": [{"b": {"x": {"z": 1}}, "x": {"z": 7}, "v": 1}, {"b": {"x": {"z": 5}}, "x": {"z": 7}, "v": 9}]}]}]}

_clash_policy(has, extra, check) := {
	"ergo_spec": "v0.3-dev",
	"subjects": object.union({"b": {"from": "bs", "identified_by": "id", "has": has}, "kid": {"from": "b.kids", "identified_by": "id"}}, extra),
	"requirements": {"r": {"subject": "kid", "checks": {"c": check}}},
}

_clash_report(has, extra, check) := ergo.report(_clash_doc, _clash_policy(has, extra, check), {})

_clash_problems(has, extra, check) := [i.value | some r in _clash_report(has, extra, check).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

_clash_rows(has, extra, check) := [[r.cause, r.passed] | some r in _clash_report(has, extra, check).results; r.check == "c"]

test_a_for_alias_named_like_a_parent_subject_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}) == [["b can't be an alias: it's a subject's name"]]
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.id is \"b1\""}) == [["b can't be an alias: it's a subject's name"]]
	stopped(_clash_report({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}))
	_clash_rows({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}) == []
}

test_a_for_alias_named_like_the_checks_own_subject_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as kid", "assert": "kid.v is 1"}) == [["kid can't be an alias: it's a subject's name"]]
}

test_a_for_alias_named_like_an_unrelated_subject_is_written_wrong if {
	extra := {"other": {"from": "bs", "identified_by": "id"}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as other", "assert": "other.v is 1"}) == [["other can't be an alias: it's a subject's name"]]
}

test_a_for_alias_named_like_a_part_of_a_parent_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as x", "assert": "x.z is 7"}) == [["x can't be an alias: it's a part of b"]]
}

test_a_for_alias_named_like_a_subject_and_a_part_gets_both_messages if {
	_clash_problems({"b": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.v is 1"}) == [["b can't be an alias: it's a part of b", "b can't be an alias: it's a subject's name"]]
}

test_a_for_alias_named_like_a_part_of_the_own_subject_is_written_wrong if {
	extra := {"kid": {"from": "b.kids", "identified_by": "id", "has": {"y": "xs"}}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.v is 1"}) == [["y can't be an alias: it's a part of kid"]]
}

test_a_for_alias_that_clashes_with_nothing_reads_the_item if {
	has := {"x": "k1.k2.k3"}
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.x.z is 7"}) == [["satisfied", true]]
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.v is 1"}) == [["value", false]]
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.b.x.z is 1"}) == [["value", false]]
}

test_a_long_parent_part_walked_from_a_for_alias_named_like_the_parent_is_written_wrong_for_the_clash_only if {
	has := {"p": "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10"}
	_clash_problems(has, {}, {"for": "every xs as y, every b.p.list as z", "assert": "z is 1"}) == [[_for_too_long]]
	_clash_problems(has, {}, {"for": "every xs as b, every b.p.list as z", "assert": "z is 1"}) == [["b can't be an alias: it's a subject's name"]]
	_clash_problems({"p": "k1.k2.k3.k4.k5.k6.k7.k8.k9"}, {}, {"for": "every xs as y, every b.p.list as z", "assert": "z is 1"}) == []
}

_part_clash_problems(subjects) := _part_clash_problems_of(subjects, "kid")

_part_clash_problems_of(subjects, subject) := [i | some r in ergo.report(_clash_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": subject, "checks": {"c": "id exists"}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

_clash_b := {"from": "bs", "identified_by": "id", "has": {"x": "k1"}}

test_a_part_named_like_the_subject_it_belongs_to_is_written_wrong if {
	subjects := {"b": _clash_b, "kid": {"from": "b.kids", "identified_by": "id", "has": {"kid": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.kid", "value": ["kid can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_the_parent_it_reads_from_is_written_wrong_as_a_subjects_name if {
	subjects := {"b": _clash_b, "kid": {"from": "b.kids", "identified_by": "id", "has": {"b": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.b", "value": ["b can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_an_unrelated_subject_is_written_wrong if {
	subjects := {"b": _clash_b, "other": {"from": "bs", "identified_by": "id"}, "kid": {"from": "b.kids", "identified_by": "id", "has": {"other": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.other", "value": ["other can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_a_part_of_a_parent_is_written_wrong if {
	subjects := {"b": _clash_b, "kid": {"from": "b.kids", "identified_by": "id", "has": {"x": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.x", "value": ["x can't be an alias: it's a part of b"], "locations": []}]
}

test_a_part_named_like_a_part_kept_from_a_narrowed_subject_is_written_wrong if {
	subjects := {"b": _clash_b, "slim": {"from": "b whose id exists", "has": {"y": "xs"}}, "wider": {"from": "slim whose id exists", "has": {"y": "v"}}}
	_part_clash_problems_of(subjects, "wider") == [{"name": "subjects.wider.has.y", "value": ["y can't be an alias: it's a part of slim"], "locations": []}]
}

test_two_for_items_with_the_same_alias_are_given_twice_and_no_subject_or_part_is_involved if {
	_clash_problems({"x": "k1"}, {}, {"for": "every xs as y, every xs as y", "assert": "y.v is 1"}) == [["for: y is given twice"]]
}

_clash3_doc := {"gps": [{"id": "g1", "cap": {"z": 1}, "mids": [{"id": "m1", "leaves": [{"id": "l1", "ys": [{"v": 1}], "zs": [{"w": 2}]}]}]}]}

_clash3_subjects(leaf_has) := {
	"gp": {"from": "gps", "identified_by": "id", "has": {"cap": "cap"}},
	"mid": {"from": "gp.mids", "identified_by": "id"},
	"leaf": {"from": "mid.leaves", "identified_by": "id", "has": leaf_has},
}

_clash3_report(leaf_has, check) := ergo.report(_clash3_doc, {"ergo_spec": "v0.3-dev", "subjects": _clash3_subjects(leaf_has), "requirements": {"r": {"subject": "leaf", "checks": {"c": check}}}}, {})

_clash3_problems(leaf_has, check) := [i.value | some r in _clash3_report(leaf_has, check).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

test_a_for_alias_named_like_a_part_of_a_grandparent_is_written_wrong if {
	_clash3_problems({}, {"for": "every ys as cap", "assert": "cap.v is 1"}) == [["cap can't be an alias: it's a part of gp"]]
}

test_a_for_alias_on_the_second_item_named_like_a_part_of_a_parent_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as y, every xs as x", "assert": "x.v is 1"}) == [["x can't be an alias: it's a part of b"]]
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as y, every xs as b", "assert": "y.v is 1"}) == [["b can't be an alias: it's a subject's name"]]
	_clash3_problems({}, {"for": "every ys as y, every zs as cap", "assert": "y.v is 1"}) == [["cap can't be an alias: it's a part of gp"]]
}

test_a_first_of_item_named_like_a_parent_or_a_part_of_it_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "first of xs as b", "assert": "b.v is 1"}) == [["b can't be an alias: it's a subject's name"]]
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "first of xs as x", "assert": "x.v is 1"}) == [["x can't be an alias: it's a part of b"]]
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "first of xs as entry", "assert": "entry.v is 1"}) == []
}

test_a_part_named_like_a_part_of_a_grandparent_is_written_wrong_without_being_a_subjects_name if {
	_part_clash_problems_of(_clash3_subjects({"cap": "ys"}), "leaf") == [{"name": "subjects.leaf.has.cap", "value": ["cap can't be an alias: it's a part of gp"], "locations": []}]
}

test_an_alias_named_like_a_part_of_a_subject_that_is_not_an_ancestor_is_accepted if {
	extra := {"other": {"from": "bs", "identified_by": "id", "has": {"y": "k1"}}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.v is 1"}) == []
	_clash_rows({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.x.z is 7"}) == [["satisfied", true]]
	_part_clash_problems({"b": _clash_b, "other": extra.other, "kid": {"from": "b.kids", "identified_by": "id", "has": {"y": "xs"}}}) == []
}

_clash_narrowed := {
	"b": {"from": "bs", "identified_by": "id", "has": {"part": "k1"}},
	"b2": {"from": "b whose id exists"},
	"kid2": {"from": "b2.kids", "identified_by": "id"},
}

_clash_narrowed_problems(subject, check) := [i.value | some r in ergo.report(_clash_doc, {"ergo_spec": "v0.3-dev", "subjects": _clash_narrowed, "requirements": {"r": {"subject": subject, "checks": {"c": check}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

test_a_for_alias_named_like_a_part_kept_from_a_narrowed_subject_names_the_subject_that_declares_it if {
	_clash_narrowed_problems("b2", {"for": "every kids as part", "assert": "part.id exists"}) == [["part can't be an alias: it's a part of b"]]
	_clash_narrowed_problems("kid2", {"for": "every xs as part", "assert": "part.v is 1"}) == [["part can't be an alias: it's a part of b"]]
}

test_a_part_kept_through_two_narrowings_is_named_once_after_the_subject_that_declares_it if {
	subjects := {"base": {"from": "bs", "identified_by": "id", "has": {"x": "k1"}}, "m": {"from": "base whose id exists"}, "n": {"from": "m whose id exists", "has": {"x": "xs"}}}
	_part_clash_problems_of(subjects, "n") == [{"name": "subjects.n.has.x", "value": ["x can't be an alias: it's a part of base"], "locations": []}]
}

test_a_subject_name_with_a_space_is_quoted_in_the_message if {
	subjects := {"pull request": {"from": "bs", "identified_by": "id", "has": {"pull": "k1"}}, "kid": {"from": `"pull request".kids`, "identified_by": "id", "has": {"pull": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.pull", "value": ["pull can't be an alias: it's a part of \"pull request\""], "locations": []}]
}

test_a_for_alias_named_like_a_part_of_a_subject_with_a_space_in_its_name_quotes_the_name if {
	subjects := {"pull request": {"from": "bs", "identified_by": "id", "has": {"pull": "k1"}}, "kid": {"from": `"pull request".kids`, "identified_by": "id"}}
	rep := ergo.report(_clash_doc, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": {"for": "every xs as pull", "assert": "pull.v is 1"}}}}}, {})
	[i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [["pull can't be an alias: it's a part of \"pull request\""]]
}

_each_id_problem := [{"name": "subjects.suite.identified_by", "value": ["not allowed with named by each of: the key is the id"], "locations": []}]

test_identified_by_is_written_wrong_on_every_form_of_a_from_line_listed_by_named_by_each_of if {
	every from in [
		"suites named by each of $params.names",
		"suites named by each of $params.names whose id exists",
		"top named by $params.g named by each of $params.names",
		"top[$params.g].suites named by each of $params.names",
		"artifact.suites named by each of $params.names",
		"artifact.suites named by each of $params.names whose id exists and id is 1",
	] {
		subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "suite": {"from": from, "identified_by": "id"}}
		rep := ergo.report({"suites": {"a": {"id": 1}}, "top": {"g": {"a": {"id": 1}}}, "artifacts": [{"id": 9, "suites": {"a": {"id": 1}}}]}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "suite", "checks": {"c": "id exists"}}}}, {"names": ["a"], "g": "g"})
		_from_problems(rep) == _each_id_problem
		[r.check | some r in rep.results] == ["$well_formed"]
	}
}

test_identified_by_stays_allowed_on_the_parent_of_a_subject_listed_by_named_by_each_of if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "suite": {"from": "artifact.suites named by each of $params.names"}}
	rep := ergo.report({"artifacts": [{"id": 9, "suites": {"a": {"id": 1}}}]}, {"ergo_spec": "v0.3-dev", "subjects": subjects, "requirements": {"r": {"subject": "suite", "checks": {"c": "id exists"}}}}, {"names": ["a"]})
	_from_problems(rep) == []
	[r.subject.id | some r in rep.results; r.check == "c"] == ["a"]
}

test_identified_by_stays_allowed_with_named_by_and_without_each_of if {
	rep := _from_report({"suites": {"g": [{"id": 1}]}}, {"suite": {"from": "suites named by $params.g", "identified_by": "id"}}, {"c": "id exists"}, {"g": "g"})
	_from_problems(rep) == []
	[r.subject.id | some r in rep.results; r.check == "c"] == [1]
}

test_identified_by_that_cannot_be_read_on_a_subject_listed_by_named_by_each_of_gives_both_problems if {
	rep := _from_report({"suites": {}}, {"suite": {"from": "suites named by each of $params.names", "identified_by": "a b c"}}, {"c": "id exists"}, {"names": ["a"]})
	_from_problems(rep) == [{"name": "subjects.suite.identified_by", "value": ["identified_by is a path, like \"id\" or \"build.number\"", "not allowed with named by each of: the key is the id"], "locations": []}]
}

_pick_reads_first_cause(item, xs, ys) := [r.cause |
	some r in ergo.report({"s": [{"id": "a", "xs": xs, "ys": ys}]}, {"ergo_spec": "v0.3-dev", "subjects": {"s": {"from": "s", "identified_by": "id"}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"for": concat("", ["every xs as p, ", item, " as q"]), "assert": "q.n is 1"}}}}}, {}).results
	r.check == "c"
][0]

test_a_second_for_item_picks_for_each_first_item_when_its_whose_reads_the_first_alias if {
	_pick_reads_first_cause("first of ys whose k is p.k", [{"k": 1}], [{"k": 1, "n": 1}]) == "satisfied"
	_pick_reads_first_cause("first of ys whose k is p.k", [{"k": 1}, {"k": 2}], [{"k": 2, "n": 1}, {"k": 1, "n": 1}, {"k": 1, "n": 9}]) == "satisfied"
	_pick_reads_first_cause("first of ys whose k is p.k", [{"k": 1}, {"k": 2}], [{"k": 2, "n": 5}, {"k": 1, "n": 1}]) == "value"
	_pick_reads_first_cause("last of ys whose k is p.k sorted by t", [{"k": 1}], [{"k": 1, "n": 2, "t": 1}, {"k": 1, "n": 1, "t": 3}]) == "satisfied"
	_pick_reads_first_cause("item 2 of ys whose k is p.k", [{"k": 1}], [{"k": 1, "n": 5}, {"k": 1, "n": 1}]) == "satisfied"
}

test_a_second_for_item_picking_with_a_whose_that_reads_the_first_alias_fails_when_nothing_matches if {
	_pick_reads_first_cause("first of ys whose k is p.k", [{"k": 3}], [{"k": 1, "n": 1}]) == "absent"
	_pick_reads_first_cause("first of ys whose k is p.k", [{"j": 1}], [{"k": 1, "n": 1}]) == "absent"
	_pick_reads_first_cause("first of ys whose k is p.k", [null], [{"k": 1, "n": 1}]) != "satisfied"
	_pick_reads_first_cause("last of ys whose k is p.k sorted by t", [{"k": 1}], [{"k": 1, "n": 1, "t": 1}, {"k": 1, "n": 1, "t": 1}]) == "ambiguous"
}

_pick_row(xs, ys, miss) := [r |
	some r in ergo.report({"s": [object.union({"id": "a", "xs": xs}, {k: ys | not miss; k := "ys"})]}, {"ergo_spec": "v0.3-dev", "subjects": {"s": {"from": "s", "identified_by": "id"}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"for": "every xs as p, first of ys whose k is p.k as q", "assert": "q.n is 1"}}}}}, {}).results
	r.check == "c"
][0]

test_a_second_for_item_that_picks_nothing_after_the_first_alias_lists_no_failed_item if {
	row := _pick_row([{"k": 1}, {"k": 2}], [], false)
	row.cause == "absent"
	row.failed_items == []
	row2 := _pick_row([{"k": 3}], [{"k": 1, "n": 1}], false)
	row2.cause == "absent"
	row2.failed_items == []
}

test_a_second_for_item_after_the_first_alias_lists_only_the_first_items_that_failed_their_check if {
	row := _pick_row([{"k": 1}, {"k": 2}], [{"k": 1, "n": 2}], false)
	[f.item | some f in row.failed_items] == ["item 1 of xs"]
}

test_a_second_for_item_after_the_first_alias_shows_its_list_when_the_first_list_is_empty if {
	row := _pick_row([], [{"k": 1, "n": 1}], false)
	[i.name | some i in row.inputs] == ["xs[]", "ys[]"]
}

test_a_second_list_that_cant_be_walked_is_listed_once_when_the_pick_reads_the_first_alias if {
	row := _pick_row([{"k": 1}, {"k": 2}], [], true)
	row.cause == "absent"
	[f.item | some f in row.failed_items] == ["ys"]
	not "failed_items" in object.keys(row.failed_items[0])
}

test_subjects_that_narrow_each_other_with_unknown_names_list_each_other_and_have_no_id if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"a": {"from": "b whose x is $foo"}, "b": {"from": "a whose x is $foo"}},
		"requirements": {"r": {"subject": "a", "checks": {"c": "n exists"}}},
	}
	report := ergo.report({}, policy, {})
	object.keys(report.subjects) == {"a", "b"}
	report.subjects.a.from == "<invalid from>"
	report.subjects.a.identified_by == null
	report.subjects.b.identified_by == null
}

test_a_from_that_reads_names_with_an_unknown_name_lists_the_subject_it_starts_at if {
	policy := {
		"ergo_spec": "v0.3-dev",
		"subjects": {"p": {"from": "things", "identified_by": "id"}, "k": {"from": "p.items named by $foo", "identified_by": "n"}},
		"requirements": {"r": {"subject": "k", "checks": {"c": "n exists"}}},
	}
	object.keys(ergo.report({}, policy, {}).subjects) == {"k", "p"}
}
