package ergo_test

import data.ergo
import rego.v1

test_message_a_list_holds_a_position_and_an_object_holds_a_key if {
	ergo._m_holds([1], 0)
	ergo._m_holds({"a": 1}, "a")
	not ergo._m_holds({"a": 1}, 0)
	not ergo._m_holds([1], "a")
}

test_message_for_item_that_has_nothing_to_walk_is_narrowed_when_its_list_is_empty if {
	ergo._m_narrows({"xs": []}, {"path": ["xs"]})
	not ergo._m_narrows({"xs": [1]}, {"path": ["xs"]})
}

test_message_for_item_that_isnt_an_object_says_so if {
	ergo._m_named_item({"cause": "not_an_object", "item": "item 1 of xs", "value": 5}) == "item 1 of xs is 5, which isn't an object"
}

test_message_tie_without_a_sort_key_names_no_key if {
	ergo._m_tie_on({"items": [{}]}, 0) == ""
}

test_message_ties_in_different_lists_are_joined_with_and if {
	ergo._m_listed(["item 1 of xs", "item 2 of ys"]) == "item 1 of xs and item 2 of ys"
	ergo._m_listed(["item 1 of xs", "item 2 of xs"]) == "item 1 and item 2 of xs"
}

test_message_of_a_subject_that_does_not_match_without_a_filter_message if {
	ergo._m_applies({}, {"subject": "thing"}, false) == {"message": "thing doesn't match"}
}

test_message_a_name_that_is_not_a_for_alias_keeps_its_dollar_sign if {
	ergo._m_marked_alias("$q") == "$q" with input as {"ergo/names": {"$at": {"names": {}}}}
	ergo._m_marked_alias("$q") == "\u0002q" with input as {"ergo/names": {"$at": {"names": {"q": "/x"}}, "q": 1}}
}

test_message_stripping_a_failed_item_without_assertions_drops_its_messages if {
	ergo._m_strip({"a": 1, "msg": "x", "said": "y"}) == {"a": 1}
}

test_message_of_an_empty_for_list_that_is_missing_names_the_list if {
	check := {"op": "for", "items": [{"path": ["xs"]}]}
	ergo._m_for_empty(check, {}, "absent") == ["xs is missing"]
}

test_message_pairs_sort_by_the_number_of_their_item_and_a_lead_without_a_number_sorts_first if {
	ergo._m_lead_n("item 12 of x") == 12
	ergo._m_lead_n("item x of y") == 0
}

test_a_for_list_that_failed_names_what_it_found_whatever_narrowed_it if {
	ergo._m_for_empty({"items": [{"path": ["xs"]}]}, {"xs": []}, "value") == ["xs is []"]
	ergo._m_for_empty({"items": [{"path": ["xs"], "whose": [{"op": "present", "path": ["v"]}]}]}, {"xs": []}, "value") == ["xs is []"]
	ergo._m_for_empty({"items": [{"path": ["xs"]}]}, {"xs": [1]}, "value") == ["xs is [1]"]
	ergo._m_for_empty({"items": [{"path": ["xs"]}], "assert": "m.v is 1"}, {"xs": "s"}, "value") == ["the check is false"]
}

test_a_ref_that_is_not_a_list_names_the_kind_of_list_the_phrase_needs if {
	ergo._m_leaf_needs({"op": "includes", "values": {"ref": ["$$params", "q"]}}, "s") == "a list"
	ergo._m_leaf_needs({"op": "includes", "values": {"ref": ["$$params", "q"]}}, []) == "a list with at least one value"
	ergo._m_leaf_needs({"op": "matches", "patterns": {"ref": ["$$params", "q"]}}, "s") == "a list"
}

test_message_groups_items_by_their_list_in_the_order_the_lists_come_and_then_by_item_number if {
	leads := ["item 10 of xs", "item 1 of ys", "item 2 of xs", "item 10 of xs", ""]
	ergo._m_list_leads(leads) == ["item 2 of xs", "item 10 of xs", "item 1 of ys", ""]
}

test_message_an_and_more_goes_with_the_root_problems_it_counts_though_the_root_counts_them_differently if {
	roots := ["item 2 of pos: name is missing", "item 3 of pos: name is missing", "item 4 of pos: name is missing", "item 5 of pos: name is missing", "item 6 of pos: name is missing"]
	p := "r.v is missing, and item 2 of pos: name is missing; item 3 of pos: name is missing; item 4 of pos: name is missing; and 2 more"
	ergo._m_unskipped(p, roots) == "r.v is missing"
	ergo._m_unskipped("v is missing; and 2 more", roots) == "v is missing; and 2 more"
}

