package ergo_test

import data.ergo
import rego.v1

test_range_rejects_numeric_string if verdict({"temp_c": "5"}, in_range) == false

test_range_rejects_missing_field if verdict({"other": 5}, in_range) == false

test_range_rejects_null if verdict({"temp_c": null}, in_range) == false

test_excludes_rejects_non_array if verdict({"labels": "wip"}, no_wip) == false

test_excludes_rejects_missing_field if verdict({}, no_wip) == false

test_includes_rejects_non_array if verdict({"labels": "approved"}, has_approved) == false

test_includes_rejects_missing_field if verdict({}, has_approved) == false

test_equals_rejects_missing_field if verdict({}, is_merged) == false

test_present_rejects_missing_field if verdict({}, has_fingerprint) == false

test_present_rejects_explicit_null if verdict({"fingerprint": null}, has_fingerprint) == false

test_non_empty_string_rejects_empty_string if verdict({"fingerprint": ""}, filled) == false

test_non_empty_string_rejects_number if verdict({"fingerprint": 42}, filled) == false

test_non_empty_string_rejects_null if verdict({"fingerprint": null}, filled) == false

test_non_empty_string_rejects_missing_field if verdict({}, filled) == false

test_matches_any_rejects_a_human if {
	verdict({"author": "Alice <alice@example.com>"}, matches("matches_any")) == false
}

test_compare_time_rejects_malformed_timestamp if {
	verdict({"start": "yesterday", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_an_out_of_range_month if {
	verdict({"start": "2024-13-01T00:00:00Z", "end": "2024-01-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_date_against_a_time_even_at_midnight if {
	verdict({"start": "2024-01-01", "end": "2024-06-01T00:00:00Z"}, compare_time_span("lt")) == false
}

test_compare_time_rejects_a_date_that_doesnt_exist if {
	verdict({"start": "2023-02-29", "end": "2024-06-01"}, compare_time_span("lt")) == false
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

test_all_rejects_non_array if verdict({"commits": "none"}, all_verified) == false

test_all_rejects_missing_path if verdict({}, all_verified) == false

test_all_rejects_object_collection if {
	verdict({"commits": {"a": {"verified": true}}}, all_verified) == false
}

test_any_rejects_missing_path if verdict({}, any_approved) == false

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

test_any_of_rejects_a_cross_product_of_two_options if {
	verdict({"type": "Story", "state": "DONE"}, flavoured) == false
}

test_any_of_rejects_when_no_option_matches_either_field if {
	verdict({"type": "Chore", "state": "OPEN"}, flavoured) == false
}

test_any_of_rejects_a_subject_missing_one_of_the_fields if {
	verdict({"type": "Story"}, flavoured) == false
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

test_a_list_index_written_as_a_whole_number_reads_the_item if {
	verdict({"id": 1, "a": [1, 2]}, "item 2 of .a is 2") == true
	verdict({"id": 1, "a": [1, 2]}, "item 1 of .a is 1") == true
}

test_a_ref_step_that_reads_a_number_written_with_an_exponent_is_not_a_list_position if {
	check := ".a named by $params.i exists"
	r := params_rows({"items": [{"id": 1, "a": [1, 2]}]}, check)[0] with data.params as {"i": 1e0}
	[r[0], r[1]] == [false, "unusable"]
}

test_a_requirement_with_a_number_out_of_range_is_not_well_formed if {
	rows := [[r.check, r.passed] |
		some m in [{"min_subjects": 1e-400}, {"from": "every xs.\"a\".1e400"}]
		rep := report({"xs": [{"id": 1}]}, {"s": object.union({"from": "xs", "checks": {"c": "id exists"}}, m)})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [["$well_formed", false], ["$well_formed", false]]
}

test_a_from_written_wrong_stops_at_well_formed_even_with_min_subjects_zero if {
	every f in [5, ["items"], "items whose"] {
		every n in [0, 1] {
			req := {"s": object.union(min_subjects_req(n).s, {"from": f})}
			stopped(report({"items": [{"id": "a"}]}, req))
		}
	}
}

test_unique_ids_lists_each_repeated_id_once_in_the_order_it_is_written_whatever_the_input_order if {
	rows := {row |
		some ids in [[3, "b", 10, "a", 3, "b", 10, 10], [10, 10, "b", 3, "a", 10, "b", 3]]
		full := unique_ids_row({"repos": [{"name": n} | some n in ids]}, owner_req)
		row := [[{"name": i.name, "value": i.value} | some i in full[0]], full[1], full[2]]
	}
	rows == {[[{"name": "repeated repo ids", "value": ["b", 10, 3]}], false, "value"]}
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

test_a_subject_with_id_instead_of_identified_by_is_written_wrong if {
	rep := ergo.report(
		{"releases": [{"id": "r-1", "signed": true}]},
		{
			"ergo_spec": ergo._spec,
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

test_every_requirement_field_ergo_knows_is_well_formed if {
	req := object.union(typed_req, {"subject_type": "item", "require": "some", "from": "items whose id exists", "description": "d", "meta": {"m": "x"}})
	rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0].passed == true
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

test_an_empty_requirement_meta_is_well_formed_and_reported if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"meta": {}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	rep.requirements.s.meta == {}
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

test_a_policy_without_ergo_spec_is_written_wrong_so_every_requirement_fails if {
	every policy in [object.remove(two_reqs_policy({}), ["ergo_spec"]), two_reqs_policy({"ergo_spec": null})] {
		_spec_rows(policy) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": ["missing"], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": ["missing"], "locations": []}]],
		]]
	}
}

test_an_ergo_spec_that_is_not_a_string_is_written_wrong_because_yaml_reads_0_1_as_a_number if {
	every v in [0.1, 1, true, [ergo._spec], {"v": ergo._spec}] {
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": ["not a string"], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": ["not a string"], "locations": []}]],
		]]
	}
}

test_an_engine_reads_only_the_version_it_follows_so_any_other_ergo_spec_is_written_wrong if {
	every v in ["v0.1", "v0.2-dev", "v1.0", "v10.25", "v0.2"] {
		expected := concat("", ["unsupported version ", v, ", expected ", ergo._spec])
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
		]]
	}
}

