package ergo_test

import data.ergo
import rego.v1

test_a_child_subject_reads_the_items_of_a_list_input_as_its_parents if {
	reqs := {"s": {"subject_type": "kid", "from": "every parent.kids", "checks": {"c": "id exists"}}, "p": {"subject_type": "parent", "from": "$input", "checks": {"c": "kids exists"}}}
	rep := report([{"kids": [{"id": "a"}]}, {"kids": []}], reqs)
	[[r.passed, r.cause, r.inputs[0].locations] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied", ["/0/kids/0"]], [false, "value", []]]
}

test_a_position_after_a_parents_name_picks_the_item_of_each_parent_that_is_a_list if {
	rep := ergo.report({"ps": [[{"x": 1}, {"x": 2}], [{"x": 3}]]}, position_child_policy("p[1]"), {})
	[r.cause | some r in rows_for(rep, "r", "$min_subjects")] == ["satisfied", "absent"]
	rep2 := ergo.report({"ps": [[{"x": 1}, {"x": 2}]]}, position_child_policy("item 2 of p"), {})
	rep2.compliant == true
	[[r.passed, r.cause] | some r in rows_for(rep2, "r", "c")] == [[true, "satisfied"]]
}

test_is_empty_reads_through_params_named_by_and_a_parent_that_cant_hold_the_field if {
	doc := {"things": [{"id": "a", "art": {"z": ""}, "s": "text"}]}
	rows := _sentence_rows({"p": "$params.p is not empty", "n": "art named by $params.k is empty", "u": "s.y is empty"}, doc, {"p": [1], "k": "z"})
	[[r[0], r[1], r[2]] | some r in rows] == [["n", true, "satisfied"], ["p", true, "satisfied"], ["u", false, "unusable"]]
}

test_an_option_of_an_any_of_reads_a_parent_subject_by_its_name if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}, "commit": {"from": "every pr.commits", "identified_by": "sha"}}, "requirements": {"s": {"subject": "commit", "checks": {"c": {"any_of": {"signed": "signed is true", "bot": "pr.author is \"bot\""}}}}}}
	r := ergo.report({"prs": [{"id": "1", "author": "bot", "commits": [{"sha": "a", "signed": false}]}, {"id": "2", "author": "ann", "commits": [{"sha": "b", "signed": true}, {"sha": "c", "signed": false}]}]}, policy, {})
	[[row.subject.id, row.cause] | some row in r.results; row.check == "c"] == [["a", "satisfied"], ["b", "satisfied"], ["c", "value"]]
}

