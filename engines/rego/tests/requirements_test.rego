package ergo_test

import data.ergo
import rego.v1

test_applies_to_narrows_matching_but_leaves_total_intact if {
	rep := report(two_states, scoped_req(merged_only))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_applies_to_checks_are_conjunctive if {
	both := concat(" and whose ", [merged_only, "base_ref is \"main\""])
	doc := {"items": [
		{"id": "a", "state": "MERGED", "base_ref": "main"},
		{"id": "b", "state": "MERGED", "base_ref": "topic"},
	]}
	rep := report(doc, scoped_req(both))
	rep.requirements.s.subjects == {"total": 2, "matching": 1}
}

test_empty_applies_to_matches_everything if {
	rep := report(two_states, scoped_req(""))
	rep.requirements.s.subjects == {"total": 2, "matching": 2}
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
	both := concat(" and whose ", [merged_only, "base_ref is \"main\""])
	rep := report(two_states, scoped_req(both))

	rep.requirements.s.checks["$applies"].expression == `state is "MERGED" and base_ref is "main"`
}

test_no_applies_to_means_no_applies_rows_or_definition if {
	rep := report(two_states, id_req("items"))
	count([r | some r in rep.results; r.check == "$applies"]) == 0
	not "$applies" in object.keys(rep.requirements.s.checks)
}

test_min_subjects_is_described_like_any_number if {
	rep := report({"xs": []}, {"s": {"from": "xs", "min_subjects": 2.0, "checks": {"c": "x exists"}}})
	rep.requirements.s.checks["$min_subjects"].description == "The in-scope subject count is at least 2"
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

test_min_subjects_guards_a_missing_collection if {
	rep := report({}, min_subjects_req(1))
	rows_for(rep, "s", "$min_subjects")[0].passed == false
	rep.compliant == false
}

test_min_subjects_fails_with_the_cause_of_a_from_it_cannot_read_even_at_zero if {
	every doc, cause in {
		"{}": "absent",
		`{"items": null}`: "null",
	} {
		every n in [0, 1] {
			rep := report(json.unmarshal(doc), min_subjects_req(n))
			[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
			rep.requirements.s.status == "not_met"
			rep.compliant == false
		}
	}
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
	req := {"s": object.union(min_subjects_req(0).s, {"from": "every builds[1].items"})}
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

test_min_subjects_fails_when_from_has_steps_and_the_document_is_not_an_object if {
	every doc, cause in {"null": "absent", `"x"`: "unusable", `[{"items": []}]`: "unusable"} {
		rep := report(json.unmarshal(doc), min_subjects_req(0))
		[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, cause]]
	}
}

test_min_subjects_at_zero_names_the_input_when_there_is_no_from if {
	req := {"s": object.union(min_subjects_req(0).s, {"from": "$input"})}
	report({}, req).requirements.s.checks["$min_subjects"].expression == "$input can be read"
}

test_unique_ids_fails_a_some_requirement_too if {
	policy := {"s": object.union(owner_req.s, {"require": "some"})}
	rep := report({"repos": [{"name": "a", "owner": "bob"}, {"name": "a", "owner": ""}]}, policy)
	rep.requirements.s.status == "not_met"
}

test_unique_ids_reads_a_subject_that_is_not_an_object_as_its_own_id if {
	unique_ids_row({"repos": ["api", "api", "web"]}, owner_req) == [[{"name": "repeated repo ids", "value": ["api"], "locations": ["/repos/0", "/repos/1"]}], false, "value"]
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

test_a_report_from_a_policy_json_cannot_hold_is_left_as_built_so_rows_still_name_their_requirement if {
	every policy in [{1: typed_req}, [typed_req]] {
		rep := report({"items": [{"id": 1.50}]}, policy)
		every row in rep.results {
			rep.requirements[row.requirement].status == "not_met"
		}
	}
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

test_a_policy_with_ergo_spec_and_no_requirements_is_still_not_compliant if {
	ergo.report({"items": [{"id": 1}]}, {"ergo_spec": ergo._spec, "requirements": {}}, {}).compliant == false
}

test_a_min_subjects_past_a_float_is_out_of_range_not_over_a_million if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": 1e400})})
	problem_inputs(rep) == [{"name": "min_subjects", "value": ["number out of range"], "locations": []}]
}

test_a_requirement_that_is_not_an_object_finds_no_subjects_so_it_cannot_claim_the_whole_input if {
	rep := report({"items": [{"id": 1}]}, {"s": 5})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
	stopped(rep)
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

test_some_with_min_subjects_zero_is_not_applicable_when_empty if {
	rep := report({"items": []}, some_req_zero)
	rep.requirements.s.status == "not_applicable"
	rep.compliant == true
}

test_some_without_min_subjects_zero_still_denies_an_empty_collection if {
	report({"items": []}, require_req("some")).requirements.s.status == "not_met"
}

test_some_with_min_subjects_zero_is_not_applicable_when_the_filter_empties_the_scope if {
	scoped := {"s": object.union(some_req_zero.s, {"from": whose_line("items", merged_only)})}
	report({"items": [{"id": "a", "state": "CLOSED"}]}, scoped).requirements.s.status == "not_applicable"
}

test_not_compliant_when_any_requirement_is_not_met if {
	doc := {"a": [{"id": "1"}], "b": [{"no_id": true}]}
	policy := {
		"first": {"subject_type": "t", "from": ".a", "identified_by": "id", "checks": {"c": "id exists"}},
		"second": {"subject_type": "t", "from": "b", "identified_by": "id", "checks": {"c": "id exists"}},
	}
	report(doc, policy).compliant == false
}

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

test_a_malformed_requirement_is_never_met_under_some if malformed_ones_fail_and_say_why("some")

test_a_malformed_requirement_is_never_met_under_a_bad_require if {
	count(malformed("most")) > 0
	malformed_ones_fail_and_say_why("most")
}

test_a_policy_with_no_requirements_is_not_compliant if {
	report({"items": []}, {}).compliant == false
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

test_a_filter_value_of_the_wrong_type_fails_the_requirement_instead_of_leaving_the_subject_out if {
	rep := report({"rounds": [{"id": "r1", "degraded": "yes"}]}, degraded_req("every"))
	rep.requirements.s.status == "not_met"
	rows_for(rep, "s", "$applies")[0].cause == "unusable"
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

test_a_policy_without_requirements_is_not_compliant if {
	has_only_the_policy_row(ergo.report({"items": [{"id": 1}]}, {}, {}))
	has_only_the_policy_row(ergo.report({"items": [{"id": 1}]}, {"ergo_spec": ergo._spec, "requirements": {}}, {}))
	has_only_the_policy_row(ergo.report({"items": [{"id": 1}]}, {"requirments": params_req("id exists")}, {}))
}

test_requirements_that_are_not_an_object_are_not_compliant if {
	every reqs in [null, true, 1, "", "s", []] {
		has_only_the_policy_row(ergo.report({"items": [{"id": 1}]}, {"ergo_spec": ergo._spec, "requirements": reqs}, {}))
	}
	ergo.report({"items": [{"id": 1}]}, {"ergo_spec": ergo._spec, "requirements": [params_req("id exists").s]}, {}).compliant == false
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

test_a_requirement_that_is_not_an_object_is_not_compliant if {
	report(one_item, {"s": 5}).compliant == false
}

test_a_set_in_the_input_fails_a_requirement_that_has_no_subjects if {
	req := {"s": object.union(json_only_req.s, {"min_subjects": 0})}
	report({"items": [], "tags": {"prod"}}, req).requirements.s.status == "not_met"
}

test_a_requirement_name_that_is_not_a_string_fails_the_requirement_and_the_policy if {
	every policy in [{1: json_only_req.s}] {
		rep := report({"items": [{"id": "a", "x": 1}]}, policy)
		rep.compliant == false
		some name, r in rep.requirements
		r.status == "not_met"
		some row in rep.results
		[row.requirement, row.check, row.passed] == [name, "$well_formed", false]
		row.inputs[0] == {"name": "requirement name", "value": ["not a string"], "locations": []}
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

test_a_requirement_can_name_the_subject_others_build_on if {
	rep := ergo.report(sbom_doc, subject_policy(sbom_subjects, {"all": {"subject": "SBOM package", "checks": {"named": "name is a non-empty string"}}}), {})
	rep.compliant == true
	rep.requirements.all.subjects == {"total": 3, "matching": 3}
}

test_a_requirement_that_holds_has_no_causes if {
	met := ergo.report({"deployments": [causes_doc.deployments[0], causes_doc.deployments[2]]}, causes_policy(approved_check), {}).requirements.r
	[met.status, met.causes] == ["met", []]
	policy := causes_policy(approved_check)
	optional := object.union(policy, {"requirements": {"r": object.union(policy.requirements.r, {"min_subjects": 0})}})
	not_applicable := ergo.report({"deployments": [causes_doc.deployments[2]]}, optional, {}).requirements.r
	[not_applicable.status, not_applicable.causes] == ["not_applicable", []]
}

test_an_assert_object_takes_only_description_and_meta if {
	_sentence_problems({"assert": 1}) == ["invalid assert"]
	_sentence_problems({"assert": 1, "description": 2}) == ["invalid assert", "invalid description"]
	_sentence_problems({"assert": "x exists", "meta": []}) == ["invalid meta"]
	ergo.report({"things": []}, _sentence_policy({"c": {"assert": 1}}), {}).requirements.s.checks.c.expression == "<invalid assert>"
}

test_a_release_the_condition_cannot_decide_fails_its_requirement_and_does_not_drop_out_of_scope if {
	rep := _from_report(_releases, {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	rep.requirements.r.status == "not_met"
	{c.cause | some c in rep.requirements.r.causes; c.cause != "value"} == {"absent", "null", "unusable"}
}

test_the_applies_row_of_a_from_condition_named_by_the_subjects_field_lists_the_key_like_a_plain_check if {
	subjects := object.union(_atts_subjects, {"pr": {"from": "every artifact.pull_requests whose some commits.author is artifact.atts named by k.owner", "identified_by": "id"}})
	rep := ergo.report(_atts_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id exists"}}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "$applies"] == [["artifact.atts named by k.owner", "commits[].author", "k"]]
}

test_the_report_lists_a_subject_with_its_description_from_and_id if {
	subjects := {"deployment": {"from": `deployments whose environment is "prod"`, "identified_by": "id", "description": "A deployment to production"}}
	_listed(subjects, "deployment") == {"deployment": {"description": "A deployment to production", "from": `deployments whose environment is "prod"`, "identified_by": "id", "parts": {}}}
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

test_no_subject_is_listed_when_no_requirement_names_one if {
	ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}}, "requirements": {"r": {"checks": {"c": "id exists"}}}}, {}).subjects == {}
	ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}}}, {}).subjects == {}
	ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}}, "requirements": {"r": {"subject": "nope", "checks": {"c": "id exists"}}}}, {}).subjects == {}
}

test_a_requirement_reports_the_name_of_its_subject if {
	rep := ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}, "e": {"from": "es"}}, "requirements": {"a": {"subject": "d", "checks": {"c": "id exists"}}, "b": {"subject": "e", "checks": {"c": "id exists"}}}}, {})
	{name: entry.subject | some name, entry in rep.requirements} == {"a": "d", "b": "e"}
}

