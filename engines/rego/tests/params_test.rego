package ergo_test

import data.ergo
import rego.v1

test_a_number_a_float_cannot_hold_read_from_the_params_is_compared_exactly if {
	check := "n is $params.n"
	big := row_in({}, {"id": 1, "n": 1e400}, check) with data.params as {"n": 1e400}
	small := row_in({}, {"id": 1, "n": 0}, check) with data.params as {"n": 1e-400}
	[[big.passed, big.cause], [small.passed, small.cause]] == [[true, "satisfied"], [false, "value"]]
	json.marshal(big.inputs) == `[{"locations":["/items/0/n"],"name":"n","value":1e400},{"locations":["$params:/n"],"name":"$params.n","value":1e400}]`
}

test_a_path_can_start_at_params if {
	check := "$params.level is one of \"strict\", \"lax\""
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.level", "value": "strict", "locations": ["$params:/level"]}]]] with data.params as {"level": "strict"}
}

test_params_that_are_missing_fail_closed if {
	check := "licences does not contain $params.banned"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}, {"name": "$params.banned", "value": null, "locations": ["$params:"]}]]]
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}, {"name": "$params.banned", "value": null, "locations": ["$params:"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "absent", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}, {"name": "$params.banned", "value": null, "locations": ["$params:"]}]]] with data.params as null
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "unusable", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}, {"name": "$params.banned", "value": null, "locations": ["$params:"]}]]] with data.params as "not an object"
	params_rows({"items": [{"id": 1, "licences": ["MIT"]}]}, check) == [[false, "null", [{"name": "licences", "value": ["MIT"], "locations": ["/items/0/licences"]}, {"name": "$params.banned", "value": null, "locations": ["$params:/banned"]}]]] with data.params as {"banned": null}
}

