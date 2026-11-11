package ergo_test

import data.ergo
import rego.v1

test_from_every_input_on_a_list_makes_each_item_a_subject_and_prints_every if {
	req := {"s": object.union(min_subjects_req(1).s, {"from": "every $input"})}
	rep := report([{"id": "a"}, {"id": "b"}], req)
	[[r.passed, r.cause, r.inputs[0].value, r.inputs[0].locations, r.failed_items] | some r in rows_for(rep, "s", "$min_subjects")] == [[true, "satisfied", 2, ["/0", "/1"], []]]
	rep.requirements.s.checks["$min_subjects"].expression == "count(matching(every $input)) >= 1"
	[[r.passed, r.cause, r.inputs[0].value, r.failed_items] | some r in rows_for(report([], req), "s", "$min_subjects")] == [[false, "value", 0, []]]
}

test_a_policy_ergo_spec_description_and_meta_are_kept_when_it_is_rewritten_as_sentences if {
	policy := two_reqs_policy({"description": "d", "meta": {"control": "DEV-0401"}})
	converted := ergo.as_sentences(policy)
	[converted.ergo_spec, converted.description, converted.meta] == [ergo._spec, "d", {"control": "DEV-0401"}]
}

test_a_dollar_word_in_a_sentence_is_not_an_alias_so_it_stays_an_unknown_name if {
	_sentence_problems({"for": "every xs as x", "assert": "x is $foo"}) == ["unknown name $foo"]
	_sentence_problems({"assert": "$foo.a exists"}) == ["unknown name $foo"]
}

test_a_problem_inside_a_sentence_is_named_by_its_check_and_the_check_prints_as_written if {
	rep := ergo.report(
		{"things": [{"items": [1]}]}, {"ergo_spec": ergo._spec, "subjects": {"b": {"from": "things"}}, "requirements": {"s": {"subject": "b", "checks": {
			"k": `count of items whose x is one of 1, "a" and whose y is one of true, 2 is 0`,
			"e": {"for": `every items whose x is one of 1, "a" as i`, "assert": "i.y exists"},
		}}}},
		{},
	)
	problem_inputs(rep) == [
		{"name": "checks.e", "value": ["for: values of mixed types"], "locations": []},
		{"name": "checks.k", "value": ["values of mixed types"], "locations": []},
	]
	rep.requirements.s.checks.k.expression == "count of items whose x is one of 1, \"a\" and whose y is one of true, 2 is 0"
	rep.requirements.s.checks.e.expression == "for every items whose x is one of 1, \"a\" as i: i.y exists"
}

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
	count(data.spec.sentence_corpus) == 319
}

_prints_back(text) if _printed(text) == text

_prints_back(text) if ergo._s_for_line_text(ergo._for_line(text)) == text

_prints_back(text) if ergo._s_from_line_text(ergo._from_line(text)) == text

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
	_read(`count of x[0] is 1`).assertions[0].terms[0].count == {"bracketed": true, "position": 1, "steps": ["x"]}
	_read(_printed(`count of x[0] is 1`)).assertions[0].terms[0].count == {"position": 1, "steps": ["x"]}
}

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

