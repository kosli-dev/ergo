package ergo_test

import data.ergo
import rego.v1

test_applies_to_excludes_subjects_whose_filtered_field_is_missing if {
	rep := report({"items": [{"id": "a"}]}, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
}

test_applies_to_is_evaluated_for_every_raw_subject if {
	rep := report(two_states, scoped_req(merged_only))
	verdicts := {r.subject.id: r.passed |
		some r in rep.results
		r.check == "$applies"
	}
	verdicts == {"a": true, "b": false}
}

any_commit_signed := "some prs.commits.signed is true"

test_each_fails_when_one_element_of_one_inner_collection_fails if {
	verdict(
		{"prs": [{"commits": [{"signed": true}]}, {"commits": [{"signed": true}, {"signed": false}]}]},
		every_commit_signed,
	) == false
}

test_each_under_any_fails_when_no_element_passes if {
	verdict({"prs": [{"commits": [{"signed": false}]}]}, any_commit_signed) == false
}

test_any_of_echoes_every_field_it_read_once_each if {
	inputs_of({"type": "Story", "state": "DONE"}, flavoured) == [
		{"name": "state", "value": "DONE", "locations": ["/items/0/state"]},
		{"name": "type", "value": "Story", "locations": ["/items/0/type"]},
	]
}

test_a_string_never_picks_a_list_item_and_a_number_never_picks_an_object_key if {
	[cause_of({"id": 1, "a": [10, 20]}, ".a.\"0\" exists"), cause_of({"id": 1, "o": {"0": "zero"}}, "item 1 of o exists")] == ["unusable", "unusable"]
}

test_a_list_index_reads_the_same_item_however_other_checks_write_it if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"item": {"from": "items", "identified_by": "id"}},
		"requirements": {"r": {"subject": "item", "checks": {
			"c1": "item 2 of .a exists",
			"c2": "item 2 of .a exists",
		}}},
	}
	rep := ergo.report({"items": [{"id": 1, "a": [1, 2]}]}, policy, {})
	[[r.check, r.passed, r.cause] | some r in rep.results] == [[c, true, "satisfied"] | some c in ["$well_formed", "$min_subjects", "$unique_ids", "c1", "c2"]]
}

test_cause_unusable_when_the_path_walks_through_a_scalar if {
	cause_of({"pr": "none"}, "pr.state is \"MERGED\"") == "unusable"
}

test_every_walks_that_start_at_a_list_input_read_the_lists_inside_its_items if {
	doc := [{"commits": [{"id": "a"}]}, {"commits": []}]
	every from in ["every $input.commits", "every commits"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report(doc, req), "s", "$min_subjects")] == [[true, "satisfied", 1, ["/0/commits/0"]]]
	}
}

test_every_walk_that_starts_at_a_list_input_fails_an_item_that_is_not_an_object_or_has_no_list if {
	every doc, cause in {`[1]`: "unusable", `[[1]]`: "not_an_object", `[{}]`: "absent", `[{"commits": null}]`: "null", `[{"commits": 1}, {"commits": [2]}]`: "unusable"} {
		req := {"s": object.union(min_subjects_req(1).s, {"from": "every commits"})}
		[[r.passed, r.cause] | some r in rows_for(report(json.unmarshal(doc), req), "s", "$min_subjects")] == [[false, cause]]
	}
}

test_every_walk_that_starts_at_a_list_input_names_where_it_broke_from_input if {
	every from in ["every $input.commits", "every commits"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[f.path, f.item, f.locations] | some r in rows_for(report([{"commits": [{"id": "a"}]}, {"commits": null}, 7], req), "s", "$min_subjects"); some f in r.failed_items] == [["$input[1].commits", "$input[1].commits", ["/1/commits"]], ["item 3 of $input", "item 3 of $input", ["/2"]]]
	}
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input[1].commits"})}
	[[f.path, f.item] | some r in rows_for(report([{"commits": []}, 5], req), "s", "$min_subjects"); some f in r.failed_items] == [["item 2 of $input", "item 2 of $input"]]
}

test_a_position_on_a_list_input_reads_the_item_and_ends_absent_past_the_end if {
	every from in ["$input[0]", "first of $input"] {
		req := {"s": object.union(min_subjects_req(1).s, {"from": from})}
		[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([{"id": "a"}, 1], req), "s", "$min_subjects")] == [[true, "satisfied", 1, ["/0"]]]
		[[r.passed, r.cause, r.inputs[0].value] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "absent", 0]]
	}
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input[5]"})}
	[[r.passed, r.cause] | some r in rows_for(report([{"id": "a"}], req), "s", "$min_subjects")] == [[false, "absent"]]
}

test_a_position_on_a_list_input_that_leads_to_a_list_reads_its_items if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input[0].commits"})}
	[[r.passed, r.cause, r.inputs[0].locations] | some r in rows_for(report([{"commits": [{"id": "a"}]}], req), "s", "$min_subjects")] == [[true, "satisfied", ["/0/commits/0"]]]
}

test_unique_ids_passes_when_every_subject_has_its_own_id if {
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "b", "owner": "carol"}]}, owner_req)
	[[r.inputs, r.passed, r.cause] | some r in rows_for(rep, "s", "$unique_ids")] == [[[{"name": "repeated repo ids", "value": [], "locations": []}], true, "satisfied"]]
	rep.requirements.s.status == "met"
}

test_unique_ids_tells_apart_subjects_whose_rows_would_look_the_same if {
	unique_ids_row({"repos": [{"name": "a", "owner": ""}, {"name": "a", "owner": ""}]}, owner_req) == [[{"name": "repeated repo ids", "value": ["a"], "locations": ["/repos/0/name", "/repos/1/name"]}], false, "value"]
}

test_keys_that_are_not_strings_get_a_name_each if {
	req := object.union(typed_req, {true: 1, false: 2, null: 3, 1.5: 4, 2.5: 5})
	names := [i.name | some i in problem_inputs(report({"items": [{"id": 1}]}, {"s": req}))]
	names == ["<invalid key null>", "<invalid key false>", "<invalid key true>", "<invalid key 1.5>", "<invalid key 2.5>"]
}

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

test_compliant_when_every_requirement_is_met if {
	doc := {"a": [{"id": "1"}], "b": [{"id": "2"}]}
	policy := {
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "min_subjects": 1, "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "min_subjects": 1, "checks": {"c": "id exists"}},
	}
	report(doc, policy).compliant == true
}

test_compliant_when_every_requirement_is_not_applicable if {
	rep := report({"deployments": [{"id": 1, "env": "dev"}]}, prod_only)
	rep.requirements.s.status == "not_applicable"
	rep.compliant == true
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

test_an_not_met_report_always_explains_itself_under_every if count(unexplained("every")) == 0

test_a_malformed_requirement_is_never_met_under_every if malformed_ones_fail_and_say_why("every")

test_every_over_no_subjects_is_not_met if {
	report({"items": []}, require_req("every")).requirements.s.status == "not_met"
}

test_a_subject_is_out_of_scope_when_every_failing_filter_reads_sound_values if {
	req := degraded_req_whose("every", concat(" and whose ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED", "degraded": false}]}, req)
	rep.requirements.s.status == "not_applicable"
	rows_for(rep, "s", "$applies")[0].cause == "value"
}

test_a_subject_whose_filter_fails_on_an_unreadable_field_is_not_ruled_out_by_a_passing_filter if {
	req := degraded_req_whose("every", concat(" and whose ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "MERGED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
}

test_a_present_filter_rules_out_a_subject_whose_field_is_null if {
	rep := report({"packages": [{"id": "a", "lock": null}]}, locked_req("lock"))
	rep.requirements.s.status == "not_applicable"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["value"]
}

test_only_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	req := {"s": object.union(locked_req("lock").s, {"from": "packages whose lock is a non-empty string"})}
	rep := report({"packages": [{"id": "a"}]}, req)
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["absent"]
}

test_the_applies_row_lists_each_field_its_filters_read_once_in_name_order if {
	req := {"s": {
		"from": "items whose status exists and whose status is \"open\" and whose kind exists",
		"identified_by": "id",
		"checks": {"c": "id exists"},
	}}
	rep := report({"items": [{"id": 1, "status": "open", "kind": "x"}]}, req)
	[i.name | some i in rows_for(rep, "s", "$applies")[0].inputs] == ["kind", "status"]
}

test_named_by_each_of_on_an_object_that_cant_be_read_fails_min_subjects_so_a_check_for_a_missing_field_cant_meet_the_requirement if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
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
	policy := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
	every keys in [["k1", 1], [null]] {
		rep := ergo.report({"m": {"k1": {}}}, policy, {"keys": keys})
		rep.compliant == false
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "unusable"]]
		rows_for(rep, "s", "c") == []
	}
}

test_named_by_each_of_still_makes_a_subject_of_a_key_the_object_lacks if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "m named by each of $params.keys"}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x does not exist"}}}}
	rep := ergo.report({"m": {"k1": {"x": 1}}}, policy, {"keys": ["k1", "k2"]})
	[[r.subject.id, r.passed] | some r in rows_for(rep, "s", "c")] == [["k1", false], ["k2", true]]
}

test_a_set_anywhere_in_the_input_fails_every_check_as_unusable_so_a_port_can_check_the_input_once if {
	rep := report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, json_only_req)
	row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", false, "unusable"], ["$unique_ids", true, "satisfied"], ["c", false, "unusable"]]
	rep.requirements.s.status == "not_met"
}

test_a_set_in_the_input_takes_every_subject_out_of_scope_as_unusable if {
	req := {"s": object.union(json_only_req.s, {"from": "items whose id exists"})}
	rows_for(report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}}, req), "s", "$applies")[0].cause == "unusable"
}

test_a_set_in_the_params_fails_every_check_as_unusable if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is one of $params.allowed"}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": {"MIT"}}), "s", "c")[0].cause == "unusable"
}

test_params_that_are_not_an_object_fail_every_requirement_even_one_that_reads_no_params_since_they_can_only_be_a_mistake if {
	every params in ["x", 1, true, [], ["a"]] {
		rep := ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), params)
		row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", false, "unusable"], ["$unique_ids", true, "satisfied"], ["c", false, "unusable"]]
		rows_for(rep, "s", "$min_subjects")[0].inputs == [{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]}, {"name": "$params", "value": ["not an object"], "locations": []}]
		rep.compliant == false
	}
}

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

test_a_requirement_lists_the_causes_of_its_failing_rows_worst_first_with_how_many_rows_each if {
	causes_of(causes_doc.deployments, approved_check) == [
		{"cause": "absent", "rows": 2},
		{"cause": "value", "rows": 1},
	]
}

test_every_or_some_reads_a_bare_name_on_the_right_from_the_subject_so_it_isnt_compared_with_itself if {
	not _sentence_problems(`every conditions.type equals type`)
	not _sentence_problems(`some pull_requests.commits[0].author is after author`)
	not _sentence_problems(`every xs.ys.zs equals ys.zs`)
	not _sentence_problems(`every $input.xs.y equals y`)
	not _sentence_problems(`every conditions.type equals .type`)
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
	}) == {"item": "value", "subject": "satisfied"}
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

test_an_any_of_row_reads_every_input_once_and_lists_no_failed_lines if {
	r := ergo.report({"things": [{"id": "a", "x": 2, "y": 1}]}, _sentence_policy({"c": {"any_of": {"a": "x is 1 and y is 1", "b": ["x is 3", "y exists"]}}}), {})
	[row | some row in r.results; row.check == "c"] == [{"requirement": "s", "subject": {"type": "thing", "id": "a"}, "check": "c", "passed": false, "cause": "value", "message": "a: x is 2; b: x is 2", "inputs": [{"name": "x", "value": 2, "locations": ["/things/0/x"]}, {"name": "y", "value": 1, "locations": ["/things/0/y"]}]}]
}

