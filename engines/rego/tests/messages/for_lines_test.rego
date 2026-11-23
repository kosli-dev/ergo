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

test_a_sentence_that_reads_params_that_arent_an_object_gives_no_clauses if {
	_sentence_clauses("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": 1}]}, 0, 0, "s") == []
	_sentence_clauses("every xs as x", ["x.v is at least $params.min"], {"xs": [{}]}, 0, 0, "s") == []
	_sentence_clauses("every gs as g", ["count of g.es whose v is at least $params.min is 0"], {"gs": [{"es": [{}, {"v": "a"}]}]}, 0, 0, "s") == []
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

test_a_for_lines_whose_item_reads_its_own_field_as_the_phrase_needs_beside_a_root if {
	ref := {"ref": ["$$params[]", "cs", "name"]}
	listed := {"op": "excludes", "path": ["tags"], "values": ref}
	[ergo._for_own_read(listed, item, ["tags"])[0] | some item in [{"tags": "a"}, {"tags": {}}, {}, {"tags": null}]] == ["unusable", "unusable", "absent", "null"]
	every tags in [["a"], [1, "a"]] {
		not ergo._for_own_read(listed, {"tags": tags}, ["tags"])[0] in {"absent", "null", "unusable", "not_an_object"}
	}
	patterned := {"op": "matches_any", "path": ["v"], "patterns": ref}
	ergo._for_own_read(patterned, {"v": 3}, ["v"])[0] == "unusable"
	not ergo._for_own_read(patterned, {"v": "s"}, ["v"])[0] in {"absent", "null", "unusable", "not_an_object"}
	ergo._for_own_read({"op": "in", "path": ["v"], "values": ref}, {"v": {}}, ["v"])[0] == ergo._side_state({"v": {}}, ["v"])
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

test_a_whose_item_beside_a_list_it_cant_read_from_a_part_is_checked_against_an_empty_list if {
	c := {"cmp": "in", "left": ["k"], "op": "compare", "right": ["${\"alias\":\"pl\",\"n\":1,\"of\":null,\"old\":true}", "c", "z"]}
	ergo._for_own_check(c, {"c": {"z": "s"}, "xs": [{"k": "a"}]}) == {"cmp": "in", "left": ["k"], "op": "compare", "right": {"literal": []}}
	ergo._for_own_check(object.union(c, {"cmp": "not_in"}), {"c": {"z": "s"}, "xs": [{"k": "a"}]}) == {"cmp": "not_in", "left": ["k"], "op": "compare", "right": {"literal": []}}
}

test_a_whose_item_beside_an_empty_list_root_says_its_own_read if {
	_whose_item_texts("every xs whose v is in $input.cs.name as x", {"xs": [{"v": "a"}, {}]}, {}) == [["item 2 of xs: v is missing"]] with data.ergo_document as {"cs": []}
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

test_a_whose_item_beside_a_time_root_says_its_own_read_against_a_stand_in_time if {
	subj := {"xs": [{}, {"v": null}, {"v": 1}, {"v": "2020-01-01T00:00:00Z"}]}
	_whose_item_texts("every xs whose v is after $params.t as x", subj, {"t": "s"}) == [["item 1 of xs: v is missing"], ["item 2 of xs: v is null"], [`item 3 of xs: v is 1, which isn't a time written like "1970-01-01T00:00:00Z"`]]
}

test_a_whose_item_beside_a_list_root_says_only_its_own_read if {
	subj := {"xs": [{"v": 1}, {}, {"v": null}, {"v": ["a"]}]}
	own := [["item 1 of xs: v is 1, which isn't a list"], ["item 2 of xs: v is missing"], ["item 3 of xs: v is null"]]
	_whose_item_texts("every xs whose v contains $params.t as x", subj, {}) == own
	_whose_item_texts("every xs whose v contains $params.t as x", subj, {"t": null}) == own
	_whose_item_texts("every xs whose v contains all of $params.t as x", subj, {"t": 3}) == own
	_whose_item_texts("every xs whose v is in $params.l as x", {"xs": [{"v": 1}, {}, {"v": null}]}, {"l": "s"}) == [["item 2 of xs: v is missing"], ["item 3 of xs: v is null"]]
	_whose_item_texts("every xs whose v matches $params.p as x", {"xs": [{"v": 1}, {}, {"v": null}, {"v": "a"}]}, {"p": 3}) == [["item 1 of xs: v is 1, which isn't text"], ["item 2 of xs: v is missing"], ["item 3 of xs: v is null"]]
}

test_a_whose_item_whose_focus_is_missing_says_the_path_to_it if {
	_whose_item_texts("every xs.t whose n is 1 as x", {"xs": [{"t": {"n": 1}}, {}]}, {}) == [["item 2 of xs: t is missing"]]
	_whose_item_texts("every xs.t.u whose n is 1 as x", {"xs": [{"t": {"u": {"n": 1}}}, {"t": {}}, {}]}, {}) == [["item 2 of xs: t.u is missing"], ["item 3 of xs: t.u is missing"]]
	_whose_item_texts("every xs.t.u whose n is 1 as x", {"xs": [{"t": 3}, {"t": null}]}, {}) == [["item 1 of xs: t is 3, which isn't an object"], ["item 2 of xs: t is null"]]
}

test_a_whose_item_whose_focus_isnt_an_object_says_so_by_its_path if {
	_whose_item_texts("every xs.t whose n is 1 as x", {"xs": [{"t": null}, {"t": 2}]}, {}) == [["item 1 of xs: t is null, which isn't an object"], ["item 2 of xs: t is 2, which isn't an object"]]
}

test_an_item_the_whose_decides_has_no_whose_item_clause if {
	_whose_item_texts("every xs whose v is 1 as x", {"xs": [{"v": 1}, {"v": 2}]}, {}) == []
}

_item_clauses(line, sentences, subj, params) := [c |
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_row_raw(check, subj) with input as {"ergo/names": names} with data.ergo_params as params
	some k, _ in r.failed
	c := ergo._for_item_clause(check, r.failed, k) with input as {"ergo/names": names} with data.ergo_params as params
]

_item_texts(line, sentences, subj, params) := [[ergo._m_aliased(t) | some t in ergo._m_clause_texts([c])] | some c in _item_clauses(line, sentences, subj, params)]

test_an_item_says_what_each_sentence_says_of_it_in_the_order_written if {
	[c] := _item_clauses("every xs as x", ["x.v is 1", "x.w is 1"], {"xs": [{"v": "a, and b"}]}, {})
	c.kind == "item"
	c.name == "item 1 of xs"
	c.cause == "unusable"
	[ergo._m_aliased(s.text) | some s in c.said] == [`x.v is "a, and b", which isn't a number`, "x.w is missing"]
	_item_texts("every xs as x", ["x.v is 1", "x.w is 1"], {"xs": [{"v": "a, and b"}]}, {}) == [[`item 1 of xs: x.v is "a, and b", which isn't a number, and x.w is missing`]]
}

test_an_item_a_sentence_reads_whole_is_named_by_the_item if {
	_item_texts("every member of ms as m", ["m is 1"], {"ms": {"a": 0, "b": 0}}, {}) == [["member a of ms is 0"], ["member b of ms is 0"]]
	[c, _] := _item_clauses("every member of ms as m", ["m is 1"], {"ms": {"a": 0, "b": 0}}, {})
	c.text == "member a of ms is 0"
	c.said == []
	c.cause == "value"
}

test_an_item_two_sentences_read_whole_is_said_once if {
	_item_texts("every member of ms as m", ["m is 1", "m is 2"], {"ms": {"a": 3}}, {}) == [["member a of ms is 3"]]
}

test_two_sentences_walking_one_list_say_its_items_in_list_order if {
	subj := {"xs": [{"ys": [{"n": 1, "m": 2}, {"m": 1}]}]}
	_item_texts("every xs as x", ["every x.ys.n is 1", "every x.ys.m is 1"], subj, {}) == [["item 1 of xs: item 1 of x.ys: m is 2", "item 1 of xs: item 2 of x.ys: n is missing"]]
}

test_a_walk_and_a_plain_sentence_keep_the_order_written if {
	subj := {"xs": [{"v": 2, "ys": [{"n": 2}]}]}
	_item_texts("every xs as x", ["every x.ys.n is 1", "x.v is 1"], subj, {}) == [["item 1 of xs: item 1 of x.ys: n is 2", "item 1 of xs: x.v is 2"]]
	_item_texts("every xs as x", ["x.v is 1", "every x.ys.n is 1"], subj, {}) == [["item 1 of xs: x.v is 2", "item 1 of xs: item 1 of x.ys: n is 2"]]
}

test_a_member_walk_and_a_plain_sentence_keep_the_order_written if {
	subj := {"xs": [{"v": 2, "ms": {"a": 2, "b": 1}}]}
	_item_texts("every xs as x", ["every member of x.ms is 1", "x.v is 1"], subj, {}) == [["item 1 of xs: member a of x.ms is 2", "item 1 of xs: x.v is 2"]]
}

test_an_item_whose_sort_key_is_of_another_kind_says_why if {
	subj := {"xs": [{"t": 1, "v": 2}, {"t": "a", "v": 3}]}
	_item_texts("first of xs sorted by t as x", ["x.v is 1"], subj, {}) == [[`item 2 of xs: t is "a", which isn't a number, a time or a date`]]
}

test_an_item_that_isnt_an_object_says_so_as_its_own_text if {
	cs := _item_clauses("every xs as x", ["x.v is 1"], {"xs": [1, {}, null]}, {})
	[[c.cause, ergo._m_aliased(c.text)] | some c in cs] == [["not_an_object", "item 1 of xs is 1, which isn't an object"], ["absent", ""], ["not_an_object", "item 3 of xs is null, which isn't an object"]]
	_item_texts("every xs as x", ["x.v is 1"], {"xs": [1, {}, null]}, {}) == [["item 1 of xs is 1, which isn't an object"], ["item 2 of xs: x.v is missing"], ["item 3 of xs is null, which isn't an object"]]
}

test_an_item_the_line_cant_reach_says_what_it_found_there if {
	_item_texts("every xs.ys as y", ["y.v is 1"], {"xs": [{"ys": [{"v": 2}]}, {}, {"ys": null}]}, {}) == [["item 1 of xs: item 1 of ys: y.v is 2"], ["item 2 of xs: ys is missing"], ["item 3 of xs: ys is null"]]
}

test_an_item_the_whose_cant_decide_is_named_by_the_path_its_whose_reads if {
	_item_texts("every xs.meta whose k is 1 as m", ["m exists"], {"xs": [{"meta": {"k": 1}}, {"meta": {"n": 1}, "k": 1}]}, {}) == [["item 2 of xs: meta: k is missing"]]
}

test_a_problem_an_earlier_sentence_said_of_an_item_is_not_said_again if {
	_item_texts("every xs as x", ["x.e exists", "x.e is after x.a"], {"xs": [{}]}, {}) == [["item 1 of xs: x.e is missing, and x.a is missing"]]
}

test_an_item_the_line_reads_through_says_what_it_found_there_with_no_whose if {
	_item_texts("every pull_requests.title as t", [`t is "Fix"`], {"pull_requests": [{"title": "Fix"}, {}]}, {}) == [["item 2 of pull_requests: title is missing"]]
}

test_an_item_the_whose_cant_decide_says_its_whose_clause if {
	_item_texts("every xs whose v is 1 as x", ["x.w is 1"], {"xs": [{"w": 2}, {"v": 1, "w": 2}]}, {}) == [["item 1 of xs: v is missing"], ["item 2 of xs: x.w is 2"]]
}

test_an_item_the_whose_cant_decide_beside_a_root_says_only_its_own_read if {
	_item_texts("every xs whose v is at least $params.min as x", ["x.w is 1"], {"xs": [{"v": 1}, {}]}, {"min": "s"}) == [["item 2 of xs: v is missing"]]
}

test_items_that_tie_give_their_tie_once if {
	_item_texts("first of xs sorted by t as x", ["x.v is 1"], {"xs": [{"t": 1, "v": 2}, {"t": 1, "v": 3}]}, {}) == [["item 1 and item 2 of xs tie on t"]]
	[c] := _item_clauses("first of xs sorted by t as x", ["x.v is 1"], {"xs": [{"t": 1, "v": 2}, {"t": 1, "v": 3}]}, {})
	c.cause == "ambiguous"
}

_item_texts_today(line, sentences, subj, params) := [[e.t | some e in ents; e.i == k] | some k, _ in r.failed] if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_row_raw(check, subj) with input as {"ergo/names": names} with data.ergo_params as params
	ents := ergo._for_ents(check, r) with input as {"ergo/names": names} with data.ergo_params as params
}

test_the_items_clause_says_what_the_row_says_today if {
	shapes := [
		["every xs as x", ["x.v is 1", "x.w is 1"], {"xs": [{}, {}, {}, {}, {}]}],
		["every xs as x", ["every x.ys.n is 1"], {"xs": [{"ys": [{"n": 2}, {}]}, {"ys": [{"n": 3}, {}]}]}],
		["every xs as x", ["x.v is 1"], {"xs": [1, {}, null]}],
		["every xs as x", ["x.v is 1", "x.w is 1"], {"xs": [{"v": "a, and b"}]}],
		["every xs as x", ["every x.ys.n is 1", "every x.ys.m is 1"], {"xs": [{"ys": [{"n": 1, "m": 2}, {"m": 1}]}]}],
		["every prs as pr, every pr.as as ap", ["ap.state is 1", "ap.user is 1", "pr.ok is true"], {"prs": [{"ok": false, "as": [{"state": 2, "user": 1}, {"state": 1, "user": 3}]}]}],
		["every cs as c", ["every c.reviews.ok is true", "c.a is 1"], {"cs": [{"a": 2, "reviews": [{"ok": true}, {"ok": false}]}, {"a": 2, "reviews": [{"ok": false}]}, {"a": 2, "reviews": [{"ok": false}]}, {"a": 2, "reviews": [{"ok": false}]}, {"a": 2, "reviews": [{"ok": false}]}]}],
	]
	every s in shapes {
		_item_texts(s[0], s[1], s[2], {}) == _item_texts_today(s[0], s[1], s[2], {})
	}
}

test_an_items_clause_leaves_its_roots_to_the_row if {
	_item_texts("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": "a"}, {}, {"v": 1}]}, {"min": "s"}) == [[`item 1 of xs: x.v is "a", which isn't a number`], ["item 2 of xs: x.v is missing"]]
	_item_texts("every xs as x", ["x.v is at least $params.min"], {"xs": [{"v": 1}, {}]}, "s") == []
}

