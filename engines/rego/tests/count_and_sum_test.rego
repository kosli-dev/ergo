package ergo_test

import data.ergo
import rego.v1

test_min_subjects_counts_subjects_after_the_applies_to_filter if {
	both := {"s": object.union(min_subjects_req(2).s, {"from": whose_line("items", merged_only)})}
	rep := report(two_states, both)
	rows_for(rep, "s", "$min_subjects")[0].passed == false
}

test_min_subjects_above_zero_keeps_the_count if {
	def := report({"items": []}, min_subjects_req(1)).requirements.s.checks["$min_subjects"]
	def.description == "The in-scope thing count is at least 1"
	def.expression == "count(matching(items)) >= 1"
}

test_unique_ids_counts_two_subjects_without_an_id_as_sharing_the_id_null if {
	unique_ids_row({"repos": [{"owner": "bob"}, {"owner": "carol"}]}, owner_req) == [[{"name": "repeated repo ids", "value": [null], "locations": ["/repos/0", "/repos/1"]}], false, "value"]
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

test_a_null_description_or_meta_counts_as_none_since_an_empty_yaml_field_reads_as_null if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"description": null, "meta": null, "checks": {"c": {"assert": "id exists", "description": null, "meta": null}}})})
	rows_for(rep, "s", "$well_formed")[0].passed == true
	[rep.requirements.s.description, rep.requirements.s.meta] == ["", {}]
	[rep.requirements.s.checks.c.description, rep.requirements.s.checks.c.meta] == ["", {}]
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

test_min_subjects_row_labels_the_count_it_actually_reports if {
	scoped := {"s": object.union(min_subjects_req(1).s, {"from": whose_line("items", merged_only)})}
	rep := report(two_states, scoped)
	row := rows_for(rep, "s", "$min_subjects")[0]
	row.inputs[0].value == 1
	row.inputs[0].name != "count(items)"
}

test_min_subjects_lists_only_the_count_when_the_input_and_params_are_json if {
	rows_for(ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), {"allowed": ["MIT"]}), "s", "$min_subjects")[0].inputs == [{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]}]
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

test_a_bare_params_after_named_by_does_not_hide_a_within_with_no_number_or_two_quantifiers if {
	_sentence_problems(`x named by $params is 1 within`) == [`"within" needs a number after it`]
	_sentence_problems(`every a every b named by $params exists`) == ["two quantifiers in one sentence: put them on a for line"]
}

test_an_option_of_an_any_of_can_hold_every_some_and_counts if {
	check := {"any_of": {"none": "count of xs is 0", "all_ok": "every xs.ok is true", "one": "some xs.n is 3"}}
	r := ergo.report({"things": [{"id": "a", "xs": []}, {"id": "b", "xs": [{"ok": true}]}, {"id": "c", "xs": [{"ok": false, "n": 3}]}, {"id": "d", "xs": [{"ok": false, "n": 2}]}, {"id": "e"}]}, _sentence_policy({"c": check}), {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "satisfied"], ["d", "value"], ["e", "absent"]]
	r.requirements.s.checks.c.expression == "one of: all_ok(every xs.ok is true) | none(count of xs is 0) | one(some xs.n is 3)"
}

