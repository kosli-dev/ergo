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
	causes == {"x": "absent", "b": "not_an_object"}
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
	rep.requirements.s.checks["$applies"].expression == "state == MERGED"
}

test_applies_definition_conjoins_multiple_filter_checks if {
	both := object.union(merged_only, {"on_main": {"op": "equals", "path": ["base_ref"], "value": "main"}})
	rep := ergo.report(two_states, scoped_req(both))

	rep.requirements.s.checks["$applies"].expression == "state == MERGED and base_ref == main"
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
	rendered({"licences": []}, licences_allowed) == "every licences: id in [Apache-2.0, MIT]"
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
	rendered(attestations_array, one) == "attestations.[attestation_type==pull_request and status==COMPLETE].payload == right"
}

test_selector_value_is_echoed_in_the_row if {
	report := solo(attestations_array, pr_payload)
	some r in report.results
	r.check == "c"
	r.inputs == [{
		"name": "attestations.[attestation_type==pull_request].payload",
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
	cause_of({"author": "svc_bot"}, check) == "absent"
}

test_matching_with_no_patterns if {
	verdict({"author": "Alice"}, {"op": "matches_any", "path": ["author"], "patterns": set()}) == false
	verdict({"author": "Alice"}, {"op": "not_matches_any", "path": ["author"], "patterns": set()}) == true
}

test_expression_for_matching_sorts_patterns if {
	rendered({"author": "Alice"}, matches("not_matches_any")) == sprintf(
		"author matches none of [%s]",
		[`.*\[bot\], noreply@github\.com, svc_.*`],
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

test_compare_time_rejects_an_out_of_range_month if {
	verdict({"start": "2024-13-01T00:00:00Z", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_date_without_a_time if {
	verdict({"start": "2024-01-01", "end": "2024-06-01"}, compare_time_span("lt")) == false
}

test_rfc3339_gate_accepts_valid_timestamps if {
	every ts in [
		"2024-01-01T00:00:00Z",
		"2024-01-01T00:00:00z",
		"2024-06-30T23:59:59.999999999Z",
		"2024-06-30T12:00:00+02:00",
		"2024-06-30T12:00:00-05:30",
	] {
		ergo.rfc3339_shaped(ts)
	}
}

test_rfc3339_gate_rejects_everything_else if {
	every ts in [
		"yesterday",
		"",
		"2024-01-01",
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
		not ergo.rfc3339_shaped(ts)
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
			`web_flow(author matches one of [noreply@github\.com])`,
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
	rendered({"branches": []}, release_branches) == "every branches: branches[] matches one of [^main$, ^release/]"
}

test_an_empty_path_names_the_item_inside_an_any_of if {
	rendered({"branches": []}, {"op": "all", "path": ["branches"], "check": {"op": "any_of", "options": {
		"main": [{"op": "equals", "path": [], "value": "main"}],
		"release": [{"op": "matches_any", "path": [], "patterns": ["^release/"]}],
	}}}) == "every branches: one of: main(branches[] == main) | release(branches[] matches one of [^release/])"
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
	rep.requirements.s.checks.c.expression == "branches[] matches one of [^main$]"
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "branches[]", "value": "main"}]]
}

test_an_empty_path_on_the_whole_input_is_named_input if {
	rep := ergo.report({"state": "ok"}, {"s": {"checks": {"c": {"op": "present", "path": []}}}})
	rep.requirements.s.checks.c.expression == "input is present"
	[r.inputs | some r in rows_for(rep, "s", "c")] == [[{"name": "input", "value": {"state": "ok"}}]]
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
	rep.requirements.s.checks.either.expression == "one of: main(branches[] == main)"
	rep.requirements.s.checks.same.expression == "branches[] eq branches[]"
	rep.requirements.s.checks.backed.expression == "branches[] == x, or substitute: branches[] is present"
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
	rendered({"licences": []}, plain_licences) == "every licences: licences[] in [Apache-2.0, MIT]"
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
	rendered({"repos": []}, nested_branches) == "every repos[]: repos[][] == main"
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
		"safe(type matches one of [^SAFe Story$] and state matches one of [^DONE$])",
		" | ",
		"standard(type matches one of [^Story$] and state matches one of [^CLOSED$])",
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

test_expression_for_excludes if rendered({"labels": []}, no_wip) == "not contains(labels, wip)"

test_expression_for_includes if rendered({"labels": []}, has_approved) == "contains(labels, approved)"

test_expression_for_in_sorts_the_values if rendered({"id": "MIT"}, allowed_licence) == "id in [Apache-2.0, MIT]"

test_expression_for_in_sorts_a_set_of_values if {
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"MIT", "Apache-2.0"}}) == "id in [Apache-2.0, MIT]"
}

test_expression_for_in_does_not_list_values_it_will_not_match if {
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": {"licence": "MIT"}}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": "MIT"}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"], "values": null}) == "id in <invalid values>"
	rendered({"id": "MIT"}, {"op": "in", "path": ["id"]}) == "id in <invalid values>"
}

test_expression_for_equals if rendered({}, is_merged) == "state == MERGED"

test_expression_for_present if rendered({}, has_fingerprint) == "fingerprint is present"

test_expression_for_non_empty_string if rendered({}, filled) == "fingerprint is a non-empty string"

test_expression_for_compare if rendered({}, compare_ab("lt")) == "a lt b"

test_expression_for_compare_time if rendered(span, compare_time_span("lt")) == "start lt end"

test_expression_for_all if rendered({"commits": []}, all_verified) == "every commits: verified == true"

test_expression_for_any if rendered({"approvers": []}, any_approved) == "some approvers: state == APPROVED"

test_expression_for_nested_paths_is_dotted if {
	check := {"op": "equals", "path": ["a", "b"], "value": 1}
	rendered({}, check) == "a.b == 1"
}

test_declared_expression_wins_over_the_rendered_one if {
	check := object.union(is_merged, {"expression": "state is MERGED"})
	rendered({}, check) == "state is MERGED"
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

test_cause_absent_when_the_path_walks_through_a_scalar if {
	cause_of({"pr": "none"}, {"op": "equals", "path": ["pr", "state"], "value": "MERGED"}) == "absent"
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
	def.description == "at least 2 matching thing subject(s) required"
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

test_well_formed_definition_is_in_the_check_table if {
	rep := ergo.report({"items": [{"id": "a"}]}, id_req(["items"]))
	rep.requirements.s.checks["$well_formed"].expression == "count(checks) >= 1 and require in {every, some}"
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

	sequence := [sprintf("%s/%s/%v", [r.requirement, r.check, r.subject.id]) |
		some r in ergo.report(doc, {"zzz": req, "aaa": req}).results
	]
	sequence == [
		"aaa/$well_formed/null",
		"zzz/$well_formed/null",
		"aaa/$min_subjects/null",
		"zzz/$min_subjects/null",
		"aaa/$applies/s2",
		"aaa/$applies/s1",
		"zzz/$applies/s2",
		"zzz/$applies/s1",
		"aaa/alpha/s2",
		"aaa/zeta/s2",
		"zzz/alpha/s2",
		"zzz/zeta/s2",
	]
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
	v[0].description == "at least 1 matching thing subject(s) required"
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
	not ergo.is_violation(rep.requirements, row)
}

test_definition_field_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := ergo.report({"items": [{"id": "a", "signed": true}]}, violating_req)
	some row in rep.results
	row.check == "reviewed"
	ergo.definition_field(rep.requirements, row, "description") == "Reviewed"
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

scan_requires := ["every", "some", "most"]

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

test_an_unsatisfied_report_always_explains_itself if {
	unexplained := [rep |
		some rq in scan_requires
		some mn in scan_mins
		some cs in scan_checksets
		some fl in scan_filters
		some d in scan_docs
		rep := ergo.report(d, scan_policy(rq, mn, cs, fl))
		rep.compliant == false
		count(ergo.violations(rep)) == 0
	]
	count(unexplained) == 0
}

test_a_malformed_requirement_is_never_satisfied if {
	malformed := [rep |
		some rq in scan_requires
		some mn in scan_mins
		some cs in scan_checksets
		some fl in scan_filters
		some d in scan_docs
		rep := ergo.report(d, scan_policy(rq, mn, cs, fl))
		rows_for(rep, "s", "$well_formed")[0].passed == false
	]

	count(malformed) > 0

	every rep in malformed {
		rep.requirements.s.satisfied == false
		count([v |
			some v in ergo.violations(rep)
			v.check == "$well_formed"
		]) == 1
	}
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
		"expression": "id == zzz",
	}
	rep.requirements.s.checks["$min_subjects"].description == "at least 1 matching thing subject(s) required"

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

test_a_subject_ruled_out_by_one_filter_stays_out_of_scope_when_another_filter_cannot_be_read if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": object.union(degraded_only, merged_only)})}
	rep := ergo.report({"rounds": [{"id": "r1", "state": "CLOSED"}]}, req)
	rep.requirements.s.satisfied == true
	rows_for(rep, "s", "$applies")[0].cause == "value"
	ergo.violations(rep) == []
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

test_a_present_check_on_a_missing_field_still_says_absent if {
	cause_of({}, {"op": "present", "path": ["lock"]}) == "absent"
}

test_only_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	req := {"s": object.union(locked_req(["lock"]).s, {"applies_to": {"locked": {"op": "non_empty_string", "path": ["lock"]}}})}
	rep := ergo.report({"packages": [{"id": "a"}]}, req)
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_a_custom_op_filter_without_inputs_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"is_even": {"op": "even", "path": ["n"], "expression": "n is even"}}})}
	ergo.report({"rounds": [{"id": "r1", "n": 3}]}, req).requirements.s.satisfied == true
}

