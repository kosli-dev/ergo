package ergo_test

import data.ergo
import rego.v1

test_a_subject_that_is_not_an_object_shows_up_as_a_violation if {
	[v.check | some v in ergo.violations(report(mixed_subjects, mixed_req))] == ["$min_subjects", "c", "c", "c"]
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

test_violations_carry_the_cause if {
	rep := report({"items": [{"id": "a"}]}, {"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
		"checks": {"c": "state is \"MERGED\""},
	}})
	[v.cause | some v in ergo.violations(rep)] == ["absent"]
}

test_a_violation_for_a_from_that_reads_nothing_says_what_failed if {
	rep := report({}, min_subjects_req(0))
	[[v.description, v.expression, v.cause] | some v in ergo.violations(rep)] == [["The thing list can be read", "items can be read", "absent"]]
}

test_a_from_that_reads_nothing_lists_its_min_subjects_row_as_a_violation if {
	rep := report({}, min_subjects_req(0))
	[[v.check, v.cause] | some v in ergo.violations(rep)] == [["$min_subjects", "absent"]]
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

test_some_with_min_subjects_zero_still_denies_when_no_subject_passes if {
	rep := report(split_across_subjects, some_req_zero)
	rep.requirements.s.status == "not_met"
	count(ergo.violations(rep)) > 0
}

failing_row := {"requirement": "s", "subject": {"id": 1, "type": "t"}, "check": "c", "passed": false, "inputs": [], "cause": "value"}

test_violations_keep_the_failing_rows_of_a_requirement_whose_status_is_not_met_missing_or_unknown if {
	kept := [count(ergo.violations({"requirements": {"s": entry}, "results": [failing_row]})) |
		some entry in [{"status": "not_met"}, {}, {"status": "maybe"}, {"status": true}, {"satisfied": true}]
	]
	kept == [1, 1, 1, 1, 1]
}

test_a_violation_keeps_its_row_message_and_a_row_without_one_is_still_a_violation if {
	with_message := object.union(failing_row, {"message": "x is 4"})
	vs := ergo.violations({"requirements": {"s": {}}, "results": [with_message, failing_row]})
	[object.get(v, "message", "none") | some v in vs] == ["x is 4", "none"]
}

test_violations_drop_the_failing_rows_of_a_requirement_that_is_met_or_not_applicable if {
	kept := [count(ergo.violations({"requirements": {"s": {"status": s}}, "results": [failing_row]})) |
		some s in ["met", "not_applicable"]
	]
	kept == [0, 0]
}

test_violations_are_empty_for_a_compliant_report if {
	rep := report({"items": [{"id": "a", "signed": true, "reviewed": true}]}, violating_req)
	rep.compliant == true
	ergo.violations(rep) == []
}

test_violation_entry_carries_exactly_the_documented_keys if {
	rep := report({"items": [{"id": "a"}]}, violating_req)
	count(ergo.violations(rep)) == 2
	every v in ergo.violations(rep) {
		object.keys(v) == {"requirement", "subject", "check", "description", "expression", "inputs", "cause", "message"}
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
		"message": "reviewed is missing",
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

test_some_on_a_child_subject_is_not_met_by_a_passing_child_under_another_parent if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {
			"commit": {"from": "commits", "identified_by": "sha"},
			"pull request": {"from": "every commit.pull_requests", "identified_by": "number"},
		},
		"requirements": {"reviewed": {"subject": "pull request", "require": "some", "checks": {"approved": "approved_by is a non-empty string"}}},
	}
	rep := ergo.report(
		{"commits": [
			{"sha": "a1", "pull_requests": [{"number": 7, "approved_by": "bob"}, {"number": 8}]},
			{"sha": "a2", "pull_requests": [{"number": 9}]},
		]},
		policy, {},
	)
	rep.requirements.reviewed.status == "not_met"
	rep.requirements.reviewed.causes == [{"cause": "absent", "rows": 1}]
	[v.subject | some v in ergo.violations(rep)] == [{"type": "pull request", "id": 9, "in": {"commit": "a2"}}]
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

test_an_unreadable_filter_is_reported_as_a_violation if {
	rep := report({"rounds": [{"id": "r1"}]}, degraded_req("every"))
	[[v.subject.id, v.check, v.cause] | some v in ergo.violations(rep)] == [["r1", "$applies", "absent"]]
}

test_a_subject_ruled_out_by_one_filter_still_fails_the_requirement_when_another_filter_cannot_be_read if {
	req := degraded_req_whose("every", concat(" and whose ", [degraded_only, merged_only]))
	rep := report({"rounds": [{"id": "r1", "state": "CLOSED"}]}, req)
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "absent"
	[v.check | some v in ergo.violations(rep)] == ["$applies"]
}

test_a_present_filter_rules_out_a_subject_whose_field_is_missing if {
	rep := report({"packages": [{"id": "a"}]}, locked_req("lock"))
	rep.requirements.s.status == "not_applicable"
	rep.requirements.s.subjects == {"total": 1, "matching": 0}
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$applies")] == [[false, "value"]]
	ergo.violations(rep) == []
}

test_a_ref_step_renders_and_is_recorded_like_any_ref if {
	rep := report(trail_doc, trail_req(attested)) with data.params as {"artifact": "app", "att": "junit"}
	rep.requirements.s.checks.c.expression == `attestations named by $params.att.status is "COMPLETE"`
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.att", "value": "junit", "locations": ["$params:/att"]}]
	ergo.violations(rep)[0].inputs == [{"name": "attestations named by $params.att.status", "value": "FAILED", "locations": ["/trail/artifacts/app/attestations/junit/status"]}, {"name": "$params.att", "value": "junit", "locations": ["$params:/att"]}]
}

test_a_ref_step_in_from_that_cannot_be_read_shows_up_in_violations if {
	vs := ergo.violations(report(trail_doc, trail_req("fingerprint exists"))) with data.params as {}
	[[v.check, v.cause, v.inputs] | some v in vs] == [["$min_subjects", "absent", [{"name": "in-scope subject count", "value": 0, "locations": []}, {"name": "$params.artifact", "value": null, "locations": ["$params:"]}]]]
}

test_a_badly_written_filter_stops_the_requirement_even_when_another_condition_rules_the_subject_out if {
	rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": `things whose x is one of 1, "a" and whose y exists`}}), {})
	stopped(rep)
	rep.requirements.s.status == "not_met"
	[v.check | some v in ergo.violations(rep)] == ["$well_formed"]
}

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

test_a_from_line_with_every_that_reads_a_missing_param_keeps_its_requirement_and_fails_min_subjects if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "every x named by $params.k", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}
	every case in [[{}, "absent"], [{"k": null}, "null"], [{"k": ["x"]}, "unusable"]] {
		rep := ergo.report({"x": [{"id": 1}]}, policy, case[0])
		rep.requirements.s.status == "not_met"
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, case[1]]]
		count(ergo.violations(rep)) == 1
	}
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

