package ergo_test

import data.ergo
import rego.v1

test_min_subjects_at_zero_says_it_only_checks_that_from_can_be_read if {
	def := report({"items": []}, min_subjects_req(0)).requirements.s.checks["$min_subjects"]
	def.description == "The thing list can be read"
	def.expression == "items can be read"
}

test_well_formed_echoes_a_valid_require_and_says_what_is_wrong_with_any_other if {
	rows_for(report(both_ok, require_req("some")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2, "locations": []},
		{"name": "require", "value": "some", "locations": []},
	]
	rows_for(report(both_ok, require_req("most")), "s", "$well_formed")[0].inputs == [
		{"name": "count(checks)", "value": 2, "locations": []},
		{"name": "require", "value": ["neither every nor some"], "locations": []},
	]
}

test_the_report_says_which_version_of_the_spec_it_follows if {
	ergo.report(_engine_doc, _engine_policy, {}).ergo == ergo._spec
}

test_the_report_says_which_version_of_the_spec_it_follows_whatever_version_the_policy_names if {
	every v in ["v9.9", 0.1, null] {
		rep := ergo.report(_engine_doc, object.union(_engine_policy, {"ergo_spec": v}), {})
		[rep.ergo, rep.compliant] == [ergo._spec, false]
	}
}

test_a_report_that_cant_read_its_input_still_says_its_version_and_engine if {
	rep := ergo.report("not an object", _engine_policy, "not params")
	rep.ergo == ergo._spec
	rep.engine.name == "ergo-rego"
}

test_the_expected_version_in_the_row_is_the_one_the_report_says_it_follows if {
	rep := ergo.report({"items": [{"id": 1}]}, two_reqs_policy({"ergo_spec": "v0.1"}), {})
	row := [i.value[0] | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "policy ergo_spec"][0]
	endswith(row, concat("", [", expected ", rep.ergo]))
}

test_every_way_a_requirement_is_written_wrong_says_what_is_wrong if {
	got := {name: [row.passed, array.slice(row.inputs, 1, count(row.inputs))] |
		some name, [fields, _] in badly_written_requirements
		base := {"from": "items", "identified_by": "id", "checks": {"c": "id exists"}}
		req := object.union(object.remove(base, object.keys(fields)), fields)
		row := rows_for(report({"items": [{"id": 1}]}, {"s": req}), "s", "$well_formed")[0]
	}
	got == {name: [false, want] | some name, [_, want] in badly_written_requirements}
}

test_a_min_subjects_over_a_million_says_so_whatever_its_size if {
	every v in [1000001, 1000000.5, 1e308, 9007199254740993, -1, 1.5, "2", null, true] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == [{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []}]
	}
}

test_a_min_subjects_that_is_not_a_number_says_so_even_holding_a_number_out_of_range if {
	every v in [[1e400], {"a": 1e400}] {
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {"min_subjects": v})})
		problem_inputs(rep) == [{"name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": []}]
	}
}

test_a_requirement_without_checks_says_they_are_missing if {
	row := rows_for(report({"items": [{"id": 1}]}, {"s": {"from": "items"}}), "s", "$well_formed")[0]
	row.inputs == [{"name": "count(checks)", "value": 0, "locations": []}, {"name": "require", "value": "every", "locations": []}, {"name": "checks", "value": ["missing"], "locations": []}]
}

wrong_type_problems := {
	"checks": "not an object",
	"from": "not a string",
	"identified_by": "not a string",
	"min_subjects": "not a whole number from 0 to 1000000",
	"subject_type": "empty or not a string",
	"description": "not a string",
	"meta": "not an object",
}

test_a_field_of_the_wrong_type_fails_well_formed_and_says_what_it_should_be if {
	rows := [[f, "s" in object.keys(rep.requirements), rep.requirements.s.status, r.passed, r.cause, r.inputs[count(r.inputs) - 1]] |
		some [f, v] in wrong_types
		rep := report({"items": [{"id": 1}]}, {"s": object.union(typed_req, {f: v})})
		some r in rows_for(rep, "s", "$well_formed")
	]
	rows == [[f, true, "not_met", false, "value", {"name": lifted_field_name(f), "value": [wrong_type_problems[f]], "locations": []}] | some [f, _] in wrong_types]
}

lifted_field_name(f) := concat(".", ["subjects", "subject", f]) if f in subject_fields

lifted_field_name("subject_type") := "subject"

lifted_field_name(f) := f if not f in array.concat(subject_fields, ["subject_type"])

test_every_badly_written_check_fails_well_formed_and_says_what_is_wrong if {
	every case in badly_written {
		[check, at, want] := case
		rep := report(typo_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}})
		problem_inputs(rep) == [{"name": concat("", ["checks.c", at]), "value": want, "locations": []}]
	}
}

badly_written_filters := [
	[`x is one of 1, "a"`, "values of mixed types"],
	["x is between 9 and 0", "min above max"],
	[`x matches "("`, `invalid pattern "("`],
	["x is $foo", "unknown name $foo"],
	["xs[9007199254740992] exists", "9007199254740992 can't be a list position"],
	["x is at least x", "whose: x is compared with itself"],
	["x is at least 1e400", "number out of range: 1e400"],
	[`x is before "yesterday"`, `"is before" takes a time or a number`],
	["x is", "doesn't parse"],
]

test_every_badly_written_filter_fails_well_formed_and_says_what_is_wrong if {
	every case in badly_written_filters {
		[whose, want] := case
		rep := ergo.report({"things": [{"x": 1}]}, filter_policy({"b": {"from": concat(" whose ", ["things", whose])}}), {})
		problem_inputs(rep) == [{"name": "subjects.b.from", "value": [want], "locations": []}]
		rep.compliant == false
	}
}

test_min_subjects_says_what_the_input_and_params_hold_that_json_cannot if {
	rep := ergo.report({"items": [{"id": "a", "x": 1}], "tags": {"prod"}, "k": {1: "a"}}, lifted(json_only_req), {"allowed": {"MIT"}})
	rows_for(rep, "s", "$min_subjects")[0].inputs == [
		{"name": "in-scope thing count", "value": 1, "locations": ["/items/0"]},
		{"name": "$input", "value": ["holds a key that isn't a string", "holds a set"], "locations": []},
		{"name": "$params", "value": ["holds a set"], "locations": []},
	]
}

test_a_whose_belongs_to_the_quantifier_and_an_and_after_the_phrase_starts_a_new_assertion if {
	_read(`every items.price whose kind is "a" and whose qty is 1 is at least 2 and owner is "x"`) == {"assertions": [
		{
			"every": {"steps": ["items", "price"]},
			"where": [
				{"path": {"steps": ["kind"]}, "phrase": {"op": "is", "value": "a"}},
				{"path": {"steps": ["qty"]}, "phrase": {"op": "is", "value": 1}},
			],
			"phrase": {"op": "is at least", "value": 2},
		},
		{"path": {"steps": ["owner"]}, "phrase": {"op": "is", "value": "x"}},
	]}
}