test_an_option_of_an_any_of_reads_a_part_by_its_alias if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"cov": "attestations.cov"}}}, "requirements": {"s": {"subject": "thing", "checks": {"c": {"any_of": {"high": "cov.pct is at least 80", "waived": "waived is true"}}}}}}
	r := ergo.report({"things": [{"id": "a", "attestations": {"cov": {"pct": 90}}}, {"id": "b", "waived": true, "attestations": {"cov": {"pct": 10}}}, {"id": "c", "waived": false, "attestations": {"cov": {"pct": 10}}}]}, policy, {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "value"]]
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

test_a_walk_that_reads_no_list_stops_at_the_end_when_every_value_along_the_path_is_an_object if {
	doc := {"things": [{"id": "a", "x": {"y": {"z": 1}}}, {"id": "b", "xs": [1, 2]}]}
	_walk_rows({"e": "every x.y is 1"}, doc, {})[0] == ["a", "e", "unusable", [{"path": "x.y", "item": "x.y", "cause": "unusable", "value": {"z": 1}, "locations": ["/things/0/x/y"]}]]
	_walk_rows({"e": "every xs[5].y is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "item 6 of xs", "item": "item 6 of xs", "cause": "absent", "value": null, "locations": ["/things/1/xs"]}]]
	_walk_rows({"e": "every x.y.z.w is 1"}, doc, {})[1] == ["b", "e", "absent", [{"path": "x", "item": "x", "cause": "absent", "value": null, "locations": ["/things/1"]}]]
}

test_an_item_a_whose_condition_cant_decide_is_undecided_even_when_another_condition_leaves_it_out if {
	doc := {"things": [{"id": "a", "xs": [{"kind": "b"}]}]}
	_walk_rows({"e": `every xs whose kind is "a" and whose state is "open" is not empty`}, doc, {}) == [["a", "e", "absent", [{"path": "xs[0].state", "item": "item 1 of xs", "cause": "absent", "value": null, "locations": ["/things/0/xs/0"]}]]]
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
	r := ergo.report({"things": ["text", null]}, {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "things"}}, "requirements": {"s": {"subject": "t", "checks": {"c": "every xs is 1"}}}}, {})
	[row.cause | some row in r.results; row.check == "c"] == ["not_an_object", "not_an_object"]
}

test_params_is_not_a_step_of_a_walk if {
	_reads("every $params.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10 is 1")
	_sentence_problems(concat("", ["every $params.", _eleven, " is 1"])) == _too_long
}

test_a_plus_reads_the_part_on_the_subject_and_on_the_right_of_a_whose if {
	doc := {"things": [{"id": "a", "p": {"z": [1], "zz": 0}, "xs": [{"n": 1, "v": 1}]}]}
	checks := {"on_subject": "x.zz plus count of x.z is 1", "in_whose": {"for": "every xs whose n is x.zz plus count of x.z as y", "assert": "y.v is 1"}}
	_part_walk_rows({"x": "p"}, checks, doc) == [["a", "in_whose", "satisfied"], ["a", "on_subject", "satisfied"]]
}

test_a_part_used_in_a_path_that_is_not_a_walk_is_never_held_to_ten_steps if {
	doc := {"things": [object.union({"id": "a"}, _k10({"z": 1}))]}
	_part_walk_rows({"x": _ten}, {"c": "x.z is 1", "d": "x exists", "e": "x.z is at least 1"}, doc) == [["a", "c", "satisfied"], ["a", "d", "satisfied"], ["a", "e", "satisfied"]]
	_part_walk_reads({"x": _eleven}, "x.z is 1")
}

test_a_walk_over_ten_steps_in_a_for_items_whose_is_listed_under_for if {
	_parent_part_problems({"x": _ten}, {"for": "every xs whose n is count of b.x.z as y", "assert": "y.v is 1"}) == [[_for_too_long]]
	_part_walk_problems({"x": _ten}, {"for": "every xs whose n is count of x.z as r", "assert": "r.v is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "every xs as r", "assert": "every r.v whose n is count of x.z is 1"}) == _too_long
}

test_a_walk_whose_named_by_cant_be_read_shows_an_empty_list_in_its_inputs if {
	r := ergo.report({"things": [{"id": "a", "xs": {"k": [1]}}]}, _sentence_policy({"c": "every xs named by $params.k is 1"}), {})
	[[row.cause, row.inputs, row.failed_items] | some row in r.results; row.check == "c"] == [["absent", [{"name": "xs named by $params.k", "value": [], "locations": []}], []]]
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

test_an_every_in_the_assertion_walks_inside_the_named_item if {
	check := {"for": "some xs as x", "assert": "every x.ys is at most 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"ys": [1, 3]}, {"ys": [1, 2]}]}, {"id": 2, "xs": [{"ys": [3]}]}], {})] == ["satisfied", "value"]
}

test_each_item_lists_every_line_it_failed_with_the_first_cause_of_each if {
	check := {"for": "every xs as x", "assert": ["x.a is 2", "x.b is 2", "x.c is 1"]}
	rows := _for_rows(check, [{"id": 1, "xs": [{"a": 1, "b": 2}, {"a": 2, "b": 2, "c": 1}]}], {})
	rows[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "absent", "value": {"a": 1, "b": 2}, "failed_assertions": [{"assertion": "x.a is 2", "cause": "value"}, {"assertion": "x.c is 1", "cause": "absent"}], "locations": ["/things/0/xs/0"]}]
}

test_a_second_item_a_whose_cant_decide_fails_the_first_item_with_its_cause if {
	check := {"for": "every xs as x, every ys whose s is 1 as y", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "xs": [1], "ys": [{"s": 1}, {"t": 1}]}], {})[0] == [1, "absent", [{"path": "item 2 of ys", "item": "item 2 of ys", "cause": "absent", "value": {"t": 1}, "failed_assertions": [], "locations": ["/things/0/ys/1"]}], [{"name": "xs[]", "value": [1], "locations": ["/things/0/xs/0"]}, {"name": "ys[]", "value": [{"s": 1}, {"t": 1}], "locations": ["/things/0/ys/0", "/things/0/ys/1"]}]]
}

_for_root_rows(checks, z, params) := {r.check: [r.cause, r.message] |
	thing := object.union({"id": 1, "xs": [{"k": "a", "v": 1}, {"k": "b", "v": "x"}]}, z)
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "pr", "checks": checks}}}
	some r in ergo.report({"things": [thing]}, policy, params).results
	not startswith(r.check, "$")
}

_for_root_checks := {
	"ab": {"for": "every xs whose v is 1 and whose k is in pr.z as m", "assert": "m.v is 1"},
	"ba": {"for": "every xs whose k is in pr.z and whose v is 1 as m", "assert": "m.v is 1"},
	"as1": {"for": "every xs as m", "assert": ["m.v is 1", "m.k is in z"]},
	"as2": {"for": "every xs as m", "assert": ["m.k is in z", "m.v is 1"]},
	"second": {"for": "every xs as m, every z as y", "assert": "y is at least m.v"},
}

test_a_root_that_cant_be_read_comes_first_and_keeps_each_items_own_problem_in_any_order if {
	missing := _for_root_rows(_for_root_checks, {}, {})
	missing.ab == ["unusable", `pr.z is missing; item 2 of xs: v is "x", which isn't a number`]
	missing.as1 == ["unusable", `z is missing; item 2 of xs: m.v is "x", which isn't a number`]
	missing.second == ["unusable", `z is missing; item 2 of xs: m.v is "x", which isn't a number`]
	nulled := _for_root_rows(_for_root_checks, {"z": null}, {})
	nulled.ab == ["unusable", `pr.z is null; item 2 of xs: v is "x", which isn't a number`]
	nulled.as1 == ["unusable", `z is null; item 2 of xs: m.v is "x", which isn't a number`]
	nulled.second == ["unusable", `z is null; item 2 of xs: m.v is "x", which isn't a number`]
	wrong := _for_root_rows(_for_root_checks, {"z": "s"}, {})
	wrong.ab == ["unusable", `pr.z is "s", which isn't a list; item 2 of xs: v is "x", which isn't a number`]
	wrong.as1 == ["unusable", `z is "s", which isn't a list; item 2 of xs: m.v is "x", which isn't a number`]
	wrong.second == ["unusable", `z is "s", which isn't a list or an object; item 2 of xs: m.v is "x", which isn't a number`]
	every rows in [missing, nulled, wrong] {
		rows.ab == rows.ba
		rows.as1 == rows.as2
	}
}

test_null_params_read_by_a_key_from_the_item_say_what_params_that_are_missing_say if {
	checks := {"whole": {"for": "every xs as m", "assert": "$params named by m.k is 1"}, "field": {"for": "every xs as m", "assert": "$params.q named by m.k is 1"}}
	every params in [null, {}] {
		said := `item 1 of xs: m is {"k": "a", "v": 1}, which isn't text; item 2 of xs: m is {"k": "b", "v": "x"}, which isn't text`
		_for_root_rows(checks, {}, params) == {"whole": ["unusable", said], "field": ["unusable", said]}
	}
}