test_a_walk_through_a_part_of_the_parent_counts_the_parts_path if {
	doc := {"bs": [{"id": "b1", "kids": [{"id": "k1"}], "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"z": [1]}}}}}}}}}}]}
	[r.cause | some r in ergo.report(doc, _parent_part_policy({"x": _nine}, "every b.x.z is 1"), {}).results; r.check == "c"] == ["satisfied"]
	wrong := ergo.report(doc, _parent_part_policy({"x": _ten}, "every b.x.z is 1"), {})
	[i.value | some r in wrong.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [_too_long]
}

_parent_part_cause(has, check, doc) := [r.cause | some r in ergo.report(doc, _parent_part_policy(has, check), {}).results; r.check == "c"]

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_reads_the_parents_part_and_counts_its_path if {
	doc := {"bs": [object.union({"id": "b1", "kids": [{"id": "c1", "n": 1, "xs": [{"v": 1, "n": 1, "b": {"x": {"z": [1, 1]}}}]}]}, _k9({"z": [1]}))]}
	has := {"x": _nine}
	_parent_part_cause(has, "count of xs whose n is count of b.x.z is 1", doc) == ["satisfied"]
	_parent_part_cause(has, "count of xs whose n is count of b.x.z is 0", doc) == ["value"]
	_parent_part_cause(has, "count of xs whose n is at least count of b.x.z is 1", doc) == ["satisfied"]
	_parent_part_cause(has, "count of xs whose n is count of .b.x.z is 1", doc) == ["value"]
	_parent_part_cause(has, "count of xs whose count of b.x.z is 2 is 1", doc) == ["satisfied"]
}

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_counts_the_parents_part_at_ten_names if {
	_parent_part_problems({"x": _ten}, "count of xs whose n is count of b.x.z is 1") == [_too_long]
	_parent_part_problems({"x": _nine}, "count of xs whose n is count of b.x.z is 1") == []
	_parent_part_problems({"x": _ten}, "count of xs whose count of b.x.z is 1 is 1") == []
}

test_a_count_or_sum_on_the_right_of_a_whose_of_a_count_reads_the_parent_and_fails_closed_when_it_cant if {
	kid := {"id": "c1", "xs": [{"v": 1, "n": 2, "b": {"z": [1]}}]}
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["satisfied"]
	_parent_part_cause({}, "count of xs whose n is count of .b.z is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["value"]
	_parent_part_cause({}, "count of xs whose count of b.z is 1 is 1", {"bs": [{"id": "b1", "z": [1, 1], "kids": [kid]}]}) == ["satisfied"]
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "kids": [kid]}]}) == ["absent"]
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": null, "kids": [kid]}]}) == ["null"]
	_parent_part_cause({}, "count of xs whose n is count of b.z is 1", {"bs": [{"id": "b1", "z": "ab", "kids": [kid]}]}) == ["unusable"]
}

test_a_parent_part_in_the_whose_of_every_some_or_a_for_item_is_still_counted_at_ten_names if {
	has := {"x": _ten}
	_parent_part_problems(has, "every xs.v whose n is count of b.x.z is 1") == [_too_long]
	_parent_part_problems(has, "some xs whose n is count of b.x.z is not empty") == [_too_long]
	_parent_part_problems({"x": _nine}, "every xs.v whose n is count of b.x.z is 1") == []
}

test_a_for_alias_named_like_a_parent_subject_still_counts_the_parents_part_beside_the_clash if {
	_parent_part_problems({"x": _ten}, {"for": "every xs as b", "assert": "every b.x.z is 1"}) == [["b can't be an alias: it's a subject's name", "every and some over more than ten steps aren't supported yet"]]
}

test_an_applies_row_of_a_child_subject_and_of_a_subject_that_reads_its_parent_has_the_same_fields if {
	doc := {"artifact": {"id": "sha", "owner": "ann", "releases": [{"id": 1, "files": [{"owner": "ann"}]}, {"id": 2, "files": [{"owner": "bob"}]}]}}
	subjects := {"artifact": {"identified_by": "id"}, "release": {"from": "every artifact.releases whose some files.owner is artifact.owner and whose id exists", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_assertions | some r in rep.results; r.check == "$applies"} == {1: [], 2: [{"assertion": "some files.owner equals artifact.owner", "cause": "value"}]}
	single := {"artifact": {"identified_by": "id"}, "release": {"from": "every artifact.releases whose some files.owner is artifact.owner", "identified_by": "id"}}
	one := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": single, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in one.results; r.check == "$applies"} == {1: [], 2: [{"path": "files[0].owner", "item": "item 1 of files", "cause": "value", "value": "bob", "locations": ["/artifact/releases/1/files/0/owner"]}]}
	chain := {"releases": {"from": "releases", "identified_by": "id"}, "source": {"from": `releases whose some files.path does not match "^docs/"`}}
	cdoc := {"releases": [{"id": 3, "files": [{"path": "a.go"}]}, {"id": 4, "files": [{"path": "docs/a"}]}]}
	crep := ergo.report(cdoc, {"ergo_spec": ergo._spec, "subjects": chain, "requirements": {"r": {"subject": "source", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: count(r.failed_items) | some r in crep.results; r.check == "$applies"} == {3: 0, 4: 1}
}

test_a_from_condition_with_some_reads_a_parent_subject_by_its_name if {
	doc := {"artifact": {"id": "sha", "owner": "ann", "releases": [{"id": 1, "files": [{"owner": "ann"}]}, {"id": 2, "files": [{"owner": "bob"}]}]}}
	subjects := {"artifact": {"identified_by": "id"}, "release": {"from": "every artifact.releases whose some files.owner is artifact.owner", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	[[r.subject.id, r.subject["in"], r.cause] | some r in rep.results; r.check == "$applies"] == [[1, {"artifact": "sha"}, "satisfied"], [2, {"artifact": "sha"}, "value"]]
}

test_a_chain_names_its_parent_in_the_expressions_of_the_checks_ergo_adds_as_its_from_line_does if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	[rep.requirements.r.checks["$min_subjects"].expression, rep.requirements.r.checks["$unique_ids"].expression] == [
		"count(matching(every artifact.pull_requests)) >= 1",
		"count(repeated(ids(every artifact.pull_requests))) == 0",
	]
	quoted := {"locked thing": {"from": "trail.artifacts named by $params.name"}, "pull request": {"from": `every "locked thing".pull_requests`, "identified_by": "url"}}
	_chain_report(_chain_doc, quoted, {"c": "approved is true"}, {"name": "web"}).requirements.r.checks["$min_subjects"].expression == `count(matching(every "locked thing".pull_requests)) >= 1`
}

test_a_check_of_a_chain_reads_the_parent_by_its_name if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": `artifact.name is "web" and url exists`}, {"name": "web"})
	[[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "c"] == [
		["pr/7", "satisfied", [{"name": "artifact.name", "value": "web", "locations": ["/trail/artifacts/web/name"]}, {"name": "url", "value": "pr/7", "locations": ["/trail/artifacts/web/pull_requests/0/url"]}]],
		["pr/8", "satisfied", [{"name": "artifact.name", "value": "web", "locations": ["/trail/artifacts/web/name"]}, {"name": "url", "value": "pr/8", "locations": ["/trail/artifacts/web/pull_requests/1/url"]}]],
	]
}

_owner_input := {"name": "artifact.owner", "value": "ann", "locations": ["/artifact/owner"]}

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

test_a_count_lists_the_parent_its_whose_reads if {
	commits := [{"author": "bob", "n": 1}, {"author": "ann", "n": 2}]
	at := ["/artifact/pull_requests/0/commits/0", "/artifact/pull_requests/0/commits/1"]
	_owner_rows({"count": "count of commits whose author is artifact.owner is 1"}) == {
		"count": [
			{"name": "count of commits whose author equals artifact.owner", "value": 1, "locations": at},
			{"name": "commits[]", "value": commits, "locations": at},
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
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	tags := {"name": "artifact.tags[]", "value": ["x", "ann"], "locations": ["/artifact/tags/0", "/artifact/tags/1"]}
	{r.check: r.inputs | some r in rep.results; r.check in {"right", "left"}} == {
		"right": [tags, commits],
		"left": [_owner_input, tags, commits],
	}
}

test_a_walk_from_a_for_alias_lists_the_parent_it_compares_with if {
	doc := object.union(_owner_doc, {"artifact": {"pull_requests": [{"id": 1, "commits": [{"author": "bob", "n": 1, "reviewers": ["ann"]}, {"author": "ann", "n": 2, "reviewers": ["cid"]}]}]}})
	checks := {"c": {"for": "every commits as c", "assert": "some c.reviewers is artifact.owner"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[r.cause, [i.name | some i in r.inputs]] | some r in rep.results; r.check == "c"] == [["value", ["artifact.owner", "commits[]"]]]
}

test_a_one_line_some_lists_a_missing_or_null_parent_value_as_a_plain_assertion_does if {
	doc := object.union(_owner_doc, {"artifact": {"nul": null}})
	checks := {"missing": "some commits.author is artifact.nope", "null": "some commits.author is artifact.nul"}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	{r.check: [r.cause, r.inputs] | some r in rep.results; r.check in {"missing", "null"}} == {
		"missing": ["absent", [{"name": "artifact.nope", "value": null, "locations": ["/artifact"]}, _owner_authors]],
		"null": ["null", [{"name": "artifact.nul", "value": null, "locations": ["/artifact/nul"]}, _owner_authors]],
	}
}

test_a_parent_read_by_a_walk_and_by_a_plain_assertion_is_listed_once if {
	_owner_rows({"c": `some commits.author is artifact.owner and artifact.owner is "ann"`}) == {"c": [_owner_input, _owner_authors]}
}

test_the_applies_row_of_a_from_condition_with_some_lists_the_parent_it_reads if {
	subjects := object.union(_owner_subjects, {"pr": {"from": "every artifact.pull_requests whose some commits.author is artifact.owner", "identified_by": "id"}})
	rep := ergo.report(_owner_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": "id exists"}}}}, {})
	_applies_of(rep) == [[1, "satisfied", [_owner_input, _owner_authors]]]
}

test_a_walk_named_by_a_parent_path_lists_the_same_entry_as_the_plain_form if {
	doc := object.union(_owner_doc, {"artifact": {"key": "k1", "map": {"k1": "ann"}}})
	checks := {"walk": "some commits.author is artifact.map named by artifact.key", "plain": "author is artifact.map named by artifact.key"}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	rows := {r.check: r.inputs | some r in rep.results; r.check in object.keys(checks)}
	entry := [i | some i in rows.plain; i.name == "artifact.map named by artifact.key"]
	entry == [i | some i in rows.walk; i.name == "artifact.map named by artifact.key"]
	count(entry) == 1
	not "artifact.map" in {i.name | some i in rows.walk}
}

test_a_count_under_a_for_line_whose_whose_reads_a_parent_lists_it_when_the_path_starts_at_the_alias if {
	doc := object.union(_owner_doc, {"artifact": {"pull_requests": [{"id": 1, "commits": [{"author": "bob", "revs": [{"n": "ann"}]}, {"author": "ann", "revs": [{"n": "x"}]}]}]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of c.revs whose n is artifact.owner is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.owner", "commits[]"]]
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

_kids_doc := {"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "v": 1}, {"id": "k2", "v": 2}]}]}

_kids_report(from) := ergo.report(_kids_doc, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": from, "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})

_applies_of(rep) := [[r.subject.id, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"]

test_a_whose_in_a_childs_from_line_reads_the_parent_by_its_name if {
	_applies_of(_kids_report("every b.kids whose v equals b.x")) == [
		["k1", "satisfied", [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "value", [{"name": "b.x", "value": 1, "locations": ["/bs/0/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_the_parents_name_on_the_left_of_a_whose_in_a_childs_from_line_is_the_childs_own_field if {
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 2}, "v": 2}, {"id": "k2", "v": 1}]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids whose b.x equals v", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": ".b.x", "value": 2, "locations": ["/bs/0/kids/0/b/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "absent", [{"name": ".b.x", "value": null, "locations": ["/bs/0/kids/1"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/1/v"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == ".b.x equals v"
}

test_a_dot_before_the_parents_name_in_a_childs_from_line_reads_the_childs_own_field if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "b": 1}, {"id": "k2", "b": 5}]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids whose .b equals 1", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "b exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": ".b", "value": 1, "locations": ["/bs/0/kids/0/b"]}]],
		["k2", "value", [{"name": ".b", "value": 5, "locations": ["/bs/0/kids/1/b"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == ".b is 1"
}

test_a_whose_in_a_childs_from_line_reads_a_part_of_the_parent_by_its_name if {
	doc := {"bs": [{"id": "b1", "meta": {"tag": {"id": "t1", "x": 1}}, "kids": [{"id": "k1", "v": 1}, {"id": "k2", "v": 2}]}]}
	subjects := {"b": {"from": "bs", "identified_by": "id", "has": {"tag": {"from": "meta.tag", "identified_by": "id"}}}, "kid": {"from": "every b.kids whose v equals b.tag.x", "identified_by": "id"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	_applies_of(rep) == [
		["k1", "satisfied", [{"name": "b.tag.x", "value": 1, "part": {"name": "b.tag", "id": "t1"}, "locations": ["/bs/0/meta/tag/x"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "value", [{"name": "b.tag.x", "value": 1, "part": {"name": "b.tag", "id": "t1"}, "locations": ["/bs/0/meta/tag/x"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_a_count_on_the_left_of_a_whose_in_a_check_reads_the_items_own_field_not_the_parent if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "items": [{"b": {"kids": [1, 2, 3]}, "v": 3}, {"b": {"kids": []}, "v": 1}]}]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": {"for": "every items whose count of b.kids is at least v as i", "assert": "i.v is 3"}}}}}, {})
	[r.cause | some r in rep.results; r.check == "c"] == ["satisfied"]
}

test_a_count_on_the_left_of_a_whose_in_a_childs_from_line_reads_the_childs_own_field_not_the_parent if {
	rep := ergo.report({"bs": [{"id": "b1", "kids": [{"id": "k1", "b": {"kids": [1, 2]}, "v": 2}, {"id": "k2", "v": 1}]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids whose count of b.kids is at least v", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "$applies"] == [["k1", "satisfied"], ["k2", "absent"]]
	rep.requirements.r.checks["$applies"].expression == "count of .b.kids is at least v"
}

test_a_whose_in_a_childs_from_line_that_reads_a_missing_field_of_the_parent_fails_as_absent if {
	_applies_of(_kids_report("every b.kids whose v equals b.nope")) == [
		["k1", "absent", [{"name": "b.nope", "value": null, "locations": ["/bs/0"]}, {"name": "v", "value": 1, "locations": ["/bs/0/kids/0/v"]}]],
		["k2", "absent", [{"name": "b.nope", "value": null, "locations": ["/bs/0"]}, {"name": "v", "value": 2, "locations": ["/bs/0/kids/1/v"]}]],
	]
}

test_a_whose_in_the_from_lines_of_a_chain_of_three_subjects_reads_every_ancestor_by_its_name if {
	doc := {"tops": [{"id": "t1", "y": 2, "bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "v": 1, "w": 2}, {"id": "k2", "v": 2, "w": 2}]}, {"id": "b2", "x": 3, "kids": [{"id": "k3", "v": 3, "w": 2}]}]}]}
	subjects := {
		"top": {"from": "tops", "identified_by": "id"},
		"b": {"from": "every top.bs whose x is less than top.y", "identified_by": "id"},
		"kid": {"from": "every b.kids whose w equals top.y and whose v equals b.x", "identified_by": "id"},
	}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": "v exists"}}}}, {})
	[[r.subject.id, r.subject.in, r.cause, r.inputs] | some r in rep.results; r.check == "$applies"] == [
		["k1", {"top": "t1", "b": "b1"}, "satisfied", [{"name": "b.x", "value": 1, "locations": ["/tops/0/bs/0/x"]}, {"name": "top.y", "value": 2, "locations": ["/tops/0/y"]}, {"name": "v", "value": 1, "locations": ["/tops/0/bs/0/kids/0/v"]}, {"name": "w", "value": 2, "locations": ["/tops/0/bs/0/kids/0/w"]}]],
		["k2", {"top": "t1", "b": "b1"}, "value", [{"name": "b.x", "value": 1, "locations": ["/tops/0/bs/0/x"]}, {"name": "top.y", "value": 2, "locations": ["/tops/0/y"]}, {"name": "v", "value": 2, "locations": ["/tops/0/bs/0/kids/1/v"]}, {"name": "w", "value": 2, "locations": ["/tops/0/bs/0/kids/1/w"]}]],
	]
}

test_a_chain_with_no_parent_or_an_unreadable_one_finds_no_subjects if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "api"})) == [["value", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": "nope"})) == [["absent", {"type", "id"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, _kept_subjects, {"c": "url exists"}, {})) == [["value", {"type", "id"}]]
	zero := _chain_report({"trail": {"artifacts": [{"fingerprint": "a", "env": "dev"}]}}, _kept_subjects, {"c": "url exists"}, {})
	zero.requirements.r.status == "not_met"
}

test_a_child_under_a_parent_that_is_not_an_object_fails_min_subjects_as_not_an_object if {
	every parent in ["x", 5, true, null] {
		_chain_min_cause(_chain_report({"trail": {"artifacts": [parent]}}, _plain_chain, {"c": "url exists"}, {})) == [["not_an_object", {"type", "id", "in"}]]
	}
	_chain_min_cause(_chain_report({"trail": {"artifacts": [[[1]]]}}, _plain_chain, {"c": "url exists"}, {})) == [["not_an_object", {"type", "id", "in"}]]
}

test_a_child_read_with_every_under_a_list_parent_of_numbers_fails_min_subjects_as_unusable if {
	_chain_min_cause(_chain_report({"trail": {"artifacts": [[1]]}}, _plain_chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id", "in"}]]
}

test_a_child_under_an_object_parent_without_the_field_still_fails_min_subjects_as_absent if {
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a"}]}}, _plain_chain, {"c": "url exists"}, {})) == [["absent", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "pull_requests": null}]}}, _plain_chain, {"c": "url exists"}, {})) == [["null", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [{"fingerprint": "a", "pull_requests": "x"}]}}, _plain_chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id", "in"}]]
}

test_a_child_from_that_starts_with_a_position_reads_its_parent_as_a_list if {
	chain := object.union(_plain_chain, {"pull request": {"from": "every artifact[0].pull_requests", "identified_by": "url"}})
	_chain_min_cause(_chain_report({"trail": {"artifacts": ["x"]}}, chain, {"c": "url exists"}, {})) == [["unusable", {"type", "id", "in"}]]
	_chain_min_cause(_chain_report({"trail": {"artifacts": [null]}}, chain, {"c": "url exists"}, {})) == [["absent", {"type", "id", "in"}]]
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
	subjects := {"artifact": {"from": "every trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	rep := _chain_report(doc, subjects, {"c": "url exists"}, {})
	[[r.subject.in, r.passed, r.cause, r.inputs] | some r in rep.results; r.check == "$min_subjects"] == [
		[{"artifact": "a"}, true, "satisfied", [{"name": "in-scope pull request count", "value": 1, "locations": ["/trail/artifacts/0/pull_requests/0"]}]],
		[{"artifact": "b"}, false, "value", [{"name": "in-scope pull request count", "value": 0, "locations": []}]],
	]
	rep.requirements.r.status == "not_met"
	zero := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	[r.passed | some r in zero.results; r.check == "$min_subjects"] == [true, true]
	zero.requirements.r.status == "met"
}

test_ids_of_a_chain_from_several_parents_are_unique_within_each_parent if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}, {"url": "pr/7"}]},
		{"fingerprint": "b", "pull_requests": [{"url": "pr/7"}]},
	]}}
	subjects := {"artifact": {"from": "every trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
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
		["$unique_ancestor_ids", {"type": "artifact", "id": null}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "a"}}, "satisfied"],
	]
	rep.requirements.r.status == "not_met"
	rep.requirements.r.causes == [{"cause": "absent", "rows": 1}]
	zero := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _kept_subjects, "requirements": {"r": {"subject": "pull request", "min_subjects": 0, "checks": {"c": "url exists"}}}}, {})
	zero.requirements.r.status == "not_met"
}

test_a_chain_from_several_parents_reads_each_parents_part_with_its_own_id if {
	doc := {"trail": {"artifacts": [
		{"fingerprint": "a", "atts": {"pr": {"id": "att-1", "pull_requests": [{"url": "pr/7", "by": "ann"}]}}},
		{"fingerprint": "b", "atts": {"pr": {"id": "att-2", "pull_requests": [{"url": "pr/8", "by": "bo"}]}}},
	]}}
	subjects := {
		"artifact": {"from": "every trail.artifacts", "identified_by": "fingerprint", "has": {"pr_att": {"from": "atts.pr", "identified_by": "id"}}},
		"pull request": {"from": "every artifact.pr_att.pull_requests", "identified_by": "url"},
	}
	rep := _chain_report(doc, subjects, {"c": "artifact.pr_att.id exists and by exists"}, {})
	[[r.subject.id, r.subject.in, r.inputs[0]] | some r in rep.results; r.check == "c"] == [
		["pr/7", {"artifact": "a"}, {"name": "artifact.pr_att.id", "value": "att-1", "part": {"name": "artifact.pr_att", "id": "att-1"}, "locations": ["/trail/artifacts/0/atts/pr/id"]}],
		["pr/8", {"artifact": "b"}, {"name": "artifact.pr_att.id", "value": "att-2", "part": {"name": "artifact.pr_att", "id": "att-2"}, "locations": ["/trail/artifacts/1/atts/pr/id"]}],
	]
}

test_a_chain_whose_parent_reads_a_param_it_cant_use_fails_with_that_cause if {
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {"name": 5})) == [["unusable", {"type", "id"}]]
	gone := {"artifact": {"from": "every trail.nope", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	_chain_min_cause(_chain_report(_chain_doc, gone, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
	_chain_min_cause(_chain_report(_chain_doc, _chain_subjects, {"c": "url exists"}, {})) == [["absent", {"type", "id"}]]
}

test_every_and_some_in_a_check_of_a_chain_can_walk_the_parent if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "some artifact.pull_requests.approved is true"}, {"name": "web"})
	[r.cause | some r in rep.results; r.check == "c"] == ["satisfied", "satisfied"]
}

test_a_whose_that_reads_a_parent_through_a_for_name_lists_the_part_before_the_name if {
	doc := {"artifacts": [{"id": "a", "nums": {"a": 1, "b": 2}, "prs": [{"id": 1, "ks": ["a", "b"], "rows": [{"n": 1}, {"n": 2}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	checks := {"c": {"for": "every ks as k", "assert": "count of rows whose n is artifact.nums named by k is at least 1"}}
	rows := [r | some r in ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results; r.check == "c"]
	[[r.cause, r.inputs] | some r in rows] == [["satisfied", [
		{"name": "artifact.nums", "value": {"a": 1, "b": 2}, "locations": ["/artifacts/0/nums"]},
		{"name": "ks[]", "value": ["a", "b"], "locations": ["/artifacts/0/prs/0/ks/0", "/artifacts/0/prs/0/ks/1"]},
		{"name": "rows[]", "value": [{"n": 1}, {"n": 2}], "locations": ["/artifacts/0/prs/0/rows/0", "/artifacts/0/prs/0/rows/1"]},
	]]]
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
		"pull request": {"description": "", "from": "every artifact.pull_requests", "identified_by": "url", "parts": {}},
	}
}

test_a_parent_that_is_not_named_by_a_requirement_is_still_listed if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {})
	object.keys(rep.subjects) == {"artifact", "pull request"}
}

test_a_child_reads_its_parents_part_on_the_right_inside_an_items_scope if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {
			"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
			"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url"},
		},
		"requirements": {"r": {"subject": "pull request", "checks": {
			"every": "every reviews.by equals artifact.pra.boss",
			"whose": "some reviews whose by equals artifact.pra.boss exists",
			"for": {"for": "some reviews whose by equals artifact.pra.boss as rv", "assert": `rv.by is "bob"`},
		}}},
	}
	doc := {"artifacts": [{"fingerprint": "f1", "attestations": {"pr": {"boss": "bob", "pull_requests": [{"url": "u1", "reviews": [{"by": "bob"}]}]}}}]}
	{r.check: r.cause | some r in ergo.report(doc, policy, {}).results; not startswith(r.check, "$")} == {"every": "satisfied", "whose": "satisfied", "for": "satisfied"}
}

_parent_name_policy(checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {
		"artifact": {"from": "artifacts", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url"},
	},
	"requirements": {"r": {"subject": "pull request", "checks": checks}},
}

_parent_name_doc := {"artifacts": [{"fingerprint": "f1", "attestations": {"pr": {"pull_requests": [{"url": "u1", "artifact": "bob", "reviews": [{"by": "bob", "artifact": "f1"}]}]}}}]}

test_a_parents_name_reads_like_any_other_name if {
	rep := ergo.report(
		_parent_name_doc, _parent_name_policy({
			"right": "every reviews.artifact equals artifact.fingerprint",
			"whose_left": {"for": `some reviews whose artifact is "f1" as rv`, "assert": `rv.by is "bob"`},
			"dot": `.artifact is "bob"`,
		}),
		{},
	)
	{r.check: r.cause | some r in rep.results; not startswith(r.check, "$")} == {"right": "satisfied", "whose_left": "satisfied", "dot": "satisfied"}
}

test_a_chained_subject_reads_its_parents_parts_and_starts_from_one if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	[[r.subject.id, r.check, r.passed, r.cause] | some r in rep.results; r.check in {"parent", "own", "field", "every"}] == [
		["pr/7", "every", true, "satisfied"], ["pr/7", "field", false, "absent"], ["pr/7", "own", true, "satisfied"], ["pr/7", "parent", true, "satisfied"],
		["pr/8", "every", true, "satisfied"], ["pr/8", "field", false, "absent"], ["pr/8", "own", false, "value"], ["pr/8", "parent", true, "satisfied"],
	]
	_untagged(_parts_row(rep, "parent").inputs) == [{"name": "artifact.pra.name", "value": "w", "locations": ["/trail/artifacts/web/attestations/pr/name"]}]
	_untagged(_parts_row(rep, "every").inputs) == [{"name": "artifact.pra.pull_requests[].url", "value": ["pr/7", "pr/8"], "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/url", "/trail/artifacts/web/attestations/pr/pull_requests/1/url"]}]
	rep.subjects["pull request"].from == "every artifact.pra.pull_requests"
}

test_a_part_is_only_reached_through_its_subject_so_a_bare_alias_in_a_chained_child_is_a_field if {
	rep := ergo.report(_parts_chain_doc, _parts_chain, {"art": "web"})
	_parts_row(rep, "field").inputs == [{"name": "pra", "value": null, "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0"]}]
	_parts_row(rep, "field").cause == "absent"
}

test_a_chained_subject_cannot_use_its_parents_name_as_a_part_alias_because_it_is_a_subjects_name if {
	subjects := object.union(_parts_chain.subjects, {"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url", "has": {"artifact": "reviews"}}})
	rep := ergo.report(_parts_chain_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": _parts_chain.requirements}, {"art": "web"})
	_parts_problems(rep)["subjects.\"pull request\".has.artifact"] == ["artifact can't be an alias: it's a subject's name"]
}

test_a_problem_in_a_parent_subjects_has_fails_the_requirements_of_its_chained_child if {
	subjects := object.union(_parts_chain.subjects, {"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": 5}}})
	rep := ergo.report(_parts_chain_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": _parts_chain.requirements}, {"art": "web"})
	_parts_problems(rep)["subjects.artifact.has.pra"] == ["not a string or an object"]
}

test_a_chained_child_cannot_read_a_part_the_parent_does_not_have if {
	policy := object.union(_parts_chain, {"requirements": {"r": {"subject": "pull request", "checks": {"c": "artifact.nope.name is \"w\""}}}})
	rep := ergo.report(_parts_chain_doc, policy, {"art": "web"})
	_parts_row(rep, "c").cause == "absent"
}

test_a_position_in_a_list_inside_a_parents_part_is_never_hidden_either if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"rv": "pull_requests.reviews"}},
		"pull request": {"from": "every artifact.items", "identified_by": "state"},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "items": [{"state": "s"}], "pull_requests": [{"reviews": [{"state": "ok"}]}, {"reviews": [{"state": "bad"}]}]}}}}
	checks := {"c": "every artifact.rv.state is \"ok\"", "n": "count of artifact.rv is 2"}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, {"art": "web"})
	row := _parts_row(rep, "c")
	row.failed_items == [{"cause": "value", "item": "item 1 of artifact.pull_requests[1].reviews", "path": "artifact.pull_requests[1].reviews[0].state", "value": "bad", "locations": ["/trail/artifacts/web/pull_requests/1/reviews/0/state"]}]
	_untagged(row.inputs) == [{"name": "artifact.pull_requests[].reviews[].state", "value": ["ok", "bad"], "locations": ["/trail/artifacts/web/pull_requests/0/reviews/0/state", "/trail/artifacts/web/pull_requests/1/reviews/0/state"]}]
}

test_a_chained_subject_that_starts_deeper_in_its_parents_part_keeps_the_rest_of_the_path_in_its_expressions if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "artifact.pra.pull_requests[0].list", "identified_by": "url"},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "attestations": {"pr": {"pull_requests": [{"list": [{"url": "a"}]}]}}}}}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {"art": "web"})
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(artifact.pra.pull_requests[0].list)) >= 1"
}

test_an_input_read_through_a_parents_part_is_tagged_with_the_parent_and_the_id_from_the_parents_part if {
	subjects := {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": {"from": "attestations.pr", "identified_by": "att"}}},
		"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url", "has": {"rev": "reviews"}},
	}
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "attestations": {"pr": {"att": "att-3", "name": "w", "pull_requests": [{"url": "pr/7", "reviews": {"count": 2}}]}}}}}}
	checks := {"parent": "artifact.pra.name is \"w\"", "own": "rev.count is 2", "field": "url exists"}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, {"art": "web"})
	_parts_row(rep, "parent").inputs == [{"name": "artifact.pra.name", "part": {"id": "att-3", "name": "artifact.pra"}, "value": "w", "locations": ["/trail/artifacts/web/attestations/pr/name"]}]
	_parts_row(rep, "own").inputs == [{"name": "rev.count", "part": {"id": null, "name": "rev"}, "value": 2, "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/reviews/count"]}]
	_parts_row(rep, "field").inputs == [{"name": "url", "value": "pr/7", "locations": ["/trail/artifacts/web/attestations/pr/pull_requests/0/url"]}]
}