test_a_failing_custom_op_filter_that_declares_no_reads_rules_a_subject_out if {
	req := {"s": object.union(degraded_req("every").s, {"applies_to": {"both": {
		"op": "both_present",
		"paths": [["a"], ["b"]],
		"expression": "a and b are present",
	}}})}
	rep := ergo.report({"rounds": [{"id": "r1", "a": 1}]}, req)
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
	[r.passed, r.cause] == [false, "absent"]
}

test_input_is_only_a_name_at_the_start_of_a_path if {
	row_in({}, {"id": 1, "a": {"$$input": "x"}}, {"op": "equals", "path": ["a", "$$input"], "value": "x"}).passed == true
}

test_a_literal_path_step_reads_a_key_that_looks_like_a_name if {
	r := row_in({"$$input": "top"}, {"id": 1, "$$input": "x"}, {"op": "equals", "path": [{"literal": "$$input"}], "value": "x"})
	[r.passed, r.inputs] == [true, [{"name": "$$input", "value": "x"}]]
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
	[r.passed, r.cause] == [false, "absent"]
}

test_a_null_ref_fails_closed_with_cause_null if {
	check := {"op": "equals", "path": ["v"], "value": {"ref": ["$$input", "params", "v"]}}
	r := row_in({"params": {"v": null}}, {"id": 1, "v": null}, check)
	[r.passed, r.cause] == [false, "null"]
}

