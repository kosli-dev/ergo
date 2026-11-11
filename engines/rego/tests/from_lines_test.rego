package ergo_test

import data.ergo
import rego.v1

test_a_from_line_that_ends_at_text_gives_it_as_one_subject if {
	subject_counts({"items": "not-a-collection"}, "items") == {"total": 1, "matching": 1}
}

test_a_from_that_reads_nothing_fails_a_some_requirement_at_zero_which_an_empty_list_leaves_not_applicable if {
	req := {"s": object.union(min_subjects_req(0).s, {"require": "some"})}
	missing := report({}, req)
	[missing.requirements.s.status, missing.compliant] == ["not_met", false]
	empty := report({"items": []}, req)
	[empty.requirements.s.status, empty.compliant] == ["not_applicable", true]
}

test_a_from_line_that_ends_at_text_a_number_or_true_or_false_gives_it_as_one_subject if {
	every doc, from in {`{"items": "none"}`: "items", `{"items": 3}`: "items", `{"items": true}`: "items", `{"b": {"items": "none"}}`: "b.items"} {
		rep := report(json.unmarshal(doc), {"s": object.union(min_subjects_req(1).s, {"from": from})})
		[[r.passed, r.cause, r.inputs[0].value] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied", 1]]
	}
}

test_from_input_on_a_list_makes_each_item_a_subject_and_an_empty_list_fails_as_value if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "$input"})}
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([{"id": "a"}, {"id": "b"}], req), "s", "$min_subjects")] == [[true, "satisfied", 2, ["/0", "/1"]]]
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "value", 0, []]]
}

test_from_every_input_on_an_input_that_is_not_a_list_fails_and_names_the_input_from_input if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input"})}
	every doc, cause in {"null": "null", `"x"`: "unusable", "3": "unusable", "true": "unusable"} {
		[[r.passed, r.cause, r.failed_items] | some r in rows_for(report(json.unmarshal(doc), req), "s", "$min_subjects")] == [[false, cause, [{"path": "$input", "item": "$input", "cause": cause, "value": json.unmarshal(doc), "locations": [""]}]]]
	}
	[[r.passed, r.cause, r.failed_items[0].path, r.failed_items[0].item] | some r in rows_for(report({"id": "a"}, req), "s", "$min_subjects")] == [[false, "unusable", "$input", "$input"]]
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

test_from_id_applies_to_and_subject_type_belong_to_the_subject_not_the_requirement if {
	rep := ergo.report(
		{"releases": [{"id": "r-1", "signed": true}]}, {
			"ergo_spec": ergo._spec,
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

test_a_from_that_is_not_a_list_records_no_refs_because_it_is_never_read if {
	rep := report({}, {"s": object.union(typed_req, {"from": {"ref": ["$$params", "p"]}})})
	not "$refs" in object.keys(rep.requirements.s.checks["$min_subjects"])
}

test_a_from_that_is_not_a_list_gives_no_subjects if {
	rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"from": 5, "min_subjects": 1})})
	rep.requirements.s.subjects == {"total": 0, "matching": 0}
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(<invalid from>)) >= 1"
}

named_by_then_each_of_policy(from) := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": from}}, "requirements": {"s": {"subject": "b", "checks": {"c": "x is 1"}}}}

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

test_a_position_of_a_list_input_in_a_from_line_is_read_and_every_over_it_reads_its_items if {
	every from in ["$input[0]", "first of $input", "item 1 of $input", "every $input[0]"] {
		rep := ergo.report([[{"x": 1}], [{"x": 2}]], position_child_policy(from), {})
		[[r.passed, r.cause] | some r in rows_for(rep, "r", "$min_subjects")] == [[true, "satisfied"]]
	}
}

test_a_from_line_with_every_on_a_null_input_fails_min_subjects_as_null_like_the_place_its_walk_breaks if {
	every from in ["every commits", "every $input[0]", "every $input[0].y", "every x.y", "every x[0]", "every commits named by $params.k"] {
		policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": from}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}
		rep := ergo.report(null, policy, {"k": "a"})
		rep.requirements.s.status == "not_met"
		[[r.passed, r.cause, [f.cause | some f in r.failed_items]] | some r in rows_for(rep, "s", "$min_subjects")] == [[false, "null", ["null"]]]
	}
}