test_the_lead_of_a_clause_goes_through_items_and_members_alike if {
	ergo._m_item_lead("item 1 of rs: member b of statuses is 1, which isn't text") == "item 1 of rs: member b of statuses"
	ergo._m_item_lead("member y of evidence: item 2 of ks is 1") == "member y of evidence: item 2 of ks"
}

test_the_lead_of_a_clause_reads_a_member_key_whole_whatever_it_holds if {
	ergo._m_item_lead(`member "a: b" of statuses is 1, which isn't text`) == `member "a: b" of statuses`
	ergo._m_item_lead(`member "a; b: c" of statuses is 1`) == `member "a; b: c" of statuses`
	ergo._m_item_lead(`member "a\" of b" of statuses is 1`) == `member "a\" of b" of statuses`
	ergo._m_item_lead(`member "x of y" of statuses is 1`) == `member "x of y" of statuses`
	ergo._m_item_lead(`item 1 of records: member "a: b" of r.evidence: e.status is 1`) == `item 1 of records: member "a: b" of r.evidence`
}

test_an_item_a_member_walk_wanted_as_an_object_says_it_isnt_one if {
	ergo._m_named_item({"item": "evidence", "cause": "unusable", "value": [1], "wants": "an object"}) == "evidence is [1], which isn't an object"
	ergo._m_named_item({"item": "evidence", "cause": "unusable", "value": [1]}) == "evidence is [1], which isn't a list or an object"
}

test_a_for_line_cuts_a_text_said_once_out_of_a_member_clause_as_out_of_an_item_clause if {
	said := ["$params.k is missing"]
	ergo._m_for_unled(said, "member a of xs: $params.k is missing") == ["$params.k is missing"]
	ergo._m_for_unled(said, "member a of xs: v is 1, and $params.k is missing") == ["$params.k is missing", "member a of xs: v is 1"]
	ergo._m_for_unled(said, "member a of xs: $params.k is missing, and v is 1") == ["$params.k is missing", "member a of xs: v is 1"]
	ergo._m_for_unled(said, "member a of xs: v is 1, and $params.k is missing, and w is 2") == ["$params.k is missing", "member a of xs: v is 1, and w is 2"]
}

test_a_for_line_counts_and_cuts_members_toward_and_n_more_like_items if {
	ents := [{"t": "member a of xs: v is 1", "x": false}, {"t": "member b of xs: v is 1", "x": false}, {"t": "$params.k is missing", "x": false}]
	ergo._m_for_counted(ents) == ["member a of xs", "member b of xs"]
	ergo._m_cut_item("member d of xs: v is 1", ["member a of xs"])
	not ergo._m_cut_item("member a of xs: v is 1", ["member a of xs"])
}

test_a_for_line_reads_the_lead_and_the_list_of_a_member_clause if {
	ergo._m_lead_of(`member x of r.evidence: e.status is "NO"`) == "member x of r.evidence"
	ergo._m_lead_of(`member "a: b" of r.evidence: e.status is "NO"`) == `member "a: b" of r.evidence`
	ergo._m_lead_list("member x of r.evidence") == "r.evidence"
	ergo._m_lead_list(`member "x of y" of r.evidence`) == "r.evidence"
	ergo._m_releaded("item 1 of rs", "member b of r.e: v is 1") == "item 1 of rs: member b of r.e: v is 1"
}

_unclean_key_whose := {"cmp": "eq", "left": ["kind"], "op": "compare", "right": ["m", {"ref": ["$$params", "k"]}]}

test_message_for_item_reads_each_member_when_it_asks_whether_an_item_cant_take_the_key if {
	ergo._for_list_unclean({"path": ["ev"], "member": true}, {"ev": {"a": {"kind": "a", "m": {}}, "b": {"m": {}}}}, _unclean_key_whose) with data.ergo_params as {"k": 3}
	ergo._for_list_unclean({"path": ["ev"]}, {"ev": [{"kind": "a", "m": {}}, {"m": {}}]}, _unclean_key_whose) with data.ergo_params as {"k": 3}
	not ergo._for_list_unclean({"path": ["ev"], "member": true}, {"ev": {"a": {"kind": "a", "m": {}}, "b": {"kind": "b", "m": {}}}}, _unclean_key_whose) with data.ergo_params as {"k": 3}
	not ergo._for_list_unclean({"path": ["ev"], "member": true}, {"ev": [{"m": {}}]}, _unclean_key_whose) with data.ergo_params as {"k": 3}
	not ergo._for_list_unclean({"path": ["ev"]}, {"ev": {"b": {"m": {}}}}, _unclean_key_whose) with data.ergo_params as {"k": 3}
}