test_a_name_whose_path_ends_missing_or_unreadable_fails_its_item_before_its_lines if {
	rows := _for_rows({"for": "every prs.title as t", "assert": "t does not exist"}, [{"id": 1, "prs": [{}]}, {"id": 2, "prs": [{"title": null}]}, {"id": 3, "prs": [{"meta": "s"}]}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [
		[1, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/0/prs/0"]}]],
		[2, "satisfied", []],
		[3, "absent", [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": null, "failed_assertions": [], "locations": ["/things/2/prs/0"]}]],
	]
	[row[1] | some row in _for_rows({"for": "every prs.meta.title as t", "assert": "t is null"}, [{"id": 1, "prs": [{"meta": "s"}]}], {})] == ["unusable"]
	[row[1] | some row in _for_rows({"for": `every prs whose n is 1 as p`, "assert": `p.title is "x"`}, [{"id": 1, "prs": [{"n": 2}, {"n": 1, "title": "x"}]}], {})] == ["satisfied"]
	[row[1] | some row in _for_rows({"for": `every prs.title whose n is 1 as t`, "assert": `t is "x"`}, [{"id": 1, "prs": [{"n": 2}, {"n": 1, "title": "x"}]}], {})] == ["not_an_object"]
}

test_a_second_item_that_reads_into_a_first_item_that_isnt_an_object_fails_it_as_not_an_object if {
	rows := _for_rows({"for": "every prs as pr, some pr.approvers as ap", "assert": "ap is 1"}, [{"id": 1, "prs": [1, null, {"approvers": [1]}]}], {})
	[[f.item, f.cause] | some f in rows[0][2]] == [["item 1 of prs", "not_an_object"], ["item 2 of prs", "not_an_object"]]
	[row[1] | some row in _for_rows({"for": "every m as row, every row as cell", "assert": "cell is 1"}, [{"id": 1, "m": [[1], [1, 1]]}], {})] == ["satisfied"]
}

test_a_key_from_the_subject_after_params_in_a_whose_never_reads_the_items_field_called_like_the_subject if {
	things := [{"id": 1, "k": "w", "xs": [{"v": 1, "thing": "z"}]}]
	[r[1] | some r in _tally_rows("count of xs whose v equals $params.m named by thing.k is 1", things, {"m": {"z": 1, "w": 2}})] == ["value"]
	[r[1] | some r in _tally_rows("count of xs whose v equals $params.m named by thing.k is 1", [{"id": 1, "xs": [{"v": 1, "thing": "z"}]}], {"m": {"z": 1}})] == ["absent"]
}

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
	rows := _applies_failures_of(_from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and whose every files.path matches "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {}))
	rows.docs == {"failed_assertions": []}
	rows.mixed.failed_assertions == [{"assertion": `every files.path matches "^docs/"`, "cause": "value"}]
	rows.unset.failed_assertions == [{"assertion": `every files.path matches "^docs/"`, "cause": "absent"}]
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

test_that_names_the_item_by_the_plain_subject_name_and_writes_the_expression_the_way_a_check_must if {
	every name, written in {"w": "w", "my w": `"my w"`, "item": `"item"`, "that": `"that"`} {
		rep := _from_report({"ws": ["bay", "apple"]}, {name: {"from": `every ws that starts with "b"`}}, {"c": "it is not empty"}, {})
		apple := [r | some r in rep.results; r.check == "$applies"; r.subject.id == "apple"][0]
		apple.inputs == [{"name": name, "value": "apple", "locations": ["/ws/1"]}]
		apple.message == sprintf("%s is \"apple\"", [name])
		rep.requirements.r.checks["$applies"].expression == sprintf("%s starts with \"b\"", [written])
	}
}

test_a_subject_named_like_a_field_its_whose_reads_lists_the_field_and_the_item_apart if {
	rep := _from_report({"ws": [null]}, {"x": {"from": "every ws whose x is 1 and that is not empty"}}, {"c": "w is not empty"}, {})
	[r.inputs | some r in rep.results; r.check == "$applies"] == [[{"name": ".x", "value": null, "locations": ["/ws/0"]}, {"name": "x", "value": null, "locations": ["/ws/0"]}]]
}

_part_subjects := object.union(_owner_subjects, {"pr": {"from": "every artifact.pull_requests", "identified_by": "id", "has": {"w": "info.who"}}})

_part_doc := {"artifact": {"name": "a1", "pull_requests": [{"id": 1, "info": {"who": "ann"}, "commits": [{"author": "bob", "revs": [{"n": "ann"}]}, {"author": "ann", "revs": [{"n": "x"}]}]}]}}

_part_rows(checks) := {r.check: [[i.name, object.get(i, "part", null)] | some i in r.inputs] |
	some r in ergo.report(_part_doc, {"ergo_spec": ergo._spec, "subjects": _part_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
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

test_a_dotted_name_on_the_right_of_a_walk_is_the_subjects_field_and_isnt_its_part if {
	doc := {"artifact": {"name": "a1", "pull_requests": [{"id": 1, "info": {"who": "ann"}, "commits": [{"author": "bob", "w": "ann"}]}]}}
	checks := {"dot": "some commits.author is .w", "part": "some commits.author is w"}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _part_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	rows := {r.check: [i.name | some i in r.inputs] | some r in rep.results; r.check in object.keys(checks)}
	rows == {"dot": [".w", "commits[].author"], "part": ["commits[].author", "w"]}
}

test_the_applies_row_of_a_from_condition_lists_the_subjects_own_part_it_compares_with if {
	subjects := object.union(_part_subjects, {"pr": {"from": "every artifact.pull_requests whose some commits.author is w", "identified_by": "id", "has": {"w": "info.who"}}})
	rep := ergo.report(_part_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id is 1"}}}}, {})
	["w", {"id": null, "name": "w"}] in [[i.name, object.get(i, "part", null)] | some r in rep.results; r.check == "$applies"; some i in r.inputs]
}

test_a_walk_named_by_the_subjects_field_lists_the_path_it_names_and_the_key_like_a_plain_check if {
	_atts_rows({"item": "some commits.author is artifact.atts named by k.owner", "param": "some commits.author is artifact.atts named by $params.n.owner"}, {"n": "x"}) == {
		"item": ["artifact.atts named by k.owner", "commits[].author", "k"],
		"param": ["artifact.atts named by $params.n.owner", "commits[].author"],
	}
}

test_subjects_that_narrow_each_other_lead_to_a_loop if {
	rep := _narrow_report({"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}}, "x")
	_from_problems(rep) == [{"name": "subjects.x.from", "value": ["leads to a loop"], "locations": []}]
}

test_a_field_after_named_by_is_part_of_its_path_so_another_sides_cause_can_come_first_as_with_a_for_name_and_a_param if {
	doc := {"things": [{"id": 1, "s": null, "m": {}}]}
	_sentence_rows({"c": "xs equals m named by s"}, doc, {})[0][2] == "absent"
	_for_rows({"for": "every ks as s", "assert": "xs equals m named by s"}, [{"id": 1, "ks": [null], "m": {}}], {})[0][1] == "absent"
	_sentence_rows({"c": "xs equals m named by $params.s"}, {"things": [{"id": 1, "m": {}}]}, {"s": null})[0][2] == "absent"
}

test_a_param_key_that_cant_be_read_still_decides_when_the_other_side_can_be_read if {
	doc := {"things": [{"id": 1, "xs": "a", "m": {"a": "a"}}]}
	_sentence_rows({"c": "xs equals m named by $params.s"}, doc, {"s": null})[0][2] == "null"
	_sentence_rows({"c": "xs equals m named by $params.s"}, doc, {})[0][2] == "absent"
	_sentence_rows({"c": "xs equals m named by $params.s"}, doc, {"s": 3})[0][2] == "unusable"
}

test_named_by_a_for_name_in_the_second_items_path_reads_the_first_items_key if {
	check := {"for": "every ys as y, every xs named by y as x", "assert": "x is 1"}
	rows := [[r.subject.id, r.cause] | some r in ergo.report({"things": [{"id": 1, "xs": {"a": [1], "b": [2]}, "ys": ["a"]}, {"id": 2, "xs": {"a": [1], "b": [2]}, "ys": ["a", "b"]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	rows == [[1, "satisfied"], [2, "value"]]
}

test_every_through_a_for_name_isnt_listed_as_an_input_since_it_changes_with_each_item if {
	doc := {"things": [{"id": 1, "ps": ["a"], "xs": [{"k": {"a": 1}}]}]}
	[[r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy({"c": {"for": "every ps as p", "assert": "every xs.k named by p is 1"}}), {}).results; r.check == "c"] == [["satisfied", [{"name": "ps[]", "value": ["a"], "locations": ["/things/0/ps/0"]}]]]
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

test_a_roots_problem_comes_first_once_and_each_item_keeps_its_own_problems if {
	checks := {"c": {"for": "every xs as m", "assert": ["m.v is 2", "m.v is at least z"]}}
	_for_sentence_root_rows(checks, {"xs": [{"v": 1}, {"v": 3}]}) == {"c": ["absent", "z is missing; item 1 of xs: m.v is 1; item 2 of xs: m.v is 3"]}
	_for_sentence_root_rows(checks, {"xs": [{"v": 1}, {"v": 3}], "z": null}) == {"c": ["null", "z is null; item 1 of xs: m.v is 1; item 2 of xs: m.v is 3"]}
	_for_sentence_root_rows(checks, {"xs": [{"v": 1}, {"v": 3}], "z": "s"}) == {"c": ["unusable", "z is \"s\", which isn't a number; item 1 of xs: m.v is 1; item 2 of xs: m.v is 3"]}
	_for_sentence_root_rows(checks, {"xs": [{"v": 1}, {}, {"v": null}, {"v": "t"}]}) == {"c": ["unusable", "z is missing; item 1 of xs: m.v is 1; item 2 of xs: m.v is missing; and 2 more"]}
}

test_a_roots_problem_said_once_still_lists_every_failed_item if {
	rep := ergo.report({"things": [{"id": 1, "xs": [{"v": 1}, {"v": 3}]}]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every xs as m", "assert": ["m.v is 2", "m.v is at least z"]}}}}}, {})
	some r in rep.results
	r.check == "c"
	[[f.item, f.cause, [a.cause | some a in f.failed_assertions]] | some f in r.failed_items] == [["item 1 of xs", "absent", ["value", "absent"]], ["item 2 of xs", "absent", ["value", "absent"]]]
}

test_a_null_on_the_items_own_path_is_named_after_a_roots_problem if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every rs as r", "assert": "r.x.y named by $params.i does not exist"}}}}}
	input_doc := {"things": [{"id": 1, "rs": [{"x": null}, {"x": {}}]}]}
	msgs := {[p, r.cause, r.message] | some p in [{}, {"i": null}, {"i": [1]}]; some r in ergo.report(input_doc, policy, p).results; r.check == "c"}
	msgs == {
		[{}, "absent", "$params.i is missing; item 1 of rs: r.x is null"],
		[{"i": null}, "null", "$params.i is null; item 1 of rs: r.x is null"],
		[{"i": [1]}, "unusable", "$params.i is [1], which isn't text; item 1 of rs: r.x is null"],
	}
}

test_every_unit_divides_the_seconds_between_two_times_by_its_length if {
	every pair in [["seconds", "302400"], ["minutes", "5040"], ["hours", "84"], ["days", "3.5"], ["weeks", "0.5"]] {
		_elapsed_first(concat("", [pair[0], " elapsed from first_seen_ts to now_ts is ", pair[1]]), [_snyk], {}) == [true, "satisfied"]
	}
}

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

test_a_missing_part_fails_as_absent_like_its_full_path if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "f": "dd.b.x is 1"}, {})
	_parts_row(rep, "c").cause == "absent"
	_parts_row(rep, "f").cause == "absent"
	rep2 := _parts_report({"cov": "dd.b"}, {"c": "cov exists", "f": "dd.b exists"}, {})
	_parts_row(rep2, "c").cause == "value"
	_parts_row(rep2, "f").cause == "value"
}

test_a_null_part_fails_as_null_and_is_named_when_a_step_follows if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "cov.x is 1", "a": "cov is null", "f": "dd.b.x is 1"}, {"b": null})
	_parts_row(rep, "c").cause == "null"
	_parts_row(rep, "c").message == "cov is null"
	_parts_row(rep, "f").cause == "null"
	_parts_row(rep, "f").message == "dd.b is null"
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
		"ergo_spec": ergo._spec,
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
	_parts_row(rep, "d").inputs == [{"name": ".cov.x", "value": 2, "locations": ["/trail/cov/x"]}]
	_parts_row(rep, "e").passed
}

test_an_own_field_named_like_a_part_keeps_its_dot_and_the_part_does_not if {
	policy := _parts_policy({"cov": "dd.b"}, {"c": "cov.x is 1", "d": ".cov.x is 2", "e": "count of .cov.xs is 1", "f": "count of cov.xs is 1", "g": ".name is \"t1\""})
	rep := ergo.report({"trail": {"name": "t1", "cov": {"x": 2, "xs": [1]}, "dd": {"b": {"x": 1, "xs": [1]}}}}, policy, {})
	[i.name | some i in _parts_row(rep, "c").inputs] == ["cov.x"]
	[i.name | some i in _parts_row(rep, "d").inputs] == [".cov.x"]
	[i.name | some i in _parts_row(rep, "e").inputs] == ["count of .cov.xs", ".cov.xs[]"]
	[i.name | some i in _parts_row(rep, "f").inputs] == ["count of cov.xs", "cov.xs[]"]
	[i.name | some i in _parts_row(rep, "g").inputs] == ["name"]
}

test_a_failed_item_of_an_own_field_named_like_a_part_or_a_for_alias_keeps_the_dot if {
	policy := _parts_policy({"cov": "dd.b"}, {"c": "every .cov.xs is at least 2", "d": "every cov.xs is at least 2"})
	rep := ergo.report({"trail": {"name": "t1", "cov": {"xs": [1, 2]}, "dd": {"b": {"xs": [1]}}}}, policy, {})
	[f.path | some f in _parts_row(rep, "c").failed_items] == ["item 1 of .cov.xs"]
	[f.path | some f in _parts_row(rep, "d").failed_items] == ["item 1 of cov.xs"]
	for_policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"round": {"from": "rounds", "identified_by": "id"}},
		"requirements": {"r": {"subject": "round", "checks": {"c": {"for": "every items as y, every .y.zs as z", "assert": "z is 1"}}}},
	}
	for_rep := ergo.report({"rounds": [{"id": "r1", "y": {"k": 1}, "items": [{"id": "i1", "zs": [1, 2]}]}]}, for_policy, {})
	[f.path | some r in for_rep.results; r.check == "c"; some f in r.failed_items] == [".y.zs"]
}

test_an_own_field_named_like_a_for_alias_keeps_its_dot if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"thing": {"from": "things", "identified_by": "id"}},
		"requirements": {"s": {"subject": "thing", "checks": {"c": {"for": "every commits as c", "assert": ".c.signed is true"}}}},
	}
	rep := ergo.report({"things": [{"id": "t1", "c": {"signed": true}, "commits": [{"signed": true}]}]}, policy, {})
	some row in rep.results
	row.check == "c"
	".c.signed" in {i.name | some i in row.inputs}
}

test_a_field_of_the_subject_with_no_alias_in_the_way_is_read_as_before if {
	rep := _parts_report({"cov": "dd.b"}, {"c": "name is \"t1\""}, {})
	_parts_row(rep, "c").passed
}

test_a_dot_in_a_later_for_item_reads_the_subjects_field if {
	checks := {"c": {"for": "some approvals as ap, every .ap.r as r", "assert": "r is 1"}}
	doc := {"things": [{"id": "t1", "ap": {"r": [1]}, "approvals": [{"r": [2]}]}]}
	[r.cause | some r in ergo.report(doc, _sentence_policy(checks), {}).results; r.check == "c"] == ["satisfied"]
}

test_a_part_on_the_right_after_every_is_not_the_item_compared_with_itself if {
	rep := _parts_report(
		{"cov": "dd.b"}, {
			"walk": "every dd.items.cov equals cov.x",
			"whose": {"for": "every dd.items whose cov equals cov.x as i", "assert": "i.x is at least 5"},
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
			"w": {"for": "every dd.items whose cov is at least 5 as i", "assert": "i.x is at least 5"},
			"a": "every dd.items.x is at least cov.x",
			"r": {"for": "every dd.items whose x is at least cov.x as i", "assert": "i.x is at least 5"},
			"d": "every dd.items.x equals .cov",
		},
		d,
	)
	_parts_row(rep, "w").passed
	_parts_row(rep, "a").passed
	_parts_row(rep, "r").passed
	_parts_row(rep, "d").cause == "absent"
	{"name": ".cov", "value": null, "locations": ["/trail"]} in _parts_row(rep, "d").inputs
}

test_two_subjects_that_do_not_narrow_each_other_can_use_the_same_alias if {
	subjects := {
		"a": {"from": "xs", "has": {"cov": "p"}},
		"b": {"from": "ys", "has": {"cov": "q"}},
	}
	policy := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"ra": {"subject": "a", "checks": {"c": "cov is 1"}}, "rb": {"subject": "b", "checks": {"c": "cov is 2"}}}}
	rep := ergo.report({"xs": [{"p": 1, "q": 2}], "ys": [{"p": 1, "q": 2}]}, policy, {})
	[r.passed | some r in rep.results; r.check == "c"] == [true, true]
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

test_a_part_alias_must_be_a_bare_word_that_is_not_a_word_of_the_grammar_or_params_or_input if {
	bad := ["empty", "every", "params", "input", "true", "a", "x y", "1x", "x.y", "é"]
	every alias in bad {
		problems := _parts_problems(_parts_report({alias: "x"}, {"c": "name is \"t1\""}, {}))
		some key, value in problems
		contains(key, "subjects.round.has")
		value == ["invalid alias"]
	}
	problems := _parts_problems(_parts_report({"$x": "x"}, {"c": "name is \"t1\""}, {}))
	problems["subjects.round.has.$x"] == ["a name can't start with $"]
	problems_empty := _parts_problems(_parts_report({"": "x"}, {"c": "name is \"t1\""}, {}))
	problems_empty["subjects.round.has.\"\""] == ["a name can't be empty"]
	good := ["x", "_x", "x-y", "x_1", "Cov", "coverage-verification"]
	every alias in good {
		problems := _parts_problems(_parts_report({alias: "x"}, {"c": "name is \"t1\""}, {}))
		count([k | some k, _ in problems; contains(k, "subjects.round.has")]) == 0
	}
}

test_a_problem_in_has_names_the_subject_that_holds_it_for_every_requirement_that_builds_on_it if {
	subjects := {
		"round": {"from": "rounds", "has": {"cov": 5}},
		"good": {"from": "round whose x is 1"},
	}
	rep := ergo.report({"rounds": [{"x": 1}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "good", "checks": {"c": "x is 1"}}}}, {})
	_parts_problems(rep)["subjects.round.has.cov"] == ["not a string or an object"]
}

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_first_one_line_checks if _swap_differences("lines_a") == set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_other_one_line_checks if _swap_differences("lines_b") == set()

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_checks_that_walk_lists if _swap_differences("walks") == set()

test_the_batched_swap_comparison_names_each_scenario_where_a_part_reads_the_wrong_path if {
	scenarios := {n: _swap_scenarios[n] | some n in {"everything_is_there", "the_named_by_param_is_a_number", "the_subject_has_no_part_field"}}
	differences := _swap_differences("lines_b") with data.ergo_test._swap_has as object.union(_swap_has, {"by": "dd.m named by $params.j"})
		with data.ergo_test._swap_scenarios as scenarios
	differences == {"everything_is_there", "the_named_by_param_is_a_number", "the_subject_has_no_part_field"}
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
	"ergo_spec": ergo._spec,
	"subjects": {"round": _swap_subject2(has)},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_subject2(has) := {"from": "$input", "has": has} if count(has) > 0

_swap_subject2(has) := {"from": "$input"} if count(has) == 0

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
		"ergo_spec": ergo._spec,
		"subjects": {"s": {"from": "xs", "identified_by": "n", "has": {"p": {"from": "d", "identified_by": "i"}}}},
		"requirements": {"r": {"subject": "s", "checks": {"c": "p.v is 1"}}},
	}
	rep := ergo.report({"xs": [{"n": "a", "d": {"i": 1, "v": 1}}, {"n": "b", "d": {"i": "two", "v": 2}}, {"n": "c"}]}, policy, {})
	[r.inputs[0].part.id | some r in rep.results; r.check == "c"] == [1, "two", null]
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
		"ergo_spec": ergo._spec,
		"subjects": {"s": {"from": "xs whose p.v is 1", "identified_by": "n", "has": {"p": {"from": "d", "identified_by": "i"}}}},
		"requirements": {"r": {"subject": "s", "checks": {"c": "n exists"}}},
	}
	rep := ergo.report({"xs": [{"n": "a", "d": {"i": 9, "v": 1}}]}, policy, {})
	[r.inputs | some r in rep.results; r.check == "$applies"] == [[{"name": "p.v", "part": {"id": 9, "name": "p"}, "value": 1, "locations": ["/xs/0/d/v"]}]]
}

test_ids_of_subjects_read_with_every_are_unique_across_all_of_them if {
	doc := {"artifacts": [{"pull_requests": [{"url": "pr/7"}]}, {"pull_requests": [{"url": "pr/7"}]}]}
	rep := _from_report(doc, _every_prs, {"c": "url exists"}, {})
	[[r.cause, r.inputs] | some r in rep.results; r.check == "$unique_ids"] == [["value", [{"name": "repeated pull request ids", "value": ["pr/7"], "locations": ["/artifacts/0/pull_requests/0/url", "/artifacts/1/pull_requests/0/url"]}]]]
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

test_a_pick_reads_items_that_arent_objects_as_not_an_object_when_sorted if {
	rows := _for_rows({"for": "last of xs sorted by t as x", "assert": "x exists"}, [{"id": 1, "xs": [1, {"t": 2}]}], {})
	rows[0][1] == "not_an_object"
	rows[0][2] == [{"path": "item 1 of xs", "item": "item 1 of xs", "cause": "not_an_object", "value": null, "failed_assertions": [], "locations": ["/things/0/xs/0"]}]
	[row[1] | some row in _for_rows({"for": "last of xs as x", "assert": "x is 1"}, [{"id": 1, "xs": [{"t": 2}, 1]}], {})] == ["satisfied"]
}

test_a_pick_sorts_every_item_a_longer_path_walks_to if {
	check := {"for": "last of pull_requests.commits sorted by timestamp as c", "assert": `c.author is "grace"`}
	prs := [{"commits": [{"author": "ada", "timestamp": 1}]}, {"commits": []}, {"commits": [{"author": "grace", "timestamp": 2}]}]
	[row[1] | some row in _for_rows(check, [{"id": 1, "pull_requests": prs}], {})] == ["satisfied"]
	rows := _for_rows(check, [{"id": 1, "pull_requests": array.concat(prs, [{"commits": 1}])}], {})
	rows[0][1] == "unusable"
	rows[0][2] == [{"path": "pull_requests[3].commits", "item": "pull_requests[3].commits", "cause": "unusable", "value": 1, "failed_assertions": [], "locations": ["/things/0/pull_requests/3/commits"]}]
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

test_a_failed_line_lists_a_value_it_reads_twice_once_for_each_pair_of_items if {
	things := [{"id": 1, "commits": [{"ts": 5}], "ap": [{"ts": 9}, {"ts": 1}]}]
	check := {"for": "every commits as c, every ap as ap", "assert": "c.ts is at least c.ts plus ap.ts"}
	rows := _for_rows_full(check, things, {})
	[x.inputs | some x in rows[0][2][0].failed_assertions[0].items] == [
		[{"name": "c.ts", "value": 5, "locations": ["/things/0/commits/0/ts"]}, {"name": "c.ts plus ap.ts", "value": 14, "locations": ["/things/0/commits/0/ts", "/things/0/ap/0/ts"]}, {"name": "ap.ts", "value": 9, "locations": ["/things/0/ap/0/ts"]}],
		[{"name": "c.ts", "value": 5, "locations": ["/things/0/commits/0/ts"]}, {"name": "c.ts plus ap.ts", "value": 6, "locations": ["/things/0/commits/0/ts", "/things/0/ap/1/ts"]}, {"name": "ap.ts", "value": 1, "locations": ["/things/0/ap/1/ts"]}],
	]
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
		{"assertion": "count of x.zs whose k equals y.k is 1", "cause": "not_an_object", "items": [{"item": "item 1 of ys", "cause": "not_an_object"}]},
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

test_a_second_list_inside_the_first_whose_ref_cant_be_read_is_named_under_each_first_item if {
	check := {"for": "every prs as pr, every pr.m named by $params.k as y", "assert": "y is 1"}
	rows := _for_rows(check, [{"id": 1, "prs": [{"m": {"a": [1]}}]}], {})
	rows[0][2] == [{"path": "item 1 of prs", "item": "item 1 of prs", "cause": "absent", "value": {"m": {"a": [1]}}, "failed_assertions": [], "failed_items": [{"path": "pr.m named by $params.k", "item": "pr.m named by $params.k", "cause": "absent", "value": null, "locations": ["/things/0/prs/0/m"]}], "locations": ["/things/0/prs/0"]}]
}

test_each_key_named_by_a_list_is_a_subject_even_when_the_object_holding_them_is_missing_or_not_an_object if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"suite": {"from": "atts named by each of $params.names"}}, "requirements": {"r": {"subject": "suite", "checks": {"c": "status is \"COMPLETE\""}}}}
	every doc in [{}, {"atts": "x"}, {"atts": null}] {
		[[r.subject.id, r.cause] | some r in ergo.report(doc, policy, {"names": ["junit", "lint"]}).results; r.check == "c"] == [["junit", "absent"], ["lint", "absent"]]
	}
}

test_a_part_read_with_named_by_on_the_right_side_shows_the_parts_value if {
	subjects := {"t": {"from": "things", "identified_by": "id", "has": {"cov": "d.b"}}}
	named_by_rows(subjects, "t", "cov.x is one of $params.allowed named by id", {"things": [{"id": "a", "d": {"b": {"x": 1}}}]}) == [[true, [{"name": "cov.x", "part": {"id": null, "name": "cov"}, "value": 1, "locations": ["/things/0/d/b/x"]}, {"name": "$params.allowed named by id", "value": [1], "locations": ["$params:/allowed/a"]}, {"name": "id", "value": "a", "locations": ["/things/0/id"]}]]]
}

test_a_subject_that_is_not_an_object_has_its_own_location_for_every_input if {
	_located_rows({"c": "x.y exists"}, {"things": ["text", 3, null, [1]]}, {}) == [
		["text", "c", [{"name": "x.y", "locations": ["/things/0"]}]],
		[3, "c", [{"name": "x.y", "locations": ["/things/1"]}]],
		[null, "c", [{"name": "x.y", "locations": ["/things/2"]}]],
		[[1], "c", [{"name": "x.y", "locations": ["/things/3"]}]],
	]
}

test_a_subject_read_with_every_starts_where_the_walk_found_it if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"item": {"from": "every groups.xs", "identified_by": "id"}}, "requirements": {"s": {"subject": "item", "checks": {"c": "id exists"}}}}
	rep := ergo.report({"groups": [{"xs": [{"id": "a"}]}, {"xs": [{"id": "b"}, {"id": "c"}]}]}, policy, {})
	[[r.subject.id, r.inputs[0].locations] | some r in rep.results; r.check == "c"] == [
		["a", ["/groups/0/xs/0/id"]],
		["b", ["/groups/1/xs/0/id"]],
		["c", ["/groups/1/xs/1/id"]],
	]
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

test_a_failed_item_points_at_where_its_value_was_read_not_at_the_item if {
	rows := _for_rows({"for": "first of owners sorted by name as o", "assert": "o.ok is true"}, [{"id": 1, "owners": [{"name": "Zoe", "ok": true}, {"name": "Zoe", "ok": false}]}], {})
	[[f.value, f.locations] | some f in rows[0][2]] == [["Zoe", ["/things/0/owners/0/name"]], ["Zoe", ["/things/0/owners/1/name"]]]
	titles := _walk_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "prs": [{"title": "x"}, {"title": "y"}]}]}, {})
	titles[0][3] == [{"path": "prs[1].title", "item": "item 2 of prs", "cause": "value", "value": "y", "locations": ["/things/0/prs/1/title"]}]
	whole := _walk_rows({"c": "every prs is 1"}, {"things": [{"id": 1, "prs": [1, 2]}]}, {})
	whole[0][3][0].locations == ["/things/0/prs/1"]
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

