package ergo_test

import data.ergo
import rego.v1

test_a_for_row_with_no_failed_item_says_what_the_empty_list_found if {
	ergo._for_item_parts({"items": [{"path": ["xs"]}]}, {"xs": []}, {"cause": "value", "failed": []}, []) == ["xs is []"]
}

test_a_root_message_said_inside_another_is_not_said_again if {
	ergo._with_roots(["x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["y is missing", "x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["item 1 of xs: y is missing"], ["y is missing"]) == ["item 1 of xs: y is missing"]
}

test_a_for_row_that_only_names_roots_has_no_item_text if {
	ergo._for_item_parts({}, {}, {"root_msgs": ["a"], "failed": []}, ["a"]) == []
}

test_a_second_for_roots_problem_is_added_to_the_row_in_every_state_the_row_can_be_in if {
	xs := [{"fl": "absent", "ms": ["m"]}]
	ergo._for_second_rooted({"cause": "value", "failed": [{}]}, xs) == {"cause": "absent", "failed": [{}], "other_roots": ["m"]}
	ergo._for_second_rooted({"cause": "value", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "absent", "failed": [], "root_msgs": ["m"]}
	ergo._for_second_rooted({"cause": "unusable", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "unusable", "failed": [{"failed_assertions": [1]}], "other_roots": ["m"]}
}

test_a_root_said_once_is_not_said_again_under_an_item_and_its_count_of_more_goes_with_it if {
	ergo._for_deduped("item 2 of pos: name is missing; item 1 of ms: item 2 of pos: name is missing; item 1 of ms: and 2 more") == "item 2 of pos: name is missing"
	ergo._for_deduped("item 1 of ms: v is missing; item 1 of ms: and 2 more") == "item 1 of ms: v is missing; item 1 of ms: and 2 more"
}

test_a_for_line_keeps_that_a_member_walk_wanted_an_object if {
	ergo._for_failed_flags({"msg": "an object"}).wants == "an object"
	not ergo._for_failed_flags({"msg": "a list"}).wants
	not ergo._for_failed_flags({}).wants
}

test_a_for_line_drops_a_member_clause_that_only_repeats_a_text_or_says_how_many_more if {
	not ergo._for_led_once("member a of xs: $params.k is missing", ["member b of ys: $params.k is missing"])
	ergo._for_led_once("member a of xs: member b of ys is 1", ["member b of ys is 1"])
	ergo._for_led_more("member a of xs: and 2 more")
	not ergo._for_led_more("member a of xs: v is 1")
}

test_an_item_of_the_second_list_keeps_that_a_member_walk_wanted_an_object if {
	check := {"items": [{"as": "r", "path": ["rs"]}, {"as": "y", "path": ["$r", "s"]}]}
	f := {"path": ["$r", "s"], "item": ["$r", "s"], "cause": "unusable", "value": [1], "msg": "an object"}
	ergo._for_unchecked_item(check, f).wants == "an object"
	not ergo._for_unchecked_item(check, object.union(f, {"msg": "a list"})).wants
}

_second_list_outcome(line, subj) := object.get([i | some i in ergo._for_inputs(check, subj, {}, check.items[0], ergo._for_walk(check.items[0], subj, {})); startswith(i.name, "x.ys")][0], "ergo/outcome", "usable") if {
	check := ergo._s_written_check({"for": line, "assert": "y is 1"})
}

test_a_second_member_walk_that_finds_no_object_at_any_end_says_its_worst_stop_in_any_order if {
	member := "every xs as x, every member of x.ys as y"
	_second_list_outcome(member, {"xs": [{"ys": [1]}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": 3}, {"ys": null}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": null}, {"ys": 3}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": null}, {}]}) == "absent"
	_second_list_outcome(member, {"xs": [{"ys": {"a": 1}}, {"ys": 3}]}) == "usable"
	_second_list_outcome(member, {"xs": [{"ys": {}}, {"ys": 3}]}) == "usable"
	_second_list_outcome(member, {"xs": [null, {"ys": 3}]}) == "usable"
}

_root_clauses_of(line, sentences, subj, params) := cs if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	cs := ergo._for_root_clauses(check, subj) with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as params
}

test_for_root_clauses_give_each_sentence_its_own_group if {
	_root_clauses_of("every xs as x", ["x.v is at least $params.b", "x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}) == [
		ergo._m_root_in("$params.b", "absent", "$params.b is missing", 2),
		ergo._m_root_in("$params.a", "unusable", `$params.a is "s", which isn't a number`, 3),
	]
}

test_for_root_clauses_put_the_lines_whose_roots_first if {
	_root_clauses_of("every xs whose v is at least $params.min as x", ["x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}) == [
		ergo._m_root_in("$params.min", "absent", "$params.min is missing", 1),
		ergo._m_root_in("$params.a", "unusable", `$params.a is "s", which isn't a number`, 2),
	]
}

test_for_root_clauses_keep_a_value_that_holds_a_semicolon_whole if {
	_root_clauses_of("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a; b"}]}, {"min": "s; t"}) == [ergo._m_root_in("$params.min", "unusable", `$params.min is "s; t", which isn't a number`, 2)]
}

_roots_said_today(line, sentences, subj, params) := {x[1] | some x in said} if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	said := ergo._walk_root_said(check, subj) with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as params
}

test_for_root_clauses_name_the_roots_the_row_names_today if {
	rows := [
		["every xs as x", ["x.v is at least $params.b", "x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}],
		["every xs whose v is at least $params.min as x", ["x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}],
		["every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a; b"}]}, {"min": "s; t"}],
		["every xs as x", ["x.v is in $params.l", "count of x.ys whose n is at least $params.m is 0"], {"xs": [{"v": 1, "ys": [{"n": 1}]}]}, {"l": 3}],
		["every xs as x, every x.ys as y", ["y.n is at least $params.m", "x.v is $params.a"], {"xs": [{"v": 1, "ys": [{"n": 1}]}]}, {"a": null}],
		["every xs whose v is at least $params.min as x", ["every x.ys whose n is $params.k has m that is 1", "x.w is at least $params.min"], {"xs": [{"v": 1, "w": 1, "ys": [{"n": 1, "m": 1}]}]}, {"min": [1]}],
	]
	every row in rows {
		texts := {c.text | some c in _root_clauses_of(row[0], row[1], row[2], row[3])}
		count(texts) > 0
		texts == _roots_said_today(row[0], row[1], row[2], row[3])
	}
}

test_for_root_clauses_say_a_root_two_sentences_read_once_in_the_first_of_their_groups if {
	_root_clauses_of("every xs as x", ["x.v is at least $params.b", "x.w is at least $params.a", "x.u is at least $params.b"], {"xs": [{"v": 1, "w": 1, "u": 1}]}, {"a": null}) == [
		ergo._m_root_in("$params.b", "absent", "$params.b is missing", 2),
		ergo._m_root_in("$params.a", "null", "$params.a is null", 3),
	]
}
