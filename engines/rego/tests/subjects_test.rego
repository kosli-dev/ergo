package ergo_test

import data.ergo
import rego.v1

test_array_from_yields_one_subject_per_element if {
	subject_counts({"items": [{"id": "a"}, {"id": "b"}]}, "items") == {"total": 2, "matching": 2}
}

test_single_object_from_is_wrapped_as_one_subject if {
	subject_counts({"item": {"id": "a"}}, ".item") == {"total": 1, "matching": 1}
}

test_missing_from_yields_no_subjects if {
	subject_counts({"other": [{"id": "a"}]}, "items") == {"total": 0, "matching": 0}
}

test_a_subject_that_is_not_an_object_keeps_its_rows if {
	rows := rows_for(report(mixed_subjects, mixed_req), "s", "c")
	[[r.subject.id, r.passed, r.cause] | some r in rows] == [
		["x", true, "satisfied"],
		["b", false, "not_an_object"],
		[null, false, "not_an_object"],
		[3, false, "not_an_object"],
	]
}

test_a_subject_that_is_not_an_object_is_not_mistaken_for_one_missing_its_fields if {
	causes := {r.subject.id: r.cause | some r in rows_for(report({"items": [{"id": "x"}, "b"]}, mixed_req), "s", "c")}
	causes == {"x": "value", "b": "not_an_object"}
}

test_empty_from_treats_the_whole_document_as_one_subject if {
	subject_counts({"id": "root"}, "$input") == {"total": 1, "matching": 1}
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

test_out_of_scope_subject_gets_no_check_rows if {
	rep := report(two_states, scoped_req(merged_only))
	ids := {r.subject.id | some r in rep.results; r.check == "c"}
	ids == {"a"}
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

test_a_missing_filter_rules_a_subject_with_the_field_out if {
	rep := report({"items": [{"id": "a", "draft": true}, {"id": "b"}]}, scoped_req("draft does not exist"))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
	rep.compliant == true
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

test_one_row_per_subject_and_check if {
	doc := {"items": [{"id": "a"}, {"id": "b"}]}
	rep := report(doc, two_check_req)
	count([r | some r in rep.results; not startswith(r.check, "$")]) == 4

	count(rep.results) == 7
}

test_rows_are_produced_even_for_an_empty_subject if {
	rep := report({"items": [{}]}, two_check_req)
	check_rows := [r | some r in rep.results; not startswith(r.check, "$")]
	count(check_rows) == 2
	every row in check_rows {
		row.passed == false
	}
}

lockfile_req(conditions) := {"s": {"from": whose_line("items", conditions), "identified_by": "id", "min_subjects": 0, "checks": {"c": "hashed is true"}}}

lockfile_scope(item, conditions) := [rep.requirements.s.status, [r.cause | some r in rows_for(rep, "s", "$applies")]] if {
	rep := report({"items": [item]}, lockfile_req(conditions))
}

test_a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_other_filters_read if {
	filters := "status exists and whose status is \"COMPLETE\""
	lockfile_scope({"id": 1}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": null}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1}, concat(" and whose ", [filters, "owner is \"me\""])) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "PENDING"}, filters) == ["not_applicable", ["value"]]
	lockfile_scope({"id": 1, "status": "COMPLETE", "hashed": true}, filters) == ["met", ["satisfied"]]
}

test_some_not_met_when_checks_are_split_across_subjects if {
	report(split_across_subjects, require_req("some")).requirements.s.status == "not_met"
}