test_a_requirement_reports_no_subject_when_it_names_none_or_one_that_is_not_there if {
	every req in [{"checks": {"c": "id exists"}}, {"subject": "nope", "checks": {"c": "id exists"}}, {"subject": 1, "checks": {"c": "id exists"}}, {"subject": null, "checks": {"c": "id exists"}}, {"subject": ["d"], "checks": {"c": "id exists"}}] {
		ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {"d": {"from": "ds"}}, "requirements": {"r": req}}, {}).requirements.r.subject == null
	}
	ergo.report({}, {"ergo_spec": ergo._spec, "subjects": [], "requirements": _listed_reqs("d")}, {}).requirements.r.subject == null
}

test_a_requirement_field_named_like_the_facts_ergo_works_out_once_is_unknown_and_stops_the_requirement if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pr_att": "atts.pr"}}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	doc := {"artifacts": [{"fingerprint": "a", "atts": {"pr": {"id": "x"}}, "pull_requests": [{"url": "pr/7"}]}, {"fingerprint": "b", "pull_requests": [{"url": "pr/8"}]}]}
	plain := {"subject": "pull request", "checks": {"c": "url exists and artifact.pr_att.id exists"}}
	odd := object.union(plain, {"ergo/fixed": {"each_step": [{"each_as": "x"}], "has_parts": true, "tagging": false, "scoped": false}})
	clean := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": plain}}, {})
	marked := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": odd}}, {})
	stopped(marked)
	[r.subject.id | some r in clean.results; r.check == "c"] == ["pr/7", "pr/8"]
	[i | some r in marked.results; r.check == "$well_formed"; some i in r.inputs; i.name == `"ergo/fixed"`] == [{"name": `"ergo/fixed"`, "value": ["unknown field"], "locations": []}]
}