test_an_item_clause_is_given_only_for_an_item_in_the_failed_list if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": ["x.v is 1"]})
	names := {"ergo/subject": {"xs": [{}]}, "$at": {"names": {}}}
	r := ergo._for_row_raw(check, {"xs": [{}]}) with input as {"ergo/names": names}
	not ergo._for_item_clause(check, r.failed, 1) with input as {"ergo/names": names}
	not ergo._for_item_clause(check, r.failed, "0") with input as {"ergo/names": names}
	not ergo._for_item_clause(check, null, 0) with input as {"ergo/names": names}
}

test_a_sentence_that_reads_no_alias_is_not_said_under_an_item if {
	_item_texts("every xs as x", ["x.v is 1", "z is 1"], {"xs": [{"v": 2}, {}]}, {}) == [["item 1 of xs: x.v is 2"], ["item 2 of xs: x.v is missing"]]
}

test_a_sentence_that_doesnt_read_the_second_alias_rides_with_the_first_pair if {
	subj := {"prs": [{"ok": false, "as": [{"state": 2, "user": 1}, {"state": 1, "user": 3}]}]}
	_item_texts("every prs as pr, every pr.as as ap", ["ap.state is 1", "ap.user is 1", "pr.ok is true"], subj, {}) == [["item 1 of prs: item 1 of pr.as: ap.state is 2, and pr.ok is false", "item 1 of prs: item 2 of pr.as: ap.user is 3"]]
}