test_each_phrase_reads_into_its_op if {
	_read(`x is not one of "a", "b"`).assertions[0].phrase == {"op": "is not one of", "values": ["a", "b"]}
	_read(`x is not in $params.k`).assertions[0].phrase == {"op": "is not one of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x is in $params.k`).assertions[0].phrase == {"op": "is one of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x is a non-empty string`).assertions[0].phrase == {"op": "is a non-empty string"}
	_read(`x is an object`).assertions[0].phrase == {"op": "is a", "type": "object"}
	_read(`x is a list`).assertions[0].phrase == {"op": "is a", "type": "list"}
	_read(`x is empty`).assertions[0].phrase == {"op": "is empty"}
	_read(`x is not empty`).assertions[0].phrase == {"op": "is not empty"}
	_read(`x exists`).assertions[0].phrase == {"op": "exists"}
	_read(`x does not exist`).assertions[0].phrase == {"op": "does not exist"}
	_read(`x contains all of "a", "b"`).assertions[0].phrase == {"op": "contains all of", "values": ["a", "b"]}
	_read(`x contains none of $params.k`).assertions[0].phrase == {"op": "contains none of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x contains "a"`).assertions[0].phrase == {"op": "contains", "value": "a"}
	_read(`x does not contain y`).assertions[0].phrase == {"op": "does not contain", "terms": [{"steps": ["y"]}]}
	_read(`x matches "^a"`).assertions[0].phrase == {"op": "matches", "values": ["^a"]}
	_read(`x does not match $params.p`).assertions[0].phrase == {"op": "does not match", "path": {"start": "params", "steps": ["p"]}}
	_read(`x starts with "a"`).assertions[0].phrase == {"op": "starts with", "value": "a"}
	_read(`x ends with "a"`).assertions[0].phrase == {"op": "ends with", "value": "a"}
	_read(`x is at least 1`).assertions[0].phrase == {"op": "is at least", "value": 1}
	_read(`x is at most 1`).assertions[0].phrase == {"op": "is at most", "value": 1}
	_read(`x is more than 1`).assertions[0].phrase == {"op": "is more than", "value": 1}
	_read(`x is less than 1`).assertions[0].phrase == {"op": "is less than", "value": 1}
	_read(`x is on or after y`).assertions[0].phrase == {"op": "is on or after", "terms": [{"steps": ["y"]}]}
	_read(`x is on or before y`).assertions[0].phrase == {"op": "is on or before", "terms": [{"steps": ["y"]}]}
	_read(`x is before y`).assertions[0].phrase == {"op": "is before", "terms": [{"steps": ["y"]}]}
	_read(`x is after y`).assertions[0].phrase == {"op": "is after", "terms": [{"steps": ["y"]}]}
	_read(`x is 1 within 0.5`).assertions[0].phrase == {"op": "is", "value": 1, "within": 0.5}
	_read(`x is not 1`).assertions[0].phrase == {"op": "is not", "value": 1}
	_read(`x does not equal y`).assertions[0].phrase == {"op": "is not", "terms": [{"steps": ["y"]}]}
	_read(`x is equal to y`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["y"]}]}
	_read(`x equals y`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["y"]}]}
}

test_a_whose_that_compares_a_field_with_itself_says_to_read_the_subjects_field_by_its_name if {
	message := "type is compared with itself, because in a whose it's read from the item: to read the subject's type, write thing.type"
	_sentence_problems(`some conditions.status whose type equals type is "OK"`) == [message]
	_sentence_problems({"for": "some conditions whose type equals type as condition", "assert": `condition.status is "OK"`}) == [concat("", ["for: ", message])]
}

test_a_count_of_or_sum_of_on_the_right_of_a_phrase_over_ten_steps_reads_and_gives_the_right_verdicts if {
	doc := {"things": [
		{"id": "a", "n": 2, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": [1, 1]}}}}}}}}}},
		{"id": "b", "n": 1, "k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": [1, 1]}}}}}}}}}},
	]}
	rows := _walk_rows({"c": concat("", ["n is count of ", _ten]), "d": concat("", ["n is at least sum of ", _ten])}, doc, {})
	[[r[0], r[1], r[2]] | some r in rows] == [["a", "c", "satisfied"], ["a", "d", "satisfied"], ["b", "c", "value"], ["b", "d", "value"]]
}