test_a_position_and_a_sum_after_plus_on_the_right_and_a_count_in_a_picked_items_whose_are_held_to_ten_steps if {
	_reads("n is count of first of k1.k2.k3.k4.k5.k6.k7.k8.k9")
	_sentence_problems(concat("", ["n is count of first of ", _ten])) == _too_long
	_reads("n is count of xs plus sum of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10")
	_sentence_problems(concat("", ["n is count of xs plus sum of ", _eleven])) == _too_long
	_reads({"for": "first of xs whose n is count of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10 as x", "assert": "x.n is 1"})
	_sentence_problems({"for": concat("", ["first of xs whose n is count of ", _eleven, " as x"]), "assert": "x.n is 1"}) == [concat("", ["for: ", p]) | some p in _too_long]
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

test_a_count_or_sum_that_starts_at_a_part_name_on_the_right_of_a_whose_reads_the_part_so_its_path_is_counted if {
	doc := {"things": [object.union({"id": "a", "xs": [{"n": 1, "v": 1, "x": {"z": [1, 1, 1]}}, {"n": 3, "v": 2, "x": {"z": [1, 1, 1]}}]}, _k9({"z": [1]}))]}
	_part_walk_rows({"x": _nine}, {"c": {"for": "every xs whose n is count of x.z as y", "assert": "y.v is 1"}}, doc) == [["a", "c", "satisfied"]]
	_part_walk_rows({"x": _nine}, {"c": {"for": "every xs whose n is count of .x.z as y", "assert": "y.v is 1"}}, doc) == [["a", "c", "value"]]
	_part_walk_rows({"x": _nine}, {"c": "count of xs whose count of x.z is 3 is 2"}, doc) == [["a", "c", "satisfied"]]
	has := {"x": _ten}
	_part_walk_problems(has, "every xs.v whose n is count of x.z is 1") == _too_long
	_part_walk_problems(has, "some xs whose n is at most sum of x.z is not empty") == _too_long
	_part_walk_problems(has, "count of xs whose n is count of x.z is 1") == _too_long
	_part_walk_reads({"x": _nine}, "every xs.v whose n is count of x.z is 1")
	_part_walk_reads({"x": _nine}, "some xs whose n is at most sum of x.z is not empty")
	_part_walk_reads({"x": _nine}, "count of xs whose n is count of x.z is 1")
	_part_walk_reads(has, "every xs.v whose n is count of .x.z is 1")
	_part_walk_reads(has, "every xs.v whose count of x.z is 1 is 1")
	_part_walk_reads(has, "count of xs whose count of x.z is 1 is 1")
	_part_walk_reads({"x": _ten}, "n is 1 and x.z is 1")
}

test_a_plus_or_an_elapsed_time_on_the_right_of_a_whose_reads_the_part_too if {
	item := {"n": 1, "v": 1, "x": {"z": [1, 1, 1], "zz": 5, "a": "2026-01-01", "b": "2026-01-03"}}
	doc := {"things": [{"id": "a", "p": {"z": [1], "zz": 0, "a": "2026-01-01", "b": "2026-01-02"}, "xs": [item]}]}
	checks := {
		"plus_number": {"for": "every xs whose n is count of x.z plus 0 as y", "assert": "y.v is 1"},
		"plus_path": {"for": "every xs whose n is x.zz plus count of x.z as y", "assert": "y.v is 1"},
		"elapsed": {"for": "every xs whose n is days elapsed from x.a to x.b as y", "assert": "y.v is 1"},
		"dot_plus_path": {"for": "every xs whose n is .x.zz plus count of .x.z as y", "assert": "y.v is 1"},
	}
	_part_walk_rows({"x": "p"}, checks, doc) == [["a", "dot_plus_path", "value"], ["a", "elapsed", "satisfied"], ["a", "plus_number", "satisfied"], ["a", "plus_path", "satisfied"]]
}

_tag_of(report, check, name) := [object.get(i, "part", null) | some r in report.results; r.check == check; some i in r.inputs; i.name == name][0]

test_a_count_or_sum_carries_a_part_tag_only_when_its_list_is_read_from_the_part if {
	policy := _part_walk_policy({"pa": "pa"}, {
		"on_items": "count of items whose w is pa.w is 1",
		"on_part": "count of pa.items whose w is pa.w is 1",
		"sum_on_part": "sum of pa.items.n that is 5 is 5",
	})
	doc := {"things": [{"id": "a", "items": [{"w": 1, "n": 2}, {"w": 2, "n": 3}], "pa": {"w": 2, "items": [{"w": 2, "n": 5}]}}]}
	report := ergo.report(doc, policy, {})
	_tag_of(report, "on_items", "count of items whose w equals pa.w") == null
	_tag_of(report, "on_items", "pa.w") == {"id": null, "name": "pa"}
	_tag_of(report, "on_part", "count of pa.items whose w equals pa.w") == {"id": null, "name": "pa"}
	_tag_of(report, "sum_on_part", "sum of pa.items.n that is 5") == {"id": null, "name": "pa"}
}

test_a_part_in_an_option_of_an_any_of_counts_the_parts_path if {
	has := {"x": _ten}
	_part_walk_problems(has, {"any_of": {"a": "every x.z is 1", "b": "n is 1"}}) == ["option a: every and some over more than ten steps aren't supported yet"]
	_part_walk_reads({"x": _nine}, {"any_of": {"a": "every x.z is 1", "b": "n is 1"}})
}

test_count_of_counts_the_items_left_in_and_shows_them_beside_the_count if {
	_tally_rows(`count of findings whose source is "claude" equals claude_found`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `count of findings whose source is "claude"`, "value": 2, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "findings[]", "value": _review.findings, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
	]]]
}