test_a_rider_written_first_is_said_first_in_its_pair if {
	subj := {"prs": [{"ok": false, "as": [{"state": 2}, {"state": 3}]}]}
	_item_texts("every prs as pr, every pr.as as ap", ["pr.ok is true", "ap.state is 1"], subj, {}) == [["item 1 of prs: item 1 of pr.as: pr.ok is false, and ap.state is 2", "item 1 of prs: item 2 of pr.as: ap.state is 3"]]
}

test_a_rider_with_no_pair_is_said_under_the_first_item if {
	_item_texts("every prs as pr, every pr.as as ap", ["ap.state is 1", "pr.ok is true"], {"prs": [{"ok": false, "as": [{"state": 1}]}]}, {}) == [["item 1 of prs: pr.ok is false"]]
}

test_a_pair_says_a_walk_apart_from_its_other_sentences if {
	subj := {"xs": [{"ys": [{"m": 2, "zs": [{"n": 2}]}]}]}
	_item_texts("every xs as x, every x.ys as y", ["every y.zs.n is 1", "y.m is 1"], subj, {}) == [["item 1 of xs: item 1 of x.ys: item 1 of y.zs: n is 2", "item 1 of xs: item 1 of x.ys: y.m is 2"]]
}

test_items_of_the_second_list_the_line_cant_check_come_in_list_order if {
	line := "every xs as x, every x.ys whose n is 1 as y"
	_item_texts(line, ["y.m is 1", "x.k is 1"], {"xs": [{"k": 2, "ys": [{}, {"n": 1, "m": 2}]}]}, {}) == [["item 1 of xs: item 1 of x.ys: n is missing", "item 1 of xs: item 2 of x.ys: y.m is 2, and x.k is 2"]]
	_item_texts(line, ["y.m is 1"], {"xs": [{"ys": [{"n": 1, "m": 2}, {}]}]}, {}) == [["item 1 of xs: item 1 of x.ys: y.m is 2", "item 1 of xs: item 2 of x.ys: n is missing"]]
}