test_a_count_of_or_sum_of_over_more_than_ten_steps_is_written_wrong_on_the_right_of_a_phrase if {
	_sentence_problems(concat("", ["n is count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["n is at least sum of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["n is count of k1 plus count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["count of k1 is at least count of ", _eleven])) == _too_long
	_sentence_problems(concat("", ["count of k1 plus count of ", _eleven, " is 1"])) == _too_long
}

test_a_walk_that_is_already_written_wrong_for_another_reason_gets_no_ten_step_message_too if {
	has := {"x": _ten}
	_part_walk_problems(has, {"for": "every xs as x", "assert": "every x.z is 1"}) == ["x can't be an alias: it's a part of thing"]
	_part_walk_problems(has, {"for": "every xs as x", "assert": "count of x.z is 1"}) == ["x can't be an alias: it's a part of thing"]
	_parent_part_problems(has, "count of xs whose sum of b.x.z is 1 is 0") == [["a sum of or a plus in the whose of a count of or a sum of isn't supported yet"]]
}

test_a_parent_part_on_the_right_of_a_count_whose_gets_the_ten_step_message_beside_another_problem if {
	_parent_part_problems({"x": _ten}, "count of xs whose n is sum of b.x.z is 0") == [["a sum of or a plus in the whose of a count of or a sum of isn't supported yet", "every and some over more than ten steps aren't supported yet"]]
}

test_a_list_phrase_after_every_or_some_is_written_wrong_because_the_last_list_is_walked_too if {
	_sentence_problems(`every pull_requests.labels does not contain "hotfix"`) == [`"does not contain" after every or some would check each item of the last list, not the list: put the walk on a for line`]
	_sentence_problems(`some xs contains all of 1, 2`) == [`"contains all of" after every or some would check each item of the last list, not the list: put the walk on a for line`]
}

test_a_for_line_written_wrong_says_why if {
	_sentence_problems({"assert": "x exists", "for": 1}) == ["invalid for"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as y, every zs as z"}) == ["for: a for line holds two items at most"]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as"}) == [`for: an item ends with "as" and a name, like "every pull_requests as pr"`]
	_sentence_problems({"assert": "x.a exists", "for": "xs as x"}) == [`for: an item starts with "every", "some" or a position, like "last of"`]
	_sentence_problems({"assert": "x.a exists", "for": "every xs as x, every ys as x"}) == ["for: x is given twice"]
	_sentence_problems({"assert": "x.a is 1", "for": "every xs as params"}) == ["for: params can't be an alias"]
	_sentence_problems({"assert": "x.a is 1", "for": "some xs, if any, as x"}) == ["for: if any can't go with some"]
	_sentence_problems({"assert": "x is $foo", "for": "every xs as x"}) == ["unknown name $foo"]
}

test_each_new_phrase_reads_into_its_op if {
	_read(`x is not a list`).assertions[0].phrase == {"op": "is not a", "type": "list"}
	_read(`x is not an object`).assertions[0].phrase == {"op": "is not a", "type": "object"}
	_read(`x is not a non-empty string`).assertions[0].phrase == {"op": "is not a non-empty string"}
	_read(`x is not between 1 and 2`).assertions[0].phrase == {"op": "is not between", "min": 1, "max": 2}
	_read(`x is not 1 within 2`).assertions[0].phrase == {"op": "is not", "value": 1, "within": 2}
	_read(`x does not equal y within 2`).assertions[0].phrase == {"op": "is not", "terms": [{"steps": ["y"]}], "within": 2}
	_read(`x contains some of "a", "b"`).assertions[0].phrase == {"op": "contains some of", "values": ["a", "b"]}
	_read(`x does not contain all of $params.k`).assertions[0].phrase == {"op": "does not contain all of", "path": {"start": "params", "steps": ["k"]}}
	_read(`x does not start with "a"`).assertions[0].phrase == {"op": "does not start with", "value": "a"}
	_read(`x does not end with y`).assertions[0].phrase == {"op": "does not end with", "terms": [{"steps": ["y"]}]}
	_read(`x is alphabetically on or before "a"`).assertions[0].phrase == {"op": "is alphabetically on or before", "value": "a"}
	_read(`x is alphabetically on or after y`).assertions[0].phrase == {"op": "is alphabetically on or after", "terms": [{"steps": ["y"]}]}
}

test_a_failed_item_of_an_applies_row_says_where_its_value_was_read_in_the_input_of_its_own_subject if {
	doc := {"releases": [
		{"id": "a", "files": [{"path": "docs/x.md"}, {"path": "src/y.go"}]},
		{"id": "b", "files": [{"path": "docs/x.md"}, {"name": "z"}]},
	]}
	some_rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": {"release": {"from": `releases whose some files.path does not match "^docs/"`, "identified_by": "id"}}, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in some_rep.results; r.check == "$applies"} == {
		"a": [],
		"b": [
			{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/x.md", "locations": ["/releases/1/files/0/path"]},
			{"path": "files[1].path", "item": "item 2 of files", "cause": "absent", "value": null, "locations": ["/releases/1/files/1"]},
		],
	}
	every_rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": {"release": {"from": `releases whose every files.path matches "^docs/"`, "identified_by": "id"}}, "requirements": {"r": {"subject": "release", "checks": {"c": "id exists"}}}}, {})
	{r.subject.id: r.failed_items | some r in every_rep.results; r.check == "$applies"} == {
		"a": [{"path": "files[1].path", "item": "item 2 of files", "cause": "value", "value": "src/y.go", "locations": ["/releases/0/files/1/path"]}],
		"b": [{"path": "files[1].path", "item": "item 2 of files", "cause": "absent", "value": null, "locations": ["/releases/1/files/1"]}],
	}
	{r.subject.id: r.inputs | some r in every_rep.results; r.check == "$applies"} == {
		"a": [{"name": "files[].path", "value": ["docs/x.md", "src/y.go"], "locations": ["/releases/0/files/0/path", "/releases/0/files/1/path"]}],
		"b": [{"name": "files[].path", "value": ["docs/x.md", null], "locations": ["/releases/1/files/0/path", "/releases/1/files/1"]}],
	}
	not contains(json.marshal(every_rep), "~~")
}

test_a_from_or_id_written_wrong_says_why_in_well_formed if {
	every pair in [
		[{"from": "xs whose"}, {"name": "subjects.x.from", "value": ["doesn't parse"], "locations": []}],
		[{"from": "xs whose last of ys is 1"}, {"name": "subjects.x.from", "value": ["whose: last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""], "locations": []}],
		[{"from": "xs whose a is 1"}, {"name": "subjects.x.from", "value": ["a is a word of the grammar: write .a"], "locations": []}],
		[{"from": "xs", "identified_by": "id is 1"}, {"name": "subjects.x.identified_by", "value": [`identified_by is a path, like "id" or "build.number"`], "locations": []}],
		[{"from": "xs whose id exists", "applies_to": {"a": {"op": "present", "path": ["id"]}}}, {"name": "subjects.x.applies_to", "value": ["unknown field"], "locations": []}],
	] {
		_from_problems(_from_report({"xs": [{"id": 1}]}, {"x": pair[0]}, {"c": "id exists"}, {})) == [pair[1]]
	}
}

test_a_chain_reads_its_path_from_the_parents_one_subject_and_every_row_but_well_formed_says_which if {
	rep := _chain_report(_chain_doc, _chain_subjects, {"c": "approved is true"}, {"name": "web"})
	[[r.subject, r.check, r.cause] | some r in rep.results] == [
		[{"type": "pull request", "id": null}, "$well_formed", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$min_subjects", "satisfied"],
		[{"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "$unique_ids", "satisfied"],
		[{"type": "artifact", "id": null}, "$unique_ancestor_ids", "satisfied"],
		[{"type": "pull request", "id": "pr/7", "in": {"artifact": "sha-1"}}, "c", "satisfied"],
		[{"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "c", "value"],
	]
}

test_a_chain_from_several_parents_checks_the_subjects_of_each_and_every_row_but_well_formed_says_which if {
	rep := _chain_report(_many_doc, _kept_subjects, {"c": "ok is true"}, {})
	_rows_of(rep) == [
		["$well_formed", {"type": "pull request", "id": null}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["$min_subjects", {"type": "pull request", "id": null, "in": {"artifact": "b"}}, "satisfied"],
		["$unique_ids", {"type": "pull request", "id": null, "in": {"artifact": "a"}}, "satisfied"],
		["$unique_ids", {"type": "pull request", "id": null, "in": {"artifact": "b"}}, "satisfied"],
		["$unique_ancestor_ids", {"type": "artifact", "id": null}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "a"}}, "satisfied"],
		["c", {"type": "pull request", "id": "pr/8", "in": {"artifact": "a"}}, "value"],
		["c", {"type": "pull request", "id": "pr/7", "in": {"artifact": "b"}}, "satisfied"],
	]
	rep.requirements.r.subjects == {"total": 3, "matching": 3}
	rep.requirements.r.status == "not_met"
}

test_named_by_a_field_in_a_whose_reads_the_items_field_and_in_the_phrase_of_a_one_line_every_the_subjects if {
	doc := {"things": [{"id": 1, "kind": "b", "items": [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}]}]}
	params := {"min": {"a": 2, "b": 4}}
	_walk_rows({"c": "every items.n is at least $params.min named by kind"}, doc, params) == [[1, "c", "value", [
		{"cause": "value", "item": "item 1 of items", "path": "items[0].n", "value": 3, "locations": ["/things/0/items/0/n"]},
		{"cause": "value", "item": "item 2 of items", "path": "items[1].n", "value": 1, "locations": ["/things/0/items/1/n"]},
	]]]
	_sentence_rows({"c": "count of items whose n is at least $params.min named by kind is 1"}, doc, params)[0][2] == "satisfied"
}

_list_phrases := {
	"is one of": "is in",
	"is not one of": "is not in",
	"contains": "contains",
	"does not contain": "does not contain",
	"contains all of": "contains all of",
	"contains none of": "contains none of",
	"matches": "matches",
	"does not match": "does not match",
}

_walking_list_phrases := {k: w | some k, w in _list_phrases; not w in {"contains", "does not contain"}}

test_the_list_phrases_compared_with_params_are_every_list_phrase if {
	{w | some _, w in _list_phrases} == {"is in", "is not in", "contains", "does not contain", "contains all of", "contains none of", "matches", "does not match"}
}

test_a_path_that_cant_be_read_after_a_list_phrase_gives_the_cause_of_the_same_path_in_params if {
	every _, words in _list_phrases {
		every right in [{}, {"v": null}, {"v": "s"}, {"v": 3}, {"v": []}, {"v": {}}, {"v": {"z": null}}, {"v": {"z": ["a"]}}, {"v": {"z": "a"}}, {"v": {"z": ["^a"]}}] {
			_list_same_as_params(words, ".z", right)
		}
	}
}

test_each_list_phrase_with_a_field_fails_closed_on_a_missing_null_or_wrong_typed_side if {
	every pair in [
		["x is in y", "a", ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x is not in y", "a", ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains y", ["a"], "a", 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x does not contain y", ["a"], "a", 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains all of y", ["a"], ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x contains none of y", ["a"], ["a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x matches y", "a", ["^a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
		["x does not match y", "a", ["^a"], 3, ["absent", "null", "unusable", "absent", "null", "unusable"]],
	] {
		things := [
			{"id": 1, "y": pair[2]},
			{"id": 2, "x": null, "y": pair[2]},
			{"id": 3, "x": pair[3], "y": pair[2]},
			{"id": 4, "x": pair[1]},
			{"id": 5, "x": pair[1], "y": null},
			{"id": 6, "x": pair[1], "y": pair[3]},
		]
		[r[2] | some r in _list_verdicts(pair[0], things, {})] == pair[4]
	}
}

test_a_field_after_a_list_phrase_passes_and_fails_by_what_the_list_holds if {
	things := [
		{"id": 1, "x": "a", "l": ["a", "b"], "p": ["^a"], "w": "a"},
		{"id": 2, "x": "c", "l": ["a", "b"], "p": ["^a"], "w": "c"},
		{"id": 3, "x": ["a", "b"], "l": ["a"], "p": ["^a"], "w": "z"},
		{"id": 4, "x": ["a", "b"], "l": ["c"], "p": [], "w": "b"},
	]
	every pair in [
		["x is in l", [true, false, false, false]],
		["x is not in l", [false, true, false, false]],
		["x contains w", [false, false, false, true]],
		["x does not contain w", [false, false, true, false]],
		["x contains all of l", [false, false, true, false]],
		["x contains none of l", [false, false, false, true]],
		["x matches p", [true, false, false, false]],
		["x does not match p", [false, true, false, false]],
	] {
		[r[1] | some r in _list_verdicts(pair[0], things, {})] == pair[1]
	}
}

_ref_list_phrases := ["is in", "is not in", "contains", "does not contain", "contains all of", "contains none of", "contains some of", "does not contain all of", "matches", "does not match"]

test_a_ref_after_a_list_phrase_is_listed_after_the_field_whatever_the_cause if {
	every phrase in _ref_list_phrases {
		every pair in [
			[{"id": "t", "x": "a"}, {"k": ["a"]}],
			[{"id": "t", "x": "a"}, {"k": "text"}],
			[{"id": "t", "x": ["a"]}, {}],
			[{"id": "t", "x": ["a"]}, {"k": null}],
			[{"id": "t"}, {"k": ["a"]}],
			[{"id": "t", "x": null}, {"k": ["a"]}],
			[{"id": "t", "x": 1}, {"k": 1}],
		] {
			r := ergo.report({"things": [pair[0]]}, _sentence_policy({"c": concat(" ", ["x", phrase, "$params.k"])}), pair[1])
			[[i.name | some i in row.inputs] | some row in r.results; row.check == "c"] == [["x", "$params.k"]]
		}
	}
}

test_a_ref_after_a_list_phrase_shows_what_it_read_and_where if {
	doc := {"things": [{"id": "t", "x": "z"}]}
	every pair in [
		[{"k": ["a"]}, ["a"], ["$params:/k"]],
		[{"k": "text"}, "text", ["$params:/k"]],
		[{}, null, ["$params:"]],
		[{"k": null}, null, ["$params:/k"]],
	] {
		r := ergo.report(doc, _sentence_policy({"c": "x is in $params.k"}), pair[0])
		[row.inputs[1] | some row in r.results; row.check == "c"] == [{"name": "$params.k", "value": pair[1], "locations": pair[2]}]
	}
	r := ergo.report({"things": [{"id": "t", "x": "z"}], "ks": [{"n": "a"}, {"n": "b"}]}, _sentence_policy({"c": "x is not in $input.ks.n"}), {})
	[row.inputs | some row in r.results; row.check == "c"] == [[
		{"name": "x", "value": "z", "locations": ["/things/0/x"]},
		{"name": "$input.ks[].n", "value": ["a", "b"], "locations": ["/ks/0/n", "/ks/1/n"]},
	]]
}

test_every_some_count_and_for_rows_list_a_ref_after_a_list_phrase_where_is_at_least_lists_its_right_side if {
	doc := {"things": [{"id": "t", "xs": [{"n": 1, "s": "a"}]}], "l": [2], "p": ["^a"], "z": 5}
	every pair in [
		["every xs.n is in $input.l", "every xs.n is at least $input.z"],
		["every xs.n is not in $params.l", "every xs.n is at least $params.z"],
		["some xs.s matches $input.p", "some xs.s is at least $input.z"],
		["count of xs whose n is in $input.l is 1", "count of xs whose n is at least $input.z is 1"],
		["count of xs whose s matches $params.p is 1", "count of xs whose n is at least $params.z is 1"],
		[{"for": "every xs as x", "assert": "x.n is in $params.l"}, {"for": "every xs as x", "assert": "x.n is at least $params.z"}],
		[{"for": "every xs as x", "assert": "x.s does not match $input.p"}, {"for": "every xs as x", "assert": "x.n is at least $input.z"}],
		[{"for": "every xs as x", "assert": "every xs.n is in $input.l"}, {"for": "every xs as x", "assert": "every xs.n is at least $input.z"}],
	] {
		r := ergo.report(doc, _sentence_policy({"a": pair[0], "b": pair[1]}), {"l": [2], "p": ["^a"], "z": 5})
		names := {row.check: [_twin_name(i.name) | some i in row.inputs] | some row in r.results; row.check in {"a", "b"}}
		names.a == names.b
	}
}

_twin_name(name) := "count" if startswith(name, "count of")

_twin_name(name) := "right" if name in {"$input.l", "$input.p", "$input.z", "$params.l", "$params.p", "$params.z"}

_twin_name(name) := name if {
	not startswith(name, "count of")
	not name in {"$input.l", "$input.p", "$input.z", "$params.l", "$params.p", "$params.z"}
}

test_a_field_of_the_input_before_a_list_phrase_reads_a_field_of_the_subject_after_it if {
	doc := {"artifact": {"developers": ["ann", "bob"]}, "things": [{"id": "t1", "tested_by": "cy"}, {"id": "t2", "tested_by": "ann"}]}
	r := ergo.report(doc, _sentence_policy({"c": "$input.artifact.developers does not contain tested_by"}), {})
	[[row.subject.id, row.cause, row.inputs] | some row in r.results; row.check == "c"] == [
		["t1", "satisfied", [{"name": "$input.artifact.developers", "value": ["ann", "bob"], "locations": ["/artifact/developers"]}, {"name": "tested_by", "value": "cy", "locations": ["/things/0/tested_by"]}]],
		["t2", "value", [{"name": "$input.artifact.developers", "value": ["ann", "bob"], "locations": ["/artifact/developers"]}, {"name": "tested_by", "value": "ann", "locations": ["/things/1/tested_by"]}]],
	]
}

test_a_list_phrase_with_a_field_runs_after_a_for_line_and_a_one_line_every_or_some_and_reads_the_subject if {
	doc := {"things": [
		{"id": 1, "excluded": ["q"], "allowed": ["s1"], "ok": ["s1", "s2"], "approvers": [{"username": "x"}, {"username": "y"}], "commits": [{"sha": "s1", "author": "x", "ok": ["s9"]}, {"sha": "s2", "author": "z", "ok": ["s1"]}]},
		{"id": 2, "excluded": ["x"], "allowed": ["s9"], "ok": ["s9"], "approvers": [{"username": "x"}, {"username": "y"}], "commits": [{"sha": "s1", "author": "x", "ok": ["s1"]}]},
	]}
	checks := {
		"f": {"for": "every approvers as ap", "assert": "ap.username is not one of excluded"},
		"w": "every commits.sha is in ok",
		"s": "some commits.sha is in ok",
		"c": {"for": "every commits as cm", "assert": "cm.sha is in allowed"},
	}
	[[r.check, r.subject.id, r.passed, r.cause] | some r in ergo.report(doc, _sentence_policy(checks), {}).results; r.check in {"f", "w", "s", "c"}] == [
		["c", 1, false, "value"], ["f", 1, true, "satisfied"], ["s", 1, true, "satisfied"], ["w", 1, true, "satisfied"],
		["c", 2, false, "value"], ["f", 2, false, "value"], ["s", 2, false, "value"], ["w", 2, false, "value"],
	]
}

test_a_list_phrase_with_a_field_runs_in_a_from_lines_whose if {
	doc := {"deployments": [
		{"id": 1, "environment": "prod", "allowed_envs": ["prod"]},
		{"id": 2, "environment": "dev", "allowed_envs": ["prod"]},
		{"id": 3, "environment": "prod", "allowed_envs": ["dev"]},
	]}
	rep := _from_report(doc, {"d": {"from": "deployments whose environment is in allowed_envs", "identified_by": "id"}}, {"c": "id exists"}, {})
	[r[0] | some r in _from_rows(rep); r[1] == "c"] == [1]
}

test_a_whose_of_a_count_with_a_field_after_a_list_phrase_decides_each_item_as_the_same_whose_with_params_does if {
	every _, words in _list_phrases {
		every right in [{}, {"v": null}, {"v": 3}, {"v": []}, {"v": ["a"]}, {"v": ["^a"]}, {"v": ["^a", "("]}] {
			items := [{"s": "a", "l": ["a"]}, {"s": "b", "l": ["a"]}, {"s": null, "l": "a"}]
			by_field := _tally_rows(concat("", ["count of xs whose s ", words, " k is at least 1"]), [{"id": 1, "xs": [object.union(i, object.filter(_list_item_right(right), ["k"])) | some i in items]}], {})
			by_params := _tally_rows(concat("", ["count of xs whose s ", words, " $params.k is at least 1"]), [{"id": 1, "xs": items}], _list_params(right))
			[r[1] | some r in by_field] == [r[1] | some r in by_params]
		}
	}
}

_list_item_right(right) := {"k": right.v} if "v" in object.keys(right)

_list_item_right(right) := {} if not "v" in object.keys(right)

test_an_elapsed_time_goes_in_a_plus_on_either_side_of_a_phrase if {
	doc := [{"id": 1, "n": 3, "p": 0, "q": 86400}, {"id": 2, "n": 3, "p": 0, "q": "1970-01-02T00:00:00Z"}, {"id": 3, "n": 3, "p": null, "q": 86400}, {"id": 4, "n": "3", "p": 0, "q": 86400}, {"id": 5, "n": 3, "p": 86400, "q": 0}]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("days elapsed from p to q plus n is 4", doc, {})] == [[1, true, "satisfied"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("n is days elapsed from p to q", doc, {})] == [[1, false, "value"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
	with_x := [object.union(d, {"x": [1, 2]}) | some d in doc]
	[[r[0], r[1], r[2]] | some r in _elapsed_rows("n is less than 1 plus days elapsed from p to q plus count of x", with_x, {})] == [[1, true, "satisfied"], [2, false, "unusable"], [3, false, "null"], [4, false, "unusable"], [5, false, "value"]]
}

test_elapsed_cant_take_a_phrase_that_takes_no_number if {
	_sentence_problems("days elapsed from p to q is empty") == ["is empty can't follow a count of, a sum of or a plus"]
	_sentence_problems("days elapsed from p to q is before c") == ["is before can't follow a count of, a sum of or a plus"]
}

test_a_whose_in_a_count_compared_with_itself_says_to_read_the_subjects_field_by_its_name if {
	message := "x is compared with itself, because in a whose it's read from the item: to read the subject's x, write thing.x"
	_sentence_problems("count of xs whose x equals x is 2") == [message]
	_sentence_problems("sum of xs.y whose x equals .x is 2") == ["whose x: sum of adds up numbers, which have no fields: to keep numbers by their value, write that instead of whose", message]
}

test_a_time_phrase_with_a_written_value_fails_closed_on_every_kind_of_field if {
	doc := {"things": [{"id": "a", "t": "2024-01-01T00:00:00Z"}, {"id": "b", "t": 5}, {"id": "c", "t": null}, {"id": "d"}, {"id": "e", "t": [1]}, {"id": "f", "t": "2025-01-01T00:00:00Z"}]}
	rows := _sentence_rows({"c": "t is before \"2024-06-01T00:00:00Z\""}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "unusable"], [false, "null"], [false, "absent"], [false, "unusable"], [false, "value"]]
}

test_a_written_value_after_a_time_phrase_that_isnt_a_time_is_written_wrong_because_it_could_only_fail if {
	every pair in [[`t is before null`, `"is before" takes a time or a number`], [`t is after true`, `"is after" takes a time or a number`], [`t is on or after "yesterday"`, `"is on or after" takes a time or a number`], [`t is on or before "2024-02-30"`, `"is on or before" takes a time or a number`], [`t is before "2024-02-30T00:00:00Z"`, `"is before" takes a time or a number`]] {
		_sentence_problems(pair[0]) == [pair[1]]
	}
}

test_a_written_number_after_a_time_phrase_is_a_time_so_a_text_field_is_unusable if {
	doc := {"things": [{"id": "a", "t": "2024-01-01T00:00:00Z"}, {"id": "b", "t": 5}]}
	[r[2] | some r in _sentence_rows({"c": "t is before 6"}, doc, {})] == ["unusable", "satisfied"]
}

test_a_time_phrase_with_a_written_value_shows_only_the_field_it_reads if {
	_sentence_rows({"c": "t is on or after 5"}, {"things": [{"id": "a", "t": 5}]}, {}) == [["c", true, "satisfied", [{"name": "t", "value": 5, "locations": ["/things/0/t"]}]]]
}

test_a_time_phrase_with_a_written_value_goes_in_a_whose if {
	doc := {"things": [{"id": "a", "xs": [{"t": "2024-01-01T00:00:00Z", "v": "x"}, {"t": "2026-01-01T00:00:00Z", "v": ""}]}, {"id": "b", "xs": [{"t": "2024-01-01T00:00:00Z", "v": ""}]}, {"id": "c", "xs": [{"t": 5, "v": ""}]}]}
	rows := _sentence_rows({"c": {"for": "every xs whose t is before \"2025-01-01T00:00:00Z\" as x", "assert": "x.v is not empty"}}, doc, {})
	[[r[1], r[2]] | some r in rows] == [[true, "satisfied"], [false, "value"], [false, "unusable"]]
	count_rows := _sentence_rows({"c": "count of xs whose t is before \"2025-01-01T00:00:00Z\" is 1"}, doc, {})
	[[r[1], r[2]] | some r in count_rows] == [[true, "satisfied"], [true, "satisfied"], [false, "unusable"]]
}

test_named_by_works_after_each_phrase_that_takes_a_list if {
	causes := {sentence: [r[2] | some r in _sentence_rows({"c": sentence}, _named_things, _named_params)] |
		some sentence in [
			"x is not in $params.lists named by $params.k",
			"x matches $params.pats named by $params.k",
			"x does not match $params.pats named by $params.k",
			"x matches $params.pats named by $params.kbad",
			"kind contains $params.lists named by $params.k",
			"kind contains none of $params.lists named by $params.k",
		]
	}
	causes["x is not in $params.lists named by $params.k"] == ["value", "satisfied", "value", "value", "value", "unusable"]
	causes["x matches $params.pats named by $params.k"] == ["value", "value", "value", "value", "value", "unusable"]
	causes["x does not match $params.pats named by $params.k"] == ["satisfied", "satisfied", "satisfied", "satisfied", "satisfied", "unusable"]
	causes["x matches $params.pats named by $params.kbad"] == ["unusable", "unusable", "unusable", "unusable", "unusable", "unusable"]
	causes["kind contains $params.lists named by $params.k"] == ["unusable", "unusable", "unusable", "unusable", "absent", "unusable"]
	causes["kind contains none of $params.lists named by $params.k"] == ["unusable", "unusable", "unusable", "unusable", "absent", "unusable"]
}

test_a_pick_written_wrong_says_why if {
	_sentence_problems({"assert": "x exists", "for": "xs as x"}) == [`for: an item starts with "every", "some" or a position, like "last of"`]
	_sentence_problems({"assert": "x exists", "for": "every xs sorted by t as x"}) == [`for: "sorted by" goes after a position, like "last of", not after every or some`]
	_sentence_problems({"assert": "x exists", "for": "last of xs, if any, as x"}) == ["for: if any can't go with a position"]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by $params.t as x"}) == [`for: "sorted by" reads a field of each item`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by last of t as x"}) == [`for: "sorted by" reads a field of each item`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by y.t as x, every ys as y"}) == [`for: "sorted by" reads a field of the item, not y: write .y`]
	_sentence_problems({"assert": "x exists", "for": "last of xs sorted by x as x"}) == [`for: "sorted by" reads a field of the item, not x: write .x`]
}

test_a_number_out_of_range_after_a_time_or_order_phrase_is_reported_once if {
	_sentence_problems({"assert": "x is before 1e400"}) == ["number out of range: 1e400"]
	_sentence_problems({"assert": "x is at least 1e400"}) == ["number out of range: 1e400"]
}

test_a_written_value_after_an_order_phrase_has_to_be_a_number if {
	_sentence_problems({"assert": "x is at most \"3\""}) == [`"is at most" takes a number`]
	_sentence_problems({"assert": "x is less than true"}) == [`"is less than" takes a number`]
}

test_a_written_date_after_a_time_phrase_is_a_time if {
	[r.cause | some r in ergo.report({"things": [{"id": 1, "x": "2026-09-30"}, {"id": 2, "x": "2026-10-01"}]}, _sentence_policy({"c": "x is before \"2026-10-01\""}), {}).results; r.check == "c"] == ["satisfied", "value"]
}

kinds_doc := {"items": [{"id": 1, "s": "x", "n": 5, "o": {"a": 1}, "e": [], "l": [1], "t": "2026-01-01T00:00:00Z", "bad_t": "2026-02-30T00:00:00Z"}]}

kind_cause(check) := [r.cause | some r in rows_for(report(kinds_doc, {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}}), "s", "c")][0]

test_a_value_the_phrase_cannot_use_fails_as_unusable if {
	every check in [
		"s is between 0 and 9",
		"n is \"5\"",
		"n is one of \"5\"",
		"n is one of \"5\", null",
		"l contains \"1\"",
		"l contains none of \"1\"",
		"n matches \"x\"",
		"n does not match \"x\"",
		"s contains \"x\"",
		"s does not contain \"y\"",
		"n equals s",
		"n is before t",
		"bad_t is before t",
		"s.x does not exist",
		"l.x does not exist",
		"item 1 of o does not exist",
	] {
		kind_cause(check) == "unusable"
	}
}

test_each_input_of_a_subject_in_a_list_says_where_in_the_input_it_was_read if {
	_located_rows({"c": "x exists"}, {"things": [{"id": "t1", "x": 1}, {"id": "t2"}, {"id": "t3", "x": null}]}, {}) == [
		["t1", "c", [{"name": "x", "locations": ["/things/0/x"]}]],
		["t2", "c", [{"name": "x", "locations": ["/things/1"]}]],
		["t3", "c", [{"name": "x", "locations": ["/things/2/x"]}]],
	]
}

test_a_walk_on_a_missing_list_has_no_values_and_its_failed_item_says_where_it_stopped if {
	rows := _walk_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "x": {}}]}, {})
	rows[0][3] == [{"path": "prs", "item": "prs", "cause": "absent", "value": null, "locations": ["/things/0"]}]
	inputs := _sentence_rows({"c": "every prs.title is \"x\""}, {"things": [{"id": 1, "x": {}}]}, {})
	inputs[0][3] == [{"name": "prs.title", "value": [], "locations": []}]
}

test_nothing_can_follow_a_subjects_name_and_the_problem_says_to_write_a_dot_for_a_field if {
	_subject_problems("every xs", {"c": "s.name is 1"}) == ["s.name: nothing can follow s, which means the subject: for a field called s, write .s.name"]
	_subject_problems("every xs", {"c": `s."x y" is 1`}) == [`s."x y": nothing can follow s, which means the subject: for a field called s, write .s."x y"`]
	_subject_problems("every xs", {"c": "every s.name is 1"}) == ["s.name: nothing can follow s, which means the subject: for a field called s, write .s.name"]
	_subject_problems("every xs", {"c": "x is s.k"}) == ["s.k: nothing can follow s, which means the subject: for a field called s, write .s.k"]
	_subject_problems("every xs", {"c": "count of s.k is 1"}) == ["s.k: nothing can follow s, which means the subject: for a field called s, write .s.k"]
	_subject_problems("every xs", {"c": "s[0].k is 1"}) == ["s[0].k: nothing can follow s, which means the subject: for a field called s, write .s[0].k"]
	_subject_problems("every xs", {"c": "first of s.k is 1"}) == ["first of s.k: nothing can follow s, which means the subject: for a field called s, write .s.k"]
}

test_the_subjects_name_on_the_right_of_a_phrase_reads_the_subject if {
	_subject_rows({"xs": [1, 2]}, "every xs", "s is s", {}) == []
	rows := _subject_rows({"xs": [{"id": "a", "x": 1}, {"id": "b", "x": {"id": "b", "x": 2}}]}, "every xs", "x is s", {})
	[r[1] | some r in rows] == [false, false]
	rows[0][3] == [{"name": "x", "value": 1, "locations": ["/xs/0/x"]}, {"name": "s", "value": {"id": "a", "x": 1}, "locations": ["/xs/0"]}]
	_subject_rows({"xs": [[1, 2]]}, "every xs", "count of x is count of s", {})[0][1] == false
}

test_a_for_alias_named_like_a_subject_and_a_part_gets_both_messages if {
	_clash_problems({"b": "k1.k2.k3"}, {}, {"for": "every xs as b", "assert": "b.v is 1"}) == [["b can't be an alias: it's a part of b", "b can't be an alias: it's a subject's name"]]
}

test_a_subject_name_with_a_space_is_quoted_in_the_message if {
	subjects := {"pull request": {"from": "bs", "identified_by": "id", "has": {"pull": "k1"}}, "kid": {"from": `every "pull request".kids`, "identified_by": "id", "has": {"pull": "xs"}}}
	_part_clash_problems(subjects) == [{"name": "subjects.kid.has.pull", "value": ["pull can't be an alias: it's a part of \"pull request\""], "locations": []}]
}

test_a_policy_that_is_not_an_object_says_so_in_place_of_requirements if {
	rep := ergo.report({}, ["x"], {})
	rows_for(rep, "$policy", "$well_formed")[0].inputs == [{"name": "policy", "value": ["not an object"], "locations": []}]
}

test_a_requirement_whose_subject_is_empty_says_so_under_subject if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"": {"from": "xs"}}, "requirements": {"r": {"subject": "", "checks": {"c": "x exists"}}}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	[i.value | some i in rows_for(rep, "r", "$well_formed")[0].inputs; i.name == "subject"] == [["empty or not a string"]]
}

test_message_names_the_object_that_cant_hold_a_key_read_from_a_field if {
	r := ergo.report({"things": [{"id": "t", "m": 5, "p": "k"}]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "m named by p is 1"}}}}, {})
	some row in r.results
	row.check == "c"
	row.message == "m is 5, which isn't an object"
}

