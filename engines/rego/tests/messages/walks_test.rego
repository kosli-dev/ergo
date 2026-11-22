package ergo_test

import data.ergo
import rego.v1

test_message_of_a_passed_walk_has_no_parts if {
	ergo._m_fail_parts("satisfied", [], set()) == []
}

test_a_clause_an_earlier_sentence_gave_is_left_out_but_a_quoted_value_is_one_clause if {
	ergo._m_said_new(["x is missing", "x is missing, and y is missing", "y is missing"]) == ["x is missing", "y is missing"]
	ergo._m_said_new(["x is \"a, and b\"", "x is \"a, and b\", and z is 1"]) == ["x is \"a, and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\", and b\"", "x is \"a\\\", and b\"; z is 1"]) == ["x is \"a\\\", and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\\\", and b is 1", "b is 1"]) == ["x is \"a\\\\\", and b is 1"]
	ergo._m_said_new(["item 1 of xs: a; item 2 of xs: b", "item 2 of xs: b; c"]) == ["item 1 of xs: a; item 2 of xs: b", "c"]
	ergo._m_quote_split("x is \"a, and b", ", and ") == ["x is \"a, and b"]
}

test_message_a_for_alias_loses_its_marker_and_a_value_that_spells_the_alias_stays if {
	ergo._m_aliased("x is \u0002c, and \"$c: y\"") == "x is c, and \"$c: y\""
	ergo._m_aliased("x is 1") == "x is 1"
}

test_message_a_key_named_by_another_name_is_another_name if {
	ergo._m_other_name({"named_by": "z"}, "c")
	ergo._m_other_name({"named_by_field": "z"}, "c")
	not ergo._m_other_name({"named_by": "c"}, "c")
}

test_message_of_a_walk_whose_path_is_not_a_path_names_no_blocked_parent if {
	ergo._m_walk_blocked({}, {"path": "x"}) == []
}

test_message_of_a_walk_that_failed_without_a_list_to_show_repeats_its_expression if {
	check := {"path": ["xs"], "expression": "every xs.ok is true"}
	ergo._walk_parts(check, {}, {"cause": "value"}, {"failed": []}) == ["every xs.ok is true is false"]
}

test_message_names_an_item_by_the_part_of_the_subject_it_goes_through if {
	marker := ergo._p_marker("cov", 0, null, false)
	ergo._m_item_name(["xs", marker, "z"], set()) == "cov.z"
	ergo._m_off_item_path(["xs", marker])
	not ergo._m_off_item_path(["xs", "z"])
}

_count_of_es(whose) := {"count_of": ["es"], "text": "count of es", "whose": whose}

test_an_item_names_every_condition_of_its_whose_it_cant_decide_and_not_only_the_first if {
	plain := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally_items({"es": [{}]}, plain)] == ["item 1 of es: v is missing", "item 1 of es: w is missing"]
	keyed := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["zz"], "right": ["m", {"ref": ["$$params", "k"]}]},
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": ["m", {"ref": ["$$params", "j"]}]},
	])
	said := [x[1] | some x in ergo._m_tally_items({"es": [{"zz": 2, "v": 2}]}, keyed)] with data.ergo_params as {"k": "a", "j": 3}
	"item 1 of es: $params.j is 3, which isn't text" in said
}

test_a_count_shows_every_item_it_cant_read_whatever_its_cause_but_not_a_root_or_a_params_item_of_another_cause if {
	item := {"item": {"i": ["xs", 0]}}
	ergo._m_record_shown(["absent", "item 1 of xs: v is missing", item], "unusable")
	ergo._m_record_shown(["not_an_object", "item 1 of xs is 3, which isn't an object", item], "absent")
	ergo._m_record_shown(["unusable", "item 1 of xs: v is \"a\", which isn't a number", item], "unusable")
	not ergo._m_record_shown(["value", "item 1 of xs: v is 2", item], "absent")
	not ergo._m_record_shown(["absent", "x is missing"], "unusable")
	not ergo._m_record_shown(["absent", "item 1 of $params.l: v is missing", {"item": {"i": ["$$params", "l", 0]}}], "unusable")
}

_keyed_count_side(sentence) := ergo._m_tally_parts(ergo._s_written_check(sentence))[0]

test_a_count_on_an_empty_list_says_only_the_root_a_key_from_the_item_is_read_in_whatever_the_phrase if {
	every s in [
		"count of xs whose v is $input.m named by key is 0",
		"count of xs whose v is not $input.m named by key is 0",
		"count of xs that is $input.m named by key is 0",
		"count of xs whose v is $input.m named by key and whose w equals 1 is 0",
		"count of xs whose tags contains $input.m named by key is 0",
		"count of xs whose v matches $input.m named by key is 0",
		"count of xs whose $input.m named by key is v is 0",
	] {
		said := [x[1] | some x in ergo._m_tally({"xs": []}, _keyed_count_side(s))] with data.ergo_document as {"m": null}
		said == ["$input.m is null"]
	}
}