test_subject_in_an_every_names_an_empty_list_and_a_missing_one if {
	rows := _subject_rows({"xs": [[], null]}, "every xs", "every s is a string", {})
	rows[1][3] == [{"name": "s", "value": [], "locations": []}]
	rep := _subject_report({"xs": [[]]}, "every xs", {"c": "every s is a string"}, {})
	[r.failed_items | some r in rep.results; r.check == "c"] == [[{"cause": "value", "item": "s", "path": "s", "value": [], "locations": ["/xs/0"]}]]
}

test_a_part_path_or_an_identified_by_called_like_the_subject_reads_a_field_of_the_subject if {
	rep := ergo.report({"xs": [{"id": "a", "s": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "every xs", "has": {"p": "s"}}}, "requirements": {"r": {"subject": "s", "checks": {"c": "p is 1"}}}}, {})
	[[r.passed, r.cause] | some r in rep.results; r.check == "c"] == [[true, "satisfied"]]
	rep2 := ergo.report({"xs": [{"id": "a", "s": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "every xs", "identified_by": "s"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}}, {})
	[r.subject.id | some r in rep2.results; r.check == "c"] == [1]
}

test_a_position_on_the_subjects_name_names_the_item_the_way_a_field_does if {
	rows := _subject_rows({"xs": [["a", "b"]]}, "every xs", "first of s is 'a'", {})
	rows == [[["a", "b"], true, "satisfied", [{"name": "item 1 of s", "value": "a", "locations": ["/xs/0/0"]}]]]
	_subject_rows({"xs": [[]]}, "every xs", "first of s is 'a'", {})[0][2] == "absent"
	_subject_rows({"xs": ["s"]}, "every xs", "first of s is 'a'", {})[0][2] == "unusable"
	_subject_rows({"xs": [null]}, "every xs", "first of s is 'a'", {})[0][2] == "null"
	_subject_report({"xs": [["a"]]}, "every xs", {"c": "item 2 of s is 'a'"}, {}).requirements.r.checks.c.expression == "item 2 of s is \"a\""
	_subject_problems("every xs", {"c": "first of s.k is 1"}) == ["first of s.k: nothing can follow s, which means the subject: for a field called s, write .s.k"]
}

test_a_walk_from_a_for_alias_that_is_null_fails_as_null_like_a_field_that_is_null if {
	_subject_rows({"xs": [null]}, "every xs", "every first of s is 1", {})[0][2] == "null"
	rep := _subject_report({"xs": [{"id": 1, "names": [null], "n": null}]}, "every xs", {"c": {"for": "every names as n", "assert": "every n.ys is 1"}, "d": "every .n.ys is 1"}, {})
	[r.cause | some r in rep.results; r.check in {"c", "d"}] == ["null", "null"]
}

test_a_position_on_a_for_alias_holding_a_list_reads_subject_as_subject_does_on_a_field if {
	rep := _subject_report({"xs": [{"id": 1, "bs": [["x", "y"], [], "s"]}]}, "every xs", {"c": {"for": "every bs as b", "assert": "first of b is \"x\""}}, {})
	[[f.item, f.cause] | some r in rep.results; r.check == "c"; some f in r.failed_items] == [["item 2 of bs", "absent"], ["item 3 of bs", "unusable"]]
}

test_subject_reads_the_location_of_the_subject_itself_and_of_each_item_of_a_list_subject if {
	doc := {"values": [1], "lists": [[1, 2]], "sets": [[3]]}
	plain := _subject_report(doc, "every values", {"c": "s is 1"}, {})
	[r.inputs | some r in plain.results; r.check == "c"] == [[{"name": "s", "value": 1, "locations": ["/values/0"]}]]
	list := _subject_report(doc, "every lists", {"c": "every s is 1 and count of s is 2"}, {})
	[r.inputs | some r in list.results; r.check == "c"] == [[
		{"name": "count of s", "value": 2, "locations": ["/lists/0/0", "/lists/0/1"]},
		{"name": "s[]", "value": [1, 2], "locations": ["/lists/0/0", "/lists/0/1"]},
	]]
	kept := _subject_report({"sets": [{"s": [3]}]}, "every sets whose some s is 1", {"c": ".s is not empty"}, {})
	[[r.inputs, r.failed_items] | some r in kept.results; r.check == "$applies"] == [[
		[{"name": ".s[]", "value": [3], "locations": ["/sets/0/s/0"]}],
		[{"cause": "value", "item": "item 1 of .s", "path": "item 1 of .s", "value": 3, "locations": ["/sets/0/s/0"]}],
	]]
}

test_an_applies_row_with_some_subject_names_its_failed_items_as_the_check_row_does if {
	doc := {"xs": [{"s": [1, 2]}, {"s": [3]}, {"s": []}, {"s": "s"}]}
	applies := [[r.subject.id, r.cause, r.failed_items] | some r in _subject_report(doc, "every xs whose some s is 1", {"c": ".s is not empty"}, {}).results; r.check == "$applies"]
	check := [[r.subject.id, r.cause, r.failed_items] | some r in _subject_report(doc, "every xs", {"c": "some .s is 1"}, {}).results; r.check == "c"]
	applies == check
	applies[1] == [{"s": [3]}, "value", [{"cause": "value", "item": "item 1 of .s", "path": "item 1 of .s", "value": 3, "locations": ["/xs/1/s/0"]}]]
	applies[2] == [{"s": []}, "value", [{"cause": "value", "item": ".s", "path": ".s", "value": [], "locations": ["/xs/2/s"]}]]
	applies[3] == [{"s": "s"}, "unusable", [{"cause": "unusable", "item": ".s", "path": ".s", "value": "s", "locations": ["/xs/3/s"]}]]
}

test_a_walk_keyed_by_the_subjects_field_reads_it_like_a_plain_check_and_one_keyed_by_an_item_field_lists_the_part_before_the_name if {
	nums := {"a": 1, "b": 2}
	rows := [{"key": "a", "n": 1}]
	doc := {"artifacts": [{"name": "x", "nums": nums, "prs": [{"id": 1, "key": "b", "keys": ["k1"], "rows": rows, "groups": [{"items": rows}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	policy := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {
		"plain": "some rows.n is at least artifact.nums named by key",
		"whose": "count of rows whose n is at least artifact.nums named by key is 1",
		"for": {"for": "every keys as k", "assert": "some rows.n is at least artifact.nums named by key"},
		"alias": {"for": "every groups as g", "assert": "some g.items.n is at least artifact.nums named by key"},
	}}}}
	got := {r.check: [r.cause, [i.name | some i in r.inputs], object.get(r, "message", "")] | some r in ergo.report(doc, policy, {}).results; not startswith(r.check, "$")}
	got == {
		"plain": ["value", ["artifact.nums named by key", "key", "rows[].n"], "item 1 of rows: n is 1, and artifact.nums named by key is 2"],
		"whose": ["satisfied", ["count of rows whose n is at least artifact.nums named by key", "rows[]", "artifact.nums"], ""],
		"for": ["value", ["artifact.nums named by key", "key", "keys[]", "rows[].n"], "item 1 of rows: n is 1, and artifact.nums named by key is 2"],
		"alias": ["value", ["artifact.nums named by key", "groups[]", "key"], "item 1 of groups: item 1 of g.items: n is 1, and artifact.nums named by key is 2"],
	}
}

test_a_walk_through_a_for_name_whose_part_before_the_name_walks_a_list_lists_nothing_of_it if {
	doc := {"artifacts": [{"name": "x", "ls": [{"m": {"a": 1}}, {"m": {"a": 2}}], "prs": [{"id": 1, "keys": ["a"]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	checks := {"c": {"for": "every keys as k", "assert": "every artifact.ls.m named by k is at least 1"}}
	rows := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[[i.name | some i in r.inputs] | some r in rows; r.check == "c"] == [["keys[]"]]
}

test_a_second_item_that_starts_at_input_or_params_keeps_its_dollar_in_the_list_and_failed_item_names if {
	doc := {"artifacts": [{"name": "a1", "pull_requests": [{"id": 1, "keys": ["k1"]}]}], "top": [11]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.pull_requests", "identified_by": "id"}}
	checks := {
		"i": {"for": "every keys as k, every $input.top as x", "assert": "x is at least 100"},
		"p": {"for": "every keys as k, some $params.l as x", "assert": "x is at least 100"},
	}
	rows := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {"l": [12]}).results
	[i.name | some r in rows; r.check == "i"; some i in r.inputs] == ["$input.top[]", "keys[]"]
	[i.name | some r in rows; r.check == "p"; some i in r.inputs] == ["$params.l[]", "keys[]"]
	[f.item | some r in rows; r.check == "i"; some o in r.failed_items; some a in o.failed_assertions; some f in a.items] == ["item 1 of $input.top"]
}

test_a_walk_keyed_by_the_subjects_field_whose_part_before_the_name_is_a_list_fails_as_unusable_and_lists_the_key if {
	doc := {"artifacts": [{"name": "x", "ls": [{"m": {"a": 1}}], "prs": [{"id": 1, "key": "a", "rows": [{"key": "a", "n": 1}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	checks := {"c": "some rows.n is at least artifact.ls.m named by key"}
	rows := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[[r.cause, [i.name | some i in r.inputs]] | some r in rows; r.check == "c"] == [["unusable", ["artifact.ls.m named by key", "key", "rows[].n"]]]
}

test_two_for_items_with_the_same_alias_are_given_twice_and_no_subject_or_part_is_involved if {
	_clash_problems({"x": "k1"}, {}, {"for": "every xs as y, every xs as y", "assert": "y.v is 1"}) == [["for: y is given twice"]]
}

test_an_alias_named_like_a_part_of_a_subject_that_is_not_an_ancestor_is_accepted if {
	extra := {"other": {"from": "bs", "identified_by": "id", "has": {"y": "k1"}}}
	_clash_problems({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.v is 1"}) == []
	_clash_rows({"x": "k1.k2.k3"}, extra, {"for": "every xs as y", "assert": "y.x.z is 7"}) == [["satisfied", true]]
	_part_clash_problems({"b": _clash_b, "other": extra.other, "kid": {"from": "every b.kids", "identified_by": "id", "has": {"y": "xs"}}}) == []
}

test_a_part_kept_through_two_narrowings_is_named_once_after_the_subject_that_declares_it if {
	subjects := {"base": {"from": "bs", "identified_by": "id", "has": {"x": "k1"}}, "m": {"from": "base whose id exists"}, "n": {"from": "m whose id exists", "has": {"x": "xs"}}}
	_part_clash_problems_of(subjects, "n") == [{"name": "subjects.n.has.x", "value": ["x can't be an alias: it's a part of base"], "locations": []}]
}

test_identified_by_stays_allowed_with_named_by_and_without_each_of if {
	rep := _from_report({"suites": {"g": [{"id": 1}]}}, {"suite": {"from": "every suites named by $params.g", "identified_by": "id"}}, {"c": "id exists"}, {"g": "g"})
	_from_problems(rep) == []
	[r.subject.id | some r in rep.results; r.check == "c"] == [1]
}

test_identified_by_that_cannot_be_read_on_a_subject_listed_by_named_by_each_of_gives_both_problems if {
	rep := _from_report({"suites": {}}, {"suite": {"from": "suites named by each of $params.names", "identified_by": "a b c"}}, {"c": "id exists"}, {"names": ["a"]})
	_from_problems(rep) == [{"name": "subjects.suite.identified_by", "value": ["identified_by is a path, like \"id\" or \"build.number\"", "not allowed with named by each of: the key is the id"], "locations": []}]
}

_pick_reads_first_cause(item, xs, ys) := [r.cause |
	some r in ergo.report({"s": [{"id": "a", "xs": xs, "ys": ys}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "s", "identified_by": "id"}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"for": concat("", ["every xs as p, ", item, " as q"]), "assert": "q.n is 1"}}}}}, {}).results
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
	some r in ergo.report({"s": [object.union({"id": "a", "xs": xs}, {k: ys | not miss; k := "ys"})]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "s", "identified_by": "id"}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"for": "every xs as p, first of ys whose k is p.k as q", "assert": "q.n is 1"}}}}}, {}).results
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
		"ergo_spec": ergo._spec,
		"subjects": {"a": {"from": "b whose x is $foo"}, "b": {"from": "a whose x is $foo"}},
		"requirements": {"r": {"subject": "a", "checks": {"c": "n exists"}}},
	}
	report := ergo.report({}, policy, {})
	object.keys(report.subjects) == {"a", "b"}
	report.subjects.a.from == "<invalid from>"
	report.subjects.a.identified_by == null
	report.subjects.b.identified_by == null
}

test_a_requirements_list_with_items_is_read_as_no_requirements if {
	rep := ergo.report({"xs": [{"x": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs"}}, "requirements": [{"subject": "s", "checks": {"c": "x exists"}}]}, {})
	object.keys(rep.requirements) == {"$policy"}
	[i.value | some i in rows_for(rep, "$policy", "$well_formed")[0].inputs; i.name == "requirements"] == [["not an object"]]
	count(rep.results) == 1
}

test_the_problems_of_parts_with_quoted_names_are_listed_in_the_order_the_report_writes_them if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs", "has": {"x\ty": "ys", "x y": "ys", "x\"y": "ys", "x": "ys"}}}, "requirements": {"r": {"subject": "s", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	[i.name | some i in rows_for(rep, "r", "$well_formed")[0].inputs; startswith(i.name, "subjects.")] == ["subjects.s.has.\"x y\"", "subjects.s.has.\"x\\\"y\"", "subjects.s.has.\"x\\ty\""]
}

test_a_ref_that_walks_a_list_of_objects_compares_with_what_it_reads_from_each_item if {
	_walk_right_rows("x is in $input.sbom.components.name", _walk_right_doc([{"name": "click"}, {"name": "jinja2"}]), {}) == [
		[true, "satisfied", ""],
		[false, "value", "x is \"attrs\", and $input.sbom.components[].name is [\"click\", \"jinja2\"]"],
	]
}

test_a_ref_that_walks_a_list_of_objects_is_listed_in_refs_with_the_location_of_each_item if {
	report := ergo.report(_walk_right_doc([{"name": "click"}, {"name": "jinja2"}]), _sentence_policy({"c": "x is in $input.sbom.components.name"}), {})
	report.requirements.s.checks.c["$refs"] == [{"name": "$input.sbom.components[].name", "value": ["click", "jinja2"], "locations": ["/sbom/components/0/name", "/sbom/components/1/name"]}]
}

test_a_param_that_walks_a_list_of_objects_compares_with_what_it_reads_from_each_item if {
	_walk_right_rows("x is in $params.deps.name", _walk_right_doc([]), {"deps": [{"name": "click"}]}) == [
		[true, "satisfied", ""],
		[false, "value", "x is \"attrs\", and $params.deps[].name is [\"click\"]"],
	]
}

test_a_ref_that_starts_at_a_list_input_walks_its_items if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {"c": {"description": "d", "assert": "id is in $input.id"}}}}}
	report := ergo.report([{"id": "a"}, {"id": "b"}], policy, {})
	[[r.passed, r.cause] | some r in report.results; r.check == "c"] == [[true, "satisfied"], [true, "satisfied"]]
	report.requirements.r.checks.c["$refs"] == [{"name": "$input[].id", "value": ["a", "b"], "locations": ["/0/id", "/1/id"]}]
}

test_a_ref_that_starts_at_a_list_input_fails_when_an_item_cant_be_read if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {"c": {"description": "d", "assert": "id is in $input.id"}}}}}
	every doc, want in {
		`[{"id": "a"}, {}]`: [[false, "absent", "item 2 of $input: id is missing"], [false, "absent", "id is missing, and item 2 of $input: id is missing"]],
		`[{"id": null}]`: [[false, "null", "id is null, and item 1 of $input: id is null"]],
		`[1]`: [[false, "unusable", "item 1 of $input is 1, which isn't an object"]],
		`[[{"id": "a"}]]`: [[false, "unusable", "item 1 of $input is [{\"id\": \"a\"}], which isn't an object"]],
	} {
		[[r.passed, r.cause, r.message] | some r in ergo.report(json.unmarshal(doc), policy, {}).results; r.check == "c"] == want
	}
}

test_named_by_each_of_a_ref_into_a_list_input_reads_one_list_and_does_not_walk_the_items if {
	m := {"x": {"v": 1}, "y": {"v": 2}}
	every doc in [[{"id": "a", "k": "x", "m": m}, {"id": "b", "k": "y"}], [{"id": "a", "k": "x", "m": m}]] {
		rep := ergo.report(doc, _list_key_policy({"from": "$input[0].m named by each of $input.k"}, "v is 1"), {})
		[[r.passed, r.cause] | some r in rep.results; r.check in {"$min_subjects", "c"}] == [[false, "unusable"]]
		rep.requirements.r.subjects == {"matching": 0, "total": 0}
	}
}

test_a_right_side_walks_a_list_input_whatever_another_check_reads_as_a_key if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {
		"c": {"description": "d", "assert": "id is in $input.k"},
		"d": {"description": "d", "assert": "m named by $input.k exists"},
	}}}}
	doc := [{"id": "x", "k": "x", "m": {"x": 1}}]
	rep := ergo.report(doc, policy, {})
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"c", "d"}] == [["c", true, "satisfied"], ["d", false, "not_an_object"]]
	rep.requirements.r.checks.c["$refs"] == [{"name": "$input[].k", "value": ["x"], "locations": ["/0/k"]}]
	rep.requirements.r.checks.d["$refs"] == [{"name": "$input.k", "value": null, "locations": [""]}]
}