test_message_names_a_param_that_isnt_a_number_on_the_right_of_a_comparison if {
	r := ergo.report({"things": [{"id": "t", "x": 4}]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "x is more than $params.max"}}}}, {"max": "5"})
	some row in r.results
	row.check == "c"
	row.message == "$params.max is \"5\", which isn't a number"
}

test_message_of_a_count_names_an_item_whose_field_cant_hold_the_next_step if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "count of xs.n.b is 1"}}}}
	r := ergo.report({"things": [{"id": "t", "xs": [{"n": 5}]}]}, policy, {})
	some row in r.results
	row.check == "c"
	row.message == "item 1 of xs: n is 5, which isn't an object"
}

_count_message(assertion, thing, params) := row.message if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": assertion}}}}
	r := ergo.report({"things": [object.union({"id": "t"}, thing)]}, policy, params)
	some row in r.results
	row.check == "c"
}

test_message_of_a_count_names_the_list_in_a_list_item_it_not_an_empty_name if {
	_count_message("count of x[0] named by zz is 1", {"x": [[1]], "zz": "a"}, {}) == "item 1 of x: item 1 of it is 1, which isn't an object"
	_count_message("count of x[0] named by zz is 1", {"x": [[{"a": 1}, 3]], "zz": "a"}, {}) == "item 1 of x: item 2 of it is 3, which isn't an object"
	_count_message("count of x[0] named by zz is 1", {"x": [[[]]], "zz": "a"}, {}) == "item 1 of x: item 1 of it is [], which isn't an object"
	_count_message("count of x[0] named by zz is 1", {"x": [[]], "zz": "a"}, {}) == "count of x[0] named by zz is 0"
	_count_message("count of x[0] named by zz is 5", {"x": [[{"a": 1}]], "zz": "a"}, {}) == "count of x[0] named by zz is 1"
	_count_message("count of x[0][0] named by zz is 1", {"x": [[[1]]], "zz": "a"}, {}) == "item 1 of x: item 1 of it: item 1 of it is 1, which isn't an object"
}