test_a_ref_must_start_with_input if {
	r := row_in({}, {"id": 1, "licence": "MIT"}, {"op": "equals", "path": ["licence"], "value": {"ref": ["licence"]}})
	[r.passed, r.cause] == [false, "absent"]
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
	expression_in({}, {"id": 1}, {"op": "in", "path": ["licence"], "values": {"literal": ["MIT"]}}) == "licence in [MIT]"
	expression_in({}, {"id": 1}, {"op": "equals", "path": ["c"], "value": {"literal": "x"}}) == "c == x"
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
	[r.passed, r.cause] == [false, "absent"]
	r.inputs == [{"name": "labels", "value": ["ready"]}]
	refs_in({}, {"id": 1}, check) == [{"name": "<invalid ref>", "value": null}]
	expression_in({}, {"id": 1}, check) == "not contains(labels, <invalid ref>)"
}

test_an_object_with_literal_and_another_key_fails_closed if {
	check := {"op": "excludes", "path": ["labels"], "value": {"literal": "wip", "note": "x"}}
	r := row_in({}, {"id": 1, "labels": ["ready"]}, check)
	[r.passed, r.cause] == [false, "absent"]
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
	row_in({}, {"id": 1}, {"op": "present", "path": "state"}).cause == "absent"
	row_in({}, {"id": 1, "state": "OPEN"}, {"op": "equals", "path": "state", "value": "OPEN"}).passed == true
	row_in({}, {"id": 1}, {"op": "present", "path": 3}).passed == false
}

test_a_path_written_as_an_object_reads_nothing if {
	r := row_in({}, {"id": 1, "a": 1}, {"op": "present", "path": {"a": 1}})
	[r.passed, r.cause] == [false, "absent"]
}

