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
		ergo._m_root_in("$params.b", "absent", "$params.b is missing", 3),
		ergo._m_root_in("$params.a", "unusable", `$params.a is "s", which isn't a number`, 4),
	]
}

test_for_root_clauses_put_the_lines_whose_roots_first if {
	_root_clauses_of("every xs whose v is at least $params.min as x", ["x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}) == [
		ergo._m_root_in("$params.min", "absent", "$params.min is missing", 1),
		ergo._m_root_in("$params.a", "unusable", `$params.a is "s", which isn't a number`, 2),
	]
}

test_for_root_clauses_put_the_sentences_that_read_no_alias_before_the_lines_whose if {
	_root_clauses_of("every xs whose v is at least $params.min as x", ["x.w is at least $params.a", "$params.b is 1"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}) == [
		ergo._m_root_in("$params.min", "absent", "$params.min is missing", 2),
		ergo._m_root_in("$params.a", "unusable", `$params.a is "s", which isn't a number`, 3),
		ergo._m_root_in("$params.b", "absent", "$params.b is missing", 1),
	]
}

test_for_root_clauses_say_a_root_the_whose_and_a_sentence_without_an_alias_read_in_the_sentences_group if {
	_root_clauses_of("every xs whose v is at least $params.min as x", ["$params.min is at least 1", "x.w is 1"], {"xs": [{"v": 1, "w": 1}]}, {}) == [ergo._m_root_in("$params.min", "absent", "$params.min is missing", 0)]
}

test_for_root_clauses_keep_a_value_that_holds_a_semicolon_whole if {
	_root_clauses_of("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a; b"}]}, {"min": "s; t"}) == [ergo._m_root_in("$params.min", "unusable", `$params.min is "s; t", which isn't a number`, 2)]
}

_roots_said_today(line, sentences, subj, params) := {x[1] | some x in said} if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	said := ergo._walk_root_said(check, subj) with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as params
}

_said_parts_match(line, sentences, subj, params) if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/names": {"ergo/subject": subj, "$at": {"names": {}}}}
	parts := ergo._for_said_parts(check, subj) with input as names with data.ergo_params as params
	parts.all == ergo._walk_root_said(check, subj) with input as names with data.ergo_params as params
	parts.said == [ergo._walk_root_said(ergo._for_one_sentence(check, c), subj) | some c in check.checks] with input as names with data.ergo_params as params
	parts.all != []
}

test_a_for_line_reads_its_roots_once_for_the_line_and_for_each_sentence if {
	_said_parts_match("every xs as x", ["x.v is $params.a", "x.v is $params.b"], {"xs": [{"v": 1}]}, {"a": null})
	_said_parts_match("every xs whose v is at least $params.min as x", ["x.w is 1", "z is 1", "approved_by is a non-empty string"], {"xs": [{"v": 1, "w": 2}]}, {"min": "s"})
	_said_parts_match("every xs as x", ["count of x.ys whose k is $params.k is 1", "every x.ys whose n is $params.n exists"], {"xs": [{"ys": [{"k": 1}]}]}, {})
}

test_a_for_row_hands_the_roots_it_read_to_its_message if {
	check := ergo._s_written_check({"for": "every tests as t", "assert": ["t.ok is true", "approved_by is a non-empty string"]})
	subj := {"tests": [{"ok": false}]}
	names := {"ergo/names": {"ergo/subject": subj, "$at": {"names": {}}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as names
	r["ergo/root_said"] == [[], [["absent", "approved_by is missing"]]]
	ergo._for_row_said(check, subj, object.union(r, {"ergo/root_said": [[["absent", "a is missing"]], []]})) == {0: [["absent", "a is missing"]], 1: []} with input as names
	approved := {"tests": [{"ok": false}], "approved_by": "a"}
	approved_names := {"ergo/names": {"ergo/subject": approved, "$at": {"names": {}}}}
	plain := ergo._for_freed(check, approved, ergo._for_row_raw(check, approved)) with input as approved_names
	ergo._for_row_said(check, approved, object.union(plain, {"ergo/root_said": [[["absent", "a is missing"]], []]})) == {0: [["absent", "a is missing"]]} with input as approved_names
}

_on_tree(line, sentences, subj, params) if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as {"ergo/names": names} with data.ergo_params as params
	ergo._for_on_tree(check, subj, r) with input as {"ergo/names": names} with data.ergo_params as params
}

test_a_one_list_for_row_with_nothing_read_outside_it_that_fails_takes_its_message_from_the_tree if {
	_on_tree("every xs as x", ["x.v is 1", "z is 1"], {"xs": [{"v": 2}], "z": 2}, {})
	_on_tree("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": 0}]}, {"min": 1})
	_on_tree("first of xs sorted by t as x", ["x.v is 1"], {"xs": [{"t": 1, "v": 2}]}, {})
	_on_tree("every xs[0].ys as y", ["y.v is 1"], {"xs": [{"ys": [{"v": 2}]}]}, {})
}