test_message_of_a_count_names_the_list_in_a_list_item_it_with_a_for_alias if {
	_count_message_for("count of w[0] named by zz is 1", {"ws": [[{"a": 1}, 3]], "zz": "a"}) == "item 1 of ws: item 1 of w: .a is 1, which isn't a list or an object"
}

test_message_of_a_count_names_the_list_in_a_list_item_it_in_params if {
	_count_message("count of $params.p[0] named by zz is 1", {"zz": "a"}, {"p": [[1]]}) == "item 1 of $params.p: item 1 of it is 1, which isn't an object"
	_count_message("count of $params.p[0][0] named by zz is 1", {"zz": "a"}, {"p": [[[1]]]}) == "item 1 of $params.p: item 1 of it: item 1 of it is 1, which isn't an object"
}

_count_message_for(assertion, thing) := row.message if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": {"assert": assertion, "for": "every ws as w"}}}}}
	r := ergo.report({"things": [object.union({"id": "t"}, thing)]}, policy, {})
	some row in r.results
	row.check == "c"
}

test_does_not_exist_with_a_key_from_a_field_that_cant_be_read_fails_as_absent_with_its_message if {
	row := _row_of("x[0] named by zz does not exist", {}, {})
	row.cause == "absent"
	row.message == "zz is missing"
	row2 := _row_of("x[0] named by zz does not exist", {"zz": 3}, {})
	row2.cause == "absent"
	row2.message == "x[0] named by zz is missing"
}