test_a_check_written_as_a_string_is_read_as_a_sentence if {
	rendered({}, "present") == "present"
	stopped(solo({}, "present"))
	_sentence_problems("present") == [`nothing after the path at column 8: expected a phrase, like "is" or "exists"`]
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

test_an_any_of_of_sentences_passes_when_every_line_of_one_option_passes if {
	doc := {"components": [
		{"name": "click", "licenses": [{"license": {"id": "BSD-3-Clause"}}]},
		{"name": "prometheus-client"},
		{"name": "leftpad", "licenses": [{"license": {"id": "WTFPL"}}]},
	]}
	policy := {"ergo_spec": ergo._spec, "subjects": {"component": {"from": "components", "identified_by": "name"}}, "requirements": {"s": {"subject": "component", "checks": {"c": {"description": "The licence is allowed", "meta": {"k": 1}, "any_of": {
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

test_every_and_some_joined_with_and_give_one_row_with_the_failed_sentences if {
	doc := {"things": [{"id": "a", "n": 1, "xs": [{"v": 1}, {"v": 2}]}]}
	r := ergo.report(doc, _sentence_policy({"c": "n is 1 and every xs.v is 1 and some xs.v is 2"}), {})
	[[row.cause, row.failed_assertions, row.inputs] | some row in r.results; row.check == "c"] == [[
		"value",
		[{"assertion": "every xs.v is 1", "cause": "value"}],
		[{"name": "n", "value": 1, "locations": ["/things/0/n"]}, {"name": "xs[].v", "value": [1, 2], "locations": ["/things/0/xs/0/v", "/things/0/xs/1/v"]}],
	]]
}

test_a_for_line_prints_as_its_for_line_and_its_assertions if {
	r := ergo.report({"things": []}, _sentence_policy({"c": _peer_approval}), {})
	r.requirements.s.checks.c.expression == `for some approvers whose state is "APPROVED" as approver, every commits as commit: approver.username does not equal author and approver.timestamp is after commit.timestamp`
}

test_every_new_phrase_prints_back_as_written_with_its_own_article_and_spacing if {
	every sentence in [
		`x is not a list`,
		`x is not an object`,
		`x is not a non-empty string`,
		`x is not between 1 and 2`,
		`x is not 1 within 2`,
		`x does not equal y within 2`,
		`x contains some of "a", "b"`,
		`x does not contain all of y`,
		`x does not start with "a"`,
		`x does not end with y`,
		`x is alphabetically on or before "a"`,
		`x is alphabetically on or after y`,
		`count of x is not between 1 and 2`,
		`count of x is not 3 within 1`,
	] {
		_printed(sentence) == sentence
	}
}

_deployments := {"deployments": [
	{"id": 1, "environment": "prod", "change_type": "emergency"},
	{"id": 2, "environment": "dev"},
	{"id": 3, "environment": "prod", "change_type": "standard"},
]}

test_a_from_written_as_a_sentence_reads_its_path_and_keeps_the_subjects_whose_conditions_hold if {
	rep := _from_report(_deployments, {"emergency change": {"from": `deployments whose environment is "prod" and whose change_type is "emergency"`, "identified_by": "id"}}, {"c": "id exists"}, {})
	_from_rows(rep) == [
		[1, "$applies", "satisfied", [{"name": "change_type", "value": "emergency", "locations": ["/deployments/0/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/0/environment"]}]],
		[2, "$applies", "absent", [{"name": "change_type", "value": null, "locations": ["/deployments/1"]}, {"name": "environment", "value": "dev", "locations": ["/deployments/1/environment"]}]],
		[3, "$applies", "value", [{"name": "change_type", "value": "standard", "locations": ["/deployments/2/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/2/environment"]}]],
		[1, "c", "satisfied", [{"name": "id", "value": 1, "locations": ["/deployments/0/id"]}]],
	]
	rep.requirements.r.checks["$applies"].expression == `environment is "prod" and change_type is "emergency"`
}

test_conditions_of_a_from_can_use_phrases_only_sentences_have if {
	doc := {"xs": [{"id": 1, "tags": [], "cs": [1]}, {"id": 2, "tags": ["a"], "cs": [1]}]}
	rep := _from_report(doc, {"x": {"from": "xs whose tags is empty and whose count of cs is at least 1", "identified_by": "id"}}, {"c": "id exists"}, {})
	[[r[0], r[1], r[2]] | some r in _from_rows(rep)] == [[1, "$applies", "satisfied"], [2, "$applies", "value"], [1, "c", "satisfied"]]
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

test_the_applies_row_of_a_plain_condition_has_no_more_fields_than_the_check_row_of_the_same_sentence if {
	every sentence in [`ticket is "ok"`, `ticket is "open"`, `ticket exists`, `count of files is at least 2`, `sum of files.size is at least 2`] {
		both := _as_condition_and_as_check([sentence])
		every _, row in _applies_failures_of(both[0]) {
			row == {}
		}
		_applies_failures_of(both[0]) == _check_failures_of(both[1])
	}
}

test_a_from_condition_written_with_some_prints_in_the_spelling_of_the_report_and_joins_with_and if {
	rep := _from_report(_releases, {"release": {"from": `releases whose some  files.path   matches "x" and whose ticket   is "ok" and whose every files.path, if any, does not match "y"`, "identified_by": "id"}}, {"c": "ticket exists"}, {})
	rep.requirements.r.checks["$applies"].expression == `some files.path matches "x" and ticket is "ok" and every files.path, if any, does not match "y"`
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

test_a_narrowing_chain_deeper_than_ten_prints_in_order if {
	subjects := object.union({"s0": {"from": "defects whose id exists", "identified_by": "id"}}, {concat("", ["s", format_int(n, 10)]): {"from": concat("", ["s", format_int(n - 1, 10), " whose id is not ", format_int(100 + n, 10)])} | some n in numbers.range(1, 11)})
	rep := _narrow_report(subjects, "s11")
	rep.requirements.r.checks["$applies"].expression == concat(" and ", array.concat(["id exists"], [concat("", ["id is not ", format_int(100 + n, 10)]) | some n in numbers.range(1, 11)]))
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

test_a_sentence_root_that_cant_be_read_fails_once_before_any_item_on_an_empty_list if {
	checks := {"c": {"for": "every xs, if any, as m", "assert": "m.v is at least z"}}
	_for_sentence_root_rows(checks, {"xs": []}) == {"c": ["absent", "z is missing"]}
	_for_sentence_root_rows(checks, {"xs": [], "z": null}) == {"c": ["null", "z is null"]}
	_for_sentence_root_rows(checks, {"xs": [], "z": "s"}) == {"c": ["unusable", "z is \"s\", which isn't a number"]}
	_for_sentence_root_rows(checks, {"xs": [{"v": 1}, {"v": 2}], "z": "s"}) == {"c": ["unusable", "z is \"s\", which isn't a number"]}
}

test_a_sentence_root_that_cant_be_read_comes_before_an_empty_list_without_if_any if {
	checks := {"c": {"for": "every xs as m", "assert": "m.v is at least $params.missing"}}
	_for_sentence_root_rows(checks, {"xs": []}) == {"c": ["absent", "$params.missing is missing; xs is []"]}
}

test_a_sentence_that_doesnt_read_the_item_is_said_once_whatever_its_cause if {
	checks := {"one": {"for": "every xs as m", "assert": "z is 1"}, "exists": {"for": "every xs as m", "assert": "z exists"}}
	xs := [{"v": 1}, {"v": 2}]
	_for_sentence_root_rows(checks, {"xs": xs}) == {"one": ["absent", "z is missing"], "exists": ["value", "z is missing"]}
	_for_sentence_root_rows(checks, {"xs": xs, "z": null}) == {"one": ["null", "z is null"], "exists": ["value", "z is null"]}
	_for_sentence_root_rows(checks, {"xs": xs, "z": ""}) == {"one": ["unusable", "z is \"\", which isn't a number"]}
}

test_a_params_sentence_that_doesnt_read_the_item_is_said_once if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"subject": "thing", "checks": {"q": {"for": "every xs as m", "assert": "$params.q exists"}}}}}
	input_doc := {"things": [{"id": 1, "xs": [{"v": 1}, {"v": 2}]}]}
	msgs := {[p, r.cause, r.message, count(r.failed_items)] | some p in [{}, {"q": null}]; some r in ergo.report(input_doc, policy, p).results; r.check == "q"}
	msgs == {[{}, "value", "$params.q is missing", 2], [{"q": null}, "value", "$params.q is null", 2]}
}

test_failed_items_lists_every_item_when_the_list_a_sentence_looks_in_isnt_a_list if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"subject": "thing", "checks": {"c": {"for": "every xs as m", "assert": "m.v is in $params.q"}}}}}
	input_doc := {"things": [{"id": 1, "xs": [{"v": 1}, {}]}]}
	rows := {[q, r.cause, r.message, [[f.item, f.cause, [[a.assertion, a.cause] | some a in f.failed_assertions]] | some f in r.failed_items]] |
		some q in ["s", 3, {"a": 1}]
		some r in ergo.report(input_doc, policy, {"q": q}).results
		r.check == "c"
	}
	items := [["item 1 of xs", "unusable", [["m.v is in $params.q", "unusable"]]], ["item 2 of xs", "unusable", [["m.v is in $params.q", "unusable"]]]]
	rows == {
		["s", "unusable", "$params.q is \"s\", which isn't a list", items],
		[3, "unusable", "$params.q is 3, which isn't a list", items],
		[{"a": 1}, "unusable", "$params.q is {\"a\": 1}, which isn't a list", items],
	}
}

test_a_sentence_root_named_by_the_lines_alias_is_read_for_each_item if {
	checks := {"c": {"for": "every ks as k", "assert": "m named by k is 1"}}
	_for_sentence_root_rows(checks, {"ks": ["a", "b"], "m": {"a": 1}}) == {"c": ["absent", "item 2 of ks: m named by k is missing"]}
}

_old_policy := {
	"ergo_spec": ergo._spec,
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
		"ergo_spec": ergo._spec,
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
	policy := {"ergo_spec": ergo._spec, "subjects": {"artifact": {"from": ["artifact"]}, "pr": {"from": ["artifact", "prs"], "identified_by": ["url"]}}}
	ergo.as_sentences(policy).subjects == {"artifact": {"from": "artifact"}, "pr": {"from": "$input.artifact.prs", "identified_by": "url"}}
}

test_as_sentences_writes_naming_and_whole_input_and_narrowing_as_from_lines if {
	policy := {"ergo_spec": ergo._spec, "subjects": {
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
		"narrow": {"from": "run whose .a exists and whose b exists"},
		"filtered": policy.subjects.filtered,
	}
}

test_as_sentences_keeps_sections_that_arent_objects_and_other_fields if {
	ergo.as_sentences({"requirements": ["x"], "subjects": 5, "other": 1}) == {"ergo_spec": ergo._spec, "requirements": ["x"], "subjects": 5, "other": 1}
	ergo.as_sentences("x") == "x"
	ergo.as_sentences({"requirements": {"r": 1, "s": {"checks": []}}}) == {"ergo_spec": ergo._spec, "requirements": {"r": 1, "s": {"checks": []}}}
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
		"ergo_spec": ergo._spec,
		"subjects": {"d": {"from": "deployments"}, "c": {"from": "every d.commits"}},
		"requirements": {"r": {"subject": "c", "checks": {"k": "d.v exists"}}},
	}
	ergo.as_sentences(policy).requirements == policy.requirements
}

test_a_field_or_a_ref_after_a_list_phrase_lists_both_sides_in_the_row_inputs_and_keeps_the_sentence_as_written if {
	doc := {"things": [{"id": "t1", "files": ["a", "b"], "gaps": ["a"]}]}
	r := ergo.report(doc, _sentence_policy({"c": "files contains all of gaps"}), {})
	[row.inputs | some row in r.results; row.check == "c"] == [[{"name": "files", "value": ["a", "b"], "locations": ["/things/0/files"]}, {"name": "gaps", "value": ["a"], "locations": ["/things/0/gaps"]}]]
	r.requirements.s.checks.c == {"description": "", "meta": {}, "expression": "files contains all of gaps"}
	r2 := ergo.report(doc, _sentence_policy({"c": "files contains all of $params.k"}), {"k": ["a"]})
	[row.inputs | some row in r2.results; row.check == "c"] == [[{"name": "files", "value": ["a", "b"], "locations": ["/things/0/files"]}, {"name": "$params.k", "value": ["a"], "locations": ["$params:/k"]}]]
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

test_an_elapsed_time_on_the_right_of_is_prints_as_is_not_equals if {
	ergo.report({"things": []}, _sentence_policy({"c": "n is days elapsed from p to q and m is not days elapsed from p to q and k is count of xs"}), {}).requirements.s.checks.c.expression == "n equals days elapsed from p to q and m does not equal days elapsed from p to q and k equals count of xs"
}

test_an_old_subject_without_filters_prints_just_its_path if {
	_listed({"d": {"from": "deployments"}}, "d").d.from == "deployments"
	_listed({"d": {"from": "$input", "identified_by": "id"}}, "d").d.from == "$input"
}

test_an_old_subject_that_names_each_key_prints_it if {
	subjects := {"d": {"from": "trail.artifacts named by each of $params.names"}}
	_listed(subjects, "d").d.from == "trail.artifacts named by each of $params.names"
}

test_an_id_written_in_the_old_syntax_is_printed_as_a_sentence_path if {
	_listed({"d": {"from": "ds", "identified_by": "build.number"}}, "d").d.identified_by == "build.number"
	_listed({"d": {"from": "ds", "identified_by": "build.number"}}, "d").d.identified_by == "build.number"
}

test_as_sentences_leaves_an_old_check_that_names_an_alias_as_written_because_a_sentence_would_read_the_part if {
	policy := {
		"ergo_spec": ergo._spec,
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

test_a_pick_prints_as_written if {
	check := {"for": `item 2 from last of approvers whose state is "APPROVED" sorted by timestamp as approval`, "assert": "approval exists"}
	ergo.report({"things": [{"id": 1}]}, _sentence_policy({"c": check}), {}).requirements.s.checks.c.expression == `for item 2 from last of approvers whose state is "APPROVED" sorted by timestamp as approval: approval exists`
}

test_last_of_in_a_sentence_points_to_the_for_line if {
	every text in ["last of xs is 1", "item 2 from last of xs is 1"] {
		_sentence_problems({"assert": text}) == [`last of isn't supported yet here: pick the item on a for line, like "for: last of commits as commit"`]
	}
}

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
	every policy in [{}, {"ergo_spec": "v0"}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": ["items"]}}}] {
		ergo.as_sentences(policy).ergo_spec == ergo._spec
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
		ergo.as_sentences({"subjects": subjects}) == {"ergo_spec": ergo._spec, "subjects": subjects}
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

test_as_sentences_keeps_a_sentence_policy_with_parts_as_it_is if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"round": {"from": "rounds", "identified_by": "id", "has": {"a": "  d.b  ", "b": {"from": "d.\"x y\".z", "identified_by": "attestation_id"}, "c": "d.m named by $params.k", "e": "item 3 of d.items", "f": "d.items[1].y"}}}, "requirements": {"r": {"subject": "round", "checks": {"c": "id exists"}}}}
	ergo.as_sentences(policy) == policy
}

test_as_sentences_leaves_an_old_any_of_and_an_object_value_as_written if {
	checks := {
		"either": {"op": "any_of", "options": {"safe": [{"op": "equals", "path": ["type"], "value": "Chore"}], "standard": [{"op": "equals", "path": ["type"], "value": "Story"}, {"op": "equals", "path": ["state"], "value": "Done"}]}},
		"object": {"op": "equals", "path": ["x"], "value": {"a": "x", "b": [1, 2]}},
	}
	as_sentences_checks(checks) == checks
}

test_as_sentences_leaves_an_empty_path_and_a_field_called_like_the_subject_as_they_are if {
	pol := {"subjects": {"s": {"from": "xs"}}, "requirements": {"r": {"subject": "s", "checks": {"c": {"op": "equals", "path": [], "value": "x"}, "d": {"op": "equals", "path": ["s"], "value": 1}, "e": {"op": "present", "path": ["k"]}}}}}
	checks := ergo.as_sentences(pol).requirements.r.checks
	checks.c == {"op": "equals", "path": [], "value": "x"}
	checks.d == {"op": "equals", "path": ["s"], "value": 1}
	checks.e == "k exists"
	ergo.as_sentences({"requirements": {"r": {"checks": {"d": {"op": "equals", "path": ["s"], "value": 1}}}}}).requirements.r.checks.d == "s is 1"
}

test_a_failed_sentence_of_a_second_for_item_that_starts_at_a_parents_part_names_its_items_without_the_part_marker if {
	doc := {"artifact": {"n": "a", "ps": {"w": ["k1", "z"]}, "kids": [{"id": 1, "keys": ["k1"]}]}}
	row := _part_for_row(doc, {"ap": "ps"}, {"for": "every keys as k, every artifact.ap.w as x", "assert": "x is k"}, {})
	[[i.item | some i in a.items] | some a in row.failed_items[0].failed_assertions] == [["item 2 of artifact.ap.w"]]
}