test_a_count_on_an_empty_list_says_a_root_further_back_than_the_key_that_isnt_an_object if {
	side := _keyed_count_side("count of xs whose v is $input.m.a named by key is 0")
	said := [x[1] | some x in ergo._m_tally({"xs": []}, side)] with data.ergo_document as {"m": 3}
	said == ["$input.m is 3, which isn't an object"]
}

test_a_count_on_an_empty_list_doesnt_add_its_root_again_after_the_root_it_already_says if {
	check := ergo._s_written_check("count of xs whose tags contains $input.m named by key is 1")
	o := {"passed": false, "cause": "null", "message": "$input.m is null"}
	ergo._keyed_rooted(o, check, {"xs": []}) == o with data.ergo_document as {"m": null}
}

test_an_item_names_the_conditions_it_cant_decide_in_the_order_the_sentence_reads_them if {
	side := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally({"es": [{}]}, side)] == ["item 1 of es: w is missing", "item 1 of es: v is missing"]
}

test_an_item_two_conditions_cant_read_for_the_same_reason_is_named_once if {
	side := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally_items({"es": [null]}, side)] == ["item 1 of es is null, which isn't an object"]
}

_tally_records(sentence, subj, cause) := ergo._m_tally_said(subj, ergo._m_tally_parts(ergo._s_written_check(sentence))[0], cause)

test_a_count_gives_its_roots_then_its_items_as_clauses if {
	_tally_records("count of ms whose v is at least $params.r is 0", {"ms": [{"v": "s"}, {}, "x"]}, "not_an_object") == [
		ergo._m_clause("root", "$params.r", "absent", "$params.r is missing"),
		ergo._m_item_clause("item 1 of ms", "unusable", [ergo._m_clause("root", "v", "unusable", `v is "s", which isn't a number`)]),
		ergo._m_item_clause("item 2 of ms", "absent", [ergo._m_clause("root", "v", "absent", "v is missing")]),
		ergo._m_clause("item", "item 3 of ms", "not_an_object", `item 3 of ms is "x", which isn't an object`),
	] with data.ergo_params as {}
	ergo._m_clauses_text(ergo._m_clauses_shown(_tally_records("count of ms whose v is at least $params.r is 0", {"ms": [{}, {}, {}, {}]}, "absent"))) == "$params.r is missing; item 1 of ms: v is missing; item 2 of ms: v is missing; item 3 of ms: v is missing; and 1 more" with data.ergo_params as {}
}

test_a_count_says_a_root_before_a_key_from_the_item_once_and_each_item_only_its_own_paths if {
	_tally_records("count of xs whose v is $params.m named by key is 1", {"xs": [{"key": "a", "v": 1}, {}]}, "absent") == [
		ergo._m_clause("root", "$params.m", "null", "$params.m is null"),
		ergo._m_item_clause("item 2 of xs", "absent", [ergo._m_clause("root", "v", "absent", "v is missing, and key is missing")]),
	] with data.ergo_params as {"m": null}
}

test_a_count_on_an_empty_list_says_the_root_a_key_from_the_item_is_read_in if {
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "absent") == [ergo._m_clause("root", "$params.m", "absent", "$params.m is missing")] with data.ergo_params as {}
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "null") == [ergo._m_clause("root", "$params.m", "null", "$params.m is null")] with data.ergo_params as {"m": null}
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "unusable") == [ergo._m_clause("root", "$params.m", "unusable", "$params.m is 3, which isn't an object")] with data.ergo_params as {"m": 3}
}

test_a_count_says_the_root_a_key_from_the_item_is_read_in_before_a_list_it_cant_read if {
	missing := _tally_records("count of xs whose v is $params.m named by key is 0", {}, "unusable") with data.ergo_params as {"m": 3}
	[[c.name, c.cause, c.text] | some c in missing] == [["$params.m", "unusable", "$params.m is 3, which isn't an object"], ["xs", "absent", "xs is missing"]]
	null_list := _tally_records("count of xs whose v is $params.m named by key is 0", {"xs": null}, "absent") with data.ergo_params as {}
	[[c.name, c.cause, c.text] | some c in null_list] == [["$params.m", "absent", "$params.m is missing"], ["xs", "null", "xs is null"]]
}