test_items_of_the_second_list_the_line_cant_check_are_said_with_no_pair_beside_them if {
	_item_texts("every ws as w, every member of w.ms as m", ["m is 1"], {"ws": [{"ms": [1]}]}, {}) == [["item 1 of ws: w.ms is [1], which isn't an object"]]
	subj := {"ws": [{"z": "p; q"}], "ys": [{"n": 1}, {"n": 2}]}
	_item_texts("every ws as w, some ys whose n is at least w.z and whose n is at most u as y", ["y.n exists"], subj, {}) == [["item 1 of ws: item 1 of ys: u is missing", "item 1 of ws: item 2 of ys: u is missing"]]
}

test_a_second_list_item_that_isnt_an_object_is_named_by_the_item if {
	_item_texts("every prs as pr, every pr.as as ap", ["ap.state is 1"], {"prs": [{"as": [3, {"state": 2}, null]}]}, {}) == [[
		"item 1 of prs: item 1 of pr.as is 3, which isn't an object",
		"item 1 of prs: item 2 of pr.as: ap.state is 2",
		"item 1 of prs: item 3 of pr.as is null, which isn't an object",
	]]
}

test_a_second_alias_read_whole_is_named_by_its_item if {
	_item_texts("every ws as w, every member of w.ms as m", ["m is 1"], {"ws": [{"ms": {"a": 2, "b": 1}}]}, {}) == [["item 1 of ws: member a of w.ms is 2"]]
}