test_a_for_row_keeps_its_message_off_the_tree_while_the_tree_cant_say_its_roots_keys_or_second_list if {
	not _on_tree("every xs as x, every x.ys as y", ["y.v is 1"], {"xs": [{"ys": [{"v": 2}]}]}, {})
	not _on_tree("every o named by $params.k as x", ["x is 1"], {"o": {"a": [2]}}, {"k": "a"})
	not _on_tree("first of xs sorted by m named by $params.k as x", ["x.v is 1"], {"xs": [{"m": {"a": 1}, "v": 2}]}, {"k": "a"})
	not _on_tree("every es whose zz is m named by $params.k as e", ["e.v is 1"], {"es": [{"zz": 1}]}, {"k": 3})
	not _on_tree("every xs as x", ["every x.ys.n is 1", "every x.ys.m is 1"], {"xs": [{"ys": [{"n": 2, "m": 2}]}]}, {})
	not _on_tree("every xs as x", ["every x.ys exists", "sum of x.ys.n is 3"], {"xs": [{"ys": [{"n": 1}, null]}]}, {})
}

test_a_one_list_for_row_with_a_root_that_fails_takes_its_message_from_the_tree if {
	_on_tree("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": 0}]}, {"min": "s"})
	_on_tree("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": 0}]}, {})
	_on_tree("every xs whose v is at least $params.min as x", ["x.w is 1"], {"xs": [{"v": 1, "w": 2}, {"w": 1}]}, {"min": "s"})
	_on_tree("every xs as x", ["x.v is $params.a", "x.v is $params.b"], {"xs": [{"v": 1}]}, {"a": null})
}

test_a_for_row_run_again_to_read_its_walked_roots_keeps_its_message_off_the_tree_when_a_root_fails if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": "x.v is at least $params.min"})
	subj := {"xs": [{"v": 0}]}
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as {"ergo/names": names} with ergo._walk_roots_on as true
	not ergo._for_on_tree(check, subj, r) with input as {"ergo/names": names} with ergo._walk_roots_on as true
	_on_tree("every xs as x", ["x.v is 1"], {"xs": [{"v": 0}]}, {}) with ergo._walk_roots_on as true
}

test_a_for_row_whose_whose_key_from_params_cant_be_read_keeps_its_message_off_the_tree if {
	not _on_tree("every es whose zz is m named by $params.k as e", ["e.v exists", "z is 1"], {"z": 2, "es": [{"zz": 2, "m": {"a": 1}, "v": 1}]}, {})
	not _on_tree("every es whose zz is m named by $params.k as e", ["e.v exists", "z is 1"], {"z": 2, "es": [{"zz": 2, "m": {"a": 1}, "v": 1}]}, {"k": null})
	_on_tree("every es whose zz is m named by $params.k as e", ["e.v is 2"], {"es": [{"zz": 2, "m": {"a": 2}, "v": 1}]}, {"k": "a"})
}

test_a_for_row_on_the_tree_leaves_its_message_to_the_tree if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": "x.v is 1"})
	subj := {"xs": [{"v": 2}]}
	row := ergo._for_row(check, subj) with input as {"ergo/names": {"ergo/subject": subj, "$at": {"names": {}}}}
	row.message == ""
	row["ergo/for_raw"].tree == true
	not "once" in object.keys(row["ergo/for_raw"])
}