test_a_parent_read_with_every_gives_its_child_subjects_per_parent if {
	doc := {"flows": [{"artifacts": [{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}]}]}, {"artifacts": [{"fingerprint": "b", "pull_requests": [{"url": "pr/7"}]}]}]}
	subjects := {"artifact": {"from": "every flows.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})
	[[r.check, r.subject.id, object.get(r.subject, "in", null)] | some r in rep.results; r.check != "$well_formed"] == [
		["$min_subjects", null, {"artifact": "a"}],
		["$min_subjects", null, {"artifact": "b"}],
		["$unique_ids", null, {"artifact": "a"}],
		["$unique_ids", null, {"artifact": "b"}],
		["$unique_ancestor_ids", null, null],
		["c", "pr/7", {"artifact": "a"}],
		["c", "pr/7", {"artifact": "b"}],
	]
	rep.requirements.r.status == "met"
	broken := ergo.report({"flows": [{"artifacts": [{"fingerprint": "a", "pull_requests": [{"url": "pr/7"}]}]}, {}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": {"c": "url exists"}}}}, {})
	[[r.check, r.cause, object.get(r.subject, "in", null)] | some r in broken.results; r.check != "$well_formed"] == [["$min_subjects", "absent", null], ["$unique_ids", "satisfied", null], ["$unique_ancestor_ids", "satisfied", null]]
}

_three_report(doc, checks) := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _three_subjects, "requirements": {"r": {"subject": "commit", "checks": checks}}}, {})

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
		["$unique_ancestor_ids", {"type": "artifact", "id": null}, "satisfied"],
		["$unique_ancestor_ids", {"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "satisfied"],
		["$unique_ancestor_ids", {"type": "pull request", "id": null, "in": {"artifact": "sha-4"}}, "satisfied"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "satisfied"],
		["c", {"type": "commit", "id": "c2", "in": {"artifact": "sha-1", "pull request": "pr/7"}}, "value"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "satisfied"],
		["c", {"type": "commit", "id": "c1", "in": {"artifact": "sha-4", "pull request": "pr/7"}}, "satisfied"],
	]
	rep.requirements.r.subjects == {"total": 4, "matching": 4}
	rep.requirements.r.checks["$min_subjects"].expression == `count(matching(every "pull request".commits)) >= 1`
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
		["$unique_ancestor_ids", {"type": "artifact", "id": null}, "satisfied"],
		["$unique_ancestor_ids", {"type": "pull request", "id": null, "in": {"artifact": "sha-2"}}, "satisfied"],
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

test_a_failed_line_lists_a_parents_field_and_the_childs_own_field_of_the_same_name_in_the_order_they_were_read if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "bs", "identified_by": "id"}, "kid": {"from": "every b.kids", "identified_by": "id"}}, "requirements": {"r": {"subject": "kid", "checks": {"c": {"for": "every cs as c", "assert": "c.ts is at least b.x plus .b.x"}}}}}
	rep := ergo.report({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 1}, "cs": [{"ts": 1}]}]}]}, policy, {})
	[i.locations | some r in rep.results; r.check == "c"; some i in r.failed_items[0].failed_assertions[0].inputs; i.name in {"b.x", ".b.x"}] == [["/bs/0/x"], ["/bs/0/kids/0/b/x"]]
}