test_an_items_cause_comes_from_its_record_not_its_last_words if {
	side := ergo._m_tally_parts(ergo._s_written_check("count of xs whose v is 1 is 0"))[0]
	e := {"i": ["xs", 0], "c": ["xs", 0], "iv": {}, "r": [], "v": {}}
	ergo._m_record_clause(["focus unusable", "item 1 of xs: v is missing", {"item": e}], side) == ergo._m_item_clause("item 1 of xs", "unusable", [ergo._m_clause("root", "v", "unusable", "v is missing")])
	ergo._m_record_clause(["absent", `item 1 of xs: v is "a", which isn't text`, {"item": e}], side) == ergo._m_item_clause("item 1 of xs", "absent", [ergo._m_clause("root", "v", "absent", `v is "a", which isn't text`)])
	ergo._m_record_clause(["root unusable", `$params.k is 3, which isn't text`], side) == ergo._m_clause("root", "$params.k", "unusable", `$params.k is 3, which isn't text`)
	ergo._m_record_clause(["absent", "xs is missing"], side) == ergo._m_clause("list", "xs", "absent", "xs is missing")
}

test_a_member_is_named_like_an_item_with_its_key_in_place_of_its_position if {
	ergo._m_item_name(["statuses", {"member": "sign-off"}], set()) == "member sign-off of statuses"
	ergo._m_item_name(["rs", 0, "statuses", {"member": "b"}], set()) == "item 1 of rs: member b of statuses"
	ergo._m_item_name(["evidence", {"member": "y"}, "kind"], set()) == "member y of evidence: kind"
	ergo._m_item_name(["evidence", {"member": "a.b"}], set()) == `member "a.b" of evidence`
}

test_a_member_walk_that_finds_no_object_says_what_is_there if {
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "absent", "value": null, "msg": "an object"}, set()) == "statuses is missing"
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "null", "value": null, "msg": "an object"}, set()) == "statuses is null"
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "unusable", "value": ["DONE"], "msg": "an object"}, set()) == `statuses is ["DONE"], which isn't an object`
}

test_members_count_toward_and_n_more_like_items if {
	ms := ["member a of xs is 1", "member b of xs is 1", "member c of xs is 1", `member "d e" of xs is 1`]
	ergo._m_joined_once(ms) == "member a of xs is 1; member b of xs is 1; member c of xs is 1; and 1 more"
	ergo._m_item_leads(ms) == ["member a of xs", "member b of xs", "member c of xs", `member "d e" of xs`]
	not ergo._m_shown_clause(`member "d e" of xs is 1`, ["member a of xs"])
}

test_members_whose_keys_hold_a_colon_count_toward_and_n_more_one_each if {
	ms := [`member "a: b" of statuses is 1, which isn't text`, `member "a; b: c" of statuses is 1, which isn't text`, "member p of statuses is 1, which isn't text", "member q of statuses is 1, which isn't text"]
	ergo._m_joined_once(ms) == `member "a: b" of statuses is 1, which isn't text; member "a; b: c" of statuses is 1, which isn't text; member p of statuses is 1, which isn't text; and 1 more`
}

test_a_member_is_placed_among_the_items_of_a_tally_by_its_key if {
	ergo._m_positions(["costs", {"member": "c"}]) == ["c"]
	ergo._m_positions(["rs", 0, "statuses", {"member": "b"}]) == [0, "b"]
	ergo._m_positions(["xs", 2, "v"]) == [2]
}

test_an_item_whose_count_of_member_of_ends_at_no_object_says_it_isnt_one if {
	c := {"op": "compare", "cmp": "eq", "left": {"count_of": ["s"], "whose": [], "text": "count of member of s", "member": true}, "right": {"literal": 1}}
	ergo._m_item_tallies({"s": [1]}, c, "unusable") == ["s is [1], which isn't an object"]
	ergo._m_item_tallies({"s": {"x": 1}}, c, "unusable") == []
	l := {"op": "compare", "cmp": "eq", "left": {"count_of": ["s"], "whose": [], "text": "count of s"}, "right": {"literal": 1}}
	ergo._m_item_tallies({"s": {"x": 1}}, l, "unusable") == [`s is {"x": 1}, which isn't a list`]
	ergo._m_item_tallies({"s": [1]}, l, "unusable") == []
}

test_a_named_failure_a_member_walk_wanted_as_an_object_says_it_isnt_one if {
	ergo._m_named_fail({"path": "r.s", "cause": "unusable", "value": [1], "wants": "an object"}) == "r.s is [1], which isn't an object"
	ergo._m_named_fail({"path": "r.s", "cause": "unusable", "value": [1]}) == "r.s is [1], which isn't a list or an object"
}