test_message_of_a_count_with_a_key_from_a_field_names_the_value_once if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "count of x named by zz is 1"}}}}
	r := ergo.report({"things": [{"id": "t", "x": {"k": 1}, "zz": "k"}]}, policy, {})
	some row in r.results
	row.check == "c"
	row.message == "x.k is 1, which isn't a list or an object"
}

test_message_names_a_param_that_isnt_a_time_on_the_right_of_a_time_comparison if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "opened is before $params.deadline"}}}}
	r := ergo.report({"things": [{"id": "t", "opened": "2026-10-02T10:00:00Z"}]}, policy, {"deadline": "soon"})
	some row in r.results
	row.check == "c"
	row.cause == "unusable"
	row.message == "$params.deadline is \"soon\", which isn't a time"
}

test_message_of_an_unreadable_input_with_refs_that_are_fine_still_has_a_message if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "every things named by $params.k", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "x is 1"}}}}
	r := ergo.report({1: "x"}, policy, {"k": "a"})
	some row in r.results
	row.check == "$min_subjects"
	row.passed == false
	row.cause == "unusable"
	is_string(row.message)
}

test_every_list_phrase_walks_a_list_input_on_its_right_side if {
	doc := [{"id": "a", "k": "x", "p": "^a", "tags": ["x"], "nest": [["x"]]}, {"id": "b", "k": "y", "p": "^b", "tags": ["z"], "nest": [["z"]]}]
	every check, want in {
		"id is one of $input.id": [true, true],
		"id is not one of $input.id": [false, false],
		"tags contains all of $input.k": [false, false],
		"tags contains none of $input.k": [false, true],
		"tags contains some of $input.k": [true, false],
		"tags does not contain all of $input.k": [true, true],
		"id matches $input.p": [true, true],
		"id does not match $input.p": [false, false],
	} {
		rows := [r | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"]
		[r.passed | some r in rows] == want
		every r in rows {
			r.cause in {"satisfied", "value"}
		}
	}
}

test_every_list_phrase_fails_every_row_as_absent_when_an_item_has_no_value_even_the_rows_that_would_pass if {
	every _, words in _walking_list_phrases {
		every row in _walk_right_rows(concat("", ["x ", words, " $input.sbom.components.name"]), _walk_right_doc([{"name": "click"}, {}]), {}) {
			row[1] == "absent"
			row[2] == "item 2 of $input.sbom.components: name is missing"
		}
	}
}

test_every_list_phrase_fails_every_row_as_null_when_an_item_has_a_null_value if {
	every _, words in _walking_list_phrases {
		every row in _walk_right_rows(concat("", ["x ", words, " $input.sbom.components.name"]), _walk_right_doc([{"name": null}]), {}) {
			row[1] == "null"
			row[2] == "item 1 of $input.sbom.components: name is null"
		}
	}
}

test_every_list_phrase_fails_every_row_as_value_when_the_list_it_walks_is_empty_even_the_ones_that_say_not if {
	every _, words in _walking_list_phrases {
		every row in _walk_right_rows(concat("", ["x ", words, " $input.sbom.components.name"]), _walk_right_doc([]), {}) {
			row[0] == false
			row[1] == "value"
			endswith(row[2], "$input.sbom.components is []")
		}
	}
}

test_every_list_phrase_fails_every_row_as_unusable_when_an_item_or_what_it_reads_past_is_not_an_object if {
	every _, words in _walking_list_phrases {
		every row in _walk_right_rows(concat("", ["x ", words, " $input.sbom.components.name"]), _walk_right_doc(["click"]), {}) {
			row[1] == "unusable"
			endswith(row[2], "item 1 of $input.sbom.components is \"click\", which isn't an object")
		}
		every row in _walk_right_rows(concat("", ["x ", words, " $input.sbom.components.name.x"]), _walk_right_doc([{"name": "click"}]), {}) {
			row[1] == "unusable"
			endswith(row[2], "item 1 of $input.sbom.components: name is \"click\", which isn't an object")
		}
	}
}

test_contains_with_a_ref_from_an_input_that_is_a_list_says_it_once_inside_a_whose if {
	doc := [{"id": "t", "k": "a", "items": [{"tags": ["a"]}, {"tags": ["b"]}]}]
	m := "$input is [{\"id\": \"t\", \"items\": [{\"tags\": [\"a\"]}, {\"tags\": [\"b\"]}], \"k\": \"a\"}], which isn't an object"
	every check in ["count of items whose tags contains $input.k is 1", "count of items whose tags does not contain $input.k is 1", "every items whose tags contains $input.k exists"] {
		[[r.cause, r.message] | some r in ergo.report(doc, _list_key_policy({"from": "$input", "identified_by": "id"}, check), {}).results; r.check == "c"] == [["not_an_object", m]]
	}
}

test_a_ref_that_reads_into_text_says_which_value_cant_hold_the_next_step if {
	every row in _walk_right_rows("x is in $input.sbom.components.name", {"sbom": {"components": "x"}, "things": [{"id": "t1", "x": "a"}]}, {}) {
		row[1] == "unusable"
		row[2] == "$input.sbom.components is \"x\", which isn't an object"
	}
}

test_a_whose_inside_count_of_says_once_which_value_cant_hold_the_next_step_of_a_ref if {
	rows := _walk_right_rows("count of deps whose name is in $input.a.b is 1", {"a": "text", "things": [{"id": "t1", "deps": [{"name": "click"}, {"name": "jinja2"}]}]}, {})
	rows == [[false, "unusable", "$input.a is \"text\", which isn't an object"]]
}

test_a_field_on_both_sides_of_a_phrase_is_said_once_in_the_message if {
	_dot_plain_rows("tags contains none of .tags", {"repos": [{"id": "r", "tags": ["a"]}]})[0].message == "tags is [\"a\"]"
	_dot_plain_rows("tags contains none of tags", {"repos": [{"id": "r", "tags": ["a"]}]})[0].message == "tags is [\"a\"]"
}

test_a_from_line_that_reads_null_params_says_the_param_is_missing if {
	_from_params_rows("things named by each of $params.ks", null) == [["$min_subjects", "absent", "$params.ks is missing"]]
	_from_params_rows("things named by $params.env", null) == [["$min_subjects", "absent", "$params.env is missing"]]
}

test_a_key_named_by_the_whole_subject_says_the_subject_cant_name_a_key if {
	message := "named by s: s is the whole subject, so it can't name a key"
	_subject_problems("every xs", {"c": "x named by s is 1"}) == [message]
	_subject_problems("every xs", {"c": "$params.m named by s is 1"}) == [message]
	_subject_problems("every xs", {"c": "x is at most $params.m named by s"}) == [message]
	_subject_problems("every xs", {"c": {"for": "every x as e", "assert": "e named by s is 1"}}) == [message]
	_subject_problems("every xs", {"c": {"any_of": {"a": "x named by s is 1", "b": "x exists"}}}) == [concat("", ["option a: ", message])]
	_subject_problems("every xs", {"c": {"assert": ["x exists", "x named by s is 1"]}}) == [message]
}

test_a_failed_walk_item_message_names_the_item_and_not_the_subject if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"x": "k1.k2"}}}, "requirements": {"s": {"subject": "thing", "checks": {"c": "every x.z is 1"}}}}
	rep := ergo.report({"things": [{"id": "t2", "k1": {"k2": {"z": [1, 2]}}}]}, policy, {})
	[r.message | some r in rep.results; r.check == "c"] == ["item 2 of x.z is 2"]
}