test_a_from_leading_to_an_object_like_ergos_absent_marker_finds_it if {
	rep := report({"items": absent_lookalike}, {"s": {"from": "items", "checks": {"p": "\"ergo/absent\" exists"}}})
	[[r.passed, r.cause] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied"]]
	[[r.subject.id, r.passed, r.cause] | some r in rows_for(rep, "s", "p")] == [[absent_lookalike, true, "satisfied"]]
}

test_a_part_in_the_whose_of_a_from_line_counts_the_parts_path if {
	doc := {"things": [object.union({"id": "a", "n": 1}, _k9({"z": [1]})), object.union({"id": "b", "n": 2}, _k9({"z": [1]}))]}
	reads := _from_report(doc, {"s": {"from": "things whose n is count of x.z", "identified_by": "id", "has": {"x": _nine}}}, {"c": "id exists"}, {})
	_from_problems(reads) == []
	[[r.subject.id, r.cause] | some r in reads.results; r.check == "$applies"] == [["a", "satisfied"], ["b", "value"]]
	wrong := _from_report(doc, {"s": {"from": "things whose n is count of x.z", "identified_by": "id", "has": {"x": _ten}}}, {"c": "id exists"}, {})
	_from_problems(wrong) == [{"name": "subjects.s.from", "value": ["every and some over more than ten steps aren't supported yet"], "locations": []}]
}

test_a_from_named_by_a_param_or_by_each_of_a_param_list if {
	doc := {"build": {"runs": {"unit": {"result": "passed"}, "integration": {"result": "failed"}, "smoke": {"result": "passed"}}}}
	each := _from_report(doc, {"run": {"from": "build.runs named by each of $params.kinds"}}, {"c": `result is "passed"`}, {"kinds": ["unit", "integration", "system"]})
	[[r[0], r[2]] | some r in _from_rows(each)] == [["integration", "value"], ["system", "absent"], ["unit", "satisfied"]]
	one := _from_report(doc, {"run": {"from": "build.runs named by $params.kind"}}, {"c": `result is "passed"`}, {"kind": "unit"})
	[r[2] | some r in _from_rows(one)] == ["satisfied"]
}

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

test_a_from_condition_with_some_reads_a_bare_name_on_its_right_side_from_the_candidate if {
	doc := {"releases": [
		{"id": 1, "steward": "bob", "files": [{"owner": "ann", "steward": "ann"}]},
		{"id": 2, "steward": "ann", "files": [{"owner": "ann", "steward": "bob"}]},
		{"id": 3, "steward": "ann", "files": [{"owner": "ann"}]},
	]}
	rep := _from_report(doc, {"release": {"from": "releases whose some files.owner is steward", "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.cause | some r in rep.results; r.check == "$applies"} == {1: "value", 2: "satisfied", 3: "satisfied"}
}

test_a_from_condition_with_some_works_on_every_from_lines_and_narrowing_chains if {
	doc := {"artifacts": [{"releases": [{"id": 1, "files": [{"path": "a.go"}]}, {"id": 2, "files": [{"path": "docs/a"}]}]}], "releases": [{"id": 3, "files": [{"path": "a.go"}]}, {"id": 4, "files": [{"path": "docs/a"}]}]}
	every_rep := _from_report(doc, {"release": {"from": `every artifacts.releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	{r.subject.id: r.cause | some r in every_rep.results; r.check == "$applies"} == {1: "satisfied", 2: "value"}
	subjects := {"releases": {"from": "releases", "identified_by": "id"}, "source": {"from": `releases whose some files.path does not match "^docs/"`}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "source", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.cause | some r in rep.results; r.check == "$applies"} == {3: "satisfied", 4: "value"}
}

test_a_from_condition_with_some_walks_every_list_along_its_path if {
	deep := {"x": {"id": 1, "p": [{"q": [{"r": [{"u": 2}, {"u": 1}]}]}]}}
	hit := _from_report(deep, {"x": {"from": "x whose some p.q.r.u is 1"}}, {"c": "id exists"}, {})
	miss := _from_report(deep, {"x": {"from": "x whose some p.q.r.u is 3"}}, {"c": "id exists"}, {})
	[r.cause | some r in hit.results; r.check == "$applies"] == ["satisfied"]
	[r.cause | some r in miss.results; r.check == "$applies"] == ["value"]
}

test_that_on_a_from_line_keeps_items_by_their_value_and_names_each_by_the_subject if {
	rep := _from_report({"ws": ["bay", "apple"]}, {"w": {"from": `every ws that starts with "b"`}}, {"c": "w is not empty"}, {})
	apply_rows := [r | some r in rep.results; r.check == "$applies"]
	sort([r.subject.id | some r in apply_rows]) == ["apple", "bay"]
	apple := [r | some r in apply_rows; r.subject.id == "apple"][0]
	apple.cause == "value"
	apple.inputs == [{"name": "w", "value": "apple", "locations": ["/ws/1"]}]
	apple.message == `w is "apple"`
}

test_a_subject_named_with_a_dollar_sign_gets_only_the_name_problem_with_a_that_from_line if {
	every name in ["$w", "$input"] {
		rep := _from_report({"ws": ["a"]}, {name: {"from": "every ws that is not empty"}}, {"c": "it is not empty"}, {})
		_from_problems(rep) == [{"name": concat(".", ["subjects", name]), "value": ["a name can't start with $"], "locations": []}]
	}
}

test_every_condition_of_a_from_line_needs_its_own_word_after_an_and if {
	doc := {"ws": ["bay", "bee"]}
	every line in [`every ws that starts with "b" and ends with "y"`, `every ws whose it starts with "b" and ends with "y"`] {
		_from_problems(_from_report(doc, {"w": {"from": line}}, {"c": "w is not empty"}, {})) == [{"name": "subjects.w.from", "value": ["a condition after and starts with whose or that"], "locations": []}]
	}
	every line in [`every ws that starts with "b" that ends with "y"`, `every ws that`] {
		_from_problems(_from_report(doc, {"w": {"from": line}}, {"c": "w is not empty"}, {})) == [{"name": "subjects.w.from", "value": ["doesn't parse"], "locations": []}]
	}
	rep := _from_report(doc, {"w": {"from": `every ws that starts with "b" and that ends with "y"`}}, {"c": "w is not empty"}, {})
	[r.subject.id | some r in rep.results; r.check == "c"] == ["bay"]
}

test_a_dot_before_a_part_on_the_left_of_a_whose_in_a_from_line_reads_the_field_not_the_part if {
	doc := {"kids": [{"id": "k1", "att": {"id": 1}, "atts": {"pr": {"id": 2}}}, {"id": "k2", "atts": {"pr": {"id": 1}}}]}
	subjects := {"kid": {"from": "kids whose .att.id is 1", "identified_by": "id", "has": {"att": {"from": "atts.pr", "identified_by": "id"}}}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "$applies"] == [["k1", "satisfied"], ["k2", "absent"]]
	plain := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": object.union(subjects, {"kid": object.union(subjects.kid, {"from": "kids whose att.id is 1"})}), "requirements": {"r": {"subject": "kid", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in plain.results; r.check == "$applies"] == [["k1", "value"], ["k2", "satisfied"]]
}

test_a_from_line_keeps_every_condition_past_a_hundred if {
	conds := concat(" and whose ", array.concat([`id is 1` | some _ in numbers.range(1, 100)], [`env is "prod"`]))
	rep := _from_report({"ds": [{"id": 1, "env": "dev"}]}, {"d": {"from": concat("", ["ds whose ", conds]), "identified_by": "id"}}, {"c": "id exists"}, {})
	rep.requirements.r.status == "not_met"
	[r.cause | some r in rep.results; r.check == "$applies"] == ["value"]
	endswith(rep.requirements.r.checks["$applies"].expression, `and env is "prod"`)
}

test_a_from_line_can_start_with_a_quoted_key_that_starts_with_a_dollar if {
	[r[2] | some r in _from_rows(_from_report({"$schema": [{"id": 2}]}, {"d": {"from": `"$schema" whose id is 2`, "identified_by": "id"}}, {"c": "id exists"}, {}))] == ["satisfied", "satisfied"]
}

test_a_from_line_that_names_another_subject_narrows_it if {
	subjects := {"defect": {"from": "defects", "identified_by": "id"}, "critical defect": {"from": `defect whose severity is "critical" and whose status is one of "open", "in_progress"`}}
	rep := _narrow_report(subjects, "critical defect")
	_kept(rep) == [1, 4]
	rep.requirements.r.checks["$applies"].expression == `severity is "critical" and status is one of "open", "in_progress"`
	_from_problems(rep) == []
	_kept(_narrow_report({"defect": {"from": "defects", "identified_by": "id"}, "all": {"from": "defect"}}, "all")) == [1, 2, 3, 4]
}

test_named_by_a_bare_word_in_a_from_line_or_an_id_is_an_unknown_name_since_there_is_no_subject_to_read_it_from if {
	from := ergo.report({"things": [{"id": 1, "k": "a"}]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "every things named by k", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "id exists"}}}}, {})
	[i.value | some r in from.results; r.check == "$well_formed"; some i in r.inputs; i.name == "subjects.thing.from"] == [["unknown alias k"]]
	id := ergo.report({"things": [{"id": {"a": 1}, "k": "a"}]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id named by k"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "k exists"}}}}, {})
	[i.value | some r in id.results; r.check == "$well_formed"; some i in r.inputs; i.name == "subjects.thing.identified_by"] == [[`identified_by is a path, like "id" or "build.number"`]]
}

test_a_from_line_named_by_a_bare_word_is_an_unknown_name if {
	_from_problems(_from_report({"m": {}}, {"x": {"from": "every m named by k"}}, {"c": "id exists"}, {})) == [{"name": "subjects.x.from", "value": ["unknown alias k"], "locations": []}]
}

test_a_from_line_is_printed_the_canonical_way if {
	subjects := {"d": {"from": `  deployments   whose environment is   "prod"  and whose approved_by exists `}}
	_listed(subjects, "d").d.from == `deployments whose environment is "prod" and whose approved_by exists`
}

test_a_from_line_that_names_each_key_is_printed_with_it if {
	subjects := {"d": {"from": "trail.artifacts named by each of $params.names"}}
	_listed(subjects, "d").d.from == "trail.artifacts named by each of $params.names"
}

test_a_from_line_with_applies_to_or_of_is_marked_invalid if {
	_listed({"d": {"from": "ds", "applies_to": {"a": {"op": "present", "path": ["x"]}}}}, "d").d.from == "<invalid from>"
	_listed({"b": {"from": "bs"}, "d": {"from": "ds", "of": "b"}}, "d").d.from == "<invalid from>"
}

test_a_whose_of_two_conditions_in_the_from_line_keeps_the_part_of_each_input if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"round": {"from": "rounds whose cov.x is 1 and whose cov.n is 2", "identified_by": "id", "has": {"cov": "dd.b"}}},
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
		"ergo_spec": ergo._spec,
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

_flows_doc := {"artifacts": [
	{"fingerprint": "sha-1", "pull_requests": [{"url": "pr/7", "approvals": 2}, {"url": "pr/8", "approvals": 0}]},
	{"fingerprint": "sha-2", "pull_requests": []},
	{"fingerprint": "sha-3", "pull_requests": [{"url": "pr/9", "approvals": 1}]},
]}

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

test_a_from_line_with_every_fails_where_its_path_stops_as_every_does_in_a_check if {
	rep := _from_report({"artifact": {"pull_requests": [{"url": "pr/7"}]}}, {"a": {"from": "every artifact"}}, {"c": "x exists"}, {})
	[[r.cause, r.failed_items] | some r in rep.results; r.check == "$min_subjects"] == [["unusable", [{"path": "artifact", "item": "artifact", "cause": "unusable", "value": {"pull_requests": [{"url": "pr/7"}]}, "locations": ["/artifact"]}]]]
	gone := _from_report({}, _every_prs, {"c": "x exists"}, {})
	[[r.cause, r.failed_items[0].path] | some r in gone.results; r.check == "$min_subjects"] == [["absent", "artifacts"]]
	ends := _from_report({"flows": [{"a": {"n": 1}}, {"a": "x"}]}, {"a": {"from": "every flows.a"}}, {"c": "n exists"}, {})
	[[r.cause, [f.path | some f in r.failed_items]] | some r in ends.results; r.check == "$min_subjects"] == [["unusable", ["flows[0].a", "flows[1].a"]]]
	[r.cause | some r in ends.results; r.check == "c"] == ["satisfied", "not_an_object"]
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

test_every_in_a_from_line_cant_stand_for_a_subject_or_go_with_named_by_each_of_or_walk_more_than_ten_steps if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	_from_problems(ergo.report(_flows_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})) == []
	narrow := {"artifact": {"from": "artifacts", "identified_by": "fingerprint"}, "kept": {"from": "every artifact"}, "picked": {"from": `every artifact whose env is "prod"`}}
	_from_problems(ergo.report(_flows_doc, {"ergo_spec": ergo._spec, "subjects": narrow, "requirements": {"r": {"subject": "kept", "checks": {"c": "url exists"}}}}, {})) == [{"name": "subjects.kept.from", "value": ["artifact is a subject: write artifact whose … to narrow it, without every"], "locations": []}]
	_from_problems(ergo.report(_flows_doc, {"ergo_spec": ergo._spec, "subjects": narrow, "requirements": {"r": {"subject": "picked", "checks": {"c": "url exists"}}}}, {})) == [{"name": "subjects.picked.from", "value": ["artifact is a subject: write artifact whose … to narrow it, without every"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every artifacts named by each of $params.names"}}, {"c": "x exists"}, {"names": ["a"]})) == [{"name": "subjects.s.from", "value": ["every can't go with named by each of: start the from line at a subject to read its names one subject at a time"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every x.b.c.d.e.f.g.h.i.j.k"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every over more than ten steps isn't supported yet"], "locations": []}]
	_from_problems(_from_report(_flows_doc, {"s": {"from": "every x.b.c.d.e.f.g.h.i.j"}}, {"c": "x exists"}, {})) == []
}

test_every_in_a_from_line_with_a_leading_dot_reads_the_top_level_field_even_when_a_subject_has_the_name if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "p": {"from": "every .artifact.p"}, "q": {"from": "every .artifact"}}
	input_doc := {"artifacts": [], "artifact": [{"p": [{"x": 1}]}]}
	rep := ergo.report(input_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "p", "checks": {"c": "x exists"}}, "s": {"subject": "q", "checks": {"c": "p exists"}}}}, {})
	_from_problems(rep) == []
	rep.subjects.p.from == "every .artifact.p"
	rep.subjects.q.from == "every .artifact"
	[r.cause | some r in rep.results; r.requirement == "r"; r.check == "c"] == ["satisfied"]
	[r.cause | some r in rep.results; r.requirement == "s"; r.check == "c"] == ["satisfied"]
	plain := ergo.report({"artifacts": [{"id": "a"}], "artifact": [{"x": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"artifact": {"from": "artifacts", "identified_by": "id"}, "q": {"from": ".artifact"}}, "requirements": {"r": {"subject": "q", "checks": {"c": "x exists"}}}}, {})
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

test_subject_name_after_whose_in_its_own_from_line_reads_each_items_own_field if {
	rep := _subject_report({"ws": [{"s": "a"}, {"s": "bb"}, "bb", {}]}, "every ws whose s is a string and whose s starts with 'b'", {"c": "s is an object"}, {})
	applies := [[r.subject.id, r.passed, r.cause, object.get(r, "message", "")] | some r in rep.results; r.check == "$applies"]
	applies == [
		[{"s": "a"}, false, "value", ".s is \"a\""],
		[{"s": "bb"}, true, "satisfied", ""],
		["bb", false, "not_an_object", "s is \"bb\", which isn't an object"],
		[{}, false, "absent", ".s is missing"],
	]
	[r.subject.id | some r in rep.results; r.check == "c"] == [{"s": "bb"}]
	counted := _subject_report({"xs": [{"s": [1]}, {"s": [1, 2]}]}, "every xs whose count of s is at least 2", {"c": "s is an object"}, {})
	[r.subject.id | some r in counted.results; r.check == "c"] == [{"s": [1, 2]}]
}

test_the_subjects_name_after_some_or_every_in_a_from_line_whose_reads_the_items_own_field if {
	doc := {"xs": [{"s": [1, 2]}, {"s": [1]}, {"s": []}, {"s": "s"}, "s"]}
	rows := [[r.subject.id, r.cause, object.get(r, "message", "")] | some r in _subject_report(doc, "every xs whose some s is 1", {"c": ".s is not empty"}, {}).results; r.check == "$applies"]
	rows == [
		[{"s": [1, 2]}, "satisfied", ""],
		[{"s": [1]}, "satisfied", ""],
		[{"s": []}, "value", ".s is []"],
		[{"s": "s"}, "unusable", ".s is \"s\", which isn't a list or an object"],
		["s", "not_an_object", "s is \"s\", which isn't an object"],
	]
	[[r.subject.id, r.cause] | some r in _subject_report({"xs": [{"s": [1, 2]}, {"s": [1]}]}, "every xs whose every s is 1", {"c": ".s is not empty"}, {}).results; r.check == "$applies"] == [[{"s": [1, 2]}, "value"], [{"s": [1]}, "satisfied"]]
}

test_a_from_that_reads_names_with_an_unknown_name_lists_the_subject_it_starts_at if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"p": {"from": "things", "identified_by": "id"}, "k": {"from": "every p.items named by $foo", "identified_by": "n"}},
		"requirements": {"r": {"subject": "k", "checks": {"c": "n exists"}}},
	}
	object.keys(ergo.report({}, policy, {}).subjects) == {"k", "p"}
}

test_a_from_line_that_reads_params_that_are_not_an_object_names_the_params_and_not_the_object if {
	every case in [[3, "3"], ["s", "\"s\""], [true, "true"], [[], "[]"], [[3], "[3]"], [[[1]], "[[1]]"], [[{"v": 1}], "[{\"v\": 1}]"], [[["k"]], "[[\"k\"]]"]] {
		message := concat("", ["$params is ", case[1], ", which isn't an object"])
		_from_params_rows("things named by each of $params.ks", case[0]) == [["$min_subjects", "unusable", message]]
		_from_params_rows("things named by $params.env named by each of $params.ks", case[0]) == [["$min_subjects", "unusable", message]]
		_from_params_rows("every things named by $params.env", case[0]) == [["$min_subjects", "unusable", message]]
	}
}

test_a_from_line_that_reads_a_position_of_the_params_names_what_it_found_there if {
	_from_params_rows("things named by each of $params[0]", 3) == [["$min_subjects", "unusable", "$params is 3, which isn't a list"]]
	_from_params_rows("things named by each of $params[0]", [3]) == [["$min_subjects", "unusable", "item 1 of $params is 3, which isn't a list of text"]]
	_from_params_rows("things named by each of $params[0].ks", [3]) == [["$min_subjects", "unusable", "item 1 of $params is 3, which isn't an object"]]
	_from_params_rows("things named by each of $params[0].ks", [{"ks": 3}]) == [["$min_subjects", "unusable", "$params[0].ks is 3, which isn't a list of text"]]
}

test_a_from_line_that_reads_the_input_and_params_that_are_not_an_object_names_both if {
	_from_params_rows("things named by $input.nope named by each of $params.ks", 3) == [["$min_subjects", "unusable", "$input.nope is missing; $params is 3, which isn't an object"]]
}

test_a_from_line_makes_no_subjects_from_keys_in_params_that_are_not_an_object if {
	_from_params_rows("things named by each of $params[0]", [["k"]]) == [["$min_subjects", "unusable", "$params is [[\"k\"]], which isn't an object"]]
	_from_params_rows("things named by each of $params[0].ks", [{"ks": ["k"]}]) == [["$min_subjects", "unusable", "$params is [{\"ks\": [\"k\"]}], which isn't an object"]]
}