test_child_subjects_that_read_each_other_lead_to_a_loop_not_a_chain_too_deep if {
	subjects := {"b": {"from": "every kid.x"}, "kid": {"from": "every b.kids"}}
	every name in ["b", "kid"] {
		subject_problems(subjects, name, {}) == [{"name": concat("", ["subjects.", name, ".from"]), "value": ["leads to a loop"], "locations": []}]
	}
}

test_every_subject_in_a_loop_through_child_subjects_is_named_after_its_own_from if {
	every subjects in [
		{"p": {"from": "every q.x"}, "q": {"from": "every r.x"}, "r": {"from": "every p.x"}},
		{"p": {"from": "q"}, "q": {"from": "every r.x"}, "r": {"from": "p"}},
		{"p": {"from": "every q.x"}, "q": {"from": "r"}, "r": {"from": "p"}},
	] {
		every name in ["p", "q", "r"] {
			subject_problems(subjects, name, {}) == [{"name": concat("", ["subjects.", name, ".from"]), "value": ["leads to a loop"], "locations": []}]
		}
	}
}

test_a_chain_through_a_subject_that_narrows_without_a_loop_is_not_a_loop if {
	subject_problems({"p": {"from": "every q.x"}, "q": {"from": "r"}, "r": {"from": "bs"}}, "p", {"bs": []}) == []
}