test_a_check_decides_a_named_by_key_on_a_list_input_by_its_own_form_not_by_the_checks_beside_it if {
	doc := [{"id": "t", "k": "a", "m": {"a": "a"}, "rs": [{"v": "a"}]}]
	message := concat("", ["$input is ", ergo._text(doc), ", which isn't an object"])
	every params in [{}, {"k": null}, {"k": 3}] {
		every beside in [{"for": "every rs as r", "assert": "r.v is \"a\""}, "every rs.v is m named by $input.k", "some rs.v is m named by $input.k", "count of rs whose v is m named by $input.k is 1", "some rs whose v is m named by $input.k exists"] {
			policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"subject": "t", "checks": {"x": "k is $input.m named by $params.k", "z": beside}}}}
			[[r.cause, r.message] | some r in ergo.report(doc, policy, params).results; r.check == "x"] == [["not_an_object", message]]
		}
	}
}

test_a_count_of_a_child_subject_and_a_from_line_read_a_named_by_key_on_a_list_input_as_they_did_before if {
	doc := [{"id": "t", "k": "a", "m": {"a": "a"}, "rs": [{"v": "a"}], "xs": [{"m": {"a": "a"}}], "cs": [{"id": "c1", "k": "a"}]}]
	listed := "$input is [an object with 6 keys], which isn't an object"
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}, "c": {"from": "every t.cs", "identified_by": "id"}, "u": {"from": "$input whose k is $input.m named by $params.k", "identified_by": "id"}}, "requirements": {
		"r": {"subject": "t", "checks": {
			"plain": "k is $input.m named by $params.k",
			"count_whose": "count of rs whose v is $input.m named by $params.k is 1",
			"count_input": "count of xs.m named by $input.k is 1",
			"any_of_count": {"any_of": {"a": "k is $input.m named by $params.k", "b": "count of xs.m named by $input.k is 1"}},
		}},
		"s": {"subject": "c", "checks": {"child": "k is $input.m named by $params.k"}},
		"q": {"subject": "u", "checks": {"c": "id exists"}},
	}}
	every said in [
		[{}, "absent", "$params.k is missing", "$params.k is missing"],
		[{"k": null}, "null", "$params.k is null", "$params.k is null"],
		[{"k": 3}, "unusable", "$params.k is 3, which isn't text", listed],
	] {
		rows := {r.check: [r.cause, r.message] | some r in ergo.report(doc, policy, said[0]).results; r.check != "$min_subjects"; r.check != "$unique_ids"; r.check != "$unique_ancestor_ids"}
		rows == {
			"plain": ["not_an_object", listed],
			"count_whose": [said[1], said[3]],
			"count_input": ["unusable", "count of xs.m named by $input.k is 1 is false"],
			"any_of_count": ["unusable", concat("", ["a: ", said[2], "; b: the check is false"])],
			"child": [said[1], said[2]],
			"$applies": [said[1], said[2]],
		}
	}
}