test_a_present_check_on_a_param_fails_as_absent_with_no_params_and_as_unusable_with_params_that_are_not_an_object if {
	check := "$params.x exists"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as null
	every params in ["not an object", 1, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[false, "value", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as {}
}

test_a_missing_check_on_a_param_fails_as_absent_with_no_params_and_as_unusable_with_params_that_are_not_an_object if {
	check := "$params.x does not exist"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as null
	every params in ["not an object", 1, [1]] {
		params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as params
	}
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params.x", "value": null, "locations": ["$params:"]}]]] with data.params as {}
}

test_the_report_never_reads_data_params if {
	policy := lifted(params_req("name is $params.artifact_name"))
	rep := ergo.report({"items": [{"id": 1, "name": "app"}]}, policy, {"artifact_name": "app"}) with data.params as {"artifact_name": "web"}
	[[r.passed, r.inputs] | some r in rows_for(rep, "s", "c")] == [[true, [{"name": "name", "value": "app", "locations": ["/items/0/name"]}, {"name": "$params.artifact_name", "value": "app", "locations": ["$params:/artifact_name"]}]]]
	unset := ergo.report({"items": [{"id": 1, "name": "app"}]}, policy, {}) with data.params as {"artifact_name": "app"}
	[r.cause | some r in rows_for(unset, "s", "c")] == ["absent"]
}

test_params_are_not_read_from_the_input if {
	check := "name is $params.artifact_name"
	params_rows({"items": [{"id": 1, "name": "app"}], "params": {"artifact_name": "app"}}, check) == [[false, "absent", [{"name": "name", "value": "app", "locations": ["/items/0/name"]}, {"name": "$params.artifact_name", "value": null, "locations": ["$params:"]}]]]
}

test_a_key_called_dollar_dollar_params_is_read_with_literal if {
	check := "\"$$params\" is \"own\""
	params_rows({"items": [{"id": 1, "$$params": "own"}]}, check) == [[true, "satisfied", [{"name": `"$$params"`, "value": "own", "locations": ["/items/0/$$params"]}]]] with data.params as {"$$params": "other"}
}

test_a_list_in_the_params_is_read_as_usual if {
	req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is one of $params.allowed"}}}
	rows_for(ergo.report({"items": [{"id": "a", "x": "MIT"}]}, lifted(req), {"allowed": ["MIT"]}), "s", "c")[0].passed == true
}

test_null_params_are_no_params_and_fail_nothing_a_policy_does_not_read if {
	every params in [null, {}] {
		rep := ergo.report({"items": [{"id": "a", "x": 1}]}, lifted(json_only_req), params)
		row_verdicts(rep) == [["$well_formed", true, "satisfied"], ["$min_subjects", true, "satisfied"], ["$unique_ids", true, "satisfied"], ["c", true, "satisfied"]]
	}
}

test_a_whole_params_read_with_null_params_fails_as_absent_and_with_an_object_reads_it if {
	check := "$params exists"
	params_rows({"items": [{"id": 1}]}, check) == [[false, "absent", [{"name": "$params", "value": null, "locations": ["$params:"]}]]] with data.params as null
	params_rows({"items": [{"id": 1}]}, check) == [[true, "satisfied", [{"name": "$params", "value": {}, "locations": ["$params:"]}]]] with data.params as {}
	params_rows({"items": [{"id": 1}]}, check) == [[false, "unusable", [{"name": "$params", "value": "x", "locations": ["$params:"]}]]] with data.params as "x"
}

test_a_path_reads_params_input_lookups_positions_and_quoted_keys if {
	_read(`$params.k."b c"[2].d is 1`).assertions[0].path == {"start": "params", "steps": ["k", "b c", {"index": 2}, "d"]}
	_read(`$params.k."b c"[2] is 1`).assertions[0].path == {"start": "params", "position": 3, "steps": ["k", "b c"], "bracketed": true}
	_read(`item 3 of k."b c" is 1`).assertions[0].path == {"position": 3, "steps": ["k", "b c"]}
	_read(`item 3 of k[0] is 1`).assertions[0].path == {"position": 3, "steps": ["k", {"index": 0}]}
	_read(`$input.x named by persona.y is 1`).assertions[0].path == {"start": "input", "steps": ["x", {"named_by": {"steps": ["persona"]}}, "y"]}
	_read(`b[$params.k] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"start": "params", "steps": ["k"]}}]}
	_read(`b[$input."k"] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"start": "input", "steps": ["k"]}}]}
	_read(`b[persona] is 1`).assertions[0].path == {"steps": ["b", {"named_by": {"steps": ["persona"]}}]}
	_read(`b["k"] is 1`).assertions[0].path == {"steps": ["b", "k"]}
	_read(`item 3 of b.c is 1`).assertions[0].path == {"position": 3, "steps": ["b", "c"]}
	_read(`first of b is 1`).assertions[0].path == {"position": "first", "steps": ["b"]}
	_read(`last of b is 1`).assertions[0].path == {"position": "last", "steps": ["b"]}
	_read(`"$schema" is 1`).assertions[0].path == {"steps": ["$schema"]}
	_read(`.count is 1`).assertions[0].path == {"steps": ["count"], "dot": true}
	_read(`"empty" is 1`).assertions[0].path == {"steps": ["empty"]}
	_read(`x is ."$schema"`).assertions[0].phrase == {"op": "is", "terms": [{"steps": ["$schema"], "dot": true}]}
	_read(`.x is 1`).assertions[0].path == {"steps": ["x"], "dot": true}
	_read(`x equals .total`).assertions[0].phrase.terms == [{"steps": ["total"], "dot": true}]
}

test_a_bare_params_or_input_after_named_by_or_in_brackets_does_not_parse_even_with_an_unknown_name if {
	every text in [`x named by $params is 1`, `x named by $input is 1`, `x[$params] is 1`, `x[$input] is 1`, `x named by $params is $foo`] {
		_sentence_problems(text) == ["doesn't parse"]
	}
}

test_is_not_in_a_list_read_from_the_params_fails_when_the_params_dont_hold_a_list if {
	doc := {"things": [{"id": "a", "x": "dev"}]}
	checks := {"e": "x is not in $params.empty", "m": "x is not in $params.none", "t": "x is not in $params.text"}
	[[r[0], r[2]] | some r in _sentence_rows(checks, doc, {"empty": [], "text": "prod"})] == [["e", "satisfied"], ["m", "absent"], ["t", "unusable"]]
}

test_an_any_of_fails_as_unusable_when_a_param_is_the_wrong_type_even_if_another_option_passes if {
	r := ergo.report({"things": [{"id": "a", "x": 1}]}, _sentence_policy({"c": {"any_of": {"a": "x is 1", "b": "x is in $params.l"}}}), {"l": "text"})
	[[row.passed, row.cause] | some row in r.results; row.check == "c"] == [[false, "unusable"]]
}