test_a_chain_four_subjects_deep_without_a_loop_is_still_too_deep if {
	subjects := {"a": {"from": "every b.x"}, "b": {"from": "every c.x"}, "c": {"from": "every d.x"}, "d": {"from": "every e.x"}, "e": {"from": "es"}}
	subject_problems(subjects, "a", {}) == [{"name": "subjects.a.from", "value": ["a chain of more than three subjects isn't supported yet"], "locations": []}]
}

test_a_chain_that_reaches_a_loop_further_up_leads_to_a_loop if {
	subjects := {"a": {"from": "every b.x"}, "b": {"from": "every c.x"}, "c": {"from": "every d.x"}, "d": {"from": "every e.x"}, "e": {"from": "every d.y"}}
	subject_problems(subjects, "a", {}) == [{"name": "subjects.a.from", "value": ["leads to a loop"], "locations": []}]
}

test_a_parent_read_with_named_by_on_the_right_side_shows_the_parents_value if {
	subjects := {"t": {"from": "ts", "identified_by": "id"}, "kid": {"from": "every t.kids"}}
	named_by_rows(subjects, "kid", "t.x is one of $params.allowed named by n", {"ts": [{"id": "a", "x": 1, "kids": [{"n": "a"}]}]}) == [[true, [{"name": "t.x", "value": 1, "locations": ["/ts/0/x"]}, {"name": "$params.allowed named by n", "value": [1], "locations": ["$params:/allowed/a"]}, {"name": "n", "value": "a", "locations": ["/ts/0/kids/0/n"]}]]]
}