_sentence_clauses(line, sentences, subj, k, i, params) := cs if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	item := check.items[0]
	names := ergo._bound({"ergo/subject": subj, "$at": {"names": {}}}, item.as, subj[item.path[0]][k], "~~/list/k")
	c := check.checks[i]
	cause := ergo._for_cause(c, subj) with input as {"ergo/names": names} with data.ergo_params as params
	cs := ergo._for_sentence_clauses(check, c, subj, cause) with input as {"ergo/names": names} with data.ergo_params as params
}

_sentence_texts(line, sentences, subj, k, i, params) := [ergo._m_aliased(t) | some t in ergo._m_clause_texts(_sentence_clauses(line, sentences, subj, k, i, params))]

test_a_sentence_says_its_own_read_without_the_root if {
	subj := {"xs": [{"v": "a"}, {}]}
	text := "\u0002x.v is \"a\", which isn't a number"
	_sentence_clauses("every xs as x", ["x.v is at least $params.min"], subj, 0, 0, {"min": "s"}) == [ergo._m_clause("root", text, "unusable", text)]
	_sentence_clauses("every xs as x", ["x.v is at least $params.min"], subj, 1, 0, {"min": "s"}) == [ergo._m_clause("root", "\u0002x.v is missing", "absent", "\u0002x.v is missing")]
}

test_a_sentence_keeps_a_value_that_holds_a_semicolon_whole if {
	_sentence_texts("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a; b"}]}, 0, 0, {"min": "s; t"}) == [`x.v is "a; b", which isn't a number`]
}

test_a_sentence_says_a_null_read_of_its_item if {
	_sentence_texts("every xs as x", ["x.v is 1"], {"xs": [{"v": null}]}, 0, 0, {}) == ["x.v is null"]
}

test_a_sentence_whose_only_problems_are_roots_says_nothing_for_the_item if {
	sentences := ["x.v is at least $params.a", "x.v is at most $params.b", "x.w is $params.c", "x.u is in $params.d"]
	every i, _ in sentences {
		_sentence_clauses("every xs as x", sentences, {"xs": [{"v": 1, "w": 1, "u": 1}]}, 0, i, {}) == []
	}
}

test_a_sentence_that_passes_says_nothing if {
	_sentence_clauses("every xs as x", ["x.v is 1"], {"xs": [{"v": 1}]}, 0, 0, {}) == []
}

test_a_sentence_that_reads_the_alias_says_each_piece_as_its_own_clause if {
	_sentence_texts("every xs as x", ["x.v is x.w"], {"xs": [{"v": 3, "w": 4}]}, 0, 0, {}) == ["x.v is 3", "x.w is 4"]
}

test_a_sentence_that_reads_no_alias_says_its_pieces_as_one_clause if {
	_sentence_texts("every xs as x", ["z is w"], {"z": 3, "w": 4, "xs": [{}]}, 0, 0, {}) == ["z is 3, and w is 4"]
}

test_a_walk_sentence_gives_its_items_as_clauses if {
	cs := _sentence_clauses("every xs as x", ["every x.ys.n is 1"], {"xs": [{"ys": [{"n": 2}, {}]}]}, 0, 0, {})
	[c.kind | some c in cs] == ["item", "item"]
	[ergo._m_aliased(c.text) | some c in cs] == ["item 1 of x.ys: n is 2", "item 2 of x.ys: n is missing"]
}

test_a_walk_sentence_leaves_out_its_root if {
	_sentence_texts("every xs as x", ["every x.ys.n is at least $params.m"], {"xs": [{"ys": [{"n": 1}, {}]}]}, 0, 0, {"m": "s"}) == ["item 2 of x.ys: n is missing"]
}

test_a_count_under_the_line_gives_its_items_as_clauses if {
	cs := _sentence_clauses("every gs as g", ["count of g.es whose v is at least $params.min is 0"], {"gs": [{"es": [{}, {}]}]}, 0, 0, {"min": "s"})
	[c.kind | some c in cs] == ["item", "item"]
	[ergo._m_aliased(t) | some t in ergo._m_clause_texts(cs)] == ["item 1 of g.es: v is missing", "item 2 of g.es: v is missing"]
}

test_a_sum_under_the_line_gives_its_items_as_clauses if {
	subj := {"gs": [{"rs": [{"n": "a"}, {}]}, {"rs": [{"n": null}]}]}
	_sentence_texts("every gs as g", ["sum of g.rs.n is 3"], subj, 0, 0, {}) == [`item 1 of g.rs: n is "a", which isn't a number`, "item 2 of g.rs: n is missing"]
	_sentence_texts("every gs as g", ["sum of g.rs.n is 3"], subj, 1, 0, {}) == ["item 1 of g.rs: n is null"]
}