test_an_ergo_spec_that_is_not_shaped_like_a_version_is_written_wrong_and_the_row_shows_it if {
	every v in ["0.1", "V0.1", "v0.1.0", " v0.2-dev", "v0.2-dev ", "v.1", "v1", "", "v0.2-beta", "v0.2-", "v0.2-dev-dev", "v0.2-DEV", "v0.2-dev2", "v0.4-devdev", "v-dev"] {
		expected := concat("", ["not a version ", v])
		_spec_rows(two_reqs_policy({"ergo_spec": v})) == [false, [
			["s", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
			["t", false, [{"name": "policy ergo_spec", "value": [expected], "locations": []}]],
		]]
	}
}

test_a_min_subjects_of_a_million_is_well_formed_however_it_is_written if {
	every v in [1000000, 1e6, 1.0e6, 1000000.0, 0] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == []
	}
}

test_a_min_subjects_whose_value_is_a_whole_number_is_well_formed_however_it_is_written if {
	rows := [r.passed |
		some m in [0, 2.0, 1e2]
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [true, true, true]
}

test_a_field_of_the_right_type_adds_no_input_to_well_formed if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": "items whose id exists"})})
	row := rows_for(rep, "s", "$well_formed")[0]
	[row.passed, count(row.inputs)] == [true, 2]
}

test_an_id_that_is_not_a_string_stops_at_well_formed if {
	stopped(report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"identified_by": 5})}))
}

test_a_min_subjects_that_is_not_a_number_stops_at_well_formed_whatever_opa_thinks_of_comparing_it if {
	every m in ["0", null, [], {}] {
		stopped(report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": m})}))
	}
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
	"ergo_spec": ergo._spec,
	"subjects": {name: {"from": "items", "identified_by": "id"}},
	"requirements": {"s": {"subject": name, "checks": {"c": "id exists"}}},
}

test_well_formed_definition_is_in_the_check_table if {
	rep := report({"items": [{"id": "a"}]}, id_req("items"))
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

test_a_policy_written_as_a_set_still_gets_a_row if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"item": {"from": "items", "identified_by": "id"}}, "requirements": {{"subject": "item", "checks": {"c": "id exists"}}}}
	stopped(ergo.report({"items": [{"id": 1}]}, policy, {}))
}

checks_for(subject) := ergo.report({"xs": [{"id": 1}]}, {"ergo_spec": ergo._spec, "requirements": {"s": {"subject": subject, "checks": {"c": "id exists"}}}}, {}).requirements.s.checks

test_a_subject_that_is_not_a_string_is_written_as_json_in_every_runtime if {
	checks_for(["a", "b"])["$min_subjects"].description == `The in-scope ["a", "b"] count is at least 1`
	checks_for(null)["$unique_ids"].description == "Every null id is unique"
	checks_for(-1)["$unique_ids"].description == "Every -1 id is unique"
}

test_any_rejects_an_object_collection if {
	verdict({"approvers": {"a": {"state": "APPROVED"}}}, any_approved) == false
}

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

test_a_badly_written_filter_fails_well_formed_too if {
	rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": `things whose x is one of 1, "a"`}}), {})
	problem_inputs(rep) == [{"name": "subjects.b.from", "value": ["values of mixed types"], "locations": []}]
	stopped(rep)
}

test_a_badly_written_filter_is_named_after_the_subject_whose_from_line_holds_it if {
	subjects := {"thing": {"from": `things whose x is one of 1, "a"`}, "b": {"from": "thing whose y exists"}}
	rep := ergo.report({"things": [{"x": 1, "y": 1}]}, filter_policy(subjects), {})
	problem_inputs(rep) == [{"name": "subjects.thing.from", "value": ["values of mixed types"], "locations": []}]
}