test_a_for_row_shows_the_parent_fields_its_assertions_read if {
	subjects := {"t": {"from": "ts", "identified_by": "id", "has": {"cov": "d.c"}}, "kid": {"from": "every t.kids", "identified_by": "id"}}
	inp := {"ts": [{"id": "t1", "x": 1, "d": {"c": {"q": 3}}, "kids": [{"id": "k1", "rs": [{"v": 1}, {"v": 2}]}]}]}
	rs := {"name": "rs[]", "value": [{"v": 1}, {"v": 2}], "locations": ["/ts/0/kids/0/rs/0", "/ts/0/kids/0/rs/1"]}
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at least t.x"}, inp) == [[true, [rs, {"name": "t.x", "value": 1, "locations": ["/ts/0/x"]}]]]
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at least t.y"}, inp) == [[false, [rs, {"name": "t.y", "value": null, "locations": ["/ts/0"]}]]]
	named_by_rows(subjects, "kid", {"for": "every rs as r", "assert": "r.v is at most t.cov.q"}, inp) == [[true, [rs, {"name": "t.cov.q", "part": {"id": null, "name": "t.cov"}, "value": 3, "locations": ["/ts/0/d/c/q"]}]]]
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

test_unique_ids_locates_the_ids_of_a_child_subject_where_they_are_in_the_input if {
	doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "pull_requests": [{"url": "pr/7"}, {"url": "pr/8"}, {"url": "pr/7"}]}}}}
	rep := _chain_report(doc, _chain_subjects, {"c": "url exists"}, {"name": "web"})
	rows_for(rep, "r", "$unique_ids")[0].inputs == [{"name": "repeated pull request ids", "value": ["pr/7"], "locations": ["/trail/artifacts/web/pull_requests/0/url", "/trail/artifacts/web/pull_requests/2/url"]}]
}