test_an_id_written_as_a_string_reads_that_one_key if {
	rep := ergo.report({"items": [{"id": 1, "name": "x"}]}, {"s": {"from": ["items"], "id": "name", "checks": {"c": {"op": "present", "path": ["id"]}}}})
	[r.subject.id | some r in rows_for(rep, "s", "c")] == ["x"]
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
		"checks": {"c": {"op": "present", "path": []}},
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
	rep.requirements.s.checks.c.expression == "$suite.result == passed"
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

test_a_name_that_is_not_bound_reads_as_absent if {
	rep := ergo.report(pr_doc, {"s": {
		"from": ["pull_requests", {"each_as": "pr"}],
		"id": ["number"],
		"checks": {"c": {"op": "present", "path": ["$p", "author"]}},
	}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"], [false, "absent"], [false, "absent"]]
}

test_a_name_is_not_bound_without_an_each_step if {
	r := row_in({}, {"id": 1, "a": 1}, {"op": "present", "path": ["$items", "a"]})
	[r.passed, r.cause] == [false, "absent"]
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
	rep.requirements.s.checks["$well_formed"].expression == "count(checks) >= 1 and require in {every, some} and from is well formed"
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
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": ["$pr", "author"]}}},
	}})
	[[r.passed, r.cause, r.inputs] | some r in rows_for(rep, "s", "c")] == [[false, "absent", [{"name": "xs[]", "value": [1, 2]}, {"name": "$pr.author", "value": null}]]]
}

test_an_input_missing_in_the_path_of_a_list_check_fails_as_absent if {
	rep := ergo.report({"items": [{"id": 1, "xs": [1]}]}, {"s": {
		"from": ["items"],
		"id": ["id"],
		"checks": {"c": {"op": "all", "path": ["xs"], "check": {"op": "present", "path": ["$$input", "nope"]}}},
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
		[43, false, "value"],
		[44, false, "value"],
		[45, false, "value"],
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

test_a_name_given_by_as_is_not_read_for_the_row_so_it_does_not_decide_the_cause if {
	check := {"op": "all", "path": ["approvers"], "as": "a", "check": {"op": "present", "path": ["$a", "timestamp"]}}
	review_rows(check)[4] == [45, false, "value"]
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
	array.slice(review_rows(check), 0, 3) == [[41, true, "satisfied"], [42, false, "value"], [43, false, "value"]]
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
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"absent"}
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
	{r.cause | some r in rows_for(rep, "s", "$applies")} == {"absent"}
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
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_a_badly_written_list_check_fails_as_absent if {
	every check in [
		{"op": "any", "path": ["approvers"], "as": "pr", "check": {"op": "present", "path": ["username"]}},
		{"op": "any", "path": ["approvers"], "as": "", "check": {"op": "present", "path": ["username"]}},
		{"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "a", "check": {"op": "present", "path": ["sha"]}}},
		{"op": "any", "path": ["approvers"], "as": "a", "check": {"op": "all", "path": ["$pr", "commits"], "as": "pr", "check": {"op": "present", "path": ["sha"]}}},
		{"op": "any", "path": ["approvers"], "check": {"op": "all", "path": ["$pr", "commits"], "as": 3, "check": {"op": "present", "path": ["sha"]}}},
	] {
		{r[2] | some r in review_rows(check)} == {"absent"}
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
		[5, false, "value"],
	]
}

test_a_list_check_inside_an_any_of_renders_in_its_option if {
	ergo.report(peer_doc, review_req(peer_check)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(state == APPROVED and username ne $pr.author and every $pr.commits: $approver.timestamp gt timestamp)"
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
	[r.passed, r.cause] == [false, "absent"]
	expression_in({}, {"id": 1}, check) == "every xs: every ys: one of: o(<nested too deep>)"
}

test_a_list_check_two_levels_under_an_any_of_at_the_top_is_too_deep if {
	check := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "check": {"op": "all", "path": ["zs"], "check": {"op": "present", "path": []}}}}]}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, check)
	[r.passed, r.cause] == [false, "absent"]
}

test_a_name_given_twice_in_a_list_check_inside_an_any_of_fails_as_absent if {
	inner := {"op": "any", "path": ["approvers"], "as": "approver", "check": {"op": "any_of", "options": {"peer": [{"op": "all", "path": ["$pr", "commits"], "as": "approver", "check": {"op": "present", "path": ["timestamp"]}}]}}}
	{r[2] | some r in peer_rows(inner)} == {"absent"}
	ergo.report(peer_doc, review_req(inner)).requirements.s.checks.c.expression == "some approvers as $approver: one of: peer(every $pr.commits as <name given twice>: timestamp is present)"
	top := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["commits"], "as": "pr", "check": {"op": "present", "path": ["timestamp"]}}]}}
	{r[2] | some r in peer_rows(top)} == {"absent"}
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