test_a_badly_written_filter_on_a_parent_or_a_grandparent_stops_the_child_at_well_formed if {
	subjects := {
		"artifact": {"from": `artifacts whose x is one of 1, "a"`, "identified_by": "id"},
		"pr": {"from": "every artifact.prs", "identified_by": "url"},
		"commit": {"from": "every pr.commits", "identified_by": "sha"},
	}
	doc := {"artifacts": [{"id": "a", "x": 1, "prs": [{"url": "p", "commits": [{"sha": "s"}]}]}]}
	every name in ["pr", "commit"] {
		rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": name, "checks": {"c": "x exists"}}}}, {})
		stopped(rep)
		problem_inputs(rep) == [{"name": "subjects.artifact.from", "value": ["values of mixed types"], "locations": []}]
	}
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
		[{"ergo_spec": ergo._spec, "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {"c": c}}}} | some c in checks],
		[filter_policy({"b": def}) | some def in subjects],
	)
	got := [[rep.compliant, [p | some i in problem_inputs(rep); some p in i.value]] |
		some policy in policies
		rep := ergo.report({"things": [{"items": [1]}]}, policy, {})
	]
	got == [[false, [concat("", [prefix, big, " can't be a list position"])]] | some prefix in ["", "", "", "", "for: ", "", ""]]
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

test_the_largest_position_a_float_holds_exactly_is_well_written if {
	rep := ergo.report(
		{"things": [{"items": [1]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {
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

test_a_range_with_equal_bounds_is_well_written if {
	verdict({"n": 1}, "n is between 1 and 1") == true
}

test_requirements_written_as_a_number_are_not_compliant if {
	report(one_item, 5).compliant == false
}

test_a_policy_written_as_a_set_is_not_compliant if {
	report({"items": [{"id": "a", "x": 1}]}, {json_only_req.s}).compliant == false
}

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
		{"ergo_spec": ergo._spec, "requirements": {"s": approved_req("deployment")}},
	] {
		rep := ergo.report(deployments_doc, policy, {})
		rep.requirements.s.status == "not_met"
		well_formed_problems(rep, "s") == [{"name": "subject", "value": ["not in subjects"], "locations": []}]
		stopped(rep)
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

test_a_subject_no_requirement_names_does_not_change_how_numbers_are_written if {
	policy := subject_policy({"i": {"from": "items", "identified_by": "id"}}, {"r": {"subject": "i", "checks": {"c": "n is 1.50"}}})
	with_unused := object.union(policy, {"subjects": {"unused": {"from": [{"where": {"k": {1}}}]}}})
	json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, with_unused, {})) == json.marshal(ergo.report({"items": [{"id": 1, "n": 1.5}]}, policy, {}))
}

test_a_position_in_brackets_is_read_like_one_in_words_but_remembers_how_it_was_written if {
	_read(`x[0] is 1`).assertions[0].path == {"bracketed": true, "position": 1, "steps": ["x"]}
	_read(`first of x is 1`).assertions[0].path == {"position": "first", "steps": ["x"]}
	_read(`item 1 of x is 1`).assertions[0].path == {"position": 1, "steps": ["x"]}
	_printed(`x[0] is 1`) == "item 1 of x is 1"
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

test_is_not_null_is_written_wrong_because_it_could_only_fail if {
	_sentence_problems(`x is not null`) == [`"is not null" is written "exists"`]
	_sentence_problems(`x does not equal null`) == [`"is not null" is written "exists"`]
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

test_a_number_just_past_the_largest_float_is_written_wrong_before_opa_reads_it if {
	every text in [`x is 1e309`, `x is 1.8e308`, `x is -1.7976931348623158e308`, `x is 0.00018e312`, `x is at least 1e350`, `x is between 1 and 2e308`, `x is 1 within 1e350`, `x is one of 1, 1e350`, `x contains 1e350`] {
		count(_sentence_problems(text)) == 1
		startswith(_sentence_problems(text)[0], "number out of range: ")
	}
	every text in [`x is 1.7976931348623157e308`, `x is 17976931348623157e292`, `x is 179769313486231570000e288`, `x is 1e308`] {
		ergo.report({"things": [{"id": "t1", "x": 1}]}, _sentence_policy({"c": text}), {}).results[0].passed
	}
}

test_within_only_compares_numbers_so_another_value_before_it_is_written_wrong if {
	every text in [`x is null within 1`, `x is "a" within 1`, `x is true within 0`] {
		_sentence_problems(text) == [`"within" only compares numbers`]
	}
}

test_a_written_value_after_starts_with_that_isnt_text_is_written_wrong_because_it_could_only_fail if {
	every pair in [[`x starts with null`, `"starts with" takes text`], [`x ends with 1`, `"ends with" takes text`], [`x starts with true`, `"starts with" takes text`]] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
}

test_forms_a_walk_cant_take_yet_are_written_wrong if {
	_sentence_problems(`every xs whose last of ys is 1 is not empty`) == ["last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""]
	_sentence_problems(`every k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11.k12 is 1`) == ["every and some over more than ten steps aren't supported yet"]
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

test_a_count_of_over_more_than_ten_steps_is_written_wrong_inside_a_whose_a_for_line_and_an_any_of if {
	_sentence_problems(concat("", ["every xs whose n is count of ", _eleven, " is not empty"])) == _too_long
	_sentence_problems(concat("", ["some xs whose n is count of ", _eleven, " is not empty"])) == _too_long
	_sentence_problems(concat("", ["count of xs whose n is count of ", _eleven, " is 1"])) == _too_long
	_sentence_problems({"for": "every xs as x", "assert": concat("", ["n is count of ", _eleven])}) == _too_long
	_sentence_problems({"for": "every xs as x", "assert": [concat("", ["x.n is at least sum of ", _eleven])]}) == _too_long
	_sentence_problems({"any_of": {"a": concat("", ["n is count of ", _eleven]), "b": "n is 1"}}) == ["option a: every and some over more than ten steps aren't supported yet"]
}

test_a_for_alias_is_a_step_of_a_count_of_on_the_right_so_a_check_that_read_before_is_written_wrong if {
	doc := {"things": [{"id": "a", "xs": [{"n": 1, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": [1]}}}}}}}}}]}]}
	[[r[0], r[2]] | some r in _walk_rows({"c": {"for": "every xs as x", "assert": "x.n is count of x.k1.k2.k3.k4.k5.k6.k7.k8.k9"}}, doc, {})] == [["a", "satisfied"]]
	_sentence_problems({"for": "every xs as x", "assert": concat("", ["x.n is count of x.", _ten])}) == _too_long
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

test_forms_ergo_does_not_run_yet_are_written_wrong_on_a_for_line_too if {
	every pair in [
		["every xs whose last of ys is 1 as x", "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""],
		["every b.c.d.e.f.g.h.i.j.k.l.m as x", "every and some over more than ten steps aren't supported yet"],
	] {
		_sentence_problems({"assert": "x is 1", "for": pair[0]}) == [concat("", ["for: ", pair[1]])]
	}
}

test_a_sum_whose_whose_reads_a_name_against_the_focus_is_written_wrong if {
	message := "sum of adds up numbers, which have no fields: to keep numbers by their value, write that instead of whose"
	_sentence_problems(`sum of items.x whose k is "a" is 1`) == [concat("", ["whose k: ", message])]
	_sentence_problems(`sum of items whose k is "a" is 1`) == [concat("", ["whose k: ", message])]
	_sentence_problems(`sum of items.x whose $params.k is lo is 1`) == [concat("", ["whose lo: ", message])]
	_sentence_problems(`sum of items.x whose count of ys is 1 is 1`) == [concat("", ["whose ys: ", message])]
	not _sentence_problems(`sum of items.x whose $params.k is 1 is 1`)
	not _sentence_problems(`sum of items.x that is at least 1 is 1`)
}

test_the_conditions_of_a_from_keep_the_order_they_were_written_in_past_ten if {
	pieces := [concat("", ["k", format_int(i, 10), " exists"]) | some i in numbers.range(1, 11)]
	rep := _from_report({"xs": [{"id": 1}]}, {"x": {"from": concat("", ["xs whose ", concat(" and whose ", pieces)])}}, {"c": "id exists"}, {})
	rep.requirements.r.checks["$applies"].expression == concat(" and ", pieces)
}

test_a_from_condition_with_if_any_after_some_or_a_whose_of_its_own_is_written_wrong if {
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files.path, if any, matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["if any can't go with some"], "locations": []}]
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files whose kind is "src" matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and whose every files whose kind is "src" matches "x"`}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	every line in [`releases whose count of files whose path is "x" is at least 1`, `releases whose sum of files.size whose path is "x" is at least 1`, `releases whose ticket is "ok" and whose count of files whose path is "x" is at least 1`] {
		_from_problems(_from_report(_releases, {"release": {"from": line}}, {"c": "ticket exists"}, {})) == [{"name": "subjects.release.from", "value": ["a condition after whose can't have a whose of its own"], "locations": []}]
	}
	_read(`count of files whose path is "x" is at least 1`).assertions[0].where != []
	_from_problems(_from_report(_releases, {"release": {"from": `releases whose some files.path`}}, {"c": "ticket exists"}, {})) != []
}

test_a_count_whose_parents_are_written_in_either_order_lists_them_in_the_same_order if {
	rows := _atts_rows(
		{
			"a": "count of commits whose author is artifact.team.lead and whose author is artifact.owner is 1",
			"b": "count of commits whose author is artifact.owner and whose author is artifact.team.lead is 1",
		},
		{},
	)
	array.slice(rows.a, 1, 4) == ["commits[]", "artifact.owner", "artifact.team.lead"]
	array.slice(rows.b, 1, 4) == ["commits[]", "artifact.owner", "artifact.team.lead"]
}

test_a_chain_whose_parent_is_written_wrong_is_written_wrong_too if {
	broken := {"artifact": {"from": "every trail.artifacts whose", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	_from_problems(_chain_report(_chain_doc, broken, {"c": "url exists"}, {})) == [{"name": "subjects.artifact.from", "value": ["doesn't parse"], "locations": []}]
	four := object.union(_chain_subjects, {"x": {"from": "every artifact.pull_requests"}, "y": {"from": "every x.reviews"}, "pull request": {"from": "every y.comments"}})
	_from_problems(_chain_report(_chain_doc, four, {"c": "url exists"}, {"name": "web"})) == [{"name": `subjects."pull request".from`, "value": ["a chain of more than three subjects isn't supported yet"], "locations": []}]
	three := object.union(_chain_subjects, {"x": {"from": "every artifact.pull_requests"}, "pull request": {"from": "every x.reviews"}})
	_from_problems(_chain_report(_chain_doc, three, {"c": "url exists"}, {"name": "web"})) == []
	grand_broken := {"artifact": {"from": "every trail.artifacts whose", "identified_by": "fingerprint"}, "x": {"from": "every artifact.pull_requests"}, "pull request": {"from": "every x.reviews", "identified_by": "url"}}
	_from_problems(_chain_report(_chain_doc, grand_broken, {"c": "url exists"}, {})) == [{"name": "subjects.artifact.from", "value": ["doesn't parse"], "locations": []}]
}

test_a_from_line_that_starts_at_input_reads_the_input_and_one_at_params_is_written_wrong if {
	doc := {"ds": [{"id": 5}]}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "every $input.ds whose id is 5", "identified_by": "id"}}, {"c": "id exists"}, {}))] == [[5, "satisfied"], [5, "satisfied"]]
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"d": {"from": "$input", "identified_by": "ds"}}, {"c": "ds exists"}, {}))] == [[[{"id": 5}], "satisfied"]]
	_from_problems(_from_report(doc, {"d": {"from": "$params.ds"}}, {"c": "id exists"}, {"ds": [{"id": 1}]})) == [{"name": "subjects.d.from", "value": ["a from reads the input, so it can't start at $params"], "locations": []}]
	both := ergo.report({"artifact": {"x": [{"id": 1}]}}, {"ergo_spec": ergo._spec, "subjects": {"artifact": null, "d": {"from": "every $input.artifact.x", "identified_by": "id"}}, "requirements": {"r": {"subject": "d", "checks": {"c": "id exists"}}}}, {})
	[r.cause | some r in both.results; r.check == "c"] == ["satisfied"]
}

test_a_from_line_can_narrow_a_subject_written_with_op if {
	subjects := {"defect": {"from": "defects whose status is \"open\"", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical"`}}
	_kept(_narrow_report(subjects, "critical defect")) == [1, 4]
}

test_a_chain_keeps_the_problems_of_a_check_written_wrong if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": `url is "x`}, {"name": "web"})
	[i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [["unclosed quote at column 8"]]
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

test_a_from_written_wrong_still_gets_an_entry_marked_invalid if {
	every from in ["???", "ds whose", "", 1, true, null, [true], [["a"]], [1.5]] {
		subjects := {"d": {"from": from, "identified_by": "id"}}
		_listed(subjects, "d").d.from == "<invalid from>"
	}
}

test_an_id_written_wrong_is_marked_invalid if {
	every id in ["???", 1, true] {
		_listed({"d": {"from": "ds", "identified_by": id}}, "d").d.identified_by == "<invalid identified_by>"
	}
}

test_a_requirement_that_names_a_subject_written_wrong_still_reports_its_name if {
	ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": 1}, "requirements": _listed_reqs("d")}, {}).requirements.r.subject == "d"
}

test_the_subjects_section_is_independent_of_the_order_the_policy_is_written_in if {
	first := {"round": {"from": "rounds", "identified_by": "id"}, "done": {"from": `round whose state is "done"`}, "old": {"from": "ds whose .a exists and whose b exists"}}
	reqs := {"x": {"subject": "done", "checks": {"c": "id exists"}}, "y": {"subject": "old", "checks": {"c": "id exists"}}}
	one := ergo.report({}, {"ergo_spec": ergo._spec, "subjects": first, "requirements": reqs}, {})
	two := ergo.report({}, {"ergo_spec": ergo._spec, "requirements": {"y": reqs.y, "x": reqs.x}, "subjects": {"old": {"from": "ds whose .a exists and whose b exists"}, "done": first.done, "round": first.round}}, {})
	json.marshal(one) == json.marshal(two)
	one.subjects.old.from == "ds whose .a exists and whose b exists"
}

test_a_part_in_the_long_form_works_like_one_written_as_a_line if {
	line := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1"}, {"b": {"x": 2}})
	long := _parts_report({"cov": {"from": "dd.b", "identified_by": "id"}}, {"c": "cov.x is 1"}, {"b": {"x": 2}})
	_parts_row(line, "c") == _parts_row(long, "c")
	_parts_row(line, "c").cause == "value"
}

test_a_for_line_alias_that_is_also_a_part_alias_is_written_wrong if {
	has := {"cov": "dd.b"}
	rep := _parts_report(has, {"c": {"for": "every dd.items as cov", "assert": "cov.x is 1"}}, {"items": [{"x": 1}]})
	_parts_problems(rep)["checks.c"] == ["cov can't be an alias: it's a part of round"]
	stopped(rep)
}

_parts_narrow := {
	"ergo_spec": ergo._spec,
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
	rep := ergo.report(_parts_rounds, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "good round", "checks": {"c": "cov.n is 2"}}}}, {})
	_parts_problems(rep)["subjects.\"good round\".has.cov"] == ["cov can't be an alias: it's a part of round"]
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
	problems["subjects.round.has.$dollar"] == ["a name can't start with $"]
	problems["subjects.round.has.\"with space\""] == ["invalid alias"]
	problems["subjects.round.has.item"] == ["invalid alias"]
	not "subjects.round.has.plain" in object.keys(problems)
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

test_a_part_with_no_alias_clash_works_when_another_subject_of_the_policy_is_written_wrong if {
	subjects := {
		"round": {"from": "rounds", "has": {"cov": "dd.b"}},
		"bad": {"from": "rounds", "has": 5},
	}
	policy := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "round", "checks": {"c": "cov.x is 1"}}}}
	rep := ergo.report({"rounds": [{"dd": {"b": {"x": 1}}}]}, policy, {})
	_parts_row(rep, "c").passed
	not "subjects.bad.has" in object.keys(_parts_problems(rep))
}

_swap_old_alias := {"cov": ["$cov"], "lst": ["$lst"], "uno": ["$uno"]}

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

test_a_chained_subject_that_starts_at_its_parents_part_shows_its_from_as_written_in_its_expressions if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	checks := rep.requirements.r.checks
	checks["$min_subjects"].expression == "count(matching(every artifact.pra.pull_requests)) >= 1"
	checks["$unique_ids"].expression == "count(repeated(ids(every artifact.pra.pull_requests))) == 0"
	deeper := object.union(_parts_chain.subjects, {"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url"}})
	policy := {"ergo_spec": ergo._spec, "subjects": deeper, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}
	ergo.report(_parts_chain_doc, policy, {"art": "web"}).requirements.r.checks["$min_subjects"].expression == "count(matching(every artifact.pra.pull_requests)) >= 1"
}

test_a_count_of_over_more_than_ten_steps_on_the_right_of_a_from_lines_whose_is_written_wrong if {
	_from_problems(_from_report({"things": []}, {"s": {"from": concat("", ["things whose n is count of ", _eleven])}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every and some over more than ten steps aren't supported yet"], "locations": []}]
	_from_problems(_from_report({"things": []}, {"s": {"from": concat("", ["things whose n is count of ", _ten])}}, {"c": "x exists"}, {})) == []
}

test_a_part_named_like_a_grandparent_is_written_wrong_as_a_subjects_name if {
	subjects := object.union(_three_subjects, {"commit": {"from": `every "pull request".commits`, "identified_by": "sha", "has": {"artifact": "x"}}})
	rep := ergo.report(_three_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "commit", "checks": {"c": "sha exists"}}}}, {})
	[i | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")] == [{"name": "subjects.commit.has.artifact", "value": ["artifact can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_written_value_that_isnt_a_time_is_written_wrong_in_a_whose_too if {
	_sentence_problems(`every xs.v whose t is before "soon" is true`) == [`"is before" takes a time or a number`]
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

test_a_for_line_picks_an_item_by_its_position_as_written if {
	_picked_author("first of commits", [3, 1, 2]) == "ada"
	_picked_author("item 2 of commits", [3, 1, 2]) == "grace"
	_picked_author("last of commits", [3, 1, 2]) == "linus"
	_picked_author("item 2 from last of commits", [3, 1, 2]) == "grace"
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

test_a_check_named_like_one_of_ergos_own_rows_is_written_wrong if {
	every name in ["$applies", "$min_subjects", "$unique_ids", "$well_formed"] {
		rep := reserved_check_rows(name)
		problem_inputs(rep) == [{"name": concat(".", ["checks", name]), "value": ["a name can't start with $"], "locations": []}]
		[r.passed | some r in rep.results] == [false]
	}
}

test_a_check_named_with_a_dollar_sign_that_ergo_never_adds_is_written_wrong_and_has_no_entry if {
	rep := reserved_check_rows("$other")
	problem_inputs(rep) == [{"name": "checks.$other", "value": ["a name can't start with $"], "locations": []}]
	object.keys(rep.requirements.s.checks) == {"$min_subjects", "$unique_ids", "$well_formed"}
}

test_a_from_line_that_starts_at_a_blank_subject_name_is_written_wrong_under_from if {
	every case in [[" ", `" " whose id is "a"`], [" ", `" ".kids`], ["", `"" whose id is "a"`], ["", `"".kids`]] {
		[name, from] := case
		subjects := {name: {"from": "things", "identified_by": "id"}, "b": {"from": from}}
		subject_problems(subjects, "b", {"things": [{"id": "a", "kids": [{"v": 1}]}]}) == [{"name": "subjects.b.from", "value": [concat("", [`"`, name, `" isn't a subject name`])], "locations": []}]
	}
}

listed_subjects(subjects, subject) := object.keys(ergo.report({}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": "v exists"}}}}, {}).subjects)

test_the_report_lists_every_subject_a_from_line_written_wrong_starts_at if {
	listed_subjects({"x": {"from": "y"}, "y": {"from": "z"}, "z": {"from": "x"}}, "x") == {"x", "y", "z"}
	listed_subjects({"p": {"from": "every q.x"}, "q": {"from": "every r.x"}, "r": {"from": "every p.x"}}, "p") == {"p", "q", "r"}
	listed_subjects({"b": {"from": "kid"}, "kid": {"from": "every b.kids"}}, "kid") == {"b", "kid"}
	listed_subjects({"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}, "t": {"from": "things"}}, "pc") == {"pa", "pb", "pc"}
	listed_subjects({" ": {"from": "things"}, "b": {"from": `every " ".kids`}}, "b") == {" ", "b"}
}

test_a_whose_with_plus_on_its_left_is_written_wrong if {
	inp := {"ts": [{"id": "t1", "p": 1, "q": 1, "xs": [{"p": 1, "q": 1, "v": 1}], "kids": [{"p": 1, "q": 1}]}]}
	every case in [
		[{"t": {"from": "ts whose p plus q is 2"}}, "t", "v exists", "subjects.t.from", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}, "kid": {"from": "every u.kids whose u.p plus q is 2"}}, "kid", "v exists", "subjects.kid.from", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", "every xs.v whose p plus q is 2 is 1", "checks.c", "doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", {"for": "every xs whose p plus q is 2 as x", "assert": "x.v is 1"}, "checks.c", "for: doesn't parse"],
		[{"u": {"from": "ts", "identified_by": "id"}}, "u", "count of xs whose p plus q is 2 is 1", "checks.c", "doesn't parse"],
	] {
		[subjects, subject, check, at, problem] := case
		rows := [r | some r in ergo.report(inp, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": check}}}}, {}).results]
		[r.check | some r in rows] == ["$well_formed"]
		{"name": at, "value": [problem], "locations": []} in rows[0].inputs
	}
}

_subject_has_no_problem(from, checks) if count([i | some i in _subject_report({"xs": []}, from, checks, {}).results[0].inputs; i.name == "checks.c"]) == 0

test_a_field_called_like_the_subject_is_written_with_a_dot_and_printed_with_one if {
	doc := {"xs": [{"id": "a", "s": 1}, {"id": "b", "s": 2}]}
	_subject_rows(doc, "every xs", ".s is 1", {}) == [
		[{"id": "a", "s": 1}, true, "satisfied", [{"name": ".s", "value": 1, "locations": ["/xs/0/s"]}]],
		[{"id": "b", "s": 2}, false, "value", [{"name": ".s", "value": 2, "locations": ["/xs/1/s"]}]],
	]
	[r[1] | some r in _subject_rows(doc, "every xs", "s is an object", {})] == [true, true]
	_subject_rows({"xs": [{"id": "a", "x": {"s": 1}}]}, "every xs", "x.s is 1", {}) == [[{"id": "a", "x": {"s": 1}}, true, "satisfied", [{"name": "x.s", "value": 1, "locations": ["/xs/0/x/s"]}]]]
	rep := _subject_report(doc, "every xs", {"c": ".s is 1 and s is an object"}, {})
	rep.requirements.r.checks.c.expression == ".s is 1 and s is an object"
}

test_the_subjects_name_followed_by_brackets_is_written_wrong_but_first_of_and_item_n_of_are_read if {
	_subject_problems("every xs", {"c": "s[0] is 1"}) == ["s[0]: nothing can follow s, which means the subject: for a field called s, write .s[0]"]
	_subject_problems("every xs", {"c": "s[1] is 1"}) == ["s[1]: nothing can follow s, which means the subject: for a field called s, write .s[1]"]
	_subject_problems("every xs", {"c": "every s[0] is 1"}) == ["s[0]: nothing can follow s, which means the subject: for a field called s, write .s[0]"]
	_subject_problems("every xs", {"c": "count of s[0] is 1"}) == ["s[0]: nothing can follow s, which means the subject: for a field called s, write .s[0]"]
	_subject_problems("every xs", {"c": "x is s[0]"}) == ["s[0]: nothing can follow s, which means the subject: for a field called s, write .s[0]"]
	_subject_problems("every xs", {"c": "s[0][1] is 1"}) == ["s[0][1]: nothing can follow s, which means the subject: for a field called s, write .s[0][1]"]
	_subject_has_no_problem("every xs", {"c": `"a b"[0] is 1`})
	_subject_has_no_problem("every xs", {"c": "first of s is 1"})
	_subject_has_no_problem("every xs", {"c": "item 2 of s is 1"})
	_subject_has_no_problem("every xs", {"c": ".s[0] is 1"})
}

test_a_written_wrong_subject_name_stops_the_requirement_with_only_its_well_formed_row if {
	rep := _subject_report({"xs": [1]}, "every xs", {"c": "s.name is 1"}, {})
	stopped(rep)
}

test_a_field_called_it_is_written_with_a_dot_when_the_subject_is_called_it if {
	doc := {"xs": [{"id": "a", "it": 1}]}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": {"it": {"from": "every xs"}}, "requirements": {"r": {"subject": "it", "checks": {"c": ".it is 1 and it is an object"}}}}, {})
	[[r.passed, r.cause] | some r in rep.results; r.check == "c"] == [[true, "satisfied"]]
}

test_a_for_alias_named_like_a_parent_subject_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}) == [["b can't be an alias: it's a subject's name"]]
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.id is \"b1\""}) == [["b can't be an alias: it's a subject's name"]]
	stopped(_clash_report({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}))
	_clash_rows({"x": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.x.z is 7"}) == []
}

test_a_for_alias_named_like_the_checks_own_subject_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as kid", "assert": "kid is an object"}) == [["kid can't be an alias: it's a subject's name"]]
}

test_a_for_alias_named_like_an_unrelated_subject_is_written_wrong if {
	extra := {"other": {"from": "bs", "identified_by": "id"}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as other", "assert": "other.v is 1"}) == [["other can't be an alias: it's a subject's name"]]
}

test_a_for_alias_named_like_a_part_of_a_parent_is_written_wrong if {
	_clash_problems({"x": "k1.k2.k3"}, {}, {"for": "every xs as x", "assert": "x.z is 7"}) == [["x can't be an alias: it's a part of b"]]
}

test_a_for_alias_named_like_a_part_of_the_own_subject_is_written_wrong if {
	extra := {"kid": {"from": "every b.kids", "identified_by": "id", "has": {"y": "xs"}}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.v is 1"}) == [["y can't be an alias: it's a part of kid"]]
}

test_a_long_parent_part_walked_from_a_for_alias_named_like_the_parent_is_written_wrong_for_the_clash_only if {
	has := {"p": "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10"}
	_clash_problems(has, {}, {"for": "every xs as y, every b.p.list as z", "assert": "z is 1"}) == [[_for_too_long]]
	_clash_problems(has, {}, {"for": "every xs as b, every b.p.list as z", "assert": "z is 1"}) == [["b can't be an alias: it's a subject's name"]]
	_clash_problems({"p": "k1.k2.k3.k4.k5.k6.k7.k8.k9"}, {}, {"for": "every xs as y, every b.p.list as z", "assert": "z is 1"}) == []
}

test_a_part_named_like_the_subject_it_belongs_to_is_written_wrong if {
	subjects := {"b": _clash_b, "kid": {"from": "every b.kids", "identified_by": "id", "has": {"kid": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.kid", "value": ["kid can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_the_parent_it_reads_from_is_written_wrong_as_a_subjects_name if {
	subjects := {"b": _clash_b, "kid": {"from": "every b.kids", "identified_by": "id", "has": {"b": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.b", "value": ["b can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_an_unrelated_subject_is_written_wrong if {
	subjects := {"b": _clash_b, "other": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids", "identified_by": "id", "has": {"other": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.other", "value": ["other can't be an alias: it's a subject's name"], "locations": []}]
}

test_a_part_named_like_a_part_of_a_parent_is_written_wrong if {
	subjects := {"b": _clash_b, "kid": {"from": "every b.kids", "identified_by": "id", "has": {"x": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.x", "value": ["x can't be an alias: it's a part of b"], "locations": []}]
}

test_a_part_named_like_a_part_kept_from_a_narrowed_subject_is_written_wrong if {
	subjects := {"b": _clash_b, "slim": {"from": "b whose id exists", "has": {"y": "xs"}}, "wider": {"from": "slim whose id exists", "has": {"y": "v"}}}
	_part_clash_problems_of(subjects, "wider") == [{"name": "subjects.wider.has.y", "value": ["y can't be an alias: it's a part of slim"], "locations": []}]
}

_clash3_doc := {"gps": [{"id": "g1", "cap": {"z": 1}, "mids": [{"id": "m1", "leaves": [{"id": "l1", "ys": [{"v": 1}], "zs": [{"w": 2}]}]}]}]}

_clash3_subjects(leaf_has) := {
	"gp": {"from": "gps", "identified_by": "id", "has": {"cap": "cap"}},
	"mid": {"from": "every gp.mids", "identified_by": "id"},
	"leaf": {"from": "every mid.leaves", "identified_by": "id", "has": leaf_has},
}

_clash3_report(leaf_has, check) := ergo.report(_clash3_doc, {"ergo_spec": ergo._spec, "subjects": _clash3_subjects(leaf_has), "requirements": {"r": {"subject": "leaf", "checks": {"c": check}}}}, {})

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

_each_id_problem := [{"name": "subjects.suite.identified_by", "value": ["not allowed with named by each of: the key is the id"], "locations": []}]

test_identified_by_is_written_wrong_on_every_form_of_a_from_line_listed_by_named_by_each_of if {
	every from in [
		"suites named by each of $params.names",
		"suites named by each of $params.names whose id exists",
		"top named by $params.g named by each of $params.names",
		"top[$params.g].suites named by each of $params.names",
		"artifact.suites named by each of $params.names",
		"artifact.suites named by each of $params.names whose id exists and whose id is 1",
	] {
		subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "suite": {"from": from, "identified_by": "id"}}
		rep := ergo.report({"suites": {"a": {"id": 1}}, "top": {"g": {"a": {"id": 1}}}, "artifacts": [{"id": 9, "suites": {"a": {"id": 1}}}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "suite", "checks": {"c": "id exists"}}}}, {"names": ["a"], "g": "g"})
		_from_problems(rep) == _each_id_problem
		[r.check | some r in rep.results] == ["$well_formed"]
	}
}

test_a_from_that_is_only_a_named_by_step_is_written_as_is_in_the_added_expressions if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "every $input named by $params.k"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}
	rep := ergo.report({"a": [{"id": 1}]}, policy, {"k": "a"})
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(every $input named by $params.k)) >= 1"
	rep.requirements.r.checks["$unique_ids"].expression == "count(repeated(ids(every $input named by $params.k))) == 0"
}

test_a_from_that_is_several_named_by_steps_or_a_named_by_with_a_position_is_written_as_it_was if {
	subjects := {"s": {"from": "every $input named by $params.k named by $params.j"}}
	rep := ergo.report({"a": {"b": [{"id": 1}]}}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}, {"k": "a", "j": "b"})
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(every $input named by $params.k named by $params.j)) >= 1"
	rep2 := ergo.report({"a": [{"id": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "$input named by $params.k[0]"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}, {"k": ["a"]})
	rep2.requirements.r.checks["$min_subjects"].expression == "count(matching(item 1 of $input named by $params.k)) >= 1"
	rep3 := ergo.report({"a": [{"id": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "every $input named by $params.k.x"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}}, {"k": {"x": "a"}})
	rep3.requirements.r.checks["$min_subjects"].expression == "count(matching(every $input named by $params.k.x)) >= 1"
}

test_a_requirement_called_policy_is_written_wrong_and_leaves_no_policy_requirement_of_its_own if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs"}}, "requirements": {"$policy": {"subject": "s", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	object.keys(rep.requirements) == {"$policy"}
	rep.requirements["$policy"].subject == "s"
	[i.value | some i in rows_for(rep, "$policy", "$well_formed")[0].inputs; i.name == "requirement name"] == [["a name can't start with $"]]
}

test_a_name_that_starts_with_a_dollar_sign_is_written_wrong_wherever_it_stands if {
	wrong := ["a name can't start with $"]
	policy := {"ergo_spec": ergo._spec, "subjects": {"$s": {"from": "xs"}, "t": {"from": "xs", "has": {"$p": "ys"}}}, "requirements": {
		"$r": {"subject": "t", "checks": {"c": "x exists"}},
		"q": {"subject": "$s", "checks": {"c": "x exists"}},
		"o": {"subject": "t", "checks": {"c": {"any_of": {"$o": "x exists", "p": "x is 1"}}}},
		"k": {"subject": "t", "checks": {"$k": "x exists"}},
		"ok": {"subject": "t", "checks": {"a$b": "x exists"}},
	}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	[i.value | some i in rows_for(rep, "$r", "$well_formed")[0].inputs; i.name == "requirement name"] == [wrong]
	[i.value | some i in rows_for(rep, "q", "$well_formed")[0].inputs; i.name == "subjects.$s"] == [wrong]
	[i.value | some i in rows_for(rep, "o", "$well_formed")[0].inputs; i.name == "checks.c"] == [["option $o: a name can't start with $"]]
	[i.value | some i in rows_for(rep, "k", "$well_formed")[0].inputs; i.name == "checks.$k"] == [wrong]
	[i.value | some i in rows_for(rep, "k", "$well_formed")[0].inputs; i.name == "subjects.t.has.$p"] == [wrong]
	[i.name | some i in rows_for(rep, "ok", "$well_formed")[0].inputs; startswith(i.name, "checks.")] == []
}

test_an_empty_name_is_written_wrong_wherever_it_stands if {
	wrong := ["a name can't be empty"]
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "xs", "has": {"": "ys"}}}, "requirements": {
		"": {"subject": "t", "checks": {"c": "x exists"}},
		"o": {"subject": "t", "checks": {"c": {"any_of": {"": "x exists", "p": "x is 1"}}}},
		"k": {"subject": "t", "checks": {"": "x exists"}},
	}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	[i.value | some i in rows_for(rep, "", "$well_formed")[0].inputs; i.name == "requirement name"] == [wrong]
	[i.value | some i in rows_for(rep, "o", "$well_formed")[0].inputs; i.name == "checks.c"] == [["option : a name can't be empty"]]
	[i.value | some i in rows_for(rep, "k", "$well_formed")[0].inputs; i.name == "checks.\"\""] == [wrong]
	[i.value | some i in rows_for(rep, "k", "$well_formed")[0].inputs; i.name == "subjects.t.has.\"\""] == [wrong]
}

test_a_name_with_spaces_inside_or_a_full_width_dollar_sign_is_written_correctly if {
	every name in ["x y", "\uff04x", "a$b", "x\ud83d\ude00"] {
		policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs"}}, "requirements": {name: {"subject": "s", "checks": {name: "x exists"}}}}
		rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
		[i.name | some i in rows_for(rep, name, "$well_formed")[0].inputs; i.name != "count(checks)"; i.name != "require"] == []
	}
}

test_a_contains_ref_that_meets_a_list_is_in_refs_as_written if {
	doc := {"r": [{"n": "a"}], "things": [{"id": "s", "items": [{"tags": ["a"]}]}]}
	every check in ["tags contains $input.r.n", "count of items whose tags contains $input.r.n is 1", "every items whose tags contains $input.r.n exists"] {
		rep := ergo.report(doc, _list_key_policy({"from": "things", "identified_by": "id"}, check), {})
		rep.requirements.r.checks.c["$refs"] == [{"name": "$input.r.n", "value": null, "locations": ["/r"]}]
	}
	keyed := ergo.report({"m": {"x": {"v": 1}}, "a": [{"k": "x"}]}, _list_key_policy({"from": "$input.m named by each of $input.a.k"}, "v is 1"), {})
	keyed.requirements.r.checks["$min_subjects"]["$refs"] == [{"name": "$input.a.k", "value": null, "locations": ["/a"]}]
}

test_named_by_each_of_a_field_or_a_subject_is_written_wrong_whatever_the_parent_holds if {
	problem := [{"name": "subjects.k.from", "value": ["named by each of takes a list from $params or $input, so it can't start at a field or a subject"], "locations": []}]
	some line in ["t named by each of t.keys", "t named by each of keys", "t named by each of .keys", "t named by each of t", "things named by each of t.keys", "t named by each of k.keys"]
	some doc in [{"things": [{"id": "a", "keys": ["p"], "p": {"x": 1}}]}, {"things": [{"id": "a"}]}, {"things": [{"id": "a", "keys": null}]}, {"things": [{"id": "a", "keys": 3}]}, {"things": []}, {"things": null}, {}]
	rep := _each_start_report(doc, line)
	_from_problems(rep) == problem
	[r.check | some r in rep.results] == ["$well_formed"]
}