test_a_second_item_that_starts_at_a_parent_is_named_with_the_whole_parent_name if {
	doc := {"artifacts": [{"name": "x", "map": {"k1": [1], "k2": []}, "prs": [{"id": 1, "keys": ["k1", "k2"], "approvers": [{"n": 1}]}]}]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	checks := {
		"c": {"for": "every keys as k, every artifact.map named by k as x", "assert": "x is not empty"},
		"e": {"for": "every artifact.prs as p, every p.approvers as person", "assert": "person.n is at least 1"},
	}
	rows := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	[i.name | some r in rows; r.check == "c"; some i in r.inputs] == ["artifact.map named by k[]", "keys[]"]
	[i.name | some r in rows; r.check == "e"; some i in r.inputs] == ["artifact.prs[]", "p.approvers[]"]
}

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
		_named_read_cause("abc", ["k1"], assertion) == "unusable"
		_named_read_cause(5, ["k1"], assertion) == "unusable"
	}
}

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

test_identified_by_stays_allowed_on_the_parent_of_a_subject_listed_by_named_by_each_of if {
	subjects := {"artifact": {"from": "artifacts", "identified_by": "id"}, "suite": {"from": "artifact.suites named by each of $params.names"}}
	rep := ergo.report({"artifacts": [{"id": 9, "suites": {"a": {"id": 1}}}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "suite", "checks": {"c": "id exists"}}}}, {"names": ["a"]})
	_from_problems(rep) == []
	[r.subject.id | some r in rep.results; r.check == "c"] == ["a"]
}