test_some_not_met_without_subjects if {
	report({"items": []}, require_req("some")).requirements.s.status == "not_met"
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

test_a_typo_in_the_subject_from_path_is_not_compliant if {
	report({"items": [{"id": "a"}]}, id_req("itmes")).compliant == false
}

test_out_of_scope_subject_is_recorded_as_evidence if {
	rep := report(two_states, scoped_req(merged_only))
	some row in rep.results
	row.subject.id == "b"
}

test_an_unreadable_filter_makes_the_policy_not_compliant if {
	report({"rounds": [{"id": "r1"}]}, degraded_req("every")).compliant == false
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

test_a_present_filter_still_fails_on_a_subject_that_is_not_an_object if {
	rep := report({"packages": ["a"]}, locked_req("lock"))
	rep.requirements.s.status == "not_met"
	[r.cause | some r in rows_for(rep, "s", "$applies")] == ["not_an_object"]
}

test_an_input_path_reads_from_the_top_for_a_subject_that_is_not_an_object if {
	r := row_in({"mode": "strict"}, "a", "$input.mode is \"strict\"")
	[r.passed, r.cause] == [true, "satisfied"]
}

test_a_ref_step_in_from_finds_the_subjects if {
	rep := report(trail_doc, trail_req("fingerprint exists")) with data.params as {"artifact": "app"}
	rep.requirements.s.subjects == {"total": 1, "matching": 1}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(trail.artifacts named by $params.artifact)) >= 1"
	rep.requirements.s.checks["$min_subjects"]["$refs"] == [{"name": "$params.artifact", "value": "app", "locations": ["$params:/artifact"]}]
	rep.requirements.s.status == "met"
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

sbom_reqs := {
	"versions": {"subject": "locked SBOM package", "checks": {"matches_lock": "sbom_release equals lock_release"}},
	"named": {"subject": "non-exempt SBOM package", "checks": {"named": "name is a non-empty string"}},
}

built_problems(subjects) := well_formed_problems(ergo.report(sbom_doc, subject_policy(subjects, {"v": sbom_reqs.versions}), {}), "v")

test_problems_with_the_subject_built_on_are_named_after_it if {
	base := {"from": 5}
	built_problems(object.union(sbom_subjects, {"SBOM package": base})) == [{"name": "subjects.\"SBOM package\".from", "value": ["not a string"], "locations": []}]
}

test_subjects_that_are_only_out_of_scope_are_not_causes if {
	causes_of([causes_doc.deployments[1], causes_doc.deployments[2]], approved_check) == [{"cause": "absent", "rows": 1}]
}

test_a_derived_check_works_as_a_filter if {
	subjects := {"pr": {"from": "prs whose count of files is more than 10", "identified_by": "n"}}
	reqs := {"r": {"subject": "pr", "checks": {"reviewed": "reviewer exists"}}}
	rep := ergo.report({"prs": [{"n": 1, "files": array.concat(numbers.range(1, 11), []), "reviewer": "ann"}, {"n": 2, "files": [1]}, {"n": 3}]}, subject_policy(subjects, reqs), {})
	[[r.subject.id, r.passed, r.cause] | some r in rep.results; r.check == "$applies"] == [[1, true, "satisfied"], [2, false, "value"], [3, false, "absent"]]
	rep.requirements.r.status == "not_met"
}

test_a_name_hides_the_subject_field_with_the_same_name if {
	check := {"for": "every xs as x", "assert": `x is "a"`}
	[row[1] | some row in _for_rows(check, [{"id": 1, "x": "b", "xs": ["a"]}], {})] == ["satisfied"]
}

test_a_subject_with_no_from_reads_the_input_field_named_like_it if {
	doc := {"artifact": {"fingerprint": "sha256:abc", "signed": true}}
	every def in [null, {}, {"identified_by": "fingerprint"}] {
		[[r[1], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": def}, {"c": "signed is true"}, {}))] == [["c", "satisfied"]]
	}
	[[r[0], r[2]] | some r in _from_rows(_from_report(doc, {"artifact": {"from": "$input", "identified_by": "artifact.fingerprint"}}, {"c": ".artifact.signed is true"}, {}))] == [["sha256:abc", "satisfied"]]
}

test_a_subjects_own_name_in_its_own_from_is_the_input_field if {
	own := ergo.report({"lockfile": {"status": "COMPLETE"}}, {"ergo_spec": ergo._spec, "subjects": {"lockfile": {"from": `lockfile whose status is "COMPLETE"`}}, "requirements": {"r": {"subject": "lockfile", "checks": {"c": "status exists"}}}}, {})
	_from_problems(own) == []
	[r.cause | some r in own.results; r.check == "c"] == ["satisfied"]
}

test_a_top_level_subject_read_from_an_input_that_is_not_an_object_keeps_its_cause if {
	_chain_min_cause(_chain_report("x", _plain_chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id"}]]
	_chain_min_cause(_chain_report(null, _plain_chain, {"c": "url exists"}, {})) == [["null", {"type", "id"}]]
}

test_a_narrowing_subject_takes_its_id_from_the_one_it_narrows if {
	subjects := {"defect": {"from": "defects", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical"`, "identified_by": "team"}}
	_from_problems(_narrow_report(subjects, "critical defect")) == [{"name": `subjects."critical defect".identified_by`, "value": ["not allowed on a subject that narrows another"], "locations": []}]
}

test_a_subject_name_that_isnt_a_string_gives_the_same_report_with_strict_builtins if {
	rep := ergo.report({"defects": [{"id": 1}]}, {"ergo_spec": ergo._spec, "subjects": {1: {"from": "defects whose id exists"}}, "requirements": {"r": {"subject": "c", "checks": {"c": "id exists"}}}}, {})
	rep.requirements.r.status == "not_met"
}

test_a_subject_cant_build_on_a_subject_read_from_another_yet if {
	doc := {"artifacts": [{"fingerprint": "a1", "prs": [{"url": "p1", "ok": true}]}], "prs": [{"url": "elsewhere", "ok": true}]}
	base := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "pr": {"from": "every artifact.prs", "identified_by": "url"}}
	every pair in [[{"from": "pr whose ok is true"}, "from"]] {
		rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": object.union(base, {"okpr": pair[0]}), "requirements": {"r": {"subject": "okpr", "checks": {"c": "url exists"}}}}, {})
		_from_problems(rep) == [{"name": concat("", ["subjects.okpr.", pair[1]]), "value": ["can't build on a subject read from another subject yet"], "locations": []}]
		stopped(rep)
	}
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

test_named_by_a_field_on_a_subject_that_isnt_an_object_fails_as_not_an_object if {
	rows := [[r.subject.id, r.cause] | some r in ergo.report({"things": ["x"]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "$params.limits named by severity is 1"}}}}, {"limits": {"x": 1}}).results; r.check == "c"]
	rows == [["x", "not_an_object"]]
}

test_a_listed_subject_carries_exactly_the_documented_keys if {
	rep := ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}}, "requirements": _listed_reqs("d")}, {})
	object.keys(rep.subjects.d) == {"description", "from", "identified_by", "parts"}
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

test_a_subject_that_is_not_an_object_still_gets_an_entry if {
	every def in ["ds", 1, true, ["ds"]] {
		_listed({"d": def}, "d").d == {"description": "", "from": "<invalid from>", "identified_by": null, "parts": {}}
	}
}

test_a_subject_nothing_builds_on_or_reads_from_is_not_listed_even_when_it_looks_related if {
	subjects := {"round": {"from": "rounds"}, "done": {"from": "round whose state is \"done\""}}
	object.keys(_listed(subjects, "round")) == {"round"}
}

test_a_subjects_section_that_is_not_an_object_lists_nothing if {
	every subjects in [null, true, 1, "d", []] {
		ergo.report({}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": _listed_reqs("d")}, {}).subjects == {}
	}
}

test_the_swap_comparison_sees_a_subject_that_is_not_an_object if {
	nothing := _swap_scenarios.the_part_field_is_text
	rep := ergo.report(nothing.doc, _swap_policy(_swap_has, _swap_group_checks("fors", _swap_alias)), nothing.params)
	{"unusable"} - {r.cause | some r in rep.results; startswith(r.check, "f")} == set()
}

test_a_list_read_with_named_by_a_subject_field_fails_closed_when_the_key_is_unusable if {
	rows := _sentence_rows({"c": "x is in $params.lists named by kind"}, _named_things, _named_params)
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [false, "absent"], [false, "absent"], [false, "unusable"]]
}

test_a_subject_that_leads_into_a_loop_is_named_after_its_own_from if {
	every subjects in [
		{"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}},
		{"pa": {"from": "every pb.x"}, "pb": {"from": "every pa.x"}, "pc": {"from": "every pa.kids"}},
		{"pa": {"from": "every pb.x"}, "pb": {"from": "every pa.x"}, "pc": {"from": "pa"}},
	] {
		subject_problems(subjects, "pc", {}) == [{"name": "subjects.pc.from", "value": ["leads to a loop"], "locations": []}]
	}
}

test_a_path_from_the_input_starts_at_the_root_of_the_input_whatever_the_subject if {
	_located_rows({"c": "n is at most $input.limits.high"}, {"limits": {"high": 9}, "things": [{"id": "t1", "n": 3}]}, {}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$input.limits.high", "locations": ["/limits/high"]}]]]
	_located_rows({"c": "n is at most $input.limits.high"}, {"limits": [1], "things": [{"id": "t1", "n": 3}]}, {}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$input.limits.high", "locations": ["/limits"]}]]]
}

test_a_subject_read_from_the_values_of_an_object_starts_at_its_escaped_key if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"scan": {"from": "scans named by each of $params.required"}}, "requirements": {"s": {"subject": "scan", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"scans": {"sast": {"x": 1}, "sca/x": {"x": 2}, "a~b": {}}}, policy, {"required": ["sast", "sca/x", "a~b", "secrets"]})
	[[r.subject.id, r.inputs[0].locations] | some r in rep.results; r.check == "c"] == [
		["a~b", ["/scans/a~0b"]],
		["sast", ["/scans/sast/x"]],
		["sca/x", ["/scans/sca~1x/x"]],
		["secrets", ["/scans"]],
	]
}

test_subject_is_the_subject_itself_when_the_subject_is_a_string if {
	_subject_rows(
		{"deployment": {"id": "d-17", "regions": ["eu-west-1", "us-east-1"]}},
		"every deployment.regions",
		"s is one of $params.allowed_regions",
		{"allowed_regions": ["eu-west-1"]},
	) == [
		["eu-west-1", true, "satisfied", [{"name": "s", "value": "eu-west-1", "locations": ["/deployment/regions/0"]}, {"name": "$params.allowed_regions", "value": ["eu-west-1"], "locations": ["$params:/allowed_regions"]}]],
		["us-east-1", false, "value", [{"name": "s", "value": "us-east-1", "locations": ["/deployment/regions/1"]}, {"name": "$params.allowed_regions", "value": ["eu-west-1"], "locations": ["$params:/allowed_regions"]}]],
	]
	rep := _subject_report({"deployment": {"regions": ["eu-west-1"]}}, "every deployment.regions", {"c": "s is one of $params.allowed_regions"}, {"allowed_regions": ["eu-west-1"]})
	rep.requirements.r.checks.c.expression == "s is in $params.allowed_regions"
}

_subject_phrases := [
	"is an object", "is a string", "is a list", "is a number", "exists", "does not exist", "is empty", "is not empty",
	"is a non-empty string", "is at least 2", "is not 1", "is one of 1, 2", "is one of $params.l", "equals $params.n",
	"contains 'a'", "contains all of 1, 2", "matches 'a'", "starts with 'a'", "is before '2020-01-01T00:00:00Z'",
	"is between 1 and 3", "is alphabetically before 'b'",
]

_subject_values := [null, "a", 1, "", [], {}, [1, 2], {"k": 1}, true, "2019-01-01T00:00:00Z"]

_subject_by_value(rows) := {json.marshal(r[3][0].value): [r[1], r[2]] | some r in rows}

test_subject_fails_like_a_field_that_holds_the_same_value if {
	every phrase in _subject_phrases {
		params := {"l": [1], "n": 1}
		got := _subject_by_value(_subject_rows({"xs": _subject_values}, "every xs", concat(" ", ["s", phrase]), params))
		want := _subject_by_value(_subject_rows({"xs": [{"id": i, "x": v} | some i, v in _subject_values]}, "every xs", concat(" ", ["x", phrase]), params))
		count(got) == count(_subject_values)
		got == want
	}
}

test_subject_is_an_object_passes_for_an_object_and_fails_for_anything_else if {
	_subject_by_value(_subject_rows({"xs": [{"a": 1}, "s", null, 3, [1]]}, "every xs", "s is an object", {})) == {
		`{"a":1}`: [true, "satisfied"],
		`"s"`: [false, "value"],
		"null": [false, "null"],
		"3": [false, "value"],
		"[1]": [false, "value"],
	}
}

test_subject_on_a_null_subject_fails_as_null_and_on_the_wrong_type_as_value_or_unusable if {
	rows := _subject_by_value(_subject_rows({"xs": [null, "a", 3]}, "every xs", "s is at least 2", {}))
	rows == {"null": [false, "null"], `"a"`: [false, "unusable"], "3": [true, "satisfied"]}
	_subject_by_value(_subject_rows({"xs": [null, "a", 3]}, "every xs", "s is a string", {})) == {"null": [false, "null"], `"a"`: [true, "satisfied"], "3": [false, "value"]}
}

test_a_subjects_name_reads_the_subject_and_never_a_field_with_the_same_name if {
	_subject_rows({"xs": [{"id": "a", "s": 1}]}, "every xs", "s is 1", {}) == [[{"id": "a", "s": 1}, false, "unusable", [{"name": "s", "value": {"id": "a", "s": 1}, "locations": ["/xs/0"]}]]]
}

test_subject_works_after_and_and_in_an_any_of_option_and_names_the_subject if {
	rows := _subject_rows({"xs": [1, 2]}, "every xs", "s is 1 and s is a number", {})
	[[r[0], r[1], r[2]] | some r in rows] == [[1, true, "satisfied"], [2, false, "value"]]
	_subject_report({"xs": [1, 2]}, "every xs", {"c": "s is 1 and s is a number"}, {}).results[4].failed_assertions == [{"assertion": "s is 1", "cause": "value"}]
	options := _subject_rows({"xs": [1, "a", null]}, "every xs", {"any_of": {"num": "s is a number", "str": ["s is a string", "s is 'a'"]}}, {})
	[[r[0], r[1], r[2]] | some r in options] == [[1, true, "satisfied"], ["a", true, "satisfied"], [null, false, "null"]]
	_subject_report({"xs": [1]}, "every xs", {"c": {"any_of": {"num": "s is a number", "str": "s is a string"}}}, {}).requirements.r.checks.c.expression == "one of: num(s is a number) | str(s is a string)"
}

_subject_named(subjects, subject) := [i | some r in ergo.report({"xs": [1]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": subject, "checks": {"c": "x exists"}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

test_a_subject_called_it_reads_the_subject_like_any_other_name if {
	_subject_named({"it": {"from": "xs"}}, "it") == []
	rep := ergo.report({"xs": [1, 2]}, {"ergo_spec": ergo._spec, "subjects": {"it": {"from": "every xs"}}, "requirements": {"r": {"subject": "it", "checks": {"c": "it is 1"}}}}, {})
	[[r.subject.id, r.passed] | some r in rep.results; r.check == "c"] == [[1, true], [2, false]]
}

_subject_position_sentences := [
	"first of X is 1", "item 2 of X is 'x'", "first of X exists",
	"first of X does not exist", "first of X is not empty", "first of X is a string", "first of X is one of 1, 2",
	"every first of X is 1", "some item 2 of X is 1", "count of first of X is 1", "sum of item 2 of X is 3",
	"every X is a string", "some X is a string", "count of X is 2", "sum of X is 3", "X is a list",
]

_subject_position_values := [[1, "x"], [], "s", null, [["a"], "b"], {"k": 1}, {}, 3, true]

_subject_shape(rows) := json.marshal([[r.passed, r.cause, _unlocated(r.inputs), _unlocated(object.get(r, "failed_items", null))] | some r in rows])

_unlocated(entries) := [{k: v | some k, v in e; k != "locations"} | some e in entries] if entries != null

_unlocated(null) := null

_subject_field_shape(rows) := replace(replace(replace(replace(_subject_shape(rows), `"v[`, `"s[`), `"v"`, `"s"`), ` of v"`, ` of s"`), ` of v[`, ` of s[`)

_subject_rows_of(doc, from, text) := [r | some r in _subject_report(doc, from, {"c": text}, {}).results; r.check == "c"]

test_a_position_on_subject_reads_and_names_like_the_same_position_on_a_field if {
	every text in _subject_position_sentences {
		on_it := _subject_rows_of({"xs": _subject_position_values}, "every xs", replace(text, "X", "s"))
		on_field := _subject_rows_of({"xs": [{"id": i, "v": v} | some i, v in _subject_position_values]}, "every xs", replace(text, "X", "v"))
		count(on_it) == count(_subject_position_values)
		_subject_shape(on_it) == _subject_field_shape(on_field)
	}
}

test_the_subjects_name_in_a_plus_term_reads_the_subject_on_either_side if {
	_subject_rows({"xs": [[1, 2]]}, "every xs", "count of s plus 1 is 3", {})[0][1] == true
	_subject_rows({"xs": [[1, 2]]}, "every xs", "count of s plus count of $params.ys is 3", {"ys": [0]})[0][1] == true
	_subject_rows({"xs": [[1, 2]]}, "every xs", "2 plus count of s is 4", {})[0][1] == true
}

test_nothing_can_follow_a_subjects_name_in_an_any_of_option if {
	_subject_problems("every xs", {"c": {"any_of": {"a": "s.name is 1", "b": "x exists"}}}) == ["option a: s.name: nothing can follow s, which means the subject: for a field called s, write .s.name"]
	_subject_problems("every xs", {"c": {"any_of": {"a": ["x exists", "s.name is 1"], "b": "x exists"}}}) == ["option a: s.name: nothing can follow s, which means the subject: for a field called s, write .s.name"]
}