_row_tree(line, sentences, subj, params) := tree if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as {"ergo/names": names} with data.ergo_params as params
	tree := ergo._for_row_clauses(check, subj, r) with input as {"ergo/names": names} with data.ergo_params as params
}

_row_tree_text(line, sentences, subj, params) := ergo._m_aliased(ergo._m_clauses_text(ergo._m_clauses_shown(_row_tree(line, sentences, subj, params))))

test_sentences_that_read_no_alias_are_said_in_the_order_written_whatever_clause_they_give if {
	_row_tree_text("every ks as k", ["every es.zz is 1", "z is 1"], {"ks": ["a"], "es": [{"zz": 2}], "z": 2}, {}) == "item 1 of es: zz is 2; z is 2"
}

test_a_value_a_sentence_that_reads_no_alias_said_is_not_said_again_under_each_item if {
	_row_tree_text("every xs as x", ["x.v is at least z", "z is 1"], {"xs": [{"v": 1}, {"v": 3}], "z": 5}, {}) == "z is 5; item 1 of xs: x.v is 1; item 2 of xs: x.v is 3"
}

test_the_first_list_said_as_a_whole_is_not_counted_among_the_items if {
	_row_tree_text("every ks, if any, as k", ["every es.zz is 1"], {"ks": null, "es": [{"zz": 2}, {"zz": 3}, {"zz": 4}]}, {}) == "item 1 of es: zz is 2; item 2 of es: zz is 3; item 3 of es: zz is 4; ks is null"
}

test_an_item_that_says_only_what_a_sentence_that_reads_no_alias_said_is_left_out if {
	_row_tree_text("every ks as k", ["count of es is 1", "every es.m named by k is 1"], {"ks": ["v"], "es": null}, {}) == "es is null"
}