test_a_for_sentence_reads_a_named_by_key_on_a_list_input_as_it_did_before if {
	doc := [{"id": "t", "k": "a", "m": {"a": "a"}, "rs": [{"v": "a"}]}]
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"subject": "t", "checks": {"z": {"for": "every rs as r", "assert": "k is \"a\" followed by $input.m named by $params.k"}}}}}
	every params in [[{}, "absent", "$params.k is missing"], [{"k": null}, "null", "$params.k is null"], [{"k": 3}, "unusable", "$params.k is 3, which isn't text"]] {
		[[r.cause, r.message] | some r in ergo.report(doc, policy, params[0]).results; r.check == "z"] == [[params[1], params[2]]]
	}
}

test_a_position_after_a_walked_ref_names_the_value_that_isnt_a_list if {
	every check, doc in {
		"id is in $input.l[0]": [{"id": "a", "l": ["a"]}, {"id": "b", "l": "ab"}],
		"id is in $input.o[0]": [{"id": "a", "o": {"x": 1}, "l": ["a"]}, {"id": "b", "o": {"x": 1}}],
	} {
		rows := [[r.passed, r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"]
		count(rows) == 2
		every row in rows {
			row[0] == false
			row[1] == "unusable"
			endswith(row[2], "which isn't a list")
		}
	}
	rows := [[r.cause, r.message] | some r in ergo.report({"w": [{"id": "a"}], "things": [{"id": "a"}]}, _list_key_policy({"from": "things", "identified_by": "id"}, "id is in $input.w.id[0]"), {}).results; r.check == "c"]
	rows == [["unusable", "item 1 of $input.w: id is \"a\", which isn't a list"]]
	past := [[r.cause, r.message] | some r in ergo.report([{"id": "a", "l": [{"x": "a"}]}, {"id": "b", "l": ["b"]}], _list_key_policy({"from": "$input", "identified_by": "id"}, "id is in $input.l[0].x"), {}).results; r.check == "c"]
	count(past) == 2
	every row in past {
		row[0] == "unusable"
		endswith(row[1], "is \"b\", which isn't an object")
	}
}

test_a_ref_that_starts_at_params_that_are_a_list_is_not_walked if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "$input", "identified_by": "id"}}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {"c": {"description": "d", "assert": "id is in $params.id"}}}}}
	report := ergo.report([{"id": "a"}], policy, [{"id": "a"}])
	[[r.passed, r.cause, r.message] | some r in report.results; r.check == "c"] == [[false, "unusable", "$params is [{\"id\": \"a\"}], which isn't an object"]]
	report.requirements.r.checks.c["$refs"] == [{"name": "$params.id", "value": null, "locations": ["$params:"]}]
}