test_a_name_read_outside_the_list_check_that_gives_it_fails_as_absent if {
	inside := {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {
		"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
		"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
	}}}
	r := row_in({}, {"id": 1, "xs": [{"ys": []}]}, inside)
	[r.passed, r.cause] == [false, "absent"]
	top := {"op": "any_of", "options": {
		"a": [{"op": "all", "path": ["ys"], "as": "x", "check": {"op": "present", "path": []}}],
		"b": [{"op": "equals", "path": ["$x", "v"], "value": 1}],
	}}
	t := row_in({}, {"id": 1, "ys": []}, top)
	[t.passed, t.cause] == [false, "absent"]
	beside := {"op": "all", "path": ["xs"], "as": "o", "check": {"op": "any_of", "options": {"a": [
		{"op": "all", "path": ["ys"], "as": "y", "check": {"op": "present", "path": []}},
		{"op": "equals", "path": ["$y"], "value": 1},
	]}}}
	b := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, beside)
	[b.passed, b.cause] == [false, "absent"]
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

test_a_name_nothing_gives_in_an_each_path_fails_as_absent if {
	top := {"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}
	r := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, top)
	[r.passed, r.cause] == [false, "absent"]
	inner := {"op": "all", "path": ["xs"], "check": {"op": "all", "path": ["ys"], "each": ["$q", "zs"], "check": {"op": "present", "path": []}}}
	i := row_in({}, {"id": 1, "xs": [{"ys": [{"zs": [1]}]}]}, inner)
	[i.passed, i.cause] == [false, "absent"]
	in_option := {"op": "any_of", "options": {"o": [{"op": "all", "path": ["xs"], "each": ["$q", "ys"], "check": {"op": "present", "path": []}}]}}
	o := row_in({}, {"id": 1, "xs": [{"ys": [1]}]}, in_option)
	[o.passed, o.cause] == [false, "absent"]
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
	params_rows({"items": [{"id": 1, "$$params": "own"}]}, check) == [[true, "satisfied", [{"name": "$$params", "value": "own"}]]] with data.params as {"$$params": "other"}
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
	rep.requirements.s.checks.c.expression == "attestations.[$$params.att].status == COMPLETE"
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
		trail_rows(attested) == [[false, "absent", [{"name": "attestations.[$$params.att].status", "value": null}]]] with data.params as {"artifact": "app", "att": bad}
	}
}

test_a_ref_step_with_another_key_fails_the_check if {
	check := {"op": "present", "path": ["attestations", {"ref": ["$$params", "att"], "note": "x"}]}
	trail_rows(check) == [[false, "absent", [{"name": "attestations.[<invalid ref>]", "value": null}]]] with data.params as {"artifact": "app", "att": "junit"}
}

test_a_ref_inside_a_ref_path_is_not_followed if {
	check := {"op": "equals", "path": ["fingerprint"], "value": {"ref": ["$$params", {"ref": ["$$params", "which"]}]}}
	[array.slice(r, 0, 2) | some r in trail_rows(check)] == [[false, "absent"]] with data.params as {"artifact": "app", "which": "fp", "fp": "abc"}
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
	rows_for(ergo.report(trail_doc, req), "s", "$min_subjects")[0].cause == "absent" with data.params as {"artifact": ["app"]}
}

test_a_ref_step_in_from_that_cannot_be_read_shows_up_in_violations if {
	vs := ergo.violations(ergo.report(trail_doc, trail_req({"op": "present", "path": ["fingerprint"]}))) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "count(matching(trail.artifacts.[$$params.artifact]))", "value": 0}, {"name": "$$params.artifact", "value": null}]]]
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

test_a_from_written_as_a_string_reads_that_one_key if {
	rep := ergo.report({"items": [{"id": 1}, {"id": 2}]}, {"s": {"from": "items", "id": ["id"], "checks": {"c": {"op": "present", "path": ["id"]}}}})
	rep.requirements.s.subjects == {"total": 2, "matching": 2}
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
	[r.passed, r.cause] == [false, "absent"]
}