test_a_count_over_a_list_the_item_cant_give_joins_the_items_other_sentences if {
	_row_tree_text("every xs as x", ["count of x.ys is 1", "x.w exists"], {"xs": [{"ys": null}]}, {}) == "item 1 of xs: x.ys is null, and x.w is missing"
	_row_tree_text("every xs as x", ["x.w exists", "count of x.ys is 1"], {"xs": [{"ys": null}]}, {}) == "item 1 of xs: x.w is missing, and x.ys is null"
	_row_tree_text("every xs as x", ["count of x.ys is 1", "x.w exists"], {"xs": [{}]}, {}) == "item 1 of xs: x.ys is missing, and x.w is missing"
	_row_tree_text("every xs as x", ["count of x.ys is 1", "x.w exists"], {"xs": [{"ys": "s"}]}, {}) == `item 1 of xs: x.ys is "s", which isn't a list or an object, and x.w is missing`
	_row_tree_text("every xs as x", ["count of x.ys whose n is 1 is 1", "x.w exists"], {"xs": [{"ys": null}]}, {}) == "item 1 of xs: x.ys is null, and x.w is missing"
	_row_tree_text("every xs as x", ["sum of x.ys.n is 1", "x.w is 1"], {"xs": [{"ys": null, "w": 2}]}, {}) == "item 1 of xs: x.ys is null, and x.w is 2"
}

test_a_part_that_walks_no_list_stays_with_its_item_when_the_cap_cuts_an_inner_list if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": ["every x.ys.n is 1", "count of x.zs is 1", "x.v is 1"]})
	subj := {"xs": [{"v": 2, "zs": [], "ys": [{"n": 2}, {"n": 3}, {"n": 4}, {"n": 5}]}]}
	row := ergo._for_row(check, subj) with input as {"ergo/names": {"ergo/subject": subj, "$at": {"names": {}}}}
	not row["ergo/for_raw"].tree
	ergo._m_aliased(row.message) == "item 1 of xs: item 1 of x.ys: n is 2; item 1 of xs: item 2 of x.ys: n is 3; item 1 of xs: item 3 of x.ys: n is 4; item 1 of xs: count of x.zs is 0, and x.v is 2; and 1 more"
}

test_an_item_keeps_only_what_the_row_hasnt_said_already if {
	said := {"z is 5"}
	not ergo._for_unrooted(ergo._m_clause("item", "item 1 of xs", "value", "z is 5"), said)
	not ergo._for_unrooted(ergo._m_item_clause("item 1 of xs", "value", [ergo._m_clause("root", "z", "value", "z is 5")]), said)
	ergo._for_unrooted(ergo._m_item_clause("item 1 of xs", "value", [ergo._m_clause("root", "z", "value", "z is 5"), ergo._m_clause("root", "v", "value", "v is 1")]), said).said == [ergo._m_clause("root", "v", "value", "v is 1")]
	ergo._for_unrooted(ergo._m_clause("item", "item 1 of xs", "value", "item 1 of xs is 1"), said).text == "item 1 of xs is 1"
}

test_a_for_line_on_a_subject_that_isnt_an_object_says_so_as_its_list_text if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": "x.v is 1"})
	ergo._for_empty_texts(check, 3, {"cause": "not_an_object", "failed": []}) == ["the subject is 3, which isn't an object"]
	ergo._for_list_texts(check, 3, {"cause": "not_an_object", "failed": []}) == ["the subject is 3, which isn't an object"]
}

test_an_empty_list_a_line_tolerates_is_not_said_beside_a_sentence_that_reads_no_alias if {
	_row_tree_text("every xs, if any, as m", ["z is 1"], {"xs": [], "z": 3}, {}) == "z is 3"
}

test_an_empty_list_a_line_tolerates_is_not_said_beside_a_root_that_fails if {
	_row_tree_text("every xs, if any, as x", ["x.v is at least $params.min"], {"xs": []}, {"min": "s"}) == `$params.min is "s", which isn't a number`
	_row_tree_text("every xs as x", ["x.v is at least $params.min"], {"xs": []}, {"min": "s"}) == `$params.min is "s", which isn't a number; xs is []`
}

test_a_for_row_on_a_subject_that_isnt_an_object_says_that_once_after_its_other_roots if {
	check := ergo._s_written_check({"for": "every owner as o", "assert": ["o is $params.z", "o is z"]})
	subj := [{"owner": "a"}]
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	p := ergo._for_row_parts(check, subj, {"cause": "not_an_object", "inputs": [], "failed": []}) with input as {"ergo/names": names}
	[c.text | some c in p.roots] == ["$params.z is missing"]
	[c.text | some c in p.lists] == [`the subject is [{"owner": "a"}], which isn't an object`]
}