test_a_right_side_that_starts_at_an_alias_that_is_a_list_walks_it_once if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {"c": {"description": "d", "for": "every deps as d", "assert": "id is in d.name"}}}}}
	walked := {"things": [{"id": "a", "deps": [[{"name": "a"}]]}]}
	[[r.passed, r.cause] | some r in ergo.report(walked, policy, {}).results; r.check == "c"] == [[true, "satisfied"]]
	nested := {"things": [{"id": "a", "deps": [[[{"name": "a"}]]]}]}
	[[r.passed, r.cause] | some r in ergo.report(nested, policy, {}).results; r.check == "c"] == [[false, "unusable"]]
}

test_named_by_each_of_a_list_read_through_a_list_fails_and_names_the_list if {
	m := {"x": {"v": 1}, "y": {"v": 1}}
	every pair in [[[{"k": "x"}, {"k": "y"}], "[{\"k\": \"x\"}, {\"k\": \"y\"}]"], [[], "[]"], [[["x"]], "[[\"x\"]]"], ["zz", "\"zz\""]] {
		rep := ergo.report({"m": m, "a": pair[0]}, _list_key_policy({"from": "$input.m named by each of $input.a.k"}, "v is 1"), {})
		[[r.check, r.passed, r.cause, r.message] | some r in rep.results; r.check in {"$min_subjects", "c"}] == [["$min_subjects", false, "unusable", concat("", ["$input.a is ", pair[1], ", which isn't an object"])]]
	}
}

test_a_walked_ref_names_the_value_that_isnt_a_list_when_another_item_holds_a_list_there if {
	every pair in [[{"x": 1}, "{\"x\": 1}"], ["zz", "\"zz\""], [5, "5"]] {
		doc := [{"id": "a", "o": [["a"]]}, {"id": "b", "o": pair[0]}]
		m := concat("", ["item 2 of $input: o is ", pair[1], ", which isn't a list"])
		[[r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, "id is in $input.o[0]"), {}).results; r.check == "c"] == [["unusable", m], ["unusable", m]]
	}
}

test_a_ref_that_reads_into_something_missing_fails_as_it_did_before_the_walk if {
	every doc in [{"sbom": {}}, {"sbom": {"components": {"a": 1}}}] {
		every row in _walk_right_rows("x is in $input.sbom.components.name", object.union(doc, {"things": [{"id": "t1", "x": "a"}]}), {}) {
			row[1] == "absent"
			row[2] == "$input.sbom.components.name is missing"
		}
	}
}

test_a_path_that_ends_at_a_list_is_not_walked_after_its_last_step if {
	_walk_right_rows("x is in $input.sbom.names", {"sbom": {"names": []}, "things": [{"id": "t1", "x": "a"}]}, {}) == [[false, "value", "x is \"a\", and $input.sbom.names is []"]]
}

test_a_field_that_walks_a_list_of_objects_lists_what_it_reads_in_the_rows_inputs if {
	rows := _sentence_rows({"c": "x is in deps.name"}, {"things": [{"id": "t1", "x": "a", "deps": [{"name": "a"}, {"name": "b"}]}]}, {})
	rows == [["c", true, "satisfied", [{"name": "x", "value": "a", "locations": ["/things/0/x"]}, {"name": "deps[].name", "value": ["a", "b"], "locations": ["/things/0/deps/0/name", "/things/0/deps/1/name"]}]]]
}

_walk_rights := [
	{"v": [{"z": "a"}]},
	{"v": [{"z": "a"}, {"z": "b"}]},
	{"v": [{"z": "a"}, {}]},
	{"v": [{"z": null}]},
	{"v": [{"z": ["a"]}]},
	{"v": [{"z": "^a"}]},
	{"v": [{"y": 1}]},
	{"v": ["s"]},
	{"v": [null]},
	{"v": [[{"z": "a"}]]},
]

test_a_field_that_walks_after_is_in_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("is in", ".z", right)
	}
}

test_a_field_that_walks_after_is_not_in_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("is not in", ".z", right)
	}
}

test_a_field_that_walks_after_contains_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("contains", ".z", right)
	}
}

test_a_field_that_walks_after_does_not_contain_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("does not contain", ".z", right)
	}
}

test_a_field_that_walks_after_contains_all_of_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("contains all of", ".z", right)
	}
}

test_a_field_that_walks_after_contains_none_of_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("contains none of", ".z", right)
	}
}

test_a_field_that_walks_after_matches_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("matches", ".z", right)
	}
}

test_a_field_that_walks_after_does_not_match_gives_the_verdict_and_cause_of_the_same_walk_in_params if {
	every right in _walk_rights {
		_list_same_as_params("does not match", ".z", right)
	}
}

test_a_path_that_walks_on_the_left_stays_unusable_even_when_the_right_is_the_same_path if {
	_walk_right_rows("deps.name is in deps.name", {"things": [{"id": "t1", "deps": [{"name": "a"}]}]}, {}) == [[false, "unusable", "deps is [{\"name\": \"a\"}], which isn't an object"]]
}

test_a_whose_that_reads_a_ref_that_walks_an_empty_list_leaves_the_item_out_as_a_value if {
	rows := _walk_right_rows("every deps.name whose x is in $input.sbom.components.name is \"a\"", {"sbom": {"components": []}, "things": [{"id": "t1", "deps": [{"name": "a", "x": "a"}]}]}, {})
	rows == [[false, "value", "deps is [{\"name\": \"a\", \"x\": \"a\"}]"]]
}

test_a_whose_that_reads_a_ref_that_walks_an_empty_list_decides_before_its_left_side_is_looked_at if {
	rows := _walk_right_rows("every deps.name whose tags contains some of $input.sbom.components.name is \"a\"", {"sbom": {"components": []}, "things": [{"id": "t1", "deps": [{"name": "a", "tags": "text"}]}]}, {})
	[row[1] | some row in rows] == ["value"]
}

test_a_path_that_starts_at_a_part_walks_and_names_the_part if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"repo": {"from": "repos", "identified_by": "id", "has": {"lock": "lockfile"}}},
		"requirements": {"s": {"subject": "repo", "checks": {"c": "id is in lock.pkgs.name"}}},
	}
	rows := [r | some r in ergo.report({"repos": [{"id": "click", "lockfile": {"pkgs": [{"name": "click"}]}}]}, policy, {}).results; r.check == "c"]
	rows[0].inputs[1] == {"name": "lock.pkgs[].name", "value": ["click"], "locations": ["/repos/0/lockfile/pkgs/0/name"], "part": {"id": null, "name": "lock"}}
}

test_a_leading_dot_on_a_right_side_that_walks_reads_the_field_and_not_the_part if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"repo": {"from": "repos", "identified_by": "id", "has": {"lock": "lockfile"}}},
		"requirements": {"s": {"subject": "repo", "checks": {"dot": "x is in .lock.pkgs.name", "part": "x is in lock.pkgs.name"}}},
	}
	doc := {"repos": [{"id": "r", "x": "a.py", "lockfile": {"pkgs": [{"name": "a.py"}]}, "lock": {"pkgs": [{"name": "nope"}]}}]}
	[[r.check, r.cause] | some r in ergo.report(doc, policy, {}).results; not startswith(r.check, "$")] == [["dot", "value"], ["part", "satisfied"]]
}

_dot_policy(checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"repo": {"from": "repos", "identified_by": "id", "has": {"lock": "lockfile"}}},
	"requirements": {"s": {"subject": "repo", "checks": checks}},
}

_dot_rows(lock) := _dot_summary(ergo.report({"repos": [{"id": "r", "x": "a", "lockfile": {"pkgs": [{"name": "a"}]}, "lock": lock}]}, _dot_policy({"c": "x is in .lock.pkgs.name"}), {}).results)

test_a_leading_dot_on_a_right_side_that_walks_fails_as_absent_when_an_item_of_the_field_has_no_name if {
	_dot_rows({"pkgs": [{"name": "a"}, {}]}) == [{"cause": "absent", "message": "item 2 of .lock.pkgs: name is missing", "names": ["x", ".lock.pkgs[].name"]}]
}

test_a_leading_dot_on_a_right_side_that_walks_fails_as_null_when_the_field_is_null if {
	_dot_rows(null) == [{"cause": "null", "message": ".lock is null", "names": ["x", ".lock.pkgs.name"]}]
}