test_assertions_joined_with_and_or_listed_under_assert_give_one_row_that_names_the_ones_that_failed if {
	doc := {"prs": [{"id": "late", "username": "bob", "author": "ann", "ts": 1, "last_commit": 2}, {"id": "gone", "username": "ann", "author": "ann", "last_commit": 2}]}
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"s": {"subject": "pr", "checks": {
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

test_an_applies_row_that_fails_with_a_cause_other_than_value_is_a_violation_with_the_failed_items_or_assertions if {
	some_rep := _from_report(_releases, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	some_violations := {v.subject.id: object.filter(v, ["failed_items", "failed_assertions"]) | some v in ergo.violations(some_rep); v.check == "$applies"}
	some_violations.unset == {"failed_items": [{"path": "files", "item": "files", "cause": "absent", "value": null, "locations": ["/releases/3"]}]}
	some_violations.null.failed_items[0].cause == "null"
	not "mixed" in object.keys(some_violations)
	not "docs" in object.keys(some_violations)
	many_rep := _from_report(_releases, {"release": {"from": `releases whose ticket is "ok" and whose every files.path matches "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	many_violations := {v.subject.id: object.filter(v, ["failed_items", "failed_assertions"]) | some v in ergo.violations(many_rep); v.check == "$applies"}
	many_violations.unset == {"failed_assertions": [{"assertion": `every files.path matches "^docs/"`, "cause": "absent"}]}
	not "mixed" in object.keys(many_violations)
}

test_a_violation_lists_a_ref_once_when_the_row_lists_it_already if {
	rep := ergo.report({"things": [{"id": "t", "x": "z"}]}, _sentence_policy({"c": "x is in $params.k"}), {"k": ["a"]})
	[v.inputs | some v in ergo.violations(rep)] == [[
		{"name": "x", "value": "z", "locations": ["/things/0/x"]},
		{"name": "$params.k", "value": ["a"], "locations": ["$params:/k"]},
	]]
}

test_a_violation_carries_the_tags_of_the_row_it_copies if {
	rep := _parts_report(_tag_has, {"c": "coverage.hunks_total is 99"}, _tag_doc)
	violation := [v | some v in ergo.violations(rep); v.check == "c"][0]
	violation.inputs[0] == {"name": "coverage.hunks_total", "part": {"id": "att-7", "name": "coverage"}, "value": 25, "locations": ["/trail/dd/cov/hunks_total"]}
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
		{"path": "artifacts[0].pull_requests", "item": "artifacts[0].pull_requests", "cause": "unusable", "value": [{"url": "pr/7", "approvals": 2}], "locations": ["/artifacts/0/pull_requests"]},
		{"path": "item 1 of artifacts[0].pull_requests", "item": "item 1 of artifacts[0].pull_requests", "cause": "unusable", "value": {"url": "pr/7", "approvals": 2}, "locations": ["/artifacts/0/pull_requests/0"]},
		{"path": "artifacts[1].pull_requests", "item": "artifacts[1].pull_requests", "cause": "absent", "value": null, "locations": ["/artifacts/1"]},
		{"path": "artifacts[2].pull_requests", "item": "artifacts[2].pull_requests", "cause": "null", "value": null, "locations": ["/artifacts/2/pull_requests"]},
		{"path": "artifacts[3].pull_requests", "item": "artifacts[3].pull_requests", "cause": "unusable", "value": "none", "locations": ["/artifacts/3/pull_requests"]},
	]]]
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "c"] == [["pr/7", "satisfied"], ["none", "not_an_object"]]
	rep.requirements.r.status == "not_met"
	[[v.check, v.failed_items[0].path] | some v in ergo.violations(rep); v.check == "$min_subjects"] == [["$min_subjects", "artifacts[0].pull_requests"]]
	missing := _from_report({"artifacts": [{"pull_requests": [{"url": "pr/7"}]}, {}]}, _every_prs, {"c": "url exists"}, {})
	[r.cause | some r in missing.results; r.check == "$min_subjects"] == ["absent"]
	zero := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _every_prs, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	[r.cause | some r in zero.results; r.check == "$min_subjects"] == ["unusable"]
	zero.requirements.r.status == "not_met"
}

test_a_failed_line_lists_its_values_in_the_violations_too if {
	check := {"for": "some approvers as approver, every commits as commit", "assert": "approver.t is more than commit.t"}
	r := ergo.report({"things": [{"id": 1, "approvers": [{"t": 5}], "commits": [{"t": 9}]}]}, _sentence_policy({"c": check}), {})
	[v.failed_items[0].failed_assertions[0].items[0].inputs | some v in ergo.violations(r); v.check == "c"] == [[
		{"name": "approver.t", "value": 5, "locations": ["/things/0/approvers/0/t"]},
		{"name": "commit.t", "value": 9, "locations": ["/things/0/commits/0/t"]},
	]]
}

test_a_ref_in_refs_has_its_location_and_a_violation_copies_it if {
	rep := ergo.report({"things": [{"id": "t1", "x": "z"}]}, _sentence_policy({"c": "x is in $params.allowed"}), {"allowed": ["p", "q"]})
	rep.requirements.s.checks.c["$refs"] == [{"name": "$params.allowed", "value": ["p", "q"], "locations": ["$params:/allowed"]}]
	[r.inputs | some r in rep.results; r.check == "c"] == [[
		{"name": "x", "value": "z", "locations": ["/things/0/x"]},
		{"name": "$params.allowed", "value": ["p", "q"], "locations": ["$params:/allowed"]},
	]]
	[v.inputs | some v in ergo.violations(rep)] == [[
		{"name": "x", "value": "z", "locations": ["/things/0/x"]},
		{"name": "$params.allowed", "value": ["p", "q"], "locations": ["$params:/allowed"]},
	]]
}

test_a_policy_with_no_requirements_has_a_violation_for_the_row_that_says_so if {
	rep := ergo.report({}, {"ergo_spec": ergo._spec}, {})
	rep.compliant == false
	ergo.violations(rep) == [{
		"requirement": "$policy",
		"subject": {"type": "$policy", "id": "$policy"},
		"check": "$well_formed",
		"description": "The policy is written correctly",
		"expression": "count(problems) == 0",
		"inputs": [{"name": "requirements", "value": ["missing"], "locations": []}],
		"cause": "value",
		"message": "requirements: missing",
	}]
}

test_a_set_of_requirements_reads_as_none if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs"}}, "requirements": {{"subject": "s", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	rep.compliant == false
	object.keys(rep.requirements) == {"$policy"}
	[i.value | some i in rows_for(rep, "$policy", "$well_formed")[0].inputs; i.name == "requirements"] == [["not an object"]]
	[v.requirement | some v in ergo.violations(rep)] == ["$policy"]
}