test_a_for_row_whose_line_reads_its_item_whole_keeps_its_message_off_the_tree if {
	not _on_tree(`every ws that starts with "b" as w`, ["w is not empty"], {"ws": ["b", 3]}, {})
	not _on_tree("every xs that is at least c as x", ["x.n is 1"], {"c": 0, "xs": [1, {"c": 0, "n": 1}]}, {})
	_on_tree("every xs whose n is at least c as x", ["x.n is 1"], {"c": 0, "xs": [1, {"c": 0, "n": 2}]}, {})
}

test_a_for_row_whose_named_by_key_is_its_alias_read_whole_keeps_its_message_off_the_tree if {
	not _on_tree("every xs as m", ["m.k named by m.k is 1"], {"xs": [{"k": null}, {}, {"k": 1}]}, {})
	not _on_tree("every xs as m", ["m is $params.l", "m.v named by m.v is 1"], {"xs": [null]}, {"l": 1})
	not _on_tree("every xs as m", ["m.k is 2", "m.v named by m.k is 1"], {"xs": [{"k": null}]}, {})
	_on_tree("every xs as m", ["m.v named by z is 1"], {"z": "a", "xs": [{"v": {"a": 2}}]}, {})
}

test_a_compiled_for_row_whose_item_leaves_whose_out_says_what_the_written_row_says_on_the_tree if {
	written := ergo._s_written_check({"for": "every xs as x", "assert": ["x.v is 1", "z is 1"]})
	compiled := object.union(written, {"items": [object.remove(written.items[0], ["whose"])]})
	subj := {"xs": [{"v": 2}, {"v": 1}], "z": 3}
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	said := [ergo._for_said(row) |
		some check in [written, compiled]
		row := ergo._for_row(check, subj) with input as {"ergo/names": names}
		row["ergo/for_raw"].tree == true
	] with input as {"ergo/names": names}
	[s.message | some s in said] == ["z is 3; item 1 of xs: x.v is 2", "z is 3; item 1 of xs: x.v is 2"]
}

test_a_for_row_whose_item_walks_one_list_takes_its_message_from_the_tree if {
	_on_tree("every xs as x", ["every x.ys.n is 1", "x.v is 1"], {"xs": [{"v": 2, "ys": [{"n": 2}]}]}, {})
	_on_tree("every xs as x", ["count of x.ys is 1", "every es.n is 1"], {"xs": [{"ys": []}], "es": [{"n": 2}]}, {})
}

test_for_root_clauses_name_the_roots_the_row_names_today if {
	rows := [
		["every xs as x", ["x.v is at least $params.b", "x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}],
		["every xs whose v is at least $params.min as x", ["x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}],
		["every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a; b"}]}, {"min": "s; t"}],
		["every xs as x", ["x.v is in $params.l", "count of x.ys whose n is at least $params.m is 0"], {"xs": [{"v": 1, "ys": [{"n": 1}]}]}, {"l": 3}],
		["every xs as x, every x.ys as y", ["y.n is at least $params.m", "x.v is $params.a"], {"xs": [{"v": 1, "ys": [{"n": 1}]}]}, {"a": null}],
		["every xs whose v is at least $params.min as x", ["every x.ys whose n is at least $params.k exists", "x.w is at least $params.min"], {"xs": [{"v": 1, "w": 1, "ys": [{"n": 1, "m": 1}]}]}, {"min": [1]}],
		["every xs whose v is at least $params.min as x", ["x.w is at least $params.a", "$params.b is 1", "$params.min is at least 1"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}],
	]
	every row in rows {
		texts := {c.text | some c in _root_clauses_of(row[0], row[1], row[2], row[3])}
		count(texts) > 0
		texts == _roots_said_today(row[0], row[1], row[2], row[3])
	}
}

test_for_root_clauses_say_a_root_two_sentences_read_once_in_the_first_of_their_groups if {
	_root_clauses_of("every xs as x", ["x.v is at least $params.b", "x.w is at least $params.a", "x.u is at least $params.b"], {"xs": [{"v": 1, "w": 1, "u": 1}]}, {"a": null}) == [
		ergo._m_root_in("$params.b", "absent", "$params.b is missing", 4),
		ergo._m_root_in("$params.a", "null", "$params.a is null", 5),
	]
}