test_a_ref_step_of_the_wrong_type_inside_a_list_check_fails_as_absent if {
	inner := {"op": "all", "path": ["xs"], "check": {"op": "present", "path": [{"ref": ["$$params", "k"]}]}}
	option := {"op": "all", "path": ["xs"], "check": {"op": "any_of", "options": {"o": [{"op": "equals", "path": [{"ref": ["$$params", "k"]}], "value": 1}]}}}
	each := {"op": "all", "path": ["xs"], "each": [{"ref": ["$$params", "k"]}], "check": {"op": "present", "path": []}}
	two_sided := {"op": "any", "path": ["xs"], "check": {"op": "compare", "left": [{"ref": ["$$params", "k"]}], "right": ["$$params", "lim"], "cmp": "lt"}}
	every check in [inner, option, each, two_sided] {
		every k in [["v"], {"a": 1}, true] {
			r := row_in({}, {"id": 1, "xs": [{"v": 1}]}, check) with data.params as {"k": k, "lim": 5}
			[r.passed, r.cause] == [false, "absent"]
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
		rows_for(rep, "s", "$min_subjects")[0].cause == "absent"
		rep.requirements.s.subjects == {"total": 0, "matching": 0}
	}
	ergo.report(suite_doc, req).requirements.s.satisfied == false with data.params as {}
}

test_keys_from_a_ref_that_cannot_be_read_show_up_in_violations if {
	vs := ergo.violations(ergo.report(suite_doc, suites_from_params)) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "count(matching(build.test_runs))", "value": 0}, {"name": "$$params.suites", "value": null}]]]
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
	{"op": "in", "path": ["n"], "values": {"ref": ["$$input", "params", "word"]}},
	{"op": "in", "path": ["n"]},
	{"op": "range", "path": ["n"], "min": "a", "max": 5},
	{"op": "range", "path": ["n"], "min": 0, "max": {"ref": ["$$input", "params", "word"]}},
	{"op": "range", "path": ["n"], "min": 0},
	{"op": "range", "path": ["n"], "min": 9, "max": 0},
	{"op": "range", "path": ["n"], "min": {"ref": ["$$input", "params", "nine"]}, "max": 5},
	{"op": "equals", "path": ["n"], "value": 1, "as": "x"},
	{"op": "present", "path": ["n"], "each": ["a"]},
	{"op": "any_of", "as": "x", "options": {"o": [{"op": "equals", "path": ["n"], "value": 1}]}},
	{"op": "any_of", "options": {"o": [{"op": "equals", "path": ["n"], "value": 1, "each": []}]}},
	{"op": "equals", "path": ["n"]},
	{"op": "includes", "path": ["xs"]},
	{"op": "excludes", "path": ["xs"]},
	{"op": "present"},
	{"op": "non_empty_string"},
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

test_a_badly_written_filter_cannot_rule_subjects_out if {
	every filter in badly_written {
		rep := ergo.report(typo_doc, typo_req(filter))
		rep.requirements.s.satisfied == false
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
	}
}

test_a_badly_written_check_fails_as_absent if {
	every check in badly_written {
		rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
	}
}

test_an_operator_that_is_not_declared_fails_even_when_a_rule_passes_it if {
	ergo.op_passed({"op": "undeclared", "path": ["n"]}, {"n": 1})
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "undeclared", "path": ["n"]}}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_a_badly_written_option_fails_an_any_of_even_when_another_option_passes if {
	check := {"op": "any_of", "options": {"good": [{"op": "present", "path": ["n"]}], "bad": [{"op": "compare", "left": ["n"], "right": ["n"], "cmp": "bad"}]}}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
}

test_a_badly_written_substitute_fails_the_check_even_when_the_check_passes if {
	check := {"op": "present", "path": ["n"], "substitute": {"op": "nope", "path": ["n"]}}
	rep := ergo.report(typo_doc, {"s": {"from": ["items"], "id": ["id"], "checks": {"c": check}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
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
		[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
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
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "c")] == [[false, "absent"]]
	}
}

test_a_present_filter_with_a_badly_written_substitute_cannot_rule_subjects_out if {
	rep := ergo.report(typo_doc, typo_req({"op": "present", "path": ["missing"], "substitute": {"op": "nope", "path": ["n"]}}))
	rep.requirements.s.satisfied == false
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
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
	[[r.passed, r.cause] | some r in solo({}, "present").results; r.check == "c"] == [[false, "absent"]]
	rendered({}, {"op": "any_of", "options": {"o": ["present"]}}) == "one of: o(<invalid check>)"
	rendered({}, {"op": "all", "path": ["xs"], "check": "present"}) == "every xs: <invalid check>"
}