test_a_root_of_a_for_row_that_names_an_item_counts_toward_the_items_shown if {
	named := ergo._m_root_in("item 1 of t: item 1 of c", "not_an_object", "item 1 of t: item 1 of c is 1, which isn't an object", 0)
	ergo._for_root_item(named) == object.union(named, {"kind": "item"})
	plain := ergo._m_root_in("$params.z", "absent", "$params.z is missing", 0)
	ergo._for_root_item(plain) == plain
	shown := ergo._m_clauses_text(ergo._m_clauses_shown([ergo._for_root_item(ergo._m_root_in(n, "not_an_object", concat("", [n, " is 1, which isn't an object"]), 0)) | some n in ["item 1 of t: item 1 of c", "item 1 of t: item 2 of c", "item 2 of t: item 1 of c", "item 2 of t: item 2 of c"]]))
	shown == "item 1 of t: item 1 of c is 1, which isn't an object; item 1 of t: item 2 of c is 1, which isn't an object; item 2 of t: item 1 of c is 1, which isn't an object; and 1 more"
}

test_a_sentences_roots_for_its_entries_come_from_what_the_tree_read_or_are_read_again if {
	check := ergo._s_written_check({"for": "every xs as x", "assert": ["x.v is $params.a", "x.w is 1"]})
	"$params.a is missing" in ergo._for_sentence_root_texts(check, {"xs": [{"v": 1}]}, 0, {})
	ergo._for_sentence_root_texts(check, {"xs": [{"v": 1}]}, 0, {0: [["absent", "$params.b is missing"]]}) == ["$params.b is missing"]
}

test_a_for_rows_list_is_not_said_when_a_root_failed_beside_a_sentence_that_reads_no_alias if {
	check := ergo._s_written_check({"for": "every xs as m", "assert": "count of xs whose v is in $input.z is 0"})
	unfreed := {"cause": "value", "failed": [], "root_msgs": ["$input.z is []"]}
	ergo._for_list_texts(check, {"xs": [{"v": 1}]}, object.union(unfreed, {"free_lines": [], "unfreed": unfreed})) == []
}

test_the_list_a_line_picks_nothing_from_comes_after_a_sentence_that_reads_no_alias if {
	_row_tree_text("every xs whose v is 1 as x", ["x.v is 1", "z is 1"], {"xs": [{"v": 3}], "z": 3}, {}) == `z is 3; xs is [{"v": 3}]`
	_row_tree_text("first of xs sorted by v as x", ["x.v is 1", "z is 1"], {"xs": [], "z": 3}, {}) == "z is 3; xs is []"
}

test_a_for_rows_roots_keep_the_order_of_their_sentences if {
	_row_tree_text("every xs as x", ["x.v is $params.a", "x.v is $params.b"], {"xs": [{"v": 1}]}, {"a": null}) == "$params.a is null; $params.b is missing"
	_row_tree_text("every xs as x", ["x.v is $params.b", "x.v is $params.a"], {"xs": [{"v": 1}]}, {}) == "$params.b is missing; $params.a is missing"
}

test_the_roots_of_the_lines_own_whose_come_before_the_sentences_roots if {
	_row_tree_text("every xs whose v is at least $params.min as x", ["x.w is at least $params.a"], {"xs": [{"v": 1, "w": 1}]}, {"a": "s"}) == `$params.min is missing; $params.a is "s", which isn't a number`
}

test_a_sentence_that_reads_no_alias_comes_first_with_its_roots if {
	_row_tree_text("every xs, if any, as x", ["w exists", "y is at least 1", "z is 1"], {"xs": [], "y": "s", "z": 3}, {}) == `w is missing; y is "s", which isn't a number; z is 3`
}

test_a_root_is_said_with_the_sentence_that_cant_read_it if {
	_row_tree_text("every xs as x", ["z is in $params.l", "w is 1", "x.m named by z is 1"], {"xs": [{"m": {"a": 1}}], "z": 1}, {"l": [1, 2]}) == "w is missing; z is 1, which isn't text"
}