test_sum_of_adds_up_the_field_across_the_items_left_in if {
	_tally_rows(`sum of stages.usd equals total_usd within 0.01`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `sum of stages.usd`, "value": 0.75, "locations": ["/things/0/stages/0/usd", "/things/0/stages/1/usd", "/things/0/stages/2/usd"]},
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

_not_within_cause(x, y, w) := cause if {
	rows := [row[1] | some row in _tally_rows(concat("", ["x does not equal y within ", w]), [{"id": 1, "x": x, "y": y}], {})]
	cause := rows[0]
}

test_a_gap_is_not_within_when_it_is_further_than_the_number_on_both_sides_of_the_boundary if {
	_not_within_cause(12345678901234567890.5, 12345678901234567890.4, "0.1") == "value"
	_not_within_cause(12345678901234567890.5, 12345678901234567890.4, "0.09") == "satisfied"
	_not_within_cause(0.3, 0.1, "0.2") == "value"
	_not_within_cause(0.3, 0.1, "0.19") == "satisfied"
	_not_within_cause(1, 5, "1") == "satisfied"
	_not_within_cause(-1, 1, "1") == "satisfied"
}

test_a_gap_that_cannot_be_worked_out_is_unusable_for_not_within_as_well if {
	_not_within_cause(1e5000, 1, "1") == "unusable"
	_not_within_cause(1, 1e5000, "1") == "unusable"
	_not_within_cause(1e4096, 1, "1") == "satisfied"
	_not_within_cause(1e4096, 1e4096, "1") == "value"
}

test_within_reads_numbers_opa_counts_as_equal_by_their_digits if {
	_within_cause(1234567890.1209567990, 1234567889.1209567890, "1") == "value"
	_within_cause(1234567890.1209567890, 1234567889.1209567890, "1.0") == "satisfied"
	_within_cause(123964818.71664440535747000531389400, 123964818.7166444053574700053138940000000000000002, "1e-40") == "value"
	_within_cause(123964818.71664440535747000531389400, 123964818.7166444053574700053138940000000000000002, "2e-40") == "satisfied"
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
	_within_cause(99999999999999999999, -1, "1e20") == "satisfied"
	_within_cause(99999999999999999999, -2, "1e20") == "value"
	_within_cause(-1, 99999999999999999999, "1e20") == "satisfied"
	_within_cause(9999999999999999999999999999, -1, "1e28") == "satisfied"
	_within_cause(9999999999999999999999999999, -2, "1e28") == "value"
	_within_cause(10000000000000000000000000000, 1, "1e28") == "satisfied"
	_within_cause(10000000000000000000000000001, 0, "1e28") == "value"
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
	_within_cause(0, -100000000000000000001, "1e20") == "value"
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

test_a_count_whose_named_by_cant_be_read_fails_with_its_cause if {
	_tally_rows("count of m named by $params.k is 2", [{"id": 1, "m": {"a": [1, 2]}}], {}) == [[1, "absent", [{"name": "count of m named by $params.k", "value": null, "locations": []}, {"name": "m named by $params.k", "value": [], "locations": []}]]]
}

_sum_whose_cause(check, items) := [row[1] | some row in _tally_rows(check, [{"id": "t", "items": items}], {})]

test_a_sum_whose_worst_cause_wins_between_its_undecided_values if {
	_sum_whose_cause(`sum of items.x that is at least 1 is 1`, [{}, {"x": null}]) == ["absent"]
	_sum_whose_cause(`sum of items.x that is at least 1 is 1`, [{"x": null}, {"x": "ab"}]) == ["unusable"]
	_sum_whose_cause(`sum of items.x that is at least 1 is 1`, [{"x": null}, {"x": 1}]) == ["null"]
}

test_a_sum_whose_that_reads_each_value_adds_the_values_it_keeps if {
	_sum_whose_cause(`sum of items.x that is at least 1 is 3`, [{"x": 1}, {"x": 0}, {"x": 2}]) == ["satisfied"]
	_sum_whose_cause(`sum of items.x that is at least 1 is 4`, [{"x": 1}, {"x": 0}, {"x": 2}]) == ["value"]
	_sum_whose_cause(`sum of items.x that is at least 1 is 3`, [{"x": 3}, {"x": "ab"}]) == ["unusable"]
}

test_a_count_whose_undecided_item_fails_with_its_cause if {
	_sum_whose_cause(`count of items whose k is "a" is 1`, [{"x": "ab", "k": null}]) == ["null"]
	_sum_whose_cause(`count of items whose k is "a" is 1`, [{"x": "ab"}]) == ["absent"]
	_sum_whose_cause(`count of items whose k is "a" is 1`, [{"x": null, "k": null}, {"x": 1, "k": "a"}]) == ["null"]
}

test_a_count_fails_on_a_value_it_cant_read_unless_whose_left_its_item_out if {
	[row[1] | some row in _tally_rows("count of xs.t is 1", [{"id": 1, "xs": ["s"]}], {})] == ["not_an_object"]
	[row[1] | some row in _tally_rows("count of xs whose k is 1 is 1", [{"id": 1, "xs": [{"k": 1, "t": 0}, {"k": 2}]}], {})] == ["satisfied"]
	[row[1] | some row in _tally_rows("count of xs.t that is 0 is 1", [{"id": 1, "xs": [{"k": 1, "t": 0}, {"k": 2}]}], {})] == ["absent"]
}

test_plus_with_a_whose_on_its_last_count if {
	_tally_rows(`claude_found plus count of findings whose source is "gpt" is at least 3`, [_review], {}) == [["pr-7", "satisfied", [
		{"name": `claude_found plus count of findings whose source is "gpt"`, "value": 3, "locations": ["/things/0/claude_found", "/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "claude_found", "value": 2, "locations": ["/things/0/claude_found"]},
		{"name": `count of findings whose source is "gpt"`, "value": 1, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
		{"name": "findings[]", "value": _review.findings, "locations": ["/things/0/findings/0", "/things/0/findings/1", "/things/0/findings/2"]},
	]]]
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

test_a_count_whose_named_by_reads_the_item_lists_the_part_before_the_name_and_not_the_path_it_names if {
	_atts_rows({"c": "count of commits whose author is artifact.atts named by k.owner is 1"}, {}) == {"c": [
		"count of commits whose author equals artifact.atts named by k.owner",
		"commits[]",
		"artifact.atts",
	]}
}

test_named_by_a_field_works_with_exists_every_count_and_plus if {
	doc := {"things": [{"id": 1, "k": "a", "xs": {"a": [1], "b": [2, 3]}}]}
	_sentence_rows({"c": "xs named by k exists"}, doc, {}) == [["c", true, "satisfied", [{"name": "xs named by k", "value": [1], "locations": ["/things/0/xs/a"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "every xs named by k is 1"}, doc, {}) == [["c", true, "satisfied", [{"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "count of xs named by k is 1"}, doc, {}) == [["c", true, "satisfied", [{"name": "count of xs named by k", "value": 1, "locations": ["/things/0/xs/a/0"]}, {"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": "count of xs.b plus $params.extra named by k is 3"}, doc, {"extra": {"a": 1}}) == [["c", true, "satisfied", [{"name": "count of xs.b plus $params.extra named by k", "value": 3, "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1", "$params:/extra/a"]}, {"name": "count of xs.b", "value": 2, "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1"]}, {"name": "xs.b[]", "value": [2, 3], "locations": ["/things/0/xs/b/0", "/things/0/xs/b/1"]}, {"name": "$params.extra named by k", "value": 1, "locations": ["$params:/extra/a"]}, {"name": "k", "value": "a", "locations": ["/things/0/k"]}]]]
	_sentence_rows({"c": {"assert": ["xs named by k exists", "every xs named by k is 1"]}}, doc, {}) == [["c", true, "satisfied", [{"name": "k", "value": "a", "locations": ["/things/0/k"]}, {"name": "xs named by k", "value": [1], "locations": ["/things/0/xs/a"]}, {"name": "xs named by k[]", "value": [1], "locations": ["/things/0/xs/a/0"]}]]]
}

test_a_count_through_a_for_name_lists_its_list_and_not_its_number_since_that_changes_with_each_item if {
	doc := {"things": [{"id": 1, "ps": ["a"], "ys": [{"m": {"a": 1}}]}]}
	[[r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy({"c": {"for": "every ps as p", "assert": "count of ys whose m named by p is 1 is 1"}}), {}).results; r.check == "c"] == [["satisfied", [
		{"name": "ps[]", "value": ["a"], "locations": ["/things/0/ps/0"]},
		{"name": "ys[]", "value": [{"m": {"a": 1}}], "locations": ["/things/0/ys/0"]},
	]]]
}

test_a_count_through_a_for_name_lists_the_part_before_the_name_and_not_its_number_or_its_items if {
	things := [{"id": 1, "ks": ["a", "b"], "m": {"a": [1], "b": [2]}}]
	_for_rows({"for": "every ks as k", "assert": "count of m named by k is at least 1"}, things, {})[0][3] == [
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/things/0/ks/0", "/things/0/ks/1"]},
		{"name": "m", "value": {"a": [1], "b": [2]}, "locations": ["/things/0/m"]},
	]
}

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

test_elapsed_counts_seconds_for_two_numbers_and_gives_fractions_and_zero if {
	_elapsed_first("days elapsed from p to q is 1.5", [{"id": 1, "p": 100, "q": 129700}], {}) == [true, "satisfied"]
	_elapsed_first("hours elapsed from p to q is 0", [{"id": 1, "p": 100, "q": 100}], {}) == [true, "satisfied"]
	_elapsed_first("days elapsed from p to q is 0", [{"id": 1, "p": "2026-01-01T00:00:00Z", "q": "2026-01-01T01:00:00+01:00"}], {}) == [true, "satisfied"]
	_elapsed_first("seconds elapsed from p to q is 0.5", [{"id": 1, "p": "2026-01-01T00:00:00Z", "q": "2026-01-01T00:00:00.5Z"}], {}) == [true, "satisfied"]
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

test_months_and_years_are_not_elapsed_phrases if {
	_sentence_problems("months elapsed from p to q is 1") == ["doesn't parse"]
	_sentence_problems("years elapsed from p to q is 1") == ["doesn't parse"]
}

test_an_elapsed_time_in_a_whose_decides_each_item_of_a_count_and_an_every if {
	doc := [{"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, {"n": 2, "p": 0, "q": 86400}, {"n": 4, "p": 0, "q": 172800}]}]
	_elapsed_rows("count of xs whose days elapsed from p to q is 1 is 2", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose n is days elapsed from p to q is 1", doc, {})[0][1] == true
	_elapsed_rows("every xs whose days elapsed from p to q is 1 and whose n is less than 3 exists", doc, {})[0][1] == true
	_elapsed_rows("every xs whose days elapsed from p to q is 3 exists", doc, {})[0][1] == false
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
		_elapsed_cause("every xs whose days elapsed from p to q is 1 exists", {"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, item]}, {}) == state_cause[state]
	}
}

state_cause := {"absent": "absent", "null": "null", "mixed": "unusable", "text": "unusable"}

test_a_part_refused_for_its_value_still_counts_as_the_part_in_the_filter_expression if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {
			"round": {"from": "rounds", "identified_by": "id"},
			"item": {"from": "every round.items whose .cov is 1", "identified_by": "id", "has": {"cov": 5}},
		},
		"requirements": {"r": {"subject": "item", "checks": {"c": ".cov is 1"}}},
	}
	rep := ergo.report({"rounds": [{"id": "r1", "items": [{"id": "i1", "cov": 1}]}]}, policy, {})
	rep.requirements.r.checks["$applies"].expression == ".cov is 1"
}

test_a_part_on_the_right_of_a_whose_in_a_count_or_a_sum_is_the_part if {
	rep := _parts_report(
		{"cov": "dd.b"}, {
			"count": "count of dd.items whose x equals cov.x is 1",
			"sum": "sum of dd.items.x that equals cov.x is 5",
		},
		{"b": {"x": 5}, "items": [{"x": 5}, {"x": 6}]},
	)
	_parts_row(rep, "count").passed
	_parts_row(rep, "sum").passed
}

test_a_count_of_a_part_after_that_reads_the_part_when_the_items_are_not_objects if {
	has := {"cov": "dd.b"}
	checks := {
		"c": "count of dd.xs that is count of cov.z is 1",
		"e": "every dd.xs that is count of cov.z is 2",
		"s": "some dd.xs that is count of cov.z is 2",
		"n": "count of dd.xs that is count of round.dd.b.z is 1",
	}
	rep := _parts_report(has, checks, {"b": {"z": [1, 2]}, "xs": [2, 5]})
	every c in ["c", "e", "s", "n"] {
		_parts_row(rep, c).cause == "satisfied"
	}
}

test_a_count_of_a_missing_part_after_that_fails_on_the_part_not_the_items if {
	has := {"cov": "dd.b"}
	checks := {
		"c": "count of dd.xs that is count of cov.z is 1",
		"e": "every dd.xs that is count of cov.z is 2",
		"n": "count of dd.xs that is count of round.dd.b.z is 1",
	}
	rep := _parts_report(has, checks, {"xs": [2, 5]})
	_parts_row(rep, "c").cause == "absent"
	_parts_row(rep, "c").message == "cov.z is missing"
	_parts_row(rep, "e").cause == "absent"
	_parts_row(rep, "n").message == "round.dd.b.z is missing"
}

test_a_between_after_a_count_reads_the_items_its_whose_keeps if {
	doc := {"things": [{"id": "a", "xs": [{"k": 1}, {"k": 1}, {"k": 2}]}, {"id": "b", "xs": [{"k": 1}, {"k": 1}, {"k": 1}, {"k": 1}]}]}
	rows := _sentence_rows({"c": "count of xs whose k is 1 is between 1 and 3"}, doc, {})
	[[r[0], r[1], r[2]] | some r in rows] == [["c", true, "satisfied"], ["c", false, "value"]]
}

test_a_between_after_a_count_goes_with_and_in_a_list_of_assertions if {
	doc := {"things": [{"id": "a", "xs": [1, 2], "n": 1}, {"id": "b", "xs": [1, 2], "n": 2}]}
	rows := ergo.report(doc, _sentence_policy({"c": {"assert": ["count of xs is between 1 and 2", "n is 1"]}}), {}).results
	[[r.subject.id, r.passed, r.cause] | some r in rows; r.check == "c"] == [["a", true, "satisfied"], ["b", false, "value"]]
}

test_a_count_in_the_whose_of_a_count_leaves_out_the_items_it_fails if {
	doc := [{"id": 1, "xs": [{"n": 2, "ys": [1, 2]}, {"n": 3, "ys": [1]}, {"n": 4, "ys": [1, 2, 3]}]}]
	_elapsed_rows("count of xs whose count of ys is at least 2 is 2", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose n is count of ys is 1", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose count of ys is at least 2 is 3", doc, {})[0][1] == false
}

test_a_count_in_the_whose_of_a_count_fails_closed_when_an_item_list_cant_be_counted if {
	every list, cause in {"missing": "absent", "null": "null", "text": "unusable"} {
		item := object.union({"n": 1}, {k: v | list != "missing"; k := "ys"; v := {"null": null, "text": "abc"}[list]})
		_elapsed_cause("count of xs whose count of ys is at least 2 is 1", {"id": 1, "xs": [{"n": 1, "ys": [1, 2]}, item]}, {}) == cause
	}
	_elapsed_cause("count of xs whose count of ys.z is at least 1 is 1", {"id": 1, "xs": [{"ys": [{"z": [1]}]}, "a"]}, {}) == "not_an_object"
}

test_a_count_in_the_whose_of_a_count_counts_through_a_list_it_walks if {
	doc := [{"id": 1, "xs": [{"ys": [{"z": [1, 2]}, {"z": [1]}]}, {"ys": [{"z": [1]}]}]}]
	_elapsed_rows("count of xs whose count of ys.z is 3 is 1", doc, {})[0][1] == true
	_elapsed_rows("count of xs whose count of ys.z is 3 is 2", doc, {})[0][1] == false
}

_named_count_in_whose(xs) := [[r.passed, r.cause] | some r in ergo.report({"things": [{"id": "t", "xs": xs}]}, _sentence_policy({"c": "count of xs whose count of $params.lists named by kind is 1 is 1"}), {"lists": {"a": [1]}}).results; r.check == "c"]

test_a_count_named_by_a_missing_or_wrong_key_in_a_whose_fails_closed if {
	_named_count_in_whose([{"kind": "a"}]) == [[true, "satisfied"]]
	_named_count_in_whose([{}]) == [[false, "absent"]]
	_named_count_in_whose([{"kind": 5}]) == [[false, "unusable"]]
	_named_count_in_whose([{"kind": "b"}]) == [[false, "absent"]]
}

test_a_failed_line_that_counts_through_an_alias_lists_the_number_then_the_list if {
	rows := _for_rows_full({"for": "every commits as commit", "assert": "count of commit.files is at least 2"}, [{"id": 1, "commits": [{"files": ["a", "b"]}, {"files": ["c"]}]}], {})
	rows[0][2][0].failed_assertions[0].inputs == [
		{"name": "count of commit.files", "value": 1, "locations": ["/things/0/commits/1/files/0"]},
		{"name": "commit.files[]", "value": ["c"], "locations": ["/things/0/commits/1/files/0"]},
	]
}

test_a_ref_step_adds_the_key_it_read_and_stops_before_it_when_it_cannot_be_read if {
	check := {"c": ".a named by $params.i exists"}
	doc := {"things": [{"id": "t1", "a": [1, 2]}]}
	_located_rows(check, {"things": [{"id": "t1", "a": {"x": 2}}]}, {"i": "x"}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a/x"]}]]]
	_located_rows(check, doc, {"i": "y"}) == [["t1", "c", [{"name": ".a named by $params.i", "locations": ["/things/0/a"]}]]]
	every i in [1, 2, -1, 1.5, "1", null, [1]] {
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

test_subject_walks_and_counts_a_subject_that_is_a_list if {
	doc := {"xs": [["a", "b"], [1, 2], [1, "a"], [], null, "s"]}
	rows := _subject_rows(doc, "every xs", "every s is a string", {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "value"], [false, "value"], [false, "value"], [false, "null"], [false, "unusable"]]
	rows[1][3] == [{"name": "s[]", "value": [1, 2], "locations": ["/xs/1/0", "/xs/1/1"]}]
	_subject_report(doc, "every xs", {"c": "every s is a string"}, {}).results[4].failed_items == [
		{"cause": "value", "item": "item 1 of s", "path": "item 1 of s", "value": 1, "locations": ["/xs/1/0"]},
		{"cause": "value", "item": "item 2 of s", "path": "item 2 of s", "value": 2, "locations": ["/xs/1/1"]},
	]
	[[r[1], r[2]] | some r in _subject_rows(doc, "every xs", "some s is a string", {})] == [[true, "satisfied"], [false, "value"], [true, "satisfied"], [false, "value"], [false, "null"], [false, "unusable"]]
	counts := _subject_rows(doc, "every xs", "count of s is 2", {})
	[[r[1], r[2]] | some r in counts] == [[true, "satisfied"], [true, "satisfied"], [true, "satisfied"], [false, "value"], [false, "null"], [false, "unusable"]]
	counts[1][3] == [{"name": "count of s", "value": 2, "locations": ["/xs/1/0", "/xs/1/1"]}, {"name": "s[]", "value": [1, 2], "locations": ["/xs/1/0", "/xs/1/1"]}]
	sums := _subject_rows(doc, "every xs", "sum of s is 3", {})
	[[r[1], r[2]] | some r in sums] == [[false, "unusable"], [true, "satisfied"], [false, "unusable"], [false, "value"], [false, "null"], [false, "unusable"]]
}

test_a_walk_through_a_for_alias_fails_like_a_count_when_the_alias_is_null_or_a_number_or_the_value_has_the_wrong_type if {
	every assertion in _named_read_walks {
		_named_read_cause({"k1": 1}, [null], assertion) == "null"
		_named_read_cause({"k1": 1}, [3], assertion) == "unusable"
		_named_read_cause({"k1": "a"}, ["k1"], assertion) == "unusable"
		_named_read_cause({"k1": null}, ["k1"], assertion) == "null"
		_named_read_cause(null, ["k1"], assertion) == "null"
	}
}

test_a_sum_through_a_for_name_lists_the_part_before_the_name_and_not_the_sum_or_a_list_per_item if {
	things := [{"id": 1, "ks": ["a", "b"], "m": {"a": [1], "b": [2]}}]
	_for_rows({"for": "every ks as k", "assert": "sum of m named by k is at least 1"}, things, {})[0][3] == [
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/things/0/ks/0", "/things/0/ks/1"]},
		{"name": "m", "value": {"a": [1], "b": [2]}, "locations": ["/things/0/m"]},
	]
}

_keyed_tally_rows(nums, rows, checks) := {r.check: [r.cause, [i.name | some i in r.inputs]] |
	doc := {"artifacts": [{"name": "x", "nums": nums, "prs": [{"id": 1, "keys": ["k1"], "rows": rows}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	some r in ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	r.check in object.keys(checks)
}

_keyed_tallies := {
	"count": "count of rows whose n is at least artifact.nums named by key is at least 1",
	"for_count": {"for": "every keys as k", "assert": "count of rows whose n is at least artifact.nums named by key is at least 1"},
}

test_a_count_keyed_by_an_item_field_lists_the_part_before_the_name_and_never_the_keyed_value if {
	got := _keyed_tally_rows({"a": 1, "b": 2}, [{"key": "a", "n": 1}, {"key": "b", "n": 2}], _keyed_tallies)
	every _, r in got {
		r[0] == "satisfied"
		"artifact.nums" in r[1]
		not "artifact.nums named by key" in r[1]
	}
}

test_a_count_keyed_by_an_item_field_fails_as_before_when_the_key_is_missing_null_or_wrong_typed if {
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

test_a_count_whose_right_side_walks_a_list_input_fails_with_the_first_cause_in_order if {
	every check in ["count of m whose v is in $input.v is 1", "sum of m.v that is in $input.v is 1"] {
		policy := _list_key_policy({"from": "$input", "identified_by": "id"}, check)
		every m in [{"v": 1}, "s", 3] {
			[[r.subject.id, r.cause] | some r in ergo.report([{"id": "a", "v": 1, "m": m}, {"id": "b"}], policy, {}).results; r.check == "c"] == [["a", "unusable"], ["b", "absent"]]
		}
		[[r.subject.id, r.cause] | some r in ergo.report([{"id": "a", "v": 1, "m": "s"}, {"id": "b", "v": null}], policy, {}).results; r.check == "c"] == [["a", "unusable"], ["b", "absent"]]
	}
}

test_a_whose_inside_count_of_and_sum_of_walks_a_ref_on_its_right_side if {
	doc := {"sbom": {"components": [{"name": "click", "n": 2}]}, "things": [{"id": "t1", "deps": [{"name": "click", "n": 2}, {"name": "x", "n": 5}]}]}
	_walk_right_rows("count of deps whose name is in $input.sbom.components.name is 1", doc, {}) == [[true, "satisfied", ""]]
	_walk_right_rows("sum of deps.n that is in $input.sbom.components.n is 2", doc, {}) == [[true, "satisfied", ""]]
	[row[1] | some row in _walk_right_rows("count of deps whose name is in $input.sbom.components.name is 1", object.union(doc, {"sbom": {"components": [{"name": "click"}, {}]}}), {})] == ["absent"]
}

test_a_count_or_a_sum_on_both_sides_is_said_once_when_its_list_is_missing_or_null if {
	_dot_plain_rows("count of xs is more than count of xs", {"repos": [{"id": "r"}]})[0].message == "xs is missing"
	_dot_plain_rows("sum of xs.n is more than sum of xs.n", {"repos": [{"id": "r", "xs": null}]})[0].message == "xs is null"
}

test_a_count_of_a_position_in_params_that_are_an_empty_list_names_the_params if {
	params_key_messages.g == "$params is [], which isn't an object" with data.params as []
}

test_null_params_fail_a_walk_or_a_count_as_absent_like_a_plain_path if {
	rows := [r |
		some r in report(
			{"items": [{"id": 1, "zz": "a"}]},
			{"s": {
				"subject_type": "thing",
				"from": "items",
				"identified_by": "id",
				"checks": {
					"c": {"assert": "every $params.a is 1"},
					"d": {"assert": "count of $params.a is 1"},
					"e": {"assert": "zz is in $params"},
				},
			}},
		).results
		not startswith(r.check, "$")
	] with data.params as null
	count(rows) == 3
	every r in rows {
		r.cause == "absent"
		r.message == "$params is missing"
	}
}

test_a_sum_or_count_that_reads_params_that_are_a_list_names_them_not_the_digits if {
	every case in [[[3], "[3]"], [[[1]], "[[1]]"]] {
		object.filter(params_for_line_messages, ["f", "g"]) == {
			"f": concat("", ["$params is ", case[1], ", which isn't an object"]),
			"g": concat("", ["$params is ", case[1], ", which isn't an object"]),
		} with data.params as case[0]
	}
}

_whose_key_doc := {"things": [{"id": "t", "m": {"a": "a"}, "rs": [{"v": "a"}, {"v": 4}]}], "m": {"a": "a"}}

_whose_key_row(doc, params, check) := [[r.cause, r.message] |
	some r in ergo.report(doc, _sentence_policy({"c": check}), params).results
	r.check == "c"
]

_whose_null_row(check) := _whose_key_row(object.union(_whose_key_doc, {"k": null}), {"k": null}, check)

_whose_missing_row(check) := _whose_key_row(_whose_key_doc, {}, check)

_whose_number_row(check) := _whose_key_row(object.union(_whose_key_doc, {"k": 3}), {"k": 3}, check)

test_a_whose_value_from_the_input_that_is_null_is_named_beside_worse_items_but_a_key_is_not if {
	_whose_null_row("count of rs whose zz is $input.k is 1") == [["absent", "$input.k is null; item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
	_whose_null_row("count of rs whose zz is m named by $input.k is 1") == [["absent", "item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
	_whose_null_row("count of rs whose zz is m named by $params.k is 1") == [["absent", "item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
	_whose_null_row("count of rs whose v is m named by $input.k is 1") == [["null", "$input.k is null"]]
}

test_a_whose_item_that_isnt_an_object_beside_a_key_that_is_missing_or_null_fails_as_not_an_object if {
	doc := {"things": [{"id": "t", "m": {"a": "a"}, "rs": ["a", {"v": 1}]}]}
	every k in [{}, {"k": null}] {
		_whose_key_row(object.union(doc, k), {}, "count of rs whose zz is m named by $input.k is 1") == [["not_an_object", "item 1 of rs is \"a\", which isn't an object"]]
		_whose_key_row(object.union(doc, k), {}, "count of rs whose v.y is m named by $input.k is 1") == [["not_an_object", "item 1 of rs is \"a\", which isn't an object"]]
	}
}

test_a_whose_path_from_the_input_with_a_null_key_is_named_as_a_root_beside_worse_items if {
	_whose_null_row("count of rs whose zz is $input.m named by $input.k is 1") == [["absent", "$input.k is null; item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
	_whose_null_row("count of rs whose zz is at least $input.m named by $input.k is 1") == [["absent", "$input.k is null; item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
}

test_a_whose_list_with_a_key_that_cant_be_read_is_read_before_any_item_so_the_key_decides if {
	every check in [
		"count of rs whose zz is in m named by $input.k is 1",
		"count of rs whose zz is in $input.m named by $input.k is 1",
		"count of rs whose zz is in $input.k is 1",
	] {
		_whose_null_row(check) == [["null", "$input.k is null"]]
		_whose_missing_row(check) == [["absent", "$input.k is missing"]]
	}
	_whose_null_row("count of rs whose zz is in m named by $params.k is 1") == [["null", "$params.k is null"]]
	_whose_missing_row("count of rs whose zz is in m named by $params.k is 1") == [["absent", "$params.k is missing"]]
}

test_a_whose_key_that_is_missing_decides_even_beside_worse_items if {
	every check in [
		"count of rs whose zz is m named by $input.k is 1",
		"count of rs whose v is m named by $input.k is 1",
		"count of rs whose zz is $input.m named by $input.k is 1",
	] {
		_whose_missing_row(check) == [["absent", "$input.k is missing"]]
	}
	_whose_missing_row("count of rs whose zz is m named by $params.k is 1") == [["absent", "$params.k is missing"]]
}

test_a_whose_key_that_isnt_text_fails_each_item_as_unusable if {
	every check in [
		"count of rs whose zz is m named by $input.k is 1",
		"count of rs whose v is m named by $input.k is 1",
		"count of rs whose zz is in m named by $input.k is 1",
		"count of rs whose zz is $input.m named by $input.k is 1",
	] {
		_whose_number_row(check) == [["unusable", "item 1 of rs: $input.k is 3, which isn't text; item 2 of rs: $input.k is 3, which isn't text"]]
	}
	_whose_number_row("count of rs whose zz is m named by $params.k is 1") == [["unusable", "item 1 of rs: $params.k is 3, which isn't text; item 2 of rs: $params.k is 3, which isn't text"]]
	_whose_number_row("count of rs whose zz is in $input.k is 1") == [["unusable", "$input.k is 3, which isn't a list"]]
}

test_a_count_sum_or_plus_with_a_key_from_a_list_input_says_the_input_is_not_an_object_not_that_it_needs_more_digits if {
	doc := [{"id": "t", "k": "a", "n": 1, "m": {"a": 1}, "tags": ["a"], "xs": [{"m": {"a": 1}}]}]
	message := "$input is [an object with 6 keys], which isn't an object"
	every check in [
		"sum of xs.m named by $input.k is 1",
		"sum of m named by $input.k is 1",
		"count of tags is n plus m named by $input.k",
		"count of xs.m named by $input.k is 1",
		"sum of xs.m named by $input.ka.k is 1",
	] {
		policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"subject": "t", "checks": {"c": check}}}}
		[[r.cause, r.message] | some r in ergo.report(doc, policy, {}).results; r.check == "c"] == [["unusable", message]]
	}
}