test_a_key_from_params_is_left_out_of_the_items_of_a_count_under_the_line if {
	_sentence_texts("every gs as g", ["count of g.es.v that is m named by $params.k is 0"], {"gs": [{"es": [{"v": {}}]}]}, 0, 0, {}) == ["item 1 of g.es: v: m is missing"]
}

test_a_sentence_says_the_value_before_a_key_it_cant_read_after_leaving_out_the_key if {
	subj := {"xs": [{"m": 3}, {"m": {}}]}
	_sentence_texts("every xs as x", ["x.m named by $params.k is 1"], subj, 0, 0, {}) == ["x.m is 3, which isn't an object"]
	_sentence_texts("every xs as x", ["x.m named by $params.k is 1"], subj, 1, 0, {}) == []
}

test_a_from_filter_walk_with_a_root_beside_items_that_fail_on_their_own_keeps_the_items_for_their_entries if {
	root := ergo._m_clause("root", "$params.min", "unusable", "$params.min is \"s\", which isn't a number")
	item := ergo._m_clause("item", ["xs", 0], "absent", "item 1 of xs: v is missing")
	w := {"root_msgs": [root, item], "ergo/alone_items": [item]}
	said := ergo._m_filter_walk({}, {}, false, "unusable", w)
	said["ergo/texts"] == [item]
	said["ergo/own"] == ["$params.min is \"s\", which isn't a number"]
}

_whose_item_texts(line, subj, params) := [[ergo._m_aliased(t) | some t in ergo._m_clause_texts([c])] |
	check := ergo._s_written_check({"for": line, "assert": ["z exists"]})
	item := check.items[0]
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	w := ergo._for_walk(item, subj, names) with input as {"ergo/names": names} with data.ergo_params as params
	some e in w.items
	wh := ergo._for_whose(item, e, names) with data.ergo_params as params
	c := ergo._for_whose_item_clause(item, e, names, wh) with data.ergo_params as params
]

test_a_whose_item_says_only_its_own_read_beside_a_root if {
	_whose_item_texts("every xs whose v is at least $params.min as x", {"xs": [{"v": 1}, {}]}, {"min": "s"}) == [["item 2 of xs: v is missing"]]
}

test_a_whose_item_says_the_first_condition_that_says_something if {
	_whose_item_texts("every xs whose v is at least $params.min and whose w is 1 as x", {"xs": [{"v": 1}]}, {"min": "s"}) == [["item 1 of xs: w is missing"]]
	_whose_item_texts("every xs whose v is at least $params.min and whose w is at least $params.min as x", {"xs": [{"v": 1}]}, {"min": "s"}) == [["item 1 of xs: w is missing"]]
}

test_a_whose_item_beside_a_root_says_a_value_of_the_wrong_kind_and_a_null if {
	_whose_item_texts("every xs whose v is at least $params.min as x", {"xs": [{"v": "a"}, {"v": null}]}, {"min": "s"}) == [[`item 1 of xs: v is "a", which isn't a number`], ["item 2 of xs: v is null"]]
}

test_a_whose_item_says_each_own_read_beside_a_key_that_isnt_text if {
	subj := {"es": [{"v": 1}, {"v": 2, "zz": 1, "m": {"a": 1}}, {"v": 3, "m": null}]}
	_whose_item_texts("every es whose zz is m named by $params.k as e", subj, {"k": 3}) == [
		["item 1 of es: zz is missing, and m is missing"],
		["item 3 of es: zz is missing, and m is null"],
	]
}

test_a_whose_item_says_the_base_of_a_key_first_when_the_key_is_read_first if {
	_whose_item_texts("every es whose m named by $params.k is zz as e", {"es": [{}]}, {"k": 3}) == [["item 1 of es: m is missing, and zz is missing"]]
}

test_a_whose_item_says_what_its_check_says_when_it_reads_no_root if {
	_whose_item_texts("every xs whose v is w as x", {"xs": [{"w": 1}]}, {}) == [["item 1 of xs: v is missing"]]
}

test_a_whose_item_that_isnt_an_object_says_so_beside_a_root if {
	_whose_item_texts("every xs whose v is at least $params.min as x", {"xs": [3]}, {"min": "s"}) == [["item 1 of xs is 3, which isn't an object"]]
}

test_an_item_the_whose_decides_has_no_whose_item_clause if {
	_whose_item_texts("every xs whose v is 1 as x", {"xs": [{"v": 1}, {"v": 2}]}, {}) == []
}