test_a_missing_param_only_fails_the_options_of_an_any_of_that_read_it if {
	rows := _sentence_rows({"c": {"any_of": {"a": "x is 1", "b": "x is in $params.l"}}}, {"things": [{"id": "t", "x": 1}, {"id": "u", "x": 2}]}, {})
	[[row[1], row[2]] | some row in rows] == [[true, "satisfied"], [false, "absent"]]
}

test_a_one_line_some_lists_an_input_value_it_compares_with_but_not_a_param if {
	_owner_rows({"input": "some commits.author is $input.artifact.owner", "param": "some commits.author is $params.owner"}) == {
		"input": [{"name": "$input.artifact.owner", "value": "ann", "locations": ["/artifact/owner"]}, _owner_authors],
		"param": [_owner_authors],
	}
}

_list_rights := [
	{},
	{"v": null},
	{"v": []},
	{"v": ["a"]},
	{"v": ["a", "b"]},
	{"v": "a"},
	{"v": "text"},
	{"v": 3},
	{"v": true},
	{"v": {"k": "a"}},
	{"v": [1, "a"]},
	{"v": ["a", null]},
	{"v": [["a"]]},
	{"v": ["^a", "("]},
	{"v": ["^a"]},
	{"v": ["^a", 1]},
	{"v": [null]},
	{"v": ["a", "a"]},
	{"v": [1]},
	{"v": [{"k": "a"}]},
	{"v": "("},
	{"v": ["["]},
	{"v": [true]},
	{"v": [false]},
]

_list_same_as_params_for_every_right(words) if {
	every right in _list_rights {
		_list_same_as_params(words, "", right)
	}
}

test_a_field_after_is_in_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("is in")

test_a_field_after_is_not_in_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("is not in")

test_a_field_after_contains_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains")

test_a_field_after_does_not_contain_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("does not contain")

test_a_field_after_contains_all_of_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains all of")

test_a_field_after_contains_none_of_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("contains none of")

test_a_field_after_matches_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("matches")

test_a_field_after_does_not_match_gives_the_verdict_and_cause_of_the_same_list_read_from_params if _list_same_as_params_for_every_right("does not match")