test_a_leading_dot_on_a_right_side_that_walks_fails_as_null_when_an_item_of_the_field_has_a_null_name if {
	_dot_rows({"pkgs": [{"name": null}]}) == [{"cause": "null", "message": "item 1 of .lock.pkgs: name is null", "names": ["x", ".lock.pkgs[].name"]}]
}

test_a_leading_dot_on_a_right_side_that_walks_fails_as_unusable_when_the_field_holds_text if {
	_dot_rows({"pkgs": "text"}) == [{"cause": "unusable", "message": ".lock.pkgs is \"text\", which isn't an object", "names": ["x", ".lock.pkgs.name"]}]
}

test_a_leading_dot_on_a_right_side_that_walks_fails_as_value_when_the_list_of_the_field_is_empty if {
	_dot_rows({"pkgs": []}) == [{"cause": "value", "message": "x is \"a\", and .lock.pkgs is []", "names": ["x", ".lock.pkgs[].name"]}]
}

test_a_leading_dot_on_a_right_side_keeps_its_dot_when_an_item_of_the_field_is_not_an_object if {
	_dot_rows({"pkgs": ["t"]}) == [{"cause": "unusable", "message": "item 1 of .lock.pkgs is \"t\", which isn't an object", "names": ["x", ".lock.pkgs[].name"]}]
}

test_a_leading_dot_on_a_right_side_leaves_its_dot_out_when_an_item_is_not_an_object_and_nothing_has_its_name if {
	_dot_plain_rows("x is in .lock.pkgs.name", {"repos": [{"id": "r", "x": "a", "lock": {"pkgs": ["t"]}}]}) == [{"cause": "unusable", "message": "item 1 of lock.pkgs is \"t\", which isn't an object", "names": ["x", "lock.pkgs[].name"]}]
}

test_a_params_path_that_starts_with_a_position_names_the_item_that_is_not_an_object if {
	every case in [[[1], "1"], [[[1]], "[1]"], [[[true]], "[true]"], [[["x"]], "[\"x\"]"]] {
		params_position_messages == {
			"c": concat("", ["item 1 of $params is ", case[1], ", which isn't an object"]),
			"d": concat("", ["item 1 of $params is ", case[1], ", which isn't an object"]),
			"e": concat("", ["item 1 of $params is ", case[1], ", which isn't an object"]),
		} with data.params as case[0]
	}
}

test_a_params_path_through_params_that_are_not_a_list_or_an_object_names_them_on_every_side if {
	every case in [[3, "3"], ["s", "\"s\""], [true, "true"], [false, "false"]] {
		params_key_messages.d == concat("", ["$params is ", case[1], ", which isn't a list"]) with data.params as case[0]
		params_key_messages.f == concat("", ["$params is ", case[1], ", which isn't a list"]) with data.params as case[0]
	}
}

test_a_subject_name_on_the_right_of_a_for_whose_reads_the_subject_and_not_a_missing_field if {
	doc := {"xs": [{"id": "i", "k": [{"v": "i"}, {"v": "j"}]}]}
	rows := _subject_rows(doc, "every xs", {"for": "every k whose v is s as e", "assert": "e is an object"}, {})
	[r[2] | some r in rows] == ["unusable"]
	[i.name | some i in rows[0][3]] == ["k[]"]
	counted := _subject_rows(doc, "every xs", {"for": "every k whose v is count of s as e", "assert": "e is an object"}, {})
	[r[2] | some r in counted] == ["unusable"]
	_subject_rows(doc, "every xs", "count of k whose v is s is 1", {})[0][2] == "unusable"
}

test_a_dot_in_a_from_whose_reads_the_field_named_like_the_subject if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"kid": {"from": "every kids whose .kid is 1"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": ".x is 1"}}}}
	rep := ergo.report({"kids": [{"kid": 1, "x": 1}, {"kid": 2, "x": 1}, {"x": 1}]}, policy, {})
	[[r.cause, r.message] | some r in rep.results; r.check == "$applies"; r.cause != "satisfied"] == [["value", ".kid is 2"], ["absent", ".kid is missing"]]
	[r.passed | some r in rep.results; r.check == "c"] == [true]
}

_rooted_field_rows(doc) := [[r.check, r.cause, r.message] | some r in ergo.report({"ts": [doc]}, {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "ts", "identified_by": "id"}}, "requirements": {"r": {"subject": "t", "checks": {"w": "every rows.n is at least m named by k", "p": "m named by k is 1"}}}}, {}).results; r.check in {"w", "p"}]

test_a_named_by_field_on_the_right_of_every_reads_the_subjects_key_and_never_an_items if {
	_rooted_field_rows({"id": 1, "k": null, "m": null, "rows": [{"n": 3}]}) == [["p", "null", "m is null; k is null"], ["w", "null", "m is null; k is null"]]
	_rooted_field_rows({"id": 1, "k": null, "m": {}, "rows": [{"n": 3}]}) == [["p", "null", "k is null"], ["w", "null", "k is null"]]
	_rooted_field_rows({"id": 1, "k": "m", "m": 3, "rows": [{"n": 3, "k": "n"}, {"n": 4}]}) == [["p", "unusable", "m is 3, which isn't an object"], ["w", "unusable", "m is 3, which isn't an object"]]
}

test_an_alias_named_by_the_subjects_field_on_the_right_of_every_lists_the_key_and_never_the_alias if {
	doc := {"things": [{"id": 1, "k": "z", "ys": [{"z": 1}], "xs": [{"v": 1}]}]}
	rows := _sentence_rows({"c": {"for": "every ys as y", "assert": "every xs.v equals y named by k"}}, doc, {})
	[i.name | some i in rows[0][3]] == ["k", "xs[].v", "ys[]"]
}

test_a_root_that_isnt_a_list_after_is_in_fails_before_any_item_is_read if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id", "has": {"pl": "c"}}}, "requirements": {"r": {"subject": "pr", "checks": {
		"subject": "count of xs whose v is in pr.z is 0",
		"part": "every xs.v, if any, is not in pl.z",
		"params": "count of xs whose v is in $params.q is 0",
		"for": {"for": "every xs whose v is in pr.z as m", "assert": "m.v is 1"},
	}}}}
	rep := ergo.report({"prs": [{"id": "p", "c": {"z": 5}, "z": "s", "xs": []}]}, policy, {"q": "s"})
	msgs := {r.check: [r.cause, r.message] | some r in rep.results; not startswith(r.check, "$")}
	msgs == {
		"subject": ["unusable", "pr.z is \"s\", which isn't a list"],
		"part": ["unusable", "pl.z is 5, which isn't a list"],
		"params": ["unusable", "$params.q is \"s\", which isn't a list"],
		"for": ["unusable", "pr.z is \"s\", which isn't a list; xs is []"],
	}
}

test_two_list_roots_of_the_wrong_type_are_both_named_on_a_list_with_items if {
	rows := _root_rows({"c": "count of xs whose v is in $params.l and whose w is in pr.l is 0"}, {"id": "p", "l": 3, "xs": [{"v": 1, "w": 1}, {}]}, {"l": "s"})
	rows.c == ["unusable", "$params.l is \"s\", which isn't a list; pr.l is 3, which isn't a list"]
}

test_every_root_that_failed_is_named_whatever_its_cause if {
	rows := _root_rows({"c": "every xs whose w is in pr.l and whose v is in $params.l, if any, exists"}, {"id": "p", "l": "s", "xs": []}, {"l": null})
	rows.c == ["unusable", "pr.l is \"s\", which isn't a list; $params.l is null"]
}

test_a_bare_params_in_a_whose_is_read_once_with_no_item_in_front if {
	whose := {"c": {"for": "every xs whose v is in $params as m", "assert": "m.v is 1"}}
	_root_rows(whose, {"id": "p", "xs": [{"v": 1}, {"v": 2}]}, null).c == ["absent", "$params is missing"]
	_root_rows(whose, {"id": "p", "xs": []}, 3).c == ["unusable", "$params is 3, which isn't an object"]
	count_whose := {"c": "count of xs whose v is in $params is 0"}
	_root_rows(count_whose, {"id": "p", "xs": [{"v": 1}, {"v": 2}]}, 3).c == ["unusable", "$params is 3, which isn't a list"]
	_root_rows(count_whose, {"id": "p", "xs": []}, null).c == ["absent", "$params is missing"]
}

test_an_item_that_isnt_an_object_and_a_null_item_under_a_named_by_key_are_each_said_once if {
	rows := _item_rows(_named_by_policy, {"prs": [{"id": "p0", "xs": ["s", null]}]}, {"l": 1})
	every check in ["every", "if_any", "two"] {
		rows[check] == ["not_an_object", "item 1 of xs is \"s\", which isn't an object; item 2 of xs: m is null"]
	}
}

test_a_named_by_key_that_is_null_or_missing_or_not_text_keeps_saying_each_item_once if {
	rows := _item_rows(_named_by_policy, {"prs": [{"id": "p0", "xs": [{"k": null}, {}, {"k": 1}]}]}, {})
	rows.every == ["unusable", "item 1 of xs: k is null; m is {\"k\": null}, which isn't text; item 2 of xs: m is {}, which isn't text; item 3 of xs: m is {\"k\": 1}, which isn't text"]
}

test_a_walk_judges_an_item_with_short_numbers_beside_an_item_with_long_ones if {
	subjects := [
		{"id": "over", "limit": 1234567890.1209567890, "prs": [{"commits": [{"n": 1}]}, {"commits": [{"n": 1234567890.1209567990}]}]},
		{"id": "equal", "limit": 1234567890.1209567890, "prs": [{"commits": [{"n": 1}]}, {"commits": [{"n": 1234567890.1209567890}]}]},
	]
	policy := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "every prs.commits.n is at most limit"}}}
	{[x.subject.id, x.passed] | some x in report({"items": subjects}, policy).results; x.check == "c"} == {["over", false], ["equal", true]}
}

test_missing_or_empty_params_leave_items_that_arent_objects_as_not_an_object if {
	every params in [null, {}] {
		rows := _item_rows(_params_cause_policy, {"prs": [{"id": "p0", "xs": ["s", {"v": "x"}]}]}, params)
		rows.plain[0] == "not_an_object"
		rows.some[0] == "not_an_object"
	}
}

_said_once_report(check, os) := ergo.report(
	{"os": os, "cs": [{"id": "c1", "os": os, "rows": [{"v": "bob", "n": 2}, {"v": "ann", "n": 2}], "ms": [{"ws": [{"v": "bob", "n": 2}, {"v": "ann", "n": 2}]}]}]},
	{"ergo_spec": ergo._spec, "subjects": {"c": {"from": "cs", "identified_by": "id", "has": {"pos": "os"}}}, "requirements": {"r": {"subject": "c", "checks": {"c": check}}}},
	{},
)

test_an_every_whose_says_a_walked_parts_problem_once_with_no_item if {
	rep := _said_once_report("every rows whose v is in pos.name exists", [{"name": "bob"}, {}])
	_parts_row(rep, "c").cause == "absent"
	_parts_row(rep, "c").message == "item 2 of pos: name is missing"
	mixed := _said_once_report("every rows whose v is in pos.name exists", [{"name": "bob"}, {"name": 3}])
	_parts_row(mixed, "c").message == "pos[].name is [\"bob\", 3], which isn't a list of one kind of value"
}

test_a_for_line_count_says_a_walked_input_lists_kind_problem_once if {
	rep := _said_once_report({"for": "every ms as m", "assert": "count of m.ws whose v is in $input.os.name is 2"}, [{"name": "bob"}, {"name": 3}])
	_parts_row(rep, "c").cause == "unusable"
	_parts_row(rep, "c").message == "$input.os[].name is [\"bob\", 3], which isn't a list of one kind of value"
}