test_a_check_named_like_one_of_ergos_own_rows_leaves_only_ergos_check_in_the_requirement if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {"$well_formed": "id is 2", "$applies": "id is 2"}})})
	object.keys(rep.requirements.s.checks) == {"$min_subjects", "$unique_ids", "$well_formed"}
	rep.requirements.s.checks["$well_formed"].expression == "count(problems) == 0"
}

test_an_applies_row_lists_an_input_read_by_two_conditions_once_with_its_location if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things whose state is \"live\" and whose state is not \"old\"", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"things": [{"id": "t1", "state": "live", "x": 1}, {"id": "t2", "state": "old"}]}, policy, {})
	[[r.subject.id, r.inputs] | some r in rep.results; r.check == "$applies"] == [
		["t1", [{"name": "state", "value": "live", "locations": ["/things/0/state"]}]],
		["t2", [{"name": "state", "value": "old", "locations": ["/things/1/state"]}]],
	]
}

test_two_equal_plain_values_fail_unique_ids_and_are_still_checked_with_it if {
	rep := _subject_report({"xs": ["a", "a", "b"]}, "every xs", {"c": "s is a string"}, {})
	uniq := [r | some r in rep.results; r.check == "$unique_ids"]
	uniq[0].passed == false
	uniq[0].inputs == [{"name": "repeated s ids", "value": ["a"], "locations": ["/xs/0", "/xs/1"]}]
	[[r.subject.id, r.passed] | some r in rep.results; r.check == "c"] == [["a", true], ["a", true], ["b", true]]
	rep.compliant == false
}

test_a_policy_with_a_requirement_gets_no_policy_requirement_of_its_own if {
	policy := {"ergo_spec": "v9.9", "subjects": {"s": {"from": "xs"}}, "requirements": {"r": {"subject": "s", "checks": {"c": "x exists"}}}}
	rep := ergo.report({}, policy, {})
	object.keys(rep.requirements) == {"r"}
	every row in rep.results {
		row.requirement == "r"
	}
}

test_a_field_compared_with_itself_in_a_requirement_without_a_subject_gives_no_advice if {
	rep := ergo.report({}, {"ergo_spec": ergo._spec, "subjects": {}, "requirements": {"r": {"checks": {"c": "count of xs whose x equals x is 2"}}}}, {})
	some r in rep.results
	r.check == "$well_formed"
	some i in r.inputs
	i.name == "checks.c"
	i.value == ["x is compared with itself, because in a whose it's read from the item"]
}