test_a_distinct_phrase_that_reads_a_bare_name_reads_it_from_the_subject_so_it_is_not_written_wrong if {
	every place in numbers.range(0, 4) {
		_distinct_scope_reads(place)
	}
	problems := _from_problems(_from_report({"rs": [{"lo": 1, "fs": [{"k": 5, "lo": 1}]}]}, {"w": {"from": "every rs whose some distinct fs.k is at least lo"}}, {"c": "w exists"}, {}))
	count(problems) == 0
}

_distinct_scope_reads(place) if {
	every sentence in [`every distinct xs.k is at least lo`, `some distinct xs.k is in ok`, `every distinct xs.k is at least .lo`, `every distinct xs.k whose lo is 1 is at least lo`] {
		checks := [
			sentence,
			{"assert": ["xs exists", sentence]},
			{"for": "every ys as y", "assert": sentence},
			{"for": "every ys as y", "assert": ["y exists", sentence]},
			{"any_of": {"x": sentence, "y": "xs exists"}},
		]
		rep := _from_report({"s": {"lo": 3, "ok": [5], "xs": [{"k": 5, "lo": 1}, {"k": 5, "lo": 9}], "ys": [1]}}, {"s": {}}, {"c": checks[place]}, {})
		[r.passed | some r in rep.results; r.check == "$well_formed"] == [true]
	}
}