test_a_list_read_with_named_by_a_params_key_shows_the_field_and_the_list_it_read if {
	rows := _sentence_rows({"c": "x is in $params.lists named by $params.k"}, _named_things, _named_params)
	[[r[1], r[2], r[3]] | some r in rows] == [
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/0/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
		[false, "value", [{"name": "x", "value": "z", "locations": ["/things/1/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/2/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/3/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
		[true, "satisfied", [{"name": "x", "value": "p", "locations": ["/things/4/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
		[false, "unusable", [{"name": "x", "value": 3, "locations": ["/things/5/x"]}, {"name": "$params.lists named by $params.k", "value": ["p", "q"], "locations": ["$params:/lists/a"]}]],
	]
}

test_a_pick_sorted_by_a_field_named_by_a_param_reads_the_param if {
	check := {"for": "last of xs sorted by t named by $params.k as x", "assert": "x.n is 2"}
	[row[1] | some row in _for_rows(check, [{"id": 1, "xs": [{"n": 1, "t": {"a": 1, "b": 9}}, {"n": 2, "t": {"a": 2, "b": 0}}]}], {"k": "a"})] == ["satisfied"]
}

test_a_path_into_params_gives_its_location_after_the_params_prefix if {
	check := {"c": "n is at most $params.max_days.high"}
	doc := {"things": [{"id": "t1", "n": 3}]}
	_located_rows(check, doc, {"max_days": {"high": 4}}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:/max_days/high"]}]]]
	_located_rows(check, doc, {"max_days": {}}) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:/max_days"]}]]]
	every params in [{}, null, "text", [1]] {
		_located_rows(check, doc, params) == [["t1", "c", [{"name": "n", "locations": ["/things/0/n"]}, {"name": "$params.max_days.high", "locations": ["$params:"]}]]]
	}
}

test_a_ref_that_is_not_a_path_in_the_input_or_the_params_has_no_location if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": {"assert": "x exists", "meta": {"ref": ["x"]}}}}}}
	rep := ergo.report({"things": [{"id": "t1", "x": "a"}]}, policy, {})
	rep.requirements.s.checks.c["$refs"] == [{"name": "<invalid ref>", "value": null, "locations": []}]
}

test_a_params_path_that_starts_with_a_position_names_the_params_that_are_not_a_list if {
	every case in [[3, "3"], ["s", "\"s\""], [true, "true"]] {
		params_position_messages == {
			"c": concat("", ["$params is ", case[1], ", which isn't a list"]),
			"d": concat("", ["$params is ", case[1], ", which isn't a list"]),
			"e": concat("", ["$params is ", case[1], ", which isn't a list"]),
		} with data.params as case[0]
	}
}

test_a_params_path_that_starts_with_a_key_names_the_params_that_are_not_an_object if {
	every case in [[3, "3"], ["s", "\"s\""], [true, "true"], [false, "false"], [[], "[]"]] {
		params_key_messages.c == concat("", ["$params is ", case[1], ", which isn't an object"]) with data.params as case[0]
		params_key_messages.e == concat("", ["$params is ", case[1], ", which isn't an object"]) with data.params as case[0]
	}
}

test_null_params_fail_params_exists_as_absent_like_a_path_into_them if {
	rows := [r |
		some r in report(
			{"items": [{"id": 1}]},
			{"s": {
				"subject_type": "thing",
				"from": "items",
				"identified_by": "id",
				"checks": {"c": {"assert": "$params exists"}},
			}},
		).results
		r.check == "c"
	] with data.params as null
	[[r.cause, r.message] | some r in rows] == [["absent", "$params is missing"]]
}

_tie_policy := _item_policy({}, {
	"plain": {"for": "every xs as p, first of xs whose k is p.k sorted by v as m", "assert": "m.v is 1"},
	"reads": {"for": "every xs as p, first of xs whose k is p.k sorted by v as m", "assert": "m.v is at least $params.n"},
	"in": {"for": "every xs as p, first of xs whose k is p.k sorted by v as m", "assert": "m.v is in $params.l"},
})

_tie_doc := {"prs": [{"id": "p0", "xs": [{"k": "a", "v": 1}, {"k": "a", "v": 1}]}]}

_tie_text := "item 1 of xs: item 1 and item 2 of xs tie on v; item 2 of xs: item 1 and item 2 of xs tie on v"

_params_word(params) := sprintf("%v", [params]) if is_number(params)

_params_word(params) := "[]" if params == []

_params_word(params) := "\"s\"" if params == "s"

_params_word(params) := "true" if params == true

test_params_that_are_not_an_object_leave_a_tie_ambiguous_when_the_check_does_not_read_them if {
	every params in [3, [], "s", true, {}, null] {
		_item_rows(_tie_policy, _tie_doc, params).plain == ["ambiguous", _tie_text]
	}
}

test_params_that_are_not_an_object_are_named_before_a_tie_when_the_check_reads_them if {
	every params in [3, [], "s", true] {
		rows := _item_rows(_tie_policy, _tie_doc, params)
		prefix := concat("", ["$params is ", _params_word(params), ", which isn't an object; "])
		rows.reads == ["ambiguous", concat("", [prefix, _tie_text])]
		rows["in"] == ["ambiguous", concat("", [prefix, _tie_text])]
	}
}

test_params_that_are_missing_or_null_are_named_before_a_tie_when_the_check_reads_them if {
	every params in [{}, null] {
		rows := _item_rows(_tie_policy, _tie_doc, params)
		rows.reads == ["ambiguous", concat("", ["$params.n is missing; ", _tie_text])]
		rows["in"] == ["ambiguous", concat("", ["$params.l is missing; ", _tie_text])]
	}
}

test_params_that_are_not_an_object_still_fail_a_check_without_a_tie_as_unusable_not_as_not_an_object if {
	policy := _item_policy({}, {
		"plain": {"for": "every xs as m", "assert": "m.v is at least 1"},
		"reads": {"for": "every xs as m", "assert": "m.v is at least $params.n"},
	})
	every params in [3, [], "s", true] {
		rows := _item_rows(policy, {"prs": [{"id": "p0", "xs": ["s", null]}]}, params)
		rows.plain[0] == "unusable"
		rows.reads == ["unusable", concat("", ["$params is ", _params_word(params), ", which isn't an object"])]
	}
}