test_a_for_rows_roots_come_before_its_items if {
	_row_tree_text("every xs as x", ["x.v is at least $params.min", "x.w is 1"], {"xs": [{"v": 1, "w": 2}, {}]}, {"min": "s"}) == `$params.min is "s", which isn't a number; item 1 of xs: x.w is 2; item 2 of xs: x.v is missing, and x.w is missing`
	_row_tree_text("every xs whose v is at least $params.min as x", ["x.w is 1"], {"xs": [{"v": 1, "w": 2}, {"w": 1}]}, {"min": "s"}) == `$params.min is "s", which isn't a number; item 2 of xs: v is missing`
	_row_tree_text("every xs as x", ["x.v is at least $params.min", "z is 1"], {"xs": [{"v": 1}, {}], "z": 2}, {"min": null}) == "z is 2; $params.min is null; item 2 of xs: x.v is missing"
}

_tree_said(line, sentences, subj, params, cause) := said if {
	check := ergo._s_written_check({"for": line, "assert": sentences})
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as {"ergo/names": names} with data.ergo_params as params
	raw := {"passed": false, "cause": cause, "message": "", "ergo/for_raw": {"check": check, "subj": subj, "r": object.union(r, {"cause": cause}), "tree": true}}
	said := ergo._for_said(raw) with input as {"ergo/names": names} with data.ergo_params as params
}

test_a_row_on_the_tree_says_the_trees_message if {
	said := _tree_said("every xs as x", ["x.v is at least z", "z is 1"], {"xs": [{"v": 1}, {"v": 3}], "z": 5}, {}, "value")
	ergo._m_aliased(said.message) == "z is 5; item 1 of xs: x.v is 1; item 2 of xs: x.v is 3"
	said.cause == "value"
	not "ergo/for_raw" in object.keys(said)
}

test_a_row_whose_sentence_reads_a_list_outside_its_item_keeps_the_text_the_tree_cant_say_yet if {
	check := ergo._s_written_check({"for": "every rows as r", "assert": ["r.v is in $input.os.name"]})
	subj := {"rows": [{"v": "bob"}, {"v": "ann"}]}
	doc := {"os": [{"name": "ann"}, {}]}
	names := {"ergo/subject": subj, "$at": {"names": {}}}
	r := ergo._for_freed(check, subj, ergo._for_row_raw(check, subj)) with input as {"ergo/names": names} with data.ergo_document as doc
	raw := {"passed": false, "cause": r.cause, "message": "", "ergo/for_raw": {"check": check, "subj": subj, "r": r, "tree": true}}
	said := ergo._for_said(raw) with input as {"ergo/names": names} with data.ergo_document as doc
	said.message == "item 2 of $input.os: name is missing"
}

test_a_row_on_the_tree_takes_the_worst_cause_of_what_it_says if {
	_tree_said("every xs as x", ["x.v is 1"], {"xs": [{}]}, {}, "value").cause == "absent"
	_tree_said("every xs as x", ["x.v is 1"], {"xs": [{}]}, {}, "not_an_object").cause == "not_an_object"
}

test_items_of_an_inner_list_that_tie_are_said_under_their_item if {
	_item_texts("every ws as w, first of w.ys sorted by t as y", ["y.v is 1"], {"ws": [{"ys": [{"t": 1, "v": 2}, {"t": 1, "v": 3}]}]}, {}) == [["item 1 of ws: item 1 and item 2 of w.ys tie on t"]]
}

test_a_for_item_keeps_the_cut_of_its_count_after_its_items_and_apart_from_a_root_it_says if {
	f := {
		"bare": "item 1 of ws", "cause": "not_an_object", "item": "item 1 of ws", "said": "item 1 of ws", "path": "item 1 of ws",
		"value": {"xs": [null, 3, "s", []]},
		"failed_assertions": [{
			"assertion": "count of w.xs whose v does not equal $input.m named by key is 0",
			"cause": "not_an_object",
			"msg": ["$input.m is null; item 1 of w.xs is null, which isn't an object; item 2 of w.xs is 3, which isn't an object; item 3 of w.xs is \"s\", which isn't an object; and 1 more"],
		}],
	}
	ergo._m_for_fail(f) == [
		"item 1 of ws: $input.m is null",
		"item 1 of ws: item 1 of w.xs is null, which isn't an object",
		"item 1 of ws: item 2 of w.xs is 3, which isn't an object",
		"item 1 of ws: item 3 of w.xs is \"s\", which isn't an object",
		"item 1 of ws: and 1 more",
	]
}