test_a_subject_that_narrows_a_parent_read_with_every_filters_the_parents_flat_list if {
	subjects := {"art": {"from": "every artifacts.releases", "identified_by": "id"}, "k": {"from": "art whose n is 1"}}
	rep := ergo.report({"artifacts": [{"releases": [{"id": "r1", "n": 1}, {"id": "r2", "n": 2}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "k", "checks": {"c": "id exists"}}}}, {})
	rep.requirements.r.subjects == {"matching": 1, "total": 2}
	rep.requirements.r.checks["$min_subjects"].expression == "count(matching(every artifacts.releases)) >= 1"
}

test_the_childs_own_field_named_like_its_parent_keeps_its_dot_in_the_input_name if {
	subjects := {"art": {"from": "arts", "identified_by": "id"}, "item": {"from": "every art.items", "identified_by": "id"}}
	rep := ergo.report({"arts": [{"id": "a1", "k": 2, "items": [{"id": "i1", "art": {"k": 1}}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "item", "checks": {"c": ".art.k is 1", "d": "art.k is 1"}}}}, {})
	[i.name | some i in rows_for(rep, "r", "c")[0].inputs] == [".art.k"]
	[i.name | some i in rows_for(rep, "r", "d")[0].inputs] == ["art.k"]
}

test_a_position_on_the_childs_own_field_named_like_its_parent_puts_the_dot_after_the_position_words if {
	subjects := {"art": {"from": "arts", "identified_by": "id"}, "item": {"from": "every art.items", "identified_by": "id"}}
	checks := {"a": ".art.xs[0] is 5", "b": "item 1 of .art.xs is 5", "c": "first of .art.xs is 5"}
	rep := ergo.report({"arts": [{"id": "a1", "items": [{"id": "i1", "art": {"xs": [5]}}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "item", "checks": checks}}}, {})
	every c in ["a", "b", "c"] {
		[i.name | some i in rows_for(rep, "r", c)[0].inputs] == ["item 1 of .art.xs"]
	}
}

test_a_for_line_names_the_childs_own_field_named_like_its_parent_with_the_dot if {
	subjects := {"art": {"from": "arts", "identified_by": "id"}, "item": {"from": "every art.items", "identified_by": "id"}}
	checks := {"f": {"for": "every .art.xs as x", "assert": "x is at least .art.k"}}
	rep := ergo.report({"arts": [{"id": "a1", "items": [{"id": "i1", "art": {"k": 1, "xs": [5]}}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "item", "checks": checks}}}, {})
	".art.k" in [i.name | some i in rows_for(rep, "r", "f")[0].inputs]
}

test_a_from_whose_condition_keeps_the_dot_of_the_childs_own_field_named_like_its_parent_in_the_subjects_from if {
	subjects := {"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "art.items whose v equals .art.k", "identified_by": "id"}}
	rep := ergo.report({"arts": [{"id": "a1", "k": 5, "items": [{"id": "i1", "art": {"k": 1}, "v": 5}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "thing", "checks": {"c": "id exists"}}}}, {})
	rep.subjects.thing.from == "art.items whose v equals .art.k"
}

_walk_parent_policy := {
	"ergo_spec": ergo._spec,
	"subjects": {"repo": {"from": "repos", "identified_by": "id"}, "dep": {"from": "every repo.deps", "identified_by": "name"}},
	"requirements": {"s": {"subject": "dep", "checks": {"c": "name is in repo.allowed.name"}}},
}

test_a_path_that_starts_at_a_parent_walks_and_fails_closed_on_each_broken_shape if {
	rows := [[r.subject.id, r.cause] |
		some r in ergo.report(
			{"repos": [
				{"id": "r1", "allowed": [{"name": "click"}], "deps": [{"name": "click"}, {"name": "attrs"}]},
				{"id": "r2", "allowed": [{"name": "click"}, {}], "deps": [{"name": "click"}]},
				{"id": "r3", "allowed": [], "deps": [{"name": "x"}]},
				{"id": "r4", "allowed": [{"name": null}], "deps": [{"name": "y"}]},
				{"id": "r5", "allowed": "t", "deps": [{"name": "z"}]},
			]},
			_walk_parent_policy, {},
		).results
		r.check == "c"
	]
	rows == [["click", "satisfied"], ["attrs", "value"], ["click", "absent"], ["x", "value"], ["y", "null"], ["z", "unusable"]]
}

test_named_by_each_of_params_or_input_is_still_read_in_a_child_from_line if {
	doc := {"keys": ["p"], "things": [{"id": "a", "p": {"x": 1}}]}
	_from_problems(_each_start_report(doc, "t named by each of $params.keys")) == []
	_from_problems(_each_start_report(doc, "t named by each of $input.keys")) == []
	rows := [[r.subject.id, r.cause] | some r in _each_start_report(doc, "t named by each of $input.keys").results; r.check == "c"]
	rows == [["p", "satisfied"]]
}

_ancestor_policy := {"ergo_spec": ergo._spec, "subjects": {"commit": {"from": "commits", "identified_by": "sha"}, "pull request": {"from": "every commit.pull_requests", "identified_by": "number"}}, "requirements": {"r": {"subject": "pull request", "checks": {"c": "number exists"}}}}

_ancestor_values(doc) := [r.inputs[0].value | some r in ergo.report(doc, _ancestor_policy, {}).results; r.check == "$unique_ancestor_ids"]

test_repeated_ancestor_ids_are_sorted_whatever_order_the_parents_come_in if {
	commits := [{"sha": 3, "pull_requests": []}, {"sha": "b", "pull_requests": []}, {"sha": 10, "pull_requests": []}, {"sha": 3, "pull_requests": []}, {"sha": 10, "pull_requests": []}, {"sha": "b", "pull_requests": []}]
	_ancestor_values({"commits": commits}) == [["b", 10, 3]]
	_ancestor_values({"commits": array.reverse(commits)}) == [["b", 10, 3]]
}

test_a_requirement_whose_subject_has_no_parent_works_out_no_ancestor_ids if {
	rep := ergo.report({"commits": [{"sha": "a"}, {"sha": "a"}]}, {"ergo_spec": ergo._spec, "subjects": {"commit": {"from": "commits", "identified_by": "sha"}}, "requirements": {"r": {"subject": "commit", "checks": {"c": "sha exists"}}}}, {})
	[r.check | some r in rep.results; startswith(r.check, "$unique")] == ["$unique_ids"]
	not "$unique_ancestor_ids" in object.keys(rep.requirements.r.checks)
}