test_message_of_an_empty_list_read_on_the_right_names_the_root_that_is_missing_not_the_list if {
	rep := ergo.report({"prs": [{"id": "p", "ys": [{}], "xs": []}]}, {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "min_subjects": 0, "checks": {"c": {"for": "every ys as y", "assert": "every xs.v, if any, equals y.z"}}}}}, {})
	some r in rep.results
	r.check == "c"
	r.message == "item 1 of ys: y.z is missing"
}

test_a_walk_whose_ref_step_cant_be_read_names_its_path_and_every_root_its_phrase_cant_read if {
	whose := {"c": "every xs named by $params.k whose v is 1, if any, exists"}
	_root_rows(whose, {"id": "p", "xs": []}, {}).c == ["absent", "xs named by $params.k is missing"]
	_root_rows(whose, {"id": "p", "xs": []}, {"k": null}).c == ["null", "xs named by $params.k is null"]
	phrase := {"c": "every xs named by $params.k, if any, equals q"}
	_root_rows(phrase, {"id": "p", "xs": []}, {}).c == ["absent", "xs named by $params.k is missing; q is missing"]
	_root_rows(phrase, {"id": "p", "xs": [], "q": null}, {"k": null}).c == ["null", "xs named by $params.k is null; q is null"]
	_root_rows(phrase, {"id": "p", "xs": [], "q": 1}, {}).c == ["absent", "xs named by $params.k is missing"]
}

test_a_for_check_that_reads_params_says_only_that_params_is_not_an_object if {
	rows := _params_not_object_rows(_params_not_object_doc, 3)
	rows.least_q == ["unusable", "$params is 3, which isn't an object", 0]
	rows.in_q == ["unusable", "$params is 3, which isn't an object", 0]
	rows_s := _params_not_object_rows(_params_not_object_doc, "s")
	rows_s.least_q == ["unusable", "$params is \"s\", which isn't an object", 0]
	rows_s.in_q == ["unusable", "$params is \"s\", which isn't an object", 0]
	rows_l := _params_not_object_rows(_params_not_object_doc, [])
	rows_l.least_q == ["unusable", "$params is [], which isn't an object", 0]
	rows_l.in_q == ["unusable", "$params is [], which isn't an object", 0]
}

test_a_for_check_that_does_not_read_params_keeps_its_message_and_lists_every_item_when_params_is_not_an_object if {
	every params in [3, "s", []] {
		rows := _params_not_object_rows(_params_not_object_doc, params)
		rows.least_z == ["unusable", "z is \"s\", which isn't a number", 2]
		rows.plain == ["unusable", "z is \"s\", which isn't a number", 2]
	}
}

test_a_null_item_under_a_named_by_key_says_it_is_null_once_beside_the_item_that_isnt_text if {
	doc := {"prs": [{"id": "p0", "xs": [null, {"k": "a"}]}]}
	rows := _item_rows(_named_by_policy, doc, {})
	want := "item 1 of xs: m is null; item 2 of xs: m is {\"k\": \"a\"}, which isn't text"
	rows.every == ["unusable", want]
	rows.if_any == ["unusable", want]
	rows.two == ["unusable", concat("", ["$params.l is missing; ", want])]
}

test_a_null_item_under_a_named_by_key_says_it_is_null_once_when_params_are_there if {
	rows := _item_rows(_named_by_policy, {"prs": [{"id": "p0", "xs": [null]}]}, {"l": 1})
	every check in ["every", "if_any", "two"] {
		rows[check] == ["null", "item 1 of xs: m is null"]
	}
}

_part_policy := _item_policy({"has": {"pl": "c"}}, {
	"in": {"for": "every xs as m", "assert": "m.v is in pl.z"},
	"matches": {"for": "every xs as m", "assert": "m.v matches pl.z"},
	"contains": {"for": "every xs as m", "assert": "pl.z contains m.v"},
})

test_a_part_that_isnt_an_object_on_the_right_of_a_list_phrase_fails_as_unusable_and_names_the_part if {
	rows := _item_rows(_part_policy, {"prs": [{"id": "p0", "c": [], "xs": [{"v": 1}]}]}, {})
	every check in ["in", "matches", "contains"] {
		rows[check] == ["unusable", "pl is [], which isn't an object"]
	}
}

test_a_part_that_is_a_list_of_objects_is_not_walked_on_the_right_of_a_list_phrase if {
	rows := _item_rows(_part_policy, {"prs": [{"id": "p0", "c": [{"z": 1}], "xs": [{"v": 1}]}]}, {})
	rows.in == ["unusable", "pl is [{\"z\": 1}], which isn't an object"]
	rows.contains == ["unusable", "pl is [{\"z\": 1}], which isn't an object"]
	rows.matches == ["unusable", "pl is [{\"z\": 1}], which isn't an object; item 1 of xs: m.v is 1, which isn't text, and pl[].z is [1], which isn't a list of patterns"]
}

test_a_part_that_is_text_or_null_on_the_right_of_a_list_phrase_says_so if {
	text := _item_rows(_part_policy, {"prs": [{"id": "p0", "c": "s", "xs": [{"v": 1}]}]}, {})
	null_part := _item_rows(_part_policy, {"prs": [{"id": "p0", "c": null, "xs": [{"v": 1}]}]}, {})
	every check in ["in", "matches", "contains"] {
		text[check][0] == "unusable"
		null_part[check] == ["null", "pl is null"]
	}
	text["in"] == ["unusable", "pl is \"s\", which isn't an object"]
}

test_a_part_that_is_an_object_with_a_list_still_works_on_the_right_of_a_list_phrase if {
	rows := _item_rows(_part_policy, {"prs": [{"id": "p0", "c": {"z": [1]}, "xs": [{"v": 1}]}]}, {})
	rows["in"][0] == "satisfied"
	rows.contains[0] == "satisfied"
}

test_a_part_that_holds_text_or_null_or_nothing_still_says_so_for_a_count_of_whose_under_a_for_line if {
	xs := [{"v": 1, "ys": [{"v": 1}]}]
	text := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": "s", "xs": xs}]}, {})
	text.xs == ["unusable", "pl is \"s\", which isn't an object"]
	null_part := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": null, "xs": xs}]}, {})
	null_part.ys == ["null", "pl is null"]
	missing := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "xs": xs}]}, {})
	missing.at_least == ["absent", "pl.z is missing"]
}
